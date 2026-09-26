# Parallel `!` Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add measured, law-covered parallel `!` paths for bloom probes, bloom build, and recovery checksum verification without weakening existing gates.

**Architecture:** Keep production semantics identical; add pure parallel variants beside sequential defs, gate `!` behind size thresholds, measure CPU-pool vs GPU vs sequential in benches before changing production call sites.

**Tech Stack:** Bend 2.0.28 (`tools/toolchain.json`), `bend guide` + `bend guide shaders` fork-tree rules, `bolt` lint gate from `AGENT.md`, `./proofs/run.sh` proof gate.

**Measurement log (2026-09-26):**
- `bloom_tune` native (`/tmp/bloom_tune --threads 8`): monkey FP=33, double FP=7, probes=4096 — unchanged vs sequential counting.
- `compaction` native (`/tmp/compaction --threads 8`, 4097 entries): bloom_construction 2–4 ms, all correctness pass. Note: the bench measures sequential `bloom_of`, not `bloom_of_auto`.
- `verify_all` native (`/tmp/verify_rt`): seq == par == `[True, True, True]` over 3 bodies (empty + 1-entry + 2-entry) in 0.5 s.
- **Checker finding:** end-to-end batch laws over entry-bearing bodies are checker-infeasible — the decoder's `Nat.div` overflow guard (`Decimal.bend:46-54`) costs ~16M unary steps per digit with 16M–1G limits in the checker (runtime unaffected). Empty-body verify ≈ 13 s in the checker; entry-bearing bodies diverge. So `batch_verify_agrees` pins a single empty body (RecoverProof: 24 s, under the 900 s budget) and entry-bearing equivalence is covered by the native runtime evidence above. Do not extend the law fixture with entries without re-measuring.

**GPU leverage log (2026-09-26):**
- `bench/workload/million_writes.sh` now honors `MYLSM_DEVICE` (`gpu/on` default, `cpu/off` → `--gpu off`, or heap caps like `4GB`), logs `gpu_mode` + `cc` in the header, and defaults `CC=/usr/bin/clang` on Darwin (homebrew llvm@19 cannot build the Metal `.gpu` artifact: module `_c_standard_library_obsolete` error).
- `bloom_pick` was briefly wired to `bloom_of_bang` (all 8192-entry frozen-merge flushes hit the ≥8192 gate). Write phase on GPU: 100k writes `elapsed_ms=10649` vs 10902 CPU pool — bangs execute correctly, on par.
- BLOCKER: Bend 2.0.28 Metal runtime faults recovery at scale (`memory fault (machine stack overflow?)` replaying a 20485-frame WAL with GPU on, any thread count/heap cap; `--gpu off` passes; 4097-write recovery passes either way). No bang executes in recovery — it is a runtime issue, not code.
- DECISION: production `bloom_pick` reverted to CPU-pool chunks (GPU runtime activation crashes production recovery; see formal limitation comment in `src/Sstable.bend`). `bloom_of_bang` stays as opt-in. Post-revert full bench with `MYLSM_DEVICE=gpu` passes all gates (20485: 10564.72 ops/s) — with no reachable bang the GPU runtime never initializes.
- To re-enable end-to-end GPU: flip `bloom_pick` False-branch to `bloom_of_bang` once the upstream recovery crash is fixed.

**Hybrid spike outcome (2026-09-26, DECISIVE):**
- Design: parallel index collection (`hash_idxs_par_go`, fork tree with concat joins, zero trees/unions) + sequential single-tree assembly (`bloom_set_all`). Law `sstable_bloom_hybrid_agrees` proven.
- 1M interleaved A/B vs 4-chunk (same machine, same toolchain): hybrid median 261,746 ms (runs 264,748 / 261,746 / 260,126) vs 4-chunk median 264,519 ms (runs 264,488 / 264,243 / 264,519) — hybrid ties 4-chunk, does NOT recover sequential level (225,105 ms).
- Two-state confirmation: all arms shifted +15k ms on the slow day (thermal/load drift); sequential re-run same day 240,290 / 238,518 ms — relative order seq < hybrid ≈ 4-chunk stable in both states (~10% gap).
- VERDICT: all parallel bloom variants lose ~10% vs sequential at 1M (fork/join + allocation overhead dominates; invisible at 100k). Production `bloom_pick` reverted to sequential on both gate branches; parallel + hybrid builds stay as law-covered spikes. Do NOT re-enable without a new 1M A/B.

---

### Task 1: Parallel bloom-probe harness

**Files:**
- Modify: `bench/workload/bloom_tune.bend:30-50`
- Modify: `laws/BloomSafe.bend`
- Modify: `proofs/BloomSafeProof.bend`
- Test: `bench/workload/bloom_tune.bend`

- [ ] **Step 1: Add sequential-vs-parallel probe equivalence law**

```python
law probe_par_equiv:
  for probes: List<&2, String>
  for tab: Sstable.Table
  {Sstable.probe_count_par(probes, tab) == Sstable.probe_count_seq(probes, tab) : Nat}
```

- [ ] **Step 2: Check the law fails before implementation**

Run: `bend proofs/BloomSafeProof.bend`
Expected: FAIL with open law `probe_par_equiv` or unknown `Sstable.probe_count_par`.

- [ ] **Step 3: Add minimal parallel probe counter in `src/Sstable.bend`**

```python
def probe_count_seq(+probes: List<&2, String>, +tab: Sstable.Table) -> Nat:
  match probes:
    case Nil{}:
      0n
    case Con{+q, t}:
      Nat.add(probe_count_seq(t, tab), probe_hit(tab, q))

def probe_count_par(+probes: List<&2, String>, +tab: Sstable.Table) -> Nat:
  +half = Nat.div(List.length(&2, String, probes), 2n)
  left right = probe_count_seq(List.take(&2, String, probes, half), tab) probe_count_seq(List.drop(&2, String, probes, half), tab)
  Nat.add(left, right)
```

Add helper `probe_hit(tab, q)` returning `1n` for `maybe_present(tab, q)` true else `0n`:

```python
def probe_hit(+tab: Sstable.Table, +key: String) -> Nat:
  match Sstable.maybe_present(tab, key):
    case True{}:
      1n
    case False{}:
      0n
```

- [ ] **Step 4: Prove the new witness**

Run: `bend proofs/BloomSafeProof.bend`
Expected: `All terms check.`

- [ ] **Step 5: Use parallel counter in `bench/workload/bloom_tune.bend:30`**

```python
def fpr_go(+probes: List<&2, String>, +tab: Sstable.Table, acc: Nat) -> Nat:
  Nat.add(Sstable.probe_count_par(probes, tab), acc)
```

- [ ] **Step 6: Add explicit `!` bang call site with size gate**

Bang only in a pure def, never inside a `do` continuation. The callee `probe_count_par` already contains the fork tree, so `!` ships that tree to the GPU:

```python
def probe_count_bang_gate(+n: Nat) -> Bool:
  Nat.is_le(16384n, n)

def probe_count_auto(+probes: List<&2, String>, +tab: Sstable.Table) -> Nat:
  match probe_count_bang_gate(List.length(&2, String, probes)):
    case False{}:
      Sstable.probe_count_par(probes, tab)
    case True{}:
      Sstable.probe_count_par!(probes, tab)
```

Use `probe_count_auto` in the bench once the law passes. Threshold rationale: aim ~4^7 leaves per bang (`bend guide shaders`); below that the GPU launch cost dominates and CPU-pool `probe_count_par` wins.

- [ ] **Step 7: Measure sequential vs CPU-pool vs `!` (native build)**

```bash
bend bench/workload/bloom_tune.bend -o /tmp/bloom_tune
/tmp/bloom_tune --threads 8
/tmp/bloom_tune --threads 8 --gpu off
/tmp/bloom_tune --threads 8 --gpu 4GB
```

Expected: record `false_positives` identical across all three; record elapsed times. Promote the `!` path only if GPU beats CPU-pool at the gated size; otherwise keep `probe_count_par` (CPU) and leave `!` behind the gate.

- [ ] **Step 7: Lint changed files**

Run: `../bolt/bin/bolt.bin src/Sstable.bend bench/workload/bloom_tune.bend laws/BloomSafe.bend proofs/BloomSafeProof.bend 2>&1 | grep -v " S002: " | grep -E "error:|warning:"`
Expected: empty output.

- [ ] **Step 8: Commit**

```bash
git add src/Sstable.bend bench/workload/bloom_tune.bend laws/BloomSafe.bend proofs/BloomSafeProof.bend
git commit -m "feat: parallel bloom probe counter with equivalence law"
```

### Task 2: Widened bloom build with guarded `!` spike

**Files:**
- Modify: `src/Sstable.bend:210-228`
- Modify: `laws/Sstable.bend:58`
- Modify: `proofs/SstableProof.bend`
- Test: `bench/workload/compaction.bend:136-140`

- [ ] **Step 1: Add K-chunk equivalence law**

```python
law bloom_chunks_equiv:
  for entries: List<&2, MemTable.Entry>
  {Sstable.bloom_of_chunks(entries, 4n, 64n) == Sstable.bloom_of(entries, Sstable.bloom_new(64n)) : Sstable.Bloom}
```

- [ ] **Step 2: Check it fails**

Run: `bend proofs/SstableProof.bend`
Expected: FAIL naming `bloom_of_chunks`.

- [ ] **Step 3: Implement 4-way chunk build with two-level fork**

```python
def bloom_of_chunks(+entries: List<&2, MemTable.Entry>, +chunks: Nat, +nb: Nat) -> Bloom:
  +n = List.length(&2, MemTable.Entry, entries)
  +q = Nat.div(n, 4n)
  a b = bloom_of_chunk(List.take(&2, MemTable.Entry, entries, q), nb) bloom_of_chunk(List.take(&2, MemTable.Entry, List.drop(&2, MemTable.Entry, entries, q), q), nb)
  c d = bloom_of_chunk(List.take(&2, MemTable.Entry, List.drop(&2, MemTable.Entry, entries, Nat.mul(q, 2n)), q), nb) bloom_of_chunk(List.drop(&2, MemTable.Entry, entries, Nat.mul(q, 3n)), nb)
  bloom_union(bloom_union(a, b), bloom_union(c, d))
```

- [ ] **Step 4: Prove equivalence for fixed 64-bit fixture**

Run: `bend proofs/SstableProof.bend`
Expected: `All terms check.`

- [ ] **Step 5: Route `bloom_pick` through chunk build only above threshold**

```python
def bloom_pick(small: Bool, +entries: List<&2, MemTable.Entry>, +nb: Nat) -> Bloom:
  match small:
    case True{}:
      bloom_of(entries, bloom_new(nb))
    case False{}:
      bloom_of_chunks(entries, 4n, nb)
```

- [ ] **Step 6: Add explicit `!` bang spike (do NOT route production yet)**

`bloom_of_chunks` contains the two-level fork tree, so it is the bang candidate — never bang `bloom_of_chunk` (single leaf, serial on a lane). Bang in a pure def:

```python
def bloom_bang_gate(+n: Nat) -> Bool:
  Nat.is_le(8192n, n)

def bloom_of_bang(+entries: List<&2, MemTable.Entry>, +nb: Nat) -> Bloom:
  match bloom_bang_gate(List.length(&2, MemTable.Entry, entries)):
    case False{}:
      bloom_of_chunks(entries, 4n, nb)
    case True{}:
      bloom_of_chunks!(entries, 4n, nb)
```

Keep `bloom_pick` on `bloom_of_chunks` (CPU) until measurements justify `bloom_of_bang`. Rationale: current 4-leaf tree fills 4 of 16384 GPU lanes — expect GPU to lose until the tree is deepened; this step measures that fact instead of assuming it.

- [ ] **Step 7: Measure compaction bloom phase (three runs)**

Run: `MYLSM_BENCH_ENTRIES=4097 MYLSM_BENCH_DIR=.mylsm-compaction-bench-data bend bench/workload/compaction.bend`
Expected: `bloom_construction` phase prints; record time vs baseline.

- [ ] **Step 7: Run proof gate**

Run: `./proofs/run.sh`
Expected: exit 0, no failed module.

- [ ] **Step 8: Commit**

```bash
git add src/Sstable.bend laws/Sstable.bend proofs/SstableProof.bend
git commit -m "feat: widen bloom build to four chunks"
```

### Task 3: Recovery checksum batch verification

**Files:**
- Modify: `src/Recover.bend:293-300`
- Modify: `src/SstFileV2.bend:380-390`
- Modify: `laws/Recover.bend`
- Modify: `proofs/RecoverProof.bend`

- [ ] **Step 1: Add batch-verify equivalence law**

```python
law batch_verify_equiv:
  for bodies: List<&2, String>
  {Recover.verify_all_par(bodies) == Recover.verify_all_seq(bodies) : List<&2, Bool>}
```

- [ ] **Step 2: Check it fails**

Run: `bend proofs/RecoverProof.bend`
Expected: FAIL naming `verify_all_par`.

- [ ] **Step 3: Implement sequential and two-way parallel verifiers**

```python
def verify_all_seq(+bodies: List<&2, String>) -> List<&2, Bool>:
  match bodies:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      Con{SstFileV2.body_checksum_ok(h), verify_all_seq(t)}

def verify_all_par(+bodies: List<&2, String>) -> List<&2, Bool>:
  +half = Nat.div(List.length(&2, String, bodies), 2n)
  left right = verify_all_seq(List.take(&2, String, bodies, half)) verify_all_seq(List.drop(&2, String, bodies, half))
  List.append(&2, Bool, left, right)
```

Add `SstFileV2.body_checksum_ok(body: String) -> Bool` extracting only the checksum decision from the existing parse path:

```python
def body_checksum_ok(+body: String) -> Bool:
  SstChecksum.verify(body, body_claimed(body))
```

where `body_claimed` is the existing helper that splits `encoded_body ++ "#" ++ digest` and returns the claimed hex part; reuse it unchanged.

- [ ] **Step 4: Prove equivalence**

Run: `bend proofs/RecoverProof.bend`
Expected: `All terms check.`

- [ ] **Step 5: Keep `load_tables` IO-sequential, verify pure batch after load**

Do not change file-read order. After `load_tables` returns bodies, call `verify_all_par` in one pure step; keep fatal-on-corrupt behavior identical.

- [ ] **Step 6: Add explicit `!` bang variant with table-count gate**

Each body hash is a serial SHA-256 chain, so one lane per body. Bang only when the batch is wide; otherwise CPU-pool `verify_all_par` wins:

```python
def verify_bang_gate(+n: Nat) -> Bool:
  Nat.is_le(64n, n)

def verify_all_auto(+bodies: List<&2, String>) -> List<&2, Bool>:
  match verify_bang_gate(List.length(&2, String, bodies)):
    case False{}:
      Recover.verify_all_par(bodies)
    case True{}:
      Recover.verify_all_par!(bodies)
```

Measure with a many-table recovery fixture (e.g. post-`million_writes` dir) before routing `open_db` through `verify_all_auto`.

- [ ] **Step 6: Run full gates**

Run: `./proofs/run.sh`
Expected: exit 0.
Run: `../bolt/bin/bolt.bin 2>&1 | grep -v " S002: " | grep -E "error:|warning:"`
Expected: empty output.

- [ ] **Step 7: Commit**

```bash
git add src/Recover.bend src/SstFileV2.bend laws/Recover.bend proofs/RecoverProof.bend
git commit -m "feat: batched recovery checksum verification"
```

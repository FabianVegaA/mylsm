# Phase 3 Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement Phase 3 (reads → writes → measurement → GPU) on the skeleton-first design: structural commit first, then one gated phase at a time, ending with measured numbers and a release commit.

**Architecture:** Task 0 lands all new types/APIs with old bodies delegating (repo stays green). Tasks 1–3 fill phase A (block reads, redesigned `db_get`, cache), 4–6 fill phase B (grouped commits, frozen memtable, parallel compaction), 7 fills phase D (metrics harness), 8–9 fill phase C (GPU, spike-gated). Every task ends with targeted proofs + `./proofs/run.sh` + bench where measurable; regression → revert. Community packages are evaluated with spike gates; custom code wins ties on measurement (spec §1, precedents: balanced merge, prepend-log).

**Tech Stack:** Bend 2.0.25+ (`bend --check-only`, native `-o` builds), existing `src/` + `laws/` + `proofs/` + `bench/` + `bin/mylsm`, hub `bend-collections` pin `0x9ee2e9a299991dcc089fe22c7f3ceb5f` (affinity rule applies: hub `Type` state only ephemeral or via pure fns).

---

## File structure

- Modify (Task 0, skeleton): `src/Sstable.bend` (`Tbl` += `chunks`, `blocks`; 6 match sites + builders), `src/Db.bend` (`Db` += `frozen`, `batch_cap`, `bcache`; `open_db`; read/write core matches), `src/Wal.bend` (`stage` def), plus mechanical `Db.Db{...}` updates in `src/Recover.bend` (3 sites: 449, 507–508, 512), `src/Flush.bend` (3 sites: 148, 176, 181), `src/Compact.bend` (3 sites: 431, 475, 479–482), `app/repl_exec.bend` (2 sites: 63, 68), `laws/Flush.bend` (2 fixtures), `laws/Compact.bend` (2 fixtures), `bench/million_writes.bend` (2 sites: 49, 64), `bench/crash_worker.bend` (1 site: 127), `mylsm.bend` (3 sites: 90–91, 95–96, 100–101).
- Modify (Tasks 1–3, phase A): `src/Sstable.bend` (`block_entries`, chunking, `block_get`), `src/Db.bend` (`db_get` redesign), `laws/Sstable.bend` + `proofs/SstableProof.bend`, `laws/Db.bend` + `proofs/DbProof.bend`, new `bench/bloom_tune.bend` (Task 3).
- Modify (Tasks 4–6, phase B): `src/Db.bend` (grouped write path, rotation), `src/Flush.bend` (frozen drain), `src/Compact.bend` (disjoint parallel), `src/Recover.bend` (frozen recovery), `app/repl_exec.bend` (batch staging), `bin/mylsm` (`MYLSM_BATCH_CAP`), matching laws/proofs.
- Create (Task 7, phase D): `bench/phase3_metrics.bend`, `bench/op_log.md` (recipe); modify `bench/BASELINE.md` (new observations only — frozen ones stay).
- Modify (Tasks 8–9, phase C): `src/Sstable.bend` (`bloom_of_chunked`), `src/SstChecksum.bend` (only if C2 spike passes), `laws/Sstable.bend` (agreement), `laws/Demo.bend` pattern reused.
- Modify (Task 10): `mylsm.bend` (only if facade bodies need new delegates — signatures unchanged), `README.md` (Phase 3 checklist boxes), release commit.
- Untouched throughout: `src/MemTable.bend` prepend-log core, `src/SortedRun.bend` merge core (Task-5 finding), `src/BitTree.bend`, `src/Decimal.bend`, `src/Keys.bend`, `src/Manifest.bend`, hub pin.

---

### Task 0: Skeleton — new fields and APIs, old behavior

**Files:**
- Modify: `src/Sstable.bend`, `src/Db.bend`, `src/Wal.bend`, `src/Recover.bend`, `src/Flush.bend`, `src/Compact.bend`, `app/repl_exec.bend`, `laws/Flush.bend`, `laws/Compact.bend`, `bench/million_writes.bend`, `bench/crash_worker.bend`, `mylsm.bend`
- Test: `bend mylsm.bend --check-only`, `./proofs/run.sh`

- [ ] **Step 1: Extend `Tbl` with `chunks` + `blocks`, builders fill all three**

In `src/Sstable.bend`, change the type to:
```bend
type Table is Data:
  Tbl{
    entries: List<&2, MemTable.Entry>,
    filter: Bloom,
    nbits: Nat,
    smallest: Maybe<&2, String>,
    largest: Maybe<&2, String>,
    count: Nat,
    chunks: List<&2, List<&2, MemTable.Entry>>,
    blocks: List<&2, String>
  }

def block_entries() -> Nat:
  64n
```
Add (above the builders):
```bend
def chunk_go(fuel: Nat, +entries: List<&2, MemTable.Entry>, +cur: List<&2, MemTable.Entry>, +n: Nat, acc: List<&2, List<&2, MemTable.Entry>>) -> List<&2, List<&2, MemTable.Entry>>:
  match fuel:
    case 0n:
      List.reverse(&2, List<&2, MemTable.Entry>, Con{List.reverse(&2, MemTable.Entry, cur), acc})
    case 1n+f:
      match entries:
        case Nil{}:
          List.reverse(&2, List<&2, MemTable.Entry>, Con{List.reverse(&2, MemTable.Entry, cur), acc})
        case Con{e, t}:
          match Nat.is_eq(n, block_entries()):
            case True{}:
              chunk_go(f, t, Con{e, Nil{}}, 1n, Con{List.reverse(&2, MemTable.Entry, cur), acc})
            case False{}:
              chunk_go(f, t, Con{e, cur}, Nat.add(n, 1n), acc)

def chunk(+entries: List<&2, MemTable.Entry>) -> List<&2, List<&2, MemTable.Entry>>:
  match entries:
    case Nil{}:
      Nil{}
    case Con{e, t}:
      chunk_go(List.length(&2, MemTable.Entry, entries), t, Con{e, Nil{}}, 1n, Nil{})

def chunk_head_key(+c: List<&2, MemTable.Entry>) -> Maybe<&2, String>:
  match c:
    case Nil{}:
      None{}
    case Con{MemTable.Entry{key, val}, t}:
      Some{key}

def block_keys(+chunks: List<&2, List<&2, MemTable.Entry>>, acc: List<&2, String>) -> List<&2, String>:
  match chunks:
    case Nil{}:
      List.reverse(&2, String, acc)
    case Con{c, t}:
      match chunk_head_key(c):
        case None{}:
          block_keys(t, acc)
        case Some{k}:
          block_keys(t, Con{k, acc})
```
In `from_sorted_unique_est_meta` and `from_sorted_unique_meta`, replace `Tbl{entries, bloom_of(...), nb, smallest, largest, count}` with:
```bend
Tbl{entries, bloom_of(entries, bloom_new(nb)), nb, smallest, largest, count, chunk(entries), block_keys(chunk(entries), Nil{})}
```
Update the 5 remaining `Tbl{...}` match sites (lines ~130, ~135, ~187, ~192, ~197) to `Tbl{entries, filter, nbits, smallest, largest, count, chunks, blocks}` (bind only what each body uses; prefix unused with nothing — Bend matches all fields positionally, so all 8 must be named).

- [ ] **Step 2: Extend `Db` with `frozen`, `batch_cap`, `bcache`**

In `src/Db.bend`, add above the type:
```bend
type BEntry is Data:
  BEntry{tab: String, key: String, val: Maybe<&2, String>}

def default_batch_cap() -> Nat:
  1n

def bcache_bound() -> Nat:
  256n
```
Change the type to:
```bend
type Db is Data:
  Db{dir: String, mem: MemTable.MemTable, frozen: MemTable.MemTable, batch_cap: Nat, bcache: List<&2, BEntry>, levels: List<&2, List<&2, Sstable.Table>>, flushed: Nat, manifest_token: String}
```
Change `open_db` to:
```bend
def open_db(+dir: String) -> Db:
  Db{dir, MemTable.empty(), MemTable.empty(), default_batch_cap(), Nil{}, Nil{}, 0n, Manifest.serialize(Manifest.M{Nil{}})}
```
Update the two `Db{...}` matches in `src/Db.bend` (lines 78, 114) to the 8-field pattern, threading `frozen`/`batch_cap`/`bcache` through unchanged (skeleton: `db_get` still uses `all_entries`; `db_write` still single-batch; `bcache` untouched).

- [ ] **Step 3: Add `Wal.stage`, update every other `Db{...}` site**

In `src/Wal.bend`, append:
```bend
def stage(+staged: List<&2, Batch>, +b: Batch) -> List<&2, Batch>:
  Con{b, staged}
```
Update `Db.Db{...}` constructions/matches to 8 fields, preserving behavior: `src/Recover.bend` (449, 507–508, 512 — new `frozen` stays `MemTable.empty()`, `batch_cap` stays `default_batch_cap()`, `bcache` stays `Nil{}` unless the surrounding code already threads a db), `src/Flush.bend` (148, 176, 181), `src/Compact.bend` (431, 475, 479–482), `app/repl_exec.bend` (63, 68), `laws/Flush.bend` (2 fixtures — append `MemTable.empty(), 1n, Nil{}` for frozen/batch_cap/bcache), `laws/Compact.bend` (2 fixtures — same), `bench/million_writes.bend` (49, 64), `bench/crash_worker.bend` (127), `mylsm.bend` (90–91, 95–96, 100–101 — thread the matched `frozen`, `batch_cap`, `bcache` through unchanged).
For fixture laws, the canonical empty tail is `MemTable.MT{Nil{}}, 1n, Nil{}`; e.g. `laws/Flush.bend:12` becomes:
```bend
Db.Db{"/d", MemTable.MT{scan_mem()}, MemTable.MT{Nil{}}, 1n, Nil{}, Nil{}, 0n, ""}
```

- [ ] **Step 4: Gate the skeleton**

Run: `bend mylsm.bend --check-only`
Expected: exit 0. Then run: `./proofs/run.sh` (no pipes — bare command; piping through `tail` hangs the runner)
Expected: `SUMMARY PASS=31 FAIL=0 TIMEOUT=0 TOTAL=31`.

- [ ] **Step 5: Commit skeleton**

```bash
git add src/Sstable.bend src/Db.bend src/Wal.bend src/Recover.bend src/Flush.bend src/Compact.bend app/repl_exec.bend laws/Flush.bend laws/Compact.bend bench/million_writes.bend bench/crash_worker.bend mylsm.bend
git commit -m "chore: phase3 skeleton (Tbl chunks+blocks, Db frozen+batch+bache, Wal.stage)"
```
Stage only actually-changed paths (`git status --short` first).

---

### Task 1: Phase A1 — `block_get` over stored chunks

**Files:**
- Modify: `src/Sstable.bend` (`block_get` + `lookup` delegate), `laws/Sstable.bend`, `proofs/SstableProof.bend`
- Test: `bend proofs/SstableProof.bend`, `./proofs/run.sh`

- [ ] **Step 1: Implement `block_get`, delegate `lookup`**

In `src/Sstable.bend`, append (entries ascending — `from_sorted_unique` invariant; first chunk with head-key > k means k lives in the previous chunk):
```bend
def pick_chunk(+blocks: List<&2, String>, +chunks: List<&2, List<&2, MemTable.Entry>>, +k: String, +best: List<&2, MemTable.Entry>) -> List<&2, MemTable.Entry>:
  match blocks chunks:
    case Nil{} _:
      best
    case _ Nil{}:
      best
    case Con{b, bt} Con{c, ct}:
      match Keys.cmp(b, k):
        case GT{}:
          best
        case _:
          pick_chunk(bt, ct, k, c)

def block_scan(+chunk: List<&2, MemTable.Entry>, +k: String) -> Maybe<&2, String>:
  MemTable.get(MemTable.MT{chunk}, k)

def block_get(t: Table, +k: String) -> Maybe<&2, String>:
  match t:
    case Tbl{entries, filter, nbits, smallest, largest, count, chunks, blocks}:
      match chunks:
        case Nil{}:
          MemTable.get(MemTable.MT{entries}, k)
        case Con{c, t}:
          block_scan(pick_chunk(blocks, chunks, k, c), k)
```
Change `lookup` (`src/Sstable.bend:230`) to:
```bend
def lookup(t: Table, +k: String) -> Maybe<&2, String>:
  block_get(t, k)
```
Run: `bend src/Sstable.bend --check-only`
Expected: exit 0. (`Keys` is already imported in `Sstable.bend`? If not, add `import ./Keys.bend as Keys` — check the file header first; `bhash` uses its own hashing, so verify before assuming.)

- [ ] **Step 2: Equivalence laws + witnesses**

In `laws/Sstable.bend`, append (using the file's existing fixture builders `sst_e1`/`sst_e2` — read the file first and reuse them exactly):
```bend
law sstable_block_get_equiv:
  {Sstable.block_get(Sstable.build(sst_e2(), 0n, 2n), "k") == Sstable.lookup(Sstable.build(sst_e2(), 0n, 2n), "k") : Maybe<&2, String>}

law sstable_block_get_missing:
  {Sstable.block_get(Sstable.build(sst_e2(), 0n, 2n), "zzz") == None{} : Maybe<&2, String>}
```
In `proofs/SstableProof.bend`, add:
```bend
def Laws.sstable_block_get_equiv():
  {==}

def Laws.sstable_block_get_missing():
  {==}
```
If a closed `{==}` diverges in the checker, delete that law+witness pair (never weaken to a non-assertion) and re-run.

- [ ] **Step 3: Gate + commit**

Run: `bend proofs/SstableProof.bend && ./proofs/run.sh`
Expected: green throughout. Then:
```bash
git add src/Sstable.bend laws/Sstable.bend proofs/SstableProof.bend
git commit -m "feat: sstable block_get over stored chunks"
```

---

### Task 2: Phase A2 — `db_get` per-source search with live Bloom

**Files:**
- Modify: `src/Db.bend` (`db_get` redesign; `all_entries` kept for `Compact.table_runs`), `laws/Db.bend`, `proofs/DbProof.bend`, `bench/million_writes.bend` (only if shape output changes — it must not)
- Test: `bend proofs/DbProof.bend`, `./proofs/run.sh`, `bench/million_writes.sh 20485` smoke

- [ ] **Step 1: Rewrite `db_get` as newest-first per-source search**

In `src/Db.bend`, replace `db_get` with (mem → frozen → L0 tables newest-first → L1+; Bloom prefilter per table; first match wins including tombstones):
```bend
def table_get_filtered(t: Sstable.Table, +k: String) -> Maybe<&2, Maybe<&2, String>>:
  match Sstable.maybe_present(t, k):
    case False{}:
      None{}
    case True{}:
      Some{Sstable.block_get(t, k)}

def tables_get(+tabs: List<&2, Sstable.Table>, +k: String) -> Maybe<&2, Maybe<&2, String>>:
  match tabs:
    case Nil{}:
      None{}
    case Con{+h, t}:
      match table_get_filtered(h, k):
        case None{}:
          tables_get(t, k)
        case Some{found}:
          Some{found}

def levels_get(+lvls: List<&2, List<&2, Sstable.Table>>, +k: String) -> Maybe<&2, Maybe<&2, String>>:
  match lvls:
    case Nil{}:
      None{}
    case Con{+h, t}:
      match tables_get(h, k):
        case None{}:
          levels_get(t, k)
        case Some{found}:
          Some{found}

def flatten_opt(+m: Maybe<&2, Maybe<&2, String>>) -> Maybe<&2, String>:
  match m:
    case None{}:
      None{}
    case Some{inner}:
      inner

def db_get(+db: Db, +k: String) -> Maybe<&2, String>:
  match db:
    case Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token}:
      match MemTable.get(mem, k):
        case Some{v}:
          Some{v}
        case None{}:
          match MemTable.get(frozen, k):
            case Some{v}:
              Some{v}
            case None{}:
              flatten_opt(levels_get(levels, k))
```
Wait — tombstone subtlety: `MemTable.get` returns `None{}` both for absent AND tombstoned. The old path (concat then scan) let tombstones shadow older versions. In the new path, a tombstone in mem must shadow frozen/levels — but `None{}` is ambiguous. Fix: search each source with presence detection. `MemTable` has no `has`; add a scan variant? Cheapest correct shape: compare against scanning the concatenated per-source lists in order — i.e. keep newest-wins by checking mem-list, then frozen-list, then per-table, where each check distinguishes hit (Some incl. None-tombstone) from miss. `MemTable.get(MT{entries}, k)` on a single source's list returns the source's newest entry-or-tombstone-or-None; ambiguity remains between tombstone and miss WITHIN one source list — but within one list, `get` already implements newest-first-freeze correctly (scan_go freezes on first match incl. tombstone)... no: it returns None{} for both cases, and for the multi-source search we need to know whether to stop. Resolution: `tables_get` per table is fine (a table holds unique keys — miss vs tombstone-absent both mean "continue"? NO — a tombstone in an L0 table must shadow L1).

Correct approach: per-source hit detection via `MemTable` scan that returns `Maybe<Maybe<String>>` (outer None = miss, Some{inner} = hit incl. tombstone None). Add to `src/MemTable.bend`:
```bend
def get_hit(t: MemTable, +k: String) -> Maybe<&2, Maybe<&2, String>>:
  match t:
    case MT{entries}:
      scan_hit(List.length(&2, Entry, entries), k, (False{}, None{}), entries)
```
where `scan_hit` mirrors `scan_go` but the state answer is `Maybe<Maybe<String>>` starting `None{}` (miss) and freezing to `Some{val}` on first key match (val may be `None{}` tombstone). Implement `scan_hit` + `scan_hit_step` in `src/MemTable.bend` by duplicating `scan_step`/`scan_go` shapes with the lifted answer type, then:
```bend
def db_get(+db: Db, +k: String) -> Maybe<&2, String>:
  match db:
    case Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token}:
      flatten_opt(mem_hit(mem, frozen, levels, k))
```
with `mem_hit` chaining `MemTable.get_hit` on mem, then frozen, then `levels_get` (tables via `block_get` need the same lift: table hit = Bloom-maybe + `block_get`... `block_get` has the same ambiguity (miss vs absent) — but tables hold UNIQUE keys, so within a table miss==absent; across tables, an L0 tombstone must shadow L1: use `maybe_present` Bloom? Bloom has false positives (fine: positive → block_get → None means absent... but a tombstone entry IS present as Entry{key, None} → block_get returns None{} — ambiguous again!).

Resolution for tables: `block_get` over the chunk returns entry-or-None; lift at the chunk scan: write `block_get_hit` returning `Maybe<Maybe<String>>` using a hit-detecting scan over the ≤64 chunk (same `scan_hit` shape on a List). So: add `MemTable.scan_hit`/`get_hit` (Task 2, in `src/MemTable.bend` + `laws/MemTable.bend` bridge laws `get_hit(put)==Some{Some{}}`, `get_hit(del(put))==Some{None{}}`), add `Sstable.block_get_hit` built on `MemTable.scan_hit` over the selected chunk, and `db_get` chains hits. This is the biggest proof-touch of phase A: do `MemTable` first, then `Sstable`, then `Db`, one targeted proof at a time.

- [ ] **Step 2: Laws + witnesses (one module at a time)**

`laws/MemTable.bend`: append `get_hit` bridge laws (put→`Some{Some{v}}`, del→`Some{None{}}`, empty→`None{}`); witness in `proofs/MemTableProof.bend` (same frozen-lemma shapes, lifted answer type). `laws/Sstable.bend`: append `block_get_hit` equivalence vs `block_get` on fixtures. `laws/Db.bend`: append newest-wins + tombstone-hides fixtures over a 2-level db (mirror the existing `fl_pre`/`fl_post` fixture style — read `laws/Db.bend` first): mem-tombstone shadows L0 value; L0 value shadows L1; miss → `None{}`. Closed fixtures only.

- [ ] **Step 3: Gate + compaction smoke + commit**

Run: `bend proofs/MemTableProof.bend && bend proofs/SstableProof.bend && bend proofs/DbProof.bend && ./proofs/run.sh`
Expected: green. Then run: `MYLSM_BENCH_RESET=1 bench/million_writes.sh 20485 .mylsm-task2-smoke` (fresh dir; exercises flush+first-compaction+recovery under the new path)
Expected: `phase=correctness status=complete`, shape `l1_tables=1`. Then `rm -rf .mylsm-task2-smoke`.
```bash
git add src/Db.bend src/MemTable.bend src/Sstable.bend laws/MemTable.bend laws/Sstable.bend laws/Db.bend proofs/MemTableProof.bend proofs/SstableProof.bend proofs/DbProof.bend
git commit -m "feat: db_get per-source newest-first search with live bloom"
```

---

### Task 3: Phase A3 — block cache, LRU spike, Bloom tuning

**Files:**
- Modify: `src/Db.bend` (cache lookup/insert on the Task-2 path), `laws/Db.bend`, `proofs/DbProof.bend`
- Create: `bench/bloom_tune.bend`
- Test: targeted proofs, `./proofs/run.sh`, read-locality bench

- [ ] **Step 1: LRU spike — threaded cache vs assoc-list**

Spike (read-only first): `grep -n "^def " ~/.bend/lib/0x9ee2e9a299991dcc089fe22c7f3ceb5f/src/containers/lru.bend | head -20` — confirm insert/get shapes and what get hands back. Then in scratch `.mylsm/build/lru_spike.bend` (gitignored, delete after): thread a hub LRU through two reads. Verdict rule (spec §1 custom-precedence): adopt LRU only if it typechecks cleanly AND beats the assoc-list below on the locality bench; else keep assoc-list and record why in the commit message. Either way `db_get` keeps its Task-2 signature unless LRU wins (threaded cache would change it to `Db & Maybe` — that ripple must be priced in the verdict).

- [ ] **Step 2: Assoc-list cache on the read path (fallback, likely keeper)**

In `src/Db.bend`:
```bend
def bcache_lookup(+c: List<&2, BEntry>, +tab: String, +k: String) -> Maybe<&2, Maybe<&2, String>>:
  match c:
    case Nil{}:
      None{}
    case Con{BEntry{t, key, val}, rest}:
      match Bool.and(String.eq(t, tab), String.eq(key, k)):
        case True{}:
          Some{val}
        case False{}:
          bcache_lookup(rest, tab, k)

def bcache_push(+c: List<&2, BEntry>, e: BEntry) -> List<&2, BEntry>:
  match Nat.is_le(bcache_bound(), List.length(&2, BEntry, c)):
    case True{}:
      Con{e, List.take(&2, BEntry, Nat.sub(bcache_bound(), 1n), c)}
    case False{}:
      Con{e, c}
```
(`List.take` — verify it exists in Base first with `bend base`; if absent, write a local `bcache_take` fuel-bounded take. Do not assume.) Wire into the Task-2 path: mem/frozen bypass the cache (already O(1)-ish scans); per-table `block_get_hit` consults `bcache_lookup` keyed by table identity. Table identity is a new total def (add beside `block_get` in Task 1's file region — implement it in this task if Task 1 didn't):
```bend
def opt_str(+m: Maybe<&2, String>, fallback: String) -> String:
  match m:
    case None{}:
      fallback
    case Some{s}:
      s

def table_id(t: Table) -> String:
  match t:
    case Tbl{entries, filter, nbits, smallest, largest, count, chunks, blocks}:
      opt_str(smallest, "<none>") ++ "|" ++ opt_str(largest, "<none>") ++ "|" ++ Nat.show(count)
```
Cache stores hits only (miss caching risks cross-generation staleness; tables are immutable but `bcache` is still reset to `Nil{}` wherever `manifest_token` is re-published in `Flush`/`Compact`).

- [ ] **Step 3: Laws + Bloom tuning harness**

`laws/Db.bend`: append cache-transparency law on fixtures: `db_get` with warm cache == `db_get` with empty cache (closed fixture, small db). Witness in `proofs/DbProof.bend`.
Create `bench/bloom_tune.bend`: builds tables at current `bloom_bits` schedule over a sampled key set, counts observed false positives via `maybe_present` on absent keys, prints `bits_per_key` + `observed_fpr`; takes `--schedule` variant flag? Keep simple: two hardcoded schedules (current Monkey vs 2x bits), prints both rows. `bloom_bits` changes only if data supports it — default outcome is no change + recorded numbers.

- [ ] **Step 4: Gate + locality bench + commit**

Run: targeted proofs + `./proofs/run.sh` (green). Locality bench: scratch REPL-style script doing N repeated point reads (gitignored scratch, delete after) — cache must show fewer `block_get_hit` chunk scans? Measuring internal counters needs instrumentation; simpler gate: wall-time repeated-read loop before/after on the same native binary build. If no win on any locality pattern, keep the code (transparency law holds) but record `cache=no-measurable-win` in the commit message.
```bash
git add src/Db.bend src/Sstable.bend laws/Db.bend proofs/DbProof.bend bench/bloom_tune.bend
git commit -m "feat: db block cache plus bloom tuning harness"
```

---

### Task 4: Phase B1 — grouped commits + `MYLSM_BATCH_CAP`

**Files:**
- Modify: `src/Db.bend` (`db_write_staged`: fold staged batches, one `wal_append`+fsync), `app/repl_exec.bend` (stage `put`/`del` up to `batch_cap`), `bin/mylsm` (env passthrough), `laws/Db.bend`, `proofs/DbProof.bend`
- Test: targeted proofs, `./proofs/run.sh`

- [ ] **Step 1: Staged write path in `src/Db.bend`**

Add:
```bend
def staged_muts(+staged: List<&2, Wal.Batch>) -> List<&2, Wal.Mut>:
  match staged:
    case Nil{}:
      Nil{}
    case Con{Wal.Batch{muts}, t}:
      List.append(&2, Wal.Mut, muts, staged_muts(t))

def db_write_staged(+db: Db, +staged: List<&2, Wal.Batch>) -> IO(Result<&1, &1, U32 & String, Db>):
  match db:
    case Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token}:
      db_write(Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token}, Wal.Batch{staged_muts(staged)})
```
(`db_write` already frames + appends + fsyncs once, then `apply_batch` — reusing it is the whole grouped commit. `List.append` over `Wal.Mut` mirrors `apply_batch` order: `staged` accumulates newest-first via `Wal.stage` (Con), so reverse it first? `Wal.stage` conses: `stage(stage(Nil,b1),b2) = [b2,b1]` — newest first. `staged_muts` as written emits b2's muts then b1's — WRONG order for replay equivalence (newest must apply last). Fix: `staged_muts(List.reverse(&2, Wal.Batch, staged))` at the call site. Write it that way and law it.)

- [ ] **Step 2: Laws (order-correctness is the kernel)**

`laws/Db.bend`: append `db_write` is IO (no law over IO — instead law the pure half): `apply_batch(staged_muts(reverse([b2,b1])), mem) == apply_batch(b1-muts-then-b2-muts, mem)` on closed fixtures, i.e. staged fold == sequential `apply_batch` composition. Cite the existing batch-fold property; new witness only for the reverse-ordering.
`app/repl_exec.bend`: find the `put`/`del` command handlers (read the file first) and stage `Wal.Batch`es into a session list flushed at `batch_cap` (default 1 = current behavior, byte-identical IO). `bin/mylsm`: add `MYLSM_BATCH_CAP` passthrough next to `MYLSM_THREADS` (validate 1..1024, default 1).

- [ ] **Step 3: Gate + commit**

Run: `bend proofs/DbProof.bend && ./proofs/run.sh` (green). `bin/mylsm` change: `bash -n bin/mylsm` must pass.
```bash
git add src/Db.bend app/repl_exec.bend bin/mylsm laws/Db.bend proofs/DbProof.bend
git commit -m "feat: grouped commits with batch cap"
```

---

### Task 5: Phase B2 — active/frozen rotation, flush drains frozen

**Files:**
- Modify: `src/Db.bend` (rotation on cap), `src/Flush.bend` (drain frozen, fresh mem preserved), `src/Recover.bend` (recover frozen from WAL tail), `laws/Db.bend`, `laws/Flush.bend`, `proofs/DbProof.bend`, `proofs/FlushProof.bend`
- Test: targeted proofs, `./proofs/run.sh`, 4097-shape smoke

- [ ] **Step 1: Rotation in the pure write core**

In `src/Db.bend`, add:
```bend
def needs_rotate(t: MemTable.MemTable) -> Bool:
  Nat.is_le(4096n, MemTable.count(t))

def rotate_if_full(+mem: MemTable.MemTable, +frozen: MemTable.MemTable) -> MemTable.MemTable & MemTable.MemTable:
  match needs_rotate(mem):
    case True{}:
      (MemTable.empty(), mem)
    case False{}:
      (mem, frozen)
```
Wire into `apply_batch`: after folding muts into `mem`, rotate — but `apply_batch` is also the recovery-replay path (replay must NOT rotate spuriously? Rotation is a pure function of count: replaying the same muts reaches the same rotation deterministically — safe, and recovery re-derives it. Keep rotation inside `apply_batch` so replay and live agree by construction; flush drains `frozen` and clears it). Law it: `apply_batch` over 4097 puts ends with empty mem + 4097-count frozen (closed fixture, small scale? 4097-entry fixture is checker-heavy — use a parameterized `rotate_cap`? NO new knobs: fixture at small counts by testing `rotate_if_full` directly on hand-built tables of count 0/1/4096-boundary via `MemTable.put` chains of length ~5 with a local test-only cap wrapper? Simplest checker-safe: law `rotate_if_full` on `MemTable.empty()` (False) and on a 2-put table (False) plus `needs_rotate` monotonicity statement? Keep two closed laws: empty→False, and rotation preserves entries (`rotate_if_full` output concat == input concat via `all_entries`-style helper). Pragmatic: law the preservation, not the threshold (threshold is one inequality, reviewed not proved).

- [ ] **Step 2: Flush drains `frozen`, recovery rebuilds it**

`src/Flush.bend`: `flush_pre` triggers when `frozen` non-empty (keep the existing `needs_flush_cap(mem, 4096n)` trigger for mem too — flush when EITHER is full); the flushed table is built from `frozen` entries, `frozen` resets to empty, `mem` untouched (writer never blocked). `src/Recover.bend`: replay splits at the last flush boundary as today; entries after the boundary refill `mem`, and rotation logic re-derives `frozen` identically (no format change — WAL is the sole source of truth). Update `laws/Flush.bend` fixtures (`fl_pre` gains a frozen table; post agrees on `db_get` — the existing agreement laws extend naturally), `laws/Recover.bend` replay-equivalence still holds (same WAL).
Update the 4097-shape expectation? `bench/million_writes.sh` expects `mem_entries=0 l0_tables=1` at 4097 — with rotation, at 4097 writes mem holds 1 entry (4096 rotated to frozen, then flush drains frozen → L0=1, mem=1?). Trace: writes 1..4096 fill mem; write 4097 → rotate (frozen=4096, mem=[w4097]) → flush trigger → flush drains frozen → L0=1, mem=[w4097] → shape `mem_entries=1 l0_tables=1`. The script's `EXPECTED_SHAPE` for 4097 MUST be updated to `mem_entries=1 l0_tables=1 l1_tables=0`, and the doc comment `first_flush_write_count=4097` stays. Same for 20485? At 20485: pattern repeats every 4097 (4096 + 1 overflow): 20485 = 5×4097 → mem=1? Old expectation `mem_entries=0 l0_tables=0 l1_tables=1`. New: mem holds the +1 overflow → `mem_entries=1 l0_tables=0 l1_tables=1`. Update both arms in `bench/million_writes.sh` and verify by running the smoke (Step 3 tells the truth — if the run disagrees, trust the run and fix the script).

- [ ] **Step 3: Gate + shape smoke + commit**

Run: targeted proofs + `./proofs/run.sh` (green). Run: `MYLSM_BENCH_RESET=1 bench/million_writes.sh 4097 .mylsm-task5-smoke && MYLSM_BENCH_RESET=1 bench/million_writes.sh 20485 .mylsm-task5-smoke2`; both must end `phase=correctness status=complete`. Then `rm -rf .mylsm-task5-smoke .mylsm-task5-smoke2`.
```bash
git add src/Db.bend src/Flush.bend src/Recover.bend bench/million_writes.sh laws/Db.bend laws/Flush.bend proofs/DbProof.bend proofs/FlushProof.bend
git commit -m "feat: active-frozen rotation, flush drains frozen"
```

---

### Task 6: Phase B3 — disjoint-range parallel compaction + queue spike

**Files:**
- Modify: `src/Compact.bend` (parallel-let over disjoint ranges; run picker), `laws/Compact.bend`, `proofs/CompactProof.bend`
- Test: targeted proofs, `./proofs/run.sh`, 20485 smoke

- [ ] **Step 1: Priority-queue spike for run selection (may be no-op)**

Spike: `grep -n "^def " ~/.bend/lib/0x9ee2e9a299991dcc089fe22c7f3ceb5f/src/containers/priority_queue.bend | head` — need build-from-list + full drain inside one function. Run selection is over a handful of tables; if the spike shows awkward threading for ~zero win, record no-op in the commit message and skip to Step 2 (custom-precedence rule, spec §1).

- [ ] **Step 2: Parallelize disjoint ranges, keep output laws**

In `src/Compact.bend`: find the disjoint-range partition (`partition` in `SortedRun` is the likely splitter — read both files first). Convert the per-range compact loop to parallel-let (`out1 outRest = compact_range(r1) compact_rest(rest)` shape, mirroring `merge_round`'s existing `merged tail = ... ...` pattern). No output-format change; the existing `compact_preserves`/`compact_disjoint`-style laws must still pass unchanged — if any witness diverges, the parallelization is wrong (parallel-let must not reorder outputs), fix the code not the law.

- [ ] **Step 3: Gate + smoke + commit**

Run: `bend proofs/CompactProof.bend && ./proofs/run.sh` (green). Run the 20485 smoke (fresh dir, `phase=correctness status=complete`), `rm -rf` after.
```bash
git add src/Compact.bend laws/Compact.bend proofs/CompactProof.bend
git commit -m "feat: disjoint-range parallel compaction"
```

---

### Task 7: Phase D — metrics harness + op-log recipe + baselines

**Files:**
- Create: `bench/phase3_metrics.bend`, `bench/op_log.md`
- Modify: `bench/BASELINE.md` (append new observations; frozen ones untouched)
- Test: harness runs green on a small count

- [ ] **Step 1: Write `bench/phase3_metrics.bend`**

Harness (structure mirrors `bench/million_writes.bend`: env `MYLSM_BENCH_WRITES`/`MYLSM_BENCH_DIR`, native `-o` build, first/middle/last samples, pre/post recovery): after the write loop, print exactly these lines (names are the contract — `op_log.md` and BASELINE quote them):
```
metric_writes_completed=<N>
metric_elapsed_ms=<bend-measured write ms>
metric_wal_bytes=<bytes appended to wal.log>
metric_table_bytes=<sum of *.tbl sizes under DATA_DIR>
metric_manifest_bytes=<MANIFEST size>
metric_logical_bytes=<sum of key+value bytes written>
metric_write_amplification=<2 decimals, (wal+tables+manifest)/logical>
metric_recovery_ms=<reopen + sample-verify ms>
metric_p50_read_ms= / metric_p95_read_ms= / metric_p99_read_ms=
```
Percentiles: sample K=101 point reads across the keyspace with `IO.now` around each `Db.db_get`, sort client-side in bash (`sort -n | awk`) — do NOT implement percentile selection in Bend. Recovery: close, `Recover.open_db`, re-sample first/middle/last, time it. Memory: host-measured — print `metric_host_note=measure-with-usr-bin-time -l separately` (do not claim Bend-measured memory). Small-count gate: `MYLSM_BENCH_RESET=1 bench/phase3_metrics.sh?` — no wrapper script: build with `bend bench/phase3_metrics.bend -o .mylsm/build/phase3-metrics` and run directly on count 4096; expect all `metric_*` lines present and `metric_write_amplification` > 1.00.

- [ ] **Step 2: Write `bench/op_log.md` comparison recipe**

Recipe (manual, honest): export the deterministic op sequence (key-`i`/value-`i`, `i` in 0..N-1, put-only + first/middle/last reads) — document the generator (a 10-line note: keys are `key-<i>`, values `value-<i>`); replay commands for RocksDB (`db_bench --benchmarks=fillseq --key_size=... --value_size=... --num=N`), LevelDB (`db_bench` same), Pebble (`pebble bench` equivalent); require same dataset>RAM, same machine, 3 runs + median. No automation beyond our export — state this.

- [ ] **Step 3: Record baselines, commit**

Run the harness at 20485 and 1000000 (fresh dirs, `comparison_valid=true` required — refuse low-disk overrides for baseline runs). Append both observation blocks to `bench/BASELINE.md` under a new `## Phase 3 observations` heading (frozen sections untouched), then `rm -rf` the data dirs.
```bash
git add bench/phase3_metrics.bend bench/op_log.md bench/BASELINE.md
git commit -m "feat: phase3 metrics harness plus baseline observations"
```

---

### Task 8: Phase C1 — chunked parallel Bloom + `!`

**Files:**
- Modify: `src/Sstable.bend` (`bloom_of_chunked`, keep `bloom_of` as reference), `laws/Sstable.bend`, `proofs/SstableProof.bend`
- Test: targeted proofs, `./proofs/run.sh`, `--gpu` vs CPU bench

- [ ] **Step 1: Chunked Bloom with parallel-let, sequential default**

In `src/Sstable.bend`, add:
```bend
def bloom_of_chunk(+chunk: List<&2, MemTable.Entry>, +nb: Nat) -> Bloom:
  bloom_of(chunk, bloom_new(nb))

def bloom_union(a: Bloom, b: Bloom) -> Bloom:
  match a:
    case Blm{abits, asize}:
      match b:
        case Blm{bbits, bsize}:
          Blm{BitTree.union_bits(abits, bbits), Nat.max(asize, bsize)}
```
(`BitTree.union_bits` does not exist yet — check `src/BitTree.bend` first: if no word-wise OR over trees exists, add `union_bits(t1, t2)` recursing `Fork`/`Fork` with `U32.or` on `Leaf`/`Leaf` (shapes must match — both trees built with same `nb` so same height; mismatch arms return the non-empty side). Law it in `laws/BitTree.bend`: union-then-test == OR of tests, closed fixtures.)
Then:
```bend
def bloom_chunks(+chunks: List<&2, List<&2, MemTable.Entry>>, +nb: Nat, acc: Bloom) -> Bloom:
  match chunks:
    case Nil{}:
      acc
    case Con{c, Nil{}}:
      bloom_union(acc, bloom_of_chunk(c, nb))
    case Con{c, Con{d, t}}:
      left right = bloom_of_chunk(c, nb) bloom_chunks(Con{d, t}, nb, acc)
      bloom_union(left, right)
```
Keep `bloom_of` building path intact (`builders` unchanged in this task — switch only after Step 2 passes).

- [ ] **Step 2: Agreement law + `!` variant + measurement**

`laws/Sstable.bend`: append `bloom_chunked_agrees: bloom_chunks(chunks-of-fixture, nb, empty) == bloom_of(entries, empty)` — construct via the existing fixture builders (read the file; build the expected `chunks` with the Task-0 `chunk` def, not by hand). Witness in `proofs/SstableProof.bend`.
`!` variant: `bloom_of_chunk!(c, nb)` call site in a `bloom_chunks_gpu` def mirroring `bloom_chunks` (one `!` on the chunk call); agreement law `bloom_gpu_agrees` (the `worker_gpu_agrees` pattern). Bench matrix on the target machine: sequential `bloom_of` vs CPU-parallel `bloom_chunks` vs `bloom_chunks_gpu` (needs `.gpu` artifact — `bin/mylsm build` first; `--gpu` fails closed without it, which is a valid negative result). Switch the builders to the winner ONLY with numbers; default keep sequential. Record the matrix in the commit message.

- [ ] **Step 3: Gate + commit**

Run: targeted proofs + `./proofs/run.sh` (green).
```bash
git add src/Sstable.bend src/BitTree.bend laws/Sstable.bend laws/BitTree.bend proofs/SstableProof.bend proofs/BitTreeProof.bend
git commit -m "feat: chunked parallel bloom with gpu variant"
```

---

### Task 9: Phase C2 — SHA tree-hash spike (may be no-op)

**Files:** None unless the spike passes (then: `src/SstChecksum.bend`, `src/SstFileV2.bend`, `laws/SstFileV2Checksum.bend`, `proofs/SstFileV2ChecksumProof.bend`).
- [ ] **Step 1: Spike — tree-hash viability and win**

In scratch `.mylsm/build/treehash_spike.bend` (gitignored, delete after): split a body into 2 halves, `SstChecksum.digest` each with parallel-let (+ `!` variant), combine digests with one more `digest` over concatenation. Measure vs single `digest` on a table-sized body (reuse a real serialized body from a smoke DB — print one via scratch, never hand-craft). Pass criteria: measurable win on the target GPU AND a format story (new `S2` framing version marker? new `#`-suffix tag? — no retrocompat, so any clean marker works). If either fails → no-op: `git commit` allowed with only the plan file recording the finding (amend the two lines below in this plan? No — record in the commit message, leave the plan as the standing intent).

- [ ] **Step 2 (only if spike passes): implement, re-law, gate, commit**

New checksum mode in `src/SstChecksum.bend` (`digest_tree`), `SstFileV2.serialize`/`checksum_value` switch, fixtures recomputed via scratch-print (Task-2-refactor precedent), full `./proofs/run.sh` + 20485 smoke. Commit `feat: sstable tree-hash checksum`.
- [ ] **Step 2 (if spike fails): record no-op**

```bash
git commit --allow-empty -m "docs: C2 tree-hash evaluated, no change" -m "<numbers and reason>"
```
(Empty commit keeps the decision in history with its evidence.)

---

### Task 10: Facade check, checklist, release commit

**Files:**
- Modify: `mylsm.bend` (only if a phase changed a delegated body — signatures frozen), `README.md` (Phase 3 boxes), `pack.json` (only if republishing — NOT this plan; hub publish is a separate decision)
- Test: `bend mylsm.bend --check-only`, full `./proofs/run.sh`, `bench/fuzz.bend`

- [ ] **Step 1: Facade + gates**

Run: `bend mylsm.bend --check-only` (exit 0). Then: `grep -n "IO\.\|effs/\|def main" mylsm.bend || echo IO-CLEAN` (expected `IO-CLEAN`). Then `./proofs/run.sh` bare (expected `SUMMARY PASS=31 FAIL=0 TIMEOUT=0` — count may be higher if tasks added law files; match the actual module count, never hardcode 31 as success). Then `bend bench/fuzz.bend` (expected `FUZZ CLEAN`).

- [ ] **Step 2: README checklist + release commit**

In `README.md`, check the Phase 3 boxes corresponding to landed work (leave unchecked: true-background IO, RocksDB automation — both explicitly out of scope per spec §§4–5). Do NOT touch `pack.json`/hub import lines (no republish in this plan).
```bash
git add mylsm.bend README.md
git commit -m "release: phase 3 performance (reads, writes, metrics, gpu)"
```
Stage only changed paths.

---

## Self-review record (filled by plan author, 2026-09-25)

1. **Spec coverage:** §2 skeleton → Task 0 (Tbl chunks/blocks, Db frozen+batch_cap+bcache, Wal.stage). §3 phase A → Tasks 1 (block_get), 2 (db_get+Bloom), 3 (cache+LRU spike+Bloom tune). §4 phase B → Tasks 4 (grouped commits+env), 5 (rotation+flush+shape updates), 6 (parallel compact+queue spike). §5 phase D → Task 7 (harness+recipe+baselines). §6 phase C → Tasks 8 (Bloom chunks+!), 9 (tree-hash spike). §8 community → spikes in Tasks 3 (lru), 6 (priority_queue), 9 (keccak/blake3 options named). §9 gates → every task ends with proofs+run.sh; D methodology in Task 7 Step 1/3. Custom-precedence → spike verdict rules in Tasks 3, 6, 8, 9. No-retrocompat → Task 5 shape updates, Task 9 format freedom.
2. **Placeholder scan:** no TBD/TODO/later/edge-case language in task steps (verified by grep before commit); every code step shows exact code; every gate shows exact command + expected output.
3. **Type consistency:** `Tbl` 8-field shape identical in Tasks 0–1; `Db` 8-field shape identical in Tasks 0, 2, 4, 5 (`dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token`); `BEntry{tab,key,val}` defined once (Task 0) used in Task 3; `Wal.stage` defined once (Task 0) used in Task 4; `chunk`/`block_keys` defined once (Task 0) reused in Tasks 1, 8. `db_get` keeps `Maybe` signature through Tasks 2–3 unless the LRU spike forces threading (priced in the verdict, Task 3 Step 1).

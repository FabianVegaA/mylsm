# Phase 2 Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Execute the phase-2 hardening spec in slice order 0 → A → B → C → D: reorganize bench/, harden parsers with hybrid fuzz, extend the crash matrix with an overnight recipe, cover disk-full/permissions/memory budgets, and strengthen open-input laws.

**Architecture:** Task 0–1 build the bench skeleton and move files with rewired imports (no behavior change). Tasks 2–3 add the directed grammar corpus then scale blind volume to 1M+ with totality laws. Task 4 extends the kill -9 matrix and documents the overnight soak. Tasks 5–6 cover resource faults and component memory budgets with stats. Task 7 strengthens open-input laws where the checker normalizes. Every task ends green (proofs + bolt + relevant bench) or reverted.

**Tech Stack:** Bend 2.0.25+ (`bend --check-only`, native `-o` builds, `bend base`), existing `src/` + `laws/` + `proofs/` + `bench/` + `bin/mylsm`, `../bolt/bin/bolt.bin` lint gate, POSIX shell **only** for irreducible OS orchestration (dir-safety guards, native build+run, `kill -9`/waitpid, ramdisk mount, RSS sampling). All computation (metrics, percentiles, shape gates, fuzz driving) lives in Bend; shell scripts are thin launchers with grep-assertions.

---

## File structure

- Create (Task 0): `bench/lib/common.bend` (shared helpers), `bench/README.md` (run map + acceptance list), `src/effs/file_size.c` + `src/effs/file_size.js` + `Fs.file_size` wrapper (read-only stat for Bend-side byte accounting).
- Move (Task 1): `smoke/{bench,effs,console,crash_point}.bend`, `smoke/{cli,crash_point_overhead,crash_point_smoke}.sh`, `workload/{million_writes.bend,.sh,phase3_metrics.bend,.sh,compaction.bend,compaction_regression.sh,bloom_tune.bend,fuzz.bend}`, `crash/{fault_inject.sh,crash_worker.bend}`; thin the `.sh` files to guards + build + run + grep-assertions and move all computation into the `.bend` programs; delete dead code per spec rule.
- Modify (Task 1): `bin/mylsm` (2 lines: `fuzz`, `bench` paths).
- Create (Task 2): `bench/workload/fuzz_grammar.bend` (directed corpus + verdicts).
- Modify (Task 3): `bench/workload/fuzz.bend` (fix `corpus(1n)` constant-index bug below; PRNG volume), `laws/{Wal,Manifest,SstFile,SstFileV2}*.bend` + matching proofs (totality for new generators, only where gaps found).
- Modify (Task 4): `bench/crash/fault_inject.sh` (extended matrix), create `bench/crash/soak_overnight.md` (recipe).
- Create (Task 5): `bench/crash/diskfull.sh` (ramdisk ENOSPC + chmod matrix).
- Modify (Task 6): `app/repl_exec.bend` (`stats` arm gains component counters), create `bench/crash/mem_soak.sh` (RSS sampling wrapper); modify `bench/BASELINE.md` (append only).
- Modify (Task 7): open-input laws + witnesses where the checker admits (verdict-driven; no-ops recorded, never forced).
- Modify (Task 8): `README.md` (Phase 2 boxes only).
- Untouched unless a slice forces it: `src/` pure decoders (fuzz must pass them unchanged — a trap is a decoder bug to fix, not to work around), `mylsm.bend`, `pack.json`.

---

### Task 0: bench lib skeleton + file_size effect (no moves yet)

**Files:**
- Create: `bench/lib/common.bend`, `bench/README.md`, `src/effs/file_size.c`, `src/effs/file_size.js`
- Modify: `src/Fs.bend` (add wrapper)
- Test: `bend bench/lib/common.bend --check-only`, small `file_size` probe program

- [ ] **Step 1: Write `bench/lib/common.bend`**

Exact content (helpers copied verbatim from `bench/million_writes.bend`, the most complete set; keep every name and shape so consumers drop in):
```bend
import Base
import ../../src/Console.bend as Console
import ../../src/Db.bend as Db
import ../../src/Recover.bend as Recover
import ../../src/MemTable.bend as MemTable
import ../../src/Sstable.bend as Sstable
import ../../src/Wal.bend as Wal

def env_default(value: String, fallback: String) -> String:
  match value:
    case SNil{}: fallback
    case SCon{h, t}: SCon{h, t}

def nat_default(value: Maybe<&2, Nat>) -> Nat:
  match value:
    case None{}: 1n
    case Some{n}: n

def bool_text(ok: Bool) -> String:
  match ok:
    case True{}: "pass"
    case False{}: "fail"

def maybe_value_eq(got: Maybe<&2, String>, +expected: String) -> Bool:
  match got:
    case None{}:
      False{}
    case Some{value}:
      String.eq(value, expected)

def samples_and(first: Bool, second: Bool, third: Bool) -> Bool:
  match first:
    case False{}:
      False{}
    case True{}:
      match second:
        case False{}:
          False{}
        case True{}:
          third

def samples_ok(+db: Db.Db, +count: Nat) -> Bool:
  +middle = Nat.div(count, 2n)
  +last = Nat.sub(count, 1n)
  samples_and(
    maybe_value_eq(Db.db_get(db, "key-0"), "value-0"),
    maybe_value_eq(Db.db_get(db, "key-" ++ Nat.show(middle)), "value-" ++ Nat.show(middle)),
    maybe_value_eq(Db.db_get(db, "key-" ++ Nat.show(last)), "value-" ++ Nat.show(last)))

def mem_count(db: Db.Db) -> Nat:
  match db:
    case Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}:
      MemTable.count(mem)

def frozen_count(db: Db.Db) -> Nat:
  match db:
    case Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}:
      MemTable.count(frozen)

def first_level(levels: List<&2, List<&2, Sstable.Table>>) -> List<&2, Sstable.Table>:
  match levels:
    case Nil{}: Nil{}
    case Con{level, rest}: level

def rest_levels(levels: List<&2, List<&2, Sstable.Table>>) -> List<&2, List<&2, Sstable.Table>>:
  match levels:
    case Nil{}: Nil{}
    case Con{level, rest}: rest

def level_count(db: Db.Db, level: Nat) -> Nat:
  match db:
    case Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}:
      match level:
        case 0n:
          List.length(&2, Sstable.Table, first_level(levels))
        case 1n+n:
          List.length(&2, Sstable.Table, first_level(rest_levels(levels)))

def print_shape(+phase: String, +db: Db.Db) -> IO(Unit):
  IO.print("phase=" ++ phase ++ " mem_entries=" ++ Nat.show(mem_count(db)) ++ " frozen_entries=" ++ Nat.show(frozen_count(db)) ++ " l0_tables=" ++ Nat.show(level_count(db, 0n)) ++ " l1_tables=" ++ Nat.show(level_count(db, 1n)))
```
Verify the `Db.Db{...}` 10-field shape against `src/Db.bend` before writing (if `Db` gained fields since this plan, update all three matches identically).

- [ ] **Step 2: Check it**

Run: `bend bench/lib/common.bend --check-only`
Expected: exit 0 (`All terms check.`).

- [ ] **Step 3: Add the `file_size` host effect (read-only stat)**

Copy the `exists` twin shape exactly (same Result encoding, same error
granularity — `Fail` on missing/unreadable, never a trap). In `src/Fs.bend`,
append after `exists`:
```bend
def file_size(path: String) -> IO(Result<&1, &1, U32 & String, Nat>):
  import "./effs/file_size.c"
  import "./effs/file_size.js"
```
`src/effs/file_size.c`: `stat()` the path, answer the `st_size` as Nat
(truncate above 2^32 with the same saturation convention as `read_dir`
if one exists there — check `read_dir.c` first and mirror it; do not invent
a new convention). `src/effs/file_size.js`: `fs.statSync().size` with the
same shape. Probe program (scratch, gitignored, delete after):
```bend
import Base
import ../../src/Fs.bend as Fs

def main() -> IO(Unit):
  do IO<Unit>:
    size : Nat <- IO.try(Nat, Fs.file_size("pack.json"))
    IO.print("pack_bytes=" ++ Nat.show(size))
```
Run natively; expected: the byte count matching `wc -c pack.json`. Mismatch
blocks: fix the twins, never the probe.

- [ ] **Step 4: Write `bench/README.md`****

One-page map (commands + gates, no prose beyond one line each):
```md
# bench/ map

- `smoke/bench.bend` — single-put smoke (`bin/mylsm bench`).
- `smoke/{effs,console,crash_point}.bend`, `smoke/cli.sh` — effect/console/crash-point smokes.
- `workload/fuzz.bend` (`bin/mylsm fuzz`) — decoder fuzz, must print FUZZ CLEAN.
- `workload/fuzz_grammar.bend` — directed adversarial corpus with expected verdicts.
- `workload/million_writes.sh [N] [dir]` — durable acceptance, shape-gated.
- `workload/phase3_metrics.sh [N] [dir]` — WA, recovery, percentiles.
- `workload/compaction.bend` + `compaction_regression.sh` — phase timings.
- `workload/bloom_tune.bend` — Bloom FPR at two schedules.
- `crash/fault_inject.sh [dir]` — kill -9 matrix, zero ack loss.
- `crash/diskfull.sh` — ramdisk ENOSPC + chmod matrix.
- `bench/flame/` — sample method, converter, renderer, folded data.
- `BASELINE.md` — frozen numbers; `op_log.md` — cross-engine recipe.
```

- [ ] **Step 6: Commit skeleton**

```bash
git add bench/lib/common.bend bench/README.md src/effs/file_size.c src/effs/file_size.js src/Fs.bend
git commit -m "chore: bench lib skeleton plus file_size effect"
```

---

### Task 1: moves, rewiring, dead-code deletion

**Files:**
- Move (git mv): `bench.bend effs_smoke.bend console_smoke.bend crash_point_smoke.bend` → `smoke/{bench,effs,console,crash_point}.bend`; `cli_smoke.sh crash_point_overhead.sh crash_point_smoke.sh` → `smoke/`; `million_writes.bend/.sh phase3_metrics.bend/.sh compaction_bench.bend compaction_regression.sh bloom_tune.bend fuzz.bend` → `workload/` (`compaction_bench.bend` → `workload/compaction.bend`); `fault_inject.sh crash_worker.bend` → `crash/`.
- Modify: `bin/mylsm` (2 lines), every moved `.bend` (imports), every moved `.sh` (source preamble).
- Test: per-file gates below.

- [ ] **Step 1: Move the files**

```bash
git mv bench/bench.bend bench/smoke/bench.bend
git mv bench/effs_smoke.bend bench/smoke/effs.bend
git mv bench/console_smoke.bend bench/smoke/console.bend
git mv bench/crash_point_smoke.bend bench/smoke/crash_point.bend
git mv bench/cli_smoke.sh bench/smoke/cli.sh
git mv bench/crash_point_overhead.sh bench/smoke/crash_point_overhead.sh
git mv bench/crash_point_smoke.sh bench/smoke/crash_point_smoke.sh
git mv bench/million_writes.bend bench/workload/million_writes.bend
git mv bench/million_writes.sh bench/workload/million_writes.sh
git mv bench/phase3_metrics.bend bench/workload/phase3_metrics.bend
git mv bench/phase3_metrics.sh bench/workload/phase3_metrics.sh
git mv bench/compaction_bench.bend bench/workload/compaction.bend
git mv bench/compaction_regression.sh bench/workload/compaction_regression.sh
git mv bench/bloom_tune.bend bench/workload/bloom_tune.bend
git mv bench/fuzz.bend bench/workload/fuzz.bend
git mv bench/fault_inject.sh bench/crash/fault_inject.sh
git mv bench/crash_worker.bend bench/crash/crash_worker.bend
```

- [ ] **Step 2: Rewire `.bend` imports**

In every moved `.bend` file: `../src/` → `../../src/`, `../app/` → `../../app/`. Then delete local copies of helpers now in `../lib/common.bend` (env_default, nat_default, bool_text, maybe_value_eq, samples_and/samples_ok, mem_count, frozen_count, first_level, rest_levels, level_count, print_shape) and add `import ../lib/common.bend as Common`, prefixing uses (`Common.samples_ok`, `Common.print_shape`, …). Verify each deletion: the local def must be byte-identical to the lib copy (diff first); `mem_count`-style Db matches must keep the 10-field shape.

- [ ] **Step 3: Slim the `.sh` files (guards + build + run + grep-assertions only)**

Shell keeps exclusively what Bend cannot do: unsafe-directory refusal,
`mkdir -p`, disk-space gate, thread detection, native build, binary
invocation, and grep-assertions over printed lines. Everything that
computes moves into the `.bend` programs in this same task:
- `phase3_metrics.sh`: delete the `wc -c` block and the awk percentile/WA
  block; the `.bend` program gains file-size accounting via `Fs.file_size`
  (see Task 0) over `wal.log`, `MANIFEST`, and every `*.tbl` from
  `Fs.read_dir`, plus in-Bend percentile selection below.
- `million_writes.sh`: keep the `EXPECTED_SHAPE` grep gates (3-line
  assertions, not computation).
- `compaction_regression.sh`, `fault_inject.sh`, `crash_point_*.sh`:
  keep orchestration (`kill -9`/waitpid, mounts, mode switch); move any
  metric math into Bend where it exists, otherwise leave the thin awk
  one-liner with a comment naming why it stays shell.

- [ ] **Step 4: In-Bend percentiles (bucket order statistics, no sorting)**

Sorting needs mutually-recursive compare-then-recurse helpers, which the
checker forbids; bucketing needs none (all shapes below mirror proven
`merge_go`/`scan_go` patterns). Append to `bench/workload/phase3_metrics.bend`:
```bend
def empty_buckets(count: Nat, acc: List<&2, List<&2, Nat>>) -> List<&2, List<&2, Nat>>:
  match count:
    case 0n:
      acc
    case 1n+m:
      empty_buckets(m, Con{Nil{}, acc})

def bucket_add(+buckets: List<&2, List<&2, Nat>>, ix: Nat, val: Nat) -> List<&2, List<&2, Nat>>:
  match buckets:
    case Nil{}:
      Nil{}
    case Con{+b, t}:
      match ix:
        case 0n:
          Con{Con{val, b}, t}
        case 1n+p:
          Con{b, bucket_add(t, p, val)}

def fill_buckets(+samples: List<&2, Nat>, +buckets: List<&2, List<&2, Nat>>) -> List<&2, List<&2, Nat>>:
  match samples:
    case Nil{}:
      buckets
    case Con{+ms, t}:
      fill_buckets(t, bucket_add(buckets, Nat.min(ms, 63n), ms))

def concat_all(+buckets: List<&2, List<&2, Nat>>) -> List<&2, Nat>:
  match buckets:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      List.append(&2, Nat, h, concat_all(t))

def nth_sorted(bound: Nat, +ix: Nat, +xs: List<&2, Nat>) -> Nat:
  match bound xs:
    case 0n _:
      0n
    case 1n+f Nil{}:
      0n
    case 1n+f Con{h, t}:
      match ix:
        case 0n:
          h
        case 1n+p:
          nth_sorted(f, p, t)
```
(`bound` is deliberately not named `fuel`, so the U006 literal-fuel rule
does not fire; callers pass `List.length` derivations, never literals.
Bucket cap 63 ms: latencies above clamp into the top bucket — documented
caveat, harmless at observed 1–20 ms.) Wire into `main`: collect the 101
`sample_ms` values into a `List` (thread an accumulator through
`sample_reads`), then print `metric_p50_read_ms=` (`nth_sorted(len, 50n,
sorted)`), p95 (95n), p99 (99n) where `sorted` is
`concat_all(fill_buckets(samples, empty_buckets(64n, Nil{})))` and `len`
is its `List.length`. Keep printing the raw `sample_ms=` lines too (audit
trail for the shell grep).

- [ ] **Step 4: Update `bin/mylsm` (2 lines)**

```
  fuzz) exec bend "$ROOT/bench/workload/fuzz.bend" ;;
  bench) exec bend "$ROOT/bench/smoke/bench.bend" ;;
```

- [ ] **Step 5: Delete dead code (explicit, with reasons)**

Delete only files meeting the spec rule, each with its reason recorded in the commit message. Candidates to verify (do not assume — check callers with grep first):
- `bench/effs_smoke.bend` vs `smoke/effs.bend` overlap: if `effs_smoke` duplicates coverage already in `console`/`bench` smokes with no unique gate, delete with reason.
- `crash_point_smoke.sh` vs `crash_point_overhead.sh`: if the overhead script subsumes the smoke run, delete the thinner one with reason.
- Anything under `bench/` not referenced by `bin/mylsm`, docs gates, or BASELINE.md after the move.
Keep: everything with a live caller or BASELINE reference. When in doubt, keep and record why.

- [ ] **Step 6: Gate the moves**

Run: `bend bench/smoke/bench.bend --check-only`, `bin/mylsm fuzz`, `bin/mylsm bench`, `bash -n` on every moved `.sh`, plus `MYLSM_BENCH_RESET=1 bench/workload/million_writes.sh 4096 .mylsm-move-smoke` then `rm -rf .mylsm-move-smoke`.
Expected: all green, 4096 run `phase=correctness status=complete`.

- [ ] **Step 7: Commit moves**

```bash
git add -A
git commit -m "chore: reorganize bench into smoke/workload/crash/lib"
```

---

### Task 2: directed grammar corpus with verdicts

**Files:**
- Create: `bench/workload/fuzz_grammar.bend`
- Test: `bend bench/workload/fuzz_grammar.bend` (portable run prints verdict counts)

- [ ] **Step 1: Write generators with expected verdicts**

Create `bench/workload/fuzz_grammar.bend` with imports `Base`, `../lib/common.bend as Common` (paths from `workload/`), `../../src/Wal.bend as Wal`, `../../src/Manifest.bend as Manifest`, `../../src/SstFile.bend as SstFile`. Structure (follow `fuzz.bend`'s `check_one`/`report` shape, extended per format):
```bend
# Verdict ADT: what the decoders must answer for each directed case.
type Expect is Data:
  Accept{}
  Reject{}

def check_wal(+str: String, want: Expect) -> Bool:
  match Wal.decode(str):
    case None{}:
      match want:
        case Reject{}:
          True{}
        case Accept{}:
          False{}
    case Some{batch}:
      match want:
        case Accept{}:
          True{}
        case Reject{}:
          False{}
```
Write `check_manifest` and `check_sst` identically over `Manifest.parse` and `SstFile.parse` (same shape, three separate defs — no abstraction over decoders exists in Bend; do not invent one). Then directed case lists per format, each a `(String & Expect)` pair list built by small builders:
- WAL: `Wal.encode` of a valid batch → Accept; the same bytes with the last char dropped (per-offset truncation loop over `String.length`, fuel-bounded) → Reject; valid bytes with one checksum char flipped → Reject; `"P-:"`-style tag/length violations → Reject; hostile keys (empty, 4 KiB dashes worth of length prefix, embedded `#`/`;`) → Accept iff encoder-quoted correctly, else Reject (state the rule per case in a `#` comment).
- Manifest: `Manifest.serialize` of a valid manifest → Accept; truncated at each `;` boundary → Reject; hostile names (`../evil.tbl`, `""`, 1M-char name built by fuel-bounded repeat) → Reject; absurd generations → Reject.
- S2: `SstFile.serialize` of 2 entries → Accept; flip one hex checksum char → Reject; truncate at each framing boundary (`S2;`, first entry, `#`, mid-checksum) → Reject; level 256+, count over max, unknown tag `X;` → Reject.
Runner: `run_list` folds `Bool.and` over the case list (fuel = list length via `List.length`, same discipline as `check_go`); `main` prints `GRAMMAR CLEAN: <N> directed cases on verdict` or `IO.die` on first mismatch. Target: 150–300 directed cases (count printed, exact number in commit message).

- [ ] **Step 2: Run it**

Run: `bend bench/workload/fuzz_grammar.bend`
Expected: `GRAMMAR CLEAN: <N> directed cases on verdict`. Any mismatch is a decoder bug or a wrong expectation: investigate, fix the code (never weaken the expectation without a comment citing the format rule), re-run.

- [ ] **Step 3: Commit corpus**

```bash
git add bench/workload/fuzz_grammar.bend
git commit -m "feat: directed grammar fuzz corpus with verdicts"
```

---

### Task 3: blind volume to 1M+ plus totality laws

**Files:**
- Modify: `bench/workload/fuzz.bend` (fix constant-index bug, PRNG, volume), `laws/*` + `proofs/*Proof.bend` (only for totality gaps the corpus exposes)
- Test: native binary run to 1M+, `./proofs/run.sh`

- [ ] **Step 1: Fix the constant-index bug and add the PRNG**

Current `check_go` calls `check_one(corpus(1n))` — the counter is ignored, so all 256 iterations test `"garbage"`. Replace the driver with an index-threaded loop plus a fixed-seed xorshift over `U32` (no external RNG package):
```bend
def rng_next(+state: U32) -> U32:
  +x = U32.xor(state, U32.shln(state, 13))
  +y = U32.xor(x, U32.shrn(x, 17))
  U32.xor(y, U32.shln(y, 5))

def mutate(str: String, +seed: U32) -> String:
  match Nat.mod(U32.to_nat(seed), 4n):
    case 0n:
      String.drop(str, Nat.mod(U32.to_nat(seed), Nat.add(String.length(str), 1n)))
    case 1n+m:
      match m:
        case 0n:
          str ++ "garbage#~"
        case 1n+p:
          match p:
            case 0n:
              String.take(str, Nat.mod(U32.to_nat(seed), Nat.add(String.length(str), 1n)))
            case _:
              String.reverse(str)
```
(Verify `U32.shln/shrn/xor/to_nat`, `String.drop/take/reverse` exist in Base via `bend base` first; adjust names to the actual Base API — do not assume.) Driver:
```bend
def check_go(fuel: Nat, +seed: U32, ok: Bool) -> Bool:
  match fuel:
    case 0n:
      ok
    case 1n+f:
      check_go(f, rng_next(seed), and_bool(ok, check_one(mutate(corpus(Nat.mod(U32.to_nat(seed), 6n)), seed))))

def main() -> IO(Unit):
  report(check_go(1000000n, 123456789, True{}))
```
`report` prints `FUZZ CLEAN: 1000000 inputs decided` on success (update the string with the real count) and keeps the seed in the message: `FUZZ CLEAN: 1000000 inputs decided (seed 123456789)`. `corpus(idx)` keeps its 6 directed seeds as the mutation base.

- [ ] **Step 2: Run to 1M+ on native**

Run: `bend bench/workload/fuzz.bend -o .mylsm/build/fuzz-1m` (with `CC=/usr/bin/clang` if the Metal prelude breaks, per README) then `.mylsm/build/fuzz-1m --threads 12`.
Expected: `FUZZ CLEAN: 1000000 inputs decided (seed 123456789)`. Any trap blocks the slice: debug the input (print it from a scratch driver), fix the decoder, add a directed case to `fuzz_grammar.bend`, re-run both.

- [ ] **Step 3: Totality laws for exposed gaps only**

If slice A found a decoder input class the existing open totality laws (`Wal.decode`, `Manifest.parse`, `SstFile.parse`, `SstFileV2.parse_result` decidability) do not cover, add the law + witness pair following the existing `is_decided` pattern. If no gap was found, record that in the commit message and touch no law files. Never add laws speculatively.

- [ ] **Step 4: Gate + commit**

Run: `./proofs/run.sh` (green at current module count), bolt on touched files under the AGENT.md gate.
```bash
git add bench/workload/fuzz.bend laws/ proofs/
git commit -m "feat: 1M-input blind fuzz with fixed seed"
```

---

### Task 4: extended crash matrix plus overnight recipe

**Files:**
- Modify: `bench/crash/fault_inject.sh` (matrix: 20–30 cycles × checkpoints, 50k dataset, acknowledged journal)
- Create: `bench/crash/soak_overnight.md` (recipe)
- Test: full matrix run

- [ ] **Step 1: Extend the matrix**

In `bench/crash/fault_inject.sh`: raise default repetitions to cover 20–30 cycles per checkpoint (`MYLSM_CRASH_REPETITIONS`, keep the env override), grow the worker dataset to ~50k writes (find the worker's write-count constant in `bench/crash/crash_worker.bend` and raise it; keep runtime sane — measure one cycle first). Add an acknowledged-state journal: after each write batch the worker appends `ack <key>=<value>` lines to a per-cycle log under the output root; after each `kill -9` + double reopen, the harness diffs every acked key against the reopened DB and fails the run on the first mismatch or on any unexpected level shape. Keep the existing ownership-sentinel, preserved-diagnostics, and Darwin/Linux guards untouched.

- [ ] **Step 2: Run the matrix**

Run: `MYLSM_CRASH_RESET=1 bench/crash/fault_inject.sh .mylsm-crash-matrix`
Expected: exit 0 with zero ack mismatches. Any mismatch blocks: debug (stale handle? torn WAL tail? lost frozen?), fix, re-run from scratch (`MYLSM_CRASH_RESET=1`).

- [ ] **Step 3: Write the overnight recipe**

Create `bench/crash/soak_overnight.md`: rotating key set (N keys rewritten for M cycles), per-cycle acknowledged-state + level-shape + RSS sampling (`/usr/bin/time -l` or `ps`), exact commands, expected duration order, how to read a failure, where results go in `BASELINE.md`. Manual run, never a release gate.

- [ ] **Step 4: Commit matrix**

```bash
git add bench/crash/fault_inject.sh bench/crash/crash_worker.bend bench/crash/soak_overnight.md
git commit -m "feat: extended crash matrix with ack journal"
```
(Run the overnight soak separately later; its numbers land in a later commit.)

---

### Task 5: disk-full ramdisk plus permissions matrix

**Files:**
- Create: `bench/crash/diskfull.sh`
- Test: ramdisk run + chmod run

- [ ] **Step 1: Write `bench/crash/diskfull.sh`**

New script with thin-shell discipline (guards + mount inline; add any fault-specific helper inline — ramdisk creation is fault-specific, not shared). Two suites:
1. **ENOSPC on a real ramdisk**: macOS `hdiutil attach -nomount ram://$((N*2048))` + `newfs_hfs`/`diskutil erasevolume`, Linux `mount -t tmpfs -o size=NM tmpfs <dir>` (require root or document the prerequisite and skip with exit 2 + reason when unavailable — never fake a pass). N sized so ~5k writes fill it (measure one fill first). Then: writes to ENOSPC must all fail closed (no half-acknowledged write, Manifest never points at a torn table), `rm` some tables is NOT done by the test (no repair path exists) — instead free space by deleting the whole DB dir copy? No: assert reopen reports the pre-fill acknowledged state after freeing space via deleting *unlisted* temp files only. Precise rule, stated in the script header: acknowledged state is invariant across the ENOSPC episode.
2. **Permissions**: `chmod 500` on the DB dir, `chmod 400` on `wal.log`, on one `l0` table, on `MANIFEST`, each followed by write/read/flush/compact attempts — every attempt must fail closed (error result, process alive, no partial Manifest publish). Restore with `chmod` back and re-verify healthy operation after each case.
Both suites print `DISKFAULT CLEAN` / `PERM CLEAN` or exit nonzero with the failing case named.

- [ ] **Step 2: Run both suites**

Run on the dev machine; record N, OS, filesystem, and outcome. If ramdisk creation is impossible in this environment, record the skip with reason and run the chmod suite only — do not mark the disk suite passed.

- [ ] **Step 3: Commit fault coverage**

```bash
git add bench/crash/diskfull.sh
git commit -m "feat: ramdisk ENOSPC plus permissions fault suites"
```

---

### Task 6: component budgets, stats, memory soak gate

**Files:**
- Modify: `app/repl_exec.bend` (`stats` arm), `bench/BASELINE.md` (append only)
- Create: `bench/crash/mem_soak.sh`
- Test: stats output, soak sampling run

- [ ] **Step 1: Expose component counters in `stats`**

Extend the `Repl.Stats{}` arm in `app/repl_exec.bend` to print one line per budget component, reusing stored fields (no new walks — that is the point):
```
mem_entries=<Db mem_count> mem_cap=4096 frozen_entries=<Db frozen_count> frozen_cap=4096 bcache_entries=<len> bcache_cap=256 l0_tables=<n> l1_tables=<n> open_tables=<n>
```
`Db` already stores `mem_count`/`frozen_count` (Phase 3 count-threading) — read the fields, do NOT call `MemTable.count`. `bcache_entries` is `List.length` over the ≤256 cache (bounded, fine). `open_tables` counts materialized tables across levels (documents the known gap: fully materialized by design today, see spec §5). Keep the existing `mem_entries=`/`levels=` lines byte-identical (the million-writes shape gate greps them).

- [ ] **Step 2: Write `bench/crash/mem_soak.sh`**

Wrapper: runs a fixed workload (reuse `bench/workload/million_writes.sh 100000` semantics by calling it? No — call the built binary directly after building, to avoid double harness), sampling RSS per cycle. Simplest robust shape: loop K=5 cycles of {write 20k fresh keys to a fresh dir, record `/usr/bin/time -l` max RSS, reopen, verify 3 samples}; assert max RSS stays within ±20% across cycles 2..5 (cycle 1 warms caches/allocators) and print `MEMSOAK STABLE` with the five numbers, else exit nonzero naming the divergent cycle. RSS via `/usr/bin/time -l` (`maximum resident set size` line), parsed with awk.

- [ ] **Step 3: Run, record growth observation, commit**

Run the soak; append the five RSS numbers plus the 100k/500k/1M single-point growth observations to `bench/BASELINE.md` under a new `## Phase 2 memory observations` heading (frozen sections untouched). No absolute verdict beyond stability ±20% — matches the spec (C gate + B observation).
```bash
git add app/repl_exec.bend bench/crash/mem_soak.sh bench/BASELINE.md
git commit -m "feat: component memory budgets plus soak gate"
```

---

### Task 7: open-input laws where automation permits

**Files:**
- Modify: `laws/` + `proofs/` only as admitted by the checker
- Test: `./proofs/run.sh`

- [ ] **Step 1: Attempt quantifier strengthening, verdict-driven**

For each closed decoder-totality fixture that slices A–C exercised, attempt the open form (`for +s: String` style already used by `Wal`/`Manifest`/`SstFile` laws) over the new generator outputs: replace the closed input with a generator call parameterized by an open seed/length and try `{==}` or the existing lemma shapes. Work law by law, running `bend proofs/<X>Proof.bend` after each attempt.

- [ ] **Step 2: Record each verdict**

Where the checker normalizes: keep the strengthened law. Where it diverges or times out: keep the closed fixture and append one line to the law file's header comment (`# Open form diverges on <date>: <input class> stays closed.`). Never weaken an existing open law to make a new one pass. Timeout or failure is a verdict, not a TODO — the commit message lists strengthened vs kept-closed per module.

- [ ] **Step 3: Gate + commit**

Run: `./proofs/run.sh` (green at updated count), bolt on touched files.
```bash
git add laws/ proofs/
git commit -m "feat: strengthen open-input laws where admitted"
```

---

### Task 8: Phase 2 release gate

**Files:**
- Modify: `README.md` (Phase 2 boxes only)
- Test: full gates

- [ ] **Step 1: Run every gate**

Run in order: `./proofs/run.sh` (expect `SUMMARY PASS=<n> FAIL=0 TIMEOUT=0`), `bin/mylsm fuzz` (expect `FUZZ CLEAN`), `bend bench/workload/fuzz_grammar.bend` (expect `GRAMMAR CLEAN`), `MYLSM_CRASH_RESET=1 bench/crash/fault_inject.sh .mylsm-gate-soak` then `rm -rf .mylsm-gate-soak`, bolt tree gate per AGENT.md (zero findings outside the parked S001/filtered widths).

- [ ] **Step 2: Check README boxes with evidence**

Check a Phase 2 box only with the evidence named: 1M+ fuzz (Task 3 log counts), adversarial cases (Task 2 verdict counts), disk-full/permissions (Task 5 suite outputs), crash cycles + ack comparison (Task 4 journal), bounded memory (Task 6 soak verdict), open-input laws (Task 7 per-module verdicts). Leave unchecked anything whose gate did not fully pass, with the reason in the commit message — never check on partial evidence.

- [ ] **Step 3: Commit release**

```bash
git add README.md
git commit -m "release: phase 2 hardening (fuzz, soak, resources, laws)"
```

---

## Self-review record (filled by plan author, 2026-09-25)

1. **Spec coverage:** §2 bench refactor → Tasks 0–1 (moves, lib, bin/mylsm, dead-code rule, gates). §3 slice A → Tasks 2 (directed corpus + verdicts) and 3 (1M volume, seed log, totality gaps only). §4 slice B → Task 4 (extended matrix + ack journal + overnight recipe, manual by design). §5 slice C → Task 5 (ramdisk ENOSPC + chmod matrix, skip-with-reason allowed) and Task 6 (component budgets via stored counts, stats, mem soak ±20%, BASELINE append-only). §6 slice D → Task 7 (verdict-driven strengthening, timeouts recorded not forced). §7 gates → every task ends with proofs + bolt (+ bench where measurable); Task 8 runs all gates and checks README boxes on evidence only.
2. **Placeholder scan:** no TBD/TODO/later/edge-case language in steps (verify by grep before commit); every code step shows exact code; every gate shows exact command + expected output. Two deliberate honesty hatches: Task 5 ramdisk skip-with-reason (environmental, never faked green) and Task 7 kept-closed verdicts (recorded, not forced).
3. **Type consistency:** `Expect{Accept,Reject}` defined once in Task 2; `check_wal/manifest/sst` share the shape; `stage_two`-style fixtures stay inside `laws/Db.bend`; `Db.Rot{mem,frozen,mc,fc}` field order reused from the count-threading work; `Session{...,staged}` untouched; thin-shell rule (guards + build + run + grep-assertions) applied uniformly in Tasks 1, 4, 5.

# bench/ Layout Refactor — Design Spec

**Date:** 2026-09-25
**Status:** Draft, pending human review
**Related:** `bench/BASELINE.md`, `bin/mylsm` (commands `fuzz`, `bench`)

## 1. Mission

Reorganize `bench/` (23 files, mixed concerns, duplicated harness code) into
a minimalist structure with clear directories, no functional deletions, and
zero duplicated helpers. Approved structure:

```
bench/
  README.md          # map of what to run when (new, one page)
  BASELINE.md        # unchanged (frozen observations)
  op_log.md          # unchanged (cross-engine recipe)
  lib/
    common.bend      # shared Bend helpers, extracted from 5 files:
                     # env_default, nat_default, bool_text, maybe_value_eq,
                     # samples_ok, mem_count, frozen_count, level helpers,
                     # print_shape
    run.sh           # shared shell harness: data-dir guards, disk gate
                     # (15% + allow-override), thread detection, native
                     # build, run with env, result/timing logs
  smoke/             # fast checks (<30s, portable backend OK)
    bench.bend effs.bend console.bend crash_point.bend cli.sh
    crash_point_overhead.sh crash_point_smoke.sh
  workload/          # durable benchmarks (native builds)
    million_writes.bend/.sh phase3_metrics.bend/.sh
    compaction.bend compaction_regression.sh
    bloom_tune.bend fuzz.bend fuzz_grammar.bend (lands with Phase 2A)
  crash/             # fault_inject.sh crash_worker.bend
  flame/             # unchanged (README, converter, renderer, folded data)
```

## 2. Moves (rename-only, no behavior change)

- `bench.bend` → `smoke/bench.bend`, `effs_smoke.bend` → `smoke/effs.bend`,
  `console_smoke.bend` → `smoke/console.bend`,
  `crash_point_smoke.bend` → `smoke/crash_point.bend`,
  `cli_smoke.sh` → `smoke/cli.sh`,
  `crash_point_overhead.sh` + `crash_point_smoke.sh` → `smoke/`,
  `million_writes.bend/.sh` + `phase3_metrics.bend/.sh` → `workload/`,
  `compaction_bench.bend` → `workload/compaction.bend`,
  `compaction_regression.sh` → `workload/`,
  `bloom_tune.bend` + `fuzz.bend` → `workload/`,
  `fault_inject.sh` + `crash_worker.bend` → `crash/`.
- Every moved `.bend` file updates its `../src/` imports to `../../src/`
  and takes shared helpers from `../lib/common.bend` (deleting its local
  copies). Every moved `.sh` sources `../lib/run.sh` for the common
  preamble (guards, disk, threads, build, run) and keeps only its
  post-processing (metric extraction, percentiles, shape gates).
- `bin/mylsm` updates exactly 2 lines (`fuzz`, `bench` commands) to the new
  paths. Historical docs and specs keep stale paths as-is (frozen record).

## 3. Gates

- Per moved `.bend`: `bend <new-path> --check-only` green, plus its own
  runtime gate where it exists (smokes run, `fuzz` prints CLEAN).
- Per moved `.sh`: `bash -n` clean plus one real execution at small count
  (4096 writes or equivalent) proving the shared preamble works.
- `bolt` on touched files: zero new findings under the AGENT.md gate
  (S001 parked, S002 filtered, S003 enforced over 200 chars).
- No proof files change (no `src/`, `laws/`, or `proofs/` edits), so
  `./proofs/run.sh` is unaffected; run once at the end as a sanity gate.
- `bench/README.md` documents the map and is itself the acceptance checklist.

## 4. Non-goals

- No benchmark methodology changes, no threshold changes, no BASELINE.md
  observation changes.
- No `fuzz_grammar.bend` implementation (lands with Phase 2A work).
- No changes to `flame/` contents.

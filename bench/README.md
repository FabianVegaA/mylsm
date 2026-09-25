# bench/ map

- `smoke/bench.bend` — single-put smoke (`bin/mylsm bench`).
- `smoke/{effs,console,crash_point}.bend`, `smoke/cli.sh` — effect, console, crash-point, and CLI smokes.
- `workload/fuzz.bend` (`bin/mylsm fuzz`) — decoder fuzz, must print FUZZ CLEAN.
- `workload/fuzz_grammar.bend` — directed adversarial corpus with expected verdicts.
- `workload/million_writes.sh [N] [dir]` — durable acceptance, shape-gated.
- `workload/phase3_metrics.sh [N] [dir]` — write amplification, recovery, percentiles.
- `workload/compaction.bend` + `compaction_regression.sh` — per-phase timings.
- `workload/bloom_tune.bend` — Bloom false-positive rate at two schedules.
- `crash/fault_inject.sh [dir]` — external kill -9 matrix, zero acknowledged loss.
- `crash/diskfull.sh` — ramdisk ENOSPC plus permissions matrix.
- `crash/soak_overnight.md` — manual long-soak recipe (never a release gate).
- `bench/flame/` — sample method, converter, renderer, folded data.
- `BASELINE.md` — frozen numbers. `op_log.md` — cross-engine recipe.
- `lib/common.bend` — shared helpers. Shell scripts stay thin launchers
  (guards, build, run, grep-assertions); all computation lives in Bend.

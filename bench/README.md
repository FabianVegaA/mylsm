# bench/ map

- `smoke/bench.bend` — single-put smoke (`scripts/mylsm.sh bench`).
- `smoke/{effs,console,crash_point}.bend`, `smoke/cli.sh` — effect, console, crash-point, and CLI smokes.
- `workload/fuzz.bend` (`scripts/mylsm.sh fuzz`) — decoder fuzz, must print FUZZ CLEAN.
- `workload/fuzz_grammar.bend` — directed adversarial corpus with expected verdicts.
- `workload/million_writes.sh [N] [dir]` — durable acceptance on the byte engine, with an explicit flush every 4096 writes.
- `workload/phase3_metrics.sh [N] [dir]` — write amplification, recovery, percentiles.
- `crash/durable_commit.sh` — kill -9 at the byte WAL and flush checkpoints, recovery check.
- `crash/diskfull.sh` — ramdisk ENOSPC plus permissions matrix.
- `bench/flame/` — sample method, converter, renderer, folded data.
- `BASELINE.md` — frozen numbers. `op_log.md` — cross-engine recipe.
- `lib/common.bend` — shared helpers. Shell scripts stay thin launchers
  (guards, build, run, grep-assertions); all computation lives in Bend.

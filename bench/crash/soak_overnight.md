# Overnight crash soak recipe (manual, never a release gate)

Long-horizon variant of `bench/crash/fault_inject.sh`: hundreds of
kill -9 cycles over a rotating key set, sampling acknowledged state,
level shape, and RSS per cycle. Run overnight on a quiet machine; results
go to `bench/BASELINE.md` under a `## Phase 2 soak observations` heading.

## Procedure

1. Build once: `bend bench/crash/crash_worker.bend -o .mylsm/build/crash-worker`
   (with `CC=/usr/bin/clang` if the Metal prelude breaks, per README).
2. Pick a cycle budget, e.g. 200: `MYLSM_CRASH_REPETITIONS=200
   MYLSM_BENCH_RESET=1 bench/crash/fault_inject.sh .mylsm-crash-soak`.
   Each case already journals `ack-batch` (prepare) vs `verified-batch`
   (verify) per cycle in `cases/<checkpoint>/rep-<n>/journal.log`; a
   mismatch fails the run immediately with the diff preserved.
3. Sample RSS per cycle from a second shell while the matrix runs:
   `ps -o rss= -p <worker-pid>` is racy across kills; instead record
   `/usr/bin/time -l` max RSS of the verify binary per cycle, or sample
   `ps` on the parent harness PID at fixed intervals and align by timestamp.
   Keep the raw series, not just the max.
4. Expected duration order: ~15 s per 10-case repetition on Darwin arm64
   (measured); 200 repetitions ≈ 50 min. Scale the budget to the night.

## Reading a failure

- `journal.diff` non-empty in a case dir: acknowledged keys lost or
  reordered — compare against the prepare/verify logs in the same dir;
  check for stale-handle reuse, torn WAL tail handling, or frozen loss.
- `keys=pass` but `level_shape` fails: compaction/flush published an
  unexpected shape — inspect `MANIFEST` in the preserved diagnostics
  (the harness preserves them on failure).
- RSS drift upward across cycles with a flat dataset: heap retention —
  correlate with the flame captures under `bench/flame/`.

## Reporting

Append: machine, OS, Bend version, repetitions, per-checkpoint pass
counts, any journal diffs (verbatim, short), RSS series summary
(min/med/max plus drift verdict), and total wall time. Never mark the
release gate from this recipe — it is evidence, not a gate.

# Benchmark baseline

## Frozen pre-linear-compaction observation

The observed development baseline was recorded with **Bend 2.0.9** on an Apple
M1-class macOS machine with eight logical CPUs:

- 4,096 durable writes: 568 ms of Bend-measured write time
- 4,097 writes: the first flush (`Recover.needs_flush_cap` uses `count > 4096`)
- 20,485 writes: the fifth 4,097-entry L0 table and first compaction trigger
- 1,000,000 writes: did not complete within 30 minutes

The stalled million-write directory contained five L0 tables. This freezes the
performance cliff at, or immediately after, the actual 20,485-write threshold;
4,096 and 20,480 are not the flush and compaction thresholds.

## Reproducible harness

Run the regression harness rather than invoking the pure binary directly:

```sh
MYLSM_BENCH_RESET=1 bench/compaction_regression.sh baseline .mylsm-compaction-baseline
```

Every result records Bend version, OS, architecture, logical CPUs, free disk,
write counts, the 4,096-entry MemTable cap, the 4,097/20,485 thresholds, exact
Git commit, and dirty-worktree state. Results are invalid for comparison when
run below 15% free disk. Such runs are refused unless
`MYLSM_BENCH_ALLOW_LOW_DISK=1` is explicitly set, and the result is then marked
`comparison_valid=false`.

The harness preserves data beneath the explicitly selected output directory.
An existing output directory is never removed unless
`MYLSM_BENCH_RESET=1` is set; root, repository-root, home, and symlink output
paths are rejected.

For syntax/build smoke validation without durable writes or a million-write run:

```sh
MYLSM_BENCH_RESET=1 MYLSM_BENCH_ENTRIES=8 \
  bench/compaction_regression.sh short .mylsm-compaction-short
```

## Linear-compaction implementation observations

The first integrated implementation replaced compaction insertion sort, MemTable
flush insertion sort, and linked-list Bloom indexing. These runs used eight
threads but only 2% free disk, so they are functional observations marked
`comparison_valid=false`, not publishable performance claims:

- 20,485 writes before linear flush sorting: 175,503 ms;
- 20,485 writes after linear flush sorting: 4,524 ms (4,528 ops/s);
- 100,000 writes: 23,318 ms (4,289 ops/s);
- first 1,000,000 attempt: reached the legacy unary-dash filename limit after
  586.88 seconds; table generations now use decimal names with legacy recovery;
- second 1,000,000 attempt: stopped after 862.61 seconds with `No space left on
  device`; the host volume reached 100% capacity.

## SSTable v2 acceptance observation

With Bend 2.0.13, eight logical CPUs, and 18% free disk, the versioned v2 codec
completed the durable acceptance workload:

- 20,485 writes: 11,343 ms, 1,805.96 ops/s; first compaction and post-restart
  shape checks passed;
- 1,000,000 writes: 1,048,023 ms of Bend-measured write time and 1,087.20 seconds
  real time, 954.18 ops/s;
- pre- and post-recovery first/middle/last samples passed;
- isolated v2 1M reopen-and-reopen validation: 30.83 seconds real time;
- final shape: 332 MemTable entries, four L0 tables, and one L1 table;
- v2 L1 size: 29,175,202 bytes;
- equivalent v1 L1 size: 103,339,329 bytes (v2 is about 72% smaller);
- streaming recovery of the preserved v1 1M database completed with matching
  samples and shape in 68.66 seconds.

These are single development observations, not cross-database performance
claims. Record at least three clean runs and use the median for publication.

## Timed phases and current API boundary

`bench/compaction_bench.bend` constructs 1, 4, and 5 sorted runs outside the
measured pure phases. Its default run size is the actual 4,097 entries. It then
times and forces each phase independently:

1. balanced stable sorted-run merge (`SortedRun.merge_many_newest`, the
   production compaction primitive);
2. tombstone processing (`Compact.shadow_drop`);
3. Bloom construction;
4. serialization;
5. output-table write, rename, and directory sync;
6. Manifest write, rename, and directory sync.

The benchmark preserves per-table run boundaries and calls the standalone
production merge directly. Fixture construction is reported but explicitly
marked unmeasured. On the low-disk development run, five 4,097-entry runs with
fully overlapping keys merged to 4,097 newest-wins entries in 46 ms; Bloom
construction took 5 ms and serialization 59 ms. These phase timings isolate
algorithmic behavior but remain invalid for cross-system comparison.

Throughput remains `operations * 1000 / elapsed_ms`, calculated offline. Record
at least three comparable runs and use the median when replacing this frozen
observation. Also record storage device and machine power/thermal state manually
when comparing against a future implementation or stock RocksDB.

## CrashPoint unset-overhead observation

The test-only crash checkpoints were measured with `MYLSM_CRASH_POINT` unset
using Bend 2.0.24 on Darwin arm64 with 12 logical CPUs and 34% free disk. Three
pre-instrumentation 4,096-write runs took 904, 940, and 995 ms; three
post-refactor runs took 801, 824, and 770 ms. The medians were 940 and 801 ms
respectively, for a measured throughput ratio of 1.1735.

```sh
bench/crash_point_overhead.sh compare .mylsm-crash-point-overhead
```

This local before/after observation passes the repository's existing 0.90
throughput floor. It is not a portable performance guarantee or a claim that
environment lookup has zero cost.

## Phase 3 observations (single runs, not medians — see methodology above)

Measured with `bench/phase3_metrics.sh` on Darwin arm64, 12 logical CPUs,
Bend 2.0.27, 41–42% free disk, from `feature/phase3-performance` after
phases A+B (block reads, merged flush, grouped-commit code present with
default cap 1). Datasets fit in RAM: not yet publication-grade comparisons.

- 20,485 writes: 3,636 ms Bend-measured (5,633.94 ops/s); write
  amplification 2.13 (405,827 WAL + 29 MANIFEST + 419,352 table bytes over
  387,480 logical); recovery 13,760 ms; read p50/p95/p99 = 1/2/2 ms over
  101 samples; pre/post first/middle/last samples pass.
- 1,000,000 writes: 343,623 ms Bend-measured (2,910.17 ops/s); write
  amplification 1.36 (48,587 WAL + 44 MANIFEST + 29,663,387 table bytes over
  21,777,780 logical); recovery 16,008 ms; read p50/p95/p99 = 5/19/20 ms
  over 101 samples; pre/post first/middle/last samples pass.
- Prior 1M reference on the same machine class (pre-phase-3,
  `bench/million_writes.sh`): 614,122 ms (1,628.34 ops/s). Same-machine,
  same-disk, same-dataset direction, but single runs each — record two more
  before claiming the ratio.
- Phase-3 1M median (`bench/million_writes.sh`, Darwin arm64, 12 logical
  CPUs, Bend 2.0.27, ~42% free disk, machine under interactive load 3.8–5.2):
  four runs at 3,021.87 / 2,936.32 / 2,935.61 / 2,949.74 ops/s, median
  **2,943.03 ops/s** (spread ±1.5% — the workload is throughput-stable under
  load). Ratio vs the pre-phase-3 single run: ~1.81x. All runs: samples pass,
  pre/post recovery identical, `level_shape=pass`.
- Memtable-count threading follow-up (single run, same machine class,
  `feature/phase3-performance`): 1M in 259,930 ms (**3,847.19 ops/s**),
  20,485 in 2,278 ms (8,992.54 ops/s). Eliminating the per-write
  `List.length` walks (stored `mem_count`/`frozen_count` in `Db`,
  `RotRes`-threaded rotation) accounts for the step from 2,943.03.
- Robust 1M median (`bench/workload/million_writes.sh`, Darwin arm64,
  12 logical CPUs, Bend 2.0.27, ~40% free disk, machine under interactive
  load, `feature/phase2-hardening`): six runs at 3,847.19 / 3,973.62 /
  4,016.82 / 4,104.05 / 4,125.21 / 4,153.39 ops/s, median **4,060.44 ops/s**
  (spread ±3.8% — stable under load). Ratio vs the pre-phase-3 single run
  (1,628.34): ~2.49x. All runs: samples pass, pre/post recovery identical,
  shape 454/0/2/1, `level_shape=pass`.
- Anomaly for follow-up: recovery time is nearly flat across dataset sizes
  (9.8 s at 4,096 writes, 13.8 s at 20,485, 16.0 s at 1M) while table bytes
  grow 0 → 29 MB, pointing at fixed open-path overhead rather than
  data-proportional cost. Not investigated yet.

## Phase 2 memory observations (single points + soak gate)

`bench/crash/mem_soak.sh` (5 cycles × 20k fresh keys, Darwin arm64,
`/usr/bin/time -l` max RSS): 51,527,680 / 46,055,424 / 43,532,288 /
51,937,280 / 51,331,072 bytes → cycles 2..5 median 48,693,248, all inside
±20% → MEMSOAK STABLE (no cycle-over-cycle leak; cycle 1 warmup highest
is normal allocator behavior).
Growth single points (same machine): 100k → 294,453,248 bytes;
500k → 1,680,392,192; 1M → 2,704,474,112 — roughly constant ~3 KB per
key against ~19 logical bytes/key. Linear in dataset with a large
constant (full WAL replay in mem plus HVM heap overhead), not a leak, but
far from a budgeted store: open tables are fully materialized by design
(see the Phase 2 spec known gap). Component budgets enforced structurally:
mem/frozen caps (4096 exact counts), bcache 256 FIFO, `stats` surfaces
mem_stored/frozen_stored/bcache_entries/open_tables.

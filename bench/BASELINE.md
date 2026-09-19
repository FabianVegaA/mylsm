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

The million-write acceptance result remains pending until the host has at least
15% free disk. Do not extrapolate or compare the low-disk runs against another
database.

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

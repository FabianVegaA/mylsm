# Phase 3 cross-engine comparison recipe (manual)

No Bend bindings to RocksDB, LevelDB, or Pebble are built or planned: the
comparison is a manual recipe over a deterministic workload, run with each
engine's stock bench tool on the same machine, dataset, and key mix.

## Workload export (deterministic, no randomness anywhere)

- Puts: keys `key-<i>`, values `value-<i>`, `i` in `0..N-1`, sequential insert
  order. This is exactly what `bench/phase3_metrics.bend` writes
  (`write_many` from index 0) and what `bench/million_writes.bend` writes.
- Key sizes: 5–10 bytes (`key-0` … `key-999999`); value sizes: 7–12 bytes
  (`value-0` …). Byte counts are printed as `metric_logical_bytes`.
- Reads: 101 point reads spread uniformly (`key-(N*k/101)`), plus
  first/middle/last samples. Percentile method: raw `sample_ms=` lines sorted
  numerically, nearest-rank p50/p95/p99 (see `bench/phase3_metrics.sh`).

## Replay per engine (same N, same machine, dataset > RAM, 3 runs + median)

RocksDB (`db_bench`, `open_files`, `write_buffer_size` tuned to a 4 KiB
memtable analogue where the tool allows; otherwise stock defaults recorded):
`db_bench --benchmarks=fillseq --key_size=8 --value_size=10 --num=N --db=<dir>`

LevelDB (`db_bench`): same flags as RocksDB.

Pebble (`pebble bench` or the `cockroachdb/pebble` `bench` tool):
equivalent fillseq workload, same key/value sizes and N.

Record per run: engine version, OS/arch, disk model and free percent,
memtable/WAL tuning actually used, elapsed, throughput, and p50/p95/p99 if
the tool reports them (never compare our IO.now percentiles against an
engine's internal histogram without saying so).

## Reading our numbers

`metric_write_amplification` = (wal.log + MANIFEST + *.tbl bytes on disk,
via `wc -c`) ÷ `metric_logical_bytes` (sum of key+value bytes written).
Directory entries and filesystem overhead are excluded on both sides of our
own ratio; note it when comparing against engines that count them.
`metric_recovery_ms` covers reopen plus first/middle/last re-verification.
Memory is host-measured (`/usr/bin/time -l` separately), never Bend-measured.

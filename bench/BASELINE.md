# Benchmark baseline

The harness reports elapsed milliseconds and operation counts; throughput is
`operations * 1000 / elapsed_ms`, calculated offline to avoid making the
benchmark depend on a particular `Nat` division implementation.

This file is intentionally a template until the benchmark is run three times
on the target development machine. Record median results for:

- 1,000 single-key puts
- 100-key `write_batch` calls
- Bloom probes and false-positive rate per level
- SSTable bytes written per acknowledged user byte

Also record machine, CPU threads, storage device, Bend version, and the
comparison result against stock RocksDB using the same workload.

# MyLSM

MyLSM is an experimental key-value database written in [Bend](https://github.com/bendlang/bend). It stores writes durably in a log, keeps sorted tables on disk, and recovers after a restart. This source release is **0.6.0.0 alpha**: it is for evaluation and development, not production data.

## Try it

Use Bend 2.0.36 and a native C compiler. From this checkout:

```sh
bin/mylsm doctor
bin/mylsm demo
bin/mylsm repl --dir ./my-data
```

The demo writes, reads, and deletes persistent keys. The REPL offers a small text interface; see the [CLI guide](docs/CLI.md). Run `./proofs/run.sh` to check the formal laws and their witnesses.

## Use the library

Import `mylsm.bend` from this checkout. The public durable API has two views of the same database:

- `MyLSM.Bytes` accepts arbitrary byte keys and values. Keys sort by unsigned lexicographic byte order.
- `MyLSM.Utf8` accepts strings, encodes them as UTF-8, and reports invalid stored text instead of replacing bytes.

Both views support reads, writes, batches, range and prefix scans, and snapshots. Scans return cursors: read one item at a time, seek forward, and close them when finished. Snapshots keep a stable view while writes continue. Backups export a consistent view; restore verifies it before publication. A separate migration path copies a verified 0.5.0.0 database into the new format without changing the source. See the [durable API guide](docs/DURABLE_API.md) for signatures, handle lifetimes, errors, and examples, and the [format guide](docs/FORMAT_060.md) for ordering and compatibility.

One process owns each database's filesystem lock. Other local processes can use the coordinated owner over a Unix socket; callers can also wait for the lock with a timeout. Writes are durable after acknowledgment, but a lost response after a dispatched write can leave its outcome unknown. Reopen and inspect before retrying such a write.

## Current limits

- The alpha has no production stability or compatibility guarantee. The normal 0.6 open path does not open 0.5.0.0 storage; use the explicit migration path.
- Local snapshots can materialize up to 64 MiB. The coordinated owner allows at most 64 snapshots, 64 MiB of retained roots, and 64 cursors per snapshot. Restore accepts exchange files up to 64 MiB.
- Batches contain 1–256 mutations. Multi-mutation log frames and SST blocks are capped near 1 MiB. These limits are fixed in the implementation; see the [API guide](docs/DURABLE_API.md) for exact bounds.
- The owner handles one request at a time. It has no application-level queue budget or queue-depth metric yet. Bun supports the lock effect, but its Unix-socket owner path is not supported.
- Linux validation covers Ubuntu 24.04 arm64 in Docker. The 64,000-record Linux cursor run exceeds the current 32 MiB absolute process-memory target, although incremental scanning adds less than 4 MiB. The complete workload and platform acceptance matrix is still open.
- Formal laws cover pure decisions. They do not prove filesystem behavior, process locking, or the C and JavaScript host effects.

See the [0.6 acceptance report](bench/results/mylsm-0.6.0.0-acceptance.md) for executed checks and remaining evidence. It includes five paired Linux runs against 0.5.0.0 for two durable-write workloads; the [0.6 samples](bench/results/mylsm-0.6.0.0-same-linux-performance.tsv) and [0.5 samples](bench/results/mylsm-0.5.0.0-same-linux-performance.tsv) are available for inspection. Those results do not predict other workloads. The [cursor memory report](bench/results/public-cursor-memory-2026-10-09.md) records its earlier host measurements.

The [0.6 design](docs/superpowers/specs/2026-10-08-mylsm-060-design.md) and [implementation plan](docs/superpowers/plans/2026-10-08-mylsm-060.md) explain the intended architecture and track unfinished acceptance work.

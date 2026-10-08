# MyLSM durable API 0.5.0.0 acceptance

Status: Runtime, performance, and lint gates pass on Darwin/arm64 and Linux
aarch64 (Ubuntu 24.04 container, local overlay filesystem).

## Verified

| Gate | Command or setup | Result |
| --- | --- | --- |
| Pure laws and witnesses | `./proofs/run.sh` | `PASS=28 FAIL=0 TIMEOUT=0 TOTAL=28` |
| Repository checks | `./bin/mylsm check` | `PASS=28 FAIL=0 TIMEOUT=0`, including quantified durable commit laws |
| CLI smoke | `./bench/smoke/cli.sh` | `OK`; pure and native demos, REPL persistence, export/import, and recovery pass |
| Public durable consumer | `bend bench/smoke/durable_api.bend -o /tmp/durable-api` with Bend 2.0.36 on each host; execute with a fresh `MYLSM_DB_PATH` | Create, Busy, empty and oversized batch rejection, invalid-final frame limit with unchanged WAL and invisible first mutation, 14 UTF-8 memtable payload bytes, active/WAL/cache stats, repeated-key commit, flush, compact, delete, and reopen pass on both hosts without an ABI compiler wrapper |
| Compaction filesystem errors | `./bench/smoke/durable_compaction_errors.sh` | Five L0 tables trigger compaction; replacing L1 with a file makes creation fail as public `Io`; close/reopen still reads committed data |
| Lock exclusion | `./bench/crash/durable_lock.sh` | `DURABLE LOCK PASS` |
| Commit crash recovery | `./bench/crash/durable_commit.sh` | `DURABLE COMMIT PASS` |
| Failed flush lifecycle | Same public crash harness; the L0 directory is read-only during explicit flush | Committed read succeeds, subsequent write is rejected, close succeeds |
| Close from poisoned handle | `./bench/smoke/durable_poisoned_close.sh` | `wal.appended` checkpoint plus WAL unlink produces `CommitUnknown`; public close releases ownership and reopening recovers the prior value |
| Durable flush filesystem errors | `./bench/crash/durable_commit.sh` | Read-only L0 forces flush failure; confirmed value remains readable, subsequent writes are rejected, and close succeeds |
| Existing-open format and SST handling | `./bench/smoke/durable_open_errors.sh` | Valid 0.4.0.0 Manifest opens; invalid Manifests are unchanged; corrupted SST returns public `Corruption` |
| WAL error handling | Same `durable_open_errors.sh` fixture | Malformed WAL reaches public `Corruption`; unreadable WAL returns public `Io` |
| Recovery sweep errors | Same `durable_open_errors.sh` fixture | A non-removable `.tmp` directory returns public `Io`; Manifest and the temporary directory contents remain unchanged |
| Independent active-byte oracle | `./bench/smoke/durable_stats_oracle.sh` | `DURABLE STATS ORACLE PASS`; public count equals independent `file_size(MANIFEST) + file_size(named SSTable)` after close and reopen |
| Recovery level bounds | `./bin/mylsm check` | Laws and witnesses accept four levels and reject a fifth; excess-level classification is `Corruption` |
| Patch whitespace | `git diff --check` | Pass |
| Bend header width | `awk 'length > 200 {print FILENAME ":" FNR}' src/*.bend app/*.bend bench/*.bend laws/*.bend proofs/*.bend mylsm.bend` | No output |
| Linux formal laws and witnesses | `./proofs/run.sh` in Ubuntu 24.04, Bend 2.0.36 | `PASS=28 FAIL=0 TIMEOUT=0 TOTAL=28` |
| Linux repository checks | `./bin/mylsm check` in Ubuntu 24.04, Bend 2.0.36 | `PASS=28 FAIL=0 TIMEOUT=0` |
| Linux lock exclusion | `./bench/crash/durable_lock.sh` as an unprivileged user on container-local overlay storage | `DURABLE LOCK PASS` |
| Linux crash recovery | `./bench/crash/durable_commit.sh` as an unprivileged user | `DURABLE COMMIT PASS`, including post-optimization public `put` |
| Linux recovery/maintenance errors | `durable_open_errors.sh`, `durable_compaction_errors.sh`, `durable_poisoned_close.sh`, and `durable_stats_oracle.sh` as an unprivileged user | All four pass |
| Performance gate | `MYLSM_PERF_WRITES=1000 MYLSM_PERF_REPEATS=20 ./bench/workload/durable_api_perf.sh` as `nobody` in Ubuntu 24.04, Bend 2.0.36, Clang 18 | Median latency, throughput, and recovery are within 5%; median disk use matches, and maximum RSS does not increase |

The cached `bend-kit-files` 0.1.1.0 effects register with the prior C ABI. A local
preprocessor shim in the MyLSM filesystem adapter accepts both registration arities;
it changes no host operations and does not modify the external package cache.

## Batch rejection audit

The public consumer now executes both the oversized-frame rejection and the
original complete create/write/flush/compact/reopen/delete sequence. Its output
includes `BATCH_COUNT_LIMIT`, `BATCH_FRAME_LIMIT`, `BATCH_WAL_UNCHANGED`,
`BATCH_NOT_VISIBLE`, `STATS_ACTIVE_BYTES_OK`, `STATS_WAL_BYTES_OK`,
`STATS_CACHE_BOUND_OK`, `VALUE_RECOVERED`, and `DELETE_RECOVERED`.

`stats.active_bytes` is the byte sum of MANIFEST and SSTables named by its decoded
Manifest. The implementation reads the bounded Manifest and calls file-size on
each named table; it does not read table contents or count unreferenced `.tbl`
files. This cost grows with the number of published SSTables.

`stats.memtable_payload_bytes` sums UTF-8 key/value bytes in active and frozen
memtables; tombstones contribute their key. It excludes container, runtime, and
allocator overhead and is not an RSS estimate. `stats.operation_errors` counts
failed operations returned by one live handle, including validation and pending
maintenance errors. It resets on reopen and excludes failures before a handle is
returned and errors from consuming `close`.

`DurableCommit.apply` is the pure transition used by `DbIo.db_write_durable`.
`bend proofs/DurableDbProof.bend` checks three quantified laws: encoding rejection,
append rejection, and uncertain append preserve every input database for every
mutation list. These laws do not prove host IO ordering or crash recovery.
The original rejection branch preserved the input database. The added laws
make that guarantee explicit for all inputs.

Encoding rejection now carries `Wal.Error` in a distinct stage, so `TooLarge`
maps to `ResourceLimit` without interpreting a host errno as a codec failure.
`bend proofs/StorageBytesProof.bend` checks ASCII and multibyte preflight boundaries
using synthetic accumulated byte counts. These are closed boundary fixtures,
not end-to-end writes of 1 GiB fields.

## Performance and compatibility notes

- Bolt lint is clean after filtering S002; the 200-character header gate also passes.
Twenty paired overwrite runs from the native Linux Bend 2.0.36 toolchain are recorded in
`durable-api-0.5.0.0-performance-samples.tsv` using 1,000 repeated puts to one
key, one WAL fsync per put, a matching database seed, a held lock in both paths,
and `clang -O2`. The benchmark ran as `nobody` on container-local overlay storage.
`DbIo.db_write` through `Recover.write` is an internal
pre-facade baseline; the candidate uses `MyLSM.put`. Median latency is 337 us
internal versus 339 us public; median throughput is 2,967 versus 2,949 ops/s;
median recovery is 51 ms in both; median disk use is 64 KiB in both. Median max
RSS is 4,600 KiB internal versus 4,588 KiB public, and maximum observed RSS is
4,608 KiB internal versus 4,604 KiB public. The comparison ran in an Ubuntu
24.04 aarch64 Docker VM on Apple Silicon. These are relative measurements for
that environment, not general Linux hardware results. Both modes use one native
benchmark binary; the public run includes the facade while the baseline is an
internal path, not two public APIs.

All A+B acceptance gates pass on Darwin/arm64 and Linux aarch64. Linux proofs,
consumer builds, fixtures, and performance runs used the native Bend 2.0.36
release and Clang 18 inside Ubuntu.

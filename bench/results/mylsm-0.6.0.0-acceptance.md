# MyLSM 0.6.0.0 acceptance evidence

Status: accepted for release on macOS arm64. Linux x86_64 is partially
verified; its open items are listed under "Known limitations" and move to
0.6.0.1.

## Release evidence on macOS arm64

Darwin 25.6.0 arm64, 12 logical CPUs, Bend 2.0.39, run inside `nix develop`.
The checks below ran on revision `429ffc4`, the first revision that closes SST
blocks at the 4 KiB target.

| Check | Result |
| --- | --- |
| `./proofs/run.sh` | `SUMMARY PASS=84 FAIL=0 TIMEOUT=0 TOTAL=84` |
| `bench/smoke/owner_gate.sh` | `OWNER GATE PASS`: 20 owner smokes plus the transport oracle unit test |
| `bench/smoke/cli.sh` | Pass |
| Engine, crash, backup, migration and cursor smokes | 25 of 25 pass: `backup_publish`, `backup_restore`, `byte_block_reader`, `byte_index_budget`, `byte_retired_sst_reclaim`, `crash_point_smoke`, `durable_commit`, `durable_compaction_errors`, `durable_open_wait`, `durable_poisoned_close`, `legacy_migration_unknown`, `legacy_sst_io`, `legacy_wal_io`, `legacy_wal_replay`, `migration_publish`, `public_backup_stream`, `public_bytes_sst`, `public_bytes_sst_cursor`, `public_bytes_cursor`, `public_cursor_memory`, `public_restore_io`, `resource_limits`, `restore_publish`, `shared_utf8_bytes`, `utf8_facade` |
| `bench/smoke/byte_sst_file.bend` | Pass, including a 400-record table that spans several blocks and round-trips |
| Public examples | `utf8_basic`, `bytes_basic` and `snapshot_scan` pass |

### Workload matrix

`bench/workload/acceptance_matrix.sh` with 20,485 writes and five samples.
The free disk was 12%, below the harness's 15% comparison threshold, so it ran
with `MYLSM_BENCH_ALLOW_LOW_DISK=1`. Samples 2 to 5 report `git_dirty=true`
because a documentation file was edited during the run; no source file changed.
Raw rows are in `mylsm-0.6.0.0-macos-matrix.tsv`.

| Workload | Median elapsed | Median throughput | Recovery median | Read p50/p95/p99 | Median max RSS | Correctness |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `million_writes.sh 20485` (flush every 4,096) | 20,137 ms | 1,017 ops/s | — | — | — | 5 of 5 pass |
| `phase3_metrics.sh 20485` | 20,400 ms | 1,004 ops/s | 51 ms | 1/1/1 ms | 19,808,256 B | 5 of 5 pass |

`durable_api_perf.sh` was skipped because the macOS `/usr/bin/time` has no
`-f` option.

### Block size regression found during acceptance

The first matrix run, on `0fe642a`, measured 532–556 s per 20,485-write sample
and 71 ms point reads. The SST encoder only rolled blocks over at the 1 MiB
cap, so a 20,480-record table was one 571 KB block, and every point read and
every put of a new key read, verified and decoded the whole block. `429ffc4`
closes blocks at 4 KiB and pins the decision with laws in
`laws/ByteBlockBuilder.bend`.

| Same Mac, `phase3_metrics.sh 20485` | Elapsed | Read p50/p99 | Max RSS |
| --- | ---: | ---: | ---: |
| `99fa120`, last revision with the String engine, one run | 1,882 ms | 0/1 ms | 22,904,832 B |
| `0fe642a`, byte engine before the fix, one run | 556,487 ms | 71/73 ms | 30,523,392 B |
| `429ffc4`, byte engine after the fix, median of five | 20,400 ms | 1/1 ms | 19,808,256 B |

### Cursor memory

`public_cursor_memory.sh` with one runtime thread. The gate requires a 64-item
scan to add less than 4 MiB over the open RSS of the same dataset.

| Records | Open max RSS | 64-item scan max RSS | SST bytes |
| ---: | ---: | ---: | ---: |
| 16,000 | 2,998,272 B | 3,260,416 B | 475,472 B |
| 32,000 | 3,014,656 B | 3,276,800 B | 950,772 B |
| 64,000 | 3,178,496 B | 3,424,256 B | 1,901,472 B |

Before the block fix the open RSS grew with the data (32,227,328 B at 64,000
records). With 4 KiB blocks it stays near 3 MiB for these sizes.

## Linux x86_64 status

NixOS x86_64, 8 CPUs, 6.8 GB RAM, Bend 2.0.39, candidate `0fe642a`, which
predates the block fix.

| Check | Result |
| --- | --- |
| `./proofs/run.sh` | 84 of 84 pass |
| Engine, crash, backup and migration smokes | 19 of 19 pass |
| Owner smokes, run one by one | 13 of 16 pass on the first run. `owner_stale_endpoint` then passed after moving its workspace to `/tmp`. The `owner_generation_tokens` fix in `d506261` is not yet verified on Linux. `coordinator_owner_socket` failed once and passed once; the cause is unknown. |
| Workload matrix | Not run; the host is shared and has little free memory |

## Historical evidence

The sections below predate the single-engine change. Rows about the public String API, `owner_spawn`, `CleanupPolicy` or `ResourceAccounting` describe code that no longer exists.

### Full proof gate after the reactor and response-limit changes

Darwin 25.6.0 arm64, Bend 2.0.39, revision `d64feb0` plus the uncommitted
`UnusedDefs` law/witness pair, run inside `nix develop`.

| Check | Result |
| --- | --- |
| `nix develop -c ./proofs/run.sh` | `NAME PASS`; `SUMMARY PASS=97 FAIL=0 TIMEOUT=0 TOTAL=97` in 8 min 25 s |

Modules added since revision `b7ae44d`: `CleanupPolicy`,
`ConnectionPolicy`, `ConnectionStore`, `CursorPreviewPolicy`, `OptionsCodec`,
`OwnerOpenPolicy`, `RequestQueue`, `ResourceAccounting`, `ResourceOptions`,
`ResponseBoundPolicy`, `SnapshotValueLengthPolicy`, `TransportBudgetPolicy`,
`UnusedDefs` and `ValueLengthPolicy`. The owner smoke gate
(`bench/smoke/owner_gate.sh`, 20 smokes plus the transport oracle unit test)
also passes on `d64feb0`. This does not change the open items below.

The unused owner auto-spawn path (`OwnerSpawn`, `SpawnPolicy`, `src/effs/owner_spawn.*`
and the `owner_spawn*` fixtures) was removed afterwards. The `owner_spawn` rows in
the tables below describe code that no longer exists.

### Bend 2.0.39 compatibility rerun

Darwin arm64, Bend 2.0.39, and `bend-mathlib@0.7.5.0` pinned to
`0xcd4682caa53da19986acd472c2181473` in `tools/hub-dependencies.json`.
The checkout includes the updated comparison/equality bridge in `src/Keys.bend`
and the `DecodedText` constructor in `src/SstFile.bend`, avoiding the new Base
`Event.Text` constructor. No law or witness was removed or weakened.

| Check | Result |
| --- | --- |
| `bash proofs/run.sh` | `PASS=82 FAIL=0 TIMEOUT=0 TOTAL=82`; all modules checked with `--verdict`, including `ReplProof` |
| `bash scripts/check-bend.sh src/Keys.bend src/SstFile.bend` | Pass; changed-source lint and width checks |
| `bash bench/smoke/shared_utf8_bytes.sh` | `SHARED_UTF8_BYTES_PASSED` |
| `bash bench/smoke/durable_session.sh` | `DURABLE SESSION PASS`; native create, reopen, error and close paths |
| `bash bench/smoke/backup_restore.sh` | `BACKUP_RESTORE_PASSED` |
| `bench/smoke/sst_v3_io.bend`, executed from a temporary working directory | Packed SST write/read passes with multibyte UTF-8 values and a tombstone |

This rerun establishes the formal gate and these focused host checks for the
updated dependency and toolchain. It does not rerun the native CLI SDK checks,
Linux platform matrix or performance workloads recorded below. Their existing
limitations and outstanding release evidence remain applicable.

### Host and toolchain of the earlier runs

| Attribute | Observed value |
| --- | --- |
| Host | Darwin 25.6.0, arm64 |
| Bend | 2.0.37 |
| Linux runtime | Ubuntu 24.04 arm64 in Docker, Bend 2.0.36, Clang 18 |
| Linux filesystem | Container overlay for lock and permission tests; bind mount for compilation and socket/client integration |
| Bun | 1.4.3 on Darwin arm64 and Linux arm64 |

### Same-container durable API comparison

The same `durable_api_perf.sh` harness ran five times against baseline commit
`6d3300e` and five times against candidate commit `93ac5ed`. Both ran in the
same Ubuntu 24.04 arm64 Docker container on LinuxKit kernel `6.12.76`, with 12
vCPUs, Bend 2.0.36, Clang 18 `-O2`, the container overlay filesystem (1,007 GiB
reported, 903 GiB available), and the harness defaults with runtime threads
unmodified. Each measured run performs 1,000 synchronous overwrites of the same key, records peak RSS and
disk bytes, then measures reopen recovery. This is one small comparable
workload, not the required release matrix.

| Mode | Baseline median elapsed | 0.6 median elapsed | Change | Baseline median recovery | 0.6 median recovery | Baseline / 0.6 median RSS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Internal | 344 ms | 319 ms | 7.3% faster | 49 ms | 49 ms | 4,604 / 4,600 KiB |
| Public String API | 336 ms | 319 ms | 5.1% faster | 53 ms | 50 ms | 4,600 / 4,724 KiB |

Raw rows are in `mylsm-0.5.0.0-same-linux-performance.tsv` and
`mylsm-0.6.0.0-same-linux-performance.tsv`. Median elapsed time is within the
5% regression gate for this workload. The public API's median RSS is 124 KiB
higher; both versions write 64 KiB and pass recovery. This does not establish
the gate for binary API, batches, range scans, snapshots, backup/restore,
coordinated clients, or larger datasets.

The same baseline/candidate comparison also ran five `phase3_metrics.sh 20485`
workloads each, with two runtime threads and 101 point reads per run. The
baseline median elapsed is 7,573 ms and candidate median is 6,913 ms (8.7%
faster); recovery medians are 317 and 299 ms. Both have read p50/p95/p99 of
1/2/2 ms, and the median peak RSS is 40,710,144 / 40,861,696 B. Both write the
same 282,839-byte WAL, 76-byte manifest, and 453,174-byte table. All ten runs
pass first/middle/last validation before and after recovery. Raw baseline rows
are in `mylsm-0.5.0.0-phase3-linux-samples.tsv`; candidate rows are in
`mylsm-0.6.0.0-phase3-linux-samples.tsv`. These comparable workloads pass the
5% median regression gate, but the other release workloads remain unmeasured.

### Executed gates

| Gate | Command | Result |
| --- | --- | --- |
| Bend 2.0.37 upgrade, Darwin arm64 | `bend update`; `bash bench/smoke/cli.sh`; focused JS effects and Bun/Node consumer smokes | Pin and docs updated; formal proofs pass 82/82 and fuzz decides 1,000,000 inputs. CLI smoke reaches the native REPL but exits 1 because Clang cannot build SDK modules (CoreFoundation/Foundation/Metal) in this host environment; JS effects pass on Node and native Bend, Bun FFI and owner-spawn smokes pass, and public examples pass. `ReplProof` typechecks, while `--verdict` reports a backend/kernel mismatch; the 2.0.36 Docker image lacks Lean, so the mismatch could not be compared against the prior release. |
| Formal laws and witnesses | `bash proofs/run.sh` | `PASS=81 FAIL=0 TIMEOUT=0 TOTAL=81` |
| Bolt lint | `../bolt/bin/bolt.bin 2>&1 | grep -v ' S002: ' | grep -E 'error:|warning:'` | No findings printed; `grep` returns 1 when the result is empty |
| Source width | Repository commands, now in the [Bend standard](../../docs/standards/bend.md) | No lines over 200 columns |
| Patch whitespace | `git diff --check` | Pass |
| Incremental cursor memory | `bash bench/smoke/public_cursor_memory.sh` | Pass at both configured dataset sizes; results below |
| Linux incremental cursor memory | `MYLSM_THREADS=2 bash bench/smoke/public_cursor_memory.sh` | Fails the 32 MiB absolute limit at 64k: 48,197,632 B open and 46,514,176 B scanning; 16k is 24,023,040 B open and 22,609,920 B scanning |
| Linux incremental cursor memory, one thread | `MYLSM_THREADS=1 bash bench/smoke/public_cursor_memory.sh` | Fails at 64k: 47,624,192 B open and 47,640,576 B scanning; 16k is 24,047,616 B open and 22,687,744 B scanning |
| JavaScript host boundaries | `db_lock_js_unsupported.sh`, `rename_noreplace_js_unsupported.sh`, `owner_spawn_js.sh` | All pass under Node.js; this does not exercise Bun FFI |
| WAL commit recovery | `bash bench/crash/durable_commit.sh` | Pass |
| Owner response-loss matrix | `bash bench/crash/coordinator_commit_unknown.sh` outside the sandbox | Six crash boundaries pass; each recovery matches the expected absent/present commit state |
| Coordinated backup/restore | `bash bench/smoke/coordinator_owner_socket.sh` outside the sandbox | Pass; owner snapshot is streamed into a checksummed bundle, restored, binary bytes verified, owner stopped, and lock reacquired |
| Backup publication matrix | `bash bench/crash/backup_publish.sh` | Pass at pre-rename, post-rename, and post-parent-sync boundaries |
| Migration publication matrix | `bash bench/crash/migration_publish.sh` | Pass at bundle and destination publication boundaries; source checksums remain stable |
| Configured batch/resource limits | `bash bench/smoke/resource_limits.sh` | Pass; exact frame limits and unchanged persisted state on rejection |
| Paged SST index and migration validation | `byte_index_budget.sh`, `legacy_sst_io.sh` | Both pass; index budget/seek checks pass, and migration corruption/collision/resource-limit cases preserve source and destination state |
| Backup ordering and historical migration edges | `bash bench/smoke/backup_restore.sh`, `bash bench/smoke/legacy_sst_io.sh` | Pass on Darwin arm64; backup rejects duplicate/descending keys, migration preserves an empty legacy SST value, and a duplicate-key SST with valid checksums is rejected without source changes or destination/staging publication |
| Physical snapshot generation retention | `bash bench/smoke/coordinator_owner_snapshot_dispatch.sh` | Pass on Darwin and Linux; two snapshots retain the same SST through compaction, closing the first preserves it, and closing the final snapshot removes it while the published generation remains |
| Linux lock and owner lifecycle | `durable_lock.sh`, `coordinator_owner_socket.sh` | Pass on Ubuntu 24.04 arm64; lock test runs from container overlay as an unprivileged user, and the owner fixture verifies clients, backup/restore, shutdown, and lock reacquisition |
| Unix socket support and permissions | `unix_socket.sh`, `unix_socket_large_write.sh`, `unix_socket_permissions.sh` | Native socket/frame transport, 70 KiB writes, and permission rejection pass on Darwin/Linux; Bun returns typed `UnsupportedPlatform` on both |
| Linux crash publication | `durable_commit.sh`, `backup_publish.sh`, `migration_publish.sh`, `coordinator_commit_unknown.sh` | All pass as an unprivileged container user; the coordinator matrix covers six commit/response-loss boundaries |
| Linux resource and legacy SST gates | `resource_limits.sh`, `byte_index_budget.sh`, `legacy_sst_io.sh` | All pass on Ubuntu 24.04 arm64 |
| Linux repeated write/recovery/read workload | `phase3_metrics.sh 20485`, five runs | Passes correctness and recovery checks; raw results are in `mylsm-0.6.0.0-phase3-linux-samples.tsv` |
| Same-container 0.5/0.6 durable API comparison | `durable_api_perf.sh`, five runs per source tree | Pass; 1,000-overwrite median elapsed time is 344→319 ms internal and 336→319 ms public String; raw comparison samples above |
| Same-container 0.5/0.6 20,485-write comparison | `phase3_metrics.sh 20485`, five runs per source tree, two threads | Pass; elapsed median 7,573→6,913 ms, recovery 317→299 ms, read p50/p95/p99 1/2/2 ms, correctness samples pass; raw TSVs above |
| Write-limit cleanup | `migration_file_limit.sh`, `backup_file_limit.sh` | Pass on Darwin and Linux; these use `RLIMIT_FSIZE`, preserve source data, and remove known staging artifacts; they are not true ENOSPC |
| True Linux filesystem-full cleanup | `migration_enospc.sh`, `backup_enospc.sh` in Docker with a full 64 KiB tmpfs | Pass; migration preserves source checksums and publishes no destination/staging paths; backup publishes no bundle/staging path and releases the source lock |
| JavaScript Bun FFI | `bun bench/smoke/js_bun_ffi.js` | Pass on Darwin and Linux arm64; exercises real flock acquire/release and atomic no-replace rename success/collision behavior |
| JavaScript Bun owner process | `bun bench/smoke/owner_spawn_bun.js` | Pass on Darwin and Linux arm64; while the parent holds flock, the spawned child cannot inspect the lock descriptor |
| JavaScript Node fallback | `db_lock_js_unsupported.sh`, `rename_noreplace_js_unsupported.sh`, `owner_spawn_js.sh` | Pass under Node; unsupported FFI remains explicitly reported as ENOTSUP |
| Linux arm64 acceptance rerun | `proofs/run.sh`, legacy/backup/owner/lock/crash/ENOSPC harnesses, and Bun 1.4.3 FFI fixtures | Ubuntu 24.04 arm64 as an unprivileged user; proofs pass 82/82, migration/backup/owner/lock and publication/crash matrices pass, all six owner response-loss boundaries recover as expected, true tmpfs ENOSPC cleanup passes for migration and backup, and Bun lock/rename plus child descriptor checks pass. Cursor RSS is excluded from this rerun. |
| Public consumer examples | `examples/utf8_basic.bend`, `examples/bytes_basic.bend`, `examples/snapshot_scan.bend` | Historical Linux run: all pass on Ubuntu 24.04 arm64 with Bend 2.0.36; they import the public facade, with the byte example also importing the bytes buffer package. |

### Cursor memory observation

Single run on the Darwin/arm64 host with one runtime thread. The harness creates
each database, then measures process maximum RSS while opening or reading 64
records. These values are observations for this machine, not repeated-run claims.

| Records | Threads | Open max RSS | 64-item scan max RSS | SST bytes |
| ---: | ---: | ---: | ---: | ---: |
| 16,000 | 1 | 11,829,248 B | 12,009,472 B | 464,172 B |
| 64,000 | 1 | 30,900,224 B | 31,047,680 B | 1,856,272 B |

Both cases remain below the harness's 32 MiB process ceiling, and opening a
64-item cursor adds less than the allowed 4 MiB over open RSS. The dataset is
small relative to process RSS, so these samples establish the harness bounds,
not asymptotic memory behavior by themselves.

## Known limitations

- Writes are about ten times slower than the 0.5 String engine on the same
  machine (20.4 s against 1.9 s for 20,485 writes). Each put scans the
  list-based memtable and, for a key the memtable does not hold, looks it up in
  the SST to keep the visible statistics exact. Moving that bookkeeping out of
  the write path is planned for 0.6.1.0.
- There is no automatic flush and no levelled compaction. Without explicit
  flushes, write cost grows with the memtable size.
- Linux x86_64: `coordinator_owner_socket` failed once in two runs, the
  `owner_generation_tokens` fix is unverified, and the workload matrix and
  cursor memory gate have not run on the block-size fix. These move to 0.6.0.1.
- Linux-specific ENOSPC harnesses use a Docker-provided tmpfs and confirm the
  filesystem is full before running the operation. The API surfaces a typed
  operation failure; it does not expose the underlying `ENOSPC` errno in the
  fixture output.
- Timing results are single-host observations. The macOS matrix ran below the
  harness's free-disk threshold.

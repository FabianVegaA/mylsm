# MyLSM 0.6.0.0 acceptance evidence

Status: implementation evidence is partial. Formal laws, current-host and
Linux runtime gates, Bun FFI effects, and snapshot-generation reclamation pass.
Release acceptance is not complete: the repeated workload matrix and Linux
cursor memory ceiling remain open.

## Host and toolchain

| Attribute | Observed value |
| --- | --- |
| Host | Darwin 25.6.0, arm64 |
| Bend | 2.0.36 (`tools/toolchain.json`) |
| Linux runtime | Ubuntu 24.04 arm64 in Docker, Bend 2.0.36, Clang 18 |
| Linux filesystem | Container overlay for lock and permission tests; bind mount for compilation and socket/client integration |
| Bun | 1.4.3 on Darwin arm64 and Linux arm64 |

## Executed gates

| Gate | Command | Result |
| --- | --- | --- |
| Formal laws and witnesses | `bash proofs/run.sh` | `PASS=81 FAIL=0 TIMEOUT=0 TOTAL=81` |
| Bolt lint | `../bolt/bin/bolt.bin 2>&1 | grep -v ' S002: ' | grep -E 'error:|warning:'` | No findings printed; `grep` returns 1 when the result is empty |
| Source width | Repository command from `AGENT.md` | No lines over 200 columns |
| Patch whitespace | `git diff --check` | Pass |
| Incremental cursor memory | `bash bench/smoke/public_cursor_memory.sh` | Pass at both configured dataset sizes; results below |
| Linux incremental cursor memory | `MYLSM_THREADS=2 bash bench/smoke/public_cursor_memory.sh` | Fails the 32 MiB absolute limit at 64k: 48,197,632 B open and 46,514,176 B scanning; 16k is 24,023,040 B open and 22,609,920 B scanning |
| JavaScript host boundaries | `db_lock_js_unsupported.sh`, `rename_noreplace_js_unsupported.sh`, `owner_spawn_js.sh` | All pass under Node.js; this does not exercise Bun FFI |
| WAL commit recovery | `bash bench/crash/durable_commit.sh` | Pass |
| Owner response-loss matrix | `bash bench/crash/coordinator_commit_unknown.sh` outside the sandbox | Six crash boundaries pass; each recovery matches the expected absent/present commit state |
| Coordinated backup/restore | `bash bench/smoke/coordinator_owner_socket.sh` outside the sandbox | Pass; owner snapshot is streamed into a checksummed bundle, restored, binary bytes verified, owner stopped, and lock reacquired |
| Backup publication matrix | `bash bench/crash/backup_publish.sh` | Pass at pre-rename, post-rename, and post-parent-sync boundaries |
| Migration publication matrix | `bash bench/crash/migration_publish.sh` | Pass at bundle and destination publication boundaries; source checksums remain stable |
| Configured batch/resource limits | `bash bench/smoke/resource_limits.sh` | Pass; exact frame limits and unchanged persisted state on rejection |
| Paged SST index and migration validation | `byte_index_budget.sh`, `legacy_sst_io.sh` | Both pass; index budget/seek checks pass, and migration corruption/collision/resource-limit cases preserve source and destination state |
| Physical snapshot generation retention | `bash bench/smoke/coordinator_owner_snapshot_dispatch.sh` | Pass on Darwin and Linux; two snapshots retain the same SST through compaction, closing the first preserves it, and closing the final snapshot removes it while the published generation remains |
| Linux lock and owner lifecycle | `durable_lock.sh`, `coordinator_owner_socket.sh` | Pass on Ubuntu 24.04 arm64; lock test runs from container overlay as an unprivileged user, and the owner fixture verifies clients, backup/restore, shutdown, and lock reacquisition |
| Unix socket support and permissions | `unix_socket.sh`, `unix_socket_large_write.sh`, `unix_socket_permissions.sh` | Native socket/frame transport, 70 KiB writes, and permission rejection pass on Darwin/Linux; Bun returns typed `UnsupportedPlatform` on both |
| Linux crash publication | `durable_commit.sh`, `backup_publish.sh`, `migration_publish.sh`, `coordinator_commit_unknown.sh` | All pass as an unprivileged container user; the coordinator matrix covers six commit/response-loss boundaries |
| Linux resource and legacy SST gates | `resource_limits.sh`, `byte_index_budget.sh`, `legacy_sst_io.sh` | All pass on Ubuntu 24.04 arm64 |
| Linux repeated write/recovery/read workload | `phase3_metrics.sh 20485`, five runs | Passes correctness and recovery checks; raw results are in `mylsm-0.6.0.0-phase3-linux-samples.tsv` |
| Write-limit cleanup | `migration_file_limit.sh`, `backup_file_limit.sh` | Pass on Darwin and Linux; these use `RLIMIT_FSIZE`, preserve source data, and remove known staging artifacts; they are not true ENOSPC |
| True Linux filesystem-full cleanup | `migration_enospc.sh`, `backup_enospc.sh` in Docker with a full 64 KiB tmpfs | Pass; migration preserves source checksums and publishes no destination/staging paths; backup publishes no bundle/staging path and releases the source lock |
| JavaScript Bun FFI | `bun bench/smoke/js_bun_ffi.js` | Pass on Darwin and Linux arm64; exercises real flock acquire/release and atomic no-replace rename success/collision behavior |
| JavaScript Bun owner process | `bun bench/smoke/owner_spawn_bun.js` | Pass on Darwin and Linux arm64; while the parent holds flock, the spawned child cannot inspect the lock descriptor |
| JavaScript Node fallback | `db_lock_js_unsupported.sh`, `rename_noreplace_js_unsupported.sh`, `owner_spawn_js.sh` | Pass under Node; unsupported FFI remains explicitly reported as ENOTSUP |

## Cursor memory observation

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

## Outstanding release evidence

- Linux evidence currently covers Ubuntu 24.04 arm64 in Docker; other Linux
  architectures/distributions and JavaScript owner-process lifecycle remain
  unverified.
- At least five samples for binary and UTF-8 point reads/writes, batches,
  recovery, cold/warm scans, snapshots under compaction, backup/restore, and
  coordinated clients, including percentiles, throughput, RSS, disk usage, and
  configured buffer/queue peaks.
- The Linux cursor memory fixture exceeds its existing 32 MiB process ceiling
  at 64,000 records, even with two runtime threads. Scanning adds less than
  4 MiB over its open RSS, but the absolute process budget still fails.
- Linux-specific ENOSPC harnesses use a Docker-provided tmpfs and confirm the
  filesystem is full before running the operation. The API surfaces a typed
  operation failure; it does not currently expose the underlying `ENOSPC`
  errno in the fixture output.

No 0.6.0.0 performance baseline or release acceptance is claimed by this file.

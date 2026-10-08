# Durable API and Exclusive Ownership Implementation Plan

> Inline execution was selected by the user. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the first safe MyLSM increment: a public durable String key-value API with atomic batches, typed failures, and exclusive ownership of each database directory.

**Target Release:** `0.5.0.0` (user-directed).

**Architecture:** Keep the existing pure `Db.Db` and session facade intact. Add an opaque durable handle that owns a host lock and the recovered state; route all public effects through that handle. Acquire the lock before recovery or cleanup, validate a whole batch before append, separate WAL commit from post-commit maintenance, and release the lock only through close or process death. Bend owns all branching, validation, identity comparison, error mapping, and lifecycle policy; host effects expose only OS primitives.

**Tech Stack:** Bend 2, MyLSM's packed WAL and recovery modules, narrow C filesystem effects, native Bend executable fixtures, Bash crash and process harnesses.

**Spec:** `docs/superpowers/specs/2026-10-07-durable-embedded-api-design.md`, deliveries A–B and their applicable adoption and validation requirements.

## Global Constraints

- Implement A+B together; the public durable API is not advertised as safe until both pass.
- Release this increment as MyLSM `0.5.0.0`; update `pack.json`, canonical import snippets, and README release notes only after the facade passes its consumer fixture.
- Support local macOS and Linux with one owning process per database. Do not promise Windows or network filesystems.
- Preserve String keys and values and the current pure `open`, `Sess`, `sput`, `sdel`, `sbatch`, and `sget` behavior.
- Never interpret a missing or corrupt existing database as an empty database.
- Never overwrite or remove an existing user directory during creation.
- Lock before WAL repair, temporary-file sweep, Manifest load, or any other mutation; keep a stable lock inode for the handle lifetime.
- A successful batch is WAL-synced and atomic; a validation failure changes no data; a failure after append begins can return `CommitUnknown` and poisons the handle until close and recovery.
- Report maintenance failure separately from the already confirmed batch; block further writes if continuing is unsafe.
- Follow `AGENT.md`: refresh `bend guide`, update the latest Bend pin in `tools/toolchain.json` when required, use laws and matching witnesses for pure decisions, run the full proof and lint gates before commit, and never use `@unsafe`.
- Keep Bash/C/JS to irreducible process and filesystem operations. Interpret environment values, select paths, compare directory identities, and classify host results in Bend. Add laws and matching witnesses for these pure decisions where practical; host behavior receives empirical fixtures. If the selected OS lock does not exclude a second handle in the same process, the host is unsupported until that guarantee can be supplied without hidden policy in C/JS.
- Reuse `bend-kit-bytes` and `bend-kit-files` where their contracts match; keep SQLite as a documented alternative backend, since embedding it would replace the selected MyLSM LSM engine.
- Bend 2.0.36 changed C effect registration to `io_eff(CID(name), run)`, while the cached `bend-kit-files` 0.1.1.0 C effects still pass a third legacy argument. `src/effs/make_dir.c` normalizes both forms at compile time without changing the filesystem operations or external cache.
- Follow the user's global `AGENTS.md` preferences: do not put ticket IDs in source; write no new source comments or docstrings unless the user approves each one first. Leave existing comments alone.
- Preserve the existing untracked GPU evaluation plan and other unrelated workspace changes.

## Review Focus

- Existing empty directory: `open_existing` must return `NotFound` without creating WAL or Manifest; Task 3 pins this.
- Symlink or alternate spelling of an active directory: the second opener must return `Busy`; Task 2 pins this.
- Invalid later mutation in a batch: no earlier mutation may reach WAL or memory; Task 4 pins this.
- Crash after a durable WAL sync and before maintenance: reopening must retain the full batch; Task 5 pins this.
- Process killed while holding a lock: reopening must succeed without deleting or stealing the lock file; Task 2 pins this.

## File Structure

| File | Responsibility |
| --- | --- |
| `src/DurableError.bend` | Public error variants, operation/path/host cause, and pure classification of existing errors. |
| `src/DurableDb.bend` | Opaque durable handle, lifecycle, public operations, and poisoned/maintenance state. |
| `src/DurableStats.bend` | Public A+B counters and units without scanning database contents. |
| `src/DbLock.bend` | Lock path construction, error mapping, and release sequencing. |
| `src/DbLockPolicy.bend` | Pure OS error classification, isolated from foreign effects. |
| `src/effs/db_lock.c` | Take/release a nonblocking OS lock on a Base `File` handle and return that same handle with the raw result. |
| `src/effs/db_lock.js` | Matching raw primitives where possible; an unsupported primitive reports its host error to Bend. |
| `laws/DbLock.bend`, `proofs/DbLockProof.bend` | Pure host-error classification and lifecycle decisions and witnesses, importing only `DbLockPolicy`. |
| `laws/DurableDb.bend`, `proofs/DurableDbProof.bend` | Pure validation and commit-state decisions and witnesses. |
| `src/Fs.bend` | Delegate metadata, listing, directory creation, rename, removal, and packed file IO to `bend-kit-files`; retain local effects only for missing primitives such as `fsync`, truncation, permission changes, exact file-size accounting, and exclusive locks. |
| `src/Recover.bend` | Separate existing-open recovery from create and remove process termination on recoverable errors. |
| `src/DbIo.bend` | Pre-append validation and commit result independent of maintenance. |
| `mylsm.bend` | Public durable delegates alongside unchanged pure facade. |
| `laws/DurableError.bend`, `proofs/DurableErrorProof.bend` | Pure error and state-decision laws and witnesses. |
| `bench/smoke/durable_api.bend`, `bench/crash/durable_lock.sh`, `bench/crash/durable_commit.sh` | Consumer, cross-process, and crash fixtures. |
| `docs/DURABLE_API.md`, `README.md`, `pack.json` | Public lifecycle, migration, error, platform contract, and 0.5.0.0 package import. |

The first implementation task checks the Bend type and host-effect signatures against `bend guide`. If a stated signature does not compile, adapt the representation while preserving the behavior and the named public operations; record the concrete signature in this plan before dependent tasks proceed.

---

### Task 1: Fix the public types and baseline

**Files:** Create `src/DurableError.bend`, `laws/DurableError.bend`, `proofs/DurableErrorProof.bend`; modify `tools/toolchain.json` only if `bend update` changes the installed release.

**Interfaces:** Produce `DurableError.Error` with `NotFound`, `AlreadyExists`, `Busy`, `InvalidArgument`, `UnsupportedFormat`, `Corruption`, `ResourceLimit`, `Io`, and `CommitUnknown`, each retaining operation and relevant path, with host code/message for IO-derived failures. Produce `DurableError.classify_open` and `DurableError.classify_write` as pure decisions used by the facade.

- [x] Read `AGENT.md`, run `bend guide`, `bend update`, and `bend version`; record Bend 2.0.36 in `tools/toolchain.json`. Capture `git status --short` and baseline proof results before edits.
- [x] Add closed laws and witnesses for missing path, lock contention, unknown format, corrupt data, and pre/post-append IO classification.
- [x] Run `bend proofs/DurableErrorProof.bend`; the initial check failed with `src/DurableError.bend` absent.
- [x] Add the error type and pure classifiers. Keep the host errno and operation/path as fields, so callers never parse error text. Distinguish `CommitUnknown` only after the append boundary has been entered.
- [x] Run targeted error and lifecycle proofs and `./proofs/run.sh`; latest result: `PASS=28 FAIL=0 TIMEOUT=0 TOTAL=28` on Darwin/arm64 and Linux/aarch64.
- [x] Run Bolt's filtered zero-finding gate after adding concise S001 documentation; S003, U001, U004, U005, and other unfiltered findings are clean.

### Task 2: Acquire and retain the database lock

**Files:** Create `src/DbLock.bend`, `src/DbLockPolicy.bend`, `src/effs/db_lock.c`, `src/effs/db_lock.js`, `laws/DbLock.bend`, `proofs/DbLockProof.bend`, and `bench/crash/durable_lock.sh`; modify `src/Fs.bend` only for the needed host bridge.

**Interfaces:** Produce an affine `DbLock.Lock` wrapper around a Base `File` with `DbLock.acquire(path) -> IO(Result<Error, Lock>)` and `DbLock.release(lock) -> IO(Result<Error, Unit>)`. Acquisition is nonblocking. Bend constructs `path ++ "/LOCK"`, opens it in append mode without truncation, and passes the File handle to the raw lock effect. The effect returns the same Base handle with success or errno; `DbLockPolicy.classify_lock_error` maps errno to `Busy`, `NotFound`, or `Io`. Aliases reach the same stable lock inode, and the OS primitive must pass the same-process duplicate-open fixture. Do not introduce a custom runtime handle type.

- [x] Build a two-process fixture that holds the first lock while a second process opens the same directory; assert `Busy` and byte-for-byte unchanged payload data. Repeat through a symlink, `..` spelling, and two opens in one process. Add kill-and-reopen and close-and-reopen cases.
- [x] Add pure law/witness cases for Linux `EAGAIN`, Darwin `EWOULDBLOCK`, missing path, and unsupported lock errors.
- [x] Implement Bend lock ownership and error mapping with minimal nonblocking `flock`/unlock C effects. The effect returns the same Base `File` handle and raw result.
- [x] Provide JS effects that preserve the handle and report unsupported locking. Native lock behavior is verified on Darwin and Linux through the C effects; JS lock execution remains explicitly unsupported and reports that limitation.
- [x] Run `bench/crash/durable_lock.sh`; result: `DURABLE LOCK PASS` on Darwin/arm64. `./proofs/run.sh` passes all 26 modules.
- [x] Verify Linux same-process and cross-process lock behavior. The lock file remains on disk after normal close and kill; its existence alone never means `Busy`.
- [x] Run Bolt's filtered zero-finding gate after adding concise S001 documentation.

### Task 3: Separate create from existing-open recovery

**Files:** Modify `src/Recover.bend`, `src/Flush.bend`, `src/Fs.bend`; create the open/create cases in `bench/smoke/durable_api.bend`.

**Interfaces:** Produce internal `Recover.open_existing_locked(dir)` and `Recover.create_locked(dir)` returning the recovered or new `Db.Db` while the caller retains `DbLock.Lock`. Neither function acquires a second lock. `create_locked` reserves a new directory exclusively; `open_existing_locked` never invokes `Flush.ensure_dir`.

- [x] Add smoke coverage for missing Manifest without mutation, successful create/open, and create on an existing destination returning `AlreadyExists`.
- [x] Add public fixtures for the valid 0.4.0.0 Manifest v3 vector, corrupt Manifest, and unsupported version. `bench/smoke/durable_open_errors.sh` verifies rejected Manifest and orphan-temp bytes remain unchanged and creates neither LOCK nor WAL.
- [x] Make `SstStreamIo.read_table` return file-size/open failures as `Result`, tag SST codec corruption for typed public classification, and propagate the result through `Recover.load_tables`, `load_levels`, and `open_levels`. A public fixture seeds an SST, corrupts it, and confirms `open_existing` returns `Corruption`.
- [x] Bound Manifest recovery to the four implemented levels in pure Bend policy and classify excess levels as corruption; add matching laws and witnesses.
- [x] Propagate malformed WAL header/frame results out of `open_levels_checked` and classify malformed WAL as public `Corruption`; the public open-error fixture covers a malformed header.
- [x] Propagate WAL initialization, size, open, and tail-repair filesystem results through the existing-open recovery path. A public fixture confirms an unreadable WAL path returns `Io` rather than terminating the process.
- [x] Add `Recover.open_existing_locked` and `Recover.create_locked`; public smokes confirm missing Manifest is not initialized and invalid Manifest is rejected before mutation.
- [x] Use checked `read_dir_count`/`read_dir_at` Results and strict temporary-file removal for durable create/open, propagating sweep errors. A public fixture confirms failed `.tmp` removal returns `Io` without changing Manifest or temp-directory contents; missing or non-directory optional levels have no sweep entries, while Manifest-referenced table reads remain checked. The legacy pure opener retains its former best-effort sweep.
- [x] Propagate Manifest and SST open/read/parse failures and WAL initialize/open/size/repair failures through existing-open recovery as `Result`; classify corrupt Manifest/WAL/SST data and verify the public behavior with unchanged-directory and open-error fixtures.
- [x] Propagate table/Manifest write, fsync, rename, directory fsync, WAL initialization, and automatic flush/maintenance failures through the durable maintenance result; committed values remain readable and subsequent writes are blocked after maintenance failure.
- [x] Propagate compaction L1 creation, SST write, rename, directory fsync, Manifest read/write/rename/fsync, and post-publication removal failures as `Result`. Keep crash checkpoints as the only `IO.try` calls in the compaction chain, and preserve `CompactIo.remove_list` best-effort semantics for legacy orphan sweeping.
- [x] Confirm creation reserves the destination with POSIX `mkdir(0700)`, an atomic exclusive operation; `EEXIST` maps to public `AlreadyExists`, and the existing public consumer verifies duplicate create. No check-then-create path is used.
- [x] Run the consumer fixture, targeted recovery proofs, and full proofs; the consumer, `./proofs/run.sh`, and `./bin/mylsm check` pass on Darwin/arm64.
- [x] Correct S003 headers, remove unused parameters, resolve U004, and document all S001 declarations concisely.

### Task 4: Validate and commit one atomic batch

**Files:** Modify `src/DbIo.bend`, `src/Wal.bend`, `src/Recover.bend`; create `src/DurableDb.bend`, `laws/DurableDb.bend`, `proofs/DurableDbProof.bend`, and extend `bench/smoke/durable_api.bend`.

**Interfaces:** Produce `DurableDb.write_batch(handle, Wal.Batch) -> IO(Result<DurableError.Error, DurableDb.WriteOutcome>)`, with the returned outcome carrying the updated handle and a separately reported maintenance status. `put` and `delete` delegate to one-mutation batches. Use a nonduplicable handle representation so each operation consumes and returns ownership explicitly.

- [x] Public consumer smoke verifies a repeated-key batch resolves to the final value after close/reopen. Existing policy laws cover pre/post-append state and poisoned-handle rejection.
- [x] Add a public compaction filesystem-error fixture: five L0 tables, blocked L1 creation, public `Io`, close/reopen, and value recovery. `DURABLE COMPACTION ERRORS PASS` on Darwin/arm64.
- [x] Reject an invalid final mutation that pushes a multi-mutation frame beyond its block cap; the public fixture checks `ResourceLimit`, unchanged WAL bytes, and invisible earlier mutation.
- [x] Add quantified laws showing encoding rejection, append rejection, and uncertain append preserve the prior database state for every database and mutation list.
- [x] Check individual key/value boundaries with UTF-8 preflight laws and synthetic WAL encoded-length rejection laws; the public fixture rejects an oversized multi-mutation frame before WAL mutation. No 1 GiB string is allocated. Public close/reopen and crash fixtures verify whole-batch visibility; pure `Db` laws cover batch/sequential equivalence and atomic application.
- [x] Add quantified laws for the actual pure commit transition: encoding rejection, append rejection, and uncertain append preserve every input database for every mutation list. `DurableCommit.apply` is shared by the witnesses and durable IO path. Host persistence remains an empirical claim.
- [x] Check closed ASCII and multibyte UTF-8 preflight boundary fixtures at and above the configured record cap, using synthetic accumulated lengths without allocating 1 GiB strings.
- [x] Encode the complete batch with Wal.encode_frame before opening the WAL; oversized or invalid frames are rejected before append. Keep the encoded frame through write and preserve append → fsync → memory ordering.
- [x] Add an explicit 256-mutation application batch-count cap and public tests for empty and 257-mutation batches. The storage codec still owns key/value/frame byte caps; they are documented and enforced during pre-append encoding.
- [x] Distinguish WAL-open rejection from write/fsync failure after append begins. The former leaves the handle Open; the latter returns CommitUnknown and poisons it. Checkpoints exist for wal.before_append, wal.appended, and wal.synced.
- [x] Add the public consumer `bench/crash/durable_commit.bend` and `bench/crash/durable_commit.sh`; `DURABLE COMMIT PASS` verifies before-append, after-append (old or full batch), after-fsync, and during-flush recovery without partial visibility on Darwin/arm64.
- [x] Return WriteOutcome with MaintenanceComplete or MaintenancePending separately from the confirmed commit; a pending status keeps the handle readable and blocks later writes.
- [x] Add a failing explicit-flush fixture: SST creation fails on a read-only L0 directory; the committed value remains readable, later writes are rejected, and close releases ownership. `DURABLE COMMIT PASS` on Darwin/arm64.

### Task 5: Publish the owned durable facade

**Files:** Modify `mylsm.bend`; complete `src/DurableDb.bend` and `bench/smoke/durable_api.bend`; create `src/DurableStats.bend` and `docs/DURABLE_API.md`; update `README.md`.

**Interfaces:** Expose `create`, `open_existing`, `get`, `write_batch`, `put`, `delete`, `flush`, `compact`, `stats`, and `close` as durable operations. `create` and `open_existing` return the opaque handle only after lock acquisition and successful initialization/recovery. `get` returns value or absence separately from errors. `stats` returns active bytes, WAL bytes, memtable/cache use, maintenance state, and process error counts in documented units without scanning data files; retained bytes and snapshot/cursor counts are added by C–D. `close` releases the lock and resources; prior confirmed commits do not depend on close.

- [x] Add an external consumer fixture importing only `mylsm.bend`: create, repeated-key batch, get, stats, flush, compact, close, reopen, delete, and confirm absence after another reopen. Stats leaves the logical value readable. The fixture builds and passes without a compiler wrapper.
- [x] Public-API smoke verifies `Busy` while the owner is live, reopens after close, and confirms a positive WAL byte count without changing the value. The count is exposed and documented in bytes.
- [x] Complete the planned stats contract for A+B: active bytes, WAL bytes, active/frozen entry count, UTF-8 payload bytes, read-cache entries (bounded at 256), per-handle operation errors, and maintenance state. Active bytes match an independent file-size oracle; payload-byte laws cover multibyte data and tombstones; the public fixture checks 14 bytes and three rejected operations. Payload bytes exclude runtime and allocator overhead.
- [x] Route durable calls through opaque public `Handle`, `Error`, `DurableStats`, and `Mutation` types in `mylsm.bend`; preserve pure API names and semantics.
- [x] Add `bench/smoke/durable_poisoned_close.sh`. It stops at `wal.appended`, removes the WAL pathname so the following fsync returns `ENOENT`, verifies the public result is `CommitUnknown`, closes the poisoned handle, restores the original WAL, and reopens the confirmed value.
- [x] Add `docs/DURABLE_API.md` and README migration guidance for ownership, current errors, durability, stats, host limits, and the existing pure API.
- [x] Document current codec key/value/frame caps and the 1–256 durable batch-count cap, plus the current error/status contract and supported-host evidence (Darwin and Linux C lock paths tested; JS locking remains unsupported).
- [x] Run the public consumer fixture (including empty and 257-mutation rejection), commit-crash matrix, lock fixture, `./proofs/run.sh` (`PASS=28 FAIL=0 TIMEOUT=0`), `./bin/mylsm check`, and `bench/smoke/cli.sh`; all local checks pass.
- [x] Preserve legacy pure `open_db` behavior by ensuring its directory before manifest loading; `bench/smoke/cli.sh` initially reproduced the regression and passes after restoration.
- [x] Run Bolt lint and compile the public consumer directly with Bend 2.0.36. The local registration shim makes the cached `bend-kit-files` C effects compatible without patching the external cache.

### Task 6: Final A+B acceptance and performance comparison

**Files:** Extend `bench/crash/durable_commit.sh`; add an A+B results document under `bench/results/`; update `docs/DURABLE_API.md` only for measured limits or supported-host facts.

**Interfaces:** The acceptance harness uses the public durable API; no internal module access is allowed for consumer expectations. The existing fault-injection harness remains the crash mechanism.

- [x] Run two-process lock tests across aliases, same-process duplicate opens, owner kill, close/reopen, and unchanged payload; `DURABLE LOCK PASS` on Darwin/arm64.
- [x] Repeat on Linux and through public durable API calls. In an Ubuntu 24.04 aarch64 Docker VM on Apple Silicon with native Bend 2.0.36 and Clang 18, proofs/checks pass and lock, crash, recovery, compaction, poisoned-close, stats-oracle, CLI, and public-consumer fixtures pass as an unprivileged user on container-local overlay storage. The bind-mounted workspace was not used for lock semantics because its shared filesystem did not reproduce native Linux `flock` behavior.
- [x] Run crash cases before append, after append, after fsync, and during flush maintenance. Verify confirmed batches survive and no batch becomes partially visible. For the unknown post-append case, reopen and inspect before any application retry; `DURABLE COMMIT PASS` on Darwin/arm64.
- [x] Measure baseline and candidate operations with equal hardware, disk, toolchain, data, configuration, and sync guarantees. Twenty 1,000-put runs compare internal `Recover.write` (one WAL `fsync` per mutation) against public `MyLSM.put`, with the same seed and lock and `clang -O2`. Raw samples are in `bench/results/durable-api-0.5.0.0-performance-samples.tsv`; median latency is 337 us internal versus 339 us public, median throughput is 2,967 versus 2,949 ops/s, recovery is 51 ms in both, disk use is 64 KiB in both, and median/max observed RSS is 4,600/4,608 KiB internal versus 4,588/4,604 KiB public. The gate passes for this overwrite workload in the tested Ubuntu 24.04 aarch64 Docker VM.
- [x] Run Bolt's filtered zero-finding gate: no errors or warnings remain after filtering S002; the 200-character width gate passes.
- [x] Run final gates: `./proofs/run.sh`, `./bin/mylsm check`, public consumer smoke, lock fixture, crash matrix, poisoned-close fixture, compaction-error fixture, open/recovery-sweep error fixture, exact active-byte oracle, performance comparison, and CLI smoke. Runtime results are recorded in `bench/results/durable-api-0.5.0.0-acceptance.md`.

## Later increments

C gets its own plan for incremental SST readers, bounded cursors, and resource budgets. D gets its own plan for immutable snapshot roots and retained file versions. E gets its own plan for logical backup, verified restore, format inspection, and migration from 0.4.0.0. F–G remain later proposals; H and specialized libraries require separate specs. No task in this plan claims those capabilities.

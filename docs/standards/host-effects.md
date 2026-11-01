# Host effects boundary

## Responsibility

Keep Bash, C, and JavaScript limited to the irreducible host operation. Policy decisions,
environment interpretation, validation, and data transformation belong in Bend,
with laws and witnesses for pure decisions when practical.

Effects are in [src/effs](../../src/effs/); Bend adapters, such as
[Fs.bend](../../src/Fs.bend), [DbLock.bend](../../src/DbLock.bend), and
[UnixSocketIo.bend](../../src/coordinator/UnixSocketIo.bend), translate their results.
[scripts/mylsm.sh](../../scripts/mylsm.sh) delegates the CLI to Bend.

## Contracts to preserve

- Return host errors for Bend to classify, without turning an unsupported
  operation into apparent success.
- Preserve ownership of files and resources when returning results or errors.
- Respect partial reads and writes. A write error does not roll back bytes
  the host has already received.
- Maintain the order of append, sync, rename, and parent-directory sync established
  by the Bend layer. File utilities do not replace that durability protocol.
- Use real process exclusion. The existence of `LOCK` alone does not constitute a lock.

The `bend-kit-files` contract, its IO limits, and nominal byte versions
are recorded in [hub-dependencies.json](../../tools/hub-dependencies.json).

## Platforms

The native path implements filesystem, locking, and Unix socket effects. The JavaScript
lock effect uses `flock` through Bun FFI; runtimes without that primitive return
a capability error. The current JavaScript effects do not support the owner's
Unix sockets.

Do not infer full platform support from a single passing primitive.
The [acceptance report](../../bench/results/mylsm-0.6.0.0-acceptance.md) defines the scope of
recorded runs on Darwin arm64 and Ubuntu arm64 in Docker.

## Checking changes

Use the targeted fixtures in [bench/smoke](../../bench/smoke/) and the matrices in
[bench/crash](../../bench/crash/). For example:

```sh
bash bench/smoke/db_lock_js_unsupported.sh
bash bench/smoke/rename_noreplace_js_unsupported.sh
bun bench/smoke/js_bun_ffi.js
bash bench/crash/durable_commit.sh
```

Platform fixtures must run where the exercised primitive is available.
An `UnsupportedPlatform` case checks explicit rejection, not execution of that capability.
The laws in [FsPolicy](../../laws/FsPolicy.bend), [DbLock](../../laws/DbLock.bend), and
[UnixSocketPolicy](../../laws/UnixSocketPolicy.bend) cover pure decisions; they do not prove
the operating system implementations.

# Durable API

## Purpose and public entry point

[mylsm.bend](../../mylsm.bend) exposes `MyLSM.Bytes` and `MyLSM.Utf8` over the same
durable byte engine. Import the facade from this checkout to use these capabilities;
[pack.json](../../pack.json) retains an import of package `0.5.0.0`.

`Bytes` accepts `bend-kit-bytes.Bytes` buffers. `Utf8` accepts `String`, encodes UTF-8,
and returns `InvalidUtf8` when reading bytes that do not represent valid text. It neither
replaces nor discards bytes. Both views share the [binary order](storage-format.md).

## Operations

| Operation | Contract |
| --- | --- |
| `create(path)` | Reserve a new database and acquire ownership |
| `open_existing(path)` | Recover an existing database; do not create a missing one |
| `open_existing_wait(path, timeout_ms, backoff_ms)` | Wait for the lock with a bounded timeout |
| `create_with_options(path, options)` | Create locally with defaults or validate options against the remote owner |
| `open_existing_with_options(path, options)` | Open only if valid options match the remote owner |
| `put(handle, key, value)` / `delete(handle, key)` | Commit a durable mutation |
| `write_batch(handle, mutations)` | Commit an atomic batch |
| `get(handle, key)` | Return the value or absence |
| `stats(handle)` | Query visible totals and owner-managed resources |
| `flush(handle)` / `compact(handle)` | Publish the state or compact the current byte table |
| `close(handle)` | Consume the handle and release its ownership resources |

Each operation that preserves the handle returns it alongside the typed result. Pass
that handle to the next operation. A handle can be local or represent a client of the
[coordinated owner](coordination.md).

The options variants exist in both `Bytes` and `Utf8`. A remote mismatch returns
`InvalidArgument` before operating on the database; an unsupported local option is also
rejected. The remote path obtains the effective configuration through the coordination
handshake. The owner in this revision publishes defaults; custom local options are not
yet configurable.

`open_existing` requires a valid manifest. Waiting for the lock does not create the
database: the maximum timeout is 60,000 ms and valid backoff is between 1 and 1,000 ms.
A missing path, a busy database, and an expired deadline are distinct results.

The [executable examples](../../examples/README.md) demonstrate text writes, non-UTF-8
bytes, and stable snapshot traversal using the public facade.

## Writes and recovery

The engine validates and encodes the batch before accessing the WAL. It then appends,
syncs, and updates in-memory state. A successful acknowledgment means the mutation
passed through the durability protocol. A subsequent maintenance failure must not be
interpreted as rolling back an already acknowledged write.

Rejection before append leaves the write unapplied. An error after append begins or
a sync failure may produce `CommitUnknown` and poison the handle for further writes.
Close, reopen, and query the state before deciding whether to retry. A remote response
lost after dispatch can also leave the outcome uncertain: the client does not
automatically retry a dispatched mutation.

Batches accept 1 to 256 mutations. An empty batch produces `InvalidArgument`, and
exceeding the allowed count or size produces `ResourceLimit`. Keys are capped at
1 GiB; single-mutation frames are bounded to 1 GiB + 36 bytes and multi-mutation frames
to 1 MiB. These are implementation constants, not per-database options.

The byte engine recovers the manifest and published SST, validates blocks, and replays
the WAL into the active delta. After a successful flush, it releases published entries
from the MemTable; it retains database totals to query the SST without keeping another
complete copy. Current byte compaction processes a single table and removes tombstones;
multilevel compaction for this engine remains pending.

Each flush or compaction publishes a new SST and leaves the previous one on disk while
the handle remains open. When the database opens successfully (lock acquired, published
SST validated, and WAL replayed), `SST.*` files not referenced by the manifest are deleted,
including temporary files from an interrupted write. If opening fails, nothing is
deleted; directories and other files are untouched. Cleanup is best effort: a deletion
failure does not prevent opening.

## Readers and transfer

- [Scans and snapshots](scans-and-snapshots.md): `[lower, upper)` bounds, prefixes,
  owned cursors, and differences between local and owner snapshots.
- [Backup and migration](backup-and-migration.md): consistent export, publication
  without replacement, validated restore, and migration from historical storage.
- [Format](storage-format.md): manifest generations, encodings, and comparison.

`inspect(path)` requires an existing `LOCK` file, acquires exclusive access, and validates
the bounded manifest without creating or repairing the database. It does not check WAL
or SST contents; the reported identity has the limitation described in the format document.

## Statistics and known limits

`Bytes.Stats` contains five totals: visible entries, visible payload bytes, owner
snapshots, bytes retained by those snapshots, and owner cursors. Local handles report
zero for the three owner-managed resources. Payload excludes runtime or allocator
overhead and is not equivalent to RSS.

Metrics for disk, buffers, queues, connections, operation failures, and persisted
generations remain pending for this facade. Release 0.6.0.0 is accepted on macOS arm64;
Linux x86_64 is partially verified. See the
[evidence report](../../bench/results/mylsm-0.6.0.0-acceptance.md) for recorded runs
and remaining work assigned to 0.6.0.1.

## Single engine

In 0.6.0.0, the facade exposes only `Bytes` and `Utf8`, both over the byte engine. The
0.5 text API (`create`, `open_existing`, `put`, `get`, `Session`, `run_session`,
`create_database`, `open_database`, `InMemory.Session`, and `open_recovering`) and its
leveled engine have been removed. `Utf8.put`, `Utf8.delete`, and `Utf8.write_batch` return
`Unit`. A database in the 0.5 format is migrated with `migrate_legacy`; `inspect` still
recognizes it.

## Implementation and checks

- Byte engine: [ByteDurableDb.bend](../../src/ByteDurableDb.bend),
  [ByteWalIo.bend](../../src/ByteWalIo.bend), and [ByteSstIo.bend](../../src/ByteSstIo.bend).
- Pure contracts: [DurableBatchPolicy.bend](../../laws/DurableBatchPolicy.bend),
  [ByteRecoveryPolicy.bend](../../laws/ByteRecoveryPolicy.bend), and
  [OwnerOpenPolicy.bend](../../laws/OwnerOpenPolicy.bend), with witnesses in [proofs](../../proofs/).
- Consumers: [shared_utf8_bytes.sh](../../bench/smoke/shared_utf8_bytes.sh),
  [public_bytes_sst.sh](../../bench/smoke/public_bytes_sst.sh),
  [resource_limits.sh](../../bench/smoke/resource_limits.sh),
  [durable_poisoned_close.sh](../../bench/smoke/durable_poisoned_close.sh), and
  [durable_open_wait.sh](../../bench/smoke/durable_open_wait.sh).
- Crash recovery: [durable_commit.sh](../../bench/crash/durable_commit.sh).

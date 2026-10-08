# Durable API

The durable API in MyLSM 0.5.0.0 adds exclusive process ownership around the existing LSM
engine. It keeps String keys and values and uses the current WAL, MemTable, SSTable, Manifest,
recovery, flush, and compaction code.

| Operation | Contract |
| --- | --- |
| `create(path)` | Reserve a new directory and return an owned handle. |
| `open_existing(path)` | Recover an existing database without creating a missing one. |
| `put(handle, key, value)` | Commit a one-mutation write batch. |
| `delete(handle, key)` | Commit a tombstone for the key. |
| `write_batch(handle, mutations)` | Apply `SetValue` and `DeleteKey` mutations atomically. |
| `get(handle, key)` | Return the current value or absence. |
| `stats(handle)` | Return active bytes, WAL bytes, in-memory entry count, read-cache entries, and maintenance state. |
| `flush(handle)` / `compact(handle)` | Run the selected maintenance operation. |
| `close(handle)` | Release ownership and consume the handle. |
| `create_database(path, session)` / `open_database(path, session)` | Open or create a database, run a durable session, then release ownership. |

Each explicit-handle operation that keeps a handle returns it beside its result. Thread the returned handle into
the next operation. Runnable consumer coverage is in `bench/smoke/durable_api.bend`. `close` consumes the handle and releases its OS lock. The lock file is
stable and remains on disk; its presence does not mean another process owns the database.

`Session` composes these operations in `do` notation without exposing handle
threading. `Session.put`, `Session.delete`, and `Session.write_batch` return a
`WriteOutcome` so callers can observe post-commit maintenance status. A session
stops at its first operation error, then its scoped runner closes the handle.
Open and create errors use `SessionError.OpenFailure`; operation and close
errors use `OperationFailure`, `CloseFailure`, or `OperationAndCloseFailure`.
If both an operation and close fail, `SessionError.OperationAndCloseFailure`
preserves both errors. A successful write remains committed if a later session
step fails; a session is not a transaction. Use `run_session(handle, program)`
to run on a long-lived handle; it returns the handle with the result so ownership
can be retained across several programs and explicitly closed later.
Runnable consumer coverage is in `bench/smoke/durable_session.bend`.

`create` reserves a new directory and initializes its Manifest while holding the lock.
`open_existing` requires a Manifest before recovery and returns `NotFound` for an empty
directory. Both operations retain the lock until `close` or process exit. A second opener
receives `Busy` while an owner holds the lock.

`put`, `delete`, and `write_batch` accept batches containing 1–256 mutations. Empty batches
return `InvalidArgument`; batches over 256 mutations return `ResourceLimit` before WAL access.
The existing WAL codec limits each encoded record to 1 GiB, including its key/value length
fields. Multi-mutation frames are limited to 1 MiB; a single-mutation frame is bounded by the
codec's record limit plus 36 bytes of frame overhead. The complete batch is encoded before opening the WAL, then appended,
synced, and applied to memory. A failure to open the WAL is a rejected write before
append. A write or sync failure after append starts returns `CommitUnknown` and poisons the
handle; close and reopen before retrying. A successful commit returns `WriteOutcome` with
`MaintenanceComplete` or `MaintenancePending`. A pending maintenance error does not revoke the
commit, leaves the handle blocked for further writes, and still permits reads and close.

`stats` reports `active_bytes` as the Manifest plus the byte sizes of the SSTables named by that
Manifest, `wal_bytes` in bytes, `memtable_entries` as an entry count across active and frozen
memory tables, `memtable_payload_bytes` as the UTF-8 byte count of resident keys and values
(tombstones contribute their key only), `cache_entries` as the number of resident read-cache
entries (maximum 256), and `operation_errors` as the number of failed operations observed by
this handle since it was opened. A pending maintenance error counts even though the confirmed
write outcome remains successful. Reopening starts the count at zero; errors before a handle is
returned and errors from consuming `close` are outside this per-handle counter. Payload bytes
exclude runtime, collection, allocator, and cache overhead, so they are not an RSS estimate.
Active bytes use metadata reads for published files and exclude orphan SSTables and temporary
files; this costs one file-size query per published SSTable and reads no SSTable contents. The
cache count and operation counter come from the in-memory handle state.

The native lock primitive has been exercised on macOS and Linux. JavaScript locking is
unsupported and returns a typed error. The filesystem adapter keeps the useful `bend-kit-files`
operations and normalizes its cached C registration ABI locally for Bend 2.0.36.

The pure in-memory API is available under `InMemory.Session` and does not persist
data. `open_recovering` remains available for callers that manage ownership themselves.

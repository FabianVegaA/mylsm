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
receives `Busy` while an owner holds the lock. The 0.6 API adds
`open_existing_wait(path, timeout_ms, backoff_ms)`: it checks the existing Manifest first,
then retries only the nonblocking lock operation. Timeouts are capped at 60,000 ms and
backoff must be from 1 to 1,000 ms. A deadline returns `TimeoutError`, distinct from
immediate `BusyError`; clock or sleep failures return `IoError`. Runtimes without the
required OS lock primitive return `UnsupportedPlatform`; they do not fall back to a
lock-file convention with weaker crash guarantees.

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

The native and Bun JavaScript runtimes call the same nonblocking `flock(2)` operation on the
open LOCK descriptor. The JavaScript effect uses Bun FFI and returns raw OS errors for Bend
to classify. Unsupported runtimes return a typed host error rather than weakening process
exclusion. Cross-runtime release validation remains part of the 0.6 acceptance gate.

The pure in-memory API is available under `InMemory.Session` and does not persist
data. `open_recovering` remains available for callers that manage ownership themselves.

## 0.6 API work in progress

The current branch exposes distinct `Utf8` and `Bytes` namespaces over the same
generation-five manifest format over the generation-four byte record codecs. `Utf8` strictly encodes String keys and values as UTF-8;
`Bytes` uses `bend-kit-bytes.Bytes` and preserves arbitrary byte sequences. Reading
invalid stored UTF-8 through `Utf8.get` returns `InvalidUtf8` and preserves the handle.
The byte facade exposes IO-based `scan`, `scan_range`, and `scan_prefix`. They capture
the current delta and open the published SST as a block cursor; `scan_next` reads
incrementally and returns an item, filtered skip, terminal end, or typed failure.
After a successful flush, the durable handle drops the published entries from its
MemTable and retains their visible totals as base stats, so subsequent lookups and
scans use the SST instead of holding a duplicate full table in memory.
`scan_seek(cursor, lower)` advances the inclusive lower bound and `scan_close` releases
the SST reader, returning a typed result. When the handle is a coordinated owner client,
`scan`, `scan_range`, and `scan_prefix` create a retained owner snapshot and remote
incremental cursor. Reaching `End` closes both resources; explicit `scan_close` releases
an early cursor and its private snapshot. A stream failure returns its cursor so callers
can close both resources. Cursors created from an explicit snapshot leave that parent
snapshot open for the caller. The generation-five SST index stores block
separators, so a validated cursor can route directly to the selected block. Range bounds are lower-inclusive and
upper-exclusive; prefix bounds compare exact bytes. The UTF-8 facade provides matching
operations over String bounds and shares the byte ordering. Its cursor enters terminal
failure if a stored key or value cannot be decoded, and close reports reader errors.
Top-level `inspect(path)` canonicalizes the database path, requires its existing
`LOCK` file, acquires the process lock, and reads the bounded `MANIFEST` without
repairing or creating database files. It reports package/storage identity and
manifest integrity; it does not yet validate WAL or SST contents.
Both facades also expose IO-based `snapshot`, snapshot `get`/range/prefix scans, and
`close`. Local direct handles preflight estimated retained bytes, read the published SST
when present, overlay the active delta, and retain a canonical visible-entry copy up to
64 MiB. Owner-backed snapshots retain a block-backed root and owner-issued resource IDs;
their cursors route reads to that owner and are bounded by its snapshot and cursor limits.
Operations sent through a handle from an earlier owner generation return `StaleOwner`;
open a new handle to discover the current owner. Cursor and snapshot tokens from the old
owner are never replayed against the new generation.
Both facades expose IO-based `backup` plus `backup_next` for bounded encoded chunks and
`backup_to(path, handle)` for durable publication. On a local handle, `backup_to` captures
an immutable retained root and streams it through a bounded cursor. On an owner-backed
handle, it opens an owner snapshot, counts it with an incremental cursor, then exports
through a second cursor over the same retained snapshot. Both paths export one consistent
view without materializing all visible results. The method creates a directory at
`path` containing the exchange file `BACKUP`; it stages that directory beside the
destination, syncs the file and directory, publishes it with no-replace rename, and
syncs the parent. If the final sync fails after rename, it returns `CommitUnknown`.
`Bytes.restore(path, exchange)` validates the complete in-memory exchange before
creating a sibling database and atomically publishing it. Restore input is currently
already resident as `Bytes`; `Bytes.restore_from(destination, bundle)` reads
`bundle/BACKUP` with a 64 MiB exchange-file limit, validates it, and publishes the
database. File import still holds the complete bounded exchange and decoded records
in memory during validation.

### Paired text and byte APIs

Use `Bytes` when keys or values are arbitrary octets. Ordering is unsigned
lexicographic byte order; a shorter matching prefix sorts first. `Utf8` accepts
`String` and strictly encodes it as UTF-8. Invalid stored bytes fail text reads and
text cursors with `InvalidUtf8`; the `Bytes` API continues to expose those bytes.

At a call site, `Bytes.put(handle, raw_key, raw_value)` accepts
`bend-kit-bytes.Bytes` keys and values; `Utf8.put(handle, "key", "value")`
accepts `String`. Each explicit-handle call returns the retained handle beside
its typed result, which the caller passes to the next operation.

`Utf8.put`, `Utf8.get`, `Utf8.scan_range`, and `Utf8.snapshot` provide the
corresponding text operations. Both scan APIs return a cursor that is read with
`scan_next` and must be released with `scan_close`; range lower bounds are
inclusive and upper bounds exclusive. Snapshot scans read a stable captured view,
and `snapshot.close` releases the snapshot token. Owner-backed snapshots and their
cursors are routed to the process holding the database lock.

Use `Bytes.backup_to(path, handle)` to publish a consistent backup from either a
local handle or a coordinated owner client, and `Bytes.restore_from(destination,
bundle)` to verify and publish it. `migrate_legacy(source, destination)` reads a
verified 0.5.0.0 database without modifying it and writes a new destination.
After `CommitUnknown`, reopen and inspect the database before deciding whether to
retry a mutation; the client never retries a dispatched write automatically.

This is implementation work toward 0.6.0.0, not a release claim. `Utf8` and `Bytes`
share the byte durable engine and storage format. Durable byte scans merge the SST block
cursor with a captured ordered delta and retain one SST head at a time; they do not clone
the complete result set. A scan cursor owns a file reader and must be closed. The explicit
snapshot API still materializes a bounded clone of visible entries and is not the
retained-generation snapshot design. `Bytes.compact`
folds the current single-run byte table, removes its tombstones, and atomically publishes
the replacement SST/WAL checkpoint; it does not yet compact multiple levels. Block
recovery validates one bounded block at a time and retains compact SST metadata; WAL
records replay into the active delta. Public scans use the file-level `SstCursor`, which
reads one block at a time and applies range/prefix filters and forward lower-bound
positioning. The serialized index and root are validated incrementally. Each positional
read is capped at 16 KiB so its read assembly and hash inputs fit the 64 KiB resident-buffer
budget; separator routing avoids scanning from the start for a validated lower-bound seek.
The explicit local snapshot API still materializes a bounded clone of visible entries;
owner-backed snapshots retain block-backed roots and route cursors through the owner.
Deferred generation-file reclamation, coordinated writers, and safe 0.5.0.0 migration
remain outstanding acceptance requirements. Restore validates a bounded whole exchange in
memory before publication. `Bytes.Stats` reports canonical visible entry and payload
totals plus active owner snapshots, their retained bytes, and owner cursors. Local direct
handles report zero for owner-managed resources; disk, buffer, queue, connection,
operation-failure, and persistent-generation metrics remain open.
Consumer smoke fixtures include `bench/smoke/byte_block_reader.sh`,
`bench/smoke/utf8_facade.sh`,
`bench/smoke/shared_utf8_bytes.sh`,
`bench/smoke/public_bytes_sst.sh`, and `bench/smoke/public_bytes_cursor.sh`.

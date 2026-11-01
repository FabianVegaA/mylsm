# Scans, snapshots, and retention

## Purpose

Traverse visible entries in order and retain a stable view while data changes. The
`Bytes` and `Utf8` views share the [binary order](storage-format.md); the latter also
checks that keys and values are valid UTF-8.

## Cursors

`scan`, `scan_range`, and `scan_prefix` in the [public API](durable-api.md) return
cursors. Ranges are `[lower, upper)`, with optional bounds; prefixes are compared as
exact bytes. `scan_seek` advances the inclusive lower bound.

`scan_next` returns an entry, a filtered step, the end, or a typed failure together
with the cursor. Continue after filtered steps. Release the cursor with `scan_close`,
including when abandoning a traversal or receiving a failure. Closing may return
reader errors. A text cursor enters terminal failure if it encounters invalid UTF-8.

Byte traversal combines a cursor over the published SST with a sorted copy of the
captured delta. It keeps one SST head at a time and reads blocks incrementally;
it does not build a list of the entire result. Index separators locate the initial
block without traversing the table from the beginning.

Positional reads are bounded to 16 KiB within a 64 KiB resident-buffer budget.
These buffer limits do not describe total process memory.

## Local and coordinated snapshots

| Type | Representation and ownership |
| --- | --- |
| Direct local handle | Canonical copy of visible entries, materialized up to 64 MiB |
| Owner handle | Block-backed root, retained delta, and remote identifiers |

`snapshot` captures the view and returns the updated handle. The snapshot supports
`get`, `scan_range`, and `scan_prefix`. Close its cursors first, then the snapshot.
Cursors created from an explicit snapshot leave responsibility for closing that
snapshot to the consumer.

A direct scan on a coordinated handle creates a private snapshot and a remote cursor.
Reaching the end releases both; `scan_close` releases them if traversal ends early.
A stream failure returns the cursor to allow cleanup.

The owner admits up to 64 snapshots, 64 MiB of retained roots in total, and 64 cursors
per snapshot. Rejected admission preserves the previous state. These are fixed
implementation limits. Identifiers belong to an owner generation; see
[coordination](coordination.md) for restarts and `StaleOwner`.

## Retained files

Flush and compaction publish a new immutable SST. Owner snapshots retain references
to the previous generation while they need it. Closing the last tracked reader allows
the retired SST to be reclaimed; the published generation is preserved. Do not delete
files from a retired generation on the assumption that they no longer have readers.

## Limits and evidence

Local snapshots still materialize entries. The
[acceptance report](../../bench/results/mylsm-0.6.0.0-acceptance.md) records that the
historical Linux test with 64,000 records, before the block-size fix, exceeded the
32 MiB process cap, although the increase from scanning 64 entries was less than
4 MiB. Linux cursor-memory revalidation after the fix remains pending; the current
macOS arm64 cursor-memory gate passes.

Physical retention is covered by snapshot fixtures during compaction; the validation
matrix for old tokens after owner restart remains pending.

## Implementation and checks

- Readers: [SstCursor.bend](../../src/scan/SstCursor.bend),
  [VisibleCursor.bend](../../src/scan/VisibleCursor.bend), and
  [RangeCursor.bend](../../src/scan/RangeCursor.bend).
- Retention: [Snapshot.bend](../../src/scan/Snapshot.bend),
  [OwnerSnapshotStore.bend](../../src/coordinator/OwnerSnapshotStore.bend), and
  [OwnerGenerationIo.bend](../../src/coordinator/OwnerGenerationIo.bend).
- Contracts: [ScanCursor.bend](../../laws/ScanCursor.bend),
  [Snapshot.bend](../../laws/Snapshot.bend), [Utf8CursorPolicy.bend](../../laws/Utf8CursorPolicy.bend),
  and their modules in [proofs](../../proofs/).
- Fixtures: [public_bytes_cursor.sh](../../bench/smoke/public_bytes_cursor.sh),
  [public_cursor_edges.sh](../../bench/smoke/public_cursor_edges.sh),
  [snapshot_preflight.sh](../../bench/smoke/snapshot_preflight.sh),
  [coordinator_owner_snapshot_dispatch.sh](../../bench/smoke/coordinator_owner_snapshot_dispatch.sh),
  and [public_cursor_memory.sh](../../bench/smoke/public_cursor_memory.sh).

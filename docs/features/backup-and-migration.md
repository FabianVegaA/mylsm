# Backup, restore, and migration

## Purpose

Export a consistent view and publish verified databases without overwriting destinations.
Public operations live in [mylsm.bend](../../mylsm.bend); encoding and generations are
described in [storage-format.md](storage-format.md).

## Backup

`Bytes.backup` materializes the local snapshot and returns an in-memory stream consumed
through `backup_next`. On a remote handle, it returns `UnsupportedOperation`;
use `backup_to` to export from the coordinated owner.
`Bytes.backup_to(path, handle)` publishes a durable bundle: a directory at `path`
containing `BACKUP`. `Utf8` offers corresponding operations over the same binary format.

The local `backup_to` path retains an immutable root and exports through a bounded
cursor. The coordinated path opens an owner snapshot, counts its entries with an
incremental cursor, and exports with another cursor over the same view. This allows
counting and emitting a consistent set while writes continue.

The bundle is written to a sibling temporary directory. The file and directory are
synced, publication uses rename without replacement, and the parent is synced. An
existing destination is rejected. A final sync failure after rename may return
`CommitUnknown`: the bundle may be published without durable confirmation.

Admission uses the retained-root budget, without an independent cap on the encoded
backup size. The incremental file path avoids constructing the complete result in
memory; do not extrapolate that property to every stream API.

## Restore

`Bytes.restore(destination, exchange)` receives bytes already in memory.
`restore_from(destination, bundle)` reads `bundle/BACKUP`, with a current limit of
64 MiB. Both paths validate version, lengths, strict ordering, absence of duplicates,
checksums, count, and final marker.

The current implementation keeps the entire bounded exchange and decoded records in
memory during validation. Incremental restore without this materialization remains pending.

The database is built in a sibling temporary directory, synced, reopened for verification,
and published without replacing an existing destination. Tombstones and database history
are not part of the exchange: it exports visible snapshot entries.

## Historical migration

`migrate_legacy(source, destination)` reads a database from API 0.5 with storage
0.4 / manifest generation 3. It validates its historical files and transforms its entries
into the current byte family, publishing a generation-5 manifest. Normal opening in
0.6 does not perform this migration implicitly.

The source is preserved. Verify the count, key/value bytes after legacy UTF-8 decoding,
and checksums before publishing the destination. Formats older than generation 3 are
unsupported. A failure before publication must not leave a final destination; if
confirmation fails after rename, inspect before retrying.

## Failures and evidence

Fixtures exercise publication, file limits, and full filesystems. A case using
`RLIMIT_FSIZE` checks the process file-size limit; it does not demonstrate behavior
under `ENOSPC`. Linux fixtures with full tmpfs exercise that case separately.

The [acceptance report](../../bench/results/mylsm-0.6.0.0-acceptance.md) records
environments and results. The final matrix of repeated backup/restore workloads remains
incomplete. [REPL](cli.md) import/export uses a different envelope and path;
do not interchange its files with a `BACKUP` bundle.

## Implementation and checks

- Backup: [Backup.bend](../../src/transfer/Backup.bend),
  [BackupIo.bend](../../src/transfer/BackupIo.bend), and
  [BackupOwnerCursorIo.bend](../../src/transfer/BackupOwnerCursorIo.bend).
- Restore and migration: [RestoreIo.bend](../../src/transfer/RestoreIo.bend),
  [MigrateIo.bend](../../src/transfer/MigrateIo.bend), and
  [MigrateRunIo.bend](../../src/transfer/MigrateRunIo.bend).
- Contracts: [Backup.bend](../../laws/Backup.bend),
  [RestorePolicy.bend](../../laws/RestorePolicy.bend), [Migration.bend](../../laws/Migration.bend),
  and [PublicationPolicy.bend](../../laws/PublicationPolicy.bend), with their [witnesses](../../proofs/).
- Integration: [backup_restore.sh](../../bench/smoke/backup_restore.sh),
  [public_backup_file.sh](../../bench/smoke/public_backup_file.sh), and
  [legacy_sst_io.sh](../../bench/smoke/legacy_sst_io.sh).
- Failures: [backup_publish.sh](../../bench/crash/backup_publish.sh),
  [migration_publish.sh](../../bench/crash/migration_publish.sh),
  [backup_enospc.sh](../../bench/crash/backup_enospc.sh), and
  [migration_enospc.sh](../../bench/crash/migration_enospc.sh).

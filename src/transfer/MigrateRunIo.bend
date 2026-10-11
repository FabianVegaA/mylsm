import Base
import ../ByteMemTable.bend as ByteMemTable
import ../Fs.bend as Fs
import ./BackupIo.bend as BackupIo
import ./FormatInspect.bend as FormatInspect
import ./FormatInspectIo.bend as FormatInspectIo
import ./Migrate.bend as Migrate
import ./MigrateIo.bend as MigrateIo
import ./RestoreIo.bend as RestoreIo

# Separates inspection, conversion, bundle, and destination publication failures.
type Error is Data:
  Inspection{error: FormatInspectIo.Error}
  Source{error: MigrateIo.Error}
  Rejected{reason: Migrate.Rejection}
  Conversion{code: U32, message: String}
  Backup{error: BackupIo.Error}
  Restore{error: RestoreIo.Error}
  Host{code: U32, message: String}
  PublicationStateInvalid{}

def path.clone.pair.go(path: String, left: String, right: String) -> String & String:
  match path:
    case SNil{}: (String.reverse(left), String.reverse(right))
    case SCon{+character, rest}:
      path.clone.pair.go(rest, SCon{character, left}, SCon{character, right})

def path.clone.pair(path: String) -> String & String:
  path.clone.pair.go(path, SNil{}, SNil{})

def path.clone.triple.second(
  first: String,
  pair: String & String
) -> String & String & String:
  match pair:
    case (second, third): (first, second, third)

def path.clone.triple.first(pair: String & String) -> String & String & String:
  match pair:
    case (first, suffix):
      path.clone.triple.second(first, path.clone.pair(suffix))

def path.clone.triple(path: String) -> String & String & String:
  path.clone.triple.first(path.clone.pair(path))

def migration.restored(
  result: Result<&1, &1, RestoreIo.Error, Unit>
) -> IO(Result<&1, &1, Error, Unit>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, Error, Unit>, Fail{Restore{error}})
    case Done{Unit{}}:
      IO.pure(Result<&1, &1, Error, Unit>, Done{Unit{}})

def cleanup.bundle(paths: String & String) -> IO(Unit):
  match paths:
    case (backup_path, directory):
      do IO<Unit>:
        _backup : Result<&1, &1, U32 & String, Unit> <-
          Fs.remove(backup_path ++ "/BACKUP")
        _directory : Result<&1, &1, U32 & String, Unit> <- Fs.remove(directory)
        return Unit{}

def migration.restore.paths(
  destination: String,
  paths: String & String & String
) -> IO(Result<&1, &1, Error, Unit>):
  match paths:
    case (restore_path, backup_path, directory):
      do IO<Result<&1, &1, Error, Unit>>:
        restored : Result<&1, &1, RestoreIo.Error, Unit> <-
          RestoreIo.restore_from(destination, restore_path)
        cleanup.bundle((backup_path, directory))
        migration.restored(restored)

def migration.restore(
  destination: String,
  bundle: String
) -> IO(Result<&1, &1, Error, Unit>):
  migration.restore.paths(destination, path.clone.triple(bundle))

def migration.exported(
  destination: String,
  bundle: String,
  result: Result<&1, &1, BackupIo.Error, Unit>
) -> IO(Result<&1, &1, Error, Unit>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, Error, Unit>, Fail{Backup{error}})
    case Done{Unit{}}:
      migration.restore(destination, bundle)

def migration.publication.export(
  destination: String,
  paths: String & String,
  entries: List<&1, ByteMemTable.Entry>
) -> IO(Result<&1, &1, Error, Unit>):
  match paths:
    case (export_path, retained_path):
      do IO<Result<&1, &1, Error, Unit>>:
        exported : Result<&1, &1, BackupIo.Error, Unit> <-
          BackupIo.export(export_path, entries)
        migration.exported(destination, retained_path, exported)

def migration.publication.started(
  result: Migrate.PublicationDecision,
  destination: String,
  bundle: String,
  entries: List<&1, ByteMemTable.Entry>
) -> IO(Result<&1, &1, Error, Unit>):
  match result:
    case Migrate.PublicationAdvanced{Migrate.SourceValidated{}}:
      migration.publication.export(destination, path.clone.pair(bundle),
        entries)
    case _:
      IO.pure(Result<&1, &1, Error, Unit>, Fail{PublicationStateInvalid{}})

def migration.admitted(
  decision: Migrate.Decision,
  destination: String,
  bundle: String,
  entries: List<&1, ByteMemTable.Entry>
) -> IO(Result<&1, &1, Error, Unit>):
  match decision:
    case Migrate.MigrateRejected{reason}:
      IO.pure(Result<&1, &1, Error, Unit>, Fail{Rejected{reason}})
    case Migrate.MigrateReady{_, _}:
      migration.publication.started(Migrate.begin(decision), destination,
        bundle, entries)

def migration.measured(
  inspection: FormatInspect.Inspection,
  destination: String,
  bundle: String,
  encoded_bytes: Nat,
  measured: List<&1, ByteMemTable.Entry> & Nat
) -> IO(Result<&1, &1, Error, Unit>):
  match measured:
    case (entries, count):
      decision = Migrate.plan(inspection,
        Migrate.LegacyFilesVerified{count, encoded_bytes}, True{},
        1000000n, 134217728n)
      migration.admitted(decision, destination, bundle, entries)

def migration.converted(
  inspection: FormatInspect.Inspection,
  destination: String,
  bundle: String,
  encoded_bytes: Nat,
  result: Result<&1, &1, U32 & String, List<&1, ByteMemTable.Entry>>
) -> IO(Result<&1, &1, Error, Unit>):
  match result:
    case Fail{(code, message)}:
      IO.pure(Result<&1, &1, Error, Unit>, Fail{Conversion{code, message}})
    case Done{entries}:
      migration.measured(inspection, destination, bundle, encoded_bytes,
        ByteMemTable.count.keep(entries))

def migration.snapshot(
  inspection: FormatInspect.Inspection,
  destination: String,
  bundle: String,
  result: Result<&1, &1, MigrateIo.Error, MigrateIo.SourceSnapshot>
) -> IO(Result<&1, &1, Error, Unit>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, Error, Unit>, Fail{Source{error}})
    case Done{MigrateIo.LegacySourceSnapshot{sst_records, wal_batches,
        _, _, encoded_bytes}}:
      migration.converted(inspection, destination, bundle, encoded_bytes,
        Migrate.legacy.snapshot.entries(sst_records, wal_batches))

def migration.destination.checked(
  source: String,
  destination: String,
  bundle: String,
  inspection: FormatInspect.Inspection,
  result: Result<&1, &1, U32 & String, Bool>
) -> IO(Result<&1, &1, Error, Unit>):
  match result:
    case Fail{(code, message)}:
      IO.pure(Result<&1, &1, Error, Unit>, Fail{Host{code, message}})
    case Done{True{}}:
      IO.pure(Result<&1, &1, Error, Unit>,
        Fail{Rejected{Migrate.DestinationExists{}}})
    case Done{False{}}:
      do IO<Result<&1, &1, Error, Unit>>:
        snapshot : Result<&1, &1, MigrateIo.Error, MigrateIo.SourceSnapshot> <-
          MigrateIo.read_legacy_source(source)
        migration.snapshot(inspection, destination, bundle, snapshot)

def inspection.checked(
  paths: String & String & String & String,
  result: Result<&1, &1, FormatInspectIo.Error, FormatInspect.Inspection>
) -> IO(Result<&1, &1, Error, Unit>):
  match paths result:
    case (source_read, destination_check, destination, bundle), Fail{error}:
      IO.pure(Result<&1, &1, Error, Unit>, Fail{Inspection{error}})
    case (source_read, destination_check, destination, bundle), Done{inspection}:
      do IO<Result<&1, &1, Error, Unit>>:
        exists : Result<&1, &1, U32 & String, Bool> <- Fs.exists(destination_check)
        migration.destination.checked(source_read, destination, bundle,
          inspection, exists)

def migrate.paths.destination(
  source_inspect: String,
  source_read: String,
  destination_paths: String & String & String
) -> IO(Result<&1, &1, Error, Unit>):
  match destination_paths:
    case (destination_check, destination, bundle_base):
      do IO<Result<&1, &1, Error, Unit>>:
        inspection : Result<&1, &1, FormatInspectIo.Error,
          FormatInspect.Inspection> <- FormatInspectIo.inspect(source_inspect)
        inspection.checked((source_read, destination_check, destination,
          bundle_base ++ ".migrate-060.bundle"), inspection)

def migrate.paths(
  source_paths: String & String,
  destination_paths: String & String & String
) -> IO(Result<&1, &1, Error, Unit>):
  match source_paths:
    case (source_inspect, source_read):
      migrate.paths.destination(source_inspect, source_read, destination_paths)

# Converts and atomically publishes one verified legacy source snapshot.
def migrate_legacy_source(
  +source: String,
  +destination: String
) -> IO(Result<&1, &1, Error, Unit>):
  migrate.paths(path.clone.pair(source), path.clone.triple(destination))

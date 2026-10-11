import Base
import ./Backup.bend as Backup
import ./PublicationPolicy.bend as PublicationPolicy
import ../ByteMemTable.bend as ByteMemTable
import ../CrashPoint.bend as CrashPoint
import ../Fs.bend as Fs
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Distinguishes pre-publication IO failures from an uncertain durable commit.
type Error is Data:
  AlreadyExists{}
  UnsupportedPlatform{}
  ResourceLimit{}
  Io{code: U32, message: String}
  CommitUnknown{code: U32, message: String}

# Carries the open staged file and one backup stream transition.
type State is Type:
  Need{file: File, stream: Backup.Stream}
  Output{file: File, result: Result<&1, &1, Backup.Error, Backup.Step>}
  Written{pair: File & Result<&1, &1, U32 & String, Unit>, stream: Backup.Stream}

def path.reverse(path: String, reversed: String) -> String:
  match path:
    case SNil{}: reversed
    case SCon{character, rest}: path.reverse(rest, SCon{character, reversed})

def path.clone(path: String) -> String:
  path.reverse(path.reverse(path, SNil{}), SNil{})

# Removes known staging contents after a failure or successful rename.
def cleanup(+directory: String) -> IO(Unit):
  do IO<Unit>:
    _file : Result<&1, &1, U32 & String, Unit> <- Fs.remove(directory ++ "/BACKUP")
    _directory : Result<&1, &1, U32 & String, Unit> <- Fs.remove(directory)
    return Unit{}

def close.failed.cleaned(
  +directory: String,
  error: U32 & String
) -> IO(Result<&1, &1, Error, Unit>):
  match error:
    case (code, message):
      do IO<Result<&1, &1, Error, Unit>>:
        cleanup(directory)
        return Fail{Io{code, message}}

def close.failed(file: File, +directory: String, error: U32 & String) -> IO(Result<&1, &1, Error, Unit>):
  do IO<Result<&1, &1, Error, Unit>>:
    _closed : Unit <- File.close(file)
    close.failed.cleaned(directory, error)

def publish.parent.failed(
  +temporary: String,
  disposition: PublicationPolicy.Failure,
  error: U32 & String
) -> IO(Result<&1, &1, Error, Unit>):
  match disposition:
    case PublicationPolicy.CommitUnknown{}:
      match error:
        case (code, message):
          do IO<Result<&1, &1, Error, Unit>>:
            cleanup(temporary)
            return Fail{CommitUnknown{code, "backup published but parent sync failed: " ++ message}}
    case PublicationPolicy.KnownFailure{}:
      match error:
        case (code, message):
          IO.pure(Result<&1, &1, Error, Unit>, Fail{Io{code, message}})

def publish.parent(
  +temporary: String,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, Error, Unit>):
  match result:
    case Fail{error}:
      publish.parent.failed(temporary,
        PublicationPolicy.failure(PublicationPolicy.AfterRename{}), error)
    case Done{Unit{}}:
      do IO<Result<&1, &1, Error, Unit>>:
        _stopped : Result<&1, &1, U32 & String, Unit> <- CrashPoint.hit("backup.parent_synced")
        cleanup(temporary)
        return Done{Unit{}}

def publish.rename.failed(
  +temporary: String,
  disposition: PublicationPolicy.Failure,
  error: U32 & String
) -> IO(Result<&1, &1, Error, Unit>):
  match disposition:
    case PublicationPolicy.KnownFailure{}:
      match error:
        case (code, message):
          do IO<Result<&1, &1, Error, Unit>>:
            cleanup(temporary)
            return Fail{Io{code, "exclusive backup rename failed: " ++ message}}
    case PublicationPolicy.CommitUnknown{}:
      match error:
        case (code, message):
          IO.pure(Result<&1, &1, Error, Unit>, Fail{CommitUnknown{code, message}})

def publish.rename(
  +destination: String,
  +temporary: String,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, Error, Unit>):
  match result:
    case Fail{error}:
      publish.rename.failed(temporary,
        PublicationPolicy.failure(PublicationPolicy.BeforeRename{}), error)
    case Done{Unit{}}:
      do IO<Result<&1, &1, Error, Unit>>:
        _stopped : Result<&1, &1, U32 & String, Unit> <- CrashPoint.hit("backup.renamed")
        synced : Result<&1, &1, U32 & String, Unit> <- Fs.fsync(path.clone(destination ++ "/.."))
        publish.parent(temporary, synced)

def publish.directory.synced(
  +destination: String,
  +temporary: String,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, Error, Unit>):
  match result:
    case Fail{(code, message)}:
      do IO<Result<&1, &1, Error, Unit>>:
        cleanup(temporary)
        return Fail{Io{code, message}}
    case Done{Unit{}}:
      do IO<Result<&1, &1, Error, Unit>>:
        _stopped : Result<&1, &1, U32 & String, Unit> <- CrashPoint.hit("backup.before_rename")
        renamed : Result<&1, &1, U32 & String, Unit> <-
          Fs.rename_noreplace(path.clone(temporary), path.clone(destination))
        publish.rename(destination, temporary, renamed)


def publish.synced(
  +destination: String,
  +temporary: String,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, Error, Unit>):
  match result:
    case Fail{(code, message)}:
      do IO<Result<&1, &1, Error, Unit>>:
        cleanup(temporary)
        return Fail{Io{code, message}}
    case Done{Unit{}}:
      do IO<Result<&1, &1, Error, Unit>>:
        synced : Result<&1, &1, U32 & String, Unit> <- Fs.fsync(path.clone(temporary))
        publish.directory.synced(destination, temporary, synced)

def publish.closed.result(
  +destination: String,
  +temporary: String,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, Error, Unit>):
  match result:
    case Fail{(code, message)}:
      do IO<Result<&1, &1, Error, Unit>>:
        cleanup(temporary)
        return Fail{Io{code, message}}
    case Done{Unit{}}:
      do IO<Result<&1, &1, Error, Unit>>:
        synced : Result<&1, &1, U32 & String, Unit> <- Fs.fsync(path.clone(temporary ++ "/BACKUP"))
        publish.synced(destination, temporary, synced)

def publish.closed(
  +destination: String,
  +temporary: String,
  file: File,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, Error, Unit>):
  do IO<Result<&1, &1, Error, Unit>>:
    _closed : Unit <- File.close(file)
    publish.closed.result(destination, temporary, result)

# Writes one bounded encoded chunk per state transition before publication.
def loop(fuel: Nat, +destination: String, +temporary: String, state: State) -> IO(Result<&1, &1, Error, Unit>):
  match fuel:
    case 0n:
      match state:
        case Need{file, _}: close.failed(file, temporary, (7, "backup stream exceeded its transition budget"))
        case Output{file, _}: close.failed(file, temporary, (7, "backup stream exceeded its transition budget"))
        case Written{(file, _), _}:
          do IO<Result<&1, &1, Error, Unit>>:
            _closed : Unit <- File.close(file)
            cleanup(temporary)
            return Fail{Io{7, "backup stream exceeded its transition budget"}}
    case 1n+rest:
      match state:
        case Need{file, stream}:
          loop(rest, destination, temporary, Output{file, Backup.next(stream)})
        case Output{file, result}:
          match result:
            case Fail{_}:
              close.failed(file, temporary, (22, "backup encoder rejected its snapshot"))
            case Done{Backup.End{}}:
              publish.closed(destination, temporary, file, Done{Unit{}})
            case Done{Backup.Chunk{stream, bytes}}:
              do IO<Result<&1, &1, Error, Unit>>:
                written : File & Result<&1, &1, U32 & String, Unit> <- Fs.write_bytes(file, bytes)
                loop(rest, destination, temporary, Written{written, stream})
        case Written{pair, stream}:
          match pair:
            case (file, Fail{error}): close.failed(file, temporary, error)
            case (file, Done{Unit{}}): loop(rest, destination, temporary, Need{file, stream})

def directory.file.opened(
  +destination: String,
  +temporary: String,
  stream: Backup.Stream,
  fuel: Nat,
  opened: Result<&1, &1, U32 & String, File>
) -> IO(Result<&1, &1, Error, Unit>):
  match opened:
    case Fail{(code, message)}:
      do IO<Result<&1, &1, Error, Unit>>:
        cleanup(temporary)
        return Fail{Io{code, message}}
    case Done{file}: loop(fuel, destination, temporary, Need{file, stream})

def directory.created(
  +destination: String,
  +temporary: String,
  result: Result<&1, &1, U32 & String, Unit>,
  stream: Backup.Stream,
  fuel: Nat
) -> IO(Result<&1, &1, Error, Unit>):
  match result:
    case Fail{(code, _)}:
      match code:
        case 17: IO.pure(Result<&1, &1, Error, Unit>, Fail{AlreadyExists{}})
        case _: IO.pure(Result<&1, &1, Error, Unit>, Fail{Io{code, "backup staging directory creation failed"}})
    case Done{Unit{}}:
      do IO<Result<&1, &1, Error, Unit>>:
        opened : Result<&1, &1, U32 & String, File> <- File.open(path.clone(temporary ++ "/BACKUP"), "w")
        directory.file.opened(destination, temporary, stream, fuel, opened)

def destination.checked(
  +destination: String,
  +temporary: String,
  exists: Result<&1, &1, U32 & String, Bool>,
  stream: Backup.Stream,
  fuel: Nat
) -> IO(Result<&1, &1, Error, Unit>):
  match exists:
    case Fail{(code, message)}:
      IO.pure(Result<&1, &1, Error, Unit>, Fail{Io{code, message}})
    case Done{True{}}: IO.pure(Result<&1, &1, Error, Unit>, Fail{AlreadyExists{}})
    case Done{False{}}:
      do IO<Result<&1, &1, Error, Unit>>:
        created : Result<&1, &1, U32 & String, Unit> <- Fs.make_dir(path.clone(temporary))
        directory.created(destination, temporary, created, stream, fuel)

# Stages a backup bundle and publishes it without replacing an existing path.
def start(+destination: String, stream: Backup.Stream) -> IO(Result<&1, &1, Error, Unit>):
  match stream:
    case Backup.Stream{_, _, _, +block_count, _}:
      +temporary = destination ++ ".backup-060.tmp"
      do IO<Result<&1, &1, Error, Unit>>:
        exists : Result<&1, &1, U32 & String, Bool> <- Fs.exists(path.clone(destination))
        destination.checked(destination, temporary, exists, stream,
          Backup.write_fuel(U32.to_nat(block_count)))

def start.result(
  +destination: String,
  result: Result<&1, &1, Backup.Error, Backup.Stream>
) -> IO(Result<&1, &1, Error, Unit>):
  match result:
    case Fail{_}: IO.pure(Result<&1, &1, Error, Unit>, Fail{Io{22, "backup encoder rejected its snapshot"}})
    case Done{stream}: start(destination, stream)

# Starts the checksummed file export from an immutable logical snapshot.
def export(+destination: String, entries: List<&1, ByteMemTable.Entry>) -> IO(Result<&1, &1, Error, Unit>):
  start.result(destination, Backup.start(entries))

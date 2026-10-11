import Base
import ../Fs.bend as Fs
import ../scan/VisibleCursor.bend as VisibleCursor
import ./BackupCursor.bend as BackupCursor
import ./BackupIo.bend as BackupIo
import ./Backup.bend as Backup
# Carries one pending read, bounded chunk write, or completed file write.
type State is Type:
  Need{file: File, stream: BackupCursor.Stream}
  Output{file: File, step: BackupCursor.Step}
  Written{pair: File & Result<&1, &1, U32 & String, Unit>, stream: BackupCursor.Stream}

def path.reverse(path: String, reversed: String) -> String:
  match path:
    case SNil{}: reversed
    case SCon{character, rest}: path.reverse(rest, SCon{character, reversed})

def path.clone(path: String) -> String:
  path.reverse(path.reverse(path, SNil{}), SNil{})

def error.host(error: Backup.Error) -> U32 & String:
  match error:
    case Backup.SourceFailure{code, message}: (code, message)
    case Backup.ResourceLimit{}: (7, "backup cursor exceeded its bounded policy")
    case Backup.InvalidOrder{}: (22, "backup cursor rejected noncanonical order")
    case Backup.CodecFailure{}: (22, "backup cursor encoder rejected its source")

def error.io.copied(pair: U32 & String) -> BackupIo.Error:
  match pair:
    case (code, message): BackupIo.Io{code, message}

def error.io(error: Backup.Error) -> BackupIo.Error:
  error.io.copied(error.host(error))

# Removes the known staging file and directory after failed publication.
# Removes the known staging file and directory after failed publication.
def cleanup(+directory: String) -> IO(Unit):
  do IO<Unit>:
    _file : Result<&1, &1, U32 & String, Unit> <- Fs.remove(directory ++ "/BACKUP")
    _directory : Result<&1, &1, U32 & String, Unit> <- Fs.remove(directory)
    return Unit{}

def close.source(
  file: File,
  +directory: String,
  cursor: VisibleCursor.Cursor,
  error: U32 & String
) -> IO(Result<&1, &1, BackupIo.Error, Unit>):
  do IO<Result<&1, &1, BackupIo.Error, Unit>>:
    _closed_cursor : Result<&1, &1, U32 & String, Unit> <- VisibleCursor.close(cursor)
    BackupIo.close.failed(file, directory, error)

def close.stream(
  file: File,
  +directory: String,
  stream: BackupCursor.Stream,
  error: U32 & String
) -> IO(Result<&1, &1, BackupIo.Error, Unit>):
  match stream:
    case BackupCursor.Stream{_, Some{cursor}, _, _, _, _, _, _, _}:
      close.source(file, directory, cursor, error)
    case BackupCursor.Stream{_, None{}, _, _, _, _, _, _, _}:
      BackupIo.close.failed(file, directory, error)

def close.optional(
  file: File,
  +directory: String,
  cursor: Maybe<&1, VisibleCursor.Cursor>,
  error: U32 & String
) -> IO(Result<&1, &1, BackupIo.Error, Unit>):
  match cursor:
    case Some{reader}: close.source(file, directory, reader, error)
    case None{}: BackupIo.close.failed(file, directory, error)

def close.resource(
  file: File,
  +directory: String,
  cursor: Maybe<&1, VisibleCursor.Cursor>
) -> IO(Result<&1, &1, BackupIo.Error, Unit>):
  match cursor:
    case Some{reader}:
      do IO<Result<&1, &1, BackupIo.Error, Unit>>:
        _closed_cursor : Result<&1, &1, U32 & String, Unit> <- VisibleCursor.close(reader)
        _closed_file : Unit <- File.close(file)
        cleanup(directory)
        return Fail{BackupIo.ResourceLimit{}}
    case None{}:
      do IO<Result<&1, &1, BackupIo.Error, Unit>>:
        _closed_file : Unit <- File.close(file)
        cleanup(directory)
        return Fail{BackupIo.ResourceLimit{}}

def close.resource.stream(
  file: File,
  +directory: String,
  stream: BackupCursor.Stream
) -> IO(Result<&1, &1, BackupIo.Error, Unit>):
  match stream:
    case BackupCursor.Stream{_, cursor, _, _, _, _, _, _, _}:
      close.resource(file, directory, cursor)

def close.error.host(
  file: File,
  +directory: String,
  cursor: Maybe<&1, VisibleCursor.Cursor>,
  pair: U32 & String
) -> IO(Result<&1, &1, BackupIo.Error, Unit>):
  match pair:
    case (code, message): close.optional(file, directory, cursor, (code, message))

def close.error(
  file: File,
  +directory: String,
  cursor: Maybe<&1, VisibleCursor.Cursor>,
  error: Backup.Error
) -> IO(Result<&1, &1, BackupIo.Error, Unit>):
  match error:
    case Backup.ResourceLimit{}: close.resource(file, directory, cursor)
    case _: close.error.host(file, directory, cursor, error.host(error))

def close.cursor(cursor: Maybe<&1, VisibleCursor.Cursor>) -> IO(Unit):
  match cursor:
    case Some{reader}:
      do IO<Unit>:
        _closed : Result<&1, &1, U32 & String, Unit> <- VisibleCursor.close(reader)
        return Unit{}
    case None{}: IO.pure(Unit, Unit{})

def close.initial.stream(stream: BackupCursor.Stream) -> IO(Unit):
  match stream:
    case BackupCursor.Stream{_, cursor, _, _, _, _, _, _, _}:
      close.cursor(cursor)

def close.initial(initial: BackupCursor.Step) -> IO(Unit):
  match initial:
    case BackupCursor.Chunk{stream, _}: close.initial.stream(stream)
    case BackupCursor.Continue{stream}: close.initial.stream(stream)
    case BackupCursor.Failure{cursor, _}: close.cursor(cursor)
    case BackupCursor.End{}: IO.pure(Unit, Unit{})

def initial.failed(
  initial: BackupCursor.Step,
  error: BackupIo.Error
) -> IO(Result<&1, &1, BackupIo.Error, Unit>):
  do IO<Result<&1, &1, BackupIo.Error, Unit>>:
    _closed : Unit <- close.initial(initial)
    return Fail{error}

def close.file.result(
  +destination: String,
  +temporary: String,
  file: File,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, BackupIo.Error, Unit>):
  match result:
    case Fail{error}: BackupIo.close.failed(file, temporary, error)
    case Done{Unit{}}:
      BackupIo.publish.closed(destination, temporary, file, Done{Unit{}})

def close.file(
  +destination: String,
  +temporary: String,
  file: File
) -> IO(Result<&1, &1, BackupIo.Error, Unit>):
  BackupIo.publish.closed(destination, temporary, file, Done{Unit{}})

def source.step(stream: BackupCursor.Stream) -> IO(BackupCursor.Step):
  match stream:
    case BackupCursor.Stream{BackupCursor.CursorBlocks{}, Some{cursor}, pending,
        pending_count, seen, expected, entry_count, block_count, block_index}:
      metadata : BackupCursor.Stream = BackupCursor.Stream{BackupCursor.CursorBlocks{}, None{},
        pending, pending_count, seen, expected, entry_count, block_count,
        block_index}
      do IO<BackupCursor.Step>:
        next : VisibleCursor.Step <- VisibleCursor.next(cursor)
        return BackupCursor.advance(metadata, next)
    case _:
      IO.pure(BackupCursor.Step, BackupCursor.advance(stream, VisibleCursor.End{}))

def loop.abort(
  +temporary: String,
  state: State
) -> IO(Result<&1, &1, BackupIo.Error, Unit>):
  match state:
    case Need{file, stream}:
      close.resource.stream(file, temporary, stream)
    case Output{file, step}:
      match step:
        case BackupCursor.Failure{cursor, error}:
          close.error(file, temporary, cursor, error)
        case BackupCursor.Chunk{stream, _}:
          close.resource.stream(file, temporary, stream)
        case BackupCursor.Continue{stream}:
          close.resource.stream(file, temporary, stream)
        case BackupCursor.End{}:
          close.resource(file, temporary, None{})
    case Written{pair, stream}:
      match pair:
        case (file, Fail{error}): close.stream(file, temporary, stream, error)
        case (file, Done{Unit{}}):
          close.resource.stream(file, temporary, stream)

# Pulls at most one visible cursor result and writes at most one encoded chunk.
def loop(
  fuel: Nat,
  +destination: String,
  +temporary: String,
  state: State
) -> IO(Result<&1, &1, BackupIo.Error, Unit>):
  match fuel:
    case 0n: loop.abort(temporary, state)
    case 1n+rest:
      match state:
        case Need{file, stream}:
          do IO<Result<&1, &1, BackupIo.Error, Unit>>:
            step : BackupCursor.Step <- source.step(stream)
            loop(rest, destination, temporary, Output{file, step})
        case Output{file, step}:
          match step:
            case BackupCursor.Failure{cursor, error}:
              close.error(file, temporary, cursor, error)
            case BackupCursor.Continue{stream}:
              loop(rest, destination, temporary, Need{file, stream})
            case BackupCursor.Chunk{stream, bytes}:
              do IO<Result<&1, &1, BackupIo.Error, Unit>>:
                written : File & Result<&1, &1, U32 & String, Unit> <- Fs.write_bytes(file, bytes)
                loop(rest, destination, temporary, Written{written, stream})
            case BackupCursor.End{}:
              close.file(destination, temporary, file)
        case Written{pair, stream}:
          match pair:
            case (file, Fail{error}):
              close.stream(file, temporary, stream, error)
            case (file, Done{Unit{}}):
              loop(rest, destination, temporary, Need{file, stream})

def file.opened(
  +destination: String,
  +temporary: String,
  initial: BackupCursor.Step,
  fuel: Nat,
  opened: Result<&1, &1, U32 & String, File>
) -> IO(Result<&1, &1, BackupIo.Error, Unit>):
  match opened:
    case Fail{(code, message)}:
      do IO<Result<&1, &1, BackupIo.Error, Unit>>:
        _closed : Unit <- close.initial(initial)
        cleanup(temporary)
        return Fail{BackupIo.Io{code, message}}
    case Done{file}:
      loop(fuel, destination, temporary, Output{file, initial})

def directory.created(
  +destination: String,
  +temporary: String,
  initial: BackupCursor.Step,
  fuel: Nat,
  created: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, BackupIo.Error, Unit>):
  match created:
    case Fail{(code, message)}:
      match code:
        case 17: initial.failed(initial, BackupIo.AlreadyExists{})
        case _: initial.failed(initial, BackupIo.Io{code, message})
    case Done{Unit{}}:
      do IO<Result<&1, &1, BackupIo.Error, Unit>>:
        opened : Result<&1, &1, U32 & String, File> <- File.open(path.clone(temporary ++ "/BACKUP"), "w")
        file.opened(destination, temporary, initial, fuel, opened)

def destination.checked(
  +destination: String,
  +temporary: String,
  initial: BackupCursor.Step,
  fuel: Nat,
  exists: Result<&1, &1, U32 & String, Bool>
) -> IO(Result<&1, &1, BackupIo.Error, Unit>):
  match exists:
    case Fail{(code, message)}:
      initial.failed(initial, BackupIo.Io{code, message})
    case Done{True{}}:
      initial.failed(initial, BackupIo.AlreadyExists{})
    case Done{False{}}:
      do IO<Result<&1, &1, BackupIo.Error, Unit>>:
        created : Result<&1, &1, U32 & String, Unit> <- Fs.make_dir(path.clone(temporary))
        directory.created(destination, temporary, initial, fuel, created)

def initial.checked(
  +destination: String,
  +temporary: String,
  initial: BackupCursor.Step,
  fuel: Nat,
  exists: Result<&1, &1, U32 & String, Bool>
) -> IO(Result<&1, &1, BackupIo.Error, Unit>):
  match initial:
    case BackupCursor.Failure{cursor, error}:
      do IO<Result<&1, &1, BackupIo.Error, Unit>>:
        _closed : Unit <- close.cursor(cursor)
        return Fail{error.io(error)}
    case BackupCursor.Chunk{_, _}:
      destination.checked(destination, temporary, initial, fuel, exists)
    case _:
      initial.failed(initial, BackupIo.Io{22, "backup cursor failed to encode its header"})

# Exports a stable visible cursor through bounded checksummed chunks.
def export(
  +destination: String,
  cursor: VisibleCursor.Cursor,
  entry_count: Nat,
  fuel: Nat
) -> IO(Result<&1, &1, BackupIo.Error, Unit>):
  +temporary = destination ++ ".backup-060.tmp"
  do IO<Result<&1, &1, BackupIo.Error, Unit>>:
    initial : BackupCursor.Step <- IO.pure(BackupCursor.Step,
      BackupCursor.start(cursor, entry_count))
    exists : Result<&1, &1, U32 & String, Bool> <- Fs.exists(path.clone(destination))
    initial.checked(destination, temporary, initial, fuel, exists)

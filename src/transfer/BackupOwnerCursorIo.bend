import Base
import ../Fs.bend as Fs
import ../coordinator/Client.bend as Client
import ../coordinator/ByteClient.bend as ByteClient
import ../coordinator/CursorCodec.bend as CursorCodec
import ../coordinator/Protocol.bend as Protocol
import ./BackupCursor.bend as BackupCursor
import ./BackupCursorIo.bend as BackupCursorIo
import ./BackupIo.bend as BackupIo
import ./Backup.bend as Backup

# Tracks the retained owner snapshot and its export cursor lifecycle.
type OwnerSource is Type:
  OwnerSource{session: Client.Session, snapshot_id: U32, cursor_id: U32,
    cursor_live: Bool}

# Carries the bounded backup writer through remote cursor transitions.
type State is Type:
  Need{file: File, source: OwnerSource, stream: BackupCursor.Stream}
  Output{file: File, source: OwnerSource, step: BackupCursor.Step}
  Written{pair: File & Result<&1, &1, U32 & String, Unit>,
    source: OwnerSource, stream: BackupCursor.Stream}

def source.clone.values(
  sessions: Client.Session & Client.Session,
  snapshot_ids: U32 & U32 & U32,
  cursor_ids: U32 & U32 & U32,
  cursor_live: Bool
) -> OwnerSource & OwnerSource:
  match sessions:
    case (first_session, second_session):
      match snapshot_ids:
        case (first_snapshot, (second_snapshot, _)):
          match cursor_ids:
            case (first_cursor, (second_cursor, _)):
              match cursor_live:
                case True{}:
                  (OwnerSource{first_session, first_snapshot, first_cursor,
                    True{}}, OwnerSource{second_session, second_snapshot,
                    second_cursor, True{}})
                case False{}:
                  (OwnerSource{first_session, first_snapshot, first_cursor,
                    False{}}, OwnerSource{second_session, second_snapshot,
                    second_cursor, False{}})

def source.clone(source: OwnerSource) -> OwnerSource & OwnerSource:
  match source:
    case OwnerSource{session, snapshot_id, cursor_id, cursor_live}:
      source.clone.values(Client.session.clone(session),
        Protocol.u32.duplicate.triple(snapshot_id),
        Protocol.u32.duplicate.triple(cursor_id), cursor_live)

def source.error(_: Client.Error) -> U32 & String:
  (5, "owner snapshot cursor request failed")

def source.error.value(pair: U32 & String) -> Backup.Error:
  match pair:
    case (code, message): Backup.SourceFailure{code, message}

def source.step.result(
  source: OwnerSource,
  stream: BackupCursor.Stream,
  pair: Client.Session & Result<&1, &1, Client.Error, CursorCodec.Frame>
) -> OwnerSource & BackupCursor.Step:
  match source:
    case OwnerSource{_, snapshot_id, cursor_id, cursor_live}:
      match pair:
        case (session, Fail{error}):
          (OwnerSource{session, snapshot_id, cursor_id, cursor_live},
            BackupCursor.Failure{None{},
              source.error.value(source.error(error))})
        case (session, Done{frame}):
          match frame:
            case CursorCodec.CursorEnd{}:
              (OwnerSource{session, snapshot_id, cursor_id, False{}},
                BackupCursor.advance.owner(stream, frame))
            case CursorCodec.CursorItem{_, _}:
              (OwnerSource{session, snapshot_id, cursor_id, True{}},
                BackupCursor.advance.owner(stream, frame))

def source.step.state(
  file: File,
  advanced: OwnerSource & BackupCursor.Step
) -> State:
  match advanced:
    case (source, step): Output{file, source, step}

def source.step.cloned(
  file: File,
  stream: BackupCursor.Stream,
  sources: OwnerSource & OwnerSource
) -> IO(State):
  match sources:
    case (request_source, retained_source):
      match request_source:
        case OwnerSource{session, _, cursor_id, _}:
          do IO<State>:
            pair : Client.Session &
              Result<&1, &1, Client.Error, CursorCodec.Frame> <-
                ByteClient.snapshot.cursor.next(session, cursor_id)
            return source.step.state(file,
              source.step.result(retained_source, stream, pair))

def source.step(
  source: OwnerSource,
  stream: BackupCursor.Stream,
  file: File
) -> IO(State):
  match stream:
    case BackupCursor.Stream{BackupCursor.CursorBlocks{}, _, _, _, _, _, _, _, _}:
      source.step.cloned(file, stream, source.clone(source))
    case _:
      IO.pure(State, Output{file, source,
        BackupCursor.advance.owner(stream, CursorCodec.CursorEnd{})})

def close.failed.snapshot(
  file: File,
  +temporary: String,
  session: Client.Session,
  snapshot_id: U32,
  error: Backup.Error
) -> IO(Result<&1, &1, BackupIo.Error, Unit>):
  do IO<Result<&1, &1, BackupIo.Error, Unit>>:
    _closed : Client.Session & Result<&1, &1, Client.Error, Unit> <-
      ByteClient.snapshot.close(session, snapshot_id)
    BackupCursorIo.close.error(file, temporary, None{}, error)

def close.failed.cursor(
  file: File,
  +temporary: String,
  snapshot_id: U32,
  error: Backup.Error,
  closed: Client.Session & Result<&1, &1, Client.Error, Unit>
) -> IO(Result<&1, &1, BackupIo.Error, Unit>):
  match closed:
    case (after_cursor, _):
      close.failed.snapshot(file, temporary, after_cursor, snapshot_id, error)

def close.failed.source(
  file: File,
  +temporary: String,
  source: OwnerSource,
  error: Backup.Error
) -> IO(Result<&1, &1, BackupIo.Error, Unit>):
  match source:
    case OwnerSource{session, snapshot_id, cursor_id, cursor_live}:
      match cursor_live:
        case True{}:
          do IO<Result<&1, &1, BackupIo.Error, Unit>>:
            closed : Client.Session &
              Result<&1, &1, Client.Error, Unit> <-
                ByteClient.snapshot.cursor.close(session, cursor_id)
            close.failed.cursor(file, temporary, snapshot_id,
              error, closed)
        case False{}:
          close.failed.snapshot(file, temporary, session, snapshot_id, error)

def close.success.snapshot(
  +destination: String,
  +temporary: String,
  file: File,
  pair: Client.Session & Result<&1, &1, Client.Error, Unit>
) -> IO(Result<&1, &1, BackupIo.Error, Unit>):
  match pair:
    case (_, Fail{_}):
      BackupCursorIo.close.error(file, temporary, None{},
        source.error.value(source.error(Client.MalformedResponse{})))
    case (_, Done{Unit{}}):
      BackupCursorIo.close.file(destination, temporary, file)

def close.success(
  +destination: String,
  +temporary: String,
  file: File,
  source: OwnerSource
) -> IO(Result<&1, &1, BackupIo.Error, Unit>):
  match source:
    case OwnerSource{session, snapshot_id, _, _}:
      do IO<Result<&1, &1, BackupIo.Error, Unit>>:
        closed : Client.Session & Result<&1, &1, Client.Error, Unit> <-
          ByteClient.snapshot.close(session, snapshot_id)
        close.success.snapshot(destination, temporary, file, closed)

def loop.abort(
  +temporary: String,
  state: State
) -> IO(Result<&1, &1, BackupIo.Error, Unit>):
  match state:
    case Need{file, source, _}:
      close.failed.source(file, temporary, source, Backup.ResourceLimit{})
    case Output{file, source, _}:
      close.failed.source(file, temporary, source, Backup.ResourceLimit{})
    case Written{(file, _), source, _}:
      close.failed.source(file, temporary, source, Backup.ResourceLimit{})

# Advances backup IO state without reading beyond its declared work budget.
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
        case Need{file, source, stream}:
          do IO<Result<&1, &1, BackupIo.Error, Unit>>:
            advanced : State <- source.step(source, stream, file)
            loop(rest, destination, temporary, advanced)
        case Output{file, source, step}:
          match step:
            case BackupCursor.Failure{_, error}:
              close.failed.source(file, temporary, source, error)
            case BackupCursor.Continue{stream}:
              loop(rest, destination, temporary, Need{file, source, stream})
            case BackupCursor.Chunk{stream, bytes}:
              do IO<Result<&1, &1, BackupIo.Error, Unit>>:
                written : File & Result<&1, &1, U32 & String, Unit> <-
                  Fs.write_bytes(file, bytes)
                loop(rest, destination, temporary,
                  Written{written, source, stream})
            case BackupCursor.End{}:
              close.success(destination, temporary, file, source)
        case Written{pair, source, stream}:
          match pair:
            case (file, Fail{(code, message)}):
              close.failed.source(file, temporary, source,
                Backup.SourceFailure{code, message})
            case (file, Done{Unit{}}):
              loop(rest, destination, temporary, Need{file, source, stream})

def close.failed.snapshot.no_file(
  session: Client.Session,
  snapshot_id: U32
) -> IO(Unit):
  do IO<Unit>:
    _closed : Client.Session & Result<&1, &1, Client.Error, Unit> <-
      ByteClient.snapshot.close(session, snapshot_id)
    return Unit{}

def close.failed.source.no_file.cursor(
  pair: Client.Session & Result<&1, &1, Client.Error, Unit>,
  snapshot_id: U32
) -> IO(Unit):
  match pair:
    case (session, _): close.failed.snapshot.no_file(session, snapshot_id)

def close.failed.source.no_file(source: OwnerSource) -> IO(Unit):
  match source:
    case OwnerSource{session, snapshot_id, cursor_id, cursor_live}:
      match cursor_live:
        case True{}:
          do IO<Unit>:
            closed : Client.Session &
              Result<&1, &1, Client.Error, Unit> <-
                ByteClient.snapshot.cursor.close(session, cursor_id)
            close.failed.source.no_file.cursor(closed, snapshot_id)
        case False{}:
          close.failed.snapshot.no_file(session, snapshot_id)

def error.io(pair: U32 & String) -> BackupIo.Error:
  match pair:
    case (17, _): BackupIo.AlreadyExists{}
    case (code, message): BackupIo.Io{code, message}

def initial.failed.io(
  initial: BackupCursor.Step,
  pair: U32 & String
) -> IO(Result<&1, &1, BackupIo.Error, Unit>):
  match pair:
    case (code, message):
      BackupCursorIo.initial.failed(initial, BackupIo.Io{code, message})

def file.opened(
  +destination: String,
  +temporary: String,
  source: OwnerSource,
  initial: BackupCursor.Step,
  fuel: Nat,
  opened: Result<&1, &1, U32 & String, File>
) -> IO(Result<&1, &1, BackupIo.Error, Unit>):
  match opened:
    case Fail{error}:
      do IO<Result<&1, &1, BackupIo.Error, Unit>>:
        _closed : Unit <- close.failed.source.no_file(source)
        BackupCursorIo.cleanup(temporary)
        initial.failed.io(initial, error)
    case Done{file}:
      loop(fuel, destination, temporary, Output{file, source, initial})

def directory.created(
  +destination: String,
  +temporary: String,
  source: OwnerSource,
  initial: BackupCursor.Step,
  fuel: Nat,
  created: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, BackupIo.Error, Unit>):
  match created:
    case Fail{error}:
      do IO<Result<&1, &1, BackupIo.Error, Unit>>:
        _closed : Unit <- close.failed.source.no_file(source)
        BackupCursorIo.initial.failed(initial, error.io(error))
    case Done{Unit{}}:
      do IO<Result<&1, &1, BackupIo.Error, Unit>>:
        opened : Result<&1, &1, U32 & String, File> <-
          File.open(BackupCursorIo.path.clone(temporary ++ "/BACKUP"), "w")
        file.opened(destination, temporary, source, initial, fuel, opened)

def destination.checked(
  +destination: String,
  +temporary: String,
  source: OwnerSource,
  initial: BackupCursor.Step,
  fuel: Nat,
  exists: Result<&1, &1, U32 & String, Bool>
) -> IO(Result<&1, &1, BackupIo.Error, Unit>):
  match exists:
    case Fail{error}:
      do IO<Result<&1, &1, BackupIo.Error, Unit>>:
        _closed : Unit <- close.failed.source.no_file(source)
        BackupCursorIo.initial.failed(initial, error.io(error))
    case Done{True{}}:
      do IO<Result<&1, &1, BackupIo.Error, Unit>>:
        _closed : Unit <- close.failed.source.no_file(source)
        BackupCursorIo.initial.failed(initial, BackupIo.AlreadyExists{})
    case Done{False{}}:
      do IO<Result<&1, &1, BackupIo.Error, Unit>>:
        created : Result<&1, &1, U32 & String, Unit> <-
          Fs.make_dir(BackupCursorIo.path.clone(temporary))
        directory.created(destination, temporary, source, initial, fuel,
          created)

# Exports a retained owner cursor through bounded checksummed backup blocks.
def export(
  +destination: String,
  source: OwnerSource,
  entry_count: Nat,
  fuel: Nat
) -> IO(Result<&1, &1, BackupIo.Error, Unit>):
  +temporary = destination ++ ".backup-060.tmp"
  do IO<Result<&1, &1, BackupIo.Error, Unit>>:
    initial : BackupCursor.Step <- IO.pure(BackupCursor.Step,
      BackupCursor.start.owner(entry_count))
    exists : Result<&1, &1, U32 & String, Bool> <-
      Fs.exists(BackupCursorIo.path.clone(destination))
    destination.checked(destination, temporary, source, initial, fuel, exists)

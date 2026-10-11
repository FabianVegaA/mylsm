import Base
import ../../src/ByteDurableDb.bend as ByteDb
import ../../src/ByteMemTable.bend as ByteMemTable
import ../../src/Console.bend as Console
import ../../src/DbLock.bend as DbLock
import ../../src/Fs.bend as Fs
import ../../src/coordinator/Owner.bend as Owner
import ../../src/coordinator/OwnerCursorStore.bend as OwnerCursorStore
import ../../src/coordinator/OwnerSnapshotStore.bend as OwnerSnapshots
import ../../src/coordinator/UnixSocketIo.bend as UnixSocket
import ../../src/scan/VisibleStats.bend as VisibleStats

# Clones a database path for listener setup and retained owner state.
def path.clone.pair.go(path: String, left: String, right: String) -> String & String:
  match path:
    case SNil{}: (String.reverse(left), String.reverse(right))
    case SCon{+character, rest}:
      path.clone.pair.go(rest, SCon{character, left}, SCon{character, right})

# Returns two independently owned database path values.
def path.clone.pair(path: String) -> String & String:
  path.clone.pair.go(path, SNil{}, SNil{})

# Closes the database and removes the endpoint after bind or listen failure.
def failed(
  server: File,
  handle: ByteDb.Handle,
  endpoint: String,
  message: String
) -> IO(Unit):
  do IO<Unit>:
    _server : Unit <- File.close(server)
    _removed : Result<&1, &1, U32 & String, Unit> <- Fs.remove(endpoint)
    _closed : Result<&1, &1, ByteDb.Error, Unit> <- ByteDb.close(handle)
    IO.die(Unit, 1, message)

# Starts the serialized owner request loop after the listener is ready.
def listening(
  pair: File & Result<&1, &1, UnixSocket.Error, Unit>,
  handle: ByteDb.Handle,
  endpoint: String
) -> IO(Unit):
  match pair:
    case (server, Done{Unit{}}):
      Owner.serve.loop(59n,
        Owner.Serving{server, handle, endpoint, 1, OwnerSnapshots.empty(),
          OwnerCursorStore.empty()})
    case (server, Fail{_}): failed(server, handle, endpoint, "owner listen failed")

# Restricts endpoint access before accepting client connections.
def permissions(
  pair: File & Result<&1, &1, U32 & String, Unit>,
  handle: ByteDb.Handle,
  endpoint: String
) -> IO(Unit):
  match pair:
    case (server, Done{Unit{}}):
      do IO<Unit>:
        result : File & Result<&1, &1, UnixSocket.Error, Unit> <-
          UnixSocket.listen(server, 8)
        listening(result, handle, endpoint)
    case (server, Fail{_}):
      failed(server, handle, endpoint, "owner endpoint permissions failed")

# Begins listening only after a successful bind and permission restriction.
def bound(
  endpoints: String & String,
  pair: File & Result<&1, &1, UnixSocket.Error, Unit>,
  handle: ByteDb.Handle
) -> IO(Unit):
  match endpoints:
    case (chmod_path, endpoint):
      match pair:
        case (server, Done{Unit{}}):
          do IO<Unit>:
            result : Result<&1, &1, U32 & String, Unit> <- Fs.chmod(chmod_path, 384)
            permissions((server, result), handle, endpoint)
        case (server, Fail{_}):
          failed(server, handle, endpoint, "owner endpoint bind failed")

# Binds the listener to the database-scoped endpoint.
def bind(
  paths: String & String,
  server: File,
  handle: ByteDb.Handle
) -> IO(Unit):
  match paths:
    case (bind_path, endpoint):
      do IO<Unit>:
        result : File & Result<&1, &1, UnixSocket.Error, Unit> <-
          UnixSocket.bind(server, bind_path)
        bound(path.clone.pair(endpoint), result, handle)

# Creates the listener only after acquiring and recovering the database.
def created(
  paths: String & String,
  result: Result<&1, &1, UnixSocket.Error, File>,
  handle: ByteDb.Handle
) -> IO(Unit):
  match paths:
    case (bind_path, endpoint):
      match result:
        case Done{server}:
          bind(path.clone.pair(bind_path), server, handle)
        case Fail{_}:
          do IO<Unit>:
            _closed : Result<&1, &1, ByteDb.Error, Unit> <- ByteDb.close(handle)
            IO.die(Unit, 1, "owner socket creation failed")

def opened.endpoint(handle: ByteDb.Handle, endpoint: String) -> IO(Unit):
  do IO<Unit>:
    created_result : Result<&1, &1, UnixSocket.Error, File> <- UnixSocket.create()
    created(path.clone.pair(endpoint), created_result, handle)

def opened.handle.paths(
  paths: String & String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  state: ByteDb.HandleState,
  stats: VisibleStats.Stats
) -> IO(Unit):
  match paths:
    case (endpoint_base, handle_path):
      opened.endpoint(ByteDb.Handle{handle_path, lock, table, state, stats},
        endpoint_base ++ "/MYLSM.sock")

# Derives and publishes one endpoint while the handle still owns the lock.
def opened.handle(handle: ByteDb.Handle) -> IO(Unit):
  match handle:
    case ByteDb.Handle{path, lock, table, state, stats}:
      opened.handle.paths(path.clone.pair(path), lock, table, state, stats)

# Proceeds to serving only when database creation and recovery succeed.
def opened(result: Result<&1, &1, ByteDb.Error, ByteDb.Handle>) -> IO(Unit):
  match result:
    case Done{handle}: opened.handle(handle)
    case Fail{_}: IO.die(Unit, 1, "owner database creation failed")

# Creates a database and serves exactly two IPC requests for the smoke test.
def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, ByteDb.Error, ByteDb.Handle> <- ByteDb.create(path)
    opened(result)

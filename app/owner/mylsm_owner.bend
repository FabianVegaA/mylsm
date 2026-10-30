import Base
import ../../src/ByteDurableDb.bend as ByteDb
import ../../src/ByteMemTable.bend as ByteMemTable
import ../../src/Console.bend as Console
import ../../src/DbLock.bend as DbLock
import ../../src/Fs.bend as Fs
import ../../src/coordinator/EndpointPath.bend as EndpointPath
import ../../src/coordinator/Owner.bend as Owner
import ../../src/coordinator/OwnerCursorStore.bend as OwnerCursorStore
import ../../src/coordinator/OwnerSnapshotStore.bend as OwnerSnapshots
import ../../src/coordinator/OwnerGenerationIo.bend as OwnerGenerationIo
import ../../src/coordinator/UnixSocketIo.bend as UnixSocket
import ../../src/scan/VisibleStats.bend as VisibleStats
import ../../src/CrashPoint.bend as CrashPoint
import ../../src/ResourceOptions.bend as ResourceOptions
import ../../src/coordinator/OptionsCodec.bend as OptionsCodec

def owner.arguments(args: List<String>) -> List<String>:
  match args:
    case Nil{}: Nil{}
    case Con{_, rest}: rest

def owner.options(args: List<String>) -> OptionsCodec.Decision:
  match args:
    case Nil{}: OptionsCodec.Parsed{ResourceOptions.defaults()}
    case Con{"--resource-options-v1", Con{hex, Nil{}}}:
      OptionsCodec.decode.hex(hex)
    case _: OptionsCodec.Malformed{}

# Closes the database handle before terminating owner startup or service.
def stop(handle: ByteDb.Handle, message: String) -> IO(Unit):
  do IO<Unit>:
    _closed : Result<&1, &1, ByteDb.Error, Unit> <- ByteDb.close(handle)
    IO.die(Unit, 1, message)

def path.clone.pair.go(path: String, left: String, right: String) -> String & String:
  match path:
    case SNil{}: (String.reverse(left), String.reverse(right))
    case SCon{+character, rest}:
      path.clone.pair.go(rest, SCon{character, left}, SCon{character, right})

def path.clone.pair(path: String) -> String & String:
  path.clone.pair.go(path, SNil{}, SNil{})

def start.nonblocking(
  handle: ByteDb.Handle,
  endpoint: String,
  generation: U32,
  options: ResourceOptions.Options,
  result: File & Result<&1, &1, UnixSocket.Error, Unit>
) -> IO(Unit):
  match result:
    case (server, Done{Unit{}}):
      do IO<Unit>:
        _checkpoint : Result<&1, &1, U32 & String, Unit> <-
          CrashPoint.hit("owner.endpoint_published")
        Owner.serve.loop(4294967295n,
          Owner.ReactorServing{server, handle, endpoint, generation, options,
            OwnerSnapshots.empty(), OwnerCursorStore.empty(), Nil{}, 1, 0n,
            Owner.reactor.queue.empty()})
    case (server, Fail{_}):
      do IO<Unit>:
        _closed : Unit <- File.close(server)
        _removed : Result<&1, &1, U32 & String, Unit> <- Fs.remove(endpoint)
        stop(handle, "owner listener could not be set to nonblocking mode")

def start.listening(
  handle: ByteDb.Handle,
  endpoint: String,
  generation: U32,
  options: ResourceOptions.Options,
  result: File & Result<&1, &1, UnixSocket.Error, Unit>
) -> IO(Unit):
  match result:
    case (server, Done{Unit{}}):
      do IO<Unit>:
        nonblocking : File & Result<&1, &1, UnixSocket.Error, Unit> <-
          UnixSocket.nonblocking(server)
        start.nonblocking(handle, endpoint, generation, options, nonblocking)
    case (server, Fail{_}):
      do IO<Unit>:
        _closed : Unit <- File.close(server)
        _removed : Result<&1, &1, U32 & String, Unit> <- Fs.remove(endpoint)
        stop(handle, "owner listen failed")

def start.permissions(
  handle: ByteDb.Handle,
  endpoint: String,
  generation: U32,
  options: ResourceOptions.Options,
  server: File,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Unit):
  match result:
    case Done{Unit{}}:
      do IO<Unit>:
        listened : File & Result<&1, &1, UnixSocket.Error, Unit> <-
          UnixSocket.listen(server, 64)
        start.listening(handle, endpoint, generation, options, listened)
    case Fail{_}:
      do IO<Unit>:
        _closed : Unit <- File.close(server)
        _removed : Result<&1, &1, U32 & String, Unit> <- Fs.remove(endpoint)
        stop(handle, "owner socket permissions could not be restricted")

def start.bound.paths(
  handle: ByteDb.Handle,
  generation: U32,
  options: ResourceOptions.Options,
  server: File,
  paths: String & String
) -> IO(Unit):
  match paths:
    case (chmod_path, listener_path):
      do IO<Unit>:
        permissions : Result<&1, &1, U32 & String, Unit> <- Fs.chmod(chmod_path, 384)
        start.permissions(handle, listener_path, generation, options, server,
          permissions)

def start.bound(
  handle: ByteDb.Handle,
  endpoint: String,
  generation: U32,
  options: ResourceOptions.Options,
  result: File & Result<&1, &1, UnixSocket.Error, Unit>
) -> IO(Unit):
  match result:
    case (server, Done{Unit{}}):
      start.bound.paths(handle, generation, options, server,
        path.clone.pair(endpoint))
    case (server, Fail{_}):
      do IO<Unit>:
        _closed : Unit <- File.close(server)
        _removed : Result<&1, &1, U32 & String, Unit> <- Fs.remove(endpoint)
        stop(handle, "owner socket bind failed")

def start.socket.bind(
  handle: ByteDb.Handle,
  generation: U32,
  options: ResourceOptions.Options,
  server: File,
  paths: String & String
) -> IO(Unit):
  match paths:
    case (bind_path, retained_path):
      do IO<Unit>:
        bound : File & Result<&1, &1, UnixSocket.Error, Unit> <-
          UnixSocket.bind(server, bind_path)
        start.bound(handle, retained_path, generation, options, bound)

def start.socket(
  handle: ByteDb.Handle,
  endpoint: String,
  generation: U32,
  options: ResourceOptions.Options,
  result: Result<&1, &1, UnixSocket.Error, File>
) -> IO(Unit):
  match result:
    case Done{server}:
      start.socket.bind(handle, generation, options, server,
        path.clone.pair(endpoint))
    case Fail{_}: stop(handle, "owner socket creation failed")

def endpoint.ready(
  handle: ByteDb.Handle,
  generation: U32,
  options: ResourceOptions.Options,
  result: EndpointPath.Decision
) -> IO(Unit):
  match result:
    case EndpointPath.Endpoint{path}:
      do IO<Unit>:
        created : Result<&1, &1, UnixSocket.Error, File> <- UnixSocket.create()
        start.socket(handle, path, generation, options, created)
    case EndpointPath.PathTooLong{}:
      stop(handle, "owner socket path exceeds the platform limit")

def stale.removal.result(
  handle: ByteDb.Handle,
  endpoint: String,
  generation: U32,
  options: ResourceOptions.Options,
  removed: Result<&1, &1, U32 & String, Unit>
) -> IO(Unit):
  match removed:
    case Fail{_}: stop(handle, "stale owner endpoint could not be removed")
    case Done{Unit{}}:
      do IO<Unit>:
        created : Result<&1, &1, UnixSocket.Error, File> <- UnixSocket.create()
        start.socket(handle, endpoint, generation, options, created)

def stale.removing(
  handle: ByteDb.Handle,
  generation: U32,
  options: ResourceOptions.Options,
  paths: String & String
) -> IO(Unit):
  match paths:
    case (remove_path, retained_path):
      do IO<Unit>:
        removed : Result<&1, &1, U32 & String, Unit> <- Fs.remove(remove_path)
        stale.removal.result(handle, retained_path, generation, options,
          removed)

def stale.removed(
  handle: ByteDb.Handle,
  endpoint: String,
  generation: U32,
  options: ResourceOptions.Options,
  exists: Result<&1, &1, U32 & String, Bool>
) -> IO(Unit):
  match exists:
    case Fail{_}: stop(handle, "owner endpoint inspection failed")
    case Done{False{}}:
      do IO<Unit>:
        created : Result<&1, &1, UnixSocket.Error, File> <- UnixSocket.create()
        start.socket(handle, endpoint, generation, options, created)
    case Done{True{}}:
      stale.removing(handle, generation, options, path.clone.pair(endpoint))

def owner.endpoint.exists(
  handle: ByteDb.Handle,
  generation: U32,
  options: ResourceOptions.Options,
  paths: String & String
) -> IO(Unit):
  match paths:
    case (endpoint, inspect_path):
      do IO<Unit>:
        exists : Result<&1, &1, U32 & String, Bool> <- Fs.exists(inspect_path)
        stale.removed(handle, endpoint, generation, options, exists)

def owner.endpoint(
  handle: ByteDb.Handle,
  generation: U32,
  options: ResourceOptions.Options,
  result: EndpointPath.Decision
) -> IO(Unit):
  match result:
    case EndpointPath.Endpoint{path}:
      owner.endpoint.exists(handle, generation, options,
        path.clone.pair(path))
    case EndpointPath.PathTooLong{}:
      stop(handle, "owner socket path exceeds the platform limit")

def owner.handle(
  handle: ByteDb.Handle,
  generation: U32,
  options: ResourceOptions.Options,
  endpoint_path: String
) -> IO(Unit):
  owner.endpoint(handle, generation, options,
    EndpointPath.for_canonical_path(endpoint_path))

def opened.generation.result(
  handle: ByteDb.Handle,
  endpoint_path: String,
  options: ResourceOptions.Options,
  result: Result<&1, &1, OwnerGenerationIo.Error, U32>
) -> IO(Unit):
  match result:
    case Done{generation}:
      do IO<Unit>:
        _checkpoint : Result<&1, &1, U32 & String, Unit> <-
          CrashPoint.hit("owner.after_generation")
        owner.handle(handle, generation, options, endpoint_path)
    case Fail{_}:
      do IO<Unit>:
        _closed : Result<&1, &1, ByteDb.Error, Unit> <- ByteDb.close(handle)
        IO.die(Unit, 1, "owner generation could not be persisted")

def opened.generation.paths(
  paths: String & String,
  endpoint_path: String,
  options: ResourceOptions.Options,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  state: ByteDb.HandleState,
  stats: VisibleStats.Stats
) -> IO(Unit):
  match paths:
    case (generation_path, handle_path):
      do IO<Unit>:
        generation : Result<&1, &1, OwnerGenerationIo.Error, U32> <-
          OwnerGenerationIo.initialize(generation_path)
        opened.generation.result(ByteDb.Handle{handle_path, lock, table,
          state, stats}, endpoint_path, options, generation)

def opened.canonical(
  paths: String & String,
  options: ResourceOptions.Options,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  state: ByteDb.HandleState,
  stats: VisibleStats.Stats
) -> IO(Unit):
  match paths:
    case (endpoint_path, handle_path):
      opened.generation.paths(path.clone.pair(handle_path), endpoint_path,
        options, lock, table, state, stats)

# Publishes the canonical endpoint only after recovery has opened the database.
def opened.with.options(
  result: Result<&1, &1, ByteDb.Error, ByteDb.Handle>,
  options: ResourceOptions.Options
) -> IO(Unit):
  match result:
    case Done{ByteDb.Handle{path, lock, table, state, stats}}:
      do IO<Unit>:
        _checkpoint : Result<&1, &1, U32 & String, Unit> <-
          CrashPoint.hit("owner.after_lock")
        opened.canonical(ByteDb.path.clone.pair(path), options, lock, table,
          state, stats)
    case Fail{_}: IO.die(Unit, 1, "owner failed to acquire and recover the database")

def owner.start.selected(
  path: String,
  options: OptionsCodec.Decision
) -> IO(Unit):
  match options:
    case OptionsCodec.Parsed{options}:
      do IO<Unit>:
        handle : Result<&1, &1, ByteDb.Error, ByteDb.Handle> <-
          ByteDb.open_existing_wait(path, 5000, 25)
        opened.with.options(handle, options)
    case _: IO.die(Unit, 2, "owner resource options are invalid")

def owner.start(path: String, args: List<String>) -> IO(Unit):
  owner.start.selected(path, owner.options(owner.arguments(args)))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    owner.start(path, args)

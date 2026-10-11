import Base
import ../../src/ByteDurableDb.bend as ByteDb
import ../../src/Console.bend as Console
import ../../src/coordinator/Operation.bend as Operation
import ../../src/coordinator/Owner.bend as Owner
import ../../src/coordinator/Protocol.bend as Protocol
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

def bytes.parsed(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}: bytes
    case None{}: Bytes.new(0)

# Returns the decoded payload or an empty byte sequence for absent input.
def bytes(hex: String) -> Bytes.Bytes:
  bytes.parsed(Bytes.from_hex(hex))

def bytes.equal(pair: Bytes.Bytes & Bytes.Bytes & Bool) -> Bool:
  match pair:
    case (_, _, equal): equal

# Requires the owner service to complete its ordered shutdown.
def closed(result: Result<&1, &1, ByteDb.Error, Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.print("OWNER_DISPATCH_PASSED")
    case Fail{_}: IO.die(Unit, 1, "owner dispatch database close failed")

def fail.close(handle: ByteDb.Handle, message: String) -> IO(Unit):
  do IO<Unit>:
    _closed : Result<&1, &1, ByteDb.Error, Unit> <- ByteDb.close(handle)
    IO.die(Unit, 1, message)

def response.missing(pair: ByteDb.Handle & Protocol.Response) -> IO(Unit):
  match pair:
    case (handle, Protocol.Response{_, _, _, Protocol.NotFound{}, _}):
      do IO<Unit>:
        result : Result<&1, &1, ByteDb.Error, Unit> <- ByteDb.close(handle)
        closed(result)
    case (handle, _):
      fail.close(handle, "owner delete did not hide the key")

# Confirms a dispatched delete response and verifies the key is absent.
def deleted(pair: ByteDb.Handle & Protocol.Response) -> IO(Unit):
  match pair:
    case (handle, Protocol.Response{_, _, _, Protocol.Success{}, _}):
      do IO<Unit>:
        result : ByteDb.Handle & Protocol.Response <- Owner.dispatch.request(
          handle, Protocol.Request{1, 1, 5, 1, bytes("00ff")}, 1)
        response.missing(result)
    case (handle, _):
      fail.close(handle, "owner delete operation failed")

def stats.matches(handle: ByteDb.Handle, matches: Bool) -> IO(Unit):
  match matches:
    case True{}:
      do IO<Unit>:
        result : ByteDb.Handle & Protocol.Response <- Owner.dispatch.request(
          handle, Protocol.Request{1, 1, 4, 3, bytes("00ff")}, 1)
        deleted(result)
    case False{}:
      fail.close(handle, "owner stats payload differs")

def stats.response(pair: ByteDb.Handle & Protocol.Response) -> IO(Unit):
  match pair:
    case (handle, Protocol.Response{_, _, _, Protocol.Success{}, payload}):
      stats.matches(handle, bytes.equal(Bytes.eq(payload, bytes("313a35"))))
    case (handle, _):
      fail.close(handle, "owner stats operation failed")

def stats.checked(pair: ByteDb.Handle & ByteDb.Stats) -> IO(Unit):
  match pair:
    case (handle, stats):
      do IO<Unit>:
        result : ByteDb.Handle & Protocol.Response <- IO.pure(
          ByteDb.Handle & Protocol.Response,
          Owner.stats.response(handle, stats,
            Owner.ReplyContext{(1, 1), (1, 1), (3, 3)}))
        stats.response(result)

def read.matches(handle: ByteDb.Handle, matches: Bool) -> IO(Unit):
  match matches:
    case True{}:
      do IO<Unit>:
        stats : ByteDb.Handle & ByteDb.Stats <- IO.pure(
          ByteDb.Handle & ByteDb.Stats, ByteDb.stats(handle))
        stats.checked(stats)
    case False{}:
      fail.close(handle, "owner get changed binary value")

def read.response(pair: ByteDb.Handle & Protocol.Response) -> IO(Unit):
  match pair:
    case (handle, Protocol.Response{_, _, _, Protocol.Success{}, payload}):
      read.matches(handle, bytes.equal(Bytes.eq(payload, bytes("80ff00"))))
    case (handle, _):
      fail.close(handle, "owner get operation failed")

# Confirms a dispatched put response and verifies its durable value.
def written(pair: ByteDb.Handle & Protocol.Response) -> IO(Unit):
  match pair:
    case (handle, Protocol.Response{_, _, _, Protocol.Success{}, _}):
      do IO<Unit>:
        result : ByteDb.Handle & Protocol.Response <- Owner.dispatch.request(
          handle, Protocol.Request{1, 1, 2, 1, bytes("00ff")}, 1)
        read.response(result)
    case (handle, _):
      fail.close(handle, "owner put operation failed")

# Starts the owner dispatch fixture with a recovered durable database.
def created(result: Result<&1, &1, ByteDb.Error, ByteDb.Handle>) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        response : ByteDb.Handle & Protocol.Response <- Owner.dispatch.request(
          handle, Protocol.Request{1, 1, 1, 2,
            Operation.encode.put(bytes("00ff"), bytes("80ff00"))}, 1)
        written(response)
    case Fail{_}: IO.die(Unit, 1, "owner dispatch database creation failed")

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, ByteDb.Error, ByteDb.Handle> <- ByteDb.create(path)
    created(result)

import Base
import ../../mylsm.bend as MyLSM
import ../../src/Console.bend as Console
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

def bytes.from_hex.result(result: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match result:
    case Some{value}: value
    case None{}: Bytes.new(0)

def bytes.from_hex(value: String) -> Bytes.Bytes:
  bytes.from_hex.result(Bytes.from_hex(value))

# Stops the fixture after a public routing or value assertion fails.
def fail(message: String) -> IO(Unit):
  IO.die(Unit, 1, message)

def finish.closed(result: Result<&1, &1, MyLSM.Bytes.Error, Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.print("PUBLIC_COORDINATOR_CLIENT_PASSED")
    case Fail{_}: fail("public coordinator client close failed")

def flush.result(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        finish.closed(closed)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        fail("public coordinator client flush failed")

def stats.valid(entries: Nat, payload_bytes: Nat) -> Bool:
  Nat.is_eq(entries, 4n) && Nat.is_eq(payload_bytes, 17n)

def stats.checked(handle: MyLSM.Bytes.Handle, valid: Bool) -> IO(Unit):
  match valid:
    case True{}:
      do IO<Unit>:
        flushed : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error,
          Unit> <- MyLSM.Bytes.flush(handle)
        flush.result(flushed)
    case False{}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        fail("public coordinator client stats did not match writes")

def stats.result(pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Stats>) -> IO(Unit):
  match pair:
    case (handle, Done{MyLSM.ByteStats{entries, payload_bytes}}):
      stats.checked(handle, stats.valid(entries, payload_bytes))
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        fail("public coordinator client stats failed")

def stats.request(handle: MyLSM.Bytes.Handle) -> IO(Unit):
  do IO<Unit>:
    pair : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error,
      MyLSM.Bytes.Stats> <- MyLSM.Bytes.stats(handle)
    stats.result(pair)

def value.valid(pair: Bytes.Bytes & Bytes.Bytes & Bool) -> Bool:
  match pair:
    case (_, (_, equal)): equal

def get.checked(handle: MyLSM.Bytes.Handle, valid: Bool) -> IO(Unit):
  match valid:
    case True{}: stats.request(handle)
    case False{}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        fail("public coordinator client changed binary bytes")

def get.result(pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, Bytes.Bytes>>) -> IO(Unit):
  match pair:
    case (handle, Done{Some{value}}):
      get.checked(handle,
        value.valid(Bytes.eq(value, bytes.from_hex("80ff"))))
    case (handle, _):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        fail("public coordinator client could not read its binary key")

def put.result(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        read : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error,
          Maybe<&1, Bytes.Bytes>> <-
            MyLSM.Bytes.get(handle, bytes.from_hex("02ff"))
        get.result(read)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        fail("public coordinator client put failed")

# Opens through the public facade while the owner holds the database lock.
def opened(result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        written : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error,
          Unit> <- MyLSM.Bytes.put(handle, bytes.from_hex("02ff"),
            bytes.from_hex("80ff"))
        put.result(written)
    case Fail{_}: fail("public coordinator client could not open owner")

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
      MyLSM.Bytes.open_existing_wait(path, 1000, 10)
    opened(result)

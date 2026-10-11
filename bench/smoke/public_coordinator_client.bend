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

def put.start(handle: MyLSM.Bytes.Handle) -> IO(Unit):
  do IO<Unit>:
    written : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error,
      Unit> <- MyLSM.Bytes.put(handle, bytes.from_hex("02ff"),
        bytes.from_hex("80ff"))
    put.result(written)

def scan.step(frame: MyLSM.Bytes.StreamStep) -> MyLSM.Bytes.ScanStep:
  match frame:
    case MyLSM.StreamItem{key, value, cursor}:
      MyLSM.ScanItem{key, value, cursor}
    case MyLSM.StreamSkip{cursor}: MyLSM.ScanSkip{cursor}
    case MyLSM.StreamEnd{cursor}: MyLSM.ScanEnd{cursor}
    case MyLSM.StreamFailure{error, cursor}: MyLSM.ScanFailure{error, cursor}

def snapshot.cursor.second.checked(
  handle: MyLSM.Bytes.Handle,
  snapshot: MyLSM.Bytes.Snapshot,
  cursor: MyLSM.Bytes.Cursor,
  valid: Bool
) -> IO(Unit):
  match valid:
    case True{}:
      do IO<Unit>:
        _cursor : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.scan_close(cursor)
        _snapshot : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.snapshot.close(snapshot)
        put.start(handle)
    case False{}: fail("remote snapshot cursor changed its second item")

def snapshot.cursor.second.read(
  handle: MyLSM.Bytes.Handle,
  snapshot: MyLSM.Bytes.Snapshot,
  step: MyLSM.Bytes.StreamStep
) -> IO(Unit):
  match step:
    case MyLSM.StreamItem{key, value, cursor}:
      snapshot.cursor.second.checked(handle, snapshot, cursor,
        value.valid(Bytes.eq(key, bytes.from_hex("0103"))) &&
          value.valid(Bytes.eq(value, bytes.from_hex("aabb"))))
    case _: fail("remote snapshot cursor ended before the second item")

def snapshot.cursor.second(
  handle: MyLSM.Bytes.Handle,
  snapshot: MyLSM.Bytes.Snapshot,
  cursor: MyLSM.Bytes.Cursor,
  closed: Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match closed:
    case Fail{MyLSM.Busy{}}:
      do IO<Unit>:
        next : MyLSM.Bytes.StreamStep <- MyLSM.Bytes.scan_next(cursor)
        snapshot.cursor.second.read(handle, snapshot, next)
    case _: fail("owner closed a snapshot with a live cursor")

def snapshot.cursor.first.cloned(
  handle: MyLSM.Bytes.Handle,
  cursor: MyLSM.Bytes.Cursor,
  snapshots: MyLSM.Bytes.Snapshot & MyLSM.Bytes.Snapshot
) -> IO(Unit):
  match snapshots:
    case (for_close, for_continue):
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.snapshot.close(for_close)
        snapshot.cursor.second(handle, for_continue, cursor, closed)

def snapshot.cursor.first.checked(
  handle: MyLSM.Bytes.Handle,
  snapshot: MyLSM.Bytes.Snapshot,
  cursor: MyLSM.Bytes.Cursor,
  valid: Bool
) -> IO(Unit):
  match valid:
    case True{}:
      snapshot.cursor.first.cloned(handle, cursor,
        MyLSM.Bytes.snapshot.clone(snapshot))
    case False{}: fail("remote snapshot cursor changed its first item")

def snapshot.cursor.first(
  handle: MyLSM.Bytes.Handle,
  snapshot: MyLSM.Bytes.Snapshot,
  step: MyLSM.Bytes.ScanStep
) -> IO(Unit):
  match step:
    case MyLSM.ScanItem{key, value, cursor}:
      snapshot.cursor.first.checked(handle, snapshot, cursor,
        value.valid(Bytes.eq(key, bytes.from_hex("00ff"))) &&
          value.valid(Bytes.eq(value, bytes.from_hex("80ff00"))))
    case _: fail("remote snapshot cursor returned no first item")

def snapshot.cursor.opened(
  handle: MyLSM.Bytes.Handle,
  pair: MyLSM.Bytes.Snapshot & Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Cursor>
) -> IO(Unit):
  match pair:
    case (snapshot, Done{cursor}):
      do IO<Unit>:
        first : MyLSM.Bytes.StreamStep <- MyLSM.Bytes.scan_next(cursor)
        snapshot.cursor.first(handle, snapshot, scan.step(first))
    case _: fail("public owner snapshot cursor could not open")

def snapshot.read.checked(
  handle: MyLSM.Bytes.Handle,
  snapshot: MyLSM.Bytes.Snapshot,
  valid: Bool
) -> IO(Unit):
  match valid:
    case True{}:
      do IO<Unit>:
        opened : MyLSM.Bytes.Snapshot &
          Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Cursor> <-
            MyLSM.Bytes.snapshot.scan_range(snapshot, None{}, None{})
        snapshot.cursor.opened(handle, opened)
    case False{}: fail("public owner snapshot changed the binary value")

def snapshot.read(
  handle: MyLSM.Bytes.Handle,
  pair: MyLSM.Bytes.Snapshot & Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, Bytes.Bytes>>
) -> IO(Unit):
  match pair:
    case (snapshot, Done{Some{value}}):
      snapshot.read.checked(handle, snapshot,
        value.valid(Bytes.eq(value, bytes.from_hex("80ff00"))))
    case _: fail("public owner snapshot omitted the binary value")

def snapshot.opened(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Snapshot>
) -> IO(Unit):
  match pair:
    case (handle, Done{snapshot}):
      do IO<Unit>:
        read : MyLSM.Bytes.Snapshot &
          Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, Bytes.Bytes>> <-
            MyLSM.Bytes.snapshot.get(snapshot, bytes.from_hex("00ff"))
        snapshot.read(handle, read)
    case (_, Fail{_}): fail("public owner snapshot could not open")

# Opens through the public facade while the owner holds the database lock.
def opened(result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        snapshot : MyLSM.Bytes.Handle &
          Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Snapshot> <-
            MyLSM.Bytes.snapshot(handle)
        snapshot.opened(snapshot)
    case Fail{_}: fail("public coordinator client could not open owner")

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
      MyLSM.Bytes.open_existing_wait(path, 1000, 10)
    opened(result)

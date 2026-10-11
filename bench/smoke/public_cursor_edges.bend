import Base
import ../../mylsm.bend as MyLSM
import ../../src/Console.bend as Console
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Unwraps a valid hexadecimal fixture buffer.
def parsed(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}: bytes
    case None{}: Bytes.new(0)

# Decodes a closed hexadecimal fixture value.
def bytes(hex: String) -> Bytes.Bytes:
  parsed(Bytes.from_hex(hex))

# Stops the fixture after a failed assertion.
def fail(message: String) -> IO(Unit):
  IO.die(Unit, 1, message)

def byte.length.result(pair: Bytes.Bytes & U32) -> U32:
  match pair:
    case (_, length): length

def byte.length(bytes: Bytes.Bytes) -> U32:
  byte.length.result(Bytes.length(bytes))

def close.handle(result: Result<&1, &1, MyLSM.Bytes.Error, Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.print("PUBLIC_CURSOR_EDGES_PASSED")
    case Fail{_}: fail("public cursor edge fixture failed to close database")

def empty_prefix.closed(
  handle: MyLSM.Bytes.Handle,
  result: Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match result:
    case Done{Unit{}}:
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        close.handle(closed)
    case Fail{_}: fail("empty-prefix cursor failed to close")

def prefix.item.key(
  handle: MyLSM.Bytes.Handle,
  cursor: MyLSM.Bytes.Cursor,
  length: U32
) -> IO(Unit):
  match length:
    case 0:
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.scan_close(cursor)
        empty_prefix.closed(handle, closed)
    case _:
      do IO<Unit>:
        _cursor : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.scan_close(cursor)
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        fail("empty-prefix scan omitted the empty key")

def prefix.item(
  fuel: Nat,
  handle: MyLSM.Bytes.Handle,
  result: MyLSM.Bytes.StreamStep
) -> IO(Unit):
  match fuel result:
    case _, MyLSM.StreamItem{key, _, cursor}:
      prefix.item.key(handle, cursor, byte.length(key))
    case _, MyLSM.StreamEnd{cursor}:
      do IO<Unit>:
        _cursor : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.scan_close(cursor)
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        fail("empty-prefix scan ended before returning the empty key")
    case _, MyLSM.StreamFailure{_, _}: fail("empty-prefix scan failed")
    case 0n, MyLSM.StreamSkip{_}: fail("empty-prefix scan exceeded its skip budget")
    case 1n+rest, MyLSM.StreamSkip{cursor}:
      do IO<Unit>:
        next : MyLSM.Bytes.StreamStep <- MyLSM.Bytes.scan_next(cursor)
        prefix.item(rest, handle, next)

def empty_prefix.opened(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Cursor>
) -> IO(Unit):
  match pair:
    case (handle, Done{cursor}):
      do IO<Unit>:
        first : MyLSM.Bytes.StreamStep <- MyLSM.Bytes.scan_next(cursor)
        prefix.item(64n, handle, first)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        fail("empty-prefix scan did not open")

def empty_range.closed(
  handle: MyLSM.Bytes.Handle,
  result: Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match result:
    case Done{Unit{}}:
      do IO<Unit>:
        prefix : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error,
          MyLSM.Bytes.Cursor> <- MyLSM.Bytes.scan_prefix(handle, Bytes.new(0))
        empty_prefix.opened(prefix)
    case Fail{_}: fail("empty-range cursor failed to close")

def empty_range.next(
  fuel: Nat,
  handle: MyLSM.Bytes.Handle,
  result: MyLSM.Bytes.StreamStep
) -> IO(Unit):
  match fuel result:
    case _, MyLSM.StreamEnd{cursor}:
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.scan_close(cursor)
        empty_range.closed(handle, closed)
    case _, MyLSM.StreamItem{_, _, cursor}:
      do IO<Unit>:
        _cursor : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.scan_close(cursor)
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        fail("equal range bounds returned an item")
    case _, MyLSM.StreamFailure{_, _}: fail("equal range bounds failed")
    case 0n, MyLSM.StreamSkip{_}: fail("equal-range scan exceeded its skip budget")
    case 1n+rest, MyLSM.StreamSkip{cursor}:
      do IO<Unit>:
        next : MyLSM.Bytes.StreamStep <- MyLSM.Bytes.scan_next(cursor)
        empty_range.next(rest, handle, next)

def empty_range.opened(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Cursor>
) -> IO(Unit):
  match pair:
    case (handle, Done{cursor}):
      do IO<Unit>:
        first : MyLSM.Bytes.StreamStep <- MyLSM.Bytes.scan_next(cursor)
        empty_range.next(64n, handle, first)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        fail("equal-bound scan did not open")

# Reopens the flushed database before testing public cursor edges.
def reopened(result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        cursor : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error,
          MyLSM.Bytes.Cursor> <- MyLSM.Bytes.scan_range(handle, Some{bytes("00")}, Some{bytes("00")})
        empty_range.opened(cursor)
    case Fail{_}: fail("cursor edge database reopen failed")

def writer.closed(result: Result<&1, &1, MyLSM.Bytes.Error, Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}:
      do IO<Unit>:
        path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
        opened : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
          MyLSM.Bytes.open_existing(path)
        reopened(opened)
    case Fail{_}: fail("cursor edge fixture writer close failed")

# Closes the writer before opening the persisted SST path.
def flushed(pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        writer.closed(closed)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        fail("cursor edge fixture flush failed")

# Publishes the seeded records before the recovery assertions.
def seeded(pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        result : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.flush(handle)
        flushed(result)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        fail("cursor edge fixture writes failed")

# Writes the empty, zero-byte, and nonempty keys to the fixture database.
def created(result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        written : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.write_batch(handle, Con{
            MyLSM.BytesPut{Bytes.new(0), Bytes.new(0)},
            Con{MyLSM.BytesPut{bytes("00"), bytes("31")},
              Con{MyLSM.BytesPut{bytes("61"), bytes("32")}, Nil{}}}})
        seeded(written)
    case Fail{_}: fail("cursor edge fixture database create failed")

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <- MyLSM.Bytes.create(path)
    created(result)

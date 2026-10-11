import Base
import ../../mylsm.bend as MyLSM
import ../../src/Console.bend as Console
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Decodes closed hexadecimal fixture keys and values.
def bytes.parsed(result: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match result:
    case Some{value}: value
    case None{}: Bytes.new(0)

# Decodes a closed hexadecimal fixture.
def bytes(hex: String) -> Bytes.Bytes:
  bytes.parsed(Bytes.from_hex(hex))

# Extracts the equality result while consuming temporary byte copies.
def bytes.eq.result(result: Bytes.Bytes & Bytes.Bytes & Bool) -> Bool:
  match result:
    case (_, _, equal): equal

def bytes.equal(left: Bytes.Bytes, right: Bytes.Bytes) -> Bool:
  bytes.eq.result(Bytes.eq(left, right))

# Stops the fixture after a failed public cursor assertion.
def fail(message: String) -> IO(Unit):
  IO.die(Unit, 1, message)

# Closes both the scan reader and database owner after terminal End.
# Checks database ownership release after cursor closure.
def finish.handle(result: Result<&1, &1, MyLSM.Bytes.Error, Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.print("PUBLIC_BYTES_SST_CURSOR_PASSED")
    case Fail{_}: fail("public SST cursor database close failed")

def prefix.closed(
  handle: MyLSM.Bytes.Handle,
  result: Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match result:
    case Fail{_}: fail("public SST prefix cursor did not close")
    case Done{Unit{}}:
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        finish.handle(closed)

def prefix.end(
  fuel: Nat,
  handle: MyLSM.Bytes.Handle,
  result: MyLSM.Bytes.StreamStep
) -> IO(Unit):
  match fuel result:
    case _, MyLSM.StreamEnd{cursor}:
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.scan_close(cursor)
        prefix.closed(handle, closed)
    case _, MyLSM.StreamFailure{_, _}: fail("public SST prefix failed after its visible key")
    case _, MyLSM.StreamItem{_, _, cursor}:
      do IO<Unit>:
        _cursor : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.scan_close(cursor)
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        fail("public SST prefix emitted an unexpected second key")
    case 0n, MyLSM.StreamSkip{_}: fail("public SST prefix exceeded its skip budget")
    case 1n+rest, MyLSM.StreamSkip{cursor}:
      do IO<Unit>:
        next : MyLSM.Bytes.StreamStep <- MyLSM.Bytes.scan_next(cursor)
        prefix.end(rest, handle, next)

def prefix.item.result(
  handle: MyLSM.Bytes.Handle,
  cursor: MyLSM.Bytes.Cursor,
  valid: Bool
) -> IO(Unit):
  match valid:
    case True{}:
      do IO<Unit>:
        next : MyLSM.Bytes.StreamStep <- MyLSM.Bytes.scan_next(cursor)
        prefix.end(64n, handle, next)
    case False{}: fail("public SST prefix returned the wrong byte item")

def prefix.item(
  fuel: Nat,
  handle: MyLSM.Bytes.Handle,
  step: MyLSM.Bytes.StreamStep
) -> IO(Unit):
  match fuel step:
    case _, MyLSM.StreamItem{key, value, cursor}:
      prefix.item.result(handle, cursor,
        Bool.and(bytes.equal(key, bytes("62")), bytes.equal(value, bytes("6e6577"))))
    case _, MyLSM.StreamFailure{_, _}: fail("public SST prefix cursor failed")
    case 0n, MyLSM.StreamSkip{_}: fail("public SST prefix exceeded its skip budget")
    case 1n+rest, MyLSM.StreamSkip{cursor}:
      do IO<Unit>:
        next : MyLSM.Bytes.StreamStep <- MyLSM.Bytes.scan_next(cursor)
        prefix.item(rest, handle, next)
    case _, _: fail("public SST prefix omitted its matching key")

def prefix.opened(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Cursor>
) -> IO(Unit):
  match pair:
    case (handle, Done{cursor}):
      do IO<Unit>:
        step : MyLSM.Bytes.StreamStep <- MyLSM.Bytes.scan_next(cursor)
        prefix.item(64n, handle, step)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        fail("public SST prefix scan did not open")

# Runs the prefix scan after the bounded range cursor closes successfully.
def finish(
  handle: MyLSM.Bytes.Handle,
  closed: Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match closed:
    case Fail{_}: fail("public SST cursor close failed")
    case Done{Unit{}}:
      do IO<Unit>:
        pair : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Cursor> <-
          MyLSM.Bytes.scan_prefix(handle, bytes("62"))
        prefix.opened(pair)

def after.end(
  fuel: Nat,
  handle: MyLSM.Bytes.Handle,
  result: MyLSM.Bytes.StreamStep
) -> IO(Unit):
  match fuel result:
    case _, MyLSM.StreamEnd{cursor}:
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.scan_close(cursor)
        finish(handle, closed)
    case _, MyLSM.StreamFailure{_, _}: fail("public SST cursor failed after its retained suffix")
    case _, MyLSM.StreamItem{_, _, cursor}:
      do IO<Unit>:
        _cursor : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.scan_close(cursor)
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        fail("public SST cursor emitted a duplicate after the retained suffix")
    case 0n, MyLSM.StreamSkip{_}: fail("cursor suffix exceeded its skip budget")
    case 1n+rest, MyLSM.StreamSkip{cursor}:
      do IO<Unit>:
        next : MyLSM.Bytes.StreamStep <- MyLSM.Bytes.scan_next(cursor)
        after.end(rest, handle, next)

def after.last(
  fuel: Nat,
  handle: MyLSM.Bytes.Handle,
  cursor: MyLSM.Bytes.Cursor,
  valid: Bool
) -> IO(Unit):
  match valid:
    case False{}:
      do IO<Unit>:
        _cursor : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.scan_close(cursor)
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        fail("public SST cursor did not retain the deleted key")
    case True{}:
      do IO<Unit>:
        next : MyLSM.Bytes.StreamStep <- MyLSM.Bytes.scan_next(cursor)
        after.end(fuel, handle, next)

# Requires the pre-write SST suffix to remain visible after compaction.
def after.item(
  fuel: Nat,
  handle: MyLSM.Bytes.Handle,
  result: MyLSM.Bytes.StreamStep
) -> IO(Unit):
  match fuel result:
    case _, MyLSM.StreamItem{key, value, cursor}:
      do IO<Unit>:
        valid : Bool = Bool.and(bytes.equal(key, bytes("63")),
          bytes.equal(value, bytes("33")))
        after.last(fuel, handle, cursor, valid)
    case _, MyLSM.StreamEnd{cursor}:
      do IO<Unit>:
        _cursor : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.scan_close(cursor)
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        fail("public SST cursor omitted the retained pre-write suffix")
    case _, MyLSM.StreamFailure{_, _}: fail("public SST cursor returned an IO failure")
    case 0n, MyLSM.StreamSkip{_}: fail("cursor suffix exceeded its skip budget")
    case 1n+rest, MyLSM.StreamSkip{cursor}:
      do IO<Unit>:
        next : MyLSM.Bytes.StreamStep <- MyLSM.Bytes.scan_next(cursor)
        after.item(rest, handle, next)

def item.compacted(
  cursor: MyLSM.Bytes.Cursor,
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        next : MyLSM.Bytes.StreamStep <- MyLSM.Bytes.scan_next(cursor)
        after.item(64n, handle, next)
    case (handle, Fail{_}):
      do IO<Unit>:
        _cursor : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.scan_close(cursor)
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        fail("compaction failed while a public SST cursor remained open")

# Requires the first item to be the value recovered from the SSTable.
def item.checked(
  handle: MyLSM.Bytes.Handle,
  cursor: MyLSM.Bytes.Cursor,
  valid: Bool
) -> IO(Unit):
  match valid:
    case True{}:
      do IO<Unit>:
        compacted : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.compact(handle)
        item.compacted(cursor, compacted)
    case False{}: fail("public SST cursor omitted the recovered key or value")

# Checks the key and value bytes returned by the public streaming cursor.
def first(fuel: Nat, result: MyLSM.Bytes.StreamStep, handle: MyLSM.Bytes.Handle) -> IO(Unit):
  match fuel result:
    case _, MyLSM.StreamItem{key, value, cursor}:
      item.checked(handle, cursor,
        Bool.and(bytes.equal(key, bytes("62")), bytes.equal(value, bytes("32"))))
    case _, MyLSM.StreamFailure{_, _}: fail("public SST cursor failed on its first read")
    case 0n, MyLSM.StreamSkip{_}: fail("public SST cursor exceeded its skip budget")
    case 1n+rest, MyLSM.StreamSkip{cursor}:
      do IO<Unit>:
        step : MyLSM.Bytes.StreamStep <- MyLSM.Bytes.scan_next(cursor)
        first(rest, step, handle)
    case _, _: fail("public SST cursor ended before the recovered SST record")

def scan.written(
  cursor: MyLSM.Bytes.Cursor,
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        step : MyLSM.Bytes.StreamStep <- MyLSM.Bytes.scan_next(cursor)
        first(64n, step, handle)
    case (handle, Fail{_}):
      do IO<Unit>:
        _cursor : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.scan_close(cursor)
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        fail("write during an open SST cursor failed")

def scan.writing(
  cursor: MyLSM.Bytes.Cursor,
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  scan.written(cursor, pair)

# Starts the cursor after reopen and streams the recovered SST record.
def scanned(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Cursor>
) -> IO(Unit):
  match pair:
    case (handle, Done{cursor}):
      do IO<Unit>:
        sought : MyLSM.Bytes.Cursor = MyLSM.Bytes.scan_seek(cursor, Some{bytes("62")})
        written : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.write_batch(handle, Con{
            MyLSM.BytesPut{bytes("62"), bytes("6e6577")},
            Con{MyLSM.BytesDelete{bytes("63")}, Nil{}}})
        scan.writing(sought, written)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        fail("public scan creation failed after SST recovery")

# Opens the byte scan with an inclusive lower and exclusive upper bound.
def reopened(result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        cursor : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error,
          MyLSM.Bytes.Cursor> <-
          MyLSM.Bytes.scan_range(handle, Some{bytes("61")}, Some{bytes("64")})
        scanned(cursor)
    case Fail{_}: fail("database reopen for SST cursor failed")

# Reopens the published fixture only after releasing its original lock.
def published.closed(result: Result<&1, &1, MyLSM.Bytes.Error, Unit>) -> IO(Unit):
  match result:
    case Fail{_}: fail("SST cursor fixture writer close failed")
    case Done{Unit{}}:
      do IO<Unit>:
        path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
        opened : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
          MyLSM.Bytes.open_existing(path)
        reopened(opened)

# Releases the writer handle before testing the recovered reader path.
def published(pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        published.closed(closed)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        fail("SST cursor fixture flush failed")

# Writes byte records before publishing them to the SSTable.
def seeded(pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        flushed : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.flush(handle)
        published(flushed)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        fail("SST cursor fixture seed write failed")

# Creates the fixture database and seeds three persisted records.
def created(result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        written : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.write_batch(handle, Con{
            MyLSM.BytesPut{bytes("61"), bytes("31")},
            Con{MyLSM.BytesPut{bytes("62"), bytes("32")},
              Con{MyLSM.BytesPut{bytes("63"), bytes("33")}, Nil{}}}})
        seeded(written)
    case Fail{_}: fail("SST cursor fixture database create failed")

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    opened : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
      MyLSM.Bytes.create(path)
    created(opened)

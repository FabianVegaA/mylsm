import Base
import ../../mylsm.bend as MyLSM
import ../../src/Console.bend as Console
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

def bytes.parsed(result: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match result:
    case Some{value}: value
    case None{}: Bytes.new(0)

# Decodes a closed hexadecimal byte fixture.
def bytes(hex: String) -> Bytes.Bytes:
  bytes.parsed(Bytes.from_hex(hex))

def equal.result(pair: Bytes.Bytes & Bytes.Bytes & Bool) -> Bool:
  match pair:
    case (_, _, equal): equal

# Stops the fixture after releasing any owned cursor or handle.
def die(message: String) -> IO(Unit):
  IO.die(Unit, 1, message)

# Closes the terminal cursor after all snapshot assertions pass.
def finish(cursor: MyLSM.Bytes.Cursor) -> IO(Unit):
  do IO<Unit>:
    _cursor : MyLSM.Bytes.Cursor = MyLSM.Bytes.snapshot.scan_close(cursor)
    IO.print("PUBLIC_BYTES_CURSOR_PASSED")

def end.check(step: MyLSM.Bytes.ScanStep) -> IO(Unit):
  match step:
    case MyLSM.ScanEnd{cursor}: finish(cursor)
    case MyLSM.ScanFailure{_, cursor}:
      do IO<Unit>:
        _cursor : MyLSM.Bytes.Cursor = MyLSM.Bytes.snapshot.scan_close(cursor)
        die("snapshot cursor failed after the final item")
    case _: die("snapshot included a key committed after scan creation")

def second.matches(cursor: MyLSM.Bytes.Cursor, checks: Bool & Bool) -> IO(Unit):
  match checks:
    case (True{}, True{}): end.check(MyLSM.Bytes.snapshot.scan_next(cursor))
    case (_, _):
      do IO<Unit>:
        _cursor : MyLSM.Bytes.Cursor = MyLSM.Bytes.snapshot.scan_close(cursor)
        die("snapshot returned the wrong second ordered entry")

def second.check(
  step: MyLSM.Bytes.ScanStep
) -> IO(Unit):
  match step:
    case MyLSM.ScanItem{key, value, cursor}:
      second.matches(cursor,
        (equal.result(Bytes.eq(key, bytes("62"))), equal.result(Bytes.eq(value, bytes("32")))))
    case MyLSM.ScanSkip{cursor}:
      do IO<Unit>:
        _cursor : MyLSM.Bytes.Cursor = MyLSM.Bytes.snapshot.scan_close(cursor)
        die("unfiltered snapshot unexpectedly skipped an entry")
    case MyLSM.ScanEnd{cursor}:
      do IO<Unit>:
        _cursor : MyLSM.Bytes.Cursor = MyLSM.Bytes.snapshot.scan_close(cursor)
        die("snapshot ended before its second entry")
    case MyLSM.ScanFailure{_, cursor}:
      do IO<Unit>:
        _cursor : MyLSM.Bytes.Cursor = MyLSM.Bytes.snapshot.scan_close(cursor)
        die("snapshot cursor failed before its second entry")

def first.matches(cursor: MyLSM.Bytes.Cursor, checks: Bool & Bool) -> IO(Unit):
  match checks:
    case (True{}, True{}): second.check(MyLSM.Bytes.snapshot.scan_next(cursor))
    case (_, _):
      do IO<Unit>:
        _cursor : MyLSM.Bytes.Cursor = MyLSM.Bytes.snapshot.scan_close(cursor)
        die("snapshot returned the wrong first ordered entry")

def first.check(
  step: MyLSM.Bytes.ScanStep
) -> IO(Unit):
  match step:
    case MyLSM.ScanItem{key, value, cursor}:
      first.matches(cursor,
        (equal.result(Bytes.eq(key, bytes("61"))), equal.result(Bytes.eq(value, bytes("31")))))
    case MyLSM.ScanSkip{cursor}:
      do IO<Unit>:
        _cursor : MyLSM.Bytes.Cursor = MyLSM.Bytes.snapshot.scan_close(cursor)
        die("unfiltered snapshot unexpectedly skipped an entry")
    case MyLSM.ScanEnd{cursor}:
      do IO<Unit>:
        _cursor : MyLSM.Bytes.Cursor = MyLSM.Bytes.snapshot.scan_close(cursor)
        die("snapshot ended before its first entry")
    case MyLSM.ScanFailure{_, cursor}:
      do IO<Unit>:
        _cursor : MyLSM.Bytes.Cursor = MyLSM.Bytes.snapshot.scan_close(cursor)
        die("snapshot cursor failed before its first entry")

def scan.closed(cursor: MyLSM.Bytes.Cursor, result: Result<&1, &1, MyLSM.Bytes.Error, Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}: first.check(MyLSM.Bytes.snapshot.scan_next(cursor))
    case Fail{_}:
      do IO<Unit>:
        _cursor : MyLSM.Bytes.Cursor = MyLSM.Bytes.snapshot.scan_close(cursor)
        die("reopened database handle could not close")

def write.closed(
  cursor: MyLSM.Bytes.Cursor,
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        scan.closed(cursor, closed)
    case (handle, Fail{_}):
      do IO<Unit>:
        _cursor : MyLSM.Bytes.Cursor = MyLSM.Bytes.snapshot.scan_close(cursor)
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        die("write through the reopened handle failed")

def reopened.write(
  cursor: MyLSM.Bytes.Cursor,
  result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>
) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        pair : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.put(handle, bytes("64"), bytes("34"))
        write.closed(cursor, pair)
    case Fail{_}:
      do IO<Unit>:
        _cursor : MyLSM.Bytes.Cursor = MyLSM.Bytes.snapshot.scan_close(cursor)
        die("database could not reopen while its cursor remained active")

def closed.after.compact(cursor: MyLSM.Bytes.Cursor, result: Result<&1, &1, MyLSM.Bytes.Error, Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}:
      do IO<Unit>:
        path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
        opened : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <- MyLSM.Bytes.open_existing(path)
        reopened.write(cursor, opened)
    case Fail{_}:
      do IO<Unit>:
        _cursor : MyLSM.Bytes.Cursor = MyLSM.Bytes.snapshot.scan_close(cursor)
        die("database handle could not close with an active cursor")

# Closes the original handle so another database handle can write during the scan.
def compacted(
  cursor: MyLSM.Bytes.Cursor,
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        closed.after.compact(cursor, closed)
    case (handle, Fail{_}):
      do IO<Unit>:
        _cursor : MyLSM.Bytes.Cursor = MyLSM.Bytes.snapshot.scan_close(cursor)
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        die("byte compaction failed")

def write.after.snapshot(
  cursor: MyLSM.Bytes.Cursor,
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        result : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.compact(handle)
        compacted(cursor, result)
    case (handle, Fail{_}):
      do IO<Unit>:
        _cursor : MyLSM.Bytes.Cursor = MyLSM.Bytes.snapshot.scan_close(cursor)
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        die("write after snapshot failed")

# Verifies a retained snapshot before beginning an independent live scan.
def snapshot.created(pair: MyLSM.Bytes.Handle & MyLSM.Bytes.Cursor) -> IO(Unit):
  match pair:
    case (handle, cursor):
      do IO<Unit>:
        pair : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.put(handle, bytes("63"), bytes("33"))
        write.after.snapshot(cursor, pair)


def snapshot.scanning(pair: MyLSM.Bytes.Handle & MyLSM.Bytes.Cursor) -> IO(Unit):
  match pair:
    case (next_handle, cursor): snapshot.created((next_handle, cursor))

def snapshot.value.verified(handle: MyLSM.Bytes.Handle, valid: Bool) -> IO(Unit):
  match valid:
    case True{}:
      snapshot.scanning(MyLSM.Bytes.snapshot.live_scan_range(handle, Some{bytes("61")}, None{}))
    case False{}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        die("byte snapshot changed its retained value")

def snapshot.cursor.item.checked(
  handle: MyLSM.Bytes.Handle,
  snapshot: MyLSM.Bytes.Snapshot,
  cursor: MyLSM.Bytes.Cursor,
  valid: Bool
) -> IO(Unit):
      match valid:
        case True{}:
          do IO<Unit>:
            _cursor : MyLSM.Bytes.Cursor = MyLSM.Bytes.snapshot.scan_close(cursor)
            _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
              MyLSM.Bytes.snapshot.close(snapshot)
            snapshot.value.verified(handle, True{})
        case False{}:
          do IO<Unit>:
            _cursor : MyLSM.Bytes.Cursor = MyLSM.Bytes.snapshot.scan_close(cursor)
            _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
              MyLSM.Bytes.snapshot.close(snapshot)
            _handle : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
            die("byte snapshot scan returned an unexpected pair")
def snapshot.cursor.item(
  handle: MyLSM.Bytes.Handle,
  snapshot: MyLSM.Bytes.Snapshot,
  step: MyLSM.Bytes.ScanStep
) -> IO(Unit):
  match step:
    case MyLSM.ScanItem{key, value, next_cursor}:
      snapshot.cursor.item.checked(handle, snapshot, next_cursor,
        equal.result(Bytes.eq(key, bytes("61"))) && equal.result(Bytes.eq(value, bytes("31"))))
    case MyLSM.ScanSkip{next_cursor}:
      do IO<Unit>:
        _cursor : MyLSM.Bytes.Cursor = MyLSM.Bytes.snapshot.scan_close(next_cursor)
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
              MyLSM.Bytes.snapshot.close(snapshot)
        _handle : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        die("byte snapshot scan unexpectedly skipped its first entry")
    case MyLSM.ScanEnd{next_cursor}:
      do IO<Unit>:
        _cursor : MyLSM.Bytes.Cursor = MyLSM.Bytes.snapshot.scan_close(next_cursor)
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
              MyLSM.Bytes.snapshot.close(snapshot)
        _handle : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        die("byte snapshot scan ended before its first entry")
    case MyLSM.ScanFailure{_, next_cursor}:
      do IO<Unit>:
        _cursor : MyLSM.Bytes.Cursor = MyLSM.Bytes.snapshot.scan_close(next_cursor)
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
              MyLSM.Bytes.snapshot.close(snapshot)
        _handle : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        die("byte snapshot scan failed before its first entry")

def snapshot.step(step: MyLSM.Bytes.StreamStep) -> MyLSM.Bytes.ScanStep:
  match step:
    case MyLSM.StreamItem{key, value, cursor}:
      MyLSM.ScanItem{key, value, cursor}
    case MyLSM.StreamSkip{cursor}: MyLSM.ScanSkip{cursor}
    case MyLSM.StreamEnd{cursor}: MyLSM.ScanEnd{cursor}
    case MyLSM.StreamFailure{error, cursor}:
      MyLSM.ScanFailure{error, cursor}

def snapshot.cursor.opened(
  handle: MyLSM.Bytes.Handle,
  pair: MyLSM.Bytes.Snapshot & Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Cursor>
) -> IO(Unit):
  match pair:
    case (_, Fail{_}): die("byte snapshot cursor could not open")
    case (snapshot, Done{cursor}):
      do IO<Unit>:
        step : MyLSM.Bytes.StreamStep <- MyLSM.Bytes.scan_next(cursor)
        snapshot.cursor.item(handle, snapshot, snapshot.step(step))

def snapshot.value.result(
  snapshot: MyLSM.Bytes.Snapshot,
  handle: MyLSM.Bytes.Handle,
  valid: Bool
) -> IO(Unit):
      match valid:
        case True{}:
          do IO<Unit>:
            opened : MyLSM.Bytes.Snapshot &
              Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Cursor> <-
                MyLSM.Bytes.snapshot.scan_range(snapshot, Some{bytes("61")}, None{})
            snapshot.cursor.opened(handle, opened)
        case False{}:
          do IO<Unit>:
            _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
              MyLSM.Bytes.snapshot.close(snapshot)
            _handle : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
            die("byte snapshot returned the wrong value")

def snapshot.read(
  handle: MyLSM.Bytes.Handle,
  pair: MyLSM.Bytes.Snapshot & Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, Bytes.Bytes>>
) -> IO(Unit):
  match pair:
    case (snapshot, Done{Some{value}}):
      snapshot.value.result(snapshot, handle, equal.result(Bytes.eq(value, bytes("31"))))
    case (snapshot, _):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.snapshot.close(snapshot)
        _handle : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        die("byte snapshot omitted its retained key")

def snapshot.opened(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Snapshot>
) -> IO(Unit):
  match pair:
    case (handle, Done{snapshot}):
      do IO<Unit>:
        value : MyLSM.Bytes.Snapshot &
          Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, Bytes.Bytes>> <-
            MyLSM.Bytes.snapshot.get(snapshot, bytes("61"))
        snapshot.read(handle, value)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        die("byte snapshot could not be retained")

def created.flushed(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        result : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error,
          MyLSM.Bytes.Snapshot> <- MyLSM.Bytes.snapshot(handle)
        snapshot.opened(result)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        die("flush before snapshot failed")

def created.second(pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        flushed : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.flush(handle)
        created.flushed(flushed)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        die("second seed write failed")

def created.first(pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        second : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.put(handle, bytes("62"), bytes("32"))
        created.second(second)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        die("first seed write failed")

def created.result(result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        first : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.put(handle, bytes("61"), bytes("31"))
        created.first(first)
    case Fail{_}: die("cursor fixture database create failed")

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <- MyLSM.Bytes.create(path)
    created.result(result)

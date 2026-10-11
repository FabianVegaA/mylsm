import Base
import ../../src/ByteDurableDb.bend as ByteDurableDb
import ../../src/ByteMemTable.bend as ByteMemTable
import ../../src/scan/RangeCursor.bend as RangeCursor
import ../../src/scan/VisibleCursor.bend as VisibleCursor
import ../../src/Console.bend as Console
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

def fixture.bytes(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}: bytes
    case None{}: Bytes.new(0)

def fixture.equal(pair: Bytes.Bytes & Bytes.Bytes & Bool) -> Bool:
  match pair:
    case (_, _, equal): equal

# Closes both readers after one streamed snapshot row is verified.
def fixture.finish(
  handle: ByteDurableDb.Handle,
  cursor: VisibleCursor.Cursor,
  valid: Bool
) -> IO(Unit):
  match valid:
    case True{}:
      do IO<Unit>:
        _cursor_close : Result<&1, &1, U32 & String, Unit> <-
          VisibleCursor.close(cursor)
        _handle_close : Result<&1, &1, ByteDurableDb.Error, Unit> <-
          ByteDurableDb.close(handle)
        IO.print("SNAPSHOT_ROOT_STREAM_PASSED")
    case False{}:
      do IO<Unit>:
        _cursor_close : Result<&1, &1, U32 & String, Unit> <-
          VisibleCursor.close(cursor)
        _handle_close : Result<&1, &1, ByteDurableDb.Error, Unit> <-
          ByteDurableDb.close(handle)
        IO.die(Unit, 1, "snapshot root returned unexpected key or value")

# Checks the exact byte key and value read from the retained SST generation.
def fixture.item(
  handle: ByteDurableDb.Handle,
  cursor: VisibleCursor.Cursor,
  key: Bytes.Bytes,
  value: Maybe<&1, Bytes.Bytes>
) -> IO(Unit):
  match value:
    case Some{bytes}:
      fixture.finish(handle, cursor,
        fixture.equal(Bytes.eq(key, fixture.bytes(Bytes.from_hex("61")))) &&
          fixture.equal(Bytes.eq(bytes, fixture.bytes(Bytes.from_hex("76")))))
    case None{}: fixture.finish(handle, cursor, False{})

# Reads the next snapshot item from the block-backed visible cursor.
def fixture.next(
  handle: ByteDurableDb.Handle,
  step: VisibleCursor.Step
) -> IO(Unit):
  match step:
    case VisibleCursor.Item{entry, cursor}:
      match entry:
        case ByteMemTable.Entry{key, value}:
          fixture.item(handle, cursor, key, value)
    case VisibleCursor.Skip{cursor}:
      do IO<Unit>:
        _cursor_close : Result<&1, &1, U32 & String, Unit> <-
          VisibleCursor.close(cursor)
        _handle_close : Result<&1, &1, ByteDurableDb.Error, Unit> <-
          ByteDurableDb.close(handle)
        IO.die(Unit, 1, "snapshot root unexpectedly skipped a live entry")
    case VisibleCursor.End{}:
      do IO<Unit>:
        _handle_close : Result<&1, &1, ByteDurableDb.Error, Unit> <-
          ByteDurableDb.close(handle)
        IO.die(Unit, 1, "snapshot root ended before its first item")
    case VisibleCursor.Error{error}:
      do IO<Unit>:
        _handle_close : Result<&1, &1, ByteDurableDb.Error, Unit> <-
          ByteDurableDb.close(handle)
        IO.die(Unit, 1, "snapshot root cursor failed")

# Starts reading after the snapshot cursor opens successfully.
def fixture.opened(
  handle: ByteDurableDb.Handle,
  opened: Result<&1, &1, ByteDurableDb.Error, VisibleCursor.Cursor>
) -> IO(Unit):
  match opened:
    case Fail{_}:
      do IO<Unit>:
        _handle_close : Result<&1, &1, ByteDurableDb.Error, Unit> <-
          ByteDurableDb.close(handle)
        IO.die(Unit, 1, "snapshot root block cursor did not open")
    case Done{cursor}:
      do IO<Unit>:
        step : VisibleCursor.Step <- VisibleCursor.next(cursor)
        fixture.next(handle, step)

def fixture.point.checked(
  handle: ByteDurableDb.Handle,
  root: ByteDurableDb.SnapshotRoot,
  matches: Bool
) -> IO(Unit):
  match matches:
    case True{}:
      do IO<Unit>:
        opened : Result<&1, &1, ByteDurableDb.Error, VisibleCursor.Cursor> <-
          ByteDurableDb.snapshot.root.cursor.open(root,
            RangeCursor.Bounds{None{}, None{}, None{}})
        fixture.opened(handle, opened)
    case False{}:
      do IO<Unit>:
        _handle_close : Result<&1, &1, ByteDurableDb.Error, Unit> <-
          ByteDurableDb.close(handle)
        IO.die(Unit, 1, "snapshot point read returned an incorrect value")

def fixture.point.clone.second(
  handle: ByteDurableDb.Handle,
  root: ByteDurableDb.SnapshotRoot,
  result: Result<&1, &1, ByteDurableDb.Error, Maybe<&1, Bytes.Bytes>>
) -> IO(Unit):
  match result:
    case Done{Some{value}}:
      fixture.point.checked(handle, root,
        fixture.equal(Bytes.eq(value, fixture.bytes(Bytes.from_hex("76")))))
    case _:
      do IO<Unit>:
        _handle_close : Result<&1, &1, ByteDurableDb.Error, Unit> <-
          ByteDurableDb.close(handle)
        IO.die(Unit, 1, "second retained-root read did not find its key")

def fixture.point.clone.first.checked.result(
  handle: ByteDurableDb.Handle,
  first_root: ByteDurableDb.SnapshotRoot,
  second_root: ByteDurableDb.SnapshotRoot,
  matches: Bool
) -> IO(Unit):
  match matches:
    case True{}:
      do IO<Unit>:
        second : Result<&1, &1, ByteDurableDb.Error,
          Maybe<&1, Bytes.Bytes>> <- ByteDurableDb.snapshot.root.get(first_root,
            fixture.bytes(Bytes.from_hex("61")))
        fixture.point.clone.second(handle, second_root, second)
    case False{}:
      do IO<Unit>:
        _handle_close : Result<&1, &1, ByteDurableDb.Error, Unit> <-
          ByteDurableDb.close(handle)
        IO.die(Unit, 1, "first retained-root read returned a changed value")

def fixture.point.clone.first.checked(
  handle: ByteDurableDb.Handle,
  roots: ByteDurableDb.SnapshotRoot & ByteDurableDb.SnapshotRoot,
  matches: Bool
) -> IO(Unit):
  match roots:
    case (first_root, second_root):
      fixture.point.clone.first.checked.result(handle, first_root, second_root,
        matches)

def fixture.point.clone.first.result(
  handle: ByteDurableDb.Handle,
  root: ByteDurableDb.SnapshotRoot,
  result: Result<&1, &1, ByteDurableDb.Error, Maybe<&1, Bytes.Bytes>>
) -> IO(Unit):
  match result:
    case Done{Some{value}}:
      fixture.point.clone.first.checked(handle,
        ByteDurableDb.snapshot.root.clone(root),
        fixture.equal(Bytes.eq(value, fixture.bytes(Bytes.from_hex("76")))))
    case _:
      do IO<Unit>:
        _handle_close : Result<&1, &1, ByteDurableDb.Error, Unit> <-
          ByteDurableDb.close(handle)
        IO.die(Unit, 1, "first retained-root read did not find its key")

def fixture.point.clone.first(
  handle: ByteDurableDb.Handle,
  roots: ByteDurableDb.SnapshotRoot & ByteDurableDb.SnapshotRoot
) -> IO(Unit):
  match roots:
    case (first_root, second_root):
      do IO<Unit>:
        result : Result<&1, &1, ByteDurableDb.Error, Maybe<&1, Bytes.Bytes>> <-
          ByteDurableDb.snapshot.root.get(first_root,
            fixture.bytes(Bytes.from_hex("61")))
        fixture.point.clone.first.result(handle, second_root, result)

def fixture.point.value.checked(
  handle: ByteDurableDb.Handle,
  root: ByteDurableDb.SnapshotRoot,
  valid: Bool
) -> IO(Unit):
  match valid:
    case True{}:
      fixture.point.clone.first(handle, ByteDurableDb.snapshot.root.clone(root))
    case False{}:
      do IO<Unit>:
        _handle_close : Result<&1, &1, ByteDurableDb.Error, Unit> <-
          ByteDurableDb.close(handle)
        IO.die(Unit, 1, "snapshot point read returned an incorrect value")

def fixture.point.value(
  handle: ByteDurableDb.Handle,
  root: ByteDurableDb.SnapshotRoot,
  result: Result<&1, &1, ByteDurableDb.Error, Maybe<&1, Bytes.Bytes>>
) -> IO(Unit):
  match result:
    case Done{Some{value}}:
      fixture.point.value.checked(handle, root,
        fixture.equal(Bytes.eq(value, fixture.bytes(Bytes.from_hex("78")))))
    case _:
      do IO<Unit>:
        _handle_close : Result<&1, &1, ByteDurableDb.Error, Unit> <-
          ByteDurableDb.close(handle)
        IO.die(Unit, 1, "snapshot point read did not find its key")

def fixture.point.root(
  root: ByteDurableDb.SnapshotRoot,
  pair:
    ByteDurableDb.Handle &
      Result<&1, &1, ByteDurableDb.Error, ByteDurableDb.SnapshotRoot>
) -> IO(Unit):
  match pair:
    case (handle, Fail{_}):
      do IO<Unit>:
        _handle_close : Result<&1, &1, ByteDurableDb.Error, Unit> <-
          ByteDurableDb.close(handle)
        IO.die(Unit, 1, "snapshot point-read root capture failed")
    case (handle, Done{point_root}):
      do IO<Unit>:
        value : Result<&1, &1, ByteDurableDb.Error, Maybe<&1, Bytes.Bytes>> <-
          ByteDurableDb.snapshot.root.get(point_root,
            fixture.bytes(Bytes.from_hex("61")))
        fixture.point.value(handle, root, value)

# Opens the captured root after later mutations and compaction complete.
def fixture.compacted(
  root: ByteDurableDb.SnapshotRoot,
  pair: ByteDurableDb.Handle & Result<&1, &1, ByteDurableDb.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        point : ByteDurableDb.Handle &
          Result<&1, &1, ByteDurableDb.Error, ByteDurableDb.SnapshotRoot> <-
            ByteDurableDb.snapshot_root_limited(1048576n, handle)
        fixture.point.root(root, point)
    case (handle, Fail{_}):
      do IO<Unit>:
        _handle_close : Result<&1, &1, ByteDurableDb.Error, Unit> <-
          ByteDurableDb.close(handle)
        IO.die(Unit, 1, "snapshot root fixture compaction failed")

# Compacts the replacement SST before reading the captured root.
def fixture.flushed.root(
  root: ByteDurableDb.SnapshotRoot,
  pair: ByteDurableDb.Handle & Result<&1, &1, ByteDurableDb.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        compacted : ByteDurableDb.Handle &
          Result<&1, &1, ByteDurableDb.Error, Unit> <-
            ByteDurableDb.compact(handle)
        fixture.compacted(root, compacted)
    case (handle, Fail{_}):
      do IO<Unit>:
        _handle_close : Result<&1, &1, ByteDurableDb.Error, Unit> <-
          ByteDurableDb.close(handle)
        IO.die(Unit, 1, "snapshot root fixture replacement flush failed")

# Flushes a later replacement while the original root remains retained.
def fixture.changed.root(
  root: ByteDurableDb.SnapshotRoot,
  pair: ByteDurableDb.Handle & Result<&1, &1, ByteDurableDb.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        flushed : ByteDurableDb.Handle &
          Result<&1, &1, ByteDurableDb.Error, Unit> <-
            ByteDurableDb.flush(handle)
        fixture.flushed.root(root, flushed)
    case (handle, Fail{_}):
      do IO<Unit>:
        _handle_close : Result<&1, &1, ByteDurableDb.Error, Unit> <-
          ByteDurableDb.close(handle)
        IO.die(Unit, 1, "snapshot root fixture replacement write failed")

# Opens a block cursor over the captured immutable SST path.
def fixture.root(
  pair: ByteDurableDb.Handle & Result<&1, &1, ByteDurableDb.Error, ByteDurableDb.SnapshotRoot>
) -> IO(Unit):
  match pair:
    case (handle, Fail{_}):
      do IO<Unit>:
        _handle_close : Result<&1, &1, ByteDurableDb.Error, Unit> <-
          ByteDurableDb.close(handle)
        IO.die(Unit, 1, "snapshot root preflight failed")
    case (handle, Done{root}):
      match root:
        case ByteDurableDb.SnapshotRoot{_, Some{_}, retained_bytes, _}:
          match retained_bytes:
            case 1n+rest:
              do IO<Unit>:
                changed : ByteDurableDb.Handle &
                  Result<&1, &1, ByteDurableDb.Error, Unit> <-
                    ByteDurableDb.put(handle,
                      fixture.bytes(Bytes.from_hex("61")),
                      fixture.bytes(Bytes.from_hex("78")))
                fixture.changed.root(root, changed)
            case 0n:
              do IO<Unit>:
                _handle_close : Result<&1, &1, ByteDurableDb.Error, Unit> <-
                  ByteDurableDb.close(handle)
                IO.die(Unit, 1, "snapshot root did not track retained bytes")
        case ByteDurableDb.SnapshotRoot{_, None{}, _, _}:
          do IO<Unit>:
            _handle_close : Result<&1, &1, ByteDurableDb.Error, Unit> <-
              ByteDurableDb.close(handle)
            IO.die(Unit, 1, "snapshot root omitted its published SST generation")

# Flushes the seed entry before capturing an SST-backed root.
def fixture.root.limited(
  pair: ByteDurableDb.Handle & Result<&1, &1, ByteDurableDb.Error, ByteDurableDb.SnapshotRoot>
) -> IO(Unit):
  match pair:
    case (handle, Fail{ByteDurableDb.ResourceLimit{}}):
      do IO<Unit>:
        root : ByteDurableDb.Handle &
          Result<&1, &1, ByteDurableDb.Error, ByteDurableDb.SnapshotRoot> <-
            ByteDurableDb.snapshot_root_limited(1048576n, handle)
        fixture.root(root)
    case (handle, _):
      do IO<Unit>:
        _handle_close : Result<&1, &1, ByteDurableDb.Error, Unit> <-
          ByteDurableDb.close(handle)
        IO.die(Unit, 1, "snapshot root ignored retained SST byte limit")

def fixture.flushed(
  pair: ByteDurableDb.Handle & Result<&1, &1, ByteDurableDb.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        limited : ByteDurableDb.Handle &
          Result<&1, &1, ByteDurableDb.Error, ByteDurableDb.SnapshotRoot> <-
            ByteDurableDb.snapshot_root_limited(0n, handle)
        fixture.root.limited(limited)
    case (handle, Fail{_}):
      do IO<Unit>:
        _handle_close : Result<&1, &1, ByteDurableDb.Error, Unit> <-
          ByteDurableDb.close(handle)
        IO.die(Unit, 1, "snapshot root fixture flush failed")

# Flushes the written seed or releases its handle on error.
def fixture.put.result(
  pair: ByteDurableDb.Handle & Result<&1, &1, ByteDurableDb.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        flushed : ByteDurableDb.Handle &
          Result<&1, &1, ByteDurableDb.Error, Unit> <-
            ByteDurableDb.flush(handle)
        fixture.flushed(flushed)
    case (handle, Fail{_}):
      do IO<Unit>:
        _handle_close : Result<&1, &1, ByteDurableDb.Error, Unit> <-
          ByteDurableDb.close(handle)
        IO.die(Unit, 1, "snapshot root fixture put failed")

# Writes the exact raw key and value used by the SST cursor assertion.
def fixture.created(
  result: Result<&1, &1, ByteDurableDb.Error, ByteDurableDb.Handle>
) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "snapshot root database creation failed")
    case Done{handle}:
      do IO<Unit>:
        put : ByteDurableDb.Handle &
          Result<&1, &1, ByteDurableDb.Error, Unit> <-
            ByteDurableDb.put(handle,
              fixture.bytes(Bytes.from_hex("61")),
              fixture.bytes(Bytes.from_hex("76")))
        fixture.put.result(put)

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, ByteDurableDb.Error, ByteDurableDb.Handle> <-
      ByteDurableDb.create(path)
    fixture.created(result)

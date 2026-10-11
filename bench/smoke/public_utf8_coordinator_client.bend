import Base
import ../../mylsm.bend as MyLSM
import ../../src/Console.bend as Console

# Stops the UTF-8 owner fixture after a failed assertion.
def fail(message: String) -> IO(Unit):
  IO.die(Unit, 1, message)

# Closes the database after the live UTF-8 range reaches its end.
def live.finished(
  handle: MyLSM.Utf8.Handle,
  step: MyLSM.Utf8.ScanStep
) -> IO(Unit):
  match step:
    case MyLSM.Utf8ScanEnd{_}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <-
          MyLSM.Utf8.close(handle)
        IO.print("PUBLIC_UTF8_COORDINATOR_CLIENT_PASSED")
    case _: fail("live UTF-8 scan did not end")

# Reads the terminal marker after the one-key live range.
def live.advanced(
  handle: MyLSM.Utf8.Handle,
  cursor: MyLSM.Utf8.Cursor
) -> IO(Unit):
  do IO<Unit>:
    step : MyLSM.Utf8.ScanStep <- MyLSM.Utf8.scan_next(cursor)
    live.finished(handle, step)

# Continues only when both UTF-8 fields match the expected range entry.
def live.item.checked(
  handle: MyLSM.Utf8.Handle,
  cursor: MyLSM.Utf8.Cursor,
  valid: Bool
) -> IO(Unit):
  match valid:
    case True{}: live.advanced(handle, cursor)
    case False{}: fail("live UTF-8 scan changed its range item")


# Validates the only key in the half-open alpha-to-beta range.
def live.matches(key: String, value: String) -> Bool:
  String.eq(key, "alpha") && String.eq(value, "uno")

def live.item(
  handle: MyLSM.Utf8.Handle,
  step: MyLSM.Utf8.ScanStep
) -> IO(Unit):
  match step:
    case MyLSM.Utf8ScanItem{key, value, cursor}:
      live.item.checked(handle, cursor, live.matches(key, value))
    case _: fail("live UTF-8 scan omitted its range item")


# Reads one live UTF-8 range item from the owner cursor.
def live.opened(
  handle: MyLSM.Utf8.Handle,
  result: Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Cursor>
) -> IO(Unit):
  match result:
    case Done{cursor}:
      do IO<Unit>:
        step : MyLSM.Utf8.ScanStep <- MyLSM.Utf8.scan_next(cursor)
        live.item(handle, step)
    case Fail{_}: fail("public live UTF-8 range scan failed to open")

# Preserves the UTF-8 handle after its earlier explicit snapshot is closed.
def snapshot.released.opened(pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Cursor>) -> IO(Unit):
  match pair:
    case (next, result): live.opened(next, result)

def snapshot.released(
  pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        opened : MyLSM.Utf8.Handle &
          Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Cursor> <-
            MyLSM.Utf8.scan_range(handle, Some{"alpha"}, Some{"beta"})
        snapshot.released.opened(opened)
    case _: fail("explicit UTF-8 snapshot close failed")

# Closes the snapshot and database after the owner cursor is released.
def closed(
  handle: MyLSM.Utf8.Handle,
  snapshot: MyLSM.Utf8.Snapshot,
  result: Result<&1, &1, MyLSM.Utf8.Error, Unit>
) -> IO(Unit):
  match result:
    case Done{Unit{}}:
      do IO<Unit>:
        snapshot_result : Result<&1, &1, MyLSM.Utf8.Error, Unit> <-
          MyLSM.Utf8.snapshot.close(snapshot)
        snapshot.released((handle, snapshot_result))
    case Fail{_}: fail("UTF-8 owner cursor close failed")

def cursor.closed(
  handle: MyLSM.Utf8.Handle,
  snapshot: MyLSM.Utf8.Snapshot,
  pair: MyLSM.Utf8.Cursor & Result<&1, &1, MyLSM.Utf8.Error, Unit>
) -> IO(Unit):
  match pair:
    case (cursor, Done{Unit{}}):
      closed(handle, snapshot, Done{Unit{}})
    case (_, Fail{MyLSM.Utf8Failure{MyLSM.Busy{}}}):
      fail("UTF-8 cursor close returned Busy")
    case (_, Fail{MyLSM.Utf8Failure{MyLSM.InvalidArgument{}}}):
      fail("UTF-8 cursor close returned InvalidArgument")
    case (_, Fail{MyLSM.Utf8Failure{MyLSM.Corruption{message}}}):
      fail("UTF-8 cursor close corruption: " ++ message)
    case (_, Fail{MyLSM.Utf8Failure{MyLSM.Io{_, message}}}):
      fail("UTF-8 cursor close IO: " ++ message)
    case _: fail("UTF-8 owner cursor close failed")

def item.checked(
  handle: MyLSM.Utf8.Handle,
  snapshot: MyLSM.Utf8.Snapshot,
  cursor: MyLSM.Utf8.Cursor,
  valid: Bool
) -> IO(Unit):
  match valid:
    case True{}:
      do IO<Unit>:
        pair : MyLSM.Utf8.Cursor &
          Result<&1, &1, MyLSM.Utf8.Error, Unit> <-
            MyLSM.Utf8.scan_close(cursor)
        cursor.closed(handle, snapshot, pair)
    case False{}: fail("UTF-8 owner seek returned an unexpected item")

# Checks the first decoded UTF-8 item after the remote seek.
def item(
  handle: MyLSM.Utf8.Handle,
  snapshot: MyLSM.Utf8.Snapshot,
  step: MyLSM.Utf8.ScanStep
) -> IO(Unit):
  match step:
    case MyLSM.Utf8ScanItem{key, value, cursor}:
      item.checked(handle, snapshot, cursor,
        String.eq(key, "beta") && String.eq(value, "dos"))
    case _: fail("UTF-8 owner seek returned no item")

# Reads one item after the owner acknowledged cursor positioning.
def sought(
  handle: MyLSM.Utf8.Handle,
  snapshot: MyLSM.Utf8.Snapshot,
  pair: MyLSM.Utf8.Cursor & Result<&1, &1, MyLSM.Utf8.Error, Unit>
) -> IO(Unit):
  match pair:
    case (cursor, Done{Unit{}}):
      do IO<Unit>:
        step : MyLSM.Utf8.ScanStep <- MyLSM.Utf8.scan_next(cursor)
        item(handle, snapshot, step)
    case _: fail("UTF-8 owner seek failed")

def opened.cursor(
  handle: MyLSM.Utf8.Handle,
  pair: MyLSM.Utf8.Snapshot & Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Cursor>
) -> IO(Unit):
  match pair:
    case (snapshot, Done{cursor}):
      do IO<Unit>:
        result : MyLSM.Utf8.Cursor &
          Result<&1, &1, MyLSM.Utf8.Error, Unit> <-
            MyLSM.Utf8.scan_seek(cursor, Some{"beta"})
        sought(handle, snapshot, result)
    case _: fail("UTF-8 owner cursor open failed")

def opened.snapshot(
  pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Snapshot>
) -> IO(Unit):
  match pair:
    case (next_handle, Done{snapshot}):
      do IO<Unit>:
        cursor : MyLSM.Utf8.Snapshot &
          Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Cursor> <-
            MyLSM.Utf8.snapshot.scan_range(snapshot, None{}, None{})
        opened.cursor(next_handle, cursor)
    case _: fail("UTF-8 owner snapshot open failed")

# Opens a UTF-8 snapshot after the seed write has committed.
def written(result: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, MyLSM.WriteOutcome>) -> IO(Unit):
  match result:
    case (next, Done{_}):
      do IO<Unit>:
        snapshot : MyLSM.Utf8.Handle &
          Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Snapshot> <-
            MyLSM.Utf8.snapshot(next)
        opened.snapshot(snapshot)
    case _: fail("UTF-8 owner write failed")

# Seeds ordered text keys before opening the owner snapshot.
def opened(result: Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle>) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        result : MyLSM.Utf8.Handle &
          Result<&1, &1, MyLSM.Utf8.Error, MyLSM.WriteOutcome> <-
            MyLSM.Utf8.write_batch(handle, Con{
              MyLSM.Utf8SetValue{"alpha", "uno"},
              Con{MyLSM.Utf8SetValue{"beta", "dos"}, Nil{}}})
        written(result)
    case _: fail("UTF-8 owner open failed")

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle> <-
      MyLSM.Utf8.open_existing_wait(path, 1000, 10)
    opened(result)

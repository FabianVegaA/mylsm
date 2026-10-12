import Base
import ../mylsm.bend as MyLSM

# Releases the database handle before reporting an example failure.
def fail(handle: MyLSM.Utf8.Handle, message: String) -> IO(Unit):
  do IO<Unit>:
    _closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
    IO.die(Unit, 1, message)

def fail.snapshot(
  handle: MyLSM.Utf8.Handle,
  snapshot: MyLSM.Utf8.Snapshot,
  message: String
) -> IO(Unit):
  do IO<Unit>:
    _snapshot : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.snapshot.close(snapshot)
    fail(handle, message)

# Reports a successful snapshot and live-read comparison.
def finished(result: Result<&1, &1, MyLSM.Utf8.Error, Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.print("SNAPSHOT_EXAMPLE_OK")
    case Fail{_}: IO.die(Unit, 1, "could not close the database")

def current.valid(handle: MyLSM.Utf8.Handle, valid: Bool) -> IO(Unit):
  match valid:
    case True{}:
      do IO<Unit>:
        IO.print("current: new")
        closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        finished(closed)
    case False{}: fail(handle, "the current value is not new")

def current.read(
  pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Maybe<&2, String>>
) -> IO(Unit):
  match pair:
    case (handle, Done{Some{value}}): current.valid(handle, String.eq(value, "new"))
    case (handle, _): fail(handle, "could not read the current value")

def snapshot.closed(
  handle: MyLSM.Utf8.Handle,
  result: Result<&1, &1, MyLSM.Utf8.Error, Unit>
) -> IO(Unit):
  match result:
    case Done{Unit{}}:
      do IO<Unit>:
        pair : MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Maybe<&2, String>> <-
          MyLSM.Utf8.get(handle, "acct/1")
        current.read(pair)
    case Fail{_}: fail(handle, "could not close the snapshot")

def cursor.closed(
  handle: MyLSM.Utf8.Handle,
  snapshot: MyLSM.Utf8.Snapshot,
  pair: MyLSM.Utf8.Cursor & Result<&1, &1, MyLSM.Utf8.Error, Unit>
) -> IO(Unit):
  # Release the child cursor before closing its parent snapshot.
  match pair:
    case (_, Done{Unit{}}):
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.snapshot.close(snapshot)
        snapshot.closed(handle, closed)
    case (_, Fail{_}): fail.snapshot(handle, snapshot, "could not close the cursor")

def cursor.item.valid(
  handle: MyLSM.Utf8.Handle,
  snapshot: MyLSM.Utf8.Snapshot,
  cursor: MyLSM.Utf8.Cursor,
  valid: Bool
) -> IO(Unit):
  match valid:
    case True{}:
      do IO<Unit>:
        IO.print("snapshot: old")
        closed : MyLSM.Utf8.Cursor & Result<&1, &1, MyLSM.Utf8.Error, Unit> <-
          MyLSM.Utf8.scan_close(cursor)
        cursor.closed(handle, snapshot, closed)
    case False{}:
      do IO<Unit>:
        _cursor : MyLSM.Utf8.Cursor & Result<&1, &1, MyLSM.Utf8.Error, Unit> <-
          MyLSM.Utf8.scan_close(cursor)
        fail.snapshot(handle, snapshot, "the snapshot did not retain the old value")

def cursor.first(
  handle: MyLSM.Utf8.Handle,
  snapshot: MyLSM.Utf8.Snapshot,
  step: MyLSM.Utf8.ScanStep
) -> IO(Unit):
  match step:
    case MyLSM.Utf8ScanItem{key, value, cursor}:
      cursor.item.valid(handle, snapshot, cursor,
        Bool.and(String.eq(key, "acct/1"), String.eq(value, "old")))
    case MyLSM.Utf8ScanSkip{cursor}:
      do IO<Unit>:
        _cursor : MyLSM.Utf8.Cursor & Result<&1, &1, MyLSM.Utf8.Error, Unit> <-
          MyLSM.Utf8.scan_close(cursor)
        fail.snapshot(handle, snapshot, "the scan skipped its first item")
    case MyLSM.Utf8ScanEnd{cursor}:
      do IO<Unit>:
        _cursor : MyLSM.Utf8.Cursor & Result<&1, &1, MyLSM.Utf8.Error, Unit> <-
          MyLSM.Utf8.scan_close(cursor)
        fail.snapshot(handle, snapshot, "the scan ended before its first item")
    case MyLSM.Utf8ScanFailure{_, cursor}:
      do IO<Unit>:
        _cursor : MyLSM.Utf8.Cursor & Result<&1, &1, MyLSM.Utf8.Error, Unit> <-
          MyLSM.Utf8.scan_close(cursor)
        fail.snapshot(handle, snapshot, "the scan failed")

def scan.opened(
  handle: MyLSM.Utf8.Handle,
  pair: MyLSM.Utf8.Snapshot & Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Cursor>
) -> IO(Unit):
  match pair:
    case (snapshot, Done{cursor}):
      do IO<Unit>:
        step : MyLSM.Utf8.ScanStep <- MyLSM.Utf8.scan_next(cursor)
        cursor.first(handle, snapshot, step)
    case (snapshot, Fail{_}): fail.snapshot(handle, snapshot, "could not open the snapshot scan")

# Scans the retained snapshot after the live database changes.
def updated(
  snapshot: MyLSM.Utf8.Snapshot,
  pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, MyLSM.WriteOutcome>
) -> IO(Unit):
  match pair:
    case (handle, Done{_}):
      do IO<Unit>:
        scan : MyLSM.Utf8.Snapshot & Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Cursor> <-
          MyLSM.Utf8.snapshot.scan_prefix(snapshot, "acct/")
        scan.opened(handle, scan)
    case (handle, Fail{_}): fail.snapshot(handle, snapshot, "could not update the live value")

# Updates the live database while the earlier snapshot is open.
def retained(
  pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Snapshot>
) -> IO(Unit):
  match pair:
    case (handle, Done{snapshot}):
      do IO<Unit>:
        update : MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, MyLSM.WriteOutcome> <-
          MyLSM.Utf8.put(handle, "acct/1", "new")
        updated(snapshot, update)
    case (handle, Fail{_}): fail(handle, "could not retain the snapshot")

# Retains a snapshot after committing the initial value.
def seeded(
  pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, MyLSM.WriteOutcome>
) -> IO(Unit):
  match pair:
    case (handle, Done{_}):
      do IO<Unit>:
        snapshot : MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Snapshot> <-
          MyLSM.Utf8.snapshot(handle)
        retained(snapshot)
    case (handle, Fail{_}): fail(handle, "could not write the first value")

# Seeds a new database with the value visible to the snapshot.
def created(result: Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle>) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        pair : MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, MyLSM.WriteOutcome> <-
          MyLSM.Utf8.put(handle, "acct/1", "old")
        seeded(pair)
    case Fail{_}: IO.die(Unit, 1, "could not create the database")

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, IO.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle> <- MyLSM.Utf8.create(path)
    created(result)

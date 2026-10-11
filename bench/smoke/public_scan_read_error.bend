import Base
import ../../mylsm.bend as MyLSM
import ../../src/Console.bend as Console
import ../../src/Fs.bend as Fs
import ../../src/Keys.bend as Keys
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

def bytes.parsed(result: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match result:
    case Some{value}: value
    case None{}: Bytes.new(0)

# Decodes one closed hexadecimal fixture key.
def bytes(hex: String) -> Bytes.Bytes:
  bytes.parsed(Bytes.from_hex(hex))

# Stops the integration fixture after a failed assertion.
def fail(message: String) -> IO(Unit):
  IO.die(Unit, 1, message)

def database.closed(result: Result<&1, &1, MyLSM.Bytes.Error, Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.print("PUBLIC_SCAN_READ_ERROR_PASSED")
    case Fail{_}: fail("database failed to close after a scan error")

def cursor.closed(
  handle: MyLSM.Bytes.Handle,
  result: Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match result:
    case Done{Unit{}}:
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        database.closed(closed)
    case Fail{_}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        fail("cursor failed to release its reader after a scan error")

def scan.failed(
  handle: MyLSM.Bytes.Handle,
  cursor: MyLSM.Bytes.Cursor,
  message: String
) -> IO(Unit):
  do IO<Unit>:
    _cursor : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.scan_close(cursor)
    _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
    fail(message)

def error.step(
  handle: MyLSM.Bytes.Handle,
  step: MyLSM.Bytes.StreamStep
) -> IO(Unit):
  match step:
    case MyLSM.StreamFailure{_, cursor}:
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.scan_close(cursor)
        cursor.closed(handle, closed)
    case MyLSM.StreamItem{_, _, cursor}:
      scan.failed(handle, cursor, "truncated later SST block still returned an item")
    case MyLSM.StreamEnd{cursor}:
      scan.failed(handle, cursor, "truncated later SST block reached End")
    case MyLSM.StreamSkip{cursor}:
      scan.failed(handle, cursor, "truncated later SST block was skipped")

def truncate.result(
  handle: MyLSM.Bytes.Handle,
  cursor: MyLSM.Bytes.Cursor,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Unit):
  match result:
    case Done{Unit{}}:
      do IO<Unit>:
        step : MyLSM.Bytes.StreamStep <- MyLSM.Bytes.scan_next(cursor)
        error.step(handle, step)
    case Fail{_}:
      scan.failed(handle, cursor, "could not truncate the SST during the scan")

def first.valid(
  handle: MyLSM.Bytes.Handle,
  cursor: MyLSM.Bytes.Cursor,
  valid: Bool
) -> IO(Unit):
  match valid:
    case False{}:
      scan.failed(handle, cursor, "public scan returned the wrong first SST key")
    case True{}:
      do IO<Unit>:
        path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
        truncated : Result<&1, &1, U32 & String, Unit> <- Fs.truncate(path ++ "/SST", 0n)
        truncate.result(handle, cursor, truncated)

def first.step(
  pair: MyLSM.Bytes.Handle & MyLSM.Bytes.StreamStep
) -> IO(Unit):
  match pair:
    case (handle, MyLSM.StreamItem{key, _, cursor}):
      first.valid(handle, cursor, Keys.Bytes.eq(key, bytes("61")))
    case (handle, MyLSM.StreamFailure{_, cursor}):
      scan.failed(handle, cursor, "public scan failed before returning its first row")
    case (handle, MyLSM.StreamEnd{cursor}):
      scan.failed(handle, cursor, "public scan ended before its first row")
    case (handle, MyLSM.StreamSkip{cursor}):
      scan.failed(handle, cursor, "public scan skipped its first visible row")

def scan.opened(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Cursor>
) -> IO(Unit):
  match pair:
    case (handle, Done{cursor}):
      do IO<Unit>:
        first_step : MyLSM.Bytes.StreamStep <- MyLSM.Bytes.scan_next(cursor)
        first.step((handle, first_step))
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        fail("public scan did not open on the valid SST")

# Reopens the two-block fixture before starting the public cursor.
def reopened(
  result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>
) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        pair : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error,
          MyLSM.Bytes.Cursor> <- MyLSM.Bytes.scan_range(handle, None{}, None{})
        scan.opened(pair)
    case Fail{_}: fail("scan-error database did not reopen")

def writer.closed(result: Result<&1, &1, MyLSM.Bytes.Error, Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}:
      do IO<Unit>:
        path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
        opened : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
          MyLSM.Bytes.open_existing(path)
        reopened(opened)
    case Fail{_}: fail("scan-error fixture writer did not close")

# Closes the fixture writer before reopening its published SST.
def published(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        writer.closed(closed)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        fail("scan-error fixture flush failed")

def second.flushed(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        flushed : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.flush(handle)
        published(flushed)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        fail("second large SST record write failed")

def second.written(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        flushed : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.flush(handle)
        second.flushed(flushed)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        fail("second large SST record write failed")

def first.flushed(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        written : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.put(handle, bytes("62"), Bytes.new(700000))
        second.written(written)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        fail("first large SST record flush failed")

def first.written(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        flushed : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.flush(handle)
        first.flushed(flushed)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        fail("first large SST record write failed")

# Seeds and publishes two large values in separate SST blocks.
def created(
  result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>
) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        written : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.put(handle, bytes("61"), Bytes.new(700000))
        first.written(written)
    case Fail{_}: fail("scan-error fixture database create failed")

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
      MyLSM.Bytes.create(path)
    created(result)

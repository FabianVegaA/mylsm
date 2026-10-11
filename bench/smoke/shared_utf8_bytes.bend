import Base
import ../../mylsm.bend as MyLSM
import bend-kit-bytes@0.3.2.0/bytes.bend as PackedBytes
import ../../src/Console.bend as Console

def bytes.parsed(result: Maybe<&1, PackedBytes.Bytes>) -> PackedBytes.Bytes:
  match result:
    case Some{value}: value
    case None{}: PackedBytes.new(0)

# Decodes a closed hexadecimal byte fixture.
def bytes(hex: String) -> PackedBytes.Bytes:
  bytes.parsed(PackedBytes.from_hex(hex))

def verify.closed(result: Result<&1, &1, MyLSM.Utf8.Error, Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.print("SHARED_UTF8_BYTES_PASSED")
    case Fail{_}: IO.die(Unit, 1, "shared UTF-8 handle could not close")

def verify.scan.terminal.error(
  handle: MyLSM.Utf8.Handle,
  cursor: MyLSM.Utf8.Cursor,
  error: MyLSM.Utf8.Error
) -> IO(Unit):
  match error:
    case MyLSM.InvalidUtf8{}:
      do IO<Unit>:
        _closed_cursor : MyLSM.Utf8.Cursor & Result<&1, &1, MyLSM.Utf8.Error, Unit> <-
          MyLSM.Utf8.scan_close(cursor)
        result : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        verify.closed(result)
    case _:
      do IO<Unit>:
        _closed_cursor : MyLSM.Utf8.Cursor & Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.scan_close(cursor)
        _closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        IO.die(Unit, 1, "UTF-8 scan returned an unexpected terminal error")

def verify.scan.terminal(
  handle: MyLSM.Utf8.Handle,
  step: MyLSM.Utf8.ScanStep
) -> IO(Unit):
  match step:
    case MyLSM.Utf8ScanFailure{error, cursor}:
      verify.scan.terminal.error(handle, cursor, error)
    case _:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        IO.die(Unit, 1, "UTF-8 scan did not remain terminal after decode failure")

def verify.scan.failure(
  handle: MyLSM.Utf8.Handle,
  cursor: MyLSM.Utf8.Cursor,
  error: MyLSM.Utf8.Error
) -> IO(Unit):
  match error:
    case MyLSM.InvalidUtf8{}:
      do IO<Unit>:
        step : MyLSM.Utf8.ScanStep <- MyLSM.Utf8.scan_next(cursor)
        verify.scan.terminal(handle, step)
    case _:
      do IO<Unit>:
        _closed_cursor : MyLSM.Utf8.Cursor & Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.scan_close(cursor)
        _closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        IO.die(Unit, 1, "UTF-8 scan returned an unexpected decode error")

def verify.scan.closed(
  handle: MyLSM.Utf8.Handle,
  step: MyLSM.Utf8.ScanStep
) -> IO(Unit):
  match step:
    case MyLSM.Utf8ScanFailure{error, failed_cursor}:
      verify.scan.failure(handle, failed_cursor, error)
    case MyLSM.Utf8ScanItem{_, _, cursor}:
      do IO<Unit>:
        _closed_cursor : MyLSM.Utf8.Cursor & Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.scan_close(cursor)
        _closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        IO.die(Unit, 1, "UTF-8 scan did not reject invalid stored data")
    case MyLSM.Utf8ScanSkip{cursor}:
      do IO<Unit>:
        _closed_cursor : MyLSM.Utf8.Cursor & Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.scan_close(cursor)
        _closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        IO.die(Unit, 1, "UTF-8 scan skipped the invalid stored value")
    case MyLSM.Utf8ScanEnd{cursor}:
      do IO<Unit>:
        _closed_cursor : MyLSM.Utf8.Cursor & Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.scan_close(cursor)
        _closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        IO.die(Unit, 1, "UTF-8 scan ended before the invalid stored value")

def verify.scan.value(
  handle: MyLSM.Utf8.Handle,
  cursor: MyLSM.Utf8.Cursor,
  equal: Bool
) -> IO(Unit):
      match equal:
        case True{}:
          do IO<Unit>:
            step : MyLSM.Utf8.ScanStep <- MyLSM.Utf8.scan_next(cursor)
            verify.scan.closed(handle, step)
        case False{}:
          do IO<Unit>:
            _closed_cursor : MyLSM.Utf8.Cursor & Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.scan_close(cursor)
            _closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
            IO.die(Unit, 1, "UTF-8 scan changed a valid value")
def verify.scan.item(
  handle: MyLSM.Utf8.Handle,
  step: MyLSM.Utf8.ScanStep
) -> IO(Unit):
  match step:
    case MyLSM.Utf8ScanItem{key, value, cursor}:
      verify.scan.value(handle, cursor,
        String.eq(key, "valid") && String.eq(value, "á"))
    case _:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        IO.die(Unit, 1, "UTF-8 scan did not return its first item")

def verify.scan.opened(
  pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Cursor>
) -> IO(Unit):
  match pair:
    case (handle, Done{cursor}):
      do IO<Unit>:
        step : MyLSM.Utf8.ScanStep <- MyLSM.Utf8.scan_next(cursor)
        verify.scan.item(handle, step)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        IO.die(Unit, 1, "UTF-8 scan range could not open")

def verify.snapshot.value(
  handle: MyLSM.Utf8.Handle,
  snapshot: MyLSM.Utf8.Snapshot,
  valid: Bool
) -> IO(Unit):
  match valid:
    case True{}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <-
          MyLSM.Utf8.snapshot.close(snapshot)
        pair : MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Cursor> <-
          MyLSM.Utf8.scan_range(handle, Some{"valid"}, None{})
        verify.scan.opened(pair)
    case False{}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <-
          MyLSM.Utf8.snapshot.close(snapshot)
        _handle : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        IO.die(Unit, 1, "UTF-8 snapshot changed its text value")

def verify.snapshot.read(
  handle: MyLSM.Utf8.Handle,
  pair: MyLSM.Utf8.Snapshot & Result<&1, &1, MyLSM.Utf8.Error, Maybe<&1, String>>
) -> IO(Unit):
  match pair:
    case (snapshot, Done{Some{value}}):
      verify.snapshot.value(handle, snapshot, String.eq(value, "á"))
    case (snapshot, _):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <-
          MyLSM.Utf8.snapshot.close(snapshot)
        _handle : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        IO.die(Unit, 1, "UTF-8 snapshot omitted its text value")

def verify.snapshot.opened(
  pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Snapshot>
) -> IO(Unit):
  match pair:
    case (handle, Done{snapshot}):
      do IO<Unit>:
        value : MyLSM.Utf8.Snapshot &
          Result<&1, &1, MyLSM.Utf8.Error, Maybe<&1, String>> <-
            MyLSM.Utf8.snapshot.get(snapshot, "valid")
        verify.snapshot.read(handle, value)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        IO.die(Unit, 1, "UTF-8 snapshot could not be retained")

def verify.invalid(pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Maybe<&2, String>>) -> IO(Unit):
  match pair:
    case (handle, Fail{MyLSM.InvalidUtf8{}}):
      do IO<Unit>:
        result : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        verify.closed(result)
    case (handle, _):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        IO.die(Unit, 1, "UTF-8 facade accepted invalid stored bytes")

def verify.value(handle: MyLSM.Utf8.Handle, equal: Bool) -> IO(Unit):
  match equal:
    case True{}:
      do IO<Unit>:
        result : MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error,
          MyLSM.Utf8.Snapshot> <- MyLSM.Utf8.snapshot(handle)
        verify.snapshot.opened(result)
    case False{}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        IO.die(Unit, 1, "UTF-8 facade changed shared byte data")

def verify.utf8(pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Maybe<&2, String>>) -> IO(Unit):
  match pair:
    case (handle, Done{Some{value}}):
      verify.value(handle, String.eq(value, "á"))
    case (handle, _):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        IO.die(Unit, 1, "UTF-8 facade could not read shared byte data")

# Reads the valid text key after opening the byte-written database.
def opened(result: Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle>) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        pair : MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Maybe<&2, String>> <-
          MyLSM.Utf8.get(handle, "valid")
        verify.utf8(pair)
    case Fail{_}: IO.die(Unit, 1, "UTF-8 facade could not open byte database")

# Opens the database through the text facade after byte writes close.
def closed(result: Result<&1, &1, MyLSM.Bytes.Error, Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}:
      do IO<Unit>:
        path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
        result : Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle> <- MyLSM.Utf8.open_existing(path)
        opened(result)
    case Fail{_}: IO.die(Unit, 1, "byte database could not close")

# Closes the byte handle after the cross-facade seed batch is flushed.
def flushed(pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        result : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        closed(result)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "byte database rejected shared values")

# Publishes the shared byte fixture to SST before the text reader opens it.
def written(pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        result : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.flush(handle)
        flushed(result)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "byte database rejected shared values")

# Seeds one valid and one invalid UTF-8 value using raw bytes.
def created(result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        pair : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.write_batch(handle, Con{
            MyLSM.BytesPut{bytes("76616c6964"), bytes("c3a1")},
            Con{MyLSM.BytesPut{bytes("7a2d696e76616c6964"), bytes("80")}, Nil{}}})
        written(pair)
    case Fail{_}: IO.die(Unit, 1, "byte database could not open")

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <- MyLSM.Bytes.create(path)
    created(result)

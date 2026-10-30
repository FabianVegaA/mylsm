import Base
import ../../mylsm.bend as MyLSM
import ../../src/Console.bend as Console
import ../../src/Fs.bend as Fs
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Carries the state for Resources.
type Resources is Type:
  Resources{handle: MyLSM.Bytes.Handle,
    snapshot: MyLSM.Bytes.Snapshot,
    cursor: MyLSM.Bytes.Cursor,
    private_cursor: MyLSM.Bytes.Cursor,
    text_handle: MyLSM.Utf8.Handle,
    text_snapshot: MyLSM.Utf8.Snapshot,
    text_cursor: MyLSM.Utf8.Cursor,
    text_seek_cursor: MyLSM.Utf8.Cursor}

def ready.bytes(parsed: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match parsed:
    case Some{bytes}: bytes
    case None{}: Bytes.new(1)

# Handles fail.
def fail(message: String) -> IO(Unit):
  IO.die(Unit, 1, message)

def ready.pipe.closed(
  pair: File & Result<&1, &1, U32 & String, Unit>
) -> IO(Unit):
  match pair:
    case (file, Fail{_}):
      do IO<Unit>:
        _closed : Unit <- File.close(file)
        IO.die(Unit, 1, "could not publish owner generation readiness")
    case (file, Done{Unit{}}):
      do IO<Unit>:
        _closed : Unit <- File.close(file)
        return Unit{}

def ready.pipe.opened(
  result: Result<&1, &1, U32 & String, File>
) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "could not open owner generation readiness pipe")
    case Done{file}:
      do IO<Unit>:
        written : File & Result<&1, &1, U32 & String, Unit> <-
          Fs.write_bytes(file, ready.bytes(Bytes.from_hex("72656164790a")))
        ready.pipe.closed(written)

def ready.pipe(path: String) -> IO(Unit):
  do IO<Unit>:
    opened : Result<&1, &1, U32 & String, File> <- File.open(path, "w")
    ready.pipe.opened(opened)

def opened.text.second.cursor.result(
  pair: MyLSM.Utf8.Snapshot &
    Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Cursor>,
  handle: MyLSM.Utf8.Handle,
  byte_handle: MyLSM.Bytes.Handle,
  snapshot: MyLSM.Bytes.Snapshot,
  cursor: MyLSM.Bytes.Cursor,
  private_cursor: MyLSM.Bytes.Cursor,
  text_cursor: MyLSM.Utf8.Cursor
) -> IO(Resources):
  match pair:
    case (_, Fail{_}):
      IO.die(Resources, 1, "could not create second public text generation cursor")
    case (text_snapshot, Done{text_seek_cursor}):
      IO.pure(Resources, Resources{byte_handle, snapshot, cursor,
        private_cursor, handle, text_snapshot, text_cursor, text_seek_cursor})

def opened.text.second.cursor(
  handle: MyLSM.Utf8.Handle,
  text_snapshot: MyLSM.Utf8.Snapshot,
  byte_handle: MyLSM.Bytes.Handle,
  snapshot: MyLSM.Bytes.Snapshot,
  cursor: MyLSM.Bytes.Cursor,
  private_cursor: MyLSM.Bytes.Cursor,
  text_cursor: MyLSM.Utf8.Cursor
) -> IO(Resources):
  do IO<Resources>:
    pair : MyLSM.Utf8.Snapshot &
      Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Cursor> <-
        MyLSM.Utf8.snapshot.scan_range(text_snapshot, None{}, None{})
    opened.text.second.cursor.result(pair, handle, byte_handle, snapshot,
      cursor, private_cursor, text_cursor)

def opened.text.cursor.result(
  pair: MyLSM.Utf8.Snapshot &
    Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Cursor>,
  handle: MyLSM.Utf8.Handle,
  byte_handle: MyLSM.Bytes.Handle,
  snapshot: MyLSM.Bytes.Snapshot,
  cursor: MyLSM.Bytes.Cursor,
  private_cursor: MyLSM.Bytes.Cursor
) -> IO(Resources):
  match pair:
    case (_, Fail{_}):
      IO.die(Resources, 1, "could not create public text generation cursor")
    case (text_snapshot, Done{text_cursor}):
      opened.text.second.cursor(handle, text_snapshot, byte_handle, snapshot,
        cursor, private_cursor, text_cursor)

def opened.text.cursor(
  handle: MyLSM.Utf8.Handle,
  text_snapshot: MyLSM.Utf8.Snapshot,
  byte_handle: MyLSM.Bytes.Handle,
  snapshot: MyLSM.Bytes.Snapshot,
  cursor: MyLSM.Bytes.Cursor,
  private_cursor: MyLSM.Bytes.Cursor
) -> IO(Resources):
  do IO<Resources>:
    pair : MyLSM.Utf8.Snapshot &
      Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Cursor> <-
        MyLSM.Utf8.snapshot.scan_range(text_snapshot, None{}, None{})
    opened.text.cursor.result(pair, handle, byte_handle, snapshot, cursor,
      private_cursor)

def opened.text.snapshot.result(
  pair: MyLSM.Utf8.Handle &
    Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Snapshot>,
  byte_handle: MyLSM.Bytes.Handle,
  snapshot: MyLSM.Bytes.Snapshot,
  cursor: MyLSM.Bytes.Cursor,
  private_cursor: MyLSM.Bytes.Cursor
) -> IO(Resources):
  match pair:
    case (_, Fail{_}):
      IO.die(Resources, 1, "could not create public text generation snapshot")
    case (handle, Done{text_snapshot}):
      opened.text.cursor(handle, text_snapshot, byte_handle, snapshot, cursor,
        private_cursor)

def opened.text.handle.result(
  result: Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle>,
  byte_handle: MyLSM.Bytes.Handle,
  snapshot: MyLSM.Bytes.Snapshot,
  cursor: MyLSM.Bytes.Cursor,
  private_cursor: MyLSM.Bytes.Cursor
) -> IO(Resources):
  match result:
    case Fail{_}: IO.die(Resources, 1, "could not open public text generation handle")
    case Done{handle}:
      do IO<Resources>:
        pair : MyLSM.Utf8.Handle &
          Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Snapshot> <-
            MyLSM.Utf8.snapshot(handle)
        opened.text.snapshot.result(pair, byte_handle, snapshot, cursor,
          private_cursor)

def opened.text.snapshot(
  handle: MyLSM.Bytes.Handle,
  snapshot: MyLSM.Bytes.Snapshot,
  cursor: MyLSM.Bytes.Cursor,
  private_cursor: MyLSM.Bytes.Cursor
) -> IO(Resources):
  do IO<Resources>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle> <-
      MyLSM.Utf8.open_existing_wait(path, 5000, 10)
    opened.text.handle.result(result, handle, snapshot, cursor, private_cursor)

def opened.private.result(
  pair: MyLSM.Bytes.Handle &
    Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Cursor>,
  snapshot: MyLSM.Bytes.Snapshot,
  cursor: MyLSM.Bytes.Cursor
) -> IO(Resources):
  match pair:
    case (_, Fail{_}):
      IO.die(Resources, 1, "could not create private public generation cursor")
    case (handle, Done{private_cursor}):
      opened.text.snapshot(handle, snapshot, cursor, private_cursor)

def opened.private(
  handle: MyLSM.Bytes.Handle,
  snapshot: MyLSM.Bytes.Snapshot,
  cursor: MyLSM.Bytes.Cursor
) -> IO(Resources):
  do IO<Resources>:
    pair : MyLSM.Bytes.Handle &
      Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Cursor> <-
        MyLSM.Bytes.scan_open(handle,
          MyLSM.ScanBounds{None{}, None{}, None{}})
    opened.private.result(pair, snapshot, cursor)

def opened.cursor.result(
  handle: MyLSM.Bytes.Handle,
  ready_path: String,
  pair: MyLSM.Bytes.Snapshot &
    Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Cursor>
) -> IO(Resources):
  match pair:
    case (_, Fail{_}):
      IO.die(Resources, 1, "could not create public generation cursor")
    case (retained_snapshot, Done{cursor}):
      do IO<Resources>:
        _ready : Unit <- ready.pipe(ready_path)
        opened.private(handle, retained_snapshot, cursor)

def opened.cursor(
  handle: MyLSM.Bytes.Handle,
  snapshot: MyLSM.Bytes.Snapshot,
  ready_path: String
) -> IO(Resources):
  do IO<Resources>:
    opened : MyLSM.Bytes.Snapshot &
      Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Cursor> <-
        MyLSM.Bytes.snapshot.scan_range(snapshot, None{}, None{})
    opened.cursor.result(handle, ready_path, opened)

def opened.snapshot(
  pair: MyLSM.Bytes.Handle &
    Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Snapshot>,
  +ready_path: String
) -> IO(Resources):
  match pair:
    case (_, Fail{_}):
      IO.die(Resources, 1, "could not create public generation snapshot")
    case (handle, Done{snapshot}):
      do IO<Resources>:
        _ready : Unit <- ready.pipe(ready_path)
        opened.cursor(handle, snapshot, ready_path)

def opened.handle(
  result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>,
  +ready_path: String
) -> IO(Resources):
  match result:
    case Fail{_}:
      IO.die(Resources, 1, "could not open public generation handle")
    case Done{handle}:
      do IO<Resources>:
        _ready : Unit <- ready.pipe(ready_path)
        pair : MyLSM.Bytes.Handle &
          Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Snapshot> <-
            MyLSM.Bytes.snapshot(handle)
        opened.snapshot(pair, ready_path)

# Handles barrier.
def barrier(marker: String, ready_path: String) -> IO(Unit):
  do IO<Unit>:
    _ready : Unit <- ready.pipe(ready_path)
    _printed : Unit <- IO.print(marker)
    _line : String <- IO.try(String, Console.read_line())
    return Unit{}

# Handles stale.
def stale(error: MyLSM.Bytes.Error) -> Bool:
  match error:
    case MyLSM.StaleOwner{}: True{}
    case _: False{}

def stale.text(error: MyLSM.Utf8.Error) -> Bool:
  match error:
    case MyLSM.Utf8Failure{inner}: stale(inner)
    case _: False{}

def old.text.snapshot.get.error(
  snapshot: MyLSM.Utf8.Snapshot,
  rejected: Bool
) -> IO(MyLSM.Utf8.Snapshot):
  match rejected:
    case True{}: IO.pure(MyLSM.Utf8.Snapshot, snapshot)
    case False{}: IO.die(MyLSM.Utf8.Snapshot, 1,
      "public text snapshot get returned the wrong error")

def old.handle.get.error(
  handle: MyLSM.Bytes.Handle,
  rejected: Bool
) -> IO(MyLSM.Bytes.Handle):
  match rejected:
    case True{}: IO.pure(MyLSM.Bytes.Handle, handle)
    case False{}: IO.die(MyLSM.Bytes.Handle, 1,
      "old public handle reconnected after owner generation changed")

def old.handle.get(
  pair: MyLSM.Bytes.Handle &
    Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, Bytes.Bytes>>
) -> IO(MyLSM.Bytes.Handle):
  match pair:
    case (handle, Fail{error}):
      old.handle.get.error(handle, stale(error))
    case (_, Done{_}):
      IO.die(MyLSM.Bytes.Handle, 1,
        "old public handle read accepted a stale generation")

def old.handle.put.error(
  handle: MyLSM.Bytes.Handle,
  rejected: Bool
) -> IO(MyLSM.Bytes.Handle):
  match rejected:
    case True{}: IO.pure(MyLSM.Bytes.Handle, handle)
    case False{}: IO.die(MyLSM.Bytes.Handle, 1,
      "old public mutation was not rejected before owner dispatch")

def old.handle.put(
  pair: MyLSM.Bytes.Handle &
    Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(MyLSM.Bytes.Handle):
  match pair:
    case (handle, Fail{error}):
      old.handle.put.error(handle, stale(error))
    case (_, Done{Unit{}}):
      IO.die(MyLSM.Bytes.Handle, 1,
        "old public mutation succeeded after owner generation changed")

def old.text.snapshot.close.error(rejected: Bool) -> IO(Unit):
  match rejected:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: fail("public text snapshot close returned the wrong error")

def old.text.cursor.seek.error(
  cursor: MyLSM.Utf8.Cursor,
  rejected: Bool
) -> IO(MyLSM.Utf8.Cursor):
  match rejected:
    case True{}: IO.pure(MyLSM.Utf8.Cursor, cursor)
    case False{}: IO.die(MyLSM.Utf8.Cursor, 1,
      "public text cursor seek returned the wrong error")

def old.text.cursor.next.error(
  cursor: MyLSM.Utf8.Cursor,
  rejected: Bool
) -> IO(MyLSM.Utf8.Cursor):
  match rejected:
    case True{}: IO.pure(MyLSM.Utf8.Cursor, cursor)
    case False{}: IO.die(MyLSM.Utf8.Cursor, 1,
      "public text cursor next returned the wrong error")

def old.text.cursor.close.error(rejected: Bool) -> IO(Unit):
  match rejected:
    case True{}: IO.print("OWNER_GENERATION_STALE_TEXT_TOKENS_REJECTED")
    case False{}: fail("public text cursor close returned the wrong error")

def old.text.snapshot.get(
  pair: MyLSM.Utf8.Snapshot &
    Result<&1, &1, MyLSM.Utf8.Error, Maybe<&1, String>>
) -> IO(MyLSM.Utf8.Snapshot):
  match pair:
    case (snapshot, Fail{error}):
      old.text.snapshot.get.error(snapshot, stale.text(error))
    case (_, Done{_}):
      IO.die(MyLSM.Utf8.Snapshot, 1,
        "public text snapshot get accepted a stale token")

def old.text.snapshot.close(
  result: Result<&1, &1, MyLSM.Utf8.Error, Unit>
) -> IO(Unit):
  match result:
    case Fail{error}:
      old.text.snapshot.close.error(stale.text(error))
    case Done{Unit{}}: fail("public text snapshot close accepted a stale token")

def old.text.cursor.seek(
  pair: MyLSM.Utf8.Cursor &
    Result<&1, &1, MyLSM.Utf8.Error, Unit>
) -> IO(MyLSM.Utf8.Cursor):
  match pair:
    case (cursor, Fail{error}):
      old.text.cursor.seek.error(cursor, stale.text(error))
    case (_, Done{Unit{}}):
      IO.die(MyLSM.Utf8.Cursor, 1,
        "public text cursor seek accepted a stale token")

def old.text.cursor.next(step: MyLSM.Utf8.ScanStep) -> IO(MyLSM.Utf8.Cursor):
  match step:
    case MyLSM.Utf8ScanFailure{error, cursor}:
      old.text.cursor.next.error(cursor, stale.text(error))
    case _: IO.die(MyLSM.Utf8.Cursor, 1,
      "public text cursor next accepted a stale token")

def old.text.cursor.close(
  pair: MyLSM.Utf8.Cursor &
    Result<&1, &1, MyLSM.Utf8.Error, Unit>
) -> IO(Unit):
  match pair:
    case (_, Fail{error}):
      old.text.cursor.close.error(stale.text(error))
    case (_, Done{Unit{}}):
      fail("public text cursor close accepted a stale token")

def old.text.handle.close(
  result: Result<&1, &1, MyLSM.Utf8.Error, Unit>
) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.print("OWNER_GENERATION_PUBLIC_TOKENS_REJECTED")
    case Fail{_}: fail("public text handle close failed")

def old.text.checked(
  handle: MyLSM.Utf8.Handle,
  snapshot: MyLSM.Utf8.Snapshot,
  cursor: MyLSM.Utf8.Cursor,
  seek_cursor: MyLSM.Utf8.Cursor
) -> IO(Unit):
  do IO<Unit>:
    get_result : MyLSM.Utf8.Snapshot &
      Result<&1, &1, MyLSM.Utf8.Error, Maybe<&1, String>> <-
        MyLSM.Utf8.snapshot.get(snapshot, "")
    snapshot_after_get : MyLSM.Utf8.Snapshot <- old.text.snapshot.get(get_result)
    next_result : MyLSM.Utf8.ScanStep <- MyLSM.Utf8.scan_next(cursor)
    cursor_after_next : MyLSM.Utf8.Cursor <- old.text.cursor.next(next_result)
    close_cursor : MyLSM.Utf8.Cursor &
      Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.scan_close(cursor_after_next)
    _cursor_close : Unit <- old.text.cursor.close(close_cursor)
    seek_result : MyLSM.Utf8.Cursor &
      Result<&1, &1, MyLSM.Utf8.Error, Unit> <-
        MyLSM.Utf8.scan_seek(seek_cursor, None{})
    cursor_after_seek : MyLSM.Utf8.Cursor <- old.text.cursor.seek(seek_result)
    seek_close : MyLSM.Utf8.Cursor &
      Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.scan_close(cursor_after_seek)
    _seek_close : Unit <- old.text.cursor.close(seek_close)
    close_snapshot : Result<&1, &1, MyLSM.Utf8.Error, Unit> <-
      MyLSM.Utf8.snapshot.close(snapshot_after_get)
    _snapshot_close : Unit <- old.text.snapshot.close(close_snapshot)
    close_handle : Result<&1, &1, MyLSM.Utf8.Error, Unit> <-
      MyLSM.Utf8.close(handle)
    old.text.handle.close(close_handle)

def old.get.snapshot.error(
  snapshot: MyLSM.Bytes.Snapshot,
  rejected: Bool
) -> IO(MyLSM.Bytes.Snapshot):
  match rejected:
    case True{}: IO.pure(MyLSM.Bytes.Snapshot, snapshot)
    case False{}: IO.die(MyLSM.Bytes.Snapshot, 1,
      "public snapshot get did not reject the stale generation")

def old.get.snapshot(
  pair: MyLSM.Bytes.Snapshot &
    Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, Bytes.Bytes>>
) -> IO(MyLSM.Bytes.Snapshot):
  match pair:
    case (snapshot, Fail{error}):
      old.get.snapshot.error(snapshot, stale(error))
    case (_, Done{_}):
      IO.die(MyLSM.Bytes.Snapshot, 1,
        "public snapshot get accepted the stale generation")

def old.snapshot.close.error(rejected: Bool) -> IO(Unit):
  match rejected:
    case True{}: IO.print("OWNER_GENERATION_STALE_SNAPSHOT_REJECTED")
    case False{}: fail("public snapshot close returned the wrong error")

def old.snapshot.close(
  result: Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match result:
    case Fail{error}:
      old.snapshot.close.error(stale(error))
    case Done{Unit{}}: fail("public snapshot close accepted a stale token")

def old.cursor.seek.error(
  cursor: MyLSM.Bytes.Cursor,
  rejected: Bool
) -> IO(MyLSM.Bytes.Cursor):
  match rejected:
    case True{}: IO.pure(MyLSM.Bytes.Cursor, cursor)
    case False{}: IO.die(MyLSM.Bytes.Cursor, 1,
      "public cursor seek returned the wrong error")

def old.cursor.seek(
  pair: MyLSM.Bytes.Cursor &
    Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(MyLSM.Bytes.Cursor):
  match pair:
    case (cursor, Fail{error}):
      old.cursor.seek.error(cursor, stale(error))
    case (_, Done{Unit{}}):
      IO.die(MyLSM.Bytes.Cursor, 1,
        "public cursor seek accepted a stale token")

def old.cursor.next.error(
  cursor: MyLSM.Bytes.Cursor,
  rejected: Bool
) -> IO(MyLSM.Bytes.Cursor):
  match rejected:
    case True{}: IO.pure(MyLSM.Bytes.Cursor, cursor)
    case False{}: IO.die(MyLSM.Bytes.Cursor, 1,
      "public cursor next returned the wrong error")

def old.cursor.next(step: MyLSM.Bytes.StreamStep) -> IO(MyLSM.Bytes.Cursor):
  match step:
    case MyLSM.StreamFailure{error, cursor}:
      old.cursor.next.error(cursor, stale(error))
    case _: IO.die(MyLSM.Bytes.Cursor, 1,
      "public cursor next accepted a stale token")

def old.cursor.close.error(rejected: Bool) -> IO(Unit):
  match rejected:
    case True{}: IO.print("OWNER_GENERATION_STALE_CURSOR_REJECTED")
    case False{}: fail("public cursor close returned the wrong error")

def old.cursor.close(
  result: Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match result:
    case Fail{error}:
      old.cursor.close.error(stale(error))
    case Done{Unit{}}: fail("public cursor close accepted a stale token")

def old.handle.close(
  result: Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.pure(Unit, Unit{})
    case Fail{_}: fail("public handle close failed")

def old.checked(resources: Resources) -> IO(Unit):
  match resources:
    case Resources{handle, snapshot, cursor, private_cursor, text_handle,
      text_snapshot, text_cursor, text_seek_cursor}:
      do IO<Unit>:
        handle_result : MyLSM.Bytes.Handle &
          Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, Bytes.Bytes>> <-
            MyLSM.Bytes.get(handle, Bytes.new(0))
        handle_after_get : MyLSM.Bytes.Handle <- old.handle.get(handle_result)
        put_result : MyLSM.Bytes.Handle &
          Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
            MyLSM.Bytes.put(handle_after_get, Bytes.new(112), Bytes.new(111))
        handle_after_put : MyLSM.Bytes.Handle <- old.handle.put(put_result)
        get_result : MyLSM.Bytes.Snapshot &
          Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, Bytes.Bytes>> <-
            MyLSM.Bytes.snapshot.get(snapshot, Bytes.new(0))
        get_snapshot_after : MyLSM.Bytes.Snapshot <-
          old.get.snapshot(get_result)
        seek_result : MyLSM.Bytes.Cursor &
          Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
            MyLSM.Bytes.scan_seek(cursor, None{})
        cursor_after_seek : MyLSM.Bytes.Cursor <- old.cursor.seek(seek_result)
        next_result : MyLSM.Bytes.StreamStep <-
          MyLSM.Bytes.scan_next(cursor_after_seek)
        cursor_after_next : MyLSM.Bytes.Cursor <- old.cursor.next(next_result)
        close_cursor : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.scan_close(cursor_after_next)
        _cursor_close : Unit <- old.cursor.close(close_cursor)
        private_seek_result : MyLSM.Bytes.Cursor &
          Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
            MyLSM.Bytes.scan_seek(private_cursor, None{})
        private_after_seek : MyLSM.Bytes.Cursor <- old.cursor.seek(private_seek_result)
        private_next_result : MyLSM.Bytes.StreamStep <-
          MyLSM.Bytes.scan_next(private_after_seek)
        private_after_next : MyLSM.Bytes.Cursor <- old.cursor.next(private_next_result)
        private_close : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.scan_close(private_after_next)
        _private_close : Unit <- old.cursor.close(private_close)
        final_snapshot_close : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.snapshot.close(get_snapshot_after)
        _snapshot_close : Unit <- old.snapshot.close(final_snapshot_close)
        closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle_after_put)
        _closed : Unit <- old.handle.close(closed)
        old.text.checked(text_handle, text_snapshot, text_cursor, text_seek_cursor)

def old.run(resources: Resources, ready_path: String) -> IO(Unit):
  do IO<Unit>:
    _barrier : Unit <- barrier("READY_OLD_PUBLIC_TOKENS", ready_path)
    old.checked(resources)

def fresh.snapshot.get(
  pair: MyLSM.Bytes.Snapshot &
    Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, Bytes.Bytes>>
) -> IO(MyLSM.Bytes.Snapshot):
  match pair:
    case (snapshot, Done{None{}}): IO.pure(MyLSM.Bytes.Snapshot, snapshot)
    case _: IO.die(MyLSM.Bytes.Snapshot, 1,
      "fresh public snapshot could not read the empty database")

def fresh.handle.get(
  pair: MyLSM.Bytes.Handle &
    Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, Bytes.Bytes>>
) -> IO(MyLSM.Bytes.Handle):
  match pair:
    case (handle, Done{None{}}): IO.pure(MyLSM.Bytes.Handle, handle)
    case _: IO.die(MyLSM.Bytes.Handle, 1,
      "fresh public handle could not read the empty database")

def fresh.snapshot.close(
  result: Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.pure(Unit, Unit{})
    case _: fail("fresh public snapshot could not close")

def fresh.cursor.next(step: MyLSM.Bytes.StreamStep) -> IO(Unit):
  match step:
    case MyLSM.StreamEnd{_}: IO.print("OWNER_GENERATION_NEW_CURSOR_VALID")
    case _: fail("fresh public cursor could not read the empty database")

def fresh.cursor.seek(
  pair: MyLSM.Bytes.Cursor &
    Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(MyLSM.Bytes.Cursor):
  match pair:
    case (cursor, Done{Unit{}}): IO.pure(MyLSM.Bytes.Cursor, cursor)
    case _: IO.die(MyLSM.Bytes.Cursor, 1,
      "fresh public cursor seek failed")

def fresh.text.snapshot.get(
  pair: MyLSM.Utf8.Snapshot &
    Result<&1, &1, MyLSM.Utf8.Error, Maybe<&1, String>>
) -> IO(MyLSM.Utf8.Snapshot):
  match pair:
    case (snapshot, Done{None{}}): IO.pure(MyLSM.Utf8.Snapshot, snapshot)
    case _: IO.die(MyLSM.Utf8.Snapshot, 1,
      "fresh public text snapshot could not read the empty database")

def fresh.text.cursor.next(step: MyLSM.Utf8.ScanStep) -> IO(Unit):
  match step:
    case MyLSM.Utf8ScanEnd{_}: IO.pure(Unit, Unit{})
    case _: fail("fresh public text cursor could not read the empty database")

def fresh.text.cursor.seek(
  pair: MyLSM.Utf8.Cursor &
    Result<&1, &1, MyLSM.Utf8.Error, Unit>
) -> IO(MyLSM.Utf8.Cursor):
  match pair:
    case (cursor, Done{Unit{}}): IO.pure(MyLSM.Utf8.Cursor, cursor)
    case _: IO.die(MyLSM.Utf8.Cursor, 1,
      "fresh public text cursor seek failed")

def fresh.text.snapshot.close(
  result: Result<&1, &1, MyLSM.Utf8.Error, Unit>
) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.pure(Unit, Unit{})
    case _: fail("fresh public text snapshot could not close")

def fresh.text.handle.close(
  result: Result<&1, &1, MyLSM.Utf8.Error, Unit>
) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.print("OWNER_GENERATION_NEW_PUBLIC_TOKENS_VALID")
    case _: fail("fresh public text handle close failed")

def fresh.text.checked(
  handle: MyLSM.Utf8.Handle,
  snapshot: MyLSM.Utf8.Snapshot,
  cursor: MyLSM.Utf8.Cursor,
  seek_cursor: MyLSM.Utf8.Cursor
) -> IO(Unit):
  do IO<Unit>:
    get_result : MyLSM.Utf8.Snapshot &
      Result<&1, &1, MyLSM.Utf8.Error, Maybe<&1, String>> <-
        MyLSM.Utf8.snapshot.get(snapshot, "")
    snapshot_after_get : MyLSM.Utf8.Snapshot <-
      fresh.text.snapshot.get(get_result)
    next_result : MyLSM.Utf8.ScanStep <- MyLSM.Utf8.scan_next(cursor)
    _next : Unit <- fresh.text.cursor.next(next_result)
    seek_result : MyLSM.Utf8.Cursor &
      Result<&1, &1, MyLSM.Utf8.Error, Unit> <-
        MyLSM.Utf8.scan_seek(seek_cursor, None{})
    seek_cursor_after : MyLSM.Utf8.Cursor <- fresh.text.cursor.seek(seek_result)
    seek_next : MyLSM.Utf8.ScanStep <- MyLSM.Utf8.scan_next(seek_cursor_after)
    _seek_next : Unit <- fresh.text.cursor.next(seek_next)
    close_snapshot : Result<&1, &1, MyLSM.Utf8.Error, Unit> <-
      MyLSM.Utf8.snapshot.close(snapshot_after_get)
    _snapshot_close : Unit <- fresh.text.snapshot.close(close_snapshot)
    close_handle : Result<&1, &1, MyLSM.Utf8.Error, Unit> <-
      MyLSM.Utf8.close(handle)
    fresh.text.handle.close(close_handle)

def fresh.handle.close(
  result: Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.pure(Unit, Unit{})
    case Fail{_}: fail("fresh public handle close failed")

def fresh.checked(resources: Resources) -> IO(Unit):
  match resources:
    case Resources{handle, snapshot, cursor, private_cursor, text_handle,
      text_snapshot, text_cursor, text_seek_cursor}:
      do IO<Unit>:
        get_result : MyLSM.Bytes.Handle &
          Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, Bytes.Bytes>> <-
            MyLSM.Bytes.get(handle, Bytes.new(0))
        handle_after_get : MyLSM.Bytes.Handle <- fresh.handle.get(get_result)
        stale_write_check : MyLSM.Bytes.Handle &
          Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, Bytes.Bytes>> <-
            MyLSM.Bytes.get(handle_after_get, Bytes.new(112))
        handle_after_stale_write_check : MyLSM.Bytes.Handle <-
          fresh.handle.get(stale_write_check)
        snapshot_result : MyLSM.Bytes.Snapshot &
          Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, Bytes.Bytes>> <-
            MyLSM.Bytes.snapshot.get(snapshot, Bytes.new(0))
        snapshot_after_get : MyLSM.Bytes.Snapshot <-
          fresh.snapshot.get(snapshot_result)
        seek_result : MyLSM.Bytes.Cursor &
          Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
            MyLSM.Bytes.scan_seek(cursor, None{})
        cursor_after_seek : MyLSM.Bytes.Cursor <- fresh.cursor.seek(seek_result)
        next_result : MyLSM.Bytes.StreamStep <-
          MyLSM.Bytes.scan_next(cursor_after_seek)
        _cursor_next : Unit <- fresh.cursor.next(next_result)
        private_next_result : MyLSM.Bytes.StreamStep <-
          MyLSM.Bytes.scan_next(private_cursor)
        _private_next : Unit <- fresh.cursor.next(private_next_result)
        snapshot_close : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.snapshot.close(snapshot_after_get)
        _snapshot_close : Unit <- fresh.snapshot.close(snapshot_close)
        handle_close : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle_after_stale_write_check)
        _handle_close : Unit <- fresh.handle.close(handle_close)
        fresh.text.checked(text_handle, text_snapshot, text_cursor,
          text_seek_cursor)

def fresh.run(resources: Resources, ready_path: String) -> IO(Unit):
  do IO<Unit>:
    _barrier : Unit <- barrier("READY_NEW_PUBLIC_TOKENS", ready_path)
    fresh.checked(resources)

# Handles dispatch.
def dispatch(mode: String, resources: Resources, ready_path: String) -> IO(Unit):
  match mode:
    case "old": old.run(resources, ready_path)
    case "new": fresh.run(resources, ready_path)
    case _: fail("unknown owner generation token fixture mode")

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    mode : String <- IO.try(String, Console.get_env("MYLSM_OWNER_TOKEN_MODE"))
    +ready_path : String <- IO.try(String, Console.get_env("MYLSM_READY_PIPE_PATH"))
    result : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
      MyLSM.Bytes.open_existing_wait(path, 5000, 10)
    resources : Resources <- opened.handle(result, ready_path)
    dispatch(mode, resources, ready_path)

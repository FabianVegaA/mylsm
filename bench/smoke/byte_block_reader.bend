import Base
import ../../mylsm.bend as MyLSM
import ../../src/Console.bend as Console
import ../../src/ByteMemTable.bend as ByteMemTable
import ../../src/scan/ByteBlockReader.bend as ByteBlockReader
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

def equal.result(comparison: Bytes.Bytes & Bytes.Bytes & Bool) -> Bool:
  match comparison:
    case (_, _, equal): equal

# Converts a fixed hexadecimal test vector into its packed byte value.
def packed(result: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match result:
    case Some{bytes}: bytes
    case None{}: Bytes.new(0)

def error.closed(
  handle: MyLSM.Bytes.Handle,
  result: Result<&1, &1, MyLSM.Bytes.Error, Unit>,
  message: String
) -> IO(Unit):
  match result:
    case Fail{_}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, message)
    case Done{Unit{}}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, message)

def check.entry.end(result: ByteBlockReader.EntryStep) -> IO(Unit):
  match result:
    case ByteBlockReader.EntryEnd{}: IO.print("BYTE_BLOCK_READER_PASSED")
    case ByteBlockReader.EntryError{ByteBlockReader.EntryFailed{(_, message)}}:
      IO.die(Unit, 1, message)
    case _:
      IO.die(Unit, 1, "byte entry reader returned an unexpected third entry")

def check.entry.second(fuel: Nat, result: ByteBlockReader.EntryStep) -> IO(Unit):
  match fuel:
    case 0n: IO.die(Unit, 1, "byte entry reader exceeded its block budget")
    case 1n+rest:
      match result:
        case ByteBlockReader.EntryItem{_, cursor}:
          do IO<Unit>:
            next : ByteBlockReader.EntryStep <- ByteBlockReader.entry.next(cursor)
            check.entry.end(next)
        case ByteBlockReader.EntrySkip{cursor}:
          do IO<Unit>:
            next : ByteBlockReader.EntryStep <- ByteBlockReader.entry.next(cursor)
            check.entry.second(rest, next)
        case _:
          IO.die(Unit, 1, "byte entry reader ended before its second entry")

def check.entry.first(fuel: Nat, result: ByteBlockReader.EntryStep) -> IO(Unit):
  match fuel:
    case 0n: IO.die(Unit, 1, "byte entry reader exceeded its block budget")
    case 1n+rest:
      match result:
        case ByteBlockReader.EntryItem{_, cursor}:
          do IO<Unit>:
            next : ByteBlockReader.EntryStep <- ByteBlockReader.entry.next(cursor)
            check.entry.second(rest, next)
        case ByteBlockReader.EntrySkip{cursor}:
          do IO<Unit>:
            next : ByteBlockReader.EntryStep <- ByteBlockReader.entry.next(cursor)
            check.entry.first(rest, next)
        case _:
          IO.die(Unit, 1, "byte entry reader ended before its first entry")

def check.selected.end(result: ByteBlockReader.EntryStep) -> IO(Unit):
  match result:
    case ByteBlockReader.EntryEnd{}: IO.print("BYTE_BLOCK_READER_PASSED")
    case ByteBlockReader.EntryError{ByteBlockReader.EntryFailed{(_, message)}}:
      IO.die(Unit, 1, message)
    case _: IO.die(Unit, 1, "indexed block seek did not stop at the file end")

def check.selected.key(cursor: ByteBlockReader.EntryCursor, valid: Bool) -> IO(Unit):
  match valid:
    case False{}: IO.die(Unit, 1, "indexed block seek returned the wrong key")
    case True{}:
      do IO<Unit>:
        next : ByteBlockReader.EntryStep <- ByteBlockReader.entry.next(cursor)
        check.selected.end(next)

def check.selected.entry(result: ByteBlockReader.EntryStep) -> IO(Unit):
  match result:
    case ByteBlockReader.EntryItem{ByteMemTable.Entry{key, _}, cursor}:
      check.selected.key(cursor,
        equal.result(Bytes.eq(key, packed(Bytes.from_hex("0000")))))
    case ByteBlockReader.EntryError{ByteBlockReader.EntryFailed{(_, message)}}:
      IO.die(Unit, 1, message)
    case _: IO.die(Unit, 1, "indexed block seek returned no entry")

def check.selected(
  selected: Result<&1, &1, U32 & String, ByteBlockReader.Reader>
) -> IO(Unit):
  match selected:
    case Fail{(_, message)}: IO.die(Unit, 1, message)
    case Done{reader}:
      do IO<Unit>:
        next : ByteBlockReader.EntryStep <-
          ByteBlockReader.entry.next(ByteBlockReader.entry.open(reader))
        check.selected.entry(next)

def check.reopened(
  result: Result<&1, &1, U32 & String, ByteBlockReader.Reader>
) -> IO(Result<&1, &1, U32 & String, ByteBlockReader.Reader>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, ByteBlockReader.Reader>, Fail{error})
    case Done{reader}: ByteBlockReader.seek_block_after_validation(reader, 1)

def check.invalid.reader(
  result: Result<&1, &1, U32 & String, ByteBlockReader.Reader>
) -> IO(Result<&1, &1, U32 & String, ByteBlockReader.Reader>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, ByteBlockReader.Reader>, Fail{error})
    case Done{reader}:
      ByteBlockReader.seek_block_after_validation(reader, 2)

def check.invalid.ordinal(
  +path: String,
  result: Result<&1, &1, U32 & String, ByteBlockReader.Reader>
) -> IO(Unit):
  match result:
    case Fail{_}:
      do IO<Unit>:
        reopened : Result<&1, &1, U32 & String, ByteBlockReader.Reader> <-
          ByteBlockReader.open(path)
        seeked : Result<&1, &1, U32 & String, ByteBlockReader.Reader> <-
          check.reopened(reopened)
        check.selected(seeked)
    case Done{reader}:
      do IO<Unit>:
        _closed : Result<&1, &1, U32 & String, Unit> <- ByteBlockReader.close(reader)
        IO.die(Unit, 1, "indexed block seek accepted an ordinal at the block count")

def check.seek.after.validation(
  fuel: Nat,
  +path: String,
  result: Result<&1, &1, U32 & String, ByteBlockReader.Step>
) -> IO(Unit):
  match fuel:
    case 0n: IO.die(Unit, 1, "byte SST validation exceeded its block budget")
    case 1n+rest:
      match result:
        case Fail{(_, message)}: IO.die(Unit, 1, message)
        case Done{ByteBlockReader.End{}}:
          do IO<Unit>:
            invalid_reader : Result<&1, &1, U32 & String, ByteBlockReader.Reader> <-
              ByteBlockReader.open(path)
            invalid : Result<&1, &1, U32 & String, ByteBlockReader.Reader> <-
              check.invalid.reader(invalid_reader)
            check.invalid.ordinal(path, invalid)
        case Done{ByteBlockReader.Block{reader, _}}:
          do IO<Unit>:
            next : Result<&1, &1, U32 & String, ByteBlockReader.Step> <-
              ByteBlockReader.next(reader)
            check.seek.after.validation(rest, path, next)

def check.opened(
  opened: Result<&1, &1, U32 & String, ByteBlockReader.Reader>,
  path: String
) -> IO(Unit):
  match opened:
    case Fail{(_, message)}:
      do IO<Unit>:
        IO.print(message)
        IO.die(Unit, 1, "byte block reader could not open the SST")
    case Done{reader}:
      do IO<Unit>:
        validated : Result<&1, &1, U32 & String, ByteBlockReader.Step> <-
          ByteBlockReader.next(reader)
        check.seek.after.validation(16n, path, validated)

def database.closed(
  handle: MyLSM.Bytes.Handle,
  result: Result<&1, &1, MyLSM.Bytes.Error, Unit>,
  +path: String
) -> IO(Unit):
  match result:
    case Fail{_}:
      error.closed(handle, result, "byte block reader fixture flush failed")
    case Done{Unit{}}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        reader : Result<&1, &1, U32 & String, ByteBlockReader.Reader> <-
          ByteBlockReader.open(path ++ "/SST")
        check.opened(reader, path ++ "/SST")

def database.flushed(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>,
  +path: String
) -> IO(Unit):
  match pair:
    case (handle, result):
      database.closed(handle, result, path)

def database.written(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>,
  +path: String
) -> IO(Unit):
  match pair:
    case (handle, Fail{error}):
      error.closed(handle, Fail{error}, "byte block reader fixture write failed")
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        flushed : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.flush(handle)
        database.flushed(flushed, path)

def database.first.put(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>,
  +path: String
) -> IO(Unit):
  match pair:
    case (handle, Fail{error}):
      error.closed(handle, Fail{error}, "byte block reader first page write failed")
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        second : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.put(handle, Bytes.new(2), Bytes.new(600000))
        database.written(second, path)

def database.write(
  result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>,
  +path: String
) -> IO(Unit):
  match result:
    case Fail{_}:
      IO.die(Unit, 1, "byte block reader fixture create failed")
    case Done{handle}:
      do IO<Unit>:
        first : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.put(handle, Bytes.new(1), Bytes.new(600000))
        database.first.put(first, path)


# Starts the byte database fixture after acquiring a temporary directory.
def created(
  result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>,
  +path: String
) -> IO(Unit):
  database.write(result, path)

def main() -> IO(Unit):
  do IO<Unit>:
    +path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
      MyLSM.Bytes.create(path)
    created(result, path)

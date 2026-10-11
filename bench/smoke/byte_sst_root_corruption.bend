import Base
import ../../src/ByteMemTable.bend as ByteMemTable
import ../../src/ByteSstFile.bend as ByteSstFile
import ../../src/Console.bend as Console
import ../../src/Fs.bend as Fs
import ../../src/scan/ByteBlockReader.bend as Reader
import ../../src/scan/SstCursor.bend as SstCursor
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Stops the fixture when root corruption is accepted or misclassified.
def fail(message: String) -> IO(Unit):
  IO.die(Unit, 1, message)

# Removes the damaged file after the reader reaches its terminal error.
def removed(result: Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match result:
    case Fail{_}: fail("root checksum fixture could not remove the SST")
    case Done{Unit{}}: IO.print("BYTE_SST_ROOT_CORRUPTION_PASSED")

# Requires the trailer read to reject the modified root checksum.
def root.result(fuel: Nat, +path: String, result: Result<&1, &1, U32 & String, Reader.Step>) -> IO(Unit):
  match fuel:
    case 0n: fail("root checksum fixture exceeded its block budget")
    case 1n+rest:
      match result:
        case Fail{(_, "byte SST root checksum mismatch")}:
          do IO<Unit>:
            removed_file : Result<&1, &1, U32 & String, Unit> <- Fs.remove(path)
            removed(removed_file)
        case Fail{_}: fail("SST root corruption returned the wrong error")
        case Done{Reader.Block{reader, _}}:
          do IO<Unit>:
            next : Result<&1, &1, U32 & String, Reader.Step> <- Reader.next(reader)
            root.result(rest, path, next)
        case Done{Reader.End{}}: fail("corrupt SST root reached End")

# Reads the validated block and then checks the damaged footer.
def opened(+path: String, result: Result<&1, &1, U32 & String, Reader.Reader>) -> IO(Unit):
  match result:
    case Fail{_}: fail("root checksum fixture could not open the SST")
    case Done{reader}:
      do IO<Unit>:
        next : Result<&1, &1, U32 & String, Reader.Step> <- Reader.next(reader)
        root.result(4n, path, next)

# Rejects a corrupt root before publishing any streaming cursor.
def cursor.checked(
  +path: String,
  result: Result<&1, &1, U32 & String, SstCursor.Cursor>
) -> IO(Unit):
  match result:
    case Fail{(_, "byte SST root checksum mismatch")}:
      do IO<Unit>:
        reader : Result<&1, &1, U32 & String, Reader.Reader> <- Reader.open(path)
        opened(path, reader)
    case Fail{_}: fail("SST cursor returned the wrong root checksum error")
    case Done{cursor}:
      do IO<Unit>:
        _closed : Result<&1, &1, U32 & String, Unit> <- SstCursor.close(cursor)
        fail("SST cursor exposed a table with a corrupt root checksum")

# Writes the corrupted bytes and opens the incremental reader.
def persisted(+path: String, pair: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match pair:
    case (file, Fail{_}):
      do IO<Unit>:
        _closed : Unit <- File.close(file)
        fail("root checksum fixture could not write the SST")
    case (file, Done{Unit{}}):
      do IO<Unit>:
        _closed : Unit <- File.close(file)
        result : Result<&1, &1, U32 & String, SstCursor.Cursor> <-
          SstCursor.open(path, SstCursor.Bounds{None{}, None{}, None{}})
        cursor.checked(path, result)

# Creates the fixture file and persists one corrupted generation-four SST.
def persist.file(
  +path: String,
  bytes: Bytes.Bytes,
  opened: Result<&1, &1, U32 & String, File>
) -> IO(Unit):
  match opened:
    case Fail{_}: fail("root checksum fixture could not create the SST")
    case Done{file}:
      do IO<Unit>:
        pair : File & Result<&1, &1, U32 & String, Unit> <- Fs.write_bytes(file, bytes)
        persisted(path, pair)

# Opens the temporary path and passes its raw write result to Bend handling.
def persist(+path: String, bytes: Bytes.Bytes) -> IO(Unit):
  do IO<Unit>:
    opened : Result<&1, &1, U32 & String, File> <- File.open(path, "w")
    persist.file(path, bytes, opened)

# Flips the final byte after measuring the packed file.
def encoded.length(+path: String, pair: Bytes.Bytes & U32) -> IO(Unit):
  match pair:
    case (input, size):
      persist(path, Bytes.set(input, U32.sub(size, 1), 255))

# Writes a valid table with only the final root digest changed.
def encoded(+path: String, result: Result<&1, &1, ByteSstFile.Error, Bytes.Bytes>) -> IO(Unit):
  match result:
    case Fail{_}: fail("root checksum fixture could not encode the SST")
    case Done{bytes}:
      encoded.length(path, Bytes.length(bytes))

def main() -> IO(Unit):
  do IO<Unit>:
    +directory : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    encoded(directory ++ "/root-corrupt.sst",
      ByteSstFile.encode_file.limit(
        Con{ByteMemTable.Entry{Bytes.new(1), Some{Bytes.new(1)}}, Nil{}}, 0, 60n))

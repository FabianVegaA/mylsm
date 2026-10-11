import Base
import ../../src/ByteMemTable.bend as ByteMemTable
import ../../src/ByteSstFile.bend as ByteSstFile
import ../../src/Console.bend as Console
import ../../src/Fs.bend as Fs
import ../../src/scan/ByteBlockReader.bend as ByteBlockReader
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Terminates the fixture with a precise validation failure.
def fail(message: String) -> IO(Unit):
  IO.die(Unit, 1, message)

def read.result(
  result: Result<&1, &1, U32 & String, ByteBlockReader.Step>
) -> IO(Unit):
  match result:
    case Fail{(_, "byte SST block checksum mismatch")}:
      IO.print("BYTE_BLOCK_CORRUPTION_PASSED")
    case Fail{_}: fail("corruption fixture returned the wrong error")
    case Done{ByteBlockReader.Block{reader, _}}:
      do IO<Unit>:
        _closed : Result<&1, &1, U32 & String, Unit> <- ByteBlockReader.close(reader)
        fail("corrupt block entries escaped validation")
    case Done{ByteBlockReader.End{}}:
      fail("corrupt SST unexpectedly reached End")

def read.opened(
  opened: Result<&1, &1, U32 & String, ByteBlockReader.Reader>
) -> IO(Unit):
  match opened:
    case Fail{_}: fail("corruption fixture reader open failed")
    case Done{reader}:
      do IO<Unit>:
        result : Result<&1, &1, U32 & String, ByteBlockReader.Step> <-
          ByteBlockReader.next(reader)
        read.result(result)

# Opens the damaged SST and requests its first block.
def read(path: String) -> IO(Unit):
  do IO<Unit>:
    opened : Result<&1, &1, U32 & String, ByteBlockReader.Reader> <-
      ByteBlockReader.open(path)
    read.opened(opened)

def persist.result(
  read_path: String,
  pair: File & Result<&1, &1, U32 & String, Unit>
) -> IO(Unit):
  match pair:
    case (write_file, Fail{_}):
      do IO<Unit>:
        _closed : Unit <- File.close(write_file)
        fail("corruption fixture could not write SST")
    case (write_file, Done{Unit{}}):
      do IO<Unit>:
        _closed : Unit <- File.close(write_file)
        read(read_path)

def persist.opened(
  read_path: String,
  bytes: Bytes.Bytes,
  opened: Result<&1, &1, U32 & String, File>
) -> IO(Unit):
  match opened:
    case Fail{_}: fail("corruption fixture could not create SST")
    case Done{file}:
      do IO<Unit>:
        pair : File & Result<&1, &1, U32 & String, Unit> <- Fs.write_bytes(file, bytes)
        persist.result(read_path, pair)

# Writes one corrupted encoded SST to the fixture directory.
def persist(path: String, read_path: String, bytes: Bytes.Bytes) -> IO(Unit):
  do IO<Unit>:
    opened : Result<&1, &1, U32 & String, File> <- File.open(path, "w")
    persist.opened(read_path, bytes, opened)

# Corrupts a data byte while preserving the encoded block checksum.
def checked(
  path: String,
  read_path: String,
  encoded: Result<&1, &1, ByteSstFile.Error, Bytes.Bytes>
) -> IO(Unit):
  match encoded:
    case Fail{_}: fail("corruption fixture encoding failed")
    case Done{bytes}:
      persist(path, read_path, Bytes.set(bytes, 28, 255))

def main() -> IO(Unit):
  do IO<Unit>:
    +directory : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    +read_directory : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    checked(directory ++ "/invalid.sst", read_directory ++ "/invalid.sst",
      ByteSstFile.encode_file.limit(
      Con{ByteMemTable.Entry{Bytes.new(1), Some{Bytes.new(1)}}, Nil{}}, 0, 60n))

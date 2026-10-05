import Base
import ../../src/Fs.bend as Fs
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Stop the smoke test when an IO assertion fails.
def require(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, message)

# Check a write result and keep its returned file handle.
def checked_write(pair: File & Result<&1, &1, U32 & String, Unit>) -> IO(File):
  match pair:
    case (handle, result):
      do IO<File>:
        IO.pass(Unit, result)
        return handle

# Check exact bytes and keep the returned file handle.
def checked_read(pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>, want: String) -> IO(File):
  match pair:
    case (handle, result):
      do IO<File>:
        data : Bytes.Bytes <- IO.pass(Bytes.Bytes, result)
        require(String.eq(Bytes.to_hex(data), want), "packed read has wrong bytes")
        return handle

# Unwrap one valid fixture or build an empty packed buffer.
def fixture(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{data}:
      data
    case None{}:
      Bytes.Bytes{0, Bytes.alloc(0)}

def main() -> IO(Unit):
  do IO<Unit>:
    +path : String = ".mylsm/build/storage-bytes-smoke.bin"
    file : File <- IO.try(File, File.open(path, "w"))
    pair : File & Result<&1, &1, U32 & String, Unit> <-
      Fs.write_bytes(file, fixture(Bytes.from_hex("")))
    file : File <- checked_write(pair)
    pair : File & Result<&1, &1, U32 & String, Unit> <-
      Fs.write_bytes(file, fixture(Bytes.from_hex("00")))
    file : File <- checked_write(pair)
    pair : File & Result<&1, &1, U32 & String, Unit> <-
      Fs.write_bytes(file, fixture(Bytes.from_hex("80ff01")))
    file : File <- checked_write(pair)
    pair : File & Result<&1, &1, U32 & String, Unit> <-
      Fs.write_bytes(file, fixture(Bytes.from_hex("02030405")))
    file : File <- checked_write(pair)
    pair : File & Result<&1, &1, U32 & String, Unit> <-
      Fs.write_bytes(file, fixture(Bytes.from_hex("06070809fe")))
    file : File <- checked_write(pair)
    File.close(file)
    file : File <- IO.try(File, File.open(path, "r"))
    pair : File & Result<&1, &1, U32 & String, Bytes.Bytes> <- Fs.read_bytes(file, 1)
    file : File <- checked_read(pair, "00")
    pair : File & Result<&1, &1, U32 & String, Bytes.Bytes> <- Fs.read_bytes(file, 4)
    file : File <- checked_read(pair, "80ff0102")
    pair : File & Result<&1, &1, U32 & String, Bytes.Bytes> <- Fs.read_bytes(file, 5)
    file : File <- checked_read(pair, "0304050607")
    pair : File & Result<&1, &1, U32 & String, Bytes.Bytes> <- Fs.read_bytes(file, 5)
    file : File <- checked_read(pair, "0809fe")
    pair : File & Result<&1, &1, U32 & String, Bytes.Bytes> <- Fs.read_bytes(file, 5)
    file : File <- checked_read(pair, "")
    File.close(file)
    IO.try(Unit, Fs.remove(path))
    IO.print("packed storage IO smoke ok")

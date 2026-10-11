import Base
import ../../src/Console.bend as Console
import ../../src/Fs.bend as Fs
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Closes the fixture handle before reporting an assertion failure.
def fail(file: File, message: String) -> IO(Unit):
  do IO<Unit>:
    _closed : Unit <- File.close(file)
    IO.die(Unit, 1, message)

# Extracts equality from the byte library comparison result.
def equal(pair: Bytes.Bytes & Bytes.Bytes & Bool) -> Bool:
  match pair:
    case (_, _, same): same

# Converts a fixed fixture literal to its packed byte buffer.
def packed(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}: bytes
    case None{}: Bytes.new(0)

def sequential.check(file: File, matches: Bool) -> IO(Unit):
  match matches:
    case True{}:
      do IO<Unit>:
        _closed : Unit <- File.close(file)
        IO.print("BYTE_SST_READ_AT_PASSED")
    case False{}: fail(file, "positional read changed the file position")

# Verifies the random read did not change the sequential file position.
def sequential(
  file: File,
  result: Result<&1, &1, U32 & String, Bytes.Bytes>
) -> IO(Unit):
  match result:
    case Fail{_}: fail(file, "sequential read failed after positional read")
    case Done{header}:
      sequential.check(file, equal(Bytes.eq(header, packed(Bytes.from_hex(
        "4d594c534d345300000000000000000200000002")))))

def sequential.pair(
  pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>
) -> IO(Unit):
  match pair:
    case (handle, result): sequential(handle, result)

def invalid_range.pair(
  pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>
) -> IO(Unit):
  match pair:
    case (file, Fail{(22, _)}):
      do IO<Unit>:
        header : File & Result<&1, &1, U32 & String, Bytes.Bytes> <-
          Fs.read_bytes(file, 20)
        sequential.pair(header)
    case (file, _): fail(file, "overflowing positional range was accepted")

def positional_read.length(file: File, valid: Bool) -> IO(Unit):
  match valid:
    case False{}: fail(file, "positional read returned the wrong length")
    case True{}:
      do IO<Unit>:
        rejected : File & Result<&1, &1, U32 & String, Bytes.Bytes> <-
          Fs.read_at(file, 4294967295, 2)
        invalid_range.pair(rejected)

def block_header.pair(
  pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>
) -> IO(Unit):
  match pair:
    case (file, Fail{_}): fail(file, "positional SST read failed")
    case (file, Done{block_header}):
      match block_header:
        case Bytes.Bytes{len, _}:
          positional_read.length(file, U32.is_eq(len, 600000))

# Reads the first block by offset, then checks sequential reading starts at zero.
def opened(result: Result<&1, &1, U32 & String, File>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "SST could not be opened for positional read")
    case Done{file}:
      do IO<Unit>:
        pair : File & Result<&1, &1, U32 & String, Bytes.Bytes> <-
          Fs.read_at(file, 20, 600000)
        block_header.pair(pair)

def main() -> IO(Unit):
  do IO<Unit>:
    +directory : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, U32 & String, File> <-
      File.open(directory ++ "/SST", "r")
    opened(result)

import Base
import ../../src/Console.bend as Console
import ../../src/Fs.bend as Fs
import ../../src/scan/ByteBlockReader.bend as Reader

# Fails the fixture when file-backed truncation is accepted or cannot be read.
def fail(message: String) -> IO(Unit):
  IO.die(Unit, 1, message)

# Reopens the path after a terminal read error to check reader cleanup.
def reopened.check(result: Result<&1, &1, U32 & String, Reader.Reader>) -> IO(Unit):
  match result:
    case Fail{_}: fail("block reader remained unavailable after truncation")
    case Done{reader}:
      do IO<Unit>:
        _closed : Result<&1, &1, U32 & String, Unit> <- Reader.close(reader)
        IO.print("BYTE_BLOCK_TRUNCATION_PASSED")

# Walks the bounded reader until the truncated trailer is rejected.
def terminal(fuel: Nat, +path: String, result: Result<&1, &1, U32 & String, Reader.Step>) -> IO(Unit):
  match fuel:
    case 0n: fail("truncated SST did not terminate within its block budget")
    case 1n+rest:
      match result:
        case Fail{_}:
          do IO<Unit>:
            reopened : Result<&1, &1, U32 & String, Reader.Reader> <- Reader.open(path)
            reopened.check(reopened)
        case Done{Reader.End{}}: fail("truncated SST reached End")
        case Done{Reader.Block{reader, _}}:
          do IO<Unit>:
            next : Result<&1, &1, U32 & String, Reader.Step> <- Reader.next(reader)
            terminal(rest, path, next)

# Opens the truncated fixture and starts its bounded read.
def opened(result: Result<&1, &1, U32 & String, Reader.Reader>, +path: String) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("BYTE_BLOCK_TRUNCATION_PASSED")
    case Done{reader}:
      do IO<Unit>:
        next : Result<&1, &1, U32 & String, Reader.Step> <- Reader.next(reader)
        terminal(16n, path, next)

# Handles the host truncation result before reopening the file.
def truncated.result(
  +path: String,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Unit):
  match result:
    case Fail{_}: fail("could not truncate SST fixture")
    case Done{Unit{}}:
      do IO<Unit>:
        reader : Result<&1, &1, U32 & String, Reader.Reader> <- Reader.open(path)
        opened(reader, path)

# Rejects a fixture too small to hold a generation-four SST header and footer.
def truncated.sized(+path: String, +size: Nat, large: Bool) -> IO(Unit):
  match large:
    case False{}: fail("SST fixture is too small to truncate")
    case True{}:
      do IO<Unit>:
        changed : Result<&1, &1, U32 & String, Unit> <- Fs.truncate(path, Nat.sub(size, 1n))
        truncated.result(path, changed)

# Measures and truncates the SST by one byte before streaming validation.
def truncated(+path: String, result: Result<&1, &1, U32 & String, Nat>) -> IO(Unit):
  match result:
    case Fail{_}: fail("could not measure SST before truncation")
    case Done{+size}: truncated.sized(path, size, Nat.is_gt(size, 60n))

# Truncates the fixture selected by the smoke harness.
def main() -> IO(Unit):
  do IO<Unit>:
    +path : String <- IO.try(String, Console.get_env("MYLSM_SST_PATH"))
    size : Result<&1, &1, U32 & String, Nat> <- Fs.file_size(path)
    truncated(path, size)

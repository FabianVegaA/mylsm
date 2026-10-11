import Base
import ../../src/Console.bend as Console
import ../../src/ByteSstIo.bend as ByteSstIo
import ../../src/scan/ByteBlockReader.bend as ByteBlockReader

# Stops the fixture when streamed SST metadata is incomplete.
def fail(message: String) -> IO(Unit):
  IO.die(Unit, 1, message)

# Requires the reader to return compact metadata after full validation.
def checked(valid: Bool) -> IO(Unit):
  match valid:
    case True{}: IO.print("BYTE_SST_METADATA_PASSED")
    case False{}: fail("streamed SST metadata did not match the fixture")

# Checks table totals, block totals, and the data/index boundary.
def result(value: Result<&1, &1, U32 & String, ByteBlockReader.Metadata>) -> IO(Unit):
  match value:
    case Fail{_}: fail("streamed SST metadata validation failed")
    case Done{ByteBlockReader.Metadata{size, total, block_count, index_offset,
        live_entries, payload_bytes}}:
      checked(U32.is_eq(total, 2) && U32.is_eq(block_count, 2) &&
        Nat.is_gt(size, index_offset) && Nat.is_eq(live_entries, 2n) &&
        Nat.is_eq(payload_bytes, 1200003n))

# Validates the generation-four SST selected by the smoke harness.
def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_SST_PATH"))
    metadata : Result<&1, &1, U32 & String, ByteBlockReader.Metadata> <-
      ByteSstIo.validate(path)
    result(metadata)

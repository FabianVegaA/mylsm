import Base
import ../../src/Wal.bend as Wal
import ../../src/transfer/LegacyWal.bend as LegacyWal
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

def frame.bytes(result: Result<&1, &1, Wal.Error, Bytes.Bytes>) -> Bytes.Bytes:
  match result:
    case Done{bytes}: bytes
    case Fail{_}: Bytes.new(0)

# Builds a checksummed one-mutation generation-three WAL fixture.
def frame() -> Bytes.Bytes:
  Bytes.concat([Wal.log_header(), frame.bytes(Wal.encode_frame(
    Wal.Batch{Con{Wal.Put{"key", "value"}, Nil{}}}))])

def next.frame() -> Bytes.Bytes:
  frame.bytes(Wal.encode_frame(Wal.Batch{Con{Wal.Del{"other"}, Nil{}}}))

def multi.frame() -> Bytes.Bytes:
  Bytes.concat([frame(), next.frame()])

# Checks the decoded batches preserve their frame order and mutations.
def matches(result: LegacyWal.ReplayResult) -> Bool:
  match result:
    case LegacyWal.ReplayValid{Con{
        Wal.Batch{Con{Wal.Put{key, value}, Nil{}}},
        Con{Wal.Batch{Con{Wal.Del{deleted_key}, Nil{}}}, Nil{}}}}:
      String.eq(key, "key") && String.eq(value, "value") &&
        String.eq(deleted_key, "other")
    case _: False{}

# Fails the fixture when replay differs from the decoded source frames.
def pass(value: Bool) -> IO(Unit):
  match value:
    case True{}: IO.print("LEGACY_WAL_REPLAY_PASSED")
    case False{}: IO.die(Unit, 1, "legacy WAL replay differs from decoded frames")

def main() -> IO(Unit):
  pass(matches(LegacyWal.replay(multi.frame())))

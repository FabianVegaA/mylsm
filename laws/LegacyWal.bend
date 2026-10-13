import Base
import ../src/transfer/LegacyWal.bend as LegacyWal
import ../src/Wal.bend as Wal
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

def frame.bytes(result: Result<&1, &1, Wal.Error, Bytes.Bytes>) -> Bytes.Bytes:
  match result:
    case Done{bytes}: bytes
    case Fail{_}: Bytes.new(0)

def slice.second(pair: Bytes.Bytes & Bytes.Bytes) -> Bytes.Bytes:
  match pair:
    case (_, bytes): bytes

# Extracts the bounded byte length for truncation fixtures.
def length(pair: Bytes.Bytes & U32) -> U32:
  match pair:
    case (_, size): size

def one.batch.frame() -> Bytes.Bytes:
  frame.bytes(Wal.encode_frame(Wal.Batch{Con{Wal.Put{"a", "b"}, Nil{}}}))

def second.batch.frame() -> Bytes.Bytes:
  frame.bytes(Wal.encode_frame(Wal.Batch{Con{Wal.Del{"c"}, Nil{}}}))

def two.frames.empty(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}: bytes
    case None{}: Bytes.new(0)

def one.frame() -> Bytes.Bytes:
  Bytes.concat([Wal.log_header(), one.batch.frame()])

def two.frames() -> Bytes.Bytes:
  Bytes.concat([Wal.log_header(), two.frames.empty(Bytes.from_hex("0000002400000000b10689a773611ef6afdd983542da2b82a13d6133370d6abecbc1476b224b09ea")),
    two.frames.empty(Bytes.from_hex("0000002400000000b10689a773611ef6afdd983542da2b82a13d6133370d6abecbc1476b224b09ea"))])

def one.batch() -> Wal.Batch:
  Wal.Batch{Con{Wal.Put{"a", "b"}, Nil{}}}

def second.batch() -> Wal.Batch:
  Wal.Batch{Con{Wal.Del{"c"}, Nil{}}}

def corrupt.ending(pair: Bytes.Bytes & Maybe<&2, U32>, index: U32) -> Bytes.Bytes:
  match pair:
    case (bytes, None{}): bytes
    case (bytes, Some{value}):
      Bytes.set(bytes, index, Bool.pick(U32, U32.is_eq(value, 0), 1, 0))

def corrupt.sized(pair: Bytes.Bytes & U32) -> Bytes.Bytes:
  match pair:
    case (bytes, size):
      +last = (size - 1 : U32)
      corrupt.ending(Bytes.get(bytes, last), last)

def corrupt.checksum() -> Bytes.Bytes:
  corrupt.sized(Bytes.length(one.frame()))

# Accepts an empty legacy WAL with only its format header.
law empty_legacy_wal_is_valid:
  {LegacyWal.verify(Wal.log_header()) == LegacyWal.WalValid{0n} : LegacyWal.VerifyResult}

# Counts one complete checksummed legacy frame.
law one_complete_frame_is_valid:
  {LegacyWal.verify(one.frame()) == LegacyWal.WalValid{1n} : LegacyWal.VerifyResult}

# Replays the single checksummed frame to its original batch.
law one_frame_replays_its_batch:
  {LegacyWal.replay(one.frame()) == LegacyWal.ReplayValid{Con{one.batch(), Nil{}}} : LegacyWal.ReplayResult}

# Counts multiple consecutive checksummed frames.
law multiple_complete_frames_are_valid:
  {LegacyWal.verify(two.frames()) == LegacyWal.WalValid{2n} : LegacyWal.VerifyResult}

# Rejects a frame whose declared size extends beyond the input.
law truncated_frame_is_rejected:
  {LegacyWal.verify(slice.second(Bytes.slice(one.frame(), 0,
    (length(Bytes.length(one.frame())) - 1 : U32)))) ==
    LegacyWal.WalInvalid{} : LegacyWal.VerifyResult}

# Rejects a complete frame after one checksum byte changes.
law corrupt_frame_checksum_is_rejected:
  {LegacyWal.verify(corrupt.checksum()) ==
    LegacyWal.WalInvalid{} : LegacyWal.VerifyResult}

# Rejects a file without the generation-three WAL signature.
law unsupported_header_is_rejected:
  {LegacyWal.verify(Bytes.new(0)) == LegacyWal.WalInvalid{} : LegacyWal.VerifyResult}

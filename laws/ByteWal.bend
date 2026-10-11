import Base
import ../src/ByteWal.bend as ByteWal
import ../src/Wal.bend as Wal

# Accepts an exact frame containing one minimum-sized deletion record.
law exact_single_record_frame_is_valid:
  {ByteWal.frame.bounds.valid(41, 1, 45) == True{} : Bool}

# Rejects a record count that cannot fit in the declared frame payload.
law impossible_record_count_is_invalid:
  {ByteWal.frame.bounds.valid(41, 9, 45) == False{} : Bool}

# Rejects a frame whose external byte length disagrees with its header.
law mismatched_frame_length_is_invalid:
  {ByteWal.frame.bounds.valid(41, 1, 44) == False{} : Bool}

# Accepts the generation-four file identity.
law current_wal_header_is_accepted:
  {Result.is_done(&1, &1, Wal.Error, Unit, ByteWal.decode_header(ByteWal.header())) == True{} : Bool}

# Rejects the generation-three file identity from the byte decoder.
law legacy_wal_header_is_rejected:
  {Result.is_done(&1, &1, Wal.Error, Unit, ByteWal.decode_header(Wal.log_header())) == False{} : Bool}

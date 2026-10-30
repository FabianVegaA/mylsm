import Base
import ../src/ByteWal.bend as ByteWal
import ../src/Wal.bend as Wal
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

def measured.record.bytes(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}: bytes
    case None{}: Bytes.new(0)

def measured.put.record() -> Bytes.Bytes:
  measured.record.bytes(Bytes.from_hex("00000000016b000000027677"))

def measured.delete.record() -> Bytes.Bytes:
  measured.record.bytes(Bytes.from_hex("01000000016b"))

def measured.frame.result(
  result: Result<&1, &1, Wal.Error, Bytes.Bytes>
) -> Bytes.Bytes:
  match result:
    case Done{frame}: frame
    case Fail{_}: Bytes.new(0)

def measured.put.frame() -> Bytes.Bytes:
  measured.frame.result(ByteWal.encode(ByteWal.Batch{[
    ByteWal.Put{measured.record.bytes(Bytes.from_hex("61")),
      measured.record.bytes(Bytes.from_hex("31"))},
    ByteWal.Put{measured.record.bytes(Bytes.from_hex("61")),
      measured.record.bytes(Bytes.from_hex("3233"))}]}))

def measured.delete.frame() -> Bytes.Bytes:
  measured.frame.result(ByteWal.encode(ByteWal.Batch{[
    ByteWal.Delete{measured.record.bytes(Bytes.from_hex("61"))}]}))

def measured.frame.length(pair: Bytes.Bytes & U32) -> U32:
  match pair:
    case (_, length): length

def measured.corrupt.measured(pair: Bytes.Bytes & U32) -> Bytes.Bytes:
  match pair:
    case (frame, length):
      Bytes.set.u32be(frame, U32.sub(length, 4), 0)

def measured.corrupt.frame(frame: Bytes.Bytes) -> Bytes.Bytes:
  measured.corrupt.measured(Bytes.length(frame))

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

# Verifies value record metadata does not require value materialization.
law value_record_metadata_does_not_require_value_materialization:
  {ByteWal.record.measure(measured.put.record(), 0) ==
    Done{ByteWal.RecordMetadata{12, measured.record.bytes(
      Bytes.from_hex("6b")), True{}, 2}} :
      Result<&1, &1, Wal.Error, ByteWal.RecordMetadata>}

# Verifies malformed value length is rejected by metadata reader.
law malformed_value_length_is_rejected_by_metadata_reader:
  {ByteWal.record.measure(measured.record.bytes(
    Bytes.from_hex("00000000016b000000037677")), 0) ==
    Fail{Wal.Malformed{}} :
      Result<&1, &1, Wal.Error, ByteWal.RecordMetadata>}

# Verifies valid value metadata returns the exact end offset.
law valid_value_metadata_returns_the_exact_end_offset:
  for frame: Bytes.Bytes
  for key: Bytes.Bytes
  for value_length: U32
  for value_offset: U32
  {ByteWal.record.measure.value.result(frame, key, value_length,
      value_offset, True{}) == ByteWal.RecordMeasure{frame,
      Done{ByteWal.RecordMetadata{
        U32.add(U32.add(value_offset, 4), value_length), key, True{},
        value_length}}} : ByteWal.RecordMeasure}

# Verifies invalid value metadata returns malformed.
law invalid_value_metadata_returns_malformed:
  for frame: Bytes.Bytes
  for key: Bytes.Bytes
  for value_length: U32
  for value_offset: U32
  {ByteWal.record.measure.value.result(frame, key, value_length,
      value_offset, False{}) == ByteWal.RecordMeasure{frame,
      Fail{Wal.Malformed{}}} : ByteWal.RecordMeasure}

# Verifies record measurement retains its source frame.
law record_measurement_retains_its_source_frame:
  {ByteWal.record.measure.retained(measured.put.record(), 0) ==
    ByteWal.RecordMeasure{measured.put.record(),
      Done{ByteWal.RecordMetadata{12, measured.record.bytes(
        Bytes.from_hex("6b")), True{}, 2}}} : ByteWal.RecordMeasure}

# Verifies deletion metadata distinguishes absence from empty value.
law deletion_metadata_distinguishes_absence_from_empty_value:
  {ByteWal.record.measure(measured.delete.record(), 0) ==
    Done{ByteWal.RecordMetadata{6, measured.record.bytes(
      Bytes.from_hex("6b")), False{}, 0}} :
    Result<&1, &1, Wal.Error, ByteWal.RecordMetadata>}

# Verifies value lookup returns the last matching record length.
law value_lookup_returns_the_last_matching_record_length:
  {ByteWal.measure.lookup(measured.put.frame(),
    measured.record.bytes(Bytes.from_hex("61"))) ==
    Done{ByteWal.ValuePresent{2}} :
    Result<&1, &1, Wal.Error, ByteWal.ValueMetadata>}

# Verifies value lookup reports a tombstone.
law value_lookup_reports_a_tombstone:
  {ByteWal.measure.lookup(measured.delete.frame(),
    measured.record.bytes(Bytes.from_hex("61"))) ==
    Done{ByteWal.ValueDeleted{}} :
    Result<&1, &1, Wal.Error, ByteWal.ValueMetadata>}

# Verifies value lookup reports an absent key.
law value_lookup_reports_an_absent_key:
  {ByteWal.measure.lookup(measured.put.frame(),
    measured.record.bytes(Bytes.from_hex("7a"))) ==
    Done{ByteWal.ValueAbsent{}} :
    Result<&1, &1, Wal.Error, ByteWal.ValueMetadata>}

# Verifies value lookup rejects a corrupt frame checksum.
law value_lookup_rejects_a_corrupt_frame_checksum:
  {ByteWal.measure.lookup(measured.corrupt.frame(measured.put.frame()),
    measured.record.bytes(Bytes.from_hex("61"))) ==
    Fail{Wal.ChecksumMismatch{}} :
    Result<&1, &1, Wal.Error, ByteWal.ValueMetadata>}

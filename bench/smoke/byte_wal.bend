import Base
import ../../src/ByteWal.bend as ByteWal
import ../../src/Wal.bend as Wal
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Fails the codec fixture at the first mismatch.
def require(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, message)

# Turns a parsed hex literal into its owned byte value.
def packed(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}:
      bytes
    case None{}:
      Bytes.new(0)

def equal.result(comparison: Bytes.Bytes & Bytes.Bytes & Bool) -> Bool:
  match comparison:
    case (_, _, equal):
      equal

# Checks that a codec result matches its expected serialized bytes.
def encoded_as(result: Result<&1, &1, Wal.Error, Bytes.Bytes>, expected: Bytes.Bytes) -> Bool:
  match result:
    case Fail{_}:
      False{}
    case Done{bytes}:
      equal.result(Bytes.eq(bytes, expected))

# Compares both successful frame encodings byte for byte.
def frames_equal(
  left: Result<&1, &1, Wal.Error, Bytes.Bytes>,
  right: Result<&1, &1, Wal.Error, Bytes.Bytes>
) -> Bool:
  match left right:
    case Done{left_bytes} Done{right_bytes}:
      equal.result(Bytes.eq(left_bytes, right_bytes))
    case _ _:
      False{}

# Compares the generation-four WAL header to its golden vector.
def header_matches() -> Bool:
  equal.result(Bytes.eq(ByteWal.header(), packed(Bytes.from_hex("4d594c534d345700"))))

# Requires the generation-four WAL identity to be accepted.
def header_accepted(result: Result<&1, &1, Wal.Error, Unit>) -> Bool:
  Result.is_done(&1, &1, Wal.Error, Unit, result)

# Requires the generation-three WAL identity to be rejected.
def legacy_header_rejected(result: Result<&1, &1, Wal.Error, Unit>) -> Bool:
  match result:
    case Fail{Wal.Malformed{}}:
      True{}
    case _:
      False{}

# Validates the generation-four header and refuses the legacy signature.
def header_validation() -> Bool:
  header_accepted(ByteWal.decode_header(ByteWal.header())) &&
    legacy_header_rejected(ByteWal.decode_header(Wal.log_header()))

# Confirms a raw decoder preserves an arbitrary key and non-UTF-8 value.
def decoded_binary(result: Result<&1, &1, Wal.Error, ByteWal.Batch>) -> Bool:
  match result:
    case Fail{_}:
      False{}
    case Done{ByteWal.Batch{Con{ByteWal.Put{key, value}, Nil{}}}}:
      equal.result(Bytes.eq(key, packed(Bytes.from_hex("610062")))) &&
        equal.result(Bytes.eq(value, packed(Bytes.from_hex("80ff00"))))
    case _:
      False{}

# Encodes then decodes a binary key/value pair through the complete frame.
def binary_roundtrip.result(
  result: Result<&1, &1, Wal.Error, Bytes.Bytes>
) -> Bool:
  match result:
    case Fail{_}:
      False{}
    case Done{frame}:
      decoded_binary(ByteWal.decode(frame))

# Builds a binary frame fixture with bytes that are invalid UTF-8.
def binary_roundtrip() -> Bool:
  key = packed(Bytes.from_hex("610062"))
  value = packed(Bytes.from_hex("80ff00"))
  binary_roundtrip.result(ByteWal.encode(ByteWal.Batch{Con{ByteWal.Put{key, value}, Nil{}}}))

# Confirms a tombstone round trip keeps an empty binary key.
def decoded_empty_delete(result: Result<&1, &1, Wal.Error, ByteWal.Batch>) -> Bool:
  match result:
    case Done{ByteWal.Batch{Con{ByteWal.Delete{key}, Nil{}}}}:
      equal.result(Bytes.eq(key, Bytes.new(0)))
    case _:
      False{}

# Builds and decodes an empty-key tombstone frame.
def empty_delete_roundtrip.result(
  result: Result<&1, &1, Wal.Error, Bytes.Bytes>
) -> Bool:
  match result:
    case Fail{_}:
      False{}
    case Done{frame}:
      decoded_empty_delete(ByteWal.decode(frame))

# Encodes and decodes an empty-key tombstone.
def empty_delete_roundtrip() -> Bool:
  key = Bytes.new(0)
  empty_delete_roundtrip.result(ByteWal.encode(ByteWal.Batch{Con{ByteWal.Delete{key}, Nil{}}}))

# Requires a changed record byte to fail the frame checksum.
def checksum_rejected(result: Result<&1, &1, Wal.Error, ByteWal.Batch>) -> Bool:
  match result:
    case Fail{Wal.ChecksumMismatch{}}:
      True{}
    case _:
      False{}

# Corrupts a key byte without changing the frame structure.
def checksum_roundtrip.result(
  result: Result<&1, &1, Wal.Error, Bytes.Bytes>
) -> Bool:
  match result:
    case Fail{_}:
      False{}
    case Done{frame}:
      checksum_rejected(ByteWal.decode(Bytes.set(frame, 13, 0)))

# Builds a valid frame whose key byte will be changed before decoding.
def checksum_roundtrip() -> Bool:
  key = packed(Bytes.from_hex("610062"))
  value = packed(Bytes.from_hex("80ff00"))
  checksum_roundtrip.result(ByteWal.encode(ByteWal.Batch{Con{ByteWal.Put{key, value}, Nil{}}}))

# Confirms two decoded records retain input order and binary payloads.
def decoded_multi(result: Result<&1, &1, Wal.Error, ByteWal.Batch>) -> Bool:
  match result:
    case Done{ByteWal.Batch{Con{ByteWal.Delete{first}, Con{ByteWal.Put{key, value}, Nil{}}}}}:
      equal.result(Bytes.eq(first, Bytes.new(0))) &&
        equal.result(Bytes.eq(key, packed(Bytes.from_hex("610062")))) &&
        equal.result(Bytes.eq(value, packed(Bytes.from_hex("80ff00"))))
    case _:
      False{}

# Encodes and decodes a tombstone followed by a binary put.
def multi_roundtrip.result(
  result: Result<&1, &1, Wal.Error, Bytes.Bytes>
) -> Bool:
  match result:
    case Fail{_}:
      False{}
    case Done{frame}:
      decoded_multi(ByteWal.decode(frame))

# Builds a two-record batch to exercise count-bounded recursive decoding.
def multi_roundtrip() -> Bool:
  empty = Bytes.new(0)
  key = packed(Bytes.from_hex("610062"))
  value = packed(Bytes.from_hex("80ff00"))
  multi_roundtrip.result(ByteWal.encode(ByteWal.Batch{
    Con{ByteWal.Delete{empty}, Con{ByteWal.Put{key, value}, Nil{}}}}))

# Requires a malformed frame length to be rejected before record parsing.
def malformed_header_rejected(result: Result<&1, &1, Wal.Error, ByteWal.Batch>) -> Bool:
  match result:
    case Fail{Wal.Malformed{}}:
      True{}
    case _:
      False{}

# Builds a valid frame and then contradicts its declared length.
def malformed_header_roundtrip.result(
  result: Result<&1, &1, Wal.Error, Bytes.Bytes>
) -> Bool:
  match result:
    case Fail{_}:
      False{}
    case Done{frame}:
      malformed_header_rejected(ByteWal.decode(Bytes.set(frame, 3, 0)))

# Encodes a small binary batch before the header corruption check.
def malformed_header_roundtrip() -> Bool:
  key = packed(Bytes.from_hex("61"))
  value = packed(Bytes.from_hex("62"))
  malformed_header_roundtrip.result(ByteWal.encode(ByteWal.Batch{Con{ByteWal.Put{key, value}, Nil{}}}))

# Confirms the decoder distinguishes an empty value from a tombstone.
def decoded_empty_put(result: Result<&1, &1, Wal.Error, ByteWal.Batch>) -> Bool:
  match result:
    case Done{ByteWal.Batch{Con{ByteWal.Put{key, value}, Nil{}}}}:
      equal.result(Bytes.eq(key, Bytes.new(0))) &&
        equal.result(Bytes.eq(value, Bytes.new(0)))
    case _:
      False{}

# Encodes and decodes a present empty value under an empty key.
def empty_put_roundtrip.result(
  result: Result<&1, &1, Wal.Error, Bytes.Bytes>
) -> Bool:
  match result:
    case Fail{_}:
      False{}
    case Done{frame}:
      decoded_empty_put(ByteWal.decode(frame))

# Builds a one-record frame whose key and value are both empty.
def empty_put_roundtrip() -> Bool:
  key = Bytes.new(0)
  value = Bytes.new(0)
  empty_put_roundtrip.result(ByteWal.encode(ByteWal.Batch{Con{ByteWal.Put{key, value}, Nil{}}}))

def main() -> IO(Unit):
  do IO<Unit>:
    key : Bytes.Bytes <- IO.pure(Bytes.Bytes, packed(Bytes.from_hex("610062")))
    value : Bytes.Bytes <- IO.pure(Bytes.Bytes, packed(Bytes.from_hex("80ff00")))
    delete_key : Bytes.Bytes <- IO.pure(Bytes.Bytes, packed(Bytes.from_hex("610062")))
    ascii_key : Bytes.Bytes <- IO.pure(Bytes.Bytes, packed(Bytes.from_hex("61")))
    ascii_value : Bytes.Bytes <- IO.pure(Bytes.Bytes, packed(Bytes.from_hex("62")))
    expected_put : Bytes.Bytes <- IO.pure(Bytes.Bytes,
      packed(Bytes.from_hex("00000000036100620000000380ff00")))
    expected_delete : Bytes.Bytes <- IO.pure(Bytes.Bytes,
      packed(Bytes.from_hex("0100000003610062")))
    require(header_matches(), "generation-four WAL header must be distinct")
    require(header_validation(), "byte WAL header decoder must reject generation three")
    require(binary_roundtrip(), "byte WAL decode must preserve non-UTF-8 records")
    require(empty_delete_roundtrip(), "byte WAL decode must preserve empty binary tombstones")
    require(checksum_roundtrip(), "byte WAL decode must reject a changed record checksum")
    require(multi_roundtrip(), "byte WAL decoder must preserve multi-record order")
    require(malformed_header_roundtrip(), "byte WAL decoder must reject malformed frame lengths")
    require(empty_put_roundtrip(), "byte WAL decoder must preserve an empty value")
    require(encoded_as(ByteWal.record.put.value(key, value), expected_put),
      "WAL records must preserve arbitrary key and value bytes")
    require(encoded_as(ByteWal.record.delete(delete_key), expected_delete),
      "WAL tombstones must preserve arbitrary key bytes")
    require(frames_equal(
      ByteWal.encode(ByteWal.Batch{Con{ByteWal.Put{ascii_key, ascii_value}, Nil{}}}),
      Wal.encode_frame(Wal.Batch{Con{Wal.Put{"a", "b"}, Nil{}}})),
      "byte WAL frame encoding must retain existing framing and checksum policy")
    IO.print("byte WAL records passed")

import Base
import ./Wal.bend as Wal
import ./StorageBytes.bend as StorageBytes
import ./hub_sha/sha256.bend as SHA
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Owns one raw byte mutation without a text conversion.
type Mutation is Type:
  Put{key: Bytes.Bytes, value: Bytes.Bytes}
  Delete{key: Bytes.Bytes}

# Owns the mutations that will be encoded into one WAL frame.
type Batch is Type:
  Batch{mutations: List<&1, Mutation>}

# Carries a raw WAL record parse without decoding either byte buffer.
type DecodedRecord is Type:
  RecordDone{frame: Bytes.Bytes, offset: U32, mutation: Mutation}
  RecordError{frame: Bytes.Bytes, error: Wal.Error}

# Carries bounded frame parsing and newest-first decoded mutations.
type DecodeState is Type:
  DecodeNext{frame: Bytes.Bytes, offset: U32, remaining: Nat,
    reversed: List<&1, Mutation>}
  DecodeRead{record: DecodedRecord, remaining: Nat,
    reversed: List<&1, Mutation>}

# Keeps a parsed frame header with its exact source length.
type FrameHeader is Type:
  FrameHeader{frame: Bytes.Bytes, frame_length: U32, count: U32, total: U32}

# Carries the final parser offset with its affine mutations.
type ParsedBatch is Type:
  ParsedBatch{offset: U32, batch: Batch}

# Encodes a raw key deletion using the shared bounded record layout.
def record.delete(key: Bytes.Bytes) -> Result<&1, &1, Wal.Error, Bytes.Bytes>:
  Wal.record.delete(Bytes.length(key))

# Encodes a raw key/value pair using exact byte lengths.
def record.put.value(
  key: Bytes.Bytes,
  value: Bytes.Bytes
) -> Result<&1, &1, Wal.Error, Bytes.Bytes>:
  Wal.record.put(Bytes.length(key), Bytes.length(value))

# Converts one byte mutation into its binary WAL record.
def record.encode(mutation: Mutation) -> Result<&1, &1, Wal.Error, Bytes.Bytes>:
  match mutation:
    case Put{key, value}:
      record.put.value(key, value)
    case Delete{key}:
      record.delete(key)

# Continues record encoding while preserving the first failure.
def records.step(
  rest: List<&1, Mutation>,
  current: Result<&1, &1, Wal.Error, Bytes.Bytes>,
  reversed: List<&1, Bytes.Bytes>,
  count: U32
) -> Result<&1, &1, Wal.Error, List<&1, Bytes.Bytes> & U32>:
  match rest current:
    case Nil{} Fail{error}:
      Fail{error}
    case Nil{} Done{bytes}:
      Done{(List.reverse(&1, Bytes.Bytes, Con{bytes, reversed}), (count + 1 : U32))}
    case Con{_, _} Fail{error}:
      Fail{error}
    case Con{mutation, tail} Done{bytes}:
      records.step(tail, record.encode(mutation), Con{bytes, reversed}, (count + 1 : U32))

# Encodes all mutations in their input order.
def records(
  mutations: List<&1, Mutation>
) -> Result<&1, &1, Wal.Error, List<&1, Bytes.Bytes> & U32>:
  match mutations:
    case Nil{}:
      Done{(Nil{}, 0)}
    case Con{mutation, tail}:
      records.step(tail, record.encode(mutation), Nil{}, 0)

# Builds the checksummed frame from encoded records and their shared count.
def encode.records(
  result: Result<&1, &1, Wal.Error, List<&1, Bytes.Bytes> & U32>
) -> Result<&1, &1, Wal.Error, Bytes.Bytes>:
  match result:
    case Fail{error}:
      Fail{error}
    case Done{(parts, count)}:
      Wal.frame.payload(count, Done{parts})

# Encodes a byte batch with the existing bounded frame checksum policy.
def encode(batch: Batch) -> Result<&1, &1, Wal.Error, Bytes.Bytes>:
  match batch:
    case Batch{mutations}:
      encode.records(records(mutations))

# Returns the generation-four WAL file identity.
def header.finish(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}:
      bytes
    case None{}:
      Bytes.new(0)

# Returns the generation-four WAL file identity.
def header() -> Bytes.Bytes:
  header.finish(Bytes.from_hex("4d594c534d345700"))

# Converts a raw WAL header comparison into a format decision.
def decode_header.comparison(
  comparison: Bytes.Bytes & Bytes.Bytes & Bool
) -> Result<&1, &1, Wal.Error, Unit>:
  match comparison:
    case (_, _, True{}):
      Done{Unit{}}
    case (_, _, False{}):
      Fail{Wal.Malformed{}}

# Accepts only the generation-four byte WAL signature.
def decode_header(bytes: Bytes.Bytes) -> Result<&1, &1, Wal.Error, Unit>:
  decode_header.comparison(Bytes.eq(header(), bytes))

# Returns a bounded byte slice while preserving the source frame.
def bytes.slice(frame: Bytes.Bytes, start: U32, length: U32) -> Bytes.Bytes & Bytes.Bytes:
  Bytes.slice(frame, start, length)

# Checks that a byte interval lies within its source frame.
# Checks a byte interval against the source length.
def bytes.interval.length(total: U32, start: U32, length: U32) -> Bool:
  Nat.is_le(Nat.add(U32.to_nat(start), U32.to_nat(length)), U32.to_nat(total))

# Checks a byte interval against the source frame.
def bytes.interval.valid(pair: Bytes.Bytes & U32, start: U32, length: U32) -> Bool:
  match pair:
    case (_, total):
      bytes.interval.length(total, start, length)

# Returns a malformed-record result while retaining the source frame.
def record.malformed(frame: Bytes.Bytes) -> DecodedRecord:
  RecordError{frame, Wal.Malformed{}}

# Advances from a copied value to a completed put record.
def record.value.finished(
  frame: Bytes.Bytes,
  value: Bytes.Bytes,
  value_offset: U32,
  +value_length: U32
) -> DecodedRecord:
  match frame:
    case Bytes.Bytes{len, buf}:
      RecordDone{Bytes.Bytes{len, buf}, (value_offset + value_length : U32),
        Put{Bytes.new(0), value}}

# Finishes a value mutation after checking its complete record bound.
def record.value.sliced(
  pair: Bytes.Bytes & Bytes.Bytes,
  value_offset: U32,
  value_length: U32
) -> DecodedRecord:
  match pair:
    case (frame, value):
      record.value.finished(frame, value, value_offset, value_length)

# Finishes a value mutation after checking its complete record bound.
def record.value.checked(
  frame: Bytes.Bytes,
  +value_length: U32,
  +value_offset: U32,
  valid: Bool
) -> DecodedRecord:
  match valid:
    case False{}:
      record.malformed(frame)
    case True{}:
      record.value.sliced(bytes.slice(frame, value_offset, value_length),
        value_offset, value_length)

# Parses the value length and validates its exact byte range.
def record.value.length.checked(
  pair: Bytes.Bytes & U32,
  +length: U32,
  +value_offset: U32
) -> DecodedRecord:
  match pair:
    case (frame, total):
      record.value.checked(frame, length, value_offset,
        bytes.interval.length(total, value_offset, length))

# Parses the value length and validates its exact byte range.
def record.value.length(
  frame: Bytes.Bytes,
  value_length: Maybe<&2, U32>,
  +value_offset: U32
) -> DecodedRecord:
  match value_length:
    case None{}:
      record.malformed(frame)
    case Some{+length}:
      record.value.length.checked(Bytes.length(frame), length, value_offset)

# Replaces the placeholder key in a completed put record.
def record.put.key(record: DecodedRecord, key: Bytes.Bytes) -> DecodedRecord:
  match record:
    case RecordDone{frame, offset, Put{_, value}}:
      RecordDone{frame, offset, Put{key, value}}
    case RecordDone{frame, offset, Delete{old_key}}:
      RecordDone{frame, offset, Delete{old_key}}
    case RecordError{frame, error}:
      RecordError{frame, error}

# Parses the raw put value and restores its key in the record result.
def record.put.value.checked(
  frame: Bytes.Bytes,
  key: Bytes.Bytes,
  +value_length: U32,
  value_offset: U32,
  valid: Bool
) -> DecodedRecord:
  match valid:
    case False{}:
      record.malformed(frame)
    case True{}:
      record.put.key(record.value.checked(frame, value_length, value_offset, True{}), key)

# Parses a put value length after the raw key bytes.
def record.put.value.length.checked(
  pair: Bytes.Bytes & U32,
  key: Bytes.Bytes,
  +length: U32,
  +value_offset: U32
) -> DecodedRecord:
  match pair:
    case (frame, total):
      record.put.value.checked(frame, key, length, value_offset,
        bytes.interval.length(total, value_offset, length))

# Parses a put value length after the raw key bytes.
def record.put.value.length(
  frame: Bytes.Bytes,
  key: Bytes.Bytes,
  value_length: Maybe<&2, U32>,
  value_length_offset: U32
) -> DecodedRecord:
  match value_length:
    case None{}:
      record.malformed(frame)
    case Some{+length}:
      record.put.value.length.checked(Bytes.length(frame), key, length,
        (value_length_offset + 4 : U32))

# Reads and parses a put's value length from its source frame.
def record.put.value.length.read(
  pair: Bytes.Bytes & Maybe<&2, U32>,
  key: Bytes.Bytes,
  value_length_offset: U32
) -> DecodedRecord:
  match pair:
    case (frame, value_length):
      record.put.value.length(frame, key, value_length, value_length_offset)

# Finishes a raw delete record or reads the following put value length.
def record.key.finished(
  frame: Bytes.Bytes,
  tag: U32,
  key: Bytes.Bytes,
  +value_length_offset: U32
) -> DecodedRecord:
  match tag:
    case 1:
      RecordDone{frame, (value_length_offset : U32), Delete{key}}
    case 0:
      record.put.value.length.read(
        Bytes.get.u32be(frame, value_length_offset), key, value_length_offset)
    case _:
      record.malformed(frame)

# Parses a raw key and selects delete or put record completion.
def record.key.sliced(
  pair: Bytes.Bytes & Bytes.Bytes,
  tag: U32,
  +key_length: U32,
  +key_offset: U32
) -> DecodedRecord:
  match pair:
    case (frame, key):
      record.key.finished(frame, tag, key,
        (key_offset + key_length : U32))

# Parses a raw key and selects delete or put record completion.
def record.key.checked(
  frame: Bytes.Bytes,
  tag: U32,
  +key_length: U32,
  +key_offset: U32,
  valid: Bool
) -> DecodedRecord:
  match valid:
    case False{}:
      record.malformed(frame)
    case True{}:
      record.key.sliced(bytes.slice(frame, key_offset, key_length), tag,
        key_length, key_offset)

# Parses a record key length and verifies its bounded range.
def record.key.length.checked(
  pair: Bytes.Bytes & U32,
  tag: U32,
  +length: U32,
  +key_offset: U32
) -> DecodedRecord:
  match pair:
    case (frame, total):
      record.key.checked(frame, tag, length, key_offset,
        U32.is_le(length, StorageBytes.MAX_RECORD_BYTES()) &&
          bytes.interval.length(total, key_offset, length))

# Parses a record key length and verifies its bounded range.
def record.key.length(
  pair: Bytes.Bytes & Maybe<&2, U32>,
  tag: U32,
  offset: U32
) -> DecodedRecord:
  match pair:
    case (frame, None{}):
      record.malformed(frame)
    case (frame, Some{+length}):
      record.key.length.checked(Bytes.length(frame), tag, length,
        (offset + 5 : U32))

# Validates the tag and reads the corresponding raw key length.
def record.tag(
  pair: Bytes.Bytes & Maybe<&2, U32>,
  +offset: U32
) -> DecodedRecord:
  match pair:
    case (frame, None{}):
      record.malformed(frame)
    case (frame, Some{0}):
      record.key.length(Bytes.get.u32be(frame, (offset + 1 : U32)), 0, offset)
    case (frame, Some{1}):
      record.key.length(Bytes.get.u32be(frame, (offset + 1 : U32)), 1, offset)
    case (frame, Some{_}):
      record.malformed(frame)

# Decodes one raw WAL record from its length-delimited frame position.
def record.decode(frame: Bytes.Bytes, +offset: U32) -> DecodedRecord:
  record.tag(Bytes.get(frame, offset), offset)

# Decodes the exact number of records declared by a WAL frame.
def decode.records.loop(fuel: Nat, state: DecodeState) -> Result<&1, &1, Wal.Error, ParsedBatch>:
  match fuel:
    case 0n:
      Fail{Wal.Malformed{}}
    case 1n+rest:
      match state:
        case DecodeNext{frame, offset, remaining, reversed}:
          match remaining:
            case 0n:
              Done{ParsedBatch{offset, Batch{List.reverse(&1, Mutation, reversed)}}}
            case 1n+more:
              decode.records.loop(rest,
                DecodeRead{record.decode(frame, offset), more, reversed})
        case DecodeRead{record, remaining, reversed}:
          match record:
            case RecordError{_, error}:
              Fail{error}
            case RecordDone{frame, offset, mutation}:
              decode.records.loop(rest,
                DecodeNext{frame, offset, remaining, Con{mutation, reversed}})

# Converts the pure frame bound decision into a typed outcome.
def decode.header.validated(
  frame: Bytes.Bytes,
  frame_length: U32,
  count: U32,
  total: U32,
  valid: Bool
) -> Result<&1, &1, Wal.Error, FrameHeader>:
  match valid:
    case False{}:
      Fail{Wal.Malformed{}}
    case True{}:
      Done{FrameHeader{frame, frame_length, count, total}}

# Validates the declared count and full frame length.
def frame.bounds.valid(+frame_length: U32, +count: U32, +total: U32) -> Bool:
  U32.is_le(36, frame_length) &&
    Nat.is_eq(U32.to_nat(total), Nat.add(U32.to_nat(frame_length), 4n)) &&
    Nat.is_le(U32.to_nat(count), Nat.div(U32.to_nat(frame_length), 5n)) &&
    Wal.frame_length_allowed(count, frame_length)

# Validates the declared count and full frame length.
def decode.header.count(
  pair: Bytes.Bytes & Maybe<&2, U32>,
  +frame_length: U32,
  +total: U32
) -> Result<&1, &1, Wal.Error, FrameHeader>:
  match pair:
    case (_, None{}):
      Fail{Wal.Malformed{}}
    case (frame, Some{+count}):
      decode.header.validated(frame, frame_length, count, total,
        frame.bounds.valid(frame_length, count, total))

# Reads frame length and count into a validated header.
def decode.header.length(
  pair: Bytes.Bytes & Maybe<&2, U32>,
  total: U32
) -> Result<&1, &1, Wal.Error, FrameHeader>:
  match pair:
    case (frame, None{}):
      Fail{Wal.Malformed{}}
    case (frame, Some{+length}):
      decode.header.count(Bytes.get.u32be(frame, 4), length, total)

# Returns the decoded batch only when the checksum agrees.
def decode.checksum.comparison(
  comparison: Bytes.Bytes & Bytes.Bytes & Bool,
  batch: Batch
) -> Result<&1, &1, Wal.Error, Batch>:
  match comparison:
    case (_, _, True{}):
      Done{batch}
    case (_, _, False{}):
      Fail{Wal.ChecksumMismatch{}}

# Compares the stored digest with the computed digest.
def decode.checksum.claimed(
  pair: Bytes.Bytes & Bytes.Bytes,
  batch: Batch,
  digest: Bytes.Bytes
) -> Result<&1, &1, Wal.Error, Batch>:
  match pair:
    case (_, claimed):
      decode.checksum.comparison(Bytes.eq(claimed, digest), batch)

# Parses the retained digest after hashing its exact frame prefix.
def decode.checksum.prefix(
  pair: Bytes.Bytes & Bytes.Bytes,
  batch: Batch,
  digest_offset: U32
) -> Result<&1, &1, Wal.Error, Batch>:
  match pair:
    case (frame, prefix):
      decode.checksum.claimed(bytes.slice(frame, digest_offset, 32), batch,
        SHA.sha256_packed_bytes(prefix))

# Compares a frame's stored digest with the digest of its exact prefix.
def decode.checksum.bytes(
  frame: Bytes.Bytes,
  batch: Batch,
  +digest_offset: U32
) -> Result<&1, &1, Wal.Error, Batch>:
  decode.checksum.prefix(bytes.slice(frame, 0, digest_offset), batch,
    digest_offset)

# Converts the record-end decision into a typed frame result.
def decode.checksum.offset(
  frame: Bytes.Bytes,
  batch: Batch,
  +total: U32,
  valid: Bool
) -> Result<&1, &1, Wal.Error, Batch>:
  match valid:
    case False{}:
      Fail{Wal.Malformed{}}
    case True{}:
      decode.checksum.bytes(frame, batch, (total - 32 : U32))

# Verifies the checksum and exact record payload boundary.
def decode.checksum(
  frame: Bytes.Bytes,
  +total: U32,
  result: Result<&1, &1, Wal.Error, ParsedBatch>
) -> Result<&1, &1, Wal.Error, Batch>:
  match result:
    case Fail{error}:
      Fail{error}
    case Done{ParsedBatch{+offset, batch}}:
      decode.checksum.offset(frame, batch, total,
        U32.is_eq(offset, (total - 32 : U32)))

# Validates record payload and checksum after parsing a bounded frame header.
def decode.frame.copies(
  pair: Bytes.Bytes & Bytes.Bytes,
  +count: U32,
  +total: U32
) -> Result<&1, &1, Wal.Error, Batch>:
  match pair:
    case (checksum_frame, parse_frame):
      decode.checksum(checksum_frame, total,
        decode.records.loop(Nat.add(Nat.mul(2n, U32.to_nat(count)), 1n),
          DecodeNext{parse_frame, 8, U32.to_nat(count), Nil{}}))

# Validates record payload and checksum after parsing a bounded frame header.
def decode.frame.header(header: FrameHeader) -> Result<&1, &1, Wal.Error, Batch>:
  match header:
    case FrameHeader{frame, _, +count, +total}:
      decode.frame.copies(Wal.bytes.clone.split(frame), count, total)

# Validates a packed frame length before reading its count and records.
def decode.frame.length(pair: Bytes.Bytes & U32) -> Result<&1, &1, Wal.Error, FrameHeader>:
  match pair:
    case (frame, +total):
      decode.header.length(Bytes.get.u32be(frame, 0), total)

# Dispatches a parsed header to the full bounded frame decoder.
def decode.frame.header.result(
  result: Result<&1, &1, Wal.Error, FrameHeader>
) -> Result<&1, &1, Wal.Error, Batch>:
  match result:
    case Fail{error}:
      Fail{error}
    case Done{header}:
      decode.frame.header(header)

# Decodes a generation-four WAL frame, rejecting malformed lengths and checksums.
def decode(frame: Bytes.Bytes) -> Result<&1, &1, Wal.Error, Batch>:
  decode.frame.header.result(decode.frame.length(Bytes.length(frame)))

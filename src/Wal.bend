import Base
import ./MemTable.bend as MemTable
import ./SstFile.bend as SstFile
import ./StorageBytes.bend as StorageBytes
import ./hub_sha/sha256.bend as SHA
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Represent Mut data used by the write-ahead log data model.
type Mut is Data:
  Put{key: String, val: String}
  Del{key: String}

# Represent Batch data used by the write-ahead log data model.
type Batch is Data:
  Batch{muts: List<&2, Mut>}

# Handle stage in the write-ahead log data model.
def stage(+staged: List<&2, Batch>, +batch: Batch) -> List<&2, Batch>:
  Con{batch, staged}

# Represent Error data used by the packed WAL codec.
type Error is Data:
  TooLarge{}
  InvalidUtf8{}
  Malformed{}
  ChecksumMismatch{}

def record.error(error: SstFile.Error) -> Error:
  match error:
    case SstFile.TooLarge{}:
      TooLarge{}
    case SstFile.InvalidUtf8{}:
      InvalidUtf8{}
    case SstFile.ChecksumMismatch{}:
      ChecksumMismatch{}
    case _:
      Malformed{}

def record.convert(
  pair: Bytes.Cursor & Result<&1, &1, SstFile.Error, SstFile.ParsedRecord>
) -> Bytes.Cursor & Result<&1, &1, Error, Mut>:
  match pair:
    case (cursor, Fail{error}):
      (cursor, Fail{record.error(error)})
    case (cursor, Done{SstFile.Rec{MemTable.Entry{key, None{}}, _}}):
      (cursor, Done{Del{key}})
    case (cursor, Done{SstFile.Rec{MemTable.Entry{key, Some{value}}, _}}):
      (cursor, Done{Put{key, value}})

def record.read(
  cursor: Bytes.Cursor
) -> Bytes.Cursor & Result<&1, &1, Error, Mut>:
  record.convert(SstFile.parse.record(cursor))

# Encode or decode a 32-bit word for bytes for the packed WAL codec.
def u32_bytes(value: U32) -> Bytes.Bytes:
  Bytes.set.u32be(Bytes.new(4), 0, value)

# Encode an 8-bit value for bytes for the packed WAL codec.
def u8_bytes(value: U32) -> Bytes.Bytes:
  Bytes.set(Bytes.new(1), 0, value)

def header.finish(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}:
      bytes
    case None{}:
      Bytes.new(0)

# Handle log header in the packed WAL codec.
def log_header() -> Bytes.Bytes:
  header.finish(Bytes.from_hex("4d594c534d335700"))

def header.valid(
  comparison: Bytes.Bytes & Bytes.Bytes & Bool
) -> Result<&1, &1, Error, Unit>:
  match comparison:
    case (_, _, True{}):
      Done{Unit{}}
    case (_, _, False{}):
      Fail{Malformed{}}

# Decode header for the packed WAL codec.
def decode_header(bytes: Bytes.Bytes) -> Result<&1, &1, Error, Unit>:
  header.valid(Bytes.eq(log_header(), bytes))

def record.delete.valid(
  tag: U32,
  key: Bytes.Bytes,
  +key_len: U32,
  valid: Bool
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match valid:
    case False{}:
      Fail{TooLarge{}}
    case True{}:
      Done{Bytes.concat([u8_bytes(tag), u32_bytes(key_len), key])}


def record.delete(
  pair: Bytes.Bytes & U32
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match pair:
    case (key, +key_len):
      record.delete.valid(1, key, key_len,
        U32.is_le(key_len, (StorageBytes.MAX_RECORD_BYTES() - 5 : U32)))


def record.put.valid(
  key: Bytes.Bytes,
  +key_len: U32,
  value: Bytes.Bytes,
  +value_len: U32,
  valid: Bool
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match valid:
    case False{}:
      Fail{TooLarge{}}
    case True{}:
      Done{Bytes.concat([Bytes.new(1), u32_bytes(key_len), key,
        u32_bytes(value_len), value])}


def record.put.checked(
  key: Bytes.Bytes,
  +key_len: U32,
  value: Bytes.Bytes,
  +value_len: U32,
  sum: Maybe<&2, U32>
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match sum:
    case None{}:
      Fail{TooLarge{}}
    case Some{size}:
      record.put.valid(key, key_len, value, value_len,
        U32.is_le(size, (StorageBytes.MAX_RECORD_BYTES() - 9 : U32)))


def record.put.value(
  key: Bytes.Bytes,
  +key_len: U32,
  value_pair: Bytes.Bytes & U32
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match value_pair:
    case (value, +value_len):
      record.put.checked(key, key_len, value, value_len,
        StorageBytes.checked_add(key_len, value_len))

def record.put(
  key_pair: Bytes.Bytes & U32,
  value_pair: Bytes.Bytes & U32
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match key_pair:
    case (key, +key_len):
      record.put.value(key, key_len, value_pair)


def record.encode.put(
  key_result: Result<&1, &1, U32 & String, Bytes.Bytes>,
  value_result: Result<&1, &1, U32 & String, Bytes.Bytes>
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match key_result value_result:
    case Fail{_} _:
      Fail{TooLarge{}}
    case _ Fail{_}:
      Fail{TooLarge{}}
    case Done{key} Done{value}:
      record.put(Bytes.length(key), Bytes.length(value))


def record.encode.delete(
  key_result: Result<&1, &1, U32 & String, Bytes.Bytes>
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match key_result:
    case Fail{_}:
      Fail{TooLarge{}}
    case Done{key}:
      record.delete(Bytes.length(key))


def record.encode(mut: Mut) -> Result<&1, &1, Error, Bytes.Bytes>:
  match mut:
    case Put{key, val}:
      record.encode.put(StorageBytes.from_string(key), StorageBytes.from_string(val))
    case Del{key}:
      record.encode.delete(StorageBytes.from_string(key))



def records.step(
  rest: List<&2, Mut>,
  current: Result<&1, &1, Error, Bytes.Bytes>,
  acc: List<&1, Bytes.Bytes>
) -> Result<&1, &1, Error, List<&1, Bytes.Bytes>>:
  match rest current:
    case Nil{} Fail{error}:
      Fail{error}
    case Nil{} Done{bytes}:
      Done{List.reverse(&1, Bytes.Bytes, bytes <> acc)}
    case Con{_mut, _tail} Fail{error}:
      Fail{error}
    case Con{mut, tail} Done{bytes}:
      records.step(tail, record.encode(mut), bytes <> acc)

# Handle the record s for the packed WAL codec.
def records(
  muts: List<&2, Mut>
) -> Result<&1, &1, Error, List<&1, Bytes.Bytes>>:
  match muts:
    case Nil{}:
      Done{Nil{}}
    case Con{mut, tail}:
      records.step(tail, record.encode(mut), Nil{})

def bytes.clone.pair(
  +len: U32,
  copied: Array<U32> & Array<U32>
) -> Bytes.Bytes & Bytes.Bytes:
  match copied:
    case (left, right):
      (Bytes.Bytes{len, left}, Bytes.Bytes{len, right})

def bytes.clone.split(bytes: Bytes.Bytes) -> Bytes.Bytes & Bytes.Bytes:
  match bytes:
    case Bytes.Bytes{+len, buf}:
      bytes.clone.pair(len, Bytes.copy.bytes(len, buf, Bytes.alloc(len), 0, 0))

def frame.digest.pair(
  +count: U32,
  +frame_len: U32,
  output_payload: Bytes.Bytes,
  hash_payload: Bytes.Bytes
) -> Result<&1, &1, Error, Bytes.Bytes>:
  digest = SHA.sha256_packed_bytes(Bytes.concat([u32_bytes(frame_len),
    u32_bytes(count), hash_payload]))
  Done{Bytes.concat([u32_bytes(frame_len), u32_bytes(count),
    output_payload, digest])}



def frame.digest(
  +count: U32,
  payload: Bytes.Bytes,
  +frame_len: U32,
  hash_payload: Bytes.Bytes
) -> Result<&1, &1, Error, Bytes.Bytes>:
  frame.digest.pair(count, frame_len, payload, hash_payload)



def frame.payload.valid(
  +count: U32,
  payload: Bytes.Bytes,
  +frame_len: U32,
  hash_payload: Bytes.Bytes,
  valid: Bool
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match valid:
    case False{}:
      Fail{TooLarge{}}
    case True{}:
      frame.digest(count, payload, frame_len, hash_payload)



# Checks an encoded WAL frame against its byte cap.
def frame_length_allowed(+count: U32, +length: U32) -> Bool:
  U32.is_le(length, StorageBytes.MAX_BLOCK_BYTES()) ||
    U32.is_eq(count, 1) && U32.is_le(length,
      (StorageBytes.MAX_RECORD_BYTES() + 36 : U32))

def frame.payload.fin(
  +count: U32,
  payload: Bytes.Bytes,
  hash_payload: Bytes.Bytes,
  frame_len: Maybe<&2, U32>
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match frame_len:
    case None{}:
      Fail{TooLarge{}}
    case Some{+length}:
      frame.payload.valid(count, payload, length, hash_payload, frame_length_allowed(count, length))



def frame.payload.output(
  count: U32,
  hash_payload: Bytes.Bytes,
  measured: Bytes.Bytes & U32
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match measured:
    case (payload, +payload_len):
      frame.payload.fin(count, payload, hash_payload,
        StorageBytes.checked_add(payload_len, 36))

def frame.payload.size(
  count: U32,
  pair: Bytes.Bytes & Bytes.Bytes
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match pair:
    case (output, hash_payload):
      frame.payload.output(count, hash_payload, Bytes.length(output))



def frame.payload(
  +count: U32,
  records: Result<&1, &1, Error, List<&1, Bytes.Bytes>>
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match records:
    case Fail{error}:
      Fail{error}
    case Done{parts}:
      frame.payload.size(count, bytes.clone.split(Bytes.concat(parts)))

# Encode frame for the packed WAL codec.
def encode_frame(batch: Batch) -> Result<&1, &1, Error, Bytes.Bytes>:
  match batch:
    case Batch{+muts}:
      frame.payload(U32.from_nat(List.length(&2, Mut, muts)), records(muts))

# Represent DigestRead data used by the packed WAL codec.
type DigestRead is Type:
  DigestInput{cursor: Bytes.Cursor, value: Maybe<&2, U32>}

def digest.read.wrap(pair: Bytes.Cursor & Maybe<&2, U32>) -> DigestRead:
  match pair:
    case (cursor, value):
      DigestInput{cursor, value}

def digest.read.go(
  remaining: Nat,
  input: DigestRead,
  digest: Bytes.Bytes,
  +offset: U32
) -> Bytes.Cursor & Result<&1, &1, Error, Bytes.Bytes>:
  match remaining input:
    case 0n DigestInput{cursor, _}:
      (cursor, Done{digest})
    case 1n+0n DigestInput{cursor, Some{word}}:
      (cursor, Done{Bytes.set.u32be(digest, offset, word)})
    case 1n+1n+rest DigestInput{cursor, Some{word}}:
      digest.read.go(1n+rest, digest.read.wrap(Bytes.Cursor.u32be(cursor)),
        Bytes.set.u32be(digest, offset, word), (offset + 4 : U32))
    case 1n+_ DigestInput{cursor, None{}}:
      (cursor, Fail{Malformed{}})

def digest.read(
  cursor: Bytes.Cursor
) -> Bytes.Cursor & Result<&1, &1, Error, Bytes.Bytes>:
  digest.read.go(8n, digest.read.wrap(Bytes.Cursor.u32be(cursor)),
    Bytes.new(32), 0)

# Represent RecordRead data used by the packed WAL codec.
type RecordRead is Type:
  RecordInput{cursor: Bytes.Cursor,
    result: Result<&1, &1, Error, Mut>}

def records.read.wrap(
  pair: Bytes.Cursor & Result<&1, &1, Error, Mut>
) -> RecordRead:
  match pair:
    case (cursor, result):
      RecordInput{cursor, result}

def records.read.go(
  remaining: Nat,
  input: RecordRead,
  reversed: List<&2, Mut>
) -> Bytes.Cursor & Result<&1, &1, Error, List<&2, Mut>>:
  match remaining input:
    case 0n RecordInput{cursor, Fail{error}}:
      (cursor, Fail{error})
    case 0n RecordInput{cursor, Done{mut}}:
      (cursor, Done{List.reverse(&2, Mut, mut <> reversed)})
    case 1n+rest RecordInput{cursor, Fail{error}}:
      (cursor, Fail{error})
    case 1n+rest RecordInput{cursor, Done{mut}}:
      records.read.go(rest, records.read.wrap(record.read(cursor)),
        mut <> reversed)

def records.read.start(
  cursor: Bytes.Cursor,
  +count: U32
) -> Bytes.Cursor & Result<&1, &1, Error, List<&2, Mut>>:
  match count:
    case 0:
      (cursor, Done{Nil{}})
    case _:
      records.read.go(Nat.sub(U32.to_nat(count), 1n),
        records.read.wrap(record.read(cursor)), Nil{})

def frame.digest.prefix(pair: Bytes.Bytes & Bytes.Bytes) -> Bytes.Bytes:
  match pair:
    case (_, prefix):
      prefix

def frame.verify.equal(
  records: List<&2, Mut>,
  comparison: Bytes.Bytes & Bytes.Bytes & Bool
) -> Result<&1, &1, Error, Batch>:
  match comparison:
    case (_, _, False{}):
      Fail{ChecksumMismatch{}}
    case (_, _, True{}):
      Done{Batch{records}}



def frame.verify.end(
  at_end: Bool,
  bytes: Bytes.Bytes,
  claimed: Bytes.Bytes,
  records: List<&2, Mut>,
  +end: U32
) -> Result<&1, &1, Error, Batch>:
  match at_end:
    case False{}:
      Fail{Malformed{}}
    case True{}:
      frame.verify.equal(records, Bytes.eq(claimed,
        SHA.sha256_packed_bytes(frame.digest.prefix(
          Bytes.slice(bytes, 0, (end - 32 : U32))))))



def frame.verify.finish(
  cursor: Bytes.Cursor,
  claimed: Bytes.Bytes,
  records: List<&2, Mut>
) -> Result<&1, &1, Error, Batch>:
  match cursor:
    case Bytes.Cursor{bytes, +pos, _, +end}:
      frame.verify.end(U32.is_eq(pos, end), bytes, claimed, records, end)


def frame.verify.cursor(
  pair: Bytes.Cursor & Result<&1, &1, Error, Bytes.Bytes>,
  records: List<&2, Mut>
) -> Result<&1, &1, Error, Batch>:
  match pair:
    case (_, Fail{error}):
      Fail{error}
    case (cursor, Done{claimed}):
      frame.verify.finish(cursor, claimed, records)



def frame.records(
  pair: Bytes.Cursor & Result<&1, &1, Error, List<&2, Mut>>
) -> Result<&1, &1, Error, Batch>:
  match pair:
    case (_, Fail{error}):
      Fail{error}
    case (cursor, Done{muts}):
      frame.verify.cursor(digest.read(cursor), muts)


def frame.bound.valid(
  +frame_len: U32,
  +count: U32,
  valid: Bool
) -> Bool:
  valid && U32.is_le(count,
    U32.from_nat(Nat.div(U32.to_nat(frame_len), 5n))) &&
    (U32.is_le(frame_len, StorageBytes.MAX_BLOCK_BYTES()) ||
      U32.is_eq(count, 1) && U32.is_le(frame_len,
        (StorageBytes.MAX_RECORD_BYTES() + 36 : U32)))

def frame.bound.checked(
  cursor: Bytes.Cursor,
  +count: U32,
  valid: Bool
) -> Result<&1, &1, Error, Batch>:
  match valid:
    case False{}:
      Fail{Malformed{}}
    case True{}:
      frame.records(records.read.start(cursor, count))


def frame.bound.count(
  pair: Bytes.Cursor & Maybe<&2, U32>,
  +frame_len: U32,
  within: Bool
) -> Result<&1, &1, Error, Batch>:
  match pair:
    case (_, None{}):
      Fail{Malformed{}}
    case (cursor, Some{+count}):
      frame.bound.checked(cursor, count,
        frame.bound.valid(frame_len, count, within))


def frame.bound.total.valid(
  cursor: Bytes.Cursor,
  +frame_len: U32,
  valid: Bool
) -> Result<&1, &1, Error, Batch>:
  match valid:
    case False{}:
      Fail{Malformed{}}
    case True{}:
      frame.bound.count(Bytes.Cursor.u32be(cursor), frame_len,
        U32.is_le(36, frame_len))


def frame.bound.total(
  cursor: Bytes.Cursor,
  +frame_len: U32,
  +end: U32,
  checked: Maybe<&2, U32>
) -> Result<&1, &1, Error, Batch>:
  match checked:
    case None{}:
      Fail{TooLarge{}}
    case Some{+expected_end}:
      frame.bound.total.valid(cursor, frame_len,
        U32.is_eq(expected_end, end))


def frame.bound.end(
  cursor: Bytes.Cursor,
  +frame_len: U32
) -> Result<&1, &1, Error, Batch>:
  match cursor:
    case Bytes.Cursor{bytes, +pos, +start, +end}:
      frame.bound.total(Bytes.Cursor{bytes, pos, start, end},
        frame_len, end, StorageBytes.checked_add(frame_len, 4))


def frame.bound.length(
  pair: Bytes.Cursor & Maybe<&2, U32>
) -> Result<&1, &1, Error, Batch>:
  match pair:
    case (_, None{}):
      Fail{Malformed{}}
    case (cursor, Some{+frame_len}):
      frame.bound.end(cursor, frame_len)


# Decode frame for the packed WAL codec.
def decode_frame(
  bytes: Bytes.Bytes
) -> Result<&1, &1, Error, Batch>:
  frame.bound.length(Bytes.Cursor.u32be(Bytes.Cursor.new(bytes)))

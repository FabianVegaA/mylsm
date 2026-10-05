import Base
import ./MemTable.bend as MemTable
import ./Keys.bend as Keys
import ./Sstable.bend as Sstable
import ./StorageBytes.bend as StorageBytes
import ./hub_sha/sha256.bend as SHA
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Errors returned by the v3 encoder and strict parser.
type Error is Data:
  InvalidLevel{}
  InvalidOrder{}
  TooLarge{}
  Malformed{}
  InvalidUtf8{}
  ChecksumMismatch{}

# Encoder progression through the header, blocks, and footer.
type Phase is Data:
  Header{}
  Blocks{}
  Finished{}

# Serialized block paired with its stored digest.
type EncodedBlock is Type:
  Block{bytes: Bytes.Bytes, digest: Bytes.Bytes}

# State that yields the encoded file in bounded chunks.
type Encoder is Type:
  Enc{
    phase: Phase,
    chunks: List<&1, Bytes.Bytes>,
    level: U32,
    total: U32,
    block_count: U32,
    footer: Bytes.Bytes
  }

# Validated level and counts read from the v3 header.
type SstHeader is Data:
  SstHdr{level: U32, total: U32, block_count: U32}

# Streaming parser stage. A completed stage carries only decoded table state.
# Bounded chunk accumulator; the final parser rejects aggregate overflow before joining.
type Decoder is Type:
  Dec{chunks: List<&1, Bytes.Bytes>, total: U32, invalid: Bool}

# Result of applying one validated block to file-level counts.
type BlockDecision is Type:
  BlockRejected{error: Error}
  BlockOutOfBounds{}
  BlockContinue{cursor: Bytes.Cursor, entries_left: U32,
    previous: Maybe<&2, String>, entries: List<&2, MemTable.Entry>,
    hashes: List<&1, Bytes.Bytes>}
  BlockFinish{cursor: Bytes.Cursor, entries: List<&2, MemTable.Entry>,
    hashes: List<&1, Bytes.Bytes>}

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

def bytes.clone.first(pair: Bytes.Bytes & Bytes.Bytes) -> Bytes.Bytes:
  match pair:
    case (left, _):
      left

def bytes.clone(bytes: Bytes.Bytes) -> Bytes.Bytes:
  bytes.clone.first(bytes.clone.split(bytes))

# Construct a packed u32 in network byte order.
def u32_bytes(value: U32) -> Bytes.Bytes:
  Bytes.set.u32be(Bytes.new(4), 0, value)

# Construct a packed tag byte.
def u8_bytes(value: U32) -> Bytes.Bytes:
  Bytes.set(Bytes.new(1), 0, value)

# Unwrap a fixed valid hexadecimal constant.
def hex_bytes.fin(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}:
      bytes
    case None{}:
      Bytes.new(0)

# Encode one mutation as a tagged, length-delimited record.
def record.value.finish.checked(
  key_bytes: Bytes.Bytes,
  +key_len: U32,
  value_bytes: Bytes.Bytes,
  +value_len: U32,
  valid: Bool
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match valid:
    case False{}:
      Fail{TooLarge{}}
    case True{}:
      Done{Bytes.concat([u8_bytes(0), u32_bytes(key_len), key_bytes,
        u32_bytes(value_len), value_bytes])}

def record.value.finish.valid(
  key_bytes: Bytes.Bytes,
  +key_len: U32,
  value_bytes: Bytes.Bytes,
  +value_len: U32,
  key_fits: Bool
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match key_fits:
    case False{}:
      Fail{TooLarge{}}
    case True{}:
      record.value.finish.checked(key_bytes, key_len, value_bytes, value_len,
        U32.is_le(value_len, (StorageBytes.MAX_RECORD_BYTES() - 9 - key_len : U32)))

def record.value.finish.val(
  key_bytes: Bytes.Bytes,
  +key_len: U32,
  value_pair: Bytes.Bytes & U32
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match value_pair:
    case (value_bytes, +value_len):
      record.value.finish.valid(key_bytes, key_len, value_bytes, value_len,
        U32.is_le(key_len, (StorageBytes.MAX_RECORD_BYTES() - 9 : U32)))

def record.value.finish(
  key_pair: Bytes.Bytes & U32,
  value_pair: Bytes.Bytes & U32
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match key_pair:
    case (key_bytes, key_len):
      record.value.finish.val(key_bytes, key_len, value_pair)

def record.value.fin(
  key_pair: Bytes.Bytes & U32,
  result: Result<&1, &1, U32 & String, Bytes.Bytes>
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match result:
    case Fail{_}:
      Fail{TooLarge{}}
    case Done{value_bytes}:
      record.value.finish(key_pair, Bytes.length(value_bytes))

def record.value(
  key_bytes: Bytes.Bytes,
  value_result: Result<&1, &1, U32 & String, Bytes.Bytes>
) -> Result<&1, &1, Error, Bytes.Bytes>:
  record.value.fin(Bytes.length(key_bytes), value_result)

def record.key.delete.checked(
  key_bytes: Bytes.Bytes,
  +key_len: U32,
  valid: Bool
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match valid:
    case False{}:
      Fail{TooLarge{}}
    case True{}:
      Done{Bytes.concat([u8_bytes(1), u32_bytes(key_len), key_bytes])}

def record.key.delete(key_pair: Bytes.Bytes & U32) -> Result<&1, &1, Error, Bytes.Bytes>:
  match key_pair:
    case (key_bytes, +key_len):
      record.key.delete.checked(key_bytes, key_len,
        U32.is_le(key_len, (StorageBytes.MAX_RECORD_BYTES() - 5 : U32)))

def record.key(
  key_result: Result<&1, &1, U32 & String, Bytes.Bytes>,
  val: Maybe<&2, String>
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match key_result val:
    case Fail{_} _:
      Fail{TooLarge{}}
    case Done{key_bytes} None{}:
      record.key.delete(Bytes.length(key_bytes))
    case Done{key_bytes} Some{value}:
      record.value(key_bytes, StorageBytes.from_string(value))

# Encode one checked put or delete record.
def encode_record(entry: MemTable.Entry) -> Result<&1, &1, Error, Bytes.Bytes>:
  match entry:
    case MemTable.Entry{key, val}:
      record.key(StorageBytes.from_string(key), val)

def entries.strict.tail(
  tail: List<&2, MemTable.Entry>,
  current: String,
  ordered: Bool
) -> Bool:
  match tail ordered:
    case Nil{} True{}:
      True{}
    case Nil{} False{}:
      False{}
    case Con{_entry, _rest} False{}:
      False{}
    case Con{MemTable.Entry{+key, val}, rest} True{}:
      entries.strict.tail(rest, key, Keys.lt(current, key))

def entries.strict(entries: List<&2, MemTable.Entry>) -> Bool:
  match entries:
    case Nil{}:
      True{}
    case Con{MemTable.Entry{key, val}, rest}:
      entries.strict.tail(rest, key, True{})

# Result of measuring a record against the target block size.
type BlockMeasure is Data:
  InvalidRecord{}
  Measured{length: U32, fits: Bool}

# Measure an already encoded record for byte-bounded block packing.
def blocks.measure.length(+length: U32, +size: U32) -> BlockMeasure:
  Measured{length, U32.is_eq(size, 0) ||
    U32.is_le((size + length : U32), StorageBytes.MAX_BLOCK_BYTES())}

def blocks.measure.valid(length: U32, +size: U32, valid: Bool) -> BlockMeasure:
  match valid:
    case False{}:
      InvalidRecord{}
    case True{}:
      blocks.measure.length(length, size)

def blocks.measure.delete(key_length: Maybe<&2, U32>, +size: U32) -> BlockMeasure:
  match key_length:
    case None{}:
      InvalidRecord{}
    case Some{+length}:
      blocks.measure.valid((5 + length : U32), size,
        U32.is_le(length, (StorageBytes.MAX_RECORD_BYTES() - 5 : U32)))

def blocks.measure.put.value(
  +key_length: U32,
  value_length: Maybe<&2, U32>,
  +size: U32
) -> BlockMeasure:
  match value_length:
    case None{}:
      InvalidRecord{}
    case Some{+length}:
      blocks.measure.valid((9 + key_length + length : U32), size,
        U32.is_le(key_length, (StorageBytes.MAX_RECORD_BYTES() - 9 : U32)) &&
        U32.is_le(length, (StorageBytes.MAX_RECORD_BYTES() - 9 - key_length : U32)))

def blocks.measure.put(
  key_length: Maybe<&2, U32>,
  value_length: Maybe<&2, U32>,
  +size: U32
) -> BlockMeasure:
  match key_length:
    case None{}:
      InvalidRecord{}
    case Some{+length}:
      blocks.measure.put.value(length, value_length, size)

def blocks.measure.entry(entry: MemTable.Entry, +size: U32) -> BlockMeasure:
  match entry:
    case MemTable.Entry{key, value}:
      match value:
        case None{}:
          blocks.measure.delete(StorageBytes.from_string.size.begin(key), size)
        case Some{text}:
          blocks.measure.put(StorageBytes.from_string.size.begin(key),
            StorageBytes.from_string.size.begin(text), size)

def blocks.measure.next(
  entries: List<&2, MemTable.Entry>,
  +size: U32
) -> BlockMeasure:
  match entries:
    case Nil{}:
      InvalidRecord{}
    case Con{MemTable.Entry{key, val}, _}:
      blocks.measure.entry(MemTable.Entry{key, val}, size)

# Finish the current block list, which is stored in reverse order.
def blocks.pack.finish(
  current: List<&2, MemTable.Entry>,
  acc: List<&2, List<&2, MemTable.Entry>>
) -> List<&2, List<&2, MemTable.Entry>>:
  match current:
    case Nil{}:
      List.reverse(&2, List<&2, MemTable.Entry>, acc)
    case Con{_, _}:
      List.reverse(&2, List<&2, MemTable.Entry>,
        Con{List.reverse(&2, MemTable.Entry, current), acc})

# Pack records into blocks capped by encoded payload bytes, preserving order.
def blocks.pack.go(
  entries: List<&2, MemTable.Entry>,
  current: List<&2, MemTable.Entry>,
  +size: U32,
  acc: List<&2, List<&2, MemTable.Entry>>,
  measured: BlockMeasure
) -> List<&2, List<&2, MemTable.Entry>>:
  match entries:
    case Nil{}:
      blocks.pack.finish(current, acc)
    case Con{entry, +rest}:
      match current:
        case Nil{}:
          match measured:
            case InvalidRecord{}:
              blocks.pack.go(rest, Con{entry, Nil{}}, StorageBytes.MAX_BLOCK_BYTES(), acc,
                blocks.measure.next(rest, StorageBytes.MAX_BLOCK_BYTES()))
            case Measured{+length, fits}:
              blocks.pack.go(rest, Con{entry, Nil{}}, length, acc,
                blocks.measure.next(rest, length))
        case Con{_, _}:
          match measured:
            case InvalidRecord{}:
              blocks.pack.go(rest, Con{entry, Nil{}}, StorageBytes.MAX_BLOCK_BYTES(),
                Con{List.reverse(&2, MemTable.Entry, current), acc},
                blocks.measure.next(rest, StorageBytes.MAX_BLOCK_BYTES()))
            case Measured{+length, False{}}:
              blocks.pack.go(rest, Con{entry, Nil{}}, length,
                Con{List.reverse(&2, MemTable.Entry, current), acc},
                blocks.measure.next(rest, length))
            case Measured{+length, True{}}:
              blocks.pack.go(rest, Con{entry, current}, (size + length : U32), acc,
                blocks.measure.next(rest, (size + length : U32)))

def blocks.pack(entries: List<&2, MemTable.Entry>) -> List<&2, List<&2, MemTable.Entry>>:
  match entries:
    case Nil{}:
      Nil{}
    case Con{+entry, _}:
      blocks.pack.go(entries, Nil{}, 0, Nil{},
        blocks.measure.entry(entry, 0))

# Continue encoding a record list after the current record has been checked.
def records.step(
  rest: List<&2, MemTable.Entry>,
  current: Result<&1, &1, Error, Bytes.Bytes>,
  acc: List<&1, Bytes.Bytes>
) -> Result<&1, &1, Error, List<&1, Bytes.Bytes>>:
  match rest current:
    case Nil{} Fail{error}:
      Fail{error}
    case Nil{} Done{bytes}:
      Done{List.reverse(&1, Bytes.Bytes, bytes <> acc)}
    case Con{_entry, _tail} Fail{error}:
      Fail{error}
    case Con{entry, tail} Done{bytes}:
      records.step(tail, encode_record(entry), bytes <> acc)

# Encode each entry independently, retaining only the record fragments for one block.
def records(entries: List<&2, MemTable.Entry>) -> Result<&1, &1, Error, List<&1, Bytes.Bytes>>:
  match entries:
    case Nil{}:
      Done{Nil{}}
    case Con{entry, +rest}:
          records.step(rest, encode_record(entry), Nil{})

# Build one v3 block and its digest over the two header words and payload.
def block.fin.digest.parts(
  +count: U32,
  payload: Bytes.Bytes,
  +payload_len: U32,
  pair: Bytes.Bytes & Bytes.Bytes
) -> EncodedBlock:
  match pair:
    case (output_digest, stored_digest):
      Block{Bytes.concat([u32_bytes(payload_len), u32_bytes(count), payload,
        output_digest]), stored_digest}

def block.fin.digest(
  +count: U32,
  pair: Bytes.Bytes & Bytes.Bytes,
  payload: Bytes.Bytes,
  +payload_len: U32
) -> EncodedBlock:
  match pair:
    case (_, _):
      block.fin.digest.parts(count, payload, payload_len, pair)

def block.fin.payload(
  +count: U32,
  +payload_len: U32,
  pair: Bytes.Bytes & Bytes.Bytes
) -> EncodedBlock:
  match pair:
    case (output_payload, hash_payload):
      block.fin.digest(count, bytes.clone.split(
        SHA.sha256_packed_bytes(Bytes.concat([u32_bytes(payload_len),
          u32_bytes(count), hash_payload]))), output_payload, payload_len)

def block.fin(
  +count: U32,
  +payload_len: U32,
  payload: Bytes.Bytes
) -> EncodedBlock:
  block.fin.payload(count, payload_len, bytes.clone.split(payload))

def block.payload.check(
  +count: U32,
  +payload_len: U32,
  payload: Bytes.Bytes,
  within: Bool
) -> Result<&1, &1, Error, EncodedBlock>:
  match within:
    case True{}:
      Done{block.fin(count, payload_len, payload)}
    case False{}:
      Fail{TooLarge{}}

def block.payload.total(
  +count: U32,
  payload_pair: Bytes.Bytes & U32
) -> Result<&1, &1, Error, EncodedBlock>:
  match payload_pair:
    case (payload, +payload_len):
      block.payload.check(count, payload_len, payload,
        U32.is_le(payload_len, StorageBytes.MAX_BLOCK_BYTES()) ||
        U32.is_eq(count, 1) && U32.is_le(payload_len, StorageBytes.MAX_RECORD_BYTES()))

def block.payload(
  count: U32,
  result: Result<&1, &1, Error, List<&1, Bytes.Bytes>>
) -> Result<&1, &1, Error, EncodedBlock>:
  match result:
    case Fail{error}:
      Fail{error}
    case Done{fragments}:
      block.payload.total(count, Bytes.length(Bytes.concat(fragments)))

# Encode records and compute the block digest.
def encode_block(+entries: List<&2, MemTable.Entry>) -> Result<&1, &1, Error, EncodedBlock>:
  block.payload(U32.from_nat(List.length(&2, MemTable.Entry, entries)), records(entries))

# Store a block digest and continue with the remaining blocks.
def blocks.prepare.step(
  rest: List<&2, List<&2, MemTable.Entry>>,
  current: Result<&1, &1, Error, EncodedBlock>,
  blocks: List<&1, Bytes.Bytes>,
  digests: List<&1, Bytes.Bytes>
) -> Result<&1, &1, Error, List<&1, Bytes.Bytes> & List<&1, Bytes.Bytes>>:
  match rest current:
    case Nil{} Fail{error}:
      Fail{error}
    case Nil{} Done{Block{bytes, digest}}:
      Done{(List.reverse(&1, Bytes.Bytes, bytes <> blocks),
        List.reverse(&1, Bytes.Bytes, digest <> digests))}
    case Con{_entries, _tail} Fail{error}:
      Fail{error}
    case Con{entries, tail} Done{Block{bytes, digest}}:
      blocks.prepare.step(tail, encode_block(entries), bytes <> blocks, digest <> digests)

def blocks.prepare(
  +chunks: List<&2, List<&2, MemTable.Entry>>
) -> Result<&1, &1, Error, List<&1, Bytes.Bytes> & List<&1, Bytes.Bytes>>:
  match chunks:
    case Nil{}:
      Done{(Nil{}, Nil{})}
    case Con{entries, rest}:
      blocks.prepare.step(rest, encode_block(entries), Nil{}, Nil{})

# Encode fixed-width v3 header fields in network byte order.
def header_bytes(
  +level: U32,
  +total: U32,
  +block_count: U32
) -> Bytes.Bytes:
  Bytes.concat([hex_bytes.fin(Bytes.from_hex("4d594c534d335300")),
    u32_bytes(level), u32_bytes(total), u32_bytes(block_count)])

# Propagate the block-summary result into an encoder header and footer.
def encoder.build(
  +entries: List<&2, MemTable.Entry>,
  +level: U32,
  +block_count: U32,
  prepared: Result<&1, &1, Error, List<&1, Bytes.Bytes> & List<&1, Bytes.Bytes>>
) -> Result<&1, &1, Error, Encoder>:
  match prepared:
    case Fail{error}:
      Fail{error}
    case Done{(chunks, hashes)}:
      +total = U32.from_nat(List.length(&2, MemTable.Entry, entries))
      root = SHA.sha256_packed_bytes(Bytes.concat(header_bytes(level, total, block_count) <> hashes))
      footer = Bytes.concat([hex_bytes.fin(Bytes.from_hex("454e4433")), u32_bytes(total), root])
      Done{Enc{Header{}, chunks, level, total, block_count, footer}}

# Create an encoder only for supported levels and bounded records.
def new_encoder.ready(
  +entries: List<&2, MemTable.Entry>,
  +level: U32,
  +chunks: List<&2, List<&2, MemTable.Entry>>
) -> Result<&1, &1, Error, Encoder>:
  encoder.build(entries, level,
    U32.from_nat(List.length(&2, List<&2, MemTable.Entry>, chunks)), blocks.prepare(chunks))

def new_encoder.order(
  +entries: List<&2, MemTable.Entry>,
  +level: U32,
  ordered: Bool
) -> Result<&1, &1, Error, Encoder>:
  match ordered:
    case False{}:
      Fail{InvalidOrder{}}
    case True{}:
      new_encoder.ready(entries, level, blocks.pack(entries))

def new_encoder.valid(
  +entries: List<&2, MemTable.Entry>,
  +level: U32,
  valid: Bool
) -> Result<&1, &1, Error, Encoder>:
  match valid:
    case False{}:
      Fail{InvalidLevel{}}
    case True{}:
      new_encoder.order(entries, level, entries.strict(entries))

# Validate input order and level before encoding.
def new_encoder(
  +entries: List<&2, MemTable.Entry>,
  +level: U32
) -> Result<&1, &1, Error, Encoder>:
  new_encoder.valid(entries, level, U32.is_le(level, 255))

# Yield the next serialized part and advance encoder state.
def next_chunk(encoder: Encoder) -> Encoder & Maybe<&1, Bytes.Bytes>:
  match encoder:
    case Enc{Header{}, chunks, +level, +total, +block_count, footer}:
      (Enc{Blocks{}, chunks, level, total, block_count, footer}, Some{header_bytes(level, total, block_count)})
    case Enc{Blocks{}, Nil{}, level, total, block_count, footer}:
      (Enc{Finished{}, Nil{}, level, total, block_count, Bytes.new(0)}, Some{footer})
    case Enc{Blocks{}, Con{bytes, rest}, level, total, block_count, footer}:
      (Enc{Blocks{}, rest, level, total, block_count, footer}, Some{bytes})
    case Enc{Finished{}, chunks, level, total, block_count, footer}:
      (Enc{Finished{}, chunks, level, total, block_count, footer}, None{})

# Translate the shared strict UTF-8 result into the SST error domain.
type TextRead is Type:
  Text{cursor: Bytes.Cursor, byte: Maybe<&2, U32>}

def parse.text.wrap(pair: Bytes.Cursor & Maybe<&2, U32>) -> TextRead:
  match pair:
    case (cursor, byte):
      Text{cursor, byte}

def parse.text.finish(
  cursor: Bytes.Cursor,
  result: Result<&1, &1, U32 & String, String>
) -> Bytes.Cursor & Result<&1, &1, Error, String>:
  match result:
    case Fail{_}:
      (cursor, Fail{InvalidUtf8{}})
    case Done{text}:
      (cursor, Done{text})

# Read exactly n UTF-8 bytes from a bounded cursor without materializing a slice.
def parse.text.go(
  remaining: Nat,
  read: TextRead,
  state: StorageBytes.Utf8State
) -> Bytes.Cursor & Result<&1, &1, Error, String>:
  match remaining read:
    case 0n Text{cursor, _}:
      parse.text.finish(cursor, StorageBytes.utf8.scan.fin(state))
    case 1n+0n Text{cursor, Some{+byte}}:
      parse.text.finish(cursor, StorageBytes.utf8.scan.fin(
        StorageBytes.utf8.step(state, byte)))
    case 1n+1n+rest Text{cursor, Some{+byte}}:
      parse.text.go(1n+rest, parse.text.wrap(Bytes.Cursor.u8(cursor)),
        StorageBytes.utf8.step(state, byte))
    case 1n+_ Text{cursor, None{}}:
      (cursor, Fail{Malformed{}})

def parse.text.start(
  cursor: Bytes.Cursor,
  +length: U32,
  empty: Bool
) -> Bytes.Cursor & Result<&1, &1, Error, String>:
  match empty:
    case True{}:
      parse.text.go(0n, Text{cursor, Some{0}},
        StorageBytes.Utf8State{0, 128, 191, 0, SNil{}, True{}})
    case False{}:
      parse.text.go(U32.to_nat(length), parse.text.wrap(Bytes.Cursor.u8(cursor)),
        StorageBytes.Utf8State{0, 128, 191, 0, SNil{}, True{}})

def parse.text(
  cursor: Bytes.Cursor,
  +length: U32
) -> Bytes.Cursor & Result<&1, &1, Error, String>:
  parse.text.start(cursor, length, U32.is_eq(length, 0))

# Parsed mutation paired with its encoded byte length.
type ParsedRecord is Type:
  Rec{entry: MemTable.Entry, bytes_used: U32}

# Decode one length-delimited key and optional value from the cursor.
def parse.record.value.decoded(
  pair: Bytes.Cursor & Result<&1, &1, Error, String>,
  +key_len: U32,
  +key: String,
  +value_len: U32
) -> Bytes.Cursor & Result<&1, &1, Error, ParsedRecord>:
  match pair:
    case (cursor, Fail{error}):
      (cursor, Fail{error})
    case (cursor, Done{value}):
      (cursor, Done{Rec{MemTable.Entry{key, Some{value}},
        (9 + key_len + value_len : U32)}})

def parse.record.value.length.checked(
  cursor: Bytes.Cursor,
  +key_len: U32,
  +key: String,
  +value_len: U32,
  valid: Bool
) -> Bytes.Cursor & Result<&1, &1, Error, ParsedRecord>:
  match valid:
    case False{}:
      (cursor, Fail{TooLarge{}})
    case True{}:
      parse.record.value.decoded(parse.text(cursor, value_len), key_len,
        key, value_len)

def parse.record.value.length(
  pair: Bytes.Cursor & Maybe<&2, U32>,
  +key_len: U32,
  +key: String
) -> Bytes.Cursor & Result<&1, &1, Error, ParsedRecord>:
  match pair:
    case (cursor, Some{+value_len}):
      parse.record.value.length.checked(cursor, key_len, key, value_len,
        U32.is_le(value_len, (StorageBytes.MAX_RECORD_BYTES() - 9 - key_len : U32)))
    case (cursor, None{}):
      (cursor, Fail{Malformed{}})

def parse.record.key.ready(
  cursor: Bytes.Cursor,
  tag: U32,
  +key_len: U32,
  +key: String
) -> Bytes.Cursor & Result<&1, &1, Error, ParsedRecord>:
  match tag:
    case 1:
      (cursor, Done{Rec{MemTable.Entry{key, None{}}, (5 + key_len : U32)}})
    case 0:
      parse.record.value.length(Bytes.Cursor.u32be(cursor), key_len, key)
    case _:
      (cursor, Fail{Malformed{}})

def parse.record.key.decoded(
  pair: Bytes.Cursor & Result<&1, &1, Error, String>,
  tag: U32,
  +key_len: U32
) -> Bytes.Cursor & Result<&1, &1, Error, ParsedRecord>:
  match pair:
    case (cursor, Fail{error}):
      (cursor, Fail{error})
    case (cursor, Done{key}):
      parse.record.key.ready(cursor, tag, key_len, key)

def parse.record.key.limit(
  tag: U32,
  +key_len: U32
) -> Bool:
  match tag:
    case 1:
      U32.is_le(key_len, (StorageBytes.MAX_RECORD_BYTES() - 5 : U32))
    case _:
      U32.is_le(key_len, (StorageBytes.MAX_RECORD_BYTES() - 9 : U32))

def parse.record.key.length.checked(
  cursor: Bytes.Cursor,
  tag: U32,
  +key_len: U32,
  valid: Bool
) -> Bytes.Cursor & Result<&1, &1, Error, ParsedRecord>:
  match valid:
    case False{}:
      (cursor, Fail{TooLarge{}})
    case True{}:
      parse.record.key.decoded(parse.text(cursor, key_len), tag, key_len)

def parse.record.key.length(
  pair: Bytes.Cursor & Maybe<&2, U32>,
  +tag: U32
) -> Bytes.Cursor & Result<&1, &1, Error, ParsedRecord>:
  match pair:
    case (cursor, Some{+key_len}):
      parse.record.key.length.checked(cursor, tag, key_len,
        parse.record.key.limit(tag, key_len))
    case (cursor, None{}):
      (cursor, Fail{Malformed{}})

def parse.record.tag(
  pair: Bytes.Cursor & Maybe<&2, U32>
) -> Bytes.Cursor & Result<&1, &1, Error, ParsedRecord>:
  match pair:
    case (cursor, Some{0}):
      parse.record.key.length(Bytes.Cursor.u32be(cursor), 0)
    case (cursor, Some{1}):
      parse.record.key.length(Bytes.Cursor.u32be(cursor), 1)
    case (cursor, Some{_}):
      (cursor, Fail{Malformed{}})
    case (cursor, None{}):
      (cursor, Fail{Malformed{}})

def parse.record(
  cursor: Bytes.Cursor
) -> Bytes.Cursor & Result<&1, &1, Error, ParsedRecord>:
  parse.record.tag(Bytes.Cursor.u8(cursor))

# Parsed entries in reverse order with the last strict-order key.
type ParsedEntries is Type:
  Entries{reversed: List<&2, MemTable.Entry>, previous: Maybe<&2, String>}

# Record result annotated with block bounds and key order.
type RecordRead is Type:
  Record{cursor: Bytes.Cursor,
    result: Result<&1, &1, Error, ParsedRecord>,
    within: Bool, ordered: Bool, last: Bool, complete: Bool, key: String}

# Decision for a record at its declared block position.
type RecordDecision is Type:
  Rejected{cursor: Bytes.Cursor, error: Error}
  OutOfBounds{cursor: Bytes.Cursor}
  OutOfOrder{cursor: Bytes.Cursor}
  LastMalformed{cursor: Bytes.Cursor}
  LastRecord{cursor: Bytes.Cursor, entry: MemTable.Entry, key: String}
  MoreRecords{cursor: Bytes.Cursor, entry: MemTable.Entry, key: String, used: U32}

def parse.entries.ordered(
  previous: Maybe<&2, String>,
  +key: String
) -> Bool:
  match previous:
    case None{}:
      True{}
    case Some{current}:
      Keys.lt(current, key)

def parse.record.read.entry(
  cursor: Bytes.Cursor,
  +entry: MemTable.Entry,
  +bytes_used: U32,
  +payload_left: U32,
  previous: Maybe<&2, String>,
  last: Bool
) -> RecordRead:
  match entry:
    case MemTable.Entry{+key, _}:
      Record{cursor, Done{Rec{entry, bytes_used}},
        U32.is_le(bytes_used, payload_left), parse.entries.ordered(previous, key),
        last, U32.is_eq(bytes_used, payload_left), key}

def parse.record.read.pair(
  pair: Bytes.Cursor & Result<&1, &1, Error, ParsedRecord>,
  payload_left: U32,
  previous: Maybe<&2, String>,
  last: Bool
) -> RecordRead:
  match pair:
    case (cursor, Fail{error}):
      Record{cursor, Fail{error}, False{}, False{}, last, False{}, ""}
    case (cursor, Done{Rec{entry, +bytes_used}}):
      parse.record.read.entry(cursor, entry, bytes_used, payload_left, previous, last)

def parse.record.read(
  cursor: Bytes.Cursor,
  +payload_left: U32,
  previous: Maybe<&2, String>,
  last: Bool
) -> RecordRead:
  parse.record.read.pair(parse.record(cursor), payload_left, previous, last)

def parse.records.decision(read: RecordRead) -> RecordDecision:
  match read:
    case Record{cursor, Fail{error}, _, _, _, _, _}:
      Rejected{cursor, error}
    case Record{cursor, Done{_}, False{}, _, _, _, _}:
      OutOfBounds{cursor}
    case Record{cursor, Done{_}, True{}, False{}, _, _, _}:
      OutOfOrder{cursor}
    case Record{cursor, Done{_}, True{}, True{}, True{}, False{}, _}:
      LastMalformed{cursor}
    case Record{cursor, Done{Rec{entry, _}}, True{}, True{}, True{}, True{}, +key}:
      LastRecord{cursor, entry, key}
    case Record{cursor, Done{Rec{entry, +used}}, True{}, True{}, False{}, _, +key}:
      MoreRecords{cursor, entry, key, used}

# Parse a counted sequence and enforce block boundaries and strict key order.
def parse.records.empty(
  decision: RecordDecision
) -> Bytes.Cursor & Result<&1, &1, Error, ParsedEntries>:
  match decision:
    case Rejected{cursor, _}:
      (cursor, Fail{Malformed{}})
    case OutOfBounds{cursor}:
      (cursor, Fail{Malformed{}})
    case OutOfOrder{cursor}:
      (cursor, Fail{Malformed{}})
    case LastMalformed{cursor}:
      (cursor, Fail{Malformed{}})
    case LastRecord{cursor, _, _}:
      (cursor, Fail{Malformed{}})
    case MoreRecords{cursor, _, _, _}:
      (cursor, Fail{Malformed{}})

def parse.records.go(
  remaining: Nat,
  decision: RecordDecision,
  +payload_left: U32,
  acc: List<&2, MemTable.Entry>
) -> Bytes.Cursor & Result<&1, &1, Error, ParsedEntries>:
  match remaining:
    case 0n:
      parse.records.empty(decision)
    case 1n++rest:
      match decision:
        case Rejected{cursor, error}:
          (cursor, Fail{error})
        case OutOfBounds{cursor}:
          (cursor, Fail{Malformed{}})
        case OutOfOrder{cursor}:
          (cursor, Fail{InvalidOrder{}})
        case LastMalformed{cursor}:
          (cursor, Fail{Malformed{}})
        case LastRecord{cursor, entry, +key}:
          (cursor, Done{Entries{Con{entry, acc}, Some{key}}})
        case MoreRecords{cursor, entry, +key, +used}:
          +payload_after = (payload_left - used : U32)
          parse.records.go(rest,
            parse.records.decision(parse.record.read(cursor, payload_after,
              Some{key}, Nat.is_eq(rest, 1n))),
            payload_after, Con{entry, acc})

def parse.records.zero(
  cursor: Bytes.Cursor,
  previous: Maybe<&2, String>,
  empty: Bool
) -> Bytes.Cursor & Result<&1, &1, Error, ParsedEntries>:
  match empty:
    case True{}:
      (cursor, Done{Entries{Nil{}, previous}})
    case False{}:
      (cursor, Fail{Malformed{}})

def parse.records.start(
  cursor: Bytes.Cursor,
  +count: U32,
  +payload_len: U32,
  previous: Maybe<&2, String>
) -> Bytes.Cursor & Result<&1, &1, Error, ParsedEntries>:
  match count:
    case 0:
      parse.records.zero(cursor, previous, U32.is_eq(payload_len, 0))
    case _:
      parse.records.go(U32.to_nat(count),
        parse.records.decision(parse.record.read(cursor, payload_len, previous, U32.is_eq(count, 1))),
        payload_len, Nil{})

# Cursor state while assembling a fixed-width digest.
type HashRead is Type:
  HashInput{cursor: Bytes.Cursor, value: Maybe<&2, U32>}

# Validated records, count, and digest for one block.
type ParsedBlock is Type:
  ParsedBlock{records: ParsedEntries, count: U32, digest: Bytes.Bytes}

# Represent StreamState data used by the packed SSTable codec.
type StreamState is Type:
  StreamState{level: U32, total: U32, block_count: U32,
    remaining: U32, entries_left: U32,
    previous: Maybe<&2, String>, entries: List<&2, MemTable.Entry>,
    hashes: List<&1, Bytes.Bytes>}

def parse.hash.wrap(pair: Bytes.Cursor & Maybe<&2, U32>) -> HashRead:
  match pair:
    case (cursor, value):
      HashInput{cursor, value}

def parse.hash.result(
  pair: Bytes.Cursor & Result<&1, &1, Error, Bytes.Bytes>
) -> Bytes.Cursor & Result<&1, &1, Error, Bytes.Bytes>:
  pair

# Read exactly eight words into a digest without consuming a byte after it.
def parse.hash.words.go(
  remaining: Nat,
  read: HashRead,
  digest: Bytes.Bytes,
  +offset: U32
) -> Bytes.Cursor & Result<&1, &1, Error, Bytes.Bytes>:
  match remaining read:
    case 0n HashInput{cursor, _}:
      (cursor, Done{digest})
    case 1n+0n HashInput{cursor, Some{word}}:
      (cursor, Done{Bytes.set.u32be(digest, offset, word)})
    case 1n+1n+rest HashInput{cursor, Some{word}}:
      parse.hash.words.go(1n+rest, parse.hash.wrap(Bytes.Cursor.u32be(cursor)),
        Bytes.set.u32be(digest, offset, word), (offset + 4 : U32))
    case 1n+_ HashInput{cursor, None{}}:
      (cursor, Fail{Malformed{}})

def parse.hash.words(
  cursor: Bytes.Cursor
) -> Bytes.Cursor & Result<&1, &1, Error, Bytes.Bytes>:
  parse.hash.words.go(8n, parse.hash.wrap(Bytes.Cursor.u32be(cursor)), Bytes.new(32), 0)

def parse.block.verify.equal(
  cursor: Bytes.Cursor,
  records: ParsedEntries,
  +count: U32,
  comparison: Bytes.Bytes & Bytes.Bytes & Bool
) -> Bytes.Cursor & Result<&1, &1, Error, ParsedBlock>:
  match comparison:
    case (claimed, actual, False{}):
      (cursor, Fail{ChecksumMismatch{}})
    case (claimed, digest, True{}):
      (cursor, Done{ParsedBlock{records, count, digest}})

def parse.block.verify.copy(
  pair: Bytes.Bytes & Bytes.Bytes,
  +pos: U32,
  +start: U32,
  +end: U32,
  records: ParsedEntries,
  +count: U32,
  claimed: Bytes.Bytes
) -> Bytes.Cursor & Result<&1, &1, Error, ParsedBlock>:
  match pair:
    case (source, content):
      parse.block.verify.equal(Bytes.Cursor{source, pos, start, end}, records,
        count, Bytes.eq(claimed, SHA.sha256_packed_bytes(content)))

def parse.block.verify(
  cursor: Bytes.Cursor,
  records: ParsedEntries,
  +payload_len: U32,
  +count: U32,
  claimed: Bytes.Bytes
) -> Bytes.Cursor & Result<&1, &1, Error, ParsedBlock>:
  match cursor:
    case Bytes.Cursor{bytes, +pos, +start, +end}:
      parse.block.verify.copy(Bytes.slice(bytes,
        (pos - (payload_len + 40 : U32) : U32), (payload_len + 8 : U32)),
        pos, start, end, records, count, claimed)

def parse.block.digest(
  pair: Bytes.Cursor & Result<&1, &1, Error, Bytes.Bytes>,
  records: ParsedEntries,
  +payload_len: U32,
  +count: U32
) -> Bytes.Cursor & Result<&1, &1, Error, ParsedBlock>:
  match pair:
    case (cursor, Fail{error}):
      (cursor, Fail{error})
    case (cursor, Done{claimed}):
      parse.block.verify(cursor, records, payload_len, count, claimed)

def parse.block.records(
  pair: Bytes.Cursor & Result<&1, &1, Error, ParsedEntries>,
  +payload_len: U32,
  +count: U32
) -> Bytes.Cursor & Result<&1, &1, Error, ParsedBlock>:
  match pair:
    case (cursor, Fail{error}):
      (cursor, Fail{error})
    case (cursor, Done{records}):
      parse.block.digest(parse.hash.words(cursor), records, payload_len, count)

def parse.block.count.valid(
  cursor: Bytes.Cursor,
  +payload_len: U32,
  +count: U32,
  previous: Maybe<&2, String>,
  valid: Bool
) -> Bytes.Cursor & Result<&1, &1, Error, ParsedBlock>:
  match valid:
    case False{}:
      (cursor, Fail{Malformed{}})
    case True{}:
      parse.block.records(parse.records.start(cursor, count, payload_len, previous),
        payload_len, count)

def parse.block.count(
  pair: Bytes.Cursor & Maybe<&2, U32>,
  +payload_len: U32,
  previous: Maybe<&2, String>
) -> Bytes.Cursor & Result<&1, &1, Error, ParsedBlock>:
  match pair:
    case (cursor, Some{+count}):
      parse.block.count.valid(cursor, payload_len, count, previous,
        U32.is_lt(0, count) && (U32.is_le(payload_len, StorageBytes.MAX_BLOCK_BYTES()) ||
          U32.is_eq(count, 1) && U32.is_le(payload_len, StorageBytes.MAX_RECORD_BYTES())))
    case (cursor, None{}):
      (cursor, Fail{Malformed{}})

def parse.block.length(
  pair: Bytes.Cursor & Maybe<&2, U32>,
  previous: Maybe<&2, String>
) -> Bytes.Cursor & Result<&1, &1, Error, ParsedBlock>:
  match pair:
    case (cursor, Some{+payload_len}):
      parse.block.count(Bytes.Cursor.u32be(cursor), payload_len, previous)
    case (cursor, None{}):
      (cursor, Fail{Malformed{}})

# Parse, bound, and authenticate one complete SST block.
def parse.block(
  cursor: Bytes.Cursor,
  previous: Maybe<&2, String>
) -> Bytes.Cursor & Result<&1, &1, Error, ParsedBlock>:
  parse.block.length(Bytes.Cursor.u32be(cursor), previous)

def parse.footer.end(
  +level: U32,
  entries: List<&2, MemTable.Entry>,
  at_end: Bool
) -> Result<&1, &1, Error, Sstable.Table>:
  match at_end:
    case False{}:
      Fail{Malformed{}}
    case True{}:
      Done{Sstable.from_sorted_unique(
        List.reverse(&2, MemTable.Entry, entries), U32.to_nat(level))}

def parse.footer.check(
  +level: U32,
  entries: List<&2, MemTable.Entry>,
  at_end: Bool,
  comparison: Bytes.Bytes & Bytes.Bytes & Bool
) -> Result<&1, &1, Error, Sstable.Table>:
  match comparison:
    case (claimed_back, expected_back, False{}):
      Fail{ChecksumMismatch{}}
    case (claimed_back, expected_back, True{}):
      parse.footer.end(level, entries, at_end)

def parse.footer.verify(
  cursor: Bytes.Cursor,
  claimed: Bytes.Bytes,
  +level: U32,
  +total: U32,
  +block_count: U32,
  entries: List<&2, MemTable.Entry>,
  hashes: List<&1, Bytes.Bytes>
) -> Result<&1, &1, Error, Sstable.Table>:
  match cursor:
    case Bytes.Cursor{bytes, +pos, _, +end}:
      expected = SHA.sha256_packed_bytes(Bytes.concat(
        header_bytes(level, total, block_count) <> List.reverse(&1, Bytes.Bytes, hashes)))
      parse.footer.check(level, entries, U32.is_eq(pos, end),
        Bytes.eq(claimed, expected))

def parse.footer.root(
  pair: Bytes.Cursor & Result<&1, &1, Error, Bytes.Bytes>,
  +level: U32,
  +total: U32,
  +block_count: U32,
  entries: List<&2, MemTable.Entry>,
  hashes: List<&1, Bytes.Bytes>
) -> Result<&1, &1, Error, Sstable.Table>:
  match pair:
    case (_, Fail{error}):
      Fail{error}
    case (cursor, Done{claimed}):
      parse.footer.verify(cursor, claimed, level, total, block_count, entries, hashes)

def parse.footer.count.checked(
  cursor: Bytes.Cursor,
  +level: U32,
  +total: U32,
  +block_count: U32,
  entries: List<&2, MemTable.Entry>,
  hashes: List<&1, Bytes.Bytes>,
  valid: Bool
) -> Result<&1, &1, Error, Sstable.Table>:
  match valid:
    case False{}:
      Fail{Malformed{}}
    case True{}:
      parse.footer.root(parse.hash.words(cursor), level, total, block_count,
        entries, hashes)

def parse.footer.count(
  pair: Bytes.Cursor & Maybe<&2, U32>,
  +level: U32,
  +total: U32,
  +block_count: U32,
  entries: List<&2, MemTable.Entry>,
  hashes: List<&1, Bytes.Bytes>
) -> Result<&1, &1, Error, Sstable.Table>:
  match pair:
    case (cursor, Some{+footer_total}):
      parse.footer.count.checked(cursor, level, total, block_count, entries,
        hashes, U32.is_eq(total, footer_total))
    case (_, None{}):
      Fail{Malformed{}}

def parse.footer.magic(
  pair: Bytes.Cursor & Maybe<&2, U32>,
  +level: U32,
  +total: U32,
  +block_count: U32,
  entries: List<&2, MemTable.Entry>,
  hashes: List<&1, Bytes.Bytes>
) -> Result<&1, &1, Error, Sstable.Table>:
  match pair:
    case (cursor, Some{1162757171}):
      parse.footer.count(Bytes.Cursor.u32be(cursor), level, total,
        block_count, entries, hashes)
    case (_, _):
      Fail{Malformed{}}

# Block result paired with its ending cursor.
type BlockRead is Type:
  BlockInput{cursor: Bytes.Cursor, result: Result<&1, &1, Error, ParsedBlock>}

def parse.block.read(pair: Bytes.Cursor & Result<&1, &1, Error, ParsedBlock>) -> BlockRead:
  match pair:
    case (cursor, result):
      BlockInput{cursor, result}

def parse.blocks.count.valid.last(
  last: Bool,
  +entries_left: U32,
  +count: U32
) -> Bool:
  match last:
    case True{}:
      U32.is_eq(entries_left, count)
    case False{}:
      U32.is_lt(count, entries_left)

def parse.blocks.count.valid(
  +remaining: Nat,
  +entries_left: U32,
  +count: U32
) -> Bool:
  parse.blocks.count.valid.last(Nat.is_eq(remaining, 1n), entries_left, count)

def parse.blocks.accumulate.records.last(
  cursor: Bytes.Cursor,
  +entries_left: U32,
  entries: List<&2, MemTable.Entry>,
  hashes: List<&1, Bytes.Bytes>,
  reversed: List<&2, MemTable.Entry>,
  previous: Maybe<&2, String>,
  last: Bool
) -> BlockDecision:
  match last:
    case True{}:
      BlockFinish{cursor, List.append(&2, MemTable.Entry, reversed, entries), hashes}
    case False{}:
      BlockContinue{cursor, entries_left, previous,
        List.append(&2, MemTable.Entry, reversed, entries), hashes}

def parse.blocks.accumulate.records(
  cursor: Bytes.Cursor,
  +remaining: Nat,
  +entries_left: U32,
  entries: List<&2, MemTable.Entry>,
  hashes: List<&1, Bytes.Bytes>,
  records: ParsedEntries
) -> BlockDecision:
  match records:
    case Entries{reversed, previous}:
      parse.blocks.accumulate.records.last(cursor, entries_left, entries,
        hashes, reversed, previous, Nat.is_eq(remaining, 1n))

def parse.blocks.content.valid(
  cursor: Bytes.Cursor,
  +remaining: Nat,
  +entries_left: U32,
  entries: List<&2, MemTable.Entry>,
  hashes: List<&1, Bytes.Bytes>,
  +count: U32,
  records: ParsedEntries,
  digest: Bytes.Bytes,
  valid: Bool
) -> BlockDecision:
  match valid:
    case False{}:
      BlockOutOfBounds{}
    case True{}:
      parse.blocks.accumulate.records(cursor, remaining,
        (entries_left - count : U32), entries, digest <> hashes, records)

def parse.blocks.content.fit(
  cursor: Bytes.Cursor,
  +remaining: Nat,
  +entries_left: U32,
  entries: List<&2, MemTable.Entry>,
  hashes: List<&1, Bytes.Bytes>,
  +count: U32,
  records: ParsedEntries,
  digest: Bytes.Bytes,
  fits: Bool
) -> BlockDecision:
  match fits:
    case False{}:
      BlockOutOfBounds{}
    case True{}:
      parse.blocks.content.valid(cursor, remaining, entries_left,
        entries, hashes, count, records, digest,
        parse.blocks.count.valid(remaining, entries_left, count))

def parse.blocks.content(
  cursor: Bytes.Cursor,
  +remaining: Nat,
  +entries_left: U32,
  entries: List<&2, MemTable.Entry>,
  hashes: List<&1, Bytes.Bytes>,
  block: ParsedBlock
) -> BlockDecision:
  match block:
    case ParsedBlock{records, +count, digest}:
      parse.blocks.content.fit(cursor, remaining, entries_left,
        entries, hashes, count, records, digest, U32.is_le(count, entries_left))

def parse.blocks.decision(
  read: BlockRead,
  +remaining: Nat,
  +entries_left: U32,
  entries: List<&2, MemTable.Entry>,
  hashes: List<&1, Bytes.Bytes>
) -> BlockDecision:
  match read:
    case BlockInput{_, Fail{error}}:
      BlockRejected{error}
    case BlockInput{cursor, Done{block}}:
      parse.blocks.content(cursor, remaining, entries_left, entries,
        hashes, block)

def parse.blocks.go(
  remaining: Nat,
  decision: BlockDecision,
  +level: U32,
  +total: U32,
  +block_count: U32
) -> Result<&1, &1, Error, Sstable.Table>:
  match remaining:
    case 0n:
      Fail{Malformed{}}
    case 1n++rest:
      match decision:
        case BlockRejected{error}:
          Fail{error}
        case BlockOutOfBounds{}:
          Fail{Malformed{}}
        case BlockFinish{cursor, entries, hashes}:
          parse.footer.magic(Bytes.Cursor.u32be(cursor), level, total,
            block_count, entries, hashes)
        case BlockContinue{cursor, entries_left, previous, entries, hashes}:
          parse.blocks.go(rest,
            parse.blocks.decision(
              parse.block.read(parse.block(cursor, previous)), rest,
              entries_left, entries, hashes),
            level, total, block_count)

def parse.blocks.start(
  cursor: Bytes.Cursor,
  valid: Bool,
  +count: U32,
  +total: U32,
  +level: U32
) -> Result<&1, &1, Error, Sstable.Table>:
  match valid:
    case False{}:
      Fail{Malformed{}}
    case True{}:
      match count:
        case 0:
          parse.footer.magic(Bytes.Cursor.u32be(cursor), level, total,
            count, Nil{}, Nil{})
        case _:
          parse.blocks.go(U32.to_nat(count),
            parse.blocks.decision(
              parse.block.read(parse.block(cursor, None{})), U32.to_nat(count),
            total, Nil{}, Nil{}),
            level, total, count)

def stream.block.records(
  +level: U32,
  +total: U32,
  +block_count: U32,
  +remaining: U32,
  +entries_left: U32,
  entries: List<&2, MemTable.Entry>,
  hashes: List<&1, Bytes.Bytes>,
  records: ParsedEntries,
  +count: U32,
  digest: Bytes.Bytes
) -> Result<&1, &1, Error, StreamState>:
  match records:
    case Entries{reversed, previous}:
      Done{StreamState{level, total, block_count,
        (remaining - 1 : U32), (entries_left - count : U32),
        previous, List.append(&2, MemTable.Entry, reversed, entries),
        digest <> hashes}}

def stream.block.count(
  +level: U32,
  +total: U32,
  +block_count: U32,
  +remaining: U32,
  +entries_left: U32,
  entries: List<&2, MemTable.Entry>,
  hashes: List<&1, Bytes.Bytes>,
  records: ParsedEntries,
  +count: U32,
  digest: Bytes.Bytes,
  valid: Bool
) -> Result<&1, &1, Error, StreamState>:
  match valid:
    case False{}:
      Fail{Malformed{}}
    case True{}:
      stream.block.records(level, total, block_count, remaining,
        entries_left, entries, hashes, records, count, digest)

def stream.block.valid(
  state: StreamState,
  records: ParsedEntries,
  +count: U32,
  digest: Bytes.Bytes,
  exact: Bool
) -> Result<&1, &1, Error, StreamState>:
  match state:
    case StreamState{+level, +total, +block_count, +remaining, +entries_left, _, entries, hashes}:
      stream.block.count(level, total, block_count, remaining,
        entries_left, entries, hashes, records, count, digest,
        exact && U32.is_le(count, entries_left) &&
          parse.blocks.count.valid(U32.to_nat(remaining), entries_left, count))

def stream.block.complete(
  state: StreamState,
  block: ParsedBlock,
  exact: Bool
) -> Result<&1, &1, Error, StreamState>:
  match block:
    case ParsedBlock{records, +count, digest}:
      stream.block.valid(state, records, count, digest, exact)

def stream.block.consumed(
  pair: Bytes.Cursor & U32,
  state: StreamState,
  block: ParsedBlock
) -> Result<&1, &1, Error, StreamState>:
  match pair:
    case (_, remaining):
      stream.block.complete(state, block, U32.is_eq(remaining, 0))

def stream.block.result(
  state: StreamState,
  pair: Bytes.Cursor & Result<&1, &1, Error, ParsedBlock>
) -> Result<&1, &1, Error, StreamState>:
  match pair:
    case (_, Fail{error}):
      Fail{error}
    case (cursor, Done{block}):
      stream.block.consumed(Bytes.Cursor.remaining(cursor), state, block)

def stream.block(state: StreamState, bytes: Bytes.Bytes) -> Result<&1, &1, Error, StreamState>:
  match state:
    case StreamState{_, _, _, 0, _, _, _, _}:
      Fail{Malformed{}}
    case StreamState{+level, +total, +block_count, +remaining,
        +entries_left, +previous, entries, hashes}:
      stream.block.result(
        StreamState{level, total, block_count, remaining, entries_left,
          previous, entries, hashes},
        parse.block(Bytes.Cursor.new(bytes), previous))

def stream.footer(state: StreamState, bytes: Bytes.Bytes) -> Result<&1, &1, Error, Sstable.Table>:
  match state:
    case StreamState{+level, +total, +block_count, 0, 0, _, entries, hashes}:
      parse.footer.magic(
        Bytes.Cursor.u32be(Bytes.Cursor.new(bytes)), level, total,
        block_count, entries, hashes)
    case _:
      Fail{Malformed{}}

def stream.block.tail.size(
  pair: Bytes.Cursor & Maybe<&2, U32>,
  +payload_len: U32
) -> Maybe<&2, U32>:
  match pair:
    case (_, Some{+count}):
      Bool.pick(Maybe<&2, U32>,
        U32.is_lt(0, count) && (U32.is_le(payload_len, StorageBytes.MAX_BLOCK_BYTES()) ||
          U32.is_eq(count, 1) && U32.is_le(payload_len, StorageBytes.MAX_RECORD_BYTES())) &&
          U32.is_le(payload_len, (4294967263 : U32)),
        Some{(payload_len + 32 : U32)}, None{})
    case (_, None{}):
      None{}

def stream.block.tail(cursor: Bytes.Cursor & Maybe<&2, U32>) -> Maybe<&2, U32>:
  match cursor:
    case (next, Some{+payload_len}):
      stream.block.tail.size(Bytes.Cursor.u32be(next), payload_len)
    case (_, None{}):
      None{}

def stream.block.tail_size(bytes: Bytes.Bytes) -> Maybe<&2, U32>:
  stream.block.tail(Bytes.Cursor.u32be(Bytes.Cursor.new(bytes)))

def parse.header.blocks.valid(
  cursor: Bytes.Cursor,
  +level: U32,
  +total: U32,
  +count: U32,
  valid: Bool
) -> Bytes.Cursor & Result<&1, &1, Error, SstHeader>:
  match valid:
    case False{}:
      (cursor, Fail{Malformed{}})
    case True{}:
      (cursor, Done{SstHdr{level, total, count}})

def parse.header.blocks(
  pair: Bytes.Cursor & Maybe<&2, U32>,
  +level: U32,
  +total: U32
) -> Bytes.Cursor & Result<&1, &1, Error, SstHeader>:
  match pair:
    case (cursor, Some{+count}):
      parse.header.blocks.valid(cursor, level, total, count,
        (U32.is_eq(total, 0) && U32.is_eq(count, 0)) ||
          (U32.is_lt(0, total) && U32.is_lt(0, count)))
    case (cursor, None{}):
      (cursor, Fail{Malformed{}})

def parse.header.total(
  pair: Bytes.Cursor & Maybe<&2, U32>,
  +level: U32
) -> Bytes.Cursor & Result<&1, &1, Error, SstHeader>:
  match pair:
    case (cursor, Some{+total}):
      parse.header.blocks(Bytes.Cursor.u32be(cursor), level, total)
    case (cursor, None{}):
      (cursor, Fail{Malformed{}})

def parse.header.level.checked(
  cursor: Bytes.Cursor,
  +level: U32,
  valid: Bool
) -> Bytes.Cursor & Result<&1, &1, Error, SstHeader>:
  match valid:
    case False{}:
      (cursor, Fail{InvalidLevel{}})
    case True{}:
      parse.header.total(Bytes.Cursor.u32be(cursor), level)

def parse.header.level(
  pair: Bytes.Cursor & Maybe<&2, U32>
) -> Bytes.Cursor & Result<&1, &1, Error, SstHeader>:
  match pair:
    case (cursor, Some{+level}):
      parse.header.level.checked(cursor, level, U32.is_le(level, 255))
    case (cursor, None{}):
      (cursor, Fail{Malformed{}})

def parse.header.magic.two(
  pair: Bytes.Cursor & Maybe<&2, U32>
) -> Bytes.Cursor & Result<&1, &1, Error, SstHeader>:
  match pair:
    case (cursor, Some{1295209216}):
      parse.header.level(Bytes.Cursor.u32be(cursor))
    case (cursor, _):
      (cursor, Fail{Malformed{}})

def parse.header.magic.one(
  pair: Bytes.Cursor & Maybe<&2, U32>
) -> Bytes.Cursor & Result<&1, &1, Error, SstHeader>:
  match pair:
    case (cursor, Some{1297697875}):
      parse.header.magic.two(Bytes.Cursor.u32be(cursor))
    case (cursor, _):
      (cursor, Fail{Malformed{}})

def stream.header.remaining(
  pair: Bytes.Cursor & U32,
  +level: U32,
  +total: U32,
  +block_count: U32
) -> Result<&1, &1, Error, StreamState>:
  match pair:
    case (_, 0):
      Done{StreamState{level, total, block_count, block_count,
        total, None{}, Nil{}, Nil{}}}
    case (_, _):
      Fail{Malformed{}}

def stream.header.done(
  pair: Bytes.Cursor & Result<&1, &1, Error, SstHeader>
) -> Result<&1, &1, Error, StreamState>:
  match pair:
    case (_, Fail{error}):
      Fail{error}
    case (cursor, Done{SstHdr{+level, +total, +block_count}}):
      stream.header.remaining(Bytes.Cursor.remaining(cursor), level, total, block_count)

def stream.header(bytes: Bytes.Bytes) -> Result<&1, &1, Error, StreamState>:
  stream.header.done(parse.header.magic.one(
    Bytes.Cursor.u32be(Bytes.Cursor.new(bytes))))

# Retain bounded file chunks until the strict parser is applied.
def new_decoder() -> Decoder:
  Dec{Nil{}, 0, False{}}

def feed.chunk.add(
  chunks: List<&1, Bytes.Bytes>,
  +total: U32,
  invalid: Bool,
  chunk: Bytes.Bytes,
  checked: Maybe<&2, U32>
) -> Decoder:
  match checked:
    case None{}:
      Dec{chunks, total, True{}}
    case Some{next_total}:
      Dec{chunk <> chunks, next_total, invalid}

def feed.chunk.result(
  chunks: List<&1, Bytes.Bytes>,
  +total: U32,
  invalid: Bool,
  pair: Bytes.Bytes & U32
) -> Decoder:
  match pair:
    case (chunk, +len):
      feed.chunk.add(chunks, total, invalid, chunk, StorageBytes.checked_add(total, len))

def feed.chunk(decoder: Decoder, pair: Bytes.Bytes & U32) -> Decoder:
  match decoder:
    case Dec{chunks, total, invalid}:
      feed.chunk.result(chunks, total, invalid, pair)

def feed.if.valid(
  invalid: Bool,
  chunks: List<&1, Bytes.Bytes>,
  total: U32,
  chunk: Bytes.Bytes
) -> Decoder:
  match invalid:
    case True{}:
      Dec{chunks, total, True{}}
    case False{}:
      feed.chunk(Dec{chunks, total, False{}}, Bytes.length(chunk))

# Buffer streaming chunks until the bounded pure parser is applied.
def feed(decoder: Decoder, chunk: Bytes.Bytes) -> Decoder:
  match decoder:
    case Dec{chunks, total, invalid}:
      feed.if.valid(invalid, chunks, total, chunk)

def parse.file.header(
  pair: Bytes.Cursor & Result<&1, &1, Error, SstHeader>
) -> Result<&1, &1, Error, Sstable.Table>:
  match pair:
    case (_, Fail{error}):
      Fail{error}
    case (cursor, Done{SstHdr{+level, +total, +block_count}}):
      parse.blocks.start(cursor, True{}, block_count, total, level)

def parse.file(bytes: Bytes.Bytes) -> Result<&1, &1, Error, Sstable.Table>:
  parse.file.header(parse.header.magic.one(
    Bytes.Cursor.u32be(Bytes.Cursor.new(bytes))))

def finish.concat.check(
  bytes: Bytes.Bytes,
  valid: Bool
) -> Result<&1, &1, Error, Sstable.Table>:
  match valid:
    case True{}:
      parse.file(bytes)
    case False{}:
      Fail{Malformed{}}

def finish.concat.pair(
  +total: U32,
  pair: Bytes.Bytes & U32
) -> Result<&1, &1, Error, Sstable.Table>:
  match pair:
    case (bytes, +len):
      finish.concat.check(bytes, U32.is_eq(total, len))

def finish.concat(
  +total: U32,
  bytes: Bytes.Bytes
) -> Result<&1, &1, Error, Sstable.Table>:
  finish.concat.pair(total, Bytes.length(bytes))

# Parse and authenticate the complete accumulated SST file.
def finish(decoder: Decoder) -> Result<&1, &1, Error, Sstable.Table>:
  match decoder:
    case Dec{chunks, total, False{}}:
      finish.concat(total, Bytes.concat(List.reverse(&1, Bytes.Bytes, chunks)))
    case Dec{_, _, True{}}:
      Fail{TooLarge{}}

# Pure whole-file encoder for fixtures and small in-memory callers. Production
# persistence uses next_chunk directly and never joins the complete file.
def encode.chunks(
  fuel: Nat,
  pair: Encoder & Maybe<&1, Bytes.Bytes>,
  acc: List<&1, Bytes.Bytes>
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match fuel:
    case 0n:
      Fail{TooLarge{}}
    case 1n+rest:
      match pair:
        case (_, None{}):
          Done{Bytes.concat(List.reverse(&1, Bytes.Bytes, acc))}
        case (encoder, Some{chunk}):
          encode.chunks(rest, next_chunk(encoder), Con{chunk, acc})

def encode.ready(
  +entries: List<&2, MemTable.Entry>,
  result: Result<&1, &1, Error, Encoder>
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match result:
    case Fail{error}:
      Fail{error}
    case Done{encoder}:
      encode.chunks(Nat.add(List.length(&2, MemTable.Entry, entries), 3n), next_chunk(encoder), Nil{})

# Encode one complete table for small in-memory callers and fixtures.
def encode_file(
  +entries: List<&2, MemTable.Entry>,
  +level: U32
) -> Result<&1, &1, Error, Bytes.Bytes>:
  encode.ready(entries, new_encoder(entries, level))

# Parse packed bytes into a validated immutable SST table.
def parse(bytes: Bytes.Bytes) -> Result<&1, &1, Error, Sstable.Table>:
  parse.file(bytes)

# Return true because the parser always returns an explicit Result value.
def is_decided(_result: Result<&1, &1, Error, Sstable.Table>) -> Bool:
  True{}

import Base
import ./ByteMemTable.bend as ByteMemTable
import ./ByteWal.bend as ByteWal
import ./StorageBytes.bend as StorageBytes
import ./scan/ByteBlockBuilder.bend as ByteBlockBuilder
import ./coordinator/QueuePolicy.bend as QueuePolicy
import ./Wal.bend as Wal
import ./hub_sha/sha256.bend as SHA
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Errors produced by the generation-four byte SST codec.
type Error is Data:
  InvalidLevel{}
  InvalidOrder{}
  TooLarge{}
  Malformed{}
  ChecksumMismatch{}

# Carries validated one-block envelope metadata after the fixed header.
type PayloadWords is Type:
  PayloadWords{cursor: Bytes.Cursor, size: U32, level: U32, total: U32,
    payload_len: U32, entries: U32}

# Carries a byte-bounded page under construction and completed pages in reverse order.
type PageBuild is Type:
  PageBuild{current: List<&1, ByteMemTable.Entry>, current_bytes: Nat,
    current_count: Nat, completed: List<&1, List<&1, ByteMemTable.Entry>>,
    completed_count: Nat}

# Holds a size-bounded page sequence and its exact count.
type PagePlan is Type:
  PagePlan{pages: List<&1, List<&1, ByteMemTable.Entry>>, count: Nat}

# Carries the shared header metadata used to parse one multi-block SST.
type MultiHeader is Type:
  MultiHeader{file: Bytes.Bytes, level: U32, total: U32, block_count: U32}

# Carries the state while decoding blocks in file order.
type MultiRead is Type:
  MultiRead{file: Bytes.Bytes, index_offset: Nat, next_block: Nat,
    block_count: Nat, level: U32, total: Nat, decoded: Nat,
    table: ByteMemTable.Table}

# Carries an encoded page block and its record count.
type EncodedBlock is Type:
  EncodedBlock{bytes: Bytes.Bytes, byte_length: U32, checksum: Bytes.Bytes,
    count: U32, separator: Bytes.Bytes, separator_length: U32}

# Holds every encoded block and the exact number of pages produced.
type EncodedPages is Type:
  EncodedPages{blocks: List<&1, EncodedBlock>, count: U32}

# Holds concatenated data blocks and the metadata used by the index and root hash.
type BlocksCollected is Type:
  BlocksCollected{bytes: Bytes.Bytes, checksums: Bytes.Bytes,
    index: Bytes.Bytes, block_count: U32, entry_count: U32}

# Reifies two independently owned copies of a byte buffer.
def clone.pair(+len: U32, copied: Array<U32> & Array<U32>) -> Bytes.Bytes & Bytes.Bytes:
  match copied:
    case (left, right):
      (Bytes.Bytes{len, left}, Bytes.Bytes{len, right})

# Clones bytes when output and hashing both need the same contents.
def clone.split(bytes: Bytes.Bytes) -> Bytes.Bytes & Bytes.Bytes:
  match bytes:
    case Bytes.Bytes{+len, buf}:
      clone.pair(len, Bytes.copy.bytes(len, buf, Bytes.alloc(len), 0, 0))

# Encodes an unsigned 32-bit word in network byte order.
def u32.bytes(value: U32) -> Bytes.Bytes:
  Bytes.set.u32be(Bytes.new(4), 0, value)

# Unwraps fixed known format markers.
def marker(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}:
      bytes
    case None{}:
      Bytes.new(0)

# Returns the generation-four SST signature.
def header.magic() -> Bytes.Bytes:
  marker(Bytes.from_hex("4d594c534d345300"))

# Returns the generation-four index signature.
def index.magic() -> Bytes.Bytes:
  marker(Bytes.from_hex("49445834"))

# Returns the generation-four SST footer signature.
def footer.magic() -> Bytes.Bytes:
  marker(Bytes.from_hex("454e4434"))

# Converts byte table entries to the shared byte WAL mutation representation.
def mutations(entries: List<&1, ByteMemTable.Entry>) -> List<&1, ByteWal.Mutation>:
  match entries:
    case Nil{}:
      Nil{}
    case Con{ByteMemTable.Entry{key, val}, tail}:
      match val:
        case None{}:
          Con{ByteWal.Delete{key}, mutations(tail)}
        case Some{value}:
          Con{ByteWal.Put{key, value}, mutations(tail)}

# Rebuilds two entries from independently owned key and value copies.
def entry.clone.parts(
  keys: Bytes.Bytes & Bytes.Bytes,
  values: Maybe<&1, Bytes.Bytes> & Maybe<&1, Bytes.Bytes>
) -> ByteMemTable.Entry & ByteMemTable.Entry:
  match keys:
    case (first_key, second_key):
      match values:
        case (first_value, second_value):
          (ByteMemTable.Entry{first_key, first_value},
            ByteMemTable.Entry{second_key, second_value})

# Clones one affine entry for independent validation and encoding passes.
def entry.clone(entry: ByteMemTable.Entry) -> ByteMemTable.Entry & ByteMemTable.Entry:
  match entry:
    case ByteMemTable.Entry{key, value}:
      entry.clone.parts(ByteMemTable.bytes.clone(key), ByteMemTable.value.clone(value))

# Prepends two cloned entries to their matching ordered lists.
def entries.clone.push(
  head: ByteMemTable.Entry & ByteMemTable.Entry,
  tail: List<&1, ByteMemTable.Entry> & List<&1, ByteMemTable.Entry>
) -> List<&1, ByteMemTable.Entry> & List<&1, ByteMemTable.Entry>:
  match head:
    case (first, second):
      match tail:
        case (first_tail, second_tail):
          (Con{first, first_tail}, Con{second, second_tail})

# Clones an entire affine entry list without changing its order.
def entries.clone(entries: List<&1, ByteMemTable.Entry>) -> List<&1, ByteMemTable.Entry> & List<&1, ByteMemTable.Entry>:
  match entries:
    case Nil{}:
      (Nil{}, Nil{})
    case Con{entry, tail}:
      entries.clone.push(entry.clone(entry), entries.clone(tail))

# Emits all authenticated file sections with a completed root digest.
def file.emit(
  header: Bytes.Bytes,
  block: Bytes.Bytes,
  index: Bytes.Bytes,
  footer: Bytes.Bytes
) -> Result<&1, &1, Error, Bytes.Bytes>:
  Done{Bytes.concat([header, block, index, footer])}

# Adds the root footer after hashing header, block digest, and index metadata.
def file.root(
  header_output: Bytes.Bytes,
  header_hash: Bytes.Bytes,
  block: Bytes.Bytes,
  block_root: Bytes.Bytes,
  index_output: Bytes.Bytes,
  index_hash: Bytes.Bytes,
  index_length: U32,
  +total: U32
) -> Result<&1, &1, Error, Bytes.Bytes>:
  file.emit(header_output, block, index_output,
    Bytes.concat([footer.magic(), u32.bytes(total), u32.bytes(index_length),
      SHA.sha256_packed_bytes(Bytes.concat([header_hash, block_root, index_hash]))]))

# Separates the index copies used by output and root authentication.
def file.index.length(
  header_output: Bytes.Bytes,
  header_hash: Bytes.Bytes,
  block: Bytes.Bytes,
  block_root: Bytes.Bytes,
  measured: Bytes.Bytes & U32,
  index_hash: Bytes.Bytes,
  +total: U32
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match measured:
    case (output, index_length):
      file.root(header_output, header_hash, block, block_root,
        output, index_hash, index_length, total)

def file.index.copies(
  header_output: Bytes.Bytes,
  header_hash: Bytes.Bytes,
  block: Bytes.Bytes,
  block_root: Bytes.Bytes,
  copies: Bytes.Bytes & Bytes.Bytes,
  +total: U32
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match copies:
    case (index_output, index_hash):
      file.index.length(header_output, header_hash, block, block_root,
        Bytes.length(index_output), index_hash, total)

# Builds the one-block index page and clones it for root authentication.
def file.index(
  header_output: Bytes.Bytes,
  header_hash: Bytes.Bytes,
  block: Bytes.Bytes,
  block_root: Bytes.Bytes,
  +total: U32,
  +payload_len: U32
) -> Result<&1, &1, Error, Bytes.Bytes>:
  file.index.copies(header_output, header_hash, block, block_root,
    clone.split(Bytes.concat([index.magic(), u32.bytes(1),
      u32.bytes(20), u32.bytes((40 + payload_len : U32))])), total)

# Separates header copies needed by output and root authentication.
def file.header.copies(
  copies: Bytes.Bytes & Bytes.Bytes,
  block: Bytes.Bytes,
  block_root: Bytes.Bytes,
  +total: U32,
  +payload_len: U32
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match copies:
    case (header_output, header_hash):
      file.index(header_output, header_hash, block, block_root, total, payload_len)

# Creates the one-block header and gives its copy to the root calculation.
def file.header(
  block: Bytes.Bytes,
  block_root: Bytes.Bytes,
  +level: U32,
  +total: U32,
  +payload_len: U32
) -> Result<&1, &1, Error, Bytes.Bytes>:
  file.header.copies(clone.split(Bytes.concat([header.magic(),
    u32.bytes(level), u32.bytes(total), u32.bytes(1)])), block,
    block_root, total, payload_len)

# Splits a block digest for the stored block and root calculation.
def file.digest.copies(
  block: Bytes.Bytes,
  copies: Bytes.Bytes & Bytes.Bytes,
  +level: U32,
  +total: U32,
  +payload_len: U32
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match copies:
    case (block_digest, block_root):
      file.header(Bytes.concat([block, block_digest]), block_root,
        level, total, payload_len)

# Adds a block checksum to the encoded block header and payload.
def file.digest(
  block_header: Bytes.Bytes,
  frame: Bytes.Bytes,
  digest: Bytes.Bytes,
  +level: U32,
  +total: U32,
  +payload_len: U32
) -> Result<&1, &1, Error, Bytes.Bytes>:
  file.digest.copies(Bytes.concat([block_header, frame]),
    clone.split(digest), level, total, payload_len)

# Unpacks both copies before hashing and constructing the block.
def file.block.parts(
  headers: Bytes.Bytes & Bytes.Bytes,
  frames: Bytes.Bytes & Bytes.Bytes,
  +level: U32,
  +total: U32,
  +payload_len: U32
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match headers:
    case (block_output, block_hash):
      match frames:
        case (frame_output, frame_hash):
          file.digest(block_output, frame_output,
            SHA.sha256_packed_bytes(Bytes.concat([block_hash, frame_hash])),
            level, total, payload_len)

# Hashes cloned block header and frame bytes before building the file.
def file.block.copies(
  headers: Bytes.Bytes & Bytes.Bytes,
  frames: Bytes.Bytes & Bytes.Bytes,
  +level: U32,
  +total: U32,
  +payload_len: U32
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match headers:
    case header_pair:
      match frames:
        case frame_pair:
          file.block.parts(header_pair, frame_pair, level, total, payload_len)

# Creates fixed block header copies and payload copies for hashing.
def file.block(
  frame: Bytes.Bytes,
  +level: U32,
  +total: U32,
  +payload_len: U32
) -> Result<&1, &1, Error, Bytes.Bytes>:
  file.block.copies(clone.split(Bytes.concat([u32.bytes(payload_len),
    u32.bytes(total)])), clone.split(frame), level, total, payload_len)

# Rejects an encoded WAL frame larger than the resident block limit.
def file.bounded(
  frame: Bytes.Bytes,
  +level: U32,
  +total: U32,
  +payload_len: U32,
  allowed: Bool
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match allowed:
    case False{}:
      Fail{TooLarge{}}
    case True{}:
      file.block(frame, level, total, payload_len)

# Unpacks frame bytes and their measured length.
def file.measured(
  pair: Bytes.Bytes & U32,
  +level: U32,
  +total: U32
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match pair:
    case (frame, +payload_len):
      file.bounded(frame, level, total, payload_len,
        U32.is_le(payload_len, StorageBytes.MAX_BLOCK_BYTES()))

# Encodes a checksummed one-block generation-four SST file.
def file(
  frame: Bytes.Bytes,
  +level: U32,
  +total: U32
) -> Result<&1, &1, Error, Bytes.Bytes>:
  file.measured(Bytes.length(frame), level, total)

# Converts a byte WAL frame result into a bounded SST file.
def encode.frame.result(
  result: Result<&1, &1, Wal.Error, Bytes.Bytes>,
  +level: U32,
  +total: U32
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match result:
    case Fail{_}:
      Fail{TooLarge{}}
    case Done{frame}:
      file(frame, level, total)

# Measures one put record without allocating its serialized bytes.
def record.size.put(+key_len: U32, value: Bytes.Bytes & U32) -> Nat:
  match value:
    case (_, +value_len):
      Nat.add(9n, Nat.add(U32.to_nat(key_len), U32.to_nat(value_len)))

# Measures a put or tombstone record from exact raw byte lengths.
def record.size(pair: Bytes.Bytes & U32, value: Maybe<&1, Bytes.Bytes>) -> Nat:
  match pair:
    case (_, +key_len):
      match value:
        case None{}:
          Nat.add(5n, U32.to_nat(key_len))
        case Some{bytes}:
          record.size.put(key_len, Bytes.length(bytes))

# Sums exact record bytes while preserving a finite structural recursion bound.
def records.size.go(
  fuel: Nat,
  entries: List<&1, ByteMemTable.Entry>,
  total: Nat
) -> Nat:
  match fuel:
    case 0n:
      total
    case 1n+rest:
      match entries:
        case Nil{}:
          total
        case Con{ByteMemTable.Entry{key, value}, tail}:
          +entry_size = record.size(Bytes.length(key), value)
          records.size.go(rest, tail, Nat.add(total, entry_size))

# Measures all encoded records before frame allocation.
def records.size(entries: List<&1, ByteMemTable.Entry>, +count: Nat) -> Nat:
  records.size.go(Nat.add(count, 1n), entries, 0n)

def page.record.required.value(record_bytes: Nat, has_current_records: Bool) -> Nat:
  match has_current_records:
    case True{}: record_bytes
    case False{}: Nat.add(40n, record_bytes)

def page.record.required(
  entry: ByteMemTable.Entry,
  has_current_records: Bool
) -> Nat:
  match entry:
    case ByteMemTable.Entry{key, value}:
      page.record.required.value(record.size(Bytes.length(key), value),
        has_current_records)

def page.finish(
  pages: List<&1, List<&1, ByteMemTable.Entry>>,
  current: List<&1, ByteMemTable.Entry>,
  completed_count: Nat
) -> PagePlan:
  match current:
    case Nil{}:
      PagePlan{List.reverse(&1, List<&1, ByteMemTable.Entry>, pages), completed_count}
    case _:
      PagePlan{List.reverse(&1, List<&1, ByteMemTable.Entry>, Con{
        List.reverse(&1, ByteMemTable.Entry, current), pages}),
        Nat.add(completed_count, 1n)}

def page.rollover(
  entry: ByteMemTable.Entry,
  current: List<&1, ByteMemTable.Entry>,
  pages: List<&1, List<&1, ByteMemTable.Entry>>,
  completed_count: Nat,
  required_bytes: Nat
) -> PageBuild:
  PageBuild{Con{entry, Nil{}}, required_bytes, 1n,
    Con{List.reverse(&1, ByteMemTable.Entry, current), pages},
    Nat.add(completed_count, 1n)}

def page.next.cloned(
  tail: List<&1, ByteMemTable.Entry>,
  current_count: Nat,
  current_bytes: Nat,
  max_bytes: Nat,
  copies: ByteMemTable.Entry & ByteMemTable.Entry
) -> List<&1, ByteMemTable.Entry> & ByteBlockBuilder.Decision:
  match copies:
    case (for_decision, for_remaining):
      (Con{for_remaining, tail}, ByteBlockBuilder.decide(current_bytes,
        page.record.required(for_decision, Nat.is_gt(current_count, 0n)),
        max_bytes))

def page.next.prepare(
  entries: List<&1, ByteMemTable.Entry>,
  current_count: Nat,
  current_bytes: Nat,
  max_bytes: Nat
) -> List<&1, ByteMemTable.Entry> & ByteBlockBuilder.Decision:
  match entries:
    case Nil{}: (Nil{}, ByteBlockBuilder.Append{current_bytes})
    case Con{entry, tail}:
      page.next.cloned(tail, current_count, current_bytes, max_bytes,
        ByteMemTable.entry.clone(entry))

def page.build.go(
  fuel: Nat,
  builder: PageBuild,
  pending: List<&1, ByteMemTable.Entry> & ByteBlockBuilder.Decision,
  +max_bytes: Nat
) -> Result<&1, &1, Error, PagePlan>:
  match fuel:
    case 0n:
      match builder:
        case PageBuild{current, _, _, completed, completed_count}:
          match pending:
            case (Nil{}, _):
              Done{page.finish(completed, current, completed_count)}
            case _: Fail{TooLarge{}}
    case 1n+rest:
      match builder:
        case PageBuild{current, current_bytes, +current_count, completed,
            completed_count}:
          match pending:
            case (Nil{}, _):
              Done{page.finish(completed, current, completed_count)}
            case (Con{entry, tail}, decision):
              match decision:
                case ByteBlockBuilder.RecordTooLarge{}: Fail{TooLarge{}}
                case ByteBlockBuilder.Append{+used_bytes}:
                  page.build.go(rest,
                    PageBuild{Con{entry, current}, used_bytes,
                      Nat.add(current_count, 1n), completed, completed_count},
                    page.next.prepare(tail, Nat.add(current_count, 1n), used_bytes,
                      max_bytes), max_bytes)
                case ByteBlockBuilder.StartNextBlock{+record_bytes}:
                  page.build.go(rest,
                    page.rollover(entry, current, completed, completed_count,
                      record_bytes),
                    page.next.prepare(tail, 1n, record_bytes, max_bytes), max_bytes)

def page.build.measured(
  measured: List<&1, ByteMemTable.Entry> & Nat,
  +max_bytes: Nat
) -> Result<&1, &1, Error, PagePlan>:
  match measured:
    case (entries, count):
      page.build.go(count, PageBuild{Nil{}, 0n, 0n, Nil{}, 0n},
        page.next.prepare(entries, 0n, 0n, max_bytes), max_bytes)

def page.build.limit(
  entries: List<&1, ByteMemTable.Entry>,
  max_bytes: Nat
) ->
  Result<&1, &1, Error, PagePlan>:
  page.build.measured(ByteMemTable.count.keep(entries), max_bytes)

# Splits strict table entries into ordered pages under the maximum block size.
def page.build(
  entries: List<&1, ByteMemTable.Entry>
) ->
  Result<&1, &1, Error, PagePlan>:
  page.build.limit(entries, U32.to_nat(StorageBytes.MAX_BLOCK_BYTES()))

def pages.count(result: Result<&1, &1, Error, PagePlan>) -> Nat:
  match result:
    case Fail{_}: 0n
    case Done{PagePlan{_, count}}: count

# Projects the byte builder's admission result to the codec preflight contract.
def block.payload.decision(decision: ByteBlockBuilder.Decision) -> Bool:
  match decision:
    case ByteBlockBuilder.Append{_}: True{}
    case _: False{}

# Checks record payload plus WAL framing through the shared byte block policy.
def block.payload.allowed(record_bytes: Nat) -> Bool:
  block.payload.decision(ByteBlockBuilder.decide(0n,
    Nat.add(40n, record_bytes), U32.to_nat(StorageBytes.MAX_BLOCK_BYTES())))

# Encodes only after the raw record sizes fit the resident block limit.
def encode.file.ready(
  entries: List<&1, ByteMemTable.Entry>,
  +total: Nat,
  +level: U32,
  valid_level: Bool,
  ordered: Bool,
  allowed: Bool
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match valid_level ordered allowed:
    case False{} _ _:
      Fail{InvalidLevel{}}
    case True{} False{} _:
      Fail{InvalidOrder{}}
    case True{} True{} False{}:
      Fail{TooLarge{}}
    case True{} True{} True{}:
      encode.frame.result(ByteWal.encode(ByteWal.Batch{mutations(entries)}),
        level, U32.from_nat(total))

# Measures one copy before passing another copy to the WAL encoder.
def encode.file.measured(
  pair: List<&1, ByteMemTable.Entry> & List<&1, ByteMemTable.Entry>,
  +total: Nat,
  +level: U32,
  ordered: Bool
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match pair:
    case (measured, encoded):
      encode.file.ready(encoded, total, level, U32.is_le(level, 255), ordered,
        block.payload.allowed(records.size(measured, total)))

# Validates distinct list copies while encoding the remaining mutation list.
def encode.file.validated(
  validation: List<&1, ByteMemTable.Entry> & List<&1, ByteMemTable.Entry>,
  encoded: List<&1, ByteMemTable.Entry>,
  +level: U32
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match validation:
    case (ordered, counted):
      encode.file.measured(entries.clone(encoded),
        List.length(&1, ByteMemTable.Entry, counted), level,
        ByteMemTable.ordered.strict(ordered))

# Splits validation from encoding so both passes retain affine ownership.
def encode.file.entries(
  entries: List<&1, ByteMemTable.Entry> & List<&1, ByteMemTable.Entry>,
  +level: U32
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match entries:
    case (validated, encoded):
      encode.file.validated(entries.clone(validated), encoded, level)

# Encodes one strictly ordered table into the legacy one-block envelope.
def encode_file.single(
  entries: List<&1, ByteMemTable.Entry>,
  +level: U32
) -> Result<&1, &1, Error, Bytes.Bytes>:
  encode.file.entries(entries.clone(entries), level)

def file.block.raw.parts(
  headers: Bytes.Bytes & Bytes.Bytes,
  frames: Bytes.Bytes & Bytes.Bytes
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match headers:
    case (header_output, header_hash):
      match frames:
        case (frame_output, frame_hash):
          Done{Bytes.concat([header_output, frame_output,
            SHA.sha256_packed_bytes(Bytes.concat([header_hash, frame_hash]))])}

def file.block.raw(
  frame: Bytes.Bytes,
  count: U32,
  payload_len: U32
) -> Result<&1, &1, Error, Bytes.Bytes>:
  file.block.raw.parts(clone.split(Bytes.concat([u32.bytes(payload_len),
    u32.bytes(count)])), clone.split(frame))

def encode.page.frame.block(
  count: U32,
  lengths: Bytes.Bytes & U32
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match lengths:
    case (frame, +frame_length):
      file.block.raw(frame, count, frame_length)

def encode.page.frame.result(
  frame: Result<&1, &1, Wal.Error, Bytes.Bytes>,
  count: U32
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match frame:
    case Fail{_}: Fail{TooLarge{}}
    case Done{bytes}:
      encode.page.frame.block(count, Bytes.length(bytes))

def encode.page.block.measured(
  measured: Bytes.Bytes & U32,
  checksum: Bytes.Bytes,
  count: U32,
  separator: Bytes.Bytes,
  separator_length: U32
) -> Result<&1, &1, Error, EncodedBlock>:
  match measured:
    case (bytes, +byte_length):
      Done{EncodedBlock{bytes, byte_length, checksum, count, separator,
        separator_length}}

def encode.page.block.output(
  copies: Bytes.Bytes & Bytes.Bytes,
  byte_length: U32,
  count: U32,
  separator: Bytes.Bytes,
  separator_length: U32
) -> Result<&1, &1, Error, EncodedBlock>:
  match copies:
    case (output, checksum):
      encode.page.block.measured((output, byte_length), checksum, count,
        separator, separator_length)

def encode.page.block.digest(
  measured: Bytes.Bytes & U32,
  count: U32,
  separator: Bytes.Bytes,
  separator_length: U32
) -> Result<&1, &1, Error, EncodedBlock>:
  match measured:
    case (bytes, +byte_length):
      encode.page.block.output(Bytes.slice(bytes, (byte_length - 32 : U32), 32),
        byte_length, count, separator, separator_length)

def encode.page.block(
  result: Result<&1, &1, Error, Bytes.Bytes>,
  count: U32,
  separator: Bytes.Bytes,
  separator_length: U32
) -> Result<&1, &1, Error, EncodedBlock>:
  match result:
    case Fail{error}: Fail{error}
    case Done{bytes}:
      encode.page.block.digest(Bytes.length(bytes), count, separator,
        separator_length)

def encode.page.frame.counted(
  encoded: List<&1, ByteMemTable.Entry>,
  +count: Nat,
  separator: Bytes.Bytes,
  separator_length: U32
) -> Result<&1, &1, Error, EncodedBlock>:
  encode.page.block(encode.page.frame.result(
    ByteWal.encode(ByteWal.Batch{mutations(encoded)}),
    U32.from_nat(count)), U32.from_nat(count), separator, separator_length)

def encode.page.frame.key.measured(
  separator: Bytes.Bytes,
  encoded: List<&1, ByteMemTable.Entry>,
  +count: Nat,
  measured: Bytes.Bytes & U32
) -> Result<&1, &1, Error, EncodedBlock>:
  match measured:
    case (_, separator_length):
      encode.page.frame.counted(encoded, count, separator, separator_length)

def encode.page.frame.key.copied(
  copied_key: Bytes.Bytes & Bytes.Bytes,
  encoded: List<&1, ByteMemTable.Entry>,
  +count: Nat
) -> Result<&1, &1, Error, EncodedBlock>:
  match copied_key:
    case (separator, measurement):
      encode.page.frame.key.measured(separator, encoded, count,
        Bytes.length(measurement))

def encode.page.frame(
  counted: List<&1, ByteMemTable.Entry> & List<&1, ByteMemTable.Entry>
) -> Result<&1, &1, Error, EncodedBlock>:
  match counted:
    case (sized, encoded):
      match sized:
        case Con{ByteMemTable.Entry{key, _}, tail}:
          encode.page.frame.key.copied(ByteMemTable.bytes.clone(key), encoded,
            Nat.add(List.length(&1, ByteMemTable.Entry, tail), 1n))
        case Nil{}: Fail{Malformed{}}

def encode.page(page: List<&1, ByteMemTable.Entry>) -> Result<&1, &1, Error, EncodedBlock>:
  encode.page.frame(ByteMemTable.entries.clone(page))

def encode.pages.prepare.cloned(
  tail: List<&1, List<&1, ByteMemTable.Entry>>,
  copies: List<&1, ByteMemTable.Entry> & List<&1, ByteMemTable.Entry>
) -> List<&1, List<&1, ByteMemTable.Entry>> &
  Result<&1, &1, Error, EncodedBlock>:
  match copies:
    case (to_encode, to_retain):
      (Con{to_retain, tail}, encode.page(to_encode))

def encode.pages.prepare(
  pages: List<&1, List<&1, ByteMemTable.Entry>>
) -> List<&1, List<&1, ByteMemTable.Entry>> &
  Result<&1, &1, Error, EncodedBlock>:
  match pages:
    case Nil{}: (Nil{}, Done{EncodedBlock{Bytes.new(0), 0, Bytes.new(0), 0,
      Bytes.new(0), 0}})
    case Con{page, tail}:
      encode.pages.prepare.cloned(tail, ByteMemTable.entries.clone(page))

def encode.blocks.go(
  fuel: Nat,
  pending: List<&1, List<&1, ByteMemTable.Entry>> & Result<&1, &1, Error, EncodedBlock>,
  reversed: List<&1, EncodedBlock>
) -> Result<&1, &1, Error, List<&1, EncodedBlock>>:
  match fuel:
    case 0n:
      match pending:
        case (Nil{}, _): Done{List.reverse(&1, EncodedBlock, reversed)}
        case _: Fail{Malformed{}}
    case 1n+rest:
      match pending:
        case (Nil{}, _): Done{List.reverse(&1, EncodedBlock, reversed)}
        case (Con{_, _}, Fail{error}): Fail{error}
        case (Con{_, tail}, Done{block}):
          encode.blocks.go(rest, encode.pages.prepare(tail),
            Con{block, reversed})

def encode.blocks.result(
  count: U32,
  result: Result<&1, &1, Error, List<&1, EncodedBlock>>
) -> Result<&1, &1, Error, EncodedPages>:
  match result:
    case Fail{error}: Fail{error}
    case Done{blocks}: Done{EncodedPages{blocks, count}}

def encode.blocks(plan: PagePlan) -> Result<&1, &1, Error, EncodedPages>:
  match plan:
    case PagePlan{pages, +count}:
      encode.blocks.result(U32.from_nat(count),
        encode.blocks.go(count, encode.pages.prepare(pages), Nil{}))

def blocks.collect.go(
  fuel: Nat,
  fits: Bool,
  remaining: List<&1, EncodedBlock>,
  parts: List<&1, Bytes.Bytes>,
  checksums: List<&1, Bytes.Bytes>,
  index_entries: List<&1, Bytes.Bytes>,
  separators: List<&1, Bytes.Bytes>,
  +offset: Nat,
  +separator_offset: Nat,
  block_count: U32,
  entry_count: U32
) -> Result<&1, &1, Error, BlocksCollected>:
  match fuel:
    case 0n:
      match fits:
        case False{}: Fail{TooLarge{}}
        case True{}:
          match remaining:
            case Nil{}:
              +count = U32.to_nat(block_count)
              Done{BlocksCollected{
                Bytes.concat(List.reverse(&1, Bytes.Bytes, parts)),
                Bytes.concat(List.reverse(&1, Bytes.Bytes, checksums)),
                Bytes.concat([index.magic(), u32.bytes(U32.from_nat(count)),
                  Bytes.concat([Bytes.concat(List.reverse(&1, Bytes.Bytes,
                    index_entries)), Bytes.concat(List.reverse(&1, Bytes.Bytes,
                    separators))])]),
                U32.from_nat(count), entry_count}}
            case _: Fail{Malformed{}}
    case 1n+rest:
      match fits:
        case False{}: Fail{TooLarge{}}
        case True{}:
          match remaining:
            case Nil{}:
              +count = U32.to_nat(block_count)
              Done{BlocksCollected{
                Bytes.concat(List.reverse(&1, Bytes.Bytes, parts)),
                Bytes.concat(List.reverse(&1, Bytes.Bytes, checksums)),
                Bytes.concat([index.magic(), u32.bytes(U32.from_nat(count)),
                  Bytes.concat([Bytes.concat(List.reverse(&1, Bytes.Bytes,
                    index_entries)), Bytes.concat(List.reverse(&1, Bytes.Bytes,
                    separators))])]),
                U32.from_nat(count), entry_count}}
            case Con{EncodedBlock{bytes, +byte_length, checksum, count,
                separator, +separator_length}, tail}:
              +length_nat = U32.to_nat(byte_length)
              +separator_length_nat = U32.to_nat(separator_length)
              blocks.collect.go(rest,
                fits && Nat.is_le(Nat.add(offset, length_nat), 4294967295n) &&
                  Nat.is_le(Nat.add(separator_offset, separator_length_nat),
                    4294967295n), tail, Con{bytes, parts},
                Con{checksum, checksums},
                Con{Bytes.concat([u32.bytes(U32.from_nat(offset)),
                  u32.bytes(byte_length),
                  u32.bytes(U32.from_nat(separator_offset)),
                  u32.bytes(separator_length)]), index_entries},
                Con{separator, separators}, Nat.add(offset, length_nat),
                Nat.add(separator_offset, separator_length_nat),
                (block_count + 1 : U32), (entry_count + count : U32))

def blocks.collect(
  encoded: EncodedPages
) -> Result<&1, &1, Error, BlocksCollected>:
  match encoded:
    case EncodedPages{blocks, count}:
      blocks.collect.go(U32.to_nat(count), True{}, blocks, Nil{}, Nil{}, Nil{},
        Nil{}, 20n, 0n, 0, 0)

def file.multi.output.measured(
  header_output: Bytes.Bytes,
  blocks: Bytes.Bytes,
  checksums: Bytes.Bytes,
  measured_index: Bytes.Bytes & U32,
  index_hash: Bytes.Bytes,
  header_hash: Bytes.Bytes,
  +total: U32
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match measured_index:
    case (index_output, index_length):
      Done{Bytes.concat([header_output, blocks, index_output,
        footer.magic(), u32.bytes(total), u32.bytes(index_length),
        SHA.sha256_packed_bytes(Bytes.concat([header_hash, checksums,
          index_hash]))])}

def file.multi.output(
  header_parts: Bytes.Bytes & Bytes.Bytes,
  blocks: Bytes.Bytes,
  checksums: Bytes.Bytes,
  index_parts: Bytes.Bytes & Bytes.Bytes,
  +total: U32
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match header_parts:
    case (header_output, header_hash):
      match index_parts:
        case (index_output, index_hash):
          file.multi.output.measured(header_output, blocks, checksums,
            Bytes.length(index_output), index_hash, header_hash, total)

def file.multi.finish(
  level: U32,
  collected: BlocksCollected
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match collected:
    case BlocksCollected{blocks, checksums, index_bytes, block_count, entry_count}:
      +total = U32.to_nat(entry_count)
      file.multi.output(clone.split(Bytes.concat([header.magic(),
        u32.bytes(level), u32.bytes(U32.from_nat(total)),
        u32.bytes(block_count)])), blocks, checksums,
        clone.split(index_bytes), U32.from_nat(total))

def encode.multi.collected(
  result: Result<&1, &1, Error, BlocksCollected>,
  level: U32
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match result:
    case Fail{error}: Fail{error}
    case Done{collected}: file.multi.finish(level, collected)

def encode.multi.pages(
  result: Result<&1, &1, Error, EncodedPages>,
  level: U32
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match result:
    case Fail{error}: Fail{error}
    case Done{pages}:
      encode.multi.collected(blocks.collect(pages), level)

def encode.multi.plan(
  result: Result<&1, &1, Error, PagePlan>,
  level: U32
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match result:
    case Fail{error}: Fail{error}
    case Done{plan}:
      encode.multi.pages(encode.blocks(plan), level)

def encode.multi.level(
  entries: List<&1, ByteMemTable.Entry>,
  level: U32,
  valid: Bool,
  max_bytes: Nat
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match valid:
    case False{}: Fail{InvalidLevel{}}
    case True{}:
      encode.multi.plan(page.build.limit(entries, max_bytes), level)

def encode.multi.order(
  entries: List<&1, ByteMemTable.Entry>,
  level: U32,
  ordered: Bool,
  max_bytes: Nat
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match ordered:
    case False{}: Fail{InvalidOrder{}}
    case True{}:
      +level_nat = U32.to_nat(level)
      encode.multi.level(entries, U32.from_nat(level_nat),
        Nat.is_le(level_nat, 255n), max_bytes)

def encode.multi.validated(
  copies: List<&1, ByteMemTable.Entry> & List<&1, ByteMemTable.Entry>,
  level: U32,
  max_bytes: Nat
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match copies:
    case (to_validate, to_encode):
      encode.multi.order(to_encode, level,
        ByteMemTable.ordered.strict(to_validate), max_bytes)

def encode_file.limit(
  entries: List<&1, ByteMemTable.Entry>,
  level: U32,
  max_bytes: Nat
) -> Result<&1, &1, Error, Bytes.Bytes>:
  encode.multi.validated(ByteMemTable.entries.clone(entries), level, max_bytes)

# Encodes the validated byte table in the canonical single-block format.
def encode_file(
  entries: List<&1, ByteMemTable.Entry>,
  level: U32
) -> Result<&1, &1, Error, Bytes.Bytes>:
  encode_file.limit(entries, level, U32.to_nat(StorageBytes.MAX_BLOCK_BYTES()))

# Applies each decoded byte mutation while rejecting count mismatches.
def decode.apply(
  fuel: Nat,
  table: ByteMemTable.Table,
  mutations: List<&1, ByteWal.Mutation>
) -> Result<&1, &1, Error, ByteMemTable.Table>:
  match fuel:
    case 0n:
      match mutations:
        case Nil{}:
          Done{table}
        case Con{_, _}:
          Fail{Malformed{}}
    case 1n+rest:
      match mutations:
        case Nil{}:
          Fail{Malformed{}}
        case Con{mutation, tail}:
          match mutation:
            case ByteWal.Put{key, value}:
              decode.apply(rest, ByteMemTable.put(table, key, value), tail)
            case ByteWal.Delete{key}:
              decode.apply(rest, ByteMemTable.del(table, key), tail)

# Decodes the inner checksummed frame and applies exactly its declared count.
def decode.frame(
  total: U32,
  result: Result<&1, &1, Wal.Error, ByteWal.Batch>
) -> Result<&1, &1, Error, ByteMemTable.Table>:
  match result:
    case Fail{Wal.ChecksumMismatch{}}:
      Fail{ChecksumMismatch{}}
    case Fail{_}:
      Fail{Malformed{}}
    case Done{ByteWal.Batch{mutations}}:
      decode.apply(U32.to_nat(total), ByteMemTable.empty(), mutations)

# Converts a root comparison over raw header, checksum, and index bytes into a result.
def parse.header.entries.valid(
  cursor: Bytes.Cursor,
  +size: U32,
  +level: U32,
  +total: U32,
  +payload_len: U32,
  +entries: U32,
  valid: Bool
) -> Result<&1, &1, Error, PayloadWords>:
  match valid:
    case True{}:
      Done{PayloadWords{cursor, size, level, total, payload_len, entries}}
    case False{}:
      Fail{Malformed{}}
def parse.header.entries(
  pair: Bytes.Cursor & Maybe<&2, U32>,
  +size: U32,
  +level: U32,
  +total: U32,
  +payload_len: U32
) -> Result<&1, &1, Error, PayloadWords>:
  match pair:
    case (cursor, Some{+entries}):
      parse.header.entries.valid(cursor, size, level, total, payload_len,
        entries, U32.is_eq(entries, total) &&
          U32.is_le(payload_len, StorageBytes.MAX_BLOCK_BYTES()) &&
          U32.is_eq(size, (116 + payload_len : U32)))
    case _:
      Fail{Malformed{}}
def parse.header.payload(
  pair: Bytes.Cursor & Maybe<&2, U32>,
  size: U32,
  level: U32,
  total: U32
) -> Result<&1, &1, Error, PayloadWords>:
  match pair:
    case (cursor, Some{payload_len}):
      parse.header.entries(Bytes.Cursor.u32be(cursor), size, level, total,
        payload_len)
    case _:
      Fail{Malformed{}}
def parse.header.blocks(
  pair: Bytes.Cursor & Maybe<&2, U32>,
  size: U32,
  level: U32,
  total: U32
) -> Result<&1, &1, Error, PayloadWords>:
  match pair:
    case (cursor, Some{1}):
      parse.header.payload(Bytes.Cursor.u32be(cursor), size, level, total)
    case _:
      Fail{Malformed{}}
def parse.header.total(
  pair: Bytes.Cursor & Maybe<&2, U32>,
  size: U32,
  level: U32
) -> Result<&1, &1, Error, PayloadWords>:
  match pair:
    case (cursor, Some{total}):
      parse.header.blocks(Bytes.Cursor.u32be(cursor), size, level, total)
    case _:
      Fail{Malformed{}}
def parse.header.level.valid(
  pair: Bytes.Cursor & Maybe<&2, U32>,
  size: U32,
  level: U32,
  valid: Bool
) -> Result<&1, &1, Error, PayloadWords>:
  match valid:
    case False{}:
      Fail{InvalidLevel{}}
    case True{}:
      parse.header.total(pair, size, level)
def parse.header.level(
  pair: Bytes.Cursor & Maybe<&2, U32>,
  size: U32
) -> Result<&1, &1, Error, PayloadWords>:
  match pair:
    case (cursor, Some{+level}):
      parse.header.level.valid(Bytes.Cursor.u32be(cursor), size, level,
        U32.is_le(level, 255))
    case _:
      Fail{Malformed{}}
def parse.header.magic.second(
  pair: Bytes.Cursor & Maybe<&2, U32>,
  size: U32
) -> Result<&1, &1, Error, PayloadWords>:
  match pair:
    case (cursor, Some{1295274752}):
      parse.header.level(Bytes.Cursor.u32be(cursor), size)
    case _:
      Fail{Malformed{}}
def parse.header.words(
  pair: Bytes.Cursor & Maybe<&2, U32>,
  size: U32
) -> Result<&1, &1, Error, PayloadWords>:
  match pair:
    case (cursor, Some{1297697875}):
      parse.header.magic.second(Bytes.Cursor.u32be(cursor), size)
    case _:
      Fail{Malformed{}}
def parse.header.length(pair: Bytes.Bytes & U32) -> Result<&1, &1, Error, PayloadWords>:
  match pair:
    case (source, size):
      parse.header.words(Bytes.Cursor.u32be(Bytes.Cursor.new(source)), size)
def parse.header(file: Bytes.Bytes) -> Result<&1, &1, Error, PayloadWords>:
  parse.header.length(Bytes.length(file))

def parse.canonical.comparison(
  entries: List<&1, ByteMemTable.Entry>,
  comparison: Bytes.Bytes & Bytes.Bytes & Bool
) -> Result<&1, &1, Error, ByteMemTable.Table>:
  match comparison:
    case (_, _, True{}):
      Done{ByteMemTable.Table{entries}}
    case (_, _, False{}):
      Fail{ChecksumMismatch{}}

def parse.canonical.encoded(
  source: Bytes.Bytes,
  entries: List<&1, ByteMemTable.Entry>,
  result: Result<&1, &1, Error, Bytes.Bytes>
) -> Result<&1, &1, Error, ByteMemTable.Table>:
  match result:
    case Fail{error}:
      Fail{error}
    case Done{expected}:
      parse.canonical.comparison(entries, Bytes.eq(source, expected))

def parse.canonical.encode(
  source: Bytes.Bytes,
  pair: List<&1, ByteMemTable.Entry> & List<&1, ByteMemTable.Entry>,
  +level: U32
) -> Result<&1, &1, Error, ByteMemTable.Table>:
  match pair:
    case (entries, encoded):
      parse.canonical.encoded(source, entries, encode_file(encoded, level))

def parse.canonical.table(
  source: Bytes.Bytes,
  table: ByteMemTable.Table,
  +level: U32
) -> Result<&1, &1, Error, ByteMemTable.Table>:
  match table:
    case ByteMemTable.Table{entries}:
      parse.canonical.encode(source, entries.clone(List.reverse(&1,
        ByteMemTable.Entry, entries)), level)
def parse.block.frame.decoded(
  result: Result<&1, &1, Error, ByteMemTable.Table>,
  source: Bytes.Bytes,
  +level: U32
) -> Result<&1, &1, Error, ByteMemTable.Table>:
  match result:
    case Fail{error}:
      Fail{error}
    case Done{table}:
      parse.canonical.table(source, table, level)
def parse.block.frame(
  pair: Bytes.Bytes & Bytes.Bytes,
  total: U32,
  +level: U32
) -> Result<&1, &1, Error, ByteMemTable.Table>:
  match pair:
    case (source, frame):
      parse.block.frame.decoded(decode.frame(total, ByteWal.decode(frame)),
        source, level)

def parse.block.payload(
  cursor: Bytes.Cursor,
  level: U32,
  total: U32,
  payload_len: U32
) -> Result<&1, &1, Error, ByteMemTable.Table>:
  match cursor:
    case Bytes.Cursor{bytes, +pos, _, _}:
      parse.block.frame(Bytes.slice(bytes, pos, payload_len), total, level)

def parse.file.header(
  result: Result<&1, &1, Error, PayloadWords>
) -> Result<&1, &1, Error, ByteMemTable.Table>:
  match result:
    case Fail{error}:
      Fail{error}
    case Done{PayloadWords{cursor, _, level, total, payload_len, _}}:
      parse.block.payload(cursor, level, total, payload_len)
def parse.file(file: Bytes.Bytes) -> Result<&1, &1, Error, ByteMemTable.Table>:
  parse.file.header(parse.header(file))

def parse.block.envelope.comparison(
  table: ByteMemTable.Table,
  comparison: Bytes.Bytes & Bytes.Bytes & Bool
) -> Result<&1, &1, Error, ByteMemTable.Table>:
  match comparison:
    case (_, _, True{}): Done{table}
    case (_, _, False{}): Fail{ChecksumMismatch{}}

def parse.block.envelope.copies(
  table: Result<&1, &1, Error, ByteMemTable.Table>,
  block: Bytes.Bytes,
  encoded: Result<&1, &1, Error, Bytes.Bytes>
) -> Result<&1, &1, Error, ByteMemTable.Table>:
  match table:
    case Fail{error}: Fail{error}
    case Done{table}:
      match encoded:
        case Fail{error}: Fail{error}
        case Done{expected}:
          parse.block.envelope.comparison(table, Bytes.eq(block, expected))

def parse.block.envelope(
  table: Result<&1, &1, Error, ByteMemTable.Table>,
  block: Bytes.Bytes,
  frame: Bytes.Bytes,
  count: U32,
  payload_length: U32
) -> Result<&1, &1, Error, ByteMemTable.Table>:
  parse.block.envelope.copies(table, block,
    file.block.raw(frame, count, payload_length))

def parse.block.frame.encoded(
  source: Bytes.Bytes,
  block: Bytes.Bytes,
  frame: Bytes.Bytes,
  count: U32,
  payload_length: U32,
  entries: List<&1, ByteMemTable.Entry>,
  encoded: Result<&1, &1, Error, Bytes.Bytes>
) -> Result<&1, &1, Error, ByteMemTable.Table>:
  parse.block.envelope(parse.canonical.encoded(source, entries, encoded),
    block, frame, count, payload_length)

def parse.block.frame.wal(
  source: Bytes.Bytes,
  block: Bytes.Bytes,
  frame: Bytes.Bytes,
  count: U32,
  payload_length: U32,
  entries: List<&1, ByteMemTable.Entry>,
  encoded: Result<&1, &1, Wal.Error, Bytes.Bytes>
) -> Result<&1, &1, Error, ByteMemTable.Table>:
  match encoded:
    case Fail{_}: Fail{Malformed{}}
    case Done{bytes}:
      parse.block.frame.encoded(source, block, frame, count, payload_length,
        entries, Done{bytes})

def parse.block.frame.order(
  ordered: Bool,
  frames: Bytes.Bytes & Bytes.Bytes,
  block: Bytes.Bytes,
  count: U32,
  payload_length: U32,
  copies: List<&1, ByteMemTable.Entry> & List<&1, ByteMemTable.Entry>
) -> Result<&1, &1, Error, ByteMemTable.Table>:
  match ordered:
    case False{}: Fail{InvalidOrder{}}
    case True{}:
      match frames:
        case (frame_source, frame_block):
          match copies:
            case (for_validation, for_encoding):
              parse.block.frame.wal(frame_source, block, frame_block,
                count, payload_length, for_validation,
                ByteWal.encode(ByteWal.Batch{mutations(for_encoding)}))

def parse.block.frame.copies(
  ordered: Bool,
  frames: Bytes.Bytes & Bytes.Bytes,
  block: Bytes.Bytes,
  count: U32,
  payload_length: U32,
  copies: List<&1, ByteMemTable.Entry> & List<&1, ByteMemTable.Entry>
) -> Result<&1, &1, Error, ByteMemTable.Table>:
  parse.block.frame.order(ordered, frames, block, count, payload_length, copies)

def parse.block.table.ordered(
  copies: List<&1, ByteMemTable.Entry> & List<&1, ByteMemTable.Entry>,
  block: Bytes.Bytes,
  frames: Bytes.Bytes & Bytes.Bytes,
  count: U32,
  payload_length: U32
) -> Result<&1, &1, Error, ByteMemTable.Table>:
  match copies:
    case (for_order, for_encoding):
      parse.block.frame.copies(ByteMemTable.ordered.strict(for_order), frames,
        block, count, payload_length,
        ByteMemTable.entries.clone(for_encoding))

def parse.block.table(
  result: Result<&1, &1, Error, ByteMemTable.Table>,
  block: Bytes.Bytes,
  frames: Bytes.Bytes & Bytes.Bytes,
  count: U32,
  payload_length: U32
) -> Result<&1, &1, Error, ByteMemTable.Table>:
  match result:
    case Fail{error}: Fail{error}
    case Done{ByteMemTable.Table{entries}}:
      parse.block.table.ordered(
        ByteMemTable.entries.clone(List.reverse(&1, ByteMemTable.Entry, entries)),
        block, frames, count, payload_length)

def parse.block.decoded(
  result: Result<&1, &1, Wal.Error, ByteWal.Batch>,
  block: Bytes.Bytes,
  frames: Bytes.Bytes & Bytes.Bytes,
  counts: Nat & Nat,
  payload_length: U32
) -> Result<&1, &1, Error, ByteMemTable.Table>:
  match result:
    case Fail{Wal.ChecksumMismatch{}}: Fail{ChecksumMismatch{}}
    case Fail{_}: Fail{Malformed{}}
    case Done{ByteWal.Batch{mutations}}:
      match counts:
        case (decode_count, stored_count):
          parse.block.table(decode.apply(decode_count,
            ByteMemTable.empty(), mutations), block, frames,
            U32.from_nat(stored_count), payload_length)

def parse.block.frames.decode(
  frames: Bytes.Bytes & Bytes.Bytes,
  block: Bytes.Bytes,
  count: U32,
  payload_length: U32
) -> Result<&1, &1, Error, ByteMemTable.Table>:
  match frames:
    case (for_decode, for_compare):
      parse.block.decoded(ByteWal.decode(for_decode), block,
        clone.split(for_compare),
        QueuePolicy.nat.clone.pair(U32.to_nat(count)), payload_length)


def parse.block.frames(
  pair: Bytes.Bytes & Bytes.Bytes,
  count: U32,
  payload_length: U32
) -> Result<&1, &1, Error, ByteMemTable.Table>:
  match pair:
    case (block, frame):
      parse.block.frames.decode(clone.split(frame), block, count,
        payload_length)
def parse.block.count.copy(
  block: Bytes.Bytes,
  count: U32,
  pair: Nat & Nat
) -> Result<&1, &1, Error, ByteMemTable.Table>:
  match pair:
    case (slice_length, check_length):
      parse.block.frames(Bytes.slice(block, 8, U32.from_nat(slice_length)),
        count, U32.from_nat(check_length))

def parse.block.count(
  pair: Bytes.Bytes & Maybe<&2, U32>,
  payload_length: U32
) -> Result<&1, &1, Error, ByteMemTable.Table>:
  match pair:
    case (block, Some{count}):
      parse.block.count.copy(block, count,
        QueuePolicy.nat.clone.pair(U32.to_nat(payload_length)))
    case (_, None{}):
      Fail{Malformed{}}

def parse.block.length.valid(
  block: Bytes.Bytes,
  payload_length: U32,
  valid: Bool
) -> Result<&1, &1, Error, ByteMemTable.Table>:
  match valid:
    case False{}: Fail{Malformed{}}
    case True{}:
      parse.block.count(Bytes.get.u32be(block, 4), payload_length)

def parse.block.length.check(
  block: Bytes.Bytes,
  size: U32,
  copies: Nat & Nat
) -> Result<&1, &1, Error, ByteMemTable.Table>:
  match copies:
    case (count_length, validation_length):
      parse.block.length.valid(block, U32.from_nat(count_length),
        U32.is_eq(size, (40 + U32.from_nat(validation_length) : U32)))


def parse.block.length(
  measured: Bytes.Bytes & U32,
  payload: Bytes.Bytes & Maybe<&2, U32>
) -> Result<&1, &1, Error, ByteMemTable.Table>:
  match measured:
    case (block, +size):
      match payload:
        case (_, Some{payload_length}):
          parse.block.length.check(block, size,
            QueuePolicy.nat.clone.pair(U32.to_nat(payload_length)))
        case _:
          Fail{Malformed{}}
def parse_block.payload.copies(
  copies: Bytes.Bytes & Bytes.Bytes,
  payload_length: U32
) -> Result<&1, &1, Error, ByteMemTable.Table>:
  match copies:
    case (measured, block):
      parse.block.length(Bytes.length(measured), (block, Some{payload_length}))

def parse_block.payload(
  pair: Bytes.Bytes & Maybe<&2, U32>
) -> Result<&1, &1, Error, ByteMemTable.Table>:
  match pair:
    case (block, Some{payload_length}):
      parse_block.payload.copies(clone.split(block), payload_length)
    case _:
      Fail{Malformed{}}

# Validates one complete generation-four page without requiring its file index.
def parse_block(block: Bytes.Bytes) -> Result<&1, &1, Error, ByteMemTable.Table>:
  parse_block.payload(Bytes.get.u32be(block, 0))

def parse.multi.header.blocks(
  pair: Bytes.Bytes & Maybe<&2, U32>,
  level: Nat,
  total: Nat
) -> Result<&1, &1, Error, MultiHeader>:
  match pair:
    case (file, Some{block_count}):
      Done{MultiHeader{file, U32.from_nat(level), U32.from_nat(total),
        block_count}}
    case _:
      Fail{Malformed{}}

def parse.multi.header.total(
  pair: Bytes.Bytes & Maybe<&2, U32>,
  level: Nat
) -> Result<&1, &1, Error, MultiHeader>:
  match pair:
    case (file, Some{total}):
      parse.multi.header.blocks(Bytes.get.u32be(file, 16), level,
        U32.to_nat(total))
    case _:
      Fail{Malformed{}}

def parse.multi.header.level(
  pair: Bytes.Bytes & Maybe<&2, U32>
) -> Result<&1, &1, Error, MultiHeader>:
  match pair:
    case (file, Some{level}):
      parse.multi.header.total(Bytes.get.u32be(file, 12), U32.to_nat(level))
    case _:
      Fail{Malformed{}}

def parse.multi.header(
  file: Bytes.Bytes
) -> Result<&1, &1, Error, MultiHeader>:
  parse.multi.header.level(Bytes.get.u32be(file, 8))

def parse.stream.header.rules(
  header: MultiHeader,
  valid_magic: Bool,
  valid_fields: Bool
) -> Result<&1, &1, Error, MultiHeader>:
  match valid_magic:
    case False{}: Fail{Malformed{}}
    case True{}:
      match valid_fields:
        case False{}: Fail{Malformed{}}
        case True{}: Done{header}

def parse.stream.header.fields(
  header: MultiHeader,
  valid_magic: Bool
) -> Result<&1, &1, Error, MultiHeader>:
  match header:
    case MultiHeader{_, +level, _, +block_count}:
      parse.stream.header.rules(header, valid_magic,
        U32.is_le(level, 255) && U32.is_lt(0, block_count))


def parse.stream.header.valid(
  result: Result<&1, &1, Error, MultiHeader>,
  valid: Bool
) -> Result<&1, &1, Error, MultiHeader>:
  match result:
    case Fail{error}: Fail{error}
    case Done{header}:
      parse.stream.header.fields(header, valid)


def parse.stream.header.magic(
  source: Bytes.Bytes,
  comparison: Bytes.Bytes & Bytes.Bytes & Bool
) -> Result<&1, &1, Error, MultiHeader>:
  match comparison:
    case (_, _, valid):
      parse.stream.header.valid(parse.multi.header(source), valid)

def parse.stream.header.slice(
  source: Bytes.Bytes,
  signature: Bytes.Bytes & Bytes.Bytes
) -> Result<&1, &1, Error, MultiHeader>:
  match signature:
    case (_, candidate):
      parse.stream.header.magic(source, Bytes.eq(header.magic(), candidate))

def parse.stream.header.copies(
  copies: Bytes.Bytes & Bytes.Bytes
) -> Result<&1, &1, Error, MultiHeader>:
  match copies:
    case (source, input):
      parse.stream.header.slice(source, Bytes.slice(input, 0, 8))

# Validates the fixed generation-four header before opening a block stream.
def parse_stream_header(source: Bytes.Bytes) -> Result<&1, &1, Error, MultiHeader>:
  parse.stream.header.copies(clone.split(source))

def parse_stream_header.accepted(
  result: Result<&1, &1, Error, MultiHeader>
) -> Bool:
  match result:
    case Done{_}: True{}
    case Fail{_}: False{}

def parse.stream.finish.footer.compare(
  comparison: Bytes.Bytes & Bytes.Bytes & Bool
) -> Result<&1, &1, Error, Unit>:
  match comparison:
    case (_, _, True{}): Done{Unit{}}
    case (_, _, False{}): Fail{ChecksumMismatch{}}

def parse.stream.finish.footer(
  index_valid: Bool,
  header_hash: Bytes.Bytes,
  checksums: Bytes.Bytes,
  index_hash: Bytes.Bytes,
  footer: Bytes.Bytes,
  +total: U32
) -> Result<&1, &1, Error, Unit>:
  match index_valid:
    case False{}: Fail{Malformed{}}
    case True{}:
      parse.stream.finish.footer.compare(Bytes.eq(footer,
        Bytes.concat([footer.magic(), u32.bytes(total),
          SHA.sha256_packed_bytes(Bytes.concat([header_hash, checksums,
            index_hash]))])))

def parse.stream.finish.index.root(
  header: Bytes.Bytes,
  checksums: Bytes.Bytes,
  footer: Bytes.Bytes,
  +total: U32,
  index_hash: Bytes.Bytes,
  comparison: Bytes.Bytes & Bytes.Bytes & Bool
) -> Result<&1, &1, Error, Unit>:
  match comparison:
    case (_, _, valid):
      parse.stream.finish.footer(valid, header, checksums, index_hash, footer,
        total)

def parse.stream.finish.index.copies(
  header: Bytes.Bytes,
  checksums: Bytes.Bytes,
  entries: Bytes.Bytes,
  index_copies: Bytes.Bytes & Bytes.Bytes,
  footer: Bytes.Bytes,
  +total: U32,
  +block_count: U32
) -> Result<&1, &1, Error, Unit>:
  match index_copies:
    case (for_compare, for_hash):
      parse.stream.finish.index.root(header, checksums, footer, total,
        for_hash, Bytes.eq(for_compare,
          Bytes.concat([index.magic(), u32.bytes(block_count), entries])))

def parse.stream.finish.index(
  header: Bytes.Bytes,
  checksums: Bytes.Bytes,
  entries: Bytes.Bytes,
  index: Bytes.Bytes,
  footer: Bytes.Bytes,
  +total: U32,
  +block_count: U32
) -> Result<&1, &1, Error, Unit>:
  parse.stream.finish.index.copies(header, checksums, entries,
    clone.split(index), footer, total, block_count)
# Verifies serialized index bytes and the generation-four root footer.
def parse_stream_finish(
  header: Bytes.Bytes,
  checksums: Bytes.Bytes,
  entries: Bytes.Bytes,
  index: Bytes.Bytes,
  footer: Bytes.Bytes,
  total: U32,
  block_count: U32
) -> Result<&1, &1, Error, Unit>:
  parse.stream.finish.index(header, checksums, entries, index, footer,
    total, block_count)

def parse_stream_finish.accepted(
  result: Result<&1, &1, Error, Unit>
) -> Bool:
  match result:
    case Done{Unit{}}: True{}
    case Fail{_}: False{}

def parse.multi.table.updated(
  result: Result<&1, &1, Error, ByteMemTable.Table>,
  file: Bytes.Bytes,
  index_offset: Nat,
  next_block: Nat,
  block_count: Nat,
  level: U32,
  total: Nat,
  decoded: Nat,
  record_count: Nat
) -> Result<&1, &1, Error, MultiRead>:
  match result:
    case Fail{error}: Fail{error}
    case Done{table}:
      Done{MultiRead{file, index_offset, Nat.add(next_block, 1n),
        block_count, level, total, Nat.add(decoded, record_count), table}}

def parse.multi.block.apply(
  record_counts: Nat & Nat,
  table: ByteMemTable.Table,
  mutations: List<&1, ByteWal.Mutation>,
  file: Bytes.Bytes,
  index_offset: Nat,
  next_block: Nat,
  block_count: Nat,
  level: U32,
  total: Nat,
  decoded: Nat
) -> Result<&1, &1, Error, MultiRead>:
  match record_counts:
    case (for_decode, for_total):
      parse.multi.table.updated(decode.apply(for_decode, table, mutations),
        file, index_offset, next_block, block_count, level, total, decoded,
        for_total)

def parse.multi.block.decoded(
  result: Result<&1, &1, Wal.Error, ByteWal.Batch>,
  file: Bytes.Bytes,
  index_offset: Nat,
  next_block: Nat,
  block_count: Nat,
  level: U32,
  total: Nat,
  decoded: Nat,
  table: ByteMemTable.Table,
  record_count: Nat
) -> Result<&1, &1, Error, MultiRead>:
  match result:
    case Fail{Wal.ChecksumMismatch{}}: Fail{ChecksumMismatch{}}
    case Fail{_}: Fail{Malformed{}}
    case Done{ByteWal.Batch{mutations}}:
      parse.multi.block.apply(QueuePolicy.nat.clone.pair(record_count),
        table, mutations, file, index_offset, next_block, block_count, level,
        total, decoded)

def parse.multi.block.frame(
  pair: Bytes.Bytes & Bytes.Bytes,
  file: Bytes.Bytes,
  index_offset: Nat,
  next_block: Nat,
  block_count: Nat,
  level: U32,
  total: Nat,
  decoded: Nat,
  table: ByteMemTable.Table,
  record_count: Nat
) -> Result<&1, &1, Error, MultiRead>:
  match pair:
    case (_, frame):
      parse.multi.block.decoded(ByteWal.decode(frame), file, index_offset,
        next_block, block_count, level, total, decoded, table, record_count)

def parse.multi.block.count(
  pair: Bytes.Bytes & Maybe<&2, U32>,
  file: Bytes.Bytes,
  index_offset: Nat,
  next_block: Nat,
  block_count: Nat,
  level: U32,
  total: Nat,
  decoded: Nat,
  table: ByteMemTable.Table,
  payload_length: U32
) -> Result<&1, &1, Error, MultiRead>:
  match pair:
    case (block, Some{record_count}):
      +payload_nat = U32.to_nat(payload_length)
      +record_nat = U32.to_nat(record_count)
      parse.multi.block.frame(Bytes.slice(block, 8, U32.from_nat(payload_nat)),
        file, index_offset, next_block, block_count, level, total, decoded,
        table, record_nat)
    case _:
      Fail{Malformed{}}

def parse.multi.block.payload.length(
  pair: Bytes.Bytes & Maybe<&2, U32>,
  file: Bytes.Bytes,
  index_offset: Nat,
  next_block: Nat,
  block_count: Nat,
  level: U32,
  total: Nat,
  decoded: Nat,
  table: ByteMemTable.Table
) -> Result<&1, &1, Error, MultiRead>:
  match pair:
    case (block, Some{payload_length}):
      parse.multi.block.count(Bytes.get.u32be(block, 4), file,
        index_offset, next_block, block_count, level, total, decoded, table,
        payload_length)
    case _:
      Fail{Malformed{}}

def parse.multi.block.payload(
  pair: Bytes.Bytes & Bytes.Bytes,
  index_offset: Nat,
  next_block: Nat,
  block_count: Nat,
  level: U32,
  total: Nat,
  decoded: Nat,
  table: ByteMemTable.Table
) -> Result<&1, &1, Error, MultiRead>:
  match pair:
    case (file, block):
      parse.multi.block.payload.length(Bytes.get.u32be(block, 0), file,
        index_offset, next_block, block_count, level, total, decoded, table)

def parse.multi.block.offset(
  pair: Bytes.Bytes & Maybe<&2, U32>,
  index_offset: Nat,
  next_block: Nat,
  block_count: Nat,
  level: U32,
  total: Nat,
  decoded: Nat,
  table: ByteMemTable.Table
) -> Result<&1, &1, Error, MultiRead>:
  match pair:
    case (file, Some{block_offset}):
      parse.multi.block.payload(Bytes.slice(file, block_offset, 4294967295),
        index_offset, next_block, block_count, level, total, decoded, table)
    case _:
      Fail{Malformed{}}

def parse.multi.step.address(
  offsets: Nat & Nat,
  positions: Nat & Nat,
  file: Bytes.Bytes,
  block_count: Nat,
  level: U32,
  total: Nat,
  decoded: Nat,
  table: ByteMemTable.Table
) -> Result<&1, &1, Error, MultiRead>:
  match offsets:
    case (index_offset, retained_offset):
      match positions:
        case (next_block, retained_block):
          parse.multi.block.offset(Bytes.get.u32be(file,
            U32.from_nat(Nat.add(Nat.add(index_offset, 8n),
              Nat.mul(next_block, 16n)))), retained_offset, retained_block,
            block_count, level, total, decoded, table)

def parse.multi.step(state: MultiRead) -> Result<&1, &1, Error, MultiRead>:
  match state:
    case MultiRead{file, index_offset, next_block, block_count, level,
        total, decoded, table}:
      parse.multi.step.address(QueuePolicy.nat.clone.pair(index_offset),
        QueuePolicy.nat.clone.pair(next_block), file, block_count, level,
        total, decoded, table)

def parse.multi.complete(
  source: Bytes.Bytes,
  table: ByteMemTable.Table,
  level: U32,
  count_matches: Bool
) -> Result<&1, &1, Error, ByteMemTable.Table>:
  match count_matches:
    case False{}: Fail{Malformed{}}
    case True{}: parse.canonical.table(source, table, level)

def parse.multi.go(
  fuel: Nat,
  source: Bytes.Bytes,
  pending: Result<&1, &1, Error, MultiRead>
) -> Result<&1, &1, Error, ByteMemTable.Table>:
  match fuel:
    case 0n:
      match pending:
        case Fail{error}: Fail{error}
        case Done{state}:
          match state:
            case MultiRead{_, _, _, _, level, total, decoded, table}:
              parse.multi.complete(source, table, level,
                Nat.is_eq(total, decoded))
    case 1n+rest:
      match pending:
        case Fail{error}: Fail{error}
        case Done{state}:
          parse.multi.go(rest, source, parse.multi.step(state))

def parse.multi.sized.start(
  block_counts: Nat & Nat,
  source: Bytes.Bytes,
  file: Bytes.Bytes,
  index_offset: Nat,
  entries: Nat,
  level: Nat
) -> Result<&1, &1, Error, ByteMemTable.Table>:
  match block_counts:
    case (fuel, block_count):
      parse.multi.go(fuel, source, Done{MultiRead{file, index_offset,
        0n, block_count, U32.from_nat(level), entries, 0n,
        ByteMemTable.empty()}})

def parse.multi.sized.valid(
  source: Bytes.Bytes,
  file: Bytes.Bytes,
  +blocks: Nat,
  +entries: Nat,
  +level: Nat,
  +size: Nat,
  index_length: Nat,
  valid: Bool
) -> Result<&1, &1, Error, ByteMemTable.Table>:
  match valid:
    case False{}: Fail{Malformed{}}
    case True{}:
      +index_size = Nat.add(44n, index_length)
      +index_offset = Nat.sub(size, index_size)
      parse.multi.sized.start(QueuePolicy.nat.clone.pair(blocks), source,
        file, index_offset, entries, level)

def parse.multi.sized.index_length(
  source: Bytes.Bytes,
  file: Bytes.Bytes,
  +blocks: Nat,
  +entries: Nat,
  +level: Nat,
  +size: Nat,
  result: Bytes.Bytes & Maybe<&2, U32>
) -> Result<&1, &1, Error, ByteMemTable.Table>:
  match result:
    case (_, Some{length}):
      +index_length = U32.to_nat(length)
      +minimum_index_length = Nat.add(8n, Nat.mul(blocks, 16n))
      +index_size = Nat.add(44n, index_length)
      parse.multi.sized.valid(source, file, blocks, entries, level, size,
        index_length,
        Nat.is_le(minimum_index_length, index_length) &&
          Nat.is_le(index_size, size) &&
          Nat.is_le(20n, Nat.sub(size, index_size)))
    case (_, None{}): Fail{Malformed{}}

def parse.multi.sized.index.read(
  source: Bytes.Bytes,
  files: Bytes.Bytes & Bytes.Bytes,
  +blocks: Nat,
  +entries: Nat,
  +level: Nat,
  +size: Nat
) -> Result<&1, &1, Error, ByteMemTable.Table>:
  match files:
    case (file, index_file):
      parse.multi.sized.index_length(source, file, blocks, entries, level,
        size, Bytes.get.u32be(index_file,
          U32.from_nat(Nat.sub(size, 36n))))

def parse.multi.sized(
  source: Bytes.Bytes,
  measured: Bytes.Bytes & U32,
  level: U32,
  total: U32,
  block_count: U32
) -> Result<&1, &1, Error, ByteMemTable.Table>:
  match measured:
    case (file, +size):
      +blocks = U32.to_nat(block_count)
      +entries = U32.to_nat(total)
      +level_value = U32.to_nat(level)
      +size_nat = U32.to_nat(size)
      parse.multi.sized.index.read(source, clone.split(file), blocks,
        entries, level_value, size_nat)

def parse.multi.header.level.valid(
  source: Bytes.Bytes,
  file: Bytes.Bytes,
  level: U32,
  total: U32,
  block_count: U32,
  valid: Bool
) -> Result<&1, &1, Error, ByteMemTable.Table>:
  match valid:
    case False{}: Fail{InvalidLevel{}}
    case True{}:
      parse.multi.sized(source, Bytes.length(file), level, total, block_count)

def parse.multi.header.valid(
  source: Bytes.Bytes,
  result: Result<&1, &1, Error, MultiHeader>
) -> Result<&1, &1, Error, ByteMemTable.Table>:
  match result:
    case Fail{error}: Fail{error}
    case Done{MultiHeader{file, level, total, block_count}}:
      +level_nat = U32.to_nat(level)
      parse.multi.header.level.valid(source, file,
        U32.from_nat(level_nat), total, block_count,
        Nat.is_le(level_nat, 255n))

def parse.multi.copies(
  copies: Bytes.Bytes & Bytes.Bytes
) -> Result<&1, &1, Error, ByteMemTable.Table>:
  match copies:
    case (source, input):
      parse.multi.header.valid(source, parse.multi.header(input))

# Parses and validates one canonical generation-four SST block.
def parse_file(file: Bytes.Bytes) -> Result<&1, &1, Error, ByteMemTable.Table>:
  parse.multi.copies(clone.split(file))

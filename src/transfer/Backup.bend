import Base
import ../ByteMemTable.bend as ByteMemTable
import ../ByteWal.bend as ByteWal
import ../StorageBytes.bend as StorageBytes
import ../Wal.bend as Wal
import ../hub_sha/sha256.bend as SHA
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Reports invalid ordering, configured block limits, and encoding failures.
type Error is Data:
  UnsupportedPlatform{}
  InvalidOrder{}
  ResourceLimit{}
  CodecFailure{}
  SourceFailure{code: U32, message: String}

# Tracks emission of the header, data blocks, footer, and terminal state.
type Phase is Data:
  Header{}
  Blocks{}
  Footer{}
  Finished{}

# Owns an immutable logical view and the remaining export position.
type Stream is Type:
  Stream{phase: Phase, entries: List<&1, ByteMemTable.Entry>,
    entry_count: U32, block_count: U32, block_index: U32}

# Returns one independently checksummed chunk or terminal completion.
type Step is Type:
  Chunk{stream: Stream, bytes: Bytes.Bytes}
  End{}

# Holds one bounded entry page and the remaining ordered suffix.
type BatchSplit is Type:
  BatchSplit{batch: List<&1, ByteMemTable.Entry>,
    rest: List<&1, ByteMemTable.Entry>, count: U32}

def clone.pair(+len: U32, copied: Array<U32> & Array<U32>) -> Bytes.Bytes & Bytes.Bytes:
  match copied:
    case (left, right):
      (Bytes.Bytes{len, left}, Bytes.Bytes{len, right})

def clone.split(bytes: Bytes.Bytes) -> Bytes.Bytes & Bytes.Bytes:
  match bytes:
    case Bytes.Bytes{+len, buf}:
      clone.pair(len, Bytes.copy.bytes(len, buf, Bytes.alloc(len), 0, 0))

# Unwraps a fixed format marker decoded from its hexadecimal literal.
def marker(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}: bytes
    case None{}: Bytes.new(0)

# Returns the version-independent backup file identity.
def magic() -> Bytes.Bytes:
  marker(Bytes.from_hex("4d594c534d424b31"))

def block.magic() -> Bytes.Bytes:
  marker(Bytes.from_hex("424c4b31"))

def footer.magic() -> Bytes.Bytes:
  marker(Bytes.from_hex("454e4431"))

def u32.bytes(value: U32) -> Bytes.Bytes:
  Bytes.set.u32be(Bytes.new(4), 0, value)

def nat.duplicate.pair.step(pair: Nat & Nat) -> Nat & Nat:
  match pair:
    case (left, right): (Nat.add(1n, left), Nat.add(1n, right))

def nat.duplicate.pair(value: Nat) -> Nat & Nat:
  match value:
    case 0n: (0n, 0n)
    case 1n+rest: nat.duplicate.pair.step(nat.duplicate.pair(rest))

def u32.duplicate.pair.result(pair: Nat & Nat) -> U32 & U32:
  match pair:
    case (left, right): (U32.from_nat(left), U32.from_nat(right))

def u32.duplicate.pair(value: U32) -> U32 & U32:
  u32.duplicate.pair.result(nat.duplicate.pair(U32.to_nat(value)))

def blocks.count.remainder(pair: Nat & Nat) -> Nat:
  match pair:
    case (quotient, remainder):
      match remainder:
        case 0n: quotient
        case _: Nat.add(quotient, 1n)

def blocks.count.parts(entries: Nat & Nat) -> U32:
  match entries:
    case (for_division, for_remainder):
      U32.from_nat(blocks.count.remainder((Nat.div(for_division, 16n),
        Nat.mod(for_remainder, 16n))))

def blocks.count(entries: Nat) -> U32:
  blocks.count.parts(nat.duplicate.pair(entries))

# Reserves three transitions per chunk and two finalization transitions.
def write_fuel(block_count: Nat) -> Nat:
  Nat.add(Nat.mul(3n, Nat.add(block_count, 2n)), 2n)

def split.batch.go(
  fuel: Nat,
  entries: List<&1, ByteMemTable.Entry>,
  reversed: List<&1, ByteMemTable.Entry>,
  count: U32
) -> BatchSplit:
  match fuel:
    case 0n: BatchSplit{List.reverse(&1, ByteMemTable.Entry, reversed), entries, count}
    case 1n+rest:
      match entries:
        case Nil{}:
          BatchSplit{List.reverse(&1, ByteMemTable.Entry, reversed), Nil{}, count}
        case Con{entry, tail}:
          split.batch.go(rest, tail, Con{entry, reversed}, (count + 1 : U32))

def split.batch.ready(pair: List<&1, ByteMemTable.Entry> & Nat) -> BatchSplit:
  match pair:
    case (entries, count):
      split.batch.go(Nat.min(16n, count), entries, Nil{}, 0)

def split.batch(entries: List<&1, ByteMemTable.Entry>) -> BatchSplit:
  split.batch.ready(ByteMemTable.count.keep(entries))

def start.counted.count(
  entries: List<&1, ByteMemTable.Entry>,
  counts: Nat & Nat
) -> Result<&1, &1, Error, Stream>:
  match counts:
    case (entry_count, block_total):
      Done{Stream{Header{}, entries, U32.from_nat(entry_count),
        blocks.count(block_total), 0}}

def start.counted(
  measured: List<&1, ByteMemTable.Entry> & Nat
) -> Result<&1, &1, Error, Stream>:
  match measured:
    case (entries, count):
      start.counted.count(entries, nat.duplicate.pair(count))

def start.ordered(
  entries: List<&1, ByteMemTable.Entry>,
  ordered: Bool
) -> Result<&1, &1, Error, Stream>:
  match ordered:
    case False{}: Fail{InvalidOrder{}}
    case True{}: start.counted(ByteMemTable.count.keep(entries))

def start.cloned(
  copies: List<&1, ByteMemTable.Entry> & List<&1, ByteMemTable.Entry>
) -> Result<&1, &1, Error, Stream>:
  match copies:
    case (validation, source):
      start.ordered(ByteMemTable.compact.live(source),
        ByteMemTable.ordered.strict(validation))

# Starts export after removing tombstones and validating key order.
def start(entries: List<&1, ByteMemTable.Entry>) -> Result<&1, &1, Error, Stream>:
  start.cloned(ByteMemTable.entries.clone(entries))

def header.bytes.counts(
  entries: List<&1, ByteMemTable.Entry>,
  entry_counts: U32 & U32,
  block_counts: U32 & U32,
  +block_index: U32
) -> Stream & Bytes.Bytes:
  match entry_counts:
    case (state_entries, encoded_entries):
      match block_counts:
        case (state_blocks, encoded_blocks):
          (Stream{Blocks{}, entries, state_entries, state_blocks, block_index},
            Bytes.concat([magic(), u32.bytes(1), u32.bytes(encoded_entries),
              u32.bytes(encoded_blocks)]))

def header.bytes(stream: Stream) -> Stream & Bytes.Bytes:
  match stream:
    case Stream{Header{}, entries, entry_count, block_count, block_index}:
      header.bytes.counts(entries, u32.duplicate.pair(entry_count),
        u32.duplicate.pair(block_count), block_index)
    case _: (stream, Bytes.new(0))

# Converts one surviving entry into its byte WAL put representation.
def mutation(entry: ByteMemTable.Entry) -> ByteWal.Mutation:
  match entry:
    case ByteMemTable.Entry{key, Some{value}}: ByteWal.Put{key, value}
    case ByteMemTable.Entry{key, None{}}: ByteWal.Delete{key}

# Converts one bounded page of entries to byte WAL mutations.
def mutations(entries: List<&1, ByteMemTable.Entry>) -> List<&1, ByteWal.Mutation>:
  match entries:
    case Nil{}: Nil{}
    case Con{entry, tail}: Con{mutation(entry), mutations(tail)}

def block.header(
  +index: U32,
  +count: U32,
  pair: Bytes.Bytes & U32
) -> Bytes.Bytes:
  match pair:
    case (frame, +length):
      Bytes.concat([block.magic(), u32.bytes(index), u32.bytes(count),
        u32.bytes(length), frame])

def block.authenticated(
  pair: Bytes.Bytes & Bytes.Bytes
) -> Bytes.Bytes:
  match pair:
    case (output, hash_input):
      Bytes.concat([output, SHA.sha256_packed_bytes(hash_input)])

def block.bytes(
  frame: Bytes.Bytes,
  +index: U32,
  +count: U32
) -> Bytes.Bytes:
  block.authenticated(clone.split(block.header(index, count, Bytes.length(frame))))

def block.frame.bounded(
  frame: Bytes.Bytes,
  +index: U32,
  +count: U32,
  fits: Bool
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match fits:
    case False{}: Fail{ResourceLimit{}}
    case True{}: Done{block.bytes(frame, index, count)}

def block.frame.length(
  pair: Bytes.Bytes & U32,
  +index: U32,
  +count: U32
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match pair:
    case (frame, +length):
      block.frame.bounded(frame, index, count,
        U32.is_le(length, StorageBytes.MAX_BLOCK_BYTES()))

def block.frame(
  result: Result<&1, &1, Wal.Error, Bytes.Bytes>,
  +index: U32,
  +count: U32
) -> Result<&1, &1, Error, Bytes.Bytes>:
  match result:
    case Fail{_}: Fail{CodecFailure{}}
    case Done{frame}:
      block.frame.length(Bytes.length(frame), index, count)

def block.encoded(
  entries: List<&1, ByteMemTable.Entry>,
  +index: U32,
  +count: U32
) -> Result<&1, &1, Error, Bytes.Bytes>:
  block.frame(ByteWal.encode(ByteWal.Batch{mutations(entries)}), index, count)

def footer.bytes.output(
  stream: Stream,
  output: Bytes.Bytes,
  checksum: Bytes.Bytes
) -> Stream & Bytes.Bytes:
  match stream:
    case Stream{Finished{}, entries, entry_count, block_count, block_index}:
      (Stream{Finished{}, entries, entry_count, block_count, block_index},
        Bytes.concat([output, checksum]))
    case _: (stream, Bytes.new(0))

def footer.bytes.hashed(
  stream: Stream,
  pair: Bytes.Bytes & Bytes.Bytes
) -> Stream & Bytes.Bytes:
  match pair:
    case (output, hash_input):
      footer.bytes.output(stream, output, SHA.sha256_packed_bytes(hash_input))

def footer.bytes.authenticated(
  entries: List<&1, ByteMemTable.Entry>,
  +entry_count: U32,
  +block_count: U32,
  +block_index: U32,
  pair: Bytes.Bytes & Bytes.Bytes
) -> Stream & Bytes.Bytes:
  footer.bytes.hashed(Stream{Finished{}, entries, entry_count, block_count,
    block_index}, pair)

def footer.bytes.counts(
  entries: List<&1, ByteMemTable.Entry>,
  entry_counts: U32 & U32,
  block_counts: U32 & U32,
  +block_index: U32
) -> Stream & Bytes.Bytes:
  match entry_counts:
    case (state_entries, encoded_entries):
      match block_counts:
        case (state_blocks, encoded_blocks):
          footer.bytes.authenticated(entries, state_entries, state_blocks,
            block_index, clone.split(Bytes.concat([footer.magic(),
              u32.bytes(encoded_entries), u32.bytes(encoded_blocks)])))

def footer.bytes(stream: Stream) -> Stream & Bytes.Bytes:
  match stream:
    case Stream{Footer{}, entries, entry_count, block_count, block_index}:
      footer.bytes.counts(entries, u32.duplicate.pair(entry_count),
        u32.duplicate.pair(block_count), block_index)
    case _: (stream, Bytes.new(0))

def next.block.encoded(
  stream: Stream,
  tail: List<&1, ByteMemTable.Entry>,
  result: Result<&1, &1, Error, Bytes.Bytes>
) -> Result<&1, &1, Error, Step>:
  match stream:
    case Stream{Blocks{}, _, entry_count, block_count, +block_index}:
      match result:
        case Fail{error}: Fail{error}
        case Done{bytes}:
          Done{Chunk{Stream{Blocks{}, tail, entry_count, block_count,
            (block_index + 1 : U32)}, bytes}}
    case _: Fail{CodecFailure{}}

def next.block.ready.index(
  +entry_count: U32,
  +block_count: U32,
  indexes: U32 & U32,
  batch: List<&1, ByteMemTable.Entry>,
  tail: List<&1, ByteMemTable.Entry>,
  +count: U32
) -> Result<&1, &1, Error, Step>:
  match indexes:
    case (state_index, encoded_index):
      next.block.encoded(Stream{Blocks{}, Nil{}, entry_count, block_count,
        state_index}, tail, block.encoded(batch, encoded_index, count))

def next.block.footer(pair: Stream & Bytes.Bytes) -> Result<&1, &1, Error, Step>:
  match pair:
    case (stream, bytes): Done{Chunk{stream, bytes}}

def next.block.ready.split(
  +entry_count: U32,
  +block_count: U32,
  +block_index: U32,
  split: BatchSplit
) -> Result<&1, &1, Error, Step>:
  match split:
    case BatchSplit{Nil{}, entries, _}:
      next.block.footer(footer.bytes(Stream{Footer{}, entries, entry_count,
        block_count, block_index}))
    case BatchSplit{batch, tail, +count}:
      next.block.ready.index(entry_count, block_count,
        u32.duplicate.pair(block_index), batch, tail, count)

def next.block.ready(stream: Stream, split: BatchSplit) -> Result<&1, &1, Error, Step>:
  match stream:
    case Stream{Blocks{}, _, entry_count, block_count, block_index}:
      next.block.ready.split(entry_count, block_count, block_index, split)
    case _: Fail{CodecFailure{}}

def next.block(stream: Stream) -> Result<&1, &1, Error, Step>:
  match stream:
    case Stream{Blocks{}, entries, entry_count, block_count, block_index}:
      next.block.ready(Stream{Blocks{}, Nil{}, entry_count, block_count,
        block_index}, split.batch(entries))
    case _: Fail{CodecFailure{}}

def next.header.result(pair: Stream & Bytes.Bytes) -> Result<&1, &1, Error, Step>:
  match pair:
    case (updated, bytes): Done{Chunk{updated, bytes}}

def next.footer.result(pair: Stream & Bytes.Bytes) -> Result<&1, &1, Error, Step>:
  match pair:
    case (updated, bytes): Done{Chunk{updated, bytes}}

# Advances an export by one header, block, footer, or terminal state.
def next(stream: Stream) -> Result<&1, &1, Error, Step>:
  match stream:
    case Stream{Header{}, _, _, _, _}:
      next.header.result(header.bytes(stream))
    case Stream{Blocks{}, _, _, _, _}:
      next.block(stream)
    case Stream{Footer{}, _, _, _, _}:
      next.footer.result(footer.bytes(stream))
    case Stream{Finished{}, _, _, _, _}:
      Done{End{}}

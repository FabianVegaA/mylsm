import Base
import ../ByteMemTable.bend as ByteMemTable
import ../ByteWal.bend as ByteWal
import ./RestorePolicy.bend as RestorePolicy
import ../StorageBytes.bend as StorageBytes
import ../Wal.bend as Wal
import ../coordinator/QueuePolicy.bend as QueuePolicy
import ../hub_sha/sha256.bend as SHA
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Distinguishes malformed exchange data from integrity and resource failures.
type Error is Data:
  InvalidFormat{}
  ResourceLimit{}
  InvalidOrder{}
  ChecksumMismatch{}
  CountMismatch{}

# Carries the verified logical records produced by restore validation.
type Decoded is Type:
  Decoded{entries: List<&1, ByteMemTable.Entry>}

# Carries the fixed header metadata shared by all restore paths.
type Header is Type:
  Header{input: Bytes.Bytes, entry_count: U32, block_count: U32}

# Tracks block traversal and the reverse-ordered decoded entries.
type State is Type:
  State{input: Bytes.Bytes & Bytes.Bytes, offset: Nat, entry_count: U32,
    block_count: U32, remaining_blocks: Nat, block_index: Nat,
    decoded_count: Nat, reversed: List<&1, ByteMemTable.Entry>}

# Retains the source slice and decoded entries for one validated block.
type BlockMeta is Type:
  BlockMeta{input: Bytes.Bytes, offset: Nat, frame_offset: Nat,
    frame_length: Nat, record_count: Nat, block_length: Nat,
    entries: List<&1, ByteMemTable.Entry>}

# Holds validated block-header fields while checksum and frame decoding run.
type BlockHeader is Type:
  BlockHeader{input: Bytes.Bytes, offset: Nat, index: U32,
    record_count: U32, frame_length: U32, block_length: Nat}

# Carries a single-block view for the legacy envelope validation path.
type OneBlock is Type:
  OneBlock{input: Bytes.Bytes, entry_count: U32, record_count: U32,
    frame_length: U32}

# Pairs decoded entries with their observed count.
type EntryBatch is Type:
  EntryBatch{entries: List<&1, ByteMemTable.Entry>, count: Nat}

# Projects byte equality from the packed-byte comparison result.
def equal(pair: Bytes.Bytes & Bytes.Bytes & Bool) -> Bool:
  match pair:
    case (_, _, same): same

def slice.result(pair: Bytes.Bytes & Bytes.Bytes) -> Bytes.Bytes:
  match pair:
    case (_, bytes): bytes

def get.u32be.result(pair: Bytes.Bytes & Maybe<&2, U32>) -> Maybe<&2, U32>:
  match pair:
    case (_, value): value

def u32.field.is(result: Maybe<&2, U32>, expected: U32) -> Bool:
  match result:
    case None{}: False{}
    case Some{field}: U32.is_eq(field, expected)

def clone.pair(+len: U32, copied: Array<U32> & Array<U32>) -> Bytes.Bytes & Bytes.Bytes:
  match copied:
    case (left, right):
      (Bytes.Bytes{len, left}, Bytes.Bytes{len, right})

def clone.split(bytes: Bytes.Bytes) -> Bytes.Bytes & Bytes.Bytes:
  match bytes:
    case Bytes.Bytes{+len, buf}:
      clone.pair(len, Bytes.copy.bytes(len, buf, Bytes.alloc(len), 0, 0))

def clone.triple.left(
  second: Bytes.Bytes,
  copies: Bytes.Bytes & Bytes.Bytes
) -> Bytes.Bytes & Bytes.Bytes & Bytes.Bytes:
  match copies:
    case (left, right): (left, right, second)

def clone.triple.step(copies: Bytes.Bytes & Bytes.Bytes) -> Bytes.Bytes & Bytes.Bytes & Bytes.Bytes:
  match copies:
    case (first, second):
      clone.triple.left(second, clone.split(first))

def clone.triple(bytes: Bytes.Bytes) -> Bytes.Bytes & Bytes.Bytes & Bytes.Bytes:
  clone.triple.step(clone.split(bytes))

def bytes.size(pair: Bytes.Bytes & U32) -> U32:
  match pair:
    case (_, size): size

# Unwraps a fixed exchange-format marker.
def magic(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}: bytes
    case None{}: Bytes.new(0)

def magic.header() -> Bytes.Bytes:
  magic(Bytes.from_hex("4d594c534d424b31"))

def footer.magic() -> Bytes.Bytes:
  magic(Bytes.from_hex("454e4431"))

def block.magic() -> Bytes.Bytes:
  magic(Bytes.from_hex("424c4b31"))

def digest.matches(
  claimed: Bytes.Bytes,
  input: Bytes.Bytes
) -> Bool:
  equal(Bytes.eq(claimed, SHA.sha256_packed_bytes(input)))

def header.ready.block(pair: Bytes.Bytes & Maybe<&2, U32>, entry_count: U32) -> Result<&1, &1, Error, Header>:
  match pair:
    case (input, value):
      match value:
        case None{}: Fail{InvalidFormat{}}
        case Some{block_count}: Done{Header{input, entry_count, block_count}}

def header.entry_count.read(pair: Bytes.Bytes & Maybe<&2, U32>) -> Result<&1, &1, Error, Header>:
  match pair:
    case (input, value):
      match value:
        case None{}: Fail{InvalidFormat{}}
        case Some{entry_count}: header.ready.block(Bytes.get.u32be(input, 16), entry_count)

def header.block_count.checked(input: Bytes.Bytes, valid: Bool) -> Result<&1, &1, Error, Header>:
  match valid:
    case False{}: Fail{ResourceLimit{}}
    case True{}: header.entry_count.read(Bytes.get.u32be(input, 12))

def header.block_count(pair: Bytes.Bytes & Maybe<&2, U32>) -> Result<&1, &1, Error, Header>:
  match pair:
    case (input, value):
      match value:
        case None{}: Fail{InvalidFormat{}}
        case Some{block_count}:
          header.block_count.checked(input, U32.is_le(block_count, 65536))

def header.entry_count.checked(input: Bytes.Bytes, valid: Bool) -> Result<&1, &1, Error, Header>:
  match valid:
    case False{}: Fail{ResourceLimit{}}
    case True{}: header.block_count(Bytes.get.u32be(input, 16))

def header.entry_count(pair: Bytes.Bytes & Maybe<&2, U32>) -> Result<&1, &1, Error, Header>:
  match pair:
    case (input, value):
      match value:
        case None{}: Fail{InvalidFormat{}}
        case Some{entry_count}:
          header.entry_count.checked(input, U32.is_le(entry_count, 1048576))

def header.version.checked(input: Bytes.Bytes, valid: Bool) -> Result<&1, &1, Error, Header>:
  match valid:
    case False{}: Fail{InvalidFormat{}}
    case True{}: header.entry_count(Bytes.get.u32be(input, 12))

def header.version(pair: Bytes.Bytes & Maybe<&2, U32>) -> Result<&1, &1, Error, Header>:
  match pair:
    case (input, value):
      match value:
        case None{}: Fail{InvalidFormat{}}
        case Some{version}: header.version.checked(input, U32.is_eq(version, 1))

def header.magic.checked(input: Bytes.Bytes, valid: Bool) -> Result<&1, &1, Error, Header>:
  match valid:
    case False{}: Fail{InvalidFormat{}}
    case True{}: header.version(Bytes.get.u32be(input, 8))

def header.marker(pair: Bytes.Bytes & Bytes.Bytes) -> Result<&1, &1, Error, Header>:
  match pair:
    case (input, marker):
      header.magic.checked(input, equal(Bytes.eq(marker, magic.header())))

def header.parse(input: Bytes.Bytes) -> Result<&1, &1, Error, Header>:
  header.marker(Bytes.slice(input, 0, 8))

def one_block.frame_length.retained(
  pair: Bytes.Bytes & Maybe<&2, U32>,
  entry_count: U32,
  record_count: U32
) -> Result<&1, &1, Error, OneBlock>:
  match pair:
    case (input, value):
      match value:
        case None{}: Fail{InvalidFormat{}}
        case Some{frame_length}:
          Done{OneBlock{input, entry_count, record_count, frame_length}}

def one_block.frame_length.checked(
  input: Bytes.Bytes,
  entry_count: U32,
  record_count: U32,
  valid: Bool
) -> Result<&1, &1, Error, OneBlock>:
  match valid:
    case False{}: Fail{ResourceLimit{}}
    case True{}:
      one_block.frame_length.retained(Bytes.get.u32be(input, 32), entry_count,
        record_count)

def one_block.frame_length(
  pair: Bytes.Bytes & Maybe<&2, U32>,
  entry_count: U32,
  record_count: U32
) -> Result<&1, &1, Error, OneBlock>:
  match pair:
    case (input, value):
      match value:
        case None{}: Fail{InvalidFormat{}}
        case Some{frame_length}:
          one_block.frame_length.checked(input, entry_count, record_count,
            U32.is_le(frame_length, StorageBytes.MAX_BLOCK_BYTES()))

def one_block.record_count.reloaded(
  pair: Bytes.Bytes & Maybe<&2, U32>,
  entry_count: U32
) -> Result<&1, &1, Error, OneBlock>:
  match pair:
    case (input, count_value):
      match count_value:
        case None{}: Fail{InvalidFormat{}}
        case Some{record_count}:
          one_block.frame_length(Bytes.get.u32be(input, 32), entry_count,
            record_count)

def one_block.entry_count(
  pair: Bytes.Bytes & Maybe<&2, U32>
) -> Result<&1, &1, Error, OneBlock>:
  match pair:
    case (input, value):
      match value:
        case None{}: Fail{InvalidFormat{}}
        case Some{entry_count}:
          one_block.record_count.reloaded(Bytes.get.u32be(input, 28), entry_count)

def one_block.record_count.validated(
  input: Bytes.Bytes,
  valid: Bool
) -> Result<&1, &1, Error, OneBlock>:
  match valid:
    case False{}: Fail{ResourceLimit{}}
    case True{}: one_block.entry_count(Bytes.get.u32be(input, 12))

def one_block.record_count(
  pair: Bytes.Bytes & Maybe<&2, U32>
) -> Result<&1, &1, Error, OneBlock>:
  match pair:
    case (input, value):
      match value:
        case None{}: Fail{InvalidFormat{}}
        case Some{record_count}:
          one_block.record_count.validated(input,
            U32.is_le(record_count, 16))

def one_block.index.checked(
  input: Bytes.Bytes,
  valid: Bool
) -> Result<&1, &1, Error, OneBlock>:
  match valid:
    case False{}: Fail{InvalidFormat{}}
    case True{}: one_block.record_count(Bytes.get.u32be(input, 28))

def one_block.index(
  pair: Bytes.Bytes & Maybe<&2, U32>
) -> Result<&1, &1, Error, OneBlock>:
  match pair:
    case (input, value):
      match value:
        case None{}: Fail{InvalidFormat{}}
        case Some{index}: one_block.index.checked(input, U32.is_eq(index, 0))

def one_block.marker.checked(
  input: Bytes.Bytes,
  valid: Bool
) -> Result<&1, &1, Error, OneBlock>:
  match valid:
    case False{}: Fail{InvalidFormat{}}
    case True{}: one_block.index(Bytes.get.u32be(input, 24))

def one_block.marker(pair: Bytes.Bytes & Bytes.Bytes) -> Result<&1, &1, Error, OneBlock>:
  match pair:
    case (retained, marker):
      one_block.marker.checked(retained, equal(Bytes.eq(marker, block.magic())))

def one_block.open.checked(
  input: Bytes.Bytes,
  one_block_only: Bool
) -> Result<&1, &1, Error, OneBlock>:
  match one_block_only:
    case False{}: Fail{ResourceLimit{}}
    case True{}: one_block.marker(Bytes.slice(input, 20, 4))

def one_block.open(header: Header) -> Result<&1, &1, Error, OneBlock>:
  match header:
    case Header{input, _, block_count}:
      one_block.open.checked(input, U32.is_eq(block_count, 1))

def block.checksum.lengths(
  lengths: U32 & U32,
  copies: Bytes.Bytes & Bytes.Bytes
) -> Bool:
  match lengths:
    case (hash_length, claim_offset):
      match copies:
        case (for_hash, for_claim):
          digest.matches(slice.result(Bytes.slice(for_claim, claim_offset, 32)),
            slice.result(Bytes.slice(for_hash, 0, hash_length)))

def block.checksum.copies.lengths(
  lengths: Nat & Nat,
  copies: Bytes.Bytes & Bytes.Bytes
) -> Bool:
  match lengths:
    case (hash_length, claim_offset):
      block.checksum.lengths((U32.from_nat(hash_length),
        U32.from_nat(claim_offset)), copies)

def block.checksum.copies(
  block_length: U32,
  copies: Bytes.Bytes & Bytes.Bytes
) -> Bool:
  block.checksum.copies.lengths(
    QueuePolicy.nat.clone.pair(U32.to_nat(U32.sub(block_length, 32))), copies)

def block.checksum.sized.validated(
  block: Bytes.Bytes,
  hash_length: U32,
  valid: Bool
) -> Bool:
  match valid:
    case False{}: False{}
    case True{}:
      block.checksum.copies(hash_length, clone.split(block))

def block.checksum.sized.measure(
  block: Bytes.Bytes,
  compare_length: U32,
  hash_length: U32,
  measured: Bytes.Bytes & U32
) -> Bool:
  match measured:
    case (_, actual):
      block.checksum.sized.validated(block, hash_length,
        U32.is_eq(compare_length, actual))

def block.checksum.sized.lengths(
  block: Bytes.Bytes,
  lengths: Nat & Nat,
  measured: Bytes.Bytes & U32
) -> Bool:
  match lengths:
    case (for_compare, for_hash):
      block.checksum.sized.measure(block, U32.from_nat(for_compare),
        U32.from_nat(for_hash), measured)

def block.checksum.sized(
  block: Bytes.Bytes,
  block_length: U32,
  measured: Bytes.Bytes & U32
) -> Bool:
  block.checksum.sized.lengths(block,
    QueuePolicy.nat.clone.pair(U32.to_nat(block_length)), measured)

def block.checksum.input.cloned(
  block_length: U32,
  copies: Bytes.Bytes & Bytes.Bytes
) -> Bool:
  match copies:
    case (for_length, for_hash):
      block.checksum.sized(for_hash, block_length, Bytes.length(for_length))

def block.checksum.input(
  block_length: U32,
  block: Bytes.Bytes & Bytes.Bytes
) -> Bool:
  match block:
    case (_, bytes):
      block.checksum.input.cloned(block_length, clone.split(bytes))

def one_block.checksum(
  one: OneBlock,
  valid: Bool
) -> Result<&1, &1, Error, OneBlock>:
  match one:
    case OneBlock{input, entry_count, record_count, frame_length}:
      match valid:
        case False{}: Fail{ChecksumMismatch{}}
        case True{}: Done{OneBlock{input, entry_count, record_count, frame_length}}

def one_block.checksum.slice(
  copies: Bytes.Bytes & Bytes.Bytes,
  entry_count: U32,
  record_count: U32,
  frame_length: U32,
  block_lengths: Nat & Nat
) -> Result<&1, &1, Error, OneBlock>:
  match copies:
    case (retained, for_slice):
      match block_lengths:
        case (for_compare, for_read):
          one_block.checksum(
            OneBlock{retained, entry_count, record_count, frame_length},
            block.checksum.input(U32.from_nat(for_compare),
              Bytes.slice(for_slice, 20, U32.from_nat(for_read))))

def one_block.checked.lengths(
  copies: Bytes.Bytes & Bytes.Bytes,
  entry_count: U32,
  record_count: U32,
  lengths: Nat & Nat
) -> Result<&1, &1, Error, OneBlock>:
  match copies:
    case (retained, for_slice):
      match lengths:
        case (for_result, for_total):
          one_block.checksum.slice((retained, for_slice), entry_count,
            record_count, U32.from_nat(for_result),
            QueuePolicy.nat.clone.pair(Nat.add(for_total, 48n)))

def one_block.checked(one: OneBlock) -> Result<&1, &1, Error, OneBlock>:
  match one:
    case OneBlock{input, entry_count, record_count, frame_length}:
      one_block.checked.lengths(clone.split(input), entry_count, record_count,
        QueuePolicy.nat.clone.pair(U32.to_nat(frame_length)))

def mutations.entries.loop(
  fuel: Nat,
  mutations: List<&1, ByteWal.Mutation>,
  reversed: List<&1, ByteMemTable.Entry>,
  count: Nat
) -> Result<&1, &1, Error, EntryBatch>:
  match fuel:
    case 0n: Fail{ResourceLimit{}}
    case 1n+rest:
      match mutations:
        case Nil{}:
          Done{EntryBatch{List.reverse(&1, ByteMemTable.Entry, reversed), count}}
        case Con{mutation, tail}:
          match mutation:
            case ByteWal.Put{key, value}:
              mutations.entries.loop(rest, tail,
                Con{ByteMemTable.Entry{key, Some{value}}, reversed},
                Nat.add(count, 1n))
            case ByteWal.Delete{_}: Fail{InvalidFormat{}}

def mutations.entries(
  result: Result<&1, &1, Wal.Error, ByteWal.Batch>,
  count: U32
) -> Result<&1, &1, Error, EntryBatch>:
  match result:
    case Fail{_}: Fail{InvalidFormat{}}
    case Done{ByteWal.Batch{mutations}}:
      mutations.entries.loop(Nat.add(U32.to_nat(count), 1n), mutations, Nil{}, 0n)

def footer.expected_prefix(entry_count: Nat, block_count: Nat) -> Bytes.Bytes:
  Bytes.concat([footer.magic(),
    Bytes.set.u32be(Bytes.new(4), 0, U32.from_nat(entry_count)),
    Bytes.set.u32be(Bytes.new(4), 0, U32.from_nat(block_count))])

def footer.valid.digest(copies: Bytes.Bytes & Bytes.Bytes) -> Bool:
  match copies:
    case (for_claim, for_hash):
      digest.matches(slice.result(Bytes.slice(for_claim, 12, 32)),
        slice.result(Bytes.slice(for_hash, 0, 12)))

def footer.valid.copies(
  copies: Bytes.Bytes & Bytes.Bytes,
  entry_count: Nat,
  block_count: Nat
) -> Bool:
  match copies:
    case (for_fields, for_digest):
      equal(Bytes.eq(slice.result(Bytes.slice(for_fields, 0, 12)),
        footer.expected_prefix(entry_count, block_count))) &&
        footer.valid.digest(clone.split(for_digest))

def footer.valid.pair(
  pair: Bytes.Bytes & Bytes.Bytes,
  entry_count: Nat,
  block_count: Nat
) -> Bool:
  match pair:
    case (_, footer): footer.valid.copies(clone.split(footer), entry_count, block_count)

def footer.valid(
  input: Bytes.Bytes,
  offset: U32,
  entry_count: Nat,
  block_count: Nat
) -> Bool:
  footer.valid.pair(Bytes.slice(input, offset, 44), entry_count, block_count)

def footer.checked.checksum(
  entries: List<&1, ByteMemTable.Entry>,
  valid: Bool
) -> Result<&1, &1, Error, Decoded>:
  match valid:
    case False{}: Fail{ChecksumMismatch{}}
    case True{}: Done{Decoded{entries}}

def footer.checked(
  input: Bytes.Bytes,
  offset: U32,
  count: Nat,
  block_count: Nat,
  entries: List<&1, ByteMemTable.Entry>,
  size_valid: Bool
) -> Result<&1, &1, Error, Decoded>:
  match size_valid:
    case False{}: Fail{InvalidFormat{}}
    case True{}:
      footer.checked.checksum(entries, footer.valid(input, offset, count, block_count))

def footer.result(
  input: Bytes.Bytes,
  offset: U32,
  count: Nat,
  block_count: Nat,
  entries: List<&1, ByteMemTable.Entry>,
  size_valid: Bool
) -> Result<&1, &1, Error, Decoded>:
  footer.checked(input, offset, count, block_count, entries, size_valid)

def entries.finish.footer.file.length.copies(
  pair: Bytes.Bytes & U32,
  block_lengths: Nat & Nat,
  count: Nat,
  entries: List<&1, ByteMemTable.Entry>
) -> Result<&1, &1, Error, Decoded>:
  match pair:
    case (retained, size):
      match block_lengths:
        case (for_offset, for_size):
          footer.result(retained, U32.from_nat(Nat.add(20n, for_offset)),
            count, 1n, entries,
            Nat.is_eq(U32.to_nat(size), Nat.add(Nat.add(20n, for_size), 44n)))

def entries.finish.footer.file.length(
  pair: Bytes.Bytes & U32,
  block_length: Nat,
  count: Nat,
  entries: List<&1, ByteMemTable.Entry>
) -> Result<&1, &1, Error, Decoded>:
  entries.finish.footer.file.length.copies(pair,
    QueuePolicy.nat.clone.pair(block_length), count, entries)

def entries.finish.footer.file(
  input: Bytes.Bytes,
  block_length: Nat,
  count: Nat,
  entries: List<&1, ByteMemTable.Entry>
) -> Result<&1, &1, Error, Decoded>:
  entries.finish.footer.file.length(Bytes.length(input), block_length,
    count, entries)

def entries.finish.footer.size(
  input: Bytes.Bytes,
  offset: U32,
  count: Nat,
  entries: List<&1, ByteMemTable.Entry>,
  valid_size: Bool
) -> Result<&1, &1, Error, Decoded>:
  match valid_size:
    case False{}: Fail{InvalidFormat{}}
    case True{}: footer.result(input, offset, count, 1n, entries, True{})

def entries.finish.validated(
  input: Bytes.Bytes,
  block_length: Nat,
  count: Nat,
  entries: List<&1, ByteMemTable.Entry>,
  valid: Bool
) -> Result<&1, &1, Error, Decoded>:
  match valid:
    case False{}: Fail{InvalidOrder{}}
    case True{}: entries.finish.footer.file(input, block_length, count, entries)

def entries.finish.count.checked(
  input: Bytes.Bytes,
  block_length: Nat,
  count: Nat,
  entries: List<&1, ByteMemTable.Entry>,
  to_order: List<&1, ByteMemTable.Entry>,
  count_valid: Bool
) -> Result<&1, &1, Error, Decoded>:
  match count_valid:
    case False{}: Fail{CountMismatch{}}
    case True{}:
      entries.finish.validated(input, block_length, count, entries,
        ByteMemTable.ordered.strict(to_order))

def entries.finish.checked(
  input: Bytes.Bytes,
  entry_count: U32,
  block_length: Nat,
  counts: Nat & Nat,
  lists: List<&1, ByteMemTable.Entry> & List<&1, ByteMemTable.Entry>
) -> Result<&1, &1, Error, Decoded>:
  match counts:
    case (count, checked_count):
      match lists:
        case (to_order, entries):
          entries.finish.count.checked(input, block_length,
            count, entries, to_order,
            Nat.is_eq(checked_count, U32.to_nat(entry_count)))

def entries.finish(
  input: Bytes.Bytes,
  entry_count: U32,
  block_length: Nat,
  parsed: EntryBatch
) -> Result<&1, &1, Error, Decoded>:
  match parsed:
    case EntryBatch{entries, count}:
      entries.finish.checked(input, entry_count, block_length,
        QueuePolicy.nat.clone.pair(count), ByteMemTable.entries.clone(entries))

def one_block.frame.entries(
  one: OneBlock,
  result: Result<&1, &1, Error, EntryBatch>
) -> Result<&1, &1, Error, Decoded>:
  match one:
    case OneBlock{input, entry_count, record_count, frame_length}:
      match result:
        case Fail{error}: Fail{error}
        case Done{entries}:
          entries.finish(input, entry_count,
            Nat.add(U32.to_nat(frame_length), 48n), entries)

def one_block.frame.decoded.count(
  input: Bytes.Bytes,
  entry_count: U32,
  frame_length: U32,
  result: Result<&1, &1, Wal.Error, ByteWal.Batch>,
  counts: Nat & Nat
) -> Result<&1, &1, Error, Decoded>:
  match counts:
    case (record_count, mutation_count):
      one_block.frame.entries(
        OneBlock{input, entry_count, U32.from_nat(record_count), frame_length},
        mutations.entries(result, U32.from_nat(mutation_count)))

def one_block.frame.decoded(
  one: OneBlock,
  result: Result<&1, &1, Wal.Error, ByteWal.Batch>
) -> Result<&1, &1, Error, Decoded>:
  match one:
    case OneBlock{input, entry_count, record_count, frame_length}:
      one_block.frame.decoded.count(input, entry_count, frame_length, result,
        QueuePolicy.nat.clone.pair(U32.to_nat(record_count)))

def one_block.frame.bytes(
  one: OneBlock,
  frame: Bytes.Bytes & Bytes.Bytes
) -> Result<&1, &1, Error, Decoded>:
  match frame:
    case (retained, bytes):
      one_block.frame.decoded(one, ByteWal.decode(bytes))

def one_block.frame.read(
  input_copies: Bytes.Bytes & Bytes.Bytes,
  frame_lengths: Nat & Nat,
  entry_count: U32,
  record_count: U32
) -> Result<&1, &1, Error, Decoded>:
  match input_copies:
    case (retained, for_slice):
      match frame_lengths:
        case (for_result, for_read):
          one_block.frame.bytes(
            OneBlock{retained, entry_count, record_count, U32.from_nat(for_result)},
            Bytes.slice(for_slice, 36, U32.from_nat(for_read)))

def one_block.frame(one: OneBlock) -> Result<&1, &1, Error, Decoded>:
  match one:
    case OneBlock{input, entry_count, record_count, frame_length}:
      one_block.frame.read(clone.split(input),
        QueuePolicy.nat.clone.pair(U32.to_nat(frame_length)), entry_count,
        record_count)

def one_block.restore.verified(
  result: Result<&1, &1, Error, OneBlock>
) -> Result<&1, &1, Error, Decoded>:
  match result:
    case Fail{error}: Fail{error}
    case Done{verified}: one_block.frame(verified)

def one_block.restore(result: Result<&1, &1, Error, OneBlock>) -> Result<&1, &1, Error, Decoded>:
  match result:
    case Fail{error}: Fail{error}
    case Done{one}: one_block.restore.verified(one_block.checked(one))

def empty.footer.valid.copies(copies: Bytes.Bytes & Bytes.Bytes) -> Bool:
  match copies:
    case (for_footer, for_digest):
      digest.matches(slice.result(Bytes.slice(for_footer, 32, 32)),
        slice.result(Bytes.slice(for_digest, 20, 12)))

def empty.footer.valid(input: Bytes.Bytes) -> Bool:
  empty.footer.valid.copies(clone.split(input))

def empty.header.blocks(pair: Bytes.Bytes & Maybe<&2, U32>) -> Bool:
  match pair:
    case (_, count): u32.field.is(count, 0)

def empty.header.entries.checked(input: Bytes.Bytes, valid: Bool) -> Bool:
  match valid:
    case False{}: False{}
    case True{}: empty.header.blocks(Bytes.get.u32be(input, 16))

def empty.header.entries(pair: Bytes.Bytes & Maybe<&2, U32>) -> Bool:
  match pair:
    case (input, count):
      empty.header.entries.checked(input, u32.field.is(count, 0))

def empty.header.version.checked(input: Bytes.Bytes, valid: Bool) -> Bool:
  match valid:
    case False{}: False{}
    case True{}: empty.header.entries(Bytes.get.u32be(input, 12))

def empty.header.version(pair: Bytes.Bytes & Maybe<&2, U32>) -> Bool:
  match pair:
    case (input, version):
      empty.header.version.checked(input, u32.field.is(version, 1))

def empty.header.magic.checked(input: Bytes.Bytes, valid: Bool) -> Bool:
  match valid:
    case False{}: False{}
    case True{}: empty.header.version(Bytes.get.u32be(input, 8))

def empty.header.magic(pair: Bytes.Bytes & Bytes.Bytes) -> Bool:
  match pair:
    case (input, marker):
      empty.header.magic.checked(input, equal(Bytes.eq(marker, magic.header())))

def empty.header.valid(input: Bytes.Bytes) -> Bool:
  empty.header.magic(Bytes.slice(input, 0, 8))

def decode.empty(valid: Bool) -> Result<&1, &1, Error, Decoded>:
  match valid:
    case False{}: Fail{InvalidFormat{}}
    case True{}: Done{Decoded{Nil{}}}

def empty.footer.fields(input: Bytes.Bytes) -> Bool:
  equal(Bytes.eq(slice.result(Bytes.slice(input, 20, 12)),
    Bytes.concat([footer.magic(), Bytes.new(8)])))

def decode.empty.footer.checked(
  input: Bytes.Bytes,
  checksum_valid: Bool
) -> Result<&1, &1, Error, Decoded>:
  match checksum_valid:
    case False{}: Fail{ChecksumMismatch{}}
    case True{}: decode.empty(empty.footer.fields(input))

def decode.empty.footer.copies(
  copies: Bytes.Bytes & Bytes.Bytes
) -> Result<&1, &1, Error, Decoded>:
  match copies:
    case (for_fields, for_digest):
      decode.empty.footer.checked(for_fields, empty.footer.valid(for_digest))

def decode.empty.header.checked(
  input: Bytes.Bytes,
  header_valid: Bool
) -> Result<&1, &1, Error, Decoded>:
  match header_valid:
    case False{}: Fail{InvalidFormat{}}
    case True{}: decode.empty.footer.copies(clone.split(input))

def decode.empty.header.copies(
  copies: Bytes.Bytes & Bytes.Bytes
) -> Result<&1, &1, Error, Decoded>:
  match copies:
    case (for_footer, for_header):
      decode.empty.header.checked(for_footer, empty.header.valid(for_header))

def decode.empty.size.validated(
  input: Bytes.Bytes,
  size_valid: Bool
) -> Result<&1, &1, Error, Decoded>:
  match size_valid:
    case False{}: Fail{InvalidFormat{}}
    case True{}: decode.empty.header.copies(clone.split(input))

def decode.empty.size(input: Bytes.Bytes, size: U32) -> Result<&1, &1, Error, Decoded>:
  decode.empty.size.validated(input, U32.is_eq(size, 64))

def decode.length(pair: Bytes.Bytes & U32) -> Result<&1, &1, Error, Decoded>:
  match pair:
    case (input, size): decode.empty.size(input, size)

def restore.block.frame.bounded(
  input: Bytes.Bytes,
  +offset: Nat,
  index: U32,
  +record_count: U32,
  +frame_length: U32,
  +block_length: Nat,
  valid: Bool
) -> Result<&1, &1, Error, BlockHeader>:
  match valid:
    case False{}: Fail{InvalidFormat{}}
    case True{}:
      Done{BlockHeader{input, offset, index, record_count,
        frame_length, block_length}}
def restore.block.frame.bounds(
  input: Bytes.Bytes,
  +offset: Nat,
  index: U32,
  record_count: U32,
  +frame_length: U32,
  +block_length: Nat,
  +input_size: U32
) -> Result<&1, &1, Error, BlockHeader>:
  restore.block.frame.bounded(input, offset, index, record_count,
    frame_length, block_length,
    Nat.is_le(Nat.add(offset, block_length), U32.to_nat(input_size)))
def restore.block.frame.limit(
  input: Bytes.Bytes,
  +offset: Nat,
  index: U32,
  record_count: U32,
  +frame_length: U32,
  +input_size: U32,
  valid: Bool
) -> Result<&1, &1, Error, BlockHeader>:
  match valid:
    case False{}: Fail{ResourceLimit{}}
    case True{}:
      +block_length = Nat.add(U32.to_nat(frame_length), 48n)
      restore.block.frame.bounds(input, offset, index, record_count,
        frame_length, block_length, input_size)
def restore.block.frame.length.checked(
  measured: Bytes.Bytes & U32,
  +offset: Nat,
  index: U32,
  record_count: U32,
  +frame_length: U32,
  valid: Bool
) -> Result<&1, &1, Error, BlockHeader>:
  match measured:
    case (input, input_size):
      restore.block.frame.limit(input, offset, index, record_count,
        frame_length, input_size, valid)

def restore.block.frame.field(
  pair: Bytes.Bytes & Maybe<&2, U32>,
  +offset: Nat,
  index: U32,
  record_count: U32
) -> Result<&1, &1, Error, BlockHeader>:
  match pair:
    case (input, result):
      match result:
        case None{}: Fail{InvalidFormat{}}
        case Some{+frame_length}:
          restore.block.frame.length.checked(Bytes.length(input), offset,
            index, record_count, frame_length,
            U32.is_le(frame_length, StorageBytes.MAX_BLOCK_BYTES()))

def restore.block.count.valid(
  input: Bytes.Bytes,
  +offset: Nat,
  index: U32,
  record_count: U32,
  within_limit: Bool,
  empty: Bool
) -> Result<&1, &1, Error, BlockHeader>:
  match within_limit:
    case False{}: Fail{ResourceLimit{}}
    case True{}:
      match empty:
        case True{}: Fail{InvalidFormat{}}
        case False{}:
          restore.block.frame.field(Bytes.get.u32be(input,
            U32.from_nat(Nat.add(offset, 12n))), offset,
            index, record_count)
def restore.block.count.field(
  pair: Bytes.Bytes & Maybe<&2, U32>,
  +offset: Nat,
  index: U32
) -> Result<&1, &1, Error, BlockHeader>:
  match pair:
    case (input, result):
      match result:
        case None{}: Fail{InvalidFormat{}}
        case Some{+record_count}:
          restore.block.count.valid(input, offset, index, record_count,
            U32.is_le(record_count, 16), U32.is_eq(record_count, 0))
def restore.block.index.checked(
  input: Bytes.Bytes,
  +offset: Nat,
  index: U32,
  valid: Bool
) -> Result<&1, &1, Error, BlockHeader>:
  match valid:
    case False{}: Fail{InvalidFormat{}}
    case True{}:
      restore.block.count.field(Bytes.get.u32be(input,
        U32.from_nat(Nat.add(offset, 8n))), offset, index)
def restore.block.index.field(
  pair: Bytes.Bytes & Maybe<&2, U32>,
  +offset: Nat,
  expected_index: U32
) -> Result<&1, &1, Error, BlockHeader>:
  match pair:
    case (input, result):
      match result:
        case None{}: Fail{InvalidFormat{}}
        case Some{+index}:
          restore.block.index.checked(input, offset, index,
            U32.is_eq(index, expected_index))
def restore.block.index.valid(
  pair: Bytes.Bytes & Maybe<&2, U32>,
  +offset: Nat,
  expected_index: U32
) -> Result<&1, &1, Error, BlockHeader>:
  restore.block.index.field(pair, offset, expected_index)
def restore.block.magic.valid(
  input: Bytes.Bytes,
  +offset: Nat,
  expected_index: U32,
  valid: Bool
) -> Result<&1, &1, Error, BlockHeader>:
  match valid:
    case False{}: Fail{InvalidFormat{}}
    case True{}:
      restore.block.index.valid(Bytes.get.u32be(input,
        U32.from_nat(Nat.add(offset, 4n))), offset, expected_index)


def restore.block.magic(
  pair: Bytes.Bytes & Bytes.Bytes,
  +offset: Nat,
  expected_index: U32
) -> Result<&1, &1, Error, BlockHeader>:
  match pair:
    case (input, marker):
      restore.block.magic.valid(input, offset, expected_index,
        equal(Bytes.eq(marker, block.magic())))

def restore.block.header(
  input: Bytes.Bytes,
  +offset: Nat,
  expected_index: U32
) -> Result<&1, &1, Error, BlockHeader>:
  restore.block.magic(Bytes.slice(input, U32.from_nat(offset), 4),
    offset, expected_index)

def restore.block.batch.checked(
  input: Bytes.Bytes,
  +offset: Nat,
  index: U32,
  record_count: U32,
  frame_length: U32,
  +block_length: Nat,
  batch: EntryBatch,
  valid: Bool
) -> Result<&1, &1, Error, BlockHeader & List<&1, ByteMemTable.Entry>>:
  match batch:
    case EntryBatch{entries, _}:
      match valid:
        case False{}: Fail{CountMismatch{}}
        case True{}:
          Done{(BlockHeader{input, offset, index, record_count,
            frame_length, block_length}, entries)}


def restore.block.batch.measure(
  input: Bytes.Bytes,
  +offset: Nat,
  index: U32,
  +record_count: U32,
  frame_length: U32,
  +block_length: Nat,
  batch: EntryBatch
) -> Result<&1, &1, Error, BlockHeader & List<&1, ByteMemTable.Entry>>:
  match batch:
    case EntryBatch{_, +count}:
      restore.block.batch.checked(input, offset, index, record_count,
        frame_length, block_length, batch,
        Nat.is_eq(count, U32.to_nat(record_count)))



def restore.block.frame.entries(
  header: BlockHeader,
  result: Result<&1, &1, Error, EntryBatch>
) -> Result<&1, &1, Error, BlockHeader & List<&1, ByteMemTable.Entry>>:
  match header:
    case BlockHeader{input, offset, index, record_count, frame_length,
        block_length}:
      match result:
        case Fail{error}: Fail{error}
        case Done{batch}:
          restore.block.batch.measure(input, offset, index, record_count,
            frame_length, block_length, batch)

def restore.block.frame.decoded(
  header: BlockHeader,
  result: Result<&1, &1, Wal.Error, ByteWal.Batch>
) -> Result<&1, &1, Error, BlockHeader & List<&1, ByteMemTable.Entry>>:
  match header:
    case BlockHeader{_, _, _, +record_count, _, _}:
      restore.block.frame.entries(header, mutations.entries(result, record_count))


def restore.block.checksum.validated(
  header: BlockHeader,
  decoded: Result<&1, &1, Wal.Error, ByteWal.Batch>,
  valid: Bool
) -> Result<&1, &1, Error, BlockHeader & List<&1, ByteMemTable.Entry>>:
  match valid:
    case False{}: Fail{ChecksumMismatch{}}
    case True{}: restore.block.frame.decoded(header, decoded)


def restore.block.checksum.copies(
  +offset: Nat,
  index: U32,
  record_count: U32,
  +frame_length: U32,
  +block_length: Nat,
  copies: Bytes.Bytes & Bytes.Bytes & Bytes.Bytes
) -> Result<&1, &1, Error, BlockHeader & List<&1, ByteMemTable.Entry>>:
  match copies:
    case (for_hash, for_frame, for_input):
      restore.block.checksum.validated(
        BlockHeader{for_input, offset, index, record_count,
          frame_length, block_length},
        ByteWal.decode(slice.result(Bytes.slice(for_frame,
          U32.from_nat(Nat.add(offset, 16n)), frame_length))),
        block.checksum.input(U32.from_nat(block_length),
          Bytes.slice(for_hash, U32.from_nat(offset),
            U32.from_nat(block_length))))


def restore.block.checksum.valid(
  header: BlockHeader
) -> Result<&1, &1, Error, BlockHeader & List<&1, ByteMemTable.Entry>>:
  match header:
    case BlockHeader{input, +offset, index, record_count, +frame_length,
        +block_length}:
      restore.block.checksum.copies(offset, index, record_count,
        frame_length, block_length, clone.triple(input))

def restore.block.checked(
  result: Result<&1, &1, Error, BlockHeader & List<&1, ByteMemTable.Entry>>
) -> Result<&1, &1, Error, BlockMeta>:
  match result:
    case Fail{error}: Fail{error}
    case Done{(verified, entries)}:
      match verified:
        case BlockHeader{input, +offset, _, +record_count,
            +frame_length, +block_length}:
          Done{BlockMeta{input, offset, Nat.add(offset, 16n),
            U32.to_nat(frame_length), U32.to_nat(record_count), block_length,
            entries}}

def restore.block.open.result(
  result: Result<&1, &1, Error, BlockHeader>
) -> Result<&1, &1, Error, BlockMeta>:
  match result:
    case Fail{error}: Fail{error}
    case Done{header}:
      restore.block.checked(restore.block.checksum.valid(header))


def restore.block.open(
  input: Bytes.Bytes,
  +offset: Nat,
  expected_index: U32
) -> Result<&1, &1, Error, BlockMeta>:
  restore.block.open.result(restore.block.header(input, offset, expected_index))


def restore.prepend.entries(
  entries: List<&1, ByteMemTable.Entry>,
  reversed: List<&1, ByteMemTable.Entry>
) -> List<&1, ByteMemTable.Entry>:
  match entries:
    case Nil{}: reversed
    case Con{entry, tail}:
      restore.prepend.entries(tail, Con{entry, reversed})

def restore.finish.order(
  input: Bytes.Bytes,
  +offset: Nat,
  +entry_count: U32,
  +block_count: U32,
  entries: List<&1, ByteMemTable.Entry>,
  ordered: Bool
) -> Result<&1, &1, Error, Decoded>:
  match ordered:
    case False{}: Fail{InvalidOrder{}}
    case True{}:
      footer.checked.checksum(entries,
        footer.valid(input, U32.from_nat(offset), U32.to_nat(entry_count),
          U32.to_nat(block_count)))


def restore.finish.footer.copies(
  input: Bytes.Bytes,
  +offset: Nat,
  entry_count: U32,
  block_count: U32,
  copies: List<&1, ByteMemTable.Entry> & List<&1, ByteMemTable.Entry>
) -> Result<&1, &1, Error, Decoded>:
  match copies:
    case (for_order, entries):
      restore.finish.order(input, offset, entry_count, block_count, entries,
        ByteMemTable.ordered.strict(for_order))



def restore.finish.footer(
  input: Bytes.Bytes,
  +offset: Nat,
  entry_count: U32,
  block_count: U32,
  entries: List<&1, ByteMemTable.Entry>
) -> Result<&1, &1, Error, Decoded>:
  restore.finish.footer.copies(input, offset, entry_count, block_count,
    ByteMemTable.entries.clone(entries))

def restore.finish.size.valid(
  input: Bytes.Bytes,
  +offset: Nat,
  entry_count: U32,
  block_count: U32,
  reversed: List<&1, ByteMemTable.Entry>,
  valid: Bool
) -> Result<&1, &1, Error, Decoded>:
  match valid:
    case False{}: Fail{InvalidFormat{}}
    case True{}:
      restore.finish.footer(input, offset, entry_count, block_count,
        List.reverse(&1, ByteMemTable.Entry, reversed))


def restore.finish.count.valid(
  input: Bytes.Bytes,
  +offset: Nat,
  entry_count: U32,
  block_count: U32,
  reversed: List<&1, ByteMemTable.Entry>,
  +size: U32,
  valid: Bool
) -> Result<&1, &1, Error, Decoded>:
  match valid:
    case False{}: Fail{CountMismatch{}}
    case True{}:
      restore.finish.size.valid(input, offset, entry_count, block_count,
        reversed, Nat.is_eq(Nat.add(offset, 44n), U32.to_nat(size)))


def restore.finish(
  measured: Bytes.Bytes & U32,
  +offset: Nat,
  +entry_count: U32,
  +block_count: U32,
  +decoded_count: Nat,
  reversed: List<&1, ByteMemTable.Entry>
) -> Result<&1, &1, Error, Decoded>:
  match measured:
    case (input, size):
      restore.finish.count.valid(input, offset, entry_count, block_count,
        reversed, size,
        U32.is_eq(U32.from_nat(decoded_count), entry_count))

def restore.loop(
  fuel: Nat,
  state: State,
  current: Result<&1, &1, Error, BlockMeta>
) -> Result<&1, &1, Error, Decoded>:
  match fuel:
    case 0n: Fail{InvalidFormat{}}
    case 1n+fuel_rest:
    match state:
      case State{input, +offset, entry_count, block_count, +remaining_blocks,
          +block_index, +decoded_count, reversed}:
        match input:
          case (for_size, retained):
            match remaining_blocks:
              case 0n: Fail{InvalidFormat{}}
              case 1n+rest:
                match rest:
                  case 0n:
                    match current:
                      case Fail{error}: Fail{error}
                      case Done{block}:
                        match block:
                          case BlockMeta{_, _, _, _, +record_count, +block_length, entries}:
                            +next_offset = Nat.add(offset, block_length)
                            +next_count = Nat.add(decoded_count, record_count)
                            next_reversed = restore.prepend.entries(entries, reversed)
                            restore.finish(Bytes.length(for_size), next_offset,
                              entry_count, block_count, next_count,
                              next_reversed)
                  case 1n+more:
                    match current:
                      case Fail{error}: Fail{error}
                      case Done{block}:
                        match block:
                          case BlockMeta{_, _, _, _, +record_count, +block_length, entries}:
                            +next_offset = Nat.add(offset, block_length)
                            +next_index = Nat.add(block_index, 1n)
                            +next_count = Nat.add(decoded_count, record_count)
                            next_reversed = restore.prepend.entries(entries, reversed)
                            restore.loop(fuel_rest,
                            State{clone.split(retained), next_offset, entry_count,
                              block_count,
                              RestorePolicy.remaining(
                                RestorePolicy.after_block(remaining_blocks)),
                              next_index, next_count,
                                next_reversed},
                              restore.block.open(for_size, next_offset,
                                U32.from_nat(next_index)))

def restore.loop.start(
  copies: Bytes.Bytes & Bytes.Bytes & Bytes.Bytes,
  entry_count: U32,
  +block_count: U32
) -> Result<&1, &1, Error, Decoded>:
  match copies:
    case (for_state, for_retained, for_open):
      restore.loop(U32.to_nat(block_count),
        State{(for_state, for_retained), 20n, entry_count, block_count,
          U32.to_nat(block_count), 0n, 0n, Nil{}},
        restore.block.open(for_open, 20n, 0))


def decode.header.blocks(input: Bytes.Bytes, header: Header) -> Result<&1, &1, Error, Decoded>:
  match header:
    case Header{_, entry_count, block_count}:
      restore.loop.start(clone.triple(input), entry_count, block_count)

def decode.header.route(input: Bytes.Bytes, header: Header, empty: Bool) -> Result<&1, &1, Error, Decoded>:
  match empty:
    case True{}: decode.length(Bytes.length(input))
    case False{}: decode.header.blocks(input, header)

def decode.header.ready.count(
  input: Bytes.Bytes,
  header_input: Bytes.Bytes,
  entry_count: U32,
  counts: Nat & Nat
) -> Result<&1, &1, Error, Decoded>:
  match counts:
    case (for_check, for_header):
      decode.header.route(input,
        Header{header_input, entry_count, U32.from_nat(for_header)},
        U32.is_eq(U32.from_nat(for_check), 0))

def decode.header.ready(input: Bytes.Bytes, header: Header) -> Result<&1, &1, Error, Decoded>:
  match header:
    case Header{header_input, entry_count, block_count}:
      decode.header.ready.count(input, header_input, entry_count,
        QueuePolicy.nat.clone.pair(U32.to_nat(block_count)))

def decode.header(input: Bytes.Bytes, result: Result<&1, &1, Error, Header>) -> Result<&1, &1, Error, Decoded>:
  match result:
    case Fail{error}: Fail{error}
    case Done{header}: decode.header.ready(input, header)

def decode.copies(copies: Bytes.Bytes & Bytes.Bytes) -> Result<&1, &1, Error, Decoded>:
  match copies:
    case (for_restore, for_header):
      decode.header(for_restore, header.parse(for_header))

# Validates a bounded exchange and decodes the currently supported block layout.
def decode(input: Bytes.Bytes) -> Result<&1, &1, Error, Decoded>:
  decode.copies(clone.split(input))

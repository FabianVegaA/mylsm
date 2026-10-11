import Base
import ../ByteSstFile.bend as ByteSstFile
import ../ByteMemTable.bend as ByteMemTable
import ../StorageBytes.bend as StorageBytes
import ../ByteRecoveryPolicy.bend as RecoveryPolicy
import ../Fs.bend as Fs
import ../SstStreamIo.bend as SstStreamIo
import ../coordinator/QueuePolicy.bend as QueuePolicy
import ./BlockOrder.bend as BlockOrder
import ./BlockIndexPolicy.bend as BlockIndexPolicy
import ./BlockIndexFormatPolicy.bend as BlockIndexFormatPolicy
import ./BlockRoutePolicy.bend as BlockRoutePolicy
import ../hub_sha/sha256.bend as SHA
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Retains bounded traversal metadata without materializing the table entries.
type State is Type:
  State{size: Nat, header: Bytes.Bytes, index_offset: Nat, used: Nat,
    total: U32, block_count: U32, next_block: U32, decoded: U32,
    root_hash: SHA.Stream, index_hash: SHA.Stream,
    last_key: Maybe<&1, Bytes.Bytes>, selected: Bool}

# Owns the open file and its current stream position.
type Reader is Type:
  Reader{file: File, state: State}

# Retains only the authenticated file's fixed-size table and index metadata.
type Metadata is Data:
  Metadata{size: Nat, total: U32, block_count: U32, index_offset: Nat,
    live_entries: Nat, payload_bytes: Nat}

# Represents one decoded block, end of input, or a read failure.
type Step is Type:
  Block{reader: Reader, entries: List<&1, ByteMemTable.Entry>}
  End{}

# Owns the active reader and the unread entries from its current block.
type EntryCursor is Type:
  EntryReady{reader: Reader, entries: List<&1, ByteMemTable.Entry>}
  EntryEnded{}
  EntryClosed{}
  EntryFailed{error: U32 & String}

# Represents one entry, an empty block, end of file, or a terminal error.
type EntryStep is Type:
  EntryItem{entry: ByteMemTable.Entry, cursor: EntryCursor}
  EntrySkip{cursor: EntryCursor}
  EntryEnd{}
  EntryError{cursor: EntryCursor}


# Carries the block header while the bounded body read is in flight.
type BodyContext is Type:
  BodyContext{state: State, block_header: Bytes.Bytes, payload_length: U32}

# Retains the file and bounded hash/index progress during traversal.
type IndexState is Type:
  IndexState{file: File, reader: State, hash: SHA.Stream, first: Nat}

# Retains one bounded serialized-index page and its incremental validators.
type IndexPageState is Type:
  IndexPageNeed{file: File, reader: IndexMeta, offset: Nat, remaining: Nat,
    actual_hash: SHA.Stream, root_hash: SHA.Stream}
  IndexPageRead{pair: File & Result<&1, &1, U32 & String, SstStreamIo.ExactResult>,
    reader: IndexMeta, offset: Nat, remaining: Nat,
    actual_hash: SHA.Stream, root_hash: SHA.Stream}
  IndexPageParsed{file: File, result: Result<&1, &1, U32 & String, IndexPageData>}

# Carries page validation outputs without retaining serialized index bytes.
type IndexPageData is Type:
  IndexPageData{reader: IndexMeta, offset: Nat, remaining: Nat,
    actual_hash: SHA.Stream, root_hash: SHA.Stream}

# Holds only footer fields required after index traversal completes.
type IndexMeta is Type:
  IndexMeta{total: U32, index_length: U32, expected_hash: SHA.Stream}

# Carries the owned reader through positional separator search states.
type RouteContext is Data:
  RouteContext{size: Nat, index_offset: Nat, block_count: Nat}

# Carries each positional read through the separator-search state machine.
type RouteState is Type:
  RouteNeed{file: File, state: State, context: RouteContext, key: Bytes.Bytes,
    search: BlockRoutePolicy.Search}
  RouteSelect{reader: Reader, block: Nat}
  RouteRecordRead{pair: File & Result<&1, &1, U32 & String,
    SstStreamIo.ExactResult>, state: State, context: RouteContext, key: Bytes.Bytes,
    search: BlockRoutePolicy.Search, mid: Nat}
  RouteSeparatorNeed{file: File, state: State, context: RouteContext, key: Bytes.Bytes,
    search: BlockRoutePolicy.Search, mid: Nat, offset: Nat, length: U32,
    separator_start: Nat}
  RouteSeparatorRead{pair: File & Result<&1, &1, U32 & String,
    SstStreamIo.ExactResult>, state: State, context: RouteContext, key: Bytes.Bytes,
    search: BlockRoutePolicy.Search, mid: Nat}
  RouteCompare{file: File, state: State, context: RouteContext, key: Bytes.Bytes,
    search: BlockRoutePolicy.Search, mid: Nat, separator: Bytes.Bytes}
  RouteFailed{file: File, error: U32 & String}

# Computes enough transitions to visit blocks and stream their index pages.
def transition.budget.state(file: File, state: State) -> Nat & Reader:
  match state:
    case State{+size, header, +index_offset, used, total, +block_count,
        next_block, decoded, root_hash, index_hash, last_key, selected}:
      +blocks = U32.to_nat(block_count)
      +index_bytes = Nat.sub(size, Nat.add(index_offset, 44n))
      +page_bytes = BlockIndexPolicy.max_bytes()
      +pages = Nat.div(Nat.add(index_bytes, Nat.sub(page_bytes, 1n)), page_bytes)
      (Nat.add(Nat.add(Nat.mul(4n, blocks), Nat.mul(3n, pages)), 4n),
        Reader{file, State{size, header, index_offset, used, total, block_count,
          next_block, decoded, root_hash, index_hash, last_key, selected}})

# Returns the block traversal budget while preserving the owned reader.
def transition_budget(reader: Reader) -> Nat & Reader:
  match reader:
    case Reader{file, state}: transition.budget.state(file, state)

# Returns compact file metadata while preserving the owned reader.
def metadata(reader: Reader) -> Metadata & Reader:
  match reader:
    case Reader{file, state}:
      match state:
        case State{+size, header, +index_offset, used, +total,
            +block_count, next_block, decoded, root_hash, index_hash,
            last_key, selected}:
          (Metadata{size, total, block_count, index_offset, 0n, 0n},
            Reader{file, State{size, header, index_offset, used, total,
              block_count, next_block, decoded, root_hash, index_hash,
              last_key, selected}})

def bytes.slice.result(pair: Bytes.Bytes & Bytes.Bytes) -> Bytes.Bytes:
  match pair:
    case (_, bytes): bytes

def block.checksum.compare(
  comparison: Bytes.Bytes & Bytes.Bytes & Bool
) -> Bool:
  match comparison:
    case (_, _, valid): valid

def block.checksum.valid.copies(
  copies: Bytes.Bytes & Bytes.Bytes,
  +payload_length: U32
) -> Bool:
  match copies:
    case (for_hash, for_checksum):
      block.checksum.compare(Bytes.eq(
        SHA.sha256_packed_bytes(bytes.slice.result(Bytes.slice(for_hash, 0,
          U32.add(8, payload_length)))), bytes.slice.result(Bytes.slice(
          for_checksum, U32.add(8, payload_length), 32))))

def block.checksum.valid(
  block: Bytes.Bytes,
  +payload_length: U32
) -> Bool:
  block.checksum.valid.copies(ByteSstFile.clone.split(block), payload_length)

def read_at.exact.complete(
  bytes: Bytes.Bytes,
  lengths: Nat & Nat,
  needed: U32
) -> Result<&1, &1, U32 & String, SstStreamIo.ExactResult>:
  match lengths:
    case (actual, _):
      Done{SstStreamIo.ExactResult{bytes,
        U32.is_eq(U32.from_nat(actual), needed)}}

def read_at.exact.length(
  needed: U32,
  copies: Bytes.Bytes & Bytes.Bytes
) -> Result<&1, &1, U32 & String, SstStreamIo.ExactResult>:
  match copies:
    case (measured, retained):
      match measured:
        case Bytes.Bytes{len, _}:
          read_at.exact.complete(retained,
            QueuePolicy.nat.clone.pair(U32.to_nat(len)), needed)

def read_at.exact.bytes(
  needed: U32,
  result: Result<&1, &1, U32 & String, Bytes.Bytes>
) -> Result<&1, &1, U32 & String, SstStreamIo.ExactResult>:
  match result:
    case Fail{error}: Fail{error}
    case Done{bytes}:
      read_at.exact.length(needed, ByteSstFile.clone.split(bytes))

def read_at.exact.pair(
  needed: U32,
  pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>
) -> File & Result<&1, &1, U32 & String, SstStreamIo.ExactResult>:
  match pair:
    case (file, result): (file, read_at.exact.bytes(needed, result))

# Maps malformed SST content to the storage corruption domain.
def corruption(message: String) -> U32 & String:
  (4294967292, message)

# Identifies the explicit resident index budget failure to the public API.
def resource_limit_error_code() -> U32:
  RecoveryPolicy.resource_limit_error_code()

# Returns a typed host error for an index larger than the resident budget.
def resource_limit(message: String) -> U32 & String:
  (resource_limit_error_code(), message)

def codec.error(error: ByteSstFile.Error) -> U32 & String:
  match error:
    case ByteSstFile.ChecksumMismatch{}:
      corruption("byte SST checksum mismatch")
    case ByteSstFile.InvalidOrder{}:
      corruption("byte SST keys are not strictly ordered")
    case _:
      corruption("malformed byte SST")

def close.failed(
  file: File,
  error: U32 & String
) -> IO(Result<&1, &1, U32 & String, Step>):
  do IO<Result<&1, &1, U32 & String, Step>>:
    _closed : Unit <- File.close(file)
        return Fail{error}

def open.failed(
  file: File,
  error: U32 & String
) -> IO(Result<&1, &1, U32 & String, Reader>):
  do IO<Result<&1, &1, U32 & String, Reader>>:
    _closed : Unit <- File.close(file)
    return Fail{error}

def open.hash.index(
  file: File,
  +size: Nat,
  header: Bytes.Bytes,
  total: U32,
  block_count: U32,
  index_offset: Nat,
  root_hash: SHA.Stream,
  result: Result<&1, &1, SHA.StreamError, SHA.Stream>
) -> IO(Result<&1, &1, U32 & String, Reader>):
  match result:
    case Fail{_}:
      open.failed(file, resource_limit("SST metadata exceeds the SHA-256 input limit"))
    case Done{index_hash}:
      IO.pure(Result<&1, &1, U32 & String, Reader>, Done{Reader{file,
        State{size, header, index_offset, 0n, total, block_count, 0, 0,
          root_hash, index_hash, None{}, False{}}}})

def open.hash.root(
  file: File,
  +size: Nat,
  header: Bytes.Bytes,
  total: U32,
  counts: Nat & Nat,
  index_offset: Nat,
  result: Result<&1, &1, SHA.StreamError, SHA.Stream>
) -> IO(Result<&1, &1, U32 & String, Reader>):
  match counts:
    case (for_reader, for_prefix):
      match result:
        case Fail{_}:
          open.failed(file, resource_limit("SST metadata exceeds the SHA-256 input limit"))
        case Done{root_hash}:
          open.hash.index(file, size, header, total, U32.from_nat(for_reader),
            index_offset, root_hash,
            SHA.stream.update(SHA.stream.initial(), Bytes.concat([
              ByteSstFile.index.magic(),
              ByteSstFile.u32.bytes(U32.from_nat(for_prefix))])))

def open.hash.header(
  file: File,
  +size: Nat,
  copies: Bytes.Bytes & Bytes.Bytes,
  total: U32,
  block_count: U32,
  index_offset: Nat
) -> IO(Result<&1, &1, U32 & String, Reader>):
  match copies:
    case (header, for_hash):
      open.hash.root(file, size, header, total,
        QueuePolicy.nat.clone.pair(U32.to_nat(block_count)), index_offset,
        SHA.stream.update(SHA.stream.initial(), for_hash))

def open.hashes(
  file: File,
  +size: Nat,
  header: Bytes.Bytes,
  total: U32,
  block_count: U32,
  index_offset: Nat
) -> IO(Result<&1, &1, U32 & String, Reader>):
  open.hash.header(file, size, ByteSstFile.clone.split(header), total,
    block_count, index_offset)

def open.header.index(
  file: File,
  +size: Nat,
  header: Bytes.Bytes,
  total: U32,
  block_count: U32,
  index_offset: Nat,
  valid: Bool
) -> IO(Result<&1, &1, U32 & String, Reader>):
  match valid:
    case False{}:
      open.failed(file, corruption("byte SST index exceeds file bounds"))
    case True{}:
      open.hashes(file, size, header, total, block_count, index_offset)

def open.header.index.length.decoded(
  file: File,
  +size: Nat,
  header: Bytes.Bytes,
  total: U32,
  block_count: U32,
  +block_count_nat: U32,
  result: Bytes.Bytes & Maybe<&2, U32>
) -> IO(Result<&1, &1, U32 & String, Reader>):
  match result:
    case (_, Some{index_length_word}):
      +index_length = U32.to_nat(index_length_word)
      +blocks = U32.to_nat(block_count_nat)
      +minimum_index_length = Nat.add(8n, Nat.mul(blocks, 16n))
      +index_size = Nat.add(44n, index_length)
      +index_offset = Nat.sub(size, index_size)
      open.header.index(file, size, header, total, block_count,
        index_offset,
        Nat.is_le(minimum_index_length, index_length) &&
          Nat.is_le(index_size, size) && Nat.is_le(20n, index_offset))
    case (_, None{}):
      open.failed(file, corruption("byte SST footer has no index length"))

def open.header.index.length.bytes(
  file: File,
  +size: Nat,
  header: Bytes.Bytes,
  total: U32,
  block_count: U32,
  block_count_nat: U32,
  result: Result<&1, &1, U32 & String, Bytes.Bytes>
) -> IO(Result<&1, &1, U32 & String, Reader>):
  match result:
    case Fail{error}: open.failed(file, error)
    case Done{bytes}:
      open.header.index.length.decoded(file, size, header, total,
        block_count, block_count_nat, Bytes.get.u32be(bytes, 0))

def open.header.index.length.exact(
  pair: File & Result<&1, &1, U32 & String, SstStreamIo.ExactResult>,
  +size: Nat,
  header: Bytes.Bytes,
  total: U32,
  block_count: U32,
  block_count_nat: U32
) -> IO(Result<&1, &1, U32 & String, Reader>):
  match pair:
    case (file, Fail{error}): open.failed(file, error)
    case (file, Done{SstStreamIo.ExactResult{bytes, complete}}):
      match complete:
        case True{}:
          open.header.index.length.bytes(file, size, header, total,
            block_count, block_count_nat, Done{bytes})
        case False{}:
          open.failed(file, corruption("truncated byte SST footer index length"))

def open.header.index.counts(
  file: File,
  +size: Nat,
  header: Bytes.Bytes,
  total: U32,
  counts: Nat & Nat
) -> IO(Result<&1, &1, U32 & String, Reader>):
  match counts:
    case (for_offset, for_reader):
      do IO<Result<&1, &1, U32 & String, Reader>>:
        footer_length : File & Result<&1, &1, U32 & String, Bytes.Bytes> <-
          Fs.read_at(file, U32.from_nat(Nat.sub(size, 36n)), 4)
        open.header.index.length.exact(
          read_at.exact.pair(4, footer_length), size, header, total,
          U32.from_nat(for_reader), U32.from_nat(for_offset))

def open.header.valid(
  file: File,
  +size: Nat,
  header: Bytes.Bytes,
  total: U32,
  block_count: U32,
  size_valid: Bool
) -> IO(Result<&1, &1, U32 & String, Reader>):
  match size_valid:
    case False{}:
      open.failed(file, corruption("byte SST exceeds reader metadata bounds"))
    case True{}:
      open.header.index.counts(file, size, header, total,
        QueuePolicy.nat.clone.pair(U32.to_nat(block_count)))

def open.header.parsed(
  file: File,
  +size: Nat,
  result: Result<&1, &1, ByteSstFile.Error, ByteSstFile.MultiHeader>
) -> IO(Result<&1, &1, U32 & String, Reader>):
  match result:
    case Fail{error}:
      open.failed(file, codec.error(error))
    case Done{ByteSstFile.MultiHeader{header, _, total, +block_count}}:
      open.header.valid(file, size, header, total, block_count,
        Nat.is_le(20n, size) && Nat.is_le(size, 4294967295n))

def open.header.result(
  file: File,
  +size: Nat,
  result: Result<&1, &1, U32 & String, Bytes.Bytes>
) -> IO(Result<&1, &1, U32 & String, Reader>):
  match result:
    case Fail{error}:
      open.failed(file, error)
    case Done{header}:
      open.header.parsed(file, size, ByteSstFile.parse_stream_header(header))

def open.header.read(
  +size: Nat,
  pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>
) -> IO(Result<&1, &1, U32 & String, Reader>):
  match pair:
    case (file, result):
      open.header.result(file, size, result)

def open.header.pair(
  +size: Nat,
  pair: File & Result<&1, &1, U32 & String, SstStreamIo.ExactResult>
) -> IO(Result<&1, &1, U32 & String, Reader>):
  open.header.read(size, SstStreamIo.read.exact.state(pair))

def open.file(
  +size: Nat,
  opened: Result<&1, &1, U32 & String, File>
) -> IO(Result<&1, &1, U32 & String, Reader>):
  match opened:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Reader>, Fail{error})
    case Done{file}:
      do IO<Result<&1, &1, U32 & String, Reader>>:
        pair : File & Result<&1, &1, U32 & String, SstStreamIo.ExactResult> <-
          SstStreamIo.exact.start(file, 20n)
        open.header.pair(size, pair)

def open.sized.valid(
  +path: String,
  +size: Nat,
  valid: Bool
) -> IO(Result<&1, &1, U32 & String, Reader>):
  match valid:
    case False{}:
      IO.pure(Result<&1, &1, U32 & String, Reader>,
        Fail{corruption("byte SST is truncated")})
    case True{}:
      do IO<Result<&1, &1, U32 & String, Reader>>:
        opened : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
        open.file(size, opened)


def open.sized(
  +path: String,
  result: Result<&1, &1, U32 & String, Nat>
) -> IO(Result<&1, &1, U32 & String, Reader>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Reader>, Fail{error})
    case Done{+size}:
      open.sized.valid(path, size, Nat.is_le(60n, size))
# Opens a generation-four SST and validates its bounded header metadata.
def open(+path: String) -> IO(Result<&1, &1, U32 & String, Reader>):
  do IO<Result<&1, &1, U32 & String, Reader>>:
    size : Result<&1, &1, U32 & String, Nat> <- Fs.file_size(path)
    open.sized(path, size)

def seek.block.invalid(file: File) -> IO(Result<&1, &1, U32 & String, Reader>):
  do IO<Result<&1, &1, U32 & String, Reader>>:
    _closed : Unit <- File.close(file)
    return Fail{corruption("byte SST block index is outside the file")}

def seek.block.construct(
  file: File,
  size: Nat,
  header: Bytes.Bytes,
  index_offset: Nat,
  total: U32,
  block_count: U32,
  root_hash: SHA.Stream,
  index_hash: SHA.Stream,
  index: U32,
  offset: U32,
  valid: Bool
) -> IO(Result<&1, &1, U32 & String, Reader>):
  match valid:
    case False{}: seek.block.invalid(file)
    case True{}:
      IO.pure(Result<&1, &1, U32 & String, Reader>,
        Done{Reader{file, State{size, header, index_offset,
          Nat.sub(U32.to_nat(offset), 20n), total, block_count, index, 0,
          root_hash, index_hash, None{}, True{}}}})

def seek.block.ready(
  file: File,
  state: State,
  index: U32,
  offset: U32,
  valid: Bool
) -> IO(Result<&1, &1, U32 & String, Reader>):
  match state:
    case State{size, header, index_offset, _, total, block_count, _, _,
        root_hash, index_hash, _, _}:
      seek.block.construct(file, size, header, index_offset, total,
        block_count, root_hash, index_hash, index, offset, valid)

def seek.block.decoded.offsets(
  state: State,
  index: U32,
  file: File,
  index_offset: Nat,
  offsets: Maybe<&2, U32> & Maybe<&2, U32>
) -> IO(Result<&1, &1, U32 & String, Reader>):
  match offsets:
    case (Some{+offset}, Some{length}):
      seek.block.ready(file, state, index, offset,
        BlockIndexPolicy.entry_valid(U32.to_nat(offset),
          U32.to_nat(length), index_offset))
    case _:
      seek.block.invalid(file)

def seek.block.decoded(
  state: State,
  index: U32,
  file: File,
  offsets: Maybe<&2, U32> & Maybe<&2, U32>
) -> IO(Result<&1, &1, U32 & String, Reader>):
  match state:
    case State{_, _, +index_offset, _, _, _, _, _, _, _, _, _}:
      seek.block.decoded.offsets(state, index, file, index_offset, offsets)

def seek.block.word(pair: Bytes.Bytes & Maybe<&2, U32>) -> Maybe<&2, U32>:
  match pair:
    case (_, value): value

def seek.block.words.copies(
  pair: Bytes.Bytes & Bytes.Bytes
) -> Maybe<&2, U32> & Maybe<&2, U32>:
  match pair:
    case (offset, length):
      (seek.block.word(Bytes.get.u32be(offset, 0)),
        seek.block.word(Bytes.get.u32be(length, 4)))

def seek.block.words(bytes: Bytes.Bytes) -> Maybe<&2, U32> & Maybe<&2, U32>:
  seek.block.words.copies(ByteSstFile.clone.split(bytes))

def seek.block.read(
  state: State,
  index: U32,
  pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>
) -> IO(Result<&1, &1, U32 & String, Reader>):
  match pair:
    case (file, Fail{_}): seek.block.invalid(file)
    case (file, Done{bytes}):
      seek.block.decoded(state, index, file, seek.block.words(bytes))

def seek.block.indices.triple.result(pair: Nat & Nat & Nat) -> U32 & U32 & U32:
  match pair:
    case (first, second, third):
      (U32.from_nat(first), U32.from_nat(second), U32.from_nat(third))

def seek.block.indices.triple(value: U32) -> U32 & U32 & U32:
  seek.block.indices.triple.result(Fs.read_at.nat.clone.triple(U32.to_nat(value)))

def seek.block.indices.quad.first(
  firsts: Nat & Nat,
  second: Nat,
  third: Nat
) -> U32 & (U32 & (U32 & U32)):
  match firsts:
    case (first, first_copy):
      (U32.from_nat(first), (U32.from_nat(first_copy),
        (U32.from_nat(second), U32.from_nat(third))))

def seek.block.indices.quad.result(
  triple: Nat & Nat & Nat
) -> U32 & (U32 & (U32 & U32)):
  match triple:
    case (first, second, third):
      seek.block.indices.quad.first(QueuePolicy.nat.clone.pair(first),
        second, third)

def seek.block.indices.quad(value: U32) -> U32 & (U32 & (U32 & U32)):
  seek.block.indices.quad.result(Fs.read_at.nat.clone.triple(U32.to_nat(value)))

def seek.block.u32.clone.pair.result(pair: Nat & Nat) -> U32 & U32:
  match pair:
    case (first, second): (U32.from_nat(first), U32.from_nat(second))

def seek.block.u32.clone.pair(value: U32) -> U32 & U32:
  seek.block.u32.clone.pair.result(QueuePolicy.nat.clone.pair(U32.to_nat(value)))

def seek.block.index.read(
  file: File,
  state: State,
  index_offset: Nat,
  indices: U32 & U32
) -> IO(Result<&1, &1, U32 & String, Reader>):
  match indices:
    case (address_index, read_index):
      do IO<Result<&1, &1, U32 & String, Reader>>:
        pair : File & Result<&1, &1, U32 & String, Bytes.Bytes> <-
          Fs.read_at(file, U32.from_nat(Nat.add(index_offset,
            Nat.add(8n, Nat.mul(U32.to_nat(address_index), 16n)))), 8)
        exact : File & Result<&1, &1, U32 & String, SstStreamIo.ExactResult> =
          read_at.exact.pair(8, pair)
        seek.block.read(state, read_index, SstStreamIo.read.exact.state(exact))

def seek.block.offsets(
  file: File,
  size: Nat,
  header: Bytes.Bytes,
  offsets: Nat & Nat,
  total: U32,
  block_count: U32,
  root_hash: SHA.Stream,
  index_hash: SHA.Stream,
  indices: U32 & U32 & U32,
  valid: Bool
) -> IO(Result<&1, &1, U32 & String, Reader>):
  match offsets:
    case (state_offset, read_offset):
      match indices:
        case (state_index, (address_index, read_index)):
          match valid:
            case False{}: seek.block.invalid(file)
            case True{}:
              seek.block.index.read(file,
                State{size, header, state_offset, 0n, total, block_count,
                  state_index, 0, root_hash, index_hash, None{}, True{}},
                read_offset, (address_index, read_index))

def seek.block.validated(
  file: File,
  size: Nat,
  header: Bytes.Bytes,
  index_offset: Nat,
  total: U32,
  block_count: U32,
  root_hash: SHA.Stream,
  index_hash: SHA.Stream,
  indices: U32 & U32 & U32,
  valid: Bool
) -> IO(Result<&1, &1, U32 & String, Reader>):
  seek.block.offsets(file, size, header, QueuePolicy.nat.clone.pair(index_offset),
    total, block_count, root_hash, index_hash, indices, valid)

def seek.block.checked.bounds(
  file: File,
  size: Nat,
  header: Bytes.Bytes,
  index_offset: Nat,
  total: U32,
  block_counts: U32 & U32,
  root_hash: SHA.Stream,
  index_hash: SHA.Stream,
  indices: U32 & (U32 & (U32 & U32))
) -> IO(Result<&1, &1, U32 & String, Reader>):
  match block_counts:
    case (result_count, check_count):
      match indices:
        case (compare_index, (state_index, (address_index, read_index))):
          seek.block.validated(file, size, header, index_offset, total,
            result_count, root_hash, index_hash,
            (state_index, (address_index, read_index)),
            BlockIndexPolicy.contains(U32.to_nat(check_count),
              U32.to_nat(compare_index)))

def seek.block.checked.indices.ready(
  file: File,
  size: Nat,
  header: Bytes.Bytes,
  index_offset: Nat,
  total: U32,
  root_hash: SHA.Stream,
  index_hash: SHA.Stream,
  indices: U32 & (U32 & (U32 & U32)),
  block_count: U32
) -> IO(Result<&1, &1, U32 & String, Reader>):
  match indices:
    case (compare_index, (state_index, (address_index, read_index))):
      seek.block.checked.bounds(file, size, header, index_offset, total,
        seek.block.u32.clone.pair(block_count), root_hash, index_hash,
        (compare_index, (state_index, (address_index, read_index))))

def seek.block.checked.indices(
  file: File,
  size: Nat,
  header: Bytes.Bytes,
  index_offset: Nat,
  total: U32,
  block_count: U32,
  root_hash: SHA.Stream,
  index_hash: SHA.Stream,
  indices: U32 & (U32 & (U32 & U32))
) -> IO(Result<&1, &1, U32 & String, Reader>):
  match block_count:
    case _:
      seek.block.checked.indices.ready(file, size, header, index_offset,
        total, root_hash, index_hash, indices, block_count)

def seek.block.checked(
  file: File,
  state: State,
  indices: U32 & (U32 & (U32 & U32))
) -> IO(Result<&1, &1, U32 & String, Reader>):
  match state:
    case State{size, header, index_offset, _, total, block_count, _, _,
        root_hash, index_hash, _, _}:
      seek.block.checked.indices(file, size, header, index_offset, total,
        block_count, root_hash, index_hash, indices)

# Positions within an SST whose complete index and root were validated by an earlier pass.
def seek_block_after_validation(
  reader: Reader,
  index: U32
) -> IO(Result<&1, &1, U32 & String, Reader>):
  match reader:
    case Reader{file, state}:
      seek.block.checked(file, state, seek.block.indices.quad(index))

# Closes the file owned by a reader that has not reached its terminal state.
def close(reader: Reader) -> IO(Result<&1, &1, U32 & String, Unit>):
  match reader:
    case Reader{file, _}:
      do IO<Result<&1, &1, U32 & String, Unit>>:
        _closed : Unit <- File.close(file)
        return Done{Unit{}}

def route.close.failed(
  file: File,
  error: U32 & String
) -> IO(Result<&1, &1, U32 & String, Reader>):
  do IO<Result<&1, &1, U32 & String, Reader>>:
    _closed : Unit <- File.close(file)
    return Fail{error}

def route.index.error(file: File) -> IO(Result<&1, &1, U32 & String, Reader>):
  route.close.failed(file, corruption("invalid byte SST separator metadata"))

def route.record.bounds(
  file: File,
  state: State,
  +context: RouteContext,
  key: Bytes.Bytes,
  +search: BlockRoutePolicy.Search,
  mid: Nat,
  +offset: U32,
  +length: U32,
  separator_start: Nat,
  valid: Bool
) -> RouteState:
  match valid:
    case True{}:
      RouteSeparatorNeed{file, state, context, key, search, mid,
        U32.to_nat(offset), length, separator_start}
    case False{}:
      RouteFailed{file, corruption("byte SST separator exceeds the index region")}

def route.record.words(
  file: File,
  state: State,
  context: RouteContext,
  key: Bytes.Bytes,
  search: BlockRoutePolicy.Search,
  mid: Nat,
  words: Maybe<&2, U32> & Maybe<&2, U32>
) -> RouteState:
  match context:
    case RouteContext{+size, +index_offset, +block_count}:
      match words:
        case (Some{+offset}, Some{+length}):
          +index_length = Nat.sub(size, Nat.add(index_offset, 44n))
          +fixed_bytes = Nat.add(8n, Nat.mul(block_count, 16n))
          +region_length = Nat.sub(index_length, fixed_bytes)
          +separator_start = Nat.add(index_offset, fixed_bytes)
          route.record.bounds(file, state, context, key, search, mid,
            offset, length, separator_start,
            BlockIndexFormatPolicy.separator_valid(U32.to_nat(offset),
              U32.to_nat(length), region_length) &&
              U32.is_le(length, StorageBytes.MAX_BLOCK_BYTES()))
        case _:
          RouteFailed{file, corruption("byte SST separator fields are missing")}

def route.record.slice(
  file: File,
  state: State,
  context: RouteContext,
  key: Bytes.Bytes,
  search: BlockRoutePolicy.Search,
  mid: Nat,
  pair: Bytes.Bytes & Bytes.Bytes
) -> RouteState:
  match pair:
    case (_, metadata):
      route.record.words(file, state, context, key, search, mid,
        seek.block.words(metadata))

def route.record.parsed(
  state: State,
  context: RouteContext,
  key: Bytes.Bytes,
  search: BlockRoutePolicy.Search,
  mid: Nat,
  pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>
) -> RouteState:
  match pair:
    case (file, Fail{error}): RouteFailed{file, error}
    case (file, Done{record}):
      route.record.slice(file, state, context, key, search, mid,
        Bytes.slice(record, 8, 8))

def route.separator.parsed(
  state: State,
  context: RouteContext,
  key: Bytes.Bytes,
  search: BlockRoutePolicy.Search,
  mid: Nat,
  pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>
) -> RouteState:
  match pair:
    case (file, Fail{error}): RouteFailed{file, error}
    case (file, Done{separator}):
      RouteCompare{file, state, context, key, search, mid, separator}

def route.compare.copies(
  file: File,
  state: State,
  context: RouteContext,
  search: BlockRoutePolicy.Search,
  mid: Nat,
  separator: Bytes.Bytes,
  copies: Bytes.Bytes & Bytes.Bytes
) -> RouteState:
  match copies:
    case (target, retained):
      RouteNeed{file, state, context, retained,
        BlockRoutePolicy.advance(search,
          BlockRoutePolicy.move(target, separator), mid)}

def route.exhausted(state: RouteState) -> IO(Result<&1, &1, U32 & String, Reader>):
  match state:
    case RouteNeed{file, _, _, _, _}:
      route.close.failed(file, resource_limit("SST key seek budget exhausted"))
    case RouteSelect{reader, _}:
      match reader:
        case Reader{file, _}:
          route.close.failed(file,
            resource_limit("SST key seek budget exhausted"))
    case RouteRecordRead{pair, _, _, _, _, _}:
      match pair:
        case (file, _):
          route.close.failed(file, resource_limit("SST key seek budget exhausted"))
    case RouteSeparatorNeed{file, _, _, _, _, _, _, _, _}:
      route.close.failed(file, resource_limit("SST key seek budget exhausted"))
    case RouteSeparatorRead{pair, _, _, _, _, _}:
      match pair:
        case (file, _):
          route.close.failed(file, resource_limit("SST key seek budget exhausted"))
    case RouteCompare{file, _, _, _, _, _, _}:
      route.close.failed(file, resource_limit("SST key seek budget exhausted"))
    case RouteFailed{file, error}: route.close.failed(file, error)

def route.midpoint(search: BlockRoutePolicy.Search) -> Nat:
  match search:
    case BlockRoutePolicy.Search{low, high, _}:
      BlockRoutePolicy.midpoint(low, high)

def route.need(
  file: File,
  state: State,
  +context: RouteContext,
  key: Bytes.Bytes,
  +search: BlockRoutePolicy.Search,
  active: Bool
) -> IO(RouteState):
  match context:
    case RouteContext{_, index_offset, _}:
      match active:
        case False{}:
          IO.pure(RouteState, RouteSelect{Reader{file, state},
            BlockRoutePolicy.selected_block(search)})
        case True{}:
          +mid = route.midpoint(search)
          do IO<RouteState>:
            raw : File & Result<&1, &1, U32 & String, Bytes.Bytes> <-
              Fs.read_at(file, U32.from_nat(Nat.add(index_offset,
                Nat.add(8n, Nat.mul(mid, 16n)))), 16)
            return RouteRecordRead{
              read_at.exact.pair(16, raw), state, context, key, search, mid}

def route.loop(fuel: Nat, pending: RouteState) -> IO(Result<&1, &1, U32 & String, Reader>):
  match fuel:
    case 0n: route.exhausted(pending)
    case 1n+rest:
      match pending:
        case RouteNeed{file, state, context, key, +search}:
          do IO<Result<&1, &1, U32 & String, Reader>>:
            next : RouteState <- route.need(file, state, context, key, search,
              BlockRoutePolicy.active(search))
            route.loop(rest, next)
        case RouteSelect{reader, block}:
          seek_block_after_validation(reader, U32.from_nat(block))
        case RouteRecordRead{pair, state, context, key, search, mid}:
          route.loop(rest, route.record.parsed(state, context, key, search,
            mid, SstStreamIo.read.exact.state(pair)))
        case RouteSeparatorNeed{file, state, context, key, search, mid,
            offset, +length, separator_start}:
          do IO<Result<&1, &1, U32 & String, Reader>>:
            raw : File & Result<&1, &1, U32 & String, Bytes.Bytes> <-
              Fs.read_at(file, U32.from_nat(Nat.add(separator_start, offset)),
                length)
            route.loop(rest, RouteSeparatorRead{
              read_at.exact.pair(length, raw), state, context, key, search,
              mid})
        case RouteSeparatorRead{pair, state, context, key, search, mid}:
          route.loop(rest, route.separator.parsed(state, context, key,
            search, mid, SstStreamIo.read.exact.state(pair)))
        case RouteCompare{file, state, context, key, search, mid, separator}:
          route.loop(rest, route.compare.copies(file, state, context, search,
            mid, separator, ByteMemTable.bytes.clone(key)))
        case RouteFailed{file, error}: route.close.failed(file, error)

# Routes a lower key to the last block whose separator does not exceed it.
def seek_key_after_validation(
  reader: Reader,
  key: Bytes.Bytes
) -> IO(Result<&1, &1, U32 & String, Reader>):
  match reader:
    case Reader{file, state}:
      match state:
        case State{+size, header, +index_offset, used, total,
            +block_count, next_block, decoded, root_hash, index_hash,
            last_key, selected}:
          +count = U32.to_nat(block_count)
          +fuel = Nat.add(Nat.mul(8n, count), 8n)
          context : RouteContext = RouteContext{size, index_offset, count}
          retained_state : State = State{size, header, index_offset, used, total, block_count,
            next_block, decoded, root_hash, index_hash, last_key, selected}
          route.loop(fuel, RouteNeed{file, retained_state, context, key,
            BlockRoutePolicy.Search{0n, count, 0n}})

def next.body.output.index.hash(
  file: File,
  +size: Nat,
  header: Bytes.Bytes,
  +index_offset: Nat,
  +next_used: Nat,
  total: U32,
  block_count: U32,
  next_number: U32,
  next_decoded: U32,
  last_key: Maybe<&1, Bytes.Bytes>,
  entries: List<&1, ByteMemTable.Entry>,
  root_hash: SHA.Stream,
  index_hash: SHA.Stream,
  selected: Bool
) -> IO(Result<&1, &1, U32 & String, Step>):
  IO.pure(Result<&1, &1, U32 & String, Step>,
    Done{Block{Reader{file, State{size, header, index_offset, next_used,
      total, block_count, next_number, next_decoded, root_hash, index_hash,
      last_key, selected}}, entries}})



def next.body.output.hash.results(
  file: File,
  +size: Nat,
  header: Bytes.Bytes,
  +index_offset: Nat,
  +next_used: Nat,
  total: U32,
  block_count: U32,
  next_number: U32,
  next_decoded: U32,
  last_key: Maybe<&1, Bytes.Bytes>,
  entries: List<&1, ByteMemTable.Entry>,
  root_result: Result<&1, &1, SHA.StreamError, SHA.Stream>,
  index_hash: SHA.Stream,
  selected: Bool
) -> IO(Result<&1, &1, U32 & String, Step>):
  match root_result:
    case Fail{_}:
      close.failed(file, resource_limit("SST root hash exceeds the SHA-256 input limit"))
    case Done{root_hash}:
      next.body.output.index.hash(file, size, header, index_offset,
        next_used, total, block_count, next_number, next_decoded,
        last_key, entries, root_hash, index_hash, selected)


def next.body.output.hashes(
  file: File,
  +size: Nat,
  header: Bytes.Bytes,
  +index_offset: Nat,
  +next_used: Nat,
  total: U32,
  block_count: U32,
  next_number: U32,
  next_decoded: U32,
  last_key: Maybe<&1, Bytes.Bytes>,
  entries: List<&1, ByteMemTable.Entry>,
  checksum: Bytes.Bytes,
  root_hash: SHA.Stream,
  index_hash: SHA.Stream,
  selected: Bool
) -> IO(Result<&1, &1, U32 & String, Step>):
  next.body.output.hash.results(file, size, header, index_offset,
    next_used, total, block_count, next_number, next_decoded,
    last_key, entries, SHA.stream.update(root_hash, checksum),
    index_hash, selected)

def next.body.output.count(
  file: File,
  +size: Nat,
  header: Bytes.Bytes,
  +index_offset: Nat,
  +used: Nat,
  total: U32,
  block_count: U32,
  next_block: U32,
  decoded: U32,
  root_hash: SHA.Stream,
  index_hash: SHA.Stream,
  block_bytes: Bytes.Bytes,
  +payload_length: U32,
  entry_count: U32,
  entries: List<&1, ByteMemTable.Entry>,
  last_key: Maybe<&1, Bytes.Bytes>,
  valid: Bool,
  selected: Bool
) -> IO(Result<&1, &1, U32 & String, Step>):
  match valid:
    case False{}:
      close.failed(file, corruption("byte SST keys are not strictly ordered"))
    case True{}:
      +block_length = U32.add(40, payload_length)
      +checksum_offset = U32.add(8, payload_length)
      block_checksum = bytes.slice.result(Bytes.slice(block_bytes,
        checksum_offset, 32))
      +next_used = Nat.add(used, U32.to_nat(block_length))
      +next_decoded = U32.add(decoded, entry_count)
      +next_number = U32.add(next_block, 1)
      next.body.output.hashes(file, size, header, index_offset, next_used,
        total, block_count, next_number, next_decoded, last_key, entries,
        block_checksum, root_hash, index_hash, selected)

def next.body.output.order(
  file: File,
  +size: Nat,
  header: Bytes.Bytes,
  +index_offset: Nat,
  +used: Nat,
  total: U32,
  block_count: U32,
  next_block: U32,
  decoded: U32,
  root_hash: SHA.Stream,
  index_hash: SHA.Stream,
  block_bytes: Bytes.Bytes,
  +payload_length: U32,
  raw_count: Nat,
  entries: List<&1, ByteMemTable.Entry>,
  order: BlockOrder.State,
  selected: Bool
) -> IO(Result<&1, &1, U32 & String, Step>):
  match order:
    case BlockOrder.State{valid, last_key, +count}:
      next.body.output.count(file, size, header, index_offset, used, total,
        block_count, next_block, decoded,
        root_hash, index_hash,
        block_bytes, payload_length, U32.from_nat(count), entries, last_key,
        valid && Nat.is_eq(raw_count, count), selected)

def next.body.output(
  file: File,
  state: State,
  block_bytes: Bytes.Bytes,
  +payload_length: U32,
  raw_count: Nat,
  copies: List<&1, ByteMemTable.Entry> & List<&1, ByteMemTable.Entry>
) -> IO(Result<&1, &1, U32 & String, Step>):
  match state:
    case State{+size, header, +index_offset, +used, total, block_count,
        next_block, decoded, root_hash, index_hash, last_key, selected}:
      match copies:
        case (for_order, retained):
          next.body.output.order(file, size, header, index_offset, used,
            total, block_count, next_block, decoded,
            root_hash, index_hash,
            block_bytes, payload_length, raw_count, retained,
            BlockOrder.go(for_order, BlockOrder.empty(last_key)), selected)

def next.body.ordered(
  file: File,
  state: State,
  block_bytes: Bytes.Bytes,
  +payload_length: U32,
  measured: List<&1, ByteMemTable.Entry> & Nat
) -> IO(Result<&1, &1, U32 & String, Step>):
  match measured:
    case (entries, raw_count):
      next.body.output(file, state, block_bytes, payload_length, raw_count,
        ByteMemTable.entries.clone(ByteMemTable.ordered_entries(
          ByteMemTable.Table{entries})))

def next.body.parsed(
  file: File,
  state: State,
  block_bytes: Bytes.Bytes,
  +payload_length: U32,
  valid_checksum: Bool,
  result: Result<&1, &1, ByteSstFile.Error, ByteMemTable.Table>
) -> IO(Result<&1, &1, U32 & String, Step>):
  match valid_checksum:
    case False{}:
      close.failed(file, corruption("byte SST block checksum mismatch"))
    case True{}:
      match result:
        case Fail{error}:
          close.failed(file, codec.error(error))
        case Done{ByteMemTable.Table{entries}}:
          next.body.ordered(file, state, block_bytes, payload_length,
            ByteMemTable.count.keep(entries))

def next.body.copies.checked(
  file: File,
  state: State,
  block_bytes: Bytes.Bytes,
  +payload_length: U32,
  copies: Bytes.Bytes & Bytes.Bytes
) -> IO(Result<&1, &1, U32 & String, Step>):
  match copies:
    case (for_checksum, for_parser):
      next.body.parsed(file, state, block_bytes, payload_length,
        block.checksum.valid(for_checksum, payload_length),
        ByteSstFile.parse_block(for_parser))

def next.body.copies(
  file: File,
  state: State,
  +payload_length: U32,
  copies: Bytes.Bytes & Bytes.Bytes
) -> IO(Result<&1, &1, U32 & String, Step>):
  match copies:
    case (for_parse, retained):
      next.body.copies.checked(file, state, retained, payload_length,
        ByteSstFile.clone.split(for_parse))

def next.body.exact(
  context: BodyContext,
  pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>
) -> IO(Result<&1, &1, U32 & String, Step>):
  match context:
    case BodyContext{state, block_header, +payload_length}:
      match pair:
        case (read_file, Fail{error}):
          close.failed(read_file, error)
        case (read_file, Done{body}):
          next.body.copies(read_file, state, payload_length,
            ByteSstFile.clone.split(Bytes.concat([block_header, body])))

def next.body.result(
  context: BodyContext,
  pair: File & Result<&1, &1, U32 & String, SstStreamIo.ExactResult>
) -> IO(Result<&1, &1, U32 & String, Step>):
  match context:
    case BodyContext{state, block_header, +payload_length}:
      match pair:
        case (file, result):
          next.body.exact(BodyContext{state, block_header, payload_length},
            SstStreamIo.read.exact.state((file, result)))

def next.body.valid(
  file: File,
  state: State,
  block_header: Bytes.Bytes,
  +used: Nat,
  +payload_length: U32,
  valid: Bool
) -> IO(Result<&1, &1, U32 & String, Step>):
  match valid:
    case False{}:
      close.failed(file, corruption("byte SST block exceeds file bounds"))
    case True{}:
      do IO<Result<&1, &1, U32 & String, Step>>:
        raw : File & Result<&1, &1, U32 & String, Bytes.Bytes> <-
          Fs.read_at(file,
            U32.from_nat(Nat.add(Nat.add(20n, used), 8n)),
            U32.add(payload_length, 32))
        next.body.result(BodyContext{state, block_header, payload_length},
          read_at.exact.pair(U32.add(payload_length, 32), raw))

def next.block.length.state(
  file: File,
  state: State,
  block_header: Bytes.Bytes,
  +payload_length: U32
) -> IO(Result<&1, &1, U32 & String, Step>):
  match state:
    case State{_, _, +index_offset, +used, _, _, _, _, _, _, _, _}:
      next.body.valid(file, state, block_header, used, payload_length,
        U32.is_le(payload_length, StorageBytes.MAX_BLOCK_BYTES()) &&
          Nat.is_le(Nat.add(used,
            U32.to_nat(U32.add(payload_length, 40))), index_offset))



def next.block.length(
  file: File,
  state: State,
  block_header: Bytes.Bytes,
  result: Bytes.Bytes & Maybe<&2, U32>
) -> IO(Result<&1, &1, U32 & String, Step>):
  match result:
    case (_, None{}):
      close.failed(file, corruption("invalid byte SST block length"))
    case (_, Some{payload_length}):
      next.block.length.state(file, state, block_header, payload_length)
def next.block.header.copies(
  file: File,
  state: State,
  copies: Bytes.Bytes & Bytes.Bytes
) -> IO(Result<&1, &1, U32 & String, Step>):
  match copies:
    case (for_length, retained):
      next.block.length(file, state, retained, Bytes.get.u32be(for_length, 0))

def next.block.header(
  file: File,
  state: State,
  result: Result<&1, &1, U32 & String, Bytes.Bytes>
) -> IO(Result<&1, &1, U32 & String, Step>):
  match result:
    case Fail{error}:
      close.failed(file, error)
    case Done{block_header}:
      next.block.header.copies(file, state,
        ByteSstFile.clone.split(block_header))
def next.block.header.bytes(
  state: State,
  pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>
) -> IO(Result<&1, &1, U32 & String, Step>):
  match pair:
    case (file, result):
      next.block.header(file, state, result)

def next.block.header.pair(
  state: State,
  pair: File & Result<&1, &1, U32 & String, SstStreamIo.ExactResult>
) -> IO(Result<&1, &1, U32 & String, Step>):
  next.block.header.bytes(state, SstStreamIo.read.exact.state(pair))


def next.block.read(
  file: File,
  state: State
) -> IO(Result<&1, &1, U32 & String, Step>):
  match state:
    case State{_, _, _, +used, _, _, _, _, _, _, _, _}:
      do IO<Result<&1, &1, U32 & String, Step>>:
        raw : File & Result<&1, &1, U32 & String, Bytes.Bytes> <-
          Fs.read_at(file, U32.from_nat(Nat.add(20n, used)), 8)
        next.block.header.pair(state, read_at.exact.pair(8, raw))

def next.trailer.finish.footer(
  file: File,
  _footer: Bytes.Bytes,
  _expected: Bytes.Bytes,
  valid: Bool
) -> IO(Result<&1, &1, U32 & String, Step>):
  match valid:
    case False{}:
      close.failed(file, corruption("byte SST root checksum mismatch"))
    case True{}:
      do IO<Result<&1, &1, U32 & String, Step>>:
        _closed : Unit <- File.close(file)
        return Done{End{}}

def next.trailer.finish.root.compare.footer(
  file: File,
  footers: Bytes.Bytes & Bytes.Bytes,
  expected: Bytes.Bytes,
  for_compare: Bytes.Bytes
) -> IO(Result<&1, &1, U32 & String, Step>):
  match footers:
    case (for_result, footer):
      next.trailer.finish.footer(file, for_result, expected,
        block.checksum.compare(Bytes.eq(footer, for_compare)))



def next.trailer.finish.root.compare(
  file: File,
  footer: Bytes.Bytes,
  copies: Bytes.Bytes & Bytes.Bytes
) -> IO(Result<&1, &1, U32 & String, Step>):
  match copies:
    case (for_result, for_compare):
      next.trailer.finish.root.compare.footer(file,
        ByteSstFile.clone.split(footer), for_result, for_compare)

def next.trailer.finish.root.expected(
  file: File,
  footer: Bytes.Bytes,
  expected: Bytes.Bytes
) -> IO(Result<&1, &1, U32 & String, Step>):
  next.trailer.finish.root.compare(file, footer,
    ByteSstFile.clone.split(expected))


def next.trailer.finish.root.digest(
  file: File,
  +total: U32,
  +index_length: U32,
  footer: Bytes.Bytes,
  digest: Bytes.Bytes
) -> IO(Result<&1, &1, U32 & String, Step>):
  next.trailer.finish.root.expected(file, footer,
    Bytes.concat([ByteSstFile.footer.magic(), ByteSstFile.u32.bytes(total),
      ByteSstFile.u32.bytes(index_length), digest]))


def next.trailer.finish.root(
  file: File,
  +total: U32,
  +index_length: U32,
  footer: Bytes.Bytes,
  result: Result<&1, &1, SHA.StreamError, SHA.Stream>
) -> IO(Result<&1, &1, U32 & String, Step>):
  match result:
    case Fail{_}:
      close.failed(file, resource_limit("SST root hash exceeds the SHA-256 input limit"))
    case Done{root_hash}:
      next.trailer.finish.root.digest(file, total, index_length, footer,
        SHA.stream.finish(root_hash))

def index.page.footer.finish(
  file: File,
  +total: U32,
  +index_length: U32,
  footer: Bytes.Bytes,
  root_hash: SHA.Stream,
  valid_index: Bool
) -> IO(Result<&1, &1, U32 & String, Step>):
  match valid_index:
    case False{}:
      close.failed(file, corruption("byte SST serialized index mismatch"))
    case True{}:
      next.trailer.finish.root.digest(file, total, index_length, footer,
        SHA.stream.finish(root_hash))

def index.page.footer.pair(
  file: File,
  reader: IndexMeta,
  footer: Bytes.Bytes,
  root_hash: SHA.Stream
) -> IO(Result<&1, &1, U32 & String, Step>):
  match reader:
    case IndexMeta{+total, +index_length, _}:
      index.page.footer.finish(file, total, index_length, footer, root_hash,
        True{})

def index.page.footer.exact(
  pair: File & Result<&1, &1, U32 & String, SstStreamIo.ExactResult>,
  reader: IndexMeta,
  root_hash: SHA.Stream
) -> IO(Result<&1, &1, U32 & String, Step>):
  match pair:
    case (file, Fail{error}): close.failed(file, error)
    case (file, Done{SstStreamIo.ExactResult{footer, complete}}):
      match complete:
        case False{}: close.failed(file, corruption("truncated byte SST footer"))
        case True{}:
          index.page.footer.pair(file, reader, footer, root_hash)

def index.page.footer.read(
  file: File,
  reader: IndexMeta,
  offset: Nat,
  root_hash: SHA.Stream
) -> IO(Result<&1, &1, U32 & String, Step>):
  do IO<Result<&1, &1, U32 & String, Step>>:
    raw : File & Result<&1, &1, U32 & String, Bytes.Bytes> <-
      Fs.read_at(file, U32.from_nat(offset), 44)
    index.page.footer.exact(read_at.exact.pair(44, raw), reader, root_hash)

def index.page.decode.root(
  reader: IndexMeta,
  +offset: Nat,
  +remaining: Nat,
  actual_hash: SHA.Stream,
  root_result: Result<&1, &1, SHA.StreamError, SHA.Stream>
) -> Result<&1, &1, U32 & String, IndexPageData>:
  match root_result:
    case Fail{_}:
      Fail{resource_limit("SST root hash exceeds the SHA-256 input limit")}
    case Done{next_root_hash}:
      +page_size = BlockIndexPolicy.read_bytes(remaining)
      Done{IndexPageData{reader, Nat.add(offset, page_size),
        Nat.sub(remaining, page_size), actual_hash, next_root_hash}}

def index.page.decode.actual(
  reader: IndexMeta,
  +offset: Nat,
  +remaining: Nat,
  root_hash: SHA.Stream,
  actual_result: Result<&1, &1, SHA.StreamError, SHA.Stream>,
  for_root: Bytes.Bytes
) -> Result<&1, &1, U32 & String, IndexPageData>:
  match actual_result:
    case Fail{_}:
      Fail{resource_limit("SST index hash exceeds the SHA-256 input limit")}
    case Done{next_actual_hash}:
      index.page.decode.root(reader, offset, remaining, next_actual_hash,
        SHA.stream.update(root_hash, for_root))

def index.page.decode.copies(
  reader: IndexMeta,
  +offset: Nat,
  +remaining: Nat,
  actual_hash: SHA.Stream,
  root_hash: SHA.Stream,
  copies: Bytes.Bytes & Bytes.Bytes,
  complete: Bool
) -> Result<&1, &1, U32 & String, IndexPageData>:
  match copies:
    case (for_hash, for_root):
      match complete:
        case False{}: Fail{corruption("truncated byte SST serialized index")}
        case True{}:
          index.page.decode.actual(reader, offset, remaining, root_hash,
            SHA.stream.update(actual_hash, for_hash), for_root)

def index.page.decode(
  reader: IndexMeta,
  +offset: Nat,
  +remaining: Nat,
  actual_hash: SHA.Stream,
  root_hash: SHA.Stream,
  bytes: Bytes.Bytes,
  complete: Bool
) -> Result<&1, &1, U32 & String, IndexPageData>:
  index.page.decode.copies(reader, offset, remaining, actual_hash, root_hash,
    ByteSstFile.clone.split(bytes), complete)

def index.page.loop(fuel: Nat, state: IndexPageState) -> IO(Result<&1, &1, U32 & String, Step>):
  match fuel:
    case 0n:
      match state:
        case IndexPageNeed{file, _, _, _, _, _}:
          close.failed(file, resource_limit("SST index page traversal limit exceeded"))
        case IndexPageRead{pair, _, _, _, _, _}:
          match pair:
            case (file, _):
              close.failed(file, resource_limit("SST index page traversal limit exceeded"))
        case IndexPageParsed{file, _}:
          close.failed(file, resource_limit("SST index page traversal limit exceeded"))
    case 1n+rest:
      match state:
        case IndexPageNeed{file, reader, +offset, +remaining,
            actual_hash, root_hash}:
          match remaining:
            case 0n:
              index.page.footer.read(file, reader, offset, root_hash)
            case 1n+_:
              +needed = U32.from_nat(BlockIndexPolicy.read_bytes(remaining))
              do IO<Result<&1, &1, U32 & String, Step>>:
                raw : File & Result<&1, &1, U32 & String, Bytes.Bytes> <-
                  Fs.read_at(file, U32.from_nat(offset), needed)
                index.page.loop(rest, IndexPageRead{
                  read_at.exact.pair(needed, raw), reader, offset, remaining,
                  actual_hash, root_hash})
        case IndexPageRead{pair, reader, +offset, +remaining,
            actual_hash, root_hash}:
          match pair:
            case (file, Fail{error}): close.failed(file, error)
            case (file, Done{SstStreamIo.ExactResult{bytes, complete}}):
              index.page.loop(rest, IndexPageParsed{file,
                index.page.decode(reader, offset, remaining,
                  actual_hash, root_hash, bytes, complete)})
        case IndexPageParsed{file, result}:
          match result:
            case Fail{error}: close.failed(file, error)
            case Done{IndexPageData{reader, offset, remaining,
                actual_hash, root_hash}}:
              index.page.loop(rest, IndexPageNeed{file, reader, offset,
                remaining, actual_hash, root_hash})
            case Done{_}:
              close.failed(file, corruption("invalid SST index traversal state"))

def index.page.start(file: File, state: State) -> IO(Result<&1, &1, U32 & String, Step>):
  match state:
    case State{+size, _, +index_offset, _, +total, _, _, _, root_hash,
        index_hash, _, _}:
      +remaining = Nat.sub(size, Nat.add(index_offset, 44n))
      +index_length = U32.from_nat(remaining)
      +page_bytes = BlockIndexPolicy.max_bytes()
      +pages = Nat.div(Nat.add(remaining, Nat.sub(page_bytes, 1n)), page_bytes)
      +fuel = Nat.add(Nat.mul(3n, pages), 1n)
      index.page.loop(fuel, IndexPageNeed{file,
        IndexMeta{total, index_length, index_hash}, index_offset, remaining,
        SHA.stream.initial(), root_hash})

def next.trailer.read(
  file: File,
  state: State
) -> IO(Result<&1, &1, U32 & String, Step>):
  index.page.start(file, state)

def next.trailer.ready(
  file: File,
  state: State,
  valid: Bool
) -> IO(Result<&1, &1, U32 & String, Step>):
  match valid:
    case False{}:
      close.failed(file, corruption("byte SST data count or index offset mismatch"))
    case True{}:
      next.trailer.read(file, state)

def next.selected.end(file: File) -> IO(Result<&1, &1, U32 & String, Step>):
  do IO<Result<&1, &1, U32 & String, Step>>:
    _closed : Unit <- File.close(file)
    return Done{End{}}

def next.trailer.state(file: File, state: State) -> IO(Result<&1, &1, U32 & String, Step>):
  match state:
    case State{_, _, +index_offset, +used, +total, _, _, +decoded, _, _, _, selected}:
      match selected:
        case True{}: next.selected.end(file)
        case False{}:
          next.trailer.ready(file, state,
            Nat.is_eq(Nat.add(20n, used), index_offset) && U32.is_eq(total, decoded))


def next.state.block.finished(
  file: File,
  state: State,
  finished: Bool
) -> IO(Result<&1, &1, U32 & String, Step>):
  match finished:
    case False{}:
      next.block.read(file, state)
    case True{}:
      next.trailer.state(file, state)

def next.state.block(
  file: File,
  state: State
) -> IO(Result<&1, &1, U32 & String, Step>):
  match state:
    case State{_, _, _, _, _, +block_count, +next_block, _, _, _, _, _}:
      next.state.block.finished(file, state,
        U32.is_eq(next_block, block_count))

def next.state(reader: Reader) -> IO(Result<&1, &1, U32 & String, Step>):
  match reader:
    case Reader{file, state}:
      next.state.block(file, state)
# Reads one bounded block or validates the trailer and returns End.
def next(reader: Reader) -> IO(Result<&1, &1, U32 & String, Step>):
  next.state(reader)

# Starts incremental entry consumption from an open block reader.
def entry.open(reader: Reader) -> EntryCursor:
  EntryReady{reader, Nil{}}

def entry.ready(
  reader: Reader,
  entries: List<&1, ByteMemTable.Entry>
) -> EntryStep:
  match entries:
    case Nil{}: EntrySkip{EntryReady{reader, Nil{}}}
    case Con{entry, tail}:
      EntryItem{entry, EntryReady{reader, tail}}

def entry.result(
  result: Result<&1, &1, U32 & String, Step>
) -> IO(EntryStep):
  match result:
    case Fail{error}:
      IO.pure(EntryStep, EntryError{EntryFailed{error}})
    case Done{End{}}:
      IO.pure(EntryStep, EntryEnd{})
    case Done{Block{reader, entries}}:
      IO.pure(EntryStep, entry.ready(reader, entries))

# Returns one entry and reads another SST block only when the current block is empty.
def entry.next(cursor: EntryCursor) -> IO(EntryStep):
  match cursor:
    case EntryReady{reader, entries}:
      match entries:
        case Con{entry, tail}:
          IO.pure(EntryStep, EntryItem{entry, EntryReady{reader, tail}})
        case Nil{}:
          do IO<EntryStep>:
            result : Result<&1, &1, U32 & String, Step> <- next(reader)
            entry.result(result)
    case EntryEnded{}: IO.pure(EntryStep, EntryEnd{})
    case EntryClosed{}: IO.pure(EntryStep, EntryEnd{})
    case EntryFailed{error}:
      IO.pure(EntryStep, EntryError{EntryFailed{error}})


# Closes the active SST reader and preserves terminal cursor states.
def entry.close(cursor: EntryCursor) -> IO(Result<&1, &1, U32 & String, Unit>):
  match cursor:
    case EntryReady{reader, _}: close(reader)
    case EntryEnded{}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Done{Unit{}})
    case EntryClosed{}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Done{Unit{}})
    case EntryFailed{_}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Done{Unit{}})

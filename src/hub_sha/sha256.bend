# Vendored from bend-collections 0x9ee2e9a299991dcc089fe22c7f3ceb5f
# (src/crypto/sha/sha256.bend), byte-identical. See core.bend header.
import Base
import ./core.bend as Core
import ./state.bend as S
import bend-kit-bytes@0.3.2.0/bytes.bend as Packed
import ../coordinator/QueuePolicy.bend as QueuePolicy

# Describes failures while enforcing the streaming hash input bound.
type StreamError is Data:
  ResourceLimit{}

# Retains the compressed hash state and one incomplete block.
type Stream is Type:
  Stream{compressed: S.State, tail: Packed.Bytes, total: Nat}

# The core refinement theorem quantifies over every constant table.
# Instantiate the verified core with the FIPS 180-4 constants.
def constants() -> List<&2, U32>:
  [1116352408, 1899447441, 3049323471, 3921009573,
   961987163, 1508970993, 2453635748, 2870763221,
   3624381080, 310598401, 607225278, 1426881987,
   1925078388, 2162078206, 2614888103, 3248222580,
   3835390401, 4022224774, 264347078, 604807628,
   770255983, 1249150122, 1555081692, 1996064986,
   2554220882, 2821834349, 2952996808, 3210313671,
   3336571891, 3584528711, 113926993, 338241895,
   666307205, 773529912, 1294757372, 1396182291,
   1695183700, 1986661051, 2177026350, 2456956037,
   2730485921, 2820302411, 3259730800, 3345764771,
   3516065817, 3600352804, 4094571909, 275423344,
   430227734, 506948616, 659060556, 883997877,
   958139571, 1322822218, 1537002063, 1747873779,
   1955562222, 2024104815, 2227730452, 2361852424,
   2428436474, 2756734187, 3204031479, 3329325298]

# SHA-256 for the reference octet-list input.
def sha256(bytes: List<&2, U32>) -> List<&2, U32>:
  Core.sha256(bytes)

# Convert ASCII text to the reference octet-list input.
def ascii(text: String) -> List<&2, U32>:
  Core.ascii(text)

# Format eight digest words as lowercase hexadecimal.
def hex(ws: List<&2, U32>) -> String:
  Core.hex(ws)

# Big-endian octets, represented as U32 values in 0..255.
def digest_bytes(ws: List<&2, U32>) -> List<&2, U32>:
  match ws:
    case Nil{}:
      Nil{}
    case +w <> tail:
      U32.and(U32.shrn(w, 24n), 255) <>
      U32.and(U32.shrn(w, 16n), 255) <>
      U32.and(U32.shrn(w, 8n), 255) <>
      U32.and(w, 255) <> digest_bytes(tail)

# Return the reference digest as eight big-endian octets per word.
def sha256_bytes(bytes: List<&2, U32>) -> List<&2, U32>:
  digest_bytes(sha256(bytes))

# Compress one packed block using sixteen transient big-endian words. The file
# buffer stays packed; no per-byte List is constructed for complete blocks.
def packed.compress(words: List<&2, U32>, state: S.State) -> S.State:
  match words:
    case a <> b <> c <> d <> e <> f <> g <> h <> i <> j <> k <> l <> m <> n <> o <> p <> Nil{}:
      Core.fips_compress16(a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, 48n, state)
    case _:
      state

# Read complete 64-byte blocks directly through a bounded package cursor.
def packed.blocks(
  remaining: Nat,
  in_block: Nat,
  pair: Packed.Cursor & Maybe<&2, U32>,
  acc: List<&2, U32>,
  state: S.State
) -> Packed.Cursor & S.State:
  match remaining:
    case 0n:
      match pair:
        case (cursor, _):
          (cursor, state)
    case 1n:
      match in_block:
        case 0n:
          match pair:
            case (cursor, _):
              (cursor, state)
        case 1n:
          match pair:
            case (cursor, Some{word}):
              (cursor, packed.compress(List.reverse(&2, U32, word <> acc), state))
            case (cursor, None{}):
              (cursor, state)
        case 1n+more:
          match pair:
            case (cursor, _):
              (cursor, state)
    case 1n+more:
      match in_block:
        case 0n:
          match pair:
            case (cursor, _):
              (cursor, state)
        case 1n:
          match pair:
            case (cursor, Some{word}):
              packed.blocks(more, 16n, Packed.Cursor.u32be(cursor), Nil{},
                packed.compress(List.reverse(&2, U32, word <> acc), state))
            case (cursor, None{}):
              (cursor, state)
        case 1n+left:
          match pair:
            case (cursor, Some{word}):
              packed.blocks(more, left, Packed.Cursor.u32be(cursor), word <> acc, state)
            case (cursor, None{}):
              (cursor, state)

# Read the remaining fewer than 64 bytes for the existing constant-space tail
# padding routines. This list is bounded by 63 octets, regardless of file size.
def packed.tail(
  remaining: Nat,
  pair: Packed.Cursor & Maybe<&2, U32>,
  acc: List<&2, U32>
) -> Packed.Cursor & List<&2, U32>:
  match remaining:
    case 0n:
      match pair:
        case (cursor, _):
          (cursor, List.reverse(&2, U32, acc))
    case 1n:
      match pair:
        case (cursor, Some{byte}):
          (cursor, List.reverse(&2, U32, byte <> acc))
        case (cursor, None{}):
          (cursor, Nil{})
    case 1n+more:
      match pair:
        case (cursor, Some{byte}):
          packed.tail(more, Packed.Cursor.u8(cursor), byte <> acc)
        case (cursor, None{}):
          (cursor, Nil{})

def packed.finish.tail(total: U32, pair: Packed.Cursor & List<&2, U32>, state: S.State) -> S.State:
  match pair:
    case (_, tail):
      Core.finish_n(tail, U32.to_nat(total), 48n, state)

def packed.final.tail(total: U32, tail_len: Nat, cursor: Packed.Cursor, state: S.State) -> S.State:
  match tail_len:
    case 0n:
      packed.finish.tail(total, (cursor, Nil{}), state)
    case 1n+more:
      packed.finish.tail(total, packed.tail(1n+more, Packed.Cursor.u8(cursor), Nil{}), state)

def packed.final(total: U32, tail_len: Nat, cursor: Packed.Cursor, state: S.State) -> List<&2, U32>:
  Core.digest(packed.final.tail(total, tail_len, cursor, state))

def packed.after_blocks(total: U32, tail_len: Nat, pair: Packed.Cursor & S.State) -> List<&2, U32>:
  match pair:
    case (cursor, state):
      packed.final(total, tail_len, cursor, state)

def packed.start.blocks(+total: U32, cursor: Packed.Cursor, blocks: Nat, +tail_len: Nat) -> List<&2, U32>:
  match blocks:
    case 0n:
      packed.final(total, tail_len, cursor, Core.initial())
    case 1n+more:
      packed.after_blocks(total, tail_len,
        packed.blocks(((1n+more) * 16n : Nat), 16n, Packed.Cursor.u32be(cursor), Nil{}, Core.initial()))

def packed.start(+total: U32, cursor: Packed.Cursor) -> List<&2, U32>:
  packed.start.blocks(total, cursor,
    Nat.div(U32.to_nat(total), 64n), Nat.mod(U32.to_nat(total), 64n))

# SHA-256 directly over packed bytes. Full blocks are read as sixteen u32be
# words; only the final 0..63 octets use the existing tail padding interface.
def sha256_packed(bytes: Packed.Bytes) -> List<&2, U32>:
  match bytes:
    case Packed.Bytes{+len, buf}:
      packed.start(len, Packed.Cursor.new(Packed.Bytes{len, buf}))

def packed.digest.finish.bytes(pair: Packed.Bytes & U32) -> Packed.Bytes:
  match pair:
    case (bytes, _):
      bytes

def packed.digest.finish(pair: Packed.Cursor & Bool) -> Packed.Bytes:
  match pair:
    case (cursor, _):
      packed.digest.finish.bytes(Packed.Cursor.finish(cursor))

def packed.digest.words(words: List<&2, U32>, pair: Packed.Cursor & Bool) -> Packed.Bytes:
  match words:
    case Nil{}:
      packed.digest.finish(pair)
    case word <> rest:
      match pair:
        case (cursor, _) :
          packed.digest.words(rest, Packed.Cursor.put.u32be(cursor, word))

# Return the SHA-256 digest as packed bytes in canonical big-endian order.
def sha256_packed_bytes(bytes: Packed.Bytes) -> Packed.Bytes:
  packed.digest.words(sha256_packed(bytes),
    (Packed.Cursor.new(Packed.Bytes{32, Packed.alloc(32)}), True{}))

def stream.empty.bytes() -> Packed.Bytes:
  Packed.Bytes{0, Packed.alloc(0)}

def stream.initial() -> Stream:
  Stream{Core.initial(), stream.empty.bytes(), 0n}

def stream.clone.bytes(+len: U32, copies: Array<U32> & Array<U32>) -> Packed.Bytes & Packed.Bytes:
  match copies:
    case (left, right):
      (Packed.Bytes{len, left}, Packed.Bytes{len, right})

def stream.clone.tail(
  +compressed: S.State,
  totals: Nat & Nat,
  copies: Packed.Bytes & Packed.Bytes
) -> Stream & Stream:
  match totals:
    case (left_total, right_total):
      match copies:
        case (left_tail, right_tail):
          (Stream{compressed, left_tail, left_total},
            Stream{compressed, right_tail, right_total})

def stream.clone.parts(
  +compressed: S.State,
  totals: Nat & Nat,
  tail: Packed.Bytes
) -> Stream & Stream:
  match tail:
    case Packed.Bytes{+len, buf}:
      stream.clone.tail(compressed, totals,
        stream.clone.bytes(len, Packed.copy.bytes(len, buf,
          Packed.alloc(len), 0, 0)))

def stream.clone(state: Stream) -> Stream & Stream:
  match state:
    case Stream{compressed, tail, +total}:
      stream.clone.parts(compressed, QueuePolicy.nat.clone.pair(total), tail)

def stream.length(pair: Packed.Bytes & U32) -> U32:
  match pair:
    case (_, size): size

def stream.count(pair: Packed.Cursor & S.State) -> S.State:
  match pair:
    case (_, compressed): compressed

def stream.compress(bytes: Packed.Bytes, compressed: S.State) -> S.State:
  match bytes:
    case Packed.Bytes{+len, buf}:
      stream.count(packed.blocks(
        Nat.mul(Nat.div(U32.to_nat(len), 64n), 16n), 16n,
        Packed.Cursor.u32be(Packed.Cursor.new(Packed.Bytes{len, buf})),
        Nil{}, compressed))

def stream.tail.result.sliced(
  +compressed: S.State,
  complete: Packed.Bytes,
  pair: Packed.Bytes & Packed.Bytes,
  total: Nat
) -> Result<&1, &1, StreamError, Stream>:
  match pair:
    case (_, tail):
      Done{Stream{stream.compress(complete, compressed), tail, total}}
def stream.tail.result(
  +compressed: S.State,
  joined: Packed.Bytes,
  complete: Packed.Bytes,
  full_length: Nat,
  remainder: Nat,
  total: Nat
) -> Result<&1, &1, StreamError, Stream>:
  stream.tail.result.sliced(compressed, complete,
    Packed.slice(joined, U32.from_nat(full_length), U32.from_nat(remainder)),
    total)
def stream.result.sliced(
  +compressed: S.State,
  pair: Packed.Bytes & Packed.Bytes,
  full_length: Nat,
  remainder: Nat,
  total: Nat
) -> Result<&1, &1, StreamError, Stream>:
  match pair:
    case (retained, complete):
      stream.tail.result(compressed, retained, complete, full_length,
        remainder, total)

def stream.result.lengths(
  +compressed: S.State,
  joined: Packed.Bytes,
  lengths: Nat & Nat,
  remainder: Nat,
  total: Nat
) -> Result<&1, &1, StreamError, Stream>:
  match lengths:
    case (for_slice, for_result):
      stream.result.sliced(compressed,
        Packed.slice(joined, 0, U32.from_nat(for_slice)), for_result,
        remainder, total)
def stream.result(
  +compressed: S.State,
  joined: Packed.Bytes,
  tail_length: Nat & Nat,
  total: Nat
) -> Result<&1, &1, StreamError, Stream>:
  match tail_length:
    case (full_length, remainder):
      stream.result.lengths(compressed, joined,
        QueuePolicy.nat.clone.pair(full_length), remainder, total)
def stream.joined.measured(
  +compressed: S.State,
  measured: Packed.Bytes & U32,
  input_length: U32,
  total: Nat
) -> Result<&1, &1, StreamError, Stream>:
  match measured:
    case (joined, size):
      +length = U32.to_nat(size)
      +remainder = Nat.mod(length, 64n)
      stream.result(compressed, joined,
        (Nat.sub(length, remainder), remainder),
        Nat.add(total, U32.to_nat(input_length)))
def stream.joined(
  +compressed: S.State,
  tail: Packed.Bytes,
  incoming: Packed.Bytes,
  input_length: U32,
  total: Nat
) -> Result<&1, &1, StreamError, Stream>:
  stream.joined.measured(compressed,
    Packed.length(Packed.concat([tail, incoming])), input_length, total)

def stream.update.checked(
  +compressed: S.State,
  tail: Packed.Bytes,
  incoming: Packed.Bytes,
  input_length: U32,
  total: Nat,
  valid: Bool
) -> Result<&1, &1, StreamError, Stream>:
  match valid:
    case False{}: Fail{ResourceLimit{}}
    case True{}:
      stream.joined(compressed, tail, incoming, input_length, total)

def stream.update.state.lengths(
  +compressed: S.State,
  tail: Packed.Bytes,
  incoming: Packed.Bytes,
  lengths: Nat & Nat,
  totals: Nat & Nat
) -> Result<&1, &1, StreamError, Stream>:
  match lengths:
    case (for_update, for_limit):
      match totals:
        case (for_update_total, for_limit_total):
          stream.update.checked(compressed, tail, incoming,
            U32.from_nat(for_update), for_update_total,
            Nat.is_le(Nat.add(for_limit_total, for_limit), 4294967295n))

def stream.update.state(
  state: Stream,
  input: Packed.Bytes & U32
) -> Result<&1, &1, StreamError, Stream>:
  match state:
    case Stream{compressed, tail, +total}:
      match input:
        case (incoming, input_length):
          stream.update.state.lengths(compressed, tail, incoming,
            QueuePolicy.nat.clone.pair(U32.to_nat(input_length)),
            QueuePolicy.nat.clone.pair(total))

def stream.update(
  state: Stream,
  incoming: Packed.Bytes
) -> Result<&1, &1, StreamError, Stream>:
  stream.update.state(state, Packed.length(incoming))

def stream.finish.words(state: Stream) -> List<&2, U32>:
  match state:
    case Stream{compressed, tail, total}:
      match tail:
        case Packed.Bytes{+len, buf}:
          Core.digest(packed.final.tail(U32.from_nat(total), U32.to_nat(len),
            Packed.Cursor.new(Packed.Bytes{len, buf}), compressed))

def stream.finish(state: Stream) -> Packed.Bytes:
  packed.digest.words(stream.finish.words(state),
    (Packed.Cursor.new(Packed.Bytes{32, Packed.alloc(32)}), True{}))

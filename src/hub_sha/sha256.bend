# Vendored from bend-collections 0x9ee2e9a299991dcc089fe22c7f3ceb5f
# (src/crypto/sha/sha256.bend), byte-identical. See core.bend header.
import Base
import ./core.bend as Core
import ./state.bend as S
import bend-kit-bytes@0.3.2.0/bytes.bend as Packed

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

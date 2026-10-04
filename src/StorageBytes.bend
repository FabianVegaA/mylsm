import Base
import 0x185ae03c75e3e75be1171471f68b43cb/bytes.bend as Bytes
import 0x49814d83de8f70993a43e1002be29ecd/bytes.bend as Bytes030
import 0xcfc8be7b076f41f95c8e118383892d55/encoding.bend as Encoding

# Rewrap the encoding package buffer without unpacking octets.
def bytes030_to_current(old: Bytes030.Bytes) -> Bytes.Bytes:
  match old:
    case Bytes030.Bytes{len, buf}:
      Bytes.Bytes{len, buf}

# Rewrap current bytes for the encoding package boundary.
def current_to_bytes030(bytes: Bytes.Bytes) -> Bytes030.Bytes:
  match bytes:
    case Bytes.Bytes{len, buf}:
      Bytes030.Bytes{len, buf}

# State for the strict single-pass UTF-8 decoder.
type Utf8State is Data:
  Utf8State{need: U32, lo: U32, hi: U32, cp: U32, out: String, valid: Bool}

def utf8.lead(+byte: U32, +out: String) -> Utf8State:
  Utf8State{
    Bool.pick(U32,
      U32.is_lt(byte, 128), 0,
      Bool.pick(U32, U32.is_le(194, byte) && U32.is_le(byte, 223), 1,
        Bool.pick(U32, U32.is_eq(byte, 224) || U32.is_le(225, byte) && U32.is_le(byte, 236) || U32.is_le(238, byte) && U32.is_le(byte, 239) || U32.is_eq(byte, 237), 2,
          Bool.pick(U32, U32.is_le(240, byte) && U32.is_le(byte, 244), 3, 0)))),
    Bool.pick(U32, U32.is_eq(byte, 224), 160,
      Bool.pick(U32, U32.is_eq(byte, 240), 144, 128)),
    Bool.pick(U32, U32.is_eq(byte, 237), 159,
      Bool.pick(U32, U32.is_eq(byte, 244), 143, 191)),
    Bool.pick(U32,
      U32.is_lt(byte, 128), byte,
      Bool.pick(U32, U32.is_le(194, byte) && U32.is_le(byte, 223), U32.and(byte, 31),
        Bool.pick(U32, U32.is_le(224, byte) && U32.is_le(byte, 239), U32.and(byte, 15),
          Bool.pick(U32, U32.is_le(240, byte) && U32.is_le(byte, 244), U32.and(byte, 7), 0)))),
    Bool.pick(String, U32.is_lt(byte, 128), SCon{Chr{byte}, out}, out),
    U32.is_lt(byte, 128) || U32.is_le(194, byte) && U32.is_le(byte, 244)
  }

def utf8.cont(+need: U32, cp: U32, +out: String, ok: Bool, in_range: Bool, byte: U32) -> Utf8State:
  match in_range:
    case True{}:
      +next_cp = (cp * 64 + U32.and(byte, 63) : U32)
      Utf8State{(need - 1 : U32), 128, 191, next_cp,
        Bool.pick(String, U32.is_eq(need, 1), SCon{Chr{next_cp}, out}, out), ok}
    case False{}:
      Utf8State{0, 128, 191, 0, out, False{}}

def utf8.step(state: Utf8State, +byte: U32) -> Utf8State:
  match state:
    case Utf8State{0, _, _, _, out, True{}}:
      utf8.lead(byte, out)
    case Utf8State{0, _, _, _, out, False{}}:
      Utf8State{0, 128, 191, 0, out, False{}}
    case Utf8State{need, lo, hi, cp, out, ok}:
      utf8.cont(need, cp, out, ok, U32.is_le(lo, byte) && U32.is_le(byte, hi), byte)

def utf8.scan.fin.done(out: String, complete: Bool) -> Result<&1, &1, U32 & String, String>:
  match complete:
    case True{}:
      Done{String.reverse(out)}
    case False{}:
      Fail{(1, "invalid UTF-8")}

def utf8.scan.fin(state: Utf8State) -> Result<&1, &1, U32 & String, String>:
  match state:
    case Utf8State{need, _, _, _, out, True{}}:
      utf8.scan.fin.done(out, U32.is_eq(need, 0))
    case Utf8State{_, _, _, _, _, False{}}:
      Fail{(1, "invalid UTF-8")}

def utf8.scan(
  remaining: Nat,
  +offset: U32,
  pair: Array<U32> & U32,
  state: Utf8State
) -> Result<&1, &1, U32 & String, String>:
  match remaining:
    case 0n:
      match pair:
        case (_, _):
          utf8.scan.fin(state)
    case 1n+p:
      match pair:
        case (buf, b):
          utf8.scan(p, (offset + 1 : U32), Bytes030.peek(buf, (offset + 1 : U32)), utf8.step(state, b))

# Return None rather than wrapping when U32 addition overflows.
def checked_add(+left: U32, +right: U32) -> Maybe<&2, U32>:
  Bool.pick(Maybe<&2, U32>, U32.is_le(left, (4294967295 - right : U32)), Some{(left + right : U32)}, None{})

# Normal target size for an encoded storage block or WAL frame.
def MAX_BLOCK_BYTES() -> U32:
  1048576

# Hard cap for an individual encoded key or value.
def MAX_RECORD_BYTES() -> U32:
  1073741824

# Hard cap for the complete serialized Manifest.
def MAX_MANIFEST_BYTES() -> U32:
  1048576

# Reject text fields outside the configured storage record cap.
def from_string.checked(+len: U32, buf: Array<U32>) -> Result<&1, &1, U32 & String, Bytes.Bytes>:
  Bool.pick(Result<&1, &1, U32 & String, Bytes.Bytes>,
    U32.is_le(len, MAX_RECORD_BYTES()),
    Done{Bytes.Bytes{len, buf}}, Fail{(2, "record too large")})

# Adapt and bound the encoded UTF-8 buffer.
def from_string.fin(old: Bytes030.Bytes) -> Result<&1, &1, U32 & String, Bytes.Bytes>:
  match old:
    case Bytes030.Bytes{+len, buf}:
      from_string.checked(len, buf)

# Encode public text at the packed storage boundary.
def from_string(+text: String) -> Result<&1, &1, U32 & String, Bytes.Bytes>:
  from_string.fin(Encoding.utf8.encode(text))

# Decode bytes after strict RFC 3629 validation.
def decode_checked(old: Bytes030.Bytes) -> Result<&1, &1, U32 & String, String>:
  match old:
    case Bytes030.Bytes{len, buf}:
      utf8.scan(U32.to_nat(len), 0, Bytes030.peek(buf, 0), Utf8State{0, 128, 191, 0, SNil{}, True{}})

# Decode a packed buffer, rejecting malformed UTF-8.
def to_string_strict(bytes: Bytes.Bytes) -> Result<&1, &1, U32 & String, String>:
  decode_checked(current_to_bytes030(bytes))

# Read one bounded big-endian u32 through a package cursor.
def read_u32be(cursor: Bytes.Cursor) -> Bytes.Cursor & Maybe<&2, U32>:
  Bytes.Cursor.u32be(cursor)

# Write one bounded big-endian u32 through a package cursor.
def write_u32be(cursor: Bytes.Cursor, value: U32) -> Bytes.Cursor & Bool:
  Bytes.Cursor.put.u32be(cursor, value)

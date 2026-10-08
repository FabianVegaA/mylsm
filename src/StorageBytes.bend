import Base
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

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
          utf8.scan(p, (offset + 1 : U32), Bytes.peek(buf, (offset + 1 : U32)), utf8.step(state, b))

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

# Checks a record against the storage codec byte cap.
def record_bytes_allowed(+length: U32) -> Bool:
  U32.is_le(length, MAX_RECORD_BYTES())

def utf8.width(+scalar: U32) -> U32:
  Bool.pick(U32, U32.is_le(scalar, 127), 1,
    Bool.pick(U32, U32.is_le(scalar, 2047), 2,
      Bool.pick(U32, U32.is_le(scalar, 65535), 3, 4)))

# Returns a string length as a storage byte count.
def string_size(+text: String) -> Nat:
  match text:
    case SNil{}:
      0n
    case SCon{Chr{scalar}, rest}:
      Nat.add(U32.to_nat(utf8.width(scalar)), string_size(rest))

def from_string.size(+text: String, +size: U32, fits: Bool) -> Maybe<&2, U32>:
  match text fits:
    case SNil{} _:
      Some{size}
    case SCon{Chr{_scalar}, SNil{}} False{}:
      None{}
    case SCon{Chr{scalar}, SNil{}} True{}:
      Some{(size + utf8.width(scalar) : U32)}
    case SCon{Chr{_scalar}, SCon{Chr{_next_scalar}, _rest}} False{}:
      None{}
    case SCon{Chr{scalar}, SCon{Chr{next_scalar}, rest}} True{}:
      from_string.size(SCon{Chr{next_scalar}, rest}, (size + utf8.width(scalar) : U32),
        U32.is_le((size + utf8.width(scalar) : U32),
          (MAX_RECORD_BYTES() - utf8.width(next_scalar) : U32)))

def from_string.size.begin(+text: String) -> Maybe<&2, U32>:
  match text:
    case SNil{}:
      Some{0}
    case SCon{Chr{scalar}, _}:
      from_string.size(text, 0,
        U32.is_le(0, (MAX_RECORD_BYTES() - utf8.width(scalar) : U32)))

# Reject text fields outside the configured storage record cap.
def from_string.checked(+len: U32, buf: Array<U32>) -> Result<&1, &1, U32 & String, Bytes.Bytes>:
  Bool.pick(Result<&1, &1, U32 & String, Bytes.Bytes>,
    record_bytes_allowed(len),
    Done{Bytes.Bytes{len, buf}}, Fail{(2, "record too large")})

def utf8.put.result(pair: Bytes.Cursor & Bool) -> Bytes.Cursor:
  match pair:
    case (cursor, _):
      cursor

def utf8.put.byte(cursor: Bytes.Cursor, +byte: U32) -> Bytes.Cursor:
  utf8.put.result(Bytes.Cursor.put.u8(cursor, byte))

def utf8.put.two(cursor: Bytes.Cursor, +scalar: U32) -> Bytes.Cursor:
  utf8.put.byte(utf8.put.byte(cursor, (192 + U32.shrn(scalar, 6n) : U32)),
    (128 + U32.and(scalar, 63) : U32))

def utf8.put.three(cursor: Bytes.Cursor, +scalar: U32) -> Bytes.Cursor:
  utf8.put.byte(utf8.put.byte(
    utf8.put.byte(cursor, (224 + U32.shrn(scalar, 12n) : U32)),
    (128 + U32.and(U32.shrn(scalar, 6n), 63) : U32)),
    (128 + U32.and(scalar, 63) : U32))

def utf8.put.four(cursor: Bytes.Cursor, +scalar: U32) -> Bytes.Cursor:
  utf8.put.byte(utf8.put.byte(
    utf8.put.byte(utf8.put.byte(cursor, (240 + U32.shrn(scalar, 18n) : U32)),
      (128 + U32.and(U32.shrn(scalar, 12n), 63) : U32)),
    (128 + U32.and(U32.shrn(scalar, 6n), 63) : U32)),
    (128 + U32.and(scalar, 63) : U32))

def utf8.put.scalar(
  cursor: Bytes.Cursor,
  +scalar: U32,
  ascii: Bool,
  two_byte: Bool,
  three_byte: Bool
) -> Bytes.Cursor:
  match ascii two_byte three_byte:
    case True{} _ _:
      utf8.put.byte(cursor, scalar)
    case False{} True{} _:
      utf8.put.two(cursor, scalar)
    case False{} False{} True{}:
      utf8.put.three(cursor, scalar)
    case False{} False{} False{}:
      utf8.put.four(cursor, scalar)

def utf8.encode.go(text: String, cursor: Bytes.Cursor) -> Bytes.Cursor:
  match text:
    case SNil{}:
      cursor
    case SCon{Chr{+scalar}, tail}:
      utf8.encode.go(tail, utf8.put.scalar(cursor, scalar,
        U32.is_le(scalar, 127), U32.is_le(scalar, 2047), U32.is_le(scalar, 65535)))

def from_string.output.pair(result: Bytes.Bytes & U32) -> Bytes.Bytes:
  match result:
    case (bytes, _):
      bytes

def from_string.output(+text: String, +len: U32) -> Bytes.Bytes:
  from_string.output.pair(Bytes.Cursor.finish(utf8.encode.go(text,
    Bytes.Cursor.new(Bytes.Bytes{len, Bytes.alloc(len)}))))

def from_string.preflight(+text: String, size: Maybe<&2, U32>) -> Result<&1, &1, U32 & String, Bytes.Bytes>:
  match size:
    case None{}:
      Fail{(2, "record too large")}
    case Some{len}:
      Done{from_string.output(text, len)}

# Encode public text at the packed storage boundary.
def from_string(+text: String) -> Result<&1, &1, U32 & String, Bytes.Bytes>:
  from_string.preflight(text, from_string.size.begin(text))

# Decode bytes after strict RFC 3629 validation.
def decode_checked(bytes: Bytes.Bytes) -> Result<&1, &1, U32 & String, String>:
  match bytes:
    case Bytes.Bytes{len, buf}:
      utf8.scan(U32.to_nat(len), 0, Bytes.peek(buf, 0), Utf8State{0, 128, 191, 0, SNil{}, True{}})

# Decode a packed buffer, rejecting malformed UTF-8.
def to_string_strict(bytes: Bytes.Bytes) -> Result<&1, &1, U32 & String, String>:
  decode_checked(bytes)

# Read one bounded big-endian u32 through a package cursor.
def read_u32be(cursor: Bytes.Cursor) -> Bytes.Cursor & Maybe<&2, U32>:
  Bytes.Cursor.u32be(cursor)

# Write one bounded big-endian u32 through a package cursor.
def write_u32be(cursor: Bytes.Cursor, value: U32) -> Bytes.Cursor & Bool:
  Bytes.Cursor.put.u32be(cursor, value)

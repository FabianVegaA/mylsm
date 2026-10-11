import Base
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Represents one incremental cursor response frame.
type Frame is Type:
  CursorEnd{}
  CursorItem{key: Bytes.Bytes, value: Bytes.Bytes}

# Reports a decoded cursor frame or malformed wire bytes.
type Decision is Type:
  Decoded{frame: Frame}
  Malformed{}

# Encodes one exact byte offset and length into a fixed-width word.
def u32.bytes(value: U32) -> Bytes.Bytes:
  Bytes.set.u32be(Bytes.new(4), 0, value)

def nat.duplicate.step(pair: Nat & Nat) -> Nat & Nat:
  match pair:
    case (first, second): (Nat.add(1n, first), Nat.add(1n, second))

def nat.duplicate(value: Nat) -> Nat & Nat:
  match value:
    case 0n: (0n, 0n)
    case 1n+rest: nat.duplicate.step(nat.duplicate(rest))

def u32.duplicate.result(pair: Nat & Nat) -> U32 & U32:
  match pair:
    case (first, second): (U32.from_nat(first), U32.from_nat(second))

def u32.duplicate(value: U32) -> U32 & U32:
  u32.duplicate.result(nat.duplicate(U32.to_nat(value)))

# Extracts the owned byte sequence from the bytes package slice result.
def slice.result(pair: Bytes.Bytes & Bytes.Bytes) -> Bytes.Bytes:
  match pair:
    case (_, sliced): sliced

# Returns the one-byte tag for terminal cursor state.
def end.tag() -> Bytes.Bytes:
  Bytes.new(1)

# Returns the one-byte tag for an item carrying raw key and value bytes.
def item.tag() -> Bytes.Bytes:
  slice.result(Bytes.slice(u32.bytes(1), 3, 1))

# Encodes retained key/value buffers after measuring each exact byte length.
def item.measured(
  key_size: Bytes.Bytes & U32,
  value_size: Bytes.Bytes & U32
) -> Bytes.Bytes:
  match key_size:
    case (key, key_length):
      match value_size:
        case (value, value_length):
          Bytes.concat([item.tag(), u32.bytes(key_length), key,
            u32.bytes(value_length), value])

# Encodes a cursor item using explicit lengths and no text conversion.
def item(
  key: Bytes.Bytes,
  value: Bytes.Bytes
) -> Bytes.Bytes:
  item.measured(Bytes.length(key), Bytes.length(value))

# Encodes End separately from an item whose key and value are empty.
def encode(frame: Frame) -> Bytes.Bytes:
  match frame:
    case CursorEnd{}: end.tag()
    case CursorItem{key, value}: item(key, value)

# Extracts exact byte equality from the bytes package comparison result.
def tag.matches(pair: Bytes.Bytes & Bytes.Bytes & Bool) -> Bool:
  match pair:
    case (_, _, equal): equal

# Decodes the terminal marker only when no trailing bytes remain.
def end.checked(
  is_end: Bool,
  exact: Bool
) -> Decision:
  match is_end:
    case True{}:
      match exact:
        case True{}: Decoded{CursorEnd{}}
        case False{}: Malformed{}
    case False{}: Malformed{}

# Combines the exact key and value byte slices into one cursor item.
def item.value.paired(
  pair: Bytes.Bytes & Bytes.Bytes,
  key: Bytes.Bytes
) -> Decision:
  match pair:
    case (_, value): Decoded{CursorItem{key, value}}

# Creates the value slice from the source retained by the key slice.
def item.value.key.sliced(
  pair: Bytes.Bytes & Bytes.Bytes,
  value_offset: U32,
  value_length: U32
) -> Decision:
  match pair:
    case (source, key):
      item.value.paired(Bytes.slice(source, value_offset, value_length), key)

# Slices the key first so the source remains available for the value slice.
def item.value.slices(
  payload: Bytes.Bytes,
  key_lengths: U32 & U32,
  value_length: U32
) -> Decision:
  match key_lengths:
    case (key_length, value_key_length):
      item.value.key.sliced(Bytes.slice(payload, 5, key_length),
        U32.from_nat(Nat.add(9n, U32.to_nat(value_key_length))), value_length)

# Accepts only an exact frame length after reading the value length.
def item.value.bound.checked(
  exact: Bool,
  payload: Bytes.Bytes,
  key_length: U32,
  value_length: U32
) -> Decision:
  match exact:
    case True{}:
      item.value.slices(payload, u32.duplicate(key_length), value_length)
    case False{}: Malformed{}

# Accepts only a value length that ends exactly at the frame boundary.
def item.value.bound.compare(
  payload: Bytes.Bytes,
  size: U32,
  key_lengths: U32 & U32,
  value_lengths: U32 & U32
) -> Decision:
  match key_lengths:
    case (checked_key_length, retained_key_length):
      match value_lengths:
        case (checked_value_length, retained_value_length):
          item.value.bound.checked(Nat.is_eq(U32.to_nat(size),
            Nat.add(9n, Nat.add(U32.to_nat(checked_key_length),
              U32.to_nat(checked_value_length)))), payload,
            retained_key_length, retained_value_length)

# Duplicates lengths for exact validation and the returned value slice.
def item.value.bound(
  payload: Bytes.Bytes,
  size: U32,
  key_length: U32,
  value_length: U32
) -> Decision:
  item.value.bound.compare(payload, size, u32.duplicate(key_length),
    u32.duplicate(value_length))

# Distinguishes a complete value length from a truncated header.
def item.value.parsed(
  payload: Bytes.Bytes,
  size: U32,
  key_length: U32,
  parsed: Maybe<&2, U32>
) -> Decision:
  match parsed:
    case Some{value_length}:
      item.value.bound(payload, size, key_length, value_length)
    case None{}: Malformed{}

# Reads the value length at the boundary immediately after the key.
def item.value.length(
  payload: Bytes.Bytes,
  size: U32,
  key_length: U32,
  parsed: Maybe<&2, U32>
) -> Decision:
  item.value.parsed(payload, size, key_length, parsed)

# Checks that the key length leaves room for the value length word.
def item.key.bound.read(
  read: Bytes.Bytes & Maybe<&2, U32>,
  size: U32,
  key_length: U32
) -> Decision:
  match read:
    case (payload, parsed):
      item.value.length(payload, size, key_length, parsed)

# Checks that the key length leaves room for the value length word.
def item.key.bound.read.offset(
  payload: Bytes.Bytes,
  size: U32,
  key_lengths: U32 & U32
) -> Decision:
  match key_lengths:
    case (offset_length, retained_length):
      item.key.bound.read(Bytes.get.u32be(payload,
        U32.from_nat(Nat.add(5n, U32.to_nat(offset_length)))), size,
        retained_length)

# Checks that the key length leaves room for the value length word.
def item.key.bound.checked(
  has_value_header: Bool,
  payload: Bytes.Bytes,
  size: U32,
  key_length: U32
) -> Decision:
  match has_value_header:
    case True{}:
      item.key.bound.read.offset(payload, size,
        u32.duplicate(key_length))
    case False{}: Malformed{}

# Accepts key lengths that leave a complete value length word.
def item.key.bound.check(
  payload: Bytes.Bytes,
  sizes: U32 & U32,
  key_lengths: U32 & U32
) -> Decision:
  match sizes:
    case (checked_size, retained_size):
      match key_lengths:
        case (checked_key_length, retained_key_length):
          item.key.bound.checked(Nat.is_le(
            Nat.add(9n, U32.to_nat(checked_key_length)),
            U32.to_nat(checked_size)), payload, retained_size,
            retained_key_length)

# Accepts key lengths that leave a complete value length word.
def item.key.bound.compare(
  payload: Bytes.Bytes,
  size: U32,
  key_lengths: U32 & U32
) -> Decision:
  item.key.bound.check(payload, u32.duplicate(size), key_lengths)

# Accepts key lengths that leave a complete value length word.
def item.key.bound(
  payload: Bytes.Bytes,
  size: U32,
  key_length: U32
) -> Decision:
  item.key.bound.compare(payload, size, u32.duplicate(key_length))

# Accepts the key-length field only when all required bytes are present.
def item.key.parsed(
  payload: Bytes.Bytes,
  size: U32,
  parsed: Maybe<&2, U32>
) -> Decision:
  match parsed:
    case Some{key_length}: item.key.bound(payload, size, key_length)
    case None{}: Malformed{}

# Reads the key length before deriving the value-length offset.
def item.key.length(
  payload: Bytes.Bytes,
  size: U32,
  parsed: Maybe<&2, U32>
) -> Decision:
  item.key.parsed(payload, size, parsed)

# Routes complete item headers to the key-length decoder.
def item.header.read(
  read: Bytes.Bytes & Maybe<&2, U32>,
  size: U32
) -> Decision:
  match read:
    case (payload, parsed): item.key.length(payload, size, parsed)

# Routes complete item headers to the key-length decoder.
def item.header.checked(
  has_header: Bool,
  payload: Bytes.Bytes,
  size: U32
) -> Decision:
  match has_header:
    case True{}:
      item.header.read(Bytes.get.u32be(payload, 1), size)
    case False{}: Malformed{}

# Checks header capacity while retaining its total for later framing checks.
def item.header.compare(
  payload: Bytes.Bytes,
  sizes: U32 & U32,
  is_item: Bool
) -> Decision:
  match sizes:
    case (checked_size, retained_size):
      item.header.checked(U32.is_le(9, checked_size) && is_item, payload,
        retained_size)

# Rejects item headers that cannot contain both length words.
def item.header.size(
  payload: Bytes.Bytes,
  size: U32,
  is_item: Bool
) -> Decision:
  item.header.compare(payload, u32.duplicate(size), is_item)

# Routes the item tag to exact length-prefixed decoding.
def decode.item(
  payload: Bytes.Bytes,
  size: U32,
  is_item: Bool
) -> Decision:
  item.header.size(payload, size, is_item)

# Decodes the item marker from the retained response source.
def decode.item.tag.sliced(
  sliced: Bytes.Bytes & Bytes.Bytes,
  size: U32
) -> Decision:
  match sliced:
    case (source, tag_bytes):
      decode.item(source, size,
        tag.matches(Bytes.eq(tag_bytes, item.tag())))

# Retains the response source while comparing the item marker.
def decode.item.tag(
  payload: Bytes.Bytes,
  size: U32
) -> Decision:
  decode.item.tag.sliced(Bytes.slice(payload, 0, 1), size)

# Selects End validation or item decoding after the terminal tag check.
def decode.tag.end.checked(
  is_end: Bool,
  payload: Bytes.Bytes,
  sizes: U32 & U32
) -> Decision:
  match is_end:
    case True{}:
      match sizes:
        case (checked_size, _):
          end.checked(True{}, U32.is_eq(checked_size, 1))
    case False{}:
      match sizes:
        case (_, retained_size): decode.item.tag(payload, retained_size)

# Checks the terminal marker while retaining bytes for item-tag decoding.
def decode.tag.end(
  sliced: Bytes.Bytes & Bytes.Bytes,
  size: U32
) -> Decision:
  match sliced:
    case (payload, tag_bytes):
      decode.tag.end.checked(tag.matches(Bytes.eq(tag_bytes, end.tag())),
        payload, u32.duplicate(size))

# Validates that a nonempty encoded response has a supported tag.
def decode.nonempty(
  payload: Bytes.Bytes,
  size: U32,
  is_nonempty: Bool
) -> Decision:
  match is_nonempty:
    case True{}: decode.tag.end(Bytes.slice(payload, 0, 1), size)
    case False{}: Malformed{}

# Decodes a complete cursor response, rejecting unknown tags and trailing data.
def decode.size.checked(
  payload: Bytes.Bytes,
  sizes: U32 & U32
) -> Decision:
  match sizes:
    case (checked_size, retained_size):
      decode.nonempty(payload, retained_size, U32.is_le(1, checked_size))

# Decodes a complete cursor response, rejecting unknown tags and trailing data.
def decode.measured(measured: Bytes.Bytes & U32) -> Decision:
  match measured:
    case (payload, size): decode.size.checked(payload, u32.duplicate(size))

# Decodes a complete cursor response from its exact byte payload.
def decode(payload: Bytes.Bytes) -> Decision:
  decode.measured(Bytes.length(payload))

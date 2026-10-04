import Base
import ../src/StorageBytes.bend as StorageBytes
import 0x185ae03c75e3e75be1171471f68b43cb/bytes.bend as Bytes
import 0x49814d83de8f70993a43e1002be29ecd/bytes.bend as Bytes030
import ../src/hub_sha/sha256.bend as SHA
import ../src/SstChecksum.bend as SstChecksum

# Unwrap a known-valid closed fixture for the following codec laws.
def packed_text.fin(result: Result<&1, &1, U32 & String, Bytes.Bytes>) -> Bytes.Bytes:
  match result:
    case Done{bytes}:
      bytes
    case Fail{_}:
      Bytes.Bytes{0, Bytes.alloc(0)}

# Build a UTF-8 packed test fixture using the production encoder.
def packed_text(text: String) -> Bytes.Bytes:
  packed_text.fin(StorageBytes.from_string(text))

# Construct the UTF-8 encoding of a forbidden surrogate scalar.
def invalid_surrogate() -> Bytes.Bytes:
  Bytes.Bytes{3, Bytes.poke(Bytes.poke(Bytes.poke(Bytes.alloc(3), 0, 237), 1, 160), 2, 128)}

# Construct a truncated four-byte UTF-8 sequence.
def invalid_truncated() -> Bytes.Bytes:
  Bytes.Bytes{2, Bytes.poke(Bytes.poke(Bytes.alloc(2), 0, 240), 1, 159)}

# Unwrap a valid closed hex fixture.
def packed_hex.fin(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}:
      bytes
    case None{}:
      Bytes.Bytes{0, Bytes.alloc(0)}

# Compare the cursor's read value with the fixture.
def cursor_roundtrip.read(pair: Bytes.Cursor & Maybe<&2, U32>) -> Bool:
  match pair:
    case (_, Some{value}):
      U32.is_eq(value, 3735928559)
    case (_, None{}):
      False{}

# Reopen the written bytes before checking the cursor read.
def cursor_roundtrip.finish(pair: Bytes.Bytes & U32) -> Bool:
  match pair:
    case (bytes, _):
      cursor_roundtrip.read(StorageBytes.read_u32be(Bytes.Cursor.new(bytes)))

# Verify a u32 survives a bounded big-endian cursor write and read.
def cursor_roundtrip(pair: Bytes.Cursor & Bool) -> Bool:
  match pair:
    case (cursor, True{}):
      cursor_roundtrip.finish(Bytes.Cursor.finish(cursor))
    case (_, False{}):
      False{}

# Build an ASCII message at a requested block boundary.
# Generate short ASCII fixtures for SHA padding-boundary checks.
def repeated_a(length: Nat, acc: String) -> String:
  match length:
    case 0n:
      acc
    case 1n+more:
      repeated_a(more, "a" ++ acc)

# Check packed and reference hashes for one message length.
def packed_hash_matches(+length: Nat) -> Bool:
  String.eq(SHA.hex(SHA.sha256_packed(Bytes.from_string(repeated_a(length, "")))),
    SHA.hex(SHA.sha256(SHA.ascii(repeated_a(length, "")))) )

# Ordinary addition remains exact.
law checked_add_exact:
  {StorageBytes.checked_add(12, 30) == Some{42} : Maybe<&2, U32>}

# Addition beyond the U32 address space is rejected.
law checked_add_overflow:
  {StorageBytes.checked_add(4294967295, 1) == None{} : Maybe<&2, U32>}

# Cursor fields use network byte order and preserve a complete value.
law cursor_u32be_roundtrip:
  {cursor_roundtrip(StorageBytes.write_u32be(Bytes.Cursor.new(Bytes.Bytes{4, Bytes.alloc(4)}), 3735928559)) == True{} : Bool}

# ASCII survives packed UTF-8 encoding and strict decoding.
law utf8_ascii_roundtrip:
  {StorageBytes.to_string_strict(packed_text("hello")) == Done{"hello"} : Result<&1, &1, U32 & String, String>}

# A two-byte UTF-8 scalar survives the storage boundary.
law utf8_multibyte_roundtrip:
  {StorageBytes.to_string_strict(packed_text("é")) == Done{"é"} : Result<&1, &1, U32 & String, String>}

# The decoder completes one legal two-byte scalar.
law utf8_two_byte_step:
  {StorageBytes.utf8.step(StorageBytes.utf8.lead(195, SNil{}), 169) == StorageBytes.Utf8State{0, 128, 191, 233, SCon{Chr{233}, SNil{}}, True{}} : StorageBytes.Utf8State}

# A supplementary scalar survives the storage boundary.
law utf8_four_byte_roundtrip:
  {StorageBytes.to_string_strict(packed_text("😀")) == Done{"😀"} : Result<&1, &1, U32 & String, String>}

# An isolated continuation byte is rejected.
law utf8_invalid_continuation_reject:
  {StorageBytes.to_string_strict(StorageBytes.bytes030_to_current(Bytes030.Bytes{1, Bytes030.poke(Bytes030.alloc(1), 0, 128)})) == Fail{(1, "invalid UTF-8")} : Result<&1, &1, U32 & String, String>}

# UTF-8 encodings of surrogate codepoints are rejected.
law utf8_surrogate_reject:
  {StorageBytes.to_string_strict(invalid_surrogate()) == Fail{(1, "invalid UTF-8")} : Result<&1, &1, U32 & String, String>}

# An incomplete multibyte suffix is rejected.
law utf8_truncated_reject:
  {StorageBytes.to_string_strict(invalid_truncated()) == Fail{(1, "invalid UTF-8")} : Result<&1, &1, U32 & String, String>}

# The packed SHA path agrees with the existing reference at the empty vector.
law sha256_packed_empty:
  {String.eq(SHA.hex(SHA.sha256_packed(Bytes.from_string(""))), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") == True{} : Bool}

# The packed SHA path agrees with the existing reference at the abc vector.
law sha256_packed_abc:
  {String.eq(SHA.hex(SHA.sha256_packed(Bytes.from_string("abc"))), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") == True{} : Bool}

# The storage checksum exposes packed digest bytes in network byte order.
law sha256_packed_digest_bytes:
  {String.eq(Bytes.to_hex(SstChecksum.digest_bytes(Bytes.from_string("abc"))), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") == True{} : Bool}

# Binary octets retain their high bits and are hashed exactly.
law sha256_packed_binary_octets:
  {String.eq(SHA.hex(SHA.sha256_packed(packed_hex.fin(Bytes.from_hex("0080ff")))), "5240672d7b51756b829ad0ef8d9468b7a078afa2f410484fd3892dab47becb72") == True{} : Bool}

# Packed hashing agrees with the byte-list implementation across padding boundaries.
law sha256_packed_padding_boundaries:
  {packed_hash_matches(55n) && packed_hash_matches(56n) && packed_hash_matches(63n) && packed_hash_matches(64n) && packed_hash_matches(65n) == True{} : Bool}

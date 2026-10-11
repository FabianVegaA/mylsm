import Base
import ./hub_sha/sha256.bend as SHA
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Represents a legacy or generation-addressed byte-store table layout.
type ManifestValue is Data:
  Empty{}
  HasSst{}
  GenerationEmpty{}
  GenerationSst{file_id: U32}

# Distinguishes malformed bytes, unknown formats, and comparator mismatch.
type Error is Data:
  Malformed{}
  UnsupportedVersion{generation: U32}
  ComparatorMismatch{generation: U32}
  ChecksumMismatch{}

# Reports the next generation identifier or exhaustion without wraparound.
type FileIdDecision is Data:
  FileIdAvailable{id: U32}
  FileIdExhausted{}

# Unwraps a fixed manifest-format literal.
def literal(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}: bytes
    case None{}: Bytes.new(0)

# Returns the byte-manifest family identifier shared by generations four and five.
def magic() -> Bytes.Bytes:
  literal(Bytes.from_hex("4d594c534d344d00"))

# Encodes one unsigned big-endian field.
def u32.bytes(value: U32) -> Bytes.Bytes:
  Bytes.set.u32be(Bytes.new(4), 0, value)

# Returns the exact fixed file name referenced by the single-run manifest.
def sst.name() -> Bytes.Bytes:
  literal(Bytes.from_hex("535354"))

def sst.generation.path(directory: String, file_id: U32) -> String:
  directory ++ "/SST." ++ Bytes.to_hex(u32.bytes(file_id))

# Creates two owned copies for hashing and output.
def clone.pair(+len: U32, copies: Array<U32> & Array<U32>) -> Bytes.Bytes & Bytes.Bytes:
  match copies:
    case (left, right): (Bytes.Bytes{len, left}, Bytes.Bytes{len, right})

# Clones a packed buffer for the manifest checksum.
def clone.split(bytes: Bytes.Bytes) -> Bytes.Bytes & Bytes.Bytes:
  match bytes:
    case Bytes.Bytes{+len, buf}:
      clone.pair(len, Bytes.copy.bytes(len, buf, Bytes.alloc(len), 0, 0))

# Packs the three independently owned manifest copies.
def clone.triple.parts(
  +len: U32,
  first: Array<U32>,
  second: Array<U32>,
  third: Array<U32>
) -> Bytes.Bytes & Bytes.Bytes & Bytes.Bytes:
  (Bytes.Bytes{len, first}, Bytes.Bytes{len, second}, Bytes.Bytes{len, third})

# Selects the retained copy from the final byte duplication.
def clone.triple.finish(
  +len: U32,
  second: Array<U32>,
  copies: Array<U32> & Array<U32>
) -> Bytes.Bytes & Bytes.Bytes & Bytes.Bytes:
  match copies:
    case (first, third): clone.triple.parts(len, first, second, third)

# Adds an independently copied third buffer.
def clone.triple.first(
  +len: U32,
  copies: Array<U32> & Array<U32>
) -> Bytes.Bytes & Bytes.Bytes & Bytes.Bytes:
  match copies:
    case (first, second):
      clone.triple.finish(len, second,
        Bytes.copy.bytes(len, first, Bytes.alloc(len), 0, 0))

# Creates three owned copies for independent header-field checks.
def clone.triple(bytes: Bytes.Bytes) -> Bytes.Bytes & Bytes.Bytes & Bytes.Bytes:
  match bytes:
    case Bytes.Bytes{+len, buf}:
      clone.triple.first(len,
        Bytes.copy.bytes(len, buf, Bytes.alloc(len), 0, 0))

# Builds the checksummed body for one manifest value.
def body(value: ManifestValue) -> Bytes.Bytes:
  match value:
    case Empty{}:
      Bytes.concat([magic(), u32.bytes(4), u32.bytes(1), u32.bytes(1), u32.bytes(0)])
    case HasSst{}:
      Bytes.concat([magic(), u32.bytes(4), u32.bytes(1), u32.bytes(1),
        u32.bytes(1), u32.bytes(3), sst.name()])
    case GenerationEmpty{}:
      Bytes.concat([magic(), u32.bytes(5), u32.bytes(1), u32.bytes(1),
        u32.bytes(0)])
    case GenerationSst{file_id}:
      Bytes.concat([magic(), u32.bytes(5), u32.bytes(1), u32.bytes(1),
        u32.bytes(1), u32.bytes(file_id)])

# Appends the digest of all preceding manifest bytes.
def encode.body.copies(copies: Bytes.Bytes & Bytes.Bytes) -> Bytes.Bytes:
  match copies:
    case (encoded, for_hash):
      Bytes.concat([encoded, SHA.sha256_packed_bytes(for_hash)])

# Appends the digest of all preceding manifest bytes.
def encode.body(packed: Bytes.Bytes) -> Bytes.Bytes:
  encode.body.copies(clone.split(packed))

# Encodes the currently supported comparator and table layout.
def encode(value: ManifestValue) -> Bytes.Bytes:
  encode.body(body(value))

def u32.read.value(pair: Bytes.Bytes & Maybe<&2, U32>) -> U32:
  match pair:
    case (_, Some{value}): value
    case _: 0

def u32.read(input: Bytes.Bytes) -> U32:
  u32.read.value(Bytes.get.u32be(input, 0))

def u32.clone.pair.bytes(copies: Bytes.Bytes & Bytes.Bytes) -> U32 & U32:
  match copies:
    case (left, right):
      (u32.read(left), u32.read(right))

def clone.file.id(file_id: U32) -> U32 & U32:
  u32.clone.pair.bytes(clone.split(u32.bytes(file_id)))

def next.file.id.current.result(next_id: U32, is_max: Bool) -> FileIdDecision:
  match is_max:
    case True{}: FileIdExhausted{}
    case False{}: FileIdAvailable{U32.add(next_id, 1)}

def next.file.id.current.copies(copies: U32 & U32) -> FileIdDecision:
  match copies:
    case (next_id, max_check):
      next.file.id.current.result(next_id,
        U32.is_eq(max_check, u32.read(literal(Bytes.from_hex("ffffffff")))))

def next.file.id.current(file_id: U32) -> FileIdDecision:
  next.file.id.current.copies(
    u32.clone.pair.bytes(clone.split(u32.bytes(file_id))))

def next.file.id(value: ManifestValue) -> FileIdDecision:
  match value:
    case Empty{}: FileIdAvailable{1}
    case HasSst{}: FileIdAvailable{1}
    case GenerationEmpty{}: FileIdAvailable{1}
    case GenerationSst{file_id}: next.file.id.current(file_id)

# Returns the second packed buffer from a slice operation.
def slice.result(pair: Bytes.Bytes & Bytes.Bytes) -> Bytes.Bytes:
  match pair:
    case (_, sliced): sliced

# Compares two packed values while preserving the equality result.
def equal(pair: Bytes.Bytes & Bytes.Bytes & Bool) -> Bool:
  match pair:
    case (_, _, same): same

# Returns the decoded value only when its body checksum is valid.
def decode.checksum.compare(
  value: ManifestValue,
  valid: Bool
) -> Result<&1, &1, Error, ManifestValue>:
  match valid:
    case True{}: Done{value}
    case False{}: Fail{ChecksumMismatch{}}

# Hashes one owned copy and compares the other with the stored digest.
def decode.checksum.copies(
  value: ManifestValue,
  +offset: U32,
  copies: Bytes.Bytes & Bytes.Bytes
) -> Result<&1, &1, Error, ManifestValue>:
  match copies:
    case (for_hash, for_digest):
      decode.checksum.compare(value,
        equal(Bytes.eq(SHA.sha256_packed_bytes(slice.result(
          Bytes.slice(for_hash, 0, offset))),
          slice.result(Bytes.slice(for_digest, offset, 32)))))

# Rejects a truncated or extended manifest before hashing it.
def decode.checksum.size(
  input: Bytes.Bytes,
  value: ManifestValue,
  +offset: U32,
  exact: Bool
) -> Result<&1, &1, Error, ManifestValue>:
  match exact:
    case False{}: Fail{Malformed{}}
    case True{}:
      decode.checksum.copies(value, offset, clone.split(input))

# Compares the measured file size with its selected canonical layout.
def decode.checksum.measured(
  value: ManifestValue,
  +offset: U32,
  +expected_size: U32,
  measured: Bytes.Bytes & U32
) -> Result<&1, &1, Error, ManifestValue>:
  match measured:
    case (input, size):
      decode.checksum.size(input, value, offset, U32.is_eq(size, expected_size))

# Checks exact size and the SHA-256 checksum over the canonical body.
def decode.checksum(
  input: Bytes.Bytes,
  value: ManifestValue,
  +offset: U32,
  +expected_size: U32
) -> Result<&1, &1, Error, ManifestValue>:
  decode.checksum.measured(value, offset, expected_size, Bytes.length(input))

# Checks the fixed table name and its exact encoded length.
def decode.sst.name.valid(input: Bytes.Bytes, valid: Bool) -> Result<&1, &1, Error, ManifestValue>:
  match valid:
    case False{}: Fail{Malformed{}}
    case True{}: decode.checksum(input, HasSst{}, 31, 63)

# Checks the fixed SST name using independent packed-byte copies.
def decode.sst_name.copies(
  copies: Bytes.Bytes & Bytes.Bytes & Bytes.Bytes
) -> Result<&1, &1, Error, ManifestValue>:
  match copies:
    case (input, length_bytes, name_bytes):
      decode.sst.name.valid(input,
        equal(Bytes.eq(slice.result(Bytes.slice(length_bytes, 24, 4)), u32.bytes(3))) &&
          equal(Bytes.eq(slice.result(Bytes.slice(name_bytes, 28, 3)), sst.name())))

# Validates the only permitted SST file name.
def decode.sst_name(input: Bytes.Bytes) -> Result<&1, &1, Error, ManifestValue>:
  decode.sst_name.copies(clone.triple(input))

# Selects the empty or one-table layout from its declared file count.
def decode.sst_count.value(
  input: Bytes.Bytes,
  field: Maybe<&2, U32>
) -> Result<&1, &1, Error, ManifestValue>:
  match field:
    case None{}: Fail{Malformed{}}
    case Some{0}: decode.checksum(input, Empty{}, 24, 56)
    case Some{1}: decode.sst_name(input)
    case _: Fail{Malformed{}}

def decode.sst_count.field(
  pair: Bytes.Bytes & Maybe<&2, U32>
) -> Result<&1, &1, Error, ManifestValue>:
  match pair:
    case (input, field): decode.sst_count.value(input, field)

def decode.sst_count(input: Bytes.Bytes) -> Result<&1, &1, Error, ManifestValue>:
  decode.sst_count.field(Bytes.get.u32be(input, 20))

# Requires the canonical single level used by the byte durable engine.
def decode.level_count.value(
  input: Bytes.Bytes,
  field: Maybe<&2, U32>
) -> Result<&1, &1, Error, ManifestValue>:
  match field:
    case None{}: Fail{Malformed{}}
    case Some{1}: decode.sst_count(input)
    case _: Fail{Malformed{}}

def decode.level_count.field(
  pair: Bytes.Bytes & Maybe<&2, U32>
) -> Result<&1, &1, Error, ManifestValue>:
  match pair:
    case (input, field): decode.level_count.value(input, field)

def decode.level_count(input: Bytes.Bytes) -> Result<&1, &1, Error, ManifestValue>:
  decode.level_count.field(Bytes.get.u32be(input, 16))

# Rejects manifests written for a different key comparator.
def decode.comparator.value(
  input: Bytes.Bytes,
  field: Maybe<&2, U32>
) -> Result<&1, &1, Error, ManifestValue>:
  match field:
    case None{}: Fail{Malformed{}}
    case Some{1}: decode.level_count(input)
    case Some{generation}: Fail{ComparatorMismatch{generation}}

def decode.comparator.field(
  pair: Bytes.Bytes & Maybe<&2, U32>
) -> Result<&1, &1, Error, ManifestValue>:
  match pair:
    case (input, field): decode.comparator.value(input, field)

def decode.comparator(input: Bytes.Bytes) -> Result<&1, &1, Error, ManifestValue>:
  decode.comparator.field(Bytes.get.u32be(input, 12))

def decode.v5.sst.value(
  input: Bytes.Bytes,
  field: Maybe<&2, U32>
) -> Result<&1, &1, Error, ManifestValue>:
  match field:
    case None{}: Fail{Malformed{}}
    case Some{file_id}:
      decode.checksum(input, GenerationSst{file_id}, 28, 60)

def decode.v5.sst.field(
  pair: Bytes.Bytes & Maybe<&2, U32>
) -> Result<&1, &1, Error, ManifestValue>:
  match pair:
    case (input, field): decode.v5.sst.value(input, field)

def decode.v5.sst.count.value(
  input: Bytes.Bytes,
  count_field: Maybe<&2, U32>
) -> Result<&1, &1, Error, ManifestValue>:
  match count_field:
    case None{}: Fail{Malformed{}}
    case Some{0}:
      decode.checksum(input, GenerationEmpty{}, 24, 56)
    case Some{1}:
      decode.v5.sst.field(Bytes.get.u32be(input, 24))
    case _: Fail{Malformed{}}

def decode.v5.sst.count.field(
  pair: Bytes.Bytes & Maybe<&2, U32>
) -> Result<&1, &1, Error, ManifestValue>:
  match pair:
    case (input, field): decode.v5.sst.count.value(input, field)

def decode.v5.level_count.value(
  input: Bytes.Bytes,
  field: Maybe<&2, U32>
) -> Result<&1, &1, Error, ManifestValue>:
  match field:
    case None{}: Fail{Malformed{}}
    case Some{1}:
      decode.v5.sst.count.field(Bytes.get.u32be(input, 20))
    case _: Fail{Malformed{}}

def decode.v5.level_count.field(
  pair: Bytes.Bytes & Maybe<&2, U32>
) -> Result<&1, &1, Error, ManifestValue>:
  match pair:
    case (input, field): decode.v5.level_count.value(input, field)

def decode.v5.level_count(input: Bytes.Bytes) -> Result<&1, &1, Error, ManifestValue>:
  decode.v5.level_count.field(Bytes.get.u32be(input, 16))

def decode.v5.comparator.value(
  input: Bytes.Bytes,
  field: Maybe<&2, U32>
) -> Result<&1, &1, Error, ManifestValue>:
  match field:
    case None{}: Fail{Malformed{}}
    case Some{1}:
      decode.v5.level_count(input)
    case Some{generation}: Fail{ComparatorMismatch{generation}}

def decode.v5.comparator.field(
  pair: Bytes.Bytes & Maybe<&2, U32>
) -> Result<&1, &1, Error, ManifestValue>:
  match pair:
    case (input, field): decode.v5.comparator.value(input, field)

def decode.v5.comparator(input: Bytes.Bytes) -> Result<&1, &1, Error, ManifestValue>:
  decode.v5.comparator.field(Bytes.get.u32be(input, 12))

# Rejects unknown storage generations before comparator validation.
def decode.version.value(
  input: Bytes.Bytes,
  field: Maybe<&2, U32>
) -> Result<&1, &1, Error, ManifestValue>:
  match field:
    case None{}: Fail{Malformed{}}
    case Some{4}: decode.comparator(input)
    case Some{5}: decode.v5.comparator(input)
    case Some{generation}: Fail{UnsupportedVersion{generation}}

def decode.version.field(
  pair: Bytes.Bytes & Maybe<&2, U32>
) -> Result<&1, &1, Error, ManifestValue>:
  match pair:
    case (input, field): decode.version.value(input, field)

def decode.version(input: Bytes.Bytes) -> Result<&1, &1, Error, ManifestValue>:
  decode.version.field(Bytes.get.u32be(input, 8))

# Checks the magic before interpreting version fields.
def decode.magic(input: Bytes.Bytes, valid: Bool) -> Result<&1, &1, Error, ManifestValue>:
  match valid:
    case False{}: Fail{Malformed{}}
    case True{}: decode.version(input)

def decode.magic.pair(pair: Bytes.Bytes & Bool) -> Result<&1, &1, Error, ManifestValue>:
  match pair:
    case (input, valid): decode.magic(input, valid)

def decode.magic.copies(
  copies: Bytes.Bytes & Bytes.Bytes
) -> Result<&1, &1, Error, ManifestValue>:
  match copies:
    case (input, for_magic):
      decode.magic.pair((input,
        equal(Bytes.eq(slice.result(Bytes.slice(for_magic, 0, 8)), magic()))))

# Validates the size before reading fixed header fields.
def decode.sized.check_magic(bytes: Bytes.Bytes) -> Result<&1, &1, Error, ManifestValue>:
  decode.magic.copies(clone.split(bytes))

def decode.sized.valid(bytes: Bytes.Bytes, valid: Bool) -> Result<&1, &1, Error, ManifestValue>:
  match valid:
    case False{}: Fail{Malformed{}}
    case True{}: decode.sized.check_magic(bytes)

# Validates the size before reading fixed header fields.
def decode.sized(input: Bytes.Bytes & U32) -> Result<&1, &1, Error, ManifestValue>:
  match input:
    case (bytes, size):
      match size:
        case 56: decode.sized.valid(bytes, True{})
        case 63: decode.sized.valid(bytes, True{})
        case 60: decode.sized.valid(bytes, True{})
        case _: decode.sized.valid(bytes, False{})

# Decodes bounded generation-four and generation-five byte manifests.
def decode(input: Bytes.Bytes) -> Result<&1, &1, Error, ManifestValue>:
  decode.sized(Bytes.length(input))

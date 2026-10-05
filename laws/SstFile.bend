import Base
import ../src/SstFile.bend as SstFile
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes
import ../src/MemTable.bend as MemTable
import ../src/Sstable.bend as Sstable

def empty_first_chunk.got(pair: SstFile.Encoder & Maybe<&1, Bytes.Bytes>) -> Bool:
  match pair:
    case (_, Some{chunk}):
      String.eq(Bytes.to_hex(chunk), "4d594c534d335300000000000000000000000000")
    case (_, None{}):
      False{}

def empty_first_chunk.result(result: Result<&1, &1, SstFile.Error, SstFile.Encoder>) -> Bool:
  match result:
    case Done{encoder}:
      empty_first_chunk.got(SstFile.next_chunk(encoder))
    case Fail{_}:
      False{}

# Empty SST starts with the pinned v3 magic, level, entry count, and block count.
law empty_header_fixture:
  {empty_first_chunk.result(SstFile.new_encoder(Nil{}, 0)) == True{} : Bool}

# Levels outside the public v3 range are rejected.
law invalid_level_rejected:
  {SstFile.new_encoder(Nil{}, 256) == Fail{SstFile.InvalidLevel{}} : Result<&1, &1, SstFile.Error, SstFile.Encoder>}

# Empty input cannot be mistaken for a valid table or a fresh database.
law empty_input_rejected:
  {SstFile.finish(SstFile.new_decoder()) == Fail{SstFile.Malformed{}} : Result<&1, &1, SstFile.Error, Sstable.Table>}

# Duplicate and descending keys cannot be emitted into a sorted SST.
law unordered_input_rejected:
  {SstFile.new_encoder([MemTable.Entry{"z", None{}}, MemTable.Entry{"a", None{}}], 0) == Fail{SstFile.InvalidOrder{}} : Result<&1, &1, SstFile.Error, SstFile.Encoder>}

def small_encoder.block_count(result: Result<&1, &1, SstFile.Error, SstFile.Encoder>) -> U32:
  match result:
    case Fail{_}:
      0
    case Done{SstFile.Enc{phase, chunks, level, total, block_count, footer}}:
      block_count

# Small ordered records share one bounded payload block.
law small_records_share_block:
  {small_encoder.block_count(SstFile.new_encoder([MemTable.Entry{"a", Some{"one"}}, MemTable.Entry{"b", None{}}], 0)) == 1 : U32}

# State the packed record measure uses utf8 byte lengths property for the SSTable codec laws.
law packed_record_measure_uses_utf8_byte_lengths:
  {SstFile.blocks.measure.next(Con{MemTable.Entry{"é", Some{"😀"}}, Nil{}}, 0) == SstFile.Measured{15, True{}} : SstFile.BlockMeasure}

# Join bounded literal pieces of an independently specified binary fixture.
def fixture_hex(parts: List<&2, String>) -> String:
  String.join(parts, "")

def encoded_file.footer(
  encoder: SstFile.Encoder & Maybe<&1, Bytes.Bytes>,
  header: Bytes.Bytes,
  block: Bytes.Bytes
) -> Maybe<&1, Bytes.Bytes>:
  match encoder:
    case (_, Some{footer}):
      Some{Bytes.concat([header, block, footer])}
    case (_, None{}):
      None{}


def encoded_file.result(
  encoder: SstFile.Encoder & Maybe<&1, Bytes.Bytes>,
  header: Bytes.Bytes
) -> Maybe<&1, Bytes.Bytes>:
  match encoder:
    case (state, Some{block}):
      encoded_file.footer(SstFile.next_chunk(state), header, block)
    case (_, None{}):
      None{}

def encoded_file.start(
  pair: SstFile.Encoder & Maybe<&1, Bytes.Bytes>
) -> Maybe<&1, Bytes.Bytes>:
  match pair:
    case (state, Some{header}):
      encoded_file.result(SstFile.next_chunk(state), header)
    case (_, None{}):
      None{}


def encoded_file.one_block(
  result: Result<&1, &1, SstFile.Error, SstFile.Encoder>
) -> Maybe<&1, Bytes.Bytes>:
  match result:
    case Fail{_}:
      None{}
    case Done{encoder}:
      encoded_file.start(SstFile.next_chunk(encoder))

# Encoding the two-record table matches its independent complete-file bytes.
def encoded_file.matches(pair: Maybe<&1, Bytes.Bytes>) -> Bool:
  match pair:
    case None{}:
      False{}
    case Some{bytes}:
      String.eq(Bytes.to_hex(bytes), fixture_hex([
        "4d594c534d3353000000000000000002000000010000001300000002000000000161",
        "000000036f6e650100000001621012d9ef310e6202f583e3147850a529ee745e4cc757",
        "27d50517481018e8ecdb454e443300000002cdcc71e02dc0d6d7b8a863a758e3ca1c",
        "7b21d50283f410ecec580c34c7491d13"]))

def encoded_file.matches_fixture() -> Bool:
  encoded_file.matches(encoded_file.one_block(SstFile.new_encoder([
    MemTable.Entry{"a", Some{"one"}}, MemTable.Entry{"b", None{}}], 0)))

# The v3 encoder emits the independently hashed bytes pinned above.
law encoder_nonempty_file_fixture:
  {encoded_file.matches_fixture() == True{} : Bool}

def empty_fixture.parse(value: Maybe<&1, Bytes.Bytes>) -> Result<&1, &1, SstFile.Error, Sstable.Table>:
  match value:
    case None{}:
      Fail{SstFile.Malformed{}}
    case Some{bytes}:
      SstFile.parse(bytes)

def empty_fixture.decode(hex: String) -> Result<&1, &1, SstFile.Error, Sstable.Table>:
  empty_fixture.parse(Bytes.from_hex(hex))

# Join fixture fragments so long independent byte strings stay readable.
def empty_fixture.accepted(result: Result<&1, &1, SstFile.Error, Sstable.Table>) -> Bool:
  match result:
    case Fail{_}:
      False{}
    case Done{_}:
      True{}

# Closed independently hashed empty-table bytes parse as a valid empty table.
law empty_file_fixture:
  {empty_fixture.accepted(empty_fixture.decode("4d594c534d335300000000000000000000000000454e44330000000070240db76e8e7aefe82e743cfc50be094ce21d8d1aa3a9b14d2a67294276c352")) == True{} : Bool}

# A complete file with a changed root digest fails closed.
law empty_file_bad_root_rejected:
  {
    empty_fixture.decode(fixture_hex([
      "4d594c534d335300000000000000000000000000454e44330000000070240db76e8e7a",
      "efe82e743cfc50be094ce21d8d1aa3a9b14d2a67294276c353"
    ])) == Fail{SstFile.ChecksumMismatch{}} :
      Result<&1, &1, SstFile.Error, Sstable.Table>
  }

def parsed_file.count(result: Result<&1, &1, SstFile.Error, Sstable.Table>) -> Nat:
  match result:
    case Fail{_}:
      0n
    case Done{table}:
      Sstable.table_count(table)

# A complete nonempty v3 file validates its block digest and table root.
law nonempty_file_fixture:
  {
    parsed_file.count(empty_fixture.decode(fixture_hex([
      "4d594c534d335300000000000000000200000001000000130000000200000000016100",
      "0000036f6e650100000001621012d9ef310e6202f583e3147850a529ee745e4cc75727",
      "d50517481018e8ecdb454e443300000002cdcc71e02dc0d6d7b8a863a758e3ca1c7b21",
      "d50283f410ecec580c34c7491d13"
    ]))) == 2n :
      Nat
  }

def stream.fixture.bytes.result(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}:
      bytes
    case None{}:
      Bytes.new(0)

def stream.fixture.bytes(hex: String) -> Bytes.Bytes:
  stream.fixture.bytes.result(Bytes.from_hex(hex))

def stream.fixture.block(
  header: Result<&1, &1, SstFile.Error, SstFile.StreamState>,
  block: Bytes.Bytes
) -> Result<&1, &1, SstFile.Error, SstFile.StreamState>:
  match header:
    case Fail{error}:
      Fail{error}
    case Done{state}:
      SstFile.stream.block(state, block)

def stream.fixture.table(
  state: Result<&1, &1, SstFile.Error, SstFile.StreamState>,
  footer: Bytes.Bytes
) -> Result<&1, &1, SstFile.Error, Sstable.Table>:
  match state:
    case Fail{error}:
      Fail{error}
    case Done{state}:
      SstFile.stream.footer(state, footer)

def stream.nonempty.result() -> Result<&1, &1, SstFile.Error, Sstable.Table>:
  stream.fixture.table(
    stream.fixture.block(SstFile.stream.header(stream.fixture.bytes(
      "4d594c534d335300000000000000000200000001")),
      stream.fixture.bytes("0000001300000002000000000161000000036f6e650100000001621012d9ef310e6202f583e3147850a529ee745e4cc75727d50517481018e8ecdb")),
    stream.fixture.bytes("454e443300000002cdcc71e02dc0d6d7b8a863a758e3ca1c7b21d50283f410ecec580c34c7491d13"))

# State the nonempty file block stream property for the SSTable codec laws.
law nonempty_file_block_stream:
  {parsed_file.count(stream.nonempty.result()) == 2n : Nat}

def fixture.split.tail(
  pair: Bytes.Bytes & Bytes.Bytes,
  first: Bytes.Bytes
) -> Bytes.Bytes & Bytes.Bytes:
  match pair:
    case (_, second):
      (first, second)

def fixture.split.first(
  pair: Bytes.Bytes & Bytes.Bytes,
  +split: U32,
  +length: U32
) -> Bytes.Bytes & Bytes.Bytes:
  match pair:
    case (source, first):
      fixture.split.tail(Bytes.slice(source, split, (length - split : U32)), first)

def fixture.split.size(
  pair: Bytes.Bytes & U32,
  +split: U32
) -> Bytes.Bytes & Bytes.Bytes:
  match pair:
    case (source, +length):
      fixture.split.first(Bytes.slice(source, 0, split), split, length)


def fixture.split(
  bytes: Bytes.Bytes,
  +split: U32
) -> Bytes.Bytes & Bytes.Bytes:
  fixture.split.size(Bytes.length(bytes), split)
def fixture.decode.split(pair: Bytes.Bytes & Bytes.Bytes) -> Result<&1, &1, SstFile.Error, Sstable.Table>:
  match pair:
    case (first, second):
      SstFile.finish(SstFile.feed(
        SstFile.feed(SstFile.new_decoder(), first), second))

def fixture.split.count(pair: Bytes.Bytes & Bytes.Bytes) -> Nat:
  parsed_file.count(fixture.decode.split(pair))

def fixture.split.decoded(
  value: Maybe<&1, Bytes.Bytes>,
  +split: U32
) -> Nat:
  match value:
    case None{}:
      0n
    case Some{bytes}:
      fixture.split.count(fixture.split(bytes, split))

# Splitting input in the header and record payload preserves the decoded table.
law nonempty_file_chunk_boundaries:
  {
    Nat.is_eq(fixture.split.decoded(Bytes.from_hex(fixture_hex([
      "4d594c534d3353000000000000000002000000010000001300000002000000000161",
      "000000036f6e650100000001621012d9ef310e6202f583e3147850a529ee745e4cc757",
      "27d50517481018e8ecdb454e443300000002cdcc71e02dc0d6d7b8a863a758e3ca1c",
      "7b21d50283f410ecec580c34c7491d13"])), 10), 2n) &&
    Nat.is_eq(fixture.split.decoded(Bytes.from_hex(fixture_hex([
      "4d594c534d3353000000000000000002000000010000001300000002000000000161",
      "000000036f6e650100000001621012d9ef310e6202f583e3147850a529ee745e4cc757",
      "27d50517481018e8ecdb454e443300000002cdcc71e02dc0d6d7b8a863a758e3ca1c",
      "7b21d50283f410ecec580c34c7491d13"])), 45), 2n) == True{} : Bool
  }

# A complete nonempty file with a corrupted block digest is rejected.
law nonempty_file_bad_block_rejected:
  {
    empty_fixture.decode(fixture_hex([
      "4d594c534d335300000000000000000200000001000000130000000200000000016100",
      "0000036f6e650100000001621012d9ef310e6202f583e3147850a529ee745e4cc75727",
      "d50517481018e8ecda454e443300000002cdcc71e02dc0d6d7b8a863a758e3ca1c7b21",
      "d50283f410ecec580c34c7491d13"
    ])) == Fail{SstFile.ChecksumMismatch{}} :
      Result<&1, &1, SstFile.Error, Sstable.Table>
  }

# Unsupported levels fail during header validation, before footer checks.
law file_level_out_of_range_rejected:
  {
    empty_fixture.decode(fixture_hex([
      "4d594c534d335300000001000000000000000000454e44330000000000000000000000",
      "000000000000000000000000000000000000000000000000000000000000000000"
    ])) == Fail{SstFile.InvalidLevel{}} :
      Result<&1, &1, SstFile.Error, Sstable.Table>
  }

# A valid empty file followed by extra bytes is not accepted.
law file_trailing_bytes_rejected:
  {
    empty_fixture.decode(fixture_hex([
      "4d594c534d335300000000000000000000000000454e44330000000070240db76e8e7a",
      "efe82e743cfc50be094ce21d8d1aa3a9b14d2a67294276c35200"
    ])) == Fail{SstFile.Malformed{}} :
      Result<&1, &1, SstFile.Error, Sstable.Table>
  }

def parsed_text.result(
  pair: Bytes.Cursor & Result<&1, &1, SstFile.Error, String>
) -> Result<&1, &1, SstFile.Error, String>:
  match pair:
    case (_, result):
      result

def parsed_text.from_hex(
  value: Maybe<&1, Bytes.Bytes>,
  +length: U32
) -> Result<&1, &1, SstFile.Error, String>:
  match value:
    case None{}:
      Fail{SstFile.Malformed{}}
    case Some{bytes}:
      parsed_text.result(SstFile.parse.text(Bytes.Cursor.new(bytes), length))

# UTF-8 fields decode in one bounded pass.
law text_field_multibyte:
  {parsed_text.from_hex(Bytes.from_hex("c3a9"), 2) == Done{"é"} : Result<&1, &1, SstFile.Error, String>}

# Overlong and truncated UTF-8 fields fail without replacement characters.
law text_field_invalid_utf8:
  {parsed_text.from_hex(Bytes.from_hex("c080"), 2) == Fail{SstFile.InvalidUtf8{}} : Result<&1, &1, SstFile.Error, String>}

def parsed_record.result(
  pair: Bytes.Cursor & Result<&1, &1, SstFile.Error, SstFile.ParsedRecord>
) -> Result<&1, &1, SstFile.Error, SstFile.ParsedRecord>:
  match pair:
    case (_, result):
      result

def parsed_record.from_hex(
  value: Maybe<&1, Bytes.Bytes>
) -> Result<&1, &1, SstFile.Error, SstFile.ParsedRecord>:
  match value:
    case None{}:
      Fail{SstFile.Malformed{}}
    case Some{bytes}:
      parsed_record.result(SstFile.parse.record(Bytes.Cursor.new(bytes)))

# Put and delete records decode their exact declared UTF-8 fields.
law put_record_fixture:
  {parsed_record.from_hex(Bytes.from_hex("000000000161000000036f6e65")) == Done{SstFile.Rec{MemTable.Entry{"a", Some{"one"}}, 13}} : Result<&1, &1, SstFile.Error, SstFile.ParsedRecord>}

# A delete record decodes its exact key and byte count.
law delete_record_fixture:
  {parsed_record.from_hex(Bytes.from_hex("010000000161")) == Done{SstFile.Rec{MemTable.Entry{"a", None{}}, 6}} : Result<&1, &1, SstFile.Error, SstFile.ParsedRecord>}

# Invalid UTF-8 in an on-disk key is rejected by the record parser.
law invalid_utf8_record_rejected:
  {parsed_record.from_hex(Bytes.from_hex("0000000001c000000000")) == Fail{SstFile.InvalidUtf8{}} : Result<&1, &1, SstFile.Error, SstFile.ParsedRecord>}

def parsed_entries.result(
  pair: Bytes.Cursor & Result<&1, &1, SstFile.Error, SstFile.ParsedEntries>
) -> Result<&1, &1, SstFile.Error, SstFile.ParsedEntries>:
  match pair:
    case (_, result):
      result

def parsed_entries.from_hex(
  value: Maybe<&1, Bytes.Bytes>,
  +count: U32,
  +payload_len: U32
) -> Result<&1, &1, SstFile.Error, SstFile.ParsedEntries>:
  match value:
    case None{}:
      Fail{SstFile.Malformed{}}
    case Some{bytes}:
      parsed_entries.result(SstFile.parse.records.start(
        Bytes.Cursor.new(bytes), count, payload_len, None{}))

# Multiple records consume exactly their block payload and preserve strict order.
law records_block_fixture:
  {
    parsed_entries.from_hex(Bytes.from_hex("000000000161000000036f6e65010000000162"), 2, 19)
      == Done{SstFile.Entries{[MemTable.Entry{"b", None{}}, MemTable.Entry{"a", Some{"one"}}], Some{"b"}}} :
      Result<&1, &1, SstFile.Error, SstFile.ParsedEntries>
  }

# Duplicate keys within one block are rejected.
law duplicate_record_keys_rejected:
  {parsed_entries.from_hex(Bytes.from_hex("010000000161010000000161"), 2, 12) == Fail{SstFile.InvalidOrder{}} : Result<&1, &1, SstFile.Error, SstFile.ParsedEntries>}

def parsed_block.result(
  pair: Bytes.Cursor & Result<&1, &1, SstFile.Error, SstFile.ParsedBlock>
) -> Result<&1, &1, SstFile.Error, SstFile.ParsedBlock>:
  match pair:
    case (_, result):
      result

def parsed_block.from_hex(
  value: Maybe<&1, Bytes.Bytes>
) -> Result<&1, &1, SstFile.Error, SstFile.ParsedBlock>:
  match value:
    case None{}:
      Fail{SstFile.Malformed{}}
    case Some{bytes}:
      parsed_block.result(SstFile.parse.block(Bytes.Cursor.new(bytes), None{}))

# A block fixture pins entry decoding, payload lengths, and the independent SHA-256 digest.
law block_fixture:
  {
    parsed_block.from_hex(Bytes.from_hex(fixture_hex([
      "0000001300000002000000000161000000036f6e650100000001621012d9ef310e6202",
      "f583e3147850a529ee745e4cc75727d50517481018e8ecdb"])))
      == Done{SstFile.ParsedBlock{
        SstFile.Entries{
          [MemTable.Entry{"b", None{}},
            MemTable.Entry{"a", Some{"one"}}],
          Some{"b"}},
        2,
        SstFile.hex_bytes.fin(Bytes.from_hex(
          "1012d9ef310e6202f583e3147850a529ee745e4cc75727d50517481018e8ecdb"))}} :
      Result<&1, &1, SstFile.Error, SstFile.ParsedBlock>
  }

# A complete block with a changed digest is corruption, not a partial result.
law block_bad_digest_rejected:
  {
    parsed_block.from_hex(Bytes.from_hex(fixture_hex(["0000001300000002000000000161000000036f6e650100000001621012d9ef310e6202", "f583e3147850a529ee745e4cc75727d50517481018e8ecda"])))
      == Fail{SstFile.ChecksumMismatch{}} :
      Result<&1, &1, SstFile.Error, SstFile.ParsedBlock>
  }

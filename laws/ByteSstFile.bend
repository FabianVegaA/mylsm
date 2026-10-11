import Base
import ../src/ByteMemTable.bend as ByteMemTable
import ../src/ByteSstFile.bend as ByteSstFile
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Builds the smallest accepted multi-block header fixture.
def valid_stream_header() -> Bytes.Bytes:
  Bytes.concat([ByteSstFile.header.magic(), ByteSstFile.u32.bytes(0),
    ByteSstFile.u32.bytes(0), ByteSstFile.u32.bytes(1)])

# Builds a two-block header matching the authenticated stream fixture.
def valid_stream_file_header() -> Bytes.Bytes:
  ByteSstFile.marker(Bytes.from_hex("4d594c534d345300000000000000000200000002"))

# Returns the serialized index for the two-block stream fixture.
def valid_stream_index() -> Bytes.Bytes:
  ByteSstFile.marker(Bytes.from_hex(
    "4944583400000002000000140009281a0009282e0009281b"))

# Returns the block checksums covered by the stream root fixture.
def valid_stream_checksums() -> Bytes.Bytes:
  ByteSstFile.marker(Bytes.from_hex(
    "1c8a2b2cafd524871ae3c02abfecfc6fc3b0c744100db353a1bc23b443e7efa904c6c1e0b5f49f165d9ff14279383cb0dc246cfe61e22f4a9afa91a7570b6272"))

# Returns the encoded offsets and lengths from the stream index fixture.
def valid_stream_entries() -> Bytes.Bytes:
  ByteSstFile.marker(Bytes.from_hex("000000140009281a0009282e0009281b"))

# Returns a footer authenticating the raw stream sections.
def valid_stream_footer() -> Bytes.Bytes:
  ByteSstFile.marker(Bytes.from_hex(
    "454e4434000000022b4673920c9fb7325df0f13e1e94a87d60a66dfb5749abac8dd00055731b815c"))

# Accepts the generation-four marker and bounded header fields.
law stream_header_accepts_valid_metadata:
  {ByteSstFile.parse_stream_header.accepted(
    ByteSstFile.parse_stream_header(valid_stream_header())) == True{} : Bool}

# Rejects headers whose generation marker is not recognized.
law stream_header_rejects_unknown_marker:
  {ByteSstFile.parse_stream_header.accepted(
    ByteSstFile.parse_stream_header(Bytes.set(valid_stream_header(), 0, 0))) == False{} : Bool}

# Rejects stream metadata whose serialized index differs from page entries.
law stream_finish_rejects_an_index_that_does_not_match_the_pages:
  {ByteSstFile.parse_stream_finish.accepted(ByteSstFile.parse_stream_finish(
    valid_stream_header(), Bytes.new(0), Bytes.new(0), Bytes.new(0),
    Bytes.new(0), 0, 1)) == False{} : Bool}

# Accepts a footer whose root covers the serialized stream sections directly.
law stream_finish_accepts_a_valid_root_over_raw_sections:
  {ByteSstFile.parse_stream_finish.accepted(ByteSstFile.parse_stream_finish(
    valid_stream_file_header(), valid_stream_checksums(),
    valid_stream_entries(), valid_stream_index(), valid_stream_footer(), 2, 2))
    == True{} : Bool}

# A one-byte key and value encode to eleven record bytes.
law put_record_size_includes_fields:
  {ByteSstFile.records.size(Con{ByteMemTable.Entry{Bytes.new(1), Some{Bytes.new(1)}}, Nil{}}, 1n) == 11n : Nat}

# A one-byte tombstone key encodes to six record bytes.
law delete_record_size_includes_tag_and_key_length:
  {ByteSstFile.records.size(Con{ByteMemTable.Entry{Bytes.new(1), None{}}, Nil{}}, 1n) == 6n : Nat}

# A record payload fitting the frame overhead is accepted at the block limit.
law block_payload_accepts_exact_limit:
  {ByteSstFile.block.payload.allowed(1048536n) == True{} : Bool}

# A record payload exceeding the block limit by one byte is rejected.
law block_payload_rejects_limit_overflow:
  {ByteSstFile.block.payload.allowed(1048537n) == False{} : Bool}

# Page construction starts a second block when the next exact record size crosses the cap.
law byte_sst_pages_roll_over_at_the_limit:
  {ByteSstFile.pages.count(ByteSstFile.page.build.limit([
    ByteMemTable.Entry{Bytes.new(1), Some{Bytes.new(1)}},
    ByteMemTable.Entry{Bytes.new(2), Some{Bytes.new(1)}}
  ], 60n)) == 2n : Nat}

# Page construction keeps the same records together when the larger cap fits them.
law byte_sst_pages_fill_available_capacity:
  {ByteSstFile.pages.count(ByteSstFile.page.build.limit([
    ByteMemTable.Entry{Bytes.new(1), Some{Bytes.new(1)}},
    ByteMemTable.Entry{Bytes.new(2), Some{Bytes.new(1)}}
  ], 64n)) == 1n : Nat}

import Base
import ../../src/ByteMemTable.bend as ByteMemTable
import ../../src/ByteSstFile.bend as ByteSstFile
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Keeps independent file images for successful parsing and corruption checks.
type FileCopies is Type:
  FileCopies{signature: Bytes.Bytes, parsed: Bytes.Bytes, corrupt: Bytes.Bytes}

# Unwraps fixed hexadecimal bytes used by the file fixture.
def packed(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}:
      bytes
    case None{}:
      Bytes.new(0)

def clone.pair(+len: U32, copied: Array<U32> & Array<U32>) -> Bytes.Bytes & Bytes.Bytes:
  match copied:
    case (left, right):
      (Bytes.Bytes{len, left}, Bytes.Bytes{len, right})

def clone.split(bytes: Bytes.Bytes) -> Bytes.Bytes & Bytes.Bytes:
  match bytes:
    case Bytes.Bytes{+len, buf}:
      clone.pair(len, Bytes.copy.bytes(len, buf, Bytes.alloc(len), 0, 0))

def clone.triple.done(
  signature: Bytes.Bytes,
  pair: Bytes.Bytes & Bytes.Bytes
) -> FileCopies:
  match pair:
    case (parsed, corrupt):
      FileCopies{signature, parsed, corrupt}

def clone.triple.rest(pair: Bytes.Bytes & Bytes.Bytes) -> FileCopies:
  match pair:
    case (signature, remaining):
      clone.triple.done(signature, clone.split(remaining))

def clone.triple(bytes: Bytes.Bytes) -> FileCopies:
  clone.triple.rest(clone.split(bytes))

# Extracts the byte equality result for the signature.
def signature.equal(result: Bytes.Bytes & Bytes.Bytes & Bool) -> Bool:
  match result:
    case (_, _, equal):
      equal

# Compares the returned signature with the generation-four marker.
def signature.result(pair: Bytes.Bytes & Bytes.Bytes) -> Bool:
  match pair:
    case (source, signature):
      signature.equal(Bytes.eq(signature, packed(Bytes.from_hex("4d594c534d345300"))))

# Checks that an encoded file carries the generation-four SST signature.
def signature.matches(file: Bytes.Bytes) -> Bool:
  signature.result(Bytes.slice(file, 0, 8))

# Verifies the decoded table preserves a value that is not valid UTF-8.
def value.matches(pair: ByteMemTable.Table & Maybe<&1, Bytes.Bytes>) -> Bool:
  match pair:
    case (_, Some{value}):
      signature.equal(Bytes.eq(value, packed(Bytes.from_hex("80ff00"))))
    case _:
      False{}

# Reports whether parser output preserves the raw stored bytes.
def checked.value(valid: Bool) -> IO(Unit):
  match valid:
    case True{}:
      IO.print("byte SST v4 one-block round-trip passed")
    case False{}:
      IO.die(Unit, 1, "byte SST v4 changed a raw value")

# Checks the table returned by the generation-four parser.
def checked.parsed(result: Result<&1, &1, ByteSstFile.Error, ByteMemTable.Table>) -> IO(Unit):
  match result:
    case Fail{ByteSstFile.Malformed{}}:
      IO.die(Unit, 1, "byte SST v4 parsing returned malformed")
    case Fail{ByteSstFile.ChecksumMismatch{}}:
      IO.die(Unit, 1, "byte SST v4 checksum mismatch")
    case Fail{_}:
      IO.die(Unit, 1, "byte SST v4 parsing failed")
    case Done{table}:
      checked.value(value.matches(ByteMemTable.get(table,
        packed(Bytes.from_hex("610062")))))

def corrupt.index(pair: Bytes.Bytes & Maybe<&2, U32>) -> Bytes.Bytes:
  match pair:
    case (file, Some{payload_len}):
      Bytes.set(file, (60 + payload_len : U32), 0)
    case (file, None{}):
      Bytes.set(file, 0, 0)


def checked.corrupt.result(
  result: Result<&1, &1, ByteSstFile.Error, ByteMemTable.Table>
) -> IO(Unit):
  match result:
    case Fail{ByteSstFile.ChecksumMismatch{}}:
      IO.print("byte SST v4 index corruption rejected")
    case _:
      IO.die(Unit, 1, "byte SST v4 accepted a corrupted index")

def checked.corrupt(file: Bytes.Bytes) -> IO(Unit):
  checked.corrupt.result(ByteSstFile.parse_file(corrupt.index(Bytes.get.u32be(file, 20))))


# Reports whether the encoded file begins with the expected v4 marker.
def checked.signature(valid: Bool) -> IO(Unit):
  match valid:
    case True{}:
      IO.print("byte SST v4 writer signature passed")
    case False{}:
      IO.die(Unit, 1, "byte SST v4 file has the wrong signature")

# Runs the parser only after verifying the generated format signature.
def checked.signature.and.parse(
  valid: Bool,
  result: Result<&1, &1, ByteSstFile.Error, ByteMemTable.Table>
) -> IO(Unit):
  match valid:
    case True{}:
      checked.parsed(result)
    case False{}:
      IO.die(Unit, 1, "byte SST v4 file has the wrong signature")

# Rejects any encoder or file-identity failure.
def checked.files(files: FileCopies) -> IO(Unit):
  match files:
    case FileCopies{signature, parsed, corrupt}:
      do IO<Unit>:
        _parsed : Unit <- checked.signature.and.parse(signature.matches(signature),
          ByteSstFile.parse_file(parsed))
        checked.corrupt(corrupt)

# Fails the fixture at the first encode, parse, or integrity mismatch.
def checked(result: Result<&1, &1, ByteSstFile.Error, Bytes.Bytes>) -> IO(Unit):
  match result:
    case Fail{_}:
      IO.die(Unit, 1, "byte SST v4 encoding failed")
    case Done{file}:
      checked.files(clone.triple(file))

def checked.multi.header.count(valid: Bool) -> IO(Unit):
  match valid:
    case True{}:
      IO.print("byte SST v4 multi-block header passed")
    case False{}:
      IO.die(Unit, 1, "byte SST v4 writer did not declare two blocks")


def checked.multi.header(
  result: Result<&1, &1, ByteSstFile.Error, ByteSstFile.MultiHeader>
) -> IO(Unit):
  match result:
    case Done{ByteSstFile.MultiHeader{_, _, _, block_count}}:
      checked.multi.header.count(U32.is_eq(block_count, 2))
    case _:
      IO.die(Unit, 1, "byte SST v4 writer did not declare two blocks")

def checked.multi.header.rejected(
  result: Result<&1, &1, ByteSstFile.Error, ByteSstFile.MultiHeader>
) -> IO(Unit):
  match result:
    case Fail{ByteSstFile.Malformed{}}:
      IO.print("byte SST v4 invalid header rejected")
    case _:
      IO.die(Unit, 1, "byte SST v4 accepted an invalid stream header")

def checked.multi.header.copies(copies: Bytes.Bytes & Bytes.Bytes) -> IO(Unit):
  match copies:
    case (valid, corrupt):
      do IO<Unit>:
        _valid : Unit <- checked.multi.header(
          ByteSstFile.parse_stream_header(valid))
        checked.multi.header.rejected(ByteSstFile.parse_stream_header(
          Bytes.set(corrupt, 0, 0)))

def checked.multi.header.file(file: Bytes.Bytes) -> IO(Unit):
  checked.multi.header.copies(clone.split(file))
def checked.multi.parsed.result(matches: Bool) -> IO(Unit):
  match matches:
    case True{}:
      IO.print("byte SST v4 multi-block round-trip passed")
    case False{}:
      IO.die(Unit, 1, "byte SST v4 multi-block changed its records")

def checked.multi.parsed(
  result: Result<&1, &1, ByteSstFile.Error, ByteMemTable.Table>
) -> IO(Unit):
  match result:
    case Fail{_}:
      IO.die(Unit, 1, "byte SST v4 multi-block round-trip failed")
    case Done{table}:
      checked.multi.parsed.result(Nat.is_eq(ByteMemTable.count(table), 2n))

def checked.multi.corrupt.offset(
  pair: Bytes.Bytes & Maybe<&2, U32>
) -> Bytes.Bytes:
  match pair:
    case (file, Some{offset}):
      Bytes.set(file, U32.add(offset, 16), 255)
    case (file, None{}):
      Bytes.set(file, 0, 0)

def checked.multi.corrupt.size(measured: Bytes.Bytes & U32) -> Bytes.Bytes:
  match measured:
    case (indexed_file, +size):
      checked.multi.corrupt.offset(Bytes.get.u32be(indexed_file,
        U32.add(U32.sub(size, 64), 16)))

def checked.multi.corrupt(file: Bytes.Bytes) -> Bytes.Bytes:
  checked.multi.corrupt.size(Bytes.length(file))

def checked.multi.corruption.rejected(
  result: Result<&1, &1, ByteSstFile.Error, ByteMemTable.Table>
) -> IO(Unit):
  match result:
    case Fail{_}:
      IO.print("byte SST v4 late-block corruption rejected")
    case Done{_}:
      IO.die(Unit, 1, "byte SST v4 accepted a corrupt later block")

def checked.multi.files(files: FileCopies) -> IO(Unit):
  match files:
    case FileCopies{signature, parsed, corrupt}:
      do IO<Unit>:
        _header : Unit <- checked.multi.header.file(signature)
        _parsed : Unit <- checked.multi.parsed(ByteSstFile.parse_file(parsed))
        checked.multi.corruption.rejected(
          ByteSstFile.parse_file(checked.multi.corrupt(corrupt)))

def checked.multi.result(
  result: Result<&1, &1, ByteSstFile.Error, Bytes.Bytes>
) -> IO(Unit):
  match result:
    case Fail{_}:
      IO.die(Unit, 1, "byte SST v4 multi-block encoding failed")
    case Done{file}:
      checked.multi.files(clone.triple(file))

def checked.multi() -> IO(Unit):
  checked.multi.result(ByteSstFile.encode_file(Con{
    ByteMemTable.Entry{packed(Bytes.from_hex("61")),
      Some{Bytes.new(600000)}}, Con{
    ByteMemTable.Entry{packed(Bytes.from_hex("62")),
      Some{Bytes.new(600000)}}, Nil{}}}, 0))

def checked.page.size(valid: Bool) -> IO(Unit):
  match valid:
    case True{}:
      IO.print("byte SST v4 page length passed")
    case False{}:
      IO.die(Unit, 1, "byte SST v4 page length disagrees with its payload")

def checked.page.payload(
  payload: Bytes.Bytes & Maybe<&2, U32>,
  measured: Bytes.Bytes & U32
) -> IO(Unit):
  match payload:
    case (_, Some{payload_len}):
      match measured:
        case (_, size):
          checked.page.size(U32.is_gt(size, (116 + payload_len : U32)))
    case _:
      IO.die(Unit, 1, "byte SST v4 page payload length is missing")

def checked.page.copies(copies: Bytes.Bytes & Bytes.Bytes) -> IO(Unit):
  match copies:
    case (size_input, payload_input):
      checked.page.payload(Bytes.get.u32be(payload_input, 20),
        Bytes.length(size_input))

def checked.block.parsed(
  result: Result<&1, &1, ByteSstFile.Error, ByteMemTable.Table>
) -> IO(Unit):
  match result:
    case Fail{_}:
      IO.die(Unit, 1, "byte SST v4 block parser rejected a valid block")
    case Done{table}:
      checked.value(value.matches(ByteMemTable.get(table,
        packed(Bytes.from_hex("610062")))))

def checked.block.corruption(
  result: Result<&1, &1, ByteSstFile.Error, ByteMemTable.Table>
) -> IO(Unit):
  match result:
    case Fail{ByteSstFile.ChecksumMismatch{}}:
      IO.print("byte SST v4 block checksum rejected")
    case _:
      IO.die(Unit, 1, "byte SST v4 accepted a corrupt block checksum")

def checked.block.corrupt(block: Bytes.Bytes & U32) -> IO(Unit):
  match block:
    case (bytes, +size):
      checked.block.corruption(ByteSstFile.parse_block(
        Bytes.set(bytes, U32.sub(size, 1), 255)))

def checked.block.copies(copies: Bytes.Bytes & Bytes.Bytes) -> IO(Unit):
  match copies:
    case (valid, corrupt):
      do IO<Unit>:
        _parsed : Unit <- checked.block.parsed(ByteSstFile.parse_block(valid))
        checked.block.corrupt(Bytes.length(corrupt))

def checked.block.bytes(pair: Bytes.Bytes & Bytes.Bytes) -> IO(Unit):
  match pair:
    case (_, block):
      checked.block.copies(clone.split(block))

def checked.block.header(
  pair: Bytes.Bytes & Maybe<&2, U32>
) -> IO(Unit):
  match pair:
    case (file, Some{payload_length}):
      checked.block.bytes(Bytes.slice(file, 20,
        U32.add(payload_length, 40)))
    case _:
      IO.die(Unit, 1, "byte SST v4 block header is truncated")



def checked.page.files(files: FileCopies) -> IO(Unit):
  match files:
    case FileCopies{signature, parsed, block_copy}:
      do IO<Unit>:
        _size : Unit <- checked.page.copies(clone.split(signature))
        _block : Unit <- checked.block.header(Bytes.get.u32be(block_copy, 20))
        checked.parsed(ByteSstFile.parse_file(parsed))

def checked.page.result(
  result: Result<&1, &1, ByteSstFile.Error, Bytes.Bytes>
) -> IO(Unit):
  match result:
    case Fail{_}:
      IO.die(Unit, 1, "byte SST v4 page encoding failed")
    case Done{file}:
      checked.page.files(clone.triple(file))

def checked.paged.single() -> IO(Unit):
  checked.page.result(ByteSstFile.encode_file.limit(Con{
    ByteMemTable.Entry{packed(Bytes.from_hex("610062")),
      Some{packed(Bytes.from_hex("80ff00"))}}, Con{
    ByteMemTable.Entry{packed(Bytes.from_hex("62")), Some{Bytes.new(0)}}, Nil{}}},
    0, 200n))

def main() -> IO(Unit):
  do IO<Unit>:
    _single : Unit <- checked(ByteSstFile.encode_file(Con{
    ByteMemTable.Entry{packed(Bytes.from_hex("610062")),
      Some{packed(Bytes.from_hex("80ff00"))}}, Con{
    ByteMemTable.Entry{packed(Bytes.from_hex("62")), Some{Bytes.new(0)}}, Nil{}}}, 0))
    _page : Unit <- checked.paged.single()
    checked.multi()

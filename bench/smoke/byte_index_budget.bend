import Base
import ../../src/Console.bend as Console
import ../../src/Fs.bend as Fs
import ../../src/ByteMemTable.bend as ByteMemTable
import ../../src/ByteSstFile.bend as ByteSstFile
import ../../src/ByteSstIo.bend as ByteSstIo
import ../../src/scan/ByteBlockReader.bend as ByteBlockReader
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

def equal.result(comparison: Bytes.Bytes & Bytes.Bytes & Bool) -> Bool:
  match comparison:
    case (_, _, equal): equal

def seek.entry.result(reader: ByteBlockReader.Reader, valid: Bool) -> IO(Unit):
  match valid:
    case True{}:
      do IO<Unit>:
        _closed : Result<&1, &1, U32 & String, Unit> <-
          ByteBlockReader.close(reader)
        IO.print("BYTE_INDEX_KEY_SEEK_PASSED")
    case False{}:
      do IO<Unit>:
        _closed : Result<&1, &1, U32 & String, Unit> <-
          ByteBlockReader.close(reader)
        IO.die(Unit, 1, "key seek selected the wrong SST block")

def seek.entry.checked(
  entry: ByteMemTable.Entry,
  reader: ByteBlockReader.Reader
) -> IO(Unit):
  match entry:
    case ByteMemTable.Entry{key, _}:
      seek.entry.result(reader, equal.result(Bytes.eq(key,
        Bytes.set.u32be(Bytes.new(4), 0, 8192))))

def seek.block(result: Result<&1, &1, U32 & String, ByteBlockReader.Step>) -> IO(Unit):
  match result:
    case Fail{(_, message)}: IO.die(Unit, 1, message)
    case Done{ByteBlockReader.Block{reader, entries}}:
      match entries:
        case Con{entry, _}: seek.entry.checked(entry, reader)
        case Nil{}:
          do IO<Unit>:
            _closed : Result<&1, &1, U32 & String, Unit> <-
              ByteBlockReader.close(reader)
            IO.die(Unit, 1, "key seek landed on an empty SST block")
    case Done{ByteBlockReader.End{}}:
      IO.die(Unit, 1, "key seek ended before the target separator")

def seek.position.checked(
  reader: ByteBlockReader.Reader,
  valid: Bool
) -> IO(Unit):
  match reader:
    case ByteBlockReader.Reader{file, state}:
      match valid:
        case False{}:
          do IO<Unit>:
            _closed : Unit <- File.close(file)
            IO.die(Unit, 1, "key seek did not position at the final block")
        case True{}:
          do IO<Unit>:
            next : Result<&1, &1, U32 & String, ByteBlockReader.Step> <-
              ByteBlockReader.next(ByteBlockReader.Reader{file, state})
            seek.block(next)

def seek.position.reader(reader: ByteBlockReader.Reader) -> IO(Unit):
  match reader:
    case ByteBlockReader.Reader{file, state}:
      match state:
        case ByteBlockReader.State{+size, header, +index_offset, +used,
            total, block_count, +next_block, decoded, root_hash, index_hash,
            last_key, selected}:
          retained_state : ByteBlockReader.State = ByteBlockReader.State{size,
            header, index_offset, used, total, block_count, next_block, decoded,
            root_hash, index_hash, last_key, selected}
          seek.position.checked(
            ByteBlockReader.Reader{file, retained_state},
            U32.is_eq(next_block, 8192))

def seek.selected(
  result: Result<&1, &1, U32 & String, ByteBlockReader.Reader>
) -> IO(Unit):
  match result:
    case Fail{(_, message)}: IO.die(Unit, 1, message)
    case Done{reader}: seek.position.reader(reader)

def seek.opened(
  result: Result<&1, &1, U32 & String, ByteBlockReader.Reader>
) -> IO(Unit):
  match result:
    case Fail{(_, message)}: IO.die(Unit, 1, message)
    case Done{reader}:
      do IO<Unit>:
        selected : Result<&1, &1, U32 & String, ByteBlockReader.Reader> <-
          ByteBlockReader.seek_key_after_validation(reader,
            Bytes.set.u32be(Bytes.new(4), 0, 8192))
        seek.selected(selected)

def seek.start(+path: String) -> IO(Unit):
  do IO<Unit>:
    opened : Result<&1, &1, U32 & String, ByteBlockReader.Reader> <-
      ByteBlockReader.open(path)
    seek.opened(opened)

def entries.build(remaining: Nat, +index: U32) -> List<&1, ByteMemTable.Entry>:
  match remaining:
    case 0n: Nil{}
    case 1n+rest:
      Con{ByteMemTable.Entry{
        Bytes.set.u32be(Bytes.new(4), 0, index), Some{Bytes.new(40)}},
        entries.build(rest, U32.add(index, 1))}

def count.matches(entries: List<&1, ByteMemTable.Entry>, count: Nat) -> Bool:
  Nat.is_eq(List.length(&1, ByteMemTable.Entry, entries), count)

# Reports the result of recovering all entries from a multi-page SST index.
def checked.result(valid: Bool) -> IO(Unit):
  match valid:
    case True{}: IO.print("BYTE_INDEX_PAGED_PASSED")
    case False{}: IO.die(Unit, 1, "paged byte SST returned the wrong entry count")

# Confirms every encoded record survived paged index validation and recovery.
def checked(table: ByteMemTable.Table, count: Nat) -> IO(Unit):
  match table:
    case ByteMemTable.Table{entries}:
      checked.result(count.matches(entries, count))

# Classifies the full SST read result.
def loaded(result: Result<&1, &1, U32 & String, ByteMemTable.Table>, count: Nat) -> IO(Unit):
  match result:
    case Done{table}: checked(table, count)
    case Fail{(_, message)}: IO.die(Unit, 1, message)

# Requires compact metadata validation to cover every indexed block.
def metadata.blocks(large: Bool) -> IO(Unit):
  match large:
    case True{}: IO.print("BYTE_INDEX_METADATA_PASSED")
    case False{}: IO.die(Unit, 1, "metadata validation returned the wrong block count")

# Checks both aggregate record and block counts from the SST header.
def metadata.counts(block_count: U32, +count: Nat, records: Bool) -> IO(Unit):
  match records:
    case False{}: IO.die(Unit, 1, "metadata validation returned the wrong record count")
    case True{}:
      metadata.blocks(U32.is_eq(block_count, U32.from_nat(count)))

# Validates the metadata result and rejects an unreadable SST.
def metadata.checked(
  result: Result<&1, &1, U32 & String, ByteBlockReader.Metadata>,
  +count: Nat
) -> IO(Unit):
  match result:
    case Fail{(_, message)}: IO.die(Unit, 1, message)
    case Done{ByteBlockReader.Metadata{_, +total, block_count, _, _, _}}:
      metadata.counts(block_count, count,
        U32.is_eq(total, U32.from_nat(count)))

# Closes the fixture output before reading it through the bounded reader.
def written(
  pair: File & Result<&1, &1, U32 & String, Unit>,
  +path: String,
  +count: Nat
) -> IO(Unit):
  match pair:
    case (file, Fail{(_, message)}):
      do IO<Unit>:
        _closed : Unit <- File.close(file)
        IO.die(Unit, 1, message)
    case (file, Done{Unit{}}):
      do IO<Unit>:
        _closed : Unit <- File.close(file)
        metadata : Result<&1, &1, U32 & String, ByteBlockReader.Metadata> <-
          ByteSstIo.validate(path)
        metadata.checked(metadata, count)
        seek.start(path)
        result : Result<&1, &1, U32 & String, ByteMemTable.Table> <- ByteSstIo.read(path)
        loaded(result, count)

# Writes the generated SST after validating its exact block count.
def encoded.write(
  +path: String,
  count: Nat,
  bytes: Bytes.Bytes,
  opened: Result<&1, &1, U32 & String, File>
) -> IO(Unit):
  match opened:
    case Fail{(_, message)}: IO.die(Unit, 1, message)
    case Done{file}:
      do IO<Unit>:
        pair : File & Result<&1, &1, U32 & String, Unit> <- Fs.write_bytes(file, bytes)
        written(pair, path, count)

def encoded.count.checked(
  +path: String,
  +count: Nat,
  valid: Bool,
  bytes: Bytes.Bytes,
  opened: Result<&1, &1, U32 & String, File>
) -> IO(Unit):
  match valid:
    case False{}:
      match opened:
        case Fail{(_, message)}: IO.die(Unit, 1, message)
        case Done{file}:
          do IO<Unit>:
            _closed : Unit <- File.close(file)
            IO.die(Unit, 1, "fixture did not encode one block per record")
    case True{}: encoded.write(path, count, bytes, opened)

def encoded.header(
  +path: String,
  +count: Nat,
  parsed: Result<&1, &1, ByteSstFile.Error, ByteSstFile.MultiHeader>,
  bytes: Bytes.Bytes,
  opened: Result<&1, &1, U32 & String, File>
) -> IO(Unit):
  match parsed:
    case Fail{_}: encoded.count.checked(path, count, False{}, bytes, opened)
    case Done{ByteSstFile.MultiHeader{_, _, _, +block_count}}:
      encoded.count.checked(path, count,
        U32.is_eq(block_count, U32.from_nat(count)), bytes, opened)

def encoded.inspect(
  +path: String,
  count: Nat,
  copies: Bytes.Bytes & Bytes.Bytes,
  opened: Result<&1, &1, U32 & String, File>
) -> IO(Unit):
  match copies:
    case (header, bytes):
      encoded.header(path, count, ByteSstFile.parse_stream_header(header),
        bytes, opened)

# Verifies the generated block count before persisting the fixture.
def encoded(
  +path: String,
  count: Nat,
  result: Result<&1, &1, ByteSstFile.Error, Bytes.Bytes>,
  opened: Result<&1, &1, U32 & String, File>
) -> IO(Unit):
  match result:
    case Fail{_}:
      match opened:
        case Fail{(_, message)}: IO.die(Unit, 1, message)
        case Done{file}:
          do IO<Unit>:
            _closed : Unit <- File.close(file)
            IO.die(Unit, 1, "large byte SST fixture encoding failed")
    case Done{bytes}:
      encoded.inspect(path, count, ByteSstFile.clone.split(bytes), opened)

# Builds more index entries than fit in one resident page.
def start(+path: String) -> IO(Unit):
  do IO<Unit>:
    opened : Result<&1, &1, U32 & String, File> <- File.open(path, "w")
    encoded(path, 8193n, ByteSstFile.encode_file.limit(
      entries.build(8193n, 0), 0, 93n), opened)

def main() -> IO(Unit):
  do IO<Unit>:
    +path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    start(path)

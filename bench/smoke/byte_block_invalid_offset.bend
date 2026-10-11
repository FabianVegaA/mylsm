import Base
import ../../src/Console.bend as Console
import ../../src/Fs.bend as Fs
import ../../src/scan/ByteBlockReader.bend as Reader
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Fails the fixture if an invalid serialized block offset is accepted.
def fail(message: String) -> IO(Unit):
  IO.die(Unit, 1, message)

# Reopens the damaged path after rejecting its out-of-range block offset.
def reopened(result: Result<&1, &1, U32 & String, Reader.Reader>) -> IO(Unit):
  match result:
    case Fail{_}: fail("invalid-offset SST could not be reopened")
    case Done{reader}:
      do IO<Unit>:
        _closed : Result<&1, &1, U32 & String, Unit> <- Reader.close(reader)
        IO.print("BYTE_BLOCK_INVALID_OFFSET_PASSED")

# Requires the indexed seek to reject the offset before reading block bytes.
def seek.result(+path: String, result: Result<&1, &1, U32 & String, Reader.Reader>) -> IO(Unit):
  match result:
    case Fail{_}:
      do IO<Unit>:
        again : Result<&1, &1, U32 & String, Reader.Reader> <- Reader.open(path)
        reopened(again)
    case Done{reader}:
      do IO<Unit>:
        _closed : Result<&1, &1, U32 & String, Unit> <- Reader.close(reader)
        fail("indexed seek accepted an out-of-range block offset")

# Requests block zero from the intentionally corrupted index.
def opened(+path: String, result: Result<&1, &1, U32 & String, Reader.Reader>) -> IO(Unit):
  match result:
    case Fail{_}: fail("invalid-offset SST could not open its header")
    case Done{reader}:
      do IO<Unit>:
        selected : Result<&1, &1, U32 & String, Reader.Reader> <-
          Reader.seek_block_after_validation(reader, 0)
        seek.result(path, selected)

# Corrupts the first serialized block offset while preserving file length.
def damaged.index(
  +size: Nat,
  result: Bytes.Bytes & Maybe<&2, U32>
) -> Bytes.Bytes:
  match result:
    case (file, Some{index_length}):
      +index_offset = Nat.sub(size, Nat.add(44n, U32.to_nat(index_length)))
      Bytes.set.u32be(file, U32.from_nat(Nat.add(index_offset, 8n)),
        4294967295)
    case (file, None{}): file

# Creates a same-length file with an invalid first block offset.
def damaged(bytes: Bytes.Bytes, +size: Nat, _: U32) -> Bytes.Bytes:
  damaged.index(size, Bytes.get.u32be(bytes,
    U32.from_nat(Nat.sub(size, 36n))))

# Writes the mutated file and checks the host reader's offset bound.
def write.result(
  +path: String,
  pair: File & Result<&1, &1, U32 & String, Unit>
) -> IO(Unit):
  match pair:
    case (file, Fail{_}):
      do IO<Unit>:
        _closed : Unit <- File.close(file)
        fail("could not write invalid-offset fixture")
    case (file, Done{Unit{}}):
      do IO<Unit>:
        _closed : Unit <- File.close(file)
        reader : Result<&1, &1, U32 & String, Reader.Reader> <- Reader.open(path)
        opened(path, reader)

# Opens the isolated damaged SST output file.
def write.opened(
  +path: String,
  bytes: Bytes.Bytes,
  opened: Result<&1, &1, U32 & String, File>
) -> IO(Unit):
  match opened:
    case Fail{_}: fail("could not create invalid-offset fixture")
    case Done{file}:
      do IO<Unit>:
        written : File & Result<&1, &1, U32 & String, Unit> <- Fs.write_bytes(file, bytes)
        write.result(path, written)

# Creates the corrupted SST only for a nonempty index.
def indexed.nonempty(
  +path: String,
  bytes: Bytes.Bytes,
  size: Nat,
  blocks: U32,
  nonempty: Bool
) -> IO(Unit):
  match nonempty:
    case False{}: fail("SST fixture has no block to index")
    case True{}:
      do IO<Unit>:
        output : Result<&1, &1, U32 & String, File> <- File.open(path ++ ".invalid", "w")
        write.opened(path ++ ".invalid", damaged(bytes, size, blocks), output)

# Validates the index entry location before creating the damaged copy.
def indexed(
  +path: String,
  bytes: Bytes.Bytes,
  size: Nat,
  block_count: Maybe<&2, U32>
) -> IO(Unit):
  match block_count:
    case None{}: fail("SST header has no block count")
    case Some{+blocks}:
      indexed.nonempty(path, bytes, size, blocks, U32.is_gt(blocks, 0))

# Closes the source descriptor before mutating its packed bytes.
def read.result(
  +path: String,
  size: Nat,
  pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>
) -> IO(Unit):
  match pair:
    case (file, Fail{_}):
      do IO<Unit>:
        _closed : Unit <- File.close(file)
        fail("could not read SST bytes")
    case (file, Done{bytes}):
      do IO<Unit>:
        _closed : Unit <- File.close(file)
        indexed(path, bytes, size, Some{2})

# Reads the bounded fixture SST for a same-length index mutation.
def read.opened(
  +path: String,
  +size: Nat,
  opened: Result<&1, &1, U32 & String, File>
) -> IO(Unit):
  match opened:
    case Fail{_}: fail("could not open source SST")
    case Done{file}:
      do IO<Unit>:
        bytes : File & Result<&1, &1, U32 & String, Bytes.Bytes> <-
          Fs.read_at(file, 0, U32.from_nat(size))
        read.result(path, size, bytes)

# Measures and reads the SST selected by the smoke harness.
def source(+path: String, size: Result<&1, &1, U32 & String, Nat>) -> IO(Unit):
  match size:
    case Fail{_}: fail("could not measure source SST")
    case Done{+length}:
      do IO<Unit>:
        input : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
        read.opened(path, length, input)

# Starts the serialized-index offset corruption fixture.
def main() -> IO(Unit):
  do IO<Unit>:
    +path : String <- IO.try(String, Console.get_env("MYLSM_SST_PATH"))
    size : Result<&1, &1, U32 & String, Nat> <- Fs.file_size(path)
    source(path, size)

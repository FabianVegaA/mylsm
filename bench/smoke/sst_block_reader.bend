import Base
import ../../src/Fs.bend as Fs
import ../../src/MemTable.bend as MemTable
import ../../src/SstStreamIo.bend as SstStreamIo
import ../../src/scan/BlockReader.bend as BlockReader

# Supplies one sorted entry to the file-backed reader fixture.
def entries() -> List<&2, MemTable.Entry>:
  [MemTable.Entry{"a", Some{"v"}}]

def check.end(
  result: Result<&1, &1, U32 & String, BlockReader.Step>,
  +path: String
) -> IO(Unit):
  match result:
    case Fail{_}:
      IO.die(Unit, 1, "block reader failed while validating footer")
    case Done{BlockReader.End{}}:
      do IO<Unit>:
        _removed : Result<&1, &1, U32 & String, Unit> <- Fs.remove(path)
        IO.print("SST file-backed block reader passed")
    case Done{BlockReader.Block{reader, _}}:
      do IO<Unit>:
        _closed : Result<&1, &1, U32 & String, Unit> <- BlockReader.close(reader)
        IO.die(Unit, 1, "block reader yielded more than one block")

def check.block(
  result: Result<&1, &1, U32 & String, BlockReader.Step>,
  +path: String
) -> IO(Unit):
  match result:
    case Fail{(_, message)}:
      do IO<Unit>:
        IO.print(message)
        IO.die(Unit, 1, "block reader failed before its first block")
    case Done{BlockReader.End{}}:
      IO.die(Unit, 1, "block reader ended before returning the record")
    case Done{BlockReader.Block{reader, entries}}:
      match entries:
        case [MemTable.Entry{"a", Some{"v"}}]:
          do IO<Unit>:
            result : Result<&1, &1, U32 & String, BlockReader.Step> <-
              BlockReader.next(reader)
            check.end(result, path)
        case _:
          do IO<Unit>:
            _closed : Result<&1, &1, U32 & String, Unit> <- BlockReader.close(reader)
            IO.die(Unit, 1, "block reader returned unexpected entries")

def check.opened(
  opened: Result<&1, &1, U32 & String, BlockReader.Reader>,
  +path: String
) -> IO(Unit):
  match opened:
    case Fail{_}:
      IO.die(Unit, 1, "block reader could not open the SST")
    case Done{reader}:
      do IO<Unit>:
        result : Result<&1, &1, U32 & String, BlockReader.Step> <-
          BlockReader.next(reader)
        check.block(result, path)

def main() -> IO(Unit):
  do IO<Unit>:
    +path : String = ".mylsm-sst-block-reader-smoke.tbl"
    _written : Unit <- IO.try(Unit, SstStreamIo.write_table(path, entries(), 0))
    opened : Result<&1, &1, U32 & String, BlockReader.Reader> <-
      BlockReader.open(path)
    check.opened(opened, path)

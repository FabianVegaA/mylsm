import Base
import ../../src/Fs.bend as Fs
import ../../src/MemTable.bend as MemTable
import ../../src/Sstable.bend as Sstable
import ../../src/SstStreamIo.bend as SstStreamIo

# Include ASCII, multibyte UTF-8, and a tombstone in the binary round trip.
def entries() -> List<&2, MemTable.Entry>:
  [MemTable.Entry{"a", Some{"packed value"}},
   MemTable.Entry{"gone", None{}},
   MemTable.Entry{"é/鍵", Some{"🌋"}}]

def table.matches.value(got: Maybe<&2, String>, want: String) -> Bool:
  match got:
    case None{}:
      False{}
    case Some{value}:
      String.eq(value, want)

def table.matches.deleted(got: Maybe<&2, String>) -> Bool:
  match got:
    case None{}:
      True{}
    case Some{_}:
      False{}

def table.matches(table: Sstable.Table) -> Bool:
  match table:
    case Sstable.Tbl{+entries, filter, nbits, smallest, largest, count, chunks, blocks}:
      Nat.is_eq(count, 3n) &&
      table.matches.value(MemTable.get(MemTable.MT{entries}, "a"), "packed value") &&
      table.matches.value(MemTable.get(MemTable.MT{entries}, "é/鍵"), "🌋") &&
      table.matches.deleted(MemTable.get(MemTable.MT{entries}, "gone"))

# Check decoded content and remove the temporary table on success.
def report(ok: Bool, +path: String) -> IO(Unit):
  match ok:
    case True{}:
      do IO<Unit>:
        _r : Result<&1, &1, U32 & String, Unit> <- Fs.remove(path)
        IO.print("packed SST write/read smoke ok")
    case False{}:
      IO.die(Unit, 1, "packed SST read differs from written entries")

def main() -> IO(Unit):
  do IO<Unit>:
    +path : String = ".mylsm-sst-v3-io-smoke.tbl"
    _w : Unit <- IO.try(Unit, SstStreamIo.write_table(path, entries(), 7))
    table : Sstable.Table <- IO.try(Sstable.Table, SstStreamIo.read_table(path))
    report(table.matches(table), path)

import Base
import ../src/MemTable.bend as MemTable
import ../src/Sstable.bend as Sstable
import ../src/SstFile.bend as SstFile

# Small local fixture duplicated from the merge-iterator domain.
def scan_mem() -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{"b", Some{"v2"}}, Con{MemTable.Entry{"a", Some{"v1"}}, Nil{}}}

# LAW: table file round-trip rebuilds the identical table (closed)
law sstfile_rt:
  {SstFile.parse(SstFile.serialize(scan_mem(), 0n)) == Some{Sstable.build(scan_mem(), 0n, 2n)} : Maybe<&2, Sstable.Table>}

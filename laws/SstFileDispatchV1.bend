import Base
import ../src/MemTable.bend as MemTable
import ../src/Sstable.bend as Sstable
import ../src/SstFile.bend as SstFile

def sst2_put_entries() -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{"a", Some{"1"}}, Con{MemTable.Entry{"b", Some{"20"}}, Nil{}}}

law sst2_dispatch_v1:
  {SstFile.parse(SstFile.serialize_v1(sst2_put_entries(), 1n)) == Some{Sstable.from_sorted_unique(sst2_put_entries(), 1n)} : Maybe<&2, Sstable.Table>}

import Base
import ../src/MemTable.bend as MemTable
import ../src/Sstable.bend as Sstable
import ../src/SstFile.bend as SstFile

def sst2_del_entries() -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{"a", None{}}, Con{MemTable.Entry{"b", Some{"2"}}, Nil{}}}

law sst2_dispatch_v2:
  {SstFile.parse(SstFile.serialize_v2(sst2_del_entries(), 1n)) == Some{Sstable.from_sorted_unique(sst2_del_entries(), 1n)} : Maybe<&2, Sstable.Table>}

import Base
import ../src/MemTable.bend as MemTable
import ../src/Sstable.bend as Sstable
import ../src/SstFileV2.bend as SstFileV2

# Closed SSTable v2 framing vector.
def sst2_del_entries() -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{"a", None{}}, Con{MemTable.Entry{"b", Some{"2"}}, Nil{}}}

law sst2_del_roundtrip:
  {SstFileV2.parse(SstFileV2.serialize(sst2_del_entries(), 1n)) == Some{Sstable.from_sorted_unique(sst2_del_entries(), 1n)} : Maybe<&2, Sstable.Table>}

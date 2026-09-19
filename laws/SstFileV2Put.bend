import Base
import ../src/MemTable.bend as MemTable
import ../src/Sstable.bend as Sstable
import ../src/SstFileV2.bend as SstFileV2

# Closed SSTable v2 framing vector.
def sst2_put_entries() -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{"a", Some{"1"}}, Con{MemTable.Entry{"b", Some{"20"}}, Nil{}}}

law sst2_put_roundtrip:
  {SstFileV2.parse(SstFileV2.serialize(sst2_put_entries(), 1n)) == Some{Sstable.from_sorted_unique(sst2_put_entries(), 1n)} : Maybe<&2, Sstable.Table>}

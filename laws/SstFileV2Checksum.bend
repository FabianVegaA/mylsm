import Base
import ../src/MemTable.bend as MemTable
import ../src/Sstable.bend as Sstable
import ../src/SstFileV2.bend as SstFileV2

# Closed SSTable v2 framing vector.
def sst2_put_entries() -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{"a", Some{"1"}}, Con{MemTable.Entry{"b", Some{"20"}}, Nil{}}}

law sst2_checksum_reject:
  {SstFileV2.parse(SstFileV2.body(sst2_put_entries(), 1n) ++ "#0") == None{} : Maybe<&2, Sstable.Table>}

import Base
import ../src/MemTable.bend as MemTable
import ../src/Sstable.bend as Sstable
import ../src/SstFileV2.bend as SstFileV2

# Closed SSTable v2 framing vector.
law sst2_descending_reject:
  {SstFileV2.parse(SstFileV2.serialize(Con{MemTable.Entry{"b", Some{"2"}}, Con{MemTable.Entry{"a", Some{"1"}}, Nil{}}}, 1n)) == None{} : Maybe<&2, Sstable.Table>}

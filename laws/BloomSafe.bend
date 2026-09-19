import Base
import ../src/MemTable.bend as MemTable
import ../src/Sstable.bend as Sstable

def sst_e1() -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{"b", Some{"2"}}, Con{MemTable.Entry{"a", Some{"1"}}, Nil{}}}

# LAW: bloom never rejects a present key (closed)
law bloom_safe:
  {Sstable.maybe_present(Sstable.build(sst_e1(), 0n, 2n), "a") == True{} : Bool}

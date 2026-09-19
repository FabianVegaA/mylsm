import Base
import ../src/MemTable.bend as MemTable
import ../src/Sstable.bend as Sstable

# LAW: filter bits follow the Monkey schedule (open, definitional)
law bloom_schedule:
  for e: List<&2, MemTable.Entry>
  for l: Nat
  for n: Nat
  {Sstable.table_bits(Sstable.build(e, l, n)) == Sstable.bloom_bits(l, Nat.max(n, List.length(&2, MemTable.Entry, e))) : Nat}

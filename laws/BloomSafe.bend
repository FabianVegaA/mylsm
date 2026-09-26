import Base
import ../src/MemTable.bend as MemTable
import ../src/Sstable.bend as Sstable

def sst_e1() -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{"b", Some{"2"}}, Con{MemTable.Entry{"a", Some{"1"}}, Nil{}}}

# LAW: bloom never rejects a present key (closed)
law bloom_safe:
  {Sstable.maybe_present(Sstable.build(sst_e1(), 0n, 2n), "a") == True{} : Bool}

# Closed table vector for probe-count equivalence.
def probe_tab() -> Sstable.Table:
  Sstable.build(sst_e1(), 0n, 2n)

# Closed probe vector: two hits, one miss.
def probe_qs() -> List<&2, String>:
  Con{"a", Con{"zzz", Con{"b", Nil{}}}}

# LAW: parallel probe counter agrees with sequential (closed)
law probe_par_agrees:
  {Sstable.probe_count_par(probe_qs(), probe_tab()) == Sstable.probe_count_seq(probe_qs(), probe_tab()) : Nat}

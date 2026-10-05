import Base
import ../src/MemTable.bend as MemTable
import ../src/Sstable.bend as Sstable

# State the bloom zero estimate safe property for the Bloom filter estimate laws.
law bloom_zero_estimate_safe:
  {Sstable.maybe_present(Sstable.build(Con{MemTable.Entry{"present", Some{"v"}}, Nil{}}, 1n, 0n), "present") == True{} : Bool}

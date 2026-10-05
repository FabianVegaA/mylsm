import Base
import ../src/Sstable.bend as Sstable

# State the bloom tree well formed property for the Bloom filter tree laws.
law bloom_tree_well_formed:
  {Sstable.bloom_well_formed(Sstable.bloom_new(65n)) == True{} : Bool}

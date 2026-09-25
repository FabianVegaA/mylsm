import Base
import ../src/MemTable.bend as MemTable
import ../src/Sstable.bend as Sstable
import ../src/SstFileV2.bend as SstFileV2

# Tombstone-transition kernel (same no-stream discipline as SstFileV2Put).

law sst2_del_accept:
  {SstFileV2.entry_transition(MemTable.Entry{"a", None{}}, 1n, None{}, Nil{}, 1n, 1n, "", 0n) == SstFileV2.Dec{SstFileV2.NeedHash{}, 0n, Some{"a"}, Con{MemTable.Entry{"a", None{}}, Nil{}}, 1n, 1n, "", 0n} : SstFileV2.Decoder}

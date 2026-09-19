import Base
import ../src/MemTable.bend as MemTable
import ../src/Sstable.bend as Sstable
import ../src/SstFileV2.bend as SstFileV2

# Entry-transition kernel, tested without the byte stream (same checker
# limitation documented in SstFileV2Checksum: end-to-end parse diverges).
# The hash travels as a literal (no accumulation), so these normalize fast.

law sst2_put_accept:
  {SstFileV2.entry_transition(MemTable.Entry{"a", Some{"1"}}, 1n, None{}, Nil{}, 1n, 1n, 0, 0n) == SstFileV2.Dec{SstFileV2.NeedHash{}, 0n, Some{"a"}, Con{MemTable.Entry{"a", Some{"1"}}, Nil{}}, 1n, 1n, 0, 0n} : SstFileV2.Decoder}

import Base
import ../src/Keys.bend as Keys
import ../src/MemTable.bend as MemTable
import ../src/Sstable.bend as Sstable
import ../src/SstFileV2.bend as SstFileV2

# Strict-order kernel: equal keys reject (same no-stream discipline).
# Keys.cmp over 1-char keys normalizes fast.

law sst2_duplicate_reject:
  {SstFileV2.order_decision(Keys.cmp("a", "a"), MemTable.Entry{"a", Some{"new"}}, 1n, Some{"a"}, Nil{}, 1n, 1n, 0, 0n) == SstFileV2.DecoderRejected{SstFileV2.UnsortedOrDuplicate{}} : SstFileV2.Decoder}

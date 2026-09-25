import Base
import ../src/Keys.bend as Keys
import ../src/MemTable.bend as MemTable
import ../src/Sstable.bend as Sstable
import ../src/SstFileV2.bend as SstFileV2

# Strict-order kernel: descending keys reject (same no-stream discipline).

law sst2_descending_reject:
  {SstFileV2.order_decision(Keys.cmp("b", "a"), MemTable.Entry{"a", Some{"1"}}, 1n, Some{"b"}, Nil{}, 1n, 1n, "", 0n) == SstFileV2.DecoderRejected{SstFileV2.UnsortedOrDuplicate{}} : SstFileV2.Decoder}

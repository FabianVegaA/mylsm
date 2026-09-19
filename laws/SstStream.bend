import Base
import ../src/MemTable.bend as MemTable
import ../src/Sstable.bend as Sstable
import ../src/SstFileV2.bend as SstFileV2
import ../src/SstFileV1Fast.bend as SstFileV1Fast
import ../src/SstStream.bend as SstStream

# Chunk-dispatch kernel, tested on 3-byte inputs (no hash accumulation
# reaches the checker-critical length; U32-only chains stay shared).
# End-to-end chunk agreement is covered at runtime (bench smoke).

law sst2_feed_routes_v2:
  {SstStream.feed_mode(SstStream.Unknown{}, "S2;") == SstStream.Current{SstStream.feed_v2("S2;", SstFileV2.Dec{SstFileV2.NeedS{}, 0n, None{}, Nil{}, 0n, 0n, 7, 0n})} : SstStream.Mode}

law sst2_feed_routes_v1:
  {SstStream.feed_mode(SstStream.Unknown{}, "T") == SstStream.Legacy{SstStream.feed_v1("T", SstFileV1Fast.Dec{SstFileV1Fast.NeedT{}, 0n, None{}, True{}, Nil{}, 0n, 0n, 7})} : SstStream.Mode}

law sst2_finish_unknown:
  {SstStream.finish_mode(SstStream.Unknown{}) == Fail{(U32.from_nat(3n), "unknown table version")} : Result<&1, &1, U32 & String, Sstable.Table>}

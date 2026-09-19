import Base
import ../src/MemTable.bend as MemTable
import ../src/Sstable.bend as Sstable
import ../src/SstFile.bend as SstFile
import ../src/SstFileV2.bend as SstFileV2

# Version routing, tested without streams (same discipline as DispatchV1).

law sst2_dispatch_v2_passthrough:
  {SstFile.parse_version(True{}, "X") == SstFileV2.parse("X") : Maybe<&2, Sstable.Table>}

law sst2_dispatch_v2_tag:
  {SstFile.parse("S2;X") == SstFileV2.parse("S2;X") : Maybe<&2, Sstable.Table>}

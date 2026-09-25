import Base
import ../src/Sstable.bend as Sstable
import ../src/SstFile.bend as SstFile
import ../src/SstFileV2.bend as SstFileV2

# Single-version routing: SstFile.parse is SstFileV2.parse.

law sst2_dispatch_v2_tag:
  {SstFile.parse("S2;X") == SstFileV2.parse("S2;X") : Maybe<&2, Sstable.Table>}

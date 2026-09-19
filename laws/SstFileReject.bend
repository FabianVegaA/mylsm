import Base
import ../src/Sstable.bend as Sstable
import ../src/SstFile.bend as SstFile

# LAW: shapeless input rejected fail-closed (closed)
law sstfile_reject:
  {SstFile.parse("garbage") == None{} : Maybe<&2, Sstable.Table>}

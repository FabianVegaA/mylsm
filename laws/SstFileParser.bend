import Base
import ../src/SstFile.bend as SstFile

# Decoder totality: every input reaches a decided fail-closed result.
law sstfile_fail_closed:
  for +s: String
  {SstFile.is_decided(SstFile.parse(s)) == True{} : Bool}

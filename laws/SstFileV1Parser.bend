import Base
import ../src/SstFileV1Fast.bend as SstFileV1Fast

law sst1_fast_parser_decides:
  for s: String
  {SstFileV1Fast.parser_decides(SstFileV1Fast.parse_result(s)) == True{} : Bool}

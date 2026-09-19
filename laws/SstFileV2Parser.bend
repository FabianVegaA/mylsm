import Base
import ../src/SstFileV2.bend as SstFileV2

law sst2_parser_decides:
  for s: String
  {SstFileV2.parser_decides(SstFileV2.parse_result(s)) == True{} : Bool}

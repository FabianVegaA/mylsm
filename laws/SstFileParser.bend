import Base
import ../src/SstFile.bend as SstFile

# Decoder totality: every input reaches a decided fail-closed result.
# Open non-S2 rejection attempted 2026-09-25 (Phase 2D): `{==}` rejected,
# needs decoder induction the checker does not admit. Closed vectors stand.
law sstfile_fail_closed:
  for +s: String
  {SstFile.is_decided(SstFile.parse(s)) == True{} : Bool}

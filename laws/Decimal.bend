import Base
import ../src/Decimal.bend as Decimal

law decimal_internal_zero:
  {Decimal.parse_complete("1010", 2000n) == Decimal.Accepted{Decimal.Dec{1010n, ""}} : Decimal.Parse}

law decimal_leading_zero_reject:
  {Decimal.parse_complete("01", 2000n) == Decimal.Rejected{Decimal.LeadingZero{}} : Decimal.Parse}

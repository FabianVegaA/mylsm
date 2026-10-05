import Base
import ../src/Decimal.bend as Decimal

# State the decimal internal zero property for the decimal conversion laws.
law decimal_internal_zero:
  {Decimal.parse_complete("1010", 2000n) == Decimal.Accepted{Decimal.Dec{1010n, ""}} : Decimal.Parse}

# State the decimal leading zero reject property for the decimal conversion laws.
law decimal_leading_zero_reject:
  {Decimal.parse_complete("01", 2000n) == Decimal.Rejected{Decimal.LeadingZero{}} : Decimal.Parse}

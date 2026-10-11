import Base

# Accepts an interval whose endpoint does not exceed its address-space limit.
def range_valid(limit: Nat, offset: Nat, max: Nat) -> Bool:
  Nat.is_le(offset, Nat.sub(limit, max))

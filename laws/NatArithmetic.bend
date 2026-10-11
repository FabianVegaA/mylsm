import Base

# Every natural number is less than or equal to itself.
law nat_is_le_reflexive:
  for count: Nat
  {Nat.is_le(count, count) == True{} : Bool}

import Base
import ../laws/NatArithmetic.bend as Laws

def Laws.nat_is_le_reflexive(count):
  match count:
    case 0n: {==}
    case 1n+rest: Laws.nat_is_le_reflexive(rest)

import Base
import ./Protocol.bend as Protocol

# Reports one representable count update or exhaustion of the backup format.
type Decision is Data:
  CountContinue{next_count: U32}
  CountLimit{}

# Increments a cursor count without wrapping its fixed-width representation.
def next.checked(count: U32, maximum: Bool) -> Decision:
  match maximum:
    case True{}: CountLimit{}
    case False{}: CountContinue{U32.from_nat(Nat.add(U32.to_nat(count), 1n))}

def next.copies(copies: U32 & U32 & U32) -> Decision:
  match copies:
    case (retained, (checked, _)):
      next.checked(retained, U32.is_eq(checked, 4294967295))

# Advances a cursor count without wrapping past its representable limit.
def next(count: U32) -> Decision:
  next.copies(Protocol.u32.duplicate.triple(count))

def u32.pair.copied(copies: U32 & U32 & U32) -> U32 & U32:
  match copies:
    case (first, (second, _)): (first, second)

def u32.pair(value: U32) -> U32 & U32:
  u32.pair.copied(Protocol.u32.duplicate.triple(value))

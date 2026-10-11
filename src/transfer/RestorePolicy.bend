import Base

# Classifies invalid, terminal, and continuing block traversal states.
type Advance is Data:
  Invalid{}
  Finish{}
  Continue{remaining: Nat}

# Decrements the declared block count exactly once after a validated block.
def after_block(remaining: Nat) -> Advance:
  match remaining:
    case 0n: Invalid{}
    case 1n: Finish{}
    case 1n+rest: Continue{rest}

# Returns the number of blocks left in a continuing traversal.
def remaining(decision: Advance) -> Nat:
  match decision:
    case Continue{remaining}: remaining
    case _: 0n

def write.page.size() -> Nat:
  16n

def write.pages(entries: Nat) -> Nat:
  Nat.div(Nat.add(entries, 15n), write.page.size())

def write.fuel(entries: Nat) -> Nat:
  Nat.add(Nat.mul(3n, write.pages(entries)), 1n)

def max.exchange.bytes() -> Nat:
  67108864n

def exchange.fits(limit: Nat, size: Nat) -> Bool:
  Nat.is_le(size, limit)

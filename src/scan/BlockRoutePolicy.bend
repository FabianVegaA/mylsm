import Base
import ../Keys.bend as Keys
import ../coordinator/QueuePolicy.bend as QueuePolicy
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Holds the binary-search interval and latest eligible block ordinal.
type Search is Data:
  Search{low: Nat, high: Nat, best: Nat}

# Selects the lower or upper half of the separator search interval.
type Move is Data:
  SearchLower{}
  SearchUpper{}

def midpoint.copies(lows: Nat & Nat, high: Nat) -> Nat:
  match lows:
    case (offset, subtractor):
      Nat.add(offset, Nat.div(Nat.sub(high, subtractor), 2n))

# Chooses the midpoint of a half-open block-index interval.
def midpoint(low: Nat, high: Nat) -> Nat:
  midpoint.copies(QueuePolicy.nat.clone.pair(low), high)

def move.order(is_less: Bool) -> Move:
  match is_less:
    case True{}: SearchLower{}
    case False{}: SearchUpper{}

# Compares the target key with one block's first-key separator.
def move(target: Bytes.Bytes, separator: Bytes.Bytes) -> Move:
  move.order(Cmp.is_lt(Keys.Bytes.cmp(target, separator)))

def advance.lower(state: Search, mid: Nat) -> Search:
  match state:
    case Search{low, _, best}: Search{low, mid, best}

def advance.upper.copies(state: Search, mids: Nat & Nat) -> Search:
  match state:
    case Search{_, high, _}:
      match mids:
        case (next_mid, candidate):
          Search{Nat.add(next_mid, 1n), high, candidate}

def advance.upper(state: Search, mid: Nat) -> Search:
  advance.upper.copies(state, QueuePolicy.nat.clone.pair(mid))

# Advances the interval and candidate after one separator comparison.
def advance(state: Search, direction: Move, mid: Nat) -> Search:
  match direction:
    case SearchLower{}: advance.lower(state, mid)
    case SearchUpper{}: advance.upper(state, mid)

# Reports whether the half-open search interval remains nonempty.
def active(state: Search) -> Bool:
  match state:
    case Search{low, high, _}: Nat.is_lt(low, high)

# Returns the latest separator not greater than the target key.
def selected_block(state: Search) -> Nat:
  match state:
    case Search{_, _, best}: best

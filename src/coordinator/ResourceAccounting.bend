import Base

# Carries the state for ReservationDecision.
type ReservationDecision is Data:
  Reserved{used: U32}
  Rejected{used: U32}

# Carries the state for ReleaseDecision.
type ReleaseDecision is Data:
  Released{used: U32}
  Missing{used: U32}

# Carries the state for Reservation.
type Reservation is Data:
  Reservation{id: U32, amount: U32}

# Carries the state for Ledger.
type Ledger is Type:
  Ledger{next_id: U32, exhausted: Bool, used: U32,
    live: List<&2, Reservation>}

# Carries the state for Acquire.
type Acquire is Type:
  Acquired{ledger: Ledger, reservation: Reservation}
  Refused{ledger: Ledger}

# Carries the state for Release.
type Release is Type:
  Returned{ledger: Ledger}
  InvalidRelease{ledger: Ledger}

# Carries the state for SearchResult.
type SearchResult is Type:
  MissingId{live: List<&2, Reservation>}
  FoundId{live: List<&2, Reservation>, amount: U32}
  SearchBoundExhausted{live: List<&2, Reservation>}

# Carries the state for SearchState.
type SearchState is Type:
  Visit{remaining: List<&2, Reservation>, id: U32,
    prefix: List<&2, Reservation>}
  Compared{remaining: List<&2, Reservation>, id: U32,
    prefix: List<&2, Reservation>, item: Reservation,
    amount: U32, matches: Bool}
  Finished{result: SearchResult}

# Handles empty.
def empty() -> Ledger:
  Ledger{1, False{}, 0, Nil{}}

def reserve.result(+used: U32, +requested: U32,
  remaining_fits: Bool) -> ReservationDecision:
  match remaining_fits:
    case True{}: Reserved{U32.add(used, requested)}
    case False{}: Rejected{used}

def reserve.fits(+used: U32, +requested: U32,
  capacity: U32, used_fits: Bool) -> ReservationDecision:
  match used_fits:
    case False{}: Rejected{used}
    case True{}:
      reserve.result(used, requested,
        U32.is_le(requested, U32.sub(capacity, used)))

# Handles reserve.
def reserve(+used: U32, +requested: U32,
  +capacity: U32) -> ReservationDecision:
  reserve.fits(used, requested, capacity, U32.is_le(used, capacity))

def release.result(+used: U32, released: U32,
  release_fits: Bool) -> ReleaseDecision:
  match release_fits:
    case True{}: Released{U32.sub(used, released)}
    case False{}: Missing{used}

# Handles release.
def release(+used: U32, +released: U32) -> ReleaseDecision:
  release.result(used, released, U32.is_le(released, used))

def acquire.reject(+next_id: U32, exhausted: Bool, +used: U32,
  live: List<&2, Reservation>) -> Acquire:
  Refused{Ledger{next_id, exhausted, used, live}}

def acquire.commit.last(+next_id: U32, +used: U32,
  live: List<&2, Reservation>, +amount: U32) -> Acquire:
  +reservation: Reservation = Reservation{next_id, amount}
  Acquired{Ledger{next_id, True{}, U32.add(used, amount),
    Con{reservation, live}}, reservation}

def acquire.commit.next.total(live: List<&2, Reservation>,
  +reservation: Reservation,
  used_after: U32, next_id_after: U32) -> Acquire:
  Acquired{Ledger{next_id_after, False{}, used_after,
    Con{reservation, live}}, reservation}

def acquire.commit.next(+next_id: U32, +used: U32,
  live: List<&2, Reservation>, +amount: U32) -> Acquire:
  +reservation: Reservation = Reservation{next_id, amount}
  acquire.commit.next.total(live, reservation,
    U32.add(used, amount), U32.add(next_id, 1))

def acquire.commit(+next_id: U32, +used: U32,
  live: List<&2, Reservation>, +amount: U32,
  last_id: Bool) -> Acquire:
  match last_id:
    case True{}: acquire.commit.last(next_id, used, live, amount)
    case False{}: acquire.commit.next(next_id, used, live, amount)

def acquire.identity(+next_id: U32, exhausted: Bool, +used: U32,
  live: List<&2, Reservation>, +amount: U32,
  last_id: Bool) -> Acquire:
  match exhausted:
    case True{}: acquire.reject(next_id, exhausted, used, live)
    case False{}: acquire.commit(next_id, used, live, amount, last_id)

def acquire.fits(+next_id: U32, exhausted: Bool, +used: U32,
  live: List<&2, Reservation>, +amount: U32, fits: Bool) -> Acquire:
  match fits:
    case False{}: acquire.reject(next_id, exhausted, used, live)
    case True{}:
      acquire.identity(next_id, exhausted, used, live, amount,
        U32.is_eq(next_id, 4294967295))

def acquire.used.fits(+next_id: U32, exhausted: Bool, +used: U32,
  live: List<&2, Reservation>, +amount: U32, +capacity: U32,
  fits: Bool) -> Acquire:
  match fits:
    case False{}: acquire.reject(next_id, exhausted, used, live)
    case True{}:
      acquire.fits(next_id, exhausted, used, live, amount,
        U32.is_le(amount, U32.sub(capacity, used)))

# Handles acquire.
def acquire(ledger: Ledger, +amount: U32,
  +capacity: U32) -> Acquire:
  match ledger:
    case Ledger{+next_id, exhausted, +used, live}:
      acquire.used.fits(next_id, exhausted, used, live, amount,
        capacity, U32.is_le(used, capacity))

# Handles append.
def append(left: List<&2, Reservation>,
  right: List<&2, Reservation>) -> List<&2, Reservation>:
  match left:
    case Nil{}: right
    case Con{item, rest}: Con{item, append(rest, right)}

def reverse.into(remaining: List<&2, Reservation>,
  output: List<&2, Reservation>) -> List<&2, Reservation>:
  match remaining:
    case Nil{}: output
    case Con{item, rest}: reverse.into(rest, Con{item, output})

# Handles measure.
def measure(+live: List<&2, Reservation>) -> List<&2, Reservation> & Nat:
  (live, List.length(&2, Reservation, live))

def search.loop(fuel: Nat, state: SearchState) -> SearchResult:
  match fuel:
    case 0n:
      match state:
        case Visit{remaining, _, prefix}:
          SearchBoundExhausted{append(reverse.into(prefix, Nil{}),
            remaining)}
        case Compared{remaining, _, prefix, item, amount, _}:
          SearchBoundExhausted{append(reverse.into(prefix, Nil{}),
            Con{item, remaining})}
        case Finished{result}: result
    case 1n+rest:
      match state:
        case Visit{remaining, +id, prefix}:
          match remaining:
            case Nil{}: MissingId{reverse.into(prefix, Nil{})}
            case Con{+item, tail}:
              match item:
                case Reservation{+item_id, +amount}:
                  search.loop(rest, Compared{tail, id, prefix, item,
                    amount, U32.is_eq(item_id, id)})
        case Compared{remaining, +id, prefix, item, amount, matches}:
          match matches:
            case True{}:
              FoundId{append(reverse.into(prefix, Nil{}), remaining),
                amount}
            case False{}:
              search.loop(rest, Visit{remaining, id, Con{item, prefix}})
        case Finished{result}: result

def search.with.length(+live: List<&2, Reservation>, +id: U32,
  length: Nat) -> SearchResult:
  search.loop(Nat.add(Nat.mul(length, 2n), 1n), Visit{live, id, Nil{}})

def search.measured(measured: List<&2, Reservation> & Nat,
  +id: U32) -> SearchResult:
  match measured:
    case (live, length): search.with.length(live, id, length)

# Handles search.
def search(+live: List<&2, Reservation>, +id: U32) -> SearchResult:
  search.measured(measure(live), id)

def return.checked(+next_id: U32, exhausted: Bool, +used: U32,
  +original: List<&2, Reservation>, remaining: List<&2, Reservation>,
  +amount: U32, valid: Bool) -> Release:
  match valid:
    case True{}:
      Returned{Ledger{next_id, exhausted, U32.sub(used, amount), remaining}}
    case False{}:
      InvalidRelease{Ledger{next_id, exhausted, used, original}}

def return.finish(+next_id: U32, exhausted: Bool, +used: U32,
  +original: List<&2, Reservation>, result: SearchResult) -> Release:
  match result:
    case MissingId{_}:
      InvalidRelease{Ledger{next_id, exhausted, used, original}}
    case SearchBoundExhausted{_}:
      InvalidRelease{Ledger{next_id, exhausted, used, original}}
    case FoundId{remaining, +amount}:
      return.checked(next_id, exhausted, used, original, remaining,
        amount, U32.is_le(amount, used))

# Handles return id.
def return_id(ledger: Ledger, +id: U32) -> Release:
  match ledger:
    case Ledger{+next_id, exhausted, +used, +live}:
      return.finish(next_id, exhausted, used, live, search(live, id))

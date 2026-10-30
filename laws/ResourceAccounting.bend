import Base
import ../src/coordinator/ResourceAccounting.bend as Accounting

# Verifies exact capacity is reserved.
law exact_capacity_is_reserved:
  {Accounting.reserve(12, 4, 16) == Accounting.Reserved{16} : Accounting.ReservationDecision}

# Verifies rejected reservation preserves usage.
law rejected_reservation_preserves_usage:
  {Accounting.reserve(12, 5, 16) == Accounting.Rejected{12} : Accounting.ReservationDecision}

# Verifies zero reservation preserves usage.
law zero_reservation_preserves_usage:
  {Accounting.reserve(0, 0, 0) == Accounting.Reserved{0} : Accounting.ReservationDecision}

# Verifies over capacity state rejects reservation.
law over_capacity_state_rejects_reservation:
  {Accounting.reserve(17, 0, 16) == Accounting.Rejected{17} : Accounting.ReservationDecision}

# Verifies rejected release preserves usage.
law rejected_release_preserves_usage:
  {Accounting.release(12, 13) == Accounting.Missing{12} : Accounting.ReleaseDecision}

# Verifies exact ledger capacity is acquired.
law exact_ledger_capacity_is_acquired:
  {Accounting.acquire(Accounting.empty(), 12, 12) == Accounting.Acquired{
    Accounting.Ledger{2, False{}, 12,
      Con{Accounting.Reservation{1, 12}, Nil{}}},
    Accounting.Reservation{1, 12}} : Accounting.Acquire}

# Verifies ledger capacity rejection preserves state.
law ledger_capacity_rejection_preserves_state:
  {Accounting.acquire(Accounting.empty(), 13, 12) ==
    Accounting.Refused{Accounting.empty()} : Accounting.Acquire}

# Verifies release returns the recorded amount.
law release_returns_the_recorded_amount:
  {Accounting.return_id(Accounting.Ledger{3, False{}, 12,
    Con{Accounting.Reservation{1, 4},
    Con{Accounting.Reservation{2, 8}, Nil{}}}}, 1) ==
    Accounting.Returned{Accounting.Ledger{3, False{}, 8,
      Con{Accounting.Reservation{2, 8}, Nil{}}}} : Accounting.Release}

# Verifies repeated release does not change live state.
law repeated_release_does_not_change_live_state:
  {Accounting.return_id(Accounting.Ledger{3, False{}, 8,
    Con{Accounting.Reservation{2, 8}, Nil{}}}, 1) ==
    Accounting.InvalidRelease{Accounting.Ledger{3, False{}, 8,
      Con{Accounting.Reservation{2, 8}, Nil{}}}} : Accounting.Release}

# Verifies empty ledger search preserves every missing id.
law empty_ledger_search_preserves_every_missing_id:
  for id: U32
  {Accounting.search(Nil{}, id) == Accounting.MissingId{Nil{}} : Accounting.SearchResult}

# Verifies search returns first matching reservation for id one.
law search_returns_first_matching_reservation_for_id_one:
  for amount: U32
  for tail: List<&2, Accounting.Reservation>
  {Accounting.search(Con{Accounting.Reservation{1, amount}, tail}, 1) ==
    Accounting.FoundId{tail, amount} : Accounting.SearchResult}

# Verifies measured search keeps the input and its length.
law measured_search_keeps_the_input_and_its_length:
  for live: List<&2, Accounting.Reservation>
  {Accounting.measure(live) ==
    (live, List.length(&2, Accounting.Reservation, live)) :
    List<&2, Accounting.Reservation> & Nat}

# Verifies rejected capacity decision preserves every ledger field.
law rejected_capacity_decision_preserves_every_ledger_field:
  for next_id: U32
  for used: U32
  for live: List<&2, Accounting.Reservation>
  for amount: U32
  {Accounting.acquire.fits(next_id, False{}, used, live, amount, False{}) ==
    Accounting.Refused{Accounting.Ledger{next_id, False{}, used, live}} :
    Accounting.Acquire}

# Verifies matched search transition returns first candidate.
law matched_search_transition_returns_first_candidate:
  for remaining: List<&2, Accounting.Reservation>
  for id: U32
  for prefix: List<&2, Accounting.Reservation>
  for item: Accounting.Reservation
  for amount: U32
  {Accounting.search.loop(1n,
    Accounting.Compared{remaining, id, prefix, item, amount, True{}}) ==
    Accounting.FoundId{
      Accounting.append(Accounting.reverse.into(prefix, Nil{}), remaining),
      amount} : Accounting.SearchResult}

# Verifies exhausted identifier is not reused.
law exhausted_identifier_is_not_reused:
  {Accounting.acquire(Accounting.Ledger{4294967295, True{}, 0, Nil{}},
    0, 0) == Accounting.Refused{
      Accounting.Ledger{4294967295, True{}, 0, Nil{}}} : Accounting.Acquire}

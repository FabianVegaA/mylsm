import Base
import ../laws/ResourceAccounting.bend as Laws

def Laws.exact_capacity_is_reserved():
  {==}

def Laws.rejected_reservation_preserves_usage():
  {==}

def Laws.zero_reservation_preserves_usage():
  {==}

def Laws.over_capacity_state_rejects_reservation():
  {==}

def Laws.rejected_release_preserves_usage():
  {==}

def Laws.exact_ledger_capacity_is_acquired():
  {==}

def Laws.ledger_capacity_rejection_preserves_state():
  {==}

def Laws.release_returns_the_recorded_amount():
  {==}

def Laws.repeated_release_does_not_change_live_state():
  {==}

def Laws.empty_ledger_search_preserves_every_missing_id(_id):
  {==}

def Laws.search_returns_first_matching_reservation_for_id_one(_amount, _tail):
  {==}

def Laws.measured_search_keeps_the_input_and_its_length(_live):
  {==}

def Laws.rejected_capacity_decision_preserves_every_ledger_field(
  _next_id, _used, _live, _amount
):
  {==}

def Laws.matched_search_transition_returns_first_candidate(
  _remaining, _id, _prefix, _item, _amount
):
  {==}

def Laws.exhausted_identifier_is_not_reused():
  {==}

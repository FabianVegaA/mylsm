import Base
import ../laws/ResourceOptions.bend as Laws

def Laws.option_comparison_checks_the_ordered_field_vector(_left, _right):
  {==}

def Laws.default_options_compare_equal():
  {==}

def Laws.default_options_are_valid():
  {==}

def Laws.snapshot_limits_match_defaults():
  {==}

def Laws.snapshot_retained_bytes_match_defaults():
  {==}

def Laws.cursor_per_snapshot_matches_defaults():
  {==}

def Laws.transport_frame_bytes_match_defaults():
  {==}

def Laws.transport_receive_bytes_match_defaults():
  {==}

def Laws.transport_connection_limit_matches_defaults():
  {==}

def Laws.transport_frame_timeout_matches_defaults():
  {==}

def Laws.transport_response_timeout_matches_defaults():
  {==}

def Laws.queue_timeout_matches_defaults():
  {==}

def Laws.queue_request_capacity_matches_defaults():
  {==}

def Laws.queue_byte_capacity_matches_defaults():
  {==}

def Laws.response_at_budget_is_admitted():
  {==}

def Laws.response_over_budget_is_rejected():
  {==}

def Laws.invalid_transport_is_rejected():
  {==}

def Laws.invalid_queue_is_rejected():
  {==}

def Laws.invalid_readers_are_rejected():
  {==}

def Laws.frame_must_fit_receive_budget():
  {==}

def Laws.queue_budget_can_be_smaller_than_transport_frame():
  {==}

def Laws.cursor_limit_cannot_exceed_global_limit():
  {==}

def Laws.index_page_must_fit_resident_budget():
  {==}

def Laws.invalid_transport_has_specific_decision():
  {==}

def Laws.invalid_queue_has_specific_decision():
  {==}

def Laws.invalid_readers_have_specific_decision():
  {==}

def Laws.default_retired_file_budget_is_64():
  {==}

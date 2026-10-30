import Base
import ../laws/ConnectionStore.bend as Laws

def Laws.queued_bound_update_preserves_the_connection_ownership(
  _id, _socket, _poll_events, _sequence, _old_bound, _new_bound
):
  {==}

def Laws.unselected_bound_update_preserves_every_phase(
  _connection, _bound
):
  {==}

def Laws.readiness_search_finds_the_matching_connection():
  {==}

def Laws.readiness_search_skips_unrelated_events():
  {==}

def Laws.readiness_validation_accepts_known_unique_ids():
  {==}

def Laws.readiness_validation_rejects_one_event_without_connections(_id,
  _flags):
  {==}

def Laws.readiness_validation_rejects_unknown_ids():
  {==}

def Laws.readiness_validation_rejects_duplicate_ids():
  {==}

def Laws.connection_detach_preserves_relative_order(_first, _target, _last):
  {==}

def Laws.accepted_socket_starts_with_an_empty_header(_id, _socket,
  _deadline_ms):
  {==}

def Laws.transmit_metrics_retain_full_response_buffers(_socket):
  {==}

def Laws.response_reservation_counts_the_whole_encoded_frame(_len):
  {==}

def Laws.rx_fragment_progress_keeps_the_entire_frame_peak_reserved(
  _expected_bytes, _received_bytes
):
  {==}

def Laws.rx_partial_transition_preserves_expected_frame_and_deadline(
  _id, _socket, _poll_events, _deadline_ms, _expected_bytes,
  _queue_deadline_ms, _received_bytes
):
  {==}

def Laws.rx_completed_frame_moves_the_request_to_admission(
  _id, _socket, _poll_events, _deadline_ms, _expected_bytes,
  _queue_deadline_ms, _request
):
  {==}

def Laws.rx_closed_connection_has_no_live_payload_reservation():
  {==}

def Laws.insertion_respects_the_connection_capacity(_socket):
  {==}

def Laws.full_connection_capacity_preserves_existing_slots(_existing,
  _socket):
  {==}

def Laws.bounded_admission_transfers_response_peak_to_fifo(_socket):
  {==}

def Laws.awaiting_admission_waits_for_tx_preflight(_socket):
  {==}

def Laws.awaiting_admission_keeps_request_when_queue_is_saturated(_socket):
  {==}

def Laws.empty_payload_becomes_admissible_without_socket_read(_socket):
  {==}

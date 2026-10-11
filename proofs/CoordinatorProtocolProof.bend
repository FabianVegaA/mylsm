import Base
import ../laws/CoordinatorProtocol.bend as Laws

def Laws.protocol_payload_at_record_ceiling_is_admitted():
  {==}

def Laws.protocol_payload_over_record_ceiling_is_rejected():
  {==}

def Laws.current_owner_request_is_accepted():
  {==}

def Laws.accepted_request_retains_operation_tag():
  {==}

def Laws.unsupported_protocol_version_is_rejected():
  {==}

def Laws.stale_owner_generation_is_rejected():
  {==}

def Laws.request_over_limit_is_rejected():
  {==}

def Laws.response_tag_is_not_a_request_operation():
  {==}

def Laws.batch_tag_is_a_request_operation():
  {==}

def Laws.snapshot_open_tag_is_a_request_operation():
  {==}

def Laws.snapshot_get_tag_is_a_request_operation():
  {==}

def Laws.snapshot_close_tag_is_a_request_operation():
  {==}

def Laws.snapshot_cursor_tags_are_request_operations():
  {==}

def Laws.snapshot_identifier_one_roundtrips():
  {==}

def Laws.snapshot_identifier_maximum_roundtrips():
  {==}

def Laws.malformed_snapshot_identifier_payload_is_rejected():
  {==}

def Laws.encoded_request_decodes_exactly():
  {==}

def Laws.truncated_frame_requests_more_bytes():
  {==}

def Laws.oversized_payload_is_rejected_before_dispatch():
  {==}

def Laws.truncated_payload_requests_more_bytes():
  {==}

def Laws.trailing_frame_bytes_are_rejected():
  {==}

def Laws.unknown_operation_tag_is_rejected():
  {==}

def Laws.encoded_response_decodes_exactly():
  {==}

def Laws.unsupported_platform_response_decodes():
  {==}

def Laws.already_exists_response_decodes():
  {==}

def Laws.unknown_response_status_is_rejected():
  {==}

def Laws.natural_pair_preserves_input(_value):
  {==}

def Laws.word_triple_preserves_input(_value):
  {==}

def Laws.maximum_declared_payload_is_rejected():
  {==}

def Laws.maximum_operation_tag_is_rejected():
  {==}

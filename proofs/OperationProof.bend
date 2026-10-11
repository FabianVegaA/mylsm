import Base
import ../laws/Operation.bend as Laws

def Laws.empty_flush_is_decoded():
  {==}

def Laws.empty_snapshot_open_is_decoded():
  {==}

def Laws.nonempty_snapshot_open_is_rejected():
  {==}

def Laws.snapshot_get_keeps_raw_key_bytes():
  {==}

def Laws.incomplete_snapshot_get_token_is_rejected():
  {==}

def Laws.snapshot_get_accepts_empty_key():
  {==}

def Laws.nonempty_flush_is_rejected():
  {==}

def Laws.unknown_operation_is_reported():
  {==}

def Laws.put_payload_roundtrips():
  {==}

def Laws.get_keeps_raw_key_bytes():
  {==}

def Laws.delete_keeps_raw_key_bytes():
  {==}

def Laws.incomplete_put_header_is_rejected():
  {==}

def Laws.mismatched_put_length_is_rejected():
  {==}

def Laws.malformed_write_batch_is_rejected():
  {==}

def Laws.decoded_batch_keeps_mutation_list():
  {==}

def Laws.snapshot_close_decodes_exact_token():
  {==}

def Laws.snapshot_close_rejects_short_token():
  {==}

def Laws.snapshot_cursor_open_decodes_token():
  {==}

def Laws.snapshot_cursor_next_decodes_token():
  {==}

def Laws.snapshot_cursor_close_decodes_token():
  {==}

def Laws.snapshot_cursor_seek_decodes_inclusive_lower():
  {==}

def Laws.snapshot_cursor_seek_rejects_upper_bound():
  {==}

def Laws.snapshot_cursor_seek_rejects_prefix():
  {==}

def Laws.snapshot_cursor_operations_reject_short_tokens():
  {==}

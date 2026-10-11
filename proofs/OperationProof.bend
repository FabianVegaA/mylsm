import Base
import ../laws/Operation.bend as Laws

def Laws.empty_flush_is_decoded():
  {==}

def Laws.empty_snapshot_open_is_decoded():
  {==}

def Laws.nonempty_snapshot_open_is_rejected():
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

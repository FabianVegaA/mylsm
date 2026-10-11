import Base
import ../laws/ByteSstFile.bend as Laws

def Laws.stream_header_accepts_valid_metadata():
  {==}

def Laws.stream_header_rejects_unknown_marker():
  {==}

def Laws.stream_finish_rejects_an_index_that_does_not_match_the_pages():
  {==}

def Laws.stream_finish_accepts_a_valid_root_over_raw_sections():
  {==}

def Laws.put_record_size_includes_fields():
  {==}

def Laws.delete_record_size_includes_tag_and_key_length():
  {==}

def Laws.block_payload_accepts_exact_limit():
  {==}

def Laws.block_payload_rejects_limit_overflow():
  {==}

def Laws.byte_sst_pages_roll_over_at_the_limit():
  {==}

def Laws.byte_sst_pages_fill_available_capacity():
  {==}

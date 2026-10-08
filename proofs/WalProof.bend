import Base
import ../laws/Wal.bend as Laws

def Laws.wal_v3_log_header_vector():
  {==}

def Laws.wal_v3_log_header_decodes():
  {==}

def Laws.wal_v3_rejects_text_log_header():
  {==}

def Laws.wal_v3_empty_frame_vector():
  {==}

def Laws.wal_v3_put_delete_frame_vector():
  {==}

def Laws.wal_v3_empty_frame_decodes():
  {==}

def Laws.wal_v3_put_delete_frame_decodes():
  {==}

def Laws.wal_v3_frame_rejects_trailing_byte():
  {==}

def Laws.wal_v3_frame_rejects_bad_digest():
  {==}

def Laws.multi_mutation_frame_limit_rejects_over_block():
  {==}

def Laws.delete_record_rejects_key_over_codec_cap():
  {==}

def Laws.put_record_rejects_value_over_combined_codec_cap():
  {==}

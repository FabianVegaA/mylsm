import Base
import ../laws/ByteWal.bend as Laws

def Laws.exact_single_record_frame_is_valid():
  {==}

def Laws.impossible_record_count_is_invalid():
  {==}

def Laws.mismatched_frame_length_is_invalid():
  {==}

def Laws.current_wal_header_is_accepted():
  {==}

def Laws.legacy_wal_header_is_rejected():
  {==}

def Laws.value_record_metadata_does_not_require_value_materialization():
  {==}

def Laws.malformed_value_length_is_rejected_by_metadata_reader():
  {==}

def Laws.valid_value_metadata_returns_the_exact_end_offset(
  _frame, _key, _value_length, _value_offset
):
  {==}

def Laws.invalid_value_metadata_returns_malformed(
  _frame, _key, _value_length, _value_offset
):
  {==}

def Laws.record_measurement_retains_its_source_frame():
  {==}

def Laws.deletion_metadata_distinguishes_absence_from_empty_value():
  {==}

def Laws.value_lookup_returns_the_last_matching_record_length():
  {==}

def Laws.value_lookup_reports_a_tombstone():
  {==}

def Laws.value_lookup_reports_an_absent_key():
  {==}

def Laws.value_lookup_rejects_a_corrupt_frame_checksum():
  {==}

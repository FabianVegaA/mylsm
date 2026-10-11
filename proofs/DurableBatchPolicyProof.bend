import Base
import ../laws/DurableBatchPolicy.bend as Laws

def Laws.empty_batch_is_rejected():
  {==}

def Laws.exactly_one_mutation_is_allowed():
  {==}

def Laws.batch_count_cap_is_allowed():
  {==}

def Laws.batch_count_over_cap_is_rejected():
  {==}

def Laws.multi_record_frame_accepts_its_byte_limit(_encoded_bytes, _limit):
  {==}

def Laws.single_record_frame_uses_its_own_limit(
  _encoded_bytes,
  _batch_limit,
  _single_limit
):
  {==}

def Laws.put_record_size_includes_fixed_prefix(
  _key_bytes,
  _value_bytes
):
  {==}

def Laws.delete_record_size_includes_fixed_prefix(_key_bytes):
  {==}

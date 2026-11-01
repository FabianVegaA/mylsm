import Base
import ../laws/ByteBlockBuilder.bend as Laws

def Laws.exact_block_capacity_is_admitted():
  {==}

def Laws.byte_block_requests_rollover():
  {==}

def Laws.byte_block_rejects_oversized_record():
  {==}

def Laws.rollover_does_not_add_to_old_block():
  {==}

def Laws.target_rejects_oversized_record_for_any_occupancy(_used, _record, starts_block):
  match starts_block:
    case True{}: {==}
    case False{}: {==}

def Laws.target_empty_block_admits_fitting_record(_record):
  {==}

def Laws.target_block_fills_up_to_target():
  {==}

def Laws.target_block_rolls_over_past_target():
  {==}

def Laws.target_large_record_starts_its_own_block():
  {==}

def Laws.target_large_record_fills_empty_block():
  {==}

def Laws.target_rejects_record_above_cap():
  {==}

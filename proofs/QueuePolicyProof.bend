import Base
import ../laws/QueuePolicy.bend as Laws

def Laws.exact_queue_capacity_is_accepted():
  {==}

def Laws.count_saturation_is_rejected():
  {==}

def Laws.byte_saturation_is_rejected():
  {==}

def Laws.oversized_request_is_distinguished():
  {==}

def Laws.stateful_admission_records_the_new_occupancy():
  {==}

def Laws.count_saturation_preserves_state():
  {==}

def Laws.byte_saturation_preserves_state():
  {==}

def Laws.oversized_request_preserves_state():
  {==}

def Laws.nat_clone_pair_preserves_both_values(value):
  match value:
    case 0n: {==}
    case 1n+rest: {==}

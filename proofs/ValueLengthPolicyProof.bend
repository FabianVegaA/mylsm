import Base
import ../laws/ValueLengthPolicy.bend as Laws
import ../src/ValueLengthPolicy.bend as Policy

def Laws.metadata_lookup_preserves_base_statistics(_base_stats, outcome):
  match outcome:
    case Policy.ValueFound{}: {==}
    case Policy.ValueMissing{}: {==}
    case Policy.LookupFailed{}: {==}

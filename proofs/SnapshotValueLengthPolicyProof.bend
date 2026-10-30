import Base
import ../laws/SnapshotValueLengthPolicy.bend as Laws

def Laws.delta_length_overrides_persisted_metadata(_value_bytes, _persisted):
  {==}

def Laws.delta_tombstone_masks_persisted_value(_value_bytes):
  {==}

def Laws.absent_delta_uses_persisted_value_length(_value_bytes):
  {==}

def Laws.absent_delta_uses_persisted_metadata(_metadata):
  {==}

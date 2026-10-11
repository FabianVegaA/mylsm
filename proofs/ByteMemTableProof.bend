import Base
import ../laws/ByteMemTable.bend as Laws
import ../src/ByteMemTable.bend as ByteMemTable
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

def Laws.put_increments_count(_key, _value):
  {==}

def Laws.delete_increments_count(_key):
  {==}

def Laws.payload_counts_exact_bytes():
  {==}

def Laws.retention_preflight_preserves_entry_count():
  {==}

def Laws.retention_preflight_preserves_payload_bytes():
  {==}

def Laws.retention_preflight_measures_entry_overhead():
  {==}

def Laws.reverse_insertions_materialize_in_byte_order():
  {==}

def Laws.materialization_keeps_newest_duplicate_value():
  {==}

def Laws.compaction_drops_tombstones():
  {==}

def Laws.probe_distinguishes_tombstone():
  {==}

def Laws.probe_distinguishes_absence():
  {==}

def Laws.probe_finds_live_value():
  {==}

def Laws.strict_order_rejects_duplicate_keys():
  {==}

def Laws.strict_order_rejects_descending_keys():
  {==}

def Laws.strict_order_accepts_prefix_extension():
  {==}

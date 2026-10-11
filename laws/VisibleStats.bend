import Base
import ../src/scan/VisibleStats.bend as Stats

# Witnesses replacement keeps the count and adjusts payload bytes only.
law replacement_preserves_visible_entry_count:
  {Stats.apply(Stats.Stats{2n, 17n}, 3n, Some{5n}, Some{8n}) ==
    Stats.Applied{Stats.Stats{2n, 20n}} : Stats.Decision}

# Witnesses an insertion adds both key and value bytes.
law new_value_adds_key_and_value_bytes:
  {Stats.apply(Stats.Stats{2n, 17n}, 3n, None{}, Some{8n}) ==
    Stats.Applied{Stats.Stats{3n, 28n}} : Stats.Decision}

# Witnesses a tombstone removes the visible key and payload.
law tombstone_removes_key_and_payload:
  {Stats.apply(Stats.Stats{2n, 17n}, 3n, Some{5n}, None{}) ==
    Stats.Applied{Stats.Stats{1n, 9n}} : Stats.Decision}

# Witnesses deleting an absent key preserves aggregate totals.
law absent_delete_preserves_totals:
  {Stats.apply(Stats.Stats{2n, 17n}, 3n, None{}, None{}) ==
    Stats.Applied{Stats.Stats{2n, 17n}} : Stats.Decision}

import Base
import ../src/scan/CursorPreviewPolicy.bend as Policy
import ../src/coordinator/TransportBudgetPolicy.bend as TxPolicy

# Verifies item payload length includes all wire fields.
law item_payload_length_includes_all_wire_fields:
  for key_bytes: Nat
  for value_bytes: Nat
  {Policy.cursor.item.payload.bytes(key_bytes, value_bytes) ==
    Nat.add(9n, Nat.add(key_bytes, value_bytes)) : Nat}

# Verifies item bound uses exact measured payload.
law item_bound_uses_exact_measured_payload:
  for key_bytes: Nat
  for value_bytes: Nat
  for max_payload_bytes: U32
  {Policy.cursor.item.bound(key_bytes, value_bytes, max_payload_bytes) ==
    TxPolicy.tx.payload.bound(
      Policy.cursor.item.payload.bytes(key_bytes, value_bytes),
      max_payload_bytes) : TxPolicy.BoundDecision}

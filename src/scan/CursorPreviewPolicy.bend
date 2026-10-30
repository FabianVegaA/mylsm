import Base
import ../coordinator/TransportBudgetPolicy.bend as TxPolicy

def cursor.item.payload.bytes(+key_bytes: Nat, +value_bytes: Nat) -> Nat:
  Nat.add(9n, Nat.add(key_bytes, value_bytes))

def cursor.item.bound(
  +key_bytes: Nat,
  +value_bytes: Nat,
  max_payload_bytes: U32
) -> TxPolicy.BoundDecision:
  TxPolicy.tx.payload.bound(
    cursor.item.payload.bytes(key_bytes, value_bytes), max_payload_bytes)

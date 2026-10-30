import Base
import ../src/coordinator/StatsCodec.bend as Codec

# Verifies stats payload length counts decimal fields and separators.
law stats_payload_length_counts_decimal_fields_and_separators:
  for entries: Nat
  for payload_bytes: Nat
  for snapshots: Nat
  for retained_bytes: Nat
  for cursors: Nat
  {Codec.payload.length(entries, payload_bytes, snapshots, retained_bytes,
    cursors) == Nat.add(4n, Nat.add(Codec.decimal.length(entries),
      Nat.add(Codec.decimal.length(payload_bytes),
        Nat.add(Codec.decimal.length(snapshots),
          Nat.add(Codec.decimal.length(retained_bytes),
            Codec.decimal.length(cursors)))))) : Nat}

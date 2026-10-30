import Base
import ../src/coordinator/SnapshotValueLengthPolicy.bend as Policy
import ../src/ByteMemTable.bend as ByteMemTable
import ../src/ByteWal.bend as ByteWal

# Verifies delta length overrides persisted metadata.
law delta_length_overrides_persisted_metadata:
  for value_bytes: U32
  for persisted: ByteWal.ValueMetadata
  {Policy.result(ByteMemTable.LengthPresent{value_bytes}, persisted) ==
    Policy.Found{value_bytes} : Policy.Decision}

# Verifies delta tombstone masks persisted value.
law delta_tombstone_masks_persisted_value:
  for value_bytes: U32
  {Policy.result(ByteMemTable.LengthDeleted{},
    ByteWal.ValuePresent{value_bytes}) == Policy.Missing{} : Policy.Decision}

# Verifies absent delta uses persisted value length.
law absent_delta_uses_persisted_value_length:
  for value_bytes: U32
  {Policy.result(ByteMemTable.LengthAbsent{},
    ByteWal.ValuePresent{value_bytes}) == Policy.Found{value_bytes} :
      Policy.Decision}

# Verifies absent delta uses persisted metadata.
law absent_delta_uses_persisted_metadata:
  for metadata: ByteWal.ValueMetadata
  {Policy.result(ByteMemTable.LengthAbsent{}, metadata) ==
    Policy.persisted(metadata) : Policy.Decision}

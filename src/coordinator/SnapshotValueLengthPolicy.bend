import Base
import ../ByteMemTable.bend as ByteMemTable
import ../ByteWal.bend as ByteWal

# Carries the state for Decision.
type Decision is Data:
  NeedSst{}
  Missing{}
  Found{value_bytes: U32}

# Handles delta.
def delta(probe: ByteMemTable.LengthProbe) -> Decision:
  match probe:
    case ByteMemTable.LengthAbsent{}: NeedSst{}
    case ByteMemTable.LengthDeleted{}: Missing{}
    case ByteMemTable.LengthPresent{value_bytes}: Found{value_bytes}

# Handles persisted.
def persisted(metadata: ByteWal.ValueMetadata) -> Decision:
  match metadata:
    case ByteWal.ValueAbsent{}: Missing{}
    case ByteWal.ValueDeleted{}: Missing{}
    case ByteWal.ValuePresent{value_bytes}: Found{value_bytes}

# Handles result.
def result(
  delta: ByteMemTable.LengthProbe,
  persisted_metadata: ByteWal.ValueMetadata
) -> Decision:
  match delta:
    case ByteMemTable.LengthAbsent{}: persisted(persisted_metadata)
    case ByteMemTable.LengthDeleted{}: Missing{}
    case ByteMemTable.LengthPresent{value_bytes}: Found{value_bytes}

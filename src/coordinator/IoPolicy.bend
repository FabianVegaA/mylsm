import Base
import ./Protocol.bend as Protocol

def write_chunk.copied(copies: U32 & U32 & U32) -> U32:
  match copies:
    case (checked, (retained, _)):
      Bool.pick(U32, U32.is_le(checked, 65536), retained, 65536)

# Caps one socket write request while preserving the remaining byte count.
def write_chunk(remaining: U32) -> U32:
  write_chunk.copied(Protocol.u32.duplicate.triple(remaining))

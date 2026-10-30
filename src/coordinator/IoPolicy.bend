import Base
import ./Protocol.bend as Protocol

# Carries the state for ReadDisposition.
type ReadDisposition is Data:
  ReadInterrupted{}
  ReadWouldBlock{}
  ReadFailure{}

# Carries the state for WriteDisposition.
type WriteDisposition is Data:
  WriteInterrupted{}
  WriteWouldBlock{}
  WriteFailure{}

def read.disposition(code: U32) -> ReadDisposition:
  match code:
    case 4: ReadInterrupted{}
    case 11: ReadWouldBlock{}
    case 35: ReadWouldBlock{}
    case _: ReadFailure{}

def write.disposition(code: U32) -> WriteDisposition:
  match code:
    case 4: WriteInterrupted{}
    case 11: WriteWouldBlock{}
    case 35: WriteWouldBlock{}
    case _: WriteFailure{}
def write_chunk.copied(copies: U32 & U32 & U32) -> U32:
  match copies:
    case (checked, (retained, _)):
      Bool.pick(U32, U32.is_le(checked, 65536), retained, 65536)

# Caps one socket write request while preserving the remaining byte count.
def write_chunk(remaining: U32) -> U32:
  write_chunk.copied(Protocol.u32.duplicate.triple(remaining))

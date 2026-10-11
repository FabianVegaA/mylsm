import Base
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Determines the next owner generation without allowing identifier wraparound.
type Decision is Data:
  GenerationReady{generation: U32}
  GenerationExhausted{}

# Separates the increment result from the wrap test.
def next.result(generation: U32, wraps: Bool) -> Decision:
  match wraps:
    case True{}: GenerationExhausted{}
    case False{}: GenerationReady{generation}

# Encodes an unsigned field in big-endian byte order.
def u32.bytes(value: U32) -> Bytes.Bytes:
  Bytes.set.u32be(Bytes.new(4), 0, value)

# Extracts a decoded word while consuming the buffer returned by the reader.
def u32.read.value(pair: Bytes.Bytes & Maybe<&2, U32>) -> U32:
  match pair:
    case (_, Some{value}): value
    case _: 0

def u32.read(input: Bytes.Bytes) -> U32:
  u32.read.value(Bytes.get.u32be(input, 0))

def u32.clone.pair.copies(copies: Bytes.Bytes & Bytes.Bytes) -> U32 & U32:
  match copies:
    case (left, right): (u32.read(left), u32.read(right))

def u32.clone.pair.buffers(
  +len: U32,
  copies: Array<U32> & Array<U32>
) -> Bytes.Bytes & Bytes.Bytes:
  match copies:
    case (left, right): (Bytes.Bytes{len, left}, Bytes.Bytes{len, right})

def u32.clone.pair.input(input: Bytes.Bytes) -> U32 & U32:
  match input:
    case Bytes.Bytes{+len, buf}:
      u32.clone.pair.copies(u32.clone.pair.buffers(len,
        Bytes.copy.bytes(len, buf, Bytes.alloc(len), 0, 0)))

# Duplicates one fixed-width owner identifier without natural-number recursion.
def u32.clone.pair(value: U32) -> U32 & U32:
  u32.clone.pair.input(u32.bytes(value))

# Advances a stored generation or reports terminal exhaustion.
def next.copies(copies: U32 & U32) -> Decision:
  match copies:
    case (for_increment, for_wrap):
      next.result(U32.add(for_increment, 1), U32.is_zero(U32.add(for_wrap, 1)))

# Chooses generation one for a new owner state and advances a persisted value.
def next(current: Maybe<&2, U32>) -> Decision:
  match current:
    case None{}: GenerationReady{1}
    case Some{generation}:
      next.copies(u32.clone.pair(generation))

import Base
import ../src/hub_sha/sha256.bend as SHA
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Returns the byte equality component of a comparison.
def equal(pair: Bytes.Bytes & Bytes.Bytes & Bool) -> Bool:
  match pair:
    case (_, _, same): same

def slice.result(pair: Bytes.Bytes & Bytes.Bytes) -> Bytes.Bytes:
  match pair:
    case (_, bytes): bytes

def clone.pair(+len: U32, copied: Array<U32> & Array<U32>) -> Bytes.Bytes & Bytes.Bytes:
  match copied:
    case (left, right):
      (Bytes.Bytes{len, left}, Bytes.Bytes{len, right})

def clone.split(bytes: Bytes.Bytes) -> Bytes.Bytes & Bytes.Bytes:
  match bytes:
    case Bytes.Bytes{+len, buf}:
      clone.pair(len, Bytes.copy.bytes(len, buf, Bytes.alloc(len), 0, 0))

def stream.update.next(
  result: Result<&1, &1, SHA.StreamError, SHA.Stream>,
  chunk: Bytes.Bytes
) -> Result<&1, &1, SHA.StreamError, SHA.Stream>:
  match result:
    case Fail{error}: Fail{error}
    case Done{stream}: SHA.stream.update(stream, chunk)

def stream.updates(chunks: Bytes.Bytes & Bytes.Bytes & Bytes.Bytes) -> Result<&1, &1, SHA.StreamError, SHA.Stream>:
  match chunks:
    case (first, second, third):
      stream.update.next(
        stream.update.next(SHA.stream.update(SHA.stream.initial(), first), second),
        third)

# Splits the final witness chunk from the preceding input.
def chunks.last(
  pair: Bytes.Bytes & Bytes.Bytes,
  first: Bytes.Bytes,
  second: Bytes.Bytes
) -> Bytes.Bytes & Bytes.Bytes & Bytes.Bytes:
  match pair:
    case (_, third): (first, second, third)

# Splits the middle witness chunk from its remaining suffix.
def chunks.second(
  pair: Bytes.Bytes & Bytes.Bytes,
  first: Bytes.Bytes
) -> Bytes.Bytes & Bytes.Bytes & Bytes.Bytes:
  match pair:
    case (input, second):
      chunks.last(Bytes.slice(input, 64, 66), first, second)

# Splits the first witness chunk from the remaining input.
def chunks.first(pair: Bytes.Bytes & Bytes.Bytes) -> Bytes.Bytes & Bytes.Bytes & Bytes.Bytes:
  match pair:
    case (retained, first):
      chunks.second(Bytes.slice(retained, 17, 47), first)

# Divides the 130-byte witness into uneven update chunks.
def chunks(input: Bytes.Bytes) -> Bytes.Bytes & Bytes.Bytes & Bytes.Bytes:
  chunks.first(Bytes.slice(input, 0, 17))

def digest.stream(
  result: Result<&1, &1, SHA.StreamError, SHA.Stream>,
  expected: Bytes.Bytes
) -> Bool:
  match result:
    case Fail{_}: False{}
    case Done{stream}: equal(Bytes.eq(SHA.stream.finish(stream), expected))

def digest.valid(pair: Bytes.Bytes & Bytes.Bytes) -> Bool:
  match pair:
    case (input, expected): digest.stream(stream.updates(chunks(input)), expected)

def stream.inputs(copies: Bytes.Bytes & Bytes.Bytes) -> Bool:
  match copies:
    case (incremental, reference):
      digest.valid((incremental, SHA.sha256_packed_bytes(reference)))

def Laws.chunked_updates_match_one_shot() -> Bool:
  stream.inputs(clone.split(Bytes.new(130)))

# Chunked updates agree with one-shot hashing for the closed witness.
law chunked_updates_match_one_shot:
  {Laws.chunked_updates_match_one_shot() == True{} : Bool}

import Base
import ../../src/hub_sha/sha256.bend as SHA
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

def stream.updates.middle(
  result: Result<&1, &1, SHA.StreamError, SHA.Stream>,
  halves: Bytes.Bytes & Bytes.Bytes,
  last: Bytes.Bytes
) -> Result<&1, &1, SHA.StreamError, SHA.Stream>:
  match halves:
    case (first, second):
      stream.update.next(stream.update.next(
        stream.update.next(result, slice.result(Bytes.slice(first, 0, 32))),
        slice.result(Bytes.slice(second, 32, 32))), last)


def stream.updates(chunks: Bytes.Bytes & Bytes.Bytes & Bytes.Bytes) -> Result<&1, &1, SHA.StreamError, SHA.Stream>:
  match chunks:
    case (first, second, third):
      stream.updates.middle(SHA.stream.update(SHA.stream.initial(), first),
        clone.split(second), third)

# Splits the final 32-byte portion from the 130-byte witness.
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
      chunks.last(Bytes.slice(input, 84, 32), first, second)

# Splits the first witness chunk from the remaining input.
def chunks.first(pair: Bytes.Bytes & Bytes.Bytes) -> Bytes.Bytes & Bytes.Bytes & Bytes.Bytes:
  match pair:
    case (retained, first):
      chunks.second(Bytes.slice(retained, 20, 64), first)

# Divides a closed input into deliberately uneven update chunks.
def chunks(input: Bytes.Bytes) -> Bytes.Bytes & Bytes.Bytes & Bytes.Bytes:
  chunks.first(Bytes.slice(input, 0, 20))

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

# Fails the smoke fixture when its concrete assertion is false.
def require(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, message)

def main.copies(copies: Bytes.Bytes & Bytes.Bytes) -> IO(Unit):
  match copies:
    case (for_incremental, for_reference):
      do IO<Unit>:
        expected : Bytes.Bytes = SHA.sha256_packed_bytes(for_reference)
        require(digest.valid((for_incremental, expected)),
          "incremental SHA-256 must match one-shot hashing across chunk boundaries")
        IO.print("SHA256_STREAM_PASSED")

def main() -> IO(Unit):
  do IO<Unit>:
    input : Bytes.Bytes = Bytes.set.u32be(Bytes.new(116), 0, 305419896)
    input : Bytes.Bytes = Bytes.set.u32be(input, 64, 2596069104)
    input : Bytes.Bytes = Bytes.set.u32be(input, 112, 19088743)
    copies : Bytes.Bytes & Bytes.Bytes = clone.split(input)
    main.copies(copies)

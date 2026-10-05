import Base
import ../../src/Wal.bend as Wal
import ../../src/Manifest.bend as Manifest
import ../../src/SstFile.bend as SstFile
import ../../src/StorageBytes.bend as StorageBytes
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

def frame.bytes(result: Result<&1, &1, Wal.Error, Bytes.Bytes>) -> Bytes.Bytes:
  match result:
    case Fail{_}:
      Bytes.new(0)
    case Done{bytes}:
      bytes

# Deterministic fail-closed corpus. The decoder totality laws cover arbitrary
# Strings; this executable adds representative truncation, noise, and valid
# records without depending on an external random-number package.
def corpus(idx: Nat) -> String:
  match idx:
    case 0n:
      ""
    case 1n+m:
      match m:
        case 0n:
          "garbage"
        case 1n+p:
          match p:
            case 0n:
              "-;"
            case 1n+q:
              match q:
                case 0n:
                  Bytes.to_hex(frame.bytes(Wal.encode_frame(Wal.Batch{Con{Wal.Put{"k", "v"}, Nil{}}})))
                case 1n+r:
                  match r:
                    case 0n:
                      "T---;---;garbage#0"
                    case 1n+s:
                      corpus(s)

# Check all decided for the storage decoder fuzz test.
def all_decided(first: Bool, second: Bool, third: Bool) -> Bool:
  match first second third:
    case True{} True{} True{}:
      True{}
    case _ _ _:
      False{}

# Handle sst decided text in the storage decoder fuzz test.
def sst_decided_text(result: Result<&1, &1, U32 & String, Bytes.Bytes>) -> Bool:
  match result:
    case Fail{_}:
      True{}
    case Done{bytes}:
      SstFile.is_decided(SstFile.parse(bytes))

# Handle manifest decided in the storage decoder fuzz test.
def manifest_decided(result: Result<&1, &1, U32 & String, Bytes.Bytes>) -> Bool:
  match result:
    case Fail{_}:
      True{}
    case Done{bytes}:
      Manifest.is_decided(Manifest.parse(bytes))

# Handle wal decided in the storage decoder fuzz test.
def wal_decided(result: Result<&1, &1, Wal.Error, Wal.Batch>) -> Bool:
  match result:
    case Fail{_}:
      True{}
    case Done{_}:
      True{}

def corpus.bytes(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case None{}:
      Bytes.new(0)
    case Some{bytes}:
      bytes

# Check whether one holds for the storage decoder fuzz test.
def check_one(+str: String) -> Bool:
  all_decided(
    wal_decided(Wal.decode_frame(corpus.bytes(Bytes.from_hex(str)))),
    manifest_decided(Done{corpus.bytes(Bytes.from_hex(str))}),
    sst_decided_text(Done{corpus.bytes(Bytes.from_hex(str))}))

# Combine bool for the storage decoder fuzz test.
def and_bool(first: Bool, second: Bool) -> Bool:
  match first:
    case True{}:
      second
    case False{}:
      False{}

# Fixed-seed xorshift over U32: deterministic across runs and backends.
def rng_next(+state: U32) -> U32:
  +x = U32.xor(state, U32.shln(state, 13n))
  +y = U32.xor(x, U32.shrn(x, 17n))
  U32.xor(y, U32.shln(y, 5n))

# Mutate pick for the storage decoder fuzz test.
def mutate_pick(sel: Nat, +str: String, +seed: U32) -> String:
  match sel:
    case 0n:
      String.drop(str, Nat.mod(U32.to_nat(seed), Nat.add(String.length(str), 1n)))
    case 1n+m:
      match m:
        case 0n:
          str ++ "garbage#~"
        case 1n+p:
          match p:
            case 0n:
              String.take(str, Nat.mod(U32.to_nat(seed), Nat.add(String.length(str), 1n)))
            case _:
              String.reverse(str)

# Handle mutate in the storage decoder fuzz test.
def mutate(+str: String, +seed: U32) -> String:
  mutate_pick(Nat.mod(U32.to_nat(seed), 4n), str, seed)

# Check whether go holds for the storage decoder fuzz test.
def check_go(count: Nat, +seed: U32, ok: Bool) -> Bool:
  match count:
    case 0n:
      ok
    case 1n+f:
      check_go(f, rng_next(seed), and_bool(ok, check_one(mutate(corpus(Nat.mod(U32.to_nat(seed), 6n)), seed))))

# Handle report in the storage decoder fuzz test.
def report(ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("FUZZ CLEAN: 1000000 inputs decided (seed 123456789)")
    case False{}:
      IO.die(Unit, U32.from_nat(1n), "decoder failed to decide input")

def main() -> IO(Unit):
  report(check_go(1000000n, 123456789, True{}))

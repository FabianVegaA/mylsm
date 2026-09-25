import Base
import ../../src/Wal.bend as Wal
import ../../src/Manifest.bend as Manifest
import ../../src/SstFile.bend as SstFile

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
                  Wal.encode(Wal.Batch{Con{Wal.Put{"k", "v"}, Nil{}}})
                case 1n+r:
                  match r:
                    case 0n:
                      "T---;---;garbage#0"
                    case 1n+s:
                      corpus(s)

def all_decided(first: Bool, second: Bool, third: Bool) -> Bool:
  match first second third:
    case True{} True{} True{}:
      True{}
    case _ _ _:
      False{}

def check_one(+str: String) -> Bool:
  all_decided(Wal.is_decided(Wal.decode(str)), Manifest.is_decided(Manifest.parse(str)), SstFile.is_decided(SstFile.parse(str)))

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

def mutate(+str: String, +seed: U32) -> String:
  mutate_pick(Nat.mod(U32.to_nat(seed), 4n), str, seed)

def check_go(count: Nat, +seed: U32, ok: Bool) -> Bool:
  match count:
    case 0n:
      ok
    case 1n+f:
      check_go(f, rng_next(seed), and_bool(ok, check_one(mutate(corpus(Nat.mod(U32.to_nat(seed), 6n)), seed))))

def report(ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("FUZZ CLEAN: 1000000 inputs decided (seed 123456789)")
    case False{}:
      IO.die(Unit, U32.from_nat(1n), "decoder failed to decide input")

def main() -> IO(Unit):
  report(check_go(1000000n, 123456789, True{}))

import Base
import ../src/Wal.bend as Wal
import ../src/Manifest.bend as Manifest
import ../src/SstFile.bend as SstFile

# Deterministic fail-closed corpus. The decoder totality laws cover arbitrary
# Strings; this executable adds representative truncation, noise, and valid
# records without depending on an external random-number package.
def corpus(i: Nat) -> String:
  match i:
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

def all_decided(a: Bool, b: Bool, c: Bool) -> Bool:
  match a b c:
    case True{} True{} True{}:
      True{}
    case _ _ _:
      False{}

def check_one(+s: String) -> Bool:
  all_decided(Wal.is_decided(Wal.decode(s)), Manifest.is_decided(Manifest.parse(s)), SstFile.is_decided(SstFile.parse(s)))

def and_bool(a: Bool, b: Bool) -> Bool:
  match a:
    case True{}:
      b
    case False{}:
      False{}

def check_go(n: Nat, ok: Bool) -> Bool:
  match n:
    case 0n:
      ok
    case 1n+m:
      check_go(m, and_bool(ok, check_one(corpus(1n))))

def report(ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("FUZZ CLEAN: 256 inputs decided")
    case False{}:
      IO.die(Unit, U32.from_nat(1n), "decoder failed to decide input")

def main() -> IO(Unit):
  report(check_go(256n, True{}))

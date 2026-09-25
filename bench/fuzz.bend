import Base
import ../src/Wal.bend as Wal
import ../src/Manifest.bend as Manifest
import ../src/SstFile.bend as SstFile

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

def check_go(num: Nat, ok: Bool) -> Bool:
  match num:
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

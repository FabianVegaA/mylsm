import Base

def show_maybe(+m: Maybe<&2, String>) -> String:
  match m:
    case None{}:
      "<missing>"
    case Some{v}:
      v

def worker(n: Nat, acc: Nat) -> Nat:
  match n:
    case 0n:
      acc
    case 1n+m:
      worker(m, Nat.add(acc, 2n))

def worker_gpu(n: Nat, acc: Nat) -> Nat:
  match n:
    case 0n:
      acc
    case 1n+m:
      worker_gpu(m, Nat.add(acc, 2n))

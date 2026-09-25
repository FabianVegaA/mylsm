import Base

def show_maybe(+opt: Maybe<&2, String>) -> String:
  match opt:
    case None{}:
      "<missing>"
    case Some{v}:
      v

def worker(num: Nat, acc: Nat) -> Nat:
  match num:
    case 0n:
      acc
    case 1n+m:
      worker(m, Nat.add(acc, 2n))

def worker_gpu(num: Nat, acc: Nat) -> Nat:
  match num:
    case 0n:
      acc
    case 1n+m:
      worker_gpu(m, Nat.add(acc, 2n))

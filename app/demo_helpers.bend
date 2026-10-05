import Base

# Show maybe for the demo output helpers.
def show_maybe(+opt: Maybe<&2, String>) -> String:
  match opt:
    case None{}:
      "<missing>"
    case Some{v}:
      v

# Handle worker in the demo output helpers.
def worker(num: Nat, acc: Nat) -> Nat:
  match num:
    case 0n:
      acc
    case 1n+m:
      worker(m, Nat.add(acc, 2n))

# Handle worker gpu in the demo output helpers.
def worker_gpu(num: Nat, acc: Nat) -> Nat:
  match num:
    case 0n:
      acc
    case 1n+m:
      worker_gpu(m, Nat.add(acc, 2n))

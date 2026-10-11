import Base
import ../../src/coordinator/OwnerSpawn.bend as OwnerSpawn

def invalid.result(result: Result<&1, &1, U32 & String, Nat>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("OWNER_SPAWN_PASSED")
    case Done{_}: IO.die(Unit, 1, "empty executable was not rejected")

def valid.result(result: Result<&1, &1, U32 & String, Nat>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "direct executable launch failed")
    case Done{_}:
      do IO<Unit>:
        rejected : Result<&1, &1, U32 & String, Nat> <-
          OwnerSpawn.launch("", Nil{})
        invalid.result(rejected)

def main() -> IO(Unit):
  do IO<Unit>:
    result : Result<&1, &1, U32 & String, Nat> <-
      OwnerSpawn.launch("/usr/bin/true", Nil{})
    valid.result(result)

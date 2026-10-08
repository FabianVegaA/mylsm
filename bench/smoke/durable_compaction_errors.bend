import Base
import ../../src/Console.bend as Console
import ../../mylsm.bend as MyLSM

# Runs the close checked step of this fixture.
def close_checked(result: Result<&1, &1, MyLSM.Error, Unit>) -> IO(Unit):
  match result:
    case Fail{_}:
      IO.die(Unit, 1, "close failed")
    case Done{Unit{}}:
      IO.print("DB_CLOSED")

# Runs the close seed step of this fixture.
def close_seed(handle: MyLSM.Handle) -> IO(Unit):
  do IO<Unit>:
    result : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
    close_checked(result)


# Tracks seeding progress for the compaction error fixture.
type SeedState is Type:
  SeedWrite{remaining: Nat, handle: MyLSM.Handle}
  SeedWriteResult{remaining: Nat, pair: MyLSM.Handle & Result<&1, &1, MyLSM.Error, MyLSM.WriteOutcome>}
  SeedFlush{remaining: Nat, handle: MyLSM.Handle}
  SeedFlushResult{pair: MyLSM.Handle & Result<&1, &1, MyLSM.Error, Unit>, remaining: Nat}

# Runs the seed step step of this fixture.
def seed_step(fuel: Nat, state: SeedState) -> IO(Unit):
  match fuel:
    case 0n:
      IO.die(Unit, 1, "seed state exhausted")
    case 1n+fuel_rest:
      match state:
        case SeedWrite{remaining, handle}:
          do IO<Unit>:
            pair : MyLSM.Handle & Result<&1, &1, MyLSM.Error, MyLSM.WriteOutcome> <- MyLSM.put(handle, "a", "value")
            seed_step(fuel_rest, SeedWriteResult{remaining, pair})
        case SeedWriteResult{remaining, pair}:
          match pair:
            case (handle, Fail{_}):
              do IO<Unit>:
                _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
                IO.die(Unit, 1, "seed write failed")
            case (handle, Done{_}):
              seed_step(fuel_rest, SeedFlush{remaining, handle})
        case SeedFlush{remaining, handle}:
          do IO<Unit>:
            pair : MyLSM.Handle & Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.flush(handle)
            seed_step(fuel_rest, SeedFlushResult{pair, remaining})
        case SeedFlushResult{pair, remaining}:
          match pair:
            case (handle, Fail{_}):
              do IO<Unit>:
                _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
                IO.die(Unit, 1, "seed flush failed")
            case (handle, Done{Unit{}}):
              match remaining:
                case 0n:
                  close_seed(handle)
                case 1n+rest:
                  match rest:
                    case 0n:
                      close_seed(handle)
                    case 1n+after_one:
                      seed_step(fuel_rest, SeedWrite{1n+after_one, handle})

# Runs the seed created step of this fixture.
def seed_created(result: Result<&1, &1, MyLSM.Error, MyLSM.Handle>) -> IO(Unit):
  match result:
    case Fail{_}:
      IO.die(Unit, 1, "database create failed")
    case Done{handle}:
      seed_step(20n, SeedWrite{5n, handle})

# Runs the compact result step of this fixture.
def compact_result(pair: MyLSM.Handle & Result<&1, &1, MyLSM.Error, Unit>) -> IO(Unit):
  match pair:
    case (handle, Fail{MyLSM.Error{MyLSM.IoError{}, _, _, _, _}}):
      do IO<Unit>:
        IO.print("COMPACTION_IO_RETURNED")
        result : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        close_checked(result)
    case (handle, _):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, 1, "compaction failure was not returned as IO")

# Runs the opened for compact step of this fixture.
def opened_for_compact(result: Result<&1, &1, MyLSM.Error, MyLSM.Handle>) -> IO(Unit):
  match result:
    case Fail{_}:
      IO.die(Unit, 1, "database open failed")
    case Done{handle}:
      do IO<Unit>:
        result : MyLSM.Handle & Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.compact(handle)
        compact_result(result)

# Continues the verified fixture step.
def verified(pair: MyLSM.Handle & Result<&1, &1, MyLSM.Error, Maybe<&2, String>>) -> IO(Unit):
  match pair:
    case (handle, Done{Some{"value"}}):
      do IO<Unit>:
        IO.print("COMPACTION_DATA_READABLE")
        result : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        close_checked(result)
    case (handle, Done{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, 1, "compaction data missing after reopen")
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, 1, "compaction data read failed")

# Runs the opened for verify step of this fixture.
def opened_for_verify(result: Result<&1, &1, MyLSM.Error, MyLSM.Handle>) -> IO(Unit):
  match result:
    case Fail{_}:
      IO.die(Unit, 1, "database reopen failed")
    case Done{handle}:
      do IO<Unit>:
        value : MyLSM.Handle & Result<&1, &1, MyLSM.Error, Maybe<&2, String>> <- MyLSM.get(handle, "a")
        verified(value)

# Runs the run mode step of this fixture.
def run_mode(path: String, mode: String) -> IO(Unit):
  match mode:
    case "seed":
      do IO<Unit>:
        result : Result<&1, &1, MyLSM.Error, MyLSM.Handle> <- MyLSM.create(path)
        seed_created(result)
    case "compact":
      do IO<Unit>:
        result : Result<&1, &1, MyLSM.Error, MyLSM.Handle> <- MyLSM.open_existing(path)
        opened_for_compact(result)
    case "verify":
      do IO<Unit>:
        result : Result<&1, &1, MyLSM.Error, MyLSM.Handle> <- MyLSM.open_existing(path)
        opened_for_verify(result)
    case _:
      IO.die(Unit, 1, "unsupported mode")

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    mode : String <- IO.try(String, Console.get_env("MYLSM_COMPACTION_MODE"))
    run_mode(path, mode)

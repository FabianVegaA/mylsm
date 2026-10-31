import Base
import ../../src/Console.bend as Console
import ../../mylsm.bend as MyLSM
import ../lib/common.bend as Common

# Runs the close public step of this fixture.
def close_public(result: Result<&1, &1, MyLSM.Utf8.Error, Unit>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, U32.from_nat(1n), "public performance close failed")
    case Done{Unit{}}: IO.pure(Unit, Unit{})

# Continues the public step result fixture step.
def public_step_result(pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, MyLSM.WriteOutcome>) -> IO(MyLSM.Utf8.Handle):
  match pair:
    case (handle, Fail{_}):
      do IO<MyLSM.Utf8.Handle>:
        _closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        IO.die(MyLSM.Utf8.Handle, U32.from_nat(1n), "public performance write failed")
    case (handle, Done{_}): IO.pure(MyLSM.Utf8.Handle, handle)

# Continues the public step fixture step.
def public_step(handle: MyLSM.Utf8.Handle) -> IO(MyLSM.Utf8.Handle):
  do IO<MyLSM.Utf8.Handle>:
    pair : MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, MyLSM.WriteOutcome> <- MyLSM.Utf8.put(handle, "key", "value")
    public_step_result(pair)

# Continues the public loop fixture step.
def public_loop(fuel: Nat, handle: MyLSM.Utf8.Handle) -> IO(MyLSM.Utf8.Handle):
  match fuel:
    case 0n: IO.pure(MyLSM.Utf8.Handle, handle)
    case 1n+rest:
      do IO<MyLSM.Utf8.Handle>:
        next : MyLSM.Utf8.Handle <- public_step(handle)
        public_loop(rest, next)

# Continues the public closed fixture step.
def public_closed(start: Nat, +writes: Nat, handle: MyLSM.Utf8.Handle) -> IO(Unit):
  do IO<Unit>:
    stop : Nat <- IO.now()
    +elapsed : Nat <- IO.pure(Nat, Nat.sub(stop, start))
    _elapsed : Unit <- IO.print("writes=" ++ Nat.show(writes) ++ " elapsed_ms=" ++ Nat.show(elapsed))
    _latency : Unit <- IO.print("latency_us=" ++ Nat.show(Nat.div(Nat.mul(elapsed, 1000n), writes)))
    _throughput : Unit <- IO.print("throughput_ops_s=" ++ Nat.show(Nat.div(Nat.mul(writes, 1000n), elapsed)))
    result : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
    close_public(result)

# Continues the public run fixture step.
def public_run(start: Nat, +writes: Nat, handle: MyLSM.Utf8.Handle) -> IO(Unit):
  do IO<Unit>:
    done : MyLSM.Utf8.Handle <- public_loop(writes, handle)
    public_closed(start, writes, done)

# Continues the public opened fixture step.
def public_opened(result: Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle>, writes: Nat) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, U32.from_nat(1n), "public performance open failed")
    case Done{handle}:
      do IO<Unit>:
        start : Nat <- IO.now()
        public_run(start, writes, handle)

# Runs the seed result step of this fixture.
def seed_result(result: Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, U32.from_nat(1n), "performance seed failed")
    case Done{handle}:
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        close_public(closed)

# Continues the public recovered fixture step.
def public_recovered(start: Nat, result: Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, U32.from_nat(1n), "public performance recovery failed")
    case Done{handle}:
      do IO<Unit>:
        stop : Nat <- IO.now()
        _elapsed : Unit <- IO.print("recovery_ms=" ++ Nat.show(Nat.sub(stop, start)))
        closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        close_public(closed)

# Runs the dispatch step of this fixture.
def dispatch(mode: String, +path: String, writes: Nat) -> IO(Unit):
  match mode:
    case "seed":
      do IO<Unit>:
        result : Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle> <- MyLSM.Utf8.create(path)
        seed_result(result)
    case "public":
      do IO<Unit>:
        result : Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle> <- MyLSM.Utf8.open_existing(path)
        public_opened(result, writes)
    case "public_recover":
      do IO<Unit>:
        start : Nat <- IO.now()
        result : Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle> <- MyLSM.Utf8.open_existing(path)
        public_recovered(start, result)
    case _:
      IO.die(Unit, 2, "unknown MYLSM_PERF_MODE")

def main() -> IO(Unit):
  do IO<Unit>:
    +mode : String <- IO.try(String, Console.get_env("MYLSM_PERF_MODE"))
    +path : String <- IO.try(String, Console.get_env("MYLSM_PERF_PATH"))
    writes_text : String <- IO.try(String, Console.get_env("MYLSM_PERF_WRITES"))
    +writes : Nat <- IO.pure(Nat, Common.nat_default(Nat.read(writes_text), 1000n))
    dispatch(mode, path, writes)

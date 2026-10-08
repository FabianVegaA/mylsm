import Base
import ../../src/Console.bend as Console
import ../../src/Db.bend as Db
import ../../src/DbIo.bend as DbIo
import ../../src/DbLock.bend as DbLock
import ../../src/DurableError.bend as DurableError
import ../../src/Recover.bend as Recover
import ../../src/Wal.bend as Wal
import ../../mylsm.bend as MyLSM
import ../lib/common.bend as Common

# Runs the close public step of this fixture.
def close_public(result: Result<&1, &1, MyLSM.Error, Unit>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, U32.from_nat(1n), "public performance close failed")
    case Done{Unit{}}: IO.pure(Unit, Unit{})

# Continues the public step result fixture step.
def public_step_result(pair: MyLSM.Handle & Result<&1, &1, MyLSM.Error, MyLSM.WriteOutcome>) -> IO(MyLSM.Handle):
  match pair:
    case (handle, Fail{_}):
      do IO<MyLSM.Handle>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(MyLSM.Handle, U32.from_nat(1n), "public performance write failed")
    case (handle, Done{_}): IO.pure(MyLSM.Handle, handle)

# Continues the public step fixture step.
def public_step(handle: MyLSM.Handle) -> IO(MyLSM.Handle):
  do IO<MyLSM.Handle>:
    pair : MyLSM.Handle & Result<&1, &1, MyLSM.Error, MyLSM.WriteOutcome> <- MyLSM.put(handle, "key", "value")
    public_step_result(pair)

# Continues the public loop fixture step.
def public_loop(fuel: Nat, handle: MyLSM.Handle) -> IO(MyLSM.Handle):
  match fuel:
    case 0n: IO.pure(MyLSM.Handle, handle)
    case 1n+rest:
      do IO<MyLSM.Handle>:
        next : MyLSM.Handle <- public_step(handle)
        public_loop(rest, next)

# Continues the internal step result fixture step.
def internal_step_result(result: Result<&1, &1, U32 & String, Db.Db>) -> IO(Db.Db):
  match result:
    case Fail{_}: IO.die(Db.Db, U32.from_nat(1n), "internal performance write failed")
    case Done{db}: IO.pure(Db.Db, db)

# Continues the internal step fixture step.
def internal_step(db: Db.Db) -> IO(Db.Db):
  do IO<Db.Db>:
    result : Result<&1, &1, U32 & String, Db.Db> <- Recover.write(db, Wal.Batch{Con{Wal.Put{"key", "value"}, Nil{}}})
    internal_step_result(result)

# Continues the internal loop fixture step.
def internal_loop(fuel: Nat, db: Db.Db) -> IO(Db.Db):
  match fuel:
    case 0n: IO.pure(Db.Db, db)
    case 1n+rest:
      do IO<Db.Db>:
        next : Db.Db <- internal_step(db)
        internal_loop(rest, next)

# Continues the public closed fixture step.
def public_closed(start: Nat, +writes: Nat, handle: MyLSM.Handle) -> IO(Unit):
  do IO<Unit>:
    stop : Nat <- IO.now()
    +elapsed : Nat <- IO.pure(Nat, Nat.sub(stop, start))
    _elapsed : Unit <- IO.print("writes=" ++ Nat.show(writes) ++ " elapsed_ms=" ++ Nat.show(elapsed))
    _latency : Unit <- IO.print("latency_us=" ++ Nat.show(Nat.div(Nat.mul(elapsed, 1000n), writes)))
    _throughput : Unit <- IO.print("throughput_ops_s=" ++ Nat.show(Nat.div(Nat.mul(writes, 1000n), elapsed)))
    result : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
    close_public(result)

# Continues the public run fixture step.
def public_run(start: Nat, +writes: Nat, handle: MyLSM.Handle) -> IO(Unit):
  do IO<Unit>:
    done : MyLSM.Handle <- public_loop(writes, handle)
    public_closed(start, writes, done)

# Continues the internal released fixture step.
def internal_released(result: Result<&1, &1, DurableError.Error, Unit>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, U32.from_nat(1n), "internal performance lock release failed")
    case Done{Unit{}}: IO.pure(Unit, Unit{})

# Continues the internal run fixture step.
def internal_run(start: Nat, +writes: Nat, lock: DbLock.Lock, db: Db.Db) -> IO(Unit):
  do IO<Unit>:
    _done : Db.Db <- internal_loop(writes, db)
    stop : Nat <- IO.now()
    +elapsed : Nat <- IO.pure(Nat, Nat.sub(stop, start))
    _elapsed : Unit <- IO.print("writes=" ++ Nat.show(writes) ++ " elapsed_ms=" ++ Nat.show(elapsed))
    _latency : Unit <- IO.print("latency_us=" ++ Nat.show(Nat.div(Nat.mul(elapsed, 1000n), writes)))
    _throughput : Unit <- IO.print("throughput_ops_s=" ++ Nat.show(Nat.div(Nat.mul(writes, 1000n), elapsed)))
    released : Result<&1, &1, DurableError.Error, Unit> <- DbLock.release(lock, "close", "")
    internal_released(released)

# Continues the internal locked fixture step.
def internal_locked(lock: DbLock.Lock, result: Result<&1, &1, U32 & String, Db.Db>, writes: Nat) -> IO(Unit):
  match result:
    case Fail{_}:
      do IO<Unit>:
        _released : Result<&1, &1, DurableError.Error, Unit> <- DbLock.release(lock, "close", "")
        IO.die(Unit, U32.from_nat(1n), "internal performance open failed")
    case Done{db}:
      do IO<Unit>:
        start : Nat <- IO.now()
        internal_run(start, writes, lock, db)

# Continues the internal lock result fixture step.
def internal_lock_result(
  result: Result<&1, &1, DurableError.Error, DbLock.Lock>,
  path: String,
  writes: Nat
) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, U32.from_nat(1n), "internal performance lock failed")
    case Done{lock}:
      do IO<Unit>:
        opened : Result<&1, &1, U32 & String, Db.Db> <- Recover.open_db(path)
        internal_locked(lock, opened, writes)

# Continues the public opened fixture step.
def public_opened(result: Result<&1, &1, MyLSM.Error, MyLSM.Handle>, writes: Nat) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, U32.from_nat(1n), "public performance open failed")
    case Done{handle}:
      do IO<Unit>:
        start : Nat <- IO.now()
        public_run(start, writes, handle)

# Runs the seed result step of this fixture.
def seed_result(result: Result<&1, &1, MyLSM.Error, MyLSM.Handle>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, U32.from_nat(1n), "performance seed failed")
    case Done{handle}:
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        close_public(closed)

# Continues the public recovered fixture step.
def public_recovered(start: Nat, result: Result<&1, &1, MyLSM.Error, MyLSM.Handle>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, U32.from_nat(1n), "public performance recovery failed")
    case Done{handle}:
      do IO<Unit>:
        stop : Nat <- IO.now()
        _elapsed : Unit <- IO.print("recovery_ms=" ++ Nat.show(Nat.sub(stop, start)))
        closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        close_public(closed)

# Continues the internal recovered fixture step.
def internal_recovered(start: Nat, lock: DbLock.Lock, result: Result<&1, &1, U32 & String, Db.Db>) -> IO(Unit):
  match result:
    case Fail{_}:
      do IO<Unit>:
        _released : Result<&1, &1, DurableError.Error, Unit> <- DbLock.release(lock, "close", "")
        IO.die(Unit, U32.from_nat(1n), "internal performance recovery failed")
    case Done{_}:
      do IO<Unit>:
        stop : Nat <- IO.now()
        _elapsed : Unit <- IO.print("recovery_ms=" ++ Nat.show(Nat.sub(stop, start)))
        released : Result<&1, &1, DurableError.Error, Unit> <- DbLock.release(lock, "close", "")
        internal_released(released)

# Continues the internal recovery lock fixture step.
def internal_recovery_lock(
  start: Nat,
  path: String,
  result: Result<&1, &1, DurableError.Error, DbLock.Lock>
) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, U32.from_nat(1n), "internal performance recovery lock failed")
    case Done{lock}:
      do IO<Unit>:
        recovered : Result<&1, &1, U32 & String, Db.Db> <- Recover.open_db(path)
        internal_recovered(start, lock, recovered)

# Runs the dispatch step of this fixture.
def dispatch(mode: String, +path: String, writes: Nat) -> IO(Unit):
  match mode:
    case "seed":
      do IO<Unit>:
        result : Result<&1, &1, MyLSM.Error, MyLSM.Handle> <- MyLSM.create(path)
        seed_result(result)
    case "public":
      do IO<Unit>:
        result : Result<&1, &1, MyLSM.Error, MyLSM.Handle> <- MyLSM.open_existing(path)
        public_opened(result, writes)
    case "public_recover":
      do IO<Unit>:
        start : Nat <- IO.now()
        result : Result<&1, &1, MyLSM.Error, MyLSM.Handle> <- MyLSM.open_existing(path)
        public_recovered(start, result)
    case "internal_recover":
      do IO<Unit>:
        start : Nat <- IO.now()
        locked : Result<&1, &1, DurableError.Error, DbLock.Lock> <- DbLock.acquire(path, "open_existing")
        internal_recovery_lock(start, path, locked)
    case _:
      do IO<Unit>:
        locked : Result<&1, &1, DurableError.Error, DbLock.Lock> <- DbLock.acquire(path, "open_existing")
        internal_lock_result(locked, path, writes)

def main() -> IO(Unit):
  do IO<Unit>:
    +mode : String <- IO.try(String, Console.get_env("MYLSM_PERF_MODE"))
    +path : String <- IO.try(String, Console.get_env("MYLSM_PERF_PATH"))
    writes_text : String <- IO.try(String, Console.get_env("MYLSM_PERF_WRITES"))
    +writes : Nat <- IO.pure(Nat, Common.nat_default(Nat.read(writes_text), 1000n))
    dispatch(mode, path, writes)

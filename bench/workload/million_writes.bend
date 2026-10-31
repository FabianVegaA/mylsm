import Base
import ../../mylsm.bend as MyLSM
import ../../src/Console.bend as Console
import ../lib/common.bend as Common

# Stops the benchmark with a message.
def fail(-A: Type, message: String) -> IO(A):
  IO.die(A, 1, message)

# Takes the handle back after a write or stops the run.
def written(
  pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, MyLSM.WriteOutcome>
) -> IO(MyLSM.Utf8.Handle):
  match pair:
    case (handle, Done{_}): IO.pure(MyLSM.Utf8.Handle, handle)
    case (_, Fail{_}): fail(MyLSM.Utf8.Handle, "benchmark write failed")

# Takes the handle back after a flush or stops the run.
def flushed(
  pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Unit>
) -> IO(MyLSM.Utf8.Handle):
  match pair:
    case (handle, Done{Unit{}}): IO.pure(MyLSM.Utf8.Handle, handle)
    case (_, Fail{_}): fail(MyLSM.Utf8.Handle, "benchmark flush failed")

def flush.due(due: Bool, handle: MyLSM.Utf8.Handle) -> IO(MyLSM.Utf8.Handle):
  match due:
    case False{}: IO.pure(MyLSM.Utf8.Handle, handle)
    case True{}:
      do IO<MyLSM.Utf8.Handle>:
        pair : MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Unit> <-
          MyLSM.Utf8.flush(handle)
        flushed(pair)

# Writes key-N=value-N for each index and flushes every flush_every writes.
def write_many(
  fuel: Nat,
  +index: Nat,
  +flush_every: Nat,
  handle: MyLSM.Utf8.Handle
) -> IO(MyLSM.Utf8.Handle):
  match fuel:
    case 0n: IO.pure(MyLSM.Utf8.Handle, handle)
    case 1n+rest:
      do IO<MyLSM.Utf8.Handle>:
        pair : MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, MyLSM.WriteOutcome> <-
          MyLSM.Utf8.put(handle, "key-" ++ Nat.show(index), "value-" ++ Nat.show(index))
        next : MyLSM.Utf8.Handle <- written(pair)
        maintained : MyLSM.Utf8.Handle <- flush.due(
          Nat.is_eq(Nat.mod(Nat.add(index, 1n), flush_every), 0n), next)
        write_many(rest, Nat.add(index, 1n), flush_every, maintained)

# Takes the opened handle or stops the run.
def opened(
  result: Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle>
) -> IO(MyLSM.Utf8.Handle):
  match result:
    case Done{handle}: IO.pure(MyLSM.Utf8.Handle, handle)
    case Fail{_}: fail(MyLSM.Utf8.Handle, "benchmark database open failed")

# Takes the new handle, or opens the existing database.
def created(
  +dir: String,
  result: Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle>
) -> IO(MyLSM.Utf8.Handle):
  match result:
    case Done{handle}: IO.pure(MyLSM.Utf8.Handle, handle)
    case Fail{_}:
      do IO<MyLSM.Utf8.Handle>:
        existing : Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle> <-
          MyLSM.Utf8.open_existing(dir)
        opened(existing)

# Opens the benchmark database, creating it when missing.
def open(+dir: String) -> IO(MyLSM.Utf8.Handle):
  do IO<MyLSM.Utf8.Handle>:
    result : Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle> <- MyLSM.Utf8.create(dir)
    created(dir, result)

def report.closed(closed: Result<&1, &1, MyLSM.Utf8.Error, Unit>) -> IO(Unit):
  match closed:
    case Done{Unit{}}: IO.pure(Unit, Unit{})
    case Fail{_}: fail(Unit, "benchmark database close failed")

# Prints the sample verdict and closes the handle.
def report(phase: String, pair: MyLSM.Utf8.Handle & Bool) -> IO(Unit):
  match pair:
    case (handle, ok):
      do IO<Unit>:
        _printed : Unit <- IO.print("phase=" ++ phase ++ " samples=" ++ Common.bool_text(ok))
        closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        report.closed(closed)

def main() -> IO(Unit):
  do IO<Unit>:
    count_env : String <- IO.try(String, Console.get_env("MYLSM_BENCH_WRITES"))
    dir_env : String <- IO.try(String, Console.get_env("MYLSM_BENCH_DIR"))
    flush_env : String <- IO.try(String, Console.get_env("MYLSM_BENCH_FLUSH_EVERY"))
    +count : Nat <- IO.pure(Nat, Common.nat_default(Nat.read(count_env), 1000000n))
    +dir : String <- IO.pure(String, Common.env_default(dir_env, ".mylsm-million-write-data"))
    +flush_every : Nat <- IO.pure(Nat, Nat.max(1n, Common.nat_default(Nat.read(flush_env), 4096n)))
    handle : MyLSM.Utf8.Handle <- open(dir)
    t0 : Nat <- IO.now()
    completed : MyLSM.Utf8.Handle <- write_many(count, 0n, flush_every, handle)
    t1 : Nat <- IO.now()
    _count : Unit <- IO.print("writes_completed=" ++ Nat.show(count))
    _elapsed : Unit <- IO.print("elapsed_ms=" ++ Nat.show(Nat.sub(t1, t0)))
    before : MyLSM.Utf8.Handle & Bool <- Common.samples(completed, count)
    _before : Unit <- report("pre_recovery", before)
    reopened : MyLSM.Utf8.Handle <- open(dir)
    after : MyLSM.Utf8.Handle & Bool <- Common.samples(reopened, count)
    _after : Unit <- report("post_recovery", after)
    IO.print("database=" ++ dir)

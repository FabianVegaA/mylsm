import Base
import ../src/Console.bend as Console
import ../src/Db.bend as Db
import ../src/Recover.bend as Recover
import ../src/MemTable.bend as MemTable
import ../src/Sstable.bend as Sstable
import ../src/Wal.bend as Wal

# Phase D metrics harness: write loop tracking logical bytes, first/middle/
# last samples, timed recovery, and 101 sampled point reads (raw sample_ms
# lines; percentiles computed by bench/phase3_metrics.sh via sort, never here).

def env_default(value: String, fallback: String) -> String:
  match value:
    case SNil{}: fallback
    case SCon{h, t}: SCon{h, t}

def nat_default(value: Maybe<&2, Nat>, fallback: Nat) -> Nat:
  match value:
    case None{}: fallback
    case Some{n}: n

def bool_text(ok: Bool) -> String:
  match ok:
    case True{}: "pass"
    case False{}: "fail"

def maybe_value_eq(got: Maybe<&2, String>, +expected: String) -> Bool:
  match got:
    case None{}:
      False{}
    case Some{value}:
      String.eq(value, expected)

def samples_and(first: Bool, second: Bool, third: Bool) -> Bool:
  match first:
    case False{}:
      False{}
    case True{}:
      match second:
        case False{}:
          False{}
        case True{}:
          third

def samples_ok(+db: Db.Db, +count: Nat) -> Bool:
  +middle = Nat.div(count, 2n)
  +last = Nat.sub(count, 1n)
  samples_and(
    maybe_value_eq(Db.db_get(db, "key-0"), "value-0"),
    maybe_value_eq(Db.db_get(db, "key-" ++ Nat.show(middle)), "value-" ++ Nat.show(middle)),
    maybe_value_eq(Db.db_get(db, "key-" ++ Nat.show(last)), "value-" ++ Nat.show(last)))

def write_many(fuel: Nat, +index: Nat, db: Db.Db) -> IO(Db.Db):
  match fuel:
    case 0n:
      IO.pure(Db.Db, db)
    case 1n+rest:
      do IO<Db.Db>:
        next : Db.Db <- IO.try(Db.Db, Recover.write(db, Wal.Batch{Con{Wal.Put{"key-" ++ Nat.show(index), "value-" ++ Nat.show(index)}, Nil{}}}))
        write_many(rest, Nat.add(index, 1n), next)

def logical_go(fuel: Nat, +start: Nat, acc: Nat) -> Nat:
  match fuel:
    case 0n:
      acc
    case 1n+f:
      logical_go(f, Nat.add(start, 1n), Nat.add(acc, Nat.add(String.length("key-" ++ Nat.show(start)), String.length("value-" ++ Nat.show(start)))))

def sample_reads(+samples: Nat, +db: Db.Db, +count: Nat) -> IO(Unit):
  match samples:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+rest:
      do IO<Unit>:
        +probe : Nat <- IO.pure(Nat, Nat.div(Nat.mul(count, Nat.sub(101n, samples)), 101n))
        start : Nat <- IO.now()
        _got : Maybe<&2, String> <- IO.pure(Maybe<&2, String>, Db.db_get(db, "key-" ++ Nat.show(probe)))
        stop : Nat <- IO.now()
        _pd : Unit <- IO.print("sample_ms=" ++ Nat.show(Nat.sub(stop, start)))
        sample_reads(rest, db, count)
        sample_reads(rest, db, count)

def main() -> IO(Unit):
  do IO<Unit>:
    count_env : String <- IO.try(String, Console.get_env("MYLSM_BENCH_WRITES"))
    dir_env : String <- IO.try(String, Console.get_env("MYLSM_BENCH_DIR"))
    +count : Nat <- IO.pure(Nat, nat_default(Nat.read(count_env), 20485n))
    +dir : String <- IO.pure(String, env_default(dir_env, ".mylsm-phase3-metrics-data"))
    db : Db.Db <- IO.try(Db.Db, Recover.open_db(dir))
    t0 : Nat <- IO.now()
    +completed : Db.Db <- write_many(count, 0n, db)
    t1 : Nat <- IO.now()
    +logical : Nat <- IO.pure(Nat, logical_go(count, 0n, 0n))
    _u0 : Unit <- IO.print("metric_writes_completed=" ++ Nat.show(count))
    _u1 : Unit <- IO.print("metric_elapsed_ms=" ++ Nat.show(Nat.sub(t1, t0)))
    _u2 : Unit <- IO.print("metric_logical_bytes=" ++ Nat.show(logical))
    _u3 : Unit <- IO.print("phase=pre_recovery samples=" ++ bool_text(samples_ok(completed, count)))
    r0 : Nat <- IO.now()
    +reopened : Db.Db <- IO.try(Db.Db, Recover.open_db(dir))
    r1 : Nat <- IO.now()
    _u4 : Unit <- IO.print("metric_recovery_ms=" ++ Nat.show(Nat.sub(r1, r0)))
    _u5 : Unit <- IO.print("phase=post_recovery samples=" ++ bool_text(samples_ok(reopened, count)))
    _u6 : Unit <- sample_reads(101n, reopened, count)
    IO.print("metrics_harness=complete")

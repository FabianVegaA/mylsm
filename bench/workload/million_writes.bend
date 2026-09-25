import Base
import ../../src/Console.bend as Console
import ../../src/Db.bend as Db
import ../../src/Recover.bend as Recover
import ../../src/MemTable.bend as MemTable
import ../../src/Sstable.bend as Sstable
import ../../src/Wal.bend as Wal
import ../lib/common.bend as Common

def write_many(fuel: Nat, +index: Nat, db: Db.Db) -> IO(Db.Db):
  match fuel:
    case 0n:
      IO.pure(Db.Db, db)
    case 1n+rest:
      do IO<Db.Db>:
        next : Db.Db <- IO.try(Db.Db, Recover.write(db, Wal.Batch{Con{Wal.Put{"key-" ++ Nat.show(index), "value-" ++ Nat.show(index)}, Nil{}}}))
        write_many(rest, Nat.add(index, 1n), next)

def main() -> IO(Unit):
  do IO<Unit>:
    count_env : String <- IO.try(String, Console.get_env("MYLSM_BENCH_WRITES"))
    dir_env : String <- IO.try(String, Console.get_env("MYLSM_BENCH_DIR"))
    +count : Nat <- IO.pure(Nat, Common.nat_default(Nat.read(count_env), 1000000n))
    +dir : String <- IO.pure(String, Common.env_default(dir_env, ".mylsm-million-write-data"))
    db : Db.Db <- IO.try(Db.Db, Recover.open_db(dir))
    t0 : Nat <- IO.now()
    +completed : Db.Db <- write_many(count, 0n, db)
    t1 : Nat <- IO.now()
    _u0 : Unit <- IO.print("writes_completed=" ++ Nat.show(count))
    _u1 : Unit <- IO.print("elapsed_ms=" ++ Nat.show(Nat.sub(t1, t0)))
    _u2 : Unit <- IO.print("phase=pre_recovery samples=" ++ Common.bool_text(Common.samples_ok(completed, count)))
    _u3 : Unit <- Common.print_shape("pre_recovery", completed)
    +recovered : Db.Db <- IO.try(Db.Db, Recover.open_db(dir))
    _u4 : Unit <- IO.print("phase=post_recovery samples=" ++ Common.bool_text(Common.samples_ok(recovered, count)))
    _u5 : Unit <- Common.print_shape("post_recovery", recovered)
    IO.print("database=" ++ dir)

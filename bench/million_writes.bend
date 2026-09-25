import Base
import ../src/Console.bend as Console
import ../src/Db.bend as Db
import ../src/Recover.bend as Recover
import ../src/MemTable.bend as MemTable
import ../src/Sstable.bend as Sstable
import ../src/Wal.bend as Wal

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

def and3(first: Bool, second: Bool, third: Bool) -> Bool:
  match first:
    case False{}: False{}
    case True{}:
      match second:
        case False{}: False{}
        case True{}: third

def samples_ok(+db: Db.Db, +count: Nat) -> Bool:
  +middle = Nat.div(count, 2n)
  +last = Nat.sub(count, 1n)
  and3(
    maybe_value_eq(Db.db_get(db, "key-0"), "value-0"),
    maybe_value_eq(Db.db_get(db, "key-" ++ Nat.show(middle)), "value-" ++ Nat.show(middle)),
    maybe_value_eq(Db.db_get(db, "key-" ++ Nat.show(last)), "value-" ++ Nat.show(last)))

def mem_count(db: Db.Db) -> Nat:
  match db:
    case Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token}:
      MemTable.count(mem)

def first_level(levels: List<&2, List<&2, Sstable.Table>>) -> List<&2, Sstable.Table>:
  match levels:
    case Nil{}: Nil{}
    case Con{level, rest}: level

def rest_levels(levels: List<&2, List<&2, Sstable.Table>>) -> List<&2, List<&2, Sstable.Table>>:
  match levels:
    case Nil{}: Nil{}
    case Con{level, rest}: rest

def level_count(db: Db.Db, level: Nat) -> Nat:
  match db:
    case Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token}:
      match level:
        case 0n:
          List.length(&2, Sstable.Table, first_level(levels))
        case 1n+n:
          List.length(&2, Sstable.Table, first_level(rest_levels(levels)))

def print_shape(+phase: String, +db: Db.Db) -> IO(Unit):
  IO.print("phase=" ++ phase ++ " mem_entries=" ++ Nat.show(mem_count(db)) ++ " l0_tables=" ++ Nat.show(level_count(db, 0n)) ++ " l1_tables=" ++ Nat.show(level_count(db, 1n)))

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
    +count : Nat <- IO.pure(Nat, nat_default(Nat.read(count_env), 1000000n))
    +dir : String <- IO.pure(String, env_default(dir_env, ".mylsm-million-write-data"))
    db : Db.Db <- IO.try(Db.Db, Recover.open_db(dir))
    t0 : Nat <- IO.now()
    +completed : Db.Db <- write_many(count, 0n, db)
    t1 : Nat <- IO.now()
    _u0 : Unit <- IO.print("writes_completed=" ++ Nat.show(count))
    _u1 : Unit <- IO.print("elapsed_ms=" ++ Nat.show(Nat.sub(t1, t0)))
    _u2 : Unit <- IO.print("phase=pre_recovery samples=" ++ bool_text(samples_ok(completed, count)))
    _u3 : Unit <- print_shape("pre_recovery", completed)
    +recovered : Db.Db <- IO.try(Db.Db, Recover.open_db(dir))
    _u4 : Unit <- IO.print("phase=post_recovery samples=" ++ bool_text(samples_ok(recovered, count)))
    _u5 : Unit <- print_shape("post_recovery", recovered)
    IO.print("database=" ++ dir)

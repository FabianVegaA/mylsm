import Base
import ../../src/Console.bend as Console
import ../../src/Db.bend as Db
import ../../src/Recover.bend as Recover
import ../../src/MemTable.bend as MemTable
import ../../src/Sstable.bend as Sstable
import ../../src/Wal.bend as Wal

# Shared bench helpers, deduplicated from million_writes.bend,
# phase3_metrics.bend, compaction_bench.bend, crash_worker.bend and app/.

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

def mem_count(db: Db.Db) -> Nat:
  match db:
    case Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}:
      MemTable.count(mem)

def frozen_count(db: Db.Db) -> Nat:
  match db:
    case Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}:
      MemTable.count(frozen)

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
    case Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}:
      match level:
        case 0n:
          List.length(&2, Sstable.Table, first_level(levels))
        case 1n+n:
          List.length(&2, Sstable.Table, first_level(rest_levels(levels)))

def print_shape(+phase: String, +db: Db.Db) -> IO(Unit):
  IO.print("phase=" ++ phase ++ " mem_entries=" ++ Nat.show(mem_count(db)) ++ " frozen_entries=" ++ Nat.show(frozen_count(db)) ++ " l0_tables=" ++ Nat.show(level_count(db, 0n)) ++ " l1_tables=" ++ Nat.show(level_count(db, 1n)))

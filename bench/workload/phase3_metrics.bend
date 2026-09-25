import Base
import ../../src/Console.bend as Console
import ../../src/Db.bend as Db
import ../../src/Fs.bend as Fs
import ../../src/Recover.bend as Recover
import ../../src/MemTable.bend as MemTable
import ../../src/Sstable.bend as Sstable
import ../../src/Wal.bend as Wal
import ../lib/common.bend as Common

# Phase D metrics harness: write loop tracking logical bytes, first/middle/
# last samples, timed recovery, and 101 sampled point reads.

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

def sample_reads(+samples: Nat, +db: Db.Db, +count: Nat, acc: List<&2, Nat>) -> IO(List<&2, Nat>):
  match samples:
    case 0n:
      IO.pure(List<&2, Nat>, acc)
    case 1n+rest:
      do IO<List<&2, Nat>>:
        +probe : Nat <- IO.pure(Nat, Nat.div(Nat.mul(count, Nat.sub(101n, samples)), 101n))
        +start : Nat <- IO.now()
        _got : Maybe<&2, String> <- IO.pure(Maybe<&2, String>, Db.db_get(db, "key-" ++ Nat.show(probe)))
        +stop : Nat <- IO.now()
        _pd : Unit <- IO.print("sample_ms=" ++ Nat.show(Nat.sub(stop, start)))
        sample_reads(rest, db, count, Con{Nat.sub(stop, start), acc})

def frac_pick(small: Bool, +frac: Nat) -> String:
  match small:
    case True{}:
      "0" ++ Nat.show(frac)
    case False{}:
      Nat.show(frac)

def print_ratio(+tag: String, +num: Nat, +den: Nat) -> IO(Unit):
  match den:
    case 0n:
      IO.print(tag ++ "=unknown")
    case 1n+d:
      +scaled = Nat.div(Nat.mul(num, 100n), den)
      +frac = Nat.mod(scaled, 100n)
      IO.print(tag ++ "=" ++ Nat.show(Nat.div(scaled, 100n)) ++ "." ++ frac_pick(Nat.is_le(frac, 9n), frac))

# Bucket order statistics for percentiles (sorting would need mutually
# recursive helpers, which the checker forbids; all shapes here mirror
# proven merge_go/scan_go patterns). Readings above 63 ms clamp.

def empty_buckets(count: Nat, acc: List<&2, List<&2, Nat>>) -> List<&2, List<&2, Nat>>:
  match count:
    case 0n:
      acc
    case 1n+m:
      empty_buckets(m, Con{Nil{}, acc})

def bucket_add(+buckets: List<&2, List<&2, Nat>>, ix: Nat, val: Nat) -> List<&2, List<&2, Nat>>:
  match buckets:
    case Nil{}:
      Nil{}
    case Con{+b, t}:
      match ix:
        case 0n:
          Con{Con{val, b}, t}
        case 1n+p:
          Con{b, bucket_add(t, p, val)}

def fill_buckets(+samples: List<&2, Nat>, +buckets: List<&2, List<&2, Nat>>) -> List<&2, List<&2, Nat>>:
  match samples:
    case Nil{}:
      buckets
    case Con{+ms, t}:
      fill_buckets(t, bucket_add(buckets, Nat.min(ms, 63n), ms))

def concat_all(+buckets: List<&2, List<&2, Nat>>) -> List<&2, Nat>:
  match buckets:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      List.append(&2, Nat, h, concat_all(t))

def nth_sorted(bound: Nat, +ix: Nat, +xs: List<&2, Nat>) -> Nat:
  match bound ix xs:
    case 0n _ _:
      0n
    case 1n+f _ Nil{}:
      0n
    case 1n+f 0n Con{h, t}:
      h
    case 1n+f 1n+p Con{h, t}:
      nth_sorted(f, p, t)

# Byte accounting over the data dir (replaces shell wc).

def pick_size(tbl: Bool, size: Nat) -> Nat:
  match tbl:
    case True{}:
      size
    case False{}:
      0n

def sum_go(names: List<&1, String>, +dir: String, acc: Nat) -> IO(Nat):
  match names:
    case Nil{}:
      IO.pure(Nat, acc)
    case Con{+h, t}:
      do IO<Nat>:
        size : Nat <- IO.try(Nat, Fs.file_size(dir ++ "/" ++ h))
        sum_go(t, dir, Nat.add(acc, pick_size(String.ends_with(h, ".tbl"), size)))

def level_sized(present: Bool, +dir: String, +sub: String) -> IO(Nat):
  match present:
    case False{}:
      IO.pure(Nat, 0n)
    case True{}:
      do IO<Nat>:
        names : List<&1, String> <- IO.try(List<&1, String>, Fs.read_dir(dir ++ "/" ++ sub))
        sum_go(names, dir ++ "/" ++ sub, 0n)

def level_bytes(+dir: String, +sub: String) -> IO(Nat):
  do IO<Nat>:
    present : Bool <- IO.try(Bool, Fs.exists(dir ++ "/" ++ sub))
    level_sized(present, dir, sub)

def size_if(present: Bool, +dir: String, +file: String) -> IO(Nat):
  match present:
    case False{}:
      IO.pure(Nat, 0n)
    case True{}:
      do IO<Nat>:
        size : Nat <- IO.try(Nat, Fs.file_size(dir ++ "/" ++ file))
        IO.pure(Nat, size)

def file_bytes(+dir: String, +file: String) -> IO(Nat):
  do IO<Nat>:
    present : Bool <- IO.try(Bool, Fs.exists(dir ++ "/" ++ file))
    size_if(present, dir, file)

def main() -> IO(Unit):
  do IO<Unit>:
    count_env : String <- IO.try(String, Console.get_env("MYLSM_BENCH_WRITES"))
    dir_env : String <- IO.try(String, Console.get_env("MYLSM_BENCH_DIR"))
    +count : Nat <- IO.pure(Nat, Common.nat_default(Nat.read(count_env), 20485n))
    +dir : String <- IO.pure(String, Common.env_default(dir_env, ".mylsm-phase3-metrics-data"))
    db : Db.Db <- IO.try(Db.Db, Recover.open_db(dir))
    +t0 : Nat <- IO.now()
    +completed : Db.Db <- write_many(count, 0n, db)
    +t1 : Nat <- IO.now()
    +logical : Nat <- IO.pure(Nat, logical_go(count, 0n, 0n))
    _u0 : Unit <- IO.print("metric_writes_completed=" ++ Nat.show(count))
    _u1 : Unit <- IO.print("metric_elapsed_ms=" ++ Nat.show(Nat.sub(t1, t0)))
    _u2 : Unit <- IO.print("metric_logical_bytes=" ++ Nat.show(logical))
    _u3 : Unit <- IO.print("phase=pre_recovery samples=" ++ Common.bool_text(Common.samples_ok(completed, count)))
    +r0 : Nat <- IO.now()
    +reopened : Db.Db <- IO.try(Db.Db, Recover.open_db(dir))
    +r1 : Nat <- IO.now()
    _u4 : Unit <- IO.print("metric_recovery_ms=" ++ Nat.show(Nat.sub(r1, r0)))
    _u5 : Unit <- IO.print("phase=post_recovery samples=" ++ Common.bool_text(Common.samples_ok(reopened, count)))
    +samples : List<&2, Nat> <- sample_reads(101n, reopened, count, Nil{})
    +ordered : List<&2, Nat> <- IO.pure(List<&2, Nat>, concat_all(fill_buckets(samples, empty_buckets(64n, Nil{}))))
    +olen : Nat <- IO.pure(Nat, List.length(&2, Nat, ordered))
    _u6 : Unit <- IO.print("metric_p50_read_ms=" ++ Nat.show(nth_sorted(olen, 50n, ordered)))
    _u7 : Unit <- IO.print("metric_p95_read_ms=" ++ Nat.show(nth_sorted(olen, 95n, ordered)))
    _u8 : Unit <- IO.print("metric_p99_read_ms=" ++ Nat.show(nth_sorted(olen, 99n, ordered)))
    _u9 : Unit <- IO.print("metric_read_samples=" ++ Nat.show(olen))
    +wal : Nat <- file_bytes(dir, "wal.log")
    +mfst : Nat <- file_bytes(dir, "MANIFEST")
    +l0 : Nat <- level_bytes(dir, "l0")
    +l1 : Nat <- level_bytes(dir, "l1")
    +l2 : Nat <- level_bytes(dir, "l2")
    +tables : Nat <- IO.pure(Nat, Nat.add(l0, Nat.add(l1, l2)))
    _u10 : Unit <- IO.print("metric_wal_bytes=" ++ Nat.show(wal))
    _u11 : Unit <- IO.print("metric_manifest_bytes=" ++ Nat.show(mfst))
    _u12 : Unit <- IO.print("metric_table_bytes=" ++ Nat.show(tables))
    _u13 : Unit <- print_ratio("metric_write_amplification", Nat.add(wal, Nat.add(mfst, tables)), logical)
    _u14 : Unit <- print_ratio("throughput_ops_per_sec", Nat.mul(count, 1000n), Nat.sub(t1, t0))
    IO.print("metrics_harness=complete")

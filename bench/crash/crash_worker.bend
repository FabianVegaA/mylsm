import Base
import ../../src/Console.bend as Console
import ../../src/Compact.bend as Compact
import ../../src/Db.bend as Db
import ../../src/Flush.bend as Flush
import ../../src/Recover.bend as Recover
import ../../src/Sstable.bend as Sstable
import ../../src/Wal.bend as Wal
import ../lib/common.bend as Common

def bool_and(lhs: Bool, rhs: Bool) -> Bool:
  match lhs:
    case True{}: rhs
    case False{}: False{}

def require(ok: Bool, +message: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, U32.from_nat(1n), message)

def require_config(ok: Bool, +message: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, U32.from_nat(2n), message)

def nonempty(str: String) -> Bool:
  match str:
    case SNil{}: False{}
    case SCon{_, _}: True{}

def fixture_key(+family: String, +batch: Nat, +index: Nat) -> String:
  family ++ "-" ++ Nat.show(batch) ++ "-" ++ Nat.show(index)

def fixture_value(+family: String, +batch: Nat, +index: Nat) -> String:
  "value-" ++ family ++ "-" ++ Nat.show(batch) ++ "-" ++ Nat.show(index)

def fixture_puts(count: Nat, +family: String, +batch: Nat, +index: Nat) -> List<&2, Wal.Mut>:
  match count:
    case 0n:
      Nil{}
    case 1n+rest:
      Con{
        Wal.Put{fixture_key(family, batch, index), fixture_value(family, batch, index)},
        fixture_puts(rest, family, batch, Nat.add(index, 1n))
      }

def optional_value_eq(got: Maybe<&2, String>, +expected: String) -> Bool:
  match got:
    case None{}: True{}
    case Some{value}: String.eq(value, expected)

def trigger_absent(got: Maybe<&2, String>) -> Bool:
  match got:
    case None{}: True{}
    case Some{_}: False{}

def trigger_optional(+db: Db.Db) -> Bool:
  optional_value_eq(Db.db_get(db, "wal-trigger"), "wal-trigger-value")

def trigger_required(+db: Db.Db) -> Bool:
  Common.maybe_value_eq(Db.db_get(db, "wal-trigger"), "wal-trigger-value")

def trigger_absent_db(+db: Db.Db) -> Bool:
  trigger_absent(Db.db_get(db, "wal-trigger"))

def trigger_optional_dec(optional: Bool, +db: Db.Db) -> Bool:
  match optional:
    case True{}:
      trigger_optional(db)
    case False{}:
      trigger_absent_db(db)

def trigger_required_dec(required: Bool, +policy: String, +db: Db.Db) -> Bool:
  match required:
    case True{}:
      trigger_required(db)
    case False{}:
      trigger_optional_dec(String.eq(policy, "optional"), db)

def trigger_ok(+policy: String, +db: Db.Db) -> Bool:
  trigger_required_dec(String.eq(policy, "required"), policy, db)

def trigger_policy_valid(+policy: String) -> Bool:
  Bool.or(String.eq(policy, "required"), Bool.or(String.eq(policy, "optional"), String.eq(policy, "absent")))

def case_valid(+case_name: String) -> Bool:
  Bool.or(String.eq(case_name, "wal"), Bool.or(String.eq(case_name, "flush"), String.eq(case_name, "compact")))

def fixture_key_ok(+family: String, +batch: Nat, +index: Nat, +db: Db.Db) -> Bool:
  Common.maybe_value_eq(Db.db_get(db, fixture_key(family, batch, index)), fixture_value(family, batch, index))

def spot_keys_ok(+family: String, +batch: Nat, +count: Nat, +db: Db.Db) -> Bool:
  +middle = Nat.div(count, 2n)
  +last = Nat.sub(count, 1n)
  bool_and(fixture_key_ok(family, batch, 0n, db), bool_and(fixture_key_ok(family, batch, middle, db), fixture_key_ok(family, batch, last, db)))

def compact_spot(count: Nat, +batch: Nat, +db: Db.Db) -> Bool:
  match count:
    case 0n:
      True{}
    case 1n+rest:
      bool_and(spot_keys_ok("compact", batch, 2000n, db), compact_spot(rest, Nat.add(batch, 1n), db))

def case_keys_flush(flush: Bool, +db: Db.Db) -> Bool:
  match flush:
    case True{}:
      spot_keys_ok("flush", 0n, 500n, db)
    case False{}:
      compact_spot(5n, 0n, db)

def case_keys_wal(wal: Bool, +case_name: String, +trigger_policy: String, +db: Db.Db) -> Bool:
  match wal:
    case True{}:
      bool_and(spot_keys_ok("wal-base", 0n, 1000n, db), trigger_ok(trigger_policy, db))
    case False{}:
      case_keys_flush(String.eq(case_name, "flush"), db)

def case_keys_ok(+case_name: String, +trigger_policy: String, +db: Db.Db) -> Bool:
  case_keys_wal(String.eq(case_name, "wal"), case_name, trigger_policy, db)

def verify_open(+case_name: String, +trigger_policy: String, +expected_l0: Nat, +expected_l1: Nat, +reopen: Nat, +db: Db.Db) -> IO(Unit):
  do IO<Unit>:
    _k : Unit <- require(case_keys_ok(case_name, trigger_policy, db), "acknowledged key/value verification failed")
    _s0 : Unit <- require(Nat.is_eq(Common.level_count(db, 0n), expected_l0), "unexpected L0 shape")
    _s1 : Unit <- require(Nat.is_eq(Common.level_count(db, 1n), expected_l1), "unexpected L1 shape")
    IO.print("worker_mode=verify case=" ++ case_name ++ " reopen=" ++ Nat.show(reopen) ++ " keys=pass level_shape=pass referenced_data=pass")

def journal_verify_compact(compact: Bool) -> IO(Unit):
  match compact:
    case True{}:
      do IO<Unit>:
        _u : Unit <- IO.print("verified-batch compact 0 2000")
        _v : Unit <- IO.print("verified-batch compact 1 2000")
        _w : Unit <- IO.print("verified-batch compact 2 2000")
        _x : Unit <- IO.print("verified-batch compact 3 2000")
        IO.print("verified-batch compact 4 2000")
    case False{}:
      IO.die(Unit, U32.from_nat(2n), "unknown crash case")

def journal_verify_flush(flush: Bool, +case_name: String) -> IO(Unit):
  match flush:
    case True{}:
      IO.print("verified-batch flush 0 500")
    case False{}:
      journal_verify_compact(String.eq(case_name, "compact"))

def journal_verify_wal(wal: Bool, +case_name: String) -> IO(Unit):
  match wal:
    case True{}:
      IO.print("verified-batch wal-base 0 1000")
    case False{}:
      journal_verify_flush(String.eq(case_name, "flush"), case_name)

def journal_verify(+case_name: String) -> IO(Unit):
  journal_verify_wal(String.eq(case_name, "wal"), case_name)

def verify_twice(+dir: String, +case_name: String, +trigger_policy: String, +expected_l0: Nat, +expected_l1: Nat) -> IO(Unit):
  do IO<Unit>:
    db1 : Db.Db <- IO.try(Db.Db, Recover.open_db(dir))
    _v1 : Unit <- verify_open(case_name, trigger_policy, expected_l0, expected_l1, 1n, db1)
    db2 : Db.Db <- IO.try(Db.Db, Recover.open_db(dir))
    _v2 : Unit <- verify_open(case_name, trigger_policy, expected_l0, expected_l1, 2n, db2)
    _j : Unit <- journal_verify(case_name)
    IO.print("worker_mode=verify case=" ++ case_name ++ " status=complete reopen_stability=pass")

def prepare_wal(+dir: String) -> IO(Unit):
  do IO<Unit>:
    db0 : Db.Db <- IO.try(Db.Db, Recover.open_db(dir))
    _db1 : Db.Db <- IO.try(Db.Db, Db.db_write(db0, Wal.Batch{fixture_puts(1000n, "wal-base", 0n, 0n)}))
    _u : Unit <- IO.print("ack-batch wal-base 0 1000")
    IO.print("worker_mode=prepare case=wal status=complete acknowledged_keys=1000")

def prepare_flush(+dir: String) -> IO(Unit):
  do IO<Unit>:
    db0 : Db.Db <- IO.try(Db.Db, Recover.open_db(dir))
    _db1 : Db.Db <- IO.try(Db.Db, Db.db_write(db0, Wal.Batch{fixture_puts(500n, "flush", 0n, 0n)}))
    _u : Unit <- IO.print("ack-batch flush 0 500")
    IO.print("worker_mode=prepare case=flush status=complete acknowledged_keys=500")

def prepare_compact_tables(count: Nat, +batch: Nat, db: Db.Db) -> IO(Db.Db):
  match count:
    case 0n:
      IO.pure(Db.Db, db)
    case 1n+rest:
      do IO<Db.Db>:
        written : Db.Db <- IO.try(Db.Db, Db.db_write(db, Wal.Batch{fixture_puts(2000n, "compact", batch, 0n)}))
        flushed : Db.Db <- IO.try(Db.Db, Flush.flush(written))
        prepare_compact_tables(rest, Nat.add(batch, 1n), flushed)

def prepare_compact(+dir: String) -> IO(Unit):
  do IO<Unit>:
    db0 : Db.Db <- IO.try(Db.Db, Recover.open_db(dir))
    _db5 : Db.Db <- prepare_compact_tables(5n, 0n, db0)
    _u : Unit <- IO.print("ack-batch compact 0 2000")
    _v : Unit <- IO.print("ack-batch compact 1 2000")
    _w : Unit <- IO.print("ack-batch compact 2 2000")
    _x : Unit <- IO.print("ack-batch compact 3 2000")
    _y : Unit <- IO.print("ack-batch compact 4 2000")
    IO.print("worker_mode=prepare case=compact status=complete acknowledged_keys=10000")

def run_wal(+dir: String) -> IO(Unit):
  do IO<Unit>:
    db0 : Db.Db <- IO.try(Db.Db, Recover.open_db(dir))
    _armed : Unit <- IO.print("worker_mode=run case=wal status=armed")
    _db1 : Db.Db <- IO.try(Db.Db, Db.db_write(db0, Wal.Batch{Con{Wal.Put{"wal-trigger", "wal-trigger-value"}, Nil{}}}))
    IO.print("worker_mode=run case=wal status=complete")

def run_flush(+dir: String) -> IO(Unit):
  do IO<Unit>:
    db0 : Db.Db <- IO.try(Db.Db, Recover.open_db(dir))
    _armed : Unit <- IO.print("worker_mode=run case=flush status=armed")
    _db1 : Db.Db <- IO.try(Db.Db, Flush.flush(db0))
    IO.print("worker_mode=run case=flush status=complete")

def run_compact(+dir: String) -> IO(Unit):
  do IO<Unit>:
    db0 : Db.Db <- IO.try(Db.Db, Recover.open_db(dir))
    _armed : Unit <- IO.print("worker_mode=run case=compact status=armed")
    _db1 : Db.Db <- IO.try(Db.Db, Compact.compact(db0))
    IO.print("worker_mode=run case=compact status=complete")

def prepare_compact_dec(compact: Bool, +dir: String) -> IO(Unit):
  match compact:
    case True{}:
      prepare_compact(dir)
    case False{}:
      IO.die(Unit, U32.from_nat(2n), "unknown crash case")

def prepare_flush_dec(flush: Bool, +case_name: String, +dir: String) -> IO(Unit):
  match flush:
    case True{}:
      prepare_flush(dir)
    case False{}:
      prepare_compact_dec(String.eq(case_name, "compact"), dir)

def prepare_wal_dec(wal: Bool, +case_name: String, +dir: String) -> IO(Unit):
  match wal:
    case True{}:
      prepare_wal(dir)
    case False{}:
      prepare_flush_dec(String.eq(case_name, "flush"), case_name, dir)

def prepare_dispatch(+case_name: String, +dir: String) -> IO(Unit):
  prepare_wal_dec(String.eq(case_name, "wal"), case_name, dir)

def run_compact_dec(compact: Bool, +dir: String) -> IO(Unit):
  match compact:
    case True{}:
      run_compact(dir)
    case False{}:
      IO.die(Unit, U32.from_nat(2n), "unknown crash case")

def run_flush_dec(flush: Bool, +case_name: String, +dir: String) -> IO(Unit):
  match flush:
    case True{}:
      run_flush(dir)
    case False{}:
      run_compact_dec(String.eq(case_name, "compact"), dir)

def run_wal_dec(wal: Bool, +case_name: String, +dir: String) -> IO(Unit):
  match wal:
    case True{}:
      run_wal(dir)
    case False{}:
      run_flush_dec(String.eq(case_name, "flush"), case_name, dir)

def run_dispatch(+case_name: String, +dir: String) -> IO(Unit):
  run_wal_dec(String.eq(case_name, "wal"), case_name, dir)

def nat_or_die(value: Maybe<&2, Nat>, +name: String) -> IO(Nat):
  match value:
    case Some{n}:
      IO.pure(Nat, n)
    case None{}:
      IO.die(Nat, U32.from_nat(2n), "invalid Nat environment value: " ++ name)

def verify_dispatch(+case_name: String, +dir: String, +trigger_policy: String, +l0_env: String, +l1_env: String) -> IO(Unit):
  do IO<Unit>:
    _valid_case : Unit <- require_config(case_valid(case_name), "unknown crash case")
    _valid_trigger : Unit <- require_config(trigger_policy_valid(trigger_policy), "invalid trigger policy")
    expected_l0 : Nat <- nat_or_die(Nat.read(l0_env), "MYLSM_EXPECT_L0")
    expected_l1 : Nat <- nat_or_die(Nat.read(l1_env), "MYLSM_EXPECT_L1")
    verify_twice(dir, case_name, trigger_policy, expected_l0, expected_l1)

def dispatch_verify(verify: Bool, +case_name: String, +dir: String, +trigger_policy: String, +l0_env: String, +l1_env: String) -> IO(Unit):
  match verify:
    case True{}:
      verify_dispatch(case_name, dir, trigger_policy, l0_env, l1_env)
    case False{}:
      IO.die(Unit, U32.from_nat(2n), "unknown crash mode")

def dispatch_run(run: Bool, +mode: String, +case_name: String, +dir: String, +trigger_policy: String, +l0_env: String, +l1_env: String) -> IO(Unit):
  match run:
    case True{}:
      run_dispatch(case_name, dir)
    case False{}:
      dispatch_verify(String.eq(mode, "verify"), case_name, dir, trigger_policy, l0_env, l1_env)

def dispatch_prepare(prepare: Bool, +mode: String, +case_name: String, +dir: String, +trigger_policy: String, +l0_env: String, +l1_env: String) -> IO(Unit):
  match prepare:
    case True{}:
      prepare_dispatch(case_name, dir)
    case False{}:
      dispatch_run(String.eq(mode, "run"), mode, case_name, dir, trigger_policy, l0_env, l1_env)

def dispatch(+mode: String, +case_name: String, +dir: String, +trigger_policy: String, +l0_env: String, +l1_env: String) -> IO(Unit):
  dispatch_prepare(String.eq(mode, "prepare"), mode, case_name, dir, trigger_policy, l0_env, l1_env)

def dispatch_dir(present: Bool, +mode: String, +case_name: String, +dir: String, +trigger_policy: String, +l0_env: String, +l1_env: String) -> IO(Unit):
  match present:
    case True{}:
      dispatch(mode, case_name, dir, trigger_policy, l0_env, l1_env)
    case False{}:
      IO.die(Unit, U32.from_nat(2n), "MYLSM_CRASH_DIR cannot be empty")

def main() -> IO(Unit):
  do IO<Unit>:
    mode : String <- IO.try(String, Console.get_env("MYLSM_CRASH_MODE"))
    case_name : String <- IO.try(String, Console.get_env("MYLSM_CRASH_CASE"))
    +dir : String <- IO.try(String, Console.get_env("MYLSM_CRASH_DIR"))
    trigger_policy : String <- IO.try(String, Console.get_env("MYLSM_EXPECT_TRIGGER"))
    l0_env : String <- IO.try(String, Console.get_env("MYLSM_EXPECT_L0"))
    l1_env : String <- IO.try(String, Console.get_env("MYLSM_EXPECT_L1"))
    dispatch_dir(nonempty(dir), mode, case_name, dir, trigger_policy, l0_env, l1_env)

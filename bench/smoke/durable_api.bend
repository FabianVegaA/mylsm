import Base
import ../../src/Console.bend as Console
import ../../mylsm.bend as MyLSM

# Runs the close result step of this fixture.
def close_result(result: Result<&1, &1, MyLSM.Error, Unit>) -> IO(Unit):
  match result:
    case Fail{_}:
      IO.die(Unit, U32.from_nat(1n), "database close failed")
    case Done{Unit{}}:
      IO.print("DB_CLOSED")

# Continues the duplicate kind fixture step.
def duplicate_kind(exists: Bool) -> IO(Unit):
  match exists:
    case True{}:
      IO.print("CREATE_ALREADY_EXISTS")
    case False{}:
      IO.die(Unit, U32.from_nat(1n), "duplicate create returned the wrong error")

# Continues the duplicate error fixture step.
def duplicate_error(error: MyLSM.Error) -> IO(Unit):
  duplicate_kind(MyLSM.error_is_already_exists(error))

# Continues the duplicate result fixture step.
def duplicate_result(result: Result<&1, &1, MyLSM.Error, MyLSM.Handle>) -> IO(Unit):
  match result:
    case Fail{error}:
      duplicate_error(error)
    case Done{handle}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, U32.from_nat(1n), "duplicate create succeeded")

# Continues the missing read fixture step.
def missing_read(pair: MyLSM.Handle & Result<&1, &1, MyLSM.Error, Maybe<&2, String>>) -> IO(Unit):
  match pair:
    case (handle, Done{None{}}):
      do IO<Unit>:
        IO.print("DELETE_RECOVERED")
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.print("DB_CLOSED")
    case (handle, _):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, U32.from_nat(1n), "deleted value returned after recovery")

# Runs the deleted open step of this fixture.
def deleted_open(result: Result<&1, &1, MyLSM.Error, MyLSM.Handle>) -> IO(Unit):
  match result:
    case Fail{_}:
      IO.die(Unit, U32.from_nat(1n), "database reopen after delete failed")
    case Done{handle}:
      do IO<Unit>:
        pair : MyLSM.Handle & Result<&1, &1, MyLSM.Error, Maybe<&2, String>> <- MyLSM.get(handle, "key")
        missing_read(pair)

# Runs the deleted result step of this fixture.
def deleted_result(pair: MyLSM.Handle & Result<&1, &1, MyLSM.Error, MyLSM.WriteOutcome>, +path: String) -> IO(Unit):
  match pair:
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, U32.from_nat(1n), "durable delete failed")
    case (handle, Done{MyLSM.WriteOutcome{MyLSM.MaintenanceComplete{}}}):
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        close_result(closed)
        reopened : Result<&1, &1, MyLSM.Error, MyLSM.Handle> <- MyLSM.open_existing(path)
        deleted_open(reopened)


    case (handle, Done{MyLSM.WriteOutcome{MyLSM.MaintenancePending{_}}}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, U32.from_nat(1n), "durable delete maintenance failed")

# Runs the verify read step of this fixture.
def verify_read(pair: MyLSM.Handle & Result<&1, &1, MyLSM.Error, Maybe<&2, String>>, +path: String) -> IO(Unit):
  match pair:
    case (handle, Done{Some{"value"}}):
      do IO<Unit>:
        IO.print("VALUE_RECOVERED")
        deleted : MyLSM.Handle & Result<&1, &1, MyLSM.Error, MyLSM.WriteOutcome> <- MyLSM.delete(handle, "key")
        deleted_result(deleted, path)
    case (handle, _):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, U32.from_nat(1n), "durable value did not recover")

# Runs the stats bytes ok step of this fixture.
def stats_bytes_ok(positive: Bool) -> IO(Unit):
  match positive:
    case True{}: IO.print("STATS_WAL_BYTES_OK")
    case False{}: IO.die(Unit, U32.from_nat(1n), "WAL byte count was zero after a write")

# Runs the stats cache ok step of this fixture.
def stats_cache_ok(bounded: Bool) -> IO(Unit):
  match bounded:
    case True{}: IO.print("STATS_CACHE_BOUND_OK")
    case False{}: IO.die(Unit, U32.from_nat(1n), "read cache exceeded its configured entry bound")

# Runs the stats active bytes ok step of this fixture.
def stats_active_bytes_ok(positive: Bool) -> IO(Unit):
  match positive:
    case True{}: IO.print("STATS_ACTIVE_BYTES_OK")
    case False{}: IO.die(Unit, U32.from_nat(1n), "active database bytes were zero")

# Runs the stats read step of this fixture.
def stats_read(pair: MyLSM.Handle & Result<&1, &1, MyLSM.Error, MyLSM.DurableStats>, +path: String) -> IO(Unit):
  match pair:
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, U32.from_nat(1n), "stats failed")
    case (handle, Done{MyLSM.DurableStats{active_bytes, wal_bytes, _, _, cache_entries, _, _}}):
      do IO<Unit>:
        stats_active_bytes_ok(Nat.is_lt(0n, active_bytes))
        stats_bytes_ok(Nat.is_lt(0n, wal_bytes))
        stats_cache_ok(Nat.is_le(cache_entries, 256n))
        value : MyLSM.Handle & Result<&1, &1, MyLSM.Error, Maybe<&2, String>> <- MyLSM.get(handle, "key")
        verify_read(value, path)

# Continues the reopened result fixture step.
def reopened_result(result: Result<&1, &1, MyLSM.Error, MyLSM.Handle>, +path: String) -> IO(Unit):
  match result:
    case Fail{_}:
      IO.die(Unit, U32.from_nat(1n), "existing database reopen failed")
    case Done{handle}:
      do IO<Unit>:
        IO.print("DB_REOPENED")
        pair : MyLSM.Handle & Result<&1, &1, MyLSM.Error, MyLSM.DurableStats> <- MyLSM.stats(handle)
        stats_read(pair, path)

# Runs the compacted result step of this fixture.
def compacted_result(pair: MyLSM.Handle & Result<&1, &1, MyLSM.Error, Unit>, +path: String) -> IO(Unit):
  match pair:
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, U32.from_nat(1n), "compact failed")
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        close_result(closed)
        reopened : Result<&1, &1, MyLSM.Error, MyLSM.Handle> <- MyLSM.open_existing(path)
        reopened_result(reopened, path)

# Runs the flushed result step of this fixture.
def flushed_result(pair: MyLSM.Handle & Result<&1, &1, MyLSM.Error, Unit>, +path: String) -> IO(Unit):
  match pair:
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, U32.from_nat(1n), "flush failed")
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        compacted : MyLSM.Handle & Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.compact(handle)
        compacted_result(compacted, path)

# Runs the stats payload result step of this fixture.
def stats_payload_result(handle: MyLSM.Handle, matches: Bool, +path: String) -> IO(Unit):
  match matches:
    case True{}:
      do IO<Unit>:
        IO.print("STATS_MEMTABLE_PAYLOAD_BYTES_OK")
        flushed : MyLSM.Handle & Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.flush(handle)
        flushed_result(flushed, path)
    case False{}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, U32.from_nat(1n), "memtable payload byte count differed")

# Runs the stats payload step of this fixture.
def stats_payload(pair: MyLSM.Handle & Result<&1, &1, MyLSM.Error, MyLSM.DurableStats>, +path: String) -> IO(Unit):
  match pair:
    case (handle, Done{MyLSM.DurableStats{_, _, _, payload_bytes, _, _, _}}):
      stats_payload_result(handle, Nat.is_eq(payload_bytes, 14n), path)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, U32.from_nat(1n), "memtable payload stats failed")

# Continues the written result fixture step.
def written_result(pair: MyLSM.Handle & Result<&1, &1, MyLSM.Error, MyLSM.WriteOutcome>, +path: String) -> IO(Unit):
  match pair:
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, U32.from_nat(1n), "durable batch failed")
    case (handle, Done{MyLSM.WriteOutcome{MyLSM.MaintenanceComplete{}}}):
      do IO<Unit>:
        stats : MyLSM.Handle & Result<&1, &1, MyLSM.Error, MyLSM.DurableStats> <- MyLSM.stats(handle)
        stats_payload(stats, path)

    case (handle, Done{MyLSM.WriteOutcome{MyLSM.MaintenancePending{_}}}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, U32.from_nat(1n), "durable write maintenance failed")

# Continues the busy error fixture step.
def busy_error(busy: Bool) -> IO(Unit):
  match busy:
    case True{}: IO.print("PUBLIC_BUSY")
    case False{}: IO.die(Unit, U32.from_nat(1n), "public contender did not return Busy")

# Continues the busy result fixture step.
def busy_result(
  result: Result<&1, &1, MyLSM.Error, MyLSM.Handle>,
  handle: MyLSM.Handle,
  +path: String
) -> IO(Unit):
  match result:
    case Fail{error}:
      do IO<Unit>:
        busy_error(MyLSM.error_is_busy(error))
        written : MyLSM.Handle & Result<&1, &1, MyLSM.Error, MyLSM.WriteOutcome> <- MyLSM.write_batch(handle, Con{MyLSM.SetValue{"key", "old"}, Con{MyLSM.SetValue{"key", "value"}, Nil{}}})
        written_result(written, path)
    case Done{contender}:
      do IO<Unit>:
        _contender_closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(contender)
        _owner_closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, U32.from_nat(1n), "public contender acquired an owned database")

# Continues the owner ready fixture step.
def owner_ready(handle: MyLSM.Handle, +path: String) -> IO(Unit):
  do IO<Unit>:
    contender : Result<&1, &1, MyLSM.Error, MyLSM.Handle> <- MyLSM.open_existing(path)
    busy_result(contender, handle, path)
    duplicate : Result<&1, &1, MyLSM.Error, MyLSM.Handle> <- MyLSM.create(path)
    duplicate_result(duplicate)

# Continues the many mutations fixture step.
def many_mutations(remaining: Nat, +acc: List<&2, MyLSM.Mutation>) -> List<&2, MyLSM.Mutation>:
  match remaining:
    case 0n:
      acc
    case 1n+rest:
      many_mutations(rest, Con{MyLSM.SetValue{"limit", "value"}, acc})

# Doubles the string each step, so total copied text is linear in final size.
def grow_text(remaining: Nat, +text: String) -> String:
  match remaining:
    case 0n:
      text
    case 1n+rest:
      grow_text(rest, text ++ text) # noqa: U004

# Runs the atomic first step of this fixture.
def atomic_first(pair: MyLSM.Handle & Result<&1, &1, MyLSM.Error, Maybe<&2, String>>, path: String) -> IO(Unit):
  match pair:
    case (handle, Done{None{}}):
      do IO<Unit>:
        IO.print("BATCH_NOT_VISIBLE")
        owner_ready(handle, path)
    case (handle, _):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, U32.from_nat(1n), "rejected batch became visible")

# Runs the atomic wal equal step of this fixture.
def atomic_wal_equal(handle: MyLSM.Handle, same_size: Bool, path: String) -> IO(Unit):
  match same_size:
    case True{}:
      do IO<Unit>:
        IO.print("BATCH_WAL_UNCHANGED")
        first : MyLSM.Handle & Result<&1, &1, MyLSM.Error, Maybe<&2, String>> <- MyLSM.get(handle, "atomic-first")
        atomic_first(first, path)
    case False{}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, U32.from_nat(1n), "rejected batch changed WAL bytes")

# Runs the atomic verify result step of this fixture.
def atomic_verify_result(handle: MyLSM.Handle, count_matches: Bool, wal_matches: Bool, +path: String) -> IO(Unit):
  match count_matches:
    case True{}:
      atomic_wal_equal(handle, wal_matches, path)
    case False{}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, U32.from_nat(1n), "operation error count differed after three rejected writes")

# Runs the atomic verify step of this fixture.
def atomic_verify(
  pair: MyLSM.Handle & Result<&1, &1, MyLSM.Error, MyLSM.DurableStats>,
  before: Nat,
  path: String
) -> IO(Unit):
  match pair:
    case (handle, Done{MyLSM.DurableStats{_, after, _, _, _, operation_errors, _}}):
      atomic_verify_result(handle, Nat.is_eq(operation_errors, 3n), Nat.is_eq(before, after), path)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, U32.from_nat(1n), "atomic batch post-write stats failed")

# Runs the atomic finish step of this fixture.
def atomic_finish(
  pair: MyLSM.Handle & Result<&1, &1, MyLSM.Error, MyLSM.WriteOutcome>,
  before: Nat,
  path: String
) -> IO(Unit):
  match pair:
    case (handle, Fail{MyLSM.Error{MyLSM.ResourceLimitError{}, _, _, _, _}}):
      do IO<Unit>:
        IO.print("BATCH_FRAME_LIMIT")
        after : MyLSM.Handle & Result<&1, &1, MyLSM.Error, MyLSM.DurableStats> <- MyLSM.stats(handle)
        atomic_verify(after, before, path)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, U32.from_nat(1n), "oversized batch returned the wrong error")
    case (handle, Done{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, U32.from_nat(1n), "oversized batch unexpectedly committed")

# Runs the atomic write step of this fixture.
def atomic_write(handle: MyLSM.Handle, before: Nat, path: String) -> IO(Unit):
  do IO<Unit>:
    attempted : MyLSM.Handle & Result<&1, &1, MyLSM.Error, MyLSM.WriteOutcome> <- MyLSM.write_batch(handle,
      Con{MyLSM.SetValue{"atomic-first", "must-not-commit"},
      Con{MyLSM.SetValue{"atomic-final", grow_text(20n, "x")}, Nil{}}})
    atomic_finish(attempted, before, path)

# Runs the atomic attempt step of this fixture.
def atomic_attempt(pair: MyLSM.Handle & Result<&1, &1, MyLSM.Error, MyLSM.DurableStats>, path: String) -> IO(Unit):
  match pair:
    case (handle, Done{MyLSM.DurableStats{_, before, _, _, _, _, _}}):
      atomic_write(handle, before, path)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, U32.from_nat(1n), "atomic batch pre-write stats failed")

def atomic_batch.begin(handle: MyLSM.Handle, path: String) -> IO(Unit):
  do IO<Unit>:
    stats : MyLSM.Handle & Result<&1, &1, MyLSM.Error, MyLSM.DurableStats> <- MyLSM.stats(handle)
    atomic_attempt(stats, path)

# Continues the too many batch result fixture step.
def too_many_batch_result(
  pair: MyLSM.Handle & Result<&1, &1, MyLSM.Error, MyLSM.WriteOutcome>,
  +path: String
) -> IO(Unit):
  match pair:
    case (handle, Fail{MyLSM.Error{MyLSM.ResourceLimitError{}, _, _, _, _}}):
      do IO<Unit>:
        IO.print("BATCH_COUNT_LIMIT")
        atomic_batch.begin(handle, path)
    case (handle, _):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, U32.from_nat(1n), "oversized mutation count was not rejected")

# Continues the empty batch result fixture step.
def empty_batch_result(pair: MyLSM.Handle & Result<&1, &1, MyLSM.Error, MyLSM.WriteOutcome>, +path: String) -> IO(Unit):
  match pair:
    case (handle, Fail{MyLSM.Error{MyLSM.InvalidArgumentError{}, _, _, _, _}}):
      do IO<Unit>:
        IO.print("EMPTY_BATCH_REJECTED")
        too_many : MyLSM.Handle & Result<&1, &1, MyLSM.Error, MyLSM.WriteOutcome> <- MyLSM.write_batch(handle, many_mutations(257n, Nil{}))
        too_many_batch_result(too_many, path)
    case (handle, _):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, U32.from_nat(1n), "empty durable batch was not rejected")

# Runs the created result step of this fixture.
def created_result(result: Result<&1, &1, MyLSM.Error, MyLSM.Handle>, +path: String) -> IO(Unit):
  match result:
    case Fail{_}:
      IO.die(Unit, U32.from_nat(1n), "database create failed")
    case Done{handle}:
      do IO<Unit>:
        empty : MyLSM.Handle & Result<&1, &1, MyLSM.Error, MyLSM.WriteOutcome> <- MyLSM.write_batch(handle, Nil{})
        empty_batch_result(empty, path)

# Runs the run path step of this fixture.
def run_path(+path: String) -> IO(Unit):
  do IO<Unit>:
    created : Result<&1, &1, MyLSM.Error, MyLSM.Handle> <- MyLSM.create(path)
    created_result(created, path)

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    run_path(path)

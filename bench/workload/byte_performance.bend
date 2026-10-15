import Base
import ../../mylsm.bend as MyLSM
import ../../src/ByteMemTable.bend as ByteMemTable
import ../../src/ByteSstFile.bend as ByteSstFile
import ../../src/ByteSstIo.bend as ByteSstIo
import ../../src/Console.bend as Console
import ../../src/DurableBatchPolicy.bend as BatchPolicy
import ../lib/common.bend as Common
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Tracks the measured delta scan until it ends or fails.
type ScanDeltaState is Type:
  ScanDeltaActive{count: Nat, payload_bytes: Nat, cursor: MyLSM.Bytes.Cursor}
  ScanDeltaEnded{count: Nat, payload_bytes: Nat, cursor: MyLSM.Bytes.Cursor}
  ScanDeltaFailed{cursor: MyLSM.Bytes.Cursor}

# Encodes an index as an eight-byte ordered key.
def make_key(index: Nat) -> Bytes.Bytes:
  Bytes.set.u32be(Bytes.new(8), 4, U32.from_nat(index))

# Builds a fixed-size value carrying its index in the first four bytes.
def make_value(index: Nat, size: Nat) -> Bytes.Bytes:
  Bytes.set.u32be(Bytes.new(U32.from_nat(size)), 0, U32.from_nat(index))

# Builds a deterministic table before the measured operation starts.
def prepare_delta(
  fuel: Nat,
  +index: Nat,
  +value_bytes: Nat,
  table: ByteMemTable.Table
) -> ByteMemTable.Table:
  match fuel:
    case 0n: table
    case 1n+rest:
      prepare_delta(rest, Nat.add(index, 1n), value_bytes,
        ByteMemTable.put(table, make_key(index), make_value(index, value_bytes)))

def prepare.overwrite(
  fuel: Nat,
  +index: Nat,
  +value_bytes: Nat,
  table: ByteMemTable.Table
) -> ByteMemTable.Table:
  match fuel:
    case 0n: table
    case 1n+rest:
      prepare.overwrite(rest, Nat.add(index, 1n), value_bytes,
        ByteMemTable.put(table, make_key(0n), make_value(index, value_bytes)))

def u32.read(pair: Bytes.Bytes & Maybe<&2, U32>) -> U32:
  match pair:
    case (_, Some{value}): value
    case (_, None{}): 0

def scan_delta.bytes.length(pair: Bytes.Bytes & U32) -> Nat:
  match pair:
    case (_, length): U32.to_nat(length)

def scan_delta.bytes.size(bytes: Bytes.Bytes) -> Nat:
  scan_delta.bytes.length(Bytes.length(bytes))

def validate_order.measure(pair: Bytes.Bytes & Maybe<&2, U32>) -> Nat & Nat:
  match pair:
    case (bytes, Some{value}): (U32.to_nat(value), scan_delta.bytes.size(bytes))
    case (bytes, None{}): (0n, scan_delta.bytes.size(bytes))

def validate_order.item.measured(
  key_data: Nat & Nat,
  value_data: Nat & Nat,
  +expected: Nat,
  +value_size: Nat
) -> Bool & Nat:
  match key_data:
    case (+key_index, key_bytes):
      match value_data:
        case (+value_index, value_bytes):
          (Bool.and(Nat.is_eq(key_index, expected),
              Bool.and(Nat.is_eq(value_index, expected),
              Bool.and(Nat.is_eq(key_bytes, 8n),
                Nat.is_eq(value_bytes, value_size)))), key_index)

def validate_order.item(
  key: Bytes.Bytes,
  value: Bytes.Bytes,
  +expected: Nat,
  +value_size: Nat
) -> Bool & Nat:
  validate_order.item.measured(
    validate_order.measure(Bytes.get.u32be(key, 4)),
    validate_order.measure(Bytes.get.u32be(value, 0)), expected, value_size)

def validate_order.step(valid: Bool, measured: Bool & Nat) -> Bool & Nat:
  match measured:
    case (tail_valid, +checksum): (Bool.and(valid, tail_valid), checksum)

def validate_order.combine(
  item: Bool & Nat,
  tail: Bool & Nat
) -> Bool & Nat:
  match item:
    case (valid, +key_index):
      match tail:
        case (tail_valid, +checksum):
          (Bool.and(valid, tail_valid), Nat.add(checksum, key_index))

def validate_order.go(
  fuel: Nat,
  +expected: Nat,
  +total: Nat,
  +value_bytes: Nat,
  +checksum: Nat,
  entries: List<&1, ByteMemTable.Entry>
) -> Bool & Nat:
  match fuel:
    case 0n: (Nat.is_eq(expected, total), checksum)
    case 1n+rest:
      match entries:
        case Nil{}: (Nat.is_eq(expected, total), checksum)
        case Con{ByteMemTable.Entry{key, Some{value}}, tail}:
          validate_order.combine(
            validate_order.item(key, value, expected, value_bytes),
            validate_order.go(rest, Nat.add(expected, 1n), total,
              value_bytes, checksum, tail))
        case Con{ByteMemTable.Entry{_, None{}}, _}: (False{}, checksum)

def validate.order(
  entries: List<&1, ByteMemTable.Entry>,
  +total: Nat,
  value_bytes: Nat
) -> Bool & Nat:
  validate_order.go(Nat.add(total, 1n), 0n, total, value_bytes, 0n, entries)

def validate.overwrite(entries: List<&1, ByteMemTable.Entry>, count: Nat) -> Bool & Nat:
  match entries:
    case [ByteMemTable.Entry{key, Some{value}}]:
      +last_index = Nat.sub(count, 1n)
      +checksum = U32.to_nat(u32.read(Bytes.get.u32be(value, 0)))
      (Bool.and(Nat.is_eq(U32.to_nat(u32.read(Bytes.get.u32be(key, 4))), 0n),
        Nat.is_eq(checksum, last_index)), checksum)
    case _ : (False{}, 0n)

# Prints one machine-readable benchmark result when its fixture is valid.
def result(
  valid: Bool,
  scenario: String,
  count: Nat,
  +value_bytes: Nat,
  phase: String,
  +checksum: Nat,
  elapsed: Nat
) -> IO(Unit):
  match valid:
    case True{}:
      IO.print("scenario=" ++ scenario ++ ",count=" ++ Nat.show(count) ++
        ",value_bytes=" ++ Nat.show(value_bytes) ++ ",phase=" ++ phase ++
        ",elapsed_ms=" ++ Nat.show(elapsed) ++
        ",checksum=" ++ Nat.show(checksum) ++ ",result=pass")
    case False{}:
      IO.die(Unit, 1, "byte performance order fixture failed")

def scan_open.checked(
  +total: Nat,
  elapsed: Nat,
  cursor_result: Result<&1, &1, MyLSM.Bytes.Error, Unit>,
  handle_result: Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match cursor_result handle_result:
    case Done{Unit{}} Done{Unit{}}:
      result(True{}, "scan_open", total, 32n, "scan_open", total, elapsed)
    case _ _:
      IO.die(Unit, 1, "byte performance scan open cleanup failed")

def scan_open.closed(
  +total: Nat,
  elapsed: Nat,
  handle: MyLSM.Bytes.Handle,
  cursor_result: Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  do IO<Unit>:
    handle_result : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
    scan_open.checked(total, elapsed, cursor_result, handle_result)

def scan_open.received(
  +total: Nat,
  start: Nat,
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Cursor>
) -> IO(Unit):
  match pair:
    case (handle, Done{cursor}):
      do IO<Unit>:
        stop : Nat <- IO.now()
        cursor_result : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.scan_close(cursor)
        scan_open.closed(total, Nat.sub(stop, start), handle, cursor_result)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "byte performance scan open failed")

def scan_open.started(total: Nat, handle: MyLSM.Bytes.Handle) -> IO(Unit):
  do IO<Unit>:
    start : Nat <- IO.now()
    pair : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Cursor> <-
      MyLSM.Bytes.scan(handle, MyLSM.ScanBounds{None{}, None{}, None{}})
    scan_open.received(total, start, pair)

def scan_delta.transition(
  count: Nat,
  payload_bytes: Nat,
  step: MyLSM.Bytes.StreamStep
) -> ScanDeltaState:
  match step:
    case MyLSM.StreamItem{key, value, cursor}:
      ScanDeltaActive{Nat.add(count, 1n),
        Nat.add(payload_bytes,
          Nat.add(scan_delta.bytes.size(key), scan_delta.bytes.size(value))), cursor}
    case MyLSM.StreamSkip{cursor}: ScanDeltaActive{count, payload_bytes, cursor}
    case MyLSM.StreamEnd{cursor}: ScanDeltaEnded{count, payload_bytes, cursor}
    case MyLSM.StreamFailure{_, cursor}: ScanDeltaFailed{cursor}

def scan_delta.finish(
  +total: Nat,
  +value_bytes: Nat,
  count: Nat,
  +payload_bytes: Nat,
  elapsed: Nat,
  cursor_result: Result<&1, &1, MyLSM.Bytes.Error, Unit>,
  handle_result: Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match cursor_result handle_result:
    case Done{Unit{}} Done{Unit{}}:
      result(Bool.and(Nat.is_eq(count, total),
        Nat.is_eq(payload_bytes, Nat.mul(total, Nat.add(8n, value_bytes)))),
        "scan_delta", total, value_bytes, "scan_next", payload_bytes, elapsed)
    case _ _:
      IO.die(Unit, 1, "byte performance scan delta cleanup failed")

def scan_delta.loop(
  fuel: Nat,
  +total: Nat,
  +value_bytes: Nat,
  start: Nat,
  handle: MyLSM.Bytes.Handle,
  state: ScanDeltaState
) -> IO(Unit):
  match fuel state:
    case _ ScanDeltaEnded{count, payload_bytes, cursor}:
      do IO<Unit>:
        stop : Nat <- IO.now()
        cursor_result : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.scan_close(cursor)
        handle_result : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        scan_delta.finish(total, value_bytes, count, payload_bytes,
          Nat.sub(stop, start), cursor_result, handle_result)
    case _ ScanDeltaFailed{cursor}:
      do IO<Unit>:
        _cursor : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.scan_close(cursor)
        _handle : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "byte performance scan delta failed")
    case 0n ScanDeltaActive{_, _, cursor}:
      do IO<Unit>:
        _cursor : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.scan_close(cursor)
        _handle : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "byte performance scan delta exceeded its count")
    case 1n+rest ScanDeltaActive{count, payload_bytes, cursor}:
      do IO<Unit>:
        step : MyLSM.Bytes.StreamStep <- MyLSM.Bytes.scan_next(cursor)
        next_state : ScanDeltaState <- IO.pure(ScanDeltaState,
          scan_delta.transition(count, payload_bytes, step))
        scan_delta.loop(rest, total, value_bytes, start, handle, next_state)

def scan_delta.opened(
  +total: Nat,
  +value_bytes: Nat,
  handle: MyLSM.Bytes.Handle,
  result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Cursor>
) -> IO(Unit):
  match result:
    case Done{cursor}:
      do IO<Unit>:
        start : Nat <- IO.now()
        state : ScanDeltaState <- IO.pure(ScanDeltaState, ScanDeltaActive{0n, 0n, cursor})
        scan_delta.loop(Nat.add(total, 1n), total, value_bytes, start, handle, state)
    case Fail{_}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "byte performance scan delta open failed")

def scan_delta.started.result(
  +total: Nat,
  +value_bytes: Nat,
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Cursor>
) -> IO(Unit):
  match pair:
    case (handle, result): scan_delta.opened(total, value_bytes, handle, result)

def scan_delta.started(
  +total: Nat,
  +value_bytes: Nat,
  handle: MyLSM.Bytes.Handle
) -> IO(Unit):
  do IO<Unit>:
    pair : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Cursor> <-
      MyLSM.Bytes.scan(handle, MyLSM.ScanBounds{None{}, None{}, None{}})
    scan_delta.started.result(total, value_bytes, pair)

def scan_open.mutations(
  fuel: Nat,
  +index: Nat,
  +value_bytes: Nat
) -> List<&1, MyLSM.Bytes.Mutation>:
  match fuel:
    case 0n: Nil{}
    case 1n+rest:
      Con{MyLSM.BytesPut{make_key(index), make_value(index, value_bytes)},
        scan_open.mutations(rest, Nat.add(index, 1n), value_bytes)}

def scan_open.writes.result(
  result: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(MyLSM.Bytes.Handle):
  match result:
    case (handle, Done{Unit{}}): IO.pure(MyLSM.Bytes.Handle, handle)
    case (handle, Fail{_}):
      do IO<MyLSM.Bytes.Handle>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(MyLSM.Bytes.Handle, 1, "byte performance setup batch failed")

def scan_open.start.scenario(
  scenario: String,
  +total: Nat,
  +value_bytes: Nat,
  handle: MyLSM.Bytes.Handle
) -> IO(Unit):
  match scenario:
    case "scan_open": scan_open.started(total, handle)
    case "scan_delta": scan_delta.started(total, value_bytes, handle)
    case _:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "unsupported byte performance scenario")

def scan_open.batch.size(value_bytes: Nat) -> Nat:
  Nat.min(BatchPolicy.max_batch_count(),
    Nat.div(BatchPolicy.max_batch_bytes(), Nat.add(value_bytes, 64n)))

def maintenance.stats.finished(
  +scenario: String,
  +delta_count: Nat,
  elapsed: Nat,
  handle: MyLSM.Bytes.Handle,
  +entries: Nat,
  payload_bytes: Nat
) -> IO(Unit):
  +expected = Nat.add(16000n, delta_count)
  +expected_payload = Nat.mul(expected, 40n)
  do IO<Unit>:
    _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
    result(Bool.and(Nat.is_eq(entries, expected),
      Nat.is_eq(payload_bytes, expected_payload)), scenario, delta_count,
      32n, scenario, entries, elapsed)

def maintenance.prepared.closed(
  +delta_count: Nat,
  closed: Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match closed:
    case Done{Unit{}}:
      result(True{}, "maintenance_prepare", delta_count, 32n, "prepare",
        Nat.add(16000n, delta_count), 0n)
    case Fail{_}: IO.die(Unit, 1, "byte maintenance fixture close failed")

def maintenance.prepared(
  +delta_count: Nat,
  handle: MyLSM.Bytes.Handle
) -> IO(Unit):
  do IO<Unit>:
    closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
    maintenance.prepared.closed(delta_count, closed)

def maintenance.stats.checked(
  +scenario: String,
  +delta_count: Nat,
  elapsed: Nat,
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Stats>
) -> IO(Unit):
  match pair:
    case (handle, Done{MyLSM.ByteStats{entries, payload_bytes, _, _, _}}):
      maintenance.stats.finished(scenario, delta_count, elapsed, handle,
        entries, payload_bytes)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "byte maintenance stats verification failed")

def maintenance.reopened(
  +scenario: String,
  +delta_count: Nat,
  elapsed: Nat,
  result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>
) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        stats : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Stats> <-
          MyLSM.Bytes.stats(handle)
        maintenance.stats.checked(scenario, delta_count, elapsed, stats)
    case Fail{_}: IO.die(Unit, 1, "byte maintenance reopen failed")

def maintenance.published(
  scenario: String,
  +delta_count: Nat,
  +path: String,
  elapsed: Nat,
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        opened : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
          MyLSM.Bytes.open_existing(path)
        maintenance.reopened(scenario, delta_count, elapsed, opened)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "byte maintenance publication failed")

def maintenance.flush(
  +delta_count: Nat,
  +path: String,
  handle: MyLSM.Bytes.Handle
) -> IO(Unit):
  do IO<Unit>:
    start : Nat <- IO.now()
    flushed : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
      MyLSM.Bytes.flush(handle)
    stop : Nat <- IO.now()
    maintenance.published("flush", delta_count, path, Nat.sub(stop, start), flushed)

def maintenance.compact(
  +delta_count: Nat,
  +path: String,
  handle: MyLSM.Bytes.Handle
) -> IO(Unit):
  do IO<Unit>:
    start : Nat <- IO.now()
    compacted : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
      MyLSM.Bytes.compact(handle)
    stop : Nat <- IO.now()
    maintenance.published("compact", delta_count, path, Nat.sub(stop, start), compacted)

def maintenance.start(
  scenario: String,
  +delta_count: Nat,
  +path: String,
  handle: MyLSM.Bytes.Handle
) -> IO(Unit):
  match scenario:
    case "flush": maintenance.flush(delta_count, path, handle)
    case "compact": maintenance.compact(delta_count, path, handle)
    case "prepare": maintenance.prepared(delta_count, handle)
    case _:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "unsupported byte maintenance operation")

def maintenance.opened(
  scenario: String,
  +delta_count: Nat,
  +path: String,
  opened: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>
) -> IO(Unit):
  match opened:
    case Done{handle}: maintenance.start(scenario, delta_count, path, handle)
    case Fail{_}: IO.die(Unit, 1, "byte maintenance fixture open failed")

def maintenance.delta.batches(
  fuel: Nat,
  scenario: String,
  +delta_count: Nat,
  +path: String,
  +remaining: Nat,
  +index: Nat,
  handle: MyLSM.Bytes.Handle
) -> IO(Unit):
  match fuel:
    case 0n: IO.die(Unit, 1, "byte delta setup exceeded its batch budget")
    case 1n+rest:
      match remaining:
        case 0n: maintenance.start(scenario, delta_count, path, handle)
        case _:
          +batch_count = Nat.min(remaining, scan_open.batch.size(32n))
          do IO<Unit>:
            written : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
              MyLSM.Bytes.write_batch(handle,
                scan_open.mutations(batch_count, index, 32n))
            next_handle : MyLSM.Bytes.Handle <- scan_open.writes.result(written)
            maintenance.delta.batches(rest, scenario, delta_count, path,
              Nat.sub(remaining, batch_count), Nat.add(index, batch_count), next_handle)

def maintenance.base.flushed(
  scenario: String,
  +delta_count: Nat,
  +path: String,
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      +batch_size = scan_open.batch.size(32n)
      maintenance.delta.batches(Nat.add(Nat.div(Nat.add(delta_count,
        Nat.sub(batch_size, 1n)), batch_size), 1n), scenario,
        delta_count, path, delta_count, 16000n, handle)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "byte maintenance base flush failed")

def maintenance.base.ready(
  scenario: String,
  +delta_count: Nat,
  +path: String,
  handle: MyLSM.Bytes.Handle
) -> IO(Unit):
  do IO<Unit>:
    flushed : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
      MyLSM.Bytes.flush(handle)
    maintenance.base.flushed(scenario, delta_count, path, flushed)

def maintenance.base.batches(
  fuel: Nat,
  scenario: String,
  +delta_count: Nat,
  +path: String,
  +remaining: Nat,
  +index: Nat,
  handle: MyLSM.Bytes.Handle
) -> IO(Unit):
  match fuel:
    case 0n: IO.die(Unit, 1, "byte base setup exceeded its batch budget")
    case 1n+rest:
      match remaining:
        case 0n: maintenance.base.ready(scenario, delta_count, path, handle)
        case _:
          +batch_count = Nat.min(remaining, scan_open.batch.size(32n))
          do IO<Unit>:
            written : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
              MyLSM.Bytes.write_batch(handle,
                scan_open.mutations(batch_count, index, 32n))
            next_handle : MyLSM.Bytes.Handle <- scan_open.writes.result(written)
            maintenance.base.batches(rest, scenario, delta_count, path,
              Nat.sub(remaining, batch_count), Nat.add(index, batch_count), next_handle)

def maintenance.created(
  scenario: String,
  +delta_count: Nat,
  +path: String,
  created: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>
) -> IO(Unit):
  match created:
    case Done{handle}:
      +batch_size = scan_open.batch.size(32n)
      maintenance.base.batches(Nat.add(Nat.div(Nat.add(16000n,
        Nat.sub(batch_size, 1n)), batch_size), 1n), scenario,
        delta_count, path, 16000n, 0n, handle)
    case Fail{_}: IO.die(Unit, 1, "byte maintenance database create failed")

def run.maintenance(
  scenario: String,
  +delta_count: Nat,
  +path: String
) -> IO(Unit):
  match scenario:
    case "prepare":
      do IO<Unit>:
        created : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
          MyLSM.Bytes.create(path)
        maintenance.created("prepare", delta_count, path, created)
    case "flush":
      do IO<Unit>:
        opened : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
          MyLSM.Bytes.open_existing(path)
        maintenance.opened(scenario, delta_count, path, opened)
    case "compact":
      do IO<Unit>:
        opened : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
          MyLSM.Bytes.open_existing(path)
        maintenance.opened(scenario, delta_count, path, opened)
    case _: IO.die(Unit, 1, "unsupported byte maintenance setup")

def maintenance.phases.encoded(
  encoded: Result<&1, &1, ByteSstFile.Error, Bytes.Bytes>
) -> Bool & Nat:
  match encoded:
    case Done{bytes}: (True{}, scan_delta.bytes.size(bytes))
    case Fail{_}: (False{}, 0n)

def maintenance.phases.encoded.finished(
  +count: Nat,
  elapsed: Nat,
  measured: Bool & Nat
) -> IO(Unit):
  match measured:
    case (valid, +bytes):
      result(Bool.and(valid, Nat.is_lt(0n, bytes)), "maintenance_phases",
        count, 32n, "encode_file", bytes, elapsed)

def maintenance.phases.encode(
  +count: Nat,
  entries: List<&1, ByteMemTable.Entry>
) -> IO(Unit):
  do IO<Unit>:
    start : Nat <- IO.now()
    encoded : Result<&1, &1, ByteSstFile.Error, Bytes.Bytes> <-
      IO.pure(Result<&1, &1, ByteSstFile.Error, Bytes.Bytes>,
        ByteSstFile.encode_file(entries, U32.from_nat(0n)))
    measured : Bool & Nat <- IO.pure(Bool & Nat,
      maintenance.phases.encoded(encoded))
    stop : Nat <- IO.now()
    maintenance.phases.encoded.finished(count, Nat.sub(stop, start), measured)

def maintenance.phases.order(+count: Nat) -> IO(Unit):
  do IO<Unit>:
    table : ByteMemTable.Table =
      prepare_delta(count, 0n, 32n, ByteMemTable.empty())
    start : Nat <- IO.now()
    entries : List<&1, ByteMemTable.Entry> <- IO.pure(
      List<&1, ByteMemTable.Entry>, ByteMemTable.ordered_entries(table))
    +measured_count : Nat <- IO.pure(Nat,
      List.length(&1, ByteMemTable.Entry, entries))
    stop : Nat <- IO.now()
    result(Nat.is_eq(measured_count, count),
      "maintenance_phases", count, 32n, "ordered_entries",
      measured_count, Nat.sub(stop, start))

def maintenance.phases.read.count(
  read_result: Result<&1, &1, U32 & String, ByteMemTable.Table>
) -> Nat:
  match read_result:
    case Done{table}: ByteMemTable.count(table)
    case Fail{_}: 0n

def maintenance.phases.read(
  +count: Nat,
  +path: String
) -> IO(Unit):
  do IO<Unit>:
    start : Nat <- IO.now()
    read_result : Result<&1, &1, U32 & String, ByteMemTable.Table> <-
      ByteSstIo.read(path ++ "/SST.00000001")
    +measured_count : Nat <- IO.pure(Nat,
      maintenance.phases.read.count(read_result))
    stop : Nat <- IO.now()
    result(Nat.is_eq(measured_count, 16000n),
      "maintenance_phases", count, 32n, "sst_read", measured_count,
      Nat.sub(stop, start))


def scan_open.write_batches(
  fuel: Nat,
  +scenario: String,
  +total: Nat,
  +value_bytes: Nat,
  +remaining: Nat,
  +index: Nat,
  handle: MyLSM.Bytes.Handle
) -> IO(Unit):
  match fuel:
    case 0n: IO.die(Unit, 1, "byte performance setup batch budget exhausted")
    case 1n+rest_fuel:
      match remaining:
        case 0n: scan_open.start.scenario(scenario, total, value_bytes, handle)
        case _:
          +batch_count = Nat.min(remaining, scan_open.batch.size(value_bytes))
          do IO<Unit>:
            outcome : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
              MyLSM.Bytes.write_batch(handle,
                scan_open.mutations(batch_count, index, value_bytes))
            next_handle : MyLSM.Bytes.Handle <- scan_open.writes.result(outcome)
            scan_open.write_batches(rest_fuel, scenario, total, value_bytes,
              Nat.sub(remaining, batch_count), Nat.add(index, batch_count), next_handle)

def scan_open.opened(
  scenario: String,
  +total: Nat,
  +value_bytes: Nat,
  result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>
) -> IO(Unit):
  match result:
    case Done{handle}:
      +batch_size = scan_open.batch.size(value_bytes)
      scan_open.write_batches(Nat.add(Nat.div(Nat.add(total,
        Nat.sub(batch_size, 1n)), batch_size), 1n),
        scenario, total, value_bytes, total, 0n, handle)
    case Fail{_}: IO.die(Unit, 1, "byte performance database create failed")

# Measures public cursor construction over a fresh delta-only database.
def run_scan_open(total: Nat, value_bytes: Nat, path: String) -> IO(Unit):
  do IO<Unit>:
    created : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <- MyLSM.Bytes.create(path)
    scan_open.opened("scan_open", total, value_bytes, created)

# Measures full public iteration over a fresh delta-only database.
def run_scan_delta(total: Nat, value_bytes: Nat, path: String) -> IO(Unit):
  do IO<Unit>:
    created : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <- MyLSM.Bytes.create(path)
    scan_open.opened("scan_delta", total, value_bytes, created)

# Reports ordered materialization only after order and count validation.
def finish_order(
  scenario: String,
  +count: Nat,
  +value_bytes: Nat,
  elapsed: Nat,
  measured: Bool & Nat
) -> IO(Unit):
  match measured:
    case (ordered, +actual):
      result(ordered, scenario, count,
        value_bytes, "ordered_entries", actual, elapsed)

def run_order.ready(
  +count: Nat,
  +value_bytes: Nat,
  delta: ByteMemTable.Table
) -> IO(Unit):
  do IO<Unit>:
    start : Nat <- IO.now()
    entries : List<&1, ByteMemTable.Entry> <- IO.pure(List<&1, ByteMemTable.Entry>,
      ByteMemTable.ordered_entries(delta))
    measured : Bool & Nat <- IO.pure(Bool & Nat,
      validate.order(entries, count, value_bytes))
    stop : Nat <- IO.now()
    finish_order("order_unique", count, value_bytes,
      Nat.sub(stop, start), measured)

# Prepares unique mutations, then measures their ordered materialization.
def run_order(+count: Nat, +value_bytes: Nat) -> IO(Unit):
  run_order.ready(count, value_bytes,
    prepare_delta(count, 0n, value_bytes, ByteMemTable.empty()))

def run_order.overwrite.ready(
  +count: Nat,
  +value_bytes: Nat,
  delta: ByteMemTable.Table
) -> IO(Unit):
  do IO<Unit>:
    start : Nat <- IO.now()
    entries : List<&1, ByteMemTable.Entry> <- IO.pure(List<&1, ByteMemTable.Entry>,
      ByteMemTable.ordered_entries(delta))
    measured : Bool & Nat <- IO.pure(Bool & Nat, validate.overwrite(entries, count))
    stop : Nat <- IO.now()
    finish_order("order_overwrite", count, value_bytes,
      Nat.sub(stop, start), measured)

def run_order.overwrite(+count: Nat, +value_bytes: Nat) -> IO(Unit):
  run_order.overwrite.ready(count, value_bytes,
    prepare.overwrite(count, 0n, value_bytes, ByteMemTable.empty()))

def dispatch.phases(
  scenario: String,
  +count: Nat,
  +path: String
) -> IO(Unit):
  match scenario:
    case "phase_read": maintenance.phases.read(count, path)
    case "phase_order": maintenance.phases.order(count)
    case "phase_encode":
      maintenance.phases.encode(count,
        ByteMemTable.ordered_entries(prepare_delta(count, 0n, 32n,
          ByteMemTable.empty())))
    case _: IO.die(Unit, 1, "unsupported byte phase scenario")

def dispatch.maintenance(
  scenario: String,
  +count: Nat,
  +path: String
) -> IO(Unit):
  match scenario:
    case "maintenance_prepare": run.maintenance("prepare", count, path)
    case "flush": run.maintenance("flush", count, path)
    case "compact": run.maintenance("compact", count, path)
    case _: dispatch.phases(scenario, count, path)

def dispatch.scan(
  scenario: String,
  +count: Nat,
  +value_bytes: Nat,
  +path: String
) -> IO(Unit):
  match scenario:
    case "scan_open": run_scan_open(count, value_bytes, path)
    case "scan_delta": run_scan_delta(count, value_bytes, path)
    case _: dispatch.maintenance(scenario, count, path)

# Selects the benchmark scenario requested through the environment.
def dispatch(scenario: String, +count: Nat, value_bytes: Nat, path: String) -> IO(Unit):
  match scenario:
    case "order_unique": run_order(count, value_bytes)
    case "order_overwrite": run_order.overwrite(count, value_bytes)
    case _: dispatch.scan(scenario, count, value_bytes, path)

def main() -> IO(Unit):
  do IO<Unit>:
    scenario : String <- IO.try(String, Console.get_env("MYLSM_BYTE_BENCH_SCENARIO"))
    count_text : String <- IO.try(String, Console.get_env("MYLSM_BYTE_BENCH_COUNT"))
    value_bytes_text : String <- IO.try(String, Console.get_env("MYLSM_BYTE_BENCH_VALUE_BYTES"))
    path : String <- IO.try(String, Console.get_env("MYLSM_BYTE_BENCH_DIR"))
    count : Nat = Common.nat_default(Nat.read(count_text), 1024n)
    value_bytes : Nat = Common.nat_default(Nat.read(value_bytes_text), 32n)
    dispatch(scenario, count, value_bytes, path)

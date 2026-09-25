import Base
import ../src/Db.bend as Db
import ../src/Recover.bend as Recover
import ../src/Flush.bend as Flush
import ../src/Compact.bend as Compact
import ../src/MergeIter.bend as MergeIter
import ../src/MemTable.bend as MemTable
import ../src/Sstable.bend as Sstable
import ../src/SortedRun.bend as SortedRun
import ../src/Wal.bend as Wal
import ../src/Fs.bend as Fs
import ../src/Console.bend as Console
import ./demo_helpers.bend as Demo
import ./interchange.bend as Interchange
import ./repl_types.bend as Repl
import ./repl_parser.bend as Parser

type Session is Data:
  Session{db: Db.Db, dir: String, timing: Repl.TimingMode, mode: Repl.ComputeMode, gpu: Bool, workers: Nat, staged: List<&2, Wal.Batch>}

type LoopState is Data:
  Running{session: Session}
  Stopped{}

def timing_should(mode: Repl.TimingMode) -> Bool:
  match mode:
    case Repl.TimingOff{}: False{}
    case Repl.TimingOn{}: True{}
    case Repl.TimingOnce{}: True{}

def timing_once(mode: Repl.TimingMode) -> Bool:
  match mode:
    case Repl.TimingOnce{}: True{}
    case _: False{}

def mode_name(mode: Repl.ComputeMode) -> String:
  match mode:
    case Repl.Cpu{}: "cpu"
    case Repl.Gpu{}: "gpu"
    case Repl.Auto{}: "auto"

def bool_name(value: Bool) -> String:
  match value:
    case True{}: "yes"
    case False{}: "no"

def entry_line(entry: MemTable.Entry) -> String:
  match entry:
    case MemTable.Entry{key, val}:
      key ++ "=" ++ Demo.show_maybe(val)

def print_entries(es: List<&2, MemTable.Entry>) -> IO(Unit):
  match es:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{h, t}:
      do IO<Unit>:
        _u : Unit <- IO.print(entry_line(h))
        print_entries(t)

def mem_count(db: Db.Db) -> Nat:
  match db:
    case Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token}:
      MemTable.count(mem)

def level_count(db: Db.Db) -> Nat:
  match db:
    case Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token}:
      List.length(&2, List<&2, Sstable.Table>, levels)

def compute_gpu_ok(enabled: Bool, fuel: Nat) -> IO(Nat):
  match enabled:
    case True{}:
      IO.pure(Nat, Demo.worker_gpu!(fuel, 0n))
    case False{}:
      do IO<Nat>:
        _u : Unit <- IO.print("error: GPU runtime is not enabled")
        return 0n

def compute_auto(enabled: Bool, fuel: Nat) -> IO(Nat):
  match enabled:
    case True{}: IO.pure(Nat, Demo.worker_gpu!(fuel, 0n))
    case False{}: IO.pure(Nat, Demo.worker(fuel, 0n))

def compute(mode: Repl.ComputeMode, enabled: Bool, fuel: Nat) -> IO(Nat):
  match mode:
    case Repl.Cpu{}: IO.pure(Nat, Demo.worker(fuel, 0n))
    case Repl.Gpu{}: compute_gpu_ok(enabled, fuel)
    case Repl.Auto{}: compute_auto(enabled, fuel)

def live_entries(es: List<&2, MemTable.Entry>) -> List<&2, MemTable.Entry>:
  match es:
    case Nil{}:
      Nil{}
    case Con{MemTable.Entry{key, val}, t}:
      match val:
        case None{}:
          live_entries(t)
        case Some{value}:
          Con{MemTable.Entry{key, Some{value}}, live_entries(t)}

def export_entries(db: Db.Db) -> List<&2, MemTable.Entry>:
  live_entries(SortedRun.sort_newest(Db.all_entries(db)))

def parent_parts(parts: List<&2, String>, acc: List<&2, String>) -> String:
  match parts:
    case Nil{}:
      "."
    case Con{last, Nil{}}:
      match acc:
        case Nil{}:
          "."
        case Con{h, t}:
          String.join(List.reverse(&2, String, Con{h, t}), "/")
    case Con{h, Con{k, t}}:
      parent_parts(Con{k, t}, Con{h, acc})

def parent_path(path: String) -> String:
  parent_parts(String.split(path, '/'), Nil{})

def return_session(session: Session) -> IO(LoopState):
  IO.pure(LoopState, Running{session})

def import_decoded(decoded: Maybe<&2, List<&2, MemTable.Entry>>, session: Session) -> IO(LoopState):
  match decoded:
    case None{}:
      do IO<LoopState>:
        _u : Unit <- IO.print("error: invalid or corrupt import file")
        return Running{session}
    case Some{entries}:
      match session:
        case Session{db, dir, timing, mode, gpu, workers, staged}:
          do IO<LoopState>:
            db2 : Db.Db <- IO.try(Db.Db, Recover.write(db, Wal.Batch{Interchange.muts_of_entries(entries)}))
            _u : Unit <- IO.print("OK import")
            return Running{Session{db2, dir, timing, mode, gpu, workers, staged}}

def replace_mode(+new_mode: Repl.ComputeMode, session: Session) -> IO(LoopState):
  match session:
    case Session{db, dir, timing, mode, gpu, workers, staged}:
      do IO<LoopState>:
        _u : Unit <- IO.print("mode=" ++ mode_name(new_mode))
        return Running{Session{db, dir, timing, new_mode, gpu, workers, staged}}

def gpu_enabled(session: Session) -> Bool:
  match session:
    case Session{db, dir, timing, mode, gpu, workers, staged}:
      gpu

def set_gpu_mode(enabled: Bool, session: Session) -> IO(LoopState):
  match enabled:
    case False{}:
      do IO<LoopState>:
        _u : Unit <- IO.print("error: GPU runtime is not enabled")
        return Running{session}
    case True{}:
      replace_mode(Repl.Gpu{}, session)

def update_mode(new_mode: Repl.ComputeMode, +session: Session) -> IO(LoopState):
  match new_mode:
    case Repl.Gpu{}:
      set_gpu_mode(gpu_enabled(session), session)
    case Repl.Cpu{}:
      replace_mode(Repl.Cpu{}, session)
    case Repl.Auto{}:
      replace_mode(Repl.Auto{}, session)

def restart_bounds(+count: Nat, +current: Nat) -> Bool:
  Bool.and(Nat.is_lt(0n, count), Bool.and(Nat.is_lt(count, 257n), Bool.not(Nat.is_eq(count, current))))

def restart_write(valid: Bool, +count: Nat, +dir: String, session: Session) -> IO(LoopState):
  match valid:
    case False{}:
      do IO<LoopState>:
        _u : Unit <- IO.print("error: threads must be 1..256 and differ from the current value")
        return Running{session}
    case True{}:
      do IO<LoopState>:
        _u0 : Unit <- IO.try(Unit, Flush.write_file(dir ++ "/.mylsm-restart-threads", Nat.show(count)))
        _u1 : Unit <- IO.print("restarting with threads=" ++ Nat.show(count))
        IO.die(LoopState, U32.from_nat(75n), "thread restart requested")

def restart_runtime(native: Bool, +count: Nat, +current: Nat, +dir: String, session: Session) -> IO(LoopState):
  match native:
    case False{}:
      do IO<LoopState>:
        _u : Unit <- IO.print("error: threads is available only in native mode")
        return Running{session}
    case True{}:
      restart_write(restart_bounds(count, current), count, dir, session)

def restart_env(runtime: String, count: Nat, current: Nat, dir: String, session: Session) -> IO(LoopState):
  restart_runtime(String.eq(runtime, "native"), count, current, dir, session)

def put_flush(full: Bool, +staged: List<&2, Wal.Batch>, +db: Db.Db, +dir: String, +timing: Repl.TimingMode, +mode: Repl.ComputeMode, +gpu: Bool, +workers: Nat) -> IO(LoopState):
  match full:
    case True{}:
      do IO<LoopState>:
        db2 : Db.Db <- IO.try(Db.Db, Db.db_write_staged(db, staged))
        _u : Unit <- IO.print("OK")
        return Running{Session{db2, dir, timing, mode, gpu, workers, Nil{}}}
    case False{}:
      do IO<LoopState>:
        _u : Unit <- IO.print("QUEUED")
        return Running{Session{db, dir, timing, mode, gpu, workers, staged}}

def execute_go(command: Repl.Command, session: Session) -> IO(LoopState):
  match command:
    case Repl.Noop{}:
      return_session(session)
    case Repl.Put{key, value}:
      match session:
        case Session{+db, dir, timing, mode, gpu, workers, +staged}:
          put_flush(Nat.is_le(Db.batch_cap_of(db), Nat.add(List.length(&2, Wal.Batch, staged), 1n)), Wal.stage(staged, Wal.Batch{Con{Wal.Put{key, value}, Nil{}}}), db, dir, timing, mode, gpu, workers)
    case Repl.Get{key}:
      match session:
        case Session{+db, dir, timing, mode, gpu, workers, staged}:
          do IO<LoopState>:
            _u : Unit <- IO.print(Demo.show_maybe(Db.db_get(db, key)))
            return Running{Session{db, dir, timing, mode, gpu, workers, staged}}
    case Repl.Del{key}:
      match session:
        case Session{+db, dir, timing, mode, gpu, workers, +staged}:
          put_flush(Nat.is_le(Db.batch_cap_of(db), Nat.add(List.length(&2, Wal.Batch, staged), 1n)), Wal.stage(staged, Wal.Batch{Con{Wal.Del{key}, Nil{}}}), db, dir, timing, mode, gpu, workers)
    case Repl.Scan{lo, hi}:
      match session:
        case Session{+db, dir, timing, mode, gpu, workers, staged}:
          do IO<LoopState>:
            _u : Unit <- print_entries(MergeIter.scan(Db.all_entries(db), lo, hi))
            return Running{Session{db, dir, timing, mode, gpu, workers, staged}}
    case Repl.Flush{}:
      match session:
        case Session{db, dir, timing, mode, gpu, workers, staged}:
          do IO<LoopState>:
            db2 : Db.Db <- IO.try(Db.Db, Flush.flush(db))
            _u : Unit <- IO.print("OK flush")
            return Running{Session{db2, dir, timing, mode, gpu, workers, staged}}
    case Repl.Compact{}:
      match session:
        case Session{db, dir, timing, mode, gpu, workers, staged}:
          do IO<LoopState>:
            db2 : Db.Db <- IO.try(Db.Db, Compact.compact(db))
            _u : Unit <- IO.print("OK compact")
            return Running{Session{db2, dir, timing, mode, gpu, workers, staged}}
    case Repl.Maintain{}:
      match session:
        case Session{db, dir, timing, mode, gpu, workers, staged}:
          do IO<LoopState>:
            db2 : Db.Db <- IO.try(Db.Db, Recover.maintain(db))
            _u : Unit <- IO.print("OK maintain")
            return Running{Session{db2, dir, timing, mode, gpu, workers, staged}}
    case Repl.Stats{}:
      match session:
        case Session{+db, dir, timing, mode, gpu, workers, staged}:
          do IO<LoopState>:
            _u0 : Unit <- IO.print("mem_entries=" ++ Nat.show(mem_count(db)))
            _u1 : Unit <- IO.print("levels=" ++ Nat.show(level_count(db)))
            return Running{Session{db, dir, timing, mode, gpu, workers, staged}}
    case Repl.Runtime{}:
      match session:
        case Session{db, dir, timing, +mode, +gpu, +workers, staged}:
          do IO<LoopState>:
            _u0 : Unit <- IO.print("mode=" ++ mode_name(mode))
            _u1 : Unit <- IO.print("gpu_enabled=" ++ bool_name(gpu))
            _u2 : Unit <- IO.print("threads=" ++ Nat.show(workers))
            _u3 : Unit <- IO.print("storage=cpu/io")
            return Running{Session{db, dir, timing, mode, gpu, workers, staged}}
    case Repl.Timing{new_timing}:
      match session:
        case Session{db, dir, timing, mode, gpu, workers, staged}:
          do IO<LoopState>:
            _u : Unit <- IO.print("timing updated")
            return Running{Session{db, dir, new_timing, mode, gpu, workers, staged}}
    case Repl.Mode{new_mode}:
      update_mode(new_mode, session)
    case Repl.Threads{+count}:
      match session:
        case Session{db, +dir, timing, mode, gpu, +workers, staged}:
          do IO<LoopState>:
            runtime : String <- IO.try(String, Console.get_env("MYLSM_RUNTIME"))
            restart_env(runtime, count, workers, dir, Session{db, dir, timing, mode, gpu, workers, staged})
    case Repl.Compute{fuel}:
      match session:
        case Session{db, dir, timing, +mode, +gpu, workers, staged}:
          do IO<LoopState>:
            value : Nat <- compute(mode, gpu, fuel)
            _u : Unit <- IO.print("compute=" ++ Nat.show(value))
            return Running{Session{db, dir, timing, mode, gpu, workers, staged}}
    case Repl.Import{path}:
      do IO<LoopState>:
        data : String <- IO.try(String, Flush.read_file(path))
        import_decoded(Interchange.parse(data), session)
    case Repl.Export{+path}:
      match session:
        case Session{+db, dir, timing, mode, gpu, workers, staged}:
          do IO<LoopState>:
            _u0 : Unit <- IO.try(Unit, Flush.write_file(path ++ ".tmp", Interchange.serialize(export_entries(db))))
            _u1 : Unit <- IO.try(Unit, Fs.rename(path ++ ".tmp", path))
            _u2 : Unit <- IO.try(Unit, Fs.fsync(parent_path(path)))
            _u3 : Unit <- IO.print("OK export")
            return Running{Session{db, dir, timing, mode, gpu, workers, staged}}
    case Repl.Time{inner}:
      do IO<LoopState>:
        _u : Unit <- IO.print("use 'timing once' before the command: " ++ inner)
        return Running{session}
    case Repl.Help{}:
      do IO<LoopState>:
        _u0 : Unit <- IO.print("put/get/del/scan <args>")
        _u1 : Unit <- IO.print("flush compact maintain stats runtime")
        _u2 : Unit <- IO.print("timing <on|off|once> mode <cpu|gpu|auto> compute <fuel>")
        _u3 : Unit <- IO.print("import <path> export <path> help exit")
        return Running{session}
    case Repl.Exit{}:
      do IO<LoopState>:
        _u : Unit <- IO.print("bye")
        return Stopped{}
    case Repl.Invalid{message}:
      do IO<LoopState>:
        _u : Unit <- IO.print("error: " ++ message)
        return Running{session}

def execute_flushed(command: Repl.Command, +db: Db.Db, +dir: String, +timing: Repl.TimingMode, +mode: Repl.ComputeMode, +gpu: Bool, +workers: Nat, +staged: List<&2, Wal.Batch>) -> IO(LoopState):
  match staged:
    case Nil{}:
      execute_go(command, Session{db, dir, timing, mode, gpu, workers, Nil{}})
    case Con{_, _}:
      do IO<LoopState>:
        db2 : Db.Db <- IO.try(Db.Db, Db.db_write_staged(db, staged))
        execute_go(command, Session{db2, dir, timing, mode, gpu, workers, Nil{}})

def execute(command: Repl.Command, session: Session) -> IO(LoopState):
  match session:
    case Session{db, dir, timing, mode, gpu, workers, staged}:
      execute_flushed(command, db, dir, timing, mode, gpu, workers, staged)

def reset_once_state(once: Bool, state: LoopState) -> LoopState:
  match once state:
    case False{} _:
      state
    case True{} Stopped{}:
      Stopped{}
    case True{} Running{Session{db, dir, timing, mode, gpu, workers, staged}}:
      Running{Session{db, dir, Repl.TimingOff{}, mode, gpu, workers, staged}}

def timed_run(once: Bool, command: Repl.Command, session: Session) -> IO(LoopState):
  do IO<LoopState>:
    start : Nat <- IO.now()
    state : LoopState <- execute(command, session)
    finish : Nat <- IO.now()
    _u : Unit <- IO.print("time_ms=" ++ Nat.show(Nat.sub(finish, start)))
    return reset_once_state(once, state)

def timed_dispatch(enabled: Bool, once: Bool, command: Repl.Command, session: Session) -> IO(LoopState):
  match enabled:
    case True{}: timed_run(once, command, session)
    case False{}: execute(command, session)

def run_regular(command: Repl.Command, session: Session) -> IO(LoopState):
  match session:
    case Session{db, dir, +timing, mode, gpu, workers, staged}:
      timed_dispatch(timing_should(timing), timing_once(timing), command, Session{db, dir, timing, mode, gpu, workers, staged})

def run_time(inner: String, session: Session) -> IO(LoopState):
  timed_dispatch(True{}, False{}, Parser.parse_command(inner), session)

# Time is expanded exactly once here; execute itself never recurses on Command.
def run_command(command: Repl.Command, session: Session) -> IO(LoopState):
  match command:
    case Repl.Time{inner}: run_time(inner, session)
    case Repl.Noop{}: run_regular(Repl.Noop{}, session)
    case Repl.Put{key, value}: run_regular(Repl.Put{key, value}, session)
    case Repl.Get{key}: run_regular(Repl.Get{key}, session)
    case Repl.Del{key}: run_regular(Repl.Del{key}, session)
    case Repl.Scan{lo, hi}: run_regular(Repl.Scan{lo, hi}, session)
    case Repl.Flush{}: run_regular(Repl.Flush{}, session)
    case Repl.Compact{}: run_regular(Repl.Compact{}, session)
    case Repl.Maintain{}: run_regular(Repl.Maintain{}, session)
    case Repl.Stats{}: run_regular(Repl.Stats{}, session)
    case Repl.Runtime{}: run_regular(Repl.Runtime{}, session)
    case Repl.Timing{mode}: run_regular(Repl.Timing{mode}, session)
    case Repl.Mode{mode}: run_regular(Repl.Mode{mode}, session)
    case Repl.Threads{count}: run_regular(Repl.Threads{count}, session)
    case Repl.Compute{fuel}: run_regular(Repl.Compute{fuel}, session)
    case Repl.Import{path}: run_regular(Repl.Import{path}, session)
    case Repl.Export{path}: run_regular(Repl.Export{path}, session)
    case Repl.Help{}: run_regular(Repl.Help{}, session)
    case Repl.Exit{}: run_regular(Repl.Exit{}, session)
    case Repl.Invalid{message}: run_regular(Repl.Invalid{message}, session)

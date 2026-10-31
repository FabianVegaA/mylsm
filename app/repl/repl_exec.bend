import Base
import ../../mylsm.bend as MyLSM
import ../../src/Fs.bend as Fs
import ../../src/Console.bend as Console
import ../demo/demo_helpers.bend as Demo
import ./interchange.bend as Interchange
import ./repl_types.bend as Repl
import ./repl_parser.bend as Parser
import ./repl_policy.bend as Policy

# Holds the session settings that do not own a resource.
type Settings is Data:
  Settings{dir: String, timing: Repl.TimingMode, mode: Repl.ComputeMode,
    gpu: Bool, workers: Nat, batch_cap: Nat}

# Owns the open database handle, the settings, and the queued mutations.
type Session is Type:
  Session{handle: MyLSM.Utf8.Handle, settings: Settings,
    staged: List<&1, MyLSM.Utf8.Mutation>}

# Says whether the REPL keeps reading commands.
type LoopState is Type:
  Running{session: Session}
  Stopped{}

# Names a compute mode the way the REPL prints it.
def mode_name(mode: Repl.ComputeMode) -> String:
  match mode:
    case Repl.Cpu{}: "cpu"
    case Repl.Gpu{}: "gpu"
    case Repl.Auto{}: "auto"

# Prints a flag as yes or no.
def bool_name(value: Bool) -> String:
  match value:
    case True{}: "yes"
    case False{}: "no"

def compute.gpu(enabled: Bool, fuel: Nat) -> IO(Nat):
  match enabled:
    case True{}: IO.pure(Nat, Demo.worker_gpu!(fuel, 0n))
    case False{}:
      do IO<Nat>:
        _printed : Unit <- IO.print("error: GPU runtime is not enabled")
        return 0n

def compute.auto(enabled: Bool, fuel: Nat) -> IO(Nat):
  match enabled:
    case True{}: IO.pure(Nat, Demo.worker_gpu!(fuel, 0n))
    case False{}: IO.pure(Nat, Demo.worker(fuel, 0n))

# Runs the compute worker in the selected mode.
def compute(mode: Repl.ComputeMode, enabled: Bool, fuel: Nat) -> IO(Nat):
  match mode:
    case Repl.Cpu{}: IO.pure(Nat, Demo.worker(fuel, 0n))
    case Repl.Gpu{}: compute.gpu(enabled, fuel)
    case Repl.Auto{}: compute.auto(enabled, fuel)

# Keeps the session running after printing a line.
def say(message: String, session: Session) -> IO(LoopState):
  do IO<LoopState>:
    _printed : Unit <- IO.print(message)
    return Running{session}

# Takes the handle back after a committed write; a failed write stops the REPL.
def written(
  pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, MyLSM.WriteOutcome>
) -> IO(MyLSM.Utf8.Handle):
  match pair:
    case (handle, Done{_}): IO.pure(MyLSM.Utf8.Handle, handle)
    case (_, Fail{_}): IO.die(MyLSM.Utf8.Handle, 1, "error: write failed")

# Commits the queued mutations as one batch.
def commit(handle: MyLSM.Utf8.Handle, staged: List<&1, MyLSM.Utf8.Mutation>) -> IO(MyLSM.Utf8.Handle):
  do IO<MyLSM.Utf8.Handle>:
    pair : MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, MyLSM.WriteOutcome> <-
      MyLSM.Utf8.write_batch(handle, staged)
    written(pair)

def staged.count.pushed(
  mutation: MyLSM.Utf8.Mutation,
  pair: List<&1, MyLSM.Utf8.Mutation> & Nat
) -> List<&1, MyLSM.Utf8.Mutation> & Nat:
  match pair:
    case (rest, count): (Con{mutation, rest}, Nat.add(count, 1n))

def staged.count(staged: List<&1, MyLSM.Utf8.Mutation>) -> List<&1, MyLSM.Utf8.Mutation> & Nat:
  match staged:
    case Nil{}: (Nil{}, 0n)
    case Con{mutation, rest}: staged.count.pushed(mutation, staged.count(rest))

def stage.decided(
  full: Bool,
  handle: MyLSM.Utf8.Handle,
  settings: Settings,
  staged: List<&1, MyLSM.Utf8.Mutation>
) -> IO(LoopState):
  match full:
    case True{}:
      do IO<LoopState>:
        committed : MyLSM.Utf8.Handle <- commit(handle, staged)
        say("OK", Session{committed, settings, Nil{}})
    case False{}: say("QUEUED", Session{handle, settings, staged})

def stage.counted(
  handle: MyLSM.Utf8.Handle,
  +settings: Settings,
  pair: List<&1, MyLSM.Utf8.Mutation> & Nat
) -> IO(LoopState):
  match settings:
    case Settings{_, _, _, _, _, +batch_cap}:
      match pair:
        case (staged, count):
          stage.decided(Nat.is_le(batch_cap, count), handle, settings, staged)

# Queues one mutation and commits once the batch reaches its cap.
def stage(session: Session, mutation: MyLSM.Utf8.Mutation) -> IO(LoopState):
  match session:
    case Session{handle, settings, staged}:
      stage.counted(handle, settings,
        staged.count(List.append(&1, MyLSM.Utf8.Mutation, staged, [mutation])))

# Prints the value a get returned.
def got(
  pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Maybe<&2, String>>,
  settings: Settings
) -> IO(LoopState):
  match pair:
    case (handle, Done{value}): say(Demo.show_maybe(value), Session{handle, settings, Nil{}})
    case (handle, Fail{_}): say("error: read failed", Session{handle, settings, Nil{}})

def scan.closed(pair: MyLSM.Utf8.Cursor & Result<&1, &1, MyLSM.Utf8.Error, Unit>) -> IO(Unit):
  match pair:
    case (_, _): IO.pure(Unit, Unit{})

def scan.close(cursor: MyLSM.Utf8.Cursor) -> IO(Unit):
  do IO<Unit>:
    pair : MyLSM.Utf8.Cursor & Result<&1, &1, MyLSM.Utf8.Error, Unit> <-
      MyLSM.Utf8.scan_close(cursor)
    scan.closed(pair)

# Prints every live entry the cursor yields as key=value.
def scan.print(fuel: Nat, step: MyLSM.Utf8.ScanStep) -> IO(Unit):
  match fuel:
    case 0n:
      match step:
        case MyLSM.Utf8ScanItem{_, _, cursor}: scan.close(cursor)
        case MyLSM.Utf8ScanSkip{cursor}: scan.close(cursor)
        case MyLSM.Utf8ScanEnd{cursor}: scan.close(cursor)
        case MyLSM.Utf8ScanFailure{_, cursor}: scan.close(cursor)
    case 1n+rest:
      match step:
        case MyLSM.Utf8ScanItem{key, value, cursor}:
          do IO<Unit>:
            _printed : Unit <- IO.print(key ++ "=" ++ value)
            next : MyLSM.Utf8.ScanStep <- MyLSM.Utf8.scan_next(cursor)
            scan.print(rest, next)
        case MyLSM.Utf8ScanSkip{cursor}:
          do IO<Unit>:
            next : MyLSM.Utf8.ScanStep <- MyLSM.Utf8.scan_next(cursor)
            scan.print(rest, next)
        case MyLSM.Utf8ScanEnd{cursor}: scan.close(cursor)
        case MyLSM.Utf8ScanFailure{_, cursor}:
          do IO<Unit>:
            _printed : Unit <- IO.print("error: scan failed")
            scan.close(cursor)

def scan.opened(
  pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Cursor>,
  settings: Settings
) -> IO(LoopState):
  match pair:
    case (handle, Fail{_}): say("error: scan failed", Session{handle, settings, Nil{}})
    case (handle, Done{cursor}):
      do IO<LoopState>:
        first : MyLSM.Utf8.ScanStep <- MyLSM.Utf8.scan_next(cursor)
        _printed : Unit <- scan.print(4294967295n, first)
        return Running{Session{handle, settings, Nil{}}}

# Prints the outcome of a flush or compaction.
def maintained(
  pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Unit>,
  settings: Settings,
  message: String
) -> IO(LoopState):
  match pair:
    case (handle, Done{Unit{}}): say(message, Session{handle, settings, Nil{}})
    case (handle, Fail{_}): say("error: " ++ message ++ " failed", Session{handle, settings, Nil{}})

def stats.line(stats: MyLSM.Utf8.Stats) -> String:
  match stats:
    case MyLSM.Utf8Stats{MyLSM.ByteStats{entries, payload_bytes, snapshots, retained_bytes, cursors}}:
      "entries=" ++ Nat.show(entries) ++ " payload_bytes=" ++ Nat.show(payload_bytes) ++
        " snapshots=" ++ Nat.show(snapshots) ++ " retained_bytes=" ++
        Nat.show(retained_bytes) ++ " cursors=" ++ Nat.show(cursors)

def stats.read(
  pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Stats>,
  settings: Settings
) -> IO(LoopState):
  match pair:
    case (handle, Done{stats}): say(stats.line(stats), Session{handle, settings, Nil{}})
    case (handle, Fail{_}): say("error: stats failed", Session{handle, settings, Nil{}})

def export.collect(
  fuel: Nat,
  step: MyLSM.Utf8.ScanStep,
  found: List<&2, Interchange.Record>
) -> IO(List<&2, Interchange.Record>):
  match fuel:
    case 0n:
      match step:
        case MyLSM.Utf8ScanItem{_, _, cursor}:
          do IO<List<&2, Interchange.Record>>:
            _closed : Unit <- scan.close(cursor)
            return List.reverse(&2, Interchange.Record, found)
        case MyLSM.Utf8ScanSkip{cursor}:
          do IO<List<&2, Interchange.Record>>:
            _closed : Unit <- scan.close(cursor)
            return List.reverse(&2, Interchange.Record, found)
        case MyLSM.Utf8ScanEnd{cursor}:
          do IO<List<&2, Interchange.Record>>:
            _closed : Unit <- scan.close(cursor)
            return List.reverse(&2, Interchange.Record, found)
        case MyLSM.Utf8ScanFailure{_, cursor}:
          do IO<List<&2, Interchange.Record>>:
            _closed : Unit <- scan.close(cursor)
            IO.die(List<&2, Interchange.Record>, 1, "error: export scan failed")
    case 1n+rest:
      match step:
        case MyLSM.Utf8ScanItem{key, value, cursor}:
          do IO<List<&2, Interchange.Record>>:
            next : MyLSM.Utf8.ScanStep <- MyLSM.Utf8.scan_next(cursor)
            export.collect(rest, next, Con{Interchange.Record{key, value}, found})
        case MyLSM.Utf8ScanSkip{cursor}:
          do IO<List<&2, Interchange.Record>>:
            next : MyLSM.Utf8.ScanStep <- MyLSM.Utf8.scan_next(cursor)
            export.collect(rest, next, found)
        case MyLSM.Utf8ScanEnd{cursor}:
          do IO<List<&2, Interchange.Record>>:
            _closed : Unit <- scan.close(cursor)
            return List.reverse(&2, Interchange.Record, found)
        case MyLSM.Utf8ScanFailure{_, cursor}:
          do IO<List<&2, Interchange.Record>>:
            _closed : Unit <- scan.close(cursor)
            IO.die(List<&2, Interchange.Record>, 1, "error: export scan failed")

def export.write(
  +path: String,
  encoded: Result<&1, &1, U32 & String, String>,
  session: Session
) -> IO(LoopState):
  match encoded:
    case Fail{_}: say("error: export could not encode a value", session)
    case Done{data}:
      do IO<LoopState>:
        _written : Unit <- IO.try(Unit, Fs.write_text(path ++ ".tmp", data))
        _renamed : Unit <- IO.try(Unit, Fs.rename(path ++ ".tmp", path))
        _synced : Unit <- IO.try(Unit, Fs.fsync(Policy.parent_path(path)))
        say("OK export", session)

def export.opened(
  +path: String,
  pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Cursor>,
  settings: Settings
) -> IO(LoopState):
  match pair:
    case (handle, Fail{_}): say("error: export scan failed", Session{handle, settings, Nil{}})
    case (handle, Done{cursor}):
      do IO<LoopState>:
        first : MyLSM.Utf8.ScanStep <- MyLSM.Utf8.scan_next(cursor)
        records : List<&2, Interchange.Record> <- export.collect(4294967295n, first, Nil{})
        export.write(path, Interchange.serialize(records), Session{handle, settings, Nil{}})

def import.mutations(records: List<&2, Interchange.Record>) -> List<&1, MyLSM.Utf8.Mutation>:
  match records:
    case Nil{}: Nil{}
    case Con{Interchange.Record{key, value}, rest}:
      Con{MyLSM.Utf8SetValue{key, value}, import.mutations(rest)}

def import.decoded(
  decoded: Maybe<&2, List<&2, Interchange.Record>>,
  session: Session
) -> IO(LoopState):
  match decoded:
    case None{}: say("error: invalid or corrupt import file", session)
    case Some{records}:
      match session:
        case Session{handle, settings, staged}:
          do IO<LoopState>:
            committed : MyLSM.Utf8.Handle <- commit(handle, import.mutations(records))
            say("OK import", Session{committed, settings, staged})

def threads.write(valid: Bool, +count: Nat, +dir: String, session: Session) -> IO(LoopState):
  match valid:
    case False{}: say("error: threads must be 1..256 and differ from the current value", session)
    case True{}:
      do IO<LoopState>:
        _written : Unit <- IO.try(Unit, Fs.write_text(dir ++ "/.mylsm-restart-threads", Nat.show(count)))
        _printed : Unit <- IO.print("restarting with threads=" ++ Nat.show(count))
        IO.die(LoopState, U32.from_nat(75n), "thread restart requested")

def threads.native(native: Bool, +count: Nat, +settings: Settings, session: Session) -> IO(LoopState):
  match native:
    case False{}: say("error: threads is available only in native mode", session)
    case True{}:
      match settings:
        case Settings{dir, _, _, _, +workers, _}:
          threads.write(Policy.restart_bounds(count, workers), count, dir, session)

def mode.set(+new_mode: Repl.ComputeMode, session: Session) -> IO(LoopState):
  match session:
    case Session{handle, Settings{dir, timing, _, gpu, workers, batch_cap}, staged}:
      say("mode=" ++ mode_name(new_mode),
        Session{handle, Settings{dir, timing, new_mode, gpu, workers, batch_cap}, staged})

def mode.gpu(enabled: Bool, session: Session) -> IO(LoopState):
  match enabled:
    case False{}: say("error: GPU runtime is not enabled", session)
    case True{}: mode.set(Repl.Gpu{}, session)

# Prints the command summary.
def help(session: Session) -> IO(LoopState):
  do IO<LoopState>:
    _line0 : Unit <- IO.print("put/get/del/scan <args>")
    _line1 : Unit <- IO.print("flush compact stats runtime")
    _line2 : Unit <- IO.print("timing <on|off|once> mode <cpu|gpu|auto> compute <fuel>")
    _line3 : Unit <- IO.print("import <path> export <path> help exit")
    return Running{session}

# Prints the runtime settings.
def runtime(+settings: Settings, session: Session) -> IO(LoopState):
  match settings:
    case Settings{_, _, mode, gpu, workers, _}:
      do IO<LoopState>:
        _mode : Unit <- IO.print("mode=" ++ mode_name(mode))
        _gpu : Unit <- IO.print("gpu_enabled=" ++ bool_name(gpu))
        _threads : Unit <- IO.print("threads=" ++ Nat.show(workers))
        say("storage=cpu/io", session)

# Closes the database before the REPL stops.
def exit(session: Session) -> IO(LoopState):
  match session:
    case Session{handle, _, _}:
      do IO<LoopState>:
        _closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        _printed : Unit <- IO.print("bye")
        return Stopped{}

def import.read(data: Result<&1, &1, U32 & String, String>, session: Session) -> IO(LoopState):
  match data:
    case Fail{_}: say("error: import file could not be read", session)
    case Done{text}: import.decoded(Interchange.parse(text), session)

def execute.go(command: Repl.Command, session: Session) -> IO(LoopState):
  match command:
    case Repl.Noop{}: IO.pure(LoopState, Running{session})
    case Repl.Put{key, value}: stage(session, MyLSM.Utf8SetValue{key, value})
    case Repl.Del{key}: stage(session, MyLSM.Utf8DeleteKey{key})
    case Repl.Get{key}:
      match session:
        case Session{handle, settings, _}:
          do IO<LoopState>:
            pair : MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Maybe<&2, String>> <-
              MyLSM.Utf8.get(handle, key)
            got(pair, settings)
    case Repl.Scan{lo, hi}:
      match session:
        case Session{handle, settings, _}:
          do IO<LoopState>:
            pair : MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Cursor> <-
              MyLSM.Utf8.scan_range(handle, Some{lo}, Some{hi})
            scan.opened(pair, settings)
    case Repl.Flush{}:
      match session:
        case Session{handle, settings, _}:
          do IO<LoopState>:
            pair : MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Unit> <-
              MyLSM.Utf8.flush(handle)
            maintained(pair, settings, "OK flush")
    case Repl.Compact{}:
      match session:
        case Session{handle, settings, _}:
          do IO<LoopState>:
            pair : MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Unit> <-
              MyLSM.Utf8.compact(handle)
            maintained(pair, settings, "OK compact")
    case Repl.Stats{}:
      match session:
        case Session{handle, settings, _}:
          do IO<LoopState>:
            pair : MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Stats> <-
              MyLSM.Utf8.stats(handle)
            stats.read(pair, settings)
    case Repl.Runtime{}:
      match session:
        case Session{handle, +settings, staged}:
          runtime(settings, Session{handle, settings, staged})
    case Repl.Timing{new_timing}:
      match session:
        case Session{handle, Settings{dir, _, mode, gpu, workers, batch_cap}, staged}:
          say("timing updated",
            Session{handle, Settings{dir, new_timing, mode, gpu, workers, batch_cap}, staged})
    case Repl.Mode{new_mode}:
      match new_mode:
        case Repl.Gpu{}:
          match session:
            case Session{handle, +settings, staged}:
              match settings:
                case Settings{_, _, _, +gpu, _, _}:
                  mode.gpu(gpu, Session{handle, settings, staged})
        case Repl.Cpu{}: mode.set(Repl.Cpu{}, session)
        case Repl.Auto{}: mode.set(Repl.Auto{}, session)
    case Repl.Threads{+count}:
      match session:
        case Session{handle, +settings, staged}:
          do IO<LoopState>:
            runtime_name : String <- IO.try(String, Console.get_env("MYLSM_RUNTIME"))
            threads.native(String.eq(runtime_name, "native"), count, settings,
              Session{handle, settings, staged})
    case Repl.Compute{fuel}:
      match session:
        case Session{handle, +settings, staged}:
          match settings:
            case Settings{_, _, +mode, +gpu, _, _}:
              do IO<LoopState>:
                value : Nat <- compute(mode, gpu, fuel)
                say("compute=" ++ Nat.show(value), Session{handle, settings, staged})
    case Repl.Import{path}:
      do IO<LoopState>:
        data : Result<&1, &1, U32 & String, String> <- Fs.read_text(path)
        import.read(data, session)
    case Repl.Export{+path}:
      match session:
        case Session{handle, settings, _}:
          do IO<LoopState>:
            pair : MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Cursor> <-
              MyLSM.Utf8.scan_range(handle, None{}, None{})
            export.opened(path, pair, settings)
    case Repl.Time{inner}: say("use 'timing once' before the command: " ++ inner, session)
    case Repl.Help{}: help(session)
    case Repl.ExitCommand{}: exit(session)
    case Repl.Invalid{message}: say("error: " ++ message, session)

# Commits queued mutations before running the next command.
def execute(command: Repl.Command, session: Session) -> IO(LoopState):
  match session:
    case Session{handle, settings, staged}:
      match staged:
        case Nil{}: execute.go(command, Session{handle, settings, Nil{}})
        case Con{first, rest}:
          do IO<LoopState>:
            committed : MyLSM.Utf8.Handle <- commit(handle, Con{first, rest})
            execute.go(command, Session{committed, settings, Nil{}})

def once.reset(once: Bool, state: LoopState) -> LoopState:
  match once:
    case False{}: state
    case True{}:
      match state:
        case Stopped{}: Stopped{}
        case Running{Session{handle, Settings{dir, _, mode, gpu, workers, batch_cap}, staged}}:
          Running{Session{handle, Settings{dir, Repl.TimingOff{}, mode, gpu, workers, batch_cap}, staged}}

def timed.run(once: Bool, command: Repl.Command, session: Session) -> IO(LoopState):
  do IO<LoopState>:
    start : Nat <- IO.now()
    state : LoopState <- execute(command, session)
    finish : Nat <- IO.now()
    _printed : Unit <- IO.print("time_ms=" ++ Nat.show(Nat.sub(finish, start)))
    return once.reset(once, state)

def timed.dispatch(enabled: Bool, once: Bool, command: Repl.Command, session: Session) -> IO(LoopState):
  match enabled:
    case True{}: timed.run(once, command, session)
    case False{}: execute(command, session)

def run.regular(command: Repl.Command, session: Session) -> IO(LoopState):
  match session:
    case Session{handle, +settings, staged}:
      match settings:
        case Settings{_, +timing, _, _, _, _}:
          timed.dispatch(Policy.timing_should(timing), Policy.timing_once(timing), command,
            Session{handle, settings, staged})

# Runs one parsed command; a time prefix is expanded here exactly once.
def run_command(command: Repl.Command, session: Session) -> IO(LoopState):
  match command:
    case Repl.Time{inner}: timed.dispatch(True{}, False{}, Parser.parse_command(inner), session)
    case Repl.Noop{}: run.regular(Repl.Noop{}, session)
    case Repl.Put{key, value}: run.regular(Repl.Put{key, value}, session)
    case Repl.Get{key}: run.regular(Repl.Get{key}, session)
    case Repl.Del{key}: run.regular(Repl.Del{key}, session)
    case Repl.Scan{lo, hi}: run.regular(Repl.Scan{lo, hi}, session)
    case Repl.Flush{}: run.regular(Repl.Flush{}, session)
    case Repl.Compact{}: run.regular(Repl.Compact{}, session)
    case Repl.Stats{}: run.regular(Repl.Stats{}, session)
    case Repl.Runtime{}: run.regular(Repl.Runtime{}, session)
    case Repl.Timing{mode}: run.regular(Repl.Timing{mode}, session)
    case Repl.Mode{mode}: run.regular(Repl.Mode{mode}, session)
    case Repl.Threads{count}: run.regular(Repl.Threads{count}, session)
    case Repl.Compute{fuel}: run.regular(Repl.Compute{fuel}, session)
    case Repl.Import{path}: run.regular(Repl.Import{path}, session)
    case Repl.Export{path}: run.regular(Repl.Export{path}, session)
    case Repl.Help{}: run.regular(Repl.Help{}, session)
    case Repl.ExitCommand{}: run.regular(Repl.ExitCommand{}, session)
    case Repl.Invalid{message}: run.regular(Repl.Invalid{message}, session)

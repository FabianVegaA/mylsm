import Base
import ../../src/Console.bend as Console
import ../../mylsm.bend as MyLSM
import ./repl_types.bend as Repl
import ./repl_parser.bend as Parser
import ./repl_exec.bend as Exec

# Read the environment setting for default for the interactive shell loop.
def env_default(value: String, fallback: String) -> String:
  match value:
    case SNil{}: fallback
    case SCon{h, t}: SCon{h, t}

# Read the environment setting for gpu for the interactive shell loop.
def env_gpu(value: String) -> Bool:
  match value:
    case SCon{'1', SNil{}}: True{}
    case _: False{}

# Read the environment setting for mode for the interactive shell loop.
def env_mode(value: String) -> Repl.ComputeMode:
  match value:
    case SCon{'g', SCon{'p', SCon{'u', SNil{}}}}: Repl.Gpu{}
    case SCon{'c', SCon{'p', SCon{'u', SNil{}}}}: Repl.Cpu{}
    case _: Repl.Auto{}

# Parse the natural-number setting for default for the interactive shell loop.
def nat_default(value: Maybe<&2, Nat>) -> Nat:
  match value:
    case None{}: 1n
    case Some{n}: n

# Handle batch clamp in the interactive shell loop.
def batch_clamp(count: Nat) -> Nat:
  Nat.max(1n, Nat.min(count, 1024n))

# Reads commands until exit or the per-process command budget runs out.
def repl_loop(commands: Nat, state: Exec.LoopState) -> IO(Unit):
  match commands:
    case 0n:
      match state:
        case Exec.Stopped{}: IO.print("session command limit reached")
        case Exec.Running{session}:
          do IO<Unit>:
            _stopped : Exec.LoopState <- Exec.execute(Repl.ExitCommand{}, session)
            IO.print("session command limit reached")
    case 1n+rest:
      match state:
        case Exec.Stopped{}: IO.pure(Unit, Unit{})
        case Exec.Running{session}:
          do IO<Unit>:
            _prompt : Unit <- IO.print("mylsm>")
            line : String <- IO.try(String, Console.read_line())
            next : Exec.LoopState <- Exec.run_command(Parser.parse_command(line), session)
            repl_loop(rest, next)

def legacy.checked(is_legacy: Bool) -> IO(MyLSM.Utf8.Handle):
  match is_legacy:
    case True{}:
      IO.die(MyLSM.Utf8.Handle, 1,
        "error: database uses the 0.5 format; run migrate_legacy first")
    case False{}: IO.die(MyLSM.Utf8.Handle, 1, "error: database could not be opened")

def legacy.inspected(
  result: Result<&1, &1, MyLSM.InspectionError, MyLSM.ManifestInspection>
) -> IO(MyLSM.Utf8.Handle):
  match result:
    case Done{MyLSM.ManifestInspection{_, _, generation, _}}:
      legacy.checked(U32.is_eq(generation, 3))
    case Fail{_}: legacy.checked(False{})

# Takes the new handle, or explains why the directory cannot be opened.
def created(
  +dir: String,
  result: Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle>
) -> IO(MyLSM.Utf8.Handle):
  match result:
    case Done{handle}: IO.pure(MyLSM.Utf8.Handle, handle)
    case Fail{_}:
      do IO<MyLSM.Utf8.Handle>:
        inspected : Result<&1, &1, MyLSM.InspectionError, MyLSM.ManifestInspection> <-
          MyLSM.inspect(dir)
        legacy.inspected(inspected)

# Takes the existing handle, or creates the database when none exists.
def opened(
  +dir: String,
  result: Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle>
) -> IO(MyLSM.Utf8.Handle):
  match result:
    case Done{handle}: IO.pure(MyLSM.Utf8.Handle, handle)
    case Fail{_}:
      do IO<MyLSM.Utf8.Handle>:
        result : Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle> <-
          MyLSM.Utf8.create(dir)
        created(dir, result)

# Opens the REPL database, creating it when the directory has none.
def open(+dir: String) -> IO(MyLSM.Utf8.Handle):
  do IO<MyLSM.Utf8.Handle>:
    result : Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle> <-
      MyLSM.Utf8.open_existing(dir)
    opened(dir, result)

def main() -> IO(Unit):
  do IO<Unit>:
    dir_env : String <- IO.try(String, Console.get_env("MYLSM_DIR"))
    mode_env : String <- IO.try(String, Console.get_env("MYLSM_EFFECTIVE_DEVICE"))
    gpu_env : String <- IO.try(String, Console.get_env("MYLSM_GPU_ENABLED"))
    workers_env : String <- IO.try(String, Console.get_env("MYLSM_THREADS"))
    batch_env : String <- IO.try(String, Console.get_env("MYLSM_BATCH_CAP"))
    +dir : String <- IO.pure(String, env_default(dir_env, ".mylsm-repl-data"))
    handle : MyLSM.Utf8.Handle <- open(dir)
    _title : Unit <- IO.print("MyLSM REPL")
    _database : Unit <- IO.print("database=" ++ dir)
    repl_loop(256n, Exec.Running{Exec.Session{handle,
      Exec.Settings{dir, Repl.TimingOff{}, env_mode(mode_env), env_gpu(gpu_env),
        nat_default(Nat.read(workers_env)),
        batch_clamp(nat_default(Nat.read(batch_env)))}, Nil{}}})

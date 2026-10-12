import Base
import ./Types.bend as Cli
import ./Policy.bend as Policy
import ./Runtime.bend as Runtime
import ../../src/Console.bend as Console
import ../../src/Fs.bend as Fs
import ../../src/Flush.bend as Flush

# Tracks whether the REPL launcher should run again or finish.
type State is Data:
  Launch{threads: Nat}
  Finished{status: U32}

# Chooses the explicit REPL directory, configured directory, or default.
def resolve_directory(value: Maybe<&2, String>, configured: String) -> String:
  match value:
    case Some{directory}: directory
    case None{}: Runtime.env_default(configured, ".mylsm-repl-data")

# Removes a restart sidecar only when it exists.
def clear_if_present(present: Bool, path: String) -> IO(Unit):
  match present:
    case False{}: IO.pure(Unit, Unit{})
    case True{}: IO.try(Unit, Fs.remove(path))

# Checks for and removes stale restart state before launching a child.
def clear_sidecar(+path: String) -> IO(Unit):
  do IO<Unit>:
    present : Bool <- IO.try(Bool, Fs.exists(path))
    clear_if_present(present, path)

# Reads a bounded restart sidecar or rejects an oversized request.
def read_small(ok: Bool, path: String) -> IO(Maybe<&2, String>):
  match ok:
    case False{}: IO.die(Maybe<&2, String>, 70, "invalid thread restart request")
    case True{}:
      do IO<Maybe<&2, String>>:
        value : String <- IO.try(String, Flush.read_file(path))
        return Some{String.trim(value)}

# Reads restart state only when a sidecar is present.
def read_if_present(present: Bool, +path: String) -> IO(Maybe<&2, String>):
  match present:
    case False{}: IO.pure(Maybe<&2, String>, None{})
    case True{}:
      do IO<Maybe<&2, String>>:
        size : Nat <- IO.try(Nat, Fs.file_size(path))
        read_small(Nat.is_lt(size, 17n), path)

# Checks for the REPL restart sidecar and reads it when present.
def read_sidecar(+path: String) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    present : Bool <- IO.try(Bool, Fs.exists(path))
    read_if_present(present, path)

# Converts the pure restart decision into the next launcher state.
def decision_state(result: Result<&1, &1, String, Maybe<&2, Nat>>, status: U32) -> IO(State):
  match result:
    case Fail{message}: IO.die(State, 70, message)
    case Done{None{}}: IO.pure(State, Finished{status})
    case Done{Some{count}}: IO.pure(State, Launch{count})

# Reads and validates restart state only after a restart exit status.
def next_state_requested(requested: Bool, +status: U32, sidecar: String, current: Nat, remaining: Nat) -> IO(State):
  match requested:
    case False{}: IO.pure(State, Finished{status})
    case True{}:
      do IO<State>:
        value : Maybe<&2, String> <- read_sidecar(sidecar)
        decision_state(Policy.restart_threads(status, value, current, remaining), status)

# Chooses a restart state from the child exit status and sidecar.
def next_state(+status: U32, sidecar: String, current: Nat, remaining: Nat) -> IO(State):
  next_state_requested(U32.is_eq(status, 75), status, sidecar, current, remaining)

# Runs the REPL child until it exits or exhausts the bounded restart budget.
def loop(
  fuel: Nat,
  state: State,
  +backend: Cli.Backend,
  +source: String,
  +output: String,
  +memory: String,
  +directory: String,
  +sidecar: String
) -> IO(Unit):
  match fuel state:
    case _ Finished{status}: Runtime.finish_status(status)
    case 0n Launch{_}: IO.die(Unit, 70, "too many thread restarts in one session")
    case 1n+ +rest Launch{+count}:
      do IO<Unit>:
        _clear : Unit <- clear_sidecar(sidecar)
        status : U32 <- Runtime.run_backend(backend, source, output, count, memory, directory)
        next : State <- next_state(status, sidecar, count, rest)
        loop(rest, next, backend, source, output, memory, directory, sidecar)

# Resolves REPL settings, builds its entry point, and starts the restart loop.
def launch(+root: String, directory_arg: Maybe<&2, String>) -> IO(Unit):
  do IO<Unit>:
    configured : String <- IO.try(String, Console.get_env("MYLSM_DIR"))
    +directory : String = resolve_directory(directory_arg, configured)
    device : Cli.Device <- Runtime.requested_device()
    count : Nat <- Runtime.threads()
    memory_env : String <- IO.try(String, Console.get_env("MYLSM_GPU_MEMORY"))
    +source : String = root ++ "/app/repl/repl.bend"
    +output : String = root ++ "/.mylsm/bin/mylsm-repl"
    built : Bool <- Runtime.build_native(root, source, output, root ++ "/.mylsm/log/mylsm-repl-build.log")
    artifact : Bool <- IO.try(Bool, Fs.exists(output ++ ".gpu"))
    backend : Cli.Backend <- Runtime.choose_backend(device, built, artifact)
    loop(8n, Launch{count}, backend, source, output, Runtime.env_default(memory_env, "4GB"), directory,
      directory ++ "/.mylsm-restart-threads")

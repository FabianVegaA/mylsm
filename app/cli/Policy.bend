import Base
import ./Types.bend as Cli

# Encloses native runtime settings in Bend's RTS delimiters.
def native_arguments(count: Nat, memory: String) -> List<String>:
  Con{"+RTS", Con{"--threads", Con{Nat.show(count), Con{"--gpu", Con{memory, Con{"-RTS", Nil{}}}}}}}

# Rejects an empty explicit directory and stores a valid REPL directory.
def parse_repl_directory(directory: String, empty: Bool) -> Result<&1, &1, String, Cli.Command>:
  match empty:
    case True{}: Fail{"REPL directory cannot be empty"}
    case False{}: Done{Cli.Repl{Some{directory}}}

# Parses the supported REPL directory option.
def parse_repl(args: List<String>) -> Result<&1, &1, String, Cli.Command>:
  match args:
    case Nil{}: Done{Cli.Repl{None{}}}
    case Con{"--dir", Con{+directory, Nil{}}}:
      parse_repl_directory(directory, String.is_empty(directory))
    case _: Fail{"usage: mylsm repl [--dir PATH]"}

# Maps a named CLI command and its arguments to a command value.
def parse_named(command: String, args: List<String>) -> Result<&1, &1, String, Cli.Command>:
  match command args:
    case "demo" Nil{}: Done{Cli.Demo{}}
    case "doctor" Nil{}: Done{Cli.Doctor{}}
    case "check" Nil{}: Done{Cli.Check{}}
    case "fuzz" Nil{}: Done{Cli.Fuzz{}}
    case "bench" Nil{}: Done{Cli.Bench{}}
    case "build" Nil{}: Done{Cli.Build{}}
    case "run" Nil{}: Done{Cli.Run{}}
    case "--help" Nil{}: Done{Cli.Help{}}
    case "-h" Nil{}: Done{Cli.Help{}}
    case _ _: Fail{"unknown command: " ++ command}

# Selects the default command or parses the first command argument.
def parse_args(args: List<String>) -> Result<&1, &1, String, Cli.Command>:
  match args:
    case Nil{}: Done{Cli.Demo{}}
    case Con{"repl", rest}: parse_repl(rest)
    case Con{command, rest}: parse_named(command, rest)

# Parses the requested automatic, CPU, or GPU device policy.
def parse_device(value: String) -> Result<&1, &1, String, Cli.Device>:
  match value:
    case "": Done{Cli.Auto{}}
    case "auto": Done{Cli.Auto{}}
    case "cpu": Done{Cli.Cpu{}}
    case "gpu": Done{Cli.Gpu{}}
    case _: Fail{"MYLSM_DEVICE must be auto, cpu, or gpu"}

# Checks whether a thread count is within the supported range.
def in_thread_bounds(count: Nat) -> Bool:
  match count:
    case 0n: False{}
    case 1n+rest: Nat.is_lt(count, 257n)

# Returns a validated thread count or its policy error.
def validate_threads_result(count: Nat, valid: Bool) -> Result<&1, &1, String, Nat>:
  match valid:
    case True{}: Done{count}
    case False{}: Fail{"MYLSM_THREADS must be between 1 and 256"}

# Rejects thread counts outside the supported range.
def validate_threads(+count: Nat) -> Result<&1, &1, String, Nat>:
  validate_threads_result(count, in_thread_bounds(count))

# Rejects malformed thread values and validates parsed counts.
def parsed_threads(value: String, count: Maybe<&2, Nat>) -> Result<&1, &1, String, Nat>:
  match count:
    case None{}: Fail{"invalid MYLSM_THREADS: " ++ value}
    case Some{count}: validate_threads(count)

# Uses the detected CPU count when no override is supplied.
def parse_threads(+value: String, detected: Nat) -> Result<&1, &1, String, Nat>:
  match value:
    case SNil{}: validate_threads(detected)
    case _: parsed_threads(value, Nat.read(value))

# Reports whether backend selection needs a GPU capability probe.
def needs_gpu_probe(device: Cli.Device) -> Bool:
  match device:
    case Cli.Cpu{}: False{}
    case _: True{}

# Selects a backend or rejects an unavailable requested GPU path.
def select_backend(
  device: Cli.Device,
  native_built: Bool,
  gpu_detected: Bool,
  gpu_artifact: Bool
) -> Result<&1, &1, String, Cli.Backend>:
  match device native_built gpu_detected gpu_artifact:
    case Cli.Cpu{} False{} _ _: Done{Cli.PortableCpu{}}
    case Cli.Cpu{} True{} _ _: Done{Cli.NativeCpu{}}
    case Cli.Auto{} False{} _ _: Done{Cli.PortableCpu{}}
    case Cli.Auto{} True{} True{} True{}: Done{Cli.NativeGpu{}}
    case Cli.Auto{} True{} _ _: Done{Cli.NativeCpu{}}
    case Cli.Gpu{} _ False{} _: Fail{"GPU requested but no supported GPU was detected"}
    case Cli.Gpu{} False{} True{} _: Fail{"GPU requested but native Bend build failed"}
    case Cli.Gpu{} True{} True{} False{}: Fail{"GPU artifact missing"}
    case Cli.Gpu{} True{} True{} True{}: Done{Cli.NativeGpu{}}

# Validates restart count bounds and rejects redundant restarts.
def checked_restart_count(count: Nat, valid: Bool, same: Bool) -> Result<&1, &1, String, Maybe<&2, Nat>>:
  match valid same:
    case False{} _: Fail{"thread restart must be 1..256"}
    case True{} True{}: Fail{"refusing a redundant thread restart"}
    case True{} False{}: Done{Some{count}}

# Parses and validates the requested restart thread count.
def checked_restart_value(value: Maybe<&2, Nat>, current: Nat) -> Result<&1, &1, String, Maybe<&2, Nat>>:
  match value:
    case None{}: Fail{"invalid thread restart request"}
    case Some{+count}: checked_restart_count(count, in_thread_bounds(count), Nat.is_eq(count, current))

# Requires a sidecar and remaining restart budget before restarting.
def checked_restart(
  sidecar: Maybe<&2, String>,
  current: Nat,
  remaining: Nat
) -> Result<&1, &1, String, Maybe<&2, Nat>>:
  match sidecar remaining:
    case _ 0n: Fail{"too many thread restarts in one session"}
    case None{} 1n+rest: Fail{"restart requested without a sidecar"}
    case Some{value} 1n+rest:
      checked_restart_value(Nat.read(value), current)

# Applies restart policy only when the child requests a restart.
def restart_threads_checked(
  requested: Bool,
  sidecar: Maybe<&2, String>,
  current: Nat,
  remaining: Nat
) -> Result<&1, &1, String, Maybe<&2, Nat>>:
  match requested:
    case False{}: Done{None{}}
    case True{}: checked_restart(sidecar, current, remaining)

# Interprets the child exit status as a possible thread restart request.
def restart_threads(
  status: U32,
  sidecar: Maybe<&2, String>,
  current: Nat,
  remaining: Nat
) -> Result<&1, &1, String, Maybe<&2, Nat>>:
  restart_threads_checked(U32.is_eq(status, 75), sidecar, current, remaining)

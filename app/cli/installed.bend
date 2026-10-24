import Base
import ./Types.bend as Cli
import ./InstalledPolicy.bend as Policy
import ./Runtime.bend as Runtime
import ./ReplLauncher.bend as ReplLauncher
import ../../src/Console.bend as Console

# Lists commands and environment settings supported by the installed package.
def usage() -> String:
  "MyLSM\n\nUsage: mylsm [demo | repl [--dir PATH] | doctor | --help]\n\n" ++
  "Environment: MYLSM_DEVICE=auto|cpu, MYLSM_THREADS=1..256, MYLSM_BATCH_CAP=1..1024, MYLSM_DIR=PATH"

# Converts device-policy errors into CLI exit status 2.
def device_result(result: Result<&1, &1, String, Unit>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit, 2, message)
    case Done{value}: IO.pure(Unit, value)

# Validates the requested device before starting a database process.
def require_cpu() -> IO(Unit):
  do IO<Unit>:
    device : Cli.Device <- Runtime.requested_device()
    device_result(Policy.device_supported(device))

# Reports host and CPU settings without requiring a compiler or Bend.
def doctor() -> IO(Unit):
  do IO<Unit>:
    os : Maybe<&2, String> <- Runtime.probe("uname", Con{"-s", Nil{}}, 1024)
    arch : Maybe<&2, String> <- Runtime.probe("uname", Con{"-m", Nil{}}, 1024)
    count : Nat <- Runtime.threads()
    _a : Unit <- IO.print("MyLSM")
    _b : Unit <- IO.print("  OS/arch: " ++ Runtime.probe_or(os, "unknown") ++ "/" ++ Runtime.probe_or(arch, "unknown"))
    _c : Unit <- IO.print("  CPU threads: " ++ Nat.show(count))
    IO.print("  storage=cpu/io")

# Runs the precompiled demo with validated CPU settings.
def run_demo(root: String) -> IO(Unit):
  do IO<Unit>:
    _device : Unit <- require_cpu()
    count : Nat <- Runtime.threads()
    status : U32 <- Runtime.run_backend(Cli.NativeCpu{}, "", root ++ "/mylsm-demo", count, "off", "")
    Runtime.finish_status(status)

# Starts the precompiled REPL under the bounded restart supervisor.
def run_repl(root: String, directory_arg: Maybe<&2, String>) -> IO(Unit):
  do IO<Unit>:
    _device : Unit <- require_cpu()
    configured : String <- IO.try(String, Console.get_env("MYLSM_DIR"))
    +directory : String = ReplLauncher.resolve_directory(directory_arg, configured)
    count : Nat <- Runtime.threads()
    ReplLauncher.loop(8n, ReplLauncher.Launch{count}, Cli.NativeCpu{}, "", root ++ "/mylsm-repl", "off", directory,
      directory ++ "/.mylsm-restart-threads")

# Routes installed commands to their owning execution path.
def dispatch(command: Cli.Command, root: String) -> IO(Unit):
  match command:
    case Cli.Demo{}: run_demo(root)
    case Cli.Repl{directory}: run_repl(root, directory)
    case Cli.Doctor{}: doctor()
    case Cli.Help{}: IO.print(usage())
    case _: IO.die(Unit, 2, "command requires the development checkout")

# Rejects parse errors before dispatching an installed command.
def command_result(result: Result<&1, &1, String, Cli.Command>, root: String) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit, 2, message)
    case Done{command}: dispatch(command, root)

# Removes the executable name from native argument input.
def arguments(args: List<String>) -> List<String>:
  match args:
    case Nil{}: Nil{}
    case Con{_, rest}: rest

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    root : String <- IO.try(String, Console.get_env("MYLSM_PACKAGE_ROOT"))
    command_result(Policy.parse_args(arguments(args)), root)

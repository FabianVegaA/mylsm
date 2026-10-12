import Base
import ./Types.bend as Cli
import ./Policy.bend as Policy
import ./Attached.bend as Attached
import ./Runtime.bend as Runtime
import ./Runner.bend as Runner
import ./ReplLauncher.bend as ReplLauncher
import ../../src/Fs.bend as Fs
import ../../src/Flush.bend as Flush
import ../../src/Console.bend as Console

# Returns the CLI usage and supported environment settings.
def usage() -> String:
  "MyLSM developer CLI\n\nUsage: scripts/mylsm.sh [command]\n\n" ++
  "Commands: demo, repl [--dir PATH], doctor, check, fuzz, bench, build, run, --help\n\n" ++
  "Environment: MYLSM_DEVICE=auto|cpu|gpu, MYLSM_THREADS=1..256, MYLSM_BATCH_CAP=1..1024, MYLSM_GPU_MEMORY=SIZE, MYLSM_DIR=PATH"

# Runs the selected command through its owning CLI module.
def dispatch(command: Cli.Command, root: String) -> IO(Unit):
  match command:
    case Cli.Demo{}: Runner.run_demo(root)
    case Cli.Repl{directory}: ReplLauncher.launch(root, directory)
    case Cli.Doctor{}: Runtime.doctor()
    case Cli.Check{}: Runner.run_check(root)
    case Cli.Fuzz{}: Runner.run_bend_file(root ++ "/bench/workload/fuzz.bend")
    case Cli.Bench{}: Runner.run_bend_file(root ++ "/bench/smoke/bench.bend")
    case Cli.Build{}: Runner.run_build(root)
    case Cli.Run{}: Runner.run_existing(root)
    case Cli.Help{}: IO.print(usage())

# Reports parse errors or dispatches a validated command.
def command_result(result: Result<&1, &1, String, Cli.Command>, root: String) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit, 2, message)
    case Done{Cli.Help{}}: IO.print(usage())
    case Done{command}: dispatch(command, root)

# Drops Bend launcher arguments before parsing user command arguments.
def arguments(args: List<String>) -> List<String>:
  match args:
    case Nil{}: Nil{}
    case Con{_, rest}: rest

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    root : String <- IO.try(String, Console.get_env("MYLSM_ROOT"))
    command_result(Policy.parse_args(arguments(args)), root)

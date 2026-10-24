import Base
import ./Types.bend as Cli
import ./Policy.bend as Policy

# Preserves supported commands while rejecting development-only commands.
def filter_command(command: Cli.Command) -> Result<&1, &1, String, Cli.Command>:
  match command:
    case Cli.Demo{}: Done{Cli.Demo{}}
    case Cli.Repl{directory}: Done{Cli.Repl{directory}}
    case Cli.Doctor{}: Done{Cli.Doctor{}}
    case Cli.Help{}: Done{Cli.Help{}}
    case _: Fail{"command requires the development checkout"}

# Preserves parse failures before validating installation command availability.
def checked_command(result: Result<&1, &1, String, Cli.Command>) -> Result<&1, &1, String, Cli.Command>:
  match result:
    case Fail{message}: Fail{message}
    case Done{command}: filter_command(command)

# Parses and restricts the installed CLI's command set.
def parse_args(args: List<String>) -> Result<&1, &1, String, Cli.Command>:
  checked_command(Policy.parse_args(args))

# Accepts automatic or CPU policy for the CPU-only package.
def device_supported(device: Cli.Device) -> Result<&1, &1, String, Unit>:
  match device:
    case Cli.Gpu{}: Fail{"this package supports CPU execution only"}
    case _: Done{Unit{}}

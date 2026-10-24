import Base
import ../app/cli/Types.bend as Cli
import ../app/cli/InstalledPolicy.bend as Policy

# The installed CLI preserves user commands and rejects development commands.
law installed_command_boundary:
  for +directory: Maybe<&2, String>
  {List.map(Cli.Command, Result<&1, &1, String, Cli.Command>, Policy.filter_command,
    [Cli.Demo{}, Cli.Repl{directory}, Cli.Doctor{}, Cli.Help{}, Cli.Check{}, Cli.Fuzz{}, Cli.Bench{}, Cli.Build{}, Cli.Run{}]) ==
    [Done{Cli.Demo{}}, Done{Cli.Repl{directory}}, Done{Cli.Doctor{}}, Done{Cli.Help{}},
    Fail{"command requires the development checkout"}, Fail{"command requires the development checkout"},
    Fail{"command requires the development checkout"}, Fail{"command requires the development checkout"},
    Fail{"command requires the development checkout"}] : List<Result<&1, &1, String, Cli.Command>>}

# The installed package accepts CPU policies and rejects explicit GPU requests.
law installed_device_boundary:
  {List.map(Cli.Device, Result<&1, &1, String, Unit>, Policy.device_supported, [Cli.Auto{}, Cli.Cpu{}, Cli.Gpu{}]) ==
    [Done{Unit{}}, Done{Unit{}}, Fail{"this package supports CPU execution only"}] : List<Result<&1, &1, String, Unit>>}

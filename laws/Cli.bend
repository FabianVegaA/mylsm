import Base
import ../app/cli/Types.bend as Cli
import ../app/cli/Policy.bend as Policy

# Native runtime settings are enclosed by Bend's RTS delimiters.
law native_runtime_arguments:
  for +count: Nat
  for +memory: String
  {Policy.native_arguments(count, memory) ==
    Con{"+RTS", Con{"--threads", Con{Nat.show(count), Con{"--gpu", Con{memory, Con{"-RTS", Nil{}}}}}}} : List<String>}

# The CLI selects the demo when no command is supplied.
law default_command:
  {Policy.parse_args(Nil{}) == Done{Cli.Demo{}} : Result<&1, &1, String, Cli.Command>}

# The parser recognizes the explicit demo command.
law demo_command:
  {Policy.parse_args(Con{"demo", Nil{}}) == Done{Cli.Demo{}} : Result<&1, &1, String, Cli.Command>}

# The parser recognizes runtime diagnostics.
law doctor_command:
  {Policy.parse_args(Con{"doctor", Nil{}}) == Done{Cli.Doctor{}} : Result<&1, &1, String, Cli.Command>}

# The parser recognizes the repository proof command.
law check_command:
  {Policy.parse_args(Con{"check", Nil{}}) == Done{Cli.Check{}} : Result<&1, &1, String, Cli.Command>}

# The parser recognizes the fuzz command.
law fuzz_command:
  {Policy.parse_args(Con{"fuzz", Nil{}}) == Done{Cli.Fuzz{}} : Result<&1, &1, String, Cli.Command>}

# The parser recognizes the benchmark command.
law bench_command:
  {Policy.parse_args(Con{"bench", Nil{}}) == Done{Cli.Bench{}} : Result<&1, &1, String, Cli.Command>}

# The parser recognizes the native build command.
law build_command:
  {Policy.parse_args(Con{"build", Nil{}}) == Done{Cli.Build{}} : Result<&1, &1, String, Cli.Command>}

# The parser recognizes the existing-binary run command.
law run_command:
  {Policy.parse_args(Con{"run", Nil{}}) == Done{Cli.Run{}} : Result<&1, &1, String, Cli.Command>}

# The parser recognizes long-form help.
law help_command:
  {Policy.parse_args(Con{"--help", Nil{}}) == Done{Cli.Help{}} : Result<&1, &1, String, Cli.Command>}

# The parser recognizes short-form help.
law short_help_command:
  {Policy.parse_args(Con{"-h", Nil{}}) == Done{Cli.Help{}} : Result<&1, &1, String, Cli.Command>}

# The REPL parser preserves an explicit directory argument.
law repl_directory:
  {Policy.parse_args(Con{"repl", Con{"--dir", Con{"data", Nil{}}}}) == Done{Cli.Repl{Some{"data"}}} : Result<&1, &1, String, Cli.Command>}

# The REPL parser leaves its directory unset when omitted.
law repl_default_directory:
  {Policy.parse_args(Con{"repl", Nil{}}) == Done{Cli.Repl{None{}}} : Result<&1, &1, String, Cli.Command>}

# The REPL parser rejects an explicit empty directory.
law empty_directory_rejected:
  {Policy.parse_args(Con{"repl", Con{"--dir", Con{"", Nil{}}}}) == Fail{"REPL directory cannot be empty"} : Result<&1, &1, String, Cli.Command>}

# The CLI parser rejects unrecognized commands.
law unknown_command_rejected:
  {Policy.parse_args(Con{"unknown", Nil{}}) == Fail{"unknown command: unknown"} : Result<&1, &1, String, Cli.Command>}

# Thread policy rejects zero workers.
law zero_threads_rejected:
  {Policy.parse_threads("0", 8n) == Fail{"MYLSM_THREADS must be between 1 and 256"} : Result<&1, &1, String, Nat>}

# Thread policy accepts its upper supported bound.
law max_threads_accepted:
  {Policy.parse_threads("256", 8n) == Done{256n} : Result<&1, &1, String, Nat>}

# Thread policy rejects counts above its upper bound.
law excessive_threads_rejected:
  {Policy.parse_threads("257", 8n) == Fail{"MYLSM_THREADS must be between 1 and 256"} : Result<&1, &1, String, Nat>}

# Thread policy rejects a nonnumeric override.
law malformed_threads_rejected:
  {Policy.parse_threads("2x", 8n) == Fail{"invalid MYLSM_THREADS: 2x"} : Result<&1, &1, String, Nat>}

# Device policy rejects unsupported values.
law unsupported_device_rejected:
  {Policy.parse_device("accelerator") == Fail{"MYLSM_DEVICE must be auto, cpu, or gpu"} : Result<&1, &1, String, Cli.Device>}

# CPU mode does not require a GPU capability probe.
law cpu_skips_gpu_probe:
  {Policy.needs_gpu_probe(Cli.Cpu{}) == False{} : Bool}

# Automatic mode checks GPU capability before backend selection.
law auto_checks_gpu:
  {Policy.needs_gpu_probe(Cli.Auto{}) == True{} : Bool}

# CPU mode uses the portable backend when native compilation fails.
law cpu_falls_back:
  {Policy.select_backend(Cli.Cpu{}, False{}, False{}, False{}) == Done{Cli.PortableCpu{}} : Result<&1, &1, String, Cli.Backend>}

# Automatic mode uses the portable backend when native compilation fails.
law auto_falls_back:
  {Policy.select_backend(Cli.Auto{}, False{}, True{}, False{}) == Done{Cli.PortableCpu{}} : Result<&1, &1, String, Cli.Backend>}

# GPU mode rejects a build without a GPU artifact.
law gpu_requires_artifact:
  {Policy.select_backend(Cli.Gpu{}, True{}, True{}, False{}) == Fail{"GPU artifact missing"} : Result<&1, &1, String, Cli.Backend>}

# GPU mode rejects a host without a supported GPU.
law gpu_requires_device:
  {Policy.select_backend(Cli.Gpu{}, True{}, False{}, True{}) == Fail{"GPU requested but no supported GPU was detected"} : Result<&1, &1, String, Cli.Backend>}

# A restart exit status requires a valid sidecar request.
law restart_requires_sidecar:
  {Policy.restart_threads(75, None{}, 8n, 7n) == Fail{"restart requested without a sidecar"} : Result<&1, &1, String, Maybe<&2, Nat>>}

# A valid sidecar requests a new thread count.
law restart_changes_threads:
  {Policy.restart_threads(75, Some{"4"}, 8n, 7n) == Done{Some{4n}} : Result<&1, &1, String, Maybe<&2, Nat>>}

# A restart request cannot repeat the active thread count.
law restart_redundant_count_rejected:
  {Policy.restart_threads(75, Some{"8"}, 8n, 7n) == Fail{"refusing a redundant thread restart"} : Result<&1, &1, String, Maybe<&2, Nat>>}

# A child exit without the restart status does not trigger a restart.
law ordinary_exit_skips_restart:
  {Policy.restart_threads(0, Some{"4"}, 8n, 7n) == Done{None{}} : Result<&1, &1, String, Maybe<&2, Nat>>}

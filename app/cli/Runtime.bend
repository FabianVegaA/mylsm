import Base
import ./Types.bend as Cli
import ./Policy.bend as Policy
import ./Attached.bend as Attached
import ../../src/Fs.bend as Fs
import ../../src/Console.bend as Console

# Uses the fallback only when an environment value is empty.
def env_default(value: String, fallback: String) -> String:
  match value:
    case SNil{}: fallback
    case _: value

# Keeps probe output only when the child exits successfully.
def probe_status(ok: Bool, output: String) -> Maybe<&2, String>:
  match ok:
    case True{}: Some{String.trim(output)}
    case False{}: None{}

# Converts a bounded process result into optional probe output.
def probe_result(result: Result<&1, &1, U32 & String, U32 & (String & String)>) -> Maybe<&2, String>:
  match result:
    case Fail{_}: None{}
    case Done{(status, (output, _))}: probe_status(U32.is_eq(status, 0), output)

# Runs a bounded, timed capability probe through Bend Base.
def probe(program: String, args: List<String>, limit: U32) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    result : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run(program, args, "", limit, 30000)
    return probe_result(result)

# Supplies a fallback when a capability probe has no result.
def probe_or(value: Maybe<&2, String>, fallback: String) -> String:
  match value:
    case None{}: fallback
    case Some{text}: text

# Parses an optional CPU-count probe result.
def cpu_value(value: Maybe<&2, String>) -> Maybe<&2, Nat>:
  match value:
    case None{}: None{}
    case Some{text}: Nat.read(text)

# Uses a fallback CPU count when parsing produced no value.
def cpu_or(value: Maybe<&2, Nat>, fallback: Nat) -> Nat:
  match value:
    case None{}: fallback
    case Some{count}: count

# Falls back to nproc when the primary CPU-count probe fails.
def logical_cpus_fallback(first: Maybe<&2, Nat>) -> IO(Nat):
  match first:
    case Some{count}: IO.pure(Nat, count)
    case None{}:
      do IO<Nat>:
        second : Maybe<&2, String> <- probe("nproc", Nil{}, 1024)
        return cpu_or(cpu_value(second), 1n)

# Detects the host logical CPU count using available system probes.
def logical_cpus() -> IO(Nat):
  do IO<Nat>:
    first : Maybe<&2, String> <- probe("sysctl", Con{"-n", Con{"hw.logicalcpu", Nil{}}}, 1024)
    logical_cpus_fallback(cpu_value(first))

# Turns thread validation into a CLI error or accepted count.
def thread_result(result: Result<&1, &1, String, Nat>) -> IO(Nat):
  match result:
    case Done{count}: IO.pure(Nat, count)
    case Fail{message}: IO.die(Nat, 2, message)

# Reads and validates the configured thread count.
def threads() -> IO(Nat):
  do IO<Nat>:
    value : String <- IO.try(String, Console.get_env("MYLSM_THREADS"))
    detected : Nat <- logical_cpus()
    thread_result(Policy.parse_threads(value, detected))

# Recognizes Metal in macOS display-probe output.
def gpu_metal(value: Maybe<&2, String>) -> Bool:
  match value:
    case None{}: False{}
    case Some{text}: String.contains(text, "Metal")

# Treats successful probe output as evidence of a supported GPU.
def gpu_present(value: Maybe<&2, String>) -> Bool:
  match value:
    case None{}: False{}
    case Some{_}: True{}

# Runs the GPU probe appropriate to the host operating system.
def gpu_from_os(os: String) -> IO(Bool):
  match os:
    case "Darwin":
      do IO<Bool>:
        result : Maybe<&2, String> <- probe("system_profiler", Con{"SPDisplaysDataType", Nil{}}, 65536)
        return gpu_metal(result)
    case "Linux":
      do IO<Bool>:
        result : Maybe<&2, String> <- probe("nvidia-smi", Nil{}, 65536)
        return gpu_present(result)
    case _: IO.pure(Bool, False{})

# Detects GPU capability from the host operating-system name.
def has_gpu() -> IO(Bool):
  do IO<Bool>:
    os : Maybe<&2, String> <- probe("uname", Con{"-s", Nil{}}, 1024)
    gpu_from_os(probe_or(os, "unknown"))

# Formats GPU detection status for the doctor report.
def gpu_name(detected: Bool) -> String:
  match detected:
    case True{}: "detected"
    case False{}: "unavailable or unverified"

# Formats native compiler availability for the doctor report.
def compiler_name(value: Maybe<&2, String>) -> String:
  match value:
    case Some{_}: "available"
    case None{}: "unavailable"

# Reports Bend, host, CPU, GPU, compiler, and device-policy information.
def doctor() -> IO(Unit):
  do IO<Unit>:
    version : Maybe<&2, String> <- probe("bend", Con{"version", Nil{}}, 1024)
    os : Maybe<&2, String> <- probe("uname", Con{"-s", Nil{}}, 1024)
    arch : Maybe<&2, String> <- probe("uname", Con{"-m", Nil{}}, 1024)
    count : Nat <- threads()
    gpu : Bool <- has_gpu()
    compiler : Maybe<&2, String> <- probe("clang", Con{"--version", Nil{}}, 8192)
    device : String <- IO.try(String, Console.get_env("MYLSM_DEVICE"))
    _a : Unit <- IO.print("MyLSM runtime")
    _b : Unit <- IO.print("  Bend: " ++ probe_or(version, "unknown"))
    _c : Unit <- IO.print("  OS/arch: " ++ probe_or(os, "unknown") ++ "/" ++ probe_or(arch, "unknown"))
    _d : Unit <- IO.print("  CPU threads: " ++ Nat.show(count))
    _e : Unit <- IO.print("  GPU: " ++ gpu_name(gpu))
    _f : Unit <- IO.print("  native compiler: " ++ compiler_name(compiler))
    IO.print("  policy: " ++ env_default(device, "auto"))

# Creates a directory only when it does not already exist.
def ensure_existing(exists: Bool, path: String) -> IO(Unit):
  match exists:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.try(Unit, Fs.make_dir(path))

# Checks for a directory path and creates it when absent.
def ensure_dir(+path: String) -> IO(Unit):
  do IO<Unit>:
    exists : Bool <- IO.try(Bool, Fs.exists(path))
    ensure_existing(exists, path)

# Creates the private artifact and log directories under the project root.
def ensure_build_dirs(+root: String) -> IO(Unit):
  do IO<Unit>:
    _a : Unit <- ensure_dir(root ++ "/.mylsm")
    _b : Unit <- ensure_dir(root ++ "/.mylsm/bin")
    ensure_dir(root ++ "/.mylsm/log")

# Converts a native build result into a success flag.
def build_status(result: Result<&1, &1, U32 & String, U32>) -> Bool:
  match result:
    case Fail{_}: False{}
    case Done{status}: U32.is_eq(status, 0)

# Builds a Bend entry point and redirects build output to its log.
def build_native(root: String, source: String, output: String, log: String) -> IO(Bool):
  do IO<Bool>:
    _dirs : Unit <- ensure_build_dirs(root)
    result : Result<&1, &1, U32 & String, U32> <- Attached.run(
      "bend", Con{source, Con{"-o", Con{output, Nil{}}}}, Nil{}, Some{log})
    return build_status(result)

# Returns a parsed device policy or exits with its validation error.
def device_result(result: Result<&1, &1, String, Cli.Device>) -> IO(Cli.Device):
  match result:
    case Done{device}: IO.pure(Cli.Device, device)
    case Fail{message}: IO.die(Cli.Device, 2, message)

# Reads and parses the configured device policy.
def requested_device() -> IO(Cli.Device):
  do IO<Cli.Device>:
    value : String <- IO.try(String, Console.get_env("MYLSM_DEVICE"))
    device_result(Policy.parse_device(value))

# Returns a selected backend or exits with its policy error.
def backend_result(result: Result<&1, &1, String, Cli.Backend>) -> IO(Cli.Backend):
  match result:
    case Done{backend}: IO.pure(Cli.Backend, backend)
    case Fail{message}: IO.die(Cli.Backend, 3, message)

# Runs GPU detection only when backend policy requires it.
def gpu_for_device(needs_probe: Bool) -> IO(Bool):
  match needs_probe:
    case False{}: IO.pure(Bool, False{})
    case True{}: has_gpu()

# Selects a backend using only the capability probes required by policy.
def choose_backend_with_probe(device: Cli.Device, needs_probe: Bool, built: Bool, artifact: Bool) -> IO(Cli.Backend):
  do IO<Cli.Backend>:
    detected : Bool <- gpu_for_device(needs_probe)
    backend_result(Policy.select_backend(device, built, detected, artifact))

# Avoids GPU probing for CPU mode and delegates other modes to policy.
def choose_backend(device: Cli.Device, built: Bool, artifact: Bool) -> IO(Cli.Backend):
  match device:
    case Cli.Cpu{}:
      choose_backend_with_probe(Cli.Cpu{}, Policy.needs_gpu_probe(Cli.Cpu{}), built, artifact)
    case Cli.Auto{}:
      choose_backend_with_probe(Cli.Auto{}, Policy.needs_gpu_probe(Cli.Auto{}), built, artifact)
    case Cli.Gpu{}:
      choose_backend_with_probe(Cli.Gpu{}, Policy.needs_gpu_probe(Cli.Gpu{}), built, artifact)

# Builds the runtime environment required by the selected backend.
def effective_env(backend: Cli.Backend, count: Nat, directory: String) -> List<(String & String)>:
  match backend:
    case Cli.PortableCpu{}:
      Con{("MYLSM_DIR", directory), Con{("MYLSM_THREADS", Nat.show(count)),
      Con{("MYLSM_RUNTIME", "portable"), Con{("MYLSM_EFFECTIVE_DEVICE", "cpu"), Con{("MYLSM_GPU_ENABLED", "0"), Nil{}}}}}}
    case Cli.NativeCpu{}:
      Con{("MYLSM_DIR", directory), Con{("MYLSM_THREADS", Nat.show(count)),
      Con{("MYLSM_RUNTIME", "native"), Con{("MYLSM_EFFECTIVE_DEVICE", "cpu"), Con{("MYLSM_GPU_ENABLED", "0"), Nil{}}}}}}
    case Cli.NativeGpu{}:
      Con{("MYLSM_DIR", directory), Con{("MYLSM_THREADS", Nat.show(count)),
      Con{("MYLSM_RUNTIME", "native"), Con{("MYLSM_EFFECTIVE_DEVICE", "gpu"), Con{("MYLSM_GPU_ENABLED", "1"), Nil{}}}}}}

# Runs the selected portable or native backend with its effective settings.
def run_backend(
  backend: Cli.Backend,
  source: String,
  output: String,
  +count: Nat,
  memory: String,
  directory: String
) -> IO(U32):
  match backend:
    case Cli.PortableCpu{}:
      IO.try(U32, Attached.run("bend", Con{source, Nil{}}, effective_env(Cli.PortableCpu{}, count, directory), None{}))
    case Cli.NativeCpu{}:
      IO.try(U32, Attached.run(output, Con{"--threads", Con{Nat.show(count), Nil{}}},
        effective_env(Cli.NativeCpu{}, count, directory), None{}))
    case Cli.NativeGpu{}:
      IO.try(U32, Attached.run(output, Con{"--threads", Con{Nat.show(count), Con{"--gpu", Con{memory, Nil{}}}}},
        effective_env(Cli.NativeGpu{}, count, directory), None{}))

# Returns on child success and propagates a nonzero child status.
def finish_status_result(ok: Bool, status: U32) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, status, "child process failed")

# Converts the final child status into CLI success or failure.
def finish_status(+status: U32) -> IO(Unit):
  finish_status_result(U32.is_eq(status, 0), status)

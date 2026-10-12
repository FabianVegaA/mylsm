import Base
import ./Types.bend as Cli
import ./Runtime.bend as Runtime
import ./Attached.bend as Attached
import ../../src/Fs.bend as Fs
import ../../src/Console.bend as Console

# Runs the repository proof suite and propagates its exit status.
def run_check(root: String) -> IO(Unit):
  do IO<Unit>:
    status : U32 <- IO.try(U32, Attached.run(root ++ "/proofs/run.sh", Nil{}, Nil{}, None{}))
    Runtime.finish_status(status)

# Runs a Bend file and propagates its exit status.
def run_bend_file(path: String) -> IO(Unit):
  do IO<Unit>:
    status : U32 <- IO.try(U32, Attached.run("bend", Con{path, Nil{}}, Nil{}, None{}))
    Runtime.finish_status(status)

# Returns on native build success and reports a failed build otherwise.
def build_finish(built: Bool) -> IO(Unit):
  match built:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "native Bend build failed")

# Builds the demo entry point into the private binary directory.
def run_build(+root: String) -> IO(Unit):
  do IO<Unit>:
    built : Bool <- Runtime.build_native(root, root ++ "/app/demo/mylsm_demo.bend", root ++ "/.mylsm/bin/mylsm-demo",
      root ++ "/.mylsm/log/mylsm-demo-build.log")
    build_finish(built)

# Builds the demo, selects its backend, and runs it.
def run_demo(+root: String) -> IO(Unit):
  do IO<Unit>:
    device : Cli.Device <- Runtime.requested_device()
    count : Nat <- Runtime.threads()
    memory_env : String <- IO.try(String, Console.get_env("MYLSM_GPU_MEMORY"))
    +source : String = root ++ "/app/demo/mylsm_demo.bend"
    +output : String = root ++ "/.mylsm/bin/mylsm-demo"
    built : Bool <- Runtime.build_native(root, source, output, root ++ "/.mylsm/log/mylsm-demo-build.log")
    artifact : Bool <- IO.try(Bool, Fs.exists(output ++ ".gpu"))
    backend : Cli.Backend <- Runtime.choose_backend(device, built, artifact)
    status : U32 <- Runtime.run_backend(backend, source, output, count, Runtime.env_default(memory_env, "4GB"), "")
    Runtime.finish_status(status)

# Runs an existing native demo or the portable Bend source.
def run_existing_choice(exists: Bool, +root: String) -> IO(Unit):
  match exists:
    case False{}: run_bend_file(root ++ "/app/demo/mylsm_demo.bend")
    case True{}:
      do IO<Unit>:
        count : Nat <- Runtime.threads()
        status : U32 <- Runtime.run_backend(Cli.NativeCpu{}, root ++ "/app/demo/mylsm_demo.bend",
          root ++ "/.mylsm/bin/mylsm-demo", count, "4GB", "")
        Runtime.finish_status(status)

# Checks for a previously built demo before choosing its run path.
def run_existing(+root: String) -> IO(Unit):
  do IO<Unit>:
    exists : Bool <- IO.try(Bool, Fs.exists(root ++ "/.mylsm/bin/mylsm-demo"))
    run_existing_choice(exists, root)

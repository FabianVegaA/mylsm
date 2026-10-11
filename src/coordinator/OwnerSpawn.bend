import Base
import ./SpawnPolicy.bend as Policy

# Starts the already validated owner argument vector without a shell.
def owner_spawn(argv: List<String>) -> IO(Result<&1, &1, U32 & String, Nat>):
  import "../effs/owner_spawn.c"
  import "../effs/owner_spawn.js"

# Dispatches only validated vectors to the native process operation.
def launch.result(
  decision: Policy.Decision
) -> IO(Result<&1, &1, U32 & String, Nat>):
  match decision:
    case Policy.SpawnReady{argv}: owner_spawn(argv)
    case Policy.SpawnInvalid{}:
      IO.pure(Result<&1, &1, U32 & String, Nat>,
        Fail{(22, "invalid owner process command")})

# Validates the executable and arguments before starting the owner.
def launch(
  program: String,
  arguments: List<String>
) -> IO(Result<&1, &1, U32 & String, Nat>):
  launch.result(Policy.prepare(program, arguments))

import Base
import ./Console.bend as Console

# Pure checkpoint policy. Console.get_env maps an unset value to "", so the
# non-empty guard distinguishes disabled injection from an exact empty match.
def nonempty(value: String) -> Bool:
  match value:
    case SNil{}: False{}
    case SCon{_, _}: True{}

def enabled(+configured: String, requested: String) -> Bool:
  Bool.and(nonempty(configured), String.eq(configured, requested))

# Irreducible host boundary: emit an unbuffered marker and stop this process.
def stop(name: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  import "./effs/crash_point.c"
  import "./effs/crash_point.js"

def hit_decision(active: Bool, name: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  match active:
    case True{}:
      stop(name)
    case False{}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Done{Unit{}})

# Test-only checkpoint. Environment lookup and activation policy stay in Bend;
# only marker emission and SIGSTOP remain in the host twins.
def hit(+name: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  do IO<Result<&1, &1, U32 & String, Unit>>:
    configured : String <- IO.try(String, Console.get_env("MYLSM_CRASH_POINT"))
    hit_decision(enabled(configured, name), name)

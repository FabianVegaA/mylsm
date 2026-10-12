import Base
import ../../app/cli/Attached.bend as Attached
import ../../src/Flush.bend as Flush

# Fails the smoke test when a child exits with a nonzero status.
def expect_zero_status(ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "attached child returned nonzero")

# Checks that an attached child operation completed successfully.
def expect_zero(result: Result<&1, &1, U32 & String, U32>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "attached child failed")
    case Done{status}: expect_zero_status(U32.is_eq(status, 0))

# Fails the fixture unless the child status matches the expected value.
def expect_seven_status(ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "attached child status mismatch")

# Requires oversized probe output to be rejected at the configured bound.
def expect_limit(result: Result<&1, &1, U32 & String, U32 & (String & String)>) -> IO(Unit):
  match result:
    case Fail{_}: IO.pure(Unit, Unit{})
    case Done{_}: IO.die(Unit, 1, "bounded process output was not limited")

# Checks that the attached child preserves a nonzero exit status.
def expect_status_seven(result: Result<&1, &1, U32 & String, U32>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "attached child failed")
    case Done{status}: expect_seven_status(U32.is_eq(status, 7))

# Checks that launching a missing executable returns an error.
def expect_missing(result: Result<&1, &1, U32 & String, U32>) -> IO(Unit):
  match result:
    case Fail{_}: IO.pure(Unit, Unit{})
    case Done{_}: IO.die(Unit, 1, "missing child unexpectedly ran")

# Fails the smoke test when redirected child output differs.
def expect_log(ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "attached child log mismatch")

def main() -> IO(Unit):
  do IO<Unit>:
    child : Result<&1, &1, U32 & String, U32> <- Attached.run(
      "/bin/sh", Con{"-c", Con{"read line; test \"$line\" = hello && test \"$MYLSM_CHILD_TEST\" = works", Nil{}}},
      Con{("MYLSM_CHILD_TEST", "works"), Nil{}}, None{})
    _child : Unit <- expect_zero(child)
    captured : Result<&1, &1, U32 & String, U32 & (String & String)> <-
      Process.run("printf", Con{"abcdef", Nil{}}, "", 3, 30000)
    _captured : Unit <- expect_limit(captured)
    nonzero : Result<&1, &1, U32 & String, U32> <- Attached.run(
      "/bin/sh", Con{"-c", Con{"exit 7", Nil{}}}, Nil{}, None{})
    _nonzero : Unit <- expect_status_seven(nonzero)
    logged : Result<&1, &1, U32 & String, U32> <- Attached.run(
      "/bin/echo", Con{"a b", Nil{}}, Nil{}, Some{".mylsm-cli-attached.log"})
    _logged : Unit <- expect_zero(logged)
    output : String <- IO.try(String, Flush.read_file(".mylsm-cli-attached.log"))
    _output : Unit <- expect_log(String.eq(output, "a b\n"))
    missing : Result<&1, &1, U32 & String, U32> <- Attached.run(
      "/no/such/mylsm-cli-program", Nil{}, Nil{}, None{})
    _missing : Unit <- expect_missing(missing)
    IO.print("CLI ATTACHED OK")

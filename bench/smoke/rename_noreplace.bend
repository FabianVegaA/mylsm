import Base
import ../../src/Console.bend as Console
import ../../src/Fs.bend as Fs

def verify.existing(result: Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.die(Unit, 1, "rename replaced an existing destination")
    case Fail{_}: IO.pure(Unit, Unit{})


def verify.moved(result: Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match result:
    case Fail{(code, message)}: IO.die(Unit, code, message)
    case Done{Unit{}}: IO.print("RENAME_NOREPLACE_PASSED")

def main() -> IO(Unit):
  do IO<Unit>:
    source : String <- IO.try(String, Console.get_env("MYLSM_RENAME_SOURCE"))
    source_again : String <- IO.try(String, Console.get_env("MYLSM_RENAME_SOURCE_AGAIN"))
    existing : String <- IO.try(String, Console.get_env("MYLSM_RENAME_EXISTING"))
    final : String <- IO.try(String, Console.get_env("MYLSM_RENAME_FINAL"))
    rejected : Result<&1, &1, U32 & String, Unit> <- Fs.rename_noreplace(source, existing)
    verify.existing(rejected)
    moved : Result<&1, &1, U32 & String, Unit> <- Fs.rename_noreplace(source_again, final)
    verify.moved(moved)

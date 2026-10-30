import Base
import ../../mylsm.bend as MyLSM
import ../../src/Console.bend as Console
import ../../src/ResourceOptions.bend as ResourceOptions

def path.clone.pair.go(path: String, left: String,
  right: String) -> String & String:
  match path:
    case SNil{}: (String.reverse(left), String.reverse(right))
    case SCon{+character, rest}:
      path.clone.pair.go(rest, SCon{character, left},
        SCon{character, right})

def path.clone.pair(path: String) -> String & String:
  path.clone.pair.go(path, SNil{}, SNil{})

def custom.options() -> ResourceOptions.Options:
  ResourceOptions.Options{
    ResourceOptions.TransportLimits{64, 16777216, 16777216, 16777216,
      30000, 30000},
    ResourceOptions.QueueLimits{64, 16777216, 30000},
    ResourceOptions.ReaderLimits{32, 4096, 64, 67108864, 64,
      16384, 65536, 67108864}}

# Handles fail.
def fail(message: String) -> IO(Unit):
  IO.die(Unit, 1, message)

# Handles finish.
def finish(result: Result<&1, &1, MyLSM.Bytes.Error, Unit>,
  message: String) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.print(message)
    case Fail{_}: fail("owner options handle close failed")

def implicit.closed(result: Result<&1, &1, MyLSM.Bytes.Error, Unit>) -> IO(Unit):
  finish(result, "OWNER_OPTIONS_PASSED")

def implicit.opened(
  result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>
) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        implicit.closed(closed)
    case Fail{_}: fail("implicit owner options handshake failed")

def mismatch.checked(
  path: String,
  result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>
) -> IO(Unit):
  match result:
    case Fail{MyLSM.InvalidArgument{}}:
      do IO<Unit>:
        opened : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
          MyLSM.Bytes.open_existing(path)
        implicit.opened(opened)
    case Done{handle}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        fail("owner accepted an explicit options mismatch")
    case Fail{_}: fail("owner mismatch returned the wrong error")

def explicit.closed.paths(paths: String & String) -> IO(Unit):
  match paths:
    case (mismatch_path, retained_path):
      do IO<Unit>:
        opened : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
          MyLSM.Bytes.open_existing_with_options(mismatch_path,
            ResourceOptions.defaults())
        mismatch.checked(retained_path, opened)

def explicit.closed(
  path: String,
  result: Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match result:
    case Done{Unit{}}: explicit.closed.paths(path.clone.pair(path))
    case Fail{_}: fail("owner options handle close failed")

def explicit.opened(
  path: String,
  result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>
) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        explicit.closed(path, closed)
    case Fail{_}: fail("owner rejected matching explicit options")

def owner.mode.paths(paths: String & String) -> IO(Unit):
  match paths:
    case (options_path, retained_path):
      do IO<Unit>:
        opened : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
          MyLSM.Bytes.open_existing_with_options(options_path,
            custom.options())
        explicit.opened(retained_path, opened)

def local.explicit.checked(
  path: String,
  result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>
) -> IO(Unit):
  match result:
    case Fail{MyLSM.InvalidArgument{}}:
      do IO<Unit>:
        opened : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
          MyLSM.Bytes.open_existing(path)
        implicit.opened(opened)
    case Done{handle}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        fail("local open accepted unsupported custom options")
    case Fail{_}: fail("local custom options returned the wrong error")

def local.mode.paths(paths: String & String) -> IO(Unit):
  match paths:
    case (options_path, retained_path):
      do IO<Unit>:
        opened : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
          MyLSM.Bytes.open_existing_with_options(options_path,
            custom.options())
        local.explicit.checked(retained_path, opened)

def run.mode(mode: String, path: String) -> IO(Unit):
  match mode:
    case "owner": owner.mode.paths(path.clone.pair(path))
    case "absent": local.mode.paths(path.clone.pair(path))
    case _: fail("unknown owner options test mode")

def main() -> IO(Unit):
  do IO<Unit>:
    mode : String <- IO.try(String, Console.get_env("MYLSM_OPTIONS_MODE"))
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    run.mode(mode, path)

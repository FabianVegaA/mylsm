import Base
import ../../mylsm.bend as MyLSM
import ../../src/Console.bend as Console
import ../../src/coordinator/OwnerSpawn.bend as OwnerSpawn
import ../../src/Fs.bend as Fs

# Recognizes completed child evidence while preserving the retry case.
def marker.state(clear_exists: Bool, inherited_exists: Bool) -> Maybe<&1, Bool>:
  match clear_exists:
    case True{}:
      match inherited_exists:
        case False{}: Some{True{}}
        case True{}: Some{False{}}
    case False{}:
      match inherited_exists:
        case False{}: None{}
        case True{}: Some{False{}}

# Chooses completed child evidence or the bounded polling continuation.
def marker.state.result(state: Maybe<&1, Bool>, retry: IO(Bool)) -> IO(Bool):
  match state:
    case Some{answer}: IO.pure(Bool, answer)
    case None{}: retry

def path.clone.pair.go(path: String, left: String, right: String) -> String & String:
  match path:
    case SNil{}: (String.reverse(left), String.reverse(right))
    case SCon{+character, rest}:
      path.clone.pair.go(rest, SCon{character, left}, SCon{character, right})

def path.clone.pair(path: String) -> String & String:
  path.clone.pair.go(path, SNil{}, SNil{})

# Polls child evidence until it reports whether the LOCK descriptor was inherited.
def marker.poll(
  fuel: Nat,
  clear_paths: String & String,
  inherited_paths: String & String
) -> IO(Bool):
  match fuel:
    case 0n: IO.die(Bool, 1, "spawn child did not publish descriptor evidence")
    case 1n+rest:
      match clear_paths:
        case (clear_check, clear_retry):
          match inherited_paths:
            case (inherited_check, inherited_retry):
              IO.bind(Bool, Bool, IO.try(Bool, Fs.exists(clear_check)),
                clear_exists =>
                  IO.bind(Bool, Bool, IO.try(Bool, Fs.exists(inherited_check)),
                    inherited_exists =>
                      IO.bind(Maybe<&1, Bool>, Bool,
                        IO.pure(Maybe<&1, Bool>,
                          marker.state(clear_exists, inherited_exists)),
                        state => marker.state.result(state,
                          IO.bind(Unit, Bool, IO.sleep(10),
                            _ => marker.poll(rest,
                              path.clone.pair(clear_retry),
                              path.clone.pair(inherited_retry)))))))

# Reopens the database while the spawned child is still alive.
def reopened(result: Result<&1, &1, MyLSM.Error, MyLSM.Handle>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "closing the parent did not release its database lock")
    case Done{handle}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.print("OWNER_SPAWN_LOCK_PASSED")

# Rejects inherited ownership and confirms that close released the database lock.
def child.evidence(
  has_no_lock_fd: Bool,
  database_path: String
) -> IO(Unit):
  match has_no_lock_fd:
    case False{}:
      IO.die(Unit, 1, "spawn child inherited the database LOCK descriptor")
    case True{}:
      do IO<Unit>:
        result : Result<&1, &1, MyLSM.Error, MyLSM.Handle> <-
          MyLSM.open_existing(database_path)
        reopened(result)

# Checks descriptor evidence while the child remains alive after parent close.
def child.started(
  handle: MyLSM.Handle,
  result: Result<&1, &1, U32 & String, Nat>,
  database_path: String,
  clear_path: String,
  inherited_path: String
) -> IO(Unit):
  match result:
    case Fail{_}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, 1, "could not start the descriptor-checking child")
    case Done{_}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        evidence : Bool <- marker.poll(100n, path.clone.pair(clear_path),
          path.clone.pair(inherited_path))
        child.evidence(evidence, database_path)

# Starts a child that checks inherited descriptors and then remains alive briefly.
def created(
  result: Result<&1, &1, MyLSM.Error, MyLSM.Handle>,
  database_path: String,
  child_database_path: String,
  clear_argument: String,
  inherited_argument: String,
  clear_check: String,
  inherited_check: String
) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "could not create the owner-spawn fixture database")
    case Done{handle}:
      do IO<Unit>:
        spawned : Result<&1, &1, U32 & String, Nat> <- OwnerSpawn.launch(
          "/usr/bin/python3",
          Con{"-c", Con{
            "import os,sys,time; p,a,b=sys.argv[1:4]; s=os.stat(p); " ++
            "q=os.path.realpath(p+'/LOCK'); " ++
            "x=any(os.path.realpath('/dev/fd/'+n)==q for n in os.listdir('/dev/fd') if int(n)>2); " ++
            "open(b if x else a,'w').write('x'); time.sleep(1)",
            Con{child_database_path,
              Con{clear_argument, Con{inherited_argument, Nil{}}}}}})
        child.started(handle, spawned, database_path, clear_check, inherited_check)

def main() -> IO(Unit):
  do IO<Unit>:
    database_path : String <- IO.try(String, Console.get_env("MYLSM_SPAWN_DB"))
    child_database_path : String <- IO.try(String, Console.get_env("MYLSM_SPAWN_DB"))
    reopen_path : String <- IO.try(String, Console.get_env("MYLSM_SPAWN_DB"))
    clear_argument : String <- IO.try(String, Console.get_env("MYLSM_SPAWN_CLEAR"))
    inherited_argument : String <- IO.try(String, Console.get_env("MYLSM_SPAWN_INHERITED"))
    clear_check : String <- IO.try(String, Console.get_env("MYLSM_SPAWN_CLEAR"))
    inherited_check : String <- IO.try(String, Console.get_env("MYLSM_SPAWN_INHERITED"))
    result : Result<&1, &1, MyLSM.Error, MyLSM.Handle> <- MyLSM.create(database_path)
    created(result, reopen_path, child_database_path, clear_argument,
      inherited_argument, clear_check, inherited_check)

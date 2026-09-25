import Base
import ../src/Console.bend as Console
import ../src/Db.bend as Db
import ../src/Recover.bend as Recover
import ./repl_types.bend as Repl
import ./repl_parser.bend as Parser
import ./repl_exec.bend as Exec

def env_default(value: String, fallback: String) -> String:
  match value:
    case SNil{}: fallback
    case SCon{h, t}: SCon{h, t}

def env_gpu(value: String) -> Bool:
  match value:
    case SCon{'1', SNil{}}: True{}
    case _: False{}

def env_mode(value: String) -> Repl.ComputeMode:
  match value:
    case SCon{'g', SCon{'p', SCon{'u', SNil{}}}}: Repl.Gpu{}
    case SCon{'c', SCon{'p', SCon{'u', SNil{}}}}: Repl.Cpu{}
    case _: Repl.Auto{}

def nat_default(value: Maybe<&2, Nat>) -> Nat:
  match value:
    case None{}: 1n
    case Some{n}: n

def batch_clamp(count: Nat) -> Nat:
  Nat.max(1n, Nat.min(count, 1024n))

def repl_loop(commands: Nat, state: Exec.LoopState) -> IO(Unit):
  match commands state:
    case 0n _:
      IO.print("session command limit reached")
    case 1n+rest Exec.Stopped{}:
      IO.pure(Unit, Unit{})
    case 1n+rest Exec.Running{session}:
      do IO<Unit>:
        _u : Unit <- IO.print("mylsm>")
        line : String <- IO.try(String, Console.read_line())
        next : Exec.LoopState <- Exec.run_command(Parser.parse_command(line), session)
        repl_loop(rest, next)

def main() -> IO(Unit):
  do IO<Unit>:
    dir_env : String <- IO.try(String, Console.get_env("MYLSM_DIR"))
    mode_env : String <- IO.try(String, Console.get_env("MYLSM_EFFECTIVE_DEVICE"))
    gpu_env : String <- IO.try(String, Console.get_env("MYLSM_GPU_ENABLED"))
    workers_env : String <- IO.try(String, Console.get_env("MYLSM_THREADS"))
    batch_env : String <- IO.try(String, Console.get_env("MYLSM_BATCH_CAP"))
    +dir : String <- IO.pure(String, env_default(dir_env, ".mylsm-repl-data"))
    db : Db.Db <- IO.try(Db.Db, Recover.open_db(dir))
    +capped : Db.Db <- IO.pure(Db.Db, Db.with_batch_cap(db, batch_clamp(nat_default(Nat.read(batch_env)))))
    _u0 : Unit <- IO.print("MyLSM REPL")
    _u1 : Unit <- IO.print("database=" ++ dir)
    repl_loop(256n, Exec.Running{Exec.Session{capped, dir, Repl.TimingOff{}, env_mode(mode_env), env_gpu(gpu_env), nat_default(Nat.read(workers_env)), Nil{}}})

import Base

# Audited host effects (spec §3.3). Thin syscall wrappers with .c + .js
# twins and matching intended semantics. No laws — validated empirically.

def fsync(path: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  import "./effs/fsync.c"
  import "./effs/fsync.js"

def rename(old: String, new: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  import "./effs/rename.c"
  import "./effs/rename.js"

def remove(path: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  import "./effs/remove.c"
  import "./effs/remove.js"

def read_dir_count(path: String) -> IO(Result<&1, &1, U32 & String, Nat>):
  import "./effs/read_dir.c"
  import "./effs/read_dir.js"

def read_dir_at(path: String, i: Nat) -> IO(Result<&1, &1, U32 & String, String>):
  import "./effs/read_dir.c"
  import "./effs/read_dir.js"

def make_dir(path: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  import "./effs/make_dir.c"
  import "./effs/make_dir.js"

def chmod(path: String, bits: U32) -> IO(Result<&1, &1, U32 & String, Unit>):
  import "./effs/chmod.c"
  import "./effs/chmod.js"

def exists(path: String) -> IO(Result<&1, &1, U32 & String, Bool>):
  import "./effs/exists.c"
  import "./effs/exists.js"

# Pure accumulator step (leaf: matches structurally, never recurses).
# Past-end fetches answer "" (SNil{}), which is skipped.

def grab_name(nm: String, acc: List<String>) -> List<String>:
  match nm:
    case SNil{}:
      acc
    case SCon{_, _}:
      Con{nm, acc}

# Fuel-bounded sweep 0..count-1. Startup-only use (spec §10 below): the
# directory is stable during recovery, so count-then-fetch is exact.

def read_go(fuel: Nat, +path: String, +i: Nat, acc: List<String>) -> IO(List<String>):
  match fuel:
    case 0n:
      IO.pure(List<String>, List.reverse(&1, String, acc))
    case 1n+f:
      do IO<List<String>>:
        nm : String <- IO.try(String, read_dir_at(path, i))
        read_go(f, path, Nat.add(i, 1n), grab_name(nm, acc))

def read_dir(+path: String) -> IO(Result<&1, &1, U32 & String, List<String>>):
  do IO<Result<&1, &1, U32 & String, List<String>>>:
    n : Nat <- IO.try(Nat, read_dir_count(path))
    names : List<String> <- read_go(Nat.add(n, 1n), path, 0n, Nil{})
    return Done{names}

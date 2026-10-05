import Base
import bend-kit-bytes@0.3.2.0/bytes.bend as StorageBytes
import 0x6c54b2522c2258baf6f58d2b970c3902/files.bend as PackedFiles

# Audited host effects (spec §3.3). Thin syscall wrappers with .c + .js
# twins and matching intended semantics. No laws — validated empirically.

# Read at most 1 MiB as packed words. Short reads are valid progress; zero is EOF.
def read_words(
  file: File,
  max: U32
) ->
  IO(File & Result<&1, &1, U32 & String, U32 & Array<U32>>):
  PackedFiles.read.words(file, max)

# Write all bytes from a packed word array, retaining the file handle on errors.
def write_words(
  file: File,
  len: U32,
  words: Array<U32>
) ->
  IO(File & Result<&1, &1, U32 & String, Unit>):
  PackedFiles.write.words(file, len, words)

def read_bytes.wrap(
  result: Result<&1, &1, U32 & String, U32 & Array<U32>>
) ->
  Result<&1, &1, U32 & String, StorageBytes.Bytes>:
  match result:
    case Fail{err}:
      Fail{err}
    case Done{(len, words)}:
      Done{StorageBytes.Bytes{len, words}}

def read_bytes.pair(
  pair: File & Result<&1, &1, U32 & String, U32 & Array<U32>>
) ->
  File & Result<&1, &1, U32 & String, StorageBytes.Bytes>:
  match pair:
    case (handle, result):
      (handle, read_bytes.wrap(result))

# Read one bounded packed chunk; nonempty short reads are not EOF.
def read_bytes(
  file: File,
  max: U32
) ->
  IO(File & Result<&1, &1, U32 & String, StorageBytes.Bytes>):
  do IO<File & Result<&1, &1, U32 & String, StorageBytes.Bytes>>:
    pair : File & Result<&1, &1, U32 & String, U32 & Array<U32>> <- read_words(file, max)
    return read_bytes.pair(pair)

# Write the significant bytes of a packed buffer through the pinned host effect.
def write_bytes(
  file: File,
  bytes: StorageBytes.Bytes
) ->
  IO(File & Result<&1, &1, U32 & String, Unit>):
  StorageBytes.Bytes{len, buf} = bytes
  write_words(file, len, buf)

# Sync file contents to stable storage.
def fsync(path: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  import "./effs/fsync.c"
  import "./effs/fsync.js"

# Handle truncate in the filesystem effects.
def truncate(path: String, offset: Nat) -> IO(Result<&1, &1, U32 & String, Unit>):
  import "./effs/truncate.c"
  import "./effs/truncate.js"

# Atomically rename a filesystem path.
def rename(old: String, new: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  import "./effs/rename.c"
  import "./effs/rename.js"

# Remove a file or empty directory.
def remove(path: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  import "./effs/remove.c"
  import "./effs/remove.js"

# Return the number of entries available through the indexed directory API.
def read_dir_count(path: String) -> IO(Result<&1, &1, U32 & String, Nat>):
  import "./effs/read_dir.c"
  import "./effs/read_dir.js"

# Fetch one directory entry by index.
def read_dir_at(path: String, idx: Nat) -> IO(Result<&1, &1, U32 & String, String>):
  import "./effs/read_dir.c"
  import "./effs/read_dir.js"

# Create one directory.
def make_dir(path: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  import "./effs/make_dir.c"
  import "./effs/make_dir.js"

# Set POSIX permission bits.
def chmod(path: String, bits: U32) -> IO(Result<&1, &1, U32 & String, Unit>):
  import "./effs/chmod.c"
  import "./effs/chmod.js"

# Check whether a filesystem path exists.
def exists(path: String) -> IO(Result<&1, &1, U32 & String, Bool>):
  import "./effs/exists.c"
  import "./effs/exists.js"

# Read-only byte size for Bend-side accounting (no shell wc needed).
def file_size(path: String) -> IO(Result<&1, &1, U32 & String, Nat>):
  import "./effs/file_size.c"
  import "./effs/file_size.js"

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
def read_go(fuel: Nat, +path: String, +idx: Nat, acc: List<String>) -> IO(List<String>):
  match fuel:
    case 0n:
      IO.pure(List<String>, List.reverse(&1, String, acc))
    case 1n+f:
      do IO<List<String>>:
        nm : String <- IO.try(String, read_dir_at(path, idx))
        read_go(f, path, Nat.add(idx, 1n), grab_name(nm, acc))

# List directory names using the bounded count-then-fetch host API.
def read_dir(+path: String) -> IO(Result<&1, &1, U32 & String, List<String>>):
  do IO<Result<&1, &1, U32 & String, List<String>>>:
    n : Nat <- IO.try(Nat, read_dir_count(path))
    names : List<String> <- read_go(Nat.add(n, 1n), path, 0n, Nil{})
    return Done{names}

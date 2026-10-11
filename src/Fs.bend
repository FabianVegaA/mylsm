import Base
import bend-kit-bytes@0.3.2.0/bytes.bend as StorageBytes
import ./FilesCompat.bend as PackedFiles
import ./FsPolicy.bend as Policy
import ./coordinator/QueuePolicy.bend as QueuePolicy
import ./ReadAtPolicy.bend as ReadAtPolicy

# Audited host effects (spec §3.3). Thin syscall wrappers with .c + .js
# twins and matching intended semantics. No laws — validated empirically.

# Read at most 1 MiB as packed words. Short reads are valid progress; zero is EOF.
def read_words(
  file: File,
  max: U32
) ->
  IO(File & Result<&1, &1, U32 & String, U32 & Array<U32>>):
  PackedFiles.read.words(file, max)

# Tracks each bounded write syscall and its terminal outcome.
type WriteWordsState is Type:
  WriteWordsNeed{file: File, offsets: U32 & U32,
    remaining: U32 & U32, words: Array<U32>, empty: Bool}
  WriteWordsFailed{file: File, error: U32 & String}
  WriteWordsNoProgress{file: File}

def u32.clone.pair.result(copies: Nat & Nat) -> U32 & U32:
  match copies:
    case (first, second): (U32.from_nat(first), U32.from_nat(second))

def u32.clone.pair(value: U32) -> U32 & U32:
  u32.clone.pair.result(QueuePolicy.nat.clone.pair(U32.to_nat(value)))

def u32.clone.triple.finish(
  first: U32,
  copies: U32 & U32
) -> U32 & (U32 & U32):
  match copies:
    case (second, third): (first, (second, third))

def u32.clone.triple.first(pair: U32 & U32) -> U32 & (U32 & U32):
  match pair:
    case (first, rest):
      u32.clone.triple.finish(first, u32.clone.pair(rest))

def u32.clone.triple(value: U32) -> U32 & (U32 & U32):
  u32.clone.triple.first(u32.clone.pair(value))

def write_words.state.remaining.copied(
  file: File,
  for_write_offset: U32,
  for_read_offset: U32,
  remaining: U32 & (U32 & U32),
  words: Array<U32>
) -> WriteWordsState:
  match remaining:
    case (for_write, (for_read, for_empty)):
      WriteWordsNeed{file, (for_write_offset, for_read_offset),
        (for_write, for_read), words, U32.is_zero(for_empty)}


def write_words.state.remaining(
  file: File,
  offsets: U32 & U32,
  remaining: U32 & (U32 & U32),
  words: Array<U32>
) -> WriteWordsState:
  match offsets:
    case (for_write_offset, for_read_offset):
      write_words.state.remaining.copied(file, for_write_offset,
        for_read_offset, remaining, words)

def write_words.state(
  file: File,
  offset: U32,
  remaining: U32,
  words: Array<U32>
) -> WriteWordsState:
  write_words.state.remaining(file, u32.clone.pair(offset),
    u32.clone.triple(remaining), words)

def write_words.after.choose(
  file: File,
  offset: U32,
  remaining: U32,
  words: Array<U32>,
  no_progress: Bool
) -> WriteWordsState:
  match no_progress:
    case True{}: WriteWordsNoProgress{file}
    case False{}: write_words.state(file, offset, remaining, words)

def write_words.after.checked(
  file: File,
  offset: U32,
  remaining: U32,
  copies: U32 & (U32 & U32),
  words: Array<U32>
) -> WriteWordsState:
  match copies:
    case (for_offset, (for_subtract, for_zero)):
      write_words.after.choose(
        file, U32.add(offset, for_offset), U32.sub(remaining, for_subtract),
        words, U32.is_zero(for_zero))

def write_words.after(
  pair: File & Result<&1, &1, U32 & String, U32 & Array<U32>>,
  offset: U32,
  remaining: U32
) -> WriteWordsState:
  match pair:
    case (file, Fail{error}): WriteWordsFailed{file, error}
    case (file, Done{(written, words)}):
      write_words.after.checked(file, offset, remaining,
        u32.clone.triple(written), words)

def write_words.loop(
  fuel: Nat,
  state: WriteWordsState
) ->
  IO(File & Result<&1, &1, U32 & String, Unit>):
  match fuel:
    case 0n:
      match state:
        case WriteWordsNeed{file, _, _, _, empty}:
          match empty:
            case True{}:
              IO.pure(File & Result<&1, &1, U32 & String, Unit>,
                (file, Done{Unit{}}))
            case False{}:
              IO.pure(File & Result<&1, &1, U32 & String, Unit>,
                (file, Fail{(7, "write ran out of bounded progress steps")}))
        case WriteWordsFailed{file, error}:
          IO.pure(File & Result<&1, &1, U32 & String, Unit>,
            (file, Fail{error}))
        case WriteWordsNoProgress{file}:
          IO.pure(File & Result<&1, &1, U32 & String, Unit>,
            (file, Fail{(5, "write made no progress")}))
    case 1n+rest:
      match state:
        case WriteWordsNeed{file, (for_write_offset, for_read_offset),
            (for_write, for_read), words, empty}:
          match empty:
            case True{}:
              IO.pure(File & Result<&1, &1, U32 & String, Unit>,
                (file, Done{Unit{}}))
            case False{}:
              do IO<File & Result<&1, &1, U32 & String, Unit>>:
                pair : File & Result<&1, &1, U32 & String, U32 & Array<U32>> <-
                  PackedFiles.write.words.once(file, for_write_offset,
                    U32.min(65536, for_write), words)
                write_words.loop(rest,
                  write_words.after(pair, for_read_offset, for_read))
        case WriteWordsFailed{file, error}:
          IO.pure(File & Result<&1, &1, U32 & String, Unit>,
            (file, Fail{error}))
        case WriteWordsNoProgress{file}:
          IO.pure(File & Result<&1, &1, U32 & String, Unit>,
            (file, Fail{(5, "write made no progress")}))

# Writes one packed buffer through bounded single-syscall steps.
def write_words(
  file: File,
  len: U32,
  words: Array<U32>
) ->
  IO(File & Result<&1, &1, U32 & String, Unit>):
  write_words.loop(4294967295n,
    write_words.state(file, 0, len, words))

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

def read_at.pack.finish(offset: U32, result: StorageBytes.Bytes) -> StorageBytes.Bytes:
  match result:
    case StorageBytes.Bytes{_, buf}:
      StorageBytes.Bytes{offset, buf}

def read_at.nat.clone.step(pair: Nat & Nat) -> Nat & Nat:
  match pair:
    case (left, right): (Nat.add(1n, left), Nat.add(1n, right))

def read_at.nat.clone(+value: Nat) -> Nat & Nat:
  (Nat.mul(1n, value), Nat.mul(1n, value))

def read_at.nat.clone.triple(+value: Nat) -> Nat & Nat & Nat:
  (Nat.mul(1n, value), Nat.mul(1n, value), Nat.mul(1n, value))

def read_at.pack.go(
  fuel: Nat,
  values: List<&2, U32>,
  result: StorageBytes.Bytes,
  +offset: U32
) -> StorageBytes.Bytes:
  match fuel:
    case 0n: read_at.pack.finish(offset, result)
    case 1n+rest:
      match values:
        case Nil{}: read_at.pack.finish(offset, result)
        case Con{value, tail}:
          read_at.pack.go(rest, tail,
            StorageBytes.set(result, offset, value), (offset + 1 : U32))

def read_at.pack.buffer.length(
  values: List<&2, U32>,
  lengths: Nat & Nat,
  buf: Array<U32>
) -> StorageBytes.Bytes:
  match lengths:
    case (fuel, capacity):
      read_at.pack.go(fuel, values,
        StorageBytes.Bytes{U32.from_nat(capacity), buf}, 0)

def read_at.pack.buffer(
  values: List<&2, U32>,
  buffer: StorageBytes.Bytes
) -> StorageBytes.Bytes:
  match buffer:
    case StorageBytes.Bytes{len, buf}:
      read_at.pack.buffer.length(values, read_at.nat.clone(U32.to_nat(len)), buf)

def read_at.pack(max: U32, values: List<&2, U32>) -> StorageBytes.Bytes:
  read_at.pack.buffer(values, StorageBytes.new(max))

# Retains the file and bounded positional-read progress between host calls.
type ReadAtState is Type:
  ReadAtNeed{file: File, offset: Nat, remaining: Nat,
    chunks: List<&1, StorageBytes.Bytes>}
  ReadAtRead{pair: File & Result<&1, &1, U32 & String, List<&2, U32>>,
    offset: Nat, remaining: Nat,
    chunks: List<&1, StorageBytes.Bytes>}
  ReadAtPacked{file: File, offset: Nat, remaining: Nat,
    chunks: List<&1, StorageBytes.Bytes>, buffer: StorageBytes.Bytes}

def read_at.finish(
  file: File,
  chunks: List<&1, StorageBytes.Bytes>
) -> IO(File & Result<&1, &1, U32 & String, StorageBytes.Bytes>):
  IO.pure(File & Result<&1, &1, U32 & String, StorageBytes.Bytes>,
    (file, Done{StorageBytes.concat(
      List.reverse(&1, StorageBytes.Bytes, chunks))}))

# Returns an explicit error if bounded progress unexpectedly runs out.
def read_at.exhausted(
  state: ReadAtState
) -> IO(
  File & Result<&1, &1, U32 & String, StorageBytes.Bytes>
):
  match state:
    case ReadAtNeed{file, _, _, _}:
      IO.pure(File & Result<&1, &1, U32 & String, StorageBytes.Bytes>,
        (file, Fail{(7, "positional read exhausted its progress budget")}))
    case ReadAtRead{pair, _, _, _}:
      match pair:
        case (file, _):
          IO.pure(File & Result<&1, &1, U32 & String, StorageBytes.Bytes>,
            (file, Fail{(7, "positional read exhausted its progress budget")}))
    case ReadAtPacked{file, _, _, _, _}:
      IO.pure(File & Result<&1, &1, U32 & String, StorageBytes.Bytes>,
        (file, Fail{(7, "positional read exhausted its progress budget")}))

# Assembles a positional read from bounded chunks without moving the file cursor.
def read_at.loop(
  fuel: Nat,
  state: ReadAtState
) -> IO(
  File & Result<&1, &1, U32 & String, StorageBytes.Bytes>
):
  match fuel:
    case 0n: read_at.exhausted(state)
    case 1n+rest:
      match state:
        case ReadAtNeed{file, +offset, +remaining, chunks}:
          match remaining:
            case 0n: read_at.finish(file, chunks)
            case 1n+_:
              do IO<File & Result<&1, &1, U32 & String, StorageBytes.Bytes>>:
                pair : File & Result<&1, &1, U32 & String, List<&2, U32>> <-
                  File.read_at(file, U32.from_nat(offset),
                    U32.from_nat(Nat.min(8192n, remaining)))
                read_at.loop(rest,
                  ReadAtRead{pair, offset, remaining, chunks})
        case ReadAtRead{pair, offset, +remaining, chunks}:
          match pair:
            case (file, Fail{error}):
              IO.pure(File & Result<&1, &1, U32 & String, StorageBytes.Bytes>,
                (file, Fail{error}))
            case (file, Done{Nil{}}): read_at.finish(file, chunks)
            case (file, Done{values}):
              read_at.loop(rest, ReadAtPacked{file, offset, remaining,
                chunks, read_at.pack(8192, values)})
        case ReadAtPacked{file, offset, +remaining, chunks, buffer}:
          match buffer:
            case StorageBytes.Bytes{+len, buf}:
              read_at.loop(rest, ReadAtNeed{file,
                Nat.add(offset, U32.to_nat(len)),
                Nat.sub(remaining, U32.to_nat(len)),
                Con{StorageBytes.Bytes{len, buf}, chunks}})

def read_at.range.valid(offset: Nat, max: Nat) -> Bool:
  ReadAtPolicy.range_valid(Nat.add(4294967295n, 1n), offset, max)

def read_at.start.validated(
  file: File,
  offset: Nat,
  maxima: Nat & Nat,
  valid: Bool
) -> IO(File & Result<&1, &1, U32 & String, StorageBytes.Bytes>):
  match maxima:
    case (for_fuel, for_remaining):
      match valid:
        case False{}:
          IO.pure(File & Result<&1, &1, U32 & String, StorageBytes.Bytes>,
            (file, Fail{(22, "positional read range exceeds offset limits")}))
        case True{}:
          read_at.loop(Nat.add(Nat.mul(3n, for_fuel), 3n),
            ReadAtNeed{file, offset, for_remaining, Nil{}})

def read_at.start(
  file: File,
  offsets: Nat & Nat,
  maxima: Nat & Nat & Nat
) -> IO(File & Result<&1, &1, U32 & String, StorageBytes.Bytes>):
  match offsets:
    case (offset, checked_offset):
      match maxima:
        case (for_validation, for_fuel, for_remaining):
          read_at.start.validated(file, offset, (for_fuel, for_remaining),
            read_at.range.valid(checked_offset, for_validation))

# Reads bounded bytes at a file offset without changing its current position.
def read_at(
  file: File,
  +offset: U32,
  +max: U32
) -> IO(File & Result<&1, &1, U32 & String, StorageBytes.Bytes>):
  read_at.start(file, read_at.nat.clone(U32.to_nat(offset)),
    read_at.nat.clone.triple(U32.to_nat(max)))

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

# Reads one monotonic clock sample as nanoseconds.
def clock_monotonic() -> IO(Result<&1, &1, U32 & String, Nat>):
  import "./effs/clock_monotonic.c"
  import "./effs/clock_monotonic.js"

# Sleeps once for the requested bounded millisecond duration.
def sleep_ms(milliseconds: U32) -> IO(Result<&1, &1, U32 & String, Unit>):
  import "./effs/sleep.c"
  import "./effs/sleep.js"

# Handle truncate in the filesystem effects.
def truncate(path: String, offset: Nat) -> IO(Result<&1, &1, U32 & String, Unit>):
  import "./effs/truncate.c"
  import "./effs/truncate.js"

# Atomically rename a filesystem path.
def rename(old: String, new: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  PackedFiles.rename(old, new)

# Atomically rename a filesystem path only when the destination is absent.
def rename_noreplace(old: String, new: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  import "./effs/rename_noreplace.c"
  import "./effs/rename_noreplace.js"

# Remove a file or empty directory.
def remove(path: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  PackedFiles.remove(path)

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

# Resolves an existing database path to its filesystem identity.
def canonical_path(path: String) -> IO(Result<&1, &1, U32 & String, String>):
  import "./effs/canonical_path.c"
  import "./effs/canonical_path.js"

# Set POSIX permission bits.
def chmod(path: String, bits: U32) -> IO(Result<&1, &1, U32 & String, Unit>):
  import "./effs/chmod.c"
  import "./effs/chmod.js"

# Check whether a filesystem path exists.
def exists.result(result: Result<&1, &1, U32 & String, PackedFiles.Info>) -> Result<&1, &1, U32 & String, Bool>:
  match result:
    case Fail{(+code, message)}:
      Policy.missing_path_result(U32.is_eq(code, 2), code, message)
    case Done{_}:
      Done{True{}}

# Returns whether a path exists and preserves other stat errors.
def exists(path: String) -> IO(Result<&1, &1, U32 & String, Bool>):
  do IO<Result<&1, &1, U32 & String, Bool>>:
    result : Result<&1, &1, U32 & String, PackedFiles.Info> <- PackedFiles.stat(path)
    return exists.result(result)

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

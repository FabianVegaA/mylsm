import Base
import ../Fs.bend as Fs
import ./OwnerGeneration.bend as Generation
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Separates host failures, corrupt state, and generation exhaustion.
type Error is Data:
  Host{code: U32, message: String}
  Invalid{}
  Exhausted{}

# Preserves the raw filesystem error in the module result type.
def host(error: U32 & String) -> Error:
  match error:
    case (code, message): Host{code, message}

def path.pair.go(path: String, left: String, right: String) -> String & String:
  match path:
    case SNil{}: (String.reverse(left), String.reverse(right))
    case SCon{+character, rest}:
      path.pair.go(rest, SCon{character, left}, SCon{character, right})

def path.pair(path: String) -> String & String:
  path.pair.go(path, SNil{}, SNil{})

def path.triple.go(
  path: String,
  first: String,
  second: String,
  third: String
) -> String & String & String:
  match path:
    case SNil{}:
      (String.reverse(first), (String.reverse(second), String.reverse(third)))
    case SCon{+character, rest}:
      path.triple.go(rest, SCon{character, first}, SCon{character, second},
        SCon{character, third})

def path.triple(path: String) -> String & String & String:
  path.triple.go(path, SNil{}, SNil{}, SNil{})

def decode.nonzero(value: U32, is_zero: Bool) -> Result<&1, &1, Error, U32>:
  match is_zero:
    case True{}: Fail{Invalid{}}
    case False{}: Done{value}

def decode.value(copies: U32 & U32) -> Result<&1, &1, Error, U32>:
  match copies:
    case (value, test): decode.nonzero(value, U32.is_zero(test))

def decode.word(bytes: Bytes.Bytes) -> Result<&1, &1, Error, U32>:
  decode.value(Generation.u32.clone.pair(Generation.u32.read(bytes)))

# Accepts only one nonzero, fixed-width owner generation.
def decode(bytes: Bytes.Bytes, size: Nat) -> Result<&1, &1, Error, U32>:
  match size:
    case 4n: decode.word(bytes)
    case _: Fail{Invalid{}}

def read.bytes(
  file: File,
  result: Result<&1, &1, U32 & String, Bytes.Bytes>
) -> IO(Result<&1, &1, Error, U32>):
  match result:
    case Fail{error}:
      do IO<Result<&1, &1, Error, U32>>:
        _closed : Unit <- File.close(file)
        return Fail{host(error)}
    case Done{bytes}:
      do IO<Result<&1, &1, Error, U32>>:
        _closed : Unit <- File.close(file)
        return decode(bytes, 4n)

def read.pair(
  pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>
) -> IO(Result<&1, &1, Error, U32>):
  match pair:
    case (file, result): read.bytes(file, result)

def read.size(
  file: File,
  result: Result<&1, &1, U32 & String, Nat>
) -> IO(Result<&1, &1, Error, U32>):
  match result:
    case Fail{error}:
      do IO<Result<&1, &1, Error, U32>>:
        _closed : Unit <- File.close(file)
        return Fail{host(error)}
    case Done{4n}:
      do IO<Result<&1, &1, Error, U32>>:
        pair : File & Result<&1, &1, U32 & String, Bytes.Bytes> <-
          Fs.read_at(file, 0, 4)
        read.pair(pair)
    case Done{_}:
      do IO<Result<&1, &1, Error, U32>>:
        _closed : Unit <- File.close(file)
        return Fail{Invalid{}}

def read.opened(
  paths: String & String,
  opened: Result<&1, &1, U32 & String, File>
) -> IO(Result<&1, &1, Error, U32>):
  match paths:
    case (size_path, retained_path):
      match opened:
        case Fail{error}:
          IO.pure(Result<&1, &1, Error, U32>, Fail{host(error)})
        case Done{file}:
          do IO<Result<&1, &1, Error, U32>>:
            size : Result<&1, &1, U32 & String, Nat> <- Fs.file_size(size_path)
            read.size(file, size)

def read.path(paths: String & String) -> IO(Result<&1, &1, Error, U32>):
  match paths:
    case (open_path, retained_path):
      do IO<Result<&1, &1, Error, U32>>:
        opened : Result<&1, &1, U32 & String, File> <- File.open(open_path, "r")
        read.opened(path.pair(retained_path), opened)

# Reads and validates the persisted generation without decoding text.
def read(path: String) -> IO(Result<&1, &1, Error, U32>):
  read.path(path.pair(path))

def write.completed(
  generation: U32,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, Error, U32>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, Error, U32>, Fail{host(error)})
    case Done{Unit{}}:
      IO.pure(Result<&1, &1, Error, U32>, Done{generation})

def write.directory.synced(
  directory: String,
  generation: U32,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, Error, U32>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, Error, U32>, Fail{host(error)})
    case Done{Unit{}}:
      do IO<Result<&1, &1, Error, U32>>:
        synced : Result<&1, &1, U32 & String, Unit> <- Fs.fsync(directory)
        write.completed(generation, synced)

def write.renamed.paths(
  directories: String & String & String,
  generation: U32,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, Error, U32>):
  match directories:
    case (temp_directory, (final_directory, retained_directory)):
      match result:
        case Fail{error}:
          IO.pure(Result<&1, &1, Error, U32>, Fail{host(error)})
        case Done{Unit{}}:
          do IO<Result<&1, &1, Error, U32>>:
            renamed : Result<&1, &1, U32 & String, Unit> <- Fs.rename(temp_directory ++ "/OWNER.GEN.tmp", final_directory ++ "/OWNER.GEN")
            write.directory.synced(retained_directory, generation, renamed)

def write.renamed(
  directory: String,
  generation: U32,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, Error, U32>):
  write.renamed.paths(path.triple(directory), generation, result)

def write.temporary.synced(
  directory: String,
  generation: U32,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, Error, U32>):
  write.renamed(directory, generation, result)

def write.result.paths(
  directories: String & String,
  generation: U32,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, Error, U32>):
  match directories:
    case (temp_directory, retained_directory):
      match result:
        case Fail{error}:
          IO.pure(Result<&1, &1, Error, U32>, Fail{host(error)})
        case Done{Unit{}}:
          do IO<Result<&1, &1, Error, U32>>:
            synced : Result<&1, &1, U32 & String, Unit> <- Fs.fsync(temp_directory ++ "/OWNER.GEN.tmp")
            write.temporary.synced(retained_directory, generation, synced)

def write.result(
  directory: String,
  generation: U32,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, Error, U32>):
  write.result.paths(path.pair(directory), generation, result)

def write.closed(
  directory: String,
  generation: U32,
  result: File & Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, Error, U32>):
  match result:
    case (file, result):
      do IO<Result<&1, &1, Error, U32>>:
        _closed : Unit <- File.close(file)
        write.result(directory, generation, result)

def write.opened.generation(
  directory: String,
  file: File,
  generations: U32 & U32
) -> IO(Result<&1, &1, Error, U32>):
  match generations:
    case (encode_generation, retained_generation):
      do IO<Result<&1, &1, Error, U32>>:
        result : File & Result<&1, &1, U32 & String, Unit> <-
          Fs.write_bytes(file, Generation.u32.bytes(encode_generation))
        write.closed(directory, retained_generation, result)

def write.opened(
  directory: String,
  generation: U32,
  opened: Result<&1, &1, U32 & String, File>
) -> IO(Result<&1, &1, Error, U32>):
  match opened:
    case Fail{error}:
      IO.pure(Result<&1, &1, Error, U32>, Fail{host(error)})
    case Done{file}:
      write.opened.generation(directory, file,
        Generation.u32.clone.pair(generation))

def write.paths(
  paths: String & String,
  generation: U32
) -> IO(Result<&1, &1, Error, U32>):
  match paths:
    case (open_directory, retained_directory):
      do IO<Result<&1, &1, Error, U32>>:
        opened : Result<&1, &1, U32 & String, File> <-
          File.open(open_directory ++ "/OWNER.GEN.tmp", "w")
        write.opened(retained_directory, generation, opened)

# Publishes a generation through a synced temporary file and atomic rename.
def write(directory: String, generation: U32) -> IO(Result<&1, &1, Error, U32>):
  write.paths(path.pair(directory), generation)

def next.decision(
  directory: String,
  decision: Generation.Decision
) -> IO(Result<&1, &1, Error, U32>):
  match decision:
    case Generation.GenerationExhausted{}:
      IO.pure(Result<&1, &1, Error, U32>, Fail{Exhausted{}})
    case Generation.GenerationReady{generation}: write(directory, generation)

def next.read(
  directory: String,
  result: Result<&1, &1, Error, U32>
) -> IO(Result<&1, &1, Error, U32>):
  match result:
    case Fail{Invalid{}}:
      IO.pure(Result<&1, &1, Error, U32>, Fail{Invalid{}})
    case Fail{Host{code, message}}:
      IO.pure(Result<&1, &1, Error, U32>, Fail{Host{code, message}})
    case Fail{Exhausted{}}:
      IO.pure(Result<&1, &1, Error, U32>, Fail{Exhausted{}})
    case Done{current}:
      next.decision(directory, Generation.next(Some{current}))

def initialize.exists(
  directories: String & String,
  result: Result<&1, &1, U32 & String, Bool>
) -> IO(Result<&1, &1, Error, U32>):
  match directories:
    case (check_directory, retained_directory):
      match result:
        case Fail{error}:
          IO.pure(Result<&1, &1, Error, U32>, Fail{host(error)})
        case Done{False{}}: write(retained_directory, 1)
        case Done{True{}}:
          do IO<Result<&1, &1, Error, U32>>:
            current : Result<&1, &1, Error, U32> <- read(check_directory ++ "/OWNER.GEN")
            next.read(retained_directory, current)

def initialize.paths(paths: String & String) -> IO(Result<&1, &1, Error, U32>):
  match paths:
    case (check_directory, retained_directory):
      do IO<Result<&1, &1, Error, U32>>:
        result : Result<&1, &1, U32 & String, Bool> <- Fs.exists(check_directory ++ "/OWNER.GEN")
        initialize.exists(path.pair(retained_directory), result)

# Starts at one or advances the persisted value before owner publication.
def initialize(directory: String) -> IO(Result<&1, &1, Error, U32>):
  initialize.paths(path.pair(directory))

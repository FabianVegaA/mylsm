import Base

# Classifies the filesystem object reported by a metadata lookup.
type FileType is Data:
  Regular{}
  Directory{}
  Other{}

# Stores the kind, size, and modification time returned by stat.
type Info is Data:
  Info{kind: FileType, size: U32, mtime: U32}

def stat.raw(path: String) -> IO(Result<&1, &1, U32 & String, U32 & U32 & U32>):
  import "./effs/files_compat.c"
  import "./effs/files_compat.js"

# Maps the operating-system kind code into the public file classification.
def kind_from_nat(kind: Nat) -> FileType:
  match kind:
    case 0n: Regular{}
    case 1n+rest:
      match rest:
        case 0n: Directory{}
        case 1n+rest: Other{}

def stat.kind(kind: U32) -> FileType:
  kind_from_nat(U32.to_nat(kind))

def stat.result(
  result: Result<&1, &1, U32 & String, U32 & U32 & U32>
) -> Result<&1, &1, U32 & String, Info>:
  match result:
    case Fail{error}: Fail{error}
    case Done{(kind, (size, mtime))}:
      Done{Info{stat.kind(kind), size, mtime}}

# Reads filesystem metadata for a path.
def stat(path: String) -> IO(Result<&1, &1, U32 & String, Info>):
  do IO<Result<&1, &1, U32 & String, Info>>:
    result : Result<&1, &1, U32 & String, U32 & U32 & U32> <- stat.raw(path)
    return stat.result(result)

# Removes a file or an empty directory at a path.
def remove(path: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  import "./effs/files_compat.c"
  import "./effs/files_compat.js"

# Renames a path using the filesystem's atomic rename operation.
def rename(from: String, to: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  import "./effs/files_compat.c"
  import "./effs/files_compat.js"

def read.words(file: File, max: U32) -> IO(File & Result<&1, &1, U32 & String, U32 & Array<U32>>):
  import "./effs/files_compat.c"
  import "./effs/files_compat.js"

def write.words.once(
  file: File,
  offset: U32,
  len: U32,
  words: Array<U32>
) -> IO(File & Result<&1, &1, U32 & String, U32 & Array<U32>>):
  import "./effs/files_compat.c"
  import "./effs/files_compat.js"

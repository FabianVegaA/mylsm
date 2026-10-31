import Base
import ../Manifest.bend as Manifest
import ../StorageBytes.bend as StorageBytes
import ../Fs.bend as Fs
import ../CrashPoint.bend as CrashPoint
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Represent ManifestReadState data used by the memtable flush.
type ManifestReadState is Type:
  ManifestNeed{file: File, remaining: Nat, chunks: List<&1, Bytes.Bytes>}
  ManifestGot{pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>, remaining: Nat, chunks: List<&1, Bytes.Bytes>}

def write_tail.chmod(
  result: Result<&1, &1, U32 & String, Unit>,
  +path: String
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{error})
    case Done{Unit{}}:
      Fs.chmod(path, U32.from_nat(384n))

def write_tail.fsync(
  result: Result<&1, &1, U32 & String, Unit>,
  +path: String
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{error})
    case Done{Unit{}}:
      do IO<Result<&1, &1, U32 & String, Unit>>:
        synced : Result<&1, &1, U32 & String, Unit> <- Fs.fsync(path)
        write_tail.chmod(synced, path)

# Writes the remaining bytes of a file buffer.
def write_tail(
  fr: File & Result<&1, &1, U32 & String, Unit>,
  +path: String
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match fr:
    case (file, result):
      do IO<Result<&1, &1, U32 & String, Unit>>:
        _closed : Unit <- File.close(file)
        write_tail.fsync(result, path)

def write_file.opened(
  opened: Result<&1, &1, U32 & String, File>,
  +path: String,
  +data: String
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match opened:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{error})
    case Done{file}:
      do IO<Result<&1, &1, U32 & String, Unit>>:
        written : File & Result<&1, &1, U32 & String, Unit> <- File.write(file, data)
        write_tail(written, path)

# Creates and syncs one storage file.
def write_file(+path: String, +data: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  do IO<Result<&1, &1, U32 & String, Unit>>:
    opened : Result<&1, &1, U32 & String, File> <- File.open(path, "w")
    write_file.opened(opened, path, data)

def write_manifest.bytes.opened(
  opened: Result<&1, &1, U32 & String, File>,
  +path: String,
  bytes: Bytes.Bytes
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match opened:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{error})
    case Done{file}:
      do IO<Result<&1, &1, U32 & String, Unit>>:
        written : File & Result<&1, &1, U32 & String, Unit> <- Fs.write_bytes(file, bytes)
        write_tail(written, path)

def write_manifest.bytes(+path: String, bytes: Bytes.Bytes) -> IO(Result<&1, &1, U32 & String, Unit>):
  do IO<Result<&1, &1, U32 & String, Unit>>:
    opened : Result<&1, &1, U32 & String, File> <- File.open(path, "w")
    write_manifest.bytes.opened(opened, path, bytes)

def write_manifest.encoded(
  path: String,
  encoded: Result<&1, &1, Manifest.Error, Bytes.Bytes>
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match encoded:
    case Fail{_}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{(U32.from_nat(1n), "cannot encode manifest")})
    case Done{bytes}:
      write_manifest.bytes(path, bytes)

# Write manifest for the memtable flush.
def write_manifest(path: String, manifest: Manifest.Manifest) -> IO(Result<&1, &1, U32 & String, Unit>):
  write_manifest.encoded(path, Manifest.serialize(manifest))

# Read tail3 for the memtable flush.
def read_tail3(fr: (File & Result<&1, &1, U32 & String, String>)) -> IO(Result<&1, &1, U32 & String, String>):
  match fr:
    case (f3, r1):
      do IO<Result<&1, &1, U32 & String, String>>:
        _cls : Unit <- File.close(f3)
        IO.pure(Result<&1, &1, U32 & String, String>, r1)


# Base File.read decodes each returned chunk independently. A chunk boundary can
# split a multi-byte UTF-8 character, so table files are read in one bounded call
# Reads a bounded storage file and returns its bytes.
def read_file.opened(
  opened: Result<&1, &1, U32 & String, File>
) -> IO(Result<&1, &1, U32 & String, String>):
  match opened:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, String>, Fail{error})
    case Done{file}:
      do IO<Result<&1, &1, U32 & String, String>>:
        result : File & Result<&1, &1, U32 & String, String> <- File.read(file, U32.from_nat(4294967295n))
        read_tail3(result)

# Reads a bounded storage file and returns its bytes.
def read_file(+path: String) -> IO(Result<&1, &1, U32 & String, String>):
  do IO<Result<&1, &1, U32 & String, String>>:
    opened : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    read_file.opened(opened)

# Classifies the Manifest parse result before recovery.
def mfst_parsed(parsed: Manifest.ParseResult) -> Result<&1, &1, U32 & String, Manifest.Manifest>:
  match parsed:
    case Manifest.Parsed{manifest}:
      Done{manifest}
    case Manifest.UnsupportedVersion{_}:
      Fail{(Manifest.unsupported_version_error_code(), "unsupported manifest version")}
    case Manifest.Malformed{}:
      Fail{(Manifest.malformed_error_code(), "malformed manifest")}
    case Manifest.ParseLimitExceeded{}:
      Fail{(Manifest.parse_limit_error_code(), "manifest size limit exceeded")}

def manifest.read.result(
  pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>
) -> IO(Result<&1, &1, U32 & String, Manifest.Manifest>):
  match pair:
    case (file, Fail{error}):
      do IO<Result<&1, &1, U32 & String, Manifest.Manifest>>:
        _closed : Unit <- File.close(file)
        return Fail{error}
    case (file, Done{bytes}):
      do IO<Result<&1, &1, U32 & String, Manifest.Manifest>>:
        _closed : Unit <- File.close(file)
        return mfst_parsed(Manifest.parse_result(bytes))

def manifest.read.loop(fuel: Nat, state: ManifestReadState) -> IO(File & Result<&1, &1, U32 & String, Bytes.Bytes>):
  match fuel:
    case 0n:
      match state:
        case ManifestNeed{file, +remaining, chunks}:
          match remaining:
            case 0n:
              IO.pure(File & Result<&1, &1, U32 & String, Bytes.Bytes>, (file, Done{Bytes.concat(List.reverse(&1, Bytes.Bytes, chunks))}))
            case 1n+_:
              IO.pure(File & Result<&1, &1, U32 & String, Bytes.Bytes>, (file, Fail{(U32.from_nat(7n), "bounded manifest read exhausted")}))
        case ManifestGot{pair, _, _}:
          match pair:
            case (file, Fail{error}):
              IO.pure(File & Result<&1, &1, U32 & String, Bytes.Bytes>, (file, Fail{error}))
            case (file, Done{_}):
              IO.pure(File & Result<&1, &1, U32 & String, Bytes.Bytes>, (file, Fail{(U32.from_nat(7n), "bounded manifest read exhausted")}))
    case 1n+rest:
      match state:
        case ManifestNeed{file, +remaining, chunks}:
          match remaining:
            case 0n:
              IO.pure(File & Result<&1, &1, U32 & String, Bytes.Bytes>, (file, Done{Bytes.concat(List.reverse(&1, Bytes.Bytes, chunks))}))
            case 1n+_:
              do IO<File & Result<&1, &1, U32 & String, Bytes.Bytes>>:
                pair : File & Result<&1, &1, U32 & String, Bytes.Bytes> <- Fs.read_bytes(file, U32.from_nat(remaining))
                manifest.read.loop(rest, ManifestGot{pair, remaining, chunks})
        case ManifestGot{pair, +remaining, chunks}:
          match pair:
            case (file, Fail{error}):
              IO.pure(File & Result<&1, &1, U32 & String, Bytes.Bytes>, (file, Fail{error}))
            case (file, Done{Bytes.Bytes{0, _}}):
              IO.pure(File & Result<&1, &1, U32 & String, Bytes.Bytes>, (file, Fail{(U32.from_nat(8n), "truncated manifest file")}))
            case (file, Done{Bytes.Bytes{+len, buf}}):
              manifest.read.loop(rest, ManifestNeed{file, Nat.sub(remaining, U32.to_nat(len)), Con{Bytes.Bytes{len, buf}, chunks}})

def manifest.read.size.run(file: File, +size: Nat) -> IO(Result<&1, &1, U32 & String, Manifest.Manifest>):
  do IO<Result<&1, &1, U32 & String, Manifest.Manifest>>:
    pair : File & Result<&1, &1, U32 & String, Bytes.Bytes> <- manifest.read.loop(Nat.add(size, 1n), ManifestNeed{file, size, Nil{}})
    manifest.read.result(pair)

def manifest.read.size.valid(
  file: File,
  size: Nat,
  within: Bool
) -> IO(Result<&1, &1, U32 & String, Manifest.Manifest>):
  match within:
    case False{}:
      do IO<Result<&1, &1, U32 & String, Manifest.Manifest>>:
        _closed : Unit <- File.close(file)
        return Fail{(U32.from_nat(9n), "manifest too large")}
    case True{}:
      manifest.read.size.run(file, size)

def manifest.read.size(
  file: File,
  result: Result<&1, &1, U32 & String, Nat>
) -> IO(Result<&1, &1, U32 & String, Manifest.Manifest>):
  match result:
    case Fail{error}:
      do IO<Result<&1, &1, U32 & String, Manifest.Manifest>>:
        _closed : Unit <- File.close(file)
        return Fail{error}
    case Done{+size}:
      manifest.read.size.valid(file, size, Nat.is_le(size, U32.to_nat(StorageBytes.MAX_MANIFEST_BYTES())))

# Handle mfst open error in the memtable flush.
def mfst_open_error(
  missing: Bool,
  +code: U32
) -> IO(Result<&1, &1, U32 & String, Manifest.Manifest>):
  match missing:
    case True{}:
      IO.pure(Result<&1, &1, U32 & String, Manifest.Manifest>, Done{Manifest.M{Nil{}}})
    case False{}:
      IO.pure(Result<&1, &1, U32 & String, Manifest.Manifest>, Fail{(code, "cannot open manifest")})

# Handle mfst opened in the memtable flush.
def mfst_opened(
  path: String,
  result: Result<&1, &1, U32 & String, File>
) -> IO(Result<&1, &1, U32 & String, Manifest.Manifest>):
  match result:
    case Fail{(+code, _)}:
      mfst_open_error(U32.is_eq(code, 2), code)
    case Done{file}:
      do IO<Result<&1, &1, U32 & String, Manifest.Manifest>>:
        size : Result<&1, &1, U32 & String, Nat> <- Fs.file_size(path)
        manifest.read.size(file, size)

# Handle load mfst in the memtable flush.
def load_mfst(+path: String) -> IO(Result<&1, &1, U32 & String, Manifest.Manifest>):
  do IO<Result<&1, &1, U32 & String, Manifest.Manifest>>:
    opened : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    mfst_opened(path, opened)

# Handle dir tail in the memtable flush.
def dir_tail(res: Result<&1, &1, U32 & String, Nat>, +path: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  match res:
    case Done{n}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Done{Unit{}})
    case Fail{e}:
      Fs.make_dir(path)

# Handle ensure dir in the memtable flush.
def ensure_dir(+path: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  do IO<Result<&1, &1, U32 & String, Unit>>:
    r : Result<&1, &1, U32 & String, Nat> <- Fs.read_dir_count(path)
    dir_tail(r, path)

# Handle ldir of in the database recovery effects.
def ldir_of(idx: Nat) -> Maybe<&2, String>:
  match idx:
    case 0n:
      Some{"l0"}
    case 1n+m:
      match m:
        case 0n:
          Some{"l1"}
        case 1n+p:
          match p:
            case 0n:
              Some{"l2"}
            case 1n+q:
              match q:
                case 0n:
                  Some{"l3"}
                case 1n+r:
                  None{}

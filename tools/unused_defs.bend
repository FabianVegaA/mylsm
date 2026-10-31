import Base
import ./UnusedDefs.bend as Unused
import ../src/Fs.bend as Fs
import ../src/FilesCompat.bend as Files

# Holds one targeted file and the names it defines.
type Candidate is Type:
  Candidate{path: String, names: List<&1, Unused.Definition>}

# Accumulates reference counts and targeted definitions while reading files.
type Scan is Type:
  Scan{counts: Map<&2, Nat>, candidates: List<&1, Candidate>}

# Holds the directories still to list and the Bend files found so far.
type Listing is Type:
  Listing{dirs: List<&2, String>, files: List<&2, String>}

# Reports whether a directory entry is outside the scanned tree.
def skipped(+name: String) -> Bool:
  String.starts_with(name, ".") || String.eq(name, "node_modules") ||
    String.eq(name, "result")

def child.decided(is_root: Bool, dir: String, name: String) -> String:
  match is_root:
    case True{}: name
    case False{}: dir ++ "/" ++ name

# Joins a directory and an entry without a leading "./".
def child(+dir: String, name: String) -> String:
  child.decided(String.eq(dir, "."), dir, name)

def list.file(is_bend: Bool, path: String, listing: Listing) -> Listing:
  match is_bend:
    case True{}:
      match listing:
        case Listing{dirs, files}: Listing{dirs, Con{path, files}}
    case False{}: listing

def list.kind(
  info: Result<&1, &1, U32 & String, Files.Info>,
  +path: String,
  listing: Listing
) -> Listing:
  match info:
    case Fail{_}: listing
    case Done{Files.Info{kind, _, _}}:
      match kind:
        case Files.Directory{}:
          match listing:
            case Listing{dirs, files}: Listing{Con{path, dirs}, files}
        case Files.Regular{}: list.file(String.ends_with(path, ".bend"), path, listing)
        case Files.Other{}: listing

def list.stat(+path: String, listing: Listing) -> IO(Listing):
  do IO<Listing>:
    info : Result<&1, &1, U32 & String, Files.Info> <- Files.stat(path)
    return list.kind(info, path, listing)

def list.named(skip: Bool, +dir: String, name: String, listing: Listing) -> IO(Listing):
  match skip:
    case True{}: IO.pure(Listing, listing)
    case False{}: list.stat(child(dir, name), listing)

def list.entry(
  read: Result<&1, &1, U32 & String, String>,
  +dir: String,
  listing: Listing
) -> IO(Listing):
  match read:
    case Fail{_}: IO.pure(Listing, listing)
    case Done{+name}: list.named(skipped(name), dir, name, listing)

def list.go(remaining: Nat, +dir: String, +index: Nat, listing: Listing) -> IO(Listing):
  match remaining:
    case 0n: IO.pure(Listing, listing)
    case 1n+rest:
      do IO<Listing>:
        read : Result<&1, &1, U32 & String, String> <- Fs.read_dir_at(dir, index)
        next : Listing <- list.entry(read, dir, listing)
        list.go(rest, dir, Nat.add(index, 1n), next)

def list.dir(
  +dir: String,
  counted: Result<&1, &1, U32 & String, Nat>,
  listing: Listing
) -> IO(Listing):
  match counted:
    case Fail{_}: IO.pure(Listing, listing)
    case Done{entries}: list.go(entries, dir, 0n, listing)

# Lists every Bend file below the pending directories, one directory per step.
def walk(fuel: Nat, listing: Listing) -> IO(List<&2, String>):
  match fuel:
    case 0n:
      match listing:
        case Listing{_, files}: IO.pure(List<&2, String>, files)
    case 1n+rest:
      match listing:
        case Listing{Nil{}, files}: IO.pure(List<&2, String>, files)
        case Listing{Con{+dir, more}, files}:
          do IO<List<&2, String>>:
            counted : Result<&1, &1, U32 & String, Nat> <- Fs.read_dir_count(dir)
            found : Listing <- list.dir(dir, counted, Listing{more, files})
            walk(rest, found)

def read.closed(
  pair: File & Result<&1, &1, U32 & String, String>
) -> IO(Result<&1, &1, U32 & String, String>):
  match pair:
    case (file, result):
      do IO<Result<&1, &1, U32 & String, String>>:
        _closed : Unit <- File.close(file)
        return result

def read.opened(
  opened: Result<&1, &1, U32 & String, File>
) -> IO(Result<&1, &1, U32 & String, String>):
  match opened:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, String>, Fail{error})
    case Done{file}:
      do IO<Result<&1, &1, U32 & String, String>>:
        pair : File & Result<&1, &1, U32 & String, String> <-
          File.read(file, U32.from_nat(4294967295n))
        read.closed(pair)

# Reads a whole text file.
def read(path: String) -> IO(Result<&1, &1, U32 & String, String>):
  do IO<Result<&1, &1, U32 & String, String>>:
    opened : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    read.opened(opened)

def scan.candidate(is_target: Bool, path: String, +text: String, scan: Scan) -> Scan:
  match is_target:
    case True{}:
      match scan:
        case Scan{counts, candidates}:
          Scan{Unused.count(counts, text),
            Con{Candidate{path, Unused.defined(text)}, candidates}}
    case False{}:
      match scan:
        case Scan{counts, candidates}: Scan{Unused.count(counts, text), candidates}

def scan.read(
  read: Result<&1, &1, U32 & String, String>,
  +path: String,
  +targets: List<&2, String>,
  scan: Scan
) -> IO(Scan):
  match read:
    case Fail{(code, message)}:
      IO.die(Scan, code, "cannot read " ++ path ++ ": " ++ message)
    case Done{text}:
      IO.pure(Scan, scan.candidate(Unused.targeted(targets, path), path, text, scan))

def scan.files(files: List<&2, String>, +targets: List<&2, String>, scan: Scan) -> IO(Scan):
  match files:
    case Nil{}: IO.pure(Scan, scan)
    case Con{+path, rest}:
      do IO<Scan>:
        text : Result<&1, &1, U32 & String, String> <- read(path)
        next : Scan <- scan.read(text, path, targets, scan)
        scan.files(rest, targets, next)

def report.check(
  is_allowed: Bool,
  counts: Map<&2, Nat>,
  +name: String,
  own: Nat
) -> Map<&2, Nat> & Bool:
  match is_allowed:
    case True{}: (counts, False{})
    case False{}: Unused.unused.own(counts, name, own)

def report.emit(
  checked: Map<&2, Nat> & Bool,
  path: String,
  name: String,
  found: Nat
) -> IO(Map<&2, Nat> & Nat):
  match checked:
    case (counts, True{}):
      do IO<Map<&2, Nat> & Nat>:
        _printed : Unit <- IO.print(path ++ " " ++ name)
        return (counts, Nat.add(found, 1n))
    case (counts, False{}): IO.pure(Map<&2, Nat> & Nat, (counts, found))

def report.names(
  names: List<&1, Unused.Definition>,
  +path: String,
  +allow: List<&2, String>,
  state: Map<&2, Nat> & Nat
) -> IO(Map<&2, Nat> & Nat):
  match names:
    case Nil{}: IO.pure(Map<&2, Nat> & Nat, state)
    case Con{Unused.Definition{+name, own}, rest}:
      match state:
        case (counts, found):
          do IO<Map<&2, Nat> & Nat>:
            emitted : Map<&2, Nat> & Nat <- report.emit(
              report.check(Unused.allowed(allow, path, name), counts, name, own),
              path, name, found)
            report.names(rest, path, allow, emitted)

def report.candidates(
  candidates: List<&1, Candidate>,
  +allow: List<&2, String>,
  state: Map<&2, Nat> & Nat
) -> IO(Map<&2, Nat> & Nat):
  match candidates:
    case Nil{}: IO.pure(Map<&2, Nat> & Nat, state)
    case Con{Candidate{path, names}, rest}:
      do IO<Map<&2, Nat> & Nat>:
        next : Map<&2, Nat> & Nat <- report.names(names, path, allow, state)
        report.candidates(rest, allow, next)

# Exits with status 1 when any definition was reported.
def finish(state: Map<&2, Nat> & Nat) -> IO(Unit):
  match state:
    case (_, 0n): IO.pure(Unit, Unit{})
    case (_, 1n+_): IO.exit(1)

def allow.line(entry: String, rest: List<&2, String>) -> List<&2, String>:
  match entry:
    case SNil{}: rest
    case SCon{c, tail}: Con{SCon{c, tail}, rest}

def allow.lines(lines: List<&2, String>) -> List<&2, String>:
  match lines:
    case Nil{}: Nil{}
    case Con{line, rest}: allow.line(String.trim(line), allow.lines(rest))

def allow.read(read: Result<&1, &1, U32 & String, String>) -> List<&2, String>:
  match read:
    case Fail{_}: Nil{}
    case Done{text}: allow.lines(String.lines(text))

def args.targets.go(args: List<String>) -> List<&2, String>:
  match args:
    case Nil{}: Nil{}
    case Con{arg, rest}: Con{arg, args.targets.go(rest)}

def args.targets(args: List<String>) -> List<&2, String>:
  match args:
    case Nil{}: Nil{}
    case Con{_, rest}: args.targets.go(rest)

def run.report(scan: Scan, allow: List<&2, String>) -> IO(Unit):
  match scan:
    case Scan{counts, candidates}:
      do IO<Unit>:
        state : Map<&2, Nat> & Nat <- report.candidates(
          List.reverse(&1, Candidate, candidates), allow, (counts, 0n))
        finish(state)

# Prints every definition under the given paths that nothing references.
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    allowed : Result<&1, &1, U32 & String, String> <- read("tools/unused_defs.allow")
    files : List<&2, String> <- walk(1000000n, Listing{["."], Nil{}})
    scan : Scan <- scan.files(files, args.targets(args),
      Scan{Map.new(&2, Nat), Nil{}})
    run.report(scan, allow.read(allowed))

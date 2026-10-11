import Base
import ../ByteDurableDb.bend as Db
import ../ByteMemTable.bend as ByteMemTable
import ../ByteWal.bend as ByteWal
import ../CrashPoint.bend as CrashPoint
import ../Fs.bend as Fs
import ./Restore.bend as Restore
import ./RestorePolicy.bend as RestorePolicy
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Classifies exchange validation, staging, publication, and durability failures.
type Error is Data:
  InvalidFormat{}
  ResourceLimit{}
  InvalidOrder{}
  ChecksumMismatch{}
  CountMismatch{}
  Storage{error: Db.Error}
  Io{code: U32, message: String}
  DestinationExists{}
  TemporaryExists{}
  VerificationFailed{}
  CommitUnknown{code: U32, message: String}

# Retains a single staged record and database handle between WAL writes.
type WriteState is Type:
  WriteNeed{handle: Db.Handle, entries: List<&1, ByteMemTable.Entry>}
  WriteBatch{handle: Db.Handle, page: WritePage}
  WriteResult{pair: Db.Handle & Result<&1, &1, Db.Error, Unit>,
    rest: List<&1, ByteMemTable.Entry>}

# Carries one bounded mutation page and the remaining ordered entries.
type WritePage is Type:
  WritePage{batch: List<&1, ByteMemTable.Entry>, rest: List<&1, ByteMemTable.Entry>}

def decode.error(error: Restore.Error) -> Error:
  match error:
    case Restore.InvalidFormat{}: InvalidFormat{}
    case Restore.ResourceLimit{}: ResourceLimit{}
    case Restore.InvalidOrder{}: InvalidOrder{}
    case Restore.ChecksumMismatch{}: ChecksumMismatch{}
    case Restore.CountMismatch{}: CountMismatch{}

def entries.count(entries: List<&1, ByteMemTable.Entry>) -> Nat:
  List.length(&1, ByteMemTable.Entry, entries)

def write.finish(pair: Db.Handle & Result<&1, &1, Db.Error, Unit>) -> WriteState:
  WriteResult{pair, Nil{}}

def write.result(
  rest: List<&1, ByteMemTable.Entry>,
  pair: Db.Handle & Result<&1, &1, Db.Error, Unit>
) -> WriteState:
  WriteResult{pair, rest}

def write.page.go(
  fuel: Nat,
  entries: List<&1, ByteMemTable.Entry>,
  reversed: List<&1, ByteMemTable.Entry>
) -> WritePage:
  match fuel:
    case 0n: WritePage{List.reverse(&1, ByteMemTable.Entry, reversed), entries}
    case 1n+rest:
      match entries:
        case Nil{}: WritePage{List.reverse(&1, ByteMemTable.Entry, reversed), Nil{}}
        case Con{entry, tail}: write.page.go(rest, tail, Con{entry, reversed})

def write.page.ready(
  measured: List<&1, ByteMemTable.Entry> & Nat
) -> WritePage:
  match measured:
    case (entries, count):
      write.page.go(Nat.min(RestorePolicy.write.page.size(), count), entries, Nil{})

def write.page(entries: List<&1, ByteMemTable.Entry>) -> WritePage:
  write.page.ready(ByteMemTable.count.keep(entries))

def write.mutations(entries: List<&1, ByteMemTable.Entry>) -> List<&1, ByteWal.Mutation>:
  match entries:
    case Nil{}: Nil{}
    case Con{ByteMemTable.Entry{key, value}, tail}:
      match value:
        case None{}: Con{ByteWal.Delete{key}, write.mutations(tail)}
        case Some{value}: Con{ByteWal.Put{key, value}, write.mutations(tail)}

def write.loop(fuel: Nat, state: WriteState) -> IO(Db.Handle & Result<&1, &1, Db.Error, Unit>):
  match fuel:
    case 0n:
      match state:
        case WriteNeed{handle, _}:
          IO.pure(Db.Handle & Result<&1, &1, Db.Error, Unit>,
            (handle, Fail{Db.ResourceLimit{}}))
        case WriteBatch{handle, _}:
          IO.pure(Db.Handle & Result<&1, &1, Db.Error, Unit>,
            (handle, Fail{Db.ResourceLimit{}}))
        case WriteResult{pair, _}: IO.pure(Db.Handle & Result<&1, &1, Db.Error, Unit>, pair)
    case 1n+rest_fuel:
      match state:
        case WriteNeed{handle, entries}:
          match entries:
            case Nil{}:
              IO.pure(Db.Handle & Result<&1, &1, Db.Error, Unit>,
                (handle, Done{Unit{}}))
            case Con{_, _}:
              write.loop(rest_fuel, WriteBatch{handle, write.page(entries)})
        case WriteBatch{handle, WritePage{batch, rest}}:
          do IO<Db.Handle & Result<&1, &1, Db.Error, Unit>>:
            pair : Db.Handle & Result<&1, &1, Db.Error, Unit> <-
              Db.write_batch(handle, write.mutations(batch))
            write.loop(rest_fuel, WriteResult{pair, rest})
        case WriteResult{pair, rest}:
          match pair:
            case (handle, Fail{error}):
              IO.pure(Db.Handle & Result<&1, &1, Db.Error, Unit>,
                (handle, Fail{error}))
            case (handle, Done{Unit{}}):
              write.loop(rest_fuel, WriteNeed{handle, rest})

def remove.ignored(path: String) -> IO(Unit):
  do IO<Unit>:
    _removed : Result<&1, &1, U32 & String, Unit> <- Fs.remove(path)
    return Unit{}

def cleanup.directory(+path: String) -> IO(Unit):
  do IO<Unit>:
    remove.ignored(path ++ "/WAL")
    remove.ignored(path ++ "/WAL.tmp")
    remove.ignored(path ++ "/SST")
    remove.ignored(path ++ "/SST.tmp")
    remove.ignored(path ++ "/LOCK")
    remove.ignored(path)

def cleanup.result(
  path: String,
  result: Result<&1, &1, Db.Error, Unit>
) -> IO(Result<&1, &1, Error, Unit>):
  match result:
    case Fail{error}:
      do IO<Result<&1, &1, Error, Unit>>:
        cleanup.directory(path)
        return Fail{Storage{error}}
    case Done{Unit{}}:
      do IO<Result<&1, &1, Error, Unit>>:
        cleanup.directory(path)
        return Done{Unit{}}

def cleanup.handle(
  path: String,
  handle: Db.Handle,
  error: Db.Error
) -> IO(Result<&1, &1, Error, Unit>):
  do IO<Result<&1, &1, Error, Unit>>:
    _closed : Result<&1, &1, Db.Error, Unit> <- Db.close(handle)
    cleanup.result(path, Fail{error})

def create.failed(path: String, error: Db.Error) -> IO(Result<&1, &1, Error, Unit>):
  match error:
    case Db.AlreadyExists{}:
      IO.pure(Result<&1, &1, Error, Unit>, Fail{Storage{error}})
    case _:
      do IO<Result<&1, &1, Error, Unit>>:
        cleanup.directory(path)
        return Fail{Storage{error}}

def flush.closed(
  path: String,
  result: Result<&1, &1, Db.Error, Unit>
) -> IO(Result<&1, &1, Error, Unit>):
  match result:
    case Fail{error}: cleanup.result(path, Fail{error})
    case Done{Unit{}}: IO.pure(Result<&1, &1, Error, Unit>, Done{Unit{}})

def flush.result(
  path: String,
  pair: Db.Handle & Result<&1, &1, Db.Error, Unit>
) -> IO(Result<&1, &1, Error, Unit>):
  match pair:
    case (handle, Fail{error}): cleanup.handle(path, handle, error)
    case (handle, Done{Unit{}}):
      do IO<Result<&1, &1, Error, Unit>>:
        closed : Result<&1, &1, Db.Error, Unit> <- Db.close(handle)
        result : Result<&1, &1, Error, Unit> <- flush.closed(path, closed)
        return result


def write.result.path(
  path: String,
  pair: Db.Handle & Result<&1, &1, Db.Error, Unit>
) -> IO(Result<&1, &1, Error, Unit>):
  match pair:
    case (handle, Fail{error}): cleanup.handle(path, handle, error)
    case (handle, Done{Unit{}}):
      do IO<Result<&1, &1, Error, Unit>>:
        flushed : Db.Handle & Result<&1, &1, Db.Error, Unit> <- Db.flush(handle)
        result : Result<&1, &1, Error, Unit> <- flush.result(path, flushed)
        return result

# Rejects a staged database whose recovered entry count differs from the exchange.
def verify_count(path: String, equal: Bool) -> IO(Result<&1, &1, Error, Unit>):
  match equal:
    case False{}:
      do IO<Result<&1, &1, Error, Unit>>:
        cleanup.directory(path)
        return Fail{VerificationFailed{}}
    case True{}: IO.pure(Result<&1, &1, Error, Unit>, Done{Unit{}})

def verified.closed(
  path: String,
  expected: Nat,
  count: Nat,
  closed: Result<&1, &1, Db.Error, Unit>
) -> IO(Result<&1, &1, Error, Unit>):
  match closed:
    case Fail{error}:
      do IO<Result<&1, &1, Error, Unit>>:
        cleanup.directory(path)
        return Fail{Storage{error}}
    case Done{Unit{}}:
      verify_count(path, Nat.is_eq(count, expected))

def path.reverse(path: String, reversed: String) -> String:
  match path:
    case SNil{}: reversed
    case SCon{character, rest}:
      path.reverse(rest, SCon{character, reversed})

def path.clone(path: String) -> String:
  path.reverse(path.reverse(path, SNil{}), SNil{})


def verified.stats(
  path: String,
  expected: Nat,
  pair: Db.Handle & Db.Stats
) -> IO(Result<&1, &1, Error, Unit>):
  match pair:
    case (handle, Db.Stats{entries, _}):
      do IO<Result<&1, &1, Error, Unit>>:
        closed : Result<&1, &1, Db.Error, Unit> <- Db.close(handle)
        verified.closed(path, expected, entries, closed)

# Opens and checks the staged database before publication.
def verified(
  path: String,
  expected: Nat,
  opened: Result<&1, &1, Db.Error, Db.Handle>
) -> IO(Result<&1, &1, Error, Unit>):
  match opened:
    case Fail{error}:
      do IO<Result<&1, &1, Error, Unit>>:
        cleanup.directory(path)
        return Fail{Storage{error}}
    case Done{handle}: verified.stats(path, expected, Db.stats(handle))

# Validates an exchange, builds a sibling database, verifies it, then publishes it.
def publish.parent.synced(
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, Error, Unit>):
  match result:
    case Fail{(code, message)}:
      IO.pure(Result<&1, &1, Error, Unit>,
        Fail{CommitUnknown{code, "parent directory sync failed: " ++ message}})
    case Done{Unit{}}:
      do IO<Result<&1, &1, Error, Unit>>:
        _checkpoint : Result<&1, &1, U32 & String, Unit> <-
          CrashPoint.hit("restore.parent_synced")
        return Done{Unit{}}

def publish.renamed(
  +destination: String,
  +temporary: String,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, Error, Unit>):
  match result:
    case Fail{(code, message)}:
      do IO<Result<&1, &1, Error, Unit>>:
        cleanup.directory(temporary)
        return Fail{Io{code, "exclusive rename failed: " ++ message}}
    case Done{Unit{}}:
      do IO<Result<&1, &1, Error, Unit>>:
        _checkpoint : Result<&1, &1, U32 & String, Unit> <-
          CrashPoint.hit("restore.renamed")
        synced : Result<&1, &1, U32 & String, Unit> <-
          Fs.fsync(path.clone(destination ++ "/.."))
        published : Result<&1, &1, Error, Unit> <- publish.parent.synced(synced)
        return published

def publish.synced(
  +destination: String,
  +temporary: String,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, Error, Unit>):
  match result:
    case Fail{(code, message)}:
      do IO<Result<&1, &1, Error, Unit>>:
        cleanup.directory(temporary)
        return Fail{Io{code, "staged directory sync failed: " ++ message}}
    case Done{Unit{}}:
      do IO<Result<&1, &1, Error, Unit>>:
        _checkpoint : Result<&1, &1, U32 & String, Unit> <-
          CrashPoint.hit("restore.before_rename")
        renamed : Result<&1, &1, U32 & String, Unit> <-
          Fs.rename_noreplace(path.clone(temporary), path.clone(destination))
        published : Result<&1, &1, Error, Unit> <- publish.renamed(destination, temporary, renamed)
        return published

def publish.verified(
  +destination: String,
  +temporary: String,
  result: Result<&1, &1, Error, Unit>
) -> IO(Result<&1, &1, Error, Unit>):
  match result:
    case Fail{error}: IO.pure(Result<&1, &1, Error, Unit>, Fail{error})
    case Done{Unit{}}:
      do IO<Result<&1, &1, Error, Unit>>:
        synced : Result<&1, &1, U32 & String, Unit> <- Fs.fsync(path.clone(temporary))
        published : Result<&1, &1, Error, Unit> <- publish.synced(destination, temporary, synced)
        return published

# Reopens staged data and checks that recovery sees the expected record count.
def publish(
  +destination: String,
  +temporary: String,
  expected: Nat
) -> IO(Result<&1, &1, Error, Unit>):
  do IO<Result<&1, &1, Error, Unit>>:
    opened : Result<&1, &1, Db.Error, Db.Handle> <- Db.open_existing(path.clone(temporary))
    verified : Result<&1, &1, Error, Unit> <- verified(temporary, expected, opened)
    published : Result<&1, &1, Error, Unit> <- publish.verified(destination, temporary, verified)
    return published

def publish.result(
  destination: String,
  temporary: String,
  expected: Nat,
  populated: Result<&1, &1, Error, Unit>
) -> IO(Result<&1, &1, Error, Unit>):
  match populated:
    case Fail{error}: IO.pure(Result<&1, &1, Error, Unit>, Fail{error})
    case Done{Unit{}}: publish(destination, temporary, expected)


def temporary.create(
  +destination: String,
  +temporary: String,
  created: Result<&1, &1, Db.Error, Db.Handle>,
  measured: List<&1, ByteMemTable.Entry> & Nat
) -> IO(Result<&1, &1, Error, Unit>):
  match created:
    case Fail{error}: IO.pure(Result<&1, &1, Error, Unit>, Fail{Storage{error}})
    case Done{handle}:
      match measured:
        case (entries, +count):
          do IO<Result<&1, &1, Error, Unit>>:
            written : Db.Handle & Result<&1, &1, Db.Error, Unit> <-
              write.loop(RestorePolicy.write.fuel(count),
                WriteNeed{handle, entries})
            populated : Result<&1, &1, Error, Unit> <- write.result.path(temporary, written)
            published : Result<&1, &1, Error, Unit> <-
              publish.result(destination, temporary, count, populated)
            return published


def temporary.decoded(
  +destination: String,
  +temporary: String,
  decoded: Result<&1, &1, Restore.Error, Restore.Decoded>
) -> IO(Result<&1, &1, Error, Unit>):
  match decoded:
    case Fail{error}:
      IO.pure(Result<&1, &1, Error, Unit>, Fail{decode.error(error)})
    case Done{Restore.Decoded{entries}}:
      do IO<Result<&1, &1, Error, Unit>>:
        created : Result<&1, &1, Db.Error, Db.Handle> <- Db.create(path.clone(temporary))
        result : Result<&1, &1, Error, Unit> <- temporary.create(destination,
          temporary, created, ByteMemTable.count.keep(entries))
        return result


def temporary.checked(
  +destination: String,
  +temporary: String,
  input: Bytes.Bytes,
  result: Result<&1, &1, U32 & String, Bool>
) -> IO(Result<&1, &1, Error, Unit>):
  match result:
    case Fail{(code, message)}:
      IO.pure(Result<&1, &1, Error, Unit>, Fail{Io{code, message}})
    case Done{True{}}:
      IO.pure(Result<&1, &1, Error, Unit>, Fail{TemporaryExists{}})
    case Done{False{}}:
      temporary.decoded(destination, temporary, Restore.decode(input))

def destination.checked(
  +destination: String,
  +temporary: String,
  input: Bytes.Bytes,
  result: Result<&1, &1, U32 & String, Bool>
) -> IO(Result<&1, &1, Error, Unit>):
  match result:
    case Fail{(code, message)}:
      IO.pure(Result<&1, &1, Error, Unit>, Fail{Io{code, message}})
    case Done{True{}}:
      IO.pure(Result<&1, &1, Error, Unit>, Fail{DestinationExists{}})
    case Done{False{}}:
      do IO<Result<&1, &1, Error, Unit>>:
        exists : Result<&1, &1, U32 & String, Bool> <- Fs.exists(path.clone(temporary))
        temporary.checked(destination, temporary, input, exists)


# Validates an exchange before staging and atomically publishing a database.
def restore(
  +destination: String,
  input: Bytes.Bytes
) -> IO(Result<&1, &1, Error, Unit>):
  +temporary = path.clone(destination ++ ".restore-060.tmp")
  do IO<Result<&1, &1, Error, Unit>>:
    exists : Result<&1, &1, U32 & String, Bool> <- Fs.exists(path.clone(destination))
    destination.checked(destination, temporary, input, exists)

def source.read.length(
  +destination: String,
  input: Bytes.Bytes,
  equal: Bool
) -> IO(Result<&1, &1, Error, Unit>):
  match equal:
    case False{}: IO.pure(Result<&1, &1, Error, Unit>, Fail{InvalidFormat{}})
    case True{}: restore(destination, input)

def source.read.checked(
  +destination: String,
  +expected_size: Nat,
  input: Bytes.Bytes
) -> IO(Result<&1, &1, Error, Unit>):
  match input:
    case Bytes.Bytes{+len, _}:
      source.read.length(destination, input,
        Nat.is_eq(U32.to_nat(len), expected_size))

def source.read.result(
  +destination: String,
  +expected_size: Nat,
  pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>
) -> IO(Result<&1, &1, Error, Unit>):
  match pair:
    case (file, Fail{(code, message)}):
      do IO<Result<&1, &1, Error, Unit>>:
        _closed : Unit <- File.close(file)
        return Fail{Io{code, message}}
    case (file, Done{input}):
      do IO<Result<&1, &1, Error, Unit>>:
        _closed : Unit <- File.close(file)
        source.read.checked(destination, expected_size, input)

def source.opened(
  +destination: String,
  +size: Nat,
  opened: Result<&1, &1, U32 & String, File>
) -> IO(Result<&1, &1, Error, Unit>):
  match opened:
    case Fail{(code, message)}:
      IO.pure(Result<&1, &1, Error, Unit>, Fail{Io{code, message}})
    case Done{file}:
      do IO<Result<&1, &1, Error, Unit>>:
        pair : File & Result<&1, &1, U32 & String, Bytes.Bytes> <-
          Fs.read_at(file, 0, U32.from_nat(size))
        source.read.result(destination, size, pair)

def source.sized.checked(
  +destination: String,
  +source: String,
  size: Nat,
  valid: Bool
) -> IO(Result<&1, &1, Error, Unit>):
  match valid:
    case False{}:
      IO.pure(Result<&1, &1, Error, Unit>, Fail{ResourceLimit{}})
    case True{}:
      do IO<Result<&1, &1, Error, Unit>>:
        opened : Result<&1, &1, U32 & String, File> <- File.open(source, "r")
        source.opened(destination, size, opened)

def source.sized(
  +destination: String,
  +source: String,
  +size: Nat
) -> IO(Result<&1, &1, Error, Unit>):
  source.sized.checked(destination, source, size,
    RestorePolicy.exchange.fits(RestorePolicy.max.exchange.bytes(), size))

def source.size(
  +destination: String,
  +source: String,
  measured: Result<&1, &1, U32 & String, Nat>
) -> IO(Result<&1, &1, Error, Unit>):
  match measured:
    case Fail{(code, message)}:
      IO.pure(Result<&1, &1, Error, Unit>, Fail{Io{code, message}})
    case Done{size}: source.sized(destination, source, size)

# Reads a bounded backup bundle file and restores its validated exchange.
def restore_from(
  +destination: String,
  +bundle: String
) -> IO(Result<&1, &1, Error, Unit>):
  do IO<Result<&1, &1, Error, Unit>>:
    measured : Result<&1, &1, U32 & String, Nat> <- Fs.file_size(bundle ++ "/BACKUP")
    source.size(destination, bundle ++ "/BACKUP", measured)

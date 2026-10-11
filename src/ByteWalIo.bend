import Base
import ./ByteMemTable.bend as ByteMemTable
import ./ByteWal.bend as ByteWal
import ./Fs.bend as Fs
import ./SstStreamIo.bend as SstStreamIo
import ./Wal.bend as Wal
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Tracks the owned file and bounded phase state during byte WAL replay.
type RecoveryState is Type:
  At{file: File, size: Nat, offset: Nat, table: ByteMemTable.Table,
    at_end: Bool, can_read_length: Bool}
  Length{pair: File & Result<&1, &1, U32 & String, SstStreamIo.ExactResult>,
    size: Nat, offset: Nat, table: ByteMemTable.Table}
  Prefix{file: File, size: Nat, offset: Nat, table: ByteMemTable.Table,
    prefix: Bytes.Bytes, frame_length: U32, within_file: Bool}
  Count{pair: File & Result<&1, &1, U32 & String, SstStreamIo.ExactResult>,
    size: Nat, offset: Nat, table: ByteMemTable.Table,
    prefix: Bytes.Bytes, frame_length: U32}
  Counted{file: File, size: Nat, offset: Nat, table: ByteMemTable.Table,
    prefix: Bytes.Bytes, count_bytes: Bytes.Bytes, frame_length: U32,
    within_limit: Bool}
  Body{pair: File & Result<&1, &1, U32 & String, SstStreamIo.ExactResult>,
    size: Nat, offset: Nat, table: ByteMemTable.Table,
    prefix: Bytes.Bytes, count_bytes: Bytes.Bytes, frame_length: U32}
  Decoded{file: File, size: Nat, next_offset: Nat,
    table: ByteMemTable.Table,
    result: Result<&1, &1, Wal.Error, ByteWal.Batch>}
  Failed{file: File, error: U32 & String}
  Tail{file: File, path: String, offset: Nat, table: ByteMemTable.Table}

# Assigns the stable file-corruption category used by this reader.
def corruption_error_code() -> U32:
  4294967292

# Pairs a corruption category with its diagnostic text.
def error(message: String) -> U32 & String:
  (corruption_error_code(), message)

def u32.read(pair: Bytes.Cursor & Maybe<&2, U32>) -> Maybe<&2, U32>:
  match pair:
    case (_, value):
      value

def frame.length(bytes: Bytes.Bytes) -> Maybe<&2, U32>:
  u32.read(Bytes.Cursor.u32be(Bytes.Cursor.new(bytes)))

def frame.count(bytes: Bytes.Bytes) -> Maybe<&2, U32>:
  frame.length(bytes)

def recover.at(
  file: File,
  +size: Nat,
  +offset: Nat,
  table: ByteMemTable.Table
) -> RecoveryState:
  At{file, size, offset, table, Nat.is_eq(offset, size),
    Nat.is_le(Nat.add(offset, 4n), size)}

def recover.prefix.next(
  file: File,
  +size: Nat,
  +offset: Nat,
  table: ByteMemTable.Table,
  prefix: Bytes.Bytes,
  parsed: Maybe<&2, U32>
) -> RecoveryState:
  match parsed:
    case None{}:
      Failed{file, error("malformed byte WAL frame length")}
    case Some{+frame_length}:
      Prefix{file, size, offset, table, prefix, frame_length,
        Nat.is_le(Nat.add(offset, Nat.add(4n, U32.to_nat(frame_length))), size) &&
          U32.is_le(36, frame_length)}

def recover.prefix.cloned(
  file: File,
  pair: Bytes.Bytes & Bytes.Bytes,
  +size: Nat,
  +offset: Nat,
  table: ByteMemTable.Table
) -> RecoveryState:
  match pair:
    case (prefix, inspected):
      recover.prefix.next(file, size, offset, table,
        prefix, frame.length(inspected))

def recover.length.next(
  pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>,
  +size: Nat,
  +offset: Nat,
  table: ByteMemTable.Table
) -> RecoveryState:
  match pair:
    case (file, Fail{failure}):
      Failed{file, failure}
    case (file, Done{prefix}):
      recover.prefix.cloned(file, Wal.bytes.clone.split(prefix),
        size, offset, table)

def recover.counted(
  file: File,
  +size: Nat,
  +offset: Nat,
  table: ByteMemTable.Table,
  prefix: Bytes.Bytes,
  count_bytes: Bytes.Bytes,
  +frame_length: U32,
  parsed: Maybe<&2, U32>
) -> RecoveryState:
  match parsed:
    case None{}:
      Failed{file, error("malformed byte WAL frame count")}
    case Some{+count}:
      Counted{file, size, offset, table, prefix, count_bytes,
        frame_length, Wal.frame_length_allowed(count, frame_length)}

def recover.count.cloned(
  file: File,
  pair: Bytes.Bytes & Bytes.Bytes,
  +size: Nat,
  +offset: Nat,
  table: ByteMemTable.Table,
  prefix: Bytes.Bytes,
  +frame_length: U32
) -> RecoveryState:
  match pair:
    case (count_bytes, inspected):
      recover.counted(file, size, offset, table, prefix,
        count_bytes, frame_length, frame.count(inspected))

def recover.count.next(
  pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>,
  +size: Nat,
  +offset: Nat,
  table: ByteMemTable.Table,
  prefix: Bytes.Bytes,
  +frame_length: U32
) -> RecoveryState:
  match pair:
    case (file, Fail{failure}):
      Failed{file, failure}
    case (file, Done{count_bytes}):
      recover.count.cloned(file, Wal.bytes.clone.split(count_bytes),
        size, offset, table, prefix, frame_length)

def recover.body.next(
  pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>,
  +size: Nat,
  +offset: Nat,
  table: ByteMemTable.Table,
  prefix: Bytes.Bytes,
  count_bytes: Bytes.Bytes,
  +frame_length: U32
) -> RecoveryState:
  match pair:
    case (file, Fail{failure}):
      Failed{file, failure}
    case (file, Done{tail}):
      Decoded{file, size,
        Nat.add(offset, Nat.add(4n, U32.to_nat(frame_length))), table,
        ByteWal.decode(Bytes.concat([prefix, count_bytes, tail]))}

def apply.batch.loop(
  fuel: Nat,
  table: ByteMemTable.Table,
  mutations: List<&1, ByteWal.Mutation>
) -> ByteMemTable.Table:
  match fuel:
    case 0n:
      table
    case 1n+rest:
      match mutations:
        case Nil{}:
          table
        case Con{ByteWal.Put{key, value}, tail}:
          apply.batch.loop(rest, ByteMemTable.put(table, key, value), tail)
        case Con{ByteWal.Delete{key}, tail}:
          apply.batch.loop(rest, ByteMemTable.del(table, key), tail)

def mutations.count.go(
  mutations: List<&1, ByteWal.Mutation>,
  reversed: List<&1, ByteWal.Mutation>,
  count: Nat
) -> List<&1, ByteWal.Mutation> & Nat:
  match mutations:
    case Nil{}:
      (List.reverse(&1, ByteWal.Mutation, reversed), count)
    case Con{mutation, tail}:
      mutations.count.go(tail, Con{mutation, reversed}, Nat.add(count, 1n))

def mutations.count(mutations: List<&1, ByteWal.Mutation>) -> List<&1, ByteWal.Mutation> & Nat:
  mutations.count.go(mutations, Nil{}, 0n)

def apply.batch.counted(
  table: ByteMemTable.Table,
  pair: List<&1, ByteWal.Mutation> & Nat
) -> ByteMemTable.Table:
  match pair:
    case (mutations, count):
      apply.batch.loop(Nat.add(count, 1n), table, mutations)

def apply.batch(table: ByteMemTable.Table, batch: ByteWal.Batch) -> ByteMemTable.Table:
  match batch:
    case ByteWal.Batch{mutations}:
      apply.batch.counted(table, mutations.count(mutations))

def close.failed(file: File, failure: U32 & String) -> IO(Result<&1, &1, U32 & String, ByteMemTable.Table>):
  do IO<Result<&1, &1, U32 & String, ByteMemTable.Table>>:
    _closed : Unit <- File.close(file)
    return Fail{failure}

def close.done(file: File, table: ByteMemTable.Table) -> IO(Result<&1, &1, U32 & String, ByteMemTable.Table>):
  do IO<Result<&1, &1, U32 & String, ByteMemTable.Table>>:
    _closed : Unit <- File.close(file)
    return Done{table}

def recover.exhausted(state: RecoveryState) -> IO(Result<&1, &1, U32 & String, ByteMemTable.Table>):
  match state:
    case At{file, _, _, _, _, _}:
      close.failed(file, error("byte WAL recovery limit exceeded"))
    case Length{pair, _, _, _}:
      match pair:
        case (file, _):
          close.failed(file, error("byte WAL recovery limit exceeded"))
    case Prefix{file, _, _, _, _, _, _}:
      close.failed(file, error("byte WAL recovery limit exceeded"))
    case Count{pair, _, _, _, _, _}:
      match pair:
        case (file, _):
          close.failed(file, error("byte WAL recovery limit exceeded"))
    case Counted{file, _, _, _, _, _, _, _}:
      close.failed(file, error("byte WAL recovery limit exceeded"))
    case Body{pair, _, _, _, _, _, _}:
      match pair:
        case (file, _):
          close.failed(file, error("byte WAL recovery limit exceeded"))
    case Decoded{file, _, _, _, _}:
      close.failed(file, error("byte WAL recovery limit exceeded"))
    case Failed{file, failure}:
      close.failed(file, failure)
    case Tail{file, _, _, _}:
      close.failed(file, error("byte WAL recovery limit exceeded"))

def recover.length.completed(
  +path: String,
  file: File,
  +size: Nat,
  +offset: Nat,
  table: ByteMemTable.Table,
  bytes: Bytes.Bytes,
  complete: Bool
) -> RecoveryState:
  match complete:
    case False{}:
      Tail{file, path, offset, table}
    case True{}:
      recover.prefix.cloned(file, Wal.bytes.clone.split(bytes), size, offset, table)

def recover.count.completed(
  +path: String,
  file: File,
  +size: Nat,
  +offset: Nat,
  table: ByteMemTable.Table,
  prefix: Bytes.Bytes,
  bytes: Bytes.Bytes,
  complete: Bool,
  +frame_length: U32
) -> RecoveryState:
  match complete:
    case False{}:
      Tail{file, path, offset, table}
    case True{}:
      recover.count.cloned(file, Wal.bytes.clone.split(bytes), size, offset, table, prefix, frame_length)

def tail.synced(
  result: Result<&1, &1, U32 & String, Unit>,
  table: ByteMemTable.Table
) -> IO(Result<&1, &1, U32 & String, ByteMemTable.Table>):
  match result:
    case Fail{failure}:
      IO.pure(Result<&1, &1, U32 & String, ByteMemTable.Table>, Fail{failure})
    case Done{Unit{}}:
      IO.pure(Result<&1, &1, U32 & String, ByteMemTable.Table>, Done{table})

def tail.truncated(
  result: Result<&1, &1, U32 & String, Unit>,
  +path: String,
  table: ByteMemTable.Table
) -> IO(Result<&1, &1, U32 & String, ByteMemTable.Table>):
  match result:
    case Fail{failure}:
      IO.pure(Result<&1, &1, U32 & String, ByteMemTable.Table>, Fail{failure})
    case Done{Unit{}}:
      do IO<Result<&1, &1, U32 & String, ByteMemTable.Table>>:
        synced : Result<&1, &1, U32 & String, Unit> <- Fs.fsync(path)
        tail.synced(synced, table)

def tail.closed(
  +path: String,
  +offset: Nat,
  table: ByteMemTable.Table
) -> IO(Result<&1, &1, U32 & String, ByteMemTable.Table>):
  do IO<Result<&1, &1, U32 & String, ByteMemTable.Table>>:
    truncated : Result<&1, &1, U32 & String, Unit> <- Fs.truncate(path, offset)
    tail.truncated(truncated, path, table)

def recover.result(
  +path: String,
  fuel: Nat,
  state: RecoveryState
) -> IO(Result<&1, &1, U32 & String, ByteMemTable.Table>):
  match fuel:
    case 0n:
      recover.exhausted(state)
    case 1n+rest:
      match state:
        case Tail{file, path, +offset, table}:
          do IO<Result<&1, &1, U32 & String, ByteMemTable.Table>>:
            _closed : Unit <- File.close(file)
            tail.closed(path, offset, table)
        case At{file, +size, +offset, table, at_end, can_read_length}:
          match at_end:
            case True{}:
              close.done(file, table)
            case False{}:
              match can_read_length:
                case False{}:
                  recover.result(path, rest, Tail{file, path, offset, table})
                case True{}:
                  do IO<Result<&1, &1, U32 & String, ByteMemTable.Table>>:
                    pair : File & Result<&1, &1, U32 & String, SstStreamIo.ExactResult> <-
                      SstStreamIo.exact.start(file, 4n)
                    recover.result(path, rest, Length{pair, size, offset, table})
        case Length{pair, +size, +offset, table}:
          match pair:
            case (file, Fail{failure}):
              close.failed(file, failure)
            case (file, Done{SstStreamIo.ExactResult{bytes, complete}}):
              recover.result(path, rest, recover.length.completed(path, file, size, offset, table, bytes, complete))
        case Prefix{file, +size, +offset, table, prefix, +frame_length, within_file}:
          match within_file:
            case False{}:
              recover.result(path, rest, Tail{file, path, offset, table})
            case True{}:
              do IO<Result<&1, &1, U32 & String, ByteMemTable.Table>>:
                pair : File & Result<&1, &1, U32 & String, SstStreamIo.ExactResult> <-
                  SstStreamIo.exact.start(file, 4n)
                recover.result(path, rest, Count{pair, size, offset, table,
                  prefix, frame_length})
        case Count{pair, +size, +offset, table, prefix, +frame_length}:
          match pair:
            case (file, Fail{failure}):
              close.failed(file, failure)
            case (file, Done{SstStreamIo.ExactResult{bytes, complete}}):
              recover.result(path, rest, recover.count.completed(path, file, size, offset, table, prefix, bytes, complete, frame_length))
        case Counted{file, +size, +offset, table, prefix, count_bytes,
            +frame_length, within_limit}:
          match within_limit:
            case False{}:
              close.failed(file, error("byte WAL frame exceeds configured limit"))
            case True{}:
              do IO<Result<&1, &1, U32 & String, ByteMemTable.Table>>:
                pair : File & Result<&1, &1, U32 & String, SstStreamIo.ExactResult> <-
                  SstStreamIo.exact.start(file, U32.to_nat((frame_length - 4 : U32)))
                recover.result(path, rest, Body{pair, size, offset, table,
                  prefix, count_bytes, frame_length})
        case Body{pair, +size, +offset, table, prefix, count_bytes, +frame_length}:
          match pair:
            case (file, Fail{failure}):
              close.failed(file, failure)
            case (file, Done{SstStreamIo.ExactResult{bytes, complete}}):
              match complete:
                case False{}:
                  recover.result(path, rest, Tail{file, path, offset, table})
                case True{}:
                  recover.result(path, rest, Decoded{file, size,
                    Nat.add(offset, Nat.add(4n, U32.to_nat(frame_length))), table,
                    ByteWal.decode(Bytes.concat([prefix, count_bytes, bytes]))})
        case Decoded{file, +size, +next_offset, table, result}:
          match result:
            case Fail{_}:
              close.failed(file, error("corrupt byte WAL frame"))
            case Done{batch}:
              recover.result(path, rest, recover.at(file, size, next_offset,
                apply.batch(table, batch)))
        case Failed{file, failure}:
          close.failed(file, failure)

def header.checked(
  +path: String,
  file: File,
  +size: Nat,
  result: Result<&1, &1, Wal.Error, Unit>,
  initial: ByteMemTable.Table
) -> IO(Result<&1, &1, U32 & String, ByteMemTable.Table>):
  match result:
    case Fail{_}:
      close.failed(file, error("unsupported byte WAL format"))
    case Done{Unit{}}:
      recover.result(path, Nat.add(Nat.mul(size, 8n), 8n),
        recover.at(file, size, 8n, initial))

def header.valid(
  +path: String,
  file: File,
  +size: Nat,
  result: Result<&1, &1, U32 & String, Bytes.Bytes>,
  initial: ByteMemTable.Table
) -> IO(Result<&1, &1, U32 & String, ByteMemTable.Table>):
  match result:
    case Fail{failure}:
      close.failed(file, failure)
    case Done{bytes}:
      header.checked(path, file, size, ByteWal.decode_header(bytes), initial)

def header.pair(
  +path: String,
  +size: Nat,
  pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>,
  initial: ByteMemTable.Table
) -> IO(Result<&1, &1, U32 & String, ByteMemTable.Table>):
  match pair:
    case (file, result):
      header.valid(path, file, size, result, initial)

def recover.opened(
  +path: String,
  +size: Nat,
  opened: Result<&1, &1, U32 & String, File>,
  initial: ByteMemTable.Table
) -> IO(Result<&1, &1, U32 & String, ByteMemTable.Table>):
  match opened:
    case Fail{failure}:
      IO.pure(Result<&1, &1, U32 & String, ByteMemTable.Table>, Fail{failure})
    case Done{file}:
      do IO<Result<&1, &1, U32 & String, ByteMemTable.Table>>:
        pair : File & Result<&1, &1, U32 & String, SstStreamIo.ExactResult> <-
          SstStreamIo.exact.start(file, 8n)
        header.pair(path, size, SstStreamIo.read.exact.state(pair), initial)

def recover.size.checked(
  +path: String,
  +size: Nat,
  valid: Bool,
  initial: ByteMemTable.Table
) -> IO(Result<&1, &1, U32 & String, ByteMemTable.Table>):
  match valid:
    case False{}:
      IO.pure(Result<&1, &1, U32 & String, ByteMemTable.Table>,
        Fail{error("malformed or oversized byte WAL")})
    case True{}:
      do IO<Result<&1, &1, U32 & String, ByteMemTable.Table>>:
        opened : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
        recover.opened(path, size, opened, initial)

def recover.sized(
  +path: String,
  result: Result<&1, &1, U32 & String, Nat>,
  initial: ByteMemTable.Table
) -> IO(Result<&1, &1, U32 & String, ByteMemTable.Table>):
  match result:
    case Fail{failure}:
      IO.pure(Result<&1, &1, U32 & String, ByteMemTable.Table>, Fail{failure})
    case Done{+size}:
      recover.size.checked(path, size,
        Nat.is_le(8n, size) && Nat.is_le(size, 4294967295n), initial)


def recover.from(+path: String, initial: ByteMemTable.Table) -> IO(Result<&1, &1, U32 & String, ByteMemTable.Table>):
  do IO<Result<&1, &1, U32 & String, ByteMemTable.Table>>:
    size : Result<&1, &1, U32 & String, Nat> <- Fs.file_size(path)
    recover.sized(path, size, initial)

# Replays the byte WAL over an empty initial mutation table.
def recover(+path: String) -> IO(Result<&1, &1, U32 & String, ByteMemTable.Table>):
  recover.from(path, ByteMemTable.empty())

# Publishes a fresh WAL header without exposing a partially truncated active file.
def create.closed(
  result: Result<&1, &1, U32 & String, Unit>,
  +path: String
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match result:
    case Fail{failure}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{failure})
    case Done{Unit{}}:
      Fs.fsync(path)

def create.written(
  pair: File & Result<&1, &1, U32 & String, Unit>,
  +path: String
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match pair:
    case (file, result):
      do IO<Result<&1, &1, U32 & String, Unit>>:
        _closed : Unit <- File.close(file)
        create.closed(result, path)

def create.opened(
  opened: Result<&1, &1, U32 & String, File>,
  +path: String
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match opened:
    case Fail{failure}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{failure})
    case Done{file}:
      do IO<Result<&1, &1, U32 & String, Unit>>:
        pair : File & Result<&1, &1, U32 & String, Unit> <-
          Fs.write_bytes(file, ByteWal.header())
        create.written(pair, path)

# Creates and durably publishes an empty generation-four byte WAL.
def create(+path: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  do IO<Result<&1, &1, U32 & String, Unit>>:
    opened : Result<&1, &1, U32 & String, File> <- File.open(path, "w")
    create.opened(opened, path)

def reset.directory.synced(
  +directory: String,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match result:
    case Fail{failure}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{failure})
    case Done{Unit{}}:
      Fs.fsync(directory)

# Creates and syncs a replacement WAL before atomic publication.

def reset.published(
  +directory: String,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match result:
    case Fail{failure}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{failure})
    case Done{Unit{}}:
      do IO<Result<&1, &1, U32 & String, Unit>>:
        renamed : Result<&1, &1, U32 & String, Unit> <-
          Fs.rename(directory ++ "/WAL.tmp", directory ++ "/WAL")
        reset.directory.synced(directory, renamed)

# Syncs the directory entry after atomically replacing the active WAL.

# Replaces the active WAL only after its new header is synced.
def reset_atomic(+directory: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  do IO<Result<&1, &1, U32 & String, Unit>>:
    created : Result<&1, &1, U32 & String, Unit> <- create(directory ++ "/WAL.tmp")
    reset.published(directory, created)


def append.synced(
  result: Result<&1, &1, U32 & String, Unit>,
  file: File,
  +path: String
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match result:
    case Fail{failure}:
      do IO<Result<&1, &1, U32 & String, Unit>>:
        _closed : Unit <- File.close(file)
        return Fail{failure}
    case Done{Unit{}}:
      do IO<Result<&1, &1, U32 & String, Unit>>:
        _closed : Unit <- File.close(file)
        Fs.fsync(path)

def append.written(
  pair: File & Result<&1, &1, U32 & String, Unit>,
  +path: String
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match pair:
    case (file, result):
      append.synced(result, file, path)

def append.opened(
  opened: Result<&1, &1, U32 & String, File>,
  frame: Bytes.Bytes,
  +path: String
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match opened:
    case Fail{failure}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{failure})
    case Done{file}:
      do IO<Result<&1, &1, U32 & String, Unit>>:
        pair : File & Result<&1, &1, U32 & String, Unit> <- Fs.write_bytes(file, frame)
        append.written(pair, path)

def append.encoded(
  result: Result<&1, &1, Wal.Error, Bytes.Bytes>,
  +path: String
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match result:
    case Fail{_}:
      IO.pure(Result<&1, &1, U32 & String, Unit>,
        Fail{(3, "byte WAL batch cannot be encoded")})
    case Done{frame}:
      do IO<Result<&1, &1, U32 & String, Unit>>:
        opened : Result<&1, &1, U32 & String, File> <- File.open(path, "a")
        append.opened(opened, frame, path)

# Appends one encoded batch and syncs the resulting WAL file.
def append(+path: String, batch: ByteWal.Batch) -> IO(Result<&1, &1, U32 & String, Unit>):
  append.encoded(ByteWal.encode(batch), path)

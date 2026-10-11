import Base
import ./ByteSstFile.bend as ByteSstFile
import ./ByteMemTable.bend as ByteMemTable
import ./Fs.bend as Fs
import ./scan/ByteBlockReader.bend as ByteBlockReader
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

def path.clone.reverse(path: String, reversed: String) -> String:
  match path:
    case SNil{}: reversed
    case SCon{character, rest}:
      path.clone.reverse(rest, SCon{character, reversed})

def path.clone(path: String) -> String:
  path.clone.reverse(path.clone.reverse(path, SNil{}), SNil{})

def nat.clone.pair.step(pair: Nat & Nat) -> Nat & Nat:
  match pair:
    case (left, right): (Nat.add(left, 1n), Nat.add(right, 1n))

def nat.clone.pair(value: Nat) -> Nat & Nat:
  match value:
    case 0n: (0n, 0n)
    case 1n+rest: nat.clone.pair.step(nat.clone.pair(rest))

def path.clone.pair.scalar(
  first: String,
  second: String,
  scalars: Nat & Nat
) -> String & String:
  match scalars:
    case (left, right):
      (SCon{Chr{U32.from_nat(left)}, first},
        SCon{Chr{U32.from_nat(right)}, second})

def path.clone.pair.build(
  path: String,
  copies: String & String
) -> String & String:
  match path:
    case SNil{}:
      match copies:
        case (left, right): (path.clone.reverse(left, SNil{}), path.clone.reverse(right, SNil{}))
    case SCon{Chr{+scalar}, rest}:
      match copies:
        case (left, right):
          path.clone.pair.build(rest,
            path.clone.pair.scalar(left, right,
              nat.clone.pair(U32.to_nat(scalar))))

def path.clone.pair(path: String) -> String & String:
  path.clone.pair.build(path, (SNil{}, SNil{}))

# Carries the reader or its latest step through blockwise recovery.
type ReadState is Type:
  ReadNeed{reader: ByteBlockReader.Reader, table: ByteMemTable.Table}
  ReadStep{result: Result<&1, &1, U32 & String, ByteBlockReader.Step>,
    table: ByteMemTable.Table}

# Carries only bounded reader state and compact file metadata during validation.
type ValidationState is Type:
  ValidateNeed{reader: ByteBlockReader.Reader,
    metadata: ByteBlockReader.Metadata}
  ValidateStep{result: Result<&1, &1, U32 & String, ByteBlockReader.Step>,
    metadata: ByteBlockReader.Metadata}
  ValidatePage{reader: ByteBlockReader.Reader,
    metadata: ByteBlockReader.Metadata, entries: List<&1, ByteMemTable.Entry>}

# Classifies malformed or oversized byte SST files as corruption.
def corruption(message: String) -> U32 & String:
  (4294967292, message)

def validate.page(
  entries: List<&1, ByteMemTable.Entry>,
  metadata: ByteBlockReader.Metadata
) -> ByteBlockReader.Metadata:
  match entries:
    case Nil{}: metadata
    case Con{ByteMemTable.Entry{Bytes.Bytes{+key_len, _}, val}, tail}:
      match val:
        case None{}: validate.page(tail, metadata)
        case Some{Bytes.Bytes{+value_len, _}}:
          match metadata:
            case ByteBlockReader.Metadata{size, total, block_count, index_offset,
                live_entries, payload_bytes}:
              validate.page(tail, ByteBlockReader.Metadata{size, total, block_count,
                index_offset, Nat.add(live_entries, 1n),
                Nat.add(payload_bytes, Nat.add(U32.to_nat(key_len),
                  U32.to_nat(value_len)))})

# Advances full-file validation without retaining decoded SST entries.
def validate.loop(
  fuel: Nat,
  state: ValidationState
) -> IO(Result<&1, &1, U32 & String, ByteBlockReader.Metadata>):
  match fuel:
    case 0n:
      match state:
        case ValidateNeed{reader, _}:
          do IO<Result<&1, &1, U32 & String, ByteBlockReader.Metadata>>:
            _closed : Result<&1, &1, U32 & String, Unit> <-
              ByteBlockReader.close(reader)
            return Fail{corruption("byte SST validation exceeded its block budget")}
        case ValidatePage{reader, _, _}:
          do IO<Result<&1, &1, U32 & String, ByteBlockReader.Metadata>>:
            _closed : Result<&1, &1, U32 & String, Unit> <-
              ByteBlockReader.close(reader)
            return Fail{corruption("byte SST validation exceeded its block budget")}
        case ValidateStep{result, _}:
          match result:
            case Done{ByteBlockReader.Block{reader, _}}:
              do IO<Result<&1, &1, U32 & String, ByteBlockReader.Metadata>>:
                _closed : Result<&1, &1, U32 & String, Unit> <-
                  ByteBlockReader.close(reader)
                return Fail{corruption("byte SST validation exceeded its block budget")}
            case Fail{error}:
              IO.pure(Result<&1, &1, U32 & String, ByteBlockReader.Metadata>, Fail{error})
            case _: IO.pure(
              Result<&1, &1, U32 & String, ByteBlockReader.Metadata>,
              Fail{corruption("byte SST validation exhausted its transition limit")})
    case 1n+rest:
      match state:
        case ValidateNeed{reader, metadata}:
          do IO<Result<&1, &1, U32 & String, ByteBlockReader.Metadata>>:
            result : Result<&1, &1, U32 & String, ByteBlockReader.Step> <-
              ByteBlockReader.next(reader)
            validate.loop(rest, ValidateStep{result, metadata})
        case ValidatePage{reader, metadata, entries}:
          validate.loop(rest, ValidateNeed{reader, validate.page(entries, metadata)})
        case ValidateStep{result, metadata}:
          match result:
            case Fail{error}:
              IO.pure(Result<&1, &1, U32 & String, ByteBlockReader.Metadata>, Fail{error})
            case Done{ByteBlockReader.End{}}:
              IO.pure(Result<&1, &1, U32 & String, ByteBlockReader.Metadata>, Done{metadata})
            case Done{ByteBlockReader.Block{reader, entries}}:
              validate.loop(rest, ValidatePage{reader, metadata, entries})

# Starts metadata-only validation with the reader's bounded transition budget.
def validate.budget(
  metadata: ByteBlockReader.Metadata,
  pair: Nat & ByteBlockReader.Reader
) -> IO(Result<&1, &1, U32 & String, ByteBlockReader.Metadata>):
  match pair:
    case (fuel, reader):
      validate.loop(fuel, ValidateNeed{reader, metadata})

# Preserves metadata while deriving the reader budget from its parsed header.
def validate.metadata(
  pair: ByteBlockReader.Metadata & ByteBlockReader.Reader
) -> IO(Result<&1, &1, U32 & String, ByteBlockReader.Metadata>):
  match pair:
    case (metadata, reader):
      validate.budget(metadata, ByteBlockReader.transition_budget(reader))

# Extracts metadata before consuming the reader through the validation pass.
def validate.opened(
  opened: Result<&1, &1, U32 & String, ByteBlockReader.Reader>
) -> IO(Result<&1, &1, U32 & String, ByteBlockReader.Metadata>):
  match opened:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, ByteBlockReader.Metadata>, Fail{error})
    case Done{reader}:
      validate.metadata(ByteBlockReader.metadata(reader))

# Validates an SST incrementally and returns only authenticated metadata.
def validate(+path: String) -> IO(Result<&1, &1, U32 & String, ByteBlockReader.Metadata>):
  do IO<Result<&1, &1, U32 & String, ByteBlockReader.Metadata>>:
    opened : Result<&1, &1, U32 & String, ByteBlockReader.Reader> <-
      ByteBlockReader.open(path)
    validate.opened(opened)

def read.fold(
  entries: List<&1, ByteMemTable.Entry>,
  table: ByteMemTable.Table
) -> ByteMemTable.Table:
  match entries:
    case Nil{}: table
    case Con{ByteMemTable.Entry{key, val}, tail}:
      match val:
        case None{}: read.fold(tail, ByteMemTable.del(table, key))
        case Some{value}: read.fold(tail, ByteMemTable.put(table, key, value))

def read.loop(fuel: Nat, state: ReadState) -> IO(Result<&1, &1, U32 & String, ByteMemTable.Table>):
  match fuel:
    case 0n:
      match state:
        case ReadNeed{reader, _}:
          do IO<Result<&1, &1, U32 & String, ByteMemTable.Table>>:
            _closed : Result<&1, &1, U32 & String, Unit> <- ByteBlockReader.close(reader)
            return Fail{corruption("byte SST block count exceeded reader limit")}
        case ReadStep{result, _}:
          match result:
            case Done{ByteBlockReader.Block{reader, _}}:
              do IO<Result<&1, &1, U32 & String, ByteMemTable.Table>>:
                _closed : Result<&1, &1, U32 & String, Unit> <- ByteBlockReader.close(reader)
                return Fail{corruption("byte SST block count exceeded reader limit")}
            case _: IO.pure(Result<&1, &1, U32 & String, ByteMemTable.Table>,
              Fail{corruption("byte SST reader exhausted its transition limit")})
    case 1n+rest:
      match state:
        case ReadNeed{reader, table}:
          do IO<Result<&1, &1, U32 & String, ByteMemTable.Table>>:
            result : Result<&1, &1, U32 & String, ByteBlockReader.Step> <-
              ByteBlockReader.next(reader)
            read.loop(rest, ReadStep{result, table})
        case ReadStep{result, table}:
          match result:
            case Fail{error}:
              IO.pure(Result<&1, &1, U32 & String, ByteMemTable.Table>, Fail{error})
            case Done{ByteBlockReader.End{}}:
              IO.pure(Result<&1, &1, U32 & String, ByteMemTable.Table>, Done{table})
            case Done{ByteBlockReader.Block{reader, entries}}:
              read.loop(rest, ReadNeed{reader, read.fold(entries, table)})

def read.loop.start(pair: Nat & ByteBlockReader.Reader) -> IO(Result<&1, &1, U32 & String, ByteMemTable.Table>):
  match pair:
    case (fuel, reader):
      read.loop(fuel, ReadNeed{reader, ByteMemTable.empty()})

def read.opened(
  opened: Result<&1, &1, U32 & String, ByteBlockReader.Reader>
) -> IO(Result<&1, &1, U32 & String, ByteMemTable.Table>):
  match opened:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, ByteMemTable.Table>, Fail{error})
    case Done{reader}:
      read.loop.start(ByteBlockReader.transition_budget(reader))

# Syncs the parent directory after SST rename publication.
def write.directory.synced(
  +directory: String,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{error})
    case Done{Unit{}}:
      Fs.fsync(directory)

# Atomically renames the synced temporary SST and syncs its directory.
def write.published(
  +directory: String,
  temporary: String,
  final_path: String,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{error})
    case Done{Unit{}}:
      do IO<Result<&1, &1, U32 & String, Unit>>:
        renamed : Result<&1, &1, U32 & String, Unit> <-
          Fs.rename(temporary, final_path)
        write.directory.synced(directory, renamed)

# Syncs the temporary SST contents before publication.
def write.synced(
  +directory: String,
  temporaries: String & String,
  final_path: String,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match temporaries:
    case (for_sync, for_rename):
      match result:
        case Fail{error}:
          IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{error})
        case Done{Unit{}}:
          do IO<Result<&1, &1, U32 & String, Unit>>:
            synced : Result<&1, &1, U32 & String, Unit> <- Fs.fsync(for_sync)
            write.published(directory, for_rename, final_path, synced)

# Closes the completed temporary-file write before syncing it.
def write.written(
  +directory: String,
  temporary: String,
  final_path: String,
  pair: File & Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match pair:
    case (file, result):
      do IO<Result<&1, &1, U32 & String, Unit>>:
        _closed : Unit <- File.close(file)
        write.synced(directory, path.clone.pair(temporary), final_path, result)

# Writes the encoded SST bytes to the temporary file.
def write.encoded(
  +directory: String,
  temporary: String,
  final_path: String,
  bytes: Bytes.Bytes,
  opened: Result<&1, &1, U32 & String, File>
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match opened:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{error})
    case Done{file}:
      do IO<Result<&1, &1, U32 & String, Unit>>:
        pair : File & Result<&1, &1, U32 & String, Unit> <- Fs.write_bytes(file, bytes)
        write.written(directory, temporary, final_path, pair)

# Closes the temporary file when encoding rejects sorted input.
def write.encoder.failed(
  opened: Result<&1, &1, U32 & String, File>
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match opened:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{error})
    case Done{file}:
      do IO<Result<&1, &1, U32 & String, Unit>>:
        _closed : Unit <- File.close(file)
        return Fail{corruption("byte SST encoder rejected its sorted input")}

# Dispatches a validated encoding result after opening the temporary file.
def write.opened(
  +directory: String,
  temporary: String,
  final_path: String,
  encoded: Result<&1, &1, ByteSstFile.Error, Bytes.Bytes>,
  opened: Result<&1, &1, U32 & String, File>
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match encoded:
    case Fail{_}:
      write.encoder.failed(opened)
    case Done{bytes}:
      write.encoded(directory, temporary, final_path, bytes, opened)

def path.temporary.final(copies: String & String) -> String & String:
  match copies:
    case (temporary_base, final_path):
      (temporary_base ++ ".tmp", final_path)

def write_atomic_at.opened(
  +directory: String,
  temporary_copies: String & String,
  final_path: String,
  entries: List<&1, ByteMemTable.Entry>
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match temporary_copies:
    case (temporary, retained_temporary):
      do IO<Result<&1, &1, U32 & String, Unit>>:
        opened : Result<&1, &1, U32 & String, File> <- File.open(temporary, "w")
        write.opened(directory, retained_temporary, final_path,
          ByteSstFile.encode_file(entries, 0), opened)

def write_atomic_at.paths(
  +directory: String,
  paths: String & String,
  entries: List<&1, ByteMemTable.Entry>
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match paths:
    case (temporary, final_path):
      write_atomic_at.opened(directory, path.clone.pair(temporary),
        final_path, entries)

# Atomically publishes one bounded byte SST at a caller-selected path.
def write_atomic_at(
  +directory: String,
  final_path: String,
  entries: List<&1, ByteMemTable.Entry>
) -> IO(Result<&1, &1, U32 & String, Unit>):
  write_atomic_at.paths(directory,
    path.temporary.final(path.clone.pair(final_path)), entries)

# Encodes and atomically publishes one bounded byte SST snapshot.
def write_atomic(
  +directory: String,
  entries: List<&1, ByteMemTable.Entry>
) -> IO(Result<&1, &1, U32 & String, Unit>):
  write_atomic_at(directory, directory ++ "/SST", entries)

# Reads one decoded block at a time and returns only after footer validation.
def read(+path: String) -> IO(Result<&1, &1, U32 & String, ByteMemTable.Table>):
  do IO<Result<&1, &1, U32 & String, ByteMemTable.Table>>:
    opened : Result<&1, &1, U32 & String, ByteBlockReader.Reader> <-
      ByteBlockReader.open(path)
    read.opened(opened)

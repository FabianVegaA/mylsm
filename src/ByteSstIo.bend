import Base
import ./ByteSstFile.bend as ByteSstFile
import ./ByteMemTable.bend as ByteMemTable
import ./Fs.bend as Fs
import ./scan/ByteBlockReader.bend as ByteBlockReader
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

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
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{error})
    case Done{Unit{}}:
      do IO<Result<&1, &1, U32 & String, Unit>>:
        renamed : Result<&1, &1, U32 & String, Unit> <-
          Fs.rename(directory ++ "/SST.tmp", directory ++ "/SST")
        write.directory.synced(directory, renamed)

# Syncs the temporary SST contents before publication.
def write.synced(
  +directory: String,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{error})
    case Done{Unit{}}:
      do IO<Result<&1, &1, U32 & String, Unit>>:
        synced : Result<&1, &1, U32 & String, Unit> <- Fs.fsync(directory ++ "/SST.tmp")
        write.published(directory, synced)

# Closes the completed temporary-file write before syncing it.
def write.written(
  +directory: String,
  pair: File & Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match pair:
    case (file, result):
      do IO<Result<&1, &1, U32 & String, Unit>>:
        _closed : Unit <- File.close(file)
        write.synced(directory, result)

# Writes the encoded SST bytes to the temporary file.
def write.encoded(
  +directory: String,
  bytes: Bytes.Bytes,
  opened: Result<&1, &1, U32 & String, File>
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match opened:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{error})
    case Done{file}:
      do IO<Result<&1, &1, U32 & String, Unit>>:
        pair : File & Result<&1, &1, U32 & String, Unit> <- Fs.write_bytes(file, bytes)
        write.written(directory, pair)

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
  encoded: Result<&1, &1, ByteSstFile.Error, Bytes.Bytes>,
  opened: Result<&1, &1, U32 & String, File>
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match encoded:
    case Fail{_}:
      write.encoder.failed(opened)
    case Done{bytes}:
      write.encoded(directory, bytes, opened)

# Encodes and atomically publishes one bounded byte SST snapshot.
def write_atomic(
  +directory: String,
  entries: List<&1, ByteMemTable.Entry>
) -> IO(Result<&1, &1, U32 & String, Unit>):
  do IO<Result<&1, &1, U32 & String, Unit>>:
    opened : Result<&1, &1, U32 & String, File> <- File.open(directory ++ "/SST.tmp", "w")
    write.opened(directory, ByteSstFile.encode_file(entries, 0), opened)

# Reads one decoded block at a time and returns only after footer validation.
def read(+path: String) -> IO(Result<&1, &1, U32 & String, ByteMemTable.Table>):
  do IO<Result<&1, &1, U32 & String, ByteMemTable.Table>>:
    opened : Result<&1, &1, U32 & String, ByteBlockReader.Reader> <-
      ByteBlockReader.open(path)
    read.opened(opened)

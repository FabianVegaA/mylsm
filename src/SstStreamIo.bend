import Base
import ./Fs.bend as Fs
import ./MemTable.bend as MemTable
import ./Sstable.bend as Sstable
import ./SstFile.bend as SstFile
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Map pure format errors to the storage IO error domain.
def codec_error(error: SstFile.Error) -> U32 & String:
  match error:
    case SstFile.InvalidLevel{}:
      (U32.from_nat(3n), "invalid SST level")
    case SstFile.InvalidOrder{}:
      (U32.from_nat(3n), "SST keys are not strictly ordered")
    case SstFile.TooLarge{}:
      (U32.from_nat(3n), "SST exceeds a size limit")
    case SstFile.Malformed{}:
      (U32.from_nat(3n), "malformed v3 SST")
    case SstFile.InvalidUtf8{}:
      (U32.from_nat(3n), "invalid UTF-8 in v3 SST")
    case SstFile.ChecksumMismatch{}:
      (U32.from_nat(3n), "v3 SST checksum mismatch")

# Represent ExactResult data used by the streaming SSTable filesystem effects.
type ExactResult is Type:
  ExactResult{bytes: Bytes.Bytes, complete: Bool}

# Represent ExactState data used by the streaming SSTable filesystem effects.
type ExactState is Type:
  ExactNeed{file: File, remaining: Nat, chunks: List<&1, Bytes.Bytes>}
  ExactRead{pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>,
    remaining: Nat, chunks: List<&1, Bytes.Bytes>}

def exact.complete(
  file: File,
  chunks: List<&1, Bytes.Bytes>,
  complete: Bool
) -> IO(File & Result<&1, &1, U32 & String, ExactResult>):
  IO.pure(File & Result<&1, &1, U32 & String, ExactResult>,
    (file, Done{ExactResult{Bytes.concat(List.reverse(&1, Bytes.Bytes, chunks)), complete}}))

def exact.loop(
  fuel: Nat,
  state: ExactState
) -> IO(File & Result<&1, &1, U32 & String, ExactResult>):
  match fuel:
    case 0n:
      match state:
        case ExactNeed{file, remaining, chunks}:
          match remaining:
            case 0n:
              exact.complete(file, chunks, True{})
            case 1n+_:
              IO.pure(File & Result<&1, &1, U32 & String, ExactResult>,
                (file, Fail{(U32.from_nat(7n), "bounded read exhausted")}))
        case ExactRead{pair, _, _}:
          match pair:
            case (file, Fail{error}):
              IO.pure(File & Result<&1, &1, U32 & String, ExactResult>, (file, Fail{error}))
            case (file, Done{_}):
              IO.pure(File & Result<&1, &1, U32 & String, ExactResult>,
                (file, Fail{(U32.from_nat(7n), "bounded read exhausted")}))
    case 1n+rest:
      match state:
        case ExactNeed{file, +remaining, chunks}:
          match remaining:
            case 0n:
              exact.complete(file, chunks, True{})
            case 1n+_:
              do IO<File & Result<&1, &1, U32 & String, ExactResult>>:
                next : File & Result<&1, &1, U32 & String, Bytes.Bytes> <-
                  Fs.read_bytes(file, U32.from_nat(Nat.min(1048576n, remaining)))
                exact.loop(rest, ExactRead{next, remaining, chunks})
        case ExactRead{pair, remaining, chunks}:
          match pair:
            case (file, Fail{error}):
              IO.pure(File & Result<&1, &1, U32 & String, ExactResult>, (file, Fail{error}))
            case (file, Done{Bytes.Bytes{0, _}}):
              exact.complete(file, chunks, False{})
            case (file, Done{Bytes.Bytes{+len, buf}}):
              exact.loop(rest, ExactNeed{file, (remaining - U32.to_nat(len) : Nat),
                Con{Bytes.Bytes{len, buf}, chunks}})

def exact.start(file: File, +needed: Nat) -> IO(File & Result<&1, &1, U32 & String, ExactResult>):
  exact.loop(Nat.add(Nat.mul(2n, needed), 1n), ExactNeed{file, needed, Nil{}})

# Represent StreamReadState data used by the streaming SSTable filesystem effects.
type StreamReadState is Type:
  ReadHeader{file: File, size: Nat}
  ReadHeaderResult{pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>, size: Nat}
  ReadBlocks{file: File, size: Nat, used: Nat, parser: SstFile.StreamState}
  ReadBlockHeaderResult{pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>,
    size: Nat, used: Nat, parser: SstFile.StreamState}
  ReadBlockBody{file: File, size: Nat, used: Nat,
    parser: SstFile.StreamState, header: Bytes.Bytes, tail_len: U32}
  ReadBlockBodyResult{pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>,
    size: Nat, used: Nat, parser: SstFile.StreamState,
    header: Bytes.Bytes, tail_len: U32}
  ReadFooterResult{pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>,
    size: Nat, used: Nat, parser: SstFile.StreamState}
  ReadClose{file: File, result: Result<&1, &1, U32 & String, Sstable.Table>}

def read.exact.complete(bytes: Bytes.Bytes, complete: Bool) -> Result<&1, &1, U32 & String, Bytes.Bytes>:
  match complete:
    case True{}:
      Done{bytes}
    case False{}:
      Fail{(U32.from_nat(3n), "truncated SST")}

def read.exact.state(
  pair: File & Result<&1, &1, U32 & String, ExactResult>
) -> File & Result<&1, &1, U32 & String, Bytes.Bytes>:
  match pair:
    case (file, Fail{error}):
      (file, Fail{error})
    case (file, Done{ExactResult{bytes, complete}}):
      (file, read.exact.complete(bytes, complete))

def read.header.parsed(
  file: File,
  +size: Nat,
  result: Result<&1, &1, SstFile.Error, SstFile.StreamState>
) -> StreamReadState:
  match result:
    case Fail{error}:
      ReadClose{file, Fail{codec_error(error)}}
    case Done{parser}:
      ReadBlocks{file, size, 20n, parser}

def read.header.state(
  pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>,
  +size: Nat
) -> StreamReadState:
  match pair:
    case (file, Fail{error}):
      ReadClose{file, Fail{error}}
    case (file, Done{bytes}):
      read.header.parsed(file, size, SstFile.stream.header(bytes))

def read.block.header.bound(
  file: File,
  +size: Nat,
  +used: Nat,
  parser: SstFile.StreamState,
  header: Bytes.Bytes,
  +tail_len: U32,
  valid: Bool
) -> StreamReadState:
  match valid:
    case False{}:
      ReadClose{file, Fail{(U32.from_nat(3n), "truncated SST block")}}
    case True{}:
      ReadBlockBody{file, size, used, parser, header, tail_len}

def read.block.header.size(
  file: File,
  +size: Nat,
  +used: Nat,
  parser: SstFile.StreamState,
  header: Bytes.Bytes,
  tail: Maybe<&2, U32>
) -> StreamReadState:
  match tail:
    case None{}:
      ReadClose{file, Fail{(U32.from_nat(3n), "invalid SST block size")}}
    case Some{+tail_len}:
      read.block.header.bound(file, size, used, parser, header, tail_len,
        Nat.is_le(Nat.add(Nat.add(used, 8n), U32.to_nat(tail_len)),
        Nat.sub(size, 40n)))

def read.block.header.tail(
  saved: Bytes.Bytes,
  tail: Maybe<&2, U32>
) -> Bytes.Bytes & Maybe<&2, U32>:
  (saved, tail)

def read.block.header.inspected(
  pair: Bytes.Bytes & Bytes.Bytes
) -> Bytes.Bytes & Maybe<&2, U32>:
  match pair:
    case (saved, inspect):
      read.block.header.tail(saved, SstFile.stream.block.tail_size(inspect))

def read.block.header.copied(
  file: File,
  +size: Nat,
  +used: Nat,
  parser: SstFile.StreamState,
  inspected: Bytes.Bytes & Maybe<&2, U32>
) -> StreamReadState:
  match inspected:
    case (saved, None{}):
      ReadClose{file, Fail{(U32.from_nat(3n), "invalid SST block size")}}
    case (saved, Some{+tail_len}):
      read.block.header.size(file, size, used, parser, saved,
        Some{tail_len})

def read.block.header.copy(
  file: File,
  +size: Nat,
  +used: Nat,
  parser: SstFile.StreamState,
  header: Bytes.Bytes
) -> StreamReadState:
  read.block.header.copied(file, size, used, parser,
    read.block.header.inspected(SstFile.bytes.clone.split(header)))

def read.block.header.state(
  pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>,
  +size: Nat,
  +used: Nat,
  parser: SstFile.StreamState
) -> StreamReadState:
  match pair:
    case (file, Fail{error}):
      ReadClose{file, Fail{error}}
    case (file, Done{header}):
      read.block.header.copy(file, size, used, parser, header)

def read.block.body.parsed(
  file: File,
  +size: Nat,
  +used: Nat,
  +tail_len: U32,
  result: Result<&1, &1, SstFile.Error, SstFile.StreamState>
) -> StreamReadState:
  match result:
    case Fail{error}:
      ReadClose{file, Fail{codec_error(error)}}
    case Done{parser}:
      ReadBlocks{file, size, Nat.add(used,
        Nat.add(8n, U32.to_nat(tail_len))), parser}

def read.block.body.state(
  pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>,
  +size: Nat,
  +used: Nat,
  parser: SstFile.StreamState,
  header: Bytes.Bytes,
  +tail_len: U32
) -> StreamReadState:
  match pair:
    case (file, Fail{error}):
      ReadClose{file, Fail{error}}
    case (file, Done{body}):
      read.block.body.parsed(file, size, used, tail_len,
        SstFile.stream.block(parser, Bytes.concat([header, body])))

def read.footer.parsed(
  file: File,
  result: Result<&1, &1, SstFile.Error, Sstable.Table>
) -> StreamReadState:
  match result:
    case Fail{error}:
      ReadClose{file, Fail{codec_error(error)}}
    case Done{table}:
      ReadClose{file, Done{table}}

def read.footer.size(
  file: File,
  parser: SstFile.StreamState,
  bytes: Bytes.Bytes,
  valid: Bool
) -> StreamReadState:
  match valid:
    case False{}:
      ReadClose{file, Fail{(U32.from_nat(3n), "malformed SST size")}}
    case True{}:
      read.footer.parsed(file, SstFile.stream.footer(parser, bytes))

def read.footer.state(
  pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>,
  +size: Nat,
  +used: Nat,
  parser: SstFile.StreamState
) -> StreamReadState:
  match pair:
    case (file, Fail{error}):
      ReadClose{file, Fail{error}}
    case (file, Done{bytes}):
      read.footer.size(file, parser, bytes,
        Nat.is_eq(Nat.add(used, 40n), size))

def read.exhausted.file(file: File) -> IO(Result<&1, &1, U32 & String, Sstable.Table>):
  do IO<Result<&1, &1, U32 & String, Sstable.Table>>:
    _closed : Unit <- File.close(file)
    return Fail{(U32.from_nat(7n), "bounded SST read exhausted")}

def read.exhausted.pair(
  pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>
) -> IO(Result<&1, &1, U32 & String, Sstable.Table>):
  match pair:
    case (file, _):
      read.exhausted.file(file)

def read.exhausted(state: StreamReadState) -> IO(Result<&1, &1, U32 & String, Sstable.Table>):
  match state:
    case ReadHeader{file, _}:
      read.exhausted.file(file)
    case ReadHeaderResult{pair, _}:
      read.exhausted.pair(pair)
    case ReadBlocks{file, _, _, _}:
      read.exhausted.file(file)
    case ReadBlockHeaderResult{pair, _, _, _}:
      read.exhausted.pair(pair)
    case ReadBlockBody{file, _, _, _, _, _}:
      read.exhausted.file(file)
    case ReadBlockBodyResult{pair, _, _, _, _, _}:
      read.exhausted.pair(pair)
    case ReadFooterResult{pair, _, _, _}:
      read.exhausted.pair(pair)
    case ReadClose{file, result}:
      do IO<Result<&1, &1, U32 & String, Sstable.Table>>:
        _closed : Unit <- File.close(file)
        return result

def read.loop(fuel: Nat, state: StreamReadState) -> IO(Result<&1, &1, U32 & String, Sstable.Table>):
  match fuel:
    case 0n:
      read.exhausted(state)
    case 1n+rest:
      match state:
        case ReadHeader{file, size}:
          do IO<Result<&1, &1, U32 & String, Sstable.Table>>:
            pair : File & Result<&1, &1, U32 & String, ExactResult> <- exact.start(file, 20n)
            read.loop(rest, read.header.state(read.exact.state(pair), size))
        case ReadHeaderResult{pair, size}:
          read.loop(rest, read.header.state(pair, size))
        case ReadBlocks{file, size, used, parser}:
          match parser:
            case SstFile.StreamState{_, _, _, 0, _, _, _, _}:
              do IO<Result<&1, &1, U32 & String, Sstable.Table>>:
                pair : File & Result<&1, &1, U32 & String, ExactResult> <- exact.start(file, 40n)
                read.loop(rest, read.footer.state(read.exact.state(pair),
                  size, used, parser))
            case SstFile.StreamState{+level, +total, +block_count, +remaining,
                +entries_left, +previous, entries, hashes}:
              do IO<Result<&1, &1, U32 & String, Sstable.Table>>:
                pair : File & Result<&1, &1, U32 & String, ExactResult> <- exact.start(file, 8n)
                read.loop(rest, read.block.header.state(read.exact.state(pair),
                  size, used, SstFile.StreamState{level, total, block_count,
                    remaining, entries_left, previous, entries, hashes}))
        case ReadBlockHeaderResult{pair, size, used, parser}:
          read.loop(rest, read.block.header.state(pair, size, used, parser))
        case ReadBlockBody{file, size, used, parser, header, +tail_len}:
          do IO<Result<&1, &1, U32 & String, Sstable.Table>>:
            pair : File & Result<&1, &1, U32 & String, ExactResult> <-
              exact.start(file, U32.to_nat(tail_len))
            read.loop(rest, ReadBlockBodyResult{read.exact.state(pair),
              size, used, parser, header, tail_len})
        case ReadBlockBodyResult{pair, size, used, parser, header, tail_len}:
          read.loop(rest, read.block.body.state(pair, size, used, parser,
            header, tail_len))
        case ReadFooterResult{pair, size, used, parser}:
          read.loop(rest, read.footer.state(pair, size, used, parser))
        case ReadClose{file, result}:
          do IO<Result<&1, &1, U32 & String, Sstable.Table>>:
            _closed : Unit <- File.close(file)
            return result

def read.table.size.checked(
  +path: String,
  +size: Nat,
  valid: Bool
) -> IO(Result<&1, &1, U32 & String, Sstable.Table>):
  match valid:
    case False{}:
      IO.pure(Result<&1, &1, U32 & String, Sstable.Table>,
        Fail{(U32.from_nat(3n), "malformed or oversized SST")})
    case True{}:
      do IO<Result<&1, &1, U32 & String, Sstable.Table>>:
        file : File <- IO.try(File, File.open(path, "r"))
        read.loop(Nat.add(Nat.mul(2n, size), 16n), ReadHeader{file, size})

def read.table.size(+path: String, +size: Nat) -> IO(Result<&1, &1, U32 & String, Sstable.Table>):
  read.table.size.checked(path, size,
    Nat.is_le(60n, size) && Nat.is_le(size, 4294967295n))

# Read table for the streaming SSTable filesystem effects.
def read_table(+path: String) -> IO(Result<&1, &1, U32 & String, Sstable.Table>):
  do IO<Result<&1, &1, U32 & String, Sstable.Table>>:
    size : Nat <- IO.try(Nat, Fs.file_size(path))
    read.table.size(path, size)

def write.finish.chmod(
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{error})
    case Done{Unit{}}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Done{Unit{}})


def write.finish.synced(
  +path: String,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{error})
    case Done{Unit{}}:
      do IO<Result<&1, &1, U32 & String, Unit>>:
        changed : Result<&1, &1, U32 & String, Unit> <-
          Fs.chmod(path, U32.from_nat(384n))
        write.finish.chmod(changed)

def write.finish(
  file: File,
  +path: String
) -> IO(Result<&1, &1, U32 & String, Unit>):
  do IO<Result<&1, &1, U32 & String, Unit>>:
    _closed : Unit <- File.close(file)
    synced : Result<&1, &1, U32 & String, Unit> <- Fs.fsync(path)
    write.finish.synced(path, synced)

# Linear writer state keeps the file handle paired with the encoder result.
type WriteState is Type:
  WriteNext{file: File, encoder: SstFile.Encoder}
  WriteOutput{file: File,
    pair: SstFile.Encoder & Maybe<&1, Bytes.Bytes>}
  WriteResult{pair: File & Result<&1, &1, U32 & String, Unit>,
    encoder: SstFile.Encoder}

def write.step(
  fuel: Nat,
  +path: String,
  state: WriteState
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match fuel:
    case 0n:
      match state:
        case WriteNext{file, _}:
          do IO<Result<&1, &1, U32 & String, Unit>>:
            _closed : Unit <- File.close(file)
            return Fail{(U32.from_nat(7n), "table exceeds packed write limit")}
        case WriteOutput{file, _}:
          do IO<Result<&1, &1, U32 & String, Unit>>:
            _closed : Unit <- File.close(file)
            return Fail{(U32.from_nat(7n), "table exceeds packed write limit")}
        case WriteResult{pair, _}:
          match pair:
            case (file, _):
              do IO<Result<&1, &1, U32 & String, Unit>>:
                _closed : Unit <- File.close(file)
                return Fail{(U32.from_nat(7n), "table exceeds packed write limit")}
    case 1n+rest:
      match state:
        case WriteNext{file, encoder}:
          write.step(rest, path,
            WriteOutput{file, SstFile.next_chunk(encoder)})
        case WriteOutput{file, pair}:
          match pair:
            case (_, None{}):
              write.finish(file, path)
            case (next, Some{bytes}):
              do IO<Result<&1, &1, U32 & String, Unit>>:
                written : File & Result<&1, &1, U32 & String, Unit> <-
                  Fs.write_bytes(file, bytes)
                write.step(rest, path, WriteResult{written, next})
        case WriteResult{pair, encoder}:
          match pair:
            case (file, Fail{error}):
              do IO<Result<&1, &1, U32 & String, Unit>>:
                _closed : Unit <- File.close(file)
                return Fail{error}
            case (file, Done{Unit{}}):
              write.step(rest, path, WriteNext{file, encoder})

def write.encoder(
  +path: String,
  fuel: Nat,
  result: Result<&1, &1, SstFile.Error, SstFile.Encoder>
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{codec_error(error)})
    case Done{encoder}:
      do IO<Result<&1, &1, U32 & String, Unit>>:
        file : File <- IO.try(File, File.open(path, "w"))
        write.step(fuel, path, WriteNext{file, encoder})

# Encode and write one SST as packed chunks, then sync it before publication.
def write_table(
  +path: String,
  +entries: List<&2, MemTable.Entry>,
  +level: U32
) -> IO(Result<&1, &1, U32 & String, Unit>):
  write.encoder(path,
    Nat.add(Nat.mul(3n, Nat.add(List.length(&2, MemTable.Entry, entries), 2n)), 2n),
    SstFile.new_encoder(entries, level))

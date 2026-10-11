import Base
import ../Fs.bend as Fs
import ../SstFile.bend as SstFile
import ../SstStreamIo.bend as SstStreamIo
import ../MemTable.bend as MemTable
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Owns one open SST file and only the current validation state.
type Reader is Type:
  Reader{file: File, size: Nat, used: Nat, stream: SstFile.BlockStreamState}

# Returns one decoded block while retaining the reader for the next call.
type Step is Type:
  Block{reader: Reader, entries: List<&2, MemTable.Entry>}
  End{}

# Carries the exact header while checking its bounded body length.
type BlockContext is Type:
  BlockContext{size: Nat, used: Nat, stream: SstFile.BlockStreamState,
    header: Bytes.Bytes, tail_length: U32}

# Carries file-level footer state after its file handle moves through IO.
type FooterContext is Type:
  FooterContext{size: Nat, used: Nat, stream: SstFile.BlockStreamState}

# Converts a validated fixed header into the bounded block state.
def open.header.parsed(
  file: File,
  +size: Nat,
  result: Result<&1, &1, SstFile.Error, SstFile.BlockStreamState>
) -> IO(Result<&1, &1, U32 & String, Reader>):
  match result:
    case Fail{error}:
      do IO<Result<&1, &1, U32 & String, Reader>>:
        _closed : Unit <- File.close(file)
        return Fail{SstStreamIo.codec_error(error)}
    case Done{stream}:
      IO.pure(Result<&1, &1, U32 & String, Reader>,
        Done{Reader{file, size, 20n, stream}})

# Closes a file when header parsing has already failed.
def open.header.error(
  file: File,
  +size: Nat,
  result: Result<&1, &1, U32 & String, Bytes.Bytes>
) -> IO(Result<&1, &1, U32 & String, Reader>):
  match result:
    case Fail{error}:
      do IO<Result<&1, &1, U32 & String, Reader>>:
        _closed : Unit <- File.close(file)
        return Fail{error}
    case Done{header}:
      open.header.parsed(file, size, SstFile.stream.blocks.header(header))

def open.header.bytes(
  +size: Nat,
  pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>
) -> IO(Result<&1, &1, U32 & String, Reader>):
  match pair:
    case (file, result):
      open.header.error(file, size, result)

# Dispatches the file and exact-read outcome without retaining a full table.
def open.header.pair(
  +size: Nat,
  pair: File & Result<&1, &1, U32 & String, SstStreamIo.ExactResult>
) -> IO(Result<&1, &1, U32 & String, Reader>):
  open.header.bytes(size, SstStreamIo.read.exact.state(pair))

# Reads and validates the fixed-size SST header.
def open.file.opened(
  +size: Nat,
  opened: Result<&1, &1, U32 & String, File>
) -> IO(Result<&1, &1, U32 & String, Reader>):
  match opened:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Reader>, Fail{error})
    case Done{file}:
      do IO<Result<&1, &1, U32 & String, Reader>>:
        pair : File & Result<&1, &1, U32 & String, SstStreamIo.ExactResult> <-
          SstStreamIo.exact.start(file, 20n)
        open.header.pair(size, pair)

# Opens a file only when its size can contain one complete SST envelope.
def open.size.checked(
  +path: String,
  +size: Nat,
  valid: Bool
) -> IO(Result<&1, &1, U32 & String, Reader>):
  match valid:
    case False{}:
      IO.pure(Result<&1, &1, U32 & String, Reader>,
        Fail{(SstStreamIo.corruption_error_code(), "malformed or oversized SST")})
    case True{}:
      do IO<Result<&1, &1, U32 & String, Reader>>:
        opened : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
        open.file.opened(size, opened)

# Continues open after reading the file's measured byte size.
def open.file_size(
  +path: String,
  result: Result<&1, &1, U32 & String, Nat>
) -> IO(Result<&1, &1, U32 & String, Reader>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Reader>, Fail{error})
    case Done{+size}:
      open.size.checked(path, size, Nat.is_le(60n, size) &&
        Nat.is_le(size, 4294967295n))

# Opens a bounded block reader over an SST file.
def open(+path: String) -> IO(Result<&1, &1, U32 & String, Reader>):
  do IO<Result<&1, &1, U32 & String, Reader>>:
    size : Result<&1, &1, U32 & String, Nat> <- Fs.file_size(path)
    open.file_size(path, size)

# Closes an owned reader explicitly.
def close(reader: Reader) -> IO(Result<&1, &1, U32 & String, Unit>):
  match reader:
    case Reader{file, _, _, _}:
      do IO<Result<&1, &1, U32 & String, Unit>>:
        _closed : Unit <- File.close(file)
        return Done{Unit{}}

# Closes the file after any parsing or bounds error.
def next.failed(
  file: File,
  error: U32 & String
) -> IO(Result<&1, &1, U32 & String, Step>):
  do IO<Result<&1, &1, U32 & String, Step>>:
    _closed : Unit <- File.close(file)
    return Fail{error}

# Returns a reader whose validated block was consumed exactly.
def next.block.output(
  file: File,
  +size: Nat,
  +used: Nat,
  +tail_length: U32,
  result: Result<&1, &1, SstFile.Error, SstFile.BlockStreamOutput>
) -> IO(Result<&1, &1, U32 & String, Step>):
  match result:
    case Fail{error}:
      next.failed(file, SstStreamIo.codec_error(error))
    case Done{SstFile.BlockStreamOutput{stream, entries}}:
      IO.pure(Result<&1, &1, U32 & String, Step>,
        Done{Block{Reader{file, size,
          Nat.add(used, Nat.add(8n, U32.to_nat(tail_length))), stream}, entries}})

# Validates the block's total file bound before reading its body.
def next.block.body.pair(
  context: BlockContext,
  pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>
) -> IO(Result<&1, &1, U32 & String, Step>):
  match context:
    case BlockContext{+size, +used, stream, header, +tail_length}:
      match pair:
        case (file, Fail{error}):
          next.failed(file, error)
        case (file, Done{bytes}):
          next.block.output(file, size, used, tail_length,
            SstFile.stream.blocks.next(stream, Bytes.concat([header, bytes])))

def next.block.body.exact(
  context: BlockContext,
  pair: File & Result<&1, &1, U32 & String, SstStreamIo.ExactResult>
) -> IO(Result<&1, &1, U32 & String, Step>):
  next.block.body.pair(context, SstStreamIo.read.exact.state(pair))

# Validates the block's total file bound before reading its body.
def next.block.bounded(
  file: File,
  context: BlockContext,
  valid: Bool
) -> IO(Result<&1, &1, U32 & String, Step>):
  match context:
    case BlockContext{+size, +used, stream, header, +tail_length}:
      match valid:
        case False{}:
          next.failed(file, (SstStreamIo.corruption_error_code(), "SST block exceeds file bounds"))
        case True{}:
          do IO<Result<&1, &1, U32 & String, Step>>:
            pair : File & Result<&1, &1, U32 & String, SstStreamIo.ExactResult> <-
              SstStreamIo.exact.start(file, U32.to_nat(tail_length))
            next.block.body.exact(BlockContext{size, used, stream, header,
              tail_length}, pair)

# Uses the declared body length only when the block fits before the footer.
def next.block.header(
  file: File,
  context: BlockContext
) -> IO(Result<&1, &1, U32 & String, Step>):
  match context:
    case BlockContext{+size, +used, _, _, +tail_length}:
      next.block.bounded(file, context,
        Nat.is_le(Nat.add(Nat.add(used, 8n), U32.to_nat(tail_length)),
          Nat.sub(size, 40n)))

# Parses one block header and rejects invalid lengths before allocation.
def next.block.inspected(
  file: File,
  size: Nat,
  used: Nat,
  stream: SstFile.BlockStreamState,
  inspected: Bytes.Bytes & Maybe<&2, U32>
) -> IO(Result<&1, &1, U32 & String, Step>):
  match inspected:
    case (_, None{}):
      next.failed(file, (SstStreamIo.corruption_error_code(), "invalid SST block size"))
    case (header, Some{+tail_length}):
      next.block.header(file, BlockContext{size, used, stream, header, tail_length})

# Converts a fixed block-header read into a checked body length.
def next.block.header.read(
  file: File,
  size: Nat,
  used: Nat,
  stream: SstFile.BlockStreamState,
  result: Result<&1, &1, U32 & String, Bytes.Bytes>
) -> IO(Result<&1, &1, U32 & String, Step>):
  match result:
    case Fail{error}:
      next.failed(file, error)
    case Done{header}:
      next.block.inspected(file, size, used, stream,
        SstStreamIo.read.block.header.inspected(SstFile.bytes.clone.split(header)))

# Reads one fixed-width block header from the current file position.
def next.block.header.pair(
  +size: Nat,
  +used: Nat,
  stream: SstFile.BlockStreamState,
  pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>
) -> IO(Result<&1, &1, U32 & String, Step>):
  match pair:
    case (file, result):
      next.block.header.read(file, size, used, stream, result)

def next.block.header.exact(
  +size: Nat,
  +used: Nat,
  stream: SstFile.BlockStreamState,
  pair: File & Result<&1, &1, U32 & String, SstStreamIo.ExactResult>
) -> IO(Result<&1, &1, U32 & String, Step>):
  next.block.header.pair(size, used, stream,
    SstStreamIo.read.exact.state(pair))

# Reads one fixed-width block header from the current file position.
def next.block.read(
  file: File,
  size: Nat,
  used: Nat,
  stream: SstFile.BlockStreamState
) -> IO(Result<&1, &1, U32 & String, Step>):
  do IO<Result<&1, &1, U32 & String, Step>>:
    pair : File & Result<&1, &1, U32 & String, SstStreamIo.ExactResult> <-
      SstStreamIo.exact.start(file, 8n)
    next.block.header.exact(size, used, stream, pair)

# Closes the file after deciding whether the footer is valid.
def next.footer.finished.valid(valid: Bool) -> Result<&1, &1, U32 & String, Step>:
  match valid:
    case True{}:
      Done{End{}}
    case False{}:
      Fail{(SstStreamIo.corruption_error_code(), "malformed SST footer size")}

# Closes the file after deciding whether the footer is valid.
def next.footer.finished(
  file: File,
  valid: Bool
) -> IO(Result<&1, &1, U32 & String, Step>):
  do IO<Result<&1, &1, U32 & String, Step>>:
    _closed : Unit <- File.close(file)
    return next.footer.finished.valid(valid)

# Closes the reader on a failed file-level footer digest.
def next.footer.validated(
  file: File,
  +size: Nat,
  +used: Nat,
  result: Result<&1, &1, SstFile.Error, Unit>
) -> IO(Result<&1, &1, U32 & String, Step>):
  match result:
    case Fail{error}:
      next.failed(file, SstStreamIo.codec_error(error))
    case Done{Unit{}}:
      next.footer.finished(file, Nat.is_eq(Nat.add(used, 40n), size))

# Validates footer counts and the root digest before closing the file.
def next.footer.parsed(
  file: File,
  context: FooterContext,
  footer: Bytes.Bytes
) -> IO(Result<&1, &1, U32 & String, Step>):
  match context:
    case FooterContext{+size, +used, stream}:
      next.footer.validated(file, size, used,
        SstFile.stream.blocks.footer(stream, footer))

# Verifies and closes after consuming the exact 40-byte footer.
def next.footer.read(
  context: FooterContext,
  pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>
) -> IO(Result<&1, &1, U32 & String, Step>):
  match pair:
    case (file, Fail{error}):
      next.failed(file, error)
    case (file, Done{footer}):
      next.footer.parsed(file, context, footer)

def next.footer.exact(
  context: FooterContext,
  pair: File & Result<&1, &1, U32 & String, SstStreamIo.ExactResult>
) -> IO(Result<&1, &1, U32 & String, Step>):
  next.footer.read(context, SstStreamIo.read.exact.state(pair))

# Reads the footer after the final authenticated block.
def next.footer(reader: Reader) -> IO(Result<&1, &1, U32 & String, Step>):
  match reader:
    case Reader{file, size, used, stream}:
      do IO<Result<&1, &1, U32 & String, Step>>:
        pair : File & Result<&1, &1, U32 & String, SstStreamIo.ExactResult> <-
          SstStreamIo.exact.start(file, 40n)
        next.footer.exact(FooterContext{size, used, stream}, pair)

# Selects the final footer or the next bounded block.
def next.ready(reader: Reader, finished: Bool) -> IO(Result<&1, &1, U32 & String, Step>):
  match reader:
    case Reader{file, size, used, stream}:
      match finished:
        case True{}:
          next.footer(reader)
        case False{}:
          next.block.read(file, size, used, stream)

# Returns the next validated block or End and closes on terminal errors.
def next(reader: Reader) -> IO(Result<&1, &1, U32 & String, Step>):
  match reader:
    case Reader{_, _, _, SstFile.BlockStreamState{_, _, _, +remaining, _, _, _}}:
      next.ready(reader, U32.is_eq(remaining, 0))

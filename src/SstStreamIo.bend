import Base
import ./SstStream.bend as Stream
import ./Decimal.bend as Decimal
import ./Fs.bend as Fs
import ./SstFileV2.bend as V2
import ./Sstable.bend as Sstable

# `chunks_left` is an 8 GiB safety cap with a loud exhaustion error
# ("table exceeds streaming read limit"), never a silent truncation.
def stream_loop(chunks_left: Nat, +path: String, +offset: Nat, mode: Stream.Mode, pending: Maybe<&2, Stream.Chunk>) -> IO(Result<&1, &1, U32 & String, Sstable.Table>):
  match chunks_left pending:
    case 0n _:
      IO.pure(Result<&1, &1, U32 & String, Sstable.Table>, Fail{(U32.from_nat(7n), "table exceeds streaming read limit")})
    case 1n+rest None{}:
      do IO<Result<&1, &1, U32 & String, Sstable.Table>>:
        raw : String <- IO.try(String, Fs.read_utf8_chunk(path, offset, V2.read_chunk_chars()))
        chunk : Stream.Chunk <- IO.try(Stream.Chunk, IO.pure(Result<&1, &1, U32 & String, Stream.Chunk>, Stream.chunk_parse(Decimal.parse_semicolon(raw, V2.read_chunk_chars()))))
        stream_loop(rest, path, offset, mode, Some{chunk})
    case 1n+rest Some{Stream.Ch{bytes, text}}:
      match bytes:
        case 0n:
          IO.pure(Result<&1, &1, U32 & String, Sstable.Table>, Stream.finish_mode(mode))
        case 1n+more:
          stream_loop(rest, path, Nat.add(offset, 1n+more), Stream.feed_mode(mode, text), None{})


def read_table(+path: String) -> IO(Result<&1, &1, U32 & String, Sstable.Table>):
  stream_loop(8192n, path, 0n, Stream.Unknown{}, None{})

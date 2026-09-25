import Base
import ./Decimal.bend as Decimal
import ./Fs.bend as Fs
import ./Sstable.bend as Sstable
import ./SstFileV2.bend as V2

# Chunked table recovery. The host effect returns UTF-8-safe positional chunks;
# the pure one-character v2 decoder transitions run per chunk.

type Chunk is Data:
  Ch{bytes: Nat, text: String}

type Mode is Data:
  Unknown{}
  Current{decoder: V2.Decoder}


def chunk_parse(p: Decimal.Parse) -> Result<&1, &1, U32 & String, Chunk>:
  match p:
    case Decimal.Rejected{error}:
      Fail{(U32.from_nat(8n), "bad UTF-8 chunk envelope")}
    case Decimal.Accepted{Decimal.Dec{value, rest}}:
      Done{Ch{value, rest}}


def feed_v2(rest: String, decoder: V2.Decoder) -> V2.Decoder:
  match rest:
    case SNil{}:
      decoder
    case SCon{c, tail}:
      feed_v2(tail, V2.decoder_step(decoder, c))


def unknown_v2(is_v2: Bool, +text: String) -> Mode:
  match is_v2:
    case True{}:
      Current{feed_v2(text, V2.Dec{V2.NeedS{}, 0n, None{}, Nil{}, 0n, 0n, 7, 0n})}
    case False{}:
      Unknown{}


def feed_mode(mode: Mode, +text: String) -> Mode:
  match mode:
    case Unknown{}:
      unknown_v2(String.starts_with(text, "S2;"), text)
    case Current{decoder}:
      Current{feed_v2(text, decoder)}


def finish_v2(result: V2.ParseResult) -> Result<&1, &1, U32 & String, Sstable.Table>:
  match result:
    case V2.ParseRejected{error}:
      Fail{(U32.from_nat(3n), "bad v2 table")}
    case V2.Parsed{table}:
      Done{table}


def finish_mode(mode: Mode) -> Result<&1, &1, U32 & String, Sstable.Table>:
  match mode:
    case Unknown{}:
      Fail{(U32.from_nat(3n), "unknown table version")}
    case Current{decoder}:
      finish_v2(V2.finish_decoder(decoder))



def stream_loop(fuel: Nat, +path: String, +offset: Nat, mode: Mode, pending: Maybe<&2, Chunk>) -> IO(Result<&1, &1, U32 & String, Sstable.Table>):
  match fuel pending:
    case 0n _:
      IO.pure(Result<&1, &1, U32 & String, Sstable.Table>, Fail{(U32.from_nat(7n), "table exceeds streaming read limit")})
    case 1n+rest None{}:
      do IO<Result<&1, &1, U32 & String, Sstable.Table>>:
        raw : String <- IO.try(String, Fs.read_utf8_chunk(path, offset, V2.read_chunk_chars()))
        chunk : Chunk <- IO.try(Chunk, IO.pure(Result<&1, &1, U32 & String, Chunk>, chunk_parse(Decimal.parse_semicolon(raw, V2.read_chunk_chars()))))
        stream_loop(rest, path, offset, mode, Some{chunk})
    case 1n+rest Some{Ch{bytes, text}}:
      match bytes:
        case 0n:
          IO.pure(Result<&1, &1, U32 & String, Sstable.Table>, finish_mode(mode))
        case 1n+more:
          stream_loop(rest, path, Nat.add(offset, 1n+more), feed_mode(mode, text), None{})


def read_table(+path: String) -> IO(Result<&1, &1, U32 & String, Sstable.Table>):
  stream_loop(8192n, path, 0n, Unknown{}, None{})

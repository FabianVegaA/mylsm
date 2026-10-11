import Base
import ../ByteMemTable.bend as ByteMemTable
import ./Protocol.bend as Protocol
import ./IoPolicy.bend as IoPolicy
import ./UnixSocketPolicy.bend as UnixSocketPolicy
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Classifies framing, resource, and host failures from socket IO.
type Error is Data:
  UnsupportedPlatform{}
  Host{code: U32, message: String}
  Truncated{}
  Malformed{}
  UnknownOperation{}
  FrameTooLarge{}
  MalformedResponse{}
  UnexpectedResponse{}
  UnknownResponseStatus{}

# Returns the terminal outcome of an exact-length socket transfer.
type ExactResult is Type:
  ExactResult{bytes: Bytes.Bytes, complete: Bool}

# Tracks partial transfer progress until the requested length is complete.
type ExactState is Type:
  Need{file: File, remaining: Nat, chunks: List<&1, Bytes.Bytes>}
  Read{pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>,
    remaining: Nat, chunks: List<&1, Bytes.Bytes>}

# Carries bounded chunks through one-syscall socket write steps.
type WriteState is Type:
  WriteNeed{file: File, remaining: U32 & U32 & U32, total: U32,
    offsets: U32 & U32 & U32, bytes: Bytes.Bytes}
  WriteDone{file: File}
  WriteSend{file: File, total: U32, offset: U32 & U32 & U32,
    remaining: U32 & U32 & U32,
    words: Array<U32>}
  WriteSent{pair: File & Result<&1, &1, U32 & String, U32 & Array<U32>>,
    total: U32, offset: U32, remaining: U32}
  WriteAdvance{file: File, total: U32, offset: U32, remaining: U32,
    sent: U32 & U32 & U32, words: Array<U32>}
  WriteFailed{file: File}


# Sets the protocol payload ceiling enforced before socket allocation.
def max_payload_bytes() -> Nat:
  Protocol.max_payload_bytes()

def host.error.classified(
  code: U32,
  message: String,
  classification: UnixSocketPolicy.Classification
) -> Error:
  match classification:
    case UnixSocketPolicy.UnsupportedPlatform{}: UnsupportedPlatform{}
    case UnixSocketPolicy.Host{_}: Host{code, message}

def host.error.copies(
  copies: U32 & U32 & U32,
  message: String
) -> Error:
  match copies:
    case (classification_code, (retained_code, _)):
      host.error.classified(retained_code, message,
        UnixSocketPolicy.classify_code(classification_code))

def host.error(code: U32, message: String) -> Error:
  host.error.copies(Protocol.u32.duplicate.triple(code), message)

# Reads one raw byte chunk from an accepted local socket.
def unix_socket_read(
  file: File,
  max_bytes: U32
) -> IO(
  File & Result<&1, &1, U32 & String, U32 & Array<U32>>
):
  import "../effs/unix_socket_read.c"
  import "../effs/unix_socket_read.js"

def read.words(
  file: File,
  max_bytes: U32
) -> IO(
  File & Result<&1, &1, U32 & String, U32 & Array<U32>>
):
  unix_socket_read(file, max_bytes)

def read.wrap(
  result: Result<&1, &1, U32 & String, U32 & Array<U32>>
) -> Result<&1, &1, U32 & String, Bytes.Bytes>:
  match result:
    case Fail{error}: Fail{error}
    case Done{(length, words)}: Done{Bytes.Bytes{length, words}}

def read.pair(
  pair: File & Result<&1, &1, U32 & String, U32 & Array<U32>>
) -> File & Result<&1, &1, U32 & String, Bytes.Bytes>:
  match pair:
    case (file, result): (file, read.wrap(result))

def read.bytes(
  file: File,
  max_bytes: U32
) -> IO(
  File & Result<&1, &1, U32 & String, Bytes.Bytes>
):
  do IO<File & Result<&1, &1, U32 & String, Bytes.Bytes>>:
    pair : File & Result<&1, &1, U32 & String, U32 & Array<U32>> <-
      read.words(file, max_bytes)
    return read.pair(pair)

def write.words(
  file: File,
  offset: U32,
  length: U32,
  words: Array<U32>
) -> IO(File & Result<&1, &1, U32 & String, U32 & Array<U32>>):
  unix_socket_write(file, offset, length, words)

def write.chunk(remaining: U32) -> U32:
  IoPolicy.write_chunk(remaining)

# Writes one raw byte chunk to a local socket connection.
def unix_socket_write(
  file: File,
  offset: U32,
  length: U32,
  words: Array<U32>
) -> IO(File & Result<&1, &1, U32 & String, U32 & Array<U32>>):
  import "../effs/unix_socket_write.c"
  import "../effs/unix_socket_write.js"

def write.advance.total(
  copies: U32 & U32 & U32,
  file: File,
  offset: U32,
  remaining: U32,
  words: Array<U32>
) -> WriteState:
  match copies:
    case (total_state, (total_bytes, _)):
      WriteNeed{file, Protocol.u32.duplicate.triple(remaining), total_state,
        Protocol.u32.duplicate.triple(offset),
        Bytes.Bytes{total_bytes, words}}

def write.advance(
  zero: Bool,
  file: File,
  total: U32,
  offset: U32,
  remaining: U32,
  sent_offset: U32,
  sent_remaining: U32,
  words: Array<U32>
) -> WriteState:
  match zero:
    case True{}: WriteFailed{file}
    case False{}:
      write.advance.total(Protocol.u32.duplicate.triple(total), file,
        (offset + sent_offset : U32), (remaining - sent_remaining : U32),
        words)

def write.need(
  zero: Bool,
  file: File,
  remaining_send: U32,
  total: U32,
  offsets: U32 & U32 & U32,
  bytes: Bytes.Bytes
) -> WriteState:
  match zero:
    case True{}: WriteDone{file}
    case False{}:
      match offsets:
        case (write_offset, _, _):
          match bytes:
            case Bytes.Bytes{_, words}:
              WriteSend{file, total,
                Protocol.u32.duplicate.triple(write_offset),
                Protocol.u32.duplicate.triple(remaining_send), words}

def write.loop(
  fuel: Nat,
  state: WriteState
) -> IO(
  File & Result<&1, &1, U32 & String, Unit>
):
  match fuel:
    case 0n:
      match state:
        case WriteNeed{file, _, _, _, _}:
          IO.pure(File & Result<&1, &1, U32 & String, Unit>,
            (file, Fail{(7, "socket write exhausted its progress bound")}))
        case WriteSent{pair, _, _, _}:
          match pair:
            case (file, _):
              IO.pure(File & Result<&1, &1, U32 & String, Unit>,
                (file, Fail{(7, "socket write exhausted its progress bound")}))
        case WriteAdvance{file, _, _, _, _, _}:
          IO.pure(File & Result<&1, &1, U32 & String, Unit>,
            (file, Fail{(7, "socket write exhausted its progress bound")}))
        case WriteFailed{file}:
          IO.pure(File & Result<&1, &1, U32 & String, Unit>,
            (file, Fail{(5, "socket write made no progress")}))
        case WriteDone{file}:
          IO.pure(File & Result<&1, &1, U32 & String, Unit>,
            (file, Done{Unit{}}))
        case WriteSend{file, _, _, _, _}:
          IO.pure(File & Result<&1, &1, U32 & String, Unit>,
            (file, Fail{(7, "socket write exhausted its progress bound")}))
    case 1n+rest:
      match state:
        case WriteNeed{file, remaining, total, offsets, bytes}:
          match remaining:
            case (remaining_check, (remaining_send, _)):
              write.loop(rest, write.need(U32.is_eq(remaining_check, 0), file,
                remaining_send, total, offsets, bytes))
        case WriteDone{file}:
          IO.pure(File & Result<&1, &1, U32 & String, Unit>,
            (file, Done{Unit{}}))
        case WriteFailed{file}:
          IO.pure(File & Result<&1, &1, U32 & String, Unit>,
            (file, Fail{(5, "socket write made no progress")}))
        case WriteSend{file, total, offset, remaining, words}:
          match offset:
            case (offset_send, (offset_keep, _)):
              match remaining:
                case (remaining_send, (remaining_keep, _)):
                  do IO<File & Result<&1, &1, U32 & String, Unit>>:
                    pair : File & Result<&1, &1, U32 & String, U32 & Array<U32>> <-
                      write.words(file, offset_send,
                        write.chunk(remaining_send), words)
                    write.loop(rest, WriteSent{pair, total, offset_keep,
                      remaining_keep})
        case WriteSent{pair, total, offset, remaining}:
          match pair:
            case (file, Fail{error}):
              IO.pure(File & Result<&1, &1, U32 & String, Unit>,
                (file, Fail{error}))
            case (file, Done{(sent, words)}):
              write.loop(rest, WriteAdvance{file, total, offset, remaining,
                Protocol.u32.duplicate.triple(sent), words})
        case WriteAdvance{file, total, offset, remaining, copies, words}:
          match copies:
            case (sent_check, (sent_offset, sent_remaining)):
              write.loop(rest, write.advance(U32.is_eq(sent_check, 0),
                file, total, offset, remaining, sent_offset, sent_remaining,
                words))

def write.start.total(
  file: File,
  words: Array<U32>,
  fuel_length: U32,
  remaining_seed: U32,
  total_copies: U32 & U32 & U32
) -> IO(File & Result<&1, &1, U32 & String, Unit>):
  match total_copies:
    case (total, (bytes_length, _)):
      write.loop(Nat.add(U32.to_nat(fuel_length), 1n),
        WriteNeed{file, Protocol.u32.duplicate.triple(remaining_seed), total,
          Protocol.u32.duplicate.triple(0), Bytes.Bytes{bytes_length, words}})

def write.start.copies(
  file: File,
  words: Array<U32>,
  copies: U32 & U32 & U32
) -> IO(File & Result<&1, &1, U32 & String, Unit>):
  match copies:
    case (fuel_length, (total_seed, remaining_seed)):
      write.start.total(file, words, fuel_length, remaining_seed,
        Protocol.u32.duplicate.triple(total_seed))

def write.start(
  file: File,
  length: U32,
  words: Array<U32>
) -> IO(File & Result<&1, &1, U32 & String, Unit>):
  write.start.copies(file, words, Protocol.u32.duplicate.triple(length))

# Completes a frame by advancing over bounded partial writes.
def write_all(
  file: File,
  bytes: Bytes.Bytes
) -> IO(
  File & Result<&1, &1, U32 & String, Unit>
):
  match bytes:
    case Bytes.Bytes{length, words}:
      write.start(file, length, words)

def exact.complete(
  file: File,
  chunks: List<&1, Bytes.Bytes>,
  complete: Bool
) -> IO(File & Result<&1, &1, U32 & String, ExactResult>):
  IO.pure(File & Result<&1, &1, U32 & String, ExactResult>,
    (file, Done{ExactResult{Bytes.concat(List.reverse(&1, Bytes.Bytes, chunks)),
      complete}}))

def exact.loop(
  fuel: Nat,
  state: ExactState
) -> IO(
  File & Result<&1, &1, U32 & String, ExactResult>
):
  match fuel:
    case 0n:
      match state:
        case Need{file, remaining, _}:
          match remaining:
            case 0n: exact.complete(file, Nil{}, True{})
            case 1n+_: IO.pure(File & Result<&1, &1, U32 & String, ExactResult>,
              (file, Fail{(7, "socket frame read exhausted its bound")}))
        case Read{pair, _, _}:
          match pair:
            case (file, Fail{error}):
              IO.pure(File & Result<&1, &1, U32 & String, ExactResult>,
                (file, Fail{error}))
            case (file, Done{_}):
              IO.pure(File & Result<&1, &1, U32 & String, ExactResult>,
                (file, Fail{(7, "socket frame read exhausted its bound")}))
    case 1n+rest:
      match state:
        case Need{file, remaining, chunks}:
          match remaining:
            case 0n: exact.complete(file, chunks, True{})
            case 1n+rest_remaining:
              +total = Nat.add(1n, rest_remaining)
              do IO<File & Result<&1, &1, U32 & String, ExactResult>>:
                pair : File & Result<&1, &1, U32 & String, Bytes.Bytes> <-
                  read.bytes(file,
                    U32.from_nat(Nat.min(65536n, total)))
                exact.loop(rest, Read{pair, total, chunks})
        case Read{pair, remaining, chunks}:
          match pair:
            case (file, Fail{error}):
              IO.pure(File & Result<&1, &1, U32 & String, ExactResult>,
                (file, Fail{error}))
            case (file, Done{Bytes.Bytes{0, _}}):
              exact.complete(file, chunks, False{})
            case (file, Done{Bytes.Bytes{+length, words}}):
              exact.loop(rest, Need{file,
                Nat.sub(remaining, U32.to_nat(length)),
                Con{Bytes.Bytes{length, words}, chunks}})

def exact.nat.duplicate.step(pair: Nat & Nat) -> Nat & Nat:
  match pair:
    case (left, right): (Nat.add(1n, left), Nat.add(1n, right))

def exact.nat.duplicate(value: Nat) -> Nat & Nat:
  match value:
    case 0n: (0n, 0n)
    case 1n+rest: exact.nat.duplicate.step(exact.nat.duplicate(rest))

def exact.start.copied(
  file: File,
  copies: Nat & Nat
) -> IO(
  File & Result<&1, &1, U32 & String, ExactResult>
):
  match copies:
    case (fuel, needed):
      exact.loop(Nat.add(Nat.mul(2n, fuel), 1n), Need{file, needed, Nil{}})

def exact.start(
  file: File,
  needed: Nat
) -> IO(
  File & Result<&1, &1, U32 & String, ExactResult>
):
  exact.start.copied(file, exact.nat.duplicate(needed))

def frame.error(decision: Protocol.FrameDecision) -> Error:
  match decision:
    case Protocol.UnknownOperation{}: UnknownOperation{}
    case Protocol.FrameTooLarge{}: FrameTooLarge{}
    case _: Malformed{}

def frame.result(
  file: File,
  decision: Protocol.FrameDecision
) -> File & Result<&1, &1, Error, Protocol.Request>:
  match decision:
    case Protocol.Decoded{request}: (file, Done{request})
    case _: (file, Fail{frame.error(decision)})

def payload.result(
  header: Bytes.Bytes,
  pair: File & Result<&1, &1, U32 & String, ExactResult>
) -> IO(File & Result<&1, &1, Error, Protocol.Request>):
  match pair:
    case (file, Fail{(code, message)}):
      IO.pure(File & Result<&1, &1, Error, Protocol.Request>,
        (file, Fail{host.error(code, message)}))
    case (file, Done{ExactResult{bytes, complete}}):
      match complete:
        case False{}:
          IO.pure(File & Result<&1, &1, Error, Protocol.Request>,
            (file, Fail{Truncated{}}))
        case True{}:
          IO.pure(File & Result<&1, &1, Error, Protocol.Request>,
            frame.result(file, Protocol.decode(Bytes.concat([header, bytes]),
              max_payload_bytes())))

def payload.header(
  file: File,
  header: Bytes.Bytes,
  length: U32
) -> IO(File & Result<&1, &1, Error, Protocol.Request>):
  do IO<File & Result<&1, &1, Error, Protocol.Request>>:
    payload : File & Result<&1, &1, U32 & String, ExactResult> <-
      exact.start(file, U32.to_nat(length))
    payload.result(header, payload)

def header.length(
  file: File,
  bytes: Bytes.Bytes,
  length: Maybe<&2, U32>
) -> IO(File & Result<&1, &1, Error, Protocol.Request>):
  match length:
    case Some{length}: payload.header(file, bytes, length)
    case None{}:
      IO.pure(File & Result<&1, &1, Error, Protocol.Request>,
        (file, Fail{Malformed{}}))

def header.length.result(
  file: File,
  pair: Bytes.Bytes & Maybe<&2, U32>
) -> IO(File & Result<&1, &1, Error, Protocol.Request>):
  match pair:
    case (bytes, length): header.length(file, bytes, length)

def header.decision(
  file: File,
  bytes: Bytes.Bytes,
  decision: Protocol.FrameDecision
) -> IO(File & Result<&1, &1, Error, Protocol.Request>):
  match decision:
    case Protocol.NeedMore{}:
      header.length.result(file, Bytes.get.u32be(bytes, 20))
    case _:
      IO.pure(File & Result<&1, &1, Error, Protocol.Request>,
        frame.result(file, decision))

def header.cloned(
  file: File,
  pair: Bytes.Bytes & Bytes.Bytes
) -> IO(File & Result<&1, &1, Error, Protocol.Request>):
  match pair:
    case (for_decode, retained):
      header.decision(file, retained,
        Protocol.decode(for_decode, max_payload_bytes()))

def header.result(
  pair: File & Result<&1, &1, U32 & String, ExactResult>
) -> IO(File & Result<&1, &1, Error, Protocol.Request>):
  match pair:
    case (file, Fail{(code, message)}):
      IO.pure(File & Result<&1, &1, Error, Protocol.Request>,
        (file, Fail{host.error(code, message)}))
    case (file, Done{ExactResult{bytes, complete}}):
      match complete:
        case False{}:
          IO.pure(File & Result<&1, &1, Error, Protocol.Request>,
            (file, Fail{Truncated{}}))
        case True{}:
          header.cloned(file, ByteMemTable.bytes.clone(bytes))

# Reads and validates one length-bounded request frame.
def read_request(
  file: File
) -> IO(
  File & Result<&1, &1, Error, Protocol.Request>
):
  do IO<File & Result<&1, &1, Error, Protocol.Request>>:
    header : File & Result<&1, &1, U32 & String, ExactResult> <-
      exact.start(file, 24n)
    header.result(header)

def response.frame.result(
  file: File,
  decision: Protocol.ResponseDecision
) -> File & Result<&1, &1, Error, Protocol.Response>:
  match decision:
    case Protocol.DecodedResponse{response}: (file, Done{response})
    case Protocol.ResponseNeedMore{}: (file, Fail{Truncated{}})
    case Protocol.ResponseTooLarge{}: (file, Fail{FrameTooLarge{}})
    case Protocol.MalformedResponse{}: (file, Fail{MalformedResponse{}})
    case Protocol.UnexpectedResponse{}: (file, Fail{UnexpectedResponse{}})
    case Protocol.UnknownResponseStatus{}:
      (file, Fail{UnknownResponseStatus{}})

def response.payload.result(
  header: Bytes.Bytes,
  pair: File & Result<&1, &1, U32 & String, ExactResult>
) -> IO(File & Result<&1, &1, Error, Protocol.Response>):
  match pair:
    case (file, Fail{(code, message)}):
      IO.pure(File & Result<&1, &1, Error, Protocol.Response>,
        (file, Fail{host.error(code, message)}))
    case (file, Done{ExactResult{bytes, complete}}):
      match complete:
        case False{}:
          IO.pure(File & Result<&1, &1, Error, Protocol.Response>,
            (file, Fail{Truncated{}}))
        case True{}:
          IO.pure(File & Result<&1, &1, Error, Protocol.Response>,
            response.frame.result(file,
              Protocol.decode_response(Bytes.concat([header, bytes]),
                max_payload_bytes())))

def response.payload(
  file: File,
  header: Bytes.Bytes,
  length: U32
) -> IO(File & Result<&1, &1, Error, Protocol.Response>):
  do IO<File & Result<&1, &1, Error, Protocol.Response>>:
    payload : File & Result<&1, &1, U32 & String, ExactResult> <-
      exact.start(file, U32.to_nat(length))
    response.payload.result(header, payload)

def response.length.admitted(
  file: File,
  header: Bytes.Bytes,
  length: U32,
  admitted: Bool
) -> IO(File & Result<&1, &1, Error, Protocol.Response>):
  match admitted:
    case True{}: response.payload(file, header, length)
    case False{}:
      IO.pure(File & Result<&1, &1, Error, Protocol.Response>,
        (file, Fail{FrameTooLarge{}}))

def response.length.checked(
  file: File,
  header: Bytes.Bytes,
  lengths: U32 & U32 & U32
) -> IO(File & Result<&1, &1, Error, Protocol.Response>):
  match lengths:
    case (read_length, (checked_length, _)):
      response.length.admitted(file, header, read_length,
        U32.is_le(checked_length, U32.from_nat(max_payload_bytes())))

def response.length(
  file: File,
  header: Bytes.Bytes,
  length: Maybe<&2, U32>
) -> IO(File & Result<&1, &1, Error, Protocol.Response>):
  match length:
    case Some{length}:
      response.length.checked(file, header,
        Protocol.u32.duplicate.triple(length))
    case _:
      IO.pure(File & Result<&1, &1, Error, Protocol.Response>,
        (file, Fail{MalformedResponse{}}))

def response.header.length(
  file: File,
  pair: Bytes.Bytes & Maybe<&2, U32>
) -> IO(File & Result<&1, &1, Error, Protocol.Response>):
  match pair:
    case (header, length): response.length(file, header, length)

def response.header.complete(
  file: File,
  header: Bytes.Bytes,
  complete: Bool
) -> IO(File & Result<&1, &1, Error, Protocol.Response>):
  match complete:
    case True{}:
      response.header.length(file, Bytes.get.u32be(header, 20))
    case False{}:
      IO.pure(File & Result<&1, &1, Error, Protocol.Response>,
        (file, Fail{Truncated{}}))

def response.header.result(
  pair: File & Result<&1, &1, U32 & String, ExactResult>
) -> IO(File & Result<&1, &1, Error, Protocol.Response>):
  match pair:
    case (file, Fail{(code, message)}):
      IO.pure(File & Result<&1, &1, Error, Protocol.Response>,
        (file, Fail{host.error(code, message)}))
    case (file, Done{ExactResult{bytes, complete}}):
      response.header.complete(file, bytes, complete)

# Reads and validates one length-bounded response frame.
def read_response(
  file: File
) -> IO(File & Result<&1, &1, Error, Protocol.Response>):
  do IO<File & Result<&1, &1, Error, Protocol.Response>>:
    header : File & Result<&1, &1, U32 & String, ExactResult> <-
      exact.start(file, 24n)
    response.header.result(header)

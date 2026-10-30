import Base
import ./UnixSocketPolicy.bend as Policy
import ./UnixSocketTypes.bend as SocketTypes

# Represents an unavailable socket primitive or another raw host failure.
type Error is Data:
  UnsupportedPlatform{}
  Transient{code: U32}
  Host{code: U32, message: String}

# Carries the state for PollStatus.
type PollStatus is Data:
  Readable{}
  ReadableFailed{}
  Idle{}
  Failed{}

# Classifies the platform-specific unsupported syscall codes.
def unsupported_code(+code: U32) -> Bool:
  U32.is_eq(code, 95) || U32.is_eq(code, 45) ||
    U32.is_eq(code, 38) || U32.is_eq(code, 78)

# Converts one host code and message to the socket error domain.
def classify.mapping(
  classification: Policy.Classification,
  message: String
) -> Error:
  match classification:
    case Policy.UnsupportedPlatform{}: UnsupportedPlatform{}
    case Policy.Transient{code}: Transient{code}
    case Policy.Host{code}: Host{code, message}

# Converts a pure platform classification into the socket error surface.
def classify(pair: U32 & String) -> Error:
  match pair:
    case (code, message):
      classify.mapping(Policy.classify_code(code), message)

# Preserves ordinary host errors and types unsupported platforms.
def classify_result(
  result: Result<&1, &1, U32 & String, Unit>
) -> Result<&1, &1, Error, Unit>:
  match result:
    case Done{Unit{}}: Done{Unit{}}
    case Fail{error}: Fail{classify(error)}

# Rewrites the error domain without consuming the socket descriptor.
def classify_file_unit(
  pair: File & Result<&1, &1, U32 & String, Unit>
) -> File & Result<&1, &1, Error, Unit>:
  match pair:
    case (file, result): (file, classify_result(result))

# Rewrites an accepted descriptor's error domain.
def classify_file_result(
  pair: File & Result<&1, &1, U32 & String, File>
) -> File & Result<&1, &1, Error, File>:
  match pair:
    case (server, Done{client}): (server, Done{client})
    case (server, Fail{error}): (server, Fail{classify(error)})

# Handles classify poll result.
def classify_poll_result(
  result: Result<&1, &1, U32 & String, U32>
) -> Result<&1, &1, Error, U32>:
  match result:
    case Done{ready}: Done{ready}
    case Fail{error}: Fail{classify(error)}

def poll.status.classified(status: Policy.PollStatus) -> PollStatus:
  match status:
    case Policy.Readable{}: Readable{}
    case Policy.ReadableFailed{}: ReadableFailed{}
    case Policy.Idle{}: Idle{}
    case Policy.Failed{}: Failed{}

def poll.status(flags: U32) -> PollStatus:
  poll.status.classified(Policy.poll_status(flags))

def poll.failure.retryable(action: Policy.PollFailureAction) -> Bool:
  match action:
    case Policy.Retry{}: True{}
    case Policy.Stop{}: False{}

def poll.error.retryable(error: Error) -> Bool:
  match error:
    case Transient{code}: poll.failure.retryable(Policy.poll.failure(code))
    case _: False{}

# Rewrites a socket-creation error into the typed platform domain.
def classify_created(
  result: Result<&1, &1, U32 & String, File>
) -> Result<&1, &1, Error, File>:
  match result:
    case Done{file}: Done{file}
    case Fail{error}: Fail{classify(error)}

# Creates one stream socket through the paired host effects.
def unix_socket_create() -> IO(Result<&1, &1, U32 & String, File>):
  import "../effs/unix_socket_create.c"
  import "../effs/unix_socket_create.js"

# Creates one stream socket and types unsupported-platform failures.
def create() -> IO(Result<&1, &1, Error, File>):
  do IO<Result<&1, &1, Error, File>>:
    result : Result<&1, &1, U32 & String, File> <- unix_socket_create()
    return classify_created(result)

# Binds one socket descriptor to an already validated local endpoint path.
def unix_socket_bind(
  server: File,
  path: String
) -> IO(File & Result<&1, &1, U32 & String, Unit>):
  import "../effs/unix_socket_bind.c"
  import "../effs/unix_socket_bind.js"

# Binds one socket descriptor to an already validated local endpoint path.
def bind(
  server: File,
  path: String
) -> IO(File & Result<&1, &1, Error, Unit>):
  do IO<File & Result<&1, &1, Error, Unit>>:
    pair : File & Result<&1, &1, U32 & String, Unit> <-
      unix_socket_bind(server, path)
    return classify_file_unit(pair)

# Starts listening on one bound socket descriptor.
def unix_socket_listen(
  server: File,
  backlog: U32
) -> IO(File & Result<&1, &1, U32 & String, Unit>):
  import "../effs/unix_socket_listen.c"
  import "../effs/unix_socket_listen.js"

# Starts listening on one bound socket descriptor.
def listen(
  server: File,
  backlog: U32
) -> IO(File & Result<&1, &1, Error, Unit>):
  do IO<File & Result<&1, &1, Error, Unit>>:
    pair : File & Result<&1, &1, U32 & String, Unit> <-
      unix_socket_listen(server, backlog)
    return classify_file_unit(pair)

# Accepts one queued connection and preserves the listening descriptor.
def unix_socket_accept(
  server: File
) -> IO(File & Result<&1, &1, U32 & String, File>):
  import "../effs/unix_socket_accept.c"
  import "../effs/unix_socket_accept.js"

# Accepts one queued connection and preserves the listening descriptor.
def accept(
  server: File
) -> IO(File & Result<&1, &1, Error, File>):
  do IO<File & Result<&1, &1, Error, File>>:
    pair : File & Result<&1, &1, U32 & String, File> <-
      unix_socket_accept(server)
    return classify_file_result(pair)

# Handles unix socket nonblocking.
def unix_socket_nonblocking(
  socket: File
) -> IO(File & Result<&1, &1, U32 & String, Unit>):
  import "../effs/unix_socket_nonblocking.c"
  import "../effs/unix_socket_nonblocking.js"

# Handles nonblocking.
def nonblocking(
  socket: File
) -> IO(File & Result<&1, &1, Error, Unit>):
  do IO<File & Result<&1, &1, Error, Unit>>:
    result : File & Result<&1, &1, U32 & String, Unit> <-
      unix_socket_nonblocking(socket)
    return classify_file_unit(result)

# Handles unix socket poll.
def unix_socket_poll(
  socket: File,
  events: U32,
  timeout_ms: U32
) -> IO(File & Result<&1, &1, U32 & String, U32>):
  import "../effs/unix_socket_poll.c"
  import "../effs/unix_socket_poll.js"

# Handles classify poll pair.
def classify_poll_pair(
  pair: File & Result<&1, &1, U32 & String, U32>
) -> File & Result<&1, &1, Error, U32>:
  match pair:
    case (file, result): (file, classify_poll_result(result))

# Handles poll.
def poll(
  socket: File,
  events: U32,
  timeout_ms: U32
) -> IO(File & Result<&1, &1, Error, U32>):
  do IO<File & Result<&1, &1, Error, U32>>:
    pair : File & Result<&1, &1, U32 & String, U32> <-
      unix_socket_poll(socket, events, timeout_ms)
    return classify_poll_pair(pair)

# Handles unix socket poll many.
def unix_socket_poll_many(
  interests: List<SocketTypes.PollInterest>,
  timeout_ms: U32
) -> IO(List<SocketTypes.PollInterest> &
  Result<&1, &1, U32 & String, List<&2, SocketTypes.ReadyEvent>>):
  import "../effs/unix_socket_poll_many.c"
  import "../effs/unix_socket_poll_many.js"

def poll_many.result(
  pair: List<SocketTypes.PollInterest> & Result<&1, &1, U32 & String, List<&2, SocketTypes.ReadyEvent>>
) -> List<SocketTypes.PollInterest> &
  Result<&1, &1, Error, List<&2, SocketTypes.ReadyEvent>>:
  match pair:
    case (interests, Done{flags}): (interests, Done{flags})
    case (interests, Fail{error}): (interests, Fail{classify(error)})

# Handles poll many.
def poll_many(
  interests: List<SocketTypes.PollInterest>,
  timeout_ms: U32
) -> IO(List<SocketTypes.PollInterest> &
  Result<&1, &1, Error, List<&2, SocketTypes.ReadyEvent>>):
  do IO<List<SocketTypes.PollInterest> &
    Result<&1, &1, Error, List<&2, SocketTypes.ReadyEvent>>>:
    pair : List<SocketTypes.PollInterest> &
      Result<&1, &1, U32 & String, List<&2, SocketTypes.ReadyEvent>> <-
        unix_socket_poll_many(interests, timeout_ms)
    return poll_many.result(pair)

# Connects one client socket descriptor to a validated local endpoint path.
def unix_socket_connect(
  client: File,
  path: String
) -> IO(File & Result<&1, &1, U32 & String, Unit>):
  import "../effs/unix_socket_connect.c"
  import "../effs/unix_socket_connect.js"

# Connects one client socket descriptor to a validated local endpoint path.
def connect(
  client: File,
  path: String
) -> IO(File & Result<&1, &1, Error, Unit>):
  do IO<File & Result<&1, &1, Error, Unit>>:
    pair : File & Result<&1, &1, U32 & String, Unit> <-
      unix_socket_connect(client, path)
    return classify_file_unit(pair)

import Base
import ./UnixSocketPolicy.bend as Policy

# Represents an unavailable socket primitive or another raw host failure.
type Error is Data:
  UnsupportedPlatform{}
  Host{code: U32, message: String}

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

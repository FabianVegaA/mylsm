import Base
import ../../src/Console.bend as Console
import ../../src/Fs.bend as Fs
import ../../src/coordinator/UnixSocketIo.bend as UnixSocket
import ../../src/coordinator/UnixSocketTypes.bend as SocketTypes
import ../../src/coordinator/ConnectionStore.bend as ConnectionStore
import ../../src/coordinator/Io.bend as Io
import ../../src/coordinator/Protocol.bend as Protocol
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Carries the state for RepeatPollState.
type RepeatPollState is Type:
  PollAgain{interests: List<SocketTypes.PollInterest>}
  PollReturned{result:
    List<SocketTypes.PollInterest> &
      Result<&1, &1, UnixSocket.Error,
        List<&2, SocketTypes.ReadyEvent>>}
  PollFinished{interests: List<SocketTypes.PollInterest>, valid: Bool}

# Handles unix socket alarm.
def unix_socket_alarm() -> IO(Unit):
  import "unix_socket_alarm.c"
  import "unix_socket_alarm.js"

def schedule.alarm() -> IO(Unit):
  do IO<Unit>:
    _scheduled : Unit <- unix_socket_alarm()
    return Unit{}

def path.clone.pair.go(path: String, left: String,
  right: String) -> String & String:
  match path:
    case SNil{}: (String.reverse(left), String.reverse(right))
    case SCon{+character, rest}:
      path.clone.pair.go(rest, SCon{character, left},
        SCon{character, right})

def path.clone.pair(path: String) -> String & String:
  path.clone.pair.go(path, SNil{}, SNil{})

# Handles success.
def success(result: Bool) -> IO(Unit):
  match result:
    case True{}: IO.print("UNIX_SOCKET_POLL_MANY_PASSED")
    case False{}: IO.die(Unit, 1, "poll_many connection identity failed")

def event.is.second(event: SocketTypes.ReadyEvent) -> Bool:
  match event:
    case SocketTypes.ReadyEvent{2, flags}:
      Bool.not(U32.is_eq(U32.and(flags, 1), 0))
    case _: False{}

def event.is.third(event: SocketTypes.ReadyEvent) -> Bool:
  match event:
    case SocketTypes.ReadyEvent{3, flags}:
      Bool.not(U32.is_eq(flags, 0))
    case _: False{}

def events.only.second.shape(events: List<&2, SocketTypes.ReadyEvent>) -> Bool:
  match events:
    case Con{event, Nil{}}: event.is.second(event)
    case _: False{}

def events.counted.valid(
  counted: List<&2, SocketTypes.ReadyEvent> & Nat
) -> Bool:
  match counted:
    case (events, count):
      Nat.is_eq(count, 1n) && events.only.second.shape(events)

def events.only.second(+events: List<&2, SocketTypes.ReadyEvent>) -> Bool:
  events.counted.valid(ConnectionStore.event.count.keep(events)) &&
    events.only.second.shape(events)

def events.empty(events: List<&2, SocketTypes.ReadyEvent>) -> Bool:
  match events:
    case Nil{}: True{}
    case _: False{}

def repeat.poll.classify(
  result: List<SocketTypes.PollInterest> &
    Result<&1, &1, UnixSocket.Error,
      List<&2, SocketTypes.ReadyEvent>>
) -> RepeatPollState:
  match result:
    case (interests, Done{events}):
      match events:
        case Nil{}: PollAgain{interests}
        case Con{_, _}: PollFinished{interests, False{}}
    case (interests, Fail{_}): PollFinished{interests, False{}}

def repeat.poll.finish(state: RepeatPollState) -> List<SocketTypes.PollInterest> & Bool:
  match state:
    case PollAgain{interests}: (interests, True{})
    case PollFinished{interests, valid}: (interests, valid)
    case PollReturned{result}:
      match result:
        case (interests, Done{events}): (interests, events.empty(events))
        case (interests, Fail{_}): (interests, False{})

def repeat.poll.loop(
  fuel: Nat,
  state: RepeatPollState
) -> IO(List<SocketTypes.PollInterest> & Bool):
  match fuel:
    case 0n:
      IO.pure(List<SocketTypes.PollInterest> & Bool,
        repeat.poll.finish(state))
    case 1n+rest:
      match state:
        case PollAgain{interests}:
          do IO<List<SocketTypes.PollInterest> & Bool>:
            result : List<SocketTypes.PollInterest> &
              Result<&1, &1, UnixSocket.Error,
                List<&2, SocketTypes.ReadyEvent>> <-
              UnixSocket.poll_many(interests, 0)
            repeat.poll.loop(rest, PollReturned{result})
        case PollReturned{result}:
          repeat.poll.loop(rest, repeat.poll.classify(result))
        case PollFinished{interests, valid}:
          IO.pure(List<SocketTypes.PollInterest> & Bool,
            (interests, valid))

def close.all(interests: List<SocketTypes.PollInterest>) -> IO(Unit):
  match interests:
    case Nil{}: IO.pure(Unit, Unit{})
    case Con{interest, rest}:
      match interest:
        case SocketTypes.PollInterest{_, socket, _}:
          do IO<Unit>:
            _closed : Unit <- File.close(socket)
            close.all(rest)

# Handles cleanup.
def cleanup(
  result: List<SocketTypes.PollInterest> &
    Result<&1, &1, UnixSocket.Error, List<&2, SocketTypes.ReadyEvent>>,
  first_path: String,
  second_path: String,
  valid: Bool
) -> IO(Unit):
  match result:
    case (interests, Done{events}):
      do IO<Unit>:
        _closed : Unit <- close.all(interests)
        _first_removed : Result<&1, &1, U32 & String, Unit> <- Fs.remove(first_path)
        _second_removed : Result<&1, &1, U32 & String, Unit> <- Fs.remove(second_path)
        success(valid && events.empty(events))
    case (interests, Fail{_}):
      do IO<Unit>:
        _closed : Unit <- close.all(interests)
        _first_removed : Result<&1, &1, U32 & String, Unit> <- Fs.remove(first_path)
        _second_removed : Result<&1, &1, U32 & String, Unit> <- Fs.remove(second_path)
        IO.die(Unit, 1, "poll_many failed")

def repeat.poll.cleanup(
  state: List<SocketTypes.PollInterest> & Bool,
  first_path: String,
  second_path: String,
  valid: Bool
) -> IO(Unit):
  match state:
    case (interests, still_idle):
      cleanup((interests, Done{Nil{}}), first_path, second_path,
        valid && still_idle)

def events.one.third(events: List<&2, SocketTypes.ReadyEvent>) -> Bool:
  match events:
    case Con{event, Nil{}}: event.is.third(event)
    case _: False{}

def event.is.first(event: SocketTypes.ReadyEvent) -> Bool:
  match event:
    case SocketTypes.ReadyEvent{1, flags}:
      Bool.not(U32.is_eq(U32.and(flags, 1), 0))
    case _: False{}

def events.both(events: List<&2, SocketTypes.ReadyEvent>) -> Bool:
  match events:
    case Con{first, Con{second, Nil{}}}:
      event.is.first(first) && event.is.second(second)
    case _: False{}

def both.write.mode(
  result: File & Result<&1, &1, UnixSocket.Error, Unit>,
  client_two: File,
  first_connection: File,
  second_connection: File,
  first: File,
  second: File,
  first_path: String,
  second_path: String,
  valid: Bool
) -> IO(Unit):
  match result:
    case (file, Done{Unit{}}):
      do IO<Unit>:
        _file_closed : Unit <- File.close(file)
        _peer_closed : Unit <- File.close(first_connection)
        _client_two_closed : Unit <- File.close(client_two)
        _second_connection_closed : Unit <- File.close(second_connection)
        idle : List<SocketTypes.PollInterest> & Bool <-
          repeat.poll.loop(256n, PollAgain{[
            SocketTypes.PollInterest{1, first, 1},
            SocketTypes.PollInterest{2, second, 1}]})
        repeat.poll.cleanup(idle, first_path, second_path, valid)
    case (file, Fail{_}):
      do IO<Unit>:
        _file_closed : Unit <- File.close(file)
        _client_two_closed : Unit <- File.close(client_two)
        _first_connection_closed : Unit <- File.close(first_connection)
        _second_connection_closed : Unit <- File.close(second_connection)
        IO.die(Unit, 1, "client socket could not become nonblocking")

def both.write.completed(
  pair: File & Io.WriteAttempt,
  client_two: File,
  first_connection: File,
  second_connection: File,
  first: File,
  second: File,
  first_path: String,
  second_path: String,
  valid: Bool
) -> IO(Unit):
  match pair:
    case (client_one,
      Io.NonblockingWriteSent{Bytes.Bytes{1, _}, 1}):
      do IO<Unit>:
        mode : File & Result<&1, &1, UnixSocket.Error, Unit> <-
          UnixSocket.nonblocking(client_one)
        both.write.mode(mode, client_two, first_connection,
          second_connection, first, second, first_path, second_path, valid)
    case (client_one, _):
      do IO<Unit>:
        _client_one_closed : Unit <- File.close(client_one)
        _client_two_closed : Unit <- File.close(client_two)
        _first_connection_closed : Unit <- File.close(first_connection)
        _second_connection_closed : Unit <- File.close(second_connection)
        IO.die(Unit, 1, "nonblocking write did not retain its encoded byte")


def both.read.received(
  pair: File & Io.ReadAttempt,
  client_one: File,
  second_connection: File,
  first: File,
  second: File,
  client_two: File,
  first_path: String,
  second_path: String,
  valid: Bool
) -> IO(Unit):
  match pair:
    case (first_connection, Io.ReadAvailable{Bytes.Bytes{1, _}}):
      do IO<Unit>:
        written : File & Io.WriteAttempt <- Io.write.nonblocking(client_one,
          0, 1, Bytes.from_string("y"))
        both.write.completed(written, client_two, first_connection,
          second_connection, first, second, first_path, second_path, valid)
    case (first_connection, _):
      do IO<Unit>:
        _client_one_closed : Unit <- File.close(client_one)
        _client_two_closed : Unit <- File.close(client_two)
        _first_connection_closed : Unit <- File.close(first_connection)
        _second_connection_closed : Unit <- File.close(second_connection)
        IO.die(Unit, 1, "nonblocking read did not return the written byte")


def both.read.ready(
  result: List<SocketTypes.PollInterest> &
    Result<&1, &1, UnixSocket.Error, List<&2, SocketTypes.ReadyEvent>>,
  client_one: File,
  second_connection: File,
  first: File,
  second: File,
  client_two: File,
  first_path: String,
  second_path: String,
  valid: Bool
) -> IO(Unit):
  match result:
    case (Con{SocketTypes.PollInterest{10, first_connection, 1}, Nil{}},
      Done{Con{SocketTypes.ReadyEvent{10, flags}, Nil{}}}):
      do IO<Unit>:
        received : File & Io.ReadAttempt <- Io.read.nonblocking(
          first_connection, 1)
        both.read.received(received, client_one, second_connection,
          first, second, client_two, first_path, second_path, valid &&
            Bool.not(U32.is_eq(U32.and(flags, 1), 0)))
    case (interests, _):
      do IO<Unit>:
        _closed : Unit <- close.all(interests)
        _client_one_closed : Unit <- File.close(client_one)
        _client_two_closed : Unit <- File.close(client_two)
        _second_connection_closed : Unit <- File.close(second_connection)
        IO.die(Unit, 1, "written byte did not become readable")

def both.read.sent(
  sent: File & Result<&1, &1, U32 & String, Unit>,
  second_connection: File,
  first_connection: File,
  first: File,
  second: File,
  client_two: File,
  first_path: String,
  second_path: String,
  valid: Bool
) -> IO(Unit):
  match sent:
    case (client_one, Done{Unit{}}):
      do IO<Unit>:
        polled : List<SocketTypes.PollInterest> &
          Result<&1, &1, UnixSocket.Error, List<&2, SocketTypes.ReadyEvent>> <-
            UnixSocket.poll_many([
              SocketTypes.PollInterest{10, first_connection, 1}], 30000)
        both.read.ready(polled, client_one, second_connection,
          first, second, client_two, first_path, second_path, valid)
    case (client_one, Fail{(code, message)}):
      do IO<Unit>:
        _client_one_closed : Unit <- File.close(client_one)
        _client_two_closed : Unit <- File.close(client_two)
        _first_connection_closed : Unit <- File.close(first_connection)
        _second_connection_closed : Unit <- File.close(second_connection)
        IO.die(Unit, code, "nonblocking read fixture could not send a byte: " ++ message)
def both.read.second(
  pair: File & Io.ReadAttempt,
  first_connection: File,
  first: File,
  second: File,
  client_one: File,
  client_two: File,
  first_path: String,
  second_path: String,
  valid: Bool
) -> IO(Unit):
  match pair:
    case (second_connection, Io.ReadWouldBlock{}):
      do IO<Unit>:
        sent : File & Result<&1, &1, U32 & String, Unit> <-
          Io.write_all(client_one, Bytes.from_string("x"))
        both.read.sent(sent, second_connection, first_connection,
          first, second, client_two, first_path, second_path, valid)
    case (second_connection, _):
      do IO<Unit>:
        _first_closed : Unit <- File.close(first_connection)
        _second_closed : Unit <- File.close(second_connection)
        _client_one_closed : Unit <- File.close(client_one)
        _client_two_closed : Unit <- File.close(client_two)
        IO.die(Unit, 1, "second silent read did not report would-block")
def both.read.first(
  pair: File & Io.ReadAttempt,
  second_connection: File,
  first: File,
  second: File,
  client_one: File,
  client_two: File,
  first_path: String,
  second_path: String,
  valid: Bool
) -> IO(Unit):
  match pair:
    case (first_connection, Io.ReadWouldBlock{}):
      do IO<Unit>:
        second_read : File & Io.ReadAttempt <- Io.read.nonblocking(
          second_connection, 1)
        both.read.second(second_read, first_connection, first, second,
          client_one, client_two, first_path, second_path, valid)
    case (first_connection, _):
      do IO<Unit>:
        _first_closed : Unit <- File.close(first_connection)
        _second_closed : Unit <- File.close(second_connection)
        _client_one_closed : Unit <- File.close(client_one)
        _client_two_closed : Unit <- File.close(client_two)
        IO.die(Unit, 1, "silent nonblocking read did not report would-block")

def both.nonblocking.second(
  pair: File & Result<&1, &1, UnixSocket.Error, Unit>,
  first_connection: File,
  first: File,
  second: File,
  client_one: File,
  client_two: File,
  first_path: String,
  second_path: String,
  valid: Bool
) -> IO(Unit):
  match pair:
    case (second_connection, Done{Unit{}}):
      do IO<Unit>:
        first_read : File & Io.ReadAttempt <- Io.read.nonblocking(
          first_connection, 1)
        both.read.first(first_read, second_connection, first, second,
          client_one, client_two, first_path, second_path, valid)
    case (second_connection, Fail{_}):
      do IO<Unit>:
        _first_closed : Unit <- File.close(first_connection)
        _second_closed : Unit <- File.close(second_connection)
        _client_one_closed : Unit <- File.close(client_one)
        _client_two_closed : Unit <- File.close(client_two)
        IO.die(Unit, 1, "second accepted socket could not become nonblocking")

def both.nonblocking.first(
  pair: File & Result<&1, &1, UnixSocket.Error, Unit>,
  second_connection: File,
  first: File,
  second: File,
  client_one: File,
  client_two: File,
  first_path: String,
  second_path: String,
  valid: Bool
) -> IO(Unit):
  match pair:
    case (first_connection, Done{Unit{}}):
      do IO<Unit>:
        second_result : File & Result<&1, &1, UnixSocket.Error, Unit> <-
          UnixSocket.nonblocking(second_connection)
        both.nonblocking.second(second_result, first_connection, first,
          second, client_one, client_two, first_path, second_path, valid)
    case (first_connection, Fail{_}):
      do IO<Unit>:
        _first_closed : Unit <- File.close(first_connection)
        _second_closed : Unit <- File.close(second_connection)
        _client_one_closed : Unit <- File.close(client_one)
        _client_two_closed : Unit <- File.close(client_two)
        IO.die(Unit, 1, "first accepted socket could not become nonblocking")


def both.accept.second(
  pair: File & Result<&1, &1, UnixSocket.Error, File>,
  first: File,
  first_connection: File,
  client_one: File,
  client_two: File,
  first_path: String,
  second_path: String,
  valid: Bool
) -> IO(Unit):
  match pair:
    case (second, Done{second_connection}):
      do IO<Unit>:
        first_result : File & Result<&1, &1, UnixSocket.Error, Unit> <-
          UnixSocket.nonblocking(first_connection)
        both.nonblocking.first(first_result, second_connection, first, second,
          client_one, client_two, first_path, second_path, valid)
    case (_, Fail{_}): IO.die(Unit, 1, "second ready listener could not accept")

def both.accept.first(
  pair: File & Result<&1, &1, UnixSocket.Error, File>,
  second: File,
  client_one: File,
  client_two: File,
  first_path: String,
  second_path: String,
  valid: Bool
) -> IO(Unit):
  match pair:
    case (first, Done{first_connection}):
      do IO<Unit>:
        second_pair : File & Result<&1, &1, UnixSocket.Error, File> <-
          UnixSocket.accept(second)
        both.accept.second(second_pair, first, first_connection,
          client_one, client_two, first_path, second_path, valid)
    case (_, Fail{_}): IO.die(Unit, 1, "first ready listener could not accept")

def both.polled(
  client_one: File,
  client_two: File,
  first_path: String,
  second_path: String,
  valid: Bool,
  result: List<SocketTypes.PollInterest> &
    Result<&1, &1, UnixSocket.Error, List<&2, SocketTypes.ReadyEvent>>
) -> IO(Unit):
  match result:
    case (Con{SocketTypes.PollInterest{1, first, 1},
      Con{SocketTypes.PollInterest{2, second, 1}, Nil{}}}, Done{events}):
      do IO<Unit>:
        first_pair : File & Result<&1, &1, UnixSocket.Error, File> <-
          UnixSocket.accept(first)
        both.accept.first(first_pair, second, client_one, client_two,
          first_path, second_path, valid && events.both(events))
    case (interests, Done{_}):
      do IO<Unit>:
        _closed : Unit <- close.all(interests)
        IO.die(Unit, 1, "both-ready poll changed its owned interests")
    case (interests, Fail{_}):
      do IO<Unit>:
        _closed : Unit <- close.all(interests)
      IO.die(Unit, 1, "both-ready poll failed")

def both.store.restored(
  decision: ConnectionStore.RestoreDecision,
  events: List<&2, SocketTypes.ReadyEvent>,
  client_one: File,
  client_two: File,
  first_path: String,
  second_path: String,
  valid: Bool
) -> IO(Unit):
  match decision:
    case ConnectionStore.Restored{connections, ids_valid}:
      match connections:
        case Con{ConnectionStore.Connection{1, first_socket, 1,
          ConnectionStore.Closing{}},
          Con{ConnectionStore.Connection{2, second_socket, 1,
            ConnectionStore.Closing{}}, Nil{}}}:
          both.polled(client_one, client_two, first_path, second_path,
            valid && ids_valid,
            (Con{SocketTypes.PollInterest{1, first_socket, 1},
              Con{SocketTypes.PollInterest{2, second_socket, 1}, Nil{}}},
              Done{events}))
        case _: IO.die(Unit, 1, "restored connection collection changed")
    case ConnectionStore.InvalidLengths{metadata, interests}:
      do IO<Unit>:
        _closed : Unit <- close.all(interests)
        IO.die(Unit, 1, "connection restore changed collection length")

def both.store.polled(
  metadata: List<&1, ConnectionStore.Metadata>,
  client_one: File,
  client_two: File,
  first_path: String,
  second_path: String,
  valid: Bool,
  result: List<SocketTypes.PollInterest> &
    Result<&1, &1, UnixSocket.Error, List<&2, SocketTypes.ReadyEvent>>
) -> IO(Unit):
  match result:
    case (interests, Done{events}):
      both.store.restored(ConnectionStore.restore(metadata, interests), events,
        client_one, client_two, first_path, second_path, valid)
    case (interests, Fail{_}):
      do IO<Unit>:
        _closed : Unit <- close.all(interests)
        IO.die(Unit, 1, "split connection poll failed")

def both.store.split(
  client_one: File,
  client_two: File,
  first_path: String,
  second_path: String,
  valid: Bool,
  split: ConnectionStore.Split
) -> IO(Unit):
  match split:
    case ConnectionStore.Split{metadata, interests}:
      do IO<Unit>:
        result : List<SocketTypes.PollInterest> &
          Result<&1, &1, UnixSocket.Error,
            List<&2, SocketTypes.ReadyEvent>> <-
          UnixSocket.poll_many(interests, 30000)
        both.store.polled(metadata, client_one, client_two, first_path,
          second_path, valid, result)

def both.client.second.connected(
  first: File,
  second: File,
  first_path: String,
  second_path: String,
  client_one: File,
  valid: Bool,
  result: File & Result<&1, &1, UnixSocket.Error, Unit>
) -> IO(Unit):
  match result:
    case (client_two, Done{Unit{}}):
      both.store.split(client_one, client_two, first_path, second_path, valid,
        ConnectionStore.split([
          ConnectionStore.Connection{1, first, 1, ConnectionStore.Closing{}},
          ConnectionStore.Connection{2, second, 1, ConnectionStore.Closing{}}]))
    case (client_two, Fail{_}):
      do IO<Unit>:
        _closed : Unit <- File.close(client_two)
        _first_closed : Unit <- File.close(client_one)
        IO.die(Unit, 1, "second both-ready client could not connect")

def both.client.second.paths(
  first: File,
  second: File,
  first_path: String,
  client_one: File,
  valid: Bool,
  paths: String & String,
  client_two: File
) -> IO(Unit):
  match paths:
    case (connect_path, retained_path):
      do IO<Unit>:
        result : File & Result<&1, &1, UnixSocket.Error, Unit> <-
          UnixSocket.connect(client_two, connect_path)
        both.client.second.connected(first, second, first_path, retained_path,
          client_one, valid, result)

def both.client.second.created(
  first: File,
  second: File,
  first_path: String,
  second_path: String,
  client_one: File,
  valid: Bool,
  result: Result<&1, &1, UnixSocket.Error, File>
) -> IO(Unit):
  match result:
    case Done{client_two}:
      both.client.second.paths(first, second, first_path, client_one,
        valid, path.clone.pair(second_path), client_two)
    case Fail{_}:
      do IO<Unit>:
        _closed : Unit <- File.close(client_one)
        IO.die(Unit, 1, "second both-ready client could not be created")

def both.client.first.connected(
  first: File,
  second: File,
  first_path: String,
  second_path: String,
  valid: Bool,
  result: File & Result<&1, &1, UnixSocket.Error, Unit>
) -> IO(Unit):
  match result:
    case (client_one, Done{Unit{}}):
      do IO<Unit>:
        client_two : Result<&1, &1, UnixSocket.Error, File> <-
          UnixSocket.create()
        both.client.second.created(first, second, first_path, second_path,
          client_one, valid, client_two)
    case (client_one, Fail{_}):
      do IO<Unit>:
        _closed : Unit <- File.close(client_one)
        IO.die(Unit, 1, "first both-ready client could not connect")

def both.client.first.paths(
  first: File,
  second: File,
  paths: String & String,
  second_path: String,
  client_one: File,
  valid: Bool
) -> IO(Unit):
  match paths:
    case (connect_path, retained_path):
      do IO<Unit>:
        result : File & Result<&1, &1, UnixSocket.Error, Unit> <-
          UnixSocket.connect(client_one, connect_path)
        both.client.first.connected(first, second, retained_path,
          second_path, valid, result)

def both.client.first.created(
  first: File,
  second: File,
  first_path: String,
  second_path: String,
  valid: Bool,
  result: Result<&1, &1, UnixSocket.Error, File>
) -> IO(Unit):
  match result:
    case Done{client_one}:
      both.client.first.paths(first, second, path.clone.pair(first_path),
        second_path, client_one, valid)
    case Fail{_}: IO.die(Unit, 1, "first both-ready client could not be created")

def both.start(
  first: File,
  second: File,
  first_path: String,
  second_path: String,
  valid: Bool
) -> IO(Unit):
  do IO<Unit>:
    client_one : Result<&1, &1, UnixSocket.Error, File> <- UnixSocket.create()
    both.client.first.created(first, second, first_path, second_path,
      valid, client_one)

def hup.checked(
  result: List<SocketTypes.PollInterest> &
    Result<&1, &1, UnixSocket.Error, List<&2, SocketTypes.ReadyEvent>>,
  first: File,
  second: File,
  first_path: String,
  second_path: String,
  valid: Bool
) -> IO(Unit):
  match result:
    case (Con{SocketTypes.PollInterest{3, connection, 1}, Nil{}},
      Done{events}):
      do IO<Unit>:
        _connection_closed : Unit <- File.close(connection)
        both.start(first, second, first_path, second_path,
          valid && events.one.third(events))
    case (interests, Done{_}):
      do IO<Unit>:
        _closed : Unit <- close.all(interests)
        IO.die(Unit, 1, "poll_many HUP changed its owned interest")
    case (interests, Fail{_}):
      do IO<Unit>:
        _closed : Unit <- close.all(interests)
        IO.die(Unit, 1, "poll_many HUP failed")

# Handles accepted.
def accepted(
  pair: File & Result<&1, &1, UnixSocket.Error, File>,
  client: File,
  first: File,
  first_path: String,
  second_path: String,
  valid: Bool
) -> IO(Unit):
  match pair:
    case (second, Done{connection}):
      do IO<Unit>:
        _client_closed : Unit <- File.close(client)
        polled_hup : List<SocketTypes.PollInterest> &
          Result<&1, &1, UnixSocket.Error,
            List<&2, SocketTypes.ReadyEvent>> <-
          UnixSocket.poll_many([
            SocketTypes.PollInterest{3, connection, 1}], 30000)
        hup.checked(polled_hup, first, second, first_path, second_path, valid)
    case (_, Fail{_}): IO.die(Unit, 1, "ready poll listener could not accept")

# Handles polled.
def polled(
  client: File,
  first_path: String,
  second_path: String,
  result: List<SocketTypes.PollInterest> &
    Result<&1, &1, UnixSocket.Error, List<&2, SocketTypes.ReadyEvent>>
) -> IO(Unit):
  match result:
    case (Con{SocketTypes.PollInterest{1, first, 1},
      Con{SocketTypes.PollInterest{2, second, 1}, Nil{}}}, Done{events}):
      do IO<Unit>:
        pair : File & Result<&1, &1, UnixSocket.Error, File> <-
          UnixSocket.accept(second)
        accepted(pair, client, first, first_path, second_path,
          events.only.second(events))
    case (_, Fail{_}): IO.die(Unit, 1, "poll_many failed")
    case (_, Done{_}): IO.die(Unit, 1, "poll_many changed its owned interests")

# Handles connected.
def connected(
  first: File,
  second: File,
  first_path: String,
  second_path: String,
  result: File & Result<&1, &1, UnixSocket.Error, Unit>
) -> IO(Unit):
  match result:
    case (client, Done{Unit{}}):
      do IO<Unit>:
        result : List<SocketTypes.PollInterest> &
          Result<&1, &1, UnixSocket.Error,
            List<&2, SocketTypes.ReadyEvent>> <-
          UnixSocket.poll_many([
            SocketTypes.PollInterest{1, first, 1},
            SocketTypes.PollInterest{2, second, 1}], 30000)
        polled(client, first_path, second_path, result)
    case (client, Fail{_}):
      do IO<Unit>:
        _closed : Unit <- File.close(client)
        IO.die(Unit, 1, "second poll client could not connect")

def client.created.paths(
  first: File,
  second: File,
  first_path: String,
  paths: String & String,
  client: File
) -> IO(Unit):
  match paths:
    case (connect_path, retained_path):
      do IO<Unit>:
        result : File & Result<&1, &1, UnixSocket.Error, Unit> <-
          UnixSocket.connect(client, connect_path)
        connected(first, second, first_path, retained_path, result)

def client.created(
  first: File,
  second: File,
  first_path: String,
  second_path: String,
  result: Result<&1, &1, UnixSocket.Error, File>
) -> IO(Unit):
  match result:
    case Done{client}:
      client.created.paths(first, second, first_path,
        path.clone.pair(second_path), client)
    case Fail{_}: IO.die(Unit, 1, "second poll client could not be created")

def timeout.checked(
  first_path: String,
  second_path: String,
  result: List<SocketTypes.PollInterest> &
    Result<&1, &1, UnixSocket.Error, List<&2, SocketTypes.ReadyEvent>>
) -> IO(Unit):
  match result:
    case (Con{SocketTypes.PollInterest{1, first, 1},
      Con{SocketTypes.PollInterest{2, second, 1}, Nil{}}}, Done{Nil{}}):
      do IO<Unit>:
        client : Result<&1, &1, UnixSocket.Error, File> <- UnixSocket.create()
        client.created(first, second, first_path, second_path, client)
    case (interests, Done{_}):
      do IO<Unit>:
        _closed : Unit <- close.all(interests)
        IO.die(Unit, 1, "poll_many timeout reported readiness")
    case (interests, Fail{_}):
      do IO<Unit>:
        _closed : Unit <- close.all(interests)
        IO.die(Unit, 1, "poll_many timeout failed")

def interrupted.checked(
  first_path: String,
  second_path: String,
  pair: List<SocketTypes.PollInterest> &
    Result<&1, &1, UnixSocket.Error, List<&2, SocketTypes.ReadyEvent>>
) -> IO(Unit):
  match pair:
    case (interests, Fail{UnixSocket.Transient{4}}):
      do IO<Unit>:
        result : List<SocketTypes.PollInterest> &
          Result<&1, &1, UnixSocket.Error,
            List<&2, SocketTypes.ReadyEvent>> <-
          UnixSocket.poll_many(interests, 0)
        timeout.checked(first_path, second_path, result)
    case (interests, Done{_}):
      do IO<Unit>:
        _closed : Unit <- close.all(interests)
        IO.die(Unit, 1, "scheduled signal did not interrupt poll_many")
    case (interests, Fail{_}):
      do IO<Unit>:
        _closed : Unit <- close.all(interests)
        IO.die(Unit, 1, "poll_many returned the wrong interruption error")

def second.ready(
  first: File,
  first_path: String,
  second_path: String,
  result: File & Result<&1, &1, UnixSocket.Error, Unit>
) -> IO(Unit):
  match result:
    case (second, Done{Unit{}}):
      do IO<Unit>:
        _scheduled : Unit <- schedule.alarm()
        result : List<SocketTypes.PollInterest> &
          Result<&1, &1, UnixSocket.Error,
            List<&2, SocketTypes.ReadyEvent>> <-
          UnixSocket.poll_many([
            SocketTypes.PollInterest{1, first, 1},
            SocketTypes.PollInterest{2, second, 1}], 30000)
        interrupted.checked(first_path, second_path, result)
    case (second, Fail{_}):
      do IO<Unit>:
        _closed : Unit <- File.close(second)
        IO.die(Unit, 1, "second poll listener could not listen")

def second.bound(
  first: File,
  first_path: String,
  second_path: String,
  result: File & Result<&1, &1, UnixSocket.Error, Unit>
) -> IO(Unit):
  match result:
    case (second, Done{Unit{}}):
      do IO<Unit>:
        result : File & Result<&1, &1, UnixSocket.Error, Unit> <-
          UnixSocket.listen(second, 8)
        second.ready(first, first_path, second_path, result)
    case (second, Fail{_}):
      do IO<Unit>:
        _closed : Unit <- File.close(second)
        IO.die(Unit, 1, "second poll listener could not bind")

def second.created.paths(
  first: File,
  first_path: String,
  paths: String & String,
  second: File
) -> IO(Unit):
  match paths:
    case (bind_path, retained_path):
      do IO<Unit>:
        result : File & Result<&1, &1, UnixSocket.Error, Unit> <-
          UnixSocket.bind(second, bind_path)
        second.bound(first, first_path, retained_path, result)

def second.created(
  first: File,
  first_path: String,
  second_path: String,
  result: Result<&1, &1, UnixSocket.Error, File>
) -> IO(Unit):
  match result:
    case Done{second}:
      second.created.paths(first, first_path,
        path.clone.pair(second_path), second)
    case Fail{_}: IO.die(Unit, 1, "second poll listener could not be created")

def first.ready(
  first_path: String,
  second_path: String,
  result: File & Result<&1, &1, UnixSocket.Error, Unit>
) -> IO(Unit):
  match result:
    case (first, Done{Unit{}}):
      do IO<Unit>:
        second : Result<&1, &1, UnixSocket.Error, File> <- UnixSocket.create()
        second.created(first, first_path, second_path, second)
    case (first, Fail{_}):
      do IO<Unit>:
        _closed : Unit <- File.close(first)
        IO.die(Unit, 1, "first poll listener could not listen")

def first.bound(
  first_path: String,
  second_path: String,
  result: File & Result<&1, &1, UnixSocket.Error, Unit>
) -> IO(Unit):
  match result:
    case (first, Done{Unit{}}):
      do IO<Unit>:
        result : File & Result<&1, &1, UnixSocket.Error, Unit> <-
          UnixSocket.listen(first, 8)
        first.ready(first_path, second_path, result)
    case (first, Fail{_}):
      do IO<Unit>:
        _closed : Unit <- File.close(first)
        IO.die(Unit, 1, "first poll listener could not bind")

def first.created.paths(
  paths: String & String,
  second_path: String,
  first: File
) -> IO(Unit):
  match paths:
    case (bind_path, retained_path):
      do IO<Unit>:
        result : File & Result<&1, &1, UnixSocket.Error, Unit> <-
          UnixSocket.bind(first, bind_path)
        first.bound(retained_path, second_path, result)

def first.created(
  first_path: String,
  second_path: String,
  result: Result<&1, &1, UnixSocket.Error, File>
) -> IO(Unit):
  match result:
    case Done{first}:
      first.created.paths(path.clone.pair(first_path), second_path, first)
    case Fail{_}: IO.die(Unit, 1, "first poll listener could not be created")

def main() -> IO(Unit):
  do IO<Unit>:
    first_path : String <- IO.try(String, Console.get_env("MYLSM_POLL_FIRST"))
    second_path : String <- IO.try(String, Console.get_env("MYLSM_POLL_SECOND"))
    first : Result<&1, &1, UnixSocket.Error, File> <- UnixSocket.create()
    first.created(first_path, second_path, first)

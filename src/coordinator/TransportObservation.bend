import Base
import ../Console.bend as Console
import ./ConnectionStore.bend as Connections
import ./TransportBudgetPolicy.bend as Budget

# Writes one already-formatted fixture record; host code only performs the write.
def emit(line: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  import "../effs/transport_observation.c"
  import "../effs/transport_observation.js"

def record.enabled(enabled: Bool, line: String) -> IO(Unit):
  match enabled:
    case False{}: IO.pure(Unit, Unit{})
    case True{}: IO.try(Unit, emit("MYLSM_TRANSPORT " ++ line ++ "\n"))

# Reads the opt-in fixture setting without moving policy into host code.
def enabled() -> IO(Bool):
  do IO<Bool>:
    configured : String <- IO.try(String,
      Console.get_env("MYLSM_TRANSPORT_OBSERVE"))
    return String.eq(configured, "1")

# Keeps fixture activation and record formatting in Bend.
def record(line: String) -> IO(Unit):
  do IO<Unit>:
    active : Bool <- enabled()
    record.enabled(active, line)

# Records the fixed control and header credit acquired with an admitted socket.
def opened(id: U32, connection_limit: U32, tx_capacity: Nat) -> IO(Unit):
  record("open " ++ U32.show(id) ++ " " ++ U32.show(connection_limit) ++
    " " ++ Nat.show(tx_capacity))

# Records the single release point for an admitted connection and its TX credit.
def closed(id: U32) -> IO(Unit):
  record("close " ++ U32.show(id))

# Observes the affine reservation immediately before the synchronous dispatcher.
def dispatched(flight: Budget.InFlight) -> IO(Budget.InFlight):
  match flight:
    case Budget.DispatchedRequest{Budget.DispatchReservation{+id,
        +request_bytes, +payload_limit, +peak_bytes}}:
      do IO<Budget.InFlight>:
        _recorded : Unit <- record("reserve " ++ U32.show(id) ++ " " ++
          Nat.show(request_bytes) ++ " " ++ Nat.show(peak_bytes) ++ " " ++
          U32.show(payload_limit))
        return Budget.DispatchedRequest{Budget.DispatchReservation{id,
          request_bytes, payload_limit, peak_bytes}}
    case other: IO.pure(Budget.InFlight, other)

# Observes transfer to an encoded frame without releasing its reservation.
def framed(reservation: Budget.FrameReservation, length: U32)
  -> IO(Budget.FrameReservation):
  match reservation:
    case Budget.FrameReservation{+id, +peak_bytes}:
      do IO<Budget.FrameReservation>:
        _recorded : Unit <- record("frame " ++ U32.show(id) ++ " " ++
          Nat.show(peak_bytes) ++ " " ++ U32.show(length))
        return Budget.FrameReservation{id, peak_bytes}

# Publishes a census outside the FIFO dispatcher, including reserved fixed slots.
def census(metrics: Connections.TransmitCount) -> IO(Connections.TransmitCount):
  match metrics:
    case Connections.TransmitCount{connections, +reserved, +count, +live,
        +control, +header}:
      do IO<Connections.TransmitCount>:
        _recorded : Unit <- record("census " ++ Nat.show(count) ++ " " ++
          Nat.show(reserved) ++ " " ++ Nat.show(live) ++ " " ++
          Nat.show(control) ++ " " ++ Nat.show(header))
        return Connections.TransmitCount{connections, reserved, count, live,
          control, header}

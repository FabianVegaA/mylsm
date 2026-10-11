import Base
import ../../src/ByteDurableDb.bend as ByteDb
import ../../src/Console.bend as Console
import ../../src/coordinator/CursorCodec.bend as CursorCodec
import ../../src/coordinator/Owner.bend as Owner
import ../../src/coordinator/OwnerCursorStore.bend as CursorStore
import ../../src/coordinator/OwnerSnapshotStore.bend as SnapshotStore
import ../../src/coordinator/Protocol.bend as Protocol
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Decodes a hexadecimal fixture into the exact request bytes.
def bytes.parsed(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}: bytes
    case None{}: Bytes.new(0)

# Converts a hexadecimal fixture into its exact byte sequence.
def bytes(hex: String) -> Bytes.Bytes:
  bytes.parsed(Bytes.from_hex(hex))

# Extracts exact byte equality from a package comparison.
def bytes.equal(pair: Bytes.Bytes & Bytes.Bytes & Bool) -> Bool:
  match pair:
    case (_, _, equal): equal

# Closes the durable database after the cursor and snapshot have been released.
def finished(result: Result<&1, &1, ByteDb.Error, Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.print("OWNER_CURSOR_DISPATCH_PASSED")
    case Fail{_}: IO.die(Unit, 1, "cursor fixture database close failed")

# Closes the durable handle after owner resource cleanup succeeds.
def close.database(handle: ByteDb.Handle) -> IO(Unit):
  do IO<Unit>:
    result : Result<&1, &1, ByteDb.Error, Unit> <- ByteDb.close(handle)
    finished(result)

# Fails the fixture only after releasing its durable database handle.
def fail.close(handle: ByteDb.Handle, message: String) -> IO(Unit):
  do IO<Unit>:
    _closed : Result<&1, &1, ByteDb.Error, Unit> <- ByteDb.close(handle)
    IO.die(Unit, 1, message)

# Closes the parent snapshot after its cursor reaches End.
def snapshot.close.result(result: Owner.DispatchResult) -> IO(Unit):
  match result:
    case Owner.DispatchResult{handle, _, _, Protocol.Response{_, _, _,
        Protocol.Success{}, _}}: close.database(handle)
    case Owner.DispatchResult{handle, _, _, _}:
      fail.close(handle, "owner rejected snapshot close after cursor End")

# Releases one childless snapshot through stateful owner dispatch.
def snapshot.close(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  snapshot_id: U32
) -> IO(Unit):
  do IO<Unit>:
    result : Owner.DispatchResult <- Owner.dispatch.request.state(handle,
      snapshots, cursors, Protocol.Request{1, 1, 6, 11,
        Protocol.snapshot.id.bytes(snapshot_id)}, 1)
    snapshot.close.result(result)

# Closes an owner cursor without reading it to End.
def cursor.close.response(
  result: Owner.DispatchResult,
  snapshot_id: U32
) -> IO(Unit):
  match result:
    case Owner.DispatchResult{handle, snapshots, cursors,
        Protocol.Response{_, _, _, Protocol.Success{}, _}}:
      snapshot.close(handle, snapshots, cursors, snapshot_id)
    case Owner.DispatchResult{handle, _, _, _}:
      fail.close(handle, "owner rejected explicit cursor close")

# Sends operation 14 and preserves the snapshot token for its final close.
def cursor.close.request.ids(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  ids: U32 & U32 & U32,
  cursor_id: U32
) -> IO(Unit):
  match ids:
    case (_, (snapshot_id, _)):
      do IO<Unit>:
        result : Owner.DispatchResult <- Owner.dispatch.request.state(handle,
          snapshots, cursors, Protocol.Request{1, 1, 7, 14,
            Protocol.snapshot.id.bytes(cursor_id)}, 1)
        cursor.close.response(result, snapshot_id)

# Requests explicit cursor close after a second cursor is opened.
def cursor.close.request(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  snapshot_id: U32,
  cursor_id: U32
) -> IO(Unit):
  cursor.close.request.ids(handle, snapshots, cursors,
    Protocol.u32.duplicate.triple(snapshot_id), cursor_id)

# Parses the cursor token returned by the second cursor-open request.
def cursor.close.token(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  snapshot_id: U32,
  parsed: Maybe<&2, U32>
) -> IO(Unit):
  match parsed:
    case Some{cursor_id}:
      cursor.close.request(handle, snapshots, cursors, snapshot_id, cursor_id)
    case None{}: fail.close(handle, "explicit-close cursor token was malformed")

# Continues after a second block-backed cursor has been opened.
def cursor.close.opened(
  result: Owner.DispatchResult,
  snapshot_id: U32
) -> IO(Unit):
  match result:
    case Owner.DispatchResult{handle, snapshots, cursors,
        Protocol.Response{_, _, _, Protocol.Success{}, payload}}:
      cursor.close.token(handle, snapshots, cursors, snapshot_id,
        Protocol.snapshot.id.read(payload))
    case Owner.DispatchResult{handle, _, _, _}:
      fail.close(handle, "owner rejected second cursor open")

# Opens a second cursor so the smoke covers explicit early closure.
def cursor.close.open.ids(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  ids: U32 & U32 & U32
) -> IO(Unit):
  match ids:
    case (wire_id, (snapshot_id, _)):
      do IO<Unit>:
        result : Owner.DispatchResult <- Owner.dispatch.request.state(handle,
          snapshots, cursors, Protocol.Request{1, 1, 6, 12,
            Protocol.snapshot.id.bytes(wire_id)}, 1)
        cursor.close.opened(result, snapshot_id)

# Opens an extra cursor after the first cursor's terminal End frame.
def cursor.close.open(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  snapshot_id: U32
) -> IO(Unit):
  cursor.close.open.ids(handle, snapshots, cursors,
    Protocol.u32.duplicate.triple(snapshot_id))

# Routes the owner response after matching the exact End frame.
def cursor.end.checked(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  snapshot_id: U32,
  matches: Bool
) -> IO(Unit):
  match matches:
    case True{}: cursor.close.open(handle, snapshots, cursors, snapshot_id)
    case False{}: fail.close(handle, "owner cursor End frame differed")

def cursor.next.end.result(
  result: Owner.DispatchResult,
  snapshot_id: U32
) -> IO(Unit):
  match result:
    case Owner.DispatchResult{handle, snapshots, cursors,
        Protocol.Response{_, _, _, Protocol.Success{}, payload}}:
      cursor.end.checked(handle, snapshots, cursors, snapshot_id,
        bytes.equal(Bytes.eq(payload,
          CursorCodec.encode(CursorCodec.CursorEnd{}))))
    case Owner.DispatchResult{handle, _, _, _}:
      fail.close(handle, "owner cursor next failed before End")

# Requests the second cursor step and validates that End is distinct from Item.
def cursor.next.end(
  result: Owner.DispatchResult,
  snapshot_id: U32
) -> IO(Unit):
  cursor.next.end.result(result, snapshot_id)

# Requests one cursor step using a retained owner cursor identifier.
def cursor.next.second(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  snapshot_id: U32,
  cursor_ids: U32 & U32 & U32
) -> IO(Unit):
  match cursor_ids:
    case (wire_id, (retained_id, _)):
      do IO<Unit>:
        result : Owner.DispatchResult <- Owner.dispatch.request.state(handle,
          snapshots, cursors, Protocol.Request{1, 1, 5, 13,
            Protocol.snapshot.id.bytes(wire_id)}, 1)
        cursor.next.end(result, snapshot_id)

# Verifies raw key and value bytes before requesting the terminal cursor step.
def cursor.item.checked(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  snapshot_id: U32,
  cursor_id: U32,
  matches: Bool
) -> IO(Unit):
  match matches:
    case True{}:
      cursor.next.second(handle, snapshots, cursors, snapshot_id,
        Protocol.u32.duplicate.triple(cursor_id))
    case False{}: fail.close(handle, "owner cursor item bytes differed")

def cursor.next.item.result(
  result: Owner.DispatchResult,
  snapshot_id: U32,
  cursor_id: U32
) -> IO(Unit):
  match result:
    case Owner.DispatchResult{handle, snapshots, cursors,
        Protocol.Response{_, _, _, Protocol.Success{}, payload}}:
      cursor.item.checked(handle, snapshots, cursors, snapshot_id, cursor_id,
        bytes.equal(Bytes.eq(payload, CursorCodec.encode(
          CursorCodec.CursorItem{bytes("00ff"), bytes("80ff00")}))))
    case Owner.DispatchResult{handle, _, _, _}:
      fail.close(handle, "owner cursor item read failed")

# Confirms the cursor codec preserves arbitrary key and value bytes.
def cursor.next.item(
  result: Owner.DispatchResult,
  snapshot_id: U32,
  cursor_id: U32
) -> IO(Unit):
  cursor.next.item.result(result, snapshot_id, cursor_id)

# Sends one incremental read and forwards its raw response frame.
def cursor.next.first(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  snapshot_id: U32,
  ids: U32 & U32 & U32
) -> IO(Unit):
  match ids:
    case (wire_id, (cursor_id, _)):
      do IO<Unit>:
        result : Owner.DispatchResult <- Owner.dispatch.request.state(handle,
          snapshots, cursors, Protocol.Request{1, 1, 4, 13,
            Protocol.snapshot.id.bytes(wire_id)}, 1)
        cursor.next.item(result, snapshot_id, cursor_id)

# Parses one owner-issued cursor token and starts its first incremental read.
def cursor.open.token(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  snapshot_id: U32,
  parsed: Maybe<&2, U32>
) -> IO(Unit):
  match parsed:
    case Some{cursor_id}:
      cursor.next.first(handle, snapshots, cursors, snapshot_id,
        Protocol.u32.duplicate.triple(cursor_id))
    case None{}: fail.close(handle, "owner cursor token was malformed")

# Routes cursor-open success and parses its fixed-width identifier.
def cursor.open.result(
  result: Owner.DispatchResult,
  snapshot_id: U32
) -> IO(Unit):
  match result:
    case Owner.DispatchResult{handle, snapshots, cursors,
        Protocol.Response{_, _, _, Protocol.Success{}, payload}}:
      cursor.open.token(handle, snapshots, cursors, snapshot_id,
        Protocol.snapshot.id.read(payload))
    case Owner.DispatchResult{handle, _, _, _}:
      fail.close(handle, "owner snapshot cursor open failed")

# Opens a full-range cursor over the retained owner snapshot.
def cursor.open.ids(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  ids: U32 & U32 & U32
) -> IO(Unit):
  match ids:
    case (wire_id, (snapshot_id, _)):
      do IO<Unit>:
        result : Owner.DispatchResult <- Owner.dispatch.request.state(handle,
          snapshots, cursors, Protocol.Request{1, 1, 3, 12,
            Protocol.snapshot.id.bytes(wire_id)}, 1)
        cursor.open.result(result, snapshot_id)

def snapshot.open.token(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  parsed: Maybe<&2, U32>
) -> IO(Unit):
  match parsed:
    case Some{snapshot_id}:
      cursor.open.ids(handle, snapshots, cursors,
        Protocol.u32.duplicate.triple(snapshot_id))
    case None{}: fail.close(handle, "owner snapshot token was malformed")

# Creates an owner snapshot and then requests its remote block-backed cursor.
def snapshot.open.result(result: Owner.DispatchResult) -> IO(Unit):
  match result:
    case Owner.DispatchResult{handle, snapshots, cursors,
        Protocol.Response{_, _, _, Protocol.Success{}, payload}}:
      snapshot.open.token(handle, snapshots, cursors,
        Protocol.snapshot.id.read(payload))
    case Owner.DispatchResult{handle, _, _, _}:
      fail.close(handle, "owner snapshot open failed")

# Registers one immutable owner snapshot before opening its remote cursor.
def snapshot.open(handle: ByteDb.Handle) -> IO(Unit):
  do IO<Unit>:
    result : Owner.DispatchResult <- Owner.dispatch.request.state(handle,
      SnapshotStore.empty(), CursorStore.empty(),
      Protocol.Request{1, 1, 2, 9, Bytes.new(0)}, 1)
    snapshot.open.result(result)

# Persists one binary key/value pair before exercising remote snapshot scans.
def written(pair: ByteDb.Handle & Result<&1, &1, ByteDb.Error, Unit>) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}): snapshot.open(handle)
    case (handle, Fail{_}): fail.close(handle, "cursor fixture put failed")

# Seeds the fixture database before dispatching snapshot and cursor operations.
def created(result: Result<&1, &1, ByteDb.Error, ByteDb.Handle>) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        pair : ByteDb.Handle & Result<&1, &1, ByteDb.Error, Unit> <-
          ByteDb.put(handle, bytes("00ff"), bytes("80ff00"))
        written(pair)
    case Fail{_}: IO.die(Unit, 1, "cursor fixture database creation failed")

# Starts the isolated owner cursor dispatch fixture.
def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, ByteDb.Error, ByteDb.Handle> <- ByteDb.create(path)
    created(result)

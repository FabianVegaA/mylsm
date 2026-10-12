import Base
import ../../src/ByteDurableDb.bend as ByteDb
import ../../src/Console.bend as Console
import ../../src/coordinator/Owner.bend as Owner
import ../../src/coordinator/OwnerCursorStore.bend as CursorStore
import ../../src/coordinator/OwnerSnapshotStore.bend as SnapshotStore
import ../../src/coordinator/Protocol.bend as Protocol
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

def bytes.parsed(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}: bytes
    case None{}: Bytes.new(0)

# Decodes a hexadecimal fixture into the exact request bytes.
def bytes(hex: String) -> Bytes.Bytes:
  bytes.parsed(Bytes.from_hex(hex))

def bytes.equal(pair: Bytes.Bytes & Bytes.Bytes & Bool) -> Bool:
  match pair:
    case (_, _, equal): equal

def fail.close(handle: ByteDb.Handle, message: String) -> IO(Unit):
  do IO<Unit>:
    _closed : Result<&1, &1, ByteDb.Error, Unit> <- ByteDb.close(handle)
    IO.die(Unit, 1, message)

# Reports success only after the fixture closes its durable handle.
def finished(result: Result<&1, &1, ByteDb.Error, Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.print("OWNER_SNAPSHOT_DISPATCH_PASSED")
    case Fail{_}: IO.die(Unit, 1, "owner snapshot dispatch close failed")

# Closes the durable handle after snapshot close has succeeded.
def closed(handle: ByteDb.Handle) -> IO(Unit):
  do IO<Unit>:
    result : Result<&1, &1, ByteDb.Error, Unit> <- ByteDb.close(handle)
    finished(result)

def close.response(result: Owner.DispatchResult) -> IO(Unit):
  match result:
    case Owner.DispatchResult{handle, _, _, Protocol.Response{_, _, _,
        Protocol.Success{}, _}}: closed(handle)
    case Owner.DispatchResult{handle, _, _, _}:
      fail.close(handle, "owner rejected snapshot close")

def close.snapshot(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  snapshot_id: U32
) -> IO(Unit):
  do IO<Unit>:
    result : Owner.DispatchResult <- Owner.dispatch.request.state(handle,
      snapshots, CursorStore.empty(), Protocol.Request{1, 1, 4, 11,
        Protocol.snapshot.id.bytes(snapshot_id)}, 1)
    close.response(result)

def get.value.checked(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  snapshot_id: U32,
  matches: Bool
) -> IO(Unit):
  match matches:
    case True{}: close.snapshot(handle, snapshots, snapshot_id)
    case False{}: fail.close(handle, "owner snapshot value changed")

def get.response(
  result: Owner.DispatchResult,
  snapshot_id: U32
) -> IO(Unit):
  match result:
    case Owner.DispatchResult{handle, snapshots, _,
        Protocol.Response{_, _, _, Protocol.Success{}, payload}}:
      get.value.checked(handle, snapshots, snapshot_id,
        bytes.equal(Bytes.eq(payload, bytes("80ff00"))))
    case Owner.DispatchResult{handle, _, _, _}:
      fail.close(handle, "owner snapshot get failed")

def get.snapshot.copies(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  ids: U32 & U32 & U32
) -> IO(Unit):
  match ids:
    case (wire_id, (snapshot_id, _)):
      do IO<Unit>:
        result : Owner.DispatchResult <- Owner.dispatch.request.state(handle,
          snapshots, CursorStore.empty(), Protocol.Request{1, 1, 3, 10,
            Bytes.concat([Protocol.snapshot.id.bytes(wire_id), bytes("00ff")])},
          1)
        get.response(result, snapshot_id)

def get.snapshot(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  snapshot_id: U32
) -> IO(Unit):
  get.snapshot.copies(handle, snapshots,
    Protocol.u32.duplicate.triple(snapshot_id))

def compact.response(
  result: Owner.DispatchResult,
  snapshot_id: U32
) -> IO(Unit):
  match result:
    case Owner.DispatchResult{handle, snapshots, _,
        Protocol.Response{_, _, _, Protocol.Success{}, _}}:
      get.snapshot(handle, snapshots, snapshot_id)
    case Owner.DispatchResult{handle, _, _, _}:
      fail.close(handle, "owner snapshot compaction failed")

def compact.snapshot(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  snapshot_id: U32
) -> IO(Unit):
  do IO<Unit>:
    result : Owner.DispatchResult <- Owner.dispatch.request.state(handle,
      snapshots, CursorStore.empty(), Protocol.Request{1, 1, 10, 5,
        Bytes.new(0)}, 1)
    compact.response(result, snapshot_id)


def open.token(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  parsed: Maybe<&2, U32>
) -> IO(Unit):
  match parsed:
    case Some{snapshot_id}: compact.snapshot(handle, snapshots, snapshot_id)
    case None{}: fail.close(handle, "owner snapshot token was malformed")

def open.result(result: Owner.DispatchResult) -> IO(Unit):
  match result:
    case Owner.DispatchResult{handle, snapshots, _,
        Protocol.Response{_, _, _, Protocol.Success{}, payload}}:
      open.token(handle, snapshots, Protocol.snapshot.id.read(payload))
    case Owner.DispatchResult{handle, _, _, _}:
      fail.close(handle, "owner snapshot open failed")

def open.snapshot(handle: ByteDb.Handle) -> IO(Unit):
  do IO<Unit>:
    result : Owner.DispatchResult <- Owner.dispatch.request.state(handle,
      SnapshotStore.empty(), CursorStore.empty(),
      Protocol.Request{1, 1, 2, 9, Bytes.new(0)}, 1)
    open.result(result)

def written.flushed(
  pair: ByteDb.Handle & Result<&1, &1, ByteDb.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}): open.snapshot(handle)
    case (handle, Fail{_}): fail.close(handle, "snapshot fixture flush failed")

# Flushes the fixture value before opening the retained snapshot.
def written(pair: ByteDb.Handle & Result<&1, &1, ByteDb.Error, Unit>) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        flushed : ByteDb.Handle & Result<&1, &1, ByteDb.Error, Unit> <-
          ByteDb.flush(handle)
        written.flushed(flushed)
    case (handle, Fail{_}): fail.close(handle, "snapshot fixture put failed")

# Creates the database and seeds its binary snapshot value.
def created(result: Result<&1, &1, ByteDb.Error, ByteDb.Handle>) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        pair : ByteDb.Handle & Result<&1, &1, ByteDb.Error, Unit> <-
          ByteDb.put(handle, bytes("00ff"), bytes("80ff00"))
        written(pair)
    case Fail{_}: IO.die(Unit, 1, "snapshot fixture database creation failed")

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, ByteDb.Error, ByteDb.Handle> <- ByteDb.create(path)
    created(result)

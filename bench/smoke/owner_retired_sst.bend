import Base
import ../../src/ByteDurableDb.bend as ByteDb
import ../../src/Console.bend as Console
import ../../src/coordinator/Operation.bend as Operation
import ../../src/coordinator/Owner.bend as Owner
import ../../src/coordinator/OwnerCursorStore.bend as CursorStore
import ../../src/coordinator/OwnerSnapshotStore.bend as SnapshotStore
import ../../src/coordinator/Protocol.bend as Protocol
import ../../src/ResourceOptions.bend as ResourceOptions
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Carries the state for SnapshotIds.
type SnapshotIds is Data:
  SnapshotIds{first: U32, duplicate: U32, second: U32, third: U32}

def snapshot.ids.first(+ids: SnapshotIds) -> U32:
  match ids:
    case SnapshotIds{first, _, _, _}: first

def snapshot.ids.duplicate(+ids: SnapshotIds) -> U32:
  match ids:
    case SnapshotIds{_, duplicate, _, _}: duplicate

def snapshot.ids.second(+ids: SnapshotIds) -> U32:
  match ids:
    case SnapshotIds{_, _, second, _}: second

def snapshot.ids.third(+ids: SnapshotIds) -> U32:
  match ids:
    case SnapshotIds{_, _, _, third}: third

def bytes.equal(pair: Bytes.Bytes & Bytes.Bytes & Bool) -> Bool:
  match pair:
    case (_, _, equal): equal

def bytes.value(result: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match result:
    case Some{value}: value
    case None{}: Bytes.new(0)

def bytes.from_hex(value: String) -> Bytes.Bytes:
  bytes.value(Bytes.from_hex(value))

def custom.options() -> ResourceOptions.Options:
  ResourceOptions.Options{
    ResourceOptions.TransportLimits{64, 16777216, 16777216, 16777216,
      30000, 30000},
    ResourceOptions.QueueLimits{64, 16777216, 30000},
    ResourceOptions.ReaderLimits{64, 4096, 64, 67108864, 2,
      16384, 65536, 67108864}}

# Handles fail.
def fail(message: String) -> IO(Unit):
  IO.die(Unit, 1, message)

# Handles request.
def request(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  +options: ResourceOptions.Options,
  request_id: U32,
  operation: U32,
  payload: Bytes.Bytes
) -> IO(Owner.DispatchResult):
  Owner.dispatch.request.with_options(handle, snapshots, cursors,
    Protocol.Request{1, 1, request_id, operation, payload}, 1, options)

def compacted.final.closed(
  result: Result<&1, &1, ByteDb.Error, Unit>
) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.print("OWNER_RETIRED_SST_PASSED")
    case Fail{_}: fail("owner database close failed")

def compacted.final(result: Owner.DispatchResult) -> IO(Unit):
  match result:
    case Owner.DispatchResult{handle, _, _,
        Protocol.Response{_, _, _, Protocol.Success{}, _}}:
      do IO<Unit>:
        closed : Result<&1, &1, ByteDb.Error, Unit> <- ByteDb.close(handle)
        compacted.final.closed(closed)
    case Owner.DispatchResult{handle, _, _, _}:
      do IO<Unit>:
        _closed : Result<&1, &1, ByteDb.Error, Unit> <- ByteDb.close(handle)
        fail("compaction did not resume after all snapshots closed")

def snapshots.close.third(
  result: Owner.DispatchResult,
  +options: ResourceOptions.Options
) -> IO(Unit):
  match result:
    case Owner.DispatchResult{handle, snapshots, cursors,
        Protocol.Response{_, _, _, Protocol.Success{}, _}}:
      do IO<Unit>:
        compacted : Owner.DispatchResult <- request(handle, snapshots,
          cursors, options, 16, 5, Bytes.new(0))
        compacted.final(compacted)
    case Owner.DispatchResult{handle, _, _, _}:
      do IO<Unit>:
        _closed : Result<&1, &1, ByteDb.Error, Unit> <- ByteDb.close(handle)
        fail("third snapshot close failed")

def snapshots.close.second(
  result: Owner.DispatchResult,
  +ids: SnapshotIds,
  +options: ResourceOptions.Options
) -> IO(Unit):
  match result:
    case Owner.DispatchResult{handle, snapshots, cursors,
        Protocol.Response{_, _, _, Protocol.Success{}, _}}:
      do IO<Unit>:
        closed : Owner.DispatchResult <- request(handle, snapshots, cursors,
          options, 15, 11,
          Protocol.snapshot.id.bytes(snapshot.ids.third(ids)))
        snapshots.close.third(closed, options)
    case Owner.DispatchResult{handle, _, _, _}:
      do IO<Unit>:
        _closed : Result<&1, &1, ByteDb.Error, Unit> <- ByteDb.close(handle)
        fail("second snapshot close failed")

def snapshots.close.duplicate(
  result: Owner.DispatchResult,
  +ids: SnapshotIds,
  +options: ResourceOptions.Options
) -> IO(Unit):
  match result:
    case Owner.DispatchResult{handle, snapshots, cursors,
        Protocol.Response{_, _, _, Protocol.Success{}, _}}:
      do IO<Unit>:
        closed : Owner.DispatchResult <- request(handle, snapshots, cursors,
          options, 14, 11,
          Protocol.snapshot.id.bytes(snapshot.ids.second(ids)))
        snapshots.close.second(closed, ids, options)
    case Owner.DispatchResult{handle, _, _, _}:
      do IO<Unit>:
        _closed : Result<&1, &1, ByteDb.Error, Unit> <- ByteDb.close(handle)
        fail("duplicate snapshot close failed")

def snapshots.close.first(
  result: Owner.DispatchResult,
  +ids: SnapshotIds,
  +options: ResourceOptions.Options
) -> IO(Unit):
  match result:
    case Owner.DispatchResult{handle, snapshots, cursors,
        Protocol.Response{_, _, _, Protocol.Success{}, _}}:
      do IO<Unit>:
        closed : Owner.DispatchResult <- request(handle, snapshots, cursors,
          options, 13, 11,
          Protocol.snapshot.id.bytes(snapshot.ids.duplicate(ids)))
        snapshots.close.duplicate(closed, ids, options)
    case Owner.DispatchResult{handle, _, _, _}:
      do IO<Unit>:
        _closed : Result<&1, &1, ByteDb.Error, Unit> <- ByteDb.close(handle)
        fail("first snapshot close failed")

def snapshots.first.value.equal(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  +ids: SnapshotIds,
  +options: ResourceOptions.Options,
  matches: Bool
) -> IO(Unit):
  match matches:
    case True{}:
      do IO<Unit>:
        closed : Owner.DispatchResult <- request(handle, snapshots, cursors,
          options, 12, 11,
          Protocol.snapshot.id.bytes(snapshot.ids.first(ids)))
        snapshots.close.first(closed, ids, options)
    case False{}:
      do IO<Unit>:
        _closed : Result<&1, &1, ByteDb.Error, Unit> <- ByteDb.close(handle)
        fail("first retained SST value changed after rejected compaction")

def snapshots.first.value(
  result: Owner.DispatchResult,
  +ids: SnapshotIds,
  +options: ResourceOptions.Options
) -> IO(Unit):
  match result:
    case Owner.DispatchResult{handle, snapshots, cursors,
        Protocol.Response{_, _, _, Protocol.Success{}, payload}}:
      snapshots.first.value.equal(handle, snapshots, cursors, ids, options,
        bytes.equal(Bytes.eq(payload, bytes.from_hex("31"))))
    case Owner.DispatchResult{handle, _, _, _}:
      do IO<Unit>:
        _closed : Result<&1, &1, ByteDb.Error, Unit> <- ByteDb.close(handle)
        fail("first retained snapshot could not be read")

def second.compacted(
  result: Owner.DispatchResult,
  +ids: SnapshotIds,
  +options: ResourceOptions.Options
) -> IO(Unit):
  match result:
    case Owner.DispatchResult{handle, snapshots, cursors,
        Protocol.Response{_, _, _, Protocol.ResponseResourceLimit{}, _}}:
      do IO<Unit>:
        first_value : Owner.DispatchResult <- request(handle, snapshots,
          cursors, options, 11, 10,
          Bytes.concat([Protocol.snapshot.id.bytes(snapshot.ids.first(ids)),
            bytes.from_hex("61")]))
        snapshots.first.value(first_value, ids, options)
    case Owner.DispatchResult{handle, _, _, _}:
      do IO<Unit>:
        _closed : Result<&1, &1, ByteDb.Error, Unit> <- ByteDb.close(handle)
        fail("compaction exceeded the retired SST budget")

def third.snapshot.id(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  +ids: SnapshotIds,
  +options: ResourceOptions.Options,
  result: Maybe<&2, U32>
) -> IO(Unit):
      match result:
        case Some{snapshot_id}:
          do IO<Unit>:
            compacted : Owner.DispatchResult <- request(handle, snapshots,
              cursors, options, 10, 5, Bytes.new(0))
            second.compacted(compacted,
              SnapshotIds{snapshot.ids.first(ids),
                snapshot.ids.duplicate(ids), snapshot.ids.second(ids),
                snapshot_id},
              options)
        case None{}: fail("third snapshot returned an invalid ID")

def third.snapshot(
  result: Owner.DispatchResult,
  +ids: SnapshotIds,
  +options: ResourceOptions.Options
) -> IO(Unit):
  match result:
    case Owner.DispatchResult{handle, snapshots, cursors,
        Protocol.Response{_, _, _, Protocol.Success{}, payload}}:
      third.snapshot.id(handle, snapshots, cursors, ids, options,
        Protocol.snapshot.id.read(payload))
    case Owner.DispatchResult{_, _, _, _}:
      fail("third snapshot open was rejected")

def first.compacted(
  result: Owner.DispatchResult,
  +ids: SnapshotIds,
  +options: ResourceOptions.Options
) -> IO(Unit):
  match result:
    case Owner.DispatchResult{handle, snapshots, cursors,
        Protocol.Response{_, _, _, Protocol.Success{}, _}}:
      do IO<Unit>:
        opened : Owner.DispatchResult <- request(handle, snapshots, cursors,
          options, 9, 9, Bytes.new(0))
        third.snapshot(opened, ids, options)
    case Owner.DispatchResult{_, _, _, _}:
      fail("two distinct retired generations were incorrectly rejected")

def second.snapshot.id(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  +ids: SnapshotIds,
  +options: ResourceOptions.Options,
  result: Maybe<&2, U32>
) -> IO(Unit):
      match result:
        case Some{snapshot_id}:
          do IO<Unit>:
            compacted : Owner.DispatchResult <- request(handle, snapshots,
              cursors, options, 8, 5, Bytes.new(0))
            first.compacted(compacted, SnapshotIds{
              snapshot.ids.first(ids), snapshot.ids.duplicate(ids),
              snapshot_id, 0}, options)
        case None{}: fail("second snapshot returned an invalid ID")

def second.snapshot(
  result: Owner.DispatchResult,
  +ids: SnapshotIds,
  +options: ResourceOptions.Options
) -> IO(Unit):
  match result:
    case Owner.DispatchResult{handle, snapshots, cursors,
        Protocol.Response{_, _, _, Protocol.Success{}, payload}}:
      second.snapshot.id(handle, snapshots, cursors, ids, options,
        Protocol.snapshot.id.read(payload))
    case Owner.DispatchResult{_, _, _, _}:
      fail("second snapshot open was rejected")

def second.flush(
  result: Owner.DispatchResult,
  +ids: SnapshotIds,
  +options: ResourceOptions.Options
) -> IO(Unit):
  match result:
    case Owner.DispatchResult{handle, snapshots, cursors,
        Protocol.Response{_, _, _, Protocol.Success{}, _}}:
      do IO<Unit>:
        opened : Owner.DispatchResult <- request(handle, snapshots, cursors,
          options, 7, 9, Bytes.new(0))
        second.snapshot(opened, ids, options)
    case Owner.DispatchResult{_, _, _, _}:
      fail("second SST flush was rejected")

def second.put(
  result: Owner.DispatchResult,
  +ids: SnapshotIds,
  +options: ResourceOptions.Options
) -> IO(Unit):
  match result:
    case Owner.DispatchResult{handle, snapshots, cursors,
        Protocol.Response{_, _, _, Protocol.Success{}, _}}:
      do IO<Unit>:
        flushed : Owner.DispatchResult <- request(handle, snapshots, cursors,
          options, 6, 4, Bytes.new(0))
        second.flush(flushed, ids, options)
    case Owner.DispatchResult{_, _, _, _}:
      fail("second SST put was rejected")

def first.duplicate.id(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  first_id: U32,
  +options: ResourceOptions.Options,
  result: Maybe<&2, U32>
) -> IO(Unit):
      match result:
        case Some{duplicate_id}:
          do IO<Unit>:
            written : Owner.DispatchResult <- request(handle, snapshots,
              cursors, options, 5, 2,
              Operation.encode.put(bytes.from_hex("62"),
                bytes.from_hex("32")))
            second.put(written, SnapshotIds{first_id, duplicate_id, 0, 0},
              options)
        case None{}: fail("duplicate snapshot returned an invalid ID")

def first.duplicate(
  result: Owner.DispatchResult,
  first_id: U32,
  +options: ResourceOptions.Options
) -> IO(Unit):
  match result:
    case Owner.DispatchResult{handle, snapshots, cursors,
        Protocol.Response{_, _, _, Protocol.Success{}, payload}}:
      first.duplicate.id(handle, snapshots, cursors, first_id,
        options, Protocol.snapshot.id.read(payload))
    case Owner.DispatchResult{_, _, _, _}:
      fail("duplicate snapshot open was rejected")

def first.snapshot.id(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  +options: ResourceOptions.Options,
  result: Maybe<&2, U32>
) -> IO(Unit):
      match result:
        case Some{snapshot_id}:
          do IO<Unit>:
            opened : Owner.DispatchResult <- request(handle, snapshots,
              cursors, options, 4, 9, Bytes.new(0))
            first.duplicate(opened, snapshot_id, options)
        case None{}: fail("first snapshot returned an invalid ID")

def first.snapshot(
  result: Owner.DispatchResult,
  +options: ResourceOptions.Options
) -> IO(Unit):
  match result:
    case Owner.DispatchResult{handle, snapshots, cursors,
        Protocol.Response{_, _, _, Protocol.Success{}, payload}}:
      first.snapshot.id(handle, snapshots, cursors, options,
        Protocol.snapshot.id.read(payload))
    case Owner.DispatchResult{_, _, _, _}:
      fail("first snapshot open was rejected")

def first.flush(
  result: Owner.DispatchResult,
  +options: ResourceOptions.Options
) -> IO(Unit):
  match result:
    case Owner.DispatchResult{handle, snapshots, cursors,
        Protocol.Response{_, _, _, Protocol.Success{}, _}}:
      do IO<Unit>:
        opened : Owner.DispatchResult <- request(handle, snapshots, cursors,
          options, 3, 9, Bytes.new(0))
        first.snapshot(opened, options)
    case Owner.DispatchResult{_, _, _, _}:
      fail("first SST flush was rejected")

# Handles completed.
def completed(
  result: Owner.DispatchResult,
  +options: ResourceOptions.Options
) -> IO(Unit):
  match result:
    case Owner.DispatchResult{handle, snapshots, cursors,
        Protocol.Response{_, _, _, Protocol.Success{}, _}}:
      do IO<Unit>:
        flushed : Owner.DispatchResult <- request(handle, snapshots, cursors,
          options, 2, 4, Bytes.new(0))
        first.flush(flushed, options)
    case Owner.DispatchResult{_, _, _, _}:
      fail("initial SST put was rejected")

# Handles opened.
def opened(
  result: Result<&1, &1, ByteDb.Error, ByteDb.Handle>,
  +options: ResourceOptions.Options
) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        written : Owner.DispatchResult <- request(handle, SnapshotStore.empty(),
          CursorStore.empty(), options, 1, 2,
          Operation.encode.put(bytes.from_hex("61"), bytes.from_hex("31")))
        completed(written, options)
    case Fail{_}: fail("owner retired SST fixture could not create database")

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, ByteDb.Error, ByteDb.Handle> <- ByteDb.create(path)
    opened(result, custom.options())

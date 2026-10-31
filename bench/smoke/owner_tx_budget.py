import socket
import os
import select
import struct
import sys
import time
import fcntl
import termios
import array
import hashlib

endpoint, mode = sys.argv[1:]
database = endpoint.rsplit("/", 1)[0]
generation = int.from_bytes(open(database + "/OWNER.GEN", "rb").read(), "big")

def request(request_id, operation, payload=b""):
    return b"MLS6" + struct.pack(
        ">IIIII", 1, generation, request_id, operation, len(payload)
    ) + payload

def exchange(request_id, operation, payload=b""):
    connection = connect()
    connection.sendall(request(request_id, operation, payload))
    status, body = receive(connection, request_id)
    connection.close()
    return status, body

def connect():
    connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    connection.settimeout(120)
    connection.connect(endpoint)
    return connection

def receive_exact(connection, length):
    output = bytearray()
    while len(output) < length:
        chunk = connection.recv(length - len(output))
        if not chunk:
            raise AssertionError("owner closed before replying")
        output.extend(chunk)
    return bytes(output)

def receive(connection, request_id):
    header = bytearray()
    header.extend(receive_exact(connection, 24))
    if struct.unpack(">I", header[12:16])[0] != request_id:
        raise AssertionError("owner returned the wrong request id")
    payload_bytes = struct.unpack(">I", header[20:24])[0]
    body = receive_exact(connection, payload_bytes)
    return struct.unpack(">I", body[:4])[0], body[4:]

key = b"large"
value = b"v" * 256

if mode == "seed_boundaries":
    for size in (127, 128, 129):
        item_key = b"~boundary" + str(size).encode()
        item_value = b"v" * size
        status, _ = exchange(size, 2, struct.pack(">II", len(item_key), size) +
                             item_key + item_value)
        assert status == 0, "boundary value could not be stored"
elif mode == "boundaries":
    for size in (127, 128, 129):
        status, body = exchange(size, 1, b"~boundary" + str(size).encode())
        assert status == (5 if size == 129 else 0), "incorrect individual TX boundary"
        assert body == (b"" if size == 129 else b"v" * size)
elif mode == "slots":
    from pathlib import Path
    from owner_transport_oracle import read
    peers = [connect() for _ in range(64)]
    for peer in peers:
        peer.sendall(b"M")
    deadline = time.monotonic() + 10
    while len(read(Path(os.environ["MYLSM_TRANSPORT_LOG"])).connections) != 64:
        assert time.monotonic() < deadline, "owner did not admit all fixed slots"
        time.sleep(0.01)
    rejected = connect()
    rejected.settimeout(10)
    try:
        assert rejected.recv(1) == b"", "connection without control credit was admitted"
    except ConnectionResetError:
        pass
    rejected.close()
    for peer in peers:
        peer.close()
elif mode in ("free_below", "free_exact", "free_above"):
    from pathlib import Path
    from owner_transport_oracle import read
    blocker = connect()
    blocker.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4096)
    blocker.sendall(request(500, 1, b"b"))
    header = receive_exact(blocker, 24)
    length = struct.unpack(">I", header[20:24])[0]
    assert length == 32 * 1024 * 1024 + 4
    queued = array.array("i", [0])
    fcntl.ioctl(blocker, termios.FIONREAD, queued, True)
    assert queued[0] < length, "boundary fixture lacks TX backpressure"
    following = connect()
    following.sendall(request(501, 1, b"~boundary128"))
    if mode == "free_below":
        ready, _, _ = select.select([following], [], [], 0.05)
        assert not ready, "response exceeded remaining TX credit"
    else:
        status, body = receive(following, 501)
        assert status == 0 and body == b"v" * 128
        observation = read(Path(os.environ["MYLSM_TRANSPORT_LOG"]))
        assert observation.peak == 2 * (32 * 1024 * 1024) + 312
    body = receive_exact(blocker, length)
    assert body == bytes(4) + b"z" * (32 * 1024 * 1024)
    if mode == "free_below":
        status, body = receive(following, 501)
        assert status == 0 and body == b"v" * 128
    following.close()
    blocker.close()
elif mode == "seed":
    payload = struct.pack(">II", len(key), len(value)) + key + value
    status, _ = exchange(1, 2, payload)
    if status != 0:
        raise AssertionError("large value could not be persisted")
elif mode == "impossible":
    wal_path = os.path.join(database, "WAL")
    baseline = os.path.getsize(wal_path)
    status, _ = exchange(2, 1, key)
    if status != 5:
        raise AssertionError("response exceeding the TX ceiling was dispatched")
    if os.path.getsize(wal_path) != baseline:
        raise AssertionError("rejected response changed the durable log")
    status, body = exchange(3, 16)
    if status != 0 or len(body) != 76:
        raise AssertionError("bounded work did not progress after rejection")
elif mode == "reopen":
    status, actual = exchange(3, 1, key)
    if status != 0 or actual != value:
        raise AssertionError("impossible response lookup changed durable data")
elif mode == "operation_matrix":
    matrix_key = b"matrix"
    matrix_value = b"v"
    status, _ = exchange(60, 2, struct.pack(">II", len(matrix_key),
                                             len(matrix_value)) +
                         matrix_key + matrix_value)
    if status != 0:
        raise AssertionError("Put did not complete through reserved dispatch")
    status, actual = exchange(61, 1, matrix_key)
    if status != 0 or actual != matrix_value:
        raise AssertionError("Get did not complete through reserved dispatch")
    status, _ = exchange(62, 3, b"missing")
    if status != 0:
        raise AssertionError("Delete did not complete through reserved dispatch")

    batch_key = b"batch"
    batch_value = b"item"
    record = (b"\x00" + struct.pack(">I", len(batch_key)) + batch_key +
              struct.pack(">I", len(batch_value)) + batch_value)
    frame_length = 36 + len(record)
    prefix = struct.pack(">II", frame_length, 1) + record
    batch = prefix + hashlib.sha256(prefix).digest()
    status, _ = exchange(63, 8, batch)
    if status != 0:
        raise AssertionError("WriteBatch did not complete through reserved dispatch")
    status, _ = exchange(64, 4)
    if status != 0:
        raise AssertionError("Flush did not complete through reserved dispatch")
    status, _ = exchange(65, 5)
    if status != 0:
        raise AssertionError("Compact did not complete through reserved dispatch")
    status, stats = exchange(66, 6)
    if status != 0 or not stats:
        raise AssertionError("Stats did not complete through reserved dispatch")
    status, options = exchange(67, 16)
    if status != 0 or len(options) != 76:
        raise AssertionError("DescribeOwner did not complete through reserved dispatch")

    status, snapshot_body = exchange(68, 9)
    if status != 0 or len(snapshot_body) != 4:
        raise AssertionError("SnapshotOpen did not complete through reserved dispatch")
    snapshot_id = struct.unpack(">I", snapshot_body)[0]
    status, actual = exchange(69, 10, struct.pack(">I", snapshot_id) + batch_key)
    if status != 0 or actual != batch_value:
        raise AssertionError("SnapshotGet did not complete through reserved dispatch")

    def cursor_open(request_id):
        payload = struct.pack(">II", snapshot_id, 0) + struct.pack(">II", 0xffffffff,
                                                                      0xffffffff)
        result, body = exchange(request_id, 12, payload)
        if result != 0 or len(body) != 4:
            raise AssertionError("SnapshotCursorOpen did not complete through reserved dispatch")
        return struct.unpack(">I", body)[0]

    cursor_id = cursor_open(70)
    seek_payload = (struct.pack(">II", cursor_id, 0) +
                    struct.pack(">II", 0xffffffff, 0xffffffff))
    status, _ = exchange(71, 15, seek_payload)
    if status != 0:
        raise AssertionError("SnapshotCursorSeek did not complete through reserved dispatch")
    status, item = exchange(72, 13, struct.pack(">I", cursor_id))
    if status != 0 or not item or item[0] != 1:
        raise AssertionError("SnapshotCursorNext did not complete through reserved dispatch")
    cursor_key_length = struct.unpack(">I", item[1:5])[0]
    cursor_key_end = 5 + cursor_key_length
    cursor_value_length = struct.unpack(">I", item[cursor_key_end:cursor_key_end + 4])[0]
    if item[5:cursor_key_end] != batch_key or \
       item[cursor_key_end + 4:] != batch_value or \
       cursor_value_length != len(batch_value):
        raise AssertionError("SnapshotCursorNext returned the wrong entry")
    status, _ = exchange(73, 14, struct.pack(">I", cursor_id))
    if status != 0:
        raise AssertionError("SnapshotCursorClose did not complete through reserved dispatch")
    status, _ = exchange(74, 11, struct.pack(">I", snapshot_id))
    if status != 0:
        raise AssertionError("SnapshotClose did not complete through reserved dispatch")
elif mode == "post_matrix":
    followup_key = b"after-impossible"
    followup_value = b"ready"
    status, _ = exchange(80, 2,
                         struct.pack(">II", len(followup_key),
                                     len(followup_value)) +
                         followup_key + followup_value)
    if status != 0:
        raise AssertionError("bounded work did not progress after rejection")
    status, snapshot_body = exchange(81, 9)
    if status != 0 or len(snapshot_body) != 4:
        raise AssertionError("post-dispatch snapshot could not open")
    snapshot_id = struct.unpack(">I", snapshot_body)[0]
    status, actual = exchange(82, 10,
                              struct.pack(">I", snapshot_id) + b"batch")
    if status != 0 or actual != b"item":
        raise AssertionError("small SnapshotGet was rejected by unrelated retained bytes")
    status, _ = exchange(83, 11, struct.pack(">I", snapshot_id))
    if status != 0:
        raise AssertionError("post-dispatch snapshot could not close")
elif mode == "reopen_post_matrix":
    status, actual = exchange(84, 1, b"after-impossible")
    if status != 0 or actual != b"ready":
        raise AssertionError("bounded work did not persist after rejected response")
elif mode == "seed_large":
    large_value = b"z" * (32 * 1024 * 1024)
    payload = struct.pack(">II", 1, len(large_value)) + b"b" + large_value
    status, _ = exchange(4, 2, payload)
    if status != 0:
        raise AssertionError("large TX fixture value could not be stored")
elif mode == "seed_cursor_root":
    for request_id, item_key, item_value in (
        (90, b"a", b"x"), (91, b"b", b"y" * 200)
    ):
        payload = struct.pack(">II", len(item_key), len(item_value)) + \
                 item_key + item_value
        status, _ = exchange(request_id, 2, payload)
        if status != 0:
            raise AssertionError("cursor bound fixture value could not be stored")
    status, _ = exchange(92, 4)
    if status != 0:
        raise AssertionError("cursor bound fixture could not flush")
    sst_sizes = [os.path.getsize(os.path.join(database, name))
                 for name in os.listdir(database) if name.startswith("SST")]
    if not sst_sizes or max(sst_sizes) <= 128:
        raise AssertionError("cursor bound fixture root did not exceed its TX limit")
elif mode == "cursor_exact":
    status, snapshot_body = exchange(93, 9)
    if status != 0 or len(snapshot_body) != 4:
        raise AssertionError("cursor bound fixture could not open snapshot")
    snapshot_id = struct.unpack(">I", snapshot_body)[0]
    cursor_payload = (struct.pack(">II", snapshot_id, 0) +
                      struct.pack(">II", 0xffffffff, 0xffffffff))
    status, cursor_body = exchange(94, 12, cursor_payload)
    if status != 0 or len(cursor_body) != 4:
        raise AssertionError("cursor bound fixture could not open cursor")
    cursor_id = struct.unpack(">I", cursor_body)[0]
    status, item = exchange(95, 13, struct.pack(">I", cursor_id))
    if status != 0 or item != b"\x01\x00\x00\x00\x01a\x00\x00\x00\x01x":
        raise AssertionError("small next item was rejected by unrelated retained data")
    for request_id in (96, 97):
        status, _ = exchange(request_id, 13, struct.pack(">I", cursor_id))
        if status != 5:
            raise AssertionError("impossible next item was not rejected without advance")
    status, actual = exchange(98, 10, struct.pack(">I", snapshot_id) + b"b")
    if status != 5:
        raise AssertionError("cursor bound rejection altered persisted snapshot data")
    exchange(99, 14, struct.pack(">I", cursor_id))
    exchange(100, 11, struct.pack(">I", snapshot_id))
elif mode == "seed_cursor_race":
    records = ((110, b"a", b"a" * (2300 * 1024)),
               (111, b"b", b"b" * (3500 * 1024)),
               (112, b"z", b"z" * (3800 * 1024)))
    for request_id, item_key, item_value in records:
        payload = struct.pack(">II", len(item_key), len(item_value)) + \
                 item_key + item_value
        status, _ = exchange(request_id, 2, payload)
        if status != 0:
            raise AssertionError("cursor race fixture value could not be stored")
elif mode == "cursor_race":
    blocker = connect()
    blocker.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4096)
    blocker.sendall(request(114, 1, b"z"))
    ready, _, _ = select.select([blocker], [], [], 10)
    if not ready:
        raise AssertionError("cursor race TX blocker did not start")
    header = receive_exact(blocker, 24)
    blocker_length = struct.unpack(">I", header[20:24])[0]
    queued_bytes = array.array("i", [0])
    fcntl.ioctl(blocker, termios.FIONREAD, queued_bytes, True)
    if queued_bytes[0] >= blocker_length - 24:
        raise AssertionError("cursor race blocker did not retain TX backpressure")

    status, snapshot_body = exchange(115, 9)
    if status != 0 or len(snapshot_body) != 4:
        raise AssertionError("cursor race snapshot could not open")
    snapshot_id = struct.unpack(">I", snapshot_body)[0]
    cursor_payload = (struct.pack(">II", snapshot_id, 0) +
                      struct.pack(">II", 0xffffffff, 0xffffffff))
    status, cursor_body = exchange(116, 12, cursor_payload)
    if status != 0 or len(cursor_body) != 4:
        raise AssertionError("cursor race cursor could not open")
    cursor_id = struct.unpack(">I", cursor_body)[0]
    first = connect()
    first.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4096)
    second = connect()
    first.sendall(request(117, 13, struct.pack(">I", cursor_id)))
    second.sendall(request(118, 13, struct.pack(">I", cursor_id)))
    waiting, _, _ = select.select([first, second], [], [], 0.02)
    if waiting:
        raise AssertionError("cursor race advanced while TX was blocked")

    blocker_body = receive_exact(blocker, blocker_length)
    if struct.unpack(">I", blocker_body[:4])[0] != 0:
        raise AssertionError("cursor race TX blocker failed")
    first_header = receive_exact(first, 24)
    if struct.unpack(">I", first_header[12:16])[0] != 117:
        raise AssertionError("cursor race first response overtook FIFO")
    first_length = struct.unpack(">I", first_header[20:24])[0]
    waiting, _, _ = select.select([second], [], [], 0.02)
    if waiting:
        raise AssertionError("second cursor response ignored the retained TX reservation")
    first_body = receive_exact(first, first_length)
    first_item = first_body[4:]
    first_key_length = struct.unpack(">I", first_item[1:5])[0]
    first_key_end = 5 + first_key_length
    first_value_length = struct.unpack(">I",
                                       first_item[first_key_end:first_key_end + 4])[0]
    if first_item[5:first_key_end] != b"a" or \
       first_value_length != 2300 * 1024 or \
       first_item[first_key_end + 4:] != b"a" * (2300 * 1024):
        raise AssertionError("cursor race first visible item was incorrect")

    second_header = receive_exact(second, 24)
    if struct.unpack(">I", second_header[12:16])[0] != 118:
        raise AssertionError("second cursor response overtook FIFO")
    second_length = struct.unpack(">I", second_header[20:24])[0]
    second_body = receive_exact(second, second_length)
    second_item = second_body[4:]
    if len(second_item) < 9:
        raise AssertionError(
            "second cursor response had status "
            + str(struct.unpack(">I", second_body[:4])[0])
            + " and payload length " + str(len(second_item))
        )
    second_key_length = struct.unpack(">I", second_item[1:5])[0]
    second_key_end = 5 + second_key_length
    second_value_length = struct.unpack(">I",
                                        second_item[second_key_end:second_key_end + 4])[0]
    if struct.unpack(">I", second_body[:4])[0] != 0 or \
       second_item[5:second_key_end] != b"b" or \
       second_value_length != 3500 * 1024 or \
       second_item[second_key_end + 4:] != b"b" * (3500 * 1024):
        raise AssertionError("second cursor request did not remeasure after dispatch")
    blocker.close()
    first.close()
    second.close()
    exchange(119, 14, struct.pack(">I", cursor_id))
    exchange(120, 11, struct.pack(">I", snapshot_id))
elif mode == "cursor_impossible":
    status, snapshot_body = exchange(5, 9)
    if status != 0 or len(snapshot_body) != 4:
        raise AssertionError("cursor rejection fixture could not open snapshot")
    snapshot_id = struct.unpack(">I", snapshot_body)[0]
    status, _ = exchange(9, 10, struct.pack(">I", snapshot_id) + b"b")
    if status != 5:
        raise AssertionError("snapshot response above the TX limit was not rejected")
    cursor_payload = (struct.pack(">II", snapshot_id, 0) +
                      struct.pack(">II", 0xffffffff, 0xffffffff))
    status, cursor_body = exchange(6, 12, cursor_payload)
    if status != 0 or len(cursor_body) != 4:
        raise AssertionError("cursor rejection fixture could not open cursor")
    cursor_id = struct.unpack(">I", cursor_body)[0]
    status, _ = exchange(7, 13, struct.pack(">I", cursor_id))
    if status != 5:
        raise AssertionError("cursor response above the TX limit was not rejected")
    status, _ = exchange(8, 13, struct.pack(">I", cursor_id))
    if status != 5:
        raise AssertionError("cursor advanced after its response could not fit")
elif mode == "fifo":
    blocked = connect()
    blocked.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4096)
    blocked.sendall(request(10, 1, b"b"))
    ready, _, _ = select.select([blocked], [], [], 10)
    if not ready:
        raise AssertionError("large response did not start writing")
    header = receive_exact(blocked, 24)
    response_length = struct.unpack(">I", header[20:24])[0]
    if response_length < 32 * 1024 * 1024:
        raise AssertionError("TX fixture did not produce a backpressured frame")
    queued_bytes = array.array("i", [0])
    fcntl.ioctl(blocked, termios.FIONREAD, queued_bytes, True)
    if queued_bytes[0] >= response_length - 24:
        raise AssertionError("peer socket buffered the whole frame; TX pressure was not established")

    status, snapshot_body = exchange(11, 9)
    if status != 0 or len(snapshot_body) != 4:
        raise AssertionError("FIFO fixture could not open its snapshot")
    snapshot_id = struct.unpack(">I", snapshot_body)[0]
    cursor_payload = (struct.pack(">II", snapshot_id, 0) +
                      struct.pack(">II", 0xffffffff, 0xffffffff))
    status, cursor_body = exchange(12, 12, cursor_payload)
    if status != 0 or len(cursor_body) != 4:
        raise AssertionError("FIFO fixture could not open its cursor")
    cursor_id = struct.unpack(">I", cursor_body)[0]
    first = connect()
    first.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4096)
    second = connect()
    first.sendall(request(13, 13, struct.pack(">I", cursor_id)))
    second.sendall(request(14, 14, struct.pack(">I", cursor_id)))
    waiting, _, _ = select.select([first, second], [], [], 0.02)
    if waiting:
        ready_id = 13 if waiting[0] is first else 14
        ready_status, _ = receive(waiting[0], ready_id)
        raise AssertionError(
            f"request {ready_id} replied with status {ready_status} before TX drain"
        )

    body = receive_exact(blocked, response_length)
    if struct.unpack(">I", body[:4])[0] != 0:
        raise AssertionError("large response failed after TX drain")
    first_header = receive_exact(first, 24)
    if struct.unpack(">I", first_header[12:16])[0] != 13:
        raise AssertionError("FIFO head response had the wrong request id")
    first_length = struct.unpack(">I", first_header[20:24])[0]
    if first_length < 32 * 1024 * 1024:
        raise AssertionError("FIFO head did not retain its large response bound")
    first_body = receive_exact(first, first_length)
    if struct.unpack(">I", first_body[:4])[0] != 0 or \
       not first_body[4:] or first_body[4] != 1:
        raise AssertionError("FIFO head cursor did not return its entry")
    item = first_body[4:]
    cursor_key_length = struct.unpack(">I", item[1:5])[0]
    cursor_key_end = 5 + cursor_key_length
    cursor_value_length = struct.unpack(">I", item[cursor_key_end:cursor_key_end + 4])[0]
    if item[5:cursor_key_end] != b"b" or \
       cursor_value_length != 32 * 1024 * 1024 or \
       item[cursor_key_end + 4:] != b"z" * (32 * 1024 * 1024):
        raise AssertionError("FIFO head cursor returned different snapshot data")
    second_status, _ = receive(second, 14)
    first.close()
    second.close()
    blocked.close()
    if second_status != 0:
        raise AssertionError(
            f"the queued cursor close returned status {second_status}"
        )
    status, _ = exchange(15, 11, struct.pack(">I", snapshot_id))
    if status != 0:
        raise AssertionError("FIFO fixture could not close its snapshot")
elif mode == "reopen_fifo":
    status, value = exchange(20, 1, b"b")
    if status != 0 or value != b"z" * (32 * 1024 * 1024):
        raise AssertionError("the queued FIFO reads lost the persisted value")
elif mode == "timeout":
    wal_path = os.path.join(database, "WAL")
    baseline = os.path.getsize(wal_path)
    blocked = connect()
    blocked.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4096)
    blocked.sendall(request(30, 1, b"b"))
    ready, _, _ = select.select([blocked], [], [], 10)
    if not ready:
        raise AssertionError("timeout fixture response did not start writing")
    header = receive_exact(blocked, 24)
    response_length = struct.unpack(">I", header[20:24])[0]
    if response_length < 32 * 1024 * 1024:
        raise AssertionError("timeout fixture did not retain its TX frame")
    queued_bytes = array.array("i", [0])
    fcntl.ioctl(blocked, termios.FIONREAD, queued_bytes, True)
    if queued_bytes[0] >= response_length - 24:
        raise AssertionError("timeout fixture did not establish TX pressure")

    status, snapshot_body = exchange(31, 9)
    if status != 0 or len(snapshot_body) != 4:
        raise AssertionError("timeout fixture could not open its snapshot")
    snapshot_id = struct.unpack(">I", snapshot_body)[0]
    cursor_payload = (struct.pack(">II", snapshot_id, 0) +
                      struct.pack(">II", 0xffffffff, 0xffffffff))
    status, cursor_body = exchange(32, 12, cursor_payload)
    if status != 0 or len(cursor_body) != 4:
        raise AssertionError("timeout fixture could not open its cursor")
    cursor_id = struct.unpack(">I", cursor_body)[0]
    waiting = connect()
    waiting.sendall(request(33, 13, struct.pack(">I", cursor_id)))
    timeout_status, _ = receive(waiting, 33)
    if timeout_status != 4:
        raise AssertionError("expired head was not answered as Timeout")
    waiting.close()
    if os.path.getsize(wal_path) != baseline:
        raise AssertionError("expired cursor advance changed the durable log")

    body = receive_exact(blocked, response_length)
    if struct.unpack(">I", body[:4])[0] != 0:
        raise AssertionError("blocking TX response failed after drain")
    blocked.close()
    status, item = exchange(34, 13, struct.pack(">I", cursor_id))
    if status != 0 or not item or item[0] != 1:
        raise AssertionError("expired cursor advance was executed")
    cursor_key_length = struct.unpack(">I", item[1:5])[0]
    cursor_key_end = 5 + cursor_key_length
    cursor_value_length = struct.unpack(">I", item[cursor_key_end:cursor_key_end + 4])[0]
    if item[5:cursor_key_end] != b"b" or \
       cursor_value_length != 32 * 1024 * 1024 or \
       item[cursor_key_end + 4:] != b"z" * (32 * 1024 * 1024):
        raise AssertionError("cursor did not remain on its first durable entry")
    exchange(35, 14, struct.pack(">I", cursor_id))
    exchange(36, 11, struct.pack(">I", snapshot_id))
elif mode == "commit_once":
    wal_path = os.path.join(database, "WAL")
    baseline = os.path.getsize(wal_path)
    key = b"once"
    value = b"done"
    payload = struct.pack(">II", len(key), len(value)) + key + value
    peer = connect()
    peer.sendall(request(40, 2, payload))
    expected = baseline + 49 + len(key) + len(value)
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        current = os.path.getsize(wal_path)
        if current >= expected:
            break
        time.sleep(0.01)
    current = os.path.getsize(wal_path)
    if current != expected:
        peer.close()
        raise AssertionError(
            f"durable dispatch WAL size was {current}, expected {expected}"
        )
    peer.close()
    status, actual = exchange(41, 1, key)
    if status != 0 or actual != value:
        raise AssertionError("TX did not recover after peer loss")
elif mode == "reopen_final":
    timeout_status, _ = exchange(50, 1, b"timeout")
    if timeout_status != 2:
        raise AssertionError("expired FIFO head mutated the database")
    once_status, once_value = exchange(51, 1, b"once")
    if once_status != 0 or once_value != b"done":
        raise AssertionError("peer-loss mutation was not durable after reopen")
else:
    raise AssertionError("unknown TX budget fixture mode")

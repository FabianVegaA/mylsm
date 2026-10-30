import os
import signal
import socket
import struct
import sys

endpoint, mode, *arguments = sys.argv[1:]
database = endpoint.rsplit("/", 1)[0]
generation = int.from_bytes(open(database + "/OWNER.GEN", "rb").read(), "big")

def request(owner_generation, request_id, operation, payload=b""):
    return b"MLS6" + struct.pack(
        ">IIIII", 1, owner_generation, request_id, operation, len(payload)
    ) + payload

def read_response(connection, request_id):
    header = bytearray()
    while len(header) < 24:
        chunk = connection.recv(24 - len(header))
        if not chunk:
            raise AssertionError("owner closed before replying")
        header.extend(chunk)
    if header[:4] != b"MLS6":
        raise AssertionError("owner returned an invalid frame")
    if struct.unpack(">I", header[12:16])[0] != request_id:
        raise AssertionError("owner returned the wrong request id")
    payload_length = struct.unpack(">I", header[20:24])[0]
    body = bytearray()
    while len(body) < payload_length:
        chunk = connection.recv(payload_length - len(body))
        if not chunk:
            raise AssertionError("owner truncated its response")
        body.extend(chunk)
    if len(body) < 4:
        raise AssertionError("owner response omitted its status")
    return struct.unpack(">I", body[:4])[0], bytes(body[4:])

def exchange(owner_generation, request_id, operation, payload=b""):
    connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    connection.settimeout(3)
    connection.connect(endpoint)
    connection.sendall(request(owner_generation, request_id, operation, payload))
    result = read_response(connection, request_id)
    connection.close()
    return result

def put_payload(value):
    return struct.pack(">II", 1, len(value)) + b"r" + value

def put_entry(key, value):
    return struct.pack(">II", len(key), len(value)) + key + value

first_value = b"first" + b"-" * 26
replacement_value = b"second" + b"-" * 25

if mode == "reject":
    payload = put_payload(b"v" * 31)
    if len(request(generation, 1, 2, payload)) != 64:
        raise AssertionError("fixture put frame is not exactly 64 bytes")
    status, _ = exchange(generation, 1, 2, payload)
    if status != 5:
        raise AssertionError("oversized queue request was not ResourceLimit")
    status, _ = exchange(generation, 2, 1, b"r")
    if status != 2:
        raise AssertionError("rejected put changed the database")
elif mode == "reopen":
    status, _ = exchange(generation, 3, 1, b"r")
    if status != 2:
        raise AssertionError("rejected put appeared after owner restart")
    status, value = exchange(generation, 4, 1, b"k")
    if status != 0 or value != replacement_value:
        raise AssertionError("replacement after cancellation was not durable")
    status, _ = exchange(generation, 5, 1, b"b")
    if status != 2:
        raise AssertionError("disconnected client's request was durable")
    status, _ = exchange(generation, 6, 1, b"c")
    if status != 2:
        raise AssertionError("busy request changed the database")
elif mode == "cancel":
    if len(arguments) != 1:
        raise AssertionError("cancel mode requires the owner process ID")
    owner_pid = int(arguments[0])
    os.kill(owner_pid, signal.SIGSTOP)
    try:
        survivor = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        survivor.settimeout(3)
        survivor.connect(endpoint)
        survivor.sendall(request(generation, 1, 2,
                                 put_entry(b"k", first_value)))

        disconnected = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        disconnected.settimeout(3)
        disconnected.connect(endpoint)
        disconnected.sendall(request(generation, 2, 2,
                                     put_entry(b"b", first_value)))
        disconnected.shutdown(socket.SHUT_WR)

        busy = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        busy.settimeout(3)
        busy.connect(endpoint)
        busy.sendall(request(generation, 3, 2,
                             put_entry(b"c", first_value)))
        if any(len(request(generation, request_id, 2, payload)) != 64
               for request_id, payload in ((1, put_entry(b"k", first_value)),
                                           (2, put_entry(b"b", first_value)),
                                           (3, put_entry(b"c", first_value)))):
            raise AssertionError("queue fixture requests are not 64-byte frames")
    finally:
        os.kill(owner_pid, signal.SIGCONT)

    status, _ = read_response(survivor, 1)
    survivor.close()
    busy_status, _ = read_response(busy, 3)
    busy.close()
    disconnected.close()
    if status != 0:
        raise AssertionError("connected client's request did not succeed")
    if busy_status != 3:
        raise AssertionError("third request was not rejected as Busy")

    status, _ = exchange(generation, 4, 2,
                         put_entry(b"k", replacement_value))
    if status != 0:
        raise AssertionError("request was not admitted after cancellation")
    status, value = exchange(generation, 5, 1, b"k")
    if status != 0 or value != replacement_value:
        raise AssertionError("FIFO replacement order was not observable")
    status, _ = exchange(generation, 6, 1, b"b")
    if status != 2:
        raise AssertionError("disconnected queued request was dispatched")
    status, _ = exchange(generation, 7, 1, b"c")
    if status != 2:
        raise AssertionError("busy request changed the database")
else:
    raise AssertionError("unknown fixture mode")

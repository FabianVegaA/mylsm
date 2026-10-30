import socket
import struct
import sys

endpoint = sys.argv[1]
database = endpoint.rsplit("/", 1)[0]
generation = int.from_bytes(open(database + "/OWNER.GEN", "rb").read(), "big")


def request(request_id, operation, payload_length):
    return b"MLS6" + struct.pack(
        ">IIIII", 1, generation, request_id, operation, payload_length
    )


def connect():
    connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    connection.settimeout(10)
    connection.connect(endpoint)
    return connection


def receive_exact(connection, length):
    result = bytearray()
    while len(result) < length:
        part = connection.recv(length - len(result))
        if not part:
            raise AssertionError("owner closed before response completed")
        result.extend(part)
    return bytes(result)


def receive(connection, request_id):
    header = receive_exact(connection, 24)
    if struct.unpack(">I", header[12:16])[0] != request_id:
        raise AssertionError("owner returned the wrong request id")
    length = struct.unpack(">I", header[20:24])[0]
    body = receive_exact(connection, length)
    return struct.unpack(">I", body[:4])[0], body[4:]


first = connect()
value = b"r" * 1340
put = struct.pack(">II", 1, len(value)) + b"k" + value
first.sendall(request(1, 2, len(put)))

second = connect()
second.sendall(request(2, 2, 10))
status, body = receive(second, 2)
if status != 3 or body:
    raise AssertionError(
        "frame without temporary RX credit was not rejected Busy: " + str(status)
    )
if second.recv(1) != b"":
    raise AssertionError("RX pressure response did not close the peer")
second.close()

for offset in range(0, len(put), 257):
    first.sendall(put[offset : offset + 257])
status, body = receive(first, 1)
if status != 0 or body:
    raise AssertionError("reserved fragmented frame did not complete")
first.close()

third = connect()
third.sendall(request(3, 1, 1) + b"k")
status, body = receive(third, 3)
if status != 0 or body != value:
    raise AssertionError("RX credit was not released after frame dispatch")
third.close()

slow = connect()
slow_value = b"s" * 991
slow_put = struct.pack(">II", 1, len(slow_value)) + b"s" + slow_value
slow.sendall(request(7, 2, len(slow_put)))

fast = connect()
fast.sendall(request(8, 1, 1) + b"k")
status, body = receive(fast, 8)
if status != 0 or body != value:
    raise AssertionError("a ready frame did not progress while another peer was slow")
fast.close()

for offset in range(0, len(slow_put), 113):
    slow.sendall(slow_put[offset : offset + 113])
status, body = receive(slow, 7)
if status != 0 or body:
    raise AssertionError("slow peer did not complete after independent progress")
slow.close()

half_closed = connect()
half_closed.sendall(request(6, 2, 10))
half_closed.shutdown(socket.SHUT_WR)
if half_closed.recv(1) != b"":
    raise AssertionError("half-closed partial payload received a response")
half_closed.close()

impossible = connect()
impossible.sendall(request(4, 2, 3000))
status, body = receive(impossible, 4)
if status != 5 or body:
    raise AssertionError("frame larger than total RX budget was not rejected")
if impossible.recv(1) != b"":
    raise AssertionError("impossible frame response did not close the peer")
impossible.close()

reopened = connect()
reopened.sendall(request(5, 1, 1) + b"k")
status, body = receive(reopened, 5)
if status != 0 or body != value:
    raise AssertionError("RX rejection changed previously persisted data")
reopened.close()

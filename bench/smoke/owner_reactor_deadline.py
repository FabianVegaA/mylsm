import socket
import struct
import sys
import time

endpoint = sys.argv[1]


def request(request_id, operation, payload=b""):
    return b"MLS6" + struct.pack(
        ">IIIII", 1, 1, request_id, operation, len(payload)
    ) + payload


def read_exact(connection, length):
    result = bytearray()
    while len(result) < length:
        chunk = connection.recv(length - len(result))
        if not chunk:
            raise AssertionError("owner closed before completing a response")
        result.extend(chunk)
    return bytes(result)


def read_response(connection, request_id):
    header = read_exact(connection, 24)
    if header[:4] != b"MLS6" or struct.unpack(">I", header[12:16])[0] != request_id:
        raise AssertionError("response did not preserve the request id")
    payload_length = struct.unpack(">I", header[20:24])[0]
    return read_exact(connection, payload_length)

slow = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
slow.settimeout(2)
slow.connect(endpoint)
slow.sendall(request(1, 1, b"key")[:12])

fast = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
fast.settimeout(2)
fast.connect(endpoint)
fast.sendall(request(2, 6))
read_response(fast, 2)

start = time.monotonic()
if slow.recv(1) != b"":
    raise AssertionError("expired partial frame received data")
if time.monotonic() - start > 1.5:
    raise AssertionError("partial frame was not closed near its deadline")

partial_eof = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
partial_eof.settimeout(2)
partial_eof.connect(endpoint)
partial_eof.sendall(request(4, 1, b"key")[:12])
partial_eof.shutdown(socket.SHUT_WR)
start = time.monotonic()
if partial_eof.recv(1) != b"":
    raise AssertionError("partial EOF received an unexpected response")
if time.monotonic() - start > 1.5:
    raise AssertionError("partial EOF was not closed promptly")
partial_eof.close()

fragmented = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
fragmented.settimeout(2)
fragmented.connect(endpoint)
frame = request(3, 1, b"key")
for byte in frame:
    fragmented.sendall(bytes((byte,)))
    time.sleep(0.001)
read_response(fragmented, 3)
fragmented.close()
fast.close()
slow.close()

import socket
import struct
import sys

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
            raise AssertionError("owner closed before completing the response")
        result.extend(chunk)
    return bytes(result)

slow = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
slow.settimeout(2)
slow.connect(endpoint)
slow.sendall(request(1, 1, b"big"))

fast = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
fast.settimeout(3)
fast.connect(endpoint)
fast.sendall(request(2, 6))
header = read_exact(fast, 24)
if header[:4] != b"MLS6" or struct.unpack(">I", header[12:16])[0] != 2:
    raise AssertionError("fast response lost its request identifier")
payload_length = struct.unpack(">I", header[20:24])[0]
if payload_length < 4:
    raise AssertionError("fast stats response omitted its payload")
read_exact(fast, payload_length)
fast.close()
slow.close()

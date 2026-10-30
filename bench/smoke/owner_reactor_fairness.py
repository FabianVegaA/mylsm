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
            raise AssertionError("owner closed the connection before replying")
        result.extend(chunk)
    return bytes(result)

slow = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
slow.settimeout(2)
slow.connect(endpoint)
slow.sendall(request(1, 1, b"key")[:12])

fast = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
fast.settimeout(2)
fast.connect(endpoint)
fast.sendall(request(2, 6))
response = read_exact(fast, 24)
if response[:4] != b"MLS6" or struct.unpack(">I", response[12:16])[0] != 2:
    raise AssertionError("response did not preserve the fast request id")
payload_length = struct.unpack(">I", response[20:24])[0]
if payload_length < 4:
    raise AssertionError("stats response omitted its status word")
read_exact(fast, payload_length)
fast.close()
slow.settimeout(0.2)
try:
    retained = slow.recv(1)
except TimeoutError:
    retained = None
if retained is not None:
    raise AssertionError("owner replied or closed before frame completion")
slow.close()

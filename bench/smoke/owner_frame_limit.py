import socket
import struct
import sys

endpoint = sys.argv[1]
header = b"MLS6" + struct.pack(">IIIII", 1, 1, 1, 1, 16777217)

for _ in range(2):
    connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    connection.settimeout(5)
    connection.connect(endpoint)
    connection.sendall(header)
    if connection.recv(1) != b"":
        raise SystemExit("oversized remote frame was not rejected")
    connection.close()

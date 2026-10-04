import Base
import ./hub_sha/sha256.bend as SHA
import 0x185ae03c75e3e75be1171471f68b43cb/bytes.bend as Bytes

# Single checksum for SSTable v2 framing. SHA-256 is vendored under
# ./hub_sha (see its headers); our laws only cover framing (digest placed
# after '#', verified on parse), and vectors below pin the primitive.
def digest(+body: String) -> String:
  SHA.hex(SHA.sha256(SHA.ascii(body)))

# Check a text-format digest against its encoded claim.
def verify(+body: String, +claimed: String) -> Bool:
  String.eq(digest(body), claimed)

# Hash a packed storage buffer without converting its bytes to a List or String.
def digest_bytes(bytes: Bytes.Bytes) -> Bytes.Bytes:
  SHA.sha256_packed_bytes(bytes)

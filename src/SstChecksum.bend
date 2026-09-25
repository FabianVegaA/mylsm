import Base
import ./hub_sha/sha256.bend as SHA

# Single checksum for SSTable v2 framing. SHA-256 is vendored under
# ./hub_sha (see its headers); our laws only cover framing (digest placed
# after '#', verified on parse), and vectors below pin the primitive.
def digest(+body: String) -> String:
  SHA.hex(SHA.sha256(SHA.ascii(body)))

def verify(+body: String, +claimed: String) -> Bool:
  String.eq(digest(body), claimed)

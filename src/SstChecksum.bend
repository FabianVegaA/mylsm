import Base
import 0x9ee2e9a299991dcc089fe22c7f3ceb5f/src/crypto/sha/sha256.bend as SHA

# Single checksum for SSTable v2 framing. The hub SHA-256 is trusted as-is
# (its own PROOF.bend proves it against the executable FIPS 180-4 spec);
# our laws only cover framing (digest placed after '#', verified on parse).
def digest(+body: String) -> String:
  SHA.hex(SHA.sha256(SHA.ascii(body)))

def verify(+body: String, +claimed: String) -> Bool:
  String.eq(digest(body), claimed)

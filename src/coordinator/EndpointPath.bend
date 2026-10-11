import Base
import ../StorageBytes.bend as StorageBytes

# Keeps a local socket endpoint within macOS and Linux sockaddr path limits.
type Decision is Data:
  Endpoint{path: String}
  PathTooLong{}

# Returns whether one complete endpoint path fits the conservative byte limit.
def admit_length(endpoint_bytes: Nat) -> Bool:
  Nat.is_le(endpoint_bytes, 100n)

# Appends the fixed owner endpoint name only when the path remains bounded.
def endpoint.result(path: String, admitted: Bool) -> Decision:
  match path:
    case canonical:
      match admitted:
        case True{}: Endpoint{canonical ++ "/MYLSM.sock"}
        case False{}: PathTooLong{}

# Builds one endpoint from a path already resolved by the filesystem layer.
def for_canonical_path(+canonical_path: String) -> Decision:
  endpoint.result(canonical_path,
    admit_length(Nat.add(StorageBytes.string_size(canonical_path), 11n)))

import Base
import ../src/coordinator/EndpointPath.bend as EndpointPath

# Admits an endpoint exactly at the cross-platform path byte limit.
law endpoint_path_limit_is_inclusive:
  {EndpointPath.admit_length(100n) == True{} : Bool}

# Rejects an endpoint that exceeds the cross-platform path byte limit.
law endpoint_path_over_limit_is_rejected:
  {EndpointPath.admit_length(101n) == False{} : Bool}

# Uses the canonical database path as the stable endpoint identity.
law canonical_database_path_determines_endpoint:
  {EndpointPath.for_canonical_path("/tmp/db") ==
    EndpointPath.Endpoint{"/tmp/db/MYLSM.sock"} : EndpointPath.Decision}

# Does not publish an endpoint path when the canonical root is too long.
law long_canonical_database_path_has_no_endpoint:
  {EndpointPath.for_canonical_path("/" ++ String.repeat("a", 90n)) ==
    EndpointPath.PathTooLong{} :
    EndpointPath.Decision}

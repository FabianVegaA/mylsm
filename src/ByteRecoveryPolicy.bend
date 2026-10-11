import Base

# Returns the raw error code for a reader resident-index budget overflow.
def resource_limit_error_code() -> U32:
  4294967289

# Separates a configured recovery bound from malformed persisted data.
def is_resource_limit(code: U32) -> Bool:
  U32.is_eq(code, resource_limit_error_code())

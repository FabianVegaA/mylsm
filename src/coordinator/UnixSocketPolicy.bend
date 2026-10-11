import Base

# Distinguishes supported socket errors from missing host capabilities.
type Classification is Data:
  UnsupportedPlatform{}
  Host{code: U32}

# Classifies platform-specific errno values without performing host IO.
def classify_code(code: U32) -> Classification:
  match code:
    case 45: UnsupportedPlatform{}
    case 78: UnsupportedPlatform{}
    case 95: UnsupportedPlatform{}
    case 38: UnsupportedPlatform{}
    case _: Host{code}

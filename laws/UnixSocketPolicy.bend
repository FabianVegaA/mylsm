import Base
import ../src/coordinator/UnixSocketPolicy.bend as Policy

# Classifies Darwin's unsupported-socket error code explicitly.
law darwin_unsupported_code:
  {Policy.classify_code(45) == Policy.UnsupportedPlatform{} : Policy.Classification}

# Classifies Darwin's alternate unsupported-socket error code explicitly.
law darwin_alt_unsupported_code:
  {Policy.classify_code(78) == Policy.UnsupportedPlatform{} : Policy.Classification}

# Classifies Linux's unsupported-socket error code explicitly.
law linux_unsupported_code:
  {Policy.classify_code(95) == Policy.UnsupportedPlatform{} : Policy.Classification}

# Classifies the shared POSIX unavailable-operation code explicitly.
law posix_unavailable_code:
  {Policy.classify_code(38) == Policy.UnsupportedPlatform{} : Policy.Classification}

# Leaves ordinary socket errors outside the unsupported category.
law preserves_ordinary_code:
  {Policy.classify_code(13) == Policy.Host{13} : Policy.Classification}

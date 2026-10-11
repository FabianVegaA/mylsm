import Base
import ../src/coordinator/OwnerGeneration.bend as Generation

# The first owner process uses generation one.
law first_owner_generation_is_one:
  {Generation.next(None{}) == Generation.GenerationReady{1} : Generation.Decision}

# Restarting an owner advances its persisted generation exactly once.
law owner_restart_advances_generation:
  {Generation.next(Some{7}) == Generation.GenerationReady{8} : Generation.Decision}

# An exhausted owner generation is rejected without wrapping to zero.
law owner_generation_exhaustion_is_reported:
  {Generation.next(Some{4294967295}) == Generation.GenerationExhausted{} : Generation.Decision}

# The fixed-width sidecar codec preserves the initial generation.
law owner_generation_codec_roundtrips_one:
  {Generation.u32.read(Generation.u32.bytes(1)) == 1 : U32}

# The fixed-width sidecar codec preserves the terminal generation.
law owner_generation_codec_roundtrips_maximum:
  {Generation.u32.read(Generation.u32.bytes(4294967295)) == 4294967295 : U32}

# An owner response carries its active generation even for an older request.
law stale_request_response_uses_active_generation:
  {Generation.response.generation(2) == 2 : U32}

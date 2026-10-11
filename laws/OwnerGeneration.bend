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

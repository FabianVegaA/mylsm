import Base
import ../src/coordinator/GenerationRetentionPolicy.bend as Policy

# The manifest's published generation remains protected from deletion.
law published_generation_is_never_reclaimed:
  {Policy.can_reclaim(7, Some{7}, [3, 7]) == False{} : Bool}

# A generation held by any snapshot remains protected from deletion.
law snapshot_generation_is_retained:
  {Policy.can_reclaim(3, Some{7}, [3]) == False{} : Bool}

# An obsolete generation with no snapshot reference can be reclaimed.
law unreferenced_obsolete_generation_is_reclaimable:
  {Policy.can_reclaim(3, Some{7}, []) == True{} : Bool}

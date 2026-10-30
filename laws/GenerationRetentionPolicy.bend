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

# Verifies repeated generation does not increase unique count.
law repeated_generation_does_not_increase_unique_count:
  for tail: List<&2, U32>
  {Policy.unique_generation_count(Con{1, Con{1, tail}}) ==
    Policy.unique_generation_count(Con{1, tail}) : Nat}

# Verifies empty generation list has zero unique files.
law empty_generation_list_has_zero_unique_files:
  {Policy.unique_generation_count(Nil{}) == 0n : Nat}

# Verifies concrete unique generations are counted once.
law concrete_unique_generations_are_counted_once:
  {Policy.unique_generation_count([1, 2, 1, 3, 2]) == 3n : Nat}

# Verifies legacy sst counts as one physical file.
law legacy_sst_counts_as_one_physical_file:
  for generations: List<&2, U32>
  {Policy.unique_file_count(generations, True{}) ==
    Nat.add(Policy.unique_generation_count(generations), 1n) : Nat}

# Verifies empty snapshot set fits zero retired file budget.
law empty_snapshot_set_fits_zero_retired_file_budget:
  {Policy.unique_file_count(Nil{}, False{}) == 0n : Nat}

# Verifies duplicate snapshot roots fit one retired file budget.
law duplicate_snapshot_roots_fit_one_retired_file_budget:
  {Nat.is_le(Policy.unique_file_count([1, 1, 1], False{}), 1n) ==
    True{} : Bool}

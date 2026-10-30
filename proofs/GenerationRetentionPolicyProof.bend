import Base
import ../laws/GenerationRetentionPolicy.bend as Laws

def Laws.published_generation_is_never_reclaimed():
  {==}

def Laws.snapshot_generation_is_retained():
  {==}

def Laws.unreferenced_obsolete_generation_is_reclaimable():
  {==}

def Laws.repeated_generation_does_not_increase_unique_count(_tail):
  {==}

def Laws.empty_generation_list_has_zero_unique_files():
  {==}

def Laws.concrete_unique_generations_are_counted_once():
  {==}

def Laws.legacy_sst_counts_as_one_physical_file(_generations):
  {==}

def Laws.empty_snapshot_set_fits_zero_retired_file_budget():
  {==}

def Laws.duplicate_snapshot_roots_fit_one_retired_file_budget():
  {==}

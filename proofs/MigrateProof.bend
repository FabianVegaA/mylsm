import Base
import ../laws/Migrate.bend as Laws

def Laws.migration_canonical_output_is_strictly_byte_ordered():
  {==}

def Laws.migration_canonical_output_drops_shadowed_tombstones():
  {==}

def Laws.migration_canonical_output_retains_newest_live_values():
  {==}

def Laws.migration_converts_legacy_unicode_to_exact_utf8_bytes():
  {==}

def Laws.migration_applies_legacy_mutations_chronologically():
  {==}

def Laws.migration_wal_tombstone_shadows_legacy_sst():
  {==}

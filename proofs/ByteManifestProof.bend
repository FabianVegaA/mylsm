import Base
import ../laws/ByteManifest.bend as Laws

def Laws.empty_manifest_round_trips():
  {==}

def Laws.sst_manifest_round_trips():
  {==}

def Laws.generation_manifest_round_trips():
  {==}

def Laws.generation_sst_manifest_round_trips():
  {==}

def Laws.generation_sst_path_encodes_the_identifier():
  {==}

def Laws.next_generation_identifier_advances():
  {==}

def Laws.generation_identifier_exhaustion_is_reported():
  {==}

def Laws.legacy_manifest_starts_generation_at_one():
  {==}

def Laws.generation_manifest_checksum_corruption_is_rejected():
  {==}

def Laws.unsupported_manifest_size_is_rejected():
  {==}

def Laws.unknown_generation_is_rejected():
  {==}

def Laws.comparator_mismatch_is_rejected():
  {==}

def Laws.manifest_checksum_corruption_is_rejected():
  {==}

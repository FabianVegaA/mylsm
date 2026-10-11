import Base
import ../laws/Migration.bend as Laws
import ../src/transfer/FormatInspect.bend as FormatInspect
import ../src/transfer/Migrate.bend as Migrate

def Laws.validated_legacy_source_is_admitted():
  {==}

def Laws.manifest_alone_never_admits_migration():
  {==}

def Laws.non_legacy_storage_is_rejected():
  {==}

def Laws.corrupt_manifest_is_rejected():
  {==}

def Laws.existing_destination_is_rejected():
  {==}

def Laws.oversized_source_is_rejected():
  {==}

def Laws.entry_limit_is_enforced():
  {==}

def Laws.corrupt_legacy_files_are_rejected():
  {==}

def Laws.manifest_resource_limit_is_preserved():
  {==}

def Laws.existing_destination_rejects_any_verified_source(
  entry_count,
  encoded_bytes,
  max_entries,
  max_encoded_bytes
):
  match entry_count encoded_bytes max_entries max_encoded_bytes:
    case _ _ _ _: {==}

def Laws.staging_requires_a_validated_source():
  {==}

def Laws.rejected_preflight_cannot_begin_publication():
  {==}

def Laws.copying_requires_a_staged_destination():
  {==}

def Laws.verification_requires_completed_copy():
  {==}

def Laws.destination_count_mismatch_rejects_verification():
  {==}

def Laws.destination_digest_mismatch_rejects_verification():
  {==}

def Laws.destination_order_mismatch_rejects_verification():
  {==}

def Laws.publication_requires_verified_destination():
  {==}

def Laws.abort_preserves_published_destination():
  {==}

def Laws.abort_unpublished_migration():
  {==}

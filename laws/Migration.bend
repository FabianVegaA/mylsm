import Base
import ../src/transfer/FormatInspect.bend as FormatInspect
import ../src/transfer/Migrate.bend as Migrate

def legacy.inspection(integrity: FormatInspect.Integrity) -> FormatInspect.Inspection:
  FormatInspect.Inspection{
    FormatInspect.Identity{"0.5.0.0", "0.4.0.0", 3}, integrity}

# Admits a legacy source only after its data files are verified.
law validated_legacy_source_is_admitted:
  {Migrate.plan(legacy.inspection(FormatInspect.Valid{}),
    Migrate.LegacyFilesVerified{4n, 64n}, True{}, 4n, 64n) ==
    Migrate.MigrateReady{4n, 64n} : Migrate.Decision}

# Rejects a valid manifest when WAL and SST contents were not checked.
law manifest_alone_never_admits_migration:
  {Migrate.plan(legacy.inspection(FormatInspect.Valid{}),
    Migrate.SourceNotChecked{}, True{}, 4n, 64n) ==
    Migrate.MigrateRejected{Migrate.SourceFilesNotVerified{}} : Migrate.Decision}

# Rejects current storage as a migration source.
law non_legacy_storage_is_rejected:
  {Migrate.plan(FormatInspect.Inspection{
      FormatInspect.Identity{"0.6.0.0", "0.6.0.0", 4}, FormatInspect.Valid{}},
    Migrate.LegacyFilesVerified{4n, 64n}, True{}, 4n, 64n) ==
    Migrate.MigrateRejected{Migrate.UnsupportedSource{}} : Migrate.Decision}

# Rejects a source whose manifest failed integrity validation.
law corrupt_manifest_is_rejected:
  {Migrate.plan(legacy.inspection(FormatInspect.Corrupt{}),
    Migrate.LegacyFilesVerified{4n, 64n}, True{}, 4n, 64n) ==
    Migrate.MigrateRejected{Migrate.InvalidManifest{}} : Migrate.Decision}

# Preserves an existing destination by rejecting migration.
law existing_destination_is_rejected:
  {Migrate.plan(legacy.inspection(FormatInspect.Valid{}),
    Migrate.LegacyFilesVerified{4n, 64n}, False{}, 4n, 64n) ==
    Migrate.MigrateRejected{Migrate.DestinationExists{}} : Migrate.Decision}

# Enforces the encoded-byte limit before migration admission.
law oversized_source_is_rejected:
  {Migrate.plan(legacy.inspection(FormatInspect.Valid{}),
    Migrate.LegacyFilesVerified{4n, 64n}, True{}, 4n, 63n) ==
    Migrate.MigrateRejected{Migrate.ResourceLimit{}} : Migrate.Decision}

# Enforces the record-count limit before migration admission.
law entry_limit_is_enforced:
  {Migrate.plan(legacy.inspection(FormatInspect.Valid{}),
    Migrate.LegacyFilesVerified{5n, 64n}, True{}, 4n, 64n) ==
    Migrate.MigrateRejected{Migrate.ResourceLimit{}} : Migrate.Decision}

# Rejects migration when a legacy WAL or SST failed validation.
law corrupt_legacy_files_are_rejected:
  {Migrate.plan(legacy.inspection(FormatInspect.Valid{}),
    Migrate.LegacyFilesRejected{}, True{}, 4n, 64n) ==
    Migrate.MigrateRejected{Migrate.SourceFilesInvalid{}} : Migrate.Decision}

# Preserves a resource-limit result from bounded manifest inspection.
law manifest_resource_limit_is_preserved:
  {Migrate.plan(legacy.inspection(FormatInspect.ResourceLimit{}),
    Migrate.SourceNotChecked{}, True{}, 4n, 64n) ==
    Migrate.MigrateRejected{Migrate.ResourceLimit{}} : Migrate.Decision}

# An existing destination is rejected for every otherwise-valid source.
law existing_destination_rejects_any_verified_source:
  for entry_count: Nat
  for encoded_bytes: Nat
  for max_entries: Nat
  for max_encoded_bytes: Nat
  {Migrate.plan(legacy.inspection(FormatInspect.Valid{}),
    Migrate.LegacyFilesVerified{entry_count, encoded_bytes}, False{},
    max_entries, max_encoded_bytes) ==
    Migrate.MigrateRejected{Migrate.DestinationExists{}} : Migrate.Decision}

# Destination staging cannot begin before source validation succeeds.
law staging_requires_a_validated_source:
  {Migrate.stage_destination(Migrate.SourceValidated{}) ==
    Migrate.PublicationAdvanced{Migrate.DestinationStaged{}} : Migrate.PublicationDecision}

# A rejected migration preflight cannot enter the publication lifecycle.
law rejected_preflight_cannot_begin_publication:
  {Migrate.begin(Migrate.MigrateRejected{Migrate.SourceFilesInvalid{}}) ==
    Migrate.PublicationRejected{} : Migrate.PublicationDecision}

# Data copying cannot begin before a destination sibling is staged.
law copying_requires_a_staged_destination:
  {Migrate.records_copied(Migrate.SourceValidated{}) ==
    Migrate.PublicationRejected{} : Migrate.PublicationDecision}

# Destination verification follows completed record copying.
law verification_requires_completed_copy:
  {Migrate.destination_validated(Migrate.RecordsCopied{}, (4n, 4n),
    (True{}, True{})) ==
    Migrate.PublicationAdvanced{Migrate.DestinationValidated{}} : Migrate.PublicationDecision}

# Rejects destination evidence whose record count differs from the source.
law destination_count_mismatch_rejects_verification:
  {Migrate.destination_validated(Migrate.RecordsCopied{}, (4n, 3n),
    (True{}, True{})) == Migrate.PublicationRejected{} : Migrate.PublicationDecision}

# Rejects destination evidence whose canonical record digest differs.
law destination_digest_mismatch_rejects_verification:
  {Migrate.destination_validated(Migrate.RecordsCopied{}, (4n, 4n),
    (False{}, True{})) == Migrate.PublicationRejected{} : Migrate.PublicationDecision}

# Rejects destination evidence whose records are not in canonical order.
law destination_order_mismatch_rejects_verification:
  {Migrate.destination_validated(Migrate.RecordsCopied{}, (4n, 4n),
    (True{}, False{})) == Migrate.PublicationRejected{} : Migrate.PublicationDecision}

# Publication cannot occur until the destination has been verified.
law publication_requires_verified_destination:
  {Migrate.publish(Migrate.RecordsCopied{}) ==
    Migrate.PublicationRejected{} : Migrate.PublicationDecision}

# A failed operation cannot turn an already published destination into an abort.
law abort_preserves_published_destination:
  {Migrate.abort(Migrate.Published{}) ==
    Migrate.PublicationRejected{} : Migrate.PublicationDecision}

# An unfinished migration can leave the final destination unpublished.
law abort_unpublished_migration:
  {Migrate.abort(Migrate.DestinationStaged{}) ==
    Migrate.PublicationAdvanced{Migrate.Aborted{}} : Migrate.PublicationDecision}

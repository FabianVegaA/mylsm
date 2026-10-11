import Base
import ../ByteMemTable.bend as ByteMemTable
import ../coordinator/QueuePolicy.bend as QueuePolicy
import ./FormatInspect.bend as FormatInspect

# Reports the result of verifying all legacy WAL and SST files.
type SourceValidation is Data:
  LegacyFilesVerified{entries: Nat, encoded_bytes: Nat}
  LegacyFilesRejected{}
  SourceNotChecked{}

# Classifies safe migration preflight failures.
type Rejection is Data:
  UnsupportedSource{}
  InvalidManifest{}
  SourceFilesInvalid{}
  SourceFilesNotVerified{}
  DestinationExists{}
  ResourceLimit{}

# Admits a fully verified source or rejects it before destination mutation.
type Decision is Data:
  MigrateReady{entries: Nat, encoded_bytes: Nat}
  MigrateRejected{reason: Rejection}

# Tracks the migration stages that guard atomic destination publication.
type Publication is Data:
  SourceValidated{}
  DestinationStaged{}
  RecordsCopied{}
  DestinationValidated{}
  Published{}
  Aborted{}

# Reports an allowed stage transition or a rejected transition.
type PublicationDecision is Data:
  PublicationAdvanced{state: Publication}
  PublicationRejected{}

def canonical.entries(table: ByteMemTable.Table) -> List<&1, ByteMemTable.Entry>:
  ByteMemTable.compact.live(ByteMemTable.ordered_entries(table))

# Begins publication only for a source admitted by the migration plan.
def begin(decision: Decision) -> PublicationDecision:
  match decision:
    case MigrateReady{_, _}: PublicationAdvanced{SourceValidated{}}
    case MigrateRejected{_}: PublicationRejected{}

# Stages a sibling destination only after source validation.
def stage_destination(state: Publication) -> PublicationDecision:
  match state:
    case SourceValidated{}: PublicationAdvanced{DestinationStaged{}}
    case _: PublicationRejected{}

# Marks the copy complete only for an initialized staging destination.
def records_copied(state: Publication) -> PublicationDecision:
  match state:
    case DestinationStaged{}: PublicationAdvanced{RecordsCopied{}}
    case _: PublicationRejected{}

# Marks the staged database verified only when count, digest, and order agree.
def destination_validated(
  state: Publication,
  counts: Nat & Nat,
  checks: Bool & Bool
) -> PublicationDecision:
  match state:
    case RecordsCopied{}:
      match counts:
        case (source_entries, destination_entries):
          match checks:
            case (digest_equal, canonical_order):
              Bool.pick(PublicationDecision,
                Nat.is_eq(source_entries, destination_entries) && digest_equal && canonical_order,
                PublicationAdvanced{DestinationValidated{}},
                PublicationRejected{})
    case _: PublicationRejected{}

# Allows final publication only after destination verification.
def publish(state: Publication) -> PublicationDecision:
  match state:
    case DestinationValidated{}: PublicationAdvanced{Published{}}
    case _: PublicationRejected{}

# Aborts an unpublished migration without retracting a published destination.
def abort(state: Publication) -> PublicationDecision:
  match state:
    case Published{}: PublicationRejected{}
    case Aborted{}: PublicationRejected{}
    case _: PublicationAdvanced{Aborted{}}

# Accepts only the durable API and storage identities promised for migration.
def source.supported(identity: FormatInspect.Identity) -> Bool:
  match identity:
    case FormatInspect.Identity{package_version, storage_version, generation}:
      String.eq(package_version, "0.5.0.0") &&
        String.eq(storage_version, "0.4.0.0") && U32.is_eq(generation, 3)

# Applies count and byte limits after duplicating the affine byte count.
def gate.destination.measured(
  max_entries: Nat,
  max_encoded_bytes: Nat,
  destination_missing: Bool,
  entry_counts: Nat & Nat,
  byte_counts: Nat & Nat
) -> Decision:
  match entry_counts:
    case (result_entries, measured_entries):
      match byte_counts:
        case (result_bytes, measured_bytes):
          Bool.pick(Decision, destination_missing,
            Bool.pick(Decision,
              Nat.is_le(measured_entries, max_entries) &&
                Nat.is_le(measured_bytes, max_encoded_bytes),
              MigrateReady{result_entries, result_bytes},
              MigrateRejected{ResourceLimit{}}),
            MigrateRejected{DestinationExists{}})

# Checks verified record and byte counts against configured migration limits.
def gate.destination(
  validation: SourceValidation,
  destination_missing: Bool,
  max_entries: Nat,
  max_encoded_bytes: Nat
) -> Decision:
  match validation:
    case LegacyFilesVerified{entries, encoded_bytes}:
      gate.destination.measured(max_entries, max_encoded_bytes,
        destination_missing, QueuePolicy.nat.clone.pair(entries),
        QueuePolicy.nat.clone.pair(encoded_bytes))
    case LegacyFilesRejected{}:
      MigrateRejected{SourceFilesInvalid{}}
    case SourceNotChecked{}:
      MigrateRejected{SourceFilesNotVerified{}}

# Applies the source compatibility check before destination admission.
def gate.source(
  validation: SourceValidation,
  destination_missing: Bool,
  max_entries: Nat,
  max_encoded_bytes: Nat,
  supported: Bool
) -> Decision:
  Bool.pick(Decision, supported,
    gate.destination(validation, destination_missing, max_entries,
      max_encoded_bytes),
    MigrateRejected{UnsupportedSource{}})

# Requires a valid manifest before considering the legacy file verification.
def gate.manifest(
  validation: SourceValidation,
  destination_missing: Bool,
  max_entries: Nat,
  max_encoded_bytes: Nat,
  supported: Bool,
  integrity: FormatInspect.Integrity
) -> Decision:
  match integrity:
    case FormatInspect.Valid{}:
      gate.source(validation, destination_missing, max_entries,
        max_encoded_bytes, supported)
    case FormatInspect.ResourceLimit{}:
      MigrateRejected{ResourceLimit{}}
    case _:
      MigrateRejected{InvalidManifest{}}

# Chooses compatibility, validation, destination, and resource preconditions.
def plan(
  inspection: FormatInspect.Inspection,
  validation: SourceValidation,
  destination_missing: Bool,
  max_entries: Nat,
  max_encoded_bytes: Nat
) -> Decision:
  match inspection:
    case FormatInspect.Inspection{identity, integrity}:
      gate.manifest(validation, destination_missing, max_entries,
        max_encoded_bytes,
        source.supported(identity), integrity)

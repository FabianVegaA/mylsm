import Base
import ../ByteMemTable.bend as ByteMemTable
import ../MemTable.bend as MemTable
import ../StorageBytes.bend as StorageBytes
import ../Wal.bend as Wal
import ../coordinator/QueuePolicy.bend as QueuePolicy
import ./FormatInspect.bend as FormatInspect
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

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

# Carries legacy record conversion across bounded state-machine steps.
type LegacyApplyState is Type:
  LegacyApplyNeed{entries: List<&2, MemTable.Entry>, table: ByteMemTable.Table}
  LegacyApplyConverted{tail: List<&2, MemTable.Entry>, table: ByteMemTable.Table,
    result: Result<&1, &1, U32 & String, ByteMemTable.Entry>}

def legacy.string.clone.go(value: String, left: String, right: String) -> String & String:
  match value:
    case SNil{}: (String.reverse(left), String.reverse(right))
    case SCon{+character, rest}:
      legacy.string.clone.go(rest, SCon{character, left}, SCon{character, right})

def legacy.string.clone(value: String) -> String & String:
  legacy.string.clone.go(value, SNil{}, SNil{})

def canonical.entries(table: ByteMemTable.Table) -> List<&1, ByteMemTable.Entry>:
  ByteMemTable.compact.live(ByteMemTable.ordered_entries(table))

def legacy.value.bytes.result(
  result: Result<&1, &1, U32 & String, Bytes.Bytes>
) -> Result<&1, &1, U32 & String, Maybe<&1, Bytes.Bytes>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{bytes}: Done{Some{bytes}}

def legacy.value.bytes(
  value: Maybe<&2, String>
) -> Result<&1, &1, U32 & String, Maybe<&1, Bytes.Bytes>>:
  match value:
    case None{}: Done{None{}}
    case Some{text}: legacy.value.bytes.result(StorageBytes.from_string(text))

def legacy.entry.bytes.value(
  key: Bytes.Bytes,
  result: Result<&1, &1, U32 & String, Maybe<&1, Bytes.Bytes>>
) -> Result<&1, &1, U32 & String, ByteMemTable.Entry>:
  match result:
    case Fail{error}: Fail{error}
    case Done{value}: Done{ByteMemTable.Entry{key, value}}

def legacy.entry.bytes.key(
  value: Maybe<&2, String>,
  pair: String & Result<&1, &1, U32 & String, Bytes.Bytes>
) -> Result<&1, &1, U32 & String, ByteMemTable.Entry>:
  match pair:
    case (_, Fail{error}): Fail{error}
    case (_, Done{key_bytes}):
      legacy.entry.bytes.value(key_bytes, legacy.value.bytes(value))

def legacy.entry.bytes.start(
  value: Maybe<&2, String>,
  pair: String & String
) -> Result<&1, &1, U32 & String, ByteMemTable.Entry>:
  match pair:
    case (source, retained):
      legacy.entry.bytes.key(value,
        (retained, StorageBytes.from_string(source)))

def legacy.entry.bytes(
  entry: MemTable.Entry
) -> Result<&1, &1, U32 & String, ByteMemTable.Entry>:
  match entry:
    case MemTable.Entry{key, value}:
      legacy.entry.bytes.start(value, legacy.string.clone(key))

def legacy.apply.loop(
  fuel: Nat,
  state: LegacyApplyState
) -> Result<&1, &1, U32 & String, ByteMemTable.Table>:
  match fuel:
    case 0n:
      match state:
        case LegacyApplyNeed{_, table}: Done{table}
        case LegacyApplyConverted{_, _, Fail{error}}: Fail{error}
        case LegacyApplyConverted{_, table, Done{_}}: Done{table}
    case 1n+rest:
      match state:
        case LegacyApplyNeed{entries, table}:
          match entries:
            case Nil{}: Done{table}
            case Con{entry, tail}:
              legacy.apply.loop(rest, LegacyApplyConverted{tail, table,
                legacy.entry.bytes(entry)})
        case LegacyApplyConverted{tail, table, result}:
          match result:
            case Fail{error}: Fail{error}
            case Done{ByteMemTable.Entry{key, value}}:
              match value:
                case None{}:
                  legacy.apply.loop(rest, LegacyApplyNeed{tail,
                    ByteMemTable.del(table, key)})
                case Some{bytes}:
                  legacy.apply.loop(rest, LegacyApplyNeed{tail,
                    ByteMemTable.put(table, key, bytes)})

def legacy.entries.measure.go(
  entries: List<&2, MemTable.Entry>,
  reversed: List<&2, MemTable.Entry>,
  count: Nat
) -> List<&2, MemTable.Entry> & Nat:
  match entries:
    case Nil{}: (List.reverse(&2, MemTable.Entry, reversed), count)
    case Con{entry, tail}:
      legacy.entries.measure.go(tail, Con{entry, reversed}, Nat.add(count, 1n))

def legacy.entries.measure(
  entries: List<&2, MemTable.Entry>
) -> List<&2, MemTable.Entry> & Nat:
  legacy.entries.measure.go(entries, Nil{}, 0n)

def legacy.apply.measured(
  pair: List<&2, MemTable.Entry> & Nat,
  table: ByteMemTable.Table
) -> Result<&1, &1, U32 & String, ByteMemTable.Table>:
  match pair:
    case (entries, count):
      legacy.apply.loop(Nat.add(Nat.mul(2n, count), 1n),
        LegacyApplyNeed{entries, table})

def legacy.apply.chronological(
  entries: List<&2, MemTable.Entry>,
  table: ByteMemTable.Table
) -> Result<&1, &1, U32 & String, ByteMemTable.Table>:
  legacy.apply.measured(legacy.entries.measure(entries), table)

def legacy.batch.entries(mutations: List<&2, Wal.Mut>) -> List<&2, MemTable.Entry>:
  match mutations:
    case Nil{}: Nil{}
    case Con{mutation, tail}:
      match mutation:
        case Wal.Put{key, val}:
          Con{MemTable.Entry{key, Some{val}}, legacy.batch.entries(tail)}
        case Wal.Del{key}:
          Con{MemTable.Entry{key, None{}}, legacy.batch.entries(tail)}

def legacy.batches.entries(batches: List<&2, Wal.Batch>) -> List<&2, MemTable.Entry>:
  match batches:
    case Nil{}: Nil{}
    case Con{Wal.Batch{muts}, tail}:
      List.append(&2, MemTable.Entry, legacy.batch.entries(muts),
        legacy.batches.entries(tail))

def legacy.sources.chronological(
  sst_newest_first: List<&2, MemTable.Entry>,
  wal_batches: List<&2, Wal.Batch>
) -> List<&2, MemTable.Entry>:
  List.append(&2, MemTable.Entry,
    List.reverse(&2, MemTable.Entry, sst_newest_first),
    legacy.batches.entries(wal_batches))

def legacy.snapshot.table(
  sst_newest_first: List<&2, MemTable.Entry>,
  wal_batches: List<&2, Wal.Batch>
) -> Result<&1, &1, U32 & String, ByteMemTable.Table>:
  legacy.apply.chronological(
    legacy.sources.chronological(sst_newest_first, wal_batches),
    ByteMemTable.empty())

def legacy.snapshot.canonicalize(
  result: Result<&1, &1, U32 & String, ByteMemTable.Table>
) -> Result<&1, &1, U32 & String, List<&1, ByteMemTable.Entry>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{table}: Done{canonical.entries(table)}

def legacy.snapshot.entries(
  sst_newest_first: List<&2, MemTable.Entry>,
  wal_batches: List<&2, Wal.Batch>
) -> Result<&1, &1, U32 & String, List<&1, ByteMemTable.Entry>>:
  legacy.snapshot.canonicalize(
    legacy.snapshot.table(sst_newest_first, wal_batches))

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

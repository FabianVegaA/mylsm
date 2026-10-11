import Base
import ../src/ByteManifest.bend as ByteManifest
import ../src/Manifest.bend as LegacyManifest
import ../src/transfer/FormatInspect.bend as FormatInspect
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Extracts the canonical empty legacy manifest used by closed witnesses.
def legacy.empty.encoded(
  result: Result<&1, &1, LegacyManifest.Error, Bytes.Bytes>
) -> Bytes.Bytes:
  match result:
    case Fail{_}: Bytes.new(0)
    case Done{bytes}: bytes

def legacy.empty() -> Bytes.Bytes:
  legacy.empty.encoded(LegacyManifest.serialize(LegacyManifest.M{Nil{}}))

# The legacy API and storage version strings must remain distinct.
law legacy_versions_are_separate:
  {FormatInspect.describe(FormatInspect.Format04{}) ==
    FormatInspect.Identity{"0.5.0.0", "0.4.0.0", 3} : FormatInspect.Identity}

# The current API and storage identity use generation four.
law current_versions_are_separate:
  {FormatInspect.describe(FormatInspect.Format06{}) ==
    FormatInspect.Identity{"0.6.0.0", "0.6.0.0", 4} : FormatInspect.Identity}

# Unknown manifest generations are classified without a fallback.
law unknown_magic_rejected:
  {FormatInspect.classify_manifest(Bytes.new(0)) == FormatInspect.UnknownFormat{} :
    FormatInspect.StorageFormat}

# A valid generation-three manifest has a distinct package/storage identity.
law valid_legacy_manifest_integrity:
  {FormatInspect.inspect_manifest_bytes(legacy.empty()) ==
    FormatInspect.Inspection{
      FormatInspect.Identity{"0.5.0.0", "0.4.0.0", 3},
      FormatInspect.Valid{}} : FormatInspect.Inspection}

# A current generation-four manifest passes its own decoder and checksum.
law valid_current_manifest_integrity:
  {FormatInspect.inspect_manifest_bytes(ByteManifest.encode(ByteManifest.Empty{})) ==
    FormatInspect.Inspection{
      FormatInspect.Identity{"0.6.0.0", "0.6.0.0", 4},
      FormatInspect.Valid{}} : FormatInspect.Inspection}

# An unknown signature is not reported as a valid manifest.
law unknown_manifest_is_not_valid:
  {FormatInspect.inspect_manifest_bytes(Bytes.new(0)) ==
    FormatInspect.Inspection{
      FormatInspect.Identity{"unknown", "unknown", 0},
      FormatInspect.UnrecognizedFormat{}} : FormatInspect.Inspection}

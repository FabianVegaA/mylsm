import Base
import ../src/ByteManifest.bend as Manifest
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# The empty generation-four manifest preserves its decoded state.
law empty_manifest_round_trips:
  {Manifest.decode(Manifest.encode(Manifest.Empty{})) == Done{Manifest.Empty{}} : Result<&1, &1, Manifest.Error, Manifest.ManifestValue>}

# The one-SST generation-four manifest preserves its decoded state.
law sst_manifest_round_trips:
  {Manifest.decode(Manifest.encode(Manifest.HasSst{})) == Done{Manifest.HasSst{}} : Result<&1, &1, Manifest.Error, Manifest.ManifestValue>}

# An unknown storage generation fails before layout interpretation.
law unknown_generation_is_rejected:
  {Manifest.decode(Bytes.set(Manifest.encode(Manifest.Empty{}), 11, 3)) == Fail{Manifest.UnsupportedVersion{3}} : Result<&1, &1, Manifest.Error, Manifest.ManifestValue>}

# A different key-comparator generation cannot be opened as current data.
law comparator_mismatch_is_rejected:
  {Manifest.decode(Bytes.set(Manifest.encode(Manifest.Empty{}), 15, 2)) == Fail{Manifest.ComparatorMismatch{2}} : Result<&1, &1, Manifest.Error, Manifest.ManifestValue>}

# Changed manifest bytes fail checksum validation.
law manifest_checksum_corruption_is_rejected:
  {Manifest.decode(Bytes.set(Manifest.encode(Manifest.Empty{}), 55, 1)) == Fail{Manifest.ChecksumMismatch{}} : Result<&1, &1, Manifest.Error, Manifest.ManifestValue>}

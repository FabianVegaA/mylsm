import Base
import ../src/ByteManifest.bend as Manifest
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# The empty generation-four manifest preserves its decoded state.
law empty_manifest_round_trips:
  {Manifest.decode(Manifest.encode(Manifest.Empty{})) == Done{Manifest.Empty{}} : Result<&1, &1, Manifest.Error, Manifest.ManifestValue>}

# The one-SST generation-four manifest preserves its decoded state.
law sst_manifest_encodes:
  {Manifest.encode(Manifest.HasSst{}) == Manifest.literal(Bytes.from_hex(
    "4d594c534d344d000000000400000001000000010000000100000003535354e796524d9c675c1254252cb9ef7b6e8cc882cf896d79d0f777afbd52e6c9ca04")) : Bytes.Bytes}

# Decodes the fixed byte vector for a one-SST generation-four manifest.
law sst_manifest_decodes:
  {Manifest.decode(Manifest.literal(Bytes.from_hex(
    "4d594c534d344d000000000400000001000000010000000100000003535354e796524d9c675c1254252cb9ef7b6e8cc882cf896d79d0f777afbd52e6c9ca04"))) ==
    Done{Manifest.HasSst{}} : Result<&1, &1, Manifest.Error, Manifest.ManifestValue>}

# The empty generation-five manifest preserves its layout.
law generation_manifest_round_trips:
  {Manifest.decode(Manifest.encode(Manifest.GenerationEmpty{})) ==
    Done{Manifest.GenerationEmpty{}} :
    Result<&1, &1, Manifest.Error, Manifest.ManifestValue>}

# A generation-addressed SST manifest preserves its active file identifier.
law generation_sst_manifest_round_trips:
  {Manifest.decode(Manifest.encode(Manifest.GenerationSst{3})) ==
    Done{Manifest.GenerationSst{3}} :
    Result<&1, &1, Manifest.Error, Manifest.ManifestValue>}

# Generation paths use an unambiguous fixed-width hexadecimal file identifier.
law generation_sst_path_encodes_the_identifier:
  {String.eq(Manifest.sst.generation.path("/db", 3), "/db/SST.00000003") ==
    True{} : Bool}

# Generation identifiers advance by one without wrapping.
law next_generation_identifier_advances:
  {Manifest.next.file.id(Manifest.GenerationSst{3}) == Manifest.FileIdAvailable{4} : Manifest.FileIdDecision}

# Exhausted generation identifiers are rejected instead of wrapping.
law generation_identifier_exhaustion_is_reported:
  {Manifest.next.file.id(Manifest.GenerationSst{4294967295}) == Manifest.FileIdExhausted{} : Manifest.FileIdDecision}

# Legacy SST manifests begin generation-addressed publication at file one.
law legacy_manifest_starts_generation_at_one:
  {Manifest.next.file.id(Manifest.HasSst{}) == Manifest.FileIdAvailable{1} : Manifest.FileIdDecision}

# Detects checksum corruption in a generation-five manifest.
law generation_manifest_checksum_corruption_is_rejected:
  {Manifest.decode(Bytes.set(Manifest.encode(Manifest.GenerationEmpty{}),
    55, 1)) == Fail{Manifest.ChecksumMismatch{}} :
    Result<&1, &1, Manifest.Error, Manifest.ManifestValue>}

# Rejects manifest lengths that no supported decoder reads from disk.
law unsupported_manifest_size_is_rejected:
  {Manifest.decode(Bytes.new(64)) == Fail{Manifest.Malformed{}} :
    Result<&1, &1, Manifest.Error, Manifest.ManifestValue>}

# An unknown storage generation fails before layout interpretation.
law unknown_generation_is_rejected:
  {Manifest.decode(Bytes.set(Manifest.encode(Manifest.Empty{}), 11, 3)) == Fail{Manifest.UnsupportedVersion{3}} : Result<&1, &1, Manifest.Error, Manifest.ManifestValue>}

# A different key-comparator generation cannot be opened as current data.
law comparator_mismatch_is_rejected:
  {Manifest.decode(Bytes.set(Manifest.encode(Manifest.Empty{}), 15, 2)) == Fail{Manifest.ComparatorMismatch{2}} : Result<&1, &1, Manifest.Error, Manifest.ManifestValue>}

# Changed manifest bytes fail checksum validation.
law manifest_checksum_corruption_is_rejected:
  {Manifest.decode(Bytes.set(Manifest.encode(Manifest.Empty{}), 55, 1)) == Fail{Manifest.ChecksumMismatch{}} : Result<&1, &1, Manifest.Error, Manifest.ManifestValue>}

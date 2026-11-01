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

# Verifies only SST files other than the published generation are retired.
law retired_keeps_the_published_generation:
  {Manifest.retired(Manifest.GenerationSst{2},
    ["LOCK", "MANIFEST", "SST.00000001", "SST.00000002", "WAL"]) ==
    ["SST.00000001"] : List<&2, String>}

# Verifies an unfinished SST write is retired.
law retired_includes_temporary_sst_files:
  {Manifest.retired(Manifest.GenerationSst{1},
    ["SST.00000001", "SST.00000002.tmp"]) ==
    ["SST.00000002.tmp"] : List<&2, String>}

# Verifies generation ids are matched in lowercase hexadecimal.
law retired_matches_lowercase_hex_names:
  {Manifest.retired(Manifest.GenerationSst{10},
    ["SST.0000000a", "SST.00000009"]) ==
    ["SST.00000009"] : List<&2, String>}

# Verifies a manifest without a published SST retires every generation file.
law retired_without_publication_takes_every_sst:
  {Manifest.retired(Manifest.GenerationEmpty{},
    ["SST.00000001", "WAL"]) == ["SST.00000001"] : List<&2, String>}

# Verifies the generation-four SST file is never retired.
law retired_keeps_the_generation_four_sst:
  {Manifest.retired(Manifest.HasSst{}, ["SST", "WAL"]) ==
    [] : List<&2, String>}

# Verifies the published generation file, named by the shared function, is never retired.
law retired_never_takes_the_published_name:
  {[Manifest.retired(Manifest.GenerationSst{1}, [Manifest.sst.generation.name(1)]),
    Manifest.retired(Manifest.GenerationSst{10}, [Manifest.sst.generation.name(10)]),
    Manifest.retired(Manifest.GenerationSst{255}, [Manifest.sst.generation.name(255)]),
    Manifest.retired(Manifest.GenerationSst{65536}, [Manifest.sst.generation.name(65536)]),
    Manifest.retired(Manifest.GenerationSst{4294967295},
      [Manifest.sst.generation.name(4294967295)])] ==
    [[], [], [], [], []] : List<&2, List<&2, String>>}

# Verifies the generation path is the directory joined with the shared file name.
law generation_path_uses_the_shared_name:
  {Manifest.sst.generation.path("db", 10) ==
    "db/" ++ Manifest.sst.generation.name(10) : String}

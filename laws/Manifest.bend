import Base
import ../src/Manifest.bend as Manifest
import ../src/StorageBytes.bend as StorageBytes
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

def hex.finish(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}:
      bytes
    case None{}:
      Bytes.new(0)

def encoded.finish(result: Result<&1, &1, Manifest.Error, Bytes.Bytes>) -> Bytes.Bytes:
  match result:
    case Done{bytes}:
      bytes
    case Fail{_}:
      Bytes.new(0)

# Handle empty in the manifest codec laws.
def empty() -> Manifest.Manifest:
  Manifest.M{Nil{}}

# Handle two levels in the manifest codec laws.
def two_levels() -> Manifest.Manifest:
  Manifest.M{Con{Con{"a.tbl", Con{"b.tbl", Nil{}}}, Con{Con{"é.tbl", Nil{}}, Nil{}}}}

# Check whether whether expected holds for the manifest codec laws.
def empty_expected() -> Bytes.Bytes:
  hex.finish(Bytes.from_hex("4d594c534d334d0000000003000000001205c80e921bb2ce3c951dca55299a11f60403d7440d7f3949c06848ca9fd22a"))

# Handle two levels expected in the manifest codec laws.
def two_levels_expected() -> Bytes.Bytes:
  hex.finish(Bytes.from_hex("4d594c534d334d0000000003000000020000000200000005612e74626c00000005622e74626c0000000100000006c3a92e74626cf39b88edf66c32df5f8d45703f73f871850048939b317897290ae7a689d303ad"))

# State the manifest v3 empty vector property for the manifest codec laws.
law manifest_v3_empty_vector:
  {Manifest.serialize(empty()) == Done{empty_expected()} : Result<&1, &1, Manifest.Error, Bytes.Bytes>}

# State the manifest v3 two levels vector property for the manifest codec laws.
law manifest_v3_two_levels_vector:
  {Manifest.serialize(two_levels()) == Done{two_levels_expected()} : Result<&1, &1, Manifest.Error, Bytes.Bytes>}

# State the manifest v3 two levels roundtrip property for the manifest codec laws.
law manifest_v3_two_levels_roundtrip:
  {Manifest.parse(two_levels_expected()) == Some{two_levels()} : Maybe<&2, Manifest.Manifest>}

# State the manifest v3 empty roundtrip property for the manifest codec laws.
law manifest_v3_empty_roundtrip:
  {Manifest.parse(empty_expected()) == Some{empty()} : Maybe<&2, Manifest.Manifest>}

# State the manifest v3 rejects text property for the manifest codec laws.
law manifest_v3_rejects_text:
  {Manifest.parse(hex.finish(Bytes.from_hex("612e74626c0a23313233"))) == None{} : Maybe<&2, Manifest.Manifest>}

# State the manifest v3 rejects trailing byte property for the manifest codec laws.
law manifest_v3_rejects_trailing_byte:
  {Manifest.parse(Bytes.concat([empty_expected(), Bytes.new(1)])) == None{} : Maybe<&2, Manifest.Manifest>}

# State the manifest v3 rejects unsafe name property for the manifest codec laws.
law manifest_v3_rejects_unsafe_name:
  {Manifest.serialize(Manifest.M{Con{Con{"../outside.tbl", Nil{}}, Nil{}}}) == Fail{Manifest.InvalidName{}} : Result<&1, &1, Manifest.Error, Bytes.Bytes>}

# State the manifest v3 total property for the manifest codec laws.
law manifest_v3_total:
  for bytes: Bytes.Bytes
  {Manifest.is_decided(Manifest.parse(bytes)) == True{} : Bool}

# States the manifest result accepts current format property.
law manifest_result_accepts_current_format:
  {Manifest.parse_result(empty_expected()) == Manifest.Parsed{empty()} : Manifest.ParseResult}

# States the manifest result identifies unsupported version property.
law manifest_result_identifies_unsupported_version:
  {Manifest.parse_result(Bytes.set.u32be(empty_expected(), 8, 4)) == Manifest.UnsupportedVersion{4} : Manifest.ParseResult}

# States the manifest result classifies malformed current format property.
law manifest_result_classifies_malformed_current_format:
  {Manifest.parse_result(Bytes.concat([empty_expected(), Bytes.new(1)])) == Manifest.Malformed{} : Manifest.ParseResult}

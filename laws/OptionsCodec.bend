import Base
import ../src/ResourceOptions.bend as ResourceOptions
import ../src/coordinator/OptionsCodec.bend as Codec
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Verifies option fields roundtrip.
law option_fields_roundtrip:
  for options: ResourceOptions.Options
  {Codec.options.from.fields(Codec.fields.of.options(options)) ==
    Some{options} : Maybe<&2, ResourceOptions.Options>}

# Verifies wrong length is malformed.
law wrong_length_is_malformed:
  {Codec.sized.result(Bytes.new(0), False{}) == Codec.Malformed{} : Codec.Decision}

# Verifies unknown version is rejected.
law unknown_version_is_rejected:
  {Codec.version.classified(Bytes.new(0), 2, False{}) ==
    Codec.UnsupportedVersion{2} : Codec.Decision}

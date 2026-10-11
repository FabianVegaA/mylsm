import Base
import ../ByteManifest.bend as ByteManifest
import ../Manifest.bend as LegacyManifest
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Identifies the storage generation independently of the writing package.
type StorageFormat is Data:
  Format04{}
  Format06{}
  UnknownFormat{}

# Reports package and storage identities as separate fields.
type Identity is Data:
  Identity{package_version: String, storage_version: String, generation: U32}

# Reports validation status without conflating it with the format identity.
type Integrity is Data:
  Valid{}
  UnsupportedVersion{generation: U32}
  UnsupportedComparator{generation: U32}
  UnrecognizedFormat{}
  Corrupt{}
  ResourceLimit{}

# Separates API/storage version identity from manifest integrity.
type Inspection is Data:
  Inspection{identity: Identity, integrity: Integrity}

# Converts a decoded hex literal to an owned buffer.
def magic.from_hex(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}:
      bytes
    case None{}:
      Bytes.new(0)

# Produces the generation-three Manifest magic.
def magic.legacy() -> Bytes.Bytes:
  magic.from_hex(Bytes.from_hex("4d594c534d334d00"))

# Produces the generation-four Manifest magic.
def magic.current() -> Bytes.Bytes:
  magic.from_hex(Bytes.from_hex("4d594c534d344d00"))

# Classifies the current magic after an unsuccessful legacy comparison.
def classify.current(comparison: Bytes.Bytes & Bytes.Bytes & Bool) -> StorageFormat:
  match comparison:
    case (_, _, True{}):
      Format06{}
    case (_, _, False{}):
      UnknownFormat{}

# Preserves the candidate bytes while checking the current manifest magic.
def classify.legacy(comparison: Bytes.Bytes & Bytes.Bytes & Bool) -> StorageFormat:
  match comparison:
    case (_, candidate, True{}):
      Format04{}
    case (_, candidate, False{}):
      classify.current(Bytes.eq(magic.current(), candidate))

# Classifies known Manifest signatures without opening or modifying storage.
def classify_manifest(magic: Bytes.Bytes) -> StorageFormat:
  classify.legacy(Bytes.eq(magic.legacy(), magic))

# Describes the package release and storage format separately.
def describe(format: StorageFormat) -> Identity:
  match format:
    case Format04{}:
      Identity{"0.5.0.0", "0.4.0.0", 3}
    case Format06{}:
      Identity{"0.6.0.0", "0.6.0.0", 4}
    case UnknownFormat{}:
      Identity{"unknown", "unknown", 0}

# Identifies a Manifest and returns its separate version fields.
def inspect_manifest(magic: Bytes.Bytes) -> Identity:
  describe(classify_manifest(magic))

def magic.slice.result(pair: Bytes.Bytes & Bytes.Bytes) -> Bytes.Bytes:
  match pair:
    case (_, bytes): bytes

def bytes.clone.pair(+len: U32, copied: Array<U32> & Array<U32>) -> Bytes.Bytes & Bytes.Bytes:
  match copied:
    case (left, right): (Bytes.Bytes{len, left}, Bytes.Bytes{len, right})

def bytes.clone.split(bytes: Bytes.Bytes) -> Bytes.Bytes & Bytes.Bytes:
  match bytes:
    case Bytes.Bytes{+len, buffer}:
      bytes.clone.pair(len, Bytes.copy.bytes(len, buffer, Bytes.alloc(len), 0, 0))

def inspect.legacy.result(result: LegacyManifest.ParseResult) -> Integrity:
  match result:
    case LegacyManifest.Parsed{_}: Valid{}
    case LegacyManifest.UnsupportedVersion{version}:
      UnsupportedVersion{version}
    case LegacyManifest.ParseLimitExceeded{}: ResourceLimit{}
    case LegacyManifest.Malformed{}: Corrupt{}

def inspect.current.result(
  result: Result<&1, &1, ByteManifest.Error, ByteManifest.ManifestValue>
) -> Integrity:
  match result:
    case Done{_}: Valid{}
    case Fail{ByteManifest.UnsupportedVersion{generation}}:
      UnsupportedVersion{generation}
    case Fail{ByteManifest.ComparatorMismatch{generation}}:
      UnsupportedComparator{generation}
    case Fail{_}: Corrupt{}

def inspect.result(format: StorageFormat, bytes: Bytes.Bytes) -> Integrity:
  match format:
    case Format04{}: inspect.legacy.result(LegacyManifest.parse_result(bytes))
    case Format06{}: inspect.current.result(ByteManifest.decode(bytes))
    case UnknownFormat{}: UnrecognizedFormat{}

def format.clone(format: StorageFormat) -> StorageFormat & StorageFormat:
  match format:
    case Format04{}: (Format04{}, Format04{})
    case Format06{}: (Format06{}, Format06{})
    case UnknownFormat{}: (UnknownFormat{}, UnknownFormat{})

def inspect.bytes.format(
  bytes: Bytes.Bytes,
  formats: StorageFormat & StorageFormat
) -> Inspection:
  match formats:
    case (identity_format, integrity_format):
      Inspection{describe(identity_format), inspect.result(integrity_format, bytes)}

def inspect.bytes.copies(copies: Bytes.Bytes & Bytes.Bytes) -> Inspection:
  match copies:
    case (data, magic_bytes):
      inspect.bytes.format(data,
        format.clone(classify_manifest(magic.slice.result(
          Bytes.slice(magic_bytes, 0, 8)))))

# Identifies and validates one complete manifest without changing storage.
def inspect_manifest_bytes(bytes: Bytes.Bytes) -> Inspection:
  inspect.bytes.copies(bytes.clone.split(bytes))

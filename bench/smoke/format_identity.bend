import Base
import ../../src/transfer/FormatInspect.bend as FormatInspect
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Stops the fixture if package and storage version identities are conflated.
def require(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, message)

# Checks one separated package/storage identity.
def legacy.matches(identity: FormatInspect.Identity) -> Bool:
  match identity:
    case FormatInspect.Identity{package_version, storage_version, generation}:
      String.eq(package_version, "0.5.0.0") &&
        String.eq(storage_version, "0.4.0.0") && U32.is_eq(generation, 3)

# Checks the generation-four release identity.
def current.matches(identity: FormatInspect.Identity) -> Bool:
  match identity:
    case FormatInspect.Identity{package_version, storage_version, generation}:
      String.eq(package_version, "0.6.0.0") &&
        String.eq(storage_version, "0.6.0.0") && U32.is_eq(generation, 4)

# Checks that unsupported signatures carry no recognized generation.
def unknown.matches(identity: FormatInspect.Identity) -> Bool:
  match identity:
    case FormatInspect.Identity{_, _, generation}:
      U32.is_eq(generation, 0)

def main() -> IO(Unit):
  do IO<Unit>:
    legacy : FormatInspect.Identity <- IO.pure(FormatInspect.Identity,
      FormatInspect.inspect_manifest(FormatInspect.magic.legacy()))
    current : FormatInspect.Identity <- IO.pure(FormatInspect.Identity,
      FormatInspect.inspect_manifest(FormatInspect.magic.current()))
    unknown : FormatInspect.Identity <- IO.pure(FormatInspect.Identity,
      FormatInspect.inspect_manifest(FormatInspect.magic.from_hex(Bytes.from_hex("0000000000000000"))))
    require(legacy.matches(legacy), "legacy package and storage versions must be reported separately")
    require(current.matches(current), "generation-four identity must be reported separately")
    require(unknown.matches(unknown), "unknown generations must not receive a known identity")
    IO.print("format identity fixture passed")

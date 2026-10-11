import Base
import ../src/ByteManifest.bend as Manifest

# Generation identifiers advance without wrapping.
law next_identifier_advances:
  {Manifest.next.file.id(Manifest.GenerationSst{3}) == Manifest.FileIdAvailable{4} : Manifest.FileIdDecision}

# The exhausted identifier is rejected instead of wrapping.
law exhausted_identifier_is_rejected:
  {Manifest.next.file.id(Manifest.GenerationSst{4294967295}) == Manifest.FileIdExhausted{} : Manifest.FileIdDecision}

# Generation paths use fixed-width hexadecimal identifiers.
law generation_path_is_fixed_width:
  {String.eq(Manifest.sst.generation.path("/db", 3), "/db/SST.00000003") == True{} : Bool}

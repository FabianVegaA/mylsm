import Base
import ../src/SstFile.bend as SstFile

# Allows an intermediate block to leave entries for later blocks.
law intermediate_block_preserves_entries:
  {SstFile.stream.blocks.count.valid(True{}, 2, 3, 2) == True{} : Bool}

# Requires the final block to consume every remaining entry.
law final_block_consumes_entries:
  {SstFile.stream.blocks.count.valid(True{}, 1, 3, 3) == True{} : Bool}

# Rejects a non-final block that claims all remaining entries.
law early_block_cannot_consume_all_entries:
  {SstFile.stream.blocks.count.valid(True{}, 2, 3, 3) == False{} : Bool}

# Rejects an unconsumed or partially parsed block.
law partial_block_is_rejected:
  {SstFile.stream.blocks.count.valid(False{}, 1, 3, 3) == False{} : Bool}

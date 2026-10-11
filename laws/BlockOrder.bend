import Base
import ../src/ByteMemTable.bend as ByteMemTable
import ../src/scan/BlockOrder.bend as BlockOrder
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Unwraps closed byte vectors used by the block-order laws.
def packed(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}: bytes
    case None{}: Bytes.new(0)

# Accepts strict unsigned lexicographic order within a block.
law accepts_a_strictly_ascending_block:
  {BlockOrder.accepted(BlockOrder.go([
    ByteMemTable.Entry{packed(Bytes.from_hex("01")), None{}},
    ByteMemTable.Entry{packed(Bytes.from_hex("02")), None{}}
  ], BlockOrder.empty(None{}))) == True{} : Bool}

# Rejects a key duplicated at the boundary between adjacent blocks.
law rejects_a_duplicate_at_a_block_boundary:
  {BlockOrder.accepted(BlockOrder.go([
    ByteMemTable.Entry{packed(Bytes.from_hex("02")), None{}}
  ], BlockOrder.empty(Some{packed(Bytes.from_hex("02"))}))) == False{} : Bool}

# Rejects a later block whose first key precedes the prior block's last key.
law rejects_a_descending_key_across_blocks:
  {BlockOrder.accepted(BlockOrder.go([
    ByteMemTable.Entry{packed(Bytes.from_hex("01")), None{}}
  ], BlockOrder.empty(Some{packed(Bytes.from_hex("02"))}))) == False{} : Bool}

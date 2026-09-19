import Base
import ../src/BitTree.bend as BitTree

# LAW: indexed tree set exposes the selected bit (closed boundary vectors)
law bit_tree_set_hit:
  {BitTree.test(BitTree.set(BitTree.new(2n), 63n), 63n) == True{} : Bool}

law bit_tree_oob_safe:
  {BitTree.test(BitTree.set(BitTree.new(1n), 32n), 32n) == False{} : Bool}

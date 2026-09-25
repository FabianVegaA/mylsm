import Base
import 0x9ee2e9a299991dcc089fe22c7f3ceb5f/src/containers/bitset.bend as BitWords
import 0x9ee2e9a299991dcc089fe22c7f3ceb5f/src/math/pow2.bend as Pow2

# Pure indexed bit tree.
#
# A non-empty BitTree is a perfect binary tree whose leaves are U32 words.
# `words` is the logical word count; `capacity` is the power-of-two leaf
# capacity, and `height` is log2(capacity). Leaves at indexes >= words are
# padding. A word index follows its `height`-bit binary representation from
# most-significant bit at the root to least-significant bit at the leaf.
#
# The empty value is represented by Empty{} with all metadata zero. Bit
# indexes outside [0, words * 32) are total: test returns False{} and set is
# the identity.

type WordTree is Data:
  Empty{}
  Leaf{word: U32}
  Fork{left: WordTree, right: WordTree}

type BitTree is Data:
  BT{root: WordTree, words: Nat, capacity: Nat, height: Nat}

type Plan is Data:
  Plan{capacity: Nat, height: Nat}

# Find the least power of two >= need. `fuel = need` is a conservative
# termination bound; each non-final step doubles capacity.
def plan_go(fuel: Nat, +need: Nat, +capacity: Nat, +height: Nat, done: Bool) -> Plan:
  match fuel:
    case 0n:
      Plan{capacity, height}
    case 1n+f:
      match done:
        case True{}:
          Plan{capacity, height}
        case False{}:
          +next = Nat.double(capacity)
          plan_go(f, need, next, Nat.add(height, 1n), Nat.is_le(need, next))

def plan(+need: Nat) -> Plan:
  match need:
    case 0n:
      Plan{0n, 0n}
    case 1n+n:
      plan_go(need, need, 1n, 0n, Nat.is_le(need, 1n))

# Independent subtrees are built in parallel.
def zero_tree(+height: Nat) -> WordTree:
  match height:
    case 0n:
      Leaf{0}
    case 1n+h:
      left right = zero_tree(h) zero_tree(h)
      Fork{left, right}

def new_from_plan(words: Nat, plan: Plan) -> BitTree:
  match plan:
    case Plan{capacity, +height}:
      BT{zero_tree(height), words, capacity, height}

def new(+words: Nat) -> BitTree:
  match words:
    case 0n:
      BT{Empty{}, 0n, 0n, 0n}
    case 1n+n:
      new_from_plan(words, plan(words))

# Metadata helpers intended to keep representation laws independent of field
# layout.
def word_count(tree: BitTree) -> Nat:
  match tree:
    case BT{root, words, capacity, height}:
      words

def capacity_words(tree: BitTree) -> Nat:
  match tree:
    case BT{root, words, capacity, height}:
      capacity

def tree_height(tree: BitTree) -> Nat:
  match tree:
    case BT{root, words, capacity, height}:
      height

def bit_count(tree: BitTree) -> Nat:
  Nat.mul(word_count(tree), 32n)

def valid_bit(tree: BitTree, bit: Nat) -> Bool:
  Nat.is_lt(bit, bit_count(tree))

def same_metadata(+ta: BitTree, +tb: BitTree) -> Bool:
  Bool.and(
    Nat.is_eq(word_count(ta), word_count(tb)),
    Bool.and(
      Nat.is_eq(capacity_words(ta), capacity_words(tb)),
      Nat.is_eq(tree_height(ta), tree_height(tb))))

# Build the root-to-leaf path by consuming low bits while prepending them.
def path_bit(rem: Nat) -> Bool:
  match rem:
    case 0n:
      False{}
    case 1n+r:
      True{}

def index_path(height: Nat, +index: Nat, acc: List<&2, Bool>) -> List<&2, Bool>:
  match height:
    case 0n:
      acc
    case 1n+h:
      index_path(h, Nat.div(index, 2n), Con{path_bit(Nat.mod(index, 2n)), acc})

def tree_word(path: List<&2, Bool>, tree: WordTree) -> U32:
  match path tree:
    case Nil{} Empty{}:
      0
    case Nil{} Leaf{word}:
      word
    case Nil{} Fork{left, right}:
      0
    case Con{side, rest} Empty{}:
      0
    case Con{side, rest} Leaf{word}:
      0
    case Con{False{}, rest} Fork{left, right}:
      tree_word(rest, left)
    case Con{True{}, rest} Fork{left, right}:
      tree_word(rest, right)

def tree_set_word(path: List<&2, Bool>, value: U32, tree: WordTree) -> WordTree:
  match path tree:
    case Nil{} Empty{}:
      Empty{}
    case Nil{} Leaf{word}:
      Leaf{value}
    case Nil{} Fork{left, right}:
      Fork{left, right}
    case Con{side, rest} Empty{}:
      Empty{}
    case Con{side, rest} Leaf{word}:
      Leaf{word}
    case Con{False{}, rest} Fork{left, right}:
      Fork{tree_set_word(rest, value, left), right}
    case Con{True{}, rest} Fork{left, right}:
      Fork{left, tree_set_word(rest, value, right)}

def word_at_if(inside: Bool, tree: BitTree, index: Nat) -> U32:
  match inside:
    case False{}:
      0
    case True{}:
      match tree:
        case BT{root, words, capacity, height}:
          tree_word(index_path(height, index, Nil{}), root)

# Safe logical-word lookup; padding leaves are not externally addressable.
def word_at(+tree: BitTree, +index: Nat) -> U32:
  word_at_if(Nat.is_lt(index, word_count(tree)), tree, index)

def replace_word_if(inside: Bool, tree: BitTree, index: Nat, value: U32) -> BitTree:
  match inside:
    case False{}:
      tree
    case True{}:
      match tree:
        case BT{root, words, capacity, +height}:
          BT{tree_set_word(index_path(height, index, Nil{}), value, root), words, capacity, height}

# Safe logical-word update. This helper makes metadata preservation and
# unaffected-word laws direct to state.
def replace_word(+tree: BitTree, +index: Nat, value: U32) -> BitTree:
  replace_word_if(Nat.is_lt(index, word_count(tree)), tree, index, value)

def set_if(inside: Bool, +tree: BitTree, +bit: Nat) -> BitTree:
  match inside:
    case False{}:
      tree
    case True{}:
      +index = Nat.div(bit, 32n)
      +old = word_at(tree, index)
      replace_word(tree, index, BitWords.word_put(True{}, old, Nat.mod(bit, 32n)))

# Set one logical bit. Out-of-range indexes leave the tree unchanged.
def set(+tree: BitTree, +bit: Nat) -> BitTree:
  set_if(valid_bit(tree, bit), tree, bit)

def test_if(inside: Bool, +tree: BitTree, +bit: Nat) -> Bool:
  match inside:
    case False{}:
      False{}
    case True{}:
      BitWords.word_get(word_at(tree, Nat.div(bit, 32n)), Nat.mod(bit, 32n))

# Test one logical bit. Out-of-range indexes, including every index in the
# zero-word tree, return False{}.
def test(+tree: BitTree, +bit: Nat) -> Bool:
  test_if(valid_bit(tree, bit), tree, bit)

# Structural checker for the exact perfect-tree shape described by metadata.
# The two equal-sized subtrees are checked in parallel.
def shape_ok(+height: Nat, tree: WordTree) -> Bool:
  match height tree:
    case 0n Empty{}:
      False{}
    case 0n Leaf{word}:
      True{}
    case 0n Fork{left, right}:
      False{}
    case 1n+h Empty{}:
      False{}
    case 1n+h Leaf{word}:
      False{}
    case 1n+h Fork{left, right}:
      a b = shape_ok(h, left) shape_ok(h, right)
      Bool.and(a, b)

def empty_metadata_ok(words: Nat, capacity: Nat, height: Nat) -> Bool:
  Bool.and(Nat.is_eq(words, 0n), Bool.and(Nat.is_eq(capacity, 0n), Nat.is_eq(height, 0n)))

def nonempty_metadata_ok(root: WordTree, +words: Nat, +capacity: Nat, +height: Nat) -> Bool:
  Bool.and(
    Nat.is_gt(words, 0n),
    Bool.and(
      Nat.is_le(words, capacity),
      Bool.and(
        Nat.is_eq(capacity, Pow2.pow2t(height)),
        shape_ok(height, root))))

# Checks zero canonicality, logical bounds, power-of-two capacity, height, and
# exact tree shape. It does not require padding words to remain zero.
def well_formed(tree: BitTree) -> Bool:
  match tree:
    case BT{Empty{}, words, capacity, height}:
      empty_metadata_ok(words, capacity, height)
    case BT{root, words, capacity, height}:
      nonempty_metadata_ok(root, words, capacity, height)

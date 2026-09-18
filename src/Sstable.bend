import Base
import ./Keys.bend as Keys
import ./MemTable.bend as MemTable

# SSTables (Task 4): immutable sorted runs with Bloom filters.
# Build = fold insert-or-replace over MemTable entries (newest wins:
# memtable is newest-first, EQ replaces the older acc version).
# Lookup is linear first-match; binary search iff benchmarks demand it.

type Bloom is Data:
  Blm{bits: List<&2, Bool>, size: Nat}

type Table is Data:
  Tbl{entries: List<&2, MemTable.Entry>, filter: Bloom, nbits: Nat}

# --- Bloom allocator (Monkey-style: smaller/upper levels get more bits) ---
# Closed form pinned here; Dayan-exact coefficients are tuning follow-up.
def bloom_bits(level: Nat, est_keys: Nat) -> Nat:
  match level:
    case 0n:
      Nat.mul(est_keys, 20n)
    case 1n+m:
      match m:
        case 0n:
          Nat.mul(est_keys, 10n)
        case 1n+p:
          Nat.mul(est_keys, 5n)

# --- Local byte hash (duplicated 5-line fold; keeps Sstable independent) ---
def bhash(s: String, h: U32) -> U32:
  match s:
    case SNil{}:
      h
    case SCon{c, t}:
      bhash(t, U32.add(U32.mul(h, 31), Char.to_u32(c)))

def bhash_n(s: String, seed: U32, m: Nat) -> Nat:
  match m:
    case 0n:
      0n
    case 1n+p:
      Nat.mod(U32.to_nat(bhash(s, seed)), m)

# --- Bit array over List<Bool> (joint structural recursion, no fuel) ---
def bits_new(n: Nat) -> List<&2, Bool>:
  match n:
    case 0n:
      Nil{}
    case 1n+m:
      Con{False{}, bits_new(m)}

def bit_set(i: Nat, bits: List<&2, Bool>) -> List<&2, Bool>:
  match i bits:
    case 0n Nil{}:
      Nil{}
    case 0n Con{h, t}:
      Con{True{}, t}
    case 1n+m Nil{}:
      Nil{}
    case 1n+m Con{h, t}:
      Con{h, bit_set(m, t)}

def bit_get(i: Nat, bits: List<&2, Bool>) -> Bool:
  match i bits:
    case 0n Nil{}:
      False{}
    case 0n Con{h, t}:
      h
    case 1n+m Nil{}:
      False{}
    case 1n+m Con{h, t}:
      bit_get(m, t)

def bloom_new(+n: Nat) -> Bloom:
  Blm{bits_new(n), n}

def bloom_add(b: Bloom, +k: String) -> Bloom:
  match b:
    case Blm{bits, +size}:
      Blm{bit_set(bhash_n(k, 17, size), bit_set(bhash_n(k, 257, size), bits)), size}

def both(a: Bool, b: Bool) -> Bool:
  match a:
    case True{}:
      b
    case False{}:
      False{}

def bloom_test(b: Bloom, +k: String) -> Bool:
  match b:
    case Blm{+bits, +size}:
      both(bit_get(bhash_n(k, 17, size), bits), bit_get(bhash_n(k, 257, size), bits))

def table_bits(t: Table) -> Nat:
  match t:
    case Tbl{entries, filter, nbits}:
      nbits

def maybe_present(t: Table, +k: String) -> Bool:
  match t:
    case Tbl{entries, filter, nbits}:
      bloom_test(filter, k)

# --- Sorted insert-or-replace (newest wins on EQ) ---
# No pairs anywhere (pair-results can't be destructured): done/acc travel
# as separate params, decisions via leaves, recursion structural on rest.
def cmp_entry(e1: MemTable.Entry, e2: MemTable.Entry) -> Cmp:
  match e1:
    case MemTable.Entry{k1, v1}:
      match e2:
        case MemTable.Entry{k2, v2}:
          Keys.cmp(k1, k2)

def ins_done(done: Bool, c: Cmp) -> Bool:
  match done:
    case True{}:
      True{}
    case False{}:
      match c:
        case LT{}:
          True{}
        case EQ{}:
          True{}
        case GT{}:
          False{}

def ins_acc(done: Bool, c: Cmp, e: MemTable.Entry, h: MemTable.Entry, acc: List<&2, MemTable.Entry>) -> List<&2, MemTable.Entry>:
  match done:
    case True{}:
      acc
    case False{}:
      match c:
        case LT{}:
          List.append(&2, MemTable.Entry, acc, Con{e, Con{h, Nil{}}})
        case EQ{}:
          List.append(&2, MemTable.Entry, acc, Con{h, Nil{}})
        case GT{}:
          List.append(&2, MemTable.Entry, acc, Con{h, Nil{}})

def ins_go(rest: List<&2, MemTable.Entry>, +e: MemTable.Entry, +done: Bool, acc: List<&2, MemTable.Entry>) -> List<&2, MemTable.Entry>:
  match rest:
    case Nil{}:
      match done:
        case True{}:
          acc
        case False{}:
          List.append(&2, MemTable.Entry, acc, Con{e, Nil{}})
    case Con{+h, t}:
      match done:
        case True{}:
          List.append(&2, MemTable.Entry, acc, Con{h, t})
        case False{}:
          +c = cmp_entry(e, h)
          +nb = ins_done(done, c)
          +na = ins_acc(done, c, e, h, acc)
          ins_go(t, e, nb, na)

def insert_sorted(e: MemTable.Entry, sorted: List<&2, MemTable.Entry>) -> List<&2, MemTable.Entry>:
  ins_go(sorted, e, False{}, Nil{})

def build_go(entries: List<&2, MemTable.Entry>, acc: List<&2, MemTable.Entry>) -> List<&2, MemTable.Entry>:
  match entries:
    case Nil{}:
      acc
    case Con{e, t}:
      build_go(t, insert_sorted(e, acc))

def bloom_of(entries: List<&2, MemTable.Entry>, +blm: Bloom) -> Bloom:
  match entries:
    case Nil{}:
      blm
    case Con{e, t}:
      match e:
        case MemTable.Entry{key, val}:
          bloom_of(t, bloom_add(blm, key))

def build(+entries: List<&2, MemTable.Entry>, level: Nat, est_keys: Nat) -> Table:
  +nb = bloom_bits(level, est_keys)
  Tbl{build_go(entries, Nil{}), bloom_of(entries, bloom_new(nb)), nb}

def size_of(b: Bloom) -> Nat:
  match b:
    case Blm{bits, size}:
      size

# Lemma: bloom filter size is invariant under inserts (set flips bits only).
def bloom_size_stable(entries: List<&2, MemTable.Entry>, bits: List<&2, Bool>, +size: Nat) -> {size_of(bloom_of(entries, Blm{bits, size})) == size : Nat}:
  match entries:
    case Nil{}:
      {==}
    case Con{e, t}:
      match e:
        case MemTable.Entry{+key, val}:
          bloom_size_stable(t, bit_set(bhash_n(key, 17, size), bit_set(bhash_n(key, 257, size), bits)), size)

def lookup(t: Table, +k: String) -> Maybe<&2, String>:
  match t:
    case Tbl{entries, filter, nbits}:
      MemTable.get(MemTable.MT{entries}, k)

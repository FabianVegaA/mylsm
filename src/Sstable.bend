import Base
import ./Keys.bend as Keys
import ./MemTable.bend as MemTable
import ./BitTree.bend as BitTree
import ./SortedRun.bend as SortedRun

# SSTables (Task 4): immutable strict sorted runs with BitTree Bloom filters.
# `build` canonicalizes newest-first raw entries; `from_sorted_unique` trusts an
# already strict, unique run and deliberately performs no sorting.

type Bloom is Data:
  Blm{bits: BitTree.BitTree, size: Nat}

type Table is Data:
  Tbl{
    entries: List<&2, MemTable.Entry>,
    filter: Bloom,
    nbits: Nat,
    smallest: Maybe<&2, String>,
    largest: Maybe<&2, String>,
    count: Nat
  }

type Metadata is Data:
  Meta{smallest: Maybe<&2, String>, largest: Maybe<&2, String>, count: Nat}

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

# --- Local byte hash (kept stable for on-disk/rebuild compatibility) ---
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

# BitTree stores whole U32 words while Bloom.size preserves the exact logical
# bit count selected by bloom_bits.
def bit_words(n: Nat) -> Nat:
  match n:
    case 0n:
      0n
    case 1n+m:
      Nat.add(1n, Nat.div(m, 32n))

def bits_new(+n: Nat) -> BitTree.BitTree:
  BitTree.new(bit_words(n))

def bit_set(i: Nat, bits: BitTree.BitTree) -> BitTree.BitTree:
  BitTree.set(bits, i)

def bit_get(i: Nat, bits: BitTree.BitTree) -> Bool:
  BitTree.test(bits, i)

def bloom_new(+n: Nat) -> Bloom:
  Blm{bits_new(n), n}

def bloom_well_formed(b: Bloom) -> Bool:
  match b:
    case Blm{+bits, +size}:
      Bool.and(
        BitTree.well_formed(bits),
        Bool.and(
          Nat.is_eq(BitTree.word_count(bits), bit_words(size)),
          Nat.is_le(size, BitTree.bit_count(bits))))

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
    case Tbl{entries, filter, nbits, smallest, largest, count}:
      nbits

def maybe_present(t: Table, +k: String) -> Bool:
  match t:
    case Tbl{entries, filter, nbits, smallest, largest, count}:
      bloom_test(filter, k)

# --- Canonicalization and construction ---
# Keep the established API used by MergeIter/Compact, now backed by the shared
# SortedRun implementation. Input order is newest-first, so equal keys retain
# the first (newest) entry.
def cmp_entry(e1: MemTable.Entry, e2: MemTable.Entry) -> Cmp:
  SortedRun.entry_cmp(e1, e2)

def insert_sorted(e: MemTable.Entry, sorted: List<&2, MemTable.Entry>) -> List<&2, MemTable.Entry>:
  SortedRun.reference_insert(e, sorted)

def build_go(entries: List<&2, MemTable.Entry>, acc: List<&2, MemTable.Entry>) -> List<&2, MemTable.Entry>:
  SortedRun.reference_fold(entries, acc)

def bloom_of(entries: List<&2, MemTable.Entry>, +blm: Bloom) -> Bloom:
  match entries:
    case Nil{}:
      blm
    case Con{e, t}:
      match e:
        case MemTable.Entry{key, val}:
          bloom_of(t, bloom_add(blm, key))

def metadata_tail(entries: List<&2, MemTable.Entry>, +first: String, last: String, +count: Nat) -> Metadata:
  match entries:
    case Nil{}:
      Meta{Some{first}, Some{last}, count}
    case Con{MemTable.Entry{key, val}, rest}:
      metadata_tail(rest, first, key, Nat.add(count, 1n))

def metadata(entries: List<&2, MemTable.Entry>) -> Metadata:
  match entries:
    case Nil{}:
      Meta{None{}, None{}, 0n}
    case Con{MemTable.Entry{+key, val}, rest}:
      metadata_tail(rest, key, key, 1n)

def from_sorted_unique_est_meta(+entries: List<&2, MemTable.Entry>, level: Nat, est_keys: Nat, meta: Metadata) -> Table:
  match meta:
    case Meta{smallest, largest, count}:
      +nb = bloom_bits(level, est_keys)
      Tbl{entries, bloom_of(entries, bloom_new(nb)), nb, smallest, largest, count}

def from_sorted_unique_meta(+entries: List<&2, MemTable.Entry>, level: Nat, meta: Metadata) -> Table:
  match meta:
    case Meta{smallest, largest, +count}:
      +nb = bloom_bits(level, count)
      Tbl{entries, bloom_of(entries, bloom_new(nb)), nb, smallest, largest, count}

def from_sorted_unique(+entries: List<&2, MemTable.Entry>, level: Nat) -> Table:
  from_sorted_unique_meta(entries, level, metadata(entries))

def build_sorted(+entries: List<&2, MemTable.Entry>, level: Nat, est_keys: Nat) -> Table:
  from_sorted_unique_est_meta(entries, level, est_keys, metadata(entries))

def build(+entries: List<&2, MemTable.Entry>, level: Nat, est_keys: Nat) -> Table:
  +effective = Nat.max(est_keys, List.length(&2, MemTable.Entry, entries))
  build_sorted(SortedRun.sort_newest(entries), level, effective)

# Metadata accessors keep clients independent of the Tbl field layout.
def table_smallest(t: Table) -> Maybe<&2, String>:
  match t:
    case Tbl{entries, filter, nbits, smallest, largest, count}:
      smallest

def table_largest(t: Table) -> Maybe<&2, String>:
  match t:
    case Tbl{entries, filter, nbits, smallest, largest, count}:
      largest

def table_count(t: Table) -> Nat:
  match t:
    case Tbl{entries, filter, nbits, smallest, largest, count}:
      count

# Open bridge: metadata is matched explicitly so the Bloom schedule projects
# through `build` without relying on reduction of an open entry list.
def table_bits_from_meta(+entries: List<&2, MemTable.Entry>, level: Nat, est_keys: Nat, meta: Metadata) -> {table_bits(from_sorted_unique_est_meta(entries, level, est_keys, meta)) == bloom_bits(level, est_keys) : Nat}:
  match meta:
    case Meta{smallest, largest, count}:
      {==}

def table_bits_build(+entries: List<&2, MemTable.Entry>, level: Nat, est_keys: Nat) -> {table_bits(build(entries, level, est_keys)) == bloom_bits(level, Nat.max(est_keys, List.length(&2, MemTable.Entry, entries))) : Nat}:
  +effective = Nat.max(est_keys, List.length(&2, MemTable.Entry, entries))
  table_bits_from_meta(SortedRun.sort_newest(entries), level, effective, metadata(SortedRun.sort_newest(entries)))


def ranges_disjoint(+a: Table, +b: Table) -> Bool:
  SortedRun.range_disjoint_bounds(table_smallest(a), table_largest(a), table_smallest(b), table_largest(b))

def size_of(b: Bloom) -> Nat:
  match b:
    case Blm{bits, size}:
      size

# Bloom insertions only set tree bits and preserve the exact logical size.
def bloom_size_stable(entries: List<&2, MemTable.Entry>, bits: BitTree.BitTree, +size: Nat) -> {size_of(bloom_of(entries, Blm{bits, size})) == size : Nat}:
  match entries:
    case Nil{}:
      {==}
    case Con{e, t}:
      match e:
        case MemTable.Entry{+key, val}:
          bloom_size_stable(t, bit_set(bhash_n(key, 17, size), bit_set(bhash_n(key, 257, size), bits)), size)

def lookup(t: Table, +k: String) -> Maybe<&2, String>:
  match t:
    case Tbl{entries, filter, nbits, smallest, largest, count}:
      MemTable.get(MemTable.MT{entries}, k)

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
    count: Nat,
    chunks: List<&2, List<&2, MemTable.Entry>>,
    blocks: List<&2, String>
  }

def block_entries() -> Nat:
  64n

def chunk_go(fuel: Nat, +entries: List<&2, MemTable.Entry>, +cur: List<&2, MemTable.Entry>, room: Nat, acc: List<&2, List<&2, MemTable.Entry>>) -> List<&2, List<&2, MemTable.Entry>>:
  match fuel:
    case 0n:
      List.reverse(&2, List<&2, MemTable.Entry>, Con{List.reverse(&2, MemTable.Entry, cur), acc})
    case 1n+f:
      match entries:
        case Nil{}:
          List.reverse(&2, List<&2, MemTable.Entry>, Con{List.reverse(&2, MemTable.Entry, cur), acc})
        case Con{e, t}:
          match room:
            case 0n:
              chunk_go(f, t, Con{e, Nil{}}, Nat.sub(block_entries(), 1n), Con{List.reverse(&2, MemTable.Entry, cur), acc})
            case 1n+r:
              chunk_go(f, t, Con{e, cur}, r, acc)

def chunk(+entries: List<&2, MemTable.Entry>) -> List<&2, List<&2, MemTable.Entry>>:
  match entries:
    case Nil{}:
      Nil{}
    case Con{e, t}:
      chunk_go(List.length(&2, MemTable.Entry, entries), t, Con{e, Nil{}}, Nat.sub(block_entries(), 1n), Nil{})

def chunk_head_key(+c: List<&2, MemTable.Entry>) -> Maybe<&2, String>:
  match c:
    case Nil{}:
      None{}
    case Con{MemTable.Entry{key, val}, t}:
      Some{key}

def block_cons_acc(head: Maybe<&2, String>, acc: List<&2, String>) -> List<&2, String>:
  match head:
    case None{}:
      acc
    case Some{k}:
      Con{k, acc}

def block_keys(+chunks: List<&2, List<&2, MemTable.Entry>>, acc: List<&2, String>) -> List<&2, String>:
  match chunks:
    case Nil{}:
      List.reverse(&2, String, acc)
    case Con{c, t}:
      block_keys(t, block_cons_acc(chunk_head_key(c), acc))

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

# --- U32->Nat bridges that stay checker-tractable ---
# The Bend checker does not share across sequentially-chained U32.mul terms:
# `U32.to_nat` applied to a hash accumulated over 4+ bytes diverges in
# `{==}` elaboration (runtime is unaffected). The bridges below therefore
# never materialize a chained U32 as a Nat: each `to_nat` covers at most two
# U32 ops (shift+mask on the ORIGINAL word — parallel, shared), and all
# accumulation happens in small-Nat land. Both are EXACT (no semantic
# change): bytes are the base-256 digits of the word (Horner), so
# u32_to_nat_exact(w) == U32.to_nat(w) and bhash_n computes the same mod.
def u32_byte(+w: U32, shift: Nat) -> Nat:
  U32.to_nat(U32.and(U32.shrn(w, shift), 255))

def u32_to_nat_exact(+w: U32) -> Nat:
  +b0 = u32_byte(w, 24n)
  +b1 = u32_byte(w, 16n)
  +b2 = u32_byte(w, 8n)
  +b3 = u32_byte(w, 0n)
  Nat.add(Nat.mul(b0, Nat.mul(Nat.mul(256n, 256n), 256n)), Nat.add(Nat.mul(b1, Nat.mul(256n, 256n)), Nat.add(Nat.mul(b2, 256n), b3)))

def bhash_n_pos(+s: String, +seed: U32, +m: Nat) -> Nat:
  +w = bhash(s, seed)
  +a0 = Nat.mod(u32_byte(w, 24n), m)
  +a1 = Nat.mod(Nat.add(Nat.mul(a0, 256n), u32_byte(w, 16n)), m)
  +a2 = Nat.mod(Nat.add(Nat.mul(a1, 256n), u32_byte(w, 8n)), m)
  Nat.mod(Nat.add(Nat.mul(a2, 256n), u32_byte(w, 0n)), m)

def bhash_n(s: String, seed: U32, m: Nat) -> Nat:
  match m:
    case 0n:
      0n
    case 1n+p:
      bhash_n_pos(s, seed, m)

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
    case Tbl{entries, filter, nbits, smallest, largest, count, chunks, blocks}:
      nbits

def maybe_present(t: Table, +k: String) -> Bool:
  match t:
    case Tbl{entries, filter, nbits, smallest, largest, count, chunks, blocks}:
      bloom_test(filter, k)

# --- Canonicalization and construction ---
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
      Tbl{entries, bloom_of(entries, bloom_new(nb)), nb, smallest, largest, count, chunk(entries), block_keys(chunk(entries), Nil{})}

def from_sorted_unique_meta(+entries: List<&2, MemTable.Entry>, level: Nat, meta: Metadata) -> Table:
  match meta:
    case Meta{smallest, largest, +count}:
      +nb = bloom_bits(level, count)
      Tbl{entries, bloom_of(entries, bloom_new(nb)), nb, smallest, largest, count, chunk(entries), block_keys(chunk(entries), Nil{})}

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
    case Tbl{entries, filter, nbits, smallest, largest, count, chunks, blocks}:
      smallest

def table_largest(t: Table) -> Maybe<&2, String>:
  match t:
    case Tbl{entries, filter, nbits, smallest, largest, count, chunks, blocks}:
      largest

def table_count(t: Table) -> Nat:
  match t:
    case Tbl{entries, filter, nbits, smallest, largest, count, chunks, blocks}:
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

# Block-scoped lookup. Checker constraints (proven by scratch experiments):
# multi-scrutinee matches follow declaration order, and only Nat answers flow
# through match arms — so selection returns an index, picked up by chunk_at_go.
def pick_ix(bt: List<&2, String>, ct: List<&2, List<&2, MemTable.Entry>>, ix: Nat, +k: String, order: Cmp) -> Nat:
  match bt ct order:
    case _ _ GT{}:
      Nat.sub(ix, 1n)
    case Nil{} _ _:
      ix
    case _ Nil{} _:
      ix
    case Con{b2, bt2} Con{d2, ct2} LT{}:
      pick_ix(bt2, ct2, Nat.add(ix, 1n), k, Keys.cmp(b2, k))
    case Con{b2, bt2} Con{d2, ct2} EQ{}:
      ix

def chunk_at_go(fuel: Nat, +chunks: List<&2, List<&2, MemTable.Entry>>, ix: Nat) -> List<&2, MemTable.Entry>:
  match fuel chunks:
    case 0n _:
      Nil{}
    case 1n+f Nil{}:
      Nil{}
    case 1n+f Con{c, t}:
      match ix:
        case 0n:
          c
        case 1n+p:
          chunk_at_go(f, t, p)

def chunk_at(+chunks: List<&2, List<&2, MemTable.Entry>>, ix: Nat) -> List<&2, MemTable.Entry>:
  chunk_at_go(List.length(&2, List<&2, MemTable.Entry>, chunks), chunks, ix)

def block_scan(+chunk: List<&2, MemTable.Entry>, +k: String) -> Maybe<&2, String>:
  MemTable.get(MemTable.MT{chunk}, k)

def block_pick(+chunks: List<&2, List<&2, MemTable.Entry>>, +blocks: List<&2, String>, +k: String) -> List<&2, MemTable.Entry>:
  match chunks blocks:
    case Nil{} _:
      Nil{}
    case _ Nil{}:
      Nil{}
    case Con{c, ct} Con{b, bt}:
      chunk_at(chunks, pick_ix(bt, ct, 0n, k, Keys.cmp(b, k)))

def block_finish(picked: List<&2, MemTable.Entry>, +entries: List<&2, MemTable.Entry>, +k: String) -> Maybe<&2, String>:
  match picked:
    case Nil{}:
      MemTable.get(MemTable.MT{entries}, k)
    case Con{e, t}:
      block_scan(Con{e, t}, k)

def hit_finish(picked: List<&2, MemTable.Entry>, +entries: List<&2, MemTable.Entry>, +k: String) -> Maybe<&2, Maybe<&2, String>>:
  match picked:
    case Nil{}:
      MemTable.get_hit(MemTable.MT{entries}, k)
    case Con{e, t}:
      MemTable.get_hit(MemTable.MT{Con{e, t}}, k)

def block_get_hit(t: Table, +k: String) -> Maybe<&2, Maybe<&2, String>>:
  match t:
    case Tbl{entries, filter, nbits, smallest, largest, count, chunks, blocks}:
      hit_finish(block_pick(chunks, blocks, k), entries, k)

def block_get(t: Table, +k: String) -> Maybe<&2, String>:
  match t:
    case Tbl{entries, filter, nbits, smallest, largest, count, chunks, blocks}:
      block_finish(block_pick(chunks, blocks, k), entries, k)

def lookup(t: Table, +k: String) -> Maybe<&2, String>:
  block_get(t, k)

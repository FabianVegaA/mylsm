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

def chunk_head_key(+xs: List<&2, MemTable.Entry>) -> Maybe<&2, String>:
  match xs:
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
def bhash(str: String, acc: U32) -> U32:
  match str:
    case SNil{}:
      acc
    case SCon{c, t}:
      bhash(t, U32.add(U32.mul(acc, 31), Char.to_u32(c)))

# --- U32->Nat bridges that stay checker-tractable ---
# The Bend checker does not share across sequentially-chained U32.mul terms:
# `U32.to_nat` applied to a hash accumulated over 4+ bytes diverges in
# `{==}` elaboration (runtime is unaffected). The bridges below therefore
# never materialize a chained U32 as a Nat: each `to_nat` covers at most two
# U32 ops (shift+mask on the ORIGINAL word — parallel, shared), and all
# accumulation happens in small-Nat land. Both are EXACT (no semantic
# change): bytes are the base-256 digits of the word (Horner), so
# u32_to_nat_exact(w) == U32.to_nat(w) and bhash_n computes the same mod.
def u32_byte(+word: U32, shift: Nat) -> Nat:
  U32.to_nat(U32.and(U32.shrn(word, shift), 255))

def u32_to_nat_exact(+word: U32) -> Nat:
  +b0 = u32_byte(word, 24n)
  +b1 = u32_byte(word, 16n)
  +b2 = u32_byte(word, 8n)
  +b3 = u32_byte(word, 0n)
  Nat.add(Nat.mul(b0, Nat.mul(Nat.mul(256n, 256n), 256n)), Nat.add(Nat.mul(b1, Nat.mul(256n, 256n)), Nat.add(Nat.mul(b2, 256n), b3)))

def bhash_n_pos(+str: String, +seed: U32, +mod: Nat) -> Nat:
  +w = bhash(str, seed)
  +a0 = Nat.mod(u32_byte(w, 24n), mod)
  +a1 = Nat.mod(Nat.add(Nat.mul(a0, 256n), u32_byte(w, 16n)), mod)
  +a2 = Nat.mod(Nat.add(Nat.mul(a1, 256n), u32_byte(w, 8n)), mod)
  Nat.mod(Nat.add(Nat.mul(a2, 256n), u32_byte(w, 0n)), mod)

def bhash_n(str: String, seed: U32, mod: Nat) -> Nat:
  match mod:
    case 0n:
      0n
    case 1n+p:
      bhash_n_pos(str, seed, mod)

# BitTree stores whole U32 words while Bloom.size preserves the exact logical
# bit count selected by bloom_bits.
def bit_words(num: Nat) -> Nat:
  match num:
    case 0n:
      0n
    case 1n+m:
      Nat.add(1n, Nat.div(m, 32n))

def bits_new(+num: Nat) -> BitTree.BitTree:
  BitTree.new(bit_words(num))

def bit_set(idx: Nat, bits: BitTree.BitTree) -> BitTree.BitTree:
  BitTree.set(bits, idx)

def bit_get(idx: Nat, bits: BitTree.BitTree) -> Bool:
  BitTree.test(bits, idx)

def bloom_new(+num: Nat) -> Bloom:
  Blm{bits_new(num), num}

def bloom_well_formed(bloom: Bloom) -> Bool:
  match bloom:
    case Blm{+bits, +size}:
      Bool.and(
        BitTree.well_formed(bits),
        Bool.and(
          Nat.is_eq(BitTree.word_count(bits), bit_words(size)),
          Nat.is_le(size, BitTree.bit_count(bits))))

def bloom_add(bloom: Bloom, +key: String) -> Bloom:
  match bloom:
    case Blm{bits, +size}:
      Blm{bit_set(bhash_n(key, 17, size), bit_set(bhash_n(key, 257, size), bits)), size}

def both(lhs: Bool, rhs: Bool) -> Bool:
  match lhs:
    case True{}:
      rhs
    case False{}:
      False{}

def bloom_test(bloom: Bloom, +key: String) -> Bool:
  match bloom:
    case Blm{+bits, +size}:
      both(bit_get(bhash_n(key, 17, size), bits), bit_get(bhash_n(key, 257, size), bits))

def table_bits(tab: Table) -> Nat:
  match tab:
    case Tbl{entries, filter, nbits, smallest, largest, count, chunks, blocks}:
      nbits

def maybe_present(tab: Table, +key: String) -> Bool:
  match tab:
    case Tbl{entries, filter, nbits, smallest, largest, count, chunks, blocks}:
      bloom_test(filter, key)

# --- Parallel probe counters (Task 1): sequential leaf, two-way fork, `!` gate ---
# Single probe as 0/1 for counting.
def probe_hit_if(present: Bool) -> Nat:
  match present:
    case True{}:
      1n
    case False{}:
      0n

# Count matching probes sequentially.
def probe_hit(+tab: Table, +key: String) -> Nat:
  probe_hit_if(maybe_present(tab, key))

# Sequential probe count over a probe list.
def probe_count_seq(+probes: List<&2, String>, +tab: Table) -> Nat:
  match probes:
    case Nil{}:
      0n
    case Con{+q, t}:
      Nat.add(probe_count_seq(t, tab), probe_hit(tab, q))

# Two-way parallel probe count; halves share no state.
def probe_count_par(+probes: List<&2, String>, +tab: Table) -> Nat:
  +half = Nat.div(List.length(&2, String, probes), 2n)
  left right = probe_count_seq(List.take(&2, String, probes, half), tab) probe_count_seq(List.drop(&2, String, probes, half), tab)
  Nat.add(left, right)

# Bang gate: GPU pays only with enough probes to fill lanes.
def probe_count_bang_gate(+num: Nat) -> Bool:
  Nat.is_le(16384n, num)

# Pick CPU-pool or GPU execution for the same fork tree.
def probe_count_pick(gate: Bool, +probes: List<&2, String>, +tab: Table) -> Nat:
  match gate:
    case False{}:
      probe_count_par(probes, tab)
    case True{}:
      probe_count_par!(probes, tab)

# Size-gated entry point for parallel probe counting.
def probe_count_auto(+probes: List<&2, String>, +tab: Table) -> Nat:
  probe_count_pick(probe_count_bang_gate(List.length(&2, String, probes)), probes, tab)

# --- Canonicalization and construction ---
def bloom_of(entries: List<&2, MemTable.Entry>, +blm: Bloom) -> Bloom:
  match entries:
    case Nil{}:
      blm
    case Con{e, t}:
      match e:
        case MemTable.Entry{key, val}:
          bloom_of(t, bloom_add(blm, key))

def bloom_union_trees(+abits: BitTree.BitTree, +bbits: BitTree.BitTree, size: Nat) -> Bloom:
  match abits:
    case BitTree.BT{aroot, awords, acap, aheight}:
      match bbits:
        case BitTree.BT{broot, bwords, bcap, bheight}:
          Blm{BitTree.BT{BitTree.union_bits(aroot, broot), awords, acap, aheight}, size}

def bloom_union(ba: Bloom, bb: Bloom) -> Bloom:
  match ba:
    case Blm{abits, asize}:
      match bb:
        case Blm{bbits, bsize}:
          bloom_union_trees(abits, bbits, Nat.max(asize, bsize))

def bloom_of_chunk(+chunk: List<&2, MemTable.Entry>, +nb: Nat) -> Bloom:
  bloom_of(chunk, bloom_new(nb))

# Two-half parallel build (spike 1): one spawn, one union. Sequential below.
def bloom_of_par(+entries: List<&2, MemTable.Entry>, +nb: Nat) -> Bloom:
  +half = Nat.div(List.length(&2, MemTable.Entry, entries), 2n)
  left right = bloom_of_chunk(List.take(&2, MemTable.Entry, entries, half), nb) bloom_of_chunk(List.drop(&2, MemTable.Entry, entries, half), nb)
  bloom_union(left, right)

# --- Four-chunk parallel build (Task 2): two-level fork, three unions ---
# Third chunk slice as take-after-drop.
def chunk_third(+entries: List<&2, MemTable.Entry>, +skip: Nat, +take: Nat) -> List<&2, MemTable.Entry>:
  List.take(&2, MemTable.Entry, List.drop(&2, MemTable.Entry, entries, skip), take)

# Four-way chunk build with a two-level fork tree.
def bloom_of_chunks(+entries: List<&2, MemTable.Entry>, +nb: Nat) -> Bloom:
  +num = List.length(&2, MemTable.Entry, entries)
  +q = Nat.div(num, 4n)
  a b = bloom_of_chunk(List.take(&2, MemTable.Entry, entries, q), nb) bloom_of_chunk(chunk_third(entries, q, q), nb)
  c d = bloom_of_chunk(chunk_third(entries, Nat.mul(q, 2n), q), nb) bloom_of_chunk(List.drop(&2, MemTable.Entry, entries, Nat.mul(q, 3n)), nb)
  bloom_union(bloom_union(a, b), bloom_union(c, d))

# Bang gate: GPU pays only with enough entries to feed lanes.
def bloom_bang_gate(+num: Nat) -> Bool:
  Nat.is_le(8192n, num)

# Pick CPU-pool or GPU execution for the same chunk tree.
def bloom_of_pick(gate: Bool, +entries: List<&2, MemTable.Entry>, +nb: Nat) -> Bloom:
  match gate:
    case False{}:
      bloom_of_chunks(entries, nb)
    case True{}:
      bloom_of_chunks!(entries, nb)

# Size-gated `!` entry point: the bang fires only at >= 8192 entries, where
# every flush in the durable write path lands (frozen merge of 4096 + 4096).
def bloom_of_bang(+entries: List<&2, MemTable.Entry>, +nb: Nat) -> Bloom:
  bloom_of_pick(bloom_bang_gate(List.length(&2, MemTable.Entry, entries)), entries, nb)

# Size-gated entry point: parallel pays only above 2048 entries.
# FORMAL LIMITATION (2026-09-26): production stays on the CPU-pool chunk
# tree. Wiring this to bloom_of_bang activates the GPU runtime for every
# native binary, and the Bend 2.0.28 Metal runtime faults recovery at scale
# (20485-write WAL replay: `memory fault (machine stack overflow?)` with GPU
# on, full pass with --gpu off; 4097-write recovery passes either way). The
# write phase with bangs measures on par with CPU (100k: 10649 ms GPU vs
# 10902 ms CPU pool), but end-to-end GPU runs cannot pass recovery gates
# until the runtime issue is fixed upstream. bloom_of_bang stays available
# for opt-in write-phase measurement; flip this branch to re-enable.
def bloom_pick(small: Bool, +entries: List<&2, MemTable.Entry>, +nb: Nat) -> Bloom:
  match small:
    case True{}:
      bloom_of(entries, bloom_new(nb))
    case False{}:
      bloom_of_chunks(entries, nb)

def bloom_of_auto(+entries: List<&2, MemTable.Entry>, +nb: Nat) -> Bloom:
  bloom_pick(Nat.is_lt(List.length(&2, MemTable.Entry, entries), 2048n), entries, nb)

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
      Tbl{entries, bloom_of_auto(entries, nb), nb, smallest, largest, count, chunk(entries), block_keys(chunk(entries), Nil{})}

def from_sorted_unique_meta(+entries: List<&2, MemTable.Entry>, level: Nat, meta: Metadata) -> Table:
  match meta:
    case Meta{smallest, largest, +count}:
      +nb = bloom_bits(level, count)
      Tbl{entries, bloom_of_auto(entries, nb), nb, smallest, largest, count, chunk(entries), block_keys(chunk(entries), Nil{})}

def from_sorted_unique(+entries: List<&2, MemTable.Entry>, level: Nat) -> Table:
  from_sorted_unique_meta(entries, level, metadata(entries))

def build_sorted(+entries: List<&2, MemTable.Entry>, level: Nat, est_keys: Nat) -> Table:
  from_sorted_unique_est_meta(entries, level, est_keys, metadata(entries))

def build(+entries: List<&2, MemTable.Entry>, level: Nat, est_keys: Nat) -> Table:
  +effective = Nat.max(est_keys, List.length(&2, MemTable.Entry, entries))
  build_sorted(SortedRun.sort_newest(entries), level, effective)

# Metadata accessors keep clients independent of the Tbl field layout.
def table_smallest(tab: Table) -> Maybe<&2, String>:
  match tab:
    case Tbl{entries, filter, nbits, smallest, largest, count, chunks, blocks}:
      smallest

def table_largest(tab: Table) -> Maybe<&2, String>:
  match tab:
    case Tbl{entries, filter, nbits, smallest, largest, count, chunks, blocks}:
      largest

def table_count(tab: Table) -> Nat:
  match tab:
    case Tbl{entries, filter, nbits, smallest, largest, count, chunks, blocks}:
      count

# Total table identity for the read cache: smallest|largest|count.
def opt_name(+opt: Maybe<&2, String>) -> String:
  match opt:
    case None{}:
      "<none>"
    case Some{s}:
      s

def table_id(tab: Table) -> String:
  match tab:
    case Tbl{entries, filter, nbits, smallest, largest, count, chunks, blocks}:
      opt_name(smallest) ++ "|" ++ opt_name(largest) ++ "|" ++ Nat.show(count)

# Open bridge: metadata is matched explicitly so the Bloom schedule projects
# through `build` without relying on reduction of an open entry list.
def table_bits_from_meta(
  +entries: List<&2, MemTable.Entry>,
  level: Nat,
  est_keys: Nat,
  meta: Metadata,
) -> {table_bits(from_sorted_unique_est_meta(entries, level, est_keys, meta)) == bloom_bits(level, est_keys) : Nat}:
  match meta:
    case Meta{smallest, largest, count}:
      {==}

def table_bits_build(
  +entries: List<&2, MemTable.Entry>,
  level: Nat,
  est_keys: Nat,
) -> {table_bits(build(entries, level, est_keys)) == bloom_bits(level, Nat.max(est_keys, List.length(&2, MemTable.Entry, entries))) : Nat}:
  +effective = Nat.max(est_keys, List.length(&2, MemTable.Entry, entries))
  table_bits_from_meta(SortedRun.sort_newest(entries), level, effective, metadata(SortedRun.sort_newest(entries)))


def ranges_disjoint(+ta: Table, +tb: Table) -> Bool:
  SortedRun.range_disjoint_bounds(table_smallest(ta), table_largest(ta), table_smallest(tb), table_largest(tb))

def size_of(bloom: Bloom) -> Nat:
  match bloom:
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
def pick_ix(bt: List<&2, String>, ct: List<&2, List<&2, MemTable.Entry>>, ix: Nat, +key: String, order: Cmp) -> Nat:
  match bt ct order:
    case _ _ GT{}:
      Nat.sub(ix, 1n)
    case Nil{} _ _:
      ix
    case _ Nil{} _:
      ix
    case Con{b2, bt2} Con{d2, ct2} LT{}:
      pick_ix(bt2, ct2, Nat.add(ix, 1n), key, Keys.cmp(b2, key))
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

def block_scan(+chunk: List<&2, MemTable.Entry>, +key: String) -> Maybe<&2, String>:
  MemTable.get(MemTable.MT{chunk}, key)

def block_pick(+chunks: List<&2, List<&2, MemTable.Entry>>, +blocks: List<&2, String>, +key: String) -> List<&2, MemTable.Entry>:
  match chunks blocks:
    case Nil{} _:
      Nil{}
    case _ Nil{}:
      Nil{}
    case Con{c, ct} Con{b, bt}:
      chunk_at(chunks, pick_ix(bt, ct, 0n, key, Keys.cmp(b, key)))

def block_finish(picked: List<&2, MemTable.Entry>, +entries: List<&2, MemTable.Entry>, +key: String) -> Maybe<&2, String>:
  match picked:
    case Nil{}:
      MemTable.get(MemTable.MT{entries}, key)
    case Con{e, t}:
      block_scan(Con{e, t}, key)

def hit_finish(picked: List<&2, MemTable.Entry>, +entries: List<&2, MemTable.Entry>, +key: String) -> Maybe<&2, Maybe<&2, String>>:
  match picked:
    case Nil{}:
      MemTable.get_hit(MemTable.MT{entries}, key)
    case Con{e, t}:
      MemTable.get_hit(MemTable.MT{Con{e, t}}, key)

def block_get_hit(tab: Table, +key: String) -> Maybe<&2, Maybe<&2, String>>:
  match tab:
    case Tbl{entries, filter, nbits, smallest, largest, count, chunks, blocks}:
      hit_finish(block_pick(chunks, blocks, key), entries, key)

def block_get(tab: Table, +key: String) -> Maybe<&2, String>:
  match tab:
    case Tbl{entries, filter, nbits, smallest, largest, count, chunks, blocks}:
      block_finish(block_pick(chunks, blocks, key), entries, key)

def lookup(tab: Table, +key: String) -> Maybe<&2, String>:
  block_get(tab, key)

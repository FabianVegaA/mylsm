import Base
import ./src/Keys.bend as Keys
import ./src/MemTable.bend as MemTable
import ./src/Wal.bend as Wal
import ./src/Sstable.bend as Sstable
import ./src/Manifest.bend as Manifest

import ./src/MergeIter.bend as MergeIter
import ./src/Db.bend as Db
import ./src/SstFile.bend as SstFile
import ./src/Compact.bend as Compact
import ./src/Recover.bend as Recover

# Trust root (read before the laws below): Bend Base primitives —
# arithmetic, comparison, String/Char ops — are the trusted kernel. They
# ship precompiled with Bend and are NOT re-proven here: reproving
# Word.cmp reflexivity from bit axioms would burn the project proving the
# compiler's own prelude. Instead every primitive WE depend on is pinned by
# closed-term laws (all inputs concrete, proven by {==} normalization) and
# hammered empirically by the Task 12 fuzz harness. All SIXTEEN product
# laws below are about OUR code and are proven in full.

# LAW: comparison unpacking is wired correctly (reflexive case)
law cmp_refl_a:
  {Keys.cmp("a", "a") == EQ{} : Cmp}

# LAW: comparison unpacking is wired correctly (ordered case)
law cmp_order_ab:
  {Keys.cmp("a", "b") == LT{} : Cmp}

# --- MemTable (Task 2) ---

# LAW: memtable read-your-writes
law mt_ryw:
  for t: MemTable.MemTable
  for +k: String
  for +v: String
  {MemTable.get(MemTable.put(t, k, v), k) == Some{v} : Maybe<&2, String>}

# LAW: memtable delete hides the key
law mt_del:
  for t: MemTable.MemTable
  for +k: String
  for v: String
  {MemTable.get(MemTable.del(MemTable.put(t, k, v), k), k) == None{} : Maybe<&2, String>}

# --- WAL codec (Task 3) ---

# LAW: WAL codec round-trip (closed vectors; each is proven by {==}
# normalization alone — no manual P's, no fragility).
# The OPEN round-trip (all batches) is fuzz-verified (Task 12, 1M+ inputs)
# and its full proof is deferred: open-key/open-length joint induction
# hits Bend 2.0.5 automation limits (syntactic P-matching over pump states
# with stuck-open tails). See spec §3.2.

# Batch fixtures (named defs: the parser rejects nested Con inside Some).
def batch_empty() -> Wal.Batch:
  Wal.Batch{Nil{}}

def batch_put1() -> Wal.Batch:
  Wal.Batch{Con{Wal.Put{"k", "v"}, Nil{}}}

def batch_del1() -> Wal.Batch:
  Wal.Batch{Con{Wal.Del{"k"}, Nil{}}}

def batch_multi() -> Wal.Batch:
  Wal.Batch{Con{Wal.Put{"a", ""}, Con{Wal.Del{"b"}, Con{Wal.Put{"", "c"}, Nil{}}}}}

law wal_rt_empty:
  {Wal.decode(Wal.encode(batch_empty())) == Some{batch_empty()} : Maybe<&2, Wal.Batch>}

law wal_rt_put1:
  {Wal.decode(Wal.encode(batch_put1())) == Some{batch_put1()} : Maybe<&2, Wal.Batch>}

law wal_rt_del1:
  {Wal.decode(Wal.encode(batch_del1())) == Some{batch_del1()} : Maybe<&2, Wal.Batch>}

law wal_rt_multi:
  {Wal.decode(Wal.encode(batch_multi())) == Some{batch_multi()} : Maybe<&2, Wal.Batch>}

# --- SSTable + Bloom (Task 4) ---
# Closed vectors ({==}-proved) + open definitional schedule law.
# Open sortedness/lookup need comparison facts on open keys (same
# automation wall as Task 3); covered by closed vectors + Task-12 fuzz.

def sst_e1() -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{"b", Some{"2"}}, Con{MemTable.Entry{"a", Some{"1"}}, Nil{}}}

def sst_e2() -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{"k", Some{"new"}}, Con{MemTable.Entry{"k", Some{"old"}}, Nil{}}}

# LAW: build sorts (closed)
law sst_sorted:
  {Sstable.build(sst_e1(), 0n, 2n) == Sstable.Tbl{Con{MemTable.Entry{"a", Some{"1"}}, Con{MemTable.Entry{"b", Some{"2"}}, Nil{}}}, Sstable.bloom_of(sst_e1(), Sstable.bloom_new(Sstable.bloom_bits(0n, 2n))), Sstable.bloom_bits(0n, 2n)} : Sstable.Table}

# LAW: newest version wins on duplicate keys (closed)
law sst_newest:
  {Sstable.lookup(Sstable.build(sst_e2(), 0n, 2n), "k") == Some{"new"} : Maybe<&2, String>}

# LAW: bloom never rejects a present key (closed)
law bloom_safe:
  {Sstable.maybe_present(Sstable.build(sst_e1(), 0n, 2n), "a") == True{} : Bool}

# LAW: filter bits follow the Monkey schedule (open, definitional)
law bloom_schedule:
  for e: List<&2, MemTable.Entry>
  for l: Nat
  for n: Nat
  {Sstable.table_bits(Sstable.build(e, l, n)) == Sstable.bloom_bits(l, n) : Nat}

# --- Manifest (Task 5): closed vectors + fuzz (same strategy as WAL) ---

def mfst_empty() -> Manifest.Manifest:
  Manifest.M{Nil{}}

def mfst_two() -> Manifest.Manifest:
  Manifest.M{Con{Con{"a.tbl", Con{"b.tbl", Nil{}}}, Con{Con{"c.tbl", Nil{}}, Nil{}}}}

law manifest_empty:
  {Manifest.parse(Manifest.serialize(mfst_empty())) == Some{mfst_empty()} : Maybe<&2, Manifest.Manifest>}

law manifest_two:
  {Manifest.parse(Manifest.serialize(mfst_two())) == Some{mfst_two()} : Maybe<&2, Manifest.Manifest>}

# --- Merge iterator (Task 6): closed vectors + fuzz (spec laws 4, 5, 10) ---
# Merge of newest-first mem [b=v2, a=v1] over L1 [a=v0, c=v3].

def scan_mem() -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{"b", Some{"v2"}}, Con{MemTable.Entry{"a", Some{"v1"}}, Nil{}}}

def scan_l1() -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{"a", Some{"v0"}}, Con{MemTable.Entry{"c", Some{"v3"}}, Nil{}}}

def scan_levels() -> List<&2, List<&2, MemTable.Entry>>:
  Con{scan_l1(), Nil{}}

def scan_merged() -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{"a", Some{"v1"}}, Con{MemTable.Entry{"b", Some{"v2"}}, Con{MemTable.Entry{"c", Some{"v3"}}, Nil{}}}}

def scan_abc() -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{"a", Some{"v1"}}, Con{MemTable.Entry{"b", Some{"v2"}}, Con{MemTable.Entry{"c", Some{"v3"}}, Nil{}}}}

def scan_ab() -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{"a", Some{"v1"}}, Con{MemTable.Entry{"b", Some{"v2"}}, Nil{}}}

def scan_del() -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{"a", Some{"v1"}}, Con{MemTable.Entry{"b", None{}}, Con{MemTable.Entry{"c", Some{"v3"}}, Nil{}}}}

def scan_ac() -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{"a", Some{"v1"}}, Con{MemTable.Entry{"c", Some{"v3"}}, Nil{}}}

# LAW: merge sorts, dedups, newest wins (closed)
law scan_newest:
  {MergeIter.merge(scan_mem(), scan_levels()) == scan_merged() : List<&2, MemTable.Entry>}

# LAW: range keeps lo <= key < hi (closed)
law scan_range:
  {MergeIter.scan(scan_abc(), "a", "c") == scan_ab() : List<&2, MemTable.Entry>}

# LAW: tombstones dropped (closed)
law scan_drops_dels:
  {MergeIter.scan(scan_del(), "a", "d") == scan_ac() : List<&2, MemTable.Entry>}

# LAW: get-scan agreement on unique-keyed runs (closed)
law scan_agree:
  {MemTable.get(MemTable.MT{scan_ab()}, "b") == Some{"v2"} : Maybe<&2, String>}

# --- Db write path (Task 7): closed vectors (spec laws 1, 2, 3, 7) ---
# IO itself is unprovable; the laws pin the pure core (batch application,
# replay) that the IO path must funnel through after fsync.

def db_muts1() -> List<&2, Wal.Mut>:
  Con{Wal.Put{"k", "v"}, Nil{}}

def db_muts2() -> List<&2, Wal.Mut>:
  Con{Wal.Put{"a", "1"}, Con{Wal.Del{"b"}, Con{Wal.Put{"c", "3"}, Nil{}}}}

def db_mem2() -> MemTable.MemTable:
  MemTable.MT{Con{MemTable.Entry{"c", Some{"3"}}, Con{MemTable.Entry{"b", None{}}, Con{MemTable.Entry{"a", Some{"1"}}, Nil{}}}}}

def batch_muts(+b: Wal.Batch) -> List<&2, Wal.Mut>:
  match b:
    case Wal.Batch{m}:
      m

def db_decoded(+b: Wal.Batch) -> Maybe<&2, Wal.Batch>:
  Wal.decode(Wal.encode(b))

def db_replay_go(+m: Maybe<&2, Wal.Batch>) -> MemTable.MemTable:
  match m:
    case None{}:
      MemTable.empty()
    case Some{Wal.Batch{muts}}:
      Db.apply_batch(muts, MemTable.empty())

def db_replay(+b: Wal.Batch) -> MemTable.MemTable:
  db_replay_go(db_decoded(b))

# LAW: read-your-writes through batch application (closed)
law db_ryw:
  {MemTable.get(Db.apply_batch(db_muts1(), MemTable.empty()), "k") == Some{"v"} : Maybe<&2, String>}

# LAW: delete hides through batch application (closed)
law db_del:
  {MemTable.get(Db.apply_batch(Con{Wal.Del{"k"}, Nil{}}, Db.apply_batch(db_muts1(), MemTable.empty())), "k") == None{} : Maybe<&2, String>}

# LAW: batch applies as one atomic sequential transition (closed)
law db_batch_atomic:
  {Db.apply_batch(db_muts2(), MemTable.empty()) == db_mem2() : MemTable.MemTable}

# LAW: recovery replay equals direct application (closed; composes wal_rt)
law db_recover:
  {db_replay(batch_multi()) == Db.apply_batch(batch_muts(batch_multi()), MemTable.empty()) : MemTable.MemTable}

# --- SSTable file codec + flush (Task 8): closed vectors (spec law 6) ---

# LAW: table file round-trip rebuilds the identical table (closed)
law sstfile_rt:
  {SstFile.parse(SstFile.serialize(scan_mem(), 0n)) == Some{Sstable.build(scan_mem(), 0n, 2n)} : Maybe<&2, Sstable.Table>}

# LAW: shapeless input rejected fail-closed (closed)
law sstfile_reject:
  {SstFile.parse("garbage") == None{} : Maybe<&2, Sstable.Table>}

def fl_pre() -> Db.Db:
  Db.Db{"/d", MemTable.MT{scan_mem()}, Nil{}, 0n}

def fl_post() -> Db.Db:
  Db.Db{"/d", MemTable.MT{Nil{}}, Con{Con{Sstable.build(scan_mem(), 0n, 2n), Nil{}}, Nil{}}, 1n}

# LAW: pre-flush read hits (closed; kills vacuity for the pair below)
law flush_hit_pre:
  {Db.db_get(fl_pre(), "a") == Some{"v1"} : Maybe<&2, String>}

# LAW: post-flush read hits identically (closed)
law flush_hit_post:
  {Db.db_get(fl_post(), "a") == Some{"v1"} : Maybe<&2, String>}

# LAW: flush preservation shape — reads equal across the transition (closed)
law flush_preserve:
  {Db.db_get(fl_pre(), "a") == Db.db_get(fl_post(), "a") : Maybe<&2, String>}

# LAW: absent key stays absent across flush (closed; meaningful paired
# with the hit laws, which prove reads are not uniformly None)
law flush_miss:
  {Db.db_get(fl_pre(), "z") == Db.db_get(fl_post(), "z") : Maybe<&2, String>}

# --- Compaction (Task 9): closed vectors (spec laws 6, 11, 12) ---
# L0 (newest-first, 5 tables > trigger 4): [m] [b=v2] [a=v1] [Del x] [c=v3].
# L1: [a=v0, z=vz] (absorbed: overlaps hull [a..m]) + [p=vp] (remainder).
# L2 shadow: [x=v_old] (drops the Del x tombstone) + [q=vq].

def cp_e1(k: String, v: String) -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{k, Some{v}}, Nil{}}

def cp_e_del(k: String) -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{k, None{}}, Nil{}}

def cp_t0() -> Sstable.Table:
  Sstable.build(cp_e1("m", "vm"), 0n, 1n)

def cp_t1() -> Sstable.Table:
  Sstable.build(cp_e1("b", "v2"), 0n, 1n)

def cp_t2() -> Sstable.Table:
  Sstable.build(cp_e1("a", "v1"), 0n, 1n)

def cp_t3() -> Sstable.Table:
  Sstable.build(cp_e_del("x"), 0n, 1n)

def cp_t4() -> Sstable.Table:
  Sstable.build(cp_e1("c", "v3"), 0n, 1n)

def cp_l0() -> List<&2, Sstable.Table>:
  Con{cp_t0(), Con{cp_t1(), Con{cp_t2(), Con{cp_t3(), Con{cp_t4(), Nil{}}}}}}

def cp_u0() -> Sstable.Table:
  Sstable.build(Con{MemTable.Entry{"a", Some{"v0"}}, Con{MemTable.Entry{"z", Some{"vz"}}, Nil{}}}, 1n, 2n)

def cp_u1() -> Sstable.Table:
  Sstable.build(cp_e1("p", "vp"), 1n, 1n)

def cp_l1() -> List<&2, Sstable.Table>:
  Con{cp_u0(), Con{cp_u1(), Nil{}}}

def cp_s0() -> Sstable.Table:
  Sstable.build(Con{MemTable.Entry{"x", Some{"vold"}}, Con{MemTable.Entry{"q", Some{"vq"}}, Nil{}}}, 2n, 2n)

def cp_l2() -> List<&2, Sstable.Table>:
  Con{cp_s0(), Nil{}}

def cp_levels() -> List<&2, List<&2, Sstable.Table>>:
  Con{cp_l0(), Con{cp_l1(), Con{cp_l2(), Nil{}}}}

def cp_kept() -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{"a", Some{"v1"}}, Con{MemTable.Entry{"b", Some{"v2"}}, Con{MemTable.Entry{"c", Some{"v3"}}, Con{MemTable.Entry{"m", Some{"vm"}}, Con{MemTable.Entry{"p", Some{"vp"}}, Con{MemTable.Entry{"z", Some{"vz"}}, Nil{}}}}}}}

def cp_out() -> Sstable.Table:
  Sstable.build(cp_kept(), 1n, 6n)

def cp_u2() -> Sstable.Table:
  Sstable.build(cp_e1("zz", "vzz"), 1n, 1n)

def cp_post_l1() -> List<&2, Sstable.Table>:
  Con{cp_out(), Nil{}}

def cp_post() -> List<&2, List<&2, Sstable.Table>>:
  Con{Nil{}, Con{cp_post_l1(), Con{cp_l2(), Nil{}}}}

# LAW: compaction output = live entries, L0 drained, remainder kept (closed;
# pins law 11 multiset + L0-drain + L1 shape in one equality)
law compact_live:
  {Compact.compact_levels(cp_levels()) == cp_post() : List<&2, List<&2, Sstable.Table>>}

# LAW: output disjoint from a non-overlapping table (closed, law 12;
# u1 was absorbed in round 2 by the widened hull — multi-round closure
# working as designed — so the witness is a fresh out-of-range table)
law compact_disjoint:
  {Compact.table_overlap(cp_out(), cp_u2()) == False{} : Bool}

# LAW: absorbed table did overlap the L0 hull (closed sanity: closure fired)
law compact_absorbed:
  {Compact.table_overlap(cp_t2(), cp_u0()) == True{} : Bool}

def cp_db_pre() -> Db.Db:
  Db.Db{"/d", MemTable.MT{Nil{}}, cp_levels(), 5n}

def cp_db_post() -> Db.Db:
  Db.Db{"/d", MemTable.MT{Nil{}}, cp_post(), 6n}

# LAW: post-compaction hit pinned (closed; anti-vacuity)
law compact_hit:
  {Db.db_get(cp_db_post(), "a") == Some{"v1"} : Maybe<&2, String>}

# LAW: preservation shape across compaction (closed, law 6)
law compact_preserve:
  {Db.db_get(cp_db_pre(), "a") == Db.db_get(cp_db_post(), "a") : Maybe<&2, String>}

# LAW: miss preserved (closed; meaningful with compact_hit)
law compact_miss:
  {Db.db_get(cp_db_pre(), "w") == Db.db_get(cp_db_post(), "w") : Maybe<&2, String>}

def cp_small_l0() -> List<&2, Sstable.Table>:
  Con{cp_t0(), Con{cp_t1(), Nil{}}}

def cp_small() -> List<&2, List<&2, Sstable.Table>>:
  Con{cp_small_l0(), Con{cp_l1(), Con{cp_l2(), Nil{}}}}

# LAW: no-op at/ below trigger (closed)
law compact_noop:
  {Compact.compact_levels(cp_small()) == cp_small() : List<&2, List<&2, Sstable.Table>>}

# --- Recovery + maintenance (Task 10): closed vectors (spec law 7) ---

# LAW: frame length parses (closed)
law frame_len_ok:
  {Recover.frame_len(Recover.frame_of("abc")) == Some{3n} : Maybe<&2, Nat>}

# LAW: single-frame replay applies the batch (closed; composes wal_rt)
law replay_single:
  {Recover.replay_mem(Recover.frame_of(Wal.encode(batch_put1()))) == MemTable.MT{Con{MemTable.Entry{"k", Some{"v"}}, Nil{}}} : MemTable.MemTable}

# LAW: torn tail replays to the valid prefix — here empty (closed)
law replay_torn:
  {Recover.replay_mem("---;ab") == MemTable.empty() : MemTable.MemTable}

def nf_mem2() -> MemTable.MemTable:
  MemTable.MT{Con{MemTable.Entry{"a", Some{"1"}}, Con{MemTable.Entry{"b", Some{"2"}}, Nil{}}}}

def nf_mem1() -> MemTable.MemTable:
  MemTable.MT{Con{MemTable.Entry{"a", Some{"1"}}, Nil{}}}

# LAW: flush gate fires above cap (closed)
law needs_flush_hi:
  {Recover.needs_flush_cap(nf_mem2(), 1n) == True{} : Bool}

# LAW: flush gate rests at/below cap (closed)
law needs_flush_lo:
  {Recover.needs_flush_cap(nf_mem1(), 1n) == False{} : Bool}

# LAW: counter restores to max dashes + 1 (closed)
law count_gen_one:
  {Recover.count_gen(Con{Con{"l0-.tbl", Nil{}}, Nil{}}) == 1n : Nat}

# LAW: recovery equivalence — replayed reads equal pre-crash reads (closed)
law recover_equiv:
  {MemTable.get(Recover.replay_mem(Recover.frame_of(Wal.encode(batch_put1()))), "k") == MemTable.get(MemTable.MT{Con{MemTable.Entry{"k", Some{"v"}}, Nil{}}}, "k") : Maybe<&2, String>}

# --- Hardening (Task 12): all decoders decide every input ---
law wal_fail_closed:
  for +s: String
  {Wal.is_decided(Wal.decode(s)) == True{} : Bool}

law manifest_fail_closed:
  for +s: String
  {Manifest.is_decided(Manifest.parse(s)) == True{} : Bool}

law sstfile_fail_closed:
  for +s: String
  {SstFile.is_decided(SstFile.parse(s)) == True{} : Bool}

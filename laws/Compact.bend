import Base
import ../src/MemTable.bend as MemTable
import ../src/Sstable.bend as Sstable
import ../src/Db.bend as Db
import ../src/Compact.bend as Compact

# --- Compaction (Task 9): closed vectors (spec laws 6, 11, 12) ---
# L0 (newest-first, 5 tables > trigger 4): [m] [b=v2] [a=v1] [Del x] [c=v3].
# L1: [a=v0, z=vz] (absorbed: overlaps hull [a..m]) + [p=vp] (remainder).
# L2 shadow: [x=v_old] (drops the Del x tombstone) + [q=vq].

def cp_e1(key: String, val: String) -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{key, Some{val}}, Nil{}}

def cp_e_del(key: String) -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{key, None{}}, Nil{}}

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
  Con{MemTable.Entry{"a", Some{"v1"}}, Con{MemTable.Entry{"b", Some{"v2"}}, Con{MemTable.Entry{"c", Some{"v3"}}, Con{MemTable.Entry{"m", Some{"vm"}}, Con{MemTable.Entry{"p", Some{"vp"}}, Con{MemTable.Entry{"x", None{}}, Con{MemTable.Entry{"z", Some{"vz"}}, Nil{}}}}}}}}

def cp_out() -> Sstable.Table:
  Sstable.from_sorted_unique(cp_kept(), 1n)

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
  Db.Db{"/d", MemTable.MT{Nil{}}, MemTable.MT{Nil{}}, 1n, Nil{}, cp_levels(), 5n, ""}

def cp_db_post() -> Db.Db:
  Db.Db{"/d", MemTable.MT{Nil{}}, MemTable.MT{Nil{}}, 1n, Nil{}, cp_post(), 6n, ""}

# LAW: post-compaction hit pinned (closed; anti-vacuity)
law compact_hit:
  {Db.db_get(cp_db_post(), "a") == Some{"v1"} : Maybe<&2, String>}

# LAW: a compacted tombstone must continue hiding the older L2 value.
law compact_no_resurrection:
  {Db.db_get(cp_db_post(), "x") == None{} : Maybe<&2, String>}

law compact_delete_preserve:
  {Db.db_get(cp_db_pre(), "x") == Db.db_get(cp_db_post(), "x") : Maybe<&2, String>}

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

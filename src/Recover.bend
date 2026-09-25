import Base
import ./Keys.bend as Keys
import ./MemTable.bend as MemTable
import ./Sstable.bend as Sstable
import ./SstFile.bend as SstFile
import ./SstStream.bend as SstStream
import ./Wal.bend as Wal
import ./Manifest.bend as Manifest
import ./Flush.bend as Flush
import ./Compact.bend as Compact
import ./Fs.bend as Fs
import ./Db.bend as Db

# Recovery + maintenance (Task 10).
#
# WAL framing v1 (no WAL-codec churn): each appended batch is
# dashes(len) ++ ";" ++ encode(batch). Replay parses frames oldest-first;
# a torn tail (crash mid-append) stops the walk (valid prefix kept) and is
# truncated on open (monotonic truncation to valid frames — safe to retry).
# Single wal.log (appends need no dir-sync: the entry pre-exists).
#
# Open: ensure dir; sweep *.tmp (best-effort); load manifest (absent =
# fresh; corrupt = fatal); shape-check all names; load tables positionally
# (listed-but-missing/corrupt = fatal, never silent); restore the flush
# counter (max dashes + 1 — open_db's 0 would collide); replay + truncate
# the WAL; return the Db.
#
# Maintenance (synchronous, observably identical ordering to background):
# after every acked batch: drain while L0 >= 8 (stall = blocking
# maintenance), flush when mem >= 4096, compact (self-gated at L0 > 4).
# True fork-based background (frozen mem + IO.spawn) is a benchmark-gated
# follow-up; ordering and stall semantics are already exact.

# --- WAL frame codec (pure) ---

def dash_step(+done: Bool, isdash: Bool, +acc: Nat) -> (Bool & Nat):
  match done:
    case True{}:
      (True{}, acc)
    case False{}:
      match isdash:
        case True{}:
          (False{}, Nat.add(1n, acc))
        case False{}:
          (True{}, acc)

def dash_snd(st: (Bool & Nat)) -> Nat:
  match st:
    case (d, a):
      a

def dash_step_fst(st: (Bool & Nat), +h: Char) -> (Bool & Nat):
  match st:
    case (done, acc):
      dash_step(done, Char.is_eq(h, Char.from_u32(45)), acc)

def dash_go(fuel: Nat, st: (Bool & Nat), s: String) -> Nat:
  match fuel:
    case 0n:
      dash_snd(st)
    case 1n+f:
      match s:
        case SNil{}:
          dash_snd(st)
        case SCon{h, t}:
          dash_go(f, dash_step_fst(st, h), t)

def dashes_len(+s: String) -> Nat:
  dash_go(Nat.add(String.length(s), 1n), (False{}, 0n), s)

def semi_eq(+b: Bool, +n: Nat) -> Maybe<&2, Nat>:
  match b:
    case True{}:
      Some{n}
    case False{}:
      None{}

def semi_go(+h: Char, +n: Nat) -> Maybe<&2, Nat>:
  semi_eq(Char.is_eq(h, Char.from_u32(59)), n)

def sc_go(dropped: String, +n: Nat) -> Maybe<&2, Nat>:
  match dropped:
    case SNil{}:
      None{}
    case SCon{h, t}:
      semi_go(h, n)

def frame_len_go(+n: Nat, +s: String) -> Maybe<&2, Nat>:
  sc_go(String.drop(s, n), n)

def frame_len(+s: String) -> Maybe<&2, Nat>:
  frame_len_go(dashes_len(s), s)

def frame_of(+w: String) -> String:
  Wal.dashes(String.length(w)) ++ ";" ++ w

def consumed(+n: Nat) -> Nat:
  Nat.add(String.length(Wal.dashes(n)), Nat.add(1n, n))

def clip_go(+mlen: Maybe<&2, Nat>, +s: String) -> String:
  match mlen:
    case None{}:
      s
    case Some{n}:
      String.take(String.drop(s, Nat.add(String.length(Wal.dashes(n)), 1n)), n)

def drop_after(+mlen: Maybe<&2, Nat>, +s: String) -> String:
  match mlen:
    case None{}:
      s
    case Some{n}:
      String.drop(s, consumed(n))

def dec_apply(+m2: Maybe<&2, Wal.Batch>, +mem: MemTable.MemTable) -> MemTable.MemTable:
  match m2:
    case None{}:
      mem
    case Some{Wal.Batch{muts}}:
      Db.apply_batch(muts, mem)

# Fuel-only drivers (no s-match: fuel bounds the walk; torn/empty tails
# are fixpoints that burn fuel and return the valid-prefix accumulation).
def replay_mem_go(fuel: Nat, +mem: MemTable.MemTable, +s: String) -> MemTable.MemTable:
  match fuel:
    case 0n:
      mem
    case 1n+g:
      +fl = frame_len(s)
      replay_mem_go(g, dec_apply(Wal.decode(clip_go(fl, s)), mem), drop_after(fl, s))

def replay_mem(+s: String) -> MemTable.MemTable:
  replay_mem_go(Nat.add(String.length(s), 1n), MemTable.empty(), s)

def valid_add(+mlen: Maybe<&2, Nat>, +acc: Nat) -> Nat:
  match mlen:
    case None{}:
      acc
    case Some{n}:
      Nat.add(acc, consumed(n))

def replay_valid_go(fuel: Nat, +acc: Nat, +s: String) -> Nat:
  match fuel:
    case 0n:
      acc
    case 1n+g:
      +fl = frame_len(s)
      replay_valid_go(g, valid_add(fl, acc), drop_after(fl, s))

def replay_valid(+s: String) -> Nat:
  replay_valid_go(Nat.add(String.length(s), 1n), 0n, s)

# --- Flush-counter restore (pure) ---

def mid_and(a: Bool, b: Bool) -> Bool:
  match a:
    case True{}:
      b
    case False{}:
      False{}

def shape_mid(a: Bool, b: Bool, c: Bool) -> Bool:
  mid_and(a, mid_and(b, c))

# Table generations are compact decimal only. Unparsable middles are invalid
# (no unary-dash legacy reads: no retrocompat).
def gen_valid_read(parsed: Maybe<&2, Nat>) -> Bool:
  match parsed:
    case Some{n}:
      True{}
    case None{}:
      False{}

def gen_valid(+middle: String) -> Bool:
  gen_valid_read(Nat.read(middle))

def ov_ok(+big: Bool, +name: String, +ln: Nat) -> Bool:
  match big:
    case True{}:
      shape_mid(String.starts_with(name, "l"), String.ends_with(name, ".tbl"), gen_valid(String.take(String.drop(name, 3n), Nat.sub(ln, 7n))))
    case False{}:
      False{}

def name_shape(+name: String) -> Bool:
  +ln = String.length(name)
  ov_ok(Nat.is_le(7n, ln), name, ln)

def level_name_ok(+big: Bool, +name: String, +ln: Nat, +prefix: String, +prefix_len: Nat) -> Bool:
  match big:
    case False{}:
      False{}
    case True{}:
      shape_mid(String.starts_with(name, prefix), String.ends_with(name, ".tbl"), gen_valid(String.take(String.drop(name, prefix_len), Nat.sub(ln, Nat.add(prefix_len, 4n)))))

def name_shape_level(+name: String, +level: Nat) -> Bool:
  +prefix = "l" ++ Nat.show(level) ++ "-"
  +prefix_len = String.length(prefix)
  +ln = String.length(name)
  level_name_ok(Nat.is_le(Nat.add(prefix_len, 4n), ln), name, ln, prefix, prefix_len)

def gen_value_read(parsed: Maybe<&2, Nat>) -> Nat:
  match parsed:
    case Some{n}:
      n
    case None{}:
      0n

def gen_value(+middle: String) -> Nat:
  gen_value_read(Nat.read(middle))

def name_gen(+name: String) -> Nat:
  +ln = String.length(name)
  gen_value(String.take(String.drop(name, 3n), Nat.sub(ln, 7n)))

def names_ok(xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{h, t}:
      mid_and(name_shape(h), names_ok(t))

def level_names_ok(+level: Nat, xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{h, t}:
      mid_and(name_shape_level(h, level), level_names_ok(level, t))

def manifest_names_ok(levels: List<&2, List<&2, String>>, +level: Nat) -> Bool:
  match levels:
    case Nil{}:
      True{}
    case Con{names, rest}:
      mid_and(level_names_ok(level, names), manifest_names_ok(rest, Nat.add(level, 1n)))

def names_all(lvls: List<&2, List<&2, String>>) -> List<&2, String>:
  match lvls:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      List.append(&2, String, h, names_all(t))

def cmax(names: List<&2, String>, +cur: Nat) -> Nat:
  match names:
    case Nil{}:
      cur
    case Con{h, t}:
      cmax(t, Nat.max(name_gen(h), cur))

def count_gen(+lvls: List<&2, List<&2, String>>) -> Nat:
  Nat.add(cmax(names_all(lvls), 0n), 1n)

def mfst_lists(+m: Manifest.Manifest) -> List<&2, List<&2, String>>:
  match m:
    case Manifest.M{lvs}:
      lvs

# L0 may overlap by design. Every table within each level below L0 must have
# a range disjoint from every peer; metadata makes this check independent of
# SortedRun and avoids reparsing entries during recovery.
def disjoint_with_table(+tbl: Sstable.Table, rest: List<&2, Sstable.Table>) -> Bool:
  match rest:
    case Nil{}:
      True{}
    case Con{+h, t}:
      mid_and(Sstable.ranges_disjoint(tbl, h), disjoint_with_table(tbl, t))

def level_pairwise_disjoint(tables: List<&2, Sstable.Table>) -> Bool:
  match tables:
    case Nil{}:
      True{}
    case Con{+h, +t}:
      mid_and(disjoint_with_table(h, t), level_pairwise_disjoint(t))

def lower_levels_disjoint(levels: List<&2, List<&2, Sstable.Table>>) -> Bool:
  match levels:
    case Nil{}:
      True{}
    case Con{+level, rest}:
      mid_and(level_pairwise_disjoint(level), lower_levels_disjoint(rest))

def l1_plus_disjoint(levels: List<&2, List<&2, Sstable.Table>>) -> Bool:
  match levels:
    case Nil{}:
      True{}
    case Con{l0, lower}:
      lower_levels_disjoint(lower)

# --- Loaders (self-recursive IO; fatal via IO.die, never silent) ---


def load_tables(names: List<&2, String>, +ldir: String, +dir: String, +acc: List<&2, Sstable.Table>) -> IO(List<&2, Sstable.Table>):
  match names:
    case Nil{}:
      IO.pure(List<&2, Sstable.Table>, List.reverse(&2, Sstable.Table, acc))
    case Con{+n, t}:
      do IO<List<&2, Sstable.Table>>:
        tbl : Sstable.Table <- IO.try(Sstable.Table, SstStream.read_table(dir ++ "/" ++ ldir ++ "/" ++ n))
        load_tables(t, ldir, dir, Con{tbl, acc})

def ldir_io(+m: Maybe<&2, String>) -> IO(String):
  match m:
    case None{}:
      IO.die(String, U32.from_nat(4n), "too many levels")
    case Some{d}:
      IO.pure(String, d)

def ldir_of(idx: Nat) -> Maybe<&2, String>:
  match idx:
    case 0n:
      Some{"l0"}
    case 1n+m:
      match m:
        case 0n:
          Some{"l1"}
        case 1n+p:
          match p:
            case 0n:
              Some{"l2"}
            case 1n+q:
              match q:
                case 0n:
                  Some{"l3"}
                case 1n+r:
                  None{}

def load_levels(lvls: List<&2, List<&2, String>>, +idx: Nat, +dir: String, +acc: List<&2, List<&2, Sstable.Table>>) -> IO(List<&2, List<&2, Sstable.Table>>):
  match lvls:
    case Nil{}:
      IO.pure(List<&2, List<&2, Sstable.Table>>, List.reverse(&2, List<&2, Sstable.Table>, acc))
    case Con{ns, t}:
      do IO<List<&2, List<&2, Sstable.Table>>>:
        ld : String <- ldir_io(ldir_of(idx))
        tabs : List<&2, Sstable.Table> <- load_tables(ns, ld, dir, Nil{})
        load_levels(t, Nat.add(idx, 1n), dir, Con{tabs, acc})

# --- WAL open (absent = fresh; torn tail truncated) ---

def trunc_go(short: Bool, +dir: String, +prefix: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  match short:
    case True{}:
      Flush.write_file(Db.wal_path(dir), prefix)
    case False{}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Done{Unit{}})

def mem_tail_snd(+s: String, +dir: String) -> IO(Result<&1, &1, U32 & String, MemTable.MemTable>):
  +valid = replay_valid(s)
  +ln = String.length(s)
  do IO<Result<&1, &1, U32 & String, MemTable.MemTable>>:
    _u : Unit <- IO.try(Unit, trunc_go(Nat.is_lt(valid, ln), dir, String.take(s, valid)))
    return Done{replay_mem(s)}

def mem_tail_fst(fr: (File & Result<&1, &1, U32 & String, String>), +dir: String) -> IO(Result<&1, &1, U32 & String, MemTable.MemTable>):
  match fr:
    case (f3, r1):
      do IO<Result<&1, &1, U32 & String, MemTable.MemTable>>:
        _cls : Unit <- File.close(f3)
        s : String <- IO.try(String, IO.pure(Result<&1, &1, U32 & String, String>, r1))
        mem_tail_snd(s, dir)

def wal_read(f: File, +dir: String) -> IO(Result<&1, &1, U32 & String, MemTable.MemTable>):
  do IO<Result<&1, &1, U32 & String, MemTable.MemTable>>:
    fr : (File & Result<&1, &1, U32 & String, String>) <- File.read(f, U32.mul(U32.from_nat(1024n), U32.from_nat(1024n)))
    mem_tail_fst(fr, dir)

def wal_open(r: Result<&1, &1, U32 & String, File>, +dir: String) -> IO(Result<&1, &1, U32 & String, MemTable.MemTable>):
  match r:
    case Fail{e}:
      IO.pure(Result<&1, &1, U32 & String, MemTable.MemTable>, Done{MemTable.empty()})
    case Done{f}:
      wal_read(f, dir)

# --- Tmp sweep (best-effort) ---

def tmp_pick(keep: Bool, +h: String, +acc: List<&2, String>) -> List<&2, String>:
  match keep:
    case True{}:
      Con{h, acc}
    case False{}:
      acc

def tmp_some(+b: Bool, +h: String) -> Maybe<&2, String>:
  match b:
    case True{}:
      Some{h}
    case False{}:
      None{}

def tmp_map_list(xs: List<&1, String>) -> List<&2, Maybe<&2, String>>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      Con{tmp_some(String.ends_with(h, ".tmp"), h), tmp_map_list(t)}

def cat_go(xs: List<&2, Maybe<&2, String>>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      match h:
        case None{}:
          cat_go(t)
        case Some{s}:
          Con{s, cat_go(t)}

def tmp_names(xs: List<&1, String>) -> List<&2, String>:
  cat_go(tmp_map_list(xs))

def sweep_one(r: Result<&1, &1, U32 & String, List<String>>, +dir: String) -> IO(Unit):
  match r:
    case Fail{e}:
      IO.pure(Unit, Unit{})
    case Done{ns}:
      do IO<Unit>:
        _ign : Result<&1, &1, U32 & String, Unit> <- Compact.remove_list(Compact.prefix(tmp_names(ns), dir))
        IO.pure(Unit, Unit{})

def sweep_get(+dir: String, +sub: String) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, List<String>> <- Fs.read_dir(dir ++ "/" ++ sub)
    sweep_one(r, dir ++ "/" ++ sub)

def sweep_cnt(c: Result<&1, &1, U32 & String, Nat>, +dir: String, +sub: String) -> IO(Unit):
  match c:
    case Fail{e}:
      IO.pure(Unit, Unit{})
    case Done{n}:
      sweep_get(dir, sub)

def sweep_dir(+dir: String, +sub: String) -> IO(Unit):
  do IO<Unit>:
    c : Result<&1, &1, U32 & String, Nat> <- Fs.read_dir_count(dir ++ "/" ++ sub)
    sweep_cnt(c, dir, sub)

# --- Open assembly ---

def wal_part(+dir: String) -> IO(Result<&1, &1, U32 & String, MemTable.MemTable>):
  do IO<Result<&1, &1, U32 & String, MemTable.MemTable>>:
    r : Result<&1, &1, U32 & String, File> <- File.open(Db.wal_path(dir), "r")
    wal_open(r, dir)

def open_levels_checked(ok: Bool, +dir: String, +m: Manifest.Manifest, levels: List<&2, List<&2, Sstable.Table>>) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match ok:
    case False{}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{(U32.from_nat(6n), "overlapping tables in L1+ manifest")})
    case True{}:
      do IO<Result<&1, &1, U32 & String, Db.Db>>:
        mem : MemTable.MemTable <- IO.try(MemTable.MemTable, wal_part(dir))
        return Done{Db.Db{dir, mem, MemTable.empty(), Db.default_batch_cap(), Nil{}, levels, count_gen(mfst_lists(m)), Manifest.serialize(m)}}

def open_levels(+dir: String, +m: Manifest.Manifest) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  do IO<Result<&1, &1, U32 & String, Db.Db>>:
    +levels : List<&2, List<&2, Sstable.Table>> <- load_levels(mfst_lists(m), 0n, dir, Nil{})
    open_levels_checked(l1_plus_disjoint(levels), dir, m, levels)

def open_names_go(ok: Bool, +dir: String, +m: Manifest.Manifest) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match ok:
    case True{}:
      open_levels(dir, m)
    case False{}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{(U32.from_nat(5n), "bad manifest names")})

def sweep_root_go(+dir: String) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, List<String>> <- Fs.read_dir(dir)
    sweep_one(r, dir)

def sweep_root_cnt(c: Result<&1, &1, U32 & String, Nat>, +dir: String) -> IO(Unit):
  match c:
    case Fail{e}:
      IO.pure(Unit, Unit{})
    case Done{n}:
      sweep_root_go(dir)

def sweep_root(+dir: String) -> IO(Unit):
  do IO<Unit>:
    c : Result<&1, &1, U32 & String, Nat> <- Fs.read_dir_count(dir)
    sweep_root_cnt(c, dir)

def open_db(+dir: String) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  do IO<Result<&1, &1, U32 & String, Db.Db>>:
    _u0 : Unit <- IO.try(Unit, Flush.ensure_dir(dir))
    _s0 : Unit <- sweep_dir(dir, "l0")
    _s1 : Unit <- sweep_dir(dir, "l1")
    _s2 : Unit <- sweep_dir(dir, "l2")
    _s3 : Unit <- sweep_dir(dir, "l3")
    _s4 : Unit <- sweep_root(dir)
    +m : Manifest.Manifest <- IO.try(Manifest.Manifest, Flush.load_mfst(dir ++ "/MANIFEST"))
    open_names_go(manifest_names_ok(mfst_lists(m), 0n), dir, m)

# --- Maintenance (synchronous auto flush/compact + stall) ---
# One drain round always suffices (L0 >= 8 > 4, so the gated compaction
# fires and empties L0) — no loop, no cycle.

def needs_flush_cap(+mem: MemTable.MemTable, +cap: Nat) -> Bool:
  Nat.is_lt(cap, MemTable.count(mem))

def flush_dec(full: Bool, +db: Db.Db) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match full:
    case True{}:
      Flush.flush(db)
    case False{}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Done{db})

def flush_gate(db: Db.Db) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match db:
    case Db.Db{dir, +mem, frozen, batch_cap, bcache, levels, flushed, manifest_token}:
      flush_dec(needs_flush_cap(mem, 4096n), Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token})

def l0_full(db: Db.Db) -> Bool:
  match db:
    case Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token}:
      Nat.is_lt(7n, List.length(&2, Sstable.Table, Compact.l0list(levels)))

def drain_once(+db: Db.Db) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  do IO<Result<&1, &1, U32 & String, Db.Db>>:
    f : Db.Db <- IO.try(Db.Db, Flush.flush(db))
    c : Db.Db <- IO.try(Db.Db, Compact.compact(f))
    return Done{c}

def drain_pick(full: Bool, +db: Db.Db) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match full:
    case True{}:
      drain_once(db)
    case False{}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Done{db})

def drain_go(+db: Db.Db) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  drain_pick(l0_full(db), db)

def maintain(+db: Db.Db) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  do IO<Result<&1, &1, U32 & String, Db.Db>>:
    d : Db.Db <- IO.try(Db.Db, drain_go(db))
    f : Db.Db <- IO.try(Db.Db, flush_gate(d))
    Compact.compact(f)

def maintain_unwrap(r: Result<&1, &1, U32 & String, Db.Db>) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match r:
    case Fail{e}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{e})
    case Done{db}:
      maintain(db)

def write(+db: Db.Db, +b: Wal.Batch) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  do IO<Result<&1, &1, U32 & String, Db.Db>>:
    r : Result<&1, &1, U32 & String, Db.Db> <- Db.db_write(db, b)
    maintain_unwrap(r)

def put(+db: Db.Db, +k: String, +v: String) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  write(db, Wal.Batch{Con{Wal.Put{k, v}, Nil{}}})

def del(+db: Db.Db, +k: String) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  write(db, Wal.Batch{Con{Wal.Del{k}, Nil{}}})

# --- Closed-vector laws live in laws/Recover.bend (spec law 7) ---

import Base
import ./Keys.bend as Keys
import ./MemTable.bend as MemTable
import ./Sstable.bend as Sstable
import ./SstStreamIo.bend as SstStreamIo
import ./Wal.bend as Wal
import ./Manifest.bend as Manifest
import ./Flush.bend as Flush
import ./Compact.bend as Compact
import ./CompactIo.bend as CompactIo
import ./Fs.bend as Fs
import ./Db.bend as Db
import ./DbIo.bend as DbIo
import ./RecoverPure.bend as Pure
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Represent ExactResult data used by the database recovery effects.
type ExactResult is Type:
  ExactResult{bytes: Bytes.Bytes, complete: Bool}

# Represent ExactState data used by the database recovery effects.
type ExactState is Type:
  ExactNeed{file: File, remaining: Nat, chunks: List<&1, Bytes.Bytes>}
  ExactRead{pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>, remaining: Nat, chunks: List<&1, Bytes.Bytes>}

# Represent WalProgress data used by the database recovery effects.
type WalProgress is Type:
  WalMore{file: File, offset: Nat, state: Db.RotRes}
  WalStop{result: Result<&1, &1, U32 & String, Db.RotRes>}

# Represent WalState data used by the database recovery effects.
type WalState is Type:
  WalAt{file: File, offset: Nat, state: Db.RotRes}
  WalAfter{progress: WalProgress}

def exact.max(large: Bool, +remaining: Nat) -> U32:
  match large:
    case True{}:
      1048576
    case False{}:
      U32.from_nat(remaining)

def exact.result(
  file: File,
  chunks: List<&1, Bytes.Bytes>,
  complete: Bool
) -> IO(File & Result<&1, &1, U32 & String, ExactResult>):
  IO.pure(File & Result<&1, &1, U32 & String, ExactResult>,
    (file, Done{ExactResult{Bytes.concat(List.reverse(&1, Bytes.Bytes, chunks)), complete}}))

def exact.loop(
  fuel: Nat,
  state: ExactState
) -> IO(File & Result<&1, &1, U32 & String, ExactResult>):
  match fuel:
    case 0n:
      match state:
        case ExactNeed{file, remaining, chunks}:
          match remaining:
            case 0n:
              exact.result(file, chunks, True{})
            case 1n+_:
              IO.pure(File & Result<&1, &1, U32 & String, ExactResult>,
                (file, Fail{(U32.from_nat(7n), "bounded read exhausted")}))
        case ExactRead{pair, _, _}:
          match pair:
            case (file, Fail{error}):
              IO.pure(File & Result<&1, &1, U32 & String, ExactResult>, (file, Fail{error}))
            case (file, Done{_}):
              IO.pure(File & Result<&1, &1, U32 & String, ExactResult>,
                (file, Fail{(U32.from_nat(7n), "bounded read exhausted")}))
    case 1n+rest:
      match state:
        case ExactNeed{file, +remaining, chunks}:
          match remaining:
            case 0n:
              exact.result(file, chunks, True{})
            case 1n+_:
              do IO<File & Result<&1, &1, U32 & String, ExactResult>>:
                next : File & Result<&1, &1, U32 & String, Bytes.Bytes> <-
                  Fs.read_bytes(file, exact.max(Nat.is_le(1048577n, remaining), remaining))
                exact.loop(rest, ExactRead{next, remaining, chunks})
        case ExactRead{pair, remaining, chunks}:
          match pair:
            case (file, Fail{error}):
              IO.pure(File & Result<&1, &1, U32 & String, ExactResult>, (file, Fail{error}))
            case (file, Done{Bytes.Bytes{0, _}}):
              exact.result(file, chunks, False{})
            case (file, Done{Bytes.Bytes{+len, buf}}):
              exact.loop(rest, ExactNeed{file,
                (remaining - U32.to_nat(len) : Nat),
                Con{Bytes.Bytes{len, buf}, chunks}})

# Recovery + maintenance (Task 10).
#
# Open: ensure dir; sweep *.tmp (best-effort); load manifest (absent =
# fresh; corrupt = fatal); shape-check all names; load tables positionally
# (listed-but-missing/corrupt = fatal, never silent); restore the flush
# counter from the greatest table-name generation; replay + truncate
# the WAL; return the Db.
#
# Maintenance (synchronous, observably identical ordering to background):
# after every acked batch: drain while L0 >= 8 (stall = blocking
# maintenance), flush when mem >= 4096, compact (self-gated at L0 > 4).
# True fork-based background (frozen mem + IO.spawn) is a benchmark-gated
# follow-up; ordering and stall semantics are already exact.

# --- Loaders (self-recursive IO; fatal via IO.die, never silent) ---


# Handle load tables in the database recovery effects.
def load_tables(
  names: List<&2, String>,
  +ldir: String,
  +dir: String,
  +acc: List<&2, Sstable.Table>
) -> IO(List<&2, Sstable.Table>):
  match names:
    case Nil{}:
      IO.pure(List<&2, Sstable.Table>, List.reverse(&2, Sstable.Table, acc))
    case Con{+n, t}:
      do IO<List<&2, Sstable.Table>>:
        tbl : Sstable.Table <- IO.try(Sstable.Table, SstStreamIo.read_table(dir ++ "/" ++ ldir ++ "/" ++ n))
        load_tables(t, ldir, dir, Con{tbl, acc})

# Handle ldir io in the database recovery effects.
def ldir_io(+opt: Maybe<&2, String>) -> IO(String):
  match opt:
    case None{}:
      IO.die(String, U32.from_nat(4n), "too many levels")
    case Some{d}:
      IO.pure(String, d)

# Handle ldir of in the database recovery effects.
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

# Handle load levels in the database recovery effects.
def load_levels(
  lvls: List<&2, List<&2, String>>,
  +idx: Nat,
  +dir: String,
  +acc: List<&2, List<&2, Sstable.Table>>
) -> IO(List<&2, List<&2, Sstable.Table>>):
  match lvls:
    case Nil{}:
      IO.pure(List<&2, List<&2, Sstable.Table>>, List.reverse(&2, List<&2, Sstable.Table>, acc))
    case Con{ns, t}:
      do IO<List<&2, List<&2, Sstable.Table>>>:
        ld : String <- ldir_io(ldir_of(idx))
        tabs : List<&2, Sstable.Table> <- load_tables(ns, ld, dir, Nil{})
        load_levels(t, Nat.add(idx, 1n), dir, Con{tabs, acc})

def wal.empty() -> Db.RotRes:
  Db.Rot{MemTable.empty(), MemTable.empty(), 0n, 0n}

def exact.start(file: File, +needed: Nat) -> IO(File & Result<&1, &1, U32 & String, ExactResult>):
  exact.loop(Nat.add(Nat.mul(2n, needed), 1n), ExactNeed{file, needed, Nil{}})

def wal.truncate(
  +path: String,
  +offset: Nat,
  state: Db.RotRes
) -> IO(WalProgress):
  do IO<WalProgress>:
    _truncated : Unit <- IO.try(Unit, Fs.truncate(path, offset))
    _synced : Unit <- IO.try(Unit, Fs.fsync(path))
    return WalStop{Done{state}}

def wal.u32.pair(pair: Bytes.Cursor & Maybe<&2, U32>) -> Maybe<&2, U32>:
  match pair:
    case (_, value):
      value

def wal.u32(bytes: Bytes.Bytes) -> Maybe<&2, U32>:
  wal.u32.pair(Bytes.Cursor.u32be(Bytes.Cursor.new(bytes)))

def wal.apply(batch: Wal.Batch, state: Db.RotRes) -> Db.RotRes:
  match batch state:
    case Wal.Batch{muts} Db.Rot{mem, frozen, mem_count, frozen_count}:
      Db.apply_and_rotate(muts, mem, frozen, mem_count, frozen_count)

def wal.frames.decoded(
  result: Result<&1, &1, Wal.Error, Wal.Batch>,
  file: File,
  +next_offset: Nat,
  state: Db.RotRes
) -> IO(WalProgress):
  match result:
    case Fail{_}:
      do IO<WalProgress>:
        _closed : Unit <- File.close(file)
        return WalStop{Fail{(U32.from_nat(3n), "corrupt WAL frame")}}
    case Done{batch}:
      IO.pure(WalProgress,
        WalMore{file, next_offset, wal.apply(batch, state)})

def wal.frames.decode(
  pair: File & Result<&1, &1, U32 & String, ExactResult>,
  prefix: Bytes.Bytes,
  +offset: Nat,
  +next_offset: Nat,
  state: Db.RotRes,
  +path: String
) -> IO(WalProgress):
  match pair:
    case (file, Fail{error}):
      do IO<WalProgress>:
        _closed : Unit <- File.close(file)
        return WalStop{Fail{error}}
    case (file, Done{ExactResult{_, False{}}}):
      do IO<WalProgress>:
        _closed : Unit <- File.close(file)
        wal.truncate(path, offset, state)
    case (file, Done{ExactResult{body, True{}}}):
      wal.frames.decoded(Wal.decode_frame(Bytes.concat([prefix, body])),
        file, next_offset, state)

def wal.frames.body.bound(
  enough: Bool,
  file: File,
  prefix: Bytes.Bytes,
  +frame_size: Nat,
  +offset: Nat,
  +next_offset: Nat,
  state: Db.RotRes,
  +path: String
) -> IO(WalProgress):
  match enough:
    case False{}:
      do IO<WalProgress>:
        _closed : Unit <- File.close(file)
        wal.truncate(path, offset, state)
    case True{}:
      do IO<WalProgress>:
        pair : File & Result<&1, &1, U32 & String, ExactResult> <- exact.start(file, frame_size)
        wal.frames.decode(pair, prefix, offset, next_offset, state, path)

def wal.frames.body(
  file: File,
  prefix: Bytes.Bytes,
  +frame_size: Nat,
  +size: Nat,
  +offset: Nat,
  state: Db.RotRes,
  +path: String
) -> IO(WalProgress):
  +next_offset = Nat.add(offset, Nat.add(4n, frame_size))
  wal.frames.body.bound(Nat.is_le(next_offset, size), file, prefix,
    frame_size, offset, next_offset, state, path)

def wal.frames.bound(
  within: Bool,
  file: File,
  bytes: Bytes.Bytes,
  frame_len: U32,
  +size: Nat,
  +offset: Nat,
  state: Db.RotRes,
  +path: String
) -> IO(WalProgress):
  match within:
    case False{}:
      do IO<WalProgress>:
        _closed : Unit <- File.close(file)
        return WalStop{Fail{(U32.from_nat(3n), "WAL frame length out of bounds")}}
    case True{}:
      wal.frames.body(file, bytes, U32.to_nat(frame_len), size,
        offset, state, path)

def wal.frames.length.checked(
  enough: Bool,
  within: Bool,
  file: File,
  prefix: Bytes.Bytes,
  frame_len: U32,
  +size: Nat,
  +offset: Nat,
  state: Db.RotRes,
  +path: String
) -> IO(WalProgress):
  match enough:
    case False{}:
      do IO<WalProgress>:
        _closed : Unit <- File.close(file)
        wal.truncate(path, offset, state)
    case True{}:
      wal.frames.bound(within, file, prefix, frame_len, size,
        offset, state, path)

def wal.frames.length.value(
  file: File,
  maybe_len: Maybe<&2, U32>,
  +size: Nat,
  +offset: Nat,
  state: Db.RotRes,
  +path: String
) -> IO(WalProgress):
  match maybe_len:
    case None{}:
      do IO<WalProgress>:
        _closed : Unit <- File.close(file)
        return WalStop{Fail{(U32.from_nat(3n), "malformed WAL frame length")}}
    case Some{+frame_len}:
      +next_offset = Nat.add(offset, Nat.add(4n, U32.to_nat(frame_len)))
      wal.frames.length.checked(Nat.is_le(next_offset, size),
        U32.is_le(36, frame_len) && U32.is_le(frame_len, 1073741860),
        file, Wal.u32_bytes(frame_len), frame_len, size, offset,
        state, path)

def wal.frames.length(
  pair: File & Result<&1, &1, U32 & String, ExactResult>,
  +size: Nat,
  +offset: Nat,
  state: Db.RotRes,
  +path: String
) -> IO(WalProgress):
  match pair:
    case (file, Fail{error}):
      do IO<WalProgress>:
        _closed : Unit <- File.close(file)
        return WalStop{Fail{error}}
    case (file, Done{ExactResult{bytes, complete}}):
      match complete:
        case False{}:
          do IO<WalProgress>:
            _closed : Unit <- File.close(file)
            wal.truncate(path, offset, state)
        case True{}:
          wal.frames.length.value(file, wal.u32(bytes),
            size, offset, state, path)

def wal.frames.remaining(
  file: File,
  +size: Nat,
  +offset: Nat,
  state: Db.RotRes,
  +path: String,
  remaining: Nat
) -> IO(WalProgress):
  match remaining:
    case 0n:
      do IO<WalProgress>:
        _closed : Unit <- File.close(file)
        return WalStop{Done{state}}
    case 1n+p:
      match p:
        case 0n:
          do IO<WalProgress>:
            _closed : Unit <- File.close(file)
            wal.truncate(path, offset, state)
        case 1n+q:
          match q:
            case 0n:
              do IO<WalProgress>:
                _closed : Unit <- File.close(file)
                wal.truncate(path, offset, state)
            case 1n+_:
              do IO<WalProgress>:
                pair : File & Result<&1, &1, U32 & String, ExactResult> <- exact.start(file, 4n)
                wal.frames.length(pair, size, offset, state, path)

def wal.frames.end(
  at_end: Bool,
  file: File,
  +size: Nat,
  +offset: Nat,
  state: Db.RotRes,
  +path: String
) -> IO(WalProgress):
  match at_end:
    case True{}:
      do IO<WalProgress>:
        _closed : Unit <- File.close(file)
        return WalStop{Done{state}}
    case False{}:
      wal.frames.remaining(file, size, offset, state, path,
        (size - offset : Nat))

def wal.frames(
  +fuel: Nat,
  +size: Nat,
  +path: String,
  state: WalState
) -> IO(Result<&1, &1, U32 & String, Db.RotRes>):
  match fuel:
    case 0n:
      match state:
        case WalAt{file, _, _}:
          do IO<Result<&1, &1, U32 & String, Db.RotRes>>:
            _closed : Unit <- File.close(file)
            return Fail{(U32.from_nat(7n), "WAL frame limit exceeded")}
        case WalAfter{WalStop{result}}:
          IO.pure(Result<&1, &1, U32 & String, Db.RotRes>, result)
        case WalAfter{WalMore{file, _, _}}:
          do IO<Result<&1, &1, U32 & String, Db.RotRes>>:
            _closed : Unit <- File.close(file)
            return Fail{(U32.from_nat(7n), "WAL frame limit exceeded")}
    case 1n+rest:
      match state:
        case WalAt{file, +offset, res}:
          do IO<Result<&1, &1, U32 & String, Db.RotRes>>:
            progress : WalProgress <- wal.frames.end(
              Nat.is_eq(offset, size), file, size, offset, res, path)
            wal.frames(rest, size, path, WalAfter{progress})
        case WalAfter{WalStop{result}}:
          IO.pure(Result<&1, &1, U32 & String, Db.RotRes>, result)
        case WalAfter{WalMore{file, offset, res}}:
          wal.frames(rest, size, path, WalAt{file, offset, res})

def wal.header.decoded(
  result: Result<&1, &1, Wal.Error, Unit>,
  file: File,
  +size: Nat,
  +path: String
) -> IO(Result<&1, &1, U32 & String, Db.RotRes>):
  match result:
    case Fail{_}:
      do IO<Result<&1, &1, U32 & String, Db.RotRes>>:
        _closed : Unit <- File.close(file)
        return Fail{(U32.from_nat(3n), "unsupported WAL format")}
    case Done{Unit{}}:
      wal.frames(Nat.add(Nat.div(size, 18n), 4n), size, path,
        WalAt{file, 8n, wal.empty()})

def wal.header(
  pair: File & Result<&1, &1, U32 & String, ExactResult>,
  +size: Nat,
  +path: String
) -> IO(Result<&1, &1, U32 & String, Db.RotRes>):
  match pair:
    case (file, Fail{error}):
      do IO<Result<&1, &1, U32 & String, Db.RotRes>>:
        _closed : Unit <- File.close(file)
        return Fail{error}
    case (file, Done{ExactResult{_, False{}}}):
      do IO<Result<&1, &1, U32 & String, Db.RotRes>>:
        _closed : Unit <- File.close(file)
        _truncated : Unit <- IO.try(Unit, Fs.truncate(path, 0n))
        _synced : Unit <- IO.try(Unit, Fs.fsync(path))
        return Done{wal.empty()}
    case (file, Done{ExactResult{bytes, True{}}}):
      wal.header.decoded(Wal.decode_header(bytes), file, size, path)

def wal.open.present(
  present: Bool,
  +path: String
) -> IO(Result<&1, &1, U32 & String, Db.RotRes>):
  match present:
    case False{}:
      IO.pure(Result<&1, &1, U32 & String, Db.RotRes>, Done{wal.empty()})
    case True{}:
      do IO<Result<&1, &1, U32 & String, Db.RotRes>>:
        size : Nat <- IO.try(Nat, Fs.file_size(path))
        file : File <- IO.try(File, File.open(path, "r"))
        pair : File & Result<&1, &1, U32 & String, ExactResult> <- exact.start(file, 8n)
        wal.header(pair, size, path)

# Handle wal open in the database recovery effects.
def wal_open(+dir: String) -> IO(Result<&1, &1, U32 & String, Db.RotRes>):
  do IO<Result<&1, &1, U32 & String, Db.RotRes>>:
    present : Bool <- IO.try(Bool, Fs.exists(Db.wal_path(dir)))
    wal.open.present(present, Db.wal_path(dir))

# --- Tmp sweep (best-effort) ---

# Handle tmp pick in the database recovery effects.
def tmp_pick(keep: Bool, +name: String, +acc: List<&2, String>) -> List<&2, String>:
  match keep:
    case True{}:
      Con{name, acc}
    case False{}:
      acc

# Handle tmp some in the database recovery effects.
def tmp_some(+ok: Bool, +name: String) -> Maybe<&2, String>:
  match ok:
    case True{}:
      Some{name}
    case False{}:
      None{}

# Handle tmp map list in the database recovery effects.
def tmp_map_list(xs: List<&1, String>) -> List<&2, Maybe<&2, String>>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      Con{tmp_some(String.ends_with(h, ".tmp"), h), tmp_map_list(t)}

# Handle cat go in the database recovery effects.
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

# Handle tmp names in the database recovery effects.
def tmp_names(xs: List<&1, String>) -> List<&2, String>:
  cat_go(tmp_map_list(xs))

# Handle sweep one in the database recovery effects.
def sweep_one(res: Result<&1, &1, U32 & String, List<String>>, +dir: String) -> IO(Unit):
  match res:
    case Fail{e}:
      IO.pure(Unit, Unit{})
    case Done{ns}:
      do IO<Unit>:
        _ign : Result<&1, &1, U32 & String, Unit> <- CompactIo.remove_list(Compact.prefix(tmp_names(ns), dir))
        IO.pure(Unit, Unit{})

# Handle sweep get in the database recovery effects.
def sweep_get(+dir: String, +sub: String) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, List<String>> <- Fs.read_dir(dir ++ "/" ++ sub)
    sweep_one(r, dir ++ "/" ++ sub)

# Handle sweep cnt in the database recovery effects.
def sweep_cnt(res: Result<&1, &1, U32 & String, Nat>, +dir: String, +sub: String) -> IO(Unit):
  match res:
    case Fail{e}:
      IO.pure(Unit, Unit{})
    case Done{n}:
      sweep_get(dir, sub)

# Handle sweep dir in the database recovery effects.
def sweep_dir(+dir: String, +sub: String) -> IO(Unit):
  do IO<Unit>:
    c : Result<&1, &1, U32 & String, Nat> <- Fs.read_dir_count(dir ++ "/" ++ sub)
    sweep_cnt(c, dir, sub)

# --- Open assembly ---

# Handle wal part in the database recovery effects.
def wal_part(+dir: String) -> IO(Result<&1, &1, U32 & String, Db.RotRes>):
  do IO<Result<&1, &1, U32 & String, Db.RotRes>>:
    _initialized : Unit <- IO.try(Unit, DbIo.wal_initialize(dir))
    wal_open(dir)

# Open assemble for the database recovery effects.
def open_assemble(
  res: Db.RotRes,
  +dir: String,
  +mfst: Manifest.Manifest,
  levels: List<&2, List<&2, Sstable.Table>>
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match res:
    case Db.Rot{mem, frozen, mc, fc}:
      do IO<Result<&1, &1, U32 & String, Db.Db>>:
        return Done{Db.Db{dir, mem, frozen, Db.default_batch_cap(), Nil{}, levels, Pure.count_gen(Pure.mfst_lists(mfst)), Manifest.token(mfst), mc, fc}}

# Open levels checked for the database recovery effects.
def open_levels_checked(
  ok: Bool,
  +dir: String,
  +mfst: Manifest.Manifest,
  levels: List<&2, List<&2, Sstable.Table>>
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match ok:
    case False{}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{(U32.from_nat(6n), "overlapping tables in L1+ manifest")})
    case True{}:
      do IO<Result<&1, &1, U32 & String, Db.Db>>:
        res : Db.RotRes <- IO.try(Db.RotRes, wal_part(dir))
        open_assemble(res, dir, mfst, levels)

# Open levels for the database recovery effects.
def open_levels(+dir: String, +mfst: Manifest.Manifest) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  do IO<Result<&1, &1, U32 & String, Db.Db>>:
    +levels : List<&2, List<&2, Sstable.Table>> <- load_levels(Pure.mfst_lists(mfst), 0n, dir, Nil{})
    open_levels_checked(Pure.l1_plus_disjoint(levels), dir, mfst, levels)

# Open names go for the database recovery effects.
def open_names_go(ok: Bool, +dir: String, +mfst: Manifest.Manifest) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match ok:
    case True{}:
      open_levels(dir, mfst)
    case False{}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{(U32.from_nat(5n), "bad manifest names")})

# Handle sweep root go in the database recovery effects.
def sweep_root_go(+dir: String) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, List<String>> <- Fs.read_dir(dir)
    sweep_one(r, dir)

# Handle sweep root cnt in the database recovery effects.
def sweep_root_cnt(res: Result<&1, &1, U32 & String, Nat>, +dir: String) -> IO(Unit):
  match res:
    case Fail{e}:
      IO.pure(Unit, Unit{})
    case Done{n}:
      sweep_root_go(dir)

# Handle sweep root in the database recovery effects.
def sweep_root(+dir: String) -> IO(Unit):
  do IO<Unit>:
    c : Result<&1, &1, U32 & String, Nat> <- Fs.read_dir_count(dir)
    sweep_root_cnt(c, dir)

# Open db for the database recovery effects.
def open_db(+dir: String) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  do IO<Result<&1, &1, U32 & String, Db.Db>>:
    _u0 : Unit <- IO.try(Unit, Flush.ensure_dir(dir))
    _s0 : Unit <- sweep_dir(dir, "l0")
    _s1 : Unit <- sweep_dir(dir, "l1")
    _s2 : Unit <- sweep_dir(dir, "l2")
    _s3 : Unit <- sweep_dir(dir, "l3")
    _s4 : Unit <- sweep_root(dir)
    +m : Manifest.Manifest <- IO.try(Manifest.Manifest, Flush.load_mfst(dir ++ "/MANIFEST"))
    open_names_go(Pure.manifest_names_ok(Pure.mfst_lists(m), 0n), dir, m)

# --- Maintenance (synchronous auto flush/compact + stall) ---
# One drain round always suffices (L0 >= 8 > 4, so the gated compaction
# fires and empties L0) — no loop, no cycle.

# Flush dec for the database recovery effects.
def flush_dec(full: Bool, +db: Db.Db) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match full:
    case True{}:
      Flush.flush(db)
    case False{}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Done{db})

# Flush gate for the database recovery effects.
def flush_gate(db: Db.Db) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match db:
    case Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, +mem_count, frozen_count}:
      flush_dec(Nat.is_lt(4096n, mem_count), Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count})

# Handle l0 full in the database recovery effects.
def l0_full(db: Db.Db) -> Bool:
  match db:
    case Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}:
      Nat.is_lt(7n, List.length(&2, Sstable.Table, Compact.l0list(levels)))

# Handle drain once in the database recovery effects.
def drain_once(+db: Db.Db) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  do IO<Result<&1, &1, U32 & String, Db.Db>>:
    f : Db.Db <- IO.try(Db.Db, Flush.flush(db))
    c : Db.Db <- IO.try(Db.Db, CompactIo.compact(f))
    return Done{c}

# Handle drain pick in the database recovery effects.
def drain_pick(full: Bool, +db: Db.Db) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match full:
    case True{}:
      drain_once(db)
    case False{}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Done{db})

# Handle drain go in the database recovery effects.
def drain_go(+db: Db.Db) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  drain_pick(l0_full(db), db)

# Handle maintain in the database recovery effects.
def maintain(+db: Db.Db) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  do IO<Result<&1, &1, U32 & String, Db.Db>>:
    d : Db.Db <- IO.try(Db.Db, drain_go(db))
    f : Db.Db <- IO.try(Db.Db, flush_gate(d))
    CompactIo.compact(f)

# Handle maintain unwrap in the database recovery effects.
def maintain_unwrap(res: Result<&1, &1, U32 & String, Db.Db>) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match res:
    case Fail{e}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{e})
    case Done{db}:
      maintain(db)

# Handle write in the database recovery effects.
def write(+db: Db.Db, +batch: Wal.Batch) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  do IO<Result<&1, &1, U32 & String, Db.Db>>:
    r : Result<&1, &1, U32 & String, Db.Db> <- DbIo.db_write(db, batch)
    maintain_unwrap(r)

# Handle put in the database recovery effects.
def put(+db: Db.Db, +key: String, +val: String) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  write(db, Wal.Batch{Con{Wal.Put{key, val}, Nil{}}})

# Handle del in the database recovery effects.
def del(+db: Db.Db, +key: String) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  write(db, Wal.Batch{Con{Wal.Del{key}, Nil{}}})

# --- Closed-vector laws live in laws/Recover.bend (spec law 7) ---

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
import ./FsPolicy.bend as FsPolicy
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

# Returns the typed corruption code for malformed WAL data.
def wal_corruption_error_code() -> U32:
  4294967290

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

# Represents loadtablesstate data in recover.
type LoadTablesState is Type:
  LoadTablesNames{names: List<&2, String>, ldir: String, dir: String, acc: List<&2, Sstable.Table>}
  LoadTablesRead{result: Result<&1, &1, U32 & String, Sstable.Table>, names: List<&2, String>, ldir: String, dir: String, acc: List<&2, Sstable.Table>}

# Represents loadlevelsstate data in recover.
type LoadLevelsState is Type:
  LoadLevelsNames{levels: List<&2, List<&2, String>>, idx: Nat, dir: String, acc: List<&2, List<&2, Sstable.Table>>}
  LoadLevelsPath{ldir: Maybe<&2, String>, names: List<&2, String>, levels: List<&2, List<&2, String>>, idx: Nat, dir: String, acc: List<&2, List<&2, Sstable.Table>>}
  LoadLevelsRead{result: Result<&1, &1, U32 & String, List<&2, Sstable.Table>>, levels: List<&2, List<&2, String>>, idx: Nat, dir: String, acc: List<&2, List<&2, Sstable.Table>>}

# Loads the SSTables referenced by a Manifest and propagates failures.
def load_tables(fuel: Nat, state: LoadTablesState) -> IO(Result<&1, &1, U32 & String, List<&2, Sstable.Table>>):
  match fuel:
    case 0n:
      IO.pure(Result<&1, &1, U32 & String, List<&2, Sstable.Table>>, Fail{(U32.from_nat(7n), "table recovery limit exceeded")})
    case 1n+rest:
      match state:
        case LoadTablesNames{names, +ldir, +dir, acc}:
          match names:
            case Nil{}:
              IO.pure(Result<&1, &1, U32 & String, List<&2, Sstable.Table>>, Done{List.reverse(&2, Sstable.Table, acc)})
            case Con{+name, tail}:
              do IO<Result<&1, &1, U32 & String, List<&2, Sstable.Table>>>:
                table : Result<&1, &1, U32 & String, Sstable.Table> <- SstStreamIo.read_table(dir ++ "/" ++ ldir ++ "/" ++ name)
                load_tables(rest, LoadTablesRead{table, tail, ldir, dir, acc})
        case LoadTablesRead{result, names, +ldir, +dir, acc}:
          match result:
            case Fail{error}:
              IO.pure(Result<&1, &1, U32 & String, List<&2, Sstable.Table>>, Fail{error})
            case Done{table}:
              load_tables(rest, LoadTablesNames{names, ldir, dir, Con{table, acc}})

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

# Builds recovered levels from the Manifest table entries.
def load_levels(
  fuel: Nat,
  state: LoadLevelsState,
) -> IO(Result<&1, &1, U32 & String, List<&2, List<&2, Sstable.Table>>>):
  match fuel:
    case 0n:
      IO.pure(Result<&1, &1, U32 & String, List<&2, List<&2, Sstable.Table>>>, Fail{(U32.from_nat(7n), "level recovery limit exceeded")})
    case 1n+rest:
      match state:
        case LoadLevelsNames{levels, +idx, +dir, acc}:
          match levels:
            case Nil{}:
              IO.pure(Result<&1, &1, U32 & String, List<&2, List<&2, Sstable.Table>>>, Done{List.reverse(&2, List<&2, Sstable.Table>, acc)})
            case Con{+names, tail}:
              load_levels(rest, LoadLevelsPath{ldir_of(idx), names, tail, Nat.add(idx, 1n), dir, acc})
        case LoadLevelsPath{ldir, +names, levels, idx, +dir, acc}:
          match ldir:
            case None{}:
              IO.pure(Result<&1, &1, U32 & String, List<&2, List<&2, Sstable.Table>>>, Fail{(U32.from_nat(5n), "bad manifest names")})
            case Some{ldir}:
              do IO<Result<&1, &1, U32 & String, List<&2, List<&2, Sstable.Table>>>>:
                tables : Result<&1, &1, U32 & String, List<&2, Sstable.Table>> <- load_tables(Nat.add(Nat.mul(2n, List.length(&2, String, names)), 1n), LoadTablesNames{names, ldir, dir, Nil{}})
                load_levels(rest, LoadLevelsRead{tables, levels, idx, dir, acc})
        case LoadLevelsRead{result, levels, idx, +dir, acc}:
          match result:
            case Fail{error}:
              IO.pure(Result<&1, &1, U32 & String, List<&2, List<&2, Sstable.Table>>>, Fail{error})
            case Done{tables}:
              load_levels(rest, LoadLevelsNames{levels, idx, dir, Con{tables, acc}})

def wal.empty() -> Db.RotRes:
  Db.Rot{MemTable.empty(), MemTable.empty(), 0n, 0n}

def exact.start(file: File, +needed: Nat) -> IO(File & Result<&1, &1, U32 & String, ExactResult>):
  exact.loop(Nat.add(Nat.mul(2n, needed), 1n), ExactNeed{file, needed, Nil{}})

def wal.truncate.synced(
  result: Result<&1, &1, U32 & String, Unit>,
  state: Db.RotRes
) -> IO(WalProgress):
  match result:
    case Fail{error}:
      IO.pure(WalProgress, WalStop{Fail{error}})
    case Done{Unit{}}:
      IO.pure(WalProgress, WalStop{Done{state}})

def wal.truncate.result(
  result: Result<&1, &1, U32 & String, Unit>,
  +path: String,
  state: Db.RotRes
) -> IO(WalProgress):
  match result:
    case Fail{error}:
      IO.pure(WalProgress, WalStop{Fail{error}})
    case Done{Unit{}}:
      do IO<WalProgress>:
        synced : Result<&1, &1, U32 & String, Unit> <- Fs.fsync(path)
        wal.truncate.synced(synced, state)

def wal.truncate(
  +path: String,
  +offset: Nat,
  state: Db.RotRes
) -> IO(WalProgress):
  do IO<WalProgress>:
    truncated : Result<&1, &1, U32 & String, Unit> <- Fs.truncate(path, offset)
    wal.truncate.result(truncated, path, state)

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
        return WalStop{Fail{(wal_corruption_error_code(), "corrupt WAL frame")}}
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
        return WalStop{Fail{(wal_corruption_error_code(), "WAL frame length out of bounds")}}
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
        return WalStop{Fail{(wal_corruption_error_code(), "malformed WAL frame length")}}
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
        return Fail{(wal_corruption_error_code(), "unsupported WAL format")}
    case Done{Unit{}}:
      wal.frames(Nat.add(Nat.div(size, 18n), 4n), size, path,
        WalAt{file, 8n, wal.empty()})

def wal.header.synced(
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, U32 & String, Db.RotRes>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Db.RotRes>, Fail{error})
    case Done{Unit{}}:
      IO.pure(Result<&1, &1, U32 & String, Db.RotRes>, Done{wal.empty()})

def wal.header.truncated(
  result: Result<&1, &1, U32 & String, Unit>,
  +path: String
) -> IO(Result<&1, &1, U32 & String, Db.RotRes>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Db.RotRes>, Fail{error})
    case Done{Unit{}}:
      do IO<Result<&1, &1, U32 & String, Db.RotRes>>:
        synced : Result<&1, &1, U32 & String, Unit> <- Fs.fsync(path)
        wal.header.synced(synced)

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
        truncated : Result<&1, &1, U32 & String, Unit> <- Fs.truncate(path, 0n)
        wal.header.truncated(truncated, path)
    case (file, Done{ExactResult{bytes, True{}}}):
      wal.header.decoded(Wal.decode_header(bytes), file, size, path)

def wal.open.file(
  size: Nat,
  opened: Result<&1, &1, U32 & String, File>,
  +path: String
) -> IO(Result<&1, &1, U32 & String, Db.RotRes>):
  match opened:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Db.RotRes>, Fail{error})
    case Done{file}:
      do IO<Result<&1, &1, U32 & String, Db.RotRes>>:
        pair : File & Result<&1, &1, U32 & String, ExactResult> <- exact.start(file, 8n)
        wal.header(pair, size, path)

def wal.open.size(
  result: Result<&1, &1, U32 & String, Nat>,
  +path: String
) -> IO(Result<&1, &1, U32 & String, Db.RotRes>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Db.RotRes>, Fail{error})
    case Done{size}:
      do IO<Result<&1, &1, U32 & String, Db.RotRes>>:
        opened : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
        wal.open.file(size, opened, path)

def wal.open.present(
  present: Bool,
  +path: String
) -> IO(Result<&1, &1, U32 & String, Db.RotRes>):
  match present:
    case False{}:
      IO.pure(Result<&1, &1, U32 & String, Db.RotRes>, Done{wal.empty()})
    case True{}:
      do IO<Result<&1, &1, U32 & String, Db.RotRes>>:
        size : Result<&1, &1, U32 & String, Nat> <- Fs.file_size(path)
        wal.open.size(size, path)

def wal_open.exists(
  result: Result<&1, &1, U32 & String, Bool>,
  +dir: String
) -> IO(Result<&1, &1, U32 & String, Db.RotRes>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Db.RotRes>, Fail{error})
    case Done{present}:
      wal.open.present(present, Db.wal_path(dir))

# Handle wal open in the database recovery effects.
def wal_open(+dir: String) -> IO(Result<&1, &1, U32 & String, Db.RotRes>):
  do IO<Result<&1, &1, U32 & String, Db.RotRes>>:
    present : Result<&1, &1, U32 & String, Bool> <- Fs.exists(Db.wal_path(dir))
    wal_open.exists(present, dir)

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

def wal_part.initialized(
  result: Result<&1, &1, U32 & String, Unit>,
  +dir: String
) -> IO(Result<&1, &1, U32 & String, Db.RotRes>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Db.RotRes>, Fail{error})
    case Done{Unit{}}:
      wal_open(dir)

# Splits the WAL replay stream at the recovery boundary.
def wal_part(+dir: String) -> IO(Result<&1, &1, U32 & String, Db.RotRes>):
  do IO<Result<&1, &1, U32 & String, Db.RotRes>>:
    initialized : Result<&1, &1, U32 & String, Unit> <- DbIo.wal_initialize(dir)
    wal_part.initialized(initialized, dir)

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

def open_levels.wal(
  result: Result<&1, &1, U32 & String, Db.RotRes>,
  +dir: String,
  +mfst: Manifest.Manifest,
  levels: List<&2, List<&2, Sstable.Table>>
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{error})
    case Done{recovered}:
      open_assemble(recovered, dir, mfst, levels)

# Loads Manifest levels and checks WAL recovery errors.
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
        recovered : Result<&1, &1, U32 & String, Db.RotRes> <- wal_part(dir)
        open_levels.wal(recovered, dir, mfst, levels)

def open_levels.loaded(
  result: Result<&1, &1, U32 & String, List<&2, List<&2, Sstable.Table>>>,
  +dir: String,
  +mfst: Manifest.Manifest
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{error})
    case Done{+levels}:
      open_levels_checked(Pure.l1_plus_disjoint(levels), dir, mfst, levels)

def open_levels.fuel(+mfst: Manifest.Manifest) -> Nat:
  Nat.add(Nat.mul(3n, List.length(&2, List<&2, String>, Pure.mfst_lists(mfst))), 1n)

# Opens levels through the legacy recovery result path.
def open_levels(+dir: String, +mfst: Manifest.Manifest) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  do IO<Result<&1, &1, U32 & String, Db.Db>>:
    levels : Result<&1, &1, U32 & String, List<&2, List<&2, Sstable.Table>>> <- load_levels(open_levels.fuel(mfst), LoadLevelsNames{Pure.mfst_lists(mfst), 0n, dir, Nil{}})
    open_levels.loaded(levels, dir, mfst)

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

def open_db.swept(+dir: String, +mfst: Manifest.Manifest) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  do IO<Result<&1, &1, U32 & String, Db.Db>>:
    _s0 : Unit <- sweep_dir(dir, "l0")
    _s1 : Unit <- sweep_dir(dir, "l1")
    _s2 : Unit <- sweep_dir(dir, "l2")
    _s3 : Unit <- sweep_dir(dir, "l3")
    _s4 : Unit <- sweep_root(dir)
    open_names_go(Pure.manifest_names_ok(Pure.mfst_lists(mfst), 0n), dir, mfst)

def open_db.manifest(
  result: Result<&1, &1, U32 & String, Manifest.Manifest>,
  +dir: String,
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{error})
    case Done{mfst}:
      open_db.swept(dir, mfst)

def open_db.ensured(
  ensured: Result<&1, &1, U32 & String, Unit>,
  +dir: String
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match ensured:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{error})
    case Done{Unit{}}:
      do IO<Result<&1, &1, U32 & String, Db.Db>>:
        manifest : Result<&1, &1, U32 & String, Manifest.Manifest> <- Flush.load_mfst(dir ++ "/MANIFEST")
        open_db.manifest(manifest, dir)

# Opens the legacy database and applies best-effort recovery cleanup.
def open_db(+dir: String) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  do IO<Result<&1, &1, U32 & String, Db.Db>>:
    ensured : Result<&1, &1, U32 & String, Unit> <- Flush.ensure_dir(dir)
    open_db.ensured(ensured, dir)

def sweep_checked_path.select(root: Bool, +dir: String, +subdir: String) -> String:
  match root:
    case True{}:
      dir
    case False{}:
      dir ++ "/" ++ subdir

# Removes one temporary path and propagates removal failures.
def sweep_checked_path(+dir: String, +subdir: String) -> String:
  sweep_checked_path.select(String.eq(subdir, "."), dir, subdir)

# Removes every temporary path with checked errors.
def sweep_checked_remove_list(+names: List<&2, String>) -> IO(Result<&1, &1, U32 & String, Unit>):
  CompactIo.remove_list_strict_start((
    Nat.add(Nat.mul(2n, List.length(&2, String, names)), 2n), names
  ))

# Represents sweepreadstate data in recover.
type SweepReadState is Type:
  SweepReadNeed{path: String, idx: Nat, remaining: Nat, names: List<String>}
  SweepReadResult{result: Result<&1, &1, U32 & String, String>, path: String, idx: Nat, remaining: Nat, names: List<String>}

# Reads a directory listing through checked indexed IO.
def sweep_read_checked(fuel: Nat, state: SweepReadState) -> IO(Result<&1, &1, U32 & String, List<String>>):
  match fuel:
    case 0n:
      IO.pure(Result<&1, &1, U32 & String, List<String>>, Fail{(7, "recovery directory read limit exceeded")})
    case 1n+rest:
      match state:
        case SweepReadNeed{+path, +idx, remaining, names}:
          match remaining:
            case 0n:
              IO.pure(Result<&1, &1, U32 & String, List<String>>,
                Done{List.reverse(&1, String, names)})
            case 1n+more:
              do IO<Result<&1, &1, U32 & String, List<String>>>:
                name : Result<&1, &1, U32 & String, String> <- Fs.read_dir_at(path, idx)
                sweep_read_checked(rest, SweepReadResult{name, path, Nat.add(idx, 1n), more, names})
        case SweepReadResult{result, path, idx, remaining, names}:
          match result:
            case Fail{error}:
              IO.pure(Result<&1, &1, U32 & String, List<String>>, Fail{error})
            case Done{name}:
              sweep_read_checked(rest, SweepReadNeed{path, idx, remaining,
                Fs.grab_name(name, names)})

# Handles the checked directory-entry count result.
def sweep_read_checked_count(
  result: Result<&1, &1, U32 & String, Nat>,
  +path: String
) -> IO(Result<&1, &1, U32 & String, List<String>>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, List<String>>, Fail{error})
    case Done{+count}:
      sweep_read_checked(Nat.add(Nat.mul(2n, Nat.add(count, 1n)), 1n),
        SweepReadNeed{path, 0n, Nat.add(count, 1n), Nil{}})

# Reads one indexed directory entry and preserves errors.
def sweep_read_checked_path(+path: String) -> IO(Result<&1, &1, U32 & String, List<String>>):
  do IO<Result<&1, &1, U32 & String, List<String>>>:
    count : Result<&1, &1, U32 & String, Nat> <- Fs.read_dir_count(path)
    sweep_read_checked_count(count, path)

# Converts a directory-read failure to the recovery result.
def sweep_checked_read_error(
  allow_missing: Bool,
  +code: U32,
  message: String
) -> IO(Result<&1, &1, U32 & String, Unit>):
  IO.pure(Result<&1, &1, U32 & String, Unit>,
    FsPolicy.optional_directory_result(allow_missing,
      U32.is_eq(code, 2) || U32.is_eq(code, 20), code, message))

def sweep_checked_dir.result(
  result: Result<&1, &1, U32 & String, List<String>>,
  allow_missing: Bool,
  +path: String
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match result:
    case Fail{(+code, message)}:
      sweep_checked_read_error(allow_missing, code, message)
    case Done{names}:
      sweep_checked_remove_list(Compact.prefix(tmp_names(names), path))

# Sweeps temporary files from one optional level directory.
def sweep_checked_dir(+dir: String, +subdir: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  +path = sweep_checked_path(dir, subdir)
  do IO<Result<&1, &1, U32 & String, Unit>>:
    listed : Result<&1, &1, U32 & String, List<String>> <- sweep_read_checked_path(path)
    sweep_checked_dir.result(listed, Bool.not(String.eq(subdir, ".")), path)

# Represents sweepcheckedstate data in recover.
type SweepCheckedState is Type:
  SweepCheckedDirs{dirs: List<&2, String>, dir: String}
  SweepCheckedResult{result: Result<&1, &1, U32 & String, Unit>, dirs: List<&2, String>, dir: String}

# Sweeps temporary files from all optional level directories.
def sweep_checked_dirs(
  fuel: Nat,
  state: SweepCheckedState
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match fuel:
    case 0n:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{(U32.from_nat(7n), "recovery sweep limit exceeded")})
    case 1n+rest:
      match state:
        case SweepCheckedDirs{dirs, +dir}:
          match dirs:
            case Nil{}:
              IO.pure(Result<&1, &1, U32 & String, Unit>, Done{Unit{}})
            case Con{subdir, tail}:
              do IO<Result<&1, &1, U32 & String, Unit>>:
                swept : Result<&1, &1, U32 & String, Unit> <- sweep_checked_dir(dir, subdir)
                sweep_checked_dirs(rest, SweepCheckedResult{swept, tail, dir})
        case SweepCheckedResult{result, dirs, +dir}:
          match result:
            case Fail{error}:
              IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{error})
            case Done{Unit{}}:
              sweep_checked_dirs(rest, SweepCheckedDirs{dirs, dir})

# Runs the checked temporary-file sweep across database levels.
def sweep_checked(+dir: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  sweep_checked_dirs(11n,
    SweepCheckedDirs{Con{"l0", Con{"l1", Con{"l2", Con{"l3", Con{".", Nil{}}}}}}, dir})

# Continues existing-open recovery after the checked sweep.
def open_existing_sweep_result(
  result: Result<&1, &1, U32 & String, Unit>,
  +dir: String,
  +manifest: Manifest.Manifest
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{error})
    case Done{Unit{}}:
      open_names_go(Pure.manifest_names_ok(Pure.mfst_lists(manifest), 0n), dir, manifest)

# Loads the Manifest before opening existing database levels.
def open_existing_manifest(
  result: Result<&1, &1, U32 & String, Manifest.Manifest>,
  +dir: String
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{error})
    case Done{manifest}:
      do IO<Result<&1, &1, U32 & String, Db.Db>>:
        swept : Result<&1, &1, U32 & String, Unit> <- sweep_checked(dir)
        open_existing_sweep_result(swept, dir, manifest)

# Recovers an existing database and propagates filesystem errors.
def open_existing_checked(
  manifest_present: Bool,
  +dir: String
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match manifest_present:
    case False{}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{(U32.from_nat(2n), "manifest missing")})
    case True{}:
      do IO<Result<&1, &1, U32 & String, Db.Db>>:
        manifest : Result<&1, &1, U32 & String, Manifest.Manifest> <- Flush.load_mfst(dir ++ "/MANIFEST")
        open_existing_manifest(manifest, dir)

def open_existing.present(
  result: Result<&1, &1, U32 & String, Bool>,
  +dir: String
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{error})
    case Done{present}:
      open_existing_checked(present, dir)

# Opens an existing database while the caller retains its lock.
def open_existing_locked(+dir: String) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  do IO<Result<&1, &1, U32 & String, Db.Db>>:
    present : Result<&1, &1, U32 & String, Bool> <- Fs.exists(dir ++ "/MANIFEST")
    open_existing.present(present, dir)

# Initializes the database state after creating its directories.
def create_initialized(
  synced: Result<&1, &1, U32 & String, Unit>,
  +dir: String,
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match synced:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{error})
    case Done{Unit{}}:
      open_existing_checked(True{}, dir)

# Writes and publishes the initial Manifest.
def create_published(
  renamed: Result<&1, &1, U32 & String, Unit>,
  +dir: String,
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match renamed:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{error})
    case Done{Unit{}}:
      do IO<Result<&1, &1, U32 & String, Db.Db>>:
        synced : Result<&1, &1, U32 & String, Unit> <- Fs.fsync(dir)
        create_initialized(synced, dir)

# Initializes the WAL after publishing the Manifest.
def create_written(
  written: Result<&1, &1, U32 & String, Unit>,
  +dir: String,
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match written:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{error})
    case Done{Unit{}}:
      do IO<Result<&1, &1, U32 & String, Db.Db>>:
        renamed : Result<&1, &1, U32 & String, Unit> <- Fs.rename(dir ++ "/MANIFEST.tmp", dir ++ "/MANIFEST")
        create_published(renamed, dir)

# Creates a new database without acquiring another lock.
def create_locked(+dir: String) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  do IO<Result<&1, &1, U32 & String, Db.Db>>:
    written : Result<&1, &1, U32 & String, Unit> <- Flush.write_manifest(dir ++ "/MANIFEST.tmp", Manifest.M{Nil{}})
    create_written(written, dir)

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

# Flushes one full MemTable and returns the updated database.
def drain_once.flushed(
  result: Result<&1, &1, U32 & String, Db.Db>
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{error})
    case Done{db}:
      CompactIo.compact(db)

# Flushes one full MemTable and returns the updated database.
def drain_once(+db: Db.Db) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  do IO<Result<&1, &1, U32 & String, Db.Db>>:
    flushed : Result<&1, &1, U32 & String, Db.Db> <- Flush.flush(db)
    drain_once.flushed(flushed)

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

def maintain.flushed(
  result: Result<&1, &1, U32 & String, Db.Db>
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{error})
    case Done{db}:
      CompactIo.compact(db)

def maintain.drained(
  result: Result<&1, &1, U32 & String, Db.Db>
) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Db.Db>, Fail{error})
    case Done{db}:
      do IO<Result<&1, &1, U32 & String, Db.Db>>:
        flushed : Result<&1, &1, U32 & String, Db.Db> <- flush_gate(db)
        maintain.flushed(flushed)

# Runs the required flush and compaction maintenance.
def maintain(+db: Db.Db) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  do IO<Result<&1, &1, U32 & String, Db.Db>>:
    drained : Result<&1, &1, U32 & String, Db.Db> <- drain_go(db)
    maintain.drained(drained)

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

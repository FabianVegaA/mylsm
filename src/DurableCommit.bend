import Base
import ./Db.bend as Db
import ./Wal.bend as Wal

# Identifies the durability boundary reached by a commit.
type Stage is Data:
  EncodingRejected{error: Wal.Error}
  AppendRejected{code: U32, message: String}
  AppendUnknown{code: U32, message: String}
  DurableAppend{}

# Applies mutations only after the WAL commit stage is durable.
def apply(pair: Stage & List<&2, Wal.Mut>, +db: Db.Db) -> Db.Db & Stage:
  match pair:
    case (stage, muts):
      match stage:
        case EncodingRejected{error}:
          (db, EncodingRejected{error})
        case AppendRejected{code, message}:
          (db, AppendRejected{code, message})
        case AppendUnknown{code, message}:
          (db, AppendUnknown{code, message})
        case DurableAppend{}:
          match db:
            case Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}:
              (Db.apply_done(Db.apply_and_rotate(muts, mem, frozen, mem_count, frozen_count), dir,
                batch_cap, bcache, levels, flushed, manifest_token), DurableAppend{})

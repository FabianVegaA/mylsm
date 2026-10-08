import Base
import ../src/Db.bend as Db
import ../src/DurableCommit.bend as Commit
import ../src/Wal.bend as Wal

# Encoding rejection leaves the database unchanged.
law encoding_rejection_preserves_database:
  for db: Db.Db
  for mutations: List<&2, Wal.Mut>
  for error: Wal.Error
  {Commit.apply((Commit.EncodingRejected{error}, mutations), db) ==
    (db, Commit.EncodingRejected{error}) : Db.Db & Commit.Stage}

# Append rejection leaves the database unchanged.
law append_rejection_preserves_database:
  for db: Db.Db
  for mutations: List<&2, Wal.Mut>
  for code: U32
  for message: String
  {Commit.apply((Commit.AppendRejected{code, message}, mutations), db) ==
    (db, Commit.AppendRejected{code, message}) : Db.Db & Commit.Stage}

# An uncertain append leaves the in-memory database unchanged.
law uncertain_append_preserves_database:
  for db: Db.Db
  for mutations: List<&2, Wal.Mut>
  for code: U32
  for message: String
  {Commit.apply((Commit.AppendUnknown{code, message}, mutations), db) ==
    (db, Commit.AppendUnknown{code, message}) : Db.Db & Commit.Stage}

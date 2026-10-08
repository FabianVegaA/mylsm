import Base
import ../src/DurableError.bend as DurableError

# States the missing path classification property.
law missing_path_classification:
  {DurableError.classify_open(
    DurableError.MissingPath{}, "open_existing", "/db"
  ) == DurableError.Error{DurableError.NotFound{}, "open_existing", "/db", 0, ""} : DurableError.Error}

# States the locked database classification property.
law locked_database_classification:
  {DurableError.classify_open(
    DurableError.Locked{}, "open_existing", "/db"
  ) == DurableError.Error{DurableError.Busy{}, "open_existing", "/db", 0, ""} : DurableError.Error}

# States the unknown format classification property.
law unknown_format_classification:
  {DurableError.classify_open(
    DurableError.UnknownFormat{}, "open_existing", "/db"
  ) == DurableError.Error{DurableError.UnsupportedFormat{}, "open_existing", "/db", 0, ""} : DurableError.Error}

# States the corrupt database classification property.
law corrupt_database_classification:
  {DurableError.classify_open(
    DurableError.CorruptData{}, "open_existing", "/db"
  ) == DurableError.Error{DurableError.Corruption{}, "open_existing", "/db", 0, ""} : DurableError.Error}

# States the unsupported manifest version classification property.
law unsupported_manifest_version_classification:
  {DurableError.classify_recovery(
    4294967295, "unsupported manifest version", "open_existing", "/db"
  ) == DurableError.Error{DurableError.UnsupportedFormat{}, "open_existing", "/db", 0, "unsupported manifest version"} : DurableError.Error}

# States the malformed manifest classification property.
law malformed_manifest_classification:
  {DurableError.classify_recovery(
    4294967294, "malformed manifest", "open_existing", "/db"
  ) == DurableError.Error{DurableError.Corruption{}, "open_existing", "/db", 0, "malformed manifest"} : DurableError.Error}

# States the manifest size limit classification property.
law manifest_size_limit_classification:
  {DurableError.classify_recovery(
    4294967293, "manifest size limit exceeded", "open_existing", "/db"
  ) == DurableError.Error{DurableError.ResourceLimit{}, "open_existing", "/db", 0, "manifest size limit exceeded"} : DurableError.Error}

# States the malformed sst classification property.
law malformed_sst_classification:
  {DurableError.classify_recovery(
    4294967292, "malformed SST", "open_existing", "/db/l0/table.sst"
  ) == DurableError.Error{DurableError.Corruption{}, "open_existing", "/db/l0/table.sst", 0, "malformed SST"} : DurableError.Error}

# States the invalid manifest names classification property.
law invalid_manifest_names_classification:
  {DurableError.classify_recovery(
    5, "bad manifest names", "open_existing", "/db"
  ) == DurableError.Error{DurableError.Corruption{}, "open_existing", "/db", 0, "invalid manifest names"} : DurableError.Error}

# States the malformed wal classification property.
law malformed_wal_classification:
  {DurableError.classify_recovery(
    4294967290, "unsupported WAL format", "open_existing", "/db/wal.log"
  ) == DurableError.Error{DurableError.Corruption{}, "open_existing", "/db/wal.log", 0, "malformed WAL"} : DurableError.Error}

# States the pre append failure classification property.
law pre_append_failure_classification:
  {DurableError.classify_write(
    DurableError.BeforeAppend{}, DurableError.WriteHostFailure{5, "io"},
    "write_batch", "/db"
  ) == DurableError.Error{DurableError.Io{}, "write_batch", "/db", 5, "io"} : DurableError.Error}

# States the post append failure classification property.
law post_append_failure_classification:
  {DurableError.classify_write(
    DurableError.AppendStarted{}, DurableError.WriteHostFailure{5, "io"},
    "write_batch", "/db"
  ) == DurableError.Error{DurableError.CommitUnknown{}, "write_batch", "/db", 5, "io"} : DurableError.Error}

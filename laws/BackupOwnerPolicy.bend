import Base
import ../src/transfer/BackupOwnerPolicy.bend as Policy
import ../src/transfer/Backup.bend as Backup

# Preserves a raw host error from an owner cursor connection failure.
law owner_connect_host_error_is_preserved:
  {Policy.source.error(Policy.ConnectHost{13, "denied"}) ==
    Backup.SourceFailure{13, "denied"} : Backup.Error}

# Maps unsupported owner sockets to a stable transport failure category.
law owner_unsupported_socket_is_not_a_resource_limit:
  {Policy.source.error(Policy.ReadUnsupported{}) ==
    Backup.SourceFailure{95, "owner snapshot cursor transport is unsupported"} :
    Backup.Error}

# Preserves stale-generation classification in the exported backup result.
law stale_owner_cursor_is_reported_as_stale:
  {Policy.source.error(Policy.StaleOwner{}) ==
    Backup.SourceFailure{116, "owner cursor generation is stale"} : Backup.Error}

# Does not turn a malformed cursor response into successful backup data.
law malformed_owner_cursor_response_fails_export:
  {Policy.source.error(Policy.MalformedResponse{}) ==
    Backup.SourceFailure{71, "owner cursor response is malformed"} : Backup.Error}

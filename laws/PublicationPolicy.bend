import Base
import ../src/transfer/PublicationPolicy.bend as PublicationPolicy

# Proves a failed exclusive rename leaves publication uncommitted.
law rename_failure_is_known:
  {PublicationPolicy.failure(PublicationPolicy.BeforeRename{}) ==
    PublicationPolicy.KnownFailure{} : PublicationPolicy.Failure}

# Proves a failed parent sync follows visible publication and is uncertain.
law post_rename_failure_is_uncertain:
  {PublicationPolicy.failure(PublicationPolicy.AfterRename{}) ==
    PublicationPolicy.CommitUnknown{} : PublicationPolicy.Failure}

import Base
import ../laws/CleanupPolicy.bend as Laws

def Laws.current_file_never_releases_cleanup_reservation(_succeeded):
  {==}

def Laws.failed_unlink_remains_pending():
  {==}

def Laws.successful_unlink_releases_pending_reservation():
  {==}

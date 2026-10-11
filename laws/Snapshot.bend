import Base
import ../src/scan/Snapshot.bend as Snapshot

# Admits a snapshot exactly at both configured retention limits.
law exact_retention_budget_is_accepted:
  {Snapshot.reserve(1n, 8n, 4n, 2n, 12n) == Snapshot.Retained{2n, 12n} : Snapshot.Decision}

# Rejects a new snapshot when all snapshot slots are reserved.
law snapshot_count_limit_is_rejected:
  {Snapshot.reserve(2n, 8n, 1n, 2n, 12n) == Snapshot.ResourceLimit{} : Snapshot.Decision}

# Rejects a snapshot that would exceed retained-byte capacity.
law retained_byte_limit_is_rejected:
  {Snapshot.reserve(1n, 9n, 4n, 2n, 12n) == Snapshot.ResourceLimit{} : Snapshot.Decision}

# Carries the first admitted reservation into the next admission decision.
law first_reservation_starts_aggregate_accounting:
  {Snapshot.reserve(0n, 0n, 8n, 3n, 12n) == Snapshot.Retained{1n, 8n} : Snapshot.Decision}

# Adds a later reservation to the retained-byte total from the earlier decision.
law later_reservation_accumulates_retained_bytes:
  {Snapshot.reserve(1n, 8n, 4n, 3n, 12n) == Snapshot.Retained{2n, 12n} : Snapshot.Decision}

# Rejects a later reservation when the aggregate retained-byte total would exceed its bound.
law aggregate_retention_limit_rejects_later_reservation:
  {Snapshot.reserve(2n, 12n, 1n, 3n, 12n) == Snapshot.ResourceLimit{} : Snapshot.Decision}

# Preserves both aggregate counters when a new reservation exceeds capacity.
law rejected_reservation_preserves_registry:
  {Snapshot.registry.reserve(Snapshot.Registry{2n, 12n}, 1n, 3n, 12n) ==
    Snapshot.Rejected{Snapshot.Registry{2n, 12n}} : Snapshot.RegistryDecision}

# Publishes both updated aggregate counters when a reservation is admitted.
law admitted_reservation_updates_registry:
  {Snapshot.registry.reserve(Snapshot.Registry{1n, 8n}, 4n, 3n, 12n) ==
    Snapshot.Admitted{Snapshot.Registry{2n, 12n}} : Snapshot.RegistryDecision}

# Returns one closed snapshot's retained bytes to the aggregate budget.
law snapshot_release_updates_registry:
  {Snapshot.registry.release(Snapshot.Registry{2n, 12n}, 4n) ==
    Snapshot.Released{Snapshot.Registry{1n, 8n}} : Snapshot.RegistryReleaseDecision}

# Preserves the registry when snapshot ownership would underflow.
law snapshot_release_rejects_empty_registry:
  {Snapshot.registry.release(Snapshot.Registry{0n, 12n}, 4n) ==
    Snapshot.InvalidRelease{Snapshot.Registry{0n, 12n}} :
    Snapshot.RegistryReleaseDecision}

# Preserves the registry when release bytes exceed the retained total.
law snapshot_release_rejects_byte_underflow:
  {Snapshot.registry.release(Snapshot.Registry{2n, 3n}, 4n) ==
    Snapshot.InvalidRelease{Snapshot.Registry{2n, 3n}} :
    Snapshot.RegistryReleaseDecision}

# Keeps a live snapshot's reservation when it still has cursor children.
law snapshot_close_preserves_registry_while_busy:
  {Snapshot.snapshot.close(Snapshot.Live{1n}, Snapshot.Registry{2n, 12n}, 4n) ==
    Snapshot.SnapshotBusy{Snapshot.Registry{2n, 12n}} :
    Snapshot.SnapshotCloseDecision}

# Releases aggregate bytes only after the final cursor is gone.
law snapshot_close_releases_after_final_cursor:
  {Snapshot.snapshot.close(Snapshot.Live{0n}, Snapshot.Registry{2n, 12n}, 4n) ==
    Snapshot.SnapshotClosed{Snapshot.Registry{1n, 8n}} :
    Snapshot.SnapshotCloseDecision}

# Does not release a registry reservation by closing an already closed snapshot.
law repeated_snapshot_close_preserves_registry:
  {Snapshot.snapshot.close(Snapshot.Closed{}, Snapshot.Registry{2n, 12n}, 4n) ==
    Snapshot.InvalidSnapshotClose{Snapshot.Registry{2n, 12n}} :
    Snapshot.SnapshotCloseDecision}


# A live cursor acquisition adds exactly one reference.
law cursor_acquisition_increments_live_snapshot:
  {Snapshot.cursor.acquire(Snapshot.Live{2n}) == Snapshot.Advanced{Snapshot.Live{3n}} : Snapshot.LifecycleDecision}

# A closed snapshot cannot create new cursor references.
law cursor_acquisition_rejects_closed_snapshot:
  {Snapshot.cursor.acquire(Snapshot.Closed{}) == Snapshot.Invalid{} : Snapshot.LifecycleDecision}

# Releasing a cursor removes exactly one existing reference.
law cursor_release_decrements_reference:
  {Snapshot.cursor.release(Snapshot.Live{2n}) == Snapshot.Advanced{Snapshot.Live{1n}} : Snapshot.LifecycleDecision}

# Releasing from zero references is invalid.
law cursor_release_rejects_underflow:
  {Snapshot.cursor.release(Snapshot.Live{0n}) == Snapshot.Invalid{} : Snapshot.LifecycleDecision}

# A snapshot with a live cursor cannot be closed.
law snapshot_close_is_busy_with_live_cursors:
  for cursor_count: Nat
  {Snapshot.close(Snapshot.Live{1n+cursor_count}) == Snapshot.Busy{} : Snapshot.LifecycleDecision}

# A snapshot closes after all cursor references are gone.
law snapshot_close_succeeds_after_final_cursor:
  {Snapshot.close(Snapshot.Live{0n}) == Snapshot.Advanced{Snapshot.Closed{}} : Snapshot.LifecycleDecision}

# Cursor acquisition increments every live snapshot's reference count exactly once.
law cursor_acquisition_increments_any_live_reference_count:
  for cursor_count: Nat
  {Snapshot.cursor.acquire(Snapshot.Live{cursor_count}) ==
    Snapshot.Advanced{Snapshot.Live{Nat.add(cursor_count, 1n)}} : Snapshot.LifecycleDecision}

# Releasing any existing cursor removes one reference and never underflows.
law cursor_release_decrements_any_positive_reference_count:
  for cursor_count: Nat
  {Snapshot.cursor.release(Snapshot.Live{1n+cursor_count}) ==
    Snapshot.Advanced{Snapshot.Live{cursor_count}} : Snapshot.LifecycleDecision}

# Retains the old SST generation when a snapshot still references it at publish.
law compaction_retains_referenced_generation:
  {Snapshot.publish_generation(7n, 4096n, 2n) ==
    Snapshot.Published{8n, Snapshot.GenerationRetained{7n, 4096n, 2n}} :
    Snapshot.GenerationDecision}

# Reclaims the old SST generation immediately when publication has no references.
law compaction_reclaims_unreferenced_generation:
  {Snapshot.publish_generation(7n, 4096n, 0n) ==
    Snapshot.Published{8n, Snapshot.NoRetained{}} : Snapshot.GenerationDecision}

# Releasing one of several references keeps the old generation available.
law generation_release_keeps_remaining_readers:
  for references: Nat
  {Snapshot.release_generation(Snapshot.GenerationRetained{7n, 4096n,
    Nat.add(2n, references)}) ==
    Snapshot.Keep{7n, 4096n, Nat.add(1n, references)} :
    Snapshot.RetentionDecision}

# Releasing the final reference allows reclamation of the old generation.
law generation_release_reclaims_final_reader:
  {Snapshot.release_generation(Snapshot.GenerationRetained{7n, 4096n, 1n}) ==
    Snapshot.Reclaim{7n, 4096n} : Snapshot.RetentionDecision}

# An unreferenced or absent generation cannot be released twice.
law generation_release_rejects_missing_reference:
  {Snapshot.release_generation(Snapshot.NoRetained{}) ==
    Snapshot.InvalidReference{} : Snapshot.RetentionDecision}

# Advances the SST generation immediately when no reader retains the old one.
law publication_advances_generation_without_readers:
  {Snapshot.publish_generation(13n, 8192n, 0n) ==
    Snapshot.Published{14n, Snapshot.NoRetained{}} :
    Snapshot.GenerationDecision}

# Keeps the old SST generation while any reader reference remains.
law publication_retains_positive_generation_references:
  for references: Nat
  {Snapshot.publish_generation(13n, 8192n, 1n+references) ==
    Snapshot.Published{14n, Snapshot.GenerationRetained{13n, 8192n, 1n+references}} :
    Snapshot.GenerationDecision}

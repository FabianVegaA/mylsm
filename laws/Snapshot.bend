import Base
import ../src/scan/Snapshot.bend as Snapshot

# A point lookup matches only when the first lower-bounded key is equal.
law snapshot_point_read_accepts_equal_key:
  {Snapshot.point_read.matches(EQ{}) == True{} : Bool}

# A point lookup rejects the next key after its inclusive lower bound.
law snapshot_point_read_rejects_greater_key:
  {Snapshot.point_read.matches(GT{}) == False{} : Bool}

# Admits a snapshot exactly at both configured retention limits.
law exact_retention_budget_is_accepted:
  {Snapshot.reserve(1n, 8n, 4n, 2n, 12n) == Snapshot.Retained{2n, 12n} : Snapshot.Decision}

# Rejects a new snapshot when all snapshot slots are reserved.
law snapshot_count_limit_is_rejected:
  {Snapshot.reserve(2n, 8n, 1n, 2n, 12n) == Snapshot.ResourceLimit{} : Snapshot.Decision}

# Rejects a snapshot that would exceed retained-byte capacity.
law retained_byte_limit_is_rejected:
  {Snapshot.reserve(1n, 9n, 4n, 2n, 12n) == Snapshot.ResourceLimit{} : Snapshot.Decision}

# Admits a retained root when its SST and active delta exactly fit the byte limit.
law snapshot_root_exact_sst_and_delta_budget_is_accepted:
  {Snapshot.reserve(0n, 0n, Nat.add(96n, 32n), 1n, 128n) ==
    Snapshot.Retained{1n, 128n} : Snapshot.Decision}

# Rejects a retained root when its SST and active delta exceed the byte limit.
law snapshot_root_sst_and_delta_overflow_is_rejected:
  {Snapshot.reserve(0n, 0n, Nat.add(97n, 32n), 1n, 128n) ==
    Snapshot.ResourceLimit{} : Snapshot.Decision}

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

# A publication preserves previously retired generations and prepends its reader-pinned predecessor.
law publication_prepends_to_retained_generations:
  for references: Nat
  {Snapshot.publish.registry(Snapshot.GenerationRegistry{
    Snapshot.FileGeneration{7n, 4096n, 1n+references},
    [Snapshot.FileGeneration{5n, 1024n, 2n}]}, 8192n) ==
    Snapshot.GenerationRegistry{Snapshot.FileGeneration{8n, 8192n, 0n},
      [Snapshot.FileGeneration{7n, 4096n, 1n+references},
       Snapshot.FileGeneration{5n, 1024n, 2n}]} : Snapshot.GenerationRegistry}

# A publication without current readers still preserves older retained generations.
law publication_preserves_older_retained_generations:
  {Snapshot.publish.registry(Snapshot.GenerationRegistry{
    Snapshot.FileGeneration{7n, 4096n, 0n},
    [Snapshot.FileGeneration{5n, 1024n, 2n}]}, 8192n) ==
    Snapshot.GenerationRegistry{Snapshot.FileGeneration{8n, 8192n, 0n},
      [Snapshot.FileGeneration{5n, 1024n, 2n}]} : Snapshot.GenerationRegistry}

# Pins the selected retired generation without changing other reader counts.
law pin_selected_retired_generation:
  {Snapshot.pin_generation(Snapshot.GenerationRegistry{
    Snapshot.FileGeneration{7n, 4096n, 0n},
    [Snapshot.FileGeneration{5n, 1024n, 1n},
     Snapshot.FileGeneration{3n, 512n, 2n}]}, 5n) ==
    Snapshot.Pinned{Snapshot.GenerationRegistry{
      Snapshot.FileGeneration{7n, 4096n, 0n},
      [Snapshot.FileGeneration{5n, 1024n, 2n},
       Snapshot.FileGeneration{3n, 512n, 2n}]}} : Snapshot.GenerationPinDecision}

# Rejects a pin for an absent generation without changing the registry.
law pin_missing_generation_preserves_registry:
  {Snapshot.pin_generation(Snapshot.GenerationRegistry{
    Snapshot.FileGeneration{7n, 4096n, 0n},
    [Snapshot.FileGeneration{5n, 1024n, 1n}]}, 9n) ==
    Snapshot.MissingGeneration{Snapshot.GenerationRegistry{
      Snapshot.FileGeneration{7n, 4096n, 0n},
      [Snapshot.FileGeneration{5n, 1024n, 1n}]}} : Snapshot.GenerationPinDecision}

# Reclaims only the selected retired generation after its final reader releases it.
law release_final_retired_generation:
  {Snapshot.release_generation.from_registry(Snapshot.GenerationRegistry{
    Snapshot.FileGeneration{7n, 4096n, 0n},
    [Snapshot.FileGeneration{5n, 1024n, 1n},
     Snapshot.FileGeneration{3n, 512n, 2n}]}, 5n) ==
    Snapshot.GenerationReclaimed{Snapshot.GenerationRegistry{
      Snapshot.FileGeneration{7n, 4096n, 0n},
      [Snapshot.FileGeneration{3n, 512n, 2n}]}, 5n, 1024n} :
    Snapshot.GenerationReleaseDecision}

# Decrements one retired reader while preserving the retained files and other entries.
law release_nonfinal_retired_generation:
  {Snapshot.release_generation.from_registry(Snapshot.GenerationRegistry{
    Snapshot.FileGeneration{7n, 4096n, 0n},
    [Snapshot.FileGeneration{5n, 1024n, 2n},
     Snapshot.FileGeneration{3n, 512n, 2n}]}, 5n) ==
    Snapshot.GenerationReleased{Snapshot.GenerationRegistry{
      Snapshot.FileGeneration{7n, 4096n, 0n},
      [Snapshot.FileGeneration{5n, 1024n, 1n},
       Snapshot.FileGeneration{3n, 512n, 2n}]}} : Snapshot.GenerationReleaseDecision}

# Rejects a release for a generation without a live reference.
law release_missing_generation_preserves_registry:
  {Snapshot.release_generation.from_registry(Snapshot.GenerationRegistry{
    Snapshot.FileGeneration{7n, 4096n, 0n},
    [Snapshot.FileGeneration{5n, 1024n, 1n}]}, 9n) ==
    Snapshot.MissingReference{Snapshot.GenerationRegistry{
      Snapshot.FileGeneration{7n, 4096n, 0n},
      [Snapshot.FileGeneration{5n, 1024n, 1n}]}} : Snapshot.GenerationReleaseDecision}

# Allocates the first nonzero owner resource identifier and advances the allocator.
law first_resource_identifier_is_one:
  {Snapshot.allocate_resource_id(Snapshot.ResourceIdAllocator{1, False{}}) ==
    Snapshot.ResourceIdAllocated{1,
      Snapshot.ResourceIdAllocator{2, False{}}} : Snapshot.ResourceIdDecision}

# Allocates the maximum identifier once and records exhaustion without wrapping.
law maximum_resource_identifier_does_not_wrap:
  {Snapshot.allocate_resource_id(Snapshot.ResourceIdAllocator{
    4294967295, False{}}) == Snapshot.ResourceIdAllocated{4294967295,
      Snapshot.ResourceIdAllocator{4294967295, True{}}} :
    Snapshot.ResourceIdDecision}

# Preserves an exhausted allocator and rejects all later identifier requests.
law exhausted_resource_identifier_is_rejected:
  {Snapshot.allocate_resource_id(Snapshot.ResourceIdAllocator{
    4294967295, True{}}) == Snapshot.ResourceIdExhausted{
      Snapshot.ResourceIdAllocator{4294967295, True{}}} :
    Snapshot.ResourceIdDecision}

# Admits a snapshot with one owner-issued ID and an aggregate byte reservation.
law owner_snapshot_admission_records_resource:
  {Snapshot.owner.snapshot.open(Snapshot.OwnerRegistry{
    Snapshot.ResourceIdAllocator{1, False{}}, Snapshot.Registry{0n, 0n},
    Nil{}, Nil{}}, 3n, 64n, (2n, 128n)) == Snapshot.OwnerSnapshotOpened{
      Snapshot.OwnerRegistry{Snapshot.ResourceIdAllocator{2, False{}},
        Snapshot.Registry{1n, 64n},
        [Snapshot.SnapshotResource{1, 3n, 64n, 0n}], Nil{}}, 1} :
    Snapshot.OwnerOpenDecision}

# Rejects an over-budget snapshot while preserving IDs, counters, and resources.
law owner_snapshot_rejection_preserves_registry:
  {Snapshot.owner.snapshot.open(Snapshot.OwnerRegistry{
    Snapshot.ResourceIdAllocator{4, False{}}, Snapshot.Registry{1n, 80n},
    [Snapshot.SnapshotResource{3, 2n, 80n, 0n}], Nil{}}, 5n, 64n, (4n, 128n)) ==
    Snapshot.OwnerSnapshotRejected{Snapshot.OwnerRegistry{
      Snapshot.ResourceIdAllocator{4, False{}}, Snapshot.Registry{1n, 80n},
      [Snapshot.SnapshotResource{3, 2n, 80n, 0n}], Nil{}}} :
    Snapshot.OwnerOpenDecision}

# Rejects exhausted owner IDs without charging an otherwise admissible snapshot.
law owner_snapshot_id_exhaustion_preserves_registry:
  {Snapshot.owner.snapshot.open(Snapshot.OwnerRegistry{
    Snapshot.ResourceIdAllocator{4294967295, True{}}, Snapshot.Registry{0n, 0n},
    Nil{}, Nil{}}, 5n, 64n, (4n, 128n)) == Snapshot.OwnerSnapshotRejected{
      Snapshot.OwnerRegistry{Snapshot.ResourceIdAllocator{4294967295, True{}},
        Snapshot.Registry{0n, 0n}, Nil{}, Nil{}}} : Snapshot.OwnerOpenDecision}

# Adds one child reference while preserving the snapshot identity and budget.
law owner_snapshot_cursor_acquire_increments_reference:
  {Snapshot.snapshot.resource.cursor.acquire(
    Snapshot.SnapshotResource{3, 7n, 64n, 0n}, 2n) ==
    Snapshot.SnapshotCursorAcquired{
      Snapshot.SnapshotResource{3, 7n, 64n, 1n}} :
    Snapshot.SnapshotCursorDecision}

# Rejects a cursor at the per-snapshot limit without changing its resource.
law owner_snapshot_cursor_limit_preserves_resource:
  {Snapshot.snapshot.resource.cursor.acquire(
    Snapshot.SnapshotResource{3, 7n, 64n, 1n}, 1n) ==
    Snapshot.SnapshotCursorLimit{
      Snapshot.SnapshotResource{3, 7n, 64n, 1n}} :
    Snapshot.SnapshotCursorDecision}

# Releases one child reference while preserving snapshot identity and bytes.
law owner_snapshot_cursor_release_decrements_reference:
  {Snapshot.snapshot.resource.cursor.release(
    Snapshot.SnapshotResource{3, 7n, 64n, 1n}) ==
    Snapshot.SnapshotCursorReleased{
      Snapshot.SnapshotResource{3, 7n, 64n, 0n}} :
    Snapshot.SnapshotCursorDecision}

# Rejects cursor underflow without changing its snapshot resource.
law owner_snapshot_cursor_release_underflow_preserves_resource:
  {Snapshot.snapshot.resource.cursor.release(
    Snapshot.SnapshotResource{3, 7n, 64n, 0n}) ==
    Snapshot.SnapshotCursorUnderflow{
      Snapshot.SnapshotResource{3, 7n, 64n, 0n}} :
    Snapshot.SnapshotCursorDecision}

# Allocates a cursor ID and increments its owner's snapshot reference.
law owner_cursor_open_records_child_reference:
  {Snapshot.owner.cursor.open(Snapshot.OwnerRegistry{
    Snapshot.ResourceIdAllocator{2, False{}}, Snapshot.Registry{1n, 64n},
    [Snapshot.SnapshotResource{1, 3n, 64n, 0n}], Nil{}}, 1, 2n) ==
    Snapshot.OwnerCursorOpened{Snapshot.OwnerRegistry{
      Snapshot.ResourceIdAllocator{3, False{}}, Snapshot.Registry{1n, 64n},
      [Snapshot.SnapshotResource{1, 3n, 64n, 1n}],
      [Snapshot.CursorResource{2, 1}]}, 2} : Snapshot.OwnerCursorOpenDecision}

# Updates the requested snapshot while preserving unrelated registry entries.
law owner_cursor_open_preserves_unrelated_snapshots:
  {Snapshot.owner.cursor.open(Snapshot.OwnerRegistry{
    Snapshot.ResourceIdAllocator{10, False{}}, Snapshot.Registry{3n, 192n},
    [Snapshot.SnapshotResource{1, 4n, 64n, 0n},
     Snapshot.SnapshotResource{2, 5n, 64n, 0n},
     Snapshot.SnapshotResource{3, 6n, 64n, 0n}], Nil{}}, 2, 2n) ==
    Snapshot.OwnerCursorOpened{Snapshot.OwnerRegistry{
      Snapshot.ResourceIdAllocator{11, False{}}, Snapshot.Registry{3n, 192n},
      [Snapshot.SnapshotResource{1, 4n, 64n, 0n},
       Snapshot.SnapshotResource{2, 5n, 64n, 1n},
       Snapshot.SnapshotResource{3, 6n, 64n, 0n}],
      [Snapshot.CursorResource{10, 2}]}, 10} :
    Snapshot.OwnerCursorOpenDecision}

# Rejects a missing snapshot without consuming an owner cursor identifier.
law owner_cursor_open_missing_snapshot_preserves_registry:
  {Snapshot.owner.cursor.open(Snapshot.OwnerRegistry{
    Snapshot.ResourceIdAllocator{2, False{}}, Snapshot.Registry{1n, 64n},
    [Snapshot.SnapshotResource{1, 3n, 64n, 0n}], Nil{}}, 9, 2n) ==
    Snapshot.OwnerCursorRejected{Snapshot.OwnerRegistry{
      Snapshot.ResourceIdAllocator{2, False{}}, Snapshot.Registry{1n, 64n},
      [Snapshot.SnapshotResource{1, 3n, 64n, 0n}], Nil{}}} :
    Snapshot.OwnerCursorOpenDecision}

# Preserves the owner registry when one snapshot reaches its cursor limit.
law owner_cursor_open_limit_preserves_registry:
  {Snapshot.owner.cursor.open(Snapshot.OwnerRegistry{
    Snapshot.ResourceIdAllocator{2, False{}}, Snapshot.Registry{1n, 64n},
    [Snapshot.SnapshotResource{1, 3n, 64n, 1n}], Nil{}}, 1, 1n) ==
    Snapshot.OwnerCursorRejected{Snapshot.OwnerRegistry{
      Snapshot.ResourceIdAllocator{2, False{}}, Snapshot.Registry{1n, 64n},
      [Snapshot.SnapshotResource{1, 3n, 64n, 1n}], Nil{}}} :
    Snapshot.OwnerCursorOpenDecision}

# Preserves the registry when cursor ID allocation is exhausted.
law owner_cursor_open_exhausted_id_preserves_registry:
  {Snapshot.owner.cursor.open(Snapshot.OwnerRegistry{
    Snapshot.ResourceIdAllocator{4294967295, True{}},
    Snapshot.Registry{1n, 64n},
    [Snapshot.SnapshotResource{1, 3n, 64n, 0n}], Nil{}}, 1, 2n) ==
    Snapshot.OwnerCursorRejected{Snapshot.OwnerRegistry{
      Snapshot.ResourceIdAllocator{4294967295, True{}},
      Snapshot.Registry{1n, 64n},
      [Snapshot.SnapshotResource{1, 3n, 64n, 0n}], Nil{}}} :
    Snapshot.OwnerCursorOpenDecision}

# Releases a cursor record and its snapshot child reference together.
law owner_cursor_close_releases_child_reference:
  {Snapshot.owner.cursor.close(Snapshot.OwnerRegistry{
    Snapshot.ResourceIdAllocator{3, False{}}, Snapshot.Registry{1n, 64n},
    [Snapshot.SnapshotResource{1, 3n, 64n, 1n}],
    [Snapshot.CursorResource{2, 1}]}, 2) ==
    Snapshot.OwnerCursorClosed{Snapshot.OwnerRegistry{
      Snapshot.ResourceIdAllocator{3, False{}}, Snapshot.Registry{1n, 64n},
      [Snapshot.SnapshotResource{1, 3n, 64n, 0n}], Nil{}}, 1} :
    Snapshot.OwnerCursorCloseDecision}

# Closes one cursor from the tail while retaining its unrelated sibling cursor.
law owner_cursor_close_preserves_unrelated_cursor:
  {Snapshot.owner.cursor.close(Snapshot.OwnerRegistry{
    Snapshot.ResourceIdAllocator{20, False{}}, Snapshot.Registry{2n, 128n},
    [Snapshot.SnapshotResource{1, 4n, 64n, 1n},
     Snapshot.SnapshotResource{2, 5n, 64n, 1n}],
    [Snapshot.CursorResource{10, 1}, Snapshot.CursorResource{11, 2}]}, 11) ==
    Snapshot.OwnerCursorClosed{Snapshot.OwnerRegistry{
      Snapshot.ResourceIdAllocator{20, False{}}, Snapshot.Registry{2n, 128n},
      [Snapshot.SnapshotResource{1, 4n, 64n, 1n},
       Snapshot.SnapshotResource{2, 5n, 64n, 0n}],
      [Snapshot.CursorResource{10, 1}]}, 2} : Snapshot.OwnerCursorCloseDecision}

# Rejects an unknown cursor while preserving every owner resource.
law owner_cursor_close_missing_id_preserves_registry:
  {Snapshot.owner.cursor.close(Snapshot.OwnerRegistry{
    Snapshot.ResourceIdAllocator{3, False{}}, Snapshot.Registry{1n, 64n},
    [Snapshot.SnapshotResource{1, 3n, 64n, 1n}],
    [Snapshot.CursorResource{2, 1}]}, 8) ==
    Snapshot.OwnerCursorCloseRejected{Snapshot.OwnerRegistry{
      Snapshot.ResourceIdAllocator{3, False{}}, Snapshot.Registry{1n, 64n},
      [Snapshot.SnapshotResource{1, 3n, 64n, 1n}],
      [Snapshot.CursorResource{2, 1}]}} : Snapshot.OwnerCursorCloseDecision}

# Preserves a cursor and snapshot record when their child count is inconsistent.
law owner_cursor_close_underflow_preserves_registry:
  {Snapshot.owner.cursor.close(Snapshot.OwnerRegistry{
    Snapshot.ResourceIdAllocator{3, False{}}, Snapshot.Registry{1n, 64n},
    [Snapshot.SnapshotResource{1, 3n, 64n, 0n}],
    [Snapshot.CursorResource{2, 1}]}, 2) ==
    Snapshot.OwnerCursorCloseRejected{Snapshot.OwnerRegistry{
      Snapshot.ResourceIdAllocator{3, False{}}, Snapshot.Registry{1n, 64n},
      [Snapshot.SnapshotResource{1, 3n, 64n, 0n}],
      [Snapshot.CursorResource{2, 1}]}} : Snapshot.OwnerCursorCloseDecision}

# Releases the aggregate reservation after closing a childless snapshot.
law owner_snapshot_close_releases_retained_budget:
  {Snapshot.owner.snapshot.close(Snapshot.OwnerRegistry{
    Snapshot.ResourceIdAllocator{3, False{}}, Snapshot.Registry{1n, 64n},
    [Snapshot.SnapshotResource{1, 3n, 64n, 0n}], Nil{}}, 1) ==
    Snapshot.OwnerSnapshotClosed{Snapshot.OwnerRegistry{
      Snapshot.ResourceIdAllocator{3, False{}}, Snapshot.Registry{0n, 0n},
      Nil{}, Nil{}}, Snapshot.SnapshotResource{1, 3n, 64n, 0n}} :
    Snapshot.OwnerSnapshotCloseDecision}

# Closes the requested snapshot while preserving earlier retained resources.
law owner_snapshot_close_preserves_unrelated_resources:
  {Snapshot.owner.snapshot.close(Snapshot.OwnerRegistry{
    Snapshot.ResourceIdAllocator{12, False{}}, Snapshot.Registry{2n, 128n},
    [Snapshot.SnapshotResource{1, 4n, 64n, 1n},
     Snapshot.SnapshotResource{2, 5n, 64n, 0n}],
    [Snapshot.CursorResource{10, 1}]}, 2) ==
    Snapshot.OwnerSnapshotClosed{Snapshot.OwnerRegistry{
      Snapshot.ResourceIdAllocator{12, False{}}, Snapshot.Registry{1n, 64n},
      [Snapshot.SnapshotResource{1, 4n, 64n, 1n}],
      [Snapshot.CursorResource{10, 1}]},
      Snapshot.SnapshotResource{2, 5n, 64n, 0n}} :
    Snapshot.OwnerSnapshotCloseDecision}

# Returns Busy without changing an open snapshot that still has a cursor.
law owner_snapshot_close_with_child_preserves_registry:
  {Snapshot.owner.snapshot.close(Snapshot.OwnerRegistry{
    Snapshot.ResourceIdAllocator{3, False{}}, Snapshot.Registry{1n, 64n},
    [Snapshot.SnapshotResource{1, 3n, 64n, 1n}],
    [Snapshot.CursorResource{2, 1}]}, 1) ==
    Snapshot.OwnerSnapshotBusy{Snapshot.OwnerRegistry{
      Snapshot.ResourceIdAllocator{3, False{}}, Snapshot.Registry{1n, 64n},
      [Snapshot.SnapshotResource{1, 3n, 64n, 1n}],
      [Snapshot.CursorResource{2, 1}]}} : Snapshot.OwnerSnapshotCloseDecision}

# Rejects an unknown snapshot without releasing any retained reservation.
law owner_snapshot_close_missing_id_preserves_registry:
  {Snapshot.owner.snapshot.close(Snapshot.OwnerRegistry{
    Snapshot.ResourceIdAllocator{3, False{}}, Snapshot.Registry{1n, 64n},
    [Snapshot.SnapshotResource{1, 3n, 64n, 0n}], Nil{}}, 9) ==
    Snapshot.OwnerSnapshotCloseRejected{Snapshot.OwnerRegistry{
      Snapshot.ResourceIdAllocator{3, False{}}, Snapshot.Registry{1n, 64n},
      [Snapshot.SnapshotResource{1, 3n, 64n, 0n}], Nil{}}} :
    Snapshot.OwnerSnapshotCloseDecision}

# Restores the childless snapshot when aggregate budget accounting is invalid.
law owner_snapshot_close_budget_underflow_preserves_registry:
  {Snapshot.owner.snapshot.close(Snapshot.OwnerRegistry{
    Snapshot.ResourceIdAllocator{3, False{}}, Snapshot.Registry{0n, 0n},
    [Snapshot.SnapshotResource{1, 3n, 64n, 0n}], Nil{}}, 1) ==
    Snapshot.OwnerSnapshotCloseRejected{Snapshot.OwnerRegistry{
      Snapshot.ResourceIdAllocator{3, False{}}, Snapshot.Registry{0n, 0n},
      [Snapshot.SnapshotResource{1, 3n, 64n, 0n}], Nil{}}} :
    Snapshot.OwnerSnapshotCloseDecision}

import Base
import ../src/transfer/BackupCursorPolicy.bend as Policy
import ../src/coordinator/CursorCodec.bend as CursorCodec
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Keeps one item in the pending block and records it as consumed.
law first_cursor_entry_is_buffered:
  {Policy.append(0n, 0n, 1n) == Policy.CursorBuffer{1n, 1n} : Policy.AppendDecision}

# The sixteenth item completes exactly one full block.
law sixteenth_cursor_entry_completes_block:
  {Policy.append(15n, 15n, 16n) == Policy.CursorBlockReady{16n, 16n} : Policy.AppendDecision}

# A full block cannot accept another entry before the writer drains it.
law full_pending_block_rejects_overflow:
  {Policy.append(16n, 16n, 17n) == Policy.CursorRejected{} : Policy.AppendDecision}

# Cursor items beyond the declared header count are rejected.
law cursor_cannot_exceed_declared_entry_count:
  {Policy.append(4n, 4n, 4n) == Policy.CursorRejected{} : Policy.AppendDecision}

# A complete exact-multiple export finishes without an empty block.
law exact_block_count_finishes_with_footer:
  {Policy.finish(16n, 16n, 0n) == Policy.CursorFooter{} : Policy.FinishDecision}

# A nonempty final suffix is emitted before the footer.
law partial_final_block_is_emitted:
  {Policy.finish(17n, 17n, 1n) == Policy.CursorFinalBlock{1n} : Policy.FinishDecision}

# A cursor that ends before its declared total cannot publish a footer.
law early_cursor_end_is_rejected:
  {Policy.finish(15n, 16n, 15n) == Policy.CursorFinishRejected{} : Policy.FinishDecision}

# Ensures consecutive block frames receive distinct sequential indexes.
law each_encoded_block_advances_its_index_once:
  {Policy.block.index.next(4n) == 5n : Nat}

# Distinguishes an owner end marker from a record with empty byte fields.
law owner_end_frame_is_classified_as_end:
  {Policy.owner.frame(CursorCodec.CursorEnd{}) == Policy.OwnerCursorEnd{} : Policy.OwnerFrameDecision}

# Preserves empty raw key and value fields in an owner item frame.
law owner_item_frame_preserves_empty_bytes:
  {Policy.owner.frame(CursorCodec.CursorItem{Bytes.new(0), Bytes.new(0)}) ==
    Policy.OwnerCursorItem{Bytes.new(0), Bytes.new(0)} : Policy.OwnerFrameDecision}

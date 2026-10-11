import Base
import ../src/transfer/Backup.bend as Backup
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Extracts an emitted chunk only when the footer transition is valid.
def footer.bytes.result(result: Result<&1, &1, Backup.Error, Backup.Step>) -> Maybe<&1, Bytes.Bytes>:
  match result:
    case Done{Backup.Chunk{_, bytes}}: Some{bytes}
    case _: None{}

# Projects equality from the byte library's preserved-input comparison.
def footer.bytes.equal(pair: Bytes.Bytes & Bytes.Bytes & Bool) -> Bool:
  match pair:
    case (_, _, equal): equal

# Unwraps a fixed checksum fixture.
def footer.bytes.hex(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}: bytes
    case None{}: Bytes.new(0)

# Checks the concrete SHA-256 footer vector for an empty export.
def empty.footer.has.sha256(step: Maybe<&1, Bytes.Bytes>) -> Bool:
  match step:
    case Some{bytes}:
      footer.bytes.equal(Bytes.eq(bytes,
        footer.bytes.hex(Bytes.from_hex("454e44310000000000000000cfc55748aa991c4fa010a2184ba9d5bffaacee95c64f7c510b106752d1f69742"))))
    case _: False{}

# Empty logical views require no data blocks.
law empty_backup_has_no_blocks:
  {Backup.blocks.count(0n) == 0 : U32}

# A partial first page uses one block.
law partial_backup_page_has_one_block:
  {Backup.blocks.count(15n) == 1 : U32}

# A full page does not allocate an empty trailing block.
law exact_backup_page_has_one_block:
  {Backup.blocks.count(16n) == 1 : U32}

# The next record after capacity starts a second block.
law backup_page_rolls_over_at_capacity:
  {Backup.blocks.count(17n) == 2 : U32}

# Export reserves three transitions per chunk and two terminal transitions.
law empty_backup_transition_budget:
  {Backup.write_fuel(0n) == 8n : Nat}

# One data block adds three transitions to the export budget.
law one_block_backup_transition_budget:
  {Backup.write_fuel(1n) == 11n : Nat}

# The empty export footer contains the SHA-256 of its marker and zero counts.
law empty_backup_footer_is_checksummed:
  {empty.footer.has.sha256(footer.bytes.result(
    Backup.next(Backup.Stream{Backup.Footer{}, Nil{}, 0, 0, 0}))) == True{} : Bool}

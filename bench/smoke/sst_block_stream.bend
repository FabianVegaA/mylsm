import Base
import ../../src/SstFile.bend as SstFile
import ../../src/MemTable.bend as MemTable
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Fails this reader smoke at its first violated contract.
def require(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, message)

# Carries the independent encoded header, block, and footer slices.
type Parts is Type:
  Parts{header: Bytes.Bytes, block: Bytes.Bytes, footer: Bytes.Bytes}

# Extracts the footer while retaining the earlier file slices.
def parts.footer(
  pair: Bytes.Bytes & Bytes.Bytes,
  header: Bytes.Bytes,
  block: Bytes.Bytes
) -> Parts:
  match pair:
    case (_, footer):
      Parts{header, block, footer}

# Extracts one complete encoded block from the legacy fixture.
def parts.block(
  pair: Bytes.Bytes & Bytes.Bytes,
  header: Bytes.Bytes
) -> Parts:
  match pair:
    case (file, block):
      parts.footer(Bytes.slice(file, 71, 40), header, block)

# Extracts the header then delegates the remaining fixed fixture slices.
def parts.header(pair: Bytes.Bytes & Bytes.Bytes) -> Parts:
  match pair:
    case (file, header):
      parts.block(Bytes.slice(file, 20, 51), header)

# Splits the one-entry SST fixture at its verified format boundaries.
def parts.file(file: Bytes.Bytes) -> Parts:
  parts.header(Bytes.slice(file, 0, 20))

# Verifies one returned block and its file-level footer before success.
def block.result(
  result: Result<&1, &1, SstFile.Error, SstFile.BlockStreamOutput>,
  footer: Bytes.Bytes
) -> Bool:
  match result:
    case Fail{_}:
      False{}
    case Done{SstFile.BlockStreamOutput{state,
        Con{MemTable.Entry{key, Some{value}}, Nil{}}}}:
      String.eq(key, "a") && String.eq(value, "v") &&
        Result.is_done(&1, &1, SstFile.Error, Unit,
          SstFile.stream.blocks.footer(state, footer))
    case _:
      False{}

# Opens the header, returns one block, and finishes root-check validation.
def stream.header.result(
  result: Result<&1, &1, SstFile.Error, SstFile.BlockStreamState>,
  block: Bytes.Bytes,
  footer: Bytes.Bytes
) -> Bool:
  match result:
    case Fail{_}:
      False{}
    case Done{state}:
      block.result(SstFile.stream.blocks.next(state, block), footer)

# Runs the incremental path over the encoded one-record SSTable fixture.
def stream.parts(parts: Parts) -> Bool:
  match parts:
    case Parts{header, block, footer}:
      stream.header.result(SstFile.stream.blocks.header(header), block, footer)

# Encodes a minimal sorted SSTable and verifies one-block streaming.
def fixture.result(
  result: Result<&1, &1, SstFile.Error, Bytes.Bytes>
) -> Bool:
  match result:
    case Fail{_}:
      False{}
    case Done{file}:
      stream.parts(parts.file(file))

# Encodes one value to exercise header, block, and footer validation.
def main() -> IO(Unit):
  do IO<Unit>:
    require(fixture.result(SstFile.encode_file(
      [MemTable.Entry{"a", Some{"v"}}], 0)),
      "block reader must return one validated entry and verify the footer")
    IO.print("SST block stream passed")

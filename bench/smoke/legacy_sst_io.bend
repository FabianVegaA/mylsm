import Base
import ../../src/Console.bend as Console
import ../../src/Flush.bend as Flush
import ../../src/Fs.bend as Fs
import ../../src/Manifest.bend as Manifest
import ../../src/MemTable.bend as MemTable
import ../../src/SstStreamIo.bend as SstStreamIo

# Stops the fixture after a source validation failure.
def fail(message: String) -> IO(Unit):
  IO.die(Unit, 1, message)

# Produces two owned copies of a fixture path.
def path.clone.pair.go(path: String, left: String, right: String) -> String & String:
  match path:
    case SNil{}: (String.reverse(left), String.reverse(right))
    case SCon{+character, rest}:
      path.clone.pair.go(rest, SCon{character, left}, SCon{character, right})

def path.clone.pair(path: String) -> String & String:
  path.clone.pair.go(path, SNil{}, SNil{})

# Closes the fixture lock file after publishing the fixture.
def lock.closed(
  result: Result<&1, &1, U32 & String, File>
) -> IO(Unit):
  match result:
    case Fail{_}: fail("legacy SST fixture lock open failed")
    case Done{file}:
      do IO<Unit>:
        _closed : Unit <- File.close(file)
        IO.print("LEGACY_SST_FIXTURE_CREATED")

def lock.open(path: String) -> IO(Unit):
  do IO<Unit>:
    opened : Result<&1, &1, U32 & String, File> <- File.open(path ++ "/LOCK", "w")
    lock.closed(opened)

# Creates a stable LOCK path after publishing the legacy table and manifest.
def lock.create(
  path: String,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Unit):
  match result:
    case Fail{_}: fail("legacy SST fixture lock creation failed")
    case Done{Unit{}}:
      lock.open(path)

# Publishes a generation-three manifest referencing the fixture table.
def manifest.write(
  path: String,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Unit):
  match result:
    case Fail{_}: fail("legacy SST fixture manifest write failed")
    case Done{Unit{}}:
      do IO<Unit>:
        lock.create(path, Done{Unit{}})

def table.manifest.publish(paths: String & String) -> IO(Unit):
  match paths:
    case (manifest_path, retained_path):
      do IO<Unit>:
        result : Result<&1, &1, U32 & String, Unit> <-
          Flush.write_manifest(manifest_path ++ "/MANIFEST",
            Manifest.M{Con{Con{"0.tbl", Nil{}},
              Con{Nil{}, Con{Nil{}, Con{Nil{}, Nil{}}}}}})
        manifest.write(retained_path, result)

# Writes the table before its manifest reference is published.
def table.write(
  path: String,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Unit):
  match result:
    case Fail{_}: fail("legacy SST fixture table write failed")
    case Done{Unit{}}:
      do IO<Unit>:
        paths : String & String = path.clone.pair(path)
        table.manifest.publish(paths)

def directory.write(paths: String & String) -> IO(Unit):
  match paths:
    case (table_path, retained_path):
      do IO<Unit>:
        written : Result<&1, &1, U32 & String, Unit> <-
          SstStreamIo.write_table(table_path ++ "/l0/0.tbl",
            Con{MemTable.Entry{"a", Some{"one"}},
              Con{MemTable.Entry{"b", Some{"two"}}, Nil{}}}, 0)
        table.write(retained_path, written)

# Creates the legacy L0 directory before writing the table file.
def directory.created(
  path: String,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Unit):
  match result:
    case Fail{_}: fail("legacy SST fixture level directory creation failed")
    case Done{Unit{}}:
      do IO<Unit>:
        paths : String & String = path.clone.pair(path)
        directory.write(paths)

def source.level(paths: String & String) -> IO(Unit):
  match paths:
    case (level_path, retained_path):
      do IO<Unit>:
        level : Result<&1, &1, U32 & String, Unit> <-
          Fs.make_dir(level_path ++ "/l0")
        directory.created(retained_path, level)

# Creates the source directory before preparing its legacy files.
def source.created(
  path: String,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Unit):
  match result:
    case Fail{_}: fail("legacy SST fixture directory creation failed")
    case Done{Unit{}}:
      do IO<Unit>:
        paths : String & String = path.clone.pair(path)
        source.level(paths)

# Builds the fixture root using the production directory policy.
def root.ready(
  path: String,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Unit):
  match result:
    case Fail{_}: fail("legacy SST fixture root creation failed")
    case Done{Unit{}}: source.created(path, Done{Unit{}})

def root.ensure(paths: String & String) -> IO(Unit):
  match paths:
    case (root_path, retained_path):
      do IO<Unit>:
        created : Result<&1, &1, U32 & String, Unit> <- Flush.ensure_dir(root_path)
        root.ready(retained_path, created)

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    paths : String & String = path.clone.pair(path)
    root.ensure(paths)

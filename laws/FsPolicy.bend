import Base
import ../src/FsPolicy.bend as FsPolicy

# States the missing metadata means absent property.
law missing_metadata_means_absent:
  {FsPolicy.missing_path_result(True{}, 2, "missing") == Done{False{}} : Result<&1, &1, U32 & String, Bool>}

# States the other metadata error is preserved property.
law other_metadata_error_is_preserved:
  {FsPolicy.missing_path_result(False{}, 13, "denied") == Fail{(13, "denied")} : Result<&1, &1, U32 & String, Bool>}

# States the optional level directory without path is empty property.
law optional_level_directory_without_path_is_empty:
  {FsPolicy.optional_directory_result(True{}, True{}, 2, "missing") == Done{Unit{}} : Result<&1, &1, U32 & String, Unit>}

# States the optional level path that is not a directory is empty property.
law optional_level_path_that_is_not_a_directory_is_empty:
  {FsPolicy.optional_directory_result(True{}, True{}, 20, "not a directory") == Done{Unit{}} : Result<&1, &1, U32 & String, Unit>}

# States the missing database root is an error property.
law missing_database_root_is_an_error:
  {FsPolicy.optional_directory_result(False{}, True{}, 2, "missing") == Fail{(2, "missing")} : Result<&1, &1, U32 & String, Unit>}

# States the nonmissing directory error is preserved property.
law nonmissing_directory_error_is_preserved:
  {FsPolicy.optional_directory_result(True{}, False{}, 13, "denied") == Fail{(13, "denied")} : Result<&1, &1, U32 & String, Unit>}

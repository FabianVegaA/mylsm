import Base
import ../tools/UnusedDefs.bend as Unused

# Verifies tokens are maximal runs of identifier characters and dots.
law tokens_split_on_punctuation:
  {Unused.tokens("A.f(x) + y_1") == ["A.f", "x", "y_1"] : List<&2, String>}

# Verifies a token yields itself and every suffix after a dot.
law suffixes_follow_each_dot:
  {Unused.suffixes("A.b.c") == ["A.b.c", "b.c", "c"] : List<&2, String>}

# Verifies a definition line yields its full dotted name.
law definition_reads_the_def_name:
  {Unused.definition("def foo.bar(x: U32) -> U32:") ==
    Some{"foo.bar"} : Maybe<&2, String>}

# Verifies a line that does not start with def has no name.
law non_definition_line_has_no_name:
  {Unused.definition("  def_x = 1") == None{} : Maybe<&2, String>}

# Verifies all definitions in a text are listed in order.
law definitions_are_listed_in_order:
  {Unused.definitions("def a()\n  b.c()\ndef b.c()\n") ==
    ["a", "b.c"] : List<&2, String>}

# Verifies a longer dotted name is not a reference to its prefix.
law longer_name_does_not_reference_its_prefix:
  {Unused.unused(Unused.count(Map.new(&2, Nat),
    "def h()\ndef h.go()\nh.go()\n"), "h") == True{} : Bool}

# Verifies a qualified call references the definition.
law qualified_call_references_the_definition:
  {Unused.unused(Unused.count(Map.new(&2, Nat),
    "def h()\nA.h(x)\n"), "h") == False{} : Bool}

# Verifies main is never reported.
law main_is_never_unused:
  {Unused.unused(Unused.count(Map.new(&2, Nat), "def main()\n"), "main") ==
    False{} : Bool}

# Verifies an empty allowlist allows nothing.
law empty_allowlist_allows_nothing:
  for path: String
  for name: String
  {Unused.allowed([], path, name) == False{} : Bool}

# Verifies a directory entry allows every path below it.
law directory_entry_allows_paths_below_it:
  {Unused.allowed(["src/vendor/"], "src/vendor/a.bend", "x") == True{} : Bool}

# Verifies a named entry allows only that definition.
law named_entry_allows_only_that_name:
  {Unused.allowed(["src/a.bend f"], "src/a.bend", "g") == False{} : Bool}

# Verifies a named entry allows the named definition.
law named_entry_allows_the_name:
  {Unused.allowed(["src/a.bend f"], "src/a.bend", "f") == True{} : Bool}

# Verifies a target covers itself and the files below it.
law target_covers_files_below_it:
  {Unused.targeted(["src/coordinator"], "src/coordinator/Owner.bend") ==
    True{} : Bool}

# Verifies a target does not cover a sibling that only shares its prefix.
law target_does_not_cover_sibling_prefix:
  {Unused.targeted(["src/coord"], "src/coordinator/Owner.bend") ==
    False{} : Bool}

# Verifies a file target covers exactly that file.
law file_target_covers_that_file:
  {Unused.targeted(["mylsm.bend"], "mylsm.bend") == True{} : Bool}

# Verifies a definition used only by itself is reported.
law self_recursion_is_not_a_reference:
  {Unused.report("def h(n: Nat) -> Nat:\n  h(n)\n") == ["h"] : List<&2, String>}

# Verifies a name used only inside a longer dotted name is reported.
law report_lists_the_unreferenced_prefix:
  {Unused.report("def h()\ndef h.go()\nh.go()\n") == ["h"] : List<&2, String>}

# Verifies a call from another block keeps a definition.
law call_from_another_block_keeps_the_definition:
  {Unused.report("def h()\n  1\ndef g()\n  h()\nmain(g)\n") ==
    [] : List<&2, String>}

# Verifies a top-level line ends the current definition block.
law top_level_line_ends_the_block:
  {Unused.report("def h()\n  1\nh()\n") == [] : List<&2, String>}

# Verifies a closing parenthesis line stays inside the block.
law closing_parenthesis_stays_in_the_block:
  {Unused.report("def h(\n  n: Nat\n) -> Nat:\n  h(n)\n") ==
    ["h"] : List<&2, String>}

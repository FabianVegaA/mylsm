import Base
import ../app/repl/repl_types.bend as Repl
import ../app/repl/repl_parser.bend as ReplParser
import ../app/repl/repl_policy.bend as ReplExec
import ../app/repl/repl_lexer.bend as ReplLexer
import ../app/repl/interchange.bend as Interchange
# --- Phase 1 REPL parser and timing policy ---
law repl_parse_put:
  {ReplParser.parse_command("put a 1") == Repl.Put{"a", "1"} : Repl.Command}

# State the repl parse get property for the interactive shell laws.
law repl_parse_get:
  {ReplParser.parse_command("get a") == Repl.Get{"a"} : Repl.Command}

# State the repl parse timing property for the interactive shell laws.
law repl_parse_timing:
  {ReplParser.parse_command("timing on") == Repl.Timing{Repl.TimingOn{}} : Repl.Command}

# State the repl parse mode gpu property for the interactive shell laws.
law repl_parse_mode_gpu:
  {ReplParser.parse_command("mode gpu") == Repl.Mode{Repl.Gpu{}} : Repl.Command}

# State the repl parse bad put property for the interactive shell laws.
law repl_parse_bad_put:
  {ReplParser.parse_command("put only-key") == Repl.Invalid{"usage: put <key> <value>"} : Repl.Command}

# State the repl timing off property for the interactive shell laws.
law repl_timing_off:
  {ReplExec.timing_should(Repl.TimingOff{}) == False{} : Bool}

# State the repl timing on property for the interactive shell laws.
law repl_timing_on:
  {ReplExec.timing_should(Repl.TimingOn{}) == True{} : Bool}

# State the repl timing once property for the interactive shell laws.
law repl_timing_once:
  {ReplExec.timing_once(Repl.TimingOnce{}) == True{} : Bool}

# State the repl lex quotes property for the interactive shell laws.
law repl_lex_quotes:
  {ReplLexer.tokenize("put \"hello world\" \"\"") == ReplLexer.LexSuccess{Con{"put", Con{"hello world", Con{"", Nil{}}}}} : ReplLexer.LexerResult}

# State the repl parse quoted put property for the interactive shell laws.
law repl_parse_quoted_put:
  {ReplParser.parse_command("put \"hello world\" \"value with spaces\"") == Repl.Put{"hello world", "value with spaces"} : Repl.Command}

# State the repl parse import property for the interactive shell laws.
law repl_parse_import:
  {ReplParser.parse_command("import data.db") == Repl.Import{"data.db"} : Repl.Command}

# Builds the one-record interchange fixture.
def interchange_fixture() -> List<&2, Interchange.Record>:
  [Interchange.Record{"hello world", "value with spaces"}]

def interchange_roundtrip.result(
  result: Result<&1, &1, U32 & String, String>
) -> Maybe<&2, List<&2, Interchange.Record>>:
  match result:
    case Fail{_}:
      None{}
    case Done{data}:
      Interchange.parse(data)

# State the interchange roundtrip property for the interactive shell laws.
law interchange_roundtrip:
  {interchange_roundtrip.result(Interchange.serialize(interchange_fixture())) ==
    Some{interchange_fixture()} : Maybe<&2, List<&2, Interchange.Record>>}

# Verifies an export with no records parses to an empty list.
law interchange_empty_export_parses:
  {Interchange.parse("MYLSM-EXPORT-3\n") ==
    Some{[]} : Maybe<&2, List<&2, Interchange.Record>>}

# Verifies a version two export is rejected.
law interchange_rejects_version_two:
  {Interchange.parse("MYLSM-EXPORT-2:6162") ==
    None{} : Maybe<&2, List<&2, Interchange.Record>>}

# Verifies a record with malformed hexadecimal is rejected.
law interchange_rejects_odd_hex:
  {Interchange.parse("MYLSM-EXPORT-3\n6 62\n") ==
    None{} : Maybe<&2, List<&2, Interchange.Record>>}

# Verifies a record line needs exactly a key and a value.
law interchange_rejects_missing_value:
  {Interchange.parse("MYLSM-EXPORT-3\n61\n") ==
    None{} : Maybe<&2, List<&2, Interchange.Record>>}

# State the interchange uses version three property for the interactive shell laws.
law interchange_uses_version_three:
  {Interchange.version_marker() == "MYLSM-EXPORT-3" : String}

# Verifies maintain is no longer a command.
law repl_maintain_is_not_a_command:
  {ReplParser.parse_command("maintain") ==
    Repl.Invalid{"unknown command: maintain"} : Repl.Command}

# State the repl restart zero rejected property for the interactive shell laws.
law repl_restart_zero_rejected:
  {ReplExec.restart_bounds(0n, 8n) == False{} : Bool}

# State the repl restart one accepted property for the interactive shell laws.
law repl_restart_one_accepted:
  {ReplExec.restart_bounds(1n, 8n) == True{} : Bool}

# State the repl restart 256 accepted property for the interactive shell laws.
law repl_restart_256_accepted:
  {ReplExec.restart_bounds(256n, 8n) == True{} : Bool}

# State the repl restart 257 rejected property for the interactive shell laws.
law repl_restart_257_rejected:
  {ReplExec.restart_bounds(257n, 8n) == False{} : Bool}

# State the repl restart same rejected property for the interactive shell laws.
law repl_restart_same_rejected:
  {ReplExec.restart_bounds(8n, 8n) == False{} : Bool}

# State the repl export parent property for the interactive shell laws.
law repl_export_parent:
  {ReplExec.parent_path("data/export.db") == "data" : String}

# State the repl export current parent property for the interactive shell laws.
law repl_export_current_parent:
  {ReplExec.parent_path("export.db") == "." : String}

# Verifies an empty import produces no batches.
law interchange_batches_empty:
  {Interchange.batches([], 256n, 1048576n) ==
    [] : List<&2, List<&2, Interchange.Record>>}

# Verifies batches close when they reach the record count limit.
law interchange_batches_split_by_count:
  {Interchange.batches([Interchange.Record{"a", "1"}, Interchange.Record{"b", "2"},
    Interchange.Record{"c", "3"}], 2n, 1048576n) ==
    [[Interchange.Record{"a", "1"}, Interchange.Record{"b", "2"}],
      [Interchange.Record{"c", "3"}]] : List<&2, List<&2, Interchange.Record>>}

# Verifies batches close before their estimated size exceeds the byte limit.
law interchange_batches_split_by_bytes:
  {Interchange.batches([Interchange.Record{"a", "xxxx"}, Interchange.Record{"b", "yyyy"}],
    256n, 40n) ==
    [[Interchange.Record{"a", "xxxx"}], [Interchange.Record{"b", "yyyy"}]] :
    List<&2, List<&2, Interchange.Record>>}

# Verifies a record larger than the byte limit still forms its own batch.
law interchange_batches_keep_an_oversized_record:
  {Interchange.batches([Interchange.Record{"a", "xxxxxxxx"}], 256n, 8n) ==
    [[Interchange.Record{"a", "xxxxxxxx"}]] : List<&2, List<&2, Interchange.Record>>}

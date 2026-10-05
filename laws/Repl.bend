import Base
import ../src/MemTable.bend as MemTable
import ../app/repl_types.bend as Repl
import ../app/repl_parser.bend as ReplParser
import ../app/repl_policy.bend as ReplExec
import ../app/repl_lexer.bend as ReplLexer
import ../app/interchange.bend as Interchange
import ../src/Wal.bend as Wal
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

# Handle interchange fixture in the interactive shell laws.
def interchange_fixture() -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{"hello world", Some{"value with spaces"}}, Nil{}}

def interchange_roundtrip.result(
  result: Result<&1, &1, Wal.Error, String>
) -> Maybe<&2, List<&2, MemTable.Entry>>:
  match result:
    case Fail{_}:
      None{}
    case Done{data}:
      Interchange.parse(data)

# State the interchange roundtrip property for the interactive shell laws.
law interchange_roundtrip:
  {interchange_roundtrip.result(Interchange.serialize(interchange_fixture())) == Some{interchange_fixture()} : Maybe<&2, List<&2, MemTable.Entry>>}

# State the interchange rejects version one property for the interactive shell laws.
law interchange_rejects_version_one:
  {Interchange.parse("MYLSM-EXPORT-1::#1394614482") == None{} : Maybe<&2, List<&2, MemTable.Entry>>}

# State the interchange uses version two property for the interactive shell laws.
law interchange_uses_version_two:
  {Interchange.version_marker() == "MYLSM-EXPORT-2" : String}

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

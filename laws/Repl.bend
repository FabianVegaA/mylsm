import Base
import ../src/MemTable.bend as MemTable
import ../app/repl_types.bend as Repl
import ../app/repl_parser.bend as ReplParser
import ../app/repl_exec.bend as ReplExec
import ../app/repl_lexer.bend as ReplLexer
import ../app/interchange.bend as Interchange

# --- Phase 1 REPL parser and timing policy ---
law repl_parse_put:
  {ReplParser.parse_command("put a 1") == Repl.Put{"a", "1"} : Repl.Command}

law repl_parse_get:
  {ReplParser.parse_command("get a") == Repl.Get{"a"} : Repl.Command}

law repl_parse_timing:
  {ReplParser.parse_command("timing on") == Repl.Timing{Repl.TimingOn{}} : Repl.Command}

law repl_parse_mode_gpu:
  {ReplParser.parse_command("mode gpu") == Repl.Mode{Repl.Gpu{}} : Repl.Command}

law repl_parse_bad_put:
  {ReplParser.parse_command("put only-key") == Repl.Invalid{"usage: put <key> <value>"} : Repl.Command}

law repl_timing_off:
  {ReplExec.timing_should(Repl.TimingOff{}) == False{} : Bool}

law repl_timing_on:
  {ReplExec.timing_should(Repl.TimingOn{}) == True{} : Bool}

law repl_timing_once:
  {ReplExec.timing_once(Repl.TimingOnce{}) == True{} : Bool}

law repl_lex_quotes:
  {ReplLexer.tokenize("put \"hello world\" \"\"") == ReplLexer.LexSuccess{Con{"put", Con{"hello world", Con{"", Nil{}}}}} : ReplLexer.LexerResult}

law repl_parse_quoted_put:
  {ReplParser.parse_command("put \"hello world\" \"value with spaces\"") == Repl.Put{"hello world", "value with spaces"} : Repl.Command}

law repl_parse_import:
  {ReplParser.parse_command("import data.db") == Repl.Import{"data.db"} : Repl.Command}

def interchange_fixture() -> List<&2, MemTable.Entry>:
  Con{MemTable.Entry{"hello world", Some{"value with spaces"}}, Nil{}}

law interchange_roundtrip:
  {Interchange.parse(Interchange.serialize(interchange_fixture())) == Some{interchange_fixture()} : Maybe<&2, List<&2, MemTable.Entry>>}

law repl_restart_zero_rejected:
  {ReplExec.restart_bounds(0n, 8n) == False{} : Bool}

law repl_restart_one_accepted:
  {ReplExec.restart_bounds(1n, 8n) == True{} : Bool}

law repl_restart_256_accepted:
  {ReplExec.restart_bounds(256n, 8n) == True{} : Bool}

law repl_restart_257_rejected:
  {ReplExec.restart_bounds(257n, 8n) == False{} : Bool}

law repl_restart_same_rejected:
  {ReplExec.restart_bounds(8n, 8n) == False{} : Bool}

law repl_export_parent:
  {ReplExec.parent_path("data/export.db") == "data" : String}

law repl_export_current_parent:
  {ReplExec.parent_path("export.db") == "." : String}

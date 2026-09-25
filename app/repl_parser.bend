import Base
import ./repl_types.bend as Repl
import ./repl_lexer.bend as Lexer

# Base's total decimal parser already handles empty/invalid/overflow input.
def parse_nat_token(str: String) -> Maybe<&2, Nat>:
  Nat.read(str)

def parse_put_key(key: String, value: String, empty: Bool) -> Repl.Command:
  match empty:
    case True{}:
      Repl.Invalid{"usage: put <key> <value>"}
    case False{}:
      Repl.Put{key, value}

def parse_put(tokens: List<&2, String>) -> Repl.Command:
  match tokens:
    case Con{+key, Con{value, Nil{}}}:
      parse_put_key(key, value, String.is_empty(key))
    case _:
      Repl.Invalid{"usage: put <key> <value>"}

def parse_get_key(key: String, empty: Bool) -> Repl.Command:
  match empty:
    case True{}:
      Repl.Invalid{"usage: get <key>"}
    case False{}:
      Repl.Get{key}

def parse_get(tokens: List<&2, String>) -> Repl.Command:
  match tokens:
    case Con{+key, Nil{}}:
      parse_get_key(key, String.is_empty(key))
    case _:
      Repl.Invalid{"usage: get <key>"}

def parse_del_key(key: String, empty: Bool) -> Repl.Command:
  match empty:
    case True{}:
      Repl.Invalid{"usage: del <key>"}
    case False{}:
      Repl.Del{key}

def parse_del(tokens: List<&2, String>) -> Repl.Command:
  match tokens:
    case Con{+key, Nil{}}:
      parse_del_key(key, String.is_empty(key))
    case _:
      Repl.Invalid{"usage: del <key>"}

def parse_scan_bounds(lo: String, hi: String, lo_empty: Bool, hi_empty: Bool) -> Repl.Command:
  match lo_empty hi_empty:
    case False{} False{}:
      Repl.Scan{lo, hi}
    case _ _:
      Repl.Invalid{"usage: scan <lo> <hi>"}

def parse_scan(tokens: List<&2, String>) -> Repl.Command:
  match tokens:
    case Con{+lo, Con{+hi, Nil{}}}:
      parse_scan_bounds(lo, hi, String.is_empty(lo), String.is_empty(hi))
    case _:
      Repl.Invalid{"usage: scan <lo> <hi>"}

def parse_no_args(tokens: List<&2, String>, command: Repl.Command, usage: String) -> Repl.Command:
  match tokens:
    case Nil{}:
      command
    case Con{_, _}:
      Repl.Invalid{usage}

def parse_timing_once(once: Bool) -> Repl.Command:
  match once:
    case True{}:
      Repl.Timing{Repl.TimingOnce{}}
    case False{}:
      Repl.Invalid{"usage: timing <on|off|once>"}

def parse_timing_off(+mode: String, off: Bool) -> Repl.Command:
  match off:
    case True{}:
      Repl.Timing{Repl.TimingOff{}}
    case False{}:
      parse_timing_once(String.eq(mode, "once"))

def parse_timing_on(+mode: String, on: Bool) -> Repl.Command:
  match on:
    case True{}:
      Repl.Timing{Repl.TimingOn{}}
    case False{}:
      parse_timing_off(mode, String.eq(mode, "off"))

def parse_timing(tokens: List<&2, String>) -> Repl.Command:
  match tokens:
    case Con{+mode, Nil{}}:
      parse_timing_on(mode, String.eq(mode, "on"))
    case _:
      Repl.Invalid{"usage: timing <on|off|once>"}

def parse_mode_auto(auto: Bool) -> Repl.Command:
  match auto:
    case True{}:
      Repl.Mode{Repl.Auto{}}
    case False{}:
      Repl.Invalid{"usage: mode <cpu|gpu|auto>"}

def parse_mode_gpu(+mode: String, gpu: Bool) -> Repl.Command:
  match gpu:
    case True{}:
      Repl.Mode{Repl.Gpu{}}
    case False{}:
      parse_mode_auto(String.eq(mode, "auto"))

def parse_mode_cpu(+mode: String, cpu: Bool) -> Repl.Command:
  match cpu:
    case True{}:
      Repl.Mode{Repl.Cpu{}}
    case False{}:
      parse_mode_gpu(mode, String.eq(mode, "gpu"))

def parse_mode(tokens: List<&2, String>) -> Repl.Command:
  match tokens:
    case Con{+mode, Nil{}}:
      parse_mode_cpu(mode, String.eq(mode, "cpu"))
    case _:
      Repl.Invalid{"usage: mode <cpu|gpu|auto>"}

def parse_threads_nat(parsed: Maybe<&2, Nat>) -> Repl.Command:
  match parsed:
    case None{}:
      Repl.Invalid{"usage: threads <n>"}
    case Some{count}:
      Repl.Threads{count}

def parse_threads(tokens: List<&2, String>) -> Repl.Command:
  match tokens:
    case Con{count, Nil{}}:
      parse_threads_nat(parse_nat_token(count))
    case _:
      Repl.Invalid{"usage: threads <n>"}

def parse_compute_nat(parsed: Maybe<&2, Nat>) -> Repl.Command:
  match parsed:
    case None{}:
      Repl.Invalid{"usage: compute <fuel>"}
    case Some{fuel}:
      Repl.Compute{fuel}

def parse_compute(tokens: List<&2, String>) -> Repl.Command:
  match tokens:
    case Con{fuel, Nil{}}:
      parse_compute_nat(parse_nat_token(fuel))
    case _:
      Repl.Invalid{"usage: compute <fuel>"}

def parse_path(tokens: List<&2, String>, importing: Bool) -> Repl.Command:
  match tokens importing:
    case Con{path, Nil{}} True{}:
      Repl.Import{path}
    case Con{path, Nil{}} False{}:
      Repl.Export{path}
    case _ True{}:
      Repl.Invalid{"usage: import <path>"}
    case _ False{}:
      Repl.Invalid{"usage: export <path>"}

def parse_time_one(inner: String) -> Repl.Command:
  match inner:
    case SNil{}:
      Repl.Invalid{"usage: time <command>"}
    case SCon{h, t}:
      Repl.Time{SCon{h, t}}

def parse_time(tokens: List<&2, String>) -> Repl.Command:
  match tokens:
    case Nil{}:
      Repl.Invalid{"usage: time <command>"}
    case Con{inner, Nil{}}:
      parse_time_one(inner)
    case Con{h, t}:
      Repl.Time{String.join(Con{h, t}, " ")}

# Linear command dispatch avoids an exponential multi-Bool match.
def dispatch_exit(hit: Bool, +cmd: String, +tokens: List<&2, String>) -> Repl.Command:
  match hit:
    case True{}:
      parse_no_args(tokens, Repl.Exit{}, "usage: exit")
    case False{}:
      Repl.Invalid{"unknown command: " ++ cmd}

def dispatch_help(hit: Bool, +cmd: String, +tokens: List<&2, String>) -> Repl.Command:
  match hit:
    case True{}:
      parse_no_args(tokens, Repl.Help{}, "usage: help")
    case False{}:
      dispatch_exit(String.eq(cmd, "exit"), cmd, tokens)

def dispatch_time(hit: Bool, +cmd: String, +tokens: List<&2, String>) -> Repl.Command:
  match hit:
    case True{}:
      parse_time(tokens)
    case False{}:
      dispatch_help(String.eq(cmd, "help"), cmd, tokens)

def dispatch_export(hit: Bool, +cmd: String, +tokens: List<&2, String>) -> Repl.Command:
  match hit:
    case True{}:
      parse_path(tokens, False{})
    case False{}:
      dispatch_time(String.eq(cmd, "time"), cmd, tokens)

def dispatch_import(hit: Bool, +cmd: String, +tokens: List<&2, String>) -> Repl.Command:
  match hit:
    case True{}:
      parse_path(tokens, True{})
    case False{}:
      dispatch_export(String.eq(cmd, "export"), cmd, tokens)

def dispatch_compute(hit: Bool, +cmd: String, +tokens: List<&2, String>) -> Repl.Command:
  match hit:
    case True{}:
      parse_compute(tokens)
    case False{}:
      dispatch_import(String.eq(cmd, "import"), cmd, tokens)

def dispatch_threads(hit: Bool, +cmd: String, +tokens: List<&2, String>) -> Repl.Command:
  match hit:
    case True{}:
      parse_threads(tokens)
    case False{}:
      dispatch_compute(String.eq(cmd, "compute"), cmd, tokens)

def dispatch_mode(hit: Bool, +cmd: String, +tokens: List<&2, String>) -> Repl.Command:
  match hit:
    case True{}:
      parse_mode(tokens)
    case False{}:
      dispatch_threads(String.eq(cmd, "threads"), cmd, tokens)

def dispatch_timing(hit: Bool, +cmd: String, +tokens: List<&2, String>) -> Repl.Command:
  match hit:
    case True{}:
      parse_timing(tokens)
    case False{}:
      dispatch_mode(String.eq(cmd, "mode"), cmd, tokens)

def dispatch_runtime(hit: Bool, +cmd: String, +tokens: List<&2, String>) -> Repl.Command:
  match hit:
    case True{}:
      parse_no_args(tokens, Repl.Runtime{}, "usage: runtime")
    case False{}:
      dispatch_timing(String.eq(cmd, "timing"), cmd, tokens)

def dispatch_stats(hit: Bool, +cmd: String, +tokens: List<&2, String>) -> Repl.Command:
  match hit:
    case True{}:
      parse_no_args(tokens, Repl.Stats{}, "usage: stats")
    case False{}:
      dispatch_runtime(String.eq(cmd, "runtime"), cmd, tokens)

def dispatch_maintain(hit: Bool, +cmd: String, +tokens: List<&2, String>) -> Repl.Command:
  match hit:
    case True{}:
      parse_no_args(tokens, Repl.Maintain{}, "usage: maintain")
    case False{}:
      dispatch_stats(String.eq(cmd, "stats"), cmd, tokens)

def dispatch_compact(hit: Bool, +cmd: String, +tokens: List<&2, String>) -> Repl.Command:
  match hit:
    case True{}:
      parse_no_args(tokens, Repl.Compact{}, "usage: compact")
    case False{}:
      dispatch_maintain(String.eq(cmd, "maintain"), cmd, tokens)

def dispatch_flush(hit: Bool, +cmd: String, +tokens: List<&2, String>) -> Repl.Command:
  match hit:
    case True{}:
      parse_no_args(tokens, Repl.Flush{}, "usage: flush")
    case False{}:
      dispatch_compact(String.eq(cmd, "compact"), cmd, tokens)

def dispatch_scan(hit: Bool, +cmd: String, +tokens: List<&2, String>) -> Repl.Command:
  match hit:
    case True{}:
      parse_scan(tokens)
    case False{}:
      dispatch_flush(String.eq(cmd, "flush"), cmd, tokens)

def dispatch_del(hit: Bool, +cmd: String, +tokens: List<&2, String>) -> Repl.Command:
  match hit:
    case True{}:
      parse_del(tokens)
    case False{}:
      dispatch_scan(String.eq(cmd, "scan"), cmd, tokens)

def dispatch_get(hit: Bool, +cmd: String, +tokens: List<&2, String>) -> Repl.Command:
  match hit:
    case True{}:
      parse_get(tokens)
    case False{}:
      dispatch_del(String.eq(cmd, "del"), cmd, tokens)

def dispatch_put(hit: Bool, +cmd: String, +tokens: List<&2, String>) -> Repl.Command:
  match hit:
    case True{}:
      parse_put(tokens)
    case False{}:
      dispatch_get(String.eq(cmd, "get"), cmd, tokens)

def parse_head(+cmd: String, tokens: List<&2, String>) -> Repl.Command:
  dispatch_put(String.eq(cmd, "put"), cmd, tokens)

def parse_tokens(tokens: List<&2, String>) -> Repl.Command:
  match tokens:
    case Nil{}:
      Repl.Noop{}
    case Con{SNil{}, Nil{}}:
      Repl.Noop{}
    case Con{cmd, rest}:
      parse_head(cmd, rest)

def parse_lexed(result: Lexer.LexerResult) -> Repl.Command:
  match result:
    case Lexer.LexSuccess{tokens}:
      parse_tokens(tokens)
    case Lexer.LexError{message}:
      Repl.Invalid{message}

def parse_command(line: String) -> Repl.Command:
  parse_lexed(Lexer.tokenize(line))

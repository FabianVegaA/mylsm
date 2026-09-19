# Phase 1 — Useful Developer Product Implementation Plan

> **For agentic workers:** follow `AGENT.md`. Run `bend guide` before Bend work,
> keep product rules in `laws/*.bend`, run `./proofs/run.sh` before every commit,
> and parallelize only independent pure work. Implement tasks in order and keep
> each checkpoint green.

**Goal:** Turn the current CLI/demo into a useful local developer product with a
persistent Bend REPL, durable commands, timing, runtime-mode controls,
administrative operations, predictable errors, and import/export foundations.

**Baseline:** branch `feature/cli-demo-runtime`; `bin/mylsm demo`, native CPU,
native Metal GPU, `./proofs/run.sh`, and `bench/cli_smoke.sh` already pass.

**Related design:**

- `docs/superpowers/specs/2026-09-18-cli-demo-runtime-design.md`
- `README.md`, Phase 1 roadmap

## Phase constraints

- Bend 2.0.5 behavior is authoritative; run `bend guide` first.
- No `@unsafe` definitions.
- The REPL loop is `Nat`-fuel-bounded; no unbounded or mutual recursion.
- Every acknowledged mutation uses `Recover.write` or the existing durable
  `Db.db_*` path; no alternate WAL implementation.
- Filesystem, WAL, Manifest, SSTable, and recovery work always execute on CPU.
- GPU mode applies only to pure, uniform workers called with `!`.
- Runtime thread count and GPU enablement are process-start settings. A REPL may
  switch CPU/GPU compute dispatch only if GPU was enabled at process start;
  changing threads requires a controlled restart.
- Host effects receive C/JS twins and empirical smoke tests. Pure parsing and
  state transitions receive laws in `laws/*.bend` and proofs in `proofs/*Proof.bend`.
- Initial command grammar uses whitespace-delimited tokens. Quoted strings are a
  later task in this phase and must not be approximated unsafely.

---

## Task 1: Audited console and environment effects

**Files:**

- Create: `src/Console.bend`
- Create: `src/effs/read_line.c`
- Create: `src/effs/read_line.js`
- Create: `src/effs/get_env.c`
- Create: `src/effs/get_env.js`
- Create: `bench/console_smoke.bend`
- Modify: `bench/cli_smoke.sh`

**Produces:**

```python
Console.read_line() -> IO(Result<&1, &1, U32 & String, String>)
Console.get_env(name: String) -> IO(Result<&1, &1, U32 & String, String>)
```

`read_line` returns a line without the trailing newline. EOF returns `""`; an
empty interactive line is therefore equivalent to a no-op command. `get_env`
returns `""` for an unset variable. This intentionally avoids packing nested
`Maybe<String>` through foreign effects.

### Step 1: Write failing smoke harness

`bench/console_smoke.bend` reads one line, reads `MYLSM_TEST_ENV`, and prints both.
Validate failure before effects exist:

```sh
printf 'hello\n' | MYLSM_TEST_ENV=world bend bench/console_smoke.bend
```

### Step 2: Implement C twins

Follow the existing `src/effs/*.c` registration and `io_done`/`io_fail` pattern.

- `read_line.c`: use a bounded growable buffer around `fgetc(stdin)` until
  newline/EOF. Cap one line at 1 MiB; return an error above the cap.
- `get_env.c`: convert the Bend string with `io_cstr`, call `getenv`, copy the
  value into a Bend string, and never expose the host pointer.
- Distinguish syscall/allocation errors with non-zero error codes.

### Step 3: Implement JS twins

- `read_line.js`: synchronously consume fd 0 one byte at a time with
  `fs.readSync`, stopping at newline/EOF and enforcing the 1 MiB cap.
- `get_env.js`: read `process.env[name] ?? ""` and return a copied string.
- Use the same Bend effect names as the C twins.

### Step 4: Validate effects

```sh
printf 'hello\n' | MYLSM_TEST_ENV=world bend bench/console_smoke.bend
```

Expected markers:

```text
line=hello
env=world
```

Also compile the native path where clang is available.

### Step 5: Proof gate and checkpoint

Host effects have no laws, but the full proof gate must remain green:

```sh
./proofs/run.sh
git add src/Console.bend src/effs/read_line.* src/effs/get_env.* bench/console_smoke.bend bench/cli_smoke.sh
git commit -m "feat: add audited console effects for the REPL"
```

---

## Task 2: Pure REPL command language

**Files:**

- Create: `app/repl_types.bend`
- Create: `app/repl_parser.bend`
- Modify: `laws/*.bend`
- Modify: `proofs/*Proof.bend`

### Step 1: Define commands and state modes

```python
type TimingMode is Data:
  TimingOff{}
  TimingOn{}
  TimingOnce{}

type ComputeMode is Data:
  Cpu{}
  Gpu{}
  Auto{}

type Command is Data:
  Noop{}
  Put{key: String, value: String}
  Get{key: String}
  Del{key: String}
  Scan{lo: String, hi: String}
  Flush{}
  Compact{}
  Stats{}
  Runtime{}
  Timing{mode: TimingMode}
  Mode{mode: ComputeMode}
  Threads{count: Nat}
  Compute{fuel: Nat}
  Time{inner: String}
  Help{}
  Exit{}
  Invalid{message: String}
```

`Time` stores the unparsed inner command to avoid a recursive `Command` type and
mutual parser recursion.

### Step 2: Implement structural parser

Implement:

```python
def parse_command(line: String) -> Command
def parse_tokens(tokens: List<&2, String>) -> Command
def parse_nat_token(s: String) -> Maybe<&2, Nat>
```

Use `String.split(line, ' ')`, reject missing/extra arguments, and reject empty
keys. Values containing spaces are not accepted yet; return an actionable
`Invalid` message rather than truncating them.

Because Bend cannot match a computed expression directly, route results through
small helpers whose parameters are matched. Do not use mutual recursion.

### Step 3: Add parser laws first

Add at least these laws:

```python
law repl_parse_put:
  {Repl.parse_command("put a 1") == Repl.Put{"a", "1"} : Repl.Command}

law repl_parse_get:
  {Repl.parse_command("get a") == Repl.Get{"a"} : Repl.Command}

law repl_parse_timing:
  {Repl.parse_command("timing on") == Repl.Timing{Repl.TimingOn{}} : Repl.Command}

law repl_parse_mode_gpu:
  {Repl.parse_command("mode gpu") == Repl.Mode{Repl.Gpu{}} : Repl.Command}

law repl_parse_bad_put:
  {Repl.parse_command("put only-key") == Repl.Invalid{"usage: put <key> <value>"} : Repl.Command}
```

Add `{==}` proofs when normalization suffices. Keep all parser laws closed until
an honest open parser theorem is practical.

### Step 4: Validate

```sh
./proofs/run.sh
```

### Step 5: Commit checkpoint

```sh
git add app/repl_types.bend app/repl_parser.bend LAWS../proofs/run.sh
git commit -m "feat: define the proven REPL command language"
```

---

## Task 3: Bend REPL session and durable core commands

**Files:**

- Create: `app/repl.bend`
- Create: `app/repl_exec.bend`
- Modify: `bin/mylsm`
- Modify: `app/README.md`

### Step 1: Define affine session state

```python
type Session is Data:
  Session{
    db: Db.Db,
    dir: String,
    timing: TimingMode,
    compute_mode: ComputeMode,
    gpu_enabled: Bool,
    workers: Nat
  }
```

The `Db.Db` value is threaded from one command to the next. Mark a session `+`
only in branches that need both an observation and a returned copy.

### Step 2: Implement bounded REPL loop

```python
def repl_loop(fuel: Nat, session: Session) -> IO(Unit)
def handle_line(line: String, rest: Nat, session: Session) -> IO(Unit)
```

Default fuel: `256n`, the largest validated interpreter-safe session literal in
this implementation. `Exit{}` finishes early; EOF is treated as an empty no-op
until fuel expires because the audited effect intentionally maps EOF to `""`.
Reaching zero prints an explicit command-limit message. Never add `@unsafe` to
simulate an infinite loop.

Prompt through `IO.print("mylsm> ")`, then call `Console.read_line`. A blank line
returns the unchanged session.

### Step 3: Implement durable commands

- `put`: call `Recover.write(db, Wal.Batch{...})`, print `OK`, retain returned DB.
- `del`: same with `Wal.Del`.
- `get`: call `Db.db_get`, print value or `<missing>`, retain the session.
- `help`: print grammar and limits.
- `exit`: print `bye` and stop.
- `Invalid`: print `error: ...`, retain session.

Do not call `Db.open_db`; startup always uses `Recover.open_db`.

### Step 4: Add CLI command

`bin/mylsm repl` must:

1. export effective `MYLSM_DIR`, `MYLSM_EFFECTIVE_DEVICE`,
   `MYLSM_GPU_ENABLED`, and `MYLSM_THREADS`;
2. compile/run `app/repl.bend` using the same adaptive native policy as demo;
3. keep GPU enabled in auto mode when verified so `mode gpu` can switch without
   restarting;
4. fall back to the portable CPU backend only in `auto`/`cpu` modes.

### Step 5: End-to-end test

```sh
printf 'put a 1\nget a\ndel a\nget a\nexit\n' | MYLSM_DEVICE=cpu bin/mylsm repl
```

Expected ordered markers:

```text
OK
1
OK
<missing>
bye
```

Restart against the same directory and confirm the deletion remains visible.

### Step 6: Commit checkpoint

```sh
./proofs/run.sh
git add app/repl.bend app/repl_exec.bend app/README.md bin/mylsm
git commit -m "feat: add persistent Bend REPL with durable commands"
```

---

## Task 4: Timing controls

**Files:**

- Modify: `app/repl_types.bend`
- Modify: `app/repl_exec.bend`
- Modify: `app/repl.bend`
- Modify: `laws/*.bend`
- Modify: `proofs/*Proof.bend`

### Step 1: Implement timing policy as pure state

```python
def timing_after(mode: TimingMode) -> TimingMode
# TimingOnce{} becomes TimingOff{}; other modes are unchanged.

def should_time(mode: TimingMode) -> Bool
```

Add closed laws for all three modes.

### Step 2: Measure commands with `IO.now`

For timed execution:

```python
start : Nat <- IO.now()
next : Session <- execute_untimed(command, session)
finish : Nat <- IO.now()
IO.print("time: " ++ show_elapsed(start, finish))
```

`show_elapsed` uses `Nat.sub`. Print `<1 ms` when elapsed is zero. Label write
measurements as including WAL append, fsync, and MemTable update. Never claim
microsecond accuracy.

### Step 3: Implement commands

```text
timing on
timing off
timing once
time <command>
```

`time <command>` parses `inner` once and executes it with one-shot timing. Reject
`time time ...` to avoid recursive command expansion.

### Step 4: Test

Pipe commands and assert timing lines appear only when expected. Add parser and
state-transition laws, then run `./proofs/run.sh`.

### Step 5: Commit checkpoint

```sh
git add app/repl_types.bend app/repl_exec.bend app/repl.bend LAWS../proofs/run.sh bench/cli_smoke.sh
git commit -m "feat: add precise REPL timing controls"
```

---

## Task 5: CPU/GPU mode controls and restartable threads

**Files:**

- Modify: `app/repl_exec.bend`
- Modify: `app/demo_helpers.bend`
- Modify: `bin/mylsm`
- Modify: `docs/CLI.md`
- Modify: `laws/*.bend`
- Modify: `proofs/*Proof.bend`

### Step 1: Pure compute dispatch

Implement CPU/GPU leaves:

```python
def compute_cpu(fuel: Nat) -> Nat:
  Demo.worker(fuel, 0n)

def compute_gpu(fuel: Nat) -> Nat:
  Demo.worker_gpu!(fuel, 0n)

def compute_dispatch(mode: ComputeMode, gpu_enabled: Bool, fuel: Nat) -> IO(Nat)
```

- `Cpu{}` calls the normal CPU function.
- `Gpu{}` calls `!` only when `gpu_enabled=True`; otherwise prints an error and
  leaves mode unchanged.
- `Auto{}` uses GPU only when enabled, otherwise CPU.

Retain the existing closed CPU/GPU agreement law and add representative fuels.

### Step 2: Runtime commands

```text
runtime
mode auto
mode cpu
mode gpu
compute <fuel>
threads <n>
```

`runtime` prints backend, configured threads, GPU-enabled flag, current compute
mode, timing state, and the statement `storage: CPU/IO`.

### Step 3: Controlled thread restart

Bend cannot change runtime threads in-process. `threads <n>` must print a restart
instruction and exit with a dedicated marker:

```text
RESTART threads=4
```

The launcher detects the marker/status, validates `1..256`, exports
`MYLSM_THREADS=4`, and `exec`s the REPL again against the same directory.
Recovery through `Recover.open_db` preserves acknowledged state.

Do not attempt to mutate the runtime scheduler from Bend.

### Step 4: Validate mode matrix

Test:

- portable CPU;
- native `--threads 1`;
- native all-core CPU;
- native GPU when `.gpu` exists;
- forced GPU without artifact (must fail clearly);
- mode switch CPU -> GPU -> CPU with equal compute results;
- invalid thread values.

### Step 5: Commit checkpoint

```sh
./proofs/run.sh
git add app/repl_exec.bend app/demo_helpers.bend bin/mylsm docs/CLI.md LAWS../proofs/run.sh bench/cli_smoke.sh
git commit -m "feat: control REPL CPU GPU and timing modes"
```

---

## Task 6: Administrative commands

**Files:**

- Modify: `app/repl_parser.bend`
- Modify: `app/repl_exec.bend`
- Modify: `src/Db.bend` only for missing pure projections
- Modify: `laws/*.bend`
- Modify: `proofs/*Proof.bend`

### Step 1: Scan

Use the existing newest-first entries and `MergeIter.scan` semantics. Add a
public pure adapter only if the current signatures do not compose cleanly:

```python
def db_scan(db: Db.Db, lo: String, hi: String) -> List<&2, MemTable.Entry>
```

Print one `key=value` line per live entry. Keep recursion structural on the
entry list.

### Step 2: Stats

Expose pure projections for:

- MemTable entry count;
- table count per level;
- total table count;
- flush generation;
- data directory.

Stats must not read or mutate files. Add closed projection laws.

### Step 3: Flush and compact

- `flush`: invoke `Flush.flush` on the current DB.
- `compact`: invoke `Compact.compact` or a focused adapter.
- `maintain`: invoke `Recover.maintain`.

All errors are surfaced; the previous session state is not silently reported as
successful.

### Step 4: Validate preservation

Create an end-to-end sequence that writes keys, flushes/compacts, and verifies
identical reads/scans. Existing preservation laws remain mandatory.

### Step 5: Commit checkpoint

```sh
./proofs/run.sh
git add app/repl_parser.bend app/repl_exec.bend src/Db.bend LAWS../proofs/run.sh bench/cli_smoke.sh
git commit -m "feat: add REPL scan stats and maintenance commands"
```

---

## Task 7: Quoted values and import/export

**Files:**

- Create: `app/repl_lexer.bend`
- Modify: `app/repl_parser.bend`
- Modify: `app/repl_exec.bend`
- Modify: `laws/*.bend`
- Modify: `proofs/*Proof.bend`
- Modify: `docs/CLI.md`

### Step 1: Pure lexer

Implement a structural lexer supporting:

- unquoted tokens;
- double-quoted strings;
- escapes `\\`, `\"`, `\n`, `\t`;
- explicit failure for unterminated quotes or unknown escapes.

Use a single state datatype instead of mutual recursion. Add closed laws for
spaces, empty strings, escapes, and malformed input.

### Step 2: Export

`export <path>` writes a deterministic sorted representation to `path.tmp`,
fsyncs, renames, and fsyncs the parent directory. Reuse audited filesystem
helpers and reject paths outside the explicitly supplied export target.

Format v1:

```text
MYLSM-EXPORT-1
<encoded key>\t<encoded value>\n
#<checksum>
```

### Step 3: Import

`import <path>` validates version/checksum before applying one or more durable
batches. A malformed import performs no acknowledged mutation. Document whether
large imports are atomic or batch-atomic; do not claim whole-file atomicity
unless it is implemented.

### Step 4: Laws and tests

Add closed lexer/escape round-trip laws and empirical export/import round trips.
Run malformed, truncated, and checksum-corrupt fixtures.

### Step 5: Commit checkpoint

```sh
./proofs/run.sh
git add app/repl_lexer.bend app/repl_parser.bend app/repl_exec.bend docs/CLI.md LAWS../proofs/run.sh bench/cli_smoke.sh
git commit -m "feat: add quoted REPL values and data interchange"
```

---

## Task 8: Documentation, usability, and Phase 1 gate

**Files:**

- Create or complete: `docs/CLI.md`
- Modify: `README.md`
- Modify: `app/README.md`
- Modify: `bench/cli_smoke.sh`

### Step 1: Document command reference

For every command document syntax, output, durability, timing scope, CPU/GPU
eligibility, and errors. Include a scripted session and recovery example.

### Step 2: Full smoke script

`bench/cli_smoke.sh` must use a temporary directory and cover:

1. `doctor`;
2. proof gate;
3. portable REPL put/get/del/restart;
4. timing on/off/once;
5. CPU/GPU compute agreement when GPU is available;
6. stats, scan, flush, compact;
7. quoted values;
8. export/import round trip;
9. cleanup via trap.

### Step 3: Final validation

```sh
./proofs/run.sh
bend bench/fuzz.bend
sh -n bin/mylsm bench/cli_smoke.sh
bench/cli_smoke.sh
git diff --check
```

Run native CPU and GPU paths on supported hardware and record actual capability
results without fabricating unsupported platforms.

### Step 4: Update roadmap

Mark Phase 1 items complete only when the associated command and test pass.
Keep Phase 2–4 claims unchanged.

### Step 5: Final checkpoint

```sh
git add README.md docs/CLI.md app/README.md bench/cli_smoke.sh
git commit -m "docs: complete the Phase 1 developer product"
```

## Phase 1 definition of done

- A persistent, fuel-bounded Bend REPL supports durable put/get/delete.
- Restart recovery is demonstrated automatically.
- Scan, stats, flush, compact, and maintain are usable and documented.
- Timing can be global, one-shot, or command-local and is labeled accurately.
- CPU/GPU compute mode can change safely; thread changes use controlled restart.
- Quoted keys/values and deterministic import/export work for documented limits.
- CPU-only machines remain fully functional.
- Native GPU mode is claimed only with a built `.gpu` artifact and successful
  execution.
- All new pure behavior has closed laws, `./proofs/run.sh` passes, and host
  effects have C/JS smoke coverage.
- `README.md` labels MyLSM as a developer product, not production-ready.

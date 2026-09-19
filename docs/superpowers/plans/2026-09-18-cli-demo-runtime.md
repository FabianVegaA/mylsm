# CLI, Demo, and Adaptive Runtime Implementation Plan

> **For agentic workers:** follow the repository `AGENT.md`; run `bend guide`,
> keep laws in `laws/*.bend`, and run `./proofs/run.sh` before committing.

**Goal:** Add a safe developer CLI, a runnable mini application, and adaptive
CPU/GPU execution without changing the MyLSM on-disk format or weakening the
proof gate.

**Spec:** `docs/superpowers/specs/2026-09-18-cli-demo-runtime-design.md`

## Global constraints

- Preserve commit `382f1dc` behavior and existing public storage semantics.
- No `@unsafe` definitions.
- No automatic dependency installation, telemetry, or network access.
- Shell detection is advisory and fails closed to CPU.
- GPU is used only for pure compute; filesystem/WAL/Manifest IO stays on CPU.
- Every code change must pass `./proofs/run.sh`.
- Keep the CLI POSIX `sh` compatible; use `shellcheck` when available.

---

## Task 1: Resource detection and CLI contract

**Files:**

- Create: `bin/mylsm`
- Create: `docs/CLI.md`

### Step 1: Write the failing CLI checks

Add a shell smoke script or documented commands covering:

```sh
bin/mylsm doctor
bin/mylsm --help
bin/mylsm check
```

Expected initial failure: the launcher does not exist.

### Step 2: Implement safe detection

Implement shell functions for:

- logical CPU count on macOS/Linux;
- OS/architecture;
- optional Metal/CUDA/GPU probes;
- bounded thread parsing (`1..256`);
- `MYLSM_DEVICE`, `MYLSM_THREADS`, and `MYLSM_GPU_MEMORY` overrides.

Do not use command substitution with untrusted user paths. Quote every path and
use `exec` for the final process.

### Step 3: Implement subcommands

Support:

```text
doctor, check, fuzz, bench, build, run, demo, --help
```

`check` runs `./proofs/run.sh`; `fuzz` and `bench` run their existing Bend
programs; `build` compiles the demo to a user-local build directory; `run` runs
the compiled artifact with selected runtime flags; `demo` builds when necessary
and runs the demo.

### Step 4: Validate

Run:

```sh
sh -n bin/mylsm
bin/mylsm doctor
bin/mylsm --help
bin/mylsm check
```

### Step 5: Commit checkpoint

```sh
git add bin/mylsm docs/CLI.md
git commit -m "feat: add adaptive MyLSM CLI"
```

---

## Task 2: Mini application

**Files:**

- Create: `app/mylsm_demo.bend`
- Create: `app/README.md`

### Step 1: Add pure demo worker

Implement a small uniform numeric worker and call it with Bend's `!` notation.
The worker must be total, structurally decreasing or fuel-bounded, and have a
closed law in `laws/*.bend` if it is exported from a source module. Keep it local
to the demo if it is only presentation code.

### Step 2: Add durable storage walkthrough

The app should:

1. call `Recover.open_db`;
2. put two keys;
3. read/print both values;
4. delete one key;
5. read/print the missing result;
6. print the compute result and completion marker.

Use `IO.try` to fail loudly on storage errors. Keep the default directory
`.mylsm-demo-data` and support the CLI-provided directory mechanism.

### Step 3: Validate directly

Run both portable and native paths where supported:

```sh
bend app/mylsm_demo.bend
bend app/mylsm_demo.bend -o .mylsm/build/demo
.mylsm/build/demo --threads 1
```

Do not claim GPU execution unless the native `.gpu` artifact is built and run.

### Step 4: Proof gate

Run:

```sh
./proofs/run.sh
```

### Step 5: Commit checkpoint

```sh
git add app/mylsm_demo.bend app/README.md LAWS../proofs/run.sh
 git commit -m "feat: add MyLSM demonstration app"
```

---

## Task 3: Adaptive native execution

**Files:**

- Modify: `bin/mylsm`
- Modify: `docs/CLI.md`
- Create: `.gitignore` entry for `.mylsm/` if needed

### Step 1: CPU path

Build the demo with Bend and invoke the binary using the detected or overridden
thread count:

```sh
bend app/mylsm_demo.bend -o .mylsm/build/demo
.mylsm/build/demo --threads "$threads"
```

Validate that the generated executable exits with the demo completion marker.

### Step 2: GPU path

When the probe succeeds:

```sh
bend app/mylsm_demo.bend -o .mylsm/build/demo
.mylsm/build/demo --threads "$threads" --gpu "$gpu_memory"
```

Verify the `.gpu` artifact exists beside the executable. If it does not, report
GPU unavailable and stop rather than claiming GPU use.

### Step 3: Fallback tests

Exercise:

- `MYLSM_DEVICE=cpu bin/mylsm demo`;
- `MYLSM_DEVICE=auto bin/mylsm demo`;
- a forced `MYLSM_DEVICE=gpu` on a CPU-only machine, which must fail clearly;
- invalid `MYLSM_THREADS`, which must fail before compilation.

### Step 4: Commit checkpoint

```sh
git add bin/mylsm docs/CLI.md .gitignore
 git commit -m "feat: select CPU and GPU execution conservatively"
```

---

## Task 4: Integration and release evidence

**Files:**

- Modify: `docs/CLI.md`
- Create: `bench/cli_smoke.sh`
- Modify: `bench/BASELINE.md` only with measured values, never placeholders

### Step 1: Add smoke runner

Run doctor, check, CPU demo, fuzz, and benchmark in a clean temporary data
folder. Ensure cleanup happens with a trap and failures preserve useful logs.

### Step 2: Validate all gates

```sh
./proofs/run.sh
sh -n bin/mylsm bench/cli_smoke.sh
bench/cli_smoke.sh
```

Run `shellcheck` if installed. Run native GPU checks only on hosts where the
probe and compiler are available.

### Step 3: Record capability matrix

Document observed results for:

- macOS CPU-only fallback;
- macOS Metal, if present;
- Linux CPU-only fallback;
- Linux CUDA, if present;
- missing clang/native compiler.

Do not fabricate throughput, GPU, or RocksDB comparison numbers.

### Step 4: Final proof and review

Run `./proofs/run.sh`, inspect `git diff --check`, and confirm that no generated
binaries/data directories are tracked.

### Step 5: Commit checkpoint

```sh
git add docs/CLI.md bench/cli_smoke.sh bench/BASELINE.md
 git commit -m "test: add CLI and runtime integration gates"
```

## Detailed Bend 2 implementation blueprint

This section is normative for the implementation. The POSIX launcher and the Bend
program have different responsibilities because Bend 2.0.5's Base API does not
provide portable `argv`, CPU-count, Metal, or CUDA introspection. Hardware
capability detection therefore remains in `bin/mylsm`; all storage behavior and
all compute kernels remain in Bend.

### A. Repository module layout

Create the following files:

```text
bin/mylsm                  # POSIX adapter: argv, host probes, bend flags
app/mylsm_demo.bend              # Bend executable entry point
app/demo_helpers.bend              # pure demo helpers and formatting
app/Runtime.bend (future host-policy types)           # Bend-side mode/configuration types
app/README.md              # direct Bend/native invocation notes
bench/cli_smoke.sh         # launcher integration test
```

Do not put shell effects, hardware probes, or dynamic process execution in
`src/`. The database core must remain importable by pure proofs.

### B. Bend-side runtime types

`app/Runtime.bend (future host-policy types)` must use explicit `Data` types:

```python
import Base

type Device is Data:
  Cpu{}
  Gpu{}

type DemoConfig is Data:
  Config{dir: String, device: Device, workers: Nat}

type DemoResult is Data:
  Result{writes: Nat, deleted: Bool, worker_value: Nat}
```

The Bend program receives the effective directory/device/thread policy from the
launcher by compiling a small generated configuration module, or by using the
checked-in defaults when invoked directly with `bend app/mylsm_demo.bend`. It must not
pretend that it can inspect the host itself.

Required pure functions:

```python
def worker_count(c: DemoConfig) -> Nat
# returns at least 1; no IO and no host assumptions

def device_name(d: Device) -> String
# "cpu" or "gpu"

def worker(n: Nat, acc: Nat) -> Nat
# structurally/fuel bounded uniform computation

def worker_gpu(n: Nat, acc: Nat) -> Nat
# same result as worker; body delegates to worker or mirrors its total recursion
```

The GPU entry must be called with Bend's GPU call marker:

```python
value : Nat <- worker_gpu!(WORK_FUEL, 0n)
```

The actual implementation must use a fixed-size numeric workload, not file
handles, strings, `Maybe`, or `IO` values. GPU execution is only a scheduling
choice; the result must be identical to the CPU function. On a machine without a
GPU, Bend's documented runtime behavior executes `!` work on the CPU.

If using parallel-let instead of a single GPU call, use independent branches
only:

```python
a b = worker_gpu!(FUEL_A, 0n) worker_gpu!(FUEL_B, 0n)
```

Then combine `a` and `b` after both branches complete. Never share affine file
handles or a mutable-looking database value across parallel branches.

### C. Bend demo IO flow

`app/mylsm_demo.bend` must import:

```python
import Base
import ../src/Db.bend as Db
import ../src/Recover.bend as Recover
import ./Demo.bend as Demo
```

Use a small result-unwrapping helper because `Recover.open_db` and `Db.db_put`
return `IO<Result<...>>`:

```python
def open_or_die(dir: String) -> IO(Db.Db):
  IO.try(Db.Db, Recover.open_db(dir))

def put_or_die(db: Db.Db, key: String, value: String) -> IO(Db.Db):
  IO.try(Db.Db, Db.db_put(db, key, value))
```

The main sequence must be affine and explicit:

```python
def main() -> IO(Unit):
  do IO<Unit>:
    db0 : Db.Db <- open_or_die(".mylsm-demo-data")
    db1 : Db.Db <- put_or_die(db0, "hello", "world")
    db2 : Db.Db <- put_or_die(db1, "answer", "42")
    # read db2 before delete and print a concrete value
    db3 : Db.Db <- delete_or_die(db2, "hello")
    # read db3 and print the missing result
    value : Nat <- Demo.run_worker(...)
    IO.print("MYLSM DEMO OK ...")
```

The final program must not recursively reuse an affine `Db.Db` value. If a loop
is needed, put the decreasing `Nat` parameter first and thread the database as
the later parameter:

```python
def put_loop(n: Nat, db: Db.Db) -> IO(Db.Db):
  match n:
    case 0n:
      IO.pure(Db.Db, db)
    case 1n+m:
      # write once, then recurse on m and the returned Db
```

Because Bend forbids mutual recursion and computed-expression matches, bind
computed values through a helper whose parameter is then matched. This applies
to `Maybe`, `Bool`, and `Result` formatting helpers.

### D. Storage correctness boundary

The demo must use these existing, already-proven paths:

```text
Recover.open_db -> Db.Db
Db.db_put       -> WAL append -> fsync -> MemTable update
Db.db_del       -> WAL append -> fsync -> tombstone
Db.db_get       -> newest-first read path
```

Do not call `Db.open_db` from the demo: that function only creates an in-memory
handle and does not perform startup recovery. Do not add a second WAL writer.

For output formatting add pure helpers such as:

```python
def show_maybe(m: Maybe<&2, String>) -> String
# None{} -> "<missing>"; Some{v} -> v
```

Use `+` only where a value is printed or consumed more than once, and preserve
the existing `Maybe<&2, String>` annotations used by the repository.

### E. Native compilation and runtime contract

`bin/mylsm` is responsible for invoking Bend exactly as follows:

```sh
bend app/mylsm_demo.bend -o .mylsm/build/demo
.mylsm/build/demo --threads "$threads"
.mylsm/build/demo --threads "$threads" --gpu "$gpu_memory"
```

The exact runtime flags are passed to the generated native binary, not to the
Bend source checker. The wrapper must verify `.mylsm/build/demo.gpu` exists
before selecting GPU mode. A direct `bend app/mylsm_demo.bend` invocation is the
portable JS/interpreter path and reports `device=cpu-portable`.

The wrapper's mode table is:

| Requested mode | GPU probe | Native compiler | Action |
|---|---:|---:|---|
| `auto` | no | any | native CPU |
| `auto` | yes | yes | native GPU with CPU fallback |
| `cpu` | irrelevant | yes | native CPU |
| `gpu` | no | any | fail with remediation |
| `gpu` | yes | no | fail with compiler remediation |

The Bend program itself must print the effective logical mode supplied by the
launcher, but correctness must not depend on that string.

### F. CPU/GPU detection implementation

Implement these POSIX functions in `bin/mylsm`:

```sh
logical_cpus()       # sysctl hw.logicalcpu, then nproc, then 1
has_metal_gpu()      # macOS system_profiler probe; empty/failed = false
has_cuda_gpu()       # Linux nvidia-smi probe; empty/failed = false
native_available()   # command -v clang and a bounded compile smoke check
validate_threads()   # decimal integer, 1..256
select_device()      # cpu|gpu|auto precedence and fail-closed policy
```

Never parse a human-readable GPU name as proof of runtime compatibility. The
positive test is: probe succeeds, native build succeeds, and the `.gpu` artifact
exists. Otherwise `auto` prints a fallback and runs CPU.

### G. Laws and tests for Bend additions

If `app/Runtime.bend (future host-policy types)` exports pure helpers, append closed laws to `laws/*.bend`:

```python
law demo_worker_zero:
  {Demo.worker(0n, 0n) == 0n : Nat}

law demo_worker_gpu_agrees:
  {Demo.worker_gpu(8n, 0n) == Demo.worker(8n, 0n) : Nat}

law device_names:
  {Runtime.device_name(Runtime.Cpu{}) == "cpu" : String}
```

Add the matching proof stubs to `proofs/*Proof.bend`, run `./proofs/run.sh`, and keep
all IO/host code outside the laws. The smoke suite must run:

```sh
./proofs/run.sh
bend app/mylsm_demo.bend
sh -n bin/mylsm
bench/cli_smoke.sh
```

`bench/cli_smoke.sh` must test both `MYLSM_DEVICE=cpu` and `MYLSM_DEVICE=auto`
in a temporary directory, preserve logs on failure, and remove generated
`.mylsm`/demo data on success.

## Definition of done

- CLI commands and error paths are documented and executable.
- Demo performs durable put/get/delete operations and reports completion.
- CPU thread selection is bounded and visible.
- GPU selection is opt-in/verified and automatically falls back only in auto
  mode.
- CPU-only machines remain fully functional.
- Bend modules, signatures, affine ownership, recursion order, and `!` usage
  are implemented as specified above.
- Proof, shell syntax, and integration gates pass.
- No performance or hardware claim is made without a recorded measurement.

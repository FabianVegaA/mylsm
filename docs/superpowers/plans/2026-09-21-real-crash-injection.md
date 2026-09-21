# Real Crash Injection and Recovery Verification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the crash-test scaffold with deterministic external `kill -9` injection at exact durability boundaries and verify that repeated recovery preserves every acknowledged key.

**Architecture:** Keep checkpoint selection in Bend: `CrashPoint.hit(name)` reads the environment through `Console.get_env` and applies the pure, witnessed `CrashPoint.enabled` policy. Only `CrashPoint.stop(name)` crosses the audited C/JavaScript boundary to emit a marker and send `SIGSTOP`; the Bash controller observes both before sending external `kill -9`. Deterministic WAL, flush, and compaction fixtures are then reopened twice and checked against acknowledged key/value sets and expected level shapes.

**Tech Stack:** Bend 2, audited C/JavaScript effects, native Bend compilation, Bash, Darwin/Linux process signals, existing MyLSM WAL/flush/compaction/recovery APIs.

**Spec:** `docs/superpowers/specs/2026-09-17-lsm-bend-design.md`, especially §§2.1, 2.6, 4, and release gate 3 in §9.

## Global Constraints

- Follow `AGENT.md`; run `bend guide` before Bend work and `bend guide effects` before implementing the host effect.
- Never use `@unsafe` in product code, laws, witnesses, or test drivers.
- Keep this plan limited to crash injection and recovery verification. Parser mutation and proof-performance work require separate plans.
- Storage IO, crash checkpoints, recovery, and verification remain CPU-only.
- `CrashPoint.enabled` and activation branching belong in Bend and receive laws/witnesses; only marker emission and `SIGSTOP` are empirical host behavior.
- With `MYLSM_CRASH_POINT` unset or unequal to the supplied name, `CrashPoint.hit` must be a successful no-op.
- With an exact match on Darwin or Linux, the effect emits `crash_point_reached=<name>` directly to stderr and the worker sends itself `SIGSTOP`; only the external Bash harness sends `kill -9`.
- An exact request on an unsupported platform fails explicitly rather than silently skipping the checkpoint.
- Preserve WAL, SSTable, Manifest, rename, fsync, and cleanup ordering exactly.
- Do not use timed sleeps to choose a crash window. Polling is allowed only to observe an already deterministic stopped state with a bounded timeout.
- Recovery must be verified through two independent `Recover.open_db` calls.
- Default matrix repetitions must be at least three.
- Preserve all case data and logs on failure.
- A proof timeout is a failure. Never report `./proofs/run.sh` as green unless it exits zero with `FAIL=0 TIMEOUT=0`.
- Every commit step below is conditional on a genuinely green proof gate. If the existing documented proof timeouts remain, retain changes uncommitted and report the blocker.
- Do not mark parser-hardening roadmap items complete.

## File Structure

- Create `src/CrashPoint.bend`: pure activation policy plus narrow IO wrapper for deterministic test checkpoints.
- Create `laws/CrashPoint.bend`: an open unset theorem plus closed mismatch/exact activation fixtures.
- Create `proofs/CrashPointProof.bend`: witnesses for the activation-policy laws.
- Create `src/effs/crash_point.c`: native marker emission, platform check, and `SIGSTOP` only.
- Create `src/effs/crash_point.js`: JavaScript twin with matching semantics.
- Create `bench/crash_point_smoke.bend`: smallest checkpoint caller.
- Create `bench/crash_point_smoke.sh`: unset, mismatch, stop, and external-kill smoke gate.
- Create `bench/crash_worker.bend`: deterministic prepare, crash-operation, and verify modes.
- Replace `bench/fault_inject.sh`: safe ten-checkpoint matrix controller.
- Create `bench/crash_point_overhead.sh`: pre/post no-op overhead measurement.
- Modify `src/Db.bend`: WAL checkpoints.
- Modify `src/Flush.bend`: flush publication checkpoints.
- Modify `src/Compact.bend`: compaction publication checkpoints.
- Modify `docs/superpowers/specs/2026-09-17-lsm-bend-design.md`: test-only effect and empirical trust boundary.
- Modify `bench/BASELINE.md`: measured no-op overhead observation.
- Modify `README.md`: accepted matrix usage and roadmap status.

---

### Task 0: Establish the Execution Baseline

**Files:**

- Inspect: `AGENT.md`
- Inspect: `README.md`
- Inspect: `docs/superpowers/specs/2026-09-17-lsm-bend-design.md`
- Modify: none

**Interfaces:**

- Consumes: the installed Bend toolchain and existing modular proof runner.
- Produces: recorded tool versions and an honest pre-change proof result.

- [ ] **Step 1: Refresh Bend syntax and effect conventions**

Run:

```bash
bend guide
bend guide effects
```

Expected: both commands exit `0`. Stop before editing `.bend`, `.c`, or `.js` effect files if either command fails.

- [ ] **Step 2: Record tool and platform details**

Run:

```bash
bend --version
uname -s
uname -m
```

Expected: Bend 2 and a platform record. The real matrix supports only `Darwin` and `Linux`.

- [ ] **Step 3: Record the worktree without modifying it**

Run:

```bash
git --no-optional-locks status --short
```

Expected: existing user changes are known and preserved.

- [ ] **Step 4: Run the current proof gate**

Run:

```bash
./proofs/run.sh
```

Green completion requires:

```text
SUMMARY PASS=<total> FAIL=0 TIMEOUT=0 TOTAL=<total>
```

Record the exact summary and log paths. The current README documents timeouts, so this may establish a pre-existing commit blocker; it does not authorize weakening the gate.

---

### Task 1: Specify and Implement the Audited CrashPoint Effect

**Files:**

- Create: `bench/crash_point_smoke.bend`
- Create: `bench/crash_point_smoke.sh`
- Create: `src/CrashPoint.bend`
- Create: `src/effs/crash_point.c`
- Create: `src/effs/crash_point.js`
- Modify: `docs/superpowers/specs/2026-09-17-lsm-bend-design.md`

**Interfaces:**

- Consumes: `Console.get_env("MYLSM_CRASH_POINT")` from Bend.
- Produces: `CrashPoint.enabled(configured: String, requested: String) -> Bool`.
- Produces: `CrashPoint.stop(name: String) -> IO(Result<&1, &1, U32 & String, Unit>)` as the minimal host boundary.
- Produces: `CrashPoint.hit(name: String) -> IO(Result<&1, &1, U32 & String, Unit>)` as the Bend-owned policy wrapper.
- Unset or unequal value: `Done{Unit{}}`.
- Exact value on Darwin/Linux: write an unbuffered `crash_point_reached=<name>` marker to stderr, then enter stopped state through `SIGSTOP`.
- Exact value elsewhere: explicit host-effect failure.
- Exact smoke marker: `crash_point_smoke=pass unset=pass mismatch=pass js_matching_stop=pass native_matching_stop=pass kill_status=137`.

- [ ] **Step 1: Write the failing Bend smoke program**

Create `bench/crash_point_smoke.bend` before creating `src/CrashPoint.bend`:

```python
import Base
import ../src/CrashPoint.bend as CrashPoint

def main() -> IO(Unit):
  do IO<Unit>:
    hit : Unit <- IO.try(Unit, CrashPoint.hit("smoke.stop"))
    IO.print("crash_point_smoke_program=complete")
```

- [ ] **Step 2: Write the failing shell acceptance check**

Create `bench/crash_point_smoke.sh` with strict mode and this observable contract:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
BUILD="$ROOT/.mylsm/build/crash-point-smoke"
JS_BUILD="$ROOT/.mylsm/build/crash-point-smoke.js"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mylsm-crash-smoke.XXXXXX")
PID=
trap 'rc=$?; if [[ -n ${PID:-} ]] && kill -0 "$PID" 2>/dev/null; then kill -9 "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true; fi; rm -rf -- "$WORK"; exit "$rc"' EXIT HUP INT TERM

wait_for_stop() {
  local pid=$1 deadline=$((SECONDS + 10)) state
  while (( SECONDS < deadline )); do
    state=$(ps -o stat= -p "$pid" 2>/dev/null | tr -d '[:space:]' || true)
    case "$state" in T*) return 0 ;; esac
    kill -0 "$pid" 2>/dev/null || return 1
    sleep 0.05
  done
  return 124
}

case "$(uname -s)" in Darwin|Linux) ;; *) echo "unsupported platform" >&2; exit 2 ;; esac
mkdir -p -- "$ROOT/.mylsm/build"

unset MYLSM_CRASH_POINT
bend "$ROOT/bench/crash_point_smoke.bend" >"$WORK/unset.log"
grep -q '^crash_point_smoke_program=complete$' "$WORK/unset.log"

MYLSM_CRASH_POINT=other.point bend "$ROOT/bench/crash_point_smoke.bend" >"$WORK/mismatch.log"
grep -q '^crash_point_smoke_program=complete$' "$WORK/mismatch.log"

bend "$ROOT/bench/crash_point_smoke.bend" -o "$JS_BUILD"
MYLSM_CRASH_POINT=smoke.stop node "$JS_BUILD" >"$WORK/js-match.log" 2>&1 &
PID=$!
wait_for_stop "$PID"
grep -qxF 'crash_point_reached=smoke.stop' "$WORK/js-match.log"
kill -9 "$PID"
set +e
wait "$PID"
js_status=$?
set -e
PID=
[[ "$js_status" -eq 137 ]]

bend "$ROOT/bench/crash_point_smoke.bend" -o "$BUILD"
MYLSM_CRASH_POINT=smoke.stop "$BUILD" --threads 1 >"$WORK/native-match.log" 2>&1 &
PID=$!
wait_for_stop "$PID"
grep -qxF 'crash_point_reached=smoke.stop' "$WORK/native-match.log"
kill -9 "$PID"
set +e
wait "$PID"
native_status=$?
set -e
PID=
[[ "$native_status" -eq 137 ]]

echo "crash_point_smoke=pass unset=pass mismatch=pass js_matching_stop=pass native_matching_stop=pass kill_status=137"
```

- [ ] **Step 3: Verify the smoke check fails before implementation**

Run:

```bash
chmod +x bench/crash_point_smoke.sh
bash -n bench/crash_point_smoke.sh
bench/crash_point_smoke.sh
```

Expected: shell syntax passes, then the smoke run fails because `src/CrashPoint.bend` does not exist. The final pass marker must be absent.

- [ ] **Step 4: Add the Bend effect wrapper**

Create `src/CrashPoint.bend`:

```python
import Base
import ./Console.bend as Console

def nonempty(value: String) -> Bool:
  match value:
    case SNil{}: False{}
    case SCon{_, _}: True{}

def enabled(+configured: String, requested: String) -> Bool:
  Bool.and(nonempty(configured), String.eq(configured, requested))

def stop(name: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  import "./effs/crash_point.c"
  import "./effs/crash_point.js"

def hit_decision(active: Bool, name: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  match active:
    case True{}: stop(name)
    case False{}: IO.pure(Result<&1, &1, U32 & String, Unit>, Done{Unit{}})

def hit(+name: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  do IO<Result<&1, &1, U32 & String, Unit>>:
    configured : String <- IO.try(String, Console.get_env("MYLSM_CRASH_POINT"))
    hit_decision(enabled(configured, name), name)
```

- [ ] **Step 5: Add the native C twin**

Create `src/effs/crash_point.c`:

```c
// Exact-match test checkpoint. The external harness sends SIGKILL.
Term stop_run(Env e, Term* f, IoWork* w) {
  uint64_t length = 0;
  char* name = io_cstr(e, f[0], &length);
  (void)w;
#if defined(__APPLE__) || defined(__linux__)
  const char marker[] = "crash_point_reached=";
  int marker_ok = write(STDERR_FILENO, marker, sizeof(marker) - 1) == sizeof(marker) - 1
    && write(STDERR_FILENO, name, length) == length
    && write(STDERR_FILENO, "\n", 1) == 1;
  free(name);
  if (!marker_ok) {
    return io_fail(e, errno != 0 ? errno : EIO, NULL);
  }
  if (kill(getpid(), SIGSTOP) != 0) {
    return io_fail(e, errno, NULL);
  }
  return io_done(e, term_pak(CID_UNIT, 0));
#else
  free(name);
  return io_fail(e, ENOTSUP, NULL);
#endif
}

static void __attribute__((constructor)) stop_use(void) {
  io_eff(CID_STOP, stop_run, 0);
}
```

The Bend-generated native translation unit must already provide the standard declarations used by adjacent effects. If `bend guide effects` requires explicit headers for this Bend version, add only `<errno.h>`, `<signal.h>`, `<stdlib.h>`, `<string.h>`, and `<unistd.h>`.

- [ ] **Step 6: Add the JavaScript twin**

Create `src/effs/crash_point.js`:

```javascript
function stop(name) {
  try {
    const requested = Buffer.from(io_bytes(name));
    if (process.platform !== "darwin" && process.platform !== "linux") {
      const os = require("os");
      return io_fail(Math.abs(os.constants.errno.ENOTSUP ?? 95));
    }
    const fs = require("fs");
    fs.writeSync(2, Buffer.concat([Buffer.from("crash_point_reached="), requested, Buffer.from("\n")]));
    process.kill(process.pid, "SIGSTOP");
    return io_done({ $: "Unit" });
  } catch (error) {
    return io_fail(Math.abs(error.errno ?? 5));
  }
}
```

- [ ] **Step 7: Add pure activation-policy laws and witnesses**

Create `laws/CrashPoint.bend` with an open theorem showing that an unset value
disables every requested name, plus closed fixtures showing mismatch disabled
and exact non-empty match enabled. Create
`proofs/CrashPointProof.bend`, import the law module as `Laws`, and discharge all
three witnesses with `{==}`. Run:

```bash
bend proofs/CrashPointProof.bend
```

Expected: `All terms check.` Host marker emission and `SIGSTOP` remain outside
the theorem scope.

- [ ] **Step 8: Amend the trust-root specification**

Add to §3.3 of `docs/superpowers/specs/2026-09-17-lsm-bend-design.md`:

```markdown
A test-only exception is `CrashPoint.hit(name)`, implemented by audited C/JS
twins. It reads only `MYLSM_CRASH_POINT`. Unset or unequal values are no-ops;
on Darwin/Linux an exact match sends the worker `SIGSTOP`, after which the
external harness sends `SIGKILL`. An exact request fails explicitly elsewhere.
This is empirical host behavior and proves nothing about signals, `fsync`,
rename, process death, filesystems, or storage hardware.
```

Update release gate 3 to name the ten checkpoints introduced in Task 2 and to require external `kill -9`, two successful reopens, and preservation of acknowledged state.

- [ ] **Step 9: Run the passing effect smoke checks**

Run:

```bash
bench/crash_point_smoke.sh
bend bench/crash_point_smoke.bend
```

Expected:

```text
crash_point_smoke=pass unset=pass mismatch=pass js_matching_stop=pass native_matching_stop=pass kill_status=137
```

- [ ] **Step 10: Run the proof gate and conditionally commit**

Run:

```bash
./proofs/run.sh
```

Only if the gate exits zero with no timeout:

```bash
git add src/CrashPoint.bend src/effs/crash_point.c src/effs/crash_point.js \
  laws/CrashPoint.bend proofs/CrashPointProof.bend \
  bench/crash_point_smoke.bend bench/crash_point_smoke.sh \
  docs/superpowers/specs/2026-09-17-lsm-bend-design.md
git commit -m "test: add audited crash checkpoint effect"
```

Otherwise keep the changes uncommitted and report the proof blocker.

---

### Task 2: Instrument Exact Durability Boundaries

**Files:**

- Modify: `src/Db.bend`
- Modify: `src/Flush.bend`
- Modify: `src/Compact.bend`

**Interfaces:**

- Consumes: `CrashPoint.hit(name)`.
- Produces exactly these names, each at one call site:
  - `wal.appended`
  - `wal.synced`
  - `flush.table_synced`
  - `flush.table_published`
  - `flush.manifest_synced`
  - `flush.manifest_published`
  - `compact.output_synced`
  - `compact.output_published`
  - `compact.manifest_synced`
  - `compact.manifest_published`
- Preserves public signatures of `Db.db_write`, `Flush.flush`, and `Compact.compact`.

- [ ] **Step 1: Add the imports**

Add to all three modules:

```python
import ./CrashPoint.bend as CrashPoint
```

- [ ] **Step 2: Instrument WAL append and sync**

In `Db.wal_tail`, preserve this exact order:

```python
res : Unit <- IO.try(Unit, IO.pure(Result<&1, &1, U32 & String, Unit>, r))
cp1 : Unit <- IO.try(Unit, CrashPoint.hit("wal.appended"))
cls : Unit <- File.close(f2)
syn : Unit <- IO.try(Unit, Fs.fsync(wal_path(dir)))
cp2 : Unit <- IO.try(Unit, CrashPoint.hit("wal.synced"))
prm : Unit <- IO.try(Unit, Fs.chmod(wal_path(dir), U32.from_nat(384n)))
return Done{res}
```

`wal.synced` remains inside `wal_append`, before `Db.db_write` applies the batch to the MemTable or returns.

- [ ] **Step 3: Instrument flush table publication**

In `Flush.flush_goA`, preserve:

```python
u1 : Unit <- IO.try(Unit, ensure_dir(l0dir))
u2 : Unit <- IO.try(Unit, write_file(tmp, content))
cp1 : Unit <- IO.try(Unit, CrashPoint.hit("flush.table_synced"))
u3 : Unit <- IO.try(Unit, Fs.rename(tmp, final))
u4 : Unit <- IO.try(Unit, Fs.fsync(l0dir))
cp2 : Unit <- IO.try(Unit, CrashPoint.hit("flush.table_published"))
+m : Manifest.Manifest <- IO.try(Manifest.Manifest, load_mfst(mpath))
```

- [ ] **Step 4: Instrument flush Manifest publication**

In `Flush.flush_goB`, preserve:

```python
v1 : Unit <- IO.try(Unit, write_file(mtmp, Manifest.serialize(m2)))
cp1 : Unit <- IO.try(Unit, CrashPoint.hit("flush.manifest_synced"))
v2 : Unit <- IO.try(Unit, Fs.rename(mtmp, mpath))
v3 : Unit <- IO.try(Unit, Fs.fsync(dir))
cp2 : Unit <- IO.try(Unit, CrashPoint.hit("flush.manifest_published"))
rm : Result<&1, &1, U32 & String, Unit> <- Fs.remove(Db.wal_path(dir))
```

- [ ] **Step 5: Instrument compaction output publication**

In `Compact.compact_goA`, preserve:

```python
u1 : Unit <- IO.try(Unit, Flush.ensure_dir(l1dir))
u2 : Unit <- IO.try(Unit, Flush.write_file(tmp, content))
cp1 : Unit <- IO.try(Unit, CrashPoint.hit("compact.output_synced"))
u3 : Unit <- IO.try(Unit, Fs.rename(tmp, final))
u4 : Unit <- IO.try(Unit, Fs.fsync(l1dir))
cp2 : Unit <- IO.try(Unit, CrashPoint.hit("compact.output_published"))
+m : Manifest.Manifest <- IO.try(Manifest.Manifest, Flush.load_mfst(mpath))
```

- [ ] **Step 6: Instrument compaction Manifest publication**

In `Compact.compact_goB`, preserve:

```python
v1 : Unit <- IO.try(Unit, Flush.write_file(mtmp, Manifest.serialize(m2)))
cp1 : Unit <- IO.try(Unit, CrashPoint.hit("compact.manifest_synced"))
v2 : Unit <- IO.try(Unit, Fs.rename(mtmp, mpath))
v3 : Unit <- IO.try(Unit, Fs.fsync(dir))
cp2 : Unit <- IO.try(Unit, CrashPoint.hit("compact.manifest_published"))
ign : Result<&1, &1, U32 & String, Unit> <- remove_list(dels)
```

- [ ] **Step 7: Preserve trust-root comments**

Add beside the storage-order comments:

```text
CrashPoint calls are test-only host effects. Unset or unequal checkpoints are
successful no-ops. Signal delivery and surrounding filesystem ordering are
validated empirically and are not Bend proofs.
```

- [ ] **Step 8: Check names and ordering**

Run:

```bash
for point in wal.appended wal.synced \
  flush.table_synced flush.table_published \
  flush.manifest_synced flush.manifest_published \
  compact.output_synced compact.output_published \
  compact.manifest_synced compact.manifest_published
do
  count=$(grep -R -F "\"$point\"" src/Db.bend src/Flush.bend src/Compact.bend | wc -l | tr -d '[:space:]')
  test "$count" = 1 || exit 1
done
git --no-pager diff -- src/Db.bend src/Flush.bend src/Compact.bend
```

Expected: every name occurs exactly once; the diff adds checkpoints without removing or reordering storage operations.

- [ ] **Step 9: Run targeted checks in parallel**

Run:

```bash
mkdir -p .mylsm/build/crash-targeted-proofs
bend proofs/DbProof.bend >.mylsm/build/crash-targeted-proofs/DbProof.log 2>&1 & p1=$!
bend proofs/FlushProof.bend >.mylsm/build/crash-targeted-proofs/FlushProof.log 2>&1 & p2=$!
bend proofs/CompactProof.bend >.mylsm/build/crash-targeted-proofs/CompactProof.log 2>&1 & p3=$!
wait "$p1" && wait "$p2" && wait "$p3"
bench/crash_point_smoke.sh
```

Expected: all targeted proofs and the smoke gate pass.

- [ ] **Step 10: Run the proof gate and conditionally commit**

Run `./proofs/run.sh`. Only after a genuinely green result:

```bash
git add src/Db.bend src/Flush.bend src/Compact.bend
git commit -m "test: instrument durability crash boundaries"
```

---

### Task 3: Build Deterministic Crash Fixtures and Recovery Oracles

**Files:**

- Create: `bench/crash_worker.bend`

**Interfaces:**

- Consumes:
  - `Recover.open_db(dir)`
  - `Db.db_write(db, batch)`
  - `Flush.flush(db)`
  - `Compact.compact(db)`
  - `Db.db_get(db, key)`
- Environment:
  - `MYLSM_CRASH_MODE=prepare|run|verify`
  - `MYLSM_CRASH_CASE=wal|flush|compact`
  - `MYLSM_CRASH_DIR=<non-empty-path>`
  - `MYLSM_EXPECT_TRIGGER=optional|required|absent`
  - `MYLSM_EXPECT_L0=<Nat>`
  - `MYLSM_EXPECT_L1=<Nat>`
- Produces exact verification markers for `reopen=1`, `reopen=2`, and `reopen_stability=pass`.

**Fixtures:**

| Case | Preparation | Crash operation | Acknowledged state |
|---|---|---|---|
| WAL | One three-key `Db.db_write` batch | Write `wal-trigger=wal-trigger-value` | Three baseline keys; trigger optional at `wal.appended`, required at `wal.synced` |
| Flush | One four-key `Db.db_write` batch, without maintenance | Reopen and call `Flush.flush` | All four keys acknowledged before reorganization |
| Compaction | Five cycles of three-key `Db.db_write` plus `Flush.flush` | Reopen and call `Compact.compact` | Fifteen keys in five acknowledged L0 tables |

- [ ] **Step 1: Verify the worker check initially fails**

Run:

```bash
bend bench/crash_worker.bend
```

Expected: non-zero because the file does not exist.

- [ ] **Step 2: Define deterministic key generation**

Create `bench/crash_worker.bend` with imports for `Console`, `Compact`, `Db`, `Flush`, `Recover`, `Sstable`, and `Wal`, then define:

```python
def fixture_key(+family: String, +batch: Nat, +index: Nat) -> String:
  family ++ "-" ++ Nat.show(batch) ++ "-" ++ Nat.show(index)

def fixture_value(+family: String, +batch: Nat, +index: Nat) -> String:
  "value-" ++ family ++ "-" ++ Nat.show(batch) ++ "-" ++ Nat.show(index)

def fixture_puts(fuel: Nat, +family: String, +batch: Nat, +index: Nat) -> List<&2, Wal.Mut>:
  match fuel:
    case 0n:
      Nil{}
    case 1n+rest:
      Con{Wal.Put{fixture_key(family, batch, index), fixture_value(family, batch, index)}, fixture_puts(rest, family, batch, Nat.add(index, 1n))}
```

- [ ] **Step 3: Implement preparation modes**

Use these exact operations:

```python
# wal: Db.db_write(batch of fixture_puts(3n, "wal-base", 0n, 0n))
# flush: Db.db_write(batch of fixture_puts(4n, "flush", 0n, 0n)); do not flush
# compact: repeat five times:
#   Db.db_write(batch of fixture_puts(3n, "compact", batch_index, 0n))
#   Flush.flush(returned_db)
```

Print only after the operation returns:

```text
worker_mode=prepare case=wal status=complete acknowledged_keys=3
worker_mode=prepare case=flush status=complete acknowledged_keys=4
worker_mode=prepare case=compact status=complete acknowledged_keys=15
```

- [ ] **Step 4: Implement crash-operation modes**

Each mode first calls `Recover.open_db`, prints `status=armed`, then performs exactly one operation:

```python
# wal: Db.db_write with Wal.Put{"wal-trigger", "wal-trigger-value"}
# flush: Flush.flush(db)
# compact: Compact.compact(db)
```

A normal return prints:

```text
worker_mode=run case=<case> status=complete
```

The shell matrix must reject a crash log containing this marker.

- [ ] **Step 5: Implement complete key verification**

Define structural checks that validate every generated key and its exact value. For WAL:

```python
def trigger_ok(+policy: String, +db: Db.Db) -> Bool:
  # required: exact value must exist
  # optional: missing or exact value is accepted
  # absent: key must be missing
```

Reject unknown policy strings through `IO.die` rather than treating them as optional.

- [ ] **Step 6: Implement exact level-shape checks**

Read L0/L1 lengths from `Db.Db.levels`, following the accessor pattern in `bench/million_writes.bend`. Compare them to parsed `MYLSM_EXPECT_L0` and `MYLSM_EXPECT_L1`; malformed numeric values terminate non-zero before opening the database.

- [ ] **Step 7: Verify recovery twice**

For `MYLSM_CRASH_MODE=verify`:

```python
first : Db.Db <- IO.try(Db.Db, Recover.open_db(dir))
# validate all keys, trigger policy, L0, and L1
second : Db.Db <- IO.try(Db.Db, Recover.open_db(dir))
# repeat the same validation independently
```

Print only after each complete validation:

```text
worker_mode=verify case=<case> reopen=1 keys=pass level_shape=pass referenced_data=pass
worker_mode=verify case=<case> reopen=2 keys=pass level_shape=pass referenced_data=pass
worker_mode=verify case=<case> status=complete reopen_stability=pass
```

`referenced_data=pass` means `Recover.open_db` loaded and parsed all Manifest-listed files; missing or corrupt references must terminate before the marker.

- [ ] **Step 8: Implement strict dispatch**

Reject empty `MYLSM_CRASH_DIR`, unknown modes, unknown cases, unknown trigger policies, and malformed expected levels through `IO.die` with exit code `2`. Do not provide a default database directory.

- [ ] **Step 9: Validate all normal paths**

Run:

```bash
bend bench/crash_worker.bend --check-only
bend bench/crash_worker.bend -o .mylsm/build/crash-worker
```

Then run prepare → run with `MYLSM_CRASH_POINT=unmatched` → verify for each case. Expected normal shapes:

```text
wal:     L0=0 L1=0 trigger=required
flush:   L0=1 L1=0 trigger=absent
compact: L0=0 L1=1 trigger=absent
```

Every case must print both reopen markers and `reopen_stability=pass`.

- [ ] **Step 10: Run the proof gate and conditionally commit**

Run `./proofs/run.sh`. Only after a green result:

```bash
git add bench/crash_worker.bend
git commit -m "test: add deterministic crash recovery worker"
```

---

### Task 4: Replace the Scaffold with a Safe External Crash Matrix

**Files:**

- Replace: `bench/fault_inject.sh`

**Interfaces:**

- Command: `bench/fault_inject.sh [--self-test|--validate-only] [output-root]`.
- Environment:
  - `MYLSM_CRASH_REPETITIONS`, default `3`
  - `MYLSM_CRASH_STOP_TIMEOUT`, default `10`
  - `MYLSM_CRASH_RESET=1`, the only authorization to delete an existing safe output root
  - `MYLSM_THREADS`, integer `1..256`
- Final marker: `matrix_status=pass checkpoints=10 repetitions=<n> cases=<10*n> platform=<Darwin|Linux>`.

**Recovery expectations:**

| Checkpoint | Case | Trigger | L0 | L1 |
|---|---|---|---:|---:|
| `wal.appended` | wal | optional | 0 | 0 |
| `wal.synced` | wal | required | 0 | 0 |
| `flush.table_synced` | flush | absent | 0 | 0 |
| `flush.table_published` | flush | absent | 0 | 0 |
| `flush.manifest_synced` | flush | absent | 0 | 0 |
| `flush.manifest_published` | flush | absent | 1 | 0 |
| `compact.output_synced` | compact | absent | 5 | 0 |
| `compact.output_published` | compact | absent | 5 | 0 |
| `compact.manifest_synced` | compact | absent | 5 | 0 |
| `compact.manifest_published` | compact | absent | 0 | 1 |

- [ ] **Step 1: Demonstrate that the current scaffold fails acceptance**

Run:

```bash
bench/fault_inject.sh >.mylsm-fault-placeholder.log 2>&1
! grep -q '^matrix_status=pass ' .mylsm-fault-placeholder.log
```

Expected: the existing script exits without the required matrix marker.

- [ ] **Step 2: Add strict startup validation**

Replace the script with Bash strict mode. Require Darwin/Linux, `bend`, `ps`, `grep`, `awk`, `sed`, and `tr`. Validate repetition, timeout, and thread values as positive integers; threads must be `1..256`.

- [ ] **Step 3: Add destructive-path safety**

Canonicalize the output parent and reject:

```text
empty path
/
repository root
$HOME
basename . or ..
any basename not starting with `.mylsm-crash-`
any path whose parent does not already exist
any path that is not a direct child of the repository root
symlink output root
existing output without the exact harness ownership sentinel
existing owned output without MYLSM_CRASH_RESET=1
```

Perform validation before any `rm -rf`. The `--self-test` mode must exercise every rejection and print:

```text
self_test_status=pass unsafe_paths=pass unsupported_platform=pass reset_guard=pass
```

- [ ] **Step 4: Build the native worker exactly once**

For a real matrix run:

```bash
mkdir -p -- "$OUTPUT_ROOT" "$ROOT/.mylsm/build"
bend "$ROOT/bench/crash_worker.bend" -o "$ROOT/.mylsm/build/crash-worker"
test -x "$ROOT/.mylsm/build/crash-worker"
```

No case may rebuild the worker.

- [ ] **Step 5: Observe stopped state deterministically**

Implement:

```bash
wait_for_stop() {
  local pid=$1 deadline=$((SECONDS + STOP_TIMEOUT)) state
  while (( SECONDS < deadline )); do
    state=$(ps -o stat= -p "$pid" 2>/dev/null | tr -d '[:space:]' || true)
    case "$state" in T*) return 0 ;; esac
    kill -0 "$pid" 2>/dev/null || return 1
    sleep 0.05
  done
  return 124
}
```

A child exit, build failure, or running process is not a detected checkpoint.

- [ ] **Step 6: Implement one crash case**

For each checkpoint/repetition:

1. Create a dedicated case directory and logs.
2. Run worker `prepare` without `MYLSM_CRASH_POINT`.
3. Require its exact acknowledged-key marker.
4. Start worker `run` with the selected checkpoint.
5. Require stopped state `T*`, the exact `crash_point_reached=<checkpoint>` marker, and `status=armed`.
6. Require absence of `status=complete`.
7. Send `kill -9` from Bash.
8. `wait` and require status `137`.
9. Run worker `verify` with the table above.
10. Require both reopen markers and `reopen_stability=pass`.
11. Delete only the successful case database; retain logs.
12. Print:

```text
case=<checkpoint> repetition=<n> stopped=pass kill_status=137 recovery=pass reopen_stability=pass level_shape=pass
```

- [ ] **Step 7: Preserve diagnostics on every failure**

Install an exit trap that kills a live child but does not remove its case directory. Print:

```text
matrix_status=fail artifacts=<case-directory>
```

Never run broad cleanup against a path that has not passed the safety validator.

- [ ] **Step 8: Run all ten checkpoints**

Use an explicit Bash array in the order listed above. For each checkpoint, execute repetitions `1..MYLSM_CRASH_REPETITIONS`. Verify the final case count equals `10 * repetitions` before printing the pass marker.

- [ ] **Step 9: Validate shell behavior**

Run:

```bash
chmod +x bench/fault_inject.sh
bash -n bench/fault_inject.sh
bench/fault_inject.sh --self-test
bench/fault_inject.sh --validate-only "$PWD/.mylsm-crash-validation"
```

Expected: syntax passes, self-tests pass, and validation reports the canonical safe root without creating or deleting the matrix directory.

- [ ] **Step 10: Run one complete short matrix**

Run:

```bash
MYLSM_CRASH_REPETITIONS=1 MYLSM_CRASH_RESET=1 \
  bench/fault_inject.sh "$PWD/.mylsm-crash-injection-short"
```

Expected:

```text
matrix_status=pass checkpoints=10 repetitions=1 cases=10 platform=<Darwin|Linux>
```

- [ ] **Step 11: Run the default acceptance matrix**

Run:

```bash
MYLSM_CRASH_RESET=1 \
  bench/fault_inject.sh "$PWD/.mylsm-crash-injection"
```

Expected:

```text
matrix_status=pass checkpoints=10 repetitions=3 cases=30 platform=<Darwin|Linux>
```

- [ ] **Step 12: Run the proof gate and conditionally commit**

Run `./proofs/run.sh`. Only after a green result:

```bash
git add bench/fault_inject.sh
git commit -m "test: verify recovery with external kill injection"
```

---

### Task 5: Measure Unset Checkpoint Overhead

**Files:**

- Create: `bench/crash_point_overhead.sh`
- Modify: `bench/BASELINE.md`

**Interfaces:**

- Command: `bench/crash_point_overhead.sh before|after|compare [output-root]`.
- Runs three 4,096-write measurements per phase with `MYLSM_CRASH_POINT` unset.
- Uses median Bend-reported `elapsed_ms`.
- Pass criterion: post-instrumentation throughput is at least `0.90` of pre-instrumentation throughput.

- [ ] **Step 1: Write the measurement harness before instrumentation is merged**

The harness must:

- apply the same safe output-root rules as the crash matrix;
- store three raw logs and `elapsed-ms.txt` per phase;
- invoke `bench/million_writes.sh 4096 <unique-data-dir>`;
- parse exactly one final `elapsed_ms=<integer>` per run;
- compute the median as the second sorted value;
- refuse `after` without existing `before` data;
- refuse overwriting a phase directory;
- print measured values rather than embedding expected numbers.

- [ ] **Step 2: Capture the pre-instrumentation phase**

From the commit immediately before Task 2 instrumentation, run:

```bash
MYLSM_CRASH_OVERHEAD_RESET=1 \
  bench/crash_point_overhead.sh before "$PWD/.mylsm-crash-point-overhead"
```

Expected: three run markers and `overhead_phase=before median_elapsed_ms=<integer>`.

If instrumentation already exists, use a clean worktree at the pre-instrumentation commit; never fabricate the baseline.

- [ ] **Step 3: Capture the post-instrumentation phase**

Run from the instrumented tree:

```bash
unset MYLSM_CRASH_POINT
bench/crash_point_overhead.sh after "$PWD/.mylsm-crash-point-overhead"
```

Expected: three run markers and `overhead_phase=after median_elapsed_ms=<integer>`.

- [ ] **Step 4: Enforce the existing performance floor**

Run:

```bash
bench/crash_point_overhead.sh compare "$PWD/.mylsm-crash-point-overhead"
```

Expected pass marker:

```text
crash_point_overhead before_median_ms=<n> after_median_ms=<n> throughput_ratio=<ratio> baseline_floor=0.90 status=pass
```

If it fails, stop and redesign checkpoint dispatch before publication.

- [ ] **Step 5: Record only observed evidence**

Add a `CrashPoint unset-overhead observation` section to `bench/BASELINE.md` containing the exact Bend version, OS, architecture, six measurements, medians, ratio, and command. State explicitly that it is a local observation, not a portable zero-cost claim.

- [ ] **Step 6: Run the proof gate and conditionally commit**

Run `./proofs/run.sh`. Only after a green result:

```bash
git add bench/crash_point_overhead.sh bench/BASELINE.md
git commit -m "bench: measure unset crash checkpoint overhead"
```

---

### Task 6: Publish Crash-Matrix Acceptance

**Files:**

- Modify: `README.md`

**Interfaces:**

- Consumes: `.mylsm-crash-injection/matrix.log` with ten checkpoints, three repetitions, and thirty passing cases.
- Produces: documented command, platform scope, empirical limitation, and exactly two completed Phase 2 bullets.

- [ ] **Step 1: Gate documentation on real acceptance evidence**

Run:

```bash
grep -q '^matrix_status=pass checkpoints=10 repetitions=3 cases=30 platform=\(Darwin\|Linux\)$' \
  .mylsm-crash-injection/matrix.log
```

Then require three exact pass lines for every checkpoint. Do not edit the roadmap if any case is missing.

- [ ] **Step 2: Document the operator command**

Add before the roadmap:

```markdown
## Crash recovery testing

On Darwin and Linux:

```sh
MYLSM_CRASH_RESET=1 bench/fault_inject.sh .mylsm-crash-injection
```

The default executes ten deterministic WAL, flush, compaction, and Manifest
publication checkpoints three times. The worker enters `SIGSTOP`; the external
Bash harness verifies the stopped state, sends `kill -9`, requires status 137,
and reopens the database twice to validate acknowledged keys and level shape.

This is empirical evidence for the audited host effects, OS, filesystem, and
hardware used by the run. It is not a Bend proof of signals, `fsync`, rename,
process death, or storage durability. A proof timeout remains a failed result.
```

- [ ] **Step 3: Update only the covered roadmap bullets**

Mark complete:

```markdown
- [x] Replace the current fault-injection scaffold with real `kill -9` phases.
- [x] Test crashes during WAL append, flush, compaction, and Manifest publish.
```

Keep unchecked:

```markdown
- [ ] Run 1M+ mutated inputs through WAL, Manifest, and SSTable parsers.
- [ ] Test truncated files, invalid checksums, missing tables, and hostile names.
```

- [ ] **Step 4: Run the proof gate and conditionally commit**

Run `./proofs/run.sh`. Only after a green result:

```bash
git add README.md
git commit -m "docs: record crash recovery matrix acceptance"
```

---

### Task 7: Full Validation and Handoff

**Files:**

- Review all files listed in the File Structure section.
- Modify only defects found in this plan’s change set.

**Interfaces:**

- Consumes: all previous task outputs.
- Produces: final validation evidence without expanding scope.

- [ ] **Step 1: Run targeted Bend and shell checks**

Run independent checks in parallel where possible:

```bash
bend bench/crash_point_smoke.bend --check-only
bend bench/crash_worker.bend --check-only
bash -n bench/crash_point_smoke.sh bench/crash_point_overhead.sh bench/fault_inject.sh
```

Expected: every command exits zero with the crash point unset.

- [ ] **Step 2: Run the host-effect smoke**

Run:

```bash
bench/crash_point_smoke.sh
```

Expected final marker:

```text
crash_point_smoke=pass unset=pass mismatch=pass js_matching_stop=pass native_matching_stop=pass kill_status=137
```

- [ ] **Step 3: Run short and default matrices**

Run:

```bash
MYLSM_CRASH_REPETITIONS=1 MYLSM_CRASH_RESET=1 \
  bench/fault_inject.sh "$PWD/.mylsm-crash-injection-final-short"
MYLSM_CRASH_RESET=1 \
  bench/fault_inject.sh "$PWD/.mylsm-crash-injection-final"
```

Expected: `10` and `30` passing cases respectively.

- [ ] **Step 4: Recheck the overhead gate**

Run:

```bash
bench/crash_point_overhead.sh compare "$PWD/.mylsm-crash-point-overhead"
```

Expected: marker ending in `baseline_floor=0.90 status=pass`.

- [ ] **Step 5: Run the complete proof gate**

Run:

```bash
./proofs/run.sh
```

Expected:

```text
SUMMARY PASS=<total> FAIL=0 TIMEOUT=0 TOTAL=<total>
```

Any timeout or failure leaves validation red and blocks commits.

- [ ] **Step 6: Run the existing CLI smoke**

Run after the proof gate is green because this script invokes the proof command:

```bash
bench/cli_smoke.sh
```

Expected: exit zero with existing demo, environment, REPL, persistence, import/export, scan, and maintenance checks passing.

- [ ] **Step 7: Verify safety and scope mechanically**

Run:

```bash
if grep -R -n '@unsafe' src bench laws proofs; then exit 1; fi
git --no-pager diff --check
git --no-pager diff --name-only
```

Expected: no `@unsafe`, no whitespace errors, and no unrelated files.

- [ ] **Step 8: Verify checkpoint-name consistency**

For every one of the ten names, require occurrences in the relevant storage module, `bench/fault_inject.sh`, and the design spec. Expected final marker:

```text
checkpoint_name_consistency=pass
```

- [ ] **Step 9: Report validation honestly**

The final report must list:

```text
crash smoke result
short matrix result
default matrix result
overhead comparison result
proof summary and log paths
CLI smoke result, if reached
supported OS and Bend version
```

If proofs time out, report that the empirical matrix may be green while the repository proof gate remains red. Do not merge those claims.

## Self-Review

- [x] The plan is limited to one subsystem: real crash injection and recovery verification.
- [x] Each checkpoint identifies the completed operation and the next operation that has not started.
- [x] The external controller, not the Bend effect, sends `kill -9`.
- [x] WAL, flush, and compaction fixtures distinguish acknowledged state from an optional pre-sync write.
- [x] Every recovery oracle checks all deterministic keys, not samples.
- [x] Recovery runs twice and validates expected level shape.
- [x] Unsafe deletion targets and false stopped-process detection are covered.
- [x] Host effects and filesystem behavior are described as empirical, not formally proved.
- [x] Parser hardening remains out of scope and unchecked.
- [x] Every commit remains blocked by a proof failure or timeout.

## Execution Handoff

Plan execution options:

1. **Subagent-Driven (recommended):** use `superpowers:subagent-driven-development`, dispatch one fresh subagent per task, and review specification compliance and code quality between tasks.
2. **Inline Execution:** use `superpowers:executing-plans`, execute tasks in bounded batches, and stop at each validation checkpoint for review.

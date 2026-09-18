# MyLSM CLI, Demo Application, and Adaptive Runtime — Product Spec

**Date:** 2026-09-18  
**Status:** Draft, pending human review  
**Related:** `docs/superpowers/specs/2026-09-17-lsm-bend-design.md`

## 1. Mission

Provide a small, usable entry point for MyLSM and a demonstrable application while
preserving the existing durable LSM core. The new surface must make it easy to:

- run a self-contained demonstration;
- execute the proof, fuzz, and benchmark checks;
- build and run the native Bend executable;
- select CPU or GPU execution conservatively based on host capabilities;
- explain the selected execution mode instead of silently making an unsafe claim.

This is a developer/demo interface, not a promise that the current storage engine
is production-ready. The CLI must expose that distinction in its output.

## 2. Scope and non-goals

### In scope

1. A POSIX CLI launcher at `bin/mylsm`.
2. A Bend mini application at `app/mylsm_demo.bend`.
3. Native build/run support with configurable CPU thread count and optional GPU.
4. A resource policy that detects host capabilities outside Bend and passes only
   supported runtime flags.
5. Documentation and smoke tests for the new surface.

### Out of scope

- A new network protocol or server mode.
- Replacing `Recover.open_db` or redesigning the storage API.
- Claiming that GPU acceleration improves WAL/file IO; GPU use is limited to
  suitable pure compute work.
- Automatic installation of Bend, clang, Metal, CUDA, or system packages.
- Treating hardware detection as a formal proof. It is host policy code and must
  fail closed to CPU mode.

## 3. User experience

From the repository root:

```text
bin/mylsm demo [--dir PATH]
bin/mylsm check
bin/mylsm fuzz
bin/mylsm bench
bin/mylsm build [--cpu|--gpu] [--threads N]
bin/mylsm run [--cpu|--gpu] [--threads N] [--dir PATH]
bin/mylsm doctor
```

The default command is `demo` when no subcommand is supplied. Every command
prints the selected mode, Bend version, CPU thread count, and GPU decision when
those values are available. `doctor` must return non-zero only for a missing
required tool, and must report optional GPU/compiler limitations separately.

Example status output:

```text
MyLSM runtime
  Bend: 2.0.5
  CPU threads: 8
  GPU: available (Metal)
  mode: gpu for pure compute, CPU for storage IO
```

If no GPU is detected, the CLI must say:

```text
GPU: unavailable or unverified; using CPU fallback
```

## 4. Mini application behavior

`app/mylsm_demo.bend` must:

1. Open a directory through `Recover.open_db`.
2. Write at least two keys through the durable `Db.db_put` path.
3. Read and print both values.
4. Delete one key through `Db.db_del` and print the resulting miss.
5. Run a small pure, uniform computation using a Bend GPU-designated call
   (`worker!(...)`) when the native runtime supports it. The same program must
   remain correct on CPU-only machines because Bend falls back to CPU execution.
6. Print a clear completion marker and the data directory used.

The demo must not mutate a user-supplied directory unless explicitly provided by
`--dir`; its default directory is `.mylsm-demo-data`, which the CLI may remove
only when the user asks for a clean demo.

## 5. Adaptive execution policy

### 5.1 Detection

The shell launcher detects:

- logical CPU count (`sysctl -n hw.logicalcpu` on macOS, `nproc` on Linux);
- operating system and architecture (`uname`);
- likely GPU backend:
  - macOS: `system_profiler SPDisplaysDataType` and Metal tool availability;
  - Linux: `nvidia-smi`/CUDA availability;
  - unknown systems: no GPU claim.

Detection is advisory. A failed probe always selects CPU mode rather than failing
or pretending that a GPU exists.

### 5.2 Selection precedence

1. `MYLSM_DEVICE=cpu|gpu|auto` if supplied.
2. CLI `--cpu` or `--gpu`.
3. `auto` policy.

An explicit `--gpu` with no usable GPU must fail with an actionable message; auto
mode must silently fall back to CPU with a visible explanation.

### 5.3 CPU policy

- Default threads: detected logical CPUs, capped at 64.
- `MYLSM_THREADS` or `--threads N` overrides the default after validating
  `1 <= N <= 256`.
- Native execution receives `--threads N`.

### 5.4 GPU policy

- GPU execution is enabled only for native builds and only after a positive probe.
- Default memory budget is 4 GB; override with `MYLSM_GPU_MEMORY`.
- Native execution receives `--gpu <memory>` and requires the generated `.gpu`
  artifact to remain beside the binary.
- Storage IO remains on the CPU; only pure compute marked with `!` is GPU-eligible.

## 6. Safety and correctness requirements

- The launcher must use `exec` so signals and exit codes reach Bend directly.
- Paths must be passed as quoted arguments; no user input may be interpolated into
  shell code.
- No automatic `sudo`, package installation, network access, or telemetry.
- GPU detection must never affect WAL ordering, fsync, recovery, or on-disk format.
- If native compilation fails because clang/Metal/CUDA is unavailable, the CLI
  must report the failed capability and offer the portable `bend file.bend` path.
- Existing `bend PROOF.bend` remains the mandatory proof gate.

## 7. Verification gates

The feature is complete when:

1. `bin/mylsm doctor` reports capabilities without modifying the repository.
2. `bin/mylsm check` runs `bend PROOF.bend` successfully.
3. `bin/mylsm demo --cpu` completes and prints the expected read/delete results.
4. `bin/mylsm demo` selects GPU only when detection and native compilation succeed.
5. A CPU-only host completes the demo without GPU-specific errors.
6. The CLI shell passes `shellcheck` when available, or an equivalent `sh -n`
   syntax check when it is not.
7. No existing proof or recovery law regresses.

The output must explicitly label the demo as an experimental/developer demo until
benchmark and crash-recovery gates are complete.

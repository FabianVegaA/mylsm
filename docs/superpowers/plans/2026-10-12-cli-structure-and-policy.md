# CLI Structure and Policy Implementation Plan

> **For agentic workers:** Use `superpowers:executing-plans` to implement this plan task by task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the CLI's location and generated artifacts unambiguous while moving its decisions from shell to Bend without changing its documented commands or runtime behavior.

**Architecture:** `scripts/mylsm.sh` only resolves the repository root and starts `app/cli/main.bend` with the original arguments. Pure Bend modules parse commands, validate configuration, select a runtime, and decide whether to restart. One CLI-local process effect executes and waits for host commands; it reports facts and exit statuses but makes no policy decisions. The demo, REPL, and owner programs live in separate directories. Only CLI-generated executables move to `.mylsm/bin/`; logs go outside that directory.

**Tech Stack:** The latest Bend release recorded in `tools/toolchain.json`, POSIX shell bootstrap, paired C/JavaScript effect implementations, Bend laws and witnesses, existing smoke scripts.

**Spec:** None; the user requested a direct plan. The behavioral baseline is `docs/CLI.md`, `app/README.md`, and the current `bin/mylsm`.

## Global constraints

- Follow `AGENT.md:14`: Bash/C/JS perform only irreducible host operations. Parsing, defaults, validation, runtime selection, fallback, and restart policy belong in Bend.
- Follow `AGENT.md:18`: keep decisions pure and effects isolated; do not duplicate capability probes, copy process output without a bound, or add parallel execution without measured benefit.
- Preserve `demo` as the no-argument default and preserve `repl`, `doctor`, `check`, `fuzz`, `bench`, `build`, `run`, `--help`, documented environment variables, exit behavior, CPU fallback, GPU failure behavior, and bounded REPL restarts.
- Use `.mylsm/bin/` for the CLI's generated native executables and `.mylsm/log/` for build logs. Do not move unrelated benchmark artifacts as part of this change.
- No new `app/cli/effs/` directory. Reuse Bend Base `Process.run` for bounded probes; keep the paired C/JS operation for attached child execution adjacent to `app/cli/Attached.bend`.
- Add no source comments or docstrings without asking the user first; add no ticket identifiers to source files. Leave existing comments alone except for mechanically necessary path changes.
- Before editing Bend, run `bend update` and `bend guide`. If the installed release changes, update `tools/toolchain.json` and rerun the repository's proof, Bolt, width, and relevant runtime gates before starting the CLI migration.

## Review focus

- Invalid arguments or environment values must fail before starting or changing a database; pin empty directory, malformed thread count, unsupported device, and unknown command cases in Task 1.
- Native compilation failure must still fall back for `cpu` and `auto`, while `gpu` must fail; pin this decision in Task 1 and its executed path in Task 3.
- A detected GPU without a generated `.gpu` artifact must not be reported as active; pin this in Tasks 1 and 3.
- A REPL exit code of 75 without a valid, different thread count in its sidecar must fail rather than loop; pin the policy and the supervised run in Tasks 1 and 3.
- Paths containing spaces and process output larger than the capture limit must remain safe and bounded; pin the host boundary in Task 2.

---

### Task 1: Express CLI decisions in pure Bend

**Files:** Create `app/cli/Types.bend`, `app/cli/Policy.bend`, `laws/Cli.bend`, `proofs/CliProof.bend`. Do not modify the launcher yet.

**Interfaces:** `Types.Command` covers all documented top-level commands, with a directory on `Repl`. `Types.Device` is `Auto`, `Cpu`, or `Gpu`; `Types.Backend` is portable CPU, native CPU, or native GPU. `Policy.parse_args(args: List<String>) -> Result<&1, &1, String, Types.Command>`, `Policy.parse_device(value: String) -> Result<&1, &1, String, Types.Device>`, `Policy.parse_threads(value: String, detected: Nat) -> Result<&1, &1, String, Nat>`, `Policy.select_backend(device: Types.Device, native_built: Bool, gpu_detected: Bool, gpu_artifact: Bool) -> Result<&1, &1, String, Types.Backend>`, and `Policy.restart_threads(status: U32, sidecar: Maybe<&2, String>, current: Nat, remaining: Nat) -> Result<&1, &1, String, Maybe<&2, Nat>>`. Keep errors as explicit values; IO and OS probes are absent from these modules.

- [x] Record closed laws and witnesses for every command shape, environment boundary (`1`, `256`, `0`, `257`, malformed), CPU/auto fallback, explicit GPU failure, absent GPU artifact, and restart status/sidecar cases. Add quantified laws over open inputs where Bend can prove the decision without assuming host facts; label closed fixtures as such in the plan or test names, not as universal proofs.
- [ ] Run `bend proofs/CliProof.bend --verdict`; verify the new laws fail or are unavailable before implementing the policy.
- [x] Implement the types and pure functions with one parse of each input and one runtime decision per launch. Avoid building intermediate lists of output strings or repeating probes.
- [x] Run `bend proofs/CliProof.bend --verdict`; expect a clean proof result.
- [x] Commit the pure layer separately.

### Task 2: Add the minimum process boundary needed by the existing CLI

**Files:** Create `app/cli/Attached.bend`, `app/cli/attached_run.c`, `app/cli/attached_run.js`, and a focused host fixture under `bench/smoke/`. Reuse Bend Base `Process.run` for bounded probes, `IO.args()`, and the existing environment/file effects rather than adding wrappers for them.

**Interface:** Bend Base `Process.run(program, args, input, max_output, timeout_ms)` provides bounded capture for short host probes. `Attached.run(program, args, env, log_path)` inherits stdin/stdout/stderr and waits for the child; an optional log path redirects both output streams to a file. Bend decides which executable and arguments to use and what an exit status means. Do not run through a shell or treat command text as code.

- [x] Add a fixture for argument boundaries including an argument containing spaces, stdin inheritance, a nonzero exit status, and a missing executable. Exercise log redirection and use Base `Process.run` to verify oversized probe output is rejected. Test both native and JavaScript hosts where supported by the existing smoke environment.
- [ ] Run the fixture and confirm it fails before the effect exists.
- [x] Implement the paired attached-child effect. Redirect logs directly to a file and inherit interactive streams without buffering them in Bend. Base `Process.run` rejects probe output beyond its declared byte limit. Keep platform branching limited to C/JS process operations, with no CLI runtime policy there.
- [x] Run the focused fixture in portable and native hosts. Review the C/JS files against `AGENT.md:14`: no defaults, device interpretation, fallback, argument validation, or exit-code policy.
- [x] Commit the host boundary separately.

### Task 3: Replace the policy-bearing shell launcher

**Files:** Create `app/cli/main.bend` and `scripts/mylsm.sh`; modify `bench/smoke/cli.sh` to exercise the new entry point. Keep the existing `bin/mylsm` until Task 4 so old callers still work while this task is reviewed.

**Interfaces:** `main` obtains `IO.args()` and raw environment values once; `Policy` returns typed choices; `Process.run` supplies host facts and runs child programs. Probe `bend version`, OS/architecture, logical CPU count, compiler availability, and GPU availability through explicit argument vectors. Interpret probe results in Bend. Keep the existing maximum of eight REPL launches and the existing status codes for invalid input, unavailable GPU, and invalid restart.

- [ ] Extend the CLI smoke fixture to compare the old and new entry points for help, doctor fields, no-argument demo, REPL persistence, `check`, `fuzz`, `bench`, `build`, `run`, CPU/auto fallback, explicit GPU rejection when unavailable, and restart errors. Use controlled fake host programs only for cases that cannot be exercised deterministically on the current machine.
- [ ] Run those new checks against the absent new entry point and confirm failure.
- [x] Implement `scripts/mylsm.sh` as root resolution plus `exec bend "$ROOT/app/cli/main.bend" -- "$@"`. Implement orchestration in Bend. Preserve the documented environment contract passed to demo and REPL. Put generated demo/REPL executables in `.mylsm/bin/` and their build logs in `.mylsm/log/`.
- [x] Run `bench/smoke/cli.sh` and the focused host fixture. Exercise help, doctor, check, fuzz, bench, build, run, CPU/auto demo, REPL persistence, thread restart, and recovery on the new entry point.
- [x] Commit the new entry point separately.

### Task 4: Group applications and switch all live references

**Files:** Move `app/mylsm_demo.bend` and `app/demo_helpers.bend` to `app/demo/`; move `app/repl.bend`, `app/repl_types.bend`, `app/repl_lexer.bend`, `app/repl_parser.bend`, `app/repl_policy.bend`, `app/repl_exec.bend`, and `app/interchange.bend` to `app/repl/`; move `app/mylsm_owner.bend` to `app/owner/`. Update their relative imports and references in `app/cli/main.bend`, `laws/Demo.bend`, `laws/Repl.bend`, owner smoke scripts, `README.md`, `app/README.md`, `docs/CLI.md`, `bench/README.md`, and `bench/smoke/cli.sh`. Remove `bin/mylsm` after live references are updated. Keep historical results and old plans as records.

- [x] Search all live references to old source and entry paths with `rg`; adjust `AGENT.md`'s width check to include nested `app/**/*.bend` files using portable enumeration.
- [x] Move files without splitting the existing parser or executor. Update imports and live scripts/docs. Preserve the owner executable as a separate application.
- [x] Run `DemoProof --verdict`, the normal `ReplProof`, both owner smoke scripts, and the full CLI smoke. Confirm no live reference uses `bin/mylsm`, the former flat `app/` paths, or `.mylsm/build/mylsm-{demo,repl}`. `ReplProof --verdict` remains blocked by a Bend TypeScript/kernel mismatch.
- [x] Commit the path migration separately.

### Task 5: Complete repository verification and documentation

**Files:** Update only any remaining current documentation or test entry paths revealed by verification; do not rewrite historical acceptance records. Update `.gitignore` only if `.mylsm/bin/` or `.mylsm/log/` is not already covered.

- [x] Run `./proofs/run.sh`; require `FAIL=0` and `TIMEOUT=0` across the complete suite.
- [x] Run the existing Bolt gate from `AGENT.md` and the revised 200-character width check; require no findings. Run `git diff --check` and `sh -n scripts/mylsm.sh`.
- [x] Run the CLI and owner smoke checks after the final behavior changes. Review the changes for comments, ticket identifiers, unnecessary copying, extra host policy, and accidental changes outside the CLI migration.
- [x] Commit the final documentation/check record. Report the exact verification results and platform behavior that could not be exercised locally.

## Execution note

The user reviewed the plan before implementation and requested a branch in the current checkout rather than a worktree. The new entry point passed the CLI smoke test before the old launcher was removed. Base `Process.run` supplies bounded process probes and rejects oversized output, so the paired `Attached` effect is limited to inherited standard streams, child waiting, environment overrides, and optional log redirection. The owner smoke tests require permission to bind local Unix sockets outside the sandbox. `ReplProof` passes in normal mode; this Bend release reports a TypeScript/kernel mismatch under `--verdict`, while the complete repository proof suite passes. Final gates: proofs `PASS=82 FAIL=0 TIMEOUT=0`, Bolt zero findings after the documented `S002` filter, all 200-character width checks empty, `git diff --check`, shell syntax, CLI smoke, focused portable/native process fixture, both owner smokes, and `DemoProof --verdict` passed. Native builds used the system Apple Clang and macOS 26 SDK because the default Homebrew Clang/SDK pairing failed independently of this refactor.

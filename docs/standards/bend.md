# Bend development

## Structure

| Location | Responsibility |
| --- | --- |
| [mylsm.bend](../../mylsm.bend) | Facade imported by consumers |
| [src](../../src/) | Engine and internal modules |
| [laws](../../laws/) | Pure contracts grouped by domain |
| [proofs](../../proofs/) | Witnesses corresponding to the laws |
| [app](../../app/) | CLI, demo, REPL, and owner process |
| [examples](../../examples/) | Consumers of the public facade |
| [bench](../../bench/) | Integration, failures, and reproducible measurements |

Use the latest Bend release through the revision pinned in
[flake.nix](../../flake.nix) and [flake.lock](../../flake.lock), and revalidate the gates when updating.
Consult `bend guide` for syntax and conventions. Hub dependency versions and
constraints are in [tools/hub-dependencies.json](../../tools/hub-dependencies.json).

## Design

Prefer pure functions, isolated effects, and modules with a clear responsibility.
Use names that express the data or behavior; new comments require individual
user approval. Do not include ticket references in source files.

Choose structures based on access patterns: contiguous arrays for traversal, balanced trees
for ordered access, and shared structure for immutable versions. Avoid unnecessary copies
and shared mutable state; allow encapsulated local mutation when it simplifies
the implementation or reduces its cost.

Expose independent work through balanced divide and conquer, independent maps,
and associative reductions. Add parallelism when the workload and runtime justify
its cost, and verify the gain with representative measurements.

## Lint and line width

The `pre-commit` hook in [lefthook.yml](../../lefthook.yml) runs
[scripts/check-bend.sh](../../scripts/check-bend.sh) on Bend paths staged
for commit, including those in subdirectories. The script uses `bolt` from the
Nix environment on `PATH`; `BOLT_BIN` explicitly selects a different executable.

The gate rejects any nonzero Bolt exit status and any diagnostic without an exemption,
including warnings. It preserves the project's line-width exemptions: it filters `S002`
and `S003` notices whose header line does not exceed 200 characters. It separately checks
the 200-character maximum on every line of the supplied files, including comments
and literals. Filtering linter output does not hide a linter failure.

```sh
lefthook run pre-commit --all-files
bash scripts/check-bend.sh src/Keys.bend
```

The script returns zero only if all its checks pass. Fix the remaining findings.
An exact `# noqa: CODE` suppression is allowed only for a false positive and after the user
approves its explanatory comment. Do not weaken rules in `bolt.bend` to reduce the count.

The [README](../../README.md#development) describes installation, hook triggers,
and the scope of checks for partially staged files.

Formal gates are described in [formal-verification.md](formal-verification.md);
effect constraints are described in [host-effects.md](host-effects.md).

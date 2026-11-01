# Formal verification and runtime evidence

## Workflow

Establish the pure contract, express it through laws and witnesses, implement it, and check
host integration. Prioritize this sequence over organizing work around runtime tests.
Those tests cover effects, integration, and properties outside the formal boundary.

Each domain has `laws/<Domain>.bend` and `proofs/<Domain>Proof.bend`. The witness
module imports its law module as `Laws` and only the dependencies it needs.
Law and witness names must match exactly. One example is the pair
[Keys.bend](../../laws/Keys.bend) / [KeysProof.bend](../../proofs/KeysProof.bend).

Never use `@unsafe` in laws, witnesses, or code whose justification depends on them.
Preserve existing trust-root comments and explicit limitations.

## What each check establishes

| Evidence | Scope |
| --- | --- |
| Quantified theorem | Property over its open inputs within the kernel's assumptions |
| Closed fixture | Behavior of the concrete cases expressed |
| Fuzzing | Cases executed empirically using the recorded corpus and seed |
| Integration or fault injection | Behavior observed in the environment and at the exercised points |

Do not attribute proofs of Bend Base primitives, the compiler, the filesystem,
or C/JavaScript effects to the laws. Dependencies retain their own trust boundary;
closed byte vectors do not prove their implementation for all inputs.

## Commands and acceptance criteria

During development, run targeted modules:

```sh
bend proofs/KeysProof.bend
bend proofs/KeysProof.bend --verdict
```

The `pre-push` hook runs the full gate once when changed paths affect
Bend code, host effects, the runner, the toolchain, dependencies, or hook
configuration. Documentation-only changes do not trigger it.
It can also be run manually inside `nix develop`, which provides
GNU `timeout` to limit each module's execution:

```sh
./proofs/run.sh
lefthook run pre-push --all-files
```

[run.sh](../../proofs/run.sh) checks name correspondence and runs modules
with `--verdict`. It requires `FAIL=0`, `TIMEOUT=0`, and every module to count as `PASS`.
Successful typechecking without a successful verdict does not satisfy the gate.

The runner supports `MYLSM_PROOF_JOBS` (default: 4), `MYLSM_PROOF_TIMEOUT` (900 seconds
per module), and `MYLSM_PROOF_LOG_DIR` (default: `.mylsm/build/proofs`). A timeout never
counts as a passing proof. Parallelize independent checks when it is correct to do so.

## Reproducible evidence

Choose smoke tests and fault matrices according to the modified functionality; their documents
link to the corresponding fixtures. Record measurements in [bench/results](../../bench/results/)
with the command, revision, toolchain, host, workload, and samples. Preserve failures and limitations.
An earlier report does not replace running the required gates for a current change.

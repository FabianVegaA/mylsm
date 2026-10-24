# MyLSM

MyLSM is an LSM key-value database written in [Bend](https://github.com/bendlang/bend), aiming to compete with leading storage engines in performance and data safety. It stores writes durably in a log, keeps sorted tables on disk, and recovers after a restart. This checkout implements **0.6.0.0 alpha** for evaluation and development. The package import in `pack.json` still points to `0.5.0.0`; this checkout does not establish a published 0.6 release.

## Try it

Use Bend 2.0.39 and a native C compiler. From this checkout:

```sh
scripts/mylsm.sh doctor
scripts/mylsm.sh demo
scripts/mylsm.sh repl --dir ./my-data
```

The demo writes, reads, and deletes persistent keys. The REPL offers a small text interface; see the [CLI guide](docs/features/cli.md). Run `./proofs/run.sh` to check the formal laws and their witnesses.

## Use the library

Import `mylsm.bend` from this checkout. The public durable API has two views of the same database:

- `MyLSM.Bytes` accepts arbitrary byte keys and values. Keys sort by unsigned lexicographic byte order.
- `MyLSM.Utf8` accepts strings, encodes them as UTF-8, and reports invalid stored text instead of replacing bytes.

Both views support reads, writes, batches, range and prefix scans, and snapshots. Scans return cursors: read one item at a time, seek forward, and close them when finished. Snapshots keep a stable view while writes continue. Backups export a consistent view; restore verifies it before publication. A separate migration path copies a verified 0.5.0.0 database into the new format without changing the source. See the [durable API guide](docs/features/durable-api.md) for signatures, handle lifetimes, errors, and examples, and the [format guide](docs/features/storage-format.md) for ordering and compatibility.

Start with the [runnable examples](examples/README.md), ordered from a text write to a stable snapshot scan.

One process owns each database's filesystem lock. Other local processes can use the coordinated owner over a Unix socket; callers can also wait for the lock with a timeout. Writes are durable after acknowledgment, but a lost response after a dispatched write can leave its outcome unknown. Reopen and inspect before retrying such a write.

## Development

The public facade is `mylsm.bend`; the engine is in `src/`, formal laws in `laws/`,
witnesses in `proofs/`, and the CLI, demo, REPL and owner process in `app/`.
The recorded Bend version is in [tools/toolchain.json](tools/toolchain.json).

Install [Lefthook](https://lefthook.dev/) 1.10.10 or newer and activate the versioned
hooks after cloning:

```sh
brew install lefthook
lefthook install
```

Bolt must be on `PATH`, supplied through `BOLT_BIN`, or available at
`../bolt/bin/bolt.bin`. Bend must be on `PATH` for the proof gate.

`pre-commit` checks staged whitespace and runs Bolt plus the 200-character line limit
on staged Bend paths. `pre-push` runs the complete proof suite when pushed changes
include Bend sources, host effects, the proof runner, toolchain/dependency metadata or
the hook configuration. Documentation-only changes skip the formal suite.

The lint command reads files from the working tree; `{staged_files}` selects paths,
not staged file contents. With partially staged files, the lint result also reflects
their unstaged edits. Checks do not rewrite or stage files.

Run the checks manually from the repository root:

```sh
lefthook run pre-commit --all-files
lefthook run pre-push --all-files
bend proofs/KeysProof.bend
./proofs/run.sh
git diff --check
```

## Documentation

| Topic | Reference |
| --- | --- |
| Purpose, users and scope | [PRODUCT.md](PRODUCT.md) |
| Agent rules | [AGENTS.md](AGENTS.md) |
| Bend conventions and development gates | [Bend](docs/standards/bend.md), [formal verification](docs/standards/formal-verification.md), [host effects](docs/standards/host-effects.md) |
| Public API, writes and errors | [Durable API](docs/features/durable-api.md) |
| Ordering, codecs and compatibility | [Storage format](docs/features/storage-format.md) |
| Cursor ownership and stable reads | [Scans and snapshots](docs/features/scans-and-snapshots.md) |
| Process ownership and local clients | [Coordination](docs/features/coordination.md) |
| Export, restore and legacy migration | [Backup and migration](docs/features/backup-and-migration.md) |
| Launcher, demo and REPL | [CLI](docs/features/cli.md) |
| Runtime checks and measurements | [Bench map](bench/README.md) and [0.6 acceptance evidence](bench/results/mylsm-0.6.0.0-acceptance.md) |

The alpha has no production stability or compatibility guarantee. Release acceptance is
incomplete, including the Linux cursor memory ceiling and the repeated workload matrix.
Each feature document records its current limits and links to the relevant evidence.
Formal laws cover pure decisions; they do not prove the filesystem or host effects.

Durable documentation is organized by feature or standard, with limits, outstanding work
and evidence alongside the relevant topic. Measurement reports retain their dates,
commands, environments and samples in `bench/results/`. Superpowers designs and plans
are local working documents under `docs/superpowers/`, excluded from Git by `.gitignore`.

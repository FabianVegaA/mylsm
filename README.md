# MyLSM

MyLSM is an LSM key-value database written in [Bend](https://github.com/bendlang/bend), aiming to compete with leading storage engines in performance and data safety. It stores writes durably in a log, keeps sorted tables on disk, and recovers after a restart. This checkout implements **0.6.0.0 alpha** for evaluation and development. The package import in `pack.json` still points to `0.5.0.0`; this checkout does not establish a published 0.6 release.

## Install with Nix

The GitHub commands require a published revision containing this flake. Use the
local checkout commands below while working on unpublished changes.

```sh
nix profile install github:FabianVegaA/mylsm
mylsm doctor
mylsm repl --dir ./my-data
```

To run without installing:

```sh
nix run github:FabianVegaA/mylsm -- repl --dir ./my-data
```

The package provides a native CPU CLI with `demo`, `repl`, `doctor` and `--help`.
It includes precompiled helpers and needs no Bend installation, compiler or Hub
downloads at runtime. Databases are created in the caller's directory or the
explicit `--dir` path. Apple Silicon requires macOS 15 or newer; Linux ARM64 and
x86-64 are also defined. GPU execution and development commands use the checkout.

From a local checkout, use `nix build` to produce `result/bin/mylsm`,
`nix run . -- repl --dir ./my-data`, or `nix profile install .`.
These commands require Nix's `nix-command` and `flakes` features; see Development.

## Run from source

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
Tool revisions are fixed in [flake.nix](flake.nix) and [flake.lock](flake.lock).

Install [Nix](https://nix.dev/install-nix) and enter the development shell:

```sh
nix --extra-experimental-features 'nix-command flakes' develop
lefthook install
```

The flake supplies Bend 2.0.39, Bolt 1.18.0, Lefthook, Clang, Bash, Git, Unix tools,
Python, Node and Bun. `flake.lock` pins the inputs; Bolt is built from its pinned
source and dependency lock without using a sibling checkout or the personal Bend
cache. The first entry downloads tools and builds Bolt. Entering the shell does not
install Git hooks; run `lefthook install` once after cloning.

The shell is defined for Apple Silicon macOS, and ARM64 and x86-64 Linux.
On macOS, install Apple's Command Line Tools with `xcode-select --install` if they
are missing; the official Bend package also uses Apple's toolchain. If a fresh Nix
installation is not yet on `PATH`, open a new terminal or source
`/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh`.

With flakes enabled in your Nix configuration, the entry command is simply
`nix develop`. Commands can also run without an interactive shell:

```sh
nix develop --command bash proofs/run.sh
nix develop --command bash bench/smoke/durable_session.sh
nix build .#bolt --no-link
```

Project Hub dependencies are fixed by file hash in [ez.lock.toml](ez.lock.toml).
Nix fetches them during construction and supplies the resulting read-only
`BEND_LIB` to the development shell. Add new imports to that lock before using
them in a sandboxed build. Bend's formal verifier still uses its writable kernel
cache when checking proofs.

To update tools, change the pinned Bend/Bolt revisions in `flake.nix`, then run
`nix flake update bend bolt`.
Check the Bend package's version: an upstream release tag can still contain the
previous version's flake. To update `ez`, change its pinned revision before running
`nix flake update ez`. Use `nix flake update nixpkgs` to update the package collection.
Re-run the proof suite, lint and relevant runtime checks after toolchain updates.
`nix flake check` also builds MyLSM and verifies the installed CLI outside its
source tree, including persistent REPL reads and a supervised thread restart.

Nix files use [nixfmt](https://github.com/NixOS/nixfmt) with a target width of
200 characters. Run `nix fmt` to format the project, or `nixfmt path/to/file.nix`
inside `nix develop`. Both use the same width. `nix flake check` verifies the format.

`pre-commit` checks staged whitespace, Nix formatting, and Bolt plus the 200-character line limit
on staged Bend paths. `pre-push` runs the complete proof suite when pushed changes
include Bend sources, host effects, the proof runner, Nix configuration, dependency metadata or
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

# MyLSM Hub Facade (importable pure core) — Design Spec

**Date:** 2026-09-22
**Status:** Draft, pending human review
**Choice:** Option C (facade `mylsm.bend`, pure-only v1) → approach C1 (single-publish amalgamation)
**Related:** `docs/superpowers/specs/2026-09-17-lsm-bend-design.md`, `README.md`, `AGENT.md`

## 1. Mission

Make MyLSM usable as `import 0xHASH/mylsm.bend as MyLSM` from the Bend hub
(`hub.bend-lang.com`) and listable on the community catalog
(`777genius/bend-packages`, default `source: hub` view), following the
SQLite/DuckDB pattern: a versioned, single-artifact embeddable core with the
OS/IO layer (`VFS`) kept outside the published bundle.

v1 publishes only the pure in-memory core. Durability (`WAL append`, `fsync`,
`Manifest` publish, `Flush`, `Compact`, `Recover`) stays git-only behind
`bin/mylsm demo/repl`. No `Nix` work is required for listing.

## 2. Scope and non-goals

### In scope

1. New facade file `mylsm.bend` at repo root that imports the pure modules and
   re-exports a curated public API (types + pure functions only).
2. Hub publish of that single file (`bend mylsm.bend --publish`), producing one
   `0xHASH` and one canonical import line.
3. `pack.json` manifest plus README import snippet so the catalog scanner
   (`scripts/scan.mjs`: README/`pack.json` contains `import 0xHASH/file.bend`,
   `file.bend` exists in repo, hub URL returns 200) promotes the row to
   `source: hub`.
4. Fetch verification from a clean `~/.bend/lib` plus `bend-packages` Add-package
   issue (category `packages` for the core; `demos` row for the full DB stays
   optional/git).

### Out of scope

- Publishing any `IO` path (`Db.db_put/db_del`, `Recover.open_db/maintain`,
  `Flush.*`, `Compact.*` IO halves, `SstStream.read_table`, `Fs.*`,
  `Console.*`, `CrashPoint.hit`). These import `./effs/*.c` + `./effs/*.js`
  twins and the host filesystem; they remain git-only.
- Per-module layered publishes (one hash per `Keys`/`MemTable`/...). Deferred
  until reuse demands it (approach C2).
- Separate `mylsm_io.bend` VFS adapter publish (approach C3). Deferred.
- Stable on-disk format promises, multi-client concurrency, network protocol,
  `Nix` flake. None is a catalog requirement.

## 3. Architecture (SQLite analogy)

```
                  ┌─────────────────────────────────┐
                  │ mylsm.bend  (v1 publish root)   │  ← amalgamation, like sqlite3.h
                  │  pure types + pure functions    │
                  └─────────┬───────────┬───────────┘
              imports       │           │       imports (transitive, bundled by hub)
              ┌─────────────▼─┐   ┌─────▼──────────────┐
              │ Keys          │   │ MemTable           │
              │ cmp/eq        │   │ put/del/get/scan   │
              └───────────────┘   └────────┬───────────┘
                                           │ entries: List Entry
              ┌──────────────────┐  ┌──────▼───────┐  ┌──────────────┐
              │ SortedRun        │  │ Sstable      │  │ Wal          │
              │ sort_newest      │  │ build(_sorted│  │ encode/decode│
              └──────────────────┘  │ from_sorted_ │  │ enc_mut/dec  │
                                    │ unique       │  └──────────────┘
                              ┌─────▼───────┐  ┌──────────────┐  ┌──────────┐
                              │ BitTree     │  │ SstFile(V2)  │  │ Manifest │
                              │ Bloom bits  │  │ serialize/   │  │ serial-  │
                              └─────────────┘  │ parse        │  │ ize/parse│
                                               └──────────────┘  └──────────┘
                                                        Decimal (parse helpers)

  OUT (git-only VFS, not published): Db.bend, Recover.bend, Flush.bend,
  Compact.bend IO halves, SstStream.bend, Fs.bend, Console.bend,
  CrashPoint.bend, src/effs/*.c + *.js, app/*, bench/*, laws/*, proofs/*
```

The hub bundles `mylsm.bend` plus everything it transitively imports into one
content-addressed directory `0xHASH/`. Consumers pin the hash exactly as they
would pin an amalgamation tarball. A later `C3` step can publish the VFS
adapter as a second package depending on this core hash, mirroring DuckDB
extensions.

## 4. Public API (v1, exact names verified 2026-09-22)

Types (re-exported, not redefined):

- `MemTable.Entry{key: String, val: Maybe<&2, String>}`
- `MemTable.MemTable` (`MT{entries}`)
- `Sstable.Table` (`Tbl{entries, filter, nbits, smallest, largest, count}`)
- `Sstable.Metadata` (`Meta{smallest, largest, count}`)
- `Wal.Mut` (`Put{key, val}` / `Del{key}`), `Wal.Batch{muts}`
- `Manifest.Manifest` (`M{...}`)

Functions (thin wrappers, same signatures as sources):

- Keys: `Keys.cmp(a, b) -> Cmp`, `Keys.eq(a, b) -> Bool`
- MemTable: `MemTable.empty()`, `MemTable.put(t, k, v)`,
  `MemTable.del(t, k)`, `MemTable.get(t, k) -> Maybe<&2, String>`
- SortedRun: `SortedRun.sort_newest(entries)`
- Sstable: `Sstable.build(entries, level, est_keys) -> Table`,
  `Sstable.from_sorted_unique(entries, level) -> Table`,
  `Sstable.build_sorted(entries, level, est_keys) -> Table`
- Wal: `Wal.encode(b: Batch) -> String`, `Wal.decode(s: String) -> Maybe<&2, Batch>`
- SstFile: `SstFile.serialize(entries, level) -> String`,
  `SstFile.parse(encoded) -> Maybe<&2, Sstable.Table>` (v2 default)
- Manifest: `Manifest.serialize(m) -> String`,
  `Manifest.parse(s) -> Maybe<&2, Manifest>`

Explicitly excluded in v1: `Db.*`, `Recover.*`, `Flush.*`, `Compact.*`,
`SstStream.*`, `Fs.*`, `Console.get_env`, `CrashPoint.hit`, any `def main`.

Facade constraints: `import Base` + relative `./src/*.bend` imports only; no
`import "./src/effs/*.c"` / `"./src/effs/*.js"`; no `IO.*`; no `def main`;
no `TODO`; no `@unsafe` (per `AGENT.md`); no `open` laws — only delegating
`def`s so checker load stays identical to checking the sources.

## 5. Data flow / consumer UX

Producer (once per release):

```sh
bend mylsm.bend --check-only
bend mylsm.bend --publish
# prints: 0x<hash>
#         import 0x<hash>/mylsm.bend as MyLSM
```

Consumer (any repo):

```bend
import Base
import 0x<hash>/mylsm.bend as MyLSM

def main() -> U32:
  t0 = MyLSM.MemTable.empty()
  t1 = MyLSM.MemTable.put(t0, "hello", "world")
  match MyLSM.MemTable.get(t1, "hello"):
    case Some{v}: 1
    case None{}: 0
```

First run fetches into `~/.bend/lib/0x<hash>/`, verifies content hash, then
runs offline. v1 is an in-memory library (MemTable + SSTable build + WAL/Manifest
codecs); durable open/write/crash-recovery remain in this repo via
`bin/mylsm demo`.

## 6. Error handling

The facade adds no error policy. Pure codecs already return
`Maybe`/`Result`-shaped answers (`Wal.decode -> Maybe<&2, Batch>`,
`SstFile.parse -> Maybe<&2, Sstable.Table>`,
`Manifest.parse -> Maybe<&2, Manifest>`, `MemTable.get -> Maybe<&2, String>`);
callers match on them. No `IO.try`, `IO.die`, or host-effect failures can occur
because no `IO` is imported. A corrupt payload yields `None{}`/`Fail`, never a
trap.

## 7. Testing and acceptance gates

1. `bend mylsm.bend --check-only` passes (Bend 2.0.x, same as CI).
2. `bend guide` sanity unaffected; `./proofs/run.sh` still green (facade adds no
   laws; existing `laws/*.bend` + `proofs/*Proof.bend` untouched).
3. Publish prints a hash + import line; `https://hub.bend-lang.com/0xHASH/mylsm.bend`
   returns 200.
4. Clean-fetch check: move `~/.bend/lib/0xHASH` aside, compile+run a scratch file
   importing the line on both native (`-o`) and portable backends.
5. Catalog checks: `mylsm.bend` exists in repo, README + `pack.json` contain the
   exact `import 0xHASH/mylsm.bend` string, `pack.json` category `packages`.
6. `bend-packages` row flips to `source: hub` (default view) after
   `scan.mjs`/`refresh-stars.mjs` run or maintainer merge.

## 8. Risks and mitigations

- Hash churn on every inner change → accept (same as amalgamation); cut
  releases deliberately, note hash in CHANGELOG/README per release.
- Accidental `IO`/`.c`/`.js` import creeping into facade → gate: `grep` for
  `IO\.|effs/|def main` on `mylsm.bend` in CI smoke.
- Name collisions for consumers (`Parse` precedent) → canonical alias `MyLSM`
  documented everywhere; facade re-exports keep `Module.fn` qualification.
- Catalog scanner mismatch (README names чужой hash) → `pack.json` is
  authoritative; verify file-in-repo + hub-200 before filing the issue.

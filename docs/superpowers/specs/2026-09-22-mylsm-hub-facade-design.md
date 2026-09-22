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

Two levels, one import: a `Db` abstraction for normal use plus granular
part control. Both are pure and in-memory; durability stays git-only.

### Level 1 — Db abstraction (high level, new thin wrappers)

`Db.bend` already splits cleanly: `open_db`, `apply_mut`, `apply_batch`,
`all_entries`, `db_get`, `wal_frame`, `wal_path` are pure; only `wal_tail`,
`wal_append`, `db_write`, `db_put`, `db_del` are `IO`. The facade exposes the
pure handle plus four composing wrappers (the only new logic in v1, ~10
lines, same read path `mem ++ L0 ++ L1...` first-match-wins incl. tombstones):

- Type `Db.Db` (`Db{dir, mem, levels, flushed, manifest_token}`), used as an
  in-memory handle. `dir` is an opaque label in v1; no filesystem is touched.
- `open(dir: String) -> Db.Db` = `Db.open_db(dir)`
- `put(db: Db.Db, k: String, v: String) -> Db.Db` =
  `Db.Db{dir, Db.apply_batch(Con{Wal.Put{k, v}, Nil{}}, mem), levels, flushed, manifest_token}`
- `del(db: Db.Db, k: String) -> Db.Db` = same with `Wal.Del{k}`
- `batch(db: Db.Db, muts: List<&2, Wal.Mut>) -> Db.Db` =
  `Db.Db{dir, Db.apply_batch(muts, mem), levels, flushed, manifest_token}`
- `get(db: Db.Db, k: String) -> Maybe<&2, String>` = `Db.db_get(db, k)`
- `encode_batch(b: Wal.Batch) -> String` = `Wal.encode(b)` (the exact bytes the
  future VFS adapter will frame with `Db.wal_frame` + `fsync`)

Consumer sketch: `open → put/put/del → get`, all pure, no `IO`.

### Level 2 — Part control (granular, delegating wrappers)

Prefixed so one alias (`MyLSM`) never collides; each delegates 1:1:

- Types: `MemTable.Entry`, `MemTable.MemTable`, `Sstable.Table`,
  `Sstable.Metadata`, `Wal.Mut`, `Wal.Batch`, `Manifest.Manifest`
  (re-exported by use, not redefined).
- Keys: `Keys.cmp(a, b) -> Cmp`, `Keys.eq(a, b) -> Bool`
- MemTable: `mem_empty()`, `mem_put(t, k, v)`, `mem_del(t, k)`,
  `mem_get(t, k) -> Maybe<&2, String>`, `mem_count(t) -> Nat`
- SortedRun: `sort_newest(entries)`; MergeIter: `range_scan(merged, lo, hi)`
  = `MergeIter.scan(merged, lo, hi)`
- Sstable: `sst_build(entries, level, est_keys) -> Table`,
  `sst_from_sorted_unique(entries, level) -> Table`,
  `sst_build_sorted(entries, level, est_keys) -> Table`
- Wal: `wal_encode(b: Batch) -> String`,
  `wal_decode(s: String) -> Maybe<&2, Batch>`
- SstFile: `sst_serialize(entries, level) -> String`,
  `sst_parse(encoded) -> Maybe<&2, Sstable.Table>` (v2 default)
- Manifest: `mfst_serialize(m) -> String`,
  `mfst_parse(s) -> Maybe<&2, Manifest>`

Explicitly excluded in v1: every `IO` def (`Db.db_put/db_del/db_write/wal_append`,
`Recover.*`, `Flush.*`, `Compact.*` IO halves, `SstStream.read_table`, `Fs.*`,
`Console.get_env`, `CrashPoint.hit`), any `def main`.

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

First run fetches into `~/.bend/lib/0x<hash>/`, verifies content hash, then
runs offline. Durable open/write/crash-recovery remain in this repo via
`bin/mylsm demo`; the published bundle is pure and in-memory.

### Level 1 — Db handle (normal use)

One handle, threaded linearly: every `Db.Db` holds affine lists, so each
binding is used exactly once (`+db` in every signature, mirroring
`src/Db.bend:36-84`). The read path is newest-first across mem ++ levels,
first match wins including tombstones — a `del` hides older versions forever.

```bend
import Base
import 0x<hash>/mylsm.bend as MyLSM

def main() -> U32:
  +db0 = MyLSM.open("/scratch")
  +db1 = MyLSM.put(db0, "hello", "world")
  +db2 = MyLSM.put(db1, "answer", "42")
  +db3 = MyLSM.del(db2, "hello")
  match MyLSM.get(db3, "answer"):
    case Some{v}: 1
    case None{}: 0
```

`batch(db, muts)` folds a whole `Wal.Mut` list at once (pinned equal to
sequential `put`/`del` by the existing `Db` laws); `encode_batch` renders the
exact bytes the future VFS adapter will frame with `Db.wal_frame` + `fsync`.

### Level 2 — part control (tuning and embedding)

Same alias, prefixed functions, no handle needed. Ordered-map core plus key
ordering, all without constructors:

```bend
import Base
import 0x<hash>/mylsm.bend as MyLSM

def main() -> U32:
  +t = MyLSM.mem_put(MyLSM.mem_empty(), "k", "v")
  match MyLSM.mem_get(t, "k"):
    case Some{v}:
      match MyLSM.eq(v, "v"):
        case True{}: 1
        case False{}: 0
    case None{}:
      0
```

Only `match` branching is used (the `if` form is untested in this codebase).
`mem_count` returns `Nat` and `cmp/lt/le` return `Cmp`/`Bool` for custom
structures; `sort_newest`, `range_scan`, `sst_*`, `wal_*`, `mfst_*`
take/return `Entry`/`Mut`/`Batch`/`Table` values (see constructor gap below).

### Session-monad ergonomics (explicit, follow-up proposal — not v1 API)

Correcting §5's earlier implication: Bend's `do M<xs.., R>:` desugars to
`M.bind`/`M.pure` for **any** type defining them (`bend guide`: "`IO`,
`Maybe`, `Result`, or your own"), so explicit `db0..dbN` threading is a v1
choice, not a language limit. A session monad would look like this (sketch,
checker-spike required before committing):

```bend
type Sess<A> is Data:
  Sess{run: Db.Db -> (Db.Db & A)}

def sput(+k: String, +v: String) -> Sess<Unit>
def sdel(+k: String) -> Sess<Unit>
def sget(+k: String) -> Sess<Maybe<&2, String>>
# plus Sess.bind / Sess.pure matching the do-desugar shape
```

Consumer payoff (no manual threading):

```bend
def session() -> Sess<U32>:
  do Sess<U32>:
    sput("hello", "world")
    sput("answer", "42")
    sdel("hello")
    v : Maybe<&2, String> <- sget("answer")
    return 1
```

Why not v1: (1) ~30-40 new lines plus `bind`/`pure` shape-matching against an
unforgiving checker — this repo already carries "checker-tractable" scars
(e.g. `src/Sstable.bend:48-50`, closed-proof bridges in `AGENT.md` history),
and affine-state closures are exactly the risky shape; (2) `AGENT.md` asks for
laws+witnesses for pure decisions, so the monad laws (`bind pure`,
associativity) become proof work; (3) affinity doesn't vanish, it hides inside
`bind` — the win is purely syntactic and grows with session length, while the
README example (4 ops) is a wash once the `session`/`run` wrapper is counted.
Decision: v1 ships explicit threading (zero new machinery, 1:1 with the
proof-covered core); the `Sess` spike is the first v2 candidate, and if the
checker blows up, explicit style stands with no harm done.

### Constructor gap (explicit, follow-up proposal — not v1 API)

v1 has no `mk_entry`/`mk_put` helpers, so a consumer cannot write an `Entry`
or `Mut` literal with only the facade imports: codec/table/scan functions are
fully callable but their inputs must come from prior facade outputs (e.g.
`wal_decode` of a hand-written payload, or entries destructured from an
`sst_build` result as in plan Task 2 `c6`). If demand appears, the follow-up
is three delegating defs (no new logic, same constraints as §4):

```bend
def mk_entry(+k: String, +v: String) -> MemTable.Entry
def mk_tombstone(+k: String) -> MemTable.Entry
def mk_put_batch(+k: String, +v: String) -> Wal.Batch
```

This keeps v1 minimal (YAGNI) while making the limitation and its fix
explicit instead of leaving consumers to guess.

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
  releases deliberately, note hash in README + `pack.json` per release.
- Accidental `IO`/`.c`/`.js` import creeping into facade → gate: `grep` for
  `IO\.|effs/|def main` on `mylsm.bend` in CI smoke.
- Name collisions for consumers (`Parse` precedent) → canonical alias `MyLSM`
  documented everywhere; facade re-exports keep `Module.fn` qualification.
- Catalog scanner mismatch (README names чужой hash) → `pack.json` is
  authoritative; verify file-in-repo + hub-200 before filing the issue.

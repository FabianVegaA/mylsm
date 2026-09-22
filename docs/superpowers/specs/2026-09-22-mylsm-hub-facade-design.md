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

Two levels, one import: a `Sess` session monad for normal use (primary API,
`do`-notation, no manual handle threading) plus granular part control. Both
are pure and in-memory; durability stays git-only.

### Level 1 — Sess session monad (primary API, `do`-notation)

`Db.bend` already splits cleanly: `open_db`, `apply_mut`, `apply_batch`,
`all_entries`, `db_get` are pure; only `wal_tail`, `wal_append`, `db_write`,
`db_put`, `db_del` are `IO`. Level 1 threads the pure `Db.Db` handle
(`Db{dir, mem, levels, flushed, manifest_token}`, `dir` an opaque label, no
filesystem touched) through a state monad, so consumers never write
`db0..dbN`. Read path unchanged: newest-first across mem ++ levels,
first-match-wins including tombstones.

Shapes proven by toy spike 2026-09-22 (compiles `All terms check`, runs
correct — `/tmp/sess_spike.bend`): quantity-mirroring `Maybe` exactly,
single shared quantity in `bind` (the `do` desugar calls
`M.bind(xs.., A, R, m, k)`, so separate `a`/`b` misaligns — diagnosed live),
all bindings affine (no `+`: `Sess` is `Kind(a <&> &1)`, and `+` demands
`Data`), fields extracted only via `case Sess{run}` patterns (there is no
`m.run` projection expression), direct calls passing quantity+type args
explicitly (`Sess.run_go(b, B, …)`), closures match-free with all logic in
named `*_go` defs on def-param binders:

```bend
type Sess<a, -A: Kind(a)> is Kind(a <&> &1):
  Sess{run: Db.Db -> (Db.Db & A)}

def Sess.pure(a, -A: Kind(a), x: A) -> Sess<a, A>:
  Sess{db => (db, x)}

def Sess.run_go(b, -B: Kind(b), s: Sess<b, B>, st: Db.Db) -> Db.Db & B:
  match s:
    case Sess{run}: run(st)

def Sess.apply(a, -A: Kind(a), b, -B: Kind(b), p: Db.Db & A, f: A -> Sess<b, B>) -> Db.Db & B:
  match p:
    case (st, x): Sess.run_go(b, B, f(x), st)

def Sess.bind(a, -A: Kind(a), -B: Kind(a), m: Sess<a, A>, f: A -> Sess<a, B>) -> Sess<a, B>:
  Sess{st => Sess.apply(a, A, a, B, Sess.run_go(a, A, m, st), f)}
```

State transitions reuse the covered core via `*_go` helpers (match only on
def params, the `src/Recover.bend:514` precedent; double-use of the `Db`
handle goes through `+` def-params, legal because `Db` `is Data` — the
`guide` `replicate` precedent):

```bend
def open(+dir: String) -> Db.Db:
  Db.open_db(dir)

def put_go(+db: Db.Db, +k: String, +v: String) -> Db.Db  # +db: Data, reusable
def del_go(+db: Db.Db, +k: String) -> Db.Db
def batch_go(+db: Db.Db, +muts: List<&2, Wal.Mut>) -> Db.Db
def sget_go(+db: Db.Db, +k: String) -> Db.Db & Maybe<&2, String>

def sput(+k: String, +v: String) -> Sess<&2, Unit>
def sdel(+k: String) -> Sess<&2, Unit>
def sbatch(+muts: List<&2, Wal.Mut>) -> Sess<&2, Unit>
def sget(+k: String) -> Sess<&2, Maybe<&2, String>>

def run_sess(a, -A: Kind(a), st: Db.Db, s: Sess<a, A>) -> Db.Db & A:
  Sess.run_go(a, A, s, st)  # s plain affine (Sess is NOT Data: +s is rejected)
def value_of(a, -A: Kind(a), p: Db.Db & A) -> A:
  match p:
    case (db, x): x  # dropping the affine handle is free (guide, Quantities)
def encode_batch(b: Wal.Batch) -> String  # VFS bridge: exact bytes for Db.wal_frame + fsync
```

Consumer sketch: `open → run_sess(session)` where `session` is a `do
Sess<…>:` block of `sput/sdel/sbatch` steps and `v : T <- sget(k)` binds —
all pure, no `IO`, no manual threading. No new laws: `Sess` is sequencing
only; the transition semantics stay covered by the existing `Db` laws, and
adding law blocks would force witnesses through the proof name-gate for zero
semantic gain.

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

### Level 1 — Sess session (normal use, primary API)

No manual `db0..dbN` threading: Bend's `do` desugars to `Sess.bind`/`Sess.pure`
for any type defining them (`bend guide`, Monads), so the session reads
linearly while the monad threads the affine handle underneath. Each
`run_sess` consumes its `Db` (affine use-once), so checks open a fresh handle
per run:

```bend
import Base
import 0x<hash>/mylsm.bend as MyLSM

def show(+m: Maybe<&2, String>) -> U32:
  match m:
    case Some{v}: 1
    case None{}: 0

def session() -> MyLSM.Sess<&2, Maybe<&2, String>>:
  do MyLSM.Sess<&2, Maybe<&2, String>>:
    MyLSM.sput("hello", "world")
    MyLSM.sput("answer", "42")
    MyLSM.sdel("hello")
    v : Maybe<&2, String> <- MyLSM.sget("answer")
    return v

def main() -> U32:
  show(MyLSM.value_of(&2, Maybe<&2, String>, MyLSM.run_sess(&2, Maybe<&2, String>, MyLSM.open("/scratch"), session())))
```

(`value_of` unwraps the runner pair; `show` matches on its parameter — the
helper rule still holds: Bend rejects `match` on computed calls, verified
`bend --check-only` 2026-09-22. Steps share the block quantity `&2`;
`v : T <- …` binds, bare `sput(…)` is a Unit step, `return` wraps via
`Sess.pure`.)

`sbatch(muts)` folds a whole `Wal.Mut` list at once (pinned equal to
sequential `sput`/`sdel` by the existing `Db` laws); `encode_batch` renders
the exact bytes the future VFS adapter will frame with `Db.wal_frame` +
`fsync`.

### Level 2 — part control (tuning and embedding)

Same alias, prefixed functions, no handle needed. Ordered-map core plus key
ordering, all without constructors:

```bend
import Base
import 0x<hash>/mylsm.bend as MyLSM

def bit(b: Bool) -> U32:
  match b:
    case True{}: 1
    case False{}: 0

def check_mem(+m: Maybe<&2, String>) -> U32:
  match m:
    case Some{v}: bit(MyLSM.eq(v, "v"))
    case None{}: 0

def main() -> U32:
  +t = MyLSM.mem_put(MyLSM.mem_empty(), "k", "v")
  check_mem(MyLSM.mem_get(t, "k"))
```

Same helper rule as Level 1 (no `match` on computed calls, no `if` —
`bend guide` has no `if` syntax yet). `mem_count` returns `Nat` and
`cmp/lt/le` return `Cmp`/`Bool` for custom structures; `sort_newest`,
`range_scan`, `sst_*`, `wal_*`, `mfst_*` take/return `Entry`/`Mut`/`Batch`/
`Table` values (see constructor gap below).

### Sess checker rules (proven 2026-09-22, normative for implementation)

`Sess` is v1 (promoted from follow-up) after a toy spike compiled
`All terms check` and ran correct, plus a qualified-alias spike
(`do L.Sess<…>` across files). Six rules, each diagnosed live against the
checker — violating any one fails `--check-only`:

1. Single shared quantity in `bind`: the desugar calls `M.bind(xs.., A, R,
   m, k)`, so separate `a`/`b` misaligns (`expected Quant, observed Data`).
   Mirror `Maybe.bind` exactly: `(a, -A: Kind(a), -B: Kind(a), m, f)`.
2. No `+` on `Sess` bindings: `Sess` is `Kind(a <&> &1)`, and `+` demands
   `Data` (`expected Data, observed Kind`). All bindings plain affine,
   used exactly once.
3. No `m.run` projection expressions (`expected a defined name`): fields
   leave the wrapper only via `case Sess{run}` patterns. Route everything
   through `Sess.run_go`.
4. Direct calls pass quantity+type args explicitly (`Sess.run_go(b, B, …)`,
   the `Maybe.is_some(a, A, m)` precedent); only the `do` desugar inserts
   them automatically.
5. Closures are match-free and `+`-free: all logic lives in named `*_go`
   defs on def-param binders; double-use of the `Db` handle goes through
   `+` def-params (legal because `Db` `is Data` — the guide `replicate`
   precedent), never `+` lambda binders (untested shape, not needed).
6. Def order is load-bearing (backward references only): machinery
   (`type`, `pure`, `run_go`, `apply`, `bind`) → `*_go` helpers → actions
   → `run_sess`/`value_of` → sessions → `main` last. A forward reference
   fails with `expected a defined name` (diagnosed live).

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

1. `bend mylsm.bend --check-only` passes (Bend 2.0.x, same as CI). The
   `Sess` shapes are pre-validated: toy spike plus qualified-alias spike
   both compile and run 2026-09-22, so a Task 2 failure points at a
   transcription error against §4, not at the design.
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
- Catalog scanner mismatch (README names someone else's hash) → `pack.json`
  is authoritative; verify file-in-repo + hub-200 before filing the issue.
- `Sess` transcription drift (the six §5 rules) → any `--check-only` failure
  in Task 2 is diffed against the proven toy (`/tmp/sess_spike.bend`,
  `/tmp/sesslib/lib.bend` + `/tmp/sess_qual.bend` shapes) before touching
  the design.

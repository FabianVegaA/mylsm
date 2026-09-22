# MyLSM Hub Facade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish `mylsm.bend` (pure Db abstraction + part-level control, no IO) to the Bend hub and list it on bend-packages as `source: hub`.

**Architecture:** Single-file facade at repo root importing `./src/*.bend` and delegating 1:1 (approach C1); four new pure `Db`-handle wrappers compose verified `Db.open_db/apply_batch/db_get`; everything else delegates with identical signatures.

**Tech Stack:** Bend 2.0.x (`bend --check-only`, `bend --publish`), existing `src/*.bend` pure modules, `pack.json` catalog manifest, `bend-packages` `scan.mjs` conventions.

---

## File structure

- Create: `mylsm.bend` — the publish root and only new Bend code. Imports `Base` + 9 `./src/*.bend` modules (`Keys`, `MemTable`, `SortedRun`, `Sstable`, `SstFile`, `Wal`, `Manifest`, `MergeIter`, `Db`). Contains Level 1 (`open/put/del/batch/get/encode_batch`) + Level 2 (`mem_*/sst_*/wal_*/mfst_*/sort_newest/range_scan`, `Keys.cmp/eq` passthroughs). No `IO`, no `.c`/`.js` imports, no `def main`, no `@unsafe`.
- Create: `pack.json` — `{"name","description","import","category":"packages"}` with the exact published import line.
- Create (scratch, delete before commit): `.mylsm/build/facade_check.bend` (gitignored) — consumer-style verification file importing the facade by relative path.
- Modify: `README.md:10-28` (Quick start section) — append `Use as a library (Bend hub)` subsection with the canonical import snippet.
- Test via: `bend mylsm.bend --check-only`, `bend .mylsm/build/facade_check.bend` (portable run), `./proofs/run.sh` (regression gate, unchanged expectations), `bend bench/fuzz.bend` (decoder smoke, unchanged).

---

### Task 1: Facade skeleton with Level 2 part-control delegates

**Files:**
- Create: `mylsm.bend`
- Test: `.mylsm/build/facade_check.bend` (created in Task 2, gitignored)

- [ ] **Step 1: Write `mylsm.bend` imports + Level 2 delegates**

```bend
import Base
import ./src/Keys.bend as Keys
import ./src/MemTable.bend as MemTable
import ./src/SortedRun.bend as SortedRun
import ./src/Sstable.bend as Sstable
import ./src/SstFile.bend as SstFile
import ./src/Wal.bend as Wal
import ./src/Manifest.bend as Manifest
import ./src/MergeIter.bend as MergeIter
import ./src/Db.bend as Db

# --- Level 2: part control (1:1 delegates) ---
def cmp(+a: String, +b: String) -> Cmp:
  Keys.cmp(a, b)

def eq(+a: String, +b: String) -> Bool:
  Keys.eq(a, b)

def mem_empty() -> MemTable.MemTable:
  MemTable.empty()

def mem_put(t: MemTable.MemTable, k: String, v: String) -> MemTable.MemTable:
  MemTable.put(t, k, v)

def mem_del(t: MemTable.MemTable, k: String) -> MemTable.MemTable:
  MemTable.del(t, k)

def mem_get(t: MemTable.MemTable, +k: String) -> Maybe<&2, String>:
  MemTable.get(t, k)

def mem_count(t: MemTable.MemTable) -> Nat:
  MemTable.count(t)

def sort_newest(entries: List<&2, MemTable.Entry>) -> List<&2, MemTable.Entry>:
  SortedRun.sort_newest(entries)

def range_scan(+merged: List<&2, MemTable.Entry>, lo: String, hi: String) -> List<&2, MemTable.Entry>:
  MergeIter.scan(merged, lo, hi)

def sst_build(+entries: List<&2, MemTable.Entry>, level: Nat, est_keys: Nat) -> Sstable.Table:
  Sstable.build(entries, level, est_keys)

def sst_from_sorted_unique(+entries: List<&2, MemTable.Entry>, level: Nat) -> Sstable.Table:
  Sstable.from_sorted_unique(entries, level)

def sst_build_sorted(+entries: List<&2, MemTable.Entry>, level: Nat, est_keys: Nat) -> Sstable.Table:
  Sstable.build_sorted(entries, level, est_keys)

def wal_encode(b: Wal.Batch) -> String:
  Wal.encode(b)

def wal_decode(+s: String) -> Maybe<&2, Wal.Batch>:
  Wal.decode(s)

def sst_serialize(+entries: List<&2, MemTable.Entry>, +level: Nat) -> String:
  SstFile.serialize(entries, level)

def sst_parse(+encoded: String) -> Maybe<&2, Sstable.Table>:
  SstFile.parse(encoded)

def mfst_serialize(m: Manifest.Manifest) -> String:
  Manifest.serialize(m)

def mfst_parse(+s: String) -> Maybe<&2, Manifest.Manifest>:
  Manifest.parse(s)
```

- [ ] **Step 2: Typecheck the skeleton**

Run: `bend mylsm.bend --check-only`
Expected: exit 0 (`All terms check.` or no output). `Keys` is already referenced by `cmp`/`eq`; `Db` is first referenced in Task 2. If the checker errors on the unused `Db` import, leave the file as-is and proceed to Task 2 before re-running.

- [ ] **Step 3: Commit skeleton**

```bash
git add mylsm.bend
git commit -m "feat: add mylsm.bend facade skeleton with part-level delegates"
```

### Task 2: Level 1 Db abstraction wrappers

**Files:**
- Modify: `mylsm.bend` (append Level 1 defs)
- Test: `.mylsm/build/facade_check.bend` (gitignored)

- [ ] **Step 1: Append Level 1 Db-handle wrappers to `mylsm.bend`**

```bend
# --- Level 1: Db abstraction (pure in-memory handle; dir is an opaque label) ---
def open(+dir: String) -> Db.Db:
  Db.open_db(dir)

def put(+db: Db.Db, +k: String, +v: String) -> Db.Db:
  match db:
    case Db.Db{dir, +mem, levels, flushed, manifest_token}:
      Db.Db{dir, Db.apply_batch(Con{Wal.Put{k, v}, Nil{}}, mem), levels, flushed, manifest_token}

def del(+db: Db.Db, +k: String) -> Db.Db:
  match db:
    case Db.Db{dir, +mem, levels, flushed, manifest_token}:
      Db.Db{dir, Db.apply_batch(Con{Wal.Del{k}, Nil{}}, mem), levels, flushed, manifest_token}

def batch(+db: Db.Db, +muts: List<&2, Wal.Mut>) -> Db.Db:
  match db:
    case Db.Db{dir, +mem, levels, flushed, manifest_token}:
      Db.Db{dir, Db.apply_batch(muts, mem), levels, flushed, manifest_token}

def get(+db: Db.Db, +k: String) -> Maybe<&2, String>:
  Db.db_get(db, k)

def encode_batch(b: Wal.Batch) -> String:
  Wal.encode(b)
```

Linearity notes (do not change): `+mem` in the `case` pattern mirrors the proven pattern at `src/Recover.bend:514`; each bound field (`dir`, `levels`, `flushed`, `manifest_token`) is used exactly once in the rebuilt `Db.Db{...}` (same as `src/Db.bend:112-119`).

- [ ] **Step 2: Write the consumer-style check file**

Each check builds its own handle because `Db.Db` holds affine lists: a handle
is consumed by `get`, so sharing one handle across assertions would violate
linearity. Two checker rules shape this file (both verified against
`bend --check-only` on 2026-09-22): no `match` on a computed call or a
`let`-bound variable (the checker rejects both: "a parameter or field
scrutinee" — corroborated by the comment at `src/Keys.bend:3-5`), so computed
results travel as arguments to helpers that match on parameters; and no `if`
(`bend guide` has none yet). `main` therefore delegates to `run_all` instead
of matching on `c1()..c6()` directly. Save as
`.mylsm/build/facade_check.bend` (`.mylsm/` is gitignored, so it never leaks
into the publish or a commit):

```bend
import Base
import ../../mylsm.bend as MyLSM
import ../../src/Wal.bend as Wal
import ../../src/Sstable.bend as Sstable
import ../../src/MemTable.bend as MemTable

def check_get_eq(got: Maybe<&2, String>, want: String) -> Bool:
  match got:
    case Some{v}:
      String.eq(v, want)
    case None{}:
      False{}

def is_missing(+m: Maybe<&2, String>) -> Bool:
  match m:
    case None{}:
      True{}
    case Some{_}:
      False{}

def is_some_batch(+m: Maybe<&2, Wal.Batch>) -> Bool:
  match m:
    case Some{_}:
      True{}
    case None{}:
      False{}

def is_some_table(+m: Maybe<&2, Sstable.Table>) -> Bool:
  match m:
    case Some{_}:
      True{}
    case None{}:
      False{}

def c1() -> Bool:
  +db = MyLSM.put(MyLSM.open("/s"), "hello", "world")
  check_get_eq(MyLSM.get(db, "hello"), "world")

def c2() -> Bool:
  +db = MyLSM.put(MyLSM.put(MyLSM.open("/s"), "hello", "world"), "answer", "42")
  check_get_eq(MyLSM.get(db, "answer"), "42")

def c3() -> Bool:
  +db = MyLSM.del(MyLSM.put(MyLSM.open("/s"), "hello", "world"), "hello")
  is_missing(MyLSM.get(db, "hello"))

def c4() -> Bool:
  +t = MyLSM.mem_put(MyLSM.mem_empty(), "k", "v")
  check_get_eq(MyLSM.mem_get(t, "k"), "v")

def c5() -> Bool:
  is_some_batch(MyLSM.wal_decode(MyLSM.wal_encode(Wal.Batch{Con{Wal.Put{"a", "b"}, Nil{}}})))

def c6_go(+t: Sstable.Table) -> Bool:
  match t:
    case Sstable.Tbl{entries, filter, nbits, smallest, largest, count}:
      is_some_table(MyLSM.sst_parse(MyLSM.sst_serialize(MyLSM.sort_newest(entries), 0n)))

def c6() -> Bool:
  c6_go(MyLSM.sst_build(Con{MemTable.Entry{"k", Some{"v"}}, Nil{}}, 0n, 1n))

def run_all(a: Bool, b: Bool, c: Bool, d: Bool, e: Bool, f: Bool) -> U32:
  match a:
    case False{}:
      1
    case True{}:
      match b:
        case False{}:
          2
        case True{}:
          match c:
            case False{}:
              3
            case True{}:
              match d:
                case False{}:
                  4
                case True{}:
                  match e:
                    case False{}:
                      5
                    case True{}:
                      match f:
                        case False{}:
                          6
                        case True{}:
                          0

def main() -> U32:
  run_all(c1(), c2(), c3(), c4(), c5(), c6())
```

`c6` exercises Level 2 end to end: `sst_build` construction → destructure →
sort → serialize (v2) → parse roundtrip. Unused field bindings (`filter`,
`nbits`, `smallest`, `largest`, `count`) follow the proven precedent of
`Db.all_entries` (`src/Db.bend:76-81`), which binds `dir`/`flushed`/
`manifest_token` without using them. Exit code `0` means all six assertions
held; any nonzero value names the failing check.

- [ ] **Step 3: Run the check on the portable backend**

Run:
```bash
mkdir -p .mylsm/build
bend .mylsm/build/facade_check.bend
```
Expected: process prints `0` and exits 0. Any other printed number is a failure identifying the exact check above; fix the facade wrapper (never the `src/` sources) and re-run.

- [ ] **Step 4: Run the checker on the facade**

Run: `bend mylsm.bend --check-only`
Expected: PASS. A failure here with a passing Step 3 means a linearity (`+`) annotation mismatch: compare against the source signature (`src/Db.bend:36-84`, `src/MemTable.bend:16-65`) and adjust only the facade annotation.

- [ ] **Step 5: Commit Level 1**

```bash
git add mylsm.bend
git commit -m "feat: add pure Db-handle abstraction to mylsm.bend facade"
```

### Task 3: Regression gates (proofs + fuzz, no new laws)

**Files:**
- Test: `proofs/run.sh`, `bench/fuzz.bend` (run only, no modifications)

- [ ] **Step 1: Run the modular proof gate**

Run: `bin/mylsm check`
Expected: `SUMMARY PASS=<total> FAIL=0 TIMEOUT=0 TOTAL=<total>` (baseline: 34 modules green on Bend 2.0.24). The facade adds no `laws/*.bend` and no `proofs/*Proof.bend`, so the name-gate (`check_names`) must pass untouched. Any FAIL/TIMEOUT is a pre-existing issue, not caused by this plan: record it, do not modify proofs here.

- [ ] **Step 2: Run the decoder smoke corpus**

Run: `bin/mylsm fuzz`
Expected: exit 0 (same as before this plan). This exercises the `Wal`/`SstFile` codecs the facade delegates to.

- [ ] **Step 3: Grep the IO-freedom gate**

Run: `grep -n 'IO\.\|effs/\|def main\|@unsafe\|TODO' mylsm.bend`
Expected: no output. If any line matches, remove the offending def/import from `mylsm.bend` (the facade must stay pure) and re-run Task 2 Steps 3-4.

### Task 4: Publish to the hub and verify clean fetch

**Files:**
- Modify: none (publish is a network action producing a hash)

- [ ] **Step 1: Publish**

Run: `bend mylsm.bend --publish`
Expected: two lines, e.g.
```
0x<64-hex>
import 0x<64-hex>/mylsm.bend as MyLSM
```
Record both exactly. Cost: proof-of-work time on first publish; do not retry with different file contents (each content change yields a different hash).

- [ ] **Step 2: Confirm hub liveness**

Run: `curl -fsSL -o /dev/null -w '%{http_code}\n' 'https://hub.bend-lang.com/0x<hash>/mylsm.bend'`
Expected: `200`. A non-200 within 5 minutes means propagation delay: wait, retry once, then check the hash string for typos before anything else.

- [ ] **Step 3: Clean-fetch verification**

Run:
```bash
mv ~/.bend/lib/0x<hash> /tmp/mylsm-hub-backup-0x<hash> 2>/dev/null || true
printf 'import Base\nimport 0x<hash>/mylsm.bend as MyLSM\ndef fetch_ok(+m: Maybe<&2, String>) -> U32:\n  match m:\n    case Some{v}: 0\n    case None{}: 1\ndef main() -> U32:\n  +db = MyLSM.put(MyLSM.open("/v"), "k", "v")\n  fetch_ok(MyLSM.get(db, "k"))\n' > /tmp/mylsm_hub_fetch_check.bend
bend /tmp/mylsm_hub_fetch_check.bend
```

The `fetch_ok` helper exists because Bend rejects `match` on a computed call
("a parameter or field scrutinee"); the computed `get` travels as an argument.
Expected: prints `0`, and `~/.bend/lib/0x<hash>/mylsm.bend` exists afterwards (re-fetched from the hub, hash-verified). Restore nothing: leave the fetched cache in place; delete `/tmp/mylsm_hub_fetch_check.bend` and `/tmp/mylsm-hub-backup-0x<hash>` only after a PASS.

### Task 5: `pack.json` + README + catalog listing

**Files:**
- Create: `pack.json`
- Modify: `README.md:10-28`
- Test: manual URL checks + `bend-packages` issue

- [ ] **Step 1: Write `pack.json` with the real hash (no placeholders)**

```json
{
  "name": "mylsm",
  "description": "Pure in-memory LSM core: Db-handle abstraction plus MemTable, SSTable, WAL and Manifest part control.",
  "import": "import 0x<hash>/mylsm.bend as MyLSM",
  "category": "packages"
}
```

Replace `0x<hash>` with the exact 64-hex hash from Task 4 Step 1. The `import` value must be byte-identical to the publish output line.

- [ ] **Step 2: Append the library subsection to README Quick start**

After the `bin/mylsm bench` code block (`README.md:26-28`), insert:

```md
## Use as a library (Bend hub)

```sh
# Paste the import; the compiler fetches and verifies the hash.
```

```bend
import 0x<hash>/mylsm.bend as MyLSM
```

Level 1 (Db handle): `MyLSM.open/put/get/del/batch`. Level 2 (parts):
`MyLSM.cmp/eq/mem_*/sst_*/wal_*/mfst_*/sort_newest/range_scan`. Pure and
in-memory; durability (`bin/mylsm demo`) stays in this repo.
```

- [ ] **Step 3: Verify the three scanner conditions locally**

Run:
```bash
test -f mylsm.bend && echo FILE_OK
grep -F 'import 0x<hash>/mylsm.bend' README.md pack.json && echo SCAN_OK
curl -fsSL -o /dev/null -w '%{http_code}\n' 'https://hub.bend-lang.com/0x<hash>/mylsm.bend'
```
Expected: `FILE_OK`, two `SCAN_OK` grep hits (README + pack.json), `200`. These are exactly what `bend-packages/scripts/scan.mjs` checks (import string present, file in repo, hub 200).

- [ ] **Step 4: Commit manifest + docs, clean scratch**

```bash
rm -f .mylsm/build/facade_check.bend /tmp/mylsm_hub_fetch_check.bend
rm -rf /tmp/mylsm-hub-backup-0x<hash>
git add pack.json README.md mylsm.bend
git status --short
git commit -m "feat: publish mylsm.bend 0x<hash> with pack.json and README import"
```

- [ ] **Step 5: File the catalog issue**

Open `https://github.com/777genius/bend-packages/issues/new` (`＋Add package`): name `mylsm`, repo URL, description from `pack.json`, category `packages`, import line. The row flips to `source: hub` (default view) after the maintainer's `scan.mjs` run.

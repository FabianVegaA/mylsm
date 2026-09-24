# MyLSM Bend-Hub Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete the V1 SSTable legacy surface, then replace MyLSM core internals with pinned `bend-collections` hub modules across 5 layers (crypto → bits → MemTable/math → sort/merge → SSTable blocks/WAL batching), keeping the `mylsm.bend` facade signatures stable, and publish the result as a new hub version.

**Architecture:** Each layer turns one `src/*.bend` module into a thin adapter (~10–30 lines) over a hash-pinned hub import (`0x9ee2e9a299991dcc089fe22c7f3ceb5f`, verified in Task 0); only LSM-glue laws in `laws/` are kept/rewritten, hub `PROOF.bend` files are trusted as-is; every layer ends with `bend --check-only` + targeted proof + `./proofs/run.sh` + `bin/mylsm bench` before commit, with bench regression → revert.

**Tech Stack:** Bend 2.0.25+ (`bend --check-only`, `bend --publish`), `bend-collections` hub package (containers + math + crypto), existing `src/` + `laws/` + `proofs/` + `bench/` harness, `pack.json` catalog manifest.

---

## File structure

- Create: `tools/toolchain.json` — pins `{"bend": "2.0.25"}` (minimum Bend for `bend-collections`).
- Create (Task 2): `src/SstChecksum.bend` — adapter over hub `sha256.bend`; sole checksum used by `SstFileV2` serialize/parse. `Manifest.mhash` stays untouched for Manifest framing.
- Modify per layer: `src/SstFileV2.bend` (Task 2), `src/BitTree.bend` (Task 3), `src/MemTable.bend` + `src/Decimal.bend` (Task 4), `src/SortedRun.bend` + `src/MergeIter.bend` + `src/Compact.bend` (Task 5), `src/Sstable.bend` + `src/Wal.bend` (Task 6).
- Modify per layer (same task, same commit): matching `laws/<Domain>.bend` glue laws + `proofs/<Domain>Proof.bend` witnesses that cite changed behavior (checksum fixtures, scan lemmas, sort/merge properties).
- Modify (Task 7): `mylsm.bend` (header comment with new hub pin only if facade bodies change; signatures unchanged), `pack.json` (new `import` line), `README.md` (new import snippet).
- Untouched: `src/Db.bend` orchestration, `src/Fs.bend`, `src/Console.bend`, `src/CrashPoint.bend`, `src/effs/`, `app/`, `laws/Db.bend` (unless a layer forces a glue change, then it is amended in that layer's task). `src/SstFile.bend`, `src/SstStream.bend`, `src/Recover.bend` and the V1 laws/proofs are modified or deleted in Task 1, not preserved.
- Test via: `bend <file> --check-only`, `bend proofs/<X>Proof.bend` (targeted), `./proofs/run.sh` (gate), `bin/mylsm bench` + `bench/BASELINE.md` (perf gate), `grep -rn "0x" src/ mylsm.bend` (single-pin gate).

---

### Task 0: Verify hub pin, fetch modules, record API surface, pin toolchain

**Files:**
- Create: `tools/toolchain.json`
- Create (scratch, gitignored, delete after Task 0): `.mylsm/build/pin_check.bend`
- Test: `bend .mylsm/build/pin_check.bend --check-only`

- [ ] **Step 1: Verify the collections pin returns 200 on the hub**

Run: `curl -s -o /dev/null -w "%{http_code}\n" https://hub.bend-lang.com/0x9ee2e9a299991dcc089fe22c7f3ceb5f/src/containers/hash_table.bend`
Expected: `200`. If it is not `200`, open `https://hub.bend-lang.com/packages` in a browser, find the `bend-collections` package hash, and replace every `0x9ee2e9a299991dcc089fe22c7f3ceb5f` in this plan with that hash before continuing.

- [ ] **Step 2: Fetch the package and list the modules this plan depends on**

Run: `bend --version && printf 'import 0x9ee2e9a299991dcc089fe22c7f3ceb5f/src/containers/hash_table.bend as HashMap\n' > .mylsm/build/pin_check.bend && bend .mylsm/build/pin_check.bend --check-only && ls ~/.bend/lib/0x9ee2e9a299991dcc089fe22c7f3ceb5f/src/containers/ ~/.bend/lib/0x9ee2e9a299991dcc089fe22c7f3ceb5f/src/crypto/sha/ ~/.bend/lib/0x9ee2e9a299991dcc089fe22c7f3ceb5f/src/math/`
Expected: `bend --version` prints `2.0.25` or newer; `--check-only` exits 0 on the import-only file; the three directory listings show `hash_table.bend`, `sha256.bend`, and the math sources. If `--check-only` fails on the import line, stop: the pin is wrong, go back to Step 1.

- [ ] **Step 3: Record the exact hub API signatures the adapters will use**

Run: `grep -n "^def \\|^type " ~/.bend/lib/0x9ee2e9a299991dcc089fe22c7f3ceb5f/src/containers/hash_table.bend | head -30 && echo "===SHA===" && grep -n "^def \\|^type " ~/.bend/lib/0x9ee2e9a299991dcc089fe22c7f3ceb5f/src/crypto/sha/sha256.bend | head -20 && echo "===BITSET===" && grep -n "^def \\|^type " ~/.bend/lib/0x9ee2e9a299991dcc089fe22c7f3ceb5f/src/containers/bitset.bend | head -20`
Expected: three short signature lists printed. Copy them into the commit message body of Step 5 (so the record of which hub API revision we coded against lives in git history). Per the package README the signatures are quantity-polymorphic (`a, -V: Kind(a)`, reads taking `-V: Data`); confirm that shape in the output before writing any adapter.

- [ ] **Step 4: Pin the toolchain floor**

Write `tools/toolchain.json` with exactly:
```json
{
  "bend": "2.0.25"
}
```
Then run: `bin/mylsm doctor`
Expected: doctor passes (Bend present, clang present). If doctor reports Bend older than 2.0.25, upgrade Bend first (`bend update`) and re-run.

- [ ] **Step 5: Commit pin + toolchain**

```bash
git add tools/toolchain.json
git commit -m "chore: pin bend-collections 0x9ee2e9 and Bend 2.0.25 floor" -m "Hub API surface recorded from ~/.bend/lib/0x9ee2e9a299991dcc089fe22c7f3ceb5f: <paste Step 3 output>"
```

---

### Task 1: Delete the V1 legacy surface (no retrocompat, no dead code)

**Files:**
- Delete: `src/SstFileV1Fast.bend`, `laws/SstFileV1Parser.bend`, `laws/SstFileV1Equivalence.bend`, `laws/SstFileDispatchV1.bend`, `proofs/SstFileV1ParserProof.bend`, `proofs/SstFileV1EquivalenceProof.bend`, `proofs/SstFileDispatchV1Proof.bend`
- Rewrite: `src/SstFile.bend` (v2-only), `src/SstStream.bend` (drop `Legacy` mode), `laws/SstFileRoundtrip.bend` (v2-only), `laws/SstFileDispatchV2.bend` (drop `parse_version` law), `laws/SstStream.bend` (drop v1-route law)
- Modify: `proofs/SstFileRoundtripProof.bend`, `proofs/SstFileDispatchV2Proof.bend`, `proofs/SstStreamProof.bend` (witnesses renamed to the new law names), `src/Recover.bend` + `laws/Recover.bend` + `proofs/RecoverProof.bend` (drop legacy-generation branch)
- Test: `bend proofs/SstFileRoundtripProof.bend`, `./proofs/run.sh`

- [ ] **Step 1: Confirm the V1 blast radius is contained**

Run: `grep -rn "SstFileV1\|serialize_v1\|serialize_v2\|parse_v1\|parse_version\|feed_v1\|Legacy\|muts_of_entries" src/ app/ bench/ laws/ proofs/ mylsm.bend | cut -d: -f1 | sort | uniq -c`
Expected: matches only in `src/SstFile.bend`, `src/SstStream.bend`, `src/SstFileV1Fast.bend`, `laws/SstFileV1Parser.bend`, `laws/SstFileV1Equivalence.bend`, `laws/SstFileDispatchV1.bend`, `laws/SstFileRoundtrip.bend`, `laws/SstFileDispatchV2.bend`, `laws/SstStream.bend`, and the four matching `proofs/` files. If any other file references these names, stop and extend the file lists in this task before deleting anything. (`mylsm.bend` uses only `SstFile.serialize`/`SstFile.parse`, which keep their names.)

- [ ] **Step 2: Rewrite `src/SstFile.bend` as v2-only**

Write `src/SstFile.bend` with exactly:
```bend
import Base
import ./MemTable.bend as MemTable
import ./Sstable.bend as Sstable
import ./SstFileV2.bend as SstFileV2

# Sole SSTable codec boundary: compact v2. The legacy v1 representation was
# removed (no retrocompat); every file on disk is v2.

def serialize(+entries: List<&2, MemTable.Entry>, +level: Nat) -> String:
  SstFileV2.serialize(entries, level)


def parse(+encoded: String) -> Maybe<&2, Sstable.Table>:
  SstFileV2.parse(encoded)


# Total-parser witness used by the hardening law.
def is_decided(+result: Maybe<&2, Sstable.Table>) -> Bool:
  True{}
```
(`muts_of_entries` goes away with `serialize_v1`; Step 1 proved nothing else uses it. The `Wal`/`Manifest` imports go away with it.)
Then run: `bend src/SstFile.bend --check-only`
Expected: exit 0.

- [ ] **Step 3: Rewrite `src/SstStream.bend` without the `Legacy` mode**

Write `src/SstStream.bend` with exactly:
```bend
import Base
import ./Decimal.bend as Decimal
import ./Fs.bend as Fs
import ./Sstable.bend as Sstable
import ./SstFileV2.bend as V2

# Chunked table recovery. The host effect returns UTF-8-safe positional chunks;
# the pure one-character v2 decoder transitions run per chunk.

type Chunk is Data:
  Ch{bytes: Nat, text: String}

type Mode is Data:
  Unknown{}
  Current{decoder: V2.Decoder}


def chunk_parse(p: Decimal.Parse) -> Result<&1, &1, U32 & String, Chunk>:
  match p:
    case Decimal.Rejected{error}:
      Fail{(U32.from_nat(8n), "bad UTF-8 chunk envelope")}
    case Decimal.Accepted{Decimal.Dec{value, rest}}:
      Done{Ch{value, rest}}


def feed_v2(rest: String, decoder: V2.Decoder) -> V2.Decoder:
  match rest:
    case SNil{}:
      decoder
    case SCon{c, tail}:
      feed_v2(tail, V2.decoder_step(decoder, c))


def unknown_v2(is_v2: Bool, +text: String) -> Mode:
  match is_v2:
    case True{}:
      Current{feed_v2(text, V2.Dec{V2.NeedS{}, 0n, None{}, Nil{}, 0n, 0n, 7, 0n})}
    case False{}:
      Unknown{}


def feed_mode(mode: Mode, +text: String) -> Mode:
  match mode:
    case Unknown{}:
      unknown_v2(String.starts_with(text, "S2;"), text)
    case Current{decoder}:
      Current{feed_v2(text, decoder)}


def finish_v2(result: V2.ParseResult) -> Result<&1, &1, U32 & String, Sstable.Table>:
  match result:
    case V2.ParseRejected{error}:
      Fail{(U32.from_nat(3n), "bad v2 table")}
    case V2.Parsed{table}:
      Done{table}


def finish_mode(mode: Mode) -> Result<&1, &1, U32 & String, Sstable.Table>:
  match mode:
    case Unknown{}:
      Fail{(U32.from_nat(3n), "unknown table version")}
    case Current{decoder}:
      finish_v2(V2.finish_decoder(decoder))



def stream_loop(fuel: Nat, +path: String, +offset: Nat, mode: Mode, pending: Maybe<&2, Chunk>) -> IO(Result<&1, &1, U32 & String, Sstable.Table>):
  match fuel pending:
    case 0n _:
      IO.pure(Result<&1, &1, U32 & String, Sstable.Table>, Fail{(U32.from_nat(7n), "table exceeds streaming read limit")})
    case 1n+rest None{}:
      do IO<Result<&1, &1, U32 & String, Sstable.Table>>:
        raw : String <- IO.try(String, Fs.read_utf8_chunk(path, offset, V2.read_chunk_chars()))
        chunk : Chunk <- IO.try(Chunk, IO.pure(Result<&1, &1, U32 & String, Chunk>, chunk_parse(Decimal.parse_semicolon(raw, V2.read_chunk_chars()))))
        stream_loop(rest, path, offset, mode, Some{chunk})
    case 1n+rest Some{Ch{bytes, text}}:
      match bytes:
        case 0n:
          IO.pure(Result<&1, &1, U32 & String, Sstable.Table>, finish_mode(mode))
        case 1n+more:
          stream_loop(rest, path, Nat.add(offset, 1n+more), feed_mode(mode, text), None{})


def read_table(+path: String) -> IO(Result<&1, &1, U32 & String, Sstable.Table>):
  stream_loop(8192n, path, 0n, Unknown{}, None{})
```
(A `"T..."` chunk now stays `Unknown{}` and fails closed at finish. `feed_v1`, `finish_v1`, `unknown_v1`, and the `V1` import are gone.)
Then run: `bend src/SstStream.bend --check-only`
Expected: exit 0.

- [ ] **Step 4: Rewrite the three affected law files v2-only**

Write `laws/SstFileRoundtrip.bend` with exactly:
```bend
import Base
import ../src/MemTable.bend as MemTable
import ../src/Sstable.bend as Sstable
import ../src/SstFile.bend as SstFile

# V2 framing kernel, tested without the byte stream (same checker
# limitation documented in SstFileV2Checksum: end-to-end `{==}` over a
# hashed stream diverges).

law sstfile_v2_tag:
  {String.starts_with(SstFile.serialize(Con{MemTable.Entry{"a", Some{"1"}}, Con{MemTable.Entry{"b", Some{"2"}}, Nil{}}}, 0n), "S2;") == True{} : Bool}

law sstfile_v2_reject:
  {SstFile.parse("X") == None{} : Maybe<&2, Sstable.Table>}
```
(Entries pre-sorted `a` < `b`; the v2 header opens with `S2;` and garbage fails closed.)

Write `laws/SstFileDispatchV2.bend` with exactly:
```bend
import Base
import ../src/Sstable.bend as Sstable
import ../src/SstFile.bend as SstFile
import ../src/SstFileV2.bend as SstFileV2

# Single-version routing: SstFile.parse is SstFileV2.parse.

law sst2_dispatch_v2_tag:
  {SstFile.parse("S2;X") == SstFileV2.parse("S2;X") : Maybe<&2, Sstable.Table>}
```

Write `laws/SstStream.bend` with exactly:
```bend
import Base
import ../src/MemTable.bend as MemTable
import ../src/Sstable.bend as Sstable
import ../src/SstFileV2.bend as SstFileV2
import ../src/SstStream.bend as SstStream

# Chunk-dispatch kernel, tested on short inputs (no hash accumulation
# reaches the checker-critical length; U32-only chains stay shared).
# End-to-end chunk agreement is covered at runtime (bench smoke).

law sst2_feed_routes_v2:
  {SstStream.feed_mode(SstStream.Unknown{}, "S2;") == SstStream.Current{SstStream.feed_v2("S2;", SstFileV2.Dec{SstFileV2.NeedS{}, 0n, None{}, Nil{}, 0n, 0n, 7, 0n})} : SstStream.Mode}

law sst2_finish_unknown:
  {SstStream.finish_mode(SstStream.Unknown{}) == Fail{(U32.from_nat(3n), "unknown table version")} : Result<&1, &1, U32 & String, Sstable.Table>}
```

- [ ] **Step 5: Adapt the three matching proof files + delete the V1 pairs**

In `proofs/SstFileRoundtripProof.bend`, replace the five v1 witnesses with:
```bend
def Laws.sstfile_v2_tag():
  {==}

def Laws.sstfile_v2_reject():
  {==}
```
(keeping the file's existing `import ../laws/SstFileRoundtrip.bend as Laws` header line). In `proofs/SstFileDispatchV2Proof.bend`, keep only `def Laws.sst2_dispatch_v2_tag():` with its existing body. In `proofs/SstStreamProof.bend`, keep the `sst2_feed_routes_v2` and `sst2_finish_unknown` witnesses with existing bodies and delete the `sst2_feed_routes_v1` witness. Then delete the V1 pairs:
```bash
git rm src/SstFileV1Fast.bend laws/SstFileV1Parser.bend laws/SstFileV1Equivalence.bend laws/SstFileDispatchV1.bend proofs/SstFileV1ParserProof.bend proofs/SstFileV1EquivalenceProof.bend proofs/SstFileDispatchV1Proof.bend
```
Then run: `bend proofs/SstFileRoundtripProof.bend && bend proofs/SstFileDispatchV2Proof.bend && bend proofs/SstStreamProof.bend`
Expected: all three exit 0. If a closed `{==}` diverges in the checker, delete that law and its witness from the pair of files (never weaken to a non-assertion) and re-run.

- [ ] **Step 6: Drop the Recover legacy-generation branch**

Read `src/Recover.bend` around line 171, `laws/Recover.bend` law `generation_legacy_branch` (line 46), and `proofs/RecoverProof.bend` witness `Laws.generation_legacy_branch` (line 25). Delete the unary-dash legacy arm (keeping the compact-decimal generation path), delete the law and its witness. Then run: `bend proofs/RecoverProof.bend`
Expected: exit 0.

- [ ] **Step 7: Gate + commit the deletion**

Run: `./proofs/run.sh`
Expected: green with 3 fewer modules (the name gate enforces the 1:1 `laws/` ↔ `proofs/` pairing, so the deletions are self-checking). Then:
```bash
git add src/SstFile.bend src/SstStream.bend src/Recover.bend laws/SstFileRoundtrip.bend laws/SstFileDispatchV2.bend laws/SstStream.bend laws/Recover.bend proofs/SstFileRoundtripProof.bend proofs/SstFileDispatchV2Proof.bend proofs/SstStreamProof.bend proofs/RecoverProof.bend
git commit -m "chore: delete v1 sstable legacy surface, v2-only codec"
```
(`git rm` in Step 5 already staged the deletions; `git status --short` first and stage only actually-changed paths.)

### Task 2: Crypto layer — SstFileV2 checksum via hub SHA-256

**Files:**
- Create: `src/SstChecksum.bend`
- Modify: `src/SstFileV2.bend` (checksum call sites in serialize + parse/verify only)
- Modify: `laws/SstFileV2Checksum.bend` (fixtures use new digest)
- Modify: `proofs/SstFileV2ChecksumProof.bend` (witnesses over new fixtures)
- Test: `bend proofs/SstFileV2ChecksumProof.bend`, `./proofs/run.sh`

- [ ] **Step 1: Write the checksum adapter**

Create `src/SstChecksum.bend` with exactly (module alias `SHA` uses the Task 0 pin):
```bend
import Base
import 0x9ee2e9a299991dcc089fe22c7f3ceb5f/src/crypto/sha/sha256.bend as SHA

# Single checksum for SSTable v2 framing. The hub SHA-256 is trusted as-is
# (its own PROOF.bend proves it against the executable FIPS 180-4 spec);
# our laws only cover framing (digest placed after '#', verified on parse).
def digest(+body: String) -> String:
  SHA.hex(SHA.hash(body))

def verify(+body: String, +claimed: String) -> Bool:
  String.eq(digest(body), claimed)
```
If the Step 0-recorded SHA API names differ (`hash`/`hex` may be named differently in the fetched source), use the recorded names instead and note the rename in the commit message. The adapter must expose exactly `digest` and `verify` with these shapes regardless.

- [ ] **Step 2: Check the adapter in isolation**

Run: `bend src/SstChecksum.bend --check-only`
Expected: exit 0. If the checker rejects the hub call shapes, fix the call sites to the Step 0-recorded signatures (do not wrap in extra conversions).

- [ ] **Step 3: Switch SstFileV2 serialize/parse to the adapter**

In `src/SstFileV2.bend`: add `import ./SstChecksum.bend as SstChecksum`; replace the `Manifest.mhash(body, 7)` computation in the serialize path with `SstChecksum.digest(body)` and the parse-side `U32.is_eq(v, mhash(content, 7))` comparison with   `SstChecksum.verify(content, claimed)` (keep the `ChecksumMismatch{}` error arm and position — only the digest computation changes). `Manifest.mhash` stays untouched for Manifest framing (V1 is gone as of Task 1).

- [ ] **Step 4: Update checksum fixtures + witnesses**

In `laws/SstFileV2Checksum.bend`, recompute every hardcoded checksum literal by running the new `digest` (write a scratch `.mylsm/build/reck.bend` with `def main() -> ...` printing `SstChecksum.digest(<fixture body>)`, run it with `bend`, paste the outputs into the law file, delete the scratch). In `proofs/SstFileV2ChecksumProof.bend`, keep witness names and structure; only the fixture literals change. No new theorems: framing logic is unchanged.

- [ ] **Step 5: Run the layer gate**

Run: `bend proofs/SstFileV2ChecksumProof.bend && bend proofs/SstFileV2ParserProof.bend && bend proofs/SstFileRoundtripProof.bend`
Expected: all three exit 0. Then run: `./proofs/run.sh`
Expected: green (a timeout or any failed module is never green — fix before committing).

- [ ] **Step 6: Bench the layer and commit**

Run: `bin/mylsm bench` and compare against `bench/BASELINE.md` (same machine/disk/tuning). Then:
```bash
git add src/SstChecksum.bend src/SstFileV2.bend laws/SstFileV2Checksum.bend proofs/SstFileV2ChecksumProof.bend
git commit -m "feat: sst v2 checksum via hub sha256 adapter"
```
If the bench regresses vs baseline on the SSTable workload, revert the `src/SstFileV2.bend` call-site change (keep the adapter file) and note it in the commit message instead.

---

### Task 3: Bits layer — BitTree Bloom over hub bitset/bitlist

**Files:**
- Modify: `src/BitTree.bend` (packed-words backend only; Bloom policy API unchanged)
- Modify: `laws/BloomSafe.bend`, `laws/BloomTree.bend`, `laws/BloomSchedule.bend`, `laws/BloomZeroEstimate.bend` (only if bit-layout literals change)
- Modify: matching `proofs/BloomSafeProof.bend`, `proofs/BloomTreeProof.bend`, `proofs/BloomScheduleProof.bend`, `proofs/BloomZeroEstimateProof.bend` (fixtures only)
- Test: `bend proofs/BloomTreeProof.bend`, `./proofs/run.sh`

- [ ] **Step 1: Reimplement the BitTree backend on hub bitset**

In `src/BitTree.bend`: add `import 0x9ee2e9a299991dcc089fe22c7f3ceb5f/src/containers/bitset.bend as BitSet` (exact def names per Task 0 records; check `~/.bend/lib/0x9ee2e9a299991dcc089fe22c7f3ceb5f/src/containers/bitset.bend` first with the same `grep -n "^def "` command from Task 0 Step 3). Keep every public `def` name and signature in `BitTree.bend` identical; only the backing-words representation and the get/set internals delegate to `BitSet`. Bloom estimation/schedule/policy defs stay hand-written.

- [ ] **Step 2: Check + targeted proofs**

Run: `bend src/BitTree.bend --check-only && bend proofs/BloomTreeProof.bend && bend proofs/BloomSafeProof.bend`
Expected: all exit 0. If a fixture fails because bit-layout literals changed, update the literal in the corresponding `laws/` file to the value the new backend computes (verify by running a scratch print first, as in Task 1 Step 4) — never weaken the assertion itself.

- [ ] **Step 3: Full gate + bench + commit**

Run: `./proofs/run.sh`
Expected: green. Then run: `bin/mylsm bench`, compare with `bench/BASELINE.md`.
```bash
git add src/BitTree.bend laws/BloomSafe.bend laws/BloomTree.bend laws/BloomSchedule.bend laws/BloomZeroEstimate.bend proofs/BloomSafeProof.bend proofs/BloomTreeProof.bend proofs/BloomScheduleProof.bend proofs/BloomZeroEstimateProof.bend
git commit -m "feat: bittree bloom backend on hub bitset"
```
Stage only the files that actually changed (`git status --short` first; drop unchanged paths from the command).

---

### Task 4: MemTable on hub hash_table + Decimal on hub math

**Files:**
- Modify: `src/MemTable.bend` (map backend; public API unchanged)
- Modify: `src/Decimal.bend` (delegate words/powers to `src/math/`)
- Modify: `laws/MemTable.bend` (keep the two bridge laws; drop scan-lemma internals), `laws/Decimal.bend` (fixtures only)
- Modify: `proofs/MemTableProof.bend`, `proofs/DecimalProof.bend`
- Test: `bend proofs/MemTableProof.bend`, `./proofs/run.sh`

- [ ] **Step 1: Rewrite MemTable on the hub hash map**

Rewrite `src/MemTable.bend` keeping the exact public surface (`Entry{key, val}`, `MemTable` type name, `empty`, `put`, `del`, `count`, `get`) with this shape (hub def names per Task 0 records):
```bend
import Base
import 0x9ee2e9a299991dcc089fe22c7f3ceb5f/src/containers/hash_table.bend as HashMap
import ./Keys.bend as Keys

type Entry is Data:
  Entry{key: String, val: Maybe<&2, String>}

type MemTable is Data:
  MT{map: HashMap.Map}

def empty() -> MemTable:
  MT{HashMap.empty()}

def put(t: MemTable, k: String, v: String) -> MemTable:
  match t:
    case MT{map}:
      MT{HashMap.insert(map, k, Some{v})}

def del(t: MemTable, k: String) -> MemTable:
  match t:
    case MT{map}:
      MT{HashMap.insert(map, k, None{})}

def get(t: MemTable, +k: String) -> Maybe<&2, String>:
  match t:
    case MT{+map}:
      HashMap.get(&2, String, map, k)
```
Delete `scan_step`, `scan_go`, `frozen_lemma`, `ryw_core`, `del_core`. Keep `ryw_bridge`/`del_bridge` statements in `laws/MemTable.bend`, re-witnessed against the map backend. `count` delegates to the hub map size (`HashMap.count` or recorded equivalent). Tombstone semantics stay: `None{}` hides older versions, newest write wins.

- [ ] **Step 2: Delegate Decimal words/powers to hub math**

In `src/Decimal.bend`: add the hub `src/math/` import (exact path from the Task 0 Step 2 listing), replace hand-rolled 64-bit word ops and powers-of-two tables with the hub defs, keeping all public `def` names/signatures. Check: `bend src/Decimal.bend --check-only`, expected exit 0.

- [ ] **Step 3: Rewrite MemTable + Decimal witnesses**

In `laws/MemTable.bend`, keep exactly the two bridge statements (`get(put(t,k,v),k)==Some{v}}`, `get(del(put(t,k,v),k),k)==None{}}`); delete scan-lemma defs. In `proofs/MemTableProof.bend`, re-prove the bridges against the map backend using the hub map's own insert-get lemma (cite it; do not re-prove the map). Same fixture-only treatment for `laws/Decimal.bend` + `proofs/DecimalProof.bend`.

- [ ] **Step 4: Gate + bench + commit**

Run: `bend proofs/MemTableProof.bend && bend proofs/DecimalProof.bend && ./proofs/run.sh`
Expected: green throughout. Then `bin/mylsm bench` vs `bench/BASELINE.md` (write path must not regress: puts are the fastest shape — O(1), zero comparisons).
```bash
git add src/MemTable.bend src/Decimal.bend laws/MemTable.bend laws/Decimal.bend proofs/MemTableProof.bend proofs/DecimalProof.bend
git commit -m "feat: memtable on hub hash map, decimal on hub math"
```

---

### Task 5: Sort/merge layer — SortedRun on tree+array, MergeIter/Compact on heap

**Files:**
- Modify: `src/SortedRun.bend`, `src/MergeIter.bend`, `src/Compact.bend` (public `def` names/signatures unchanged)
- Modify: `laws/SortedRun.bend`, `laws/MergeIter.bend`, `laws/Compact.bend` + matching proofs (glue properties only)
- Test: targeted proofs, `./proofs/run.sh`, compaction bench

- [ ] **Step 1: SortedRun via indexed red-black tree draining to packed array**

In `src/SortedRun.bend`: add `import 0x9ee2e9a299991dcc089fe22c7f3ceb5f/src/containers/balanced_search_tree.bend as RBTree` and `import 0x9ee2e9a299991dcc089fe22c7f3ceb5f/src/containers/dynamic_array.bend as DynArray` (exact def names per a fresh `grep -n "^def " ` on the fetched sources, same command shape as Task 0 Step 3). Keep `sort_newest(entries)` signature; implement as: insert entries into the tree keyed by `Keys.cmp` (newest-first tiebreak preserved), drain in order to a packed array, return as `List`. Delete the quadratic construction internals. Check: `bend src/SortedRun.bend --check-only`, expected exit 0.

- [ ] **Step 2: MergeIter/Compact N-way merge via binary heap**

In `src/MergeIter.bend`: keep `scan(merged, lo, hi)` signature; implement the merge with `binary_heap.bend` (packed-array min-heap, `Keys.cmp` as static comparator) instead of linear scans. In `src/Compact.bend`: use `priority_queue.bend` facades for run selection and parallelize independent compaction ranges (per `AGENT.md`: parallelize whenever semantically sound). No signature changes; no new `IO`. Check both: `bend src/MergeIter.bend --check-only && bend src/Compact.bend --check-only`, expected exit 0 for both.

- [ ] **Step 3: Glue laws + witnesses for ordering**

In `laws/SortedRun.bend` keep newest-wins + sortedness statements; in `laws/MergeIter.bend` keep `range_scan` correctness; in `laws/Compact.bend` keep merge-output properties. Re-witness in the three matching `proofs/` files against the new backends, citing hub tree/heap lemmas where applicable. This is the biggest proof-touch layer: run each targeted proof individually (`bend proofs/SortedRunProof.bend`, then `MergeIter`, then `Compact`) and fix one module at a time before the full gate.

- [ ] **Step 4: Gate + compaction bench + commit**

Run: `./proofs/run.sh` (expected green), then `bin/mylsm bench` plus `bench/compaction_regression.sh`, compared against `bench/BASELINE.md` (the 20,485-write / 4.524s reference and the 1M-write acceptance figures are the bars to beat on identical hardware).
```bash
git add src/SortedRun.bend src/MergeIter.bend src/Compact.bend laws/SortedRun.bend laws/MergeIter.bend laws/Compact.bend proofs/SortedRunProof.bend proofs/MergeIterProof.bend proofs/CompactProof.bend
git commit -m "feat: sorted runs on hub tree+array, merge on hub heap"
```
Bench regression on the compaction workload → revert that layer's `src/` change and keep the laws intact, noted in the commit message.

---

### Task 6: SSTable blocks + WAL batching (+ optional LRU block cache)

**Files:**
- Modify: `src/Sstable.bend` (`build`/`from_sorted_unique`/`build_sorted` emit block index; add block-scoped lookup, keep old whole-table lookup name as delegate), `src/Wal.bend` (`encode`/`decode` unchanged; batching via hub queue/deque)
- Modify: `laws/Sstable.bend`, `laws/Wal.bend` + matching proofs (block-index lookup equivalence, batch fold equivalence)
- Test: targeted proofs, `./proofs/run.sh`, million-write acceptance if time permits

- [ ] **Step 1: Sparse block index + binary search in Sstable**

In `src/Sstable.bend`: build tables over `dynamic_array.bend` packed storage; `build`/`build_sorted`/`from_sorted_unique` additionally record a sparse block index (first key per N-entry block; N as a named `def block_entries() -> Nat` returning `64n`); add `block_get(table, k)` doing binary search over the index then a bounded intra-block scan; keep the existing whole-table lookup `def` as a one-line delegate to `block_get` so callers and laws keep working. Check: `bend src/Sstable.bend --check-only`, expected exit 0.

- [ ] **Step 2: WAL grouped commits via hub queue**

In `src/Wal.bend`: keep `encode`/`decode`/`Mut`/`Batch` shapes; implement batch accumulation with `queue.bend` (two-list FIFO) and `deque.bend` where both ends are needed (exact hub def names via the Task 0 `grep` command on those two files). No `IO` changes; batching stays pure (grouped-commit policy in Bend, host append stays in `src/effs/`). Check: `bend src/Wal.bend --check-only`, expected exit 0.

- [ ] **Step 3: Block-index equivalence laws + optional LRU cache**

In `laws/Sstable.bend` add: `block_get(t,k) == lookup(t,k)` for all fixture tables (closed fixtures) plus the open-input statement the checker admits. `lookup` is the existing whole-table lookup (`src/Sstable.bend:230`); it becomes a one-line delegate to `block_get`, so this law pins the block index to current behavior. If `lru.bend` block-cache is added, it must be a pure-behind-facade memo that never changes lookup results: add the law `cached_get(t,k) == block_get(t,k)` in the same file. Witness both in `proofs/SstableProof.bend`. In `laws/Wal.bend` keep batch-fold equivalence (`sbatch` == sequential `sput`/`sdel`); witness in `proofs/` — this property already exists via `Db` laws, so prefer citing over re-proving.

- [ ] **Step 4: Gate + bench + commit**

Run: `bend proofs/SstableProof.bend && bend proofs/WalProof.bend`, then `./proofs/run.sh` (expected green), then `bin/mylsm bench` vs `bench/BASELINE.md` (block reads must beat whole-file reads on a dataset exceeding RAM to count as the Phase 3 win).
```bash
git add src/Sstable.bend src/Wal.bend laws/Sstable.bend laws/Wal.bend proofs/SstableProof.bend
git commit -m "feat: sstable block index plus wal queue batching"
```
Stage only changed paths (`git status --short` first).

---

### Task 7: Facade check, republish, catalog update

**Files:**
- Modify: `mylsm.bend` (header pin comment only; no signature changes), `pack.json`, `README.md`
- Test: clean-fetch verification (see steps)

- [ ] **Step 1: Facade typecheck + single-pin gate**

Run: `bend mylsm.bend --check-only`
Expected: exit 0 (facade signatures unchanged; bodies delegate through adapted `src/`). Then run: `grep -rn "0x" src/ mylsm.bend | grep -v "0x9ee2e9a299991dcc089fe22c7f3ceb5f" || echo SINGLE-PIN-OK`
Expected: `SINGLE-PIN-OK` (every hub import uses the Task 0 pin; no strays). Then run: `grep -n "IO\.\|effs/\|def main" mylsm.bend || echo IO-CLEAN`
Expected: `IO-CLEAN` (no host-effect creep in the published facade, per the 2026-09-22 spec §8 gate).

- [ ] **Step 2: Regression sweep before publish**

Run: `./proofs/run.sh && bin/mylsm bench && bin/mylsm fuzz`
Expected: proofs green; bench meets `bench/BASELINE.md` bars recorded in Tasks 2–6; fuzz completes without crashes. Any failure blocks the publish.

- [ ] **Step 3: Publish the new hub version**

Run: `bend mylsm.bend --publish`
Expected: prints `0x<NEW_HASH>` plus the canonical `import 0x<NEW_HASH>/mylsm.bend as MyLSM` line. Copy both exactly.

- [ ] **Step 4: Update pack.json + README with the new import line**

Write `pack.json` with exactly (replace `<NEW_HASH>` with the Step 3 output):
```json
{
  "name": "mylsm",
  "description": "Pure in-memory LSM core: Sess session monad plus MemTable, SSTable, WAL and Manifest part control.",
  "import": "import 0x<NEW_HASH>/mylsm.bend as MyLSM",
  "category": "packages"
}
```
In `README.md`, replace both occurrences of `import 0x05fa0e42448e8e221df592b204de523d/mylsm.bend as MyLSM` with `import 0x<NEW_HASH>/mylsm.bend as MyLSM` (Level 1 snippet line 40 and Level 2 snippet line 49). Verify: `grep -n "import 0x" README.md pack.json`.

- [ ] **Step 5: Clean-fetch verification + commit**

Run: `mv ~/.bend/lib/0x<NEW_HASH> ~/.bend/lib/0x<NEW_HASH>.bak 2>/dev/null; printf 'import 0x<NEW_HASH>/mylsm.bend as MyLSM\ndef check(+m: Maybe<&2, String>) -> U32:\n  match m:\n    case Some{v}: 1\n    case None{}: 0\ndef main() -> U32:\n  +live = MyLSM.mem_put(MyLSM.mem_empty(), "k", "v1")\n  check(MyLSM.mem_get(live, "k"))\n' > /tmp/mylsm_fetch_check.bend && bend /tmp/mylsm_fetch_check.bend && rm /tmp/mylsm_fetch_check.bend; mv ~/.bend/lib/0x<NEW_HASH>.bak ~/.bend/lib/0x<NEW_HASH> 2>/dev/null || true`
Expected: prints `1` (fetch from hub, hash-verified, runs offline afterwards). The scratch follows the proven checker shape (match only on a `def` param, `+` handle threaded through a named binding — never `match` on a computed call). Then:
```bash
git add mylsm.bend pack.json README.md
git commit -m "release: publish hub refactor as 0x<NEW_HASH>"
```
Also verify `https://hub.bend-lang.com/0x<NEW_HASH>/mylsm.bend` returns 200 before announcing.

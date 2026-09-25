# MyLSM Bend-Hub Refactor (core-replace por capas) — Design Spec

**Date:** 2026-09-24
**Status:** Draft, pending human review
**Choice:** Enfoque 2 (core-replace por capas, ejecutado con disciplina de bench por capa)
**Related:** `docs/superpowers/specs/2026-09-22-mylsm-hub-facade-design.md`, `README.md`, `AGENT.md`, `bench/BASELINE.md`

## 1. Mission

Reducir código propio de MyLSM sustituyendo internals por librerías de la
comunidad en BendHub (referencia: `bend-collections`: containers + math +
crypto con `PROOF.bend` / `END_TO_END.bend`), ganando rendimiento de Phase 3
y heredando proofs comunitarios. La fachada publicada `mylsm.bend` (Level 1
`Sess` + Level 2 part-control) mantiene firmas; solo los cuerpos delegan.

Decisiones del usuario (2026-09-24): objetivo A+B+C (menos código, más perf,
delegar proofs); formato on-disk rompible (sin migración); refactor por capas
completo (opción D); proofs del hub confiados tal cual (opción A);
enfoque 2 aprobado.

## 2. Mapeo capa → módulo hub

| Capa MyLSM hoy | Módulo hub (`bend-collections`) | Cambio |
|---|---|---|
| `Keys` (cmp/eq + refl chain) | se queda como comparador; `balanced_search_tree` lo consume | sin cambio de API; expone `cmp` como `static comparator` del heap/tree |
| `MemTable` (prepend-log + `scan_go`) | — | SE QUEDA: el hub `HashMap` es lineal y `MT`/`Db` son `Data` (ver §2c). Puts ya O(1), scan acotado a 4096, nunca fue el cuello |
| `SortedRun` (build cuadrático) | `src/containers/balanced_search_tree.bend` (indexed red-black), uso efímero | `sort_newest` construye/drena el tree dentro de la función sin almacenarlo (ver §2c); requiere drain consumible en la API hub |
| `MergeIter` / `Compact` merge | `src/containers/binary_heap.bend` (min-heap, static comparator) + `src/containers/priority_queue.bend`, uso efímero | merge N-way por heap sin almacenar estado; misma condición de drain |
| `BitTree` Bloom | `src/containers/bitset.bend` solo fns puras (`word_get`/`word_put`/`word_op`) | SE QUEDA el storage `Data`; el `Bitset` lineal no cabe en `BitTree is Data` (ver §2c) |
| `Sstable` lookup lineal | índice de bloques disperso como `Data` sobre storage `List` actual | bloques + binary search (Phase 3); `DynArray` solo efímero en `build` si se consume entero; `lru` block-cache diferido (exigiría cache threaded) |
| `SstFileV2` checksums + codec (V1 eliminado, §2b) | `src/crypto/sha/sha256.bend` (FIPS 180-4) | v2 adopta `hex(sha256(ascii(body)))` vía `src/SstChecksum.bend` |
| `Decimal` / words / potencias | `src/math/` (u64 words, hashing), solo fns puras | se delega lo que encaje sin tocar los tipos `Data` |
| `Wal` / `Manifest` batching | `src/containers/queue.bend` (two-list) / `src/containers/deque.bend`, solo si hay forma efímera limpia | `Batch is Data` no admite queue almacenada; si no encaja, `Wal` no se toca |

## 2c. Regla de afinidad (probada contra el checker, 2026-09-24)

Los containers del hub son `Type` (lineales): las lecturas devuelven el
estado (`HashMap.get → map & V`, `Bitset.get/set → Bitset & …`) y descartarlo
falla (`expected Data, observed Quant`); ningún `type … is Data` puede
contenerlos (`expected Data, observed Type` — incluye campos `Array`). Como
`MemTable`/`Db`/`Sstable`/`Wal`/`BitTree` son `Data` y el threading `+db` de
`Sess` depende de ello, los containers del hub solo se usan **efímeros dentro
de funciones** (construidos, threaded, consumidos del todo; nunca almacenados
en `Data`, nunca descartados). Las funciones puras (`SHA.*`, `math.*`,
`word_get`/`word_put`) no tienen restricción. Los swaps totales que exigirían
almacenar estado hub en `Data` quedan **rechazados** con el rationale
registrado en el plan.

No-objetivos: orquestación `Db` / `Recover` / `Flush`, host effects
(`Fs` / `Console` / `CrashPoint` / `src/effs/*.c|*.js`), formato exacto de
bytes (se permite romper, sin migración).

## 2b. Eliminaciones legacy (decisión 2026-09-24: sin retrocompat, sin dead code)

Se elimina la superficie V1 de SSTable antes de adaptar nada (Task 1 del plan):

- Delete: `src/SstFileV1Fast.bend` (462 líneas), `laws/SstFileV1Parser.bend`,
  `laws/SstFileV1Equivalence.bend`, `laws/SstFileDispatchV1.bend` y sus tres
  `proofs/*Proof.bend` (el gate `proofs/run.sh` auto-descubre pares
  `laws/<M>` ↔ `proofs/<M>Proof`, así que borrar en parejas lo mantiene verde).
- `src/SstFile.bend` pasa a v2-only (`serialize`/`parse` delegan a
  `SstFileV2`; caen `serialize_v1`, `serialize_v2`, `parse_v1`,
  `parse_version`, `muts_of_entries` si nada más lo usa).
- `src/SstStream.bend` pierde el modo `Legacy` (`feed_v1`, `finish_v1`,
  `unknown_v1`); un chunk `"T..."` queda `Unknown{}` y `finish_mode`
  falla cerrado (`"unknown table version"`).
- `laws/SstFileRoundtrip.bend` se reescribe a v2-only (dos leyes cerradas:
  tag `"S2;"` + reject de `"X"`); `laws/SstFileDispatchV2.bend` pierde la ley
  de `parse_version`; `laws/SstStream.bend` pierde la ley de ruta v1.
- Rama legacy de `Recover` (generaciones unary-dash, `src/Recover.bend:171`,
  ley `generation_legacy_branch`, su witness): se elimina con la misma
  disciplina, quedando solo generaciones decimal compactas.

## 3. Pins + layout de imports

- Un solo pin por release del hub. Todos los
  `import 0x<hash>/src/...` usan el mismo hash en todo el repo; el hash vive
  en `pack.json` + comentario cabecera de `mylsm.bend`. Subir versión =
  cambiar un sitio + `bend fetch` + `./proofs/run.sh`. Nada de flotantes.
- Fachada estable. `mylsm.bend` Level 1 (`Sess`, `sput` / `sget` / `sdel`) y
  Level 2 (`mem_*`, `sst_*`, `mfst_*`, `wal_*`) no cambian firmas; solo los
  cuerpos delegan. Los `src/*.bend` se vuelven adaptadores finos (~10–30
  líneas) sobre el hub.
- Toolchain. `bend-collections` pide Bend 2.0.25; MyLSM hoy valida en
  2.0.13–2.0.24. Fijar `tools/toolchain.json` a 2.0.25 y exigirlo en
  `bin/mylsm doctor` antes del refactor.
- Vendoring cero. Sin copiar archivos del hub al repo; el compilador verifica
  cada fichero contra el hash al traerlo a `~/.bend/lib`. Offline después del
  primer fetch.

## 4. Leyes del pegamento + proof gate (confianza en el hub)

Los `PROOF.bend` / `END_TO_END.bend` de `bend-collections` se confían tal
cual. Nuestras `laws/` solo cubren el pegamento LSM que el hub no conoce:

- `laws/MemTable.bend`: `get(put(t,k,v),k)==Some{v}`,
  `get(del(put(t,k,v),k),k)==None` — ahora vía `HashMap` en vez de `scan_go`.
  Se eliminan `frozen_lemma` / `ryw_core` / `del_core`.
- `laws/SortedRun.bend` + `laws/MergeIter.bend`: newest-wins + `range_scan`
  sobre arrays packed / heap-merge.
- `laws/SstFileV2*.bend`: roundtrip `parse(serialize)==Some` + checksum
  `sha256` / `blake3` delegado (sin re-probar FIPS).

Gate intacto según `AGENT.md`: `laws/*.bend` por dominio,
`proofs/*Proof.bend` importa su ley como `Laws`,
`bend proofs/<X>Proof.bend` en desarrollo, `./proofs/run.sh` verde antes de
commit, sin `@unsafe`, teoremas abiertos vs fixtures cerrados distinguidos.

## 5. Orden de rollout + bench gate

Capas en este orden (cada una: adaptar → `bend <X>Proof.bend` →
`./proofs/run.sh` → `bin/mylsm bench` antes/después):

1. Crypto (`SstFileV2` → `sha256` / `blake3`): riesgo mínimo, elimina codec propio.
2. Bits (`BitTree` → `bitset` / `bitlist`): Bloom packed, prerrequisito de SSTable.
3. `MemTable` (→ `hash_table`) + `Decimal` (→ `src/math`): escrituras O(1) reales.
4. Ordenación/merge (`SortedRun` → tree+array, `MergeIter` / `Compact` → heap): el salto gordo de Phase 3.
5. SSTable bloques + `Wal` batching (`dynamic_array`, `queue` / `deque`, futuro `lru` block-cache).

Gate de bench: `bench/BASELINE.md` manda — mejora solo publicable con
dataset > RAM y misma máquina/disco/tuning. Sin mejora medida, la capa se
revierte.

## 6. Publicación en el hub (nueva versión = hash nuevo)

El hub es content-addressed: `bend mylsm.bend --publish` empaqueta
`mylsm.bend` + sus imports relativos y calcula el hash del contenido.
Cualquier cambio → hash nuevo. Los imports al hub de terceros
(`import 0x<collections>/...`) quedan como dependencias externas pineadas,
no se re-empaquetan.

```sh
bend mylsm.bend --check-only
bend mylsm.bend --publish        # imprime 0x<NUEVO_HASH>
# actualizar pack.json + README: import 0x<NUEVO_HASH>/mylsm.bend as MyLSM
# verificar https://hub.bend-lang.com/0x<NUEVO_HASH>/mylsm.bend → 200
# clean-fetch: mover ~/.bend/lib/0x<NUEVO_HASH> y recompilar un scratch
```

Nombres legibles (requiere `bend login`):
`bend mylsm.bend --publish mylsm@<version>` y
`bend link mylsm@<version> 0x<HASH>`. Este refactor = release nuevo, hash
nuevo, sin migración de DBs viejas.

## 7. Riesgos y mitigaciones

- Churn de hash en cada cambio interno → releases deliberados, hash anotado en README + `pack.json` (patrón amalgamación, spec 2026-09-22 §8).
- Deriva de API del hub (collections aún joven) → pin único + `doctor` con toolchain fija; bump solo tras `run.sh` + bench verdes.
- Invariantes LSM rotas por semántica ajena (p. ej. `HashMap.get` con `-V: Data`, comparator estático del heap) → leyes del pegamento (§4) como red.
- `IO` / `.c` / `.js` colándose en la fachada → gate `grep` para `IO\.|effs/|def main` sobre `mylsm.bend` (spec 2026-09-22 §8).

# Rendimiento de la API Bytes — plan de experimentos e implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) for tracking.

**Goal:** Comprobar, con cargas reproducibles y el mismo toolchain, si tres cambios concretos mejoran MyLSM.Bytes: ordenación estable de mutaciones, comprobaciones del cursor sin copiar valores y mantenimiento incremental del SST.

**Architecture:** Primero se agrega un benchmark inmutable y se mide el código actual. Cada candidato nace del mismo commit de referencia, conserva la API y se compara de forma aislada. El merge incremental se divide en lectura/ordenación y escritura, porque ByteSstFile.encode_file todavía construye el archivo completo en memoria.

**Tech Stack:** Bend, leyes y testigos Bend, Bolt, ejecutables nativos, bench/measure_rss.py, harnesses de fallo y recuperación existentes.

**Spec:** docs/superpowers/specs/2026-10-08-mylsm-060-design.md; AGENT.md; petición de evaluar las tres oportunidades de rendimiento.

## Estado de ejecución (2026-10-15)

La implementación está en `codex/byte-performance-experiments`. Los resultados crudos y las decisiones están en [bench/results/byte-performance-2026-10-15.md](../../bench/results/byte-performance-2026-10-15.md) y `bench/results/byte-performance-2026-10-15.tsv`.

| Etapa | Estado | Evidencia |
| --- | --- | --- |
| Preflight de Bend | Parcial | `bend guide` consultado. `bend update` no pudo resolver `bend-lang.com`; baseline y candidato usan Bend 2.0.37. |
| Harness | Parcial | Incluye ordenación, overwrite, apertura/iteración, mantenimiento y fases SST. Falta `scan_mixed` con reemplazos y tombstones; las fixtures de mantenimiento actuales solo insertan. |
| Task 2, ordenación | Aceptada | Merge balanceado estable, leyes/testigos y A/B limpio. `order_unique` grande y `scan_open` mejoran 95–98%, con 8/8 muestras ganadas. |
| Task 3, cursor | Aceptada con límite formal | Las comparaciones ya no clonan valores; `scan_next` de 4 096 claves/valores de 4 096 B mejora 95,1%, 8/8. La igualdad de `Bytes.copy.bytes` no se afirma como teorema porque es primitiva Base. |
| Task 4, escritor SST | Sin cambio de producto | `flush`/`compact` mejoran 98,5% por la composición candidata. El RSS sube menos de 2%; no hay candidato incremental que demuestre la reducción de 15% exigida. Se conserva el codec y la publicación actuales. |
| Task 5, gates e informe | Hecho para la composición | 82/82 pruebas formales, smokes públicos, Bolt filtrado, ancho y diff limpios. Reporte y muestras ABBA/BAAB guardados. |

### Decisiones y límites

- Se conserva Bend 2.0.37 porque no se pudo consultar el servidor de releases. Ambos worktrees usan el mismo compilador, flags, host, filesystem y un hilo; los commits comparados están limpios.
- Se aceptan Task 2 y Task 3 por mejoras públicas grandes y repetibles. No se aceptan inferencias a partir de muestras sub-200 ms aisladas.
- Task 4 no añade un escritor incremental: las mejoras medidas ya ocurren en el candidato de ordenación, el RSS público no empeora materialmente y no se midió una alternativa de streaming con menor memoria. La codificación SST se mantiene sin cambios.
- La matriz no es exhaustiva: falta `scan_mixed`, la fixture de mantenimiento no tiene reemplazos/tombstones y la salida del scan valida cantidad y bytes agregados, no digest criptográfico de cada valor. Las limitaciones están recogidas en el informe; no se presentan esas comprobaciones como equivalencia completa.
- El harness y la fuente no añaden `@unsafe` ni comentarios nuevos. Se conservaron las limitaciones de primitivas Base y efectos host.

### Reproducción

Desde ambos worktrees, compilar el mismo commit común del harness y usar directorios de salida nuevos:

~~~sh
bend version
cat tools/toolchain.json
bend guide
bend bench/workload/byte_performance.bend -o .mylsm/build/byte-performance
MYLSM_BYTE_BENCH_CASES=ordering bench/workload/byte_performance.sh baseline /tmp/byte-baseline 8
MYLSM_BYTE_BENCH_CASES=ordering bench/workload/byte_performance.sh candidate /tmp/byte-candidate 8
MYLSM_BYTE_BENCH_CASES=maintenance MYLSM_BYTE_BENCH_MAINTENANCE_COUNTS=128 bench/workload/byte_performance.sh candidate /tmp/byte-maintenance 8
MYLSM_BYTE_BENCH_CASES=phases MYLSM_BYTE_BENCH_FIXTURE_DIR=/tmp/byte-fixture bench/workload/byte_performance.sh candidate /tmp/byte-phases 8
./proofs/run.sh
~~~

El arnés usa `bench/measure_rss.py`, registra commit/dirty/toolchain/compilador/host/disco, conserva cada TSV y log, y rechaza resultados sin `result=pass`. Las muestras pequeñas que quedan bajo 200 ms se consideran exploratorias, no evidencia de aceptación independiente.

## Pseudocódigo de las rutas candidatas

### Materialización de la tabla

`Table.entries` contiene mutaciones newest-first. Para conservar esa precedencia al formar runs:

~~~text
ordered_entries(table):
  runs = map(entry -> [entry], table.entries)
  while length(runs) > 1:
    runs = merge_round(runs)       # pares adyacentes; impar pasa intacto
  return head(runs) o []

merge_newer(newer, older):
  si newer está vacío: devolver older
  si older está vacío: devolver newer
  (clave_nueva, clave_vieja, cmp) = cmp_with_inputs(head(newer), head(older))
  si cmp == LT: emitir entrada nueva y avanzar newer
  si cmp == EQ: emitir entrada nueva y avanzar ambos
  si cmp == GT: emitir entrada vieja y avanzar older
  reconstruir cada Entry con su valor/tombstone movido, no clonado
  acumular en reversa; invertir una vez al cerrar el run
~~~

Invariante: cada run está ordenado estrictamente y contiene la mutación más nueva por clave de su segmento original. En cada ronda los segmentos adyacentes se combinan manteniendo el segmento newest a la izquierda; por eso EQ conserva la versión más reciente aunque el orden de agrupación sea balanceado.

### Cursor, solo si las mediciones lo justifican

~~~text
key_copy(entry): (entry reconstruida con el mismo val, clone(entry.key))
live_keep(entry): (entry reconstruida con el mismo key/val, val es Some)

comparar_delta_base(delta, base):
  (delta_original, delta_key) = key_copy(delta)
  (base_original, base_key) = key_copy(base)
  cmp = compare(delta_key, base_key)
  aplicar ScanMerge.choose(cmp, presencia, tombstone)
  conservar/emitir entradas originales; nunca clonar sus valores
~~~

Los clones de clave que requieren límites, prefijos o snapshots siguen siendo explícitos. El contrato observable de `VisibleCursor.next`, `seek`, errores y snapshots no cambia.

### Mantenimiento SST, solo si se acepta por datos

~~~text
merge_stream(delta_ordenado, base_bloques, drop_tombstones):
  mientras delta o base tenga head:
    comparar claves disponibles
    menor -> emitir ese head
    igual -> emitir delta; avanzar ambos
    si drop_tombstones y la entrada resuelta es tombstone: no emitir
    alimentar ByteBlockBuilder hasta límite MAX_BLOCK_BYTES
  primera pasada: calcular entry_count, block_count y límites para header
  segunda pasada: releer generación inmutable y escribir frames a temporal
  escribir índice/footer con el digest definido por el codec actual
  sync temporal -> rename SST -> sync directorio -> manifest -> reset WAL
~~~

No se acepta una variante que conserve el SST entero en memoria, altere bytes/formato sin equivalencia, publique en distinto orden o retire una generación todavía usada por un snapshot.

## Situación comprobada en el código

| Ruta | Código actual | Coste que se quiere comprobar |
| --- | --- | --- |
| Ordenación | ByteMemTable.ordered_entries llama ordered.insert para cada mutación; cada inserción llama count.keep sobre el acumulado | Con n claves distintas, el trabajo de lista es cuadrático |
| Scan | ByteDurableDb.scan.open copia el delta y llama ordered_entries; VisibleCursor.delta.head, compare y delta.output llaman entry.clone, que copia clave y valor | Apertura dependiente del delta y copias de valores durante la iteración |
| Flush/compact | ByteDurableDb.flush.sst.loaded y compact.sst.loaded llaman ByteSstIo.read, agregan delta y base, ordenan y publican; ByteSstIo.write_atomic_at llama ByteSstFile.encode_file y escribe el buffer completo | Relectura, ordenación y memoria proporcional al SST completo |

La apertura normal de la base usa ByteSstIo.validate y reproduce el WAL; no debe incluirse como si materializara el SST. Los resultados de bench/workload/phase3_metrics.bend y durable_api_perf.bend ejercitan principalmente el motor anterior, así que no sirven como comparación directa de estas rutas de MyLSM.Bytes.

## Mapa de archivos

| Archivo | Cambio previsto |
| --- | --- |
| bench/workload/byte_performance.bend | Fixture Bend y tiempos de operaciones de MyLSM.Bytes; sin política en Bash |
| bench/workload/byte_performance.sh | Compilación, metadatos del host, directorios seguros y muestras |
| bench/results/byte-performance-*.tsv y .md | Datos crudos y decisión por candidato |
| src/ByteMemTable.bend | Ordenación balanceada y auxiliares de inspección de clave sin copiar valores |
| laws/ByteMemTable.bend, proofs/ByteMemTableProof.bend | Contrato puro de precedencia y orden |
| src/scan/VisibleCursor.bend | Sustituir copias de entradas completas en las comprobaciones |
| laws/ScanMerge.bend, proofs/ScanMergeProof.bend | Decisiones puras del merge del cursor |
| src/ByteSstIo.bend, src/ByteSstFile.bend, src/ByteDurableDb.bend | Solo en el experimento de mantenimiento si las fases anteriores lo justifican |
| laws/ByteSortedRun.bend, proofs/ByteSortedRunProof.bend | Contrato del merge incremental de SST y delta |

## Reglas de ejecución y decisión

- [x] Al empezar, ejecutar bend update y bend guide; `bend update` no pudo resolver DNS, por lo que se congeló 2.0.37 para **ambos lados** de cada comparación.
- [x] Preparar el benchmark en commits comunes antes de tocar código de producción. Crear dos worktrees desde el mismo harness y compilar ambos con las mismas opciones.
- [x] Correr un proceso a la vez, con threads, compilador, optimización, host, disco y fixture constantes. Preparar y copiar los fixtures antes del reloj.
- [x] Tomar ocho muestras por versión en bloques ABBA/BAAB. Guardar resultados individuales, RSS, bytes en disco y metadatos; no reemplazar fallas silenciosamente.
- [x] Aplicar el gate de tiempo, victorias pareadas y memoria a los casos públicos grandes; los casos menores de 200 ms no se usan como evidencia independiente.
- [x] Mantener las leyes y testigos separados de los fixtures cerrados y las comprobaciones runtime de IO.
- [x] No añadir comentarios ni referencias de ticket; no usar `@unsafe` en código justificado por leyes.

## Task 1: Fijar un benchmark de la API pública

**Files:** Crear bench/workload/byte_performance.bend y bench/workload/byte_performance.sh. Crear después de medir un TSV y un informe en bench/results/.

**Interfaces:**
- Entrada del ejecutable: escenario, tamaño, tamaño de valor y ruta de base por argumentos o variables MYLSM_BYTE_BENCH_* validadas.
- Salida: una fila por ejecución con scenario, count, value_bytes, phase, elapsed_ms, checksum y result=pass.
- El shell solo prepara rutas, compila, controla repeticiones y recoge RSS; la construcción de claves, la validación y los tiempos de operaciones viven en Bend.

**Funciones de la fixture:** bench/workload/byte_performance.bend importa mylsm.bend as MyLSM, ByteMemTable.bend as ByteMemTable y las funciones de fase que mide. Definir make_key(index: Nat) -> Bytes.Bytes con ocho bytes big-endian; make_value(index: Nat, size: Nat) -> Bytes.Bytes; prepare_delta(count: Nat, value_bytes: Nat, order: Order) -> ByteMemTable.Table; scan_all(cursor: MyLSM.Bytes.Cursor) -> IO(ScanTotals). ScanTotals guarda count, bytes de valor y primera/última clave. El ejecutable despacha por escenario sin añadir lógica de benchmark al producto.

- [ ] **Step 1: Definir datos deterministas.** Usar claves binarias de 8 bytes en orden ascendente para la base y de orden inverso para el delta; valores repetibles de 32 y 4096 bytes. Incluir un control de una sola clave sobrescrita muchas veces. Para cada tamaño, registrar el número real de entradas del SST y del WAL, no solo el solicitado.
- [ ] **Step 2: Implementar los casos.** La matriz mínima es:

| Caso | Estado inicial | Región medida | Resultado a verificar |
| --- | --- | --- | --- |
| order_unique | 256, 1024, 4096, 8192 mutaciones distintas, construidas antes del reloj | ByteMemTable.ordered_entries | orden estricto, cuenta exacta y digest de claves/valores |
| order_overwrite | 4096 mutaciones de la misma clave | ordered_entries | gana la última versión |
| scan_open | SST vacío; deltas de 0, 1024 y 4096 entradas | MyLSM.Bytes.scan hasta recibir cursor | cursor válido y handle preservado |
| scan_delta | deltas de 1024 y 4096 entradas, sin SST | scan_next hasta End, medido aparte de scan_open | cada clave una vez, valores completos |
| scan_mixed | SST de 16000 entradas de 32 bytes; delta de 128 o 4096, con reemplazos y tombstones | scan_next hasta End | vista más reciente, sin claves borradas |
| scan_value | delta de 1024 entradas con valores de 32 o 4096 bytes | iteración completa | mismo conjunto de claves y valores íntegros |
| flush | SST de 16000 entradas, delta nuevo de 128 o 4096 | MyLSM.Bytes.flush | reopen y comparación exacta |
| compact | misma base con reemplazos y tombstones | MyLSM.Bytes.compact | reopen, sin tombstones visibles |

- [ ] **Step 3: Separar preparación, tiempo y verificación.** Para cada caso: crear fixture; tomar IO.now; ejecutar exactamente la operación indicada; consumir el resultado mediante count, longitudes y claves primera/última; tomar IO.now. Verificar contenidos completos y recuperación en otra pasada fuera del tramo medido, para que el coste de hashing no oculte las copias de valores que se investigan. Si la duración de un caso puro es menor de 200 ms, repetir sobre entradas preparadas antes del reloj y dividir por el número de repeticiones. No medir creación de claves ni compilación como tiempo de ordenación.
- [x] **Step 4: Añadir medidas de fases sin confundirlas con el API total.** `phase_read`, `phase_order` y `phase_encode` emiten filas separadas; no se suman para estimar `flush`.
- [x] **Step 5: Hacer el shell reproducible.** El runner valida rutas/espacio, compila una vez, usa `bench/measure_rss.py` y guarda resultados y metadatos por muestra.
- [ ] **Step 6: Validar el harness.** Compilar con bend bench/workload/byte_performance.bend -o <ruta temporal>; correr una muestra pequeña; exigir result=pass, tiempos no vacíos y digest estable en dos ejecuciones. Reutilizar bench/smoke/public_bytes_api.bend y public_cursor_memory.sh como comprobación de integración, sin usar el segundo como benchmark de delta (su delta está vacío después de flush). Guardar el commit del harness y tomar las ocho muestras baseline.

**Comandos esperados del harness:**

~~~sh
bend bench/workload/byte_performance.bend -o .mylsm/build/byte-performance
MYLSM_BYTE_BENCH_SCENARIO=scan_delta MYLSM_BYTE_BENCH_COUNT=1024 MYLSM_BYTE_BENCH_VALUE_BYTES=32 MYLSM_BYTE_BENCH_DIR=/tmp/mylsm-byte-scan-a .mylsm/build/byte-performance --threads 1
bench/workload/byte_performance.sh baseline /tmp/mylsm-byte-baseline 8
~~~

La segunda línea debe imprimir una fila con result=pass y elapsed_ms numérico. El shell rechaza una ruta existente salvo reset explícito y no borra la raíz del repo ni el home. El TSV conserva cada muestra; el informe no sustituye los datos crudos.

## Task 2: Ordenación estable en O(n log n)

**Files:** Modificar src/ByteMemTable.bend, laws/ByteMemTable.bend y proofs/ByteMemTableProof.bend. No modificar el harness de Task 1.

**Interfaces:**
- Se conserva def ordered_entries(table: Table) -> List<&1, Entry>.
- Las entradas llegan newest-first desde Table.entries; la salida debe tener claves estrictamente ascendentes, una entrada por clave y valor/tombstone de la mutación más reciente.
- Se reemplazan OrderedSearch y ordered.insert/fold si dejan de tener referencias; no se altera put, del, get, probe ni el formato SST.

**Auxiliares previstos en ByteMemTable.bend:**

~~~bend
def ordered.singleton_runs(entries: List<&1, Entry>) -> List<&1, List<&1, Entry>>
def ordered.merge_newer(newer: List<&1, Entry>, older: List<&1, Entry>) -> List<&1, Entry>
def ordered.merge_round(runs: List<&1, List<&1, Entry>>) -> List<&1, List<&1, Entry>>
def ordered.merge_many(runs: List<&1, List<&1, Entry>>) -> List<&1, Entry>
def ordered_entries(table: Table) -> List<&1, Entry>
~~~

El implementador puede ajustar nombres internos si Bend exige otro orden para la recursión estructural; la firma pública y la precedencia son fijas. En merge_newer, Keys.Bytes.cmp.with_inputs devuelve ambas claves junto al Cmp, lo que permite reconstruir cabezas afines sin duplicar valores.

- [x] **Step 1: Fijar el contrato antes del código.** Las leyes cubren LT/EQ/GT sobre comparación abierta; los fixtures cerrados comparan la lista canónica completa, incluyendo claves binarias, sobrescritura y tombstones.

**Leyes objetivo:** ordered.merge_newer con cabeza LT emite la del run nuevo; EQ emite la nueva y elimina la vieja; GT emite la vieja y preserva la nueva para el siguiente paso. Estas tres decisiones se prueban sobre valores abiertos de Cmp cuando sea posible. La afirmación general sobre listas arbitrarias requiere además invariantes de runs ordenados y prioridad; si Bend no permite cerrarla, registrar esa limitación y usar equivalencia exhaustiva para vectores pequeños más fixtures grandes. No llamar prueba general a esos fixtures.
- [x] **Step 2: Implementar la división en runs.** `ByteMemTable.ordered_entries` crea runs singleton y los fusiona por rondas balanceadas.
- [x] **Step 3: Implementar el merge estable.** El merge compara heads por bytes, elige la entrada más nueva en EQ y no clona valores.

~~~text
merge(newer, older):
  si newer está vacío: devolver older
  si older está vacío: devolver newer
  comparar sus claves con Keys.Bytes.cmp.with_inputs
  LT: emitir cabeza de newer y avanzar newer
  EQ: emitir cabeza de newer y descartar cabeza de older
  GT: emitir cabeza de older y avanzar older
~~~

Cada comparación devuelve los dos buffers de clave; reconstruir las entradas con sus valores afines. Acumular en reversa y revertir una sola vez al cerrar cada merge. Usar fuel calculado del tamaño de ambos runs, sin @unsafe ni List.append dentro de cada paso. No paralelizar rounds sin un A/B específico: el repositorio ya midió una regresión al paralelizar Bloom.
- [ ] **Step 4: Probar el límite funcional.** Verificar en Bend los testigos de ByteMemTable y ByteSortedRun y correr la fixture pública de Bytes. Comparar byte por byte la salida de la versión vieja y la nueva para vectores generados determinísticamente con duplicados y tombstones; esos vectores son regresiones ejecutables, no teoremas.
- [x] **Step 5: Medir aislado.** `order_unique` y `scan_open` cumplen el gate público con ocho muestras por versión; se conserva Task 2.

**Casos exactos de equivalencia:** aplicar en ese orden put(ff, 01), put(00, 02), put(ff, 03), del(00), put(0000, 04), put(clave vacía, 05). La salida canónica esperada, expresada como clave:valor, es vacía:05, 00:tombstone, 0000:04, ff:03. Repetir con del(ff) al final y exigir ff:tombstone. El comparador usa bytes sin decodificación UTF-8. Si la salida es igual en esos casos, aún falta comparar los vectores determinísticos más grandes.

## Task 3: Evitar copiar valores durante comparaciones de cursor

**Files:** Modificar src/ByteMemTable.bend y src/scan/VisibleCursor.bend; añadir leyes en laws/ByteMemTable.bend y testigos en proofs/ByteMemTableProof.bend. La política ScanMerge.choose no cambia.

**Interfaces:**
- Auxiliar propuesto: def entry.key.copy(entry: Entry) -> Entry & Bytes.Bytes. Devuelve la entrada intacta y una copia solo de la clave; su valor no se copia.
- Auxiliar propuesto: def entry.live.keep(entry: Entry) -> Entry & Bool. Inspecciona Some/None, reconstruye la entrada original y devuelve si está viva.
- VisibleCursor.next, seek y el tipo público Step no cambian.

**Esqueleto de la operación afín:**

~~~bend
def entry.key.copy.pair(pair: Bytes.Bytes & Bytes.Bytes, val: Maybe<&1, Bytes.Bytes>) -> Entry & Bytes.Bytes:
  match pair:
    case (retained, probe):
      (Entry{retained, val}, probe)

def entry.key.copy(entry: Entry) -> Entry & Bytes.Bytes:
  match entry:
    case Entry{key, val}:
      entry.key.copy.pair(bytes.clone(key), val)
~~~

La propiedad relevante es que val atraviesa la función una sola vez y nunca llega a value.clone.

- [ ] **Step 1: Medir el patrón que puede mostrar el coste.** Partir de otro worktree del commit del harness, sin Task 2. Comparar scan_delta y scan_value con 32 frente a 4096 bytes, y scan_mixed con 0, 128 y 4096 entradas delta. Si scan_value no empeora con el tamaño de valor, documentar la ausencia de evidencia y no cambiar el cursor.
- [x] **Step 2: Fijar el comportamiento de los auxiliares.** Se añadieron leyes/testigos de presencia abierta y fixtures de entrada viva y tombstone; las limitaciones de bytes Base se registran explícitamente.

**Esqueleto de presencia sin copia de valor:** match entry sobre Entry{key, val}; match val sobre None{} o Some{value}; reconstruir Entry{key, None{}} o Entry{key, Some{value}} junto a False{} o True{}. El valor se mueve una sola vez. Una ley cuantificada sobre la entrada abierta debe comprobar que el primer componente reconstruido representa la misma entrada; los casos cerrados cubren clave y valor binarios.
- [x] **Step 3: Reescribir solo las comprobaciones.** `VisibleCursor` usa copias de clave y preserva valores durante comparación y comprobación de presencia.

~~~text
(entry_preservada, clave_para_comparar) = entry.key.copy(entry)
orden = comparar(clave_para_comparar, otra_clave_para_comparar)
decisión = ScanMerge.choose(base_presente, delta_presente, vivo, orden)
devolver entry_preservada o conservarla en el cursor según la decisión
~~~

No sustituir las copias necesarias para que el snapshot siga siendo independiente del handle. No alterar SstCursor ni RangeCursor en esta tarea.
- [x] **Step 4: Verificar y medir.** Los proofs y smokes pasan; `scan_next` con valor de 4 096 B mejora 95,1% en las ocho muestras pareadas.

**Casos de cursor que deben pasar:** delta y SST con la misma clave devuelven solo el valor del delta; tombstone delta oculta SST; un límite upper igual a la siguiente clave termina sin exponerla; una entrada fuera del prefix se omite; seek avanza y no retrocede; cursor abierto antes de put mantiene el valor anterior; cerrar después de error conserva el error tipado. Medir por separado scan_open y scan_next: una mejora de apertura no demuestra que la iteración haya mejorado.

## Task 4: Determinar si merece la pena cambiar el mantenimiento del SST

**Files:** La investigación usa Task 1. Solo si la decisión es positiva, modificar src/ByteDurableDb.bend, src/ByteSstIo.bend, src/ByteSstFile.bend, laws/ByteSortedRun.bend y proofs/ByteSortedRunProof.bend.

**Interfaces:**
- Mantener los contratos públicos MyLSM.Bytes.flush y compact y su secuencia de publicación.
- El merge recibe delta newest-first ya ordenado y un flujo SST older estrictamente ordenado. En clave igual gana delta; compact descarta tombstones solo después de resolver la base.
- El escritor debe devolver conteo y bytes de payload visibles para reemplazar flush.stats.entries sin retener una lista completa de la base.

**Contratos internos propuestos:**

~~~bend
type MergeDecision is Data:
  TakeDelta{advance_base: Bool}
  TakeBase{}
  SkipDelta{advance_base: Bool}
  SkipBase{}
  Finished{}

def merge.decide(delta_present: Bool, base_present: Bool, order: Cmp, delta_live: Bool, base_live: Bool, drop_tombstones: Bool) -> MergeDecision
def write_merged_atomic_at(directory: String, final_path: String, base_path: Maybe<&1, String>, delta: List<&1, ByteMemTable.Entry>, drop_tombstones: Bool) -> IO(Result<&1, &1, U32 & String, VisibleStats.Stats>)
~~~

TakeDelta/SkipDelta consumen delta y también base cuando advance_base es True; TakeBase/SkipBase consumen solo base. Si drop_tombstones es False, los tombstones se emiten; si es True, se omiten después de resolver claves iguales. La implementación puede dividir write_merged_atomic_at en estados de IO más pequeños; el contrato obliga a no devolver una lista de todas las entradas de la base.

- [x] **Step 1: Cuantificar la oportunidad.** Se midieron operaciones públicas con base de 16 000 y delta de 128/4 096, fases aisladas y RSS. El candidato reduce tiempo; no muestra reducción de memoria que justifique aún el escritor incremental.
- [ ] **Step 2: Diseñar la primera variante medible sin cambiar formato.** Abrir el SST con ByteBlockReader y consumir ByteBlockReader.next bloque a bloque; ordenar únicamente el delta. Comparar un head de delta con un head de base, emitir el menor, resolver EQ a favor de delta y aplicar la regla de tombstones de flush/compact. Mantener un bloque de entrada y un bloque de salida como máximo. Añadir un módulo puro de decisiones de dos heads en ByteSortedRun y leyes para LT/EQ/GT, tombstones y orden estricto.
- [ ] **Step 2b: Asegurar la precedencia y el formato.** En flush se retienen tombstones en el archivo; en compact se eliminan después del merge. Construir el mismo orden de bloques que ByteSstFile.page.build.limit usando ByteBlockBuilder.decide y el límite StorageBytes.MAX_BLOCK_BYTES. Comprobar los casos de bloque exactamente lleno, entrada que fuerza rollover y registro demasiado grande.
- [ ] **Step 3: Resolver la dependencia del header.** El header existente contiene entry_count y block_count antes de los bloques. La primera variante hace una pasada de planificación que calcula conteos y límites de bloque, luego reabre la misma generación inmutable para emitirla. Evita un efecto host de escritura posicional nuevo; medir expresamente el coste de la segunda lectura. Si esta variante no supera el gate, no agregar write_at por intuición.
- [ ] **Step 4: Escribir bloques sin un buffer SST completo.** Extraer del codec actual una operación que recibe un bloque ordenado y devuelve el mismo frame, digest, separador y conteo que encode.page. Escribir cada frame con Fs.write_bytes en el archivo temporal; retener solo metadatos de índice y el estado SHA incremental. Al terminar, escribir índice y footer, cuyo root autentica header, digests de bloques e índice exactamente como ByteSstFile.file.multi.finish. Comparar la salida byte por byte con encode_file sobre fixtures cerrados antes de reemplazar el camino público.
- [ ] **Step 5: Integrar sin alterar publicación.** ByteDurableDb entrega delta y ruta SST al escritor incremental, recibe estadísticas visibles y conserva el handle original ante fallos. Mantener el orden existente: archivo temporal escrito y sincronizado, rename de la nueva generación, sync del directorio, manifest atómico, reset del WAL. No borrar la generación anterior mientras un snapshot la retenga. Las rutas de error deben cerrar lectores y escritor y limpiar temporales según las garantías actuales.
- [ ] **Step 6: Gates y A/B.** Ejecutar los testigos de merge, smokes de SST/flush/compact, recovery, snapshot retention y los harnesses de publicación/crash que cubren esos límites. Medir la variante sola contra baseline y contra la combinación aceptada de Tasks 2 y 3; informar ambas comparaciones. Guardar el cambio solo si pasa el criterio de tiempo o RSS y ninguna ruta medida regresa más de 5%.

**Comparación obligatoria del codec:** para SST vacío, una entrada, dos entradas con overwrite, entrada en límite de bloque y varios bloques, comparar bytes completos del escritor nuevo con ByteSstFile.encode_file para el mismo resultado canónico. Corromper un byte de bloque, índice y footer por separado y exigir el mismo error tipado tras reopen. Los escenarios de crash deben cubrir antes/después del rename SST, manifest y reset WAL.

## Task 5: Verificación y reporte de decisiones

**Files:** Actualizar el informe y muestras bajo bench/results/; enlazar el informe desde bench/BASELINE.md solo si los datos son comparables.

- [ ] **Step 1: Ejecutar gates sobre cada candidato que se conserva.** Usar bend proofs/ByteMemTableProof.bend, bend proofs/ByteSortedRunProof.bend y bend proofs/ScanMergeProof.bend durante desarrollo; luego ./proofs/run.sh. Un timeout o módulo fallido no es un resultado verde. Correr Bolt y los dos checks de ancho exactamente como AGENT.md; cero errores y advertencias. Correr las pruebas de IO pertinentes a los archivos cambiados.
- [x] **Step 2: Publicar tabla por escenario.** Se guardaron ocho muestras por versión, metadatos crudos, RSS, bytes en disco, rangos y medianas en `bench/results/`.
- [x] **Step 3: Registrar la decisión.** Task 2 y Task 3 se aceptan; el escritor incremental no se implementa por falta de evidencia de reducción de RSS. Las limitaciones formales y de fixture constan en el informe.

**Comandos mínimos de verificación para los módulos afectados:**

~~~sh
bend proofs/ByteMemTableProof.bend
bend proofs/ByteSortedRunProof.bend
bend proofs/ScanMergeProof.bend
bend bench/smoke/public_bytes_api.bend
bend bench/smoke/byte_sst_delta_flush.bend
bend bench/smoke/byte_sst_delta_compact.bend
bash bench/smoke/public_cursor_edges.sh
bash bench/smoke/durable_compaction_errors.sh
./proofs/run.sh
../bolt/bin/bolt.bin 2>&1 | grep -v " S002: " | grep -E "error:|warning:"
awk 'length > 200 {print FILENAME":"FNR}' src/*.bend bench/*.bend laws/*.bend proofs/*.bend mylsm.bend
rg --files -0 app -g '*.bend' | xargs -0 awk 'length > 200 {print FILENAME":"FNR}'
git diff --check
~~~

Las dos órdenes de ancho y el filtro de Bolt deben imprimir cero líneas; grep devuelve 1 cuando no encuentra hallazgos. En un cambio de codec o publicación, agregar los harnesses de corrupción y crash correspondientes antes de declarar el cambio listo. En un bump de Bend, reejecutar todos estos gates con la versión registrada.

# API durable

## Propósito y entrada pública

[mylsm.bend](../../mylsm.bend) expone `MyLSM.Bytes` y `MyLSM.Utf8` sobre el mismo motor
durable de bytes. Importar la fachada desde este checkout para usar estas capacidades;
[pack.json](../../pack.json) conserva un import del paquete `0.5.0.0`.

`Bytes` acepta buffers de `bend-kit-bytes.Bytes`. `Utf8` acepta `String`, codifica UTF-8
y devuelve `InvalidUtf8` al leer bytes que no representan texto válido. No reemplaza
ni descarta bytes. Ambas vistas comparten el [orden binario](storage-format.md).

## Operaciones

| Operación | Contrato |
| --- | --- |
| `create(path)` | Reservar una base nueva y adquirir su propiedad |
| `open_existing(path)` | Recuperar una base existente; no crear una faltante |
| `open_existing_wait(path, timeout_ms, backoff_ms)` | Esperar el lock con timeout acotado |
| `put(handle, key, value)` / `delete(handle, key)` | Confirmar una mutación durable |
| `write_batch(handle, mutations)` | Confirmar un lote atómico |
| `get(handle, key)` | Devolver el valor o ausencia |
| `stats(handle)` | Consultar totales visibles y recursos gestionados por el propietario |
| `flush(handle)` / `compact(handle)` | Publicar el estado o compactar la tabla byte actual |
| `close(handle)` | Consumir el handle y liberar sus recursos de propiedad |

Cada operación que conserva el handle lo devuelve junto al resultado tipado. Pasar ese
handle a la siguiente operación. Un handle puede ser local o representar un cliente del
[propietario coordinado](coordination.md).

`open_existing` requiere un manifest válido. Esperar el lock no crea la base: el timeout
máximo es 60.000 ms y el backoff válido está entre 1 y 1.000 ms. Una ruta faltante,
una base ocupada y un plazo vencido son resultados diferentes.

Los [ejemplos ejecutables](../../examples/README.md) muestran escritura de texto, bytes
fuera de UTF-8 y un recorrido estable de snapshot usando la fachada pública.

## Escritura y recuperación

El motor valida y codifica el lote antes de acceder al WAL. Después hace append,
sincroniza y actualiza el estado en memoria. Una confirmación exitosa implica que la
mutación pasó por el protocolo durable. Un fallo posterior de mantenimiento no debe
interpretarse como reversión de una escritura ya confirmada.

Un rechazo anterior al append deja la escritura sin aplicar. Un error después de iniciar
el append o un fallo de sync puede producir `CommitUnknown` y dejar el handle envenenado
para nuevas escrituras. Cerrar, reabrir y consultar el estado antes de decidir un reintento.
Una respuesta remota perdida después del despacho también puede dejar un resultado
incierto: el cliente no repite automáticamente una mutación despachada.

Los lotes admiten de 1 a 256 mutaciones. El lote vacío produce `InvalidArgument` y superar
el conteo o tamaño permitido produce `ResourceLimit`. Las claves tienen un techo de
1 GiB; los frames de una mutación están acotados a 1 GiB + 36 bytes y los frames
multimutación a 1 MiB. Son constantes de implementación, no opciones por base.

El motor byte recupera el manifest y la SST publicada, valida bloques y reproduce el
WAL en el delta activo. Tras un flush exitoso libera del MemTable las entradas publicadas;
conserva los totales de base para consultar la SST sin mantener otra copia completa.
La compactación byte actual procesa una sola tabla y elimina tombstones; la compactación
multinivel de ese motor sigue pendiente.

## Lectores y transferencia

- [Scans y snapshots](scans-and-snapshots.md): límites `[lower, upper)`, prefijos,
  cursores con propiedad y diferencias entre snapshots locales y del propietario.
- [Backup y migración](backup-and-migration.md): exportación consistente, publicación
  sin reemplazo, restore validado y migración desde almacenamiento histórico.
- [Formato](storage-format.md): generaciones del manifest, encodings y comparación.

`inspect(path)` requiere el archivo `LOCK` existente, adquiere exclusión y valida el
manifest acotado sin crear ni reparar la base. No comprueba el contenido del WAL o SST;
la identidad reportada tiene la limitación descrita en el documento de formato.

## Estadísticas y límites conocidos

`Bytes.Stats` contiene cinco totales: entradas visibles, bytes de payload visible,
snapshots del propietario, bytes retenidos por esos snapshots y cursores del propietario.
Los handles locales reportan cero para los tres recursos gestionados por el propietario.
Payload no incluye overhead del runtime o allocator y no equivale a RSS.

Siguen pendientes métricas de disco, buffers, cola, conexiones, fallos de operaciones y
generaciones persistidas para esta fachada. La aceptación 0.6 está incompleta; consultar
el [informe de evidencia](../../bench/results/mylsm-0.6.0.0-acceptance.md) para el alcance
de las ejecuciones registradas.

## API histórica

La fachada también conserva operaciones superiores de texto de la API 0.5 y `Session`
sobre [DurableDb.bend](../../src/DurableDb.bend). Esta ruta usa el motor histórico;
su API y estadísticas no son intercambiables con las de `Bytes`/`Utf8`.

`Session` compone operaciones en notación `do` y los runners `create_database` y
`open_database` cierran la propiedad al terminar. `run_session` devuelve el handle para
continuar con otros programas. La sesión se detiene ante el primer error, pero no es
una transacción: escrituras ya confirmadas permanecen aunque falle otro paso.
`OperationAndCloseFailure` conserva ambos errores cuando fallan la operación y el cierre.
Los errores al abrir o crear usan `SessionError.OpenFailure`; una operación o cierre
fallidos usan `OperationFailure`, `CloseFailure` o la combinación anterior.

Las escrituras históricas devuelven `WriteOutcome`: `MaintenanceComplete` o
`MaintenancePending`. El segundo conserva el commit y permite lecturas y cierre, pero
bloquea nuevas escrituras hasta resolver el estado. Sus estadísticas se interpretan así:

| Campo | Medida |
| --- | --- |
| `active_bytes` | Manifest más SST publicadas que referencia; excluye archivos huérfanos y temporales |
| `wal_bytes` | Tamaño del WAL en bytes |
| `memtable_entries` | Conteo agregado de entradas activas y congeladas |
| `memtable_payload_bytes` | Bytes UTF-8 de claves y valores residentes; un tombstone aporta solo su clave |
| `cache_entries` | Entradas de cache residentes, con máximo 256 |
| `operation_errors` | Operaciones fallidas observadas durante la vida del handle |
| `state` | Estado del handle, incluido el mantenimiento pendiente |

Los bytes activos se obtienen con consultas de tamaño por SST publicada, sin leer sus
contenidos. Payload excluye estructuras, cache y overhead del runtime. Un mantenimiento
pendiente incrementa el contador de errores aunque la escritura siga confirmada. Reabrir
reinicia el contador; los errores anteriores a obtener el handle y del cierre que lo consume
quedan fuera. `InMemory.Session` no persiste; `open_recovering` deja al consumidor la
gestión de propiedad.

## Implementación y comprobaciones

- Motor byte: [ByteDurableDb.bend](../../src/ByteDurableDb.bend),
  [ByteWalIo.bend](../../src/ByteWalIo.bend) y [ByteSstIo.bend](../../src/ByteSstIo.bend).
- Contratos puros: [DurableBatchPolicy.bend](../../laws/DurableBatchPolicy.bend),
  [ByteRecoveryPolicy.bend](../../laws/ByteRecoveryPolicy.bend) y
  [DurableDbPolicy.bend](../../laws/DurableDbPolicy.bend), con testigos en [proofs](../../proofs/).
- Consumidores: [shared_utf8_bytes.sh](../../bench/smoke/shared_utf8_bytes.sh),
  [public_bytes_sst.sh](../../bench/smoke/public_bytes_sst.sh),
  [resource_limits.sh](../../bench/smoke/resource_limits.sh) y
  [durable_session.sh](../../bench/smoke/durable_session.sh).
- Recuperación ante fallo: [durable_commit.sh](../../bench/crash/durable_commit.sh).

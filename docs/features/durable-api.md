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
| `create_with_options(path, options)` | Crear local con defaults o validar opciones contra el owner remoto |
| `open_existing_with_options(path, options)` | Abrir sólo si las opciones válidas coinciden con el owner remoto |
| `put(handle, key, value)` / `delete(handle, key)` | Confirmar una mutación durable |
| `write_batch(handle, mutations)` | Confirmar un lote atómico |
| `get(handle, key)` | Devolver el valor o ausencia |
| `stats(handle)` | Consultar totales visibles y recursos gestionados por el propietario |
| `flush(handle)` / `compact(handle)` | Publicar el estado o compactar la tabla byte actual |
| `close(handle)` | Consumir el handle y liberar sus recursos de propiedad |

Cada operación que conserva el handle lo devuelve junto al resultado tipado. Pasar ese
handle a la siguiente operación. Un handle puede ser local o representar un cliente del
[propietario coordinado](coordination.md).

Las variantes con opciones existen en `Bytes` y `Utf8`. Un mismatch remoto devuelve
`InvalidArgument` antes de operar la base; una opción local no soportada también se
rechaza. La ruta remota obtiene la configuración efectiva mediante el handshake de
coordinación. El owner de esta revisión publica defaults; las opciones personalizadas
locales aún no son configurables.

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

## Motor único

En 0.6.0.0 la fachada expone solo `Bytes` y `Utf8`, ambas sobre el motor byte. La
API de texto 0.5 (`create`, `open_existing`, `put`, `get`, `Session`, `run_session`,
`create_database`, `open_database`, `InMemory.Session` y `open_recovering`) y su motor
de niveles se retiraron. `Utf8.put`, `Utf8.delete` y `Utf8.write_batch` devuelven `Unit`.
Una base con formato 0.5 se migra con `migrate_legacy`; `inspect` sigue reconociéndola.

## Implementación y comprobaciones

- Motor byte: [ByteDurableDb.bend](../../src/ByteDurableDb.bend),
  [ByteWalIo.bend](../../src/ByteWalIo.bend) y [ByteSstIo.bend](../../src/ByteSstIo.bend).
- Contratos puros: [DurableBatchPolicy.bend](../../laws/DurableBatchPolicy.bend),
  [ByteRecoveryPolicy.bend](../../laws/ByteRecoveryPolicy.bend) y
  [OwnerOpenPolicy.bend](../../laws/OwnerOpenPolicy.bend), con testigos en [proofs](../../proofs/).
- Consumidores: [shared_utf8_bytes.sh](../../bench/smoke/shared_utf8_bytes.sh),
  [public_bytes_sst.sh](../../bench/smoke/public_bytes_sst.sh),
  [resource_limits.sh](../../bench/smoke/resource_limits.sh),
  [durable_poisoned_close.sh](../../bench/smoke/durable_poisoned_close.sh) y
  [durable_open_wait.sh](../../bench/smoke/durable_open_wait.sh).
- Recuperación ante fallo: [durable_commit.sh](../../bench/crash/durable_commit.sh).

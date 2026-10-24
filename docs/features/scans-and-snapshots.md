# Scans, snapshots y retención

## Propósito

Recorrer entradas visibles en orden y conservar una vista estable mientras cambian los
datos. Las vistas `Bytes` y `Utf8` comparten el [orden binario](storage-format.md);
la segunda comprueba además que las claves y valores sean UTF-8 válidos.

## Cursores

`scan`, `scan_range` y `scan_prefix` de la [API pública](durable-api.md) devuelven
cursores. Los rangos son `[lower, upper)`, con límites opcionales; los prefijos se
comparan como bytes exactos. `scan_seek` avanza la cota inferior inclusiva.

`scan_next` devuelve una entrada, un paso filtrado, el final o un fallo tipado junto
al cursor. Continuar tras los pasos filtrados. Liberar el cursor mediante `scan_close`,
también al abandonar un recorrido o recibir un fallo. El cierre puede devolver errores
del lector. Un cursor de texto entra en fallo terminal si encuentra UTF-8 inválido.

El recorrido byte combina un cursor de la SST publicada con una copia ordenada del
delta capturado. Mantiene una cabeza de SST a la vez y lee bloques incrementalmente;
no construye una lista con todo el resultado. Los separadores del índice permiten
ubicar el bloque inicial sin recorrer la tabla desde el comienzo.

Las lecturas posicionales están acotadas a 16 KiB dentro de un presupuesto de buffers
residentes de 64 KiB. Estos límites de buffers no describen la memoria total del proceso.

## Snapshots locales y coordinados

| Tipo | Representación y propiedad |
| --- | --- |
| Handle local directo | Copia canónica de las entradas visibles, materializada hasta 64 MiB |
| Handle del propietario | Raíz respaldada por bloques, delta retenido e identificadores remotos |

`snapshot` captura la vista y devuelve el handle actualizado. El snapshot permite
`get`, `scan_range` y `scan_prefix`. Cerrar primero sus cursores y después el snapshot.
Los cursores creados desde un snapshot explícito dejan a su consumidor la responsabilidad
de cerrar ese snapshot.

Un scan directo sobre un handle coordinado crea un snapshot privado y un cursor remoto.
Llegar al final libera ambos; `scan_close` los libera si se termina antes. Un fallo de
stream devuelve el cursor para permitir su limpieza.

El propietario admite hasta 64 snapshots, 64 MiB agregados de raíces retenidas y
64 cursores por snapshot. La admisión rechazada conserva el estado anterior. Son límites
fijos de implementación. Los identificadores pertenecen a una generación del propietario;
consultar [coordinación](coordination.md) para reinicios y `StaleOwner`.

## Archivos retenidos

Flush y compactación publican una nueva SST inmutable. Los snapshots del propietario
mantienen referencias a la generación previa mientras la necesitan. Cerrar el último
lector rastreado permite reclamar la SST retirada; la generación publicada se conserva.
No borrar archivos de una generación retirada suponiendo que ya no tienen lectores.

## Límites y evidencia

El snapshot local todavía materializa entradas. El
[informe de aceptación](../../bench/results/mylsm-0.6.0.0-acceptance.md) registra que la
prueba Linux de 64.000 registros supera el techo de proceso de 32 MiB, aunque el incremento
por escanear 64 entradas es menor a 4 MiB. Ese límite absoluto sigue abierto.

La retención física está cubierta por fixtures de snapshots durante compactación; la
matriz de validación de tokens viejos tras reinicio del propietario sigue pendiente.

## Implementación y comprobaciones

- Lectores: [SstCursor.bend](../../src/scan/SstCursor.bend),
  [VisibleCursor.bend](../../src/scan/VisibleCursor.bend) y
  [RangeCursor.bend](../../src/scan/RangeCursor.bend).
- Retención: [Snapshot.bend](../../src/scan/Snapshot.bend),
  [OwnerSnapshotStore.bend](../../src/coordinator/OwnerSnapshotStore.bend) y
  [OwnerGenerationIo.bend](../../src/coordinator/OwnerGenerationIo.bend).
- Contratos: [ScanCursor.bend](../../laws/ScanCursor.bend),
  [Snapshot.bend](../../laws/Snapshot.bend), [Utf8CursorPolicy.bend](../../laws/Utf8CursorPolicy.bend)
  y sus módulos en [proofs](../../proofs/).
- Fixtures: [public_bytes_cursor.sh](../../bench/smoke/public_bytes_cursor.sh),
  [public_cursor_edges.sh](../../bench/smoke/public_cursor_edges.sh),
  [snapshot_preflight.sh](../../bench/smoke/snapshot_preflight.sh),
  [coordinator_owner_snapshot_dispatch.sh](../../bench/smoke/coordinator_owner_snapshot_dispatch.sh)
  y [public_cursor_memory.sh](../../bench/smoke/public_cursor_memory.sh).

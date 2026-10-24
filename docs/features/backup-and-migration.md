# Backup, restore y migración

## Propósito

Exportar una vista consistente y publicar bases verificadas sin sobrescribir destinos.
Las operaciones públicas viven en [mylsm.bend](../../mylsm.bend); el encoding y las
generaciones están descritos en [storage-format.md](storage-format.md).

## Backup

`Bytes.backup` materializa el snapshot local y devuelve un stream en memoria que se
consume mediante `backup_next`. Sobre un handle remoto devuelve `UnsupportedOperation`;
usar `backup_to` para exportar desde el propietario coordinado.
`Bytes.backup_to(path, handle)` publica un bundle durable: un directorio en `path`
que contiene `BACKUP`. `Utf8` ofrece las operaciones correspondientes sobre el mismo
formato binario.

La ruta local de `backup_to` retiene una raíz inmutable y exporta mediante un cursor
acotado. La ruta coordinada abre un snapshot del propietario, cuenta sus entradas con
un cursor incremental y exporta con otro cursor sobre la misma vista. Esto permite
contar y emitir un conjunto consistente aunque continúen las escrituras.

El bundle se escribe en un directorio temporal hermano. Se sincronizan archivo y
directorio, se publica con rename sin reemplazo y se sincroniza el padre. Un destino
existente se rechaza. Un fallo en el sync final después del rename puede devolver
`CommitUnknown`: el bundle podría estar publicado aunque no exista confirmación durable.

La admisión usa el presupuesto de la raíz retenida, sin un techo independiente para
el tamaño del backup codificado. La ruta de archivo incremental evita construir el
resultado completo en memoria; no extrapolar esa propiedad a todas las APIs de stream.

## Restore

`Bytes.restore(destination, exchange)` recibe bytes ya residentes. `restore_from(destination,
bundle)` lee `bundle/BACKUP`, con un límite actual de 64 MiB. Ambas rutas validan versión,
longitudes, orden estricto, ausencia de duplicados, checksums, conteo y marcador final.

La implementación actual mantiene el exchange completo acotado y los registros
decodificados en memoria durante la validación. Restore incremental sin esa materialización
sigue pendiente.

La base se construye en un directorio temporal hermano, se sincroniza, se reabre para
verificarla y se publica sin reemplazar un destino existente. Los tombstones y la historia
de la base no forman parte del intercambio: se exportan entradas visibles de un snapshot.

## Migración histórica

`migrate_legacy(source, destination)` lee una base de la API 0.5 con almacenamiento
0.4 / manifest generación 3. Valida sus archivos históricos y transforma sus entradas
a la familia byte actual, publicando un manifest de generación 5. La apertura normal
0.6 no hace esta migración implícitamente.

La fuente se conserva. Verificar conteo, bytes de claves/valores tras la decodificación
UTF-8 histórica y checksums antes de publicar el destino. Los formatos anteriores a
generación 3 no están soportados. Un fallo previo a publicación no debe dejar un destino
final; si falla la confirmación después del rename, inspeccionar antes de reintentar.

## Fallos y evidencia

Los fixtures ejercitan publicación, límites de archivos y filesystem lleno. Un caso con
`RLIMIT_FSIZE` comprueba el límite de tamaño del proceso; no demuestra comportamiento
ante `ENOSPC`. Los fixtures Linux con tmpfs lleno ejercitan ese caso por separado.

El [informe de aceptación](../../bench/results/mylsm-0.6.0.0-acceptance.md) registra
entornos y resultados. La matriz final de cargas repetidas para backup/restore sigue
incompleta. La importación/exportación del [REPL](cli.md) usa otro envelope y otra ruta;
no intercambiar sus archivos con un bundle `BACKUP`.

## Implementación y comprobaciones

- Backup: [Backup.bend](../../src/transfer/Backup.bend),
  [BackupIo.bend](../../src/transfer/BackupIo.bend) y
  [BackupOwnerCursorIo.bend](../../src/transfer/BackupOwnerCursorIo.bend).
- Restore y migración: [RestoreIo.bend](../../src/transfer/RestoreIo.bend),
  [MigrateIo.bend](../../src/transfer/MigrateIo.bend) y
  [MigrateRunIo.bend](../../src/transfer/MigrateRunIo.bend).
- Contratos: [Backup.bend](../../laws/Backup.bend),
  [RestorePolicy.bend](../../laws/RestorePolicy.bend), [Migration.bend](../../laws/Migration.bend)
  y [PublicationPolicy.bend](../../laws/PublicationPolicy.bend), con sus [testigos](../../proofs/).
- Integración: [backup_restore.sh](../../bench/smoke/backup_restore.sh),
  [public_backup_file.sh](../../bench/smoke/public_backup_file.sh) y
  [legacy_sst_io.sh](../../bench/smoke/legacy_sst_io.sh).
- Fallos: [backup_publish.sh](../../bench/crash/backup_publish.sh),
  [migration_publish.sh](../../bench/crash/migration_publish.sh),
  [backup_enospc.sh](../../bench/crash/backup_enospc.sh) y
  [migration_enospc.sh](../../bench/crash/migration_enospc.sh).

# Propietario y clientes coordinados

## Propósito

Un solo proceso posee el lock del filesystem y ejecuta las operaciones durables de una
base. Otros procesos locales pueden enviarle solicitudes por un socket Unix. La fachada
[Bytes/Utf8](durable-api.md) representa ambas rutas mediante handles locales o remotos.

## Propiedad y descubrimiento

La exclusión usa `flock` sobre un descriptor abierto de `LOCK`. El archivo permanece
en disco al cerrar; su existencia no demuestra que la base esté ocupada. El lock se
libera al cerrar el descriptor o terminar el proceso.

La apertura canónica y el descubrimiento del endpoint determinan si usar un propietario
existente. El proceso de servicio tiene su entrada en
[app/owner/mylsm_owner.bend](../../app/owner/mylsm_owner.bend). El protocolo incluye
versión, generación del propietario, identificador y código de operación.

`open_existing_wait` espera únicamente la adquisición del lock después de comprobar
el manifest. Distingue el resultado inmediato `Busy` del vencimiento `Timeout`;
no convierte una espera exitosa en permiso para reinterpretar formatos incompatibles.

## Despacho y resultados inciertos

[Owner.serve.loop](../../src/coordinator/Owner.bend) acepta una conexión, lee y atiende
una solicitud, responde y cierra esa conexión. Las mutaciones se serializan bajo el
único handle durable; no hay varios escritores independientes sobre los archivos.

El cliente distingue una solicitud no despachada de una mutación cuya respuesta se
perdió después del despacho. En el segundo caso, `CommitUnknown` impide suponer que
el cambio no ocurrió. Reabrir y consultar antes de decidir un reintento; no repetir
automáticamente la mutación.

## Generaciones y recursos remotos

Las solicitudes y los recursos están asociados a una generación del propietario. Un
handle anterior recibe `StaleOwner` al dirigirse a otra generación. Abrir un handle
nuevo para descubrir el propietario vigente; no reproducir tokens de cursores o
snapshots viejos contra el nuevo.

Los registros de snapshots y cursores viven en el propietario. Sus límites, cierre y
retención de SST se describen en [scans-and-snapshots.md](scans-and-snapshots.md).
La validación integral de tokens viejos después de reinicios sigue pendiente.

## Restricciones actuales

El backlog del listener es una sugerencia al kernel. No existe todavía una cola de
aplicación con presupuesto de solicitudes/bytes ni métricas de profundidad. La existencia
de [QueuePolicy.bend](../../src/coordinator/QueuePolicy.bend) y sus leyes expresa decisiones
puras de admisión; no implica que haya una cola runtime integrada al servidor.

El servidor hace lectura y escritura de cada solicitud antes de aceptar la siguiente.
Todavía falta transporte incremental con límites y plazos que eviten que un cliente lento
monopolice esa atención. Los presupuestos configurables de conexiones y buffers, así
como su observabilidad, siguen pendientes.

La ruta de sockets Unix es nativa. Los efectos JavaScript devuelven una capacidad no
soportada; Bun FFI para locking no implica soporte del servidor Unix en JavaScript.
Consultar la [frontera de efectos](../standards/host-effects.md).

## Implementación y comprobaciones

- Servicio y clientes: [Owner.bend](../../src/coordinator/Owner.bend),
  [ByteClient.bend](../../src/coordinator/ByteClient.bend) y
  [Client.bend](../../src/coordinator/Client.bend).
- Transporte: [Protocol.bend](../../src/coordinator/Protocol.bend),
  [Io.bend](../../src/coordinator/Io.bend) y [UnixSocketIo.bend](../../src/coordinator/UnixSocketIo.bend).
- Contratos: [CoordinatorPolicy.bend](../../laws/CoordinatorPolicy.bend),
  [ClientPolicy.bend](../../laws/ClientPolicy.bend), [QueuePolicy.bend](../../laws/QueuePolicy.bend)
  y [OwnerGeneration.bend](../../laws/OwnerGeneration.bend), con sus [testigos](../../proofs/).
- Integración: [coordinator_owner_socket.sh](../../bench/smoke/coordinator_owner_socket.sh),
  [coordinator_owner_cursor_dispatch.sh](../../bench/smoke/coordinator_owner_cursor_dispatch.sh)
  y [owner_generation_client.bend](../../bench/smoke/owner_generation_client.bend).
- Pérdida de respuesta: [coordinator_commit_unknown.sh](../../bench/crash/coordinator_commit_unknown.sh).
  El [informe de aceptación](../../bench/results/mylsm-0.6.0.0-acceptance.md) registra
  los seis puntos de fallo ejercitados y sus resultados de recuperación.

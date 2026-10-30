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

Cada apertura remota consulta `DescribeOwner` (operación 16) y valida el codec de
opciones efectivo antes de devolver el handle. `OptionsCodec` usa `MLO6`, versión
u32be 1 y 17 campos u32be en 76 bytes. Las variantes
`Bytes.create_with_options`, `Bytes.open_existing_with_options` y sus equivalentes
Utf8 rechazan opciones inválidas antes de abrir. Si existe un owner, comparan los
17 campos y devuelven `InvalidArgument` ante un mismatch; no inician un proceso
owner ni modifican la configuración del existente. El owner actual publica defaults.
La ruta local acepta defaults y rechaza opciones no soportadas, porque todavía no
recibe límites configurables.

## Despacho y resultados inciertos

El reactor del owner mantiene varias conexiones nonblocking y avanza headers, payloads
y respuestas parciales por readiness. Cada conexión admite un request pendiente, sin
pipelining. Las mutaciones se serializan bajo el único handle durable; no hay varios
escritores independientes sobre los archivos. `EINTR` y `EAGAIN`/`EWOULDBLOCK` en
`poll` o `accept` se tratan como transitorios y devuelven el loop a la espera.

El owner rechaza headers cuyo payload supera 16 MiB antes de leerlo y asignarlo. El
preflight rechaza con `ResourceLimit` una respuesta cuya cota individual no cabe antes
del dispatch. Si un productor excede su cota después del dispatch, el owner responde
`CommitUnknown` con payload vacío. Los clientes locales conservan el ceiling de
protocolo de 1 GiB.

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
El propietario limita snapshots a 64, cursores a 4.096 en total y 64 cursores por
snapshot. La validación integral de tokens viejos después de reinicios sigue pendiente.

## Restricciones actuales

El owner tiene una cola FIFO runtime limitada por solicitudes y bytes. Los frames
completos se admiten en orden ascendente de ID estable y se despacha como máximo una
petición por tick. Una cabeza que espera crédito TX conserva su posición; el poll
espera readiness o deadline mientras no haya trabajo elegible. Una request que excede
el presupuesto de cola recibe `ResourceLimit`; la saturación recibe `Busy`. El smoke
`owner_queue.sh` pausa el owner antes del dispatch, admite dos frames de 64 bytes con
presupuesto de 128, rechaza el tercero, cancela el segundo al detectar el half-close y
admite una petición de reemplazo. Dos mutaciones sobrescriben la misma clave; el valor
final y la ausencia de las mutaciones cancelada/rechazada se comprueban antes y después
de reiniciar. El presupuesto de cola puede ser menor que el techo de frame, de modo que
la admisión individual puede rechazar un frame válido de transporte.

El reactor drena bytes legibles aunque `poll()` también señale hangup. Cuando una
conexión ya admitida o en cola se cierra, elimina sus peticiones pendientes y cierra el
socket antes del siguiente dispatch. La petición retirada de la cola conserva su
reserva en un estado InFlight hasta producir el frame; no vuelve a la cola ni se cancela
después del dispatch.

Después de validar el header de 24 bytes, el owner reserva el pico RX completo antes
de leer payload: `48 + 3 × payload_bytes`, que cubre header/chunks, el frame ensamblado
y el payload decodificado mientras coexisten. Los headers usan slots fijos limitados por
`max_connections`; cada conexión también dispone de un frame de control de 28 bytes
fuera del presupuesto TX de payload. Si el pico individual excede `receive_bytes`, responde
`ResourceLimit` y cierra; si cabe en el límite total pero no queda crédito, responde
`Busy` y cierra sin conservar payload parcial. Al completar el frame, la reserva pasa a
la admisión de la cola. Una lectura adicional sobre una conexión en espera o en cola
cierra esa conexión, y POLLIN permanece activo para detectar half-close; así no se
drena pipelining ni se pierde la señal de cierre.

Los deadlines monotónicos cierran frames parciales y limitan la espera de cola y la
escritura de respuesta. Los smokes cubren peer silencioso, fragmentación byte a byte,
EOF parcial, cliente que no lee y progreso concurrente. Las fixtures
`owner_tx_budget.sh` y `owner_rx_budget.sh` cubren presión TX/FIFO, cota RX, Busy,
ResourceLimit y reintento tras liberación. Siguen pendientes oráculos numéricos de
reservas y picos, ledger/stats integrado, observación de poll spin, inyección
EINTR/EAGAIN dentro del Owner, métricas de profundidad y la matriz Linux del reactor.

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
  [owner_frame_limit.sh](../../bench/smoke/owner_frame_limit.sh) y
  [owner_generation_client.bend](../../bench/smoke/owner_generation_client.bend),
  [owner_reactor_fairness.sh](../../bench/smoke/owner_reactor_fairness.sh),
  [owner_reactor_deadline.sh](../../bench/smoke/owner_reactor_deadline.sh) y
  [owner_queue.sh](../../bench/smoke/owner_queue.sh).
- Pérdida de respuesta: [coordinator_commit_unknown.sh](../../bench/crash/coordinator_commit_unknown.sh).
  El [informe de aceptación](../../bench/results/mylsm-0.6.0.0-acceptance.md) registra
  los seis puntos de fallo ejercitados y sus resultados de recuperación.

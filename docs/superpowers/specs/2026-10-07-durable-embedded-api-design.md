# MyLSM Durable Embedded Key-Value API — Design Spec

**Date:** 2026-10-07
**Status:** A+B accepted for MyLSM 0.5.0.0; C–E remain separate increments.
**Target release:** `0.5.0.0` for deliveries A–B; C–E remain separate increments.
**Scope:** Core deliveries A–E. Binary values and conditional batches (F–G)
are later proposals; general transactions and specialized libraries require
separate designs.
**Decision:** Adopt a single-owner embedded database with durable atomic
batches, bounded scans, retained-version snapshots, and logical backup and
restore. Keep the public key/value API String-based through A–E.

## 1. Misión y contexto

Convertir MyLSM en una base key-value embedded útil para aplicaciones de propósito
general, con API durable, exclusión entre procesos, scans acotados, snapshots y
herramientas de backup/restauración/evolución del formato. Una aplicación debe poder
usarla como almacenamiento principal sin conocer sus módulos internos ni mantener
un archivo externo que duplique los datos.

El éxito se evalúa por los contratos de la base, su corrección, límites de recursos
y operación reproducible. Ninguna integración particular determina la arquitectura
o condiciona la aceptación de estas cinco entregas. Esto no implica un motor SQL
ni una promesa de preparación universal para producción.

Supuestos propuestos: ejecución local en macOS y Linux; un proceso propietario
por base; operaciones del propietario serializadas; String sigue siendo la API
de claves y valores. No se promete compatibilidad Windows o con filesystems de
red. No se incorpora concurrencia multiescritor, distribución ni búsqueda vectorial.

Evidencia local consultada:

- `mylsm.bend`: las sesiones existentes aplican transiciones puras.
- `src/DbIo.bend`: escritura de WAL y fsync antes de actualizar memoria.
- `src/Recover.bend`: recuperación carga SSTables completas y puede reparar WAL.
- `src/MergeIter.bend`: merge y scan actuales materializan listas.
- `src/CompactIo.bend`: elimina archivos reemplazados tras publicar.
- `docs/CLI.md`: ya existen import/export con checksums; no equivalen todavía
  al contrato de backup consistente definido aquí.

Este documento propone evolucionar la política anterior de romper formatos sin
migración. No exige reconstruir lectores para formatos anteriores a 0.4.0.0.
La primera entrega A+B está fijada por el usuario como versión 0.5.0.0; su publicación queda sujeta a todos los gates de aceptación.

## 2. Alcance y supuestos

### Incluye

- API pública durable con ownership explícito y errores tipados.
- Exclusión de acceso a la base entre procesos.
- Scans incrementales con límites de memoria configurados.
- Snapshots consistentes retenidos durante escrituras y mantenimiento.
- Backup lógico, restauración verificada, inspección de formato y ruta de
  migración.
- Documentación pública, métricas operativas, evidencia de corrección y gates
  de rendimiento para estos contratos.

### Fuera de alcance

- Concurrencia multiwriter, servidor o protocolo entre procesos y uso
  distribuido.
- SQL, búsqueda vectorial, índices secundarios automáticos y una promesa
  universal de preparación para producción.
- Transacciones generales de lectura-modificación-escritura; requieren un
  diseño separado.
- Bindings de lenguajes y distribución de binarios.
- Modelos de documentos, búsqueda o memoria dentro del motor.

Assumptions: local execution on macOS and Linux, one owning process per
database, serialized operations in that process, and String keys and values
through A–E. Windows and network filesystems are not promised.

The pure/in-memory API remains available under `InMemory.Session`. The durable
`Session` API is a separate IO-backed program, so existing pure operations do
not silently change behavior. The public documentation describes the move.

## 3. Alternativas y decisión propuesta

1. Exponer únicamente los módulos actuales: menor esfuerzo, pero conserva
   riesgos de ownership, memoria proporcional al dataset y errores ambiguos.
2. Reutilizar `bend-kit-sqlite`: ofrece SQLite embebido, sentencias preparadas
   y transacciones sobre la biblioteca del sistema, pero sustituye el motor LSM
   y no conserva el formato ni las operaciones internas de MyLSM.
3. Contrato embedded LSM con propietario único, cursores y versiones de archivos
   retenidas: recomendado; cubre 1–5 sin requerir un servidor permanente.
4. Servicio multicliente con transacciones y MVCC por registro: más flexible,
   pero amplía mucho el alcance antes de demostrar un consumidor que lo necesite.

Se elige la tercera alternativa para conservar el motor y el formato LSM de
MyLSM. `bend-kit-bytes` ya proporciona buffers empaquetados y cursores, y
`bend-kit-files` ya proporciona metadata, listado de directorios, creación,
renombrado y eliminación de archivos, además de lectura y escritura empaquetada;
la implementación debe delegar allí las operaciones cubiertas y mantener
efectos propios solo para primitivas ausentes, como `flock`, `fsync` y
truncamiento. `bend-kit-sqlite` sigue siendo una alternativa válida si se decide
reemplazar MyLSM por SQLite, no un componente del motor LSM.

Los snapshots fijan una versión de los datos en memoria y del conjunto de
SSTables; no requieren inicialmente historial de versiones dentro de cada
registro. Compartir estructuras en Bend debe verificarse: no se da por hecho
que capturar un valor evite copiarlo.

## 4. Public API and delivery contracts

### A. API pública durable

Los nombres siguientes describen contratos, no firmas Bend compiladas:

| Operación | Contrato |
| --- | --- |
| create(path, options) | Crea exclusivamente una base nueva; rechaza una existente. |
| open_existing(path, options) | Abre una base válida; nunca transforma datos ausentes o corruptos en una base vacía. |
| get(handle, key) | Devuelve valor o ausencia; corrupción e IO son errores distintos. |
| write_batch(handle, mutations) | Commit durable y atómico del batch, con orden interno y última mutación ganadora. |
| put / delete | Conveniencias sobre un batch de una mutación. |
| flush / compact | Mantenimiento explícito, sin alterar el estado lógico. |
| close(handle) | Libera recursos y lock; no es necesario para persistir commits ya confirmados. |

El handle durable es opaco, no duplicable, y posee el recurso de exclusión.
Las operaciones preservan su ownership o lo consumen explícitamente. La API
pure/in-memory continúa disponible bajo `InMemory.Session`. `Session` es un
programa separado basado en IO; las operaciones puras no cambian su semántica.

Un batch se valida completamente antes de modificar almacenamiento. Su éxito
solo se devuelve después de sincronizar el WAL y cualquier entrada de directorio
necesaria para recuperarlo. Los lectores del propietario observan el batch entero.
Tras caída, se recupera todo o nada de cada batch; uno no confirmado puede existir.
La API durable acepta de 1 a 256 mutaciones por batch. El codec vigente limita
cada registro codificado a 1 GiB, incluidos los campos de longitud; frames con
varias mutaciones se limitan a 1 MiB y uno de una mutación queda limitado por el
tope de registro más 36 bytes de encabezado.

Errores públicos: NotFound, AlreadyExists, Busy, InvalidArgument, UnsupportedFormat,
Corruption, ResourceLimit, Io y CommitUnknown. Conservan operación, ruta pertinente
y causa del host sin obligar a interpretar texto libre.

Una validación fallida garantiza ausencia de commit. Un fallo después de comenzar
la escritura puede producir CommitUnknown: no se promete rollback ni reintento
seguro. El handle queda inutilizable para operaciones de datos hasta cerrar y
recuperar. El mantenimiento posterior a un commit confirmado no convierte ese
commit en un fracaso: se informa por separado y se bloquean nuevas escrituras
cuando continuar sea inseguro. La API no termina el proceso con IO.die por errores
recuperables por su consumidor; debe auditarse el camino completo de IO.try.

### B. Ownership y exclusión entre procesos

Toda apertura adquiere un lock exclusivo del sistema operativo antes de recuperar,
reparar, barrer temporales o modificar datos. Se mantiene durante toda la vida del
handle; lectores externos tampoco abren directamente una base activa en esta fase.
Un segundo propietario obtiene Busy inmediatamente. No se incorpora espera implícita.

Se usa un archivo de lock estable que nunca se elimina/reemplaza durante operación
normal. Su existencia no representa ownership; el kernel libera el lock al morir
el proceso. Aliases de ruta al mismo directorio deben contender por el mismo lock.
El registro del proceso también impide aperturas duplicadas cuando la primitiva
del host no ofrece esa garantía dentro de un proceso. No se roba un lock por PID
o antigüedad y no se hereda accidentalmente a procesos hijos ejecutados.

Crear y restaurar reservan el destino sin sobreescribir ni borrar directorios del
usuario. Locks son cooperativos: no protegen contra otro programa que ignore el
protocolo. Sistemas donde no se validen lock, rename y sincronización necesarios
fallan explícitamente, sin fallback silencioso.

### C. Scans y lecturas con memoria acotada

`scan(snapshot, lower, upper)` crea un cursor ascendente sobre [lower, upper).
Los límites pueden ser abiertos; se usa exactamente el orden de Keys. Un rango
vacío termina sin resultados. Cada clave aparece una vez, gana la versión más
nueva visible y se omiten tombstones. `next` distingue Item, End y Error.

El cursor mezcla runs mediante lectores incrementales. No concatena ni ordena
el dataset completo. SSTables pasan de contenido residente a descriptores con
metadatos e índices bajo demanda. Recuperación puede validar todo el contenido
secuencialmente, pero no lo retiene completo; menor latencia de apertura requiere
medición separada y no se deduce de menor memoria.

Cada cursor utiliza memoria proporcional a fuentes activas, buffers de bloque y
tamaño máximo de registro, además de estructuras compartidas. Los límites de
memtable, caché, cursores, snapshots y buffers son opciones explícitas y observables.
Índices grandes también se paginan. Si no cabe una operación se devuelve ResourceLimit
antes de publicar resultados incompletos como éxito. El límite de registro existente
no puede tratarse como gratuito: la configuración debe contabilizarlo.

El consumidor controla el avance y puede cerrar antes de End. Cancelación, error
y cierre liberan lectores y referencias. No hay tokens de cursor persistentes
entre reinicios. Scans sin snapshot explícito crean uno interno de duración limitada
por la vida del cursor.

### D. Snapshots consistentes

Capturar un snapshot fija el estado tras un batch completo del propietario.
Get y scan sobre él conservan ese estado pese a puts, deletes, flush y compactación
posteriores. Las operaciones se intercalan secuencialmente en el proceso propietario;
no se introduce ejecución paralela de IO como requisito.

El snapshot retiene las raíces inmutables de memtables y una versión del conjunto
de SSTables. Si una estructura no puede compartirse con seguridad, se congela o
copia dentro del presupuesto configurado; la operación se rechaza si lo excede.
La compactación publica nuevas tablas y difiere el borrado de las antiguas hasta
que ningún snapshot/cursor las necesite. Un snapshot no necesita retener WAL para
lecturas si conserva todo el estado de memoria correspondiente.

Hay límites explícitos de cantidad y bytes retenidos. Al agotarlos se rechaza la
operación que incrementaría retención; nunca se invalida silenciosamente un snapshot.
Los bytes de tablas retenidas se exponen separados de los bytes activos.
Cerrar un snapshot con cursores activos devuelve Busy. Cerrar la base con recursos
hijos vivos también devuelve Busy. Snapshots no sobreviven a una caída: la reapertura
recupera el estado durable y recoge huérfanos solo después de validar el Manifest.

### E. Backup, restauración y formato

El primer backup es lógico y consistente: recorre un snapshot mediante el cursor
acotado y genera un archivo de intercambio versionado con orden canónico, longitudes,
conteo, checksum por bloque y marca final verificable. Puede reutilizar el formato
de export existente únicamente si satisface el contrato; de otro modo introduce
una versión explícita. Exportar datos no conserva historial, WAL ni snapshots activos.

Backup escribe un temporal en el destino, sincroniza contenido, publica mediante
rename atómico y sincroniza el directorio. Éxito significa archivo completo y
verificable. Se rechaza un destino existente. Un aborto deja un temporal reconocible,
no un backup publicado. El snapshot dura toda la exportación y consume su presupuesto.

Restore verifica versión, checksums, orden, duplicados, límites y terminación;
construye una base en un directorio temporal hermano del destino, la sincroniza,
la reabre/verifica y solo entonces publica el directorio final y sincroniza su padre.
No sobreescribe bases existentes. Un fallo conserva el origen y no publica una base
parcial. Los datos restaurados equivalen exactamente al snapshot exportado.

Versiones de API, formato de disco y formato de backup son independientes. Un formato
desconocido se rechaza antes de mutar. Se añade inspección offline de versión e
integridad usando el mismo lock; no repara ni descarta datos corruptos automáticamente.

Para 0.4.0.0 se exige una ruta de migración por exportación con lector compatible y
restauración con el nuevo escritor. Si el export existente no es consumible, se provee
un conversor probado antes de release. No se modifica la base fuente in situ.
Futuras rupturas deben entregar una ruta documentada y fixtures de compatibilidad.
Los formatos anteriores a 0.4.0.0 permanecen fuera del compromiso.

## 5. Contrato de adopción y operación

MyLSM es la fuente de verdad del estado confirmado. WAL, memtables y SSTables son
mecanismos internos: el consumidor no lee ni administra wal.log y no necesita un
LOG.txt paralelo. Un historial permanente se representa mediante registros con
claves distintas; sobrescribir una clave no preserva por contrato sus valores
anteriores. El WAL puede reciclarse después de la publicación durable correspondiente.

La documentación pública debe incluir ejemplos ejecutables de creación, reapertura,
batches, recuperación de errores, scans, snapshots y backup/restore, usando solo
la API pública. Debe publicar orden de claves, límites de claves/valores/batches,
propiedad y cierre de recursos, plataformas soportadas y garantías de durabilidad.
No se confunde atomicidad de batch con una transacción de lectura-modificación-
escritura: las aplicaciones serializan esas secuencias en su proceso propietario.

Dentro de A–E se exige observabilidad suficiente para operar sus contratos: bytes
activos y retenidos, tamaño del WAL, uso de memtables/caché, snapshots y cursores
abiertos, estado de mantenimiento y errores. Consultar estas métricas no modifica
los datos ni exige recorrer todo su contenido. Los nombres y unidades forman parte
de la documentación pública; los contadores de proceso se distinguen de los datos
persistidos. En A+B, los errores se contabilizan por handle desde la apertura; las
fallas previas a entregar un handle y el resultado de `close` quedan fuera de ese
contador. Los bytes de memtable representan payload UTF-8 de claves y valores,
sin atribuir overhead del runtime o allocator ni presentarse como RSS. No se exige
un servicio externo de métricas.

Bindings para Python u otros lenguajes, un protocolo de procesos y distribución
de binarios son extensiones de adopción futuras, con diseño y validación propios.
No se elige un transporte ni se agrega un servidor como requisito de estas entregas.
A–E conservan String como contrato público. Bytes arbitrarios y operaciones
condicionales se describen como evolución F–G en §8. Transacciones generales,
índices secundarios automáticos y búsqueda textual no forman parte de A–G. La
documentación debe expresar las capacidades disponibles por entrega.

OptMem puede ser uno de los consumidores futuros, al igual que herramientas locales,
catálogos o almacenes de estado. Sus comandos, formatos e índices no pertenecen al
núcleo ni a los gates de este spec. Cada integración deberá justificar por separado
su valor y su estrategia de migración.

## 6. Validación y aceptación

Cada entrega conserva gates vigentes de proofs, lint y pruebas pertinentes del repo.
Se distinguen teoremas sobre entradas abiertas, fixtures cerradas y evidencia empírica
del host. Este spec no amplía por afirmación la cobertura formal existente.

| Área | Evidencia obligatoria |
| --- | --- |
| API/commit | Modelo de mapa y batches; fallos antes/después de append, fsync y mantenimiento; ningún commit confirmado perdido ni batch parcialmente visible. |
| Lock | Dos procesos, aliases, dos handles del mismo proceso, kill del dueño y reapertura; segundo proceso no modifica archivos de datos. |
| Scans | Límites, Unicode, borrados/sobrescrituras entre runs, cierre anticipado y corrupción; igualdad contra el modelo. |
| Memoria | Dataset mayor que el presupuesto; consumo de buffers acotado y límites de retención efectivos; contabilizar metadatos y tamaño de registro. |
| Snapshot | Lecturas estables al intercalar escrituras, flush y compactación; archivos se conservan hasta liberar la última referencia. |
| Backup | Caídas en escritura/publicación, disco lleno y permisos; un backup publicado restaura exactamente un snapshot. |
| Formato | Fixtures de 0.4.0.0 y formato nuevo; desconocidos rechazados sin mutación; migración preserva datos. |

La evaluación de rendimiento usa cargas del motor: inserciones secuenciales y
aleatorias, sobrescrituras, borrados, lecturas presentes/ausentes, cargas mixtas,
batches de distintos tamaños, scans cortos y completos, snapshots retenidos durante
mantenimiento, recuperación y backup/restore. Incluir tamaños variables de clave y
valor, localidades distintas y datasets superiores al presupuesto de memoria.

Comparar baseline y candidato con el mismo hardware, disco, toolchain, configuración,
datos y garantías de sync. Ejecutar al menos cinco veces por caso y publicar mediana,
dispersión y muestras crudas; medir throughput, p50/p95/p99 con suficientes operaciones,
RSS máximo, espacio, amplificación de escritura y tiempos de apertura/recuperación.
Separar caché fría y caliente, arranque y operación estable. Las nuevas capacidades
se evalúan también contra el modelo lógico cuando no exista equivalente en baseline.

Aceptación funcional: todas las garantías de A–E verificadas, ninguna escritura
confirmada perdida en la matriz de fallos, límites de recursos efectivos y restauración
exacta del estado exportado. Los ejemplos públicos deben ejecutarse sin acceder a
módulos internos. No se exige ganar un benchmark de una aplicación particular.

Gate de rendimiento propuesto: en operaciones existentes comparables, no más de 5%
de regresión mediana de latencia o throughput frente al baseline fijado antes de
implementar, y sin incremento de RSS máximo bajo igual configuración y carga.
Una diferencia dentro de la variabilidad observada se registra como inconclusa y
requiere más muestras antes de decidir. Para capacidades nuevas, se verifican los
presupuestos configurados y se publica su costo; no se inventa una comparación con
una operación que no existía. Una regresión confirmada exige corregirla o revisar
explícitamente este contrato antes de release. Son criterios propuestos, no resultados.

## 7. Secuencia de entrega y decisiones de revisión

Orden: A+B como primer incremento seguro; después C, D y E. A no se anuncia apta
para consumidores durables hasta completar B. C prepara descriptores y lectores;
D introduce retención; E reutiliza ambos. Cada incremento tendrá un plan independiente
y no se considera terminado por añadir solamente nombres públicos.

Decisiones propuestas para revisión: propietario único, snapshots por versiones
retenidas, backup lógico, migración desde 0.4.0.0 y aceptación independiente de
aplicaciones consumidoras. La aprobación de este spec permite preparar los planes;
la implementación y las integraciones son pasos posteriores.


## 8. Evolución futura del núcleo y capas especializadas

MyLSM conserva el modelo key-value. Se amplían las primitivas generales que permiten
construir aplicaciones encima, sin incorporar sus modelos de dominio al motor.
F–G son propuestas posteriores con planes y validación propios. No bloquean la
aceptación de A–E ni representan funcionalidades ya disponibles.

### F. Claves y valores binarios

La API de almacenamiento acepta secuencias de bytes arbitrarias, incluyendo cero,
contenido no UTF-8 y secuencias vacías. Ausencia de una clave se distingue de un valor
vacío. Claves se comparan lexicográficamente por bytes sin signo; un prefijo ordena
antes que su extensión. No hay normalización Unicode, collation regional ni conversión
implícita a texto. El orden debe ser idéntico en memtables, SSTables, Bloom, scans,
compactación, recuperación y exportación.

String permanece como adaptador explícito UTF-8 sobre la API binaria. Antes de migrar
se verifica si su orden actual coincide con el nuevo: si difiere, se reconstruyen
tablas e índices durante la migración; nunca se reinterpretan tablas existentes bajo
un comparador distinto. Se versiona el contrato de orden junto al formato necesario.
Los nombres exactos de la API se fijan en su diseño para evitar ambigüedad entre texto
y bytes. Cada tamaño máximo se expresa en bytes y se valida antes de asignar memoria.

WAL, SSTables y backup preservan bytes exactamente. Tener codecs binarios internos
hoy no demuestra soporte de claves y valores binarios en todas las rutas. La entrega
audita esas rutas, evita conversiones String intermedias y proporciona migración
mediante la infraestructura E, manteniendo intacta la base fuente.

Aceptación: round trips de todos los valores de byte, claves vacías y con prefijos,
valores vacíos, contenido UTF-8 inválido, límites de tamaño, orden contra un modelo
binario, snapshots, fallos y backup/restore sin pérdida. Medir costo de adaptadores
y cargas binarias además de conservar los gates aplicables de A–E.

### G. Operaciones condicionales atómicas

La primitiva propuesta es un batch condicional: un conjunto de condiciones sobre
claves y un batch de mutaciones. Condiciones iniciales: clave ausente o valor actual
igual a una secuencia de bytes. Put-if-absent y compare-and-swap son conveniencias
sobre esa primitiva, no implementaciones cliente de get seguido de put.

Todas las condiciones se evalúan sobre el mismo estado actual, antes de las
mutaciones. El propietario serializa evaluación y commit respecto de otras escrituras.
Si alguna condición no se cumple, devuelve ConditionFailed y no aplica ninguna
mutación. Si todas se cumplen, aplica el batch completo con las mismas garantías
de durabilidad y CommitUnknown que A. Condiciones no se evalúan sobre un snapshot
antiguo ni se vuelven a evaluar al recuperar: el WAL registra el batch ya decidido.

Igualdad de valor no detecta el patrón A→B→A. Esta entrega no promete detección de
cambios intermedios, exactly-once ni reintento seguro después de CommitUnknown.
Una aplicación que necesite detectar cambios intermedios debe mantener un token
monótono como parte del valor y actualizarlo condicionalmente en el mismo batch.
Condiciones y mutaciones tienen límites explícitos de cantidad y bytes.

Aceptación: dos intentos condicionados al mismo valor no pueden ambos ganar si el
primero cambia ese valor; condición ausente distingue valor vacío; un fallo en una
condición impide todo el batch; múltiples claves se actualizan juntas; snapshots
observan antes o después, nunca un estado parcial. Incluir límites, recuperación,
fallos de IO y comparación contra una máquina de estados de referencia.

### H. Transacciones generales, sujetas a un caso concreto

Un batch atómico y un batch condicional no equivalen a una sesión transaccional con
lecturas arbitrarias. Begin/read/write/commit/abort se considerarán cuando un consumidor
necesite coordinar lecturas y escrituras que F–G no resuelvan razonablemente.

Antes de aceptar esa entrega se exige un spec separado que seleccione aislamiento,
semántica de conflictos, validación de rangos y phantoms, visibilidad de escrituras
propias, límites de duración/memoria, abortos, reintentos y recuperación. Debe incluir
historias concurrentes y una justificación del costo frente al batch condicional.
No se promete serializabilidad ni se agrega MVCC por registro anticipadamente.

### Capas de documentos, búsqueda y memoria

Estas capacidades viven en librerías separadas que consumen exclusivamente la API
pública. Serialización de documentos, esquemas, extracción de términos, índices,
ranking y políticas de memoria pertenecen a esas librerías. Los prefijos de claves
se codifican sin colisiones y no convierten al motor en consciente de su significado.

Cuando una capa almacena documentos e índices en la misma base, utiliza un batch
para publicar sus cambios juntos y condiciones cuando deba validar el estado leído.
Un índice asíncrono requiere su propio contrato de atraso y reconstrucción. Ninguna
capa puede asumir transacciones o búsquedas que la versión del motor no ofrece.
Cada librería define sus formatos, migraciones, pruebas y benchmarks por separado;
no accede al WAL ni a tablas internas. Una limitación repetida entre consumidores
puede motivar una nueva primitiva general mediante otro spec.

La secuencia propuesta es A–E → F → G. H y las librerías se eligen por necesidades
comprobadas, no como requisito para declarar útil la base key-value.

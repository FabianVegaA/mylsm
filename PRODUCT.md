# MyLSM

## Propósito

Construir la base de datos clave-valor basada en LSM más rápida y segura posible. El objetivo
es ofrecer rendimiento de primer nivel y confianza en la integridad de los datos para
aplicaciones de producción exigentes.

Bend y la verificación formal son herramientas centrales para alcanzar esa ambición:
expresar contratos precisos, demostrar las propiedades críticas del motor y aprovechar
el hardware con algoritmos eficientes. La competitividad debe sostenerse con garantías
explícitas, mediciones reproducibles y comportamiento confiable ante fallos.

## Usuarios y necesidades

MyLSM está dirigido a desarrolladores y equipos que necesitan un motor de almacenamiento
ordenado para aplicaciones, servicios e infraestructura con requisitos exigentes de
latencia, throughput y durabilidad.

Sus usuarios necesitan conservar los datos confirmados, consultar vistas consistentes,
recuperar el servicio después de un fallo y mantener un costo predecible de memoria,
CPU y disco. Deben poder integrar y operar el motor entendiendo sus garantías, límites
y modos de fallo.

## Qué significa tener éxito

- **Rendimiento competitivo sostenido.** Buscar la menor latencia y el mayor throughput
  posibles en lecturas, escrituras, lotes y recorridos, incluyendo el costo de recuperación,
  flush y compactación. Evaluar percentiles de latencia y cargas mixtas prolongadas,
  con datasets que superen la memoria disponible.
- **Seguridad de los datos.** Preservar escrituras confirmadas, atomicidad de los lotes,
  orden y consistencia de las lecturas. Detectar corrupción, rechazar entradas inválidas
  y conservar una ruta de recuperación definida ante fallos de proceso o almacenamiento.
- **Corrección verificable.** Especificar y demostrar los invariantes críticos. Las
  pruebas formales, la integración y la inyección de fallos deben aportar evidencia
  complementaria sobre el comportamiento real del motor.
- **Eficiencia de recursos.** Reducir amplificación de lectura y escritura, uso de memoria,
  copias y trabajo de mantenimiento. Mantener límites y mecanismos de admisión que hagan
  predecible el comportamiento bajo carga.
- **Operación confiable.** Ofrecer errores accionables, observabilidad y procedimientos
  seguros de backup, restore, migración y actualización de formatos.

## Criterios de diseño

La velocidad se mide bajo las garantías de durabilidad y consistencia que recibe el
consumidor. Una comparación competitiva debe usar garantías equivalentes, la misma carga
y condiciones de hardware y almacenamiento comparables. Conservar muestras, configuración,
revisión y método para reproducir los resultados.

Optimizar el recorrido completo de las operaciones: estructuras de datos, codecs, IO,
concurrencia y mantenimiento. Aprovechar las capacidades nativas de Bend y del hardware
cuando reduzcan el costo total y mejoren las cargas relevantes. Cada optimización debe
conservar los invariantes del motor y demostrar su beneficio.

La propiedad y vida de handles, lectores, buffers y archivos deben ser explícitas.
El costo de snapshots y cursores retenidos forma parte del presupuesto del sistema.
La saturación debe tener una respuesta definida y observable.

Ante un resultado de commit incierto, comunicar esa incertidumbre y permitir resolverla
antes de repetir una mutación. La publicación de archivos y formatos debe preservar
la recuperación y evitar que una operación fallida destruya datos válidos.

Las garantías formales deben declarar sus supuestos y frontera de confianza. Las
dependencias, el runtime, el compilador, el filesystem y los efectos de host necesitan
la evidencia correspondiente a su papel en el sistema.

## Capacidades del motor

El núcleo del producto es almacenamiento durable y ordenado de claves y valores binarios,
con una interfaz UTF-8 estricta, operaciones puntuales, lotes atómicos, recorridos por rango
y prefijo, snapshots y mantenimiento del almacenamiento.

La coordinación entre procesos locales, los respaldos consistentes, la restauración
validada y la evolución explícita de formatos forman parte de la confiabilidad que el
producto debe ofrecer. Las interfaces y sus contratos están en [docs/features](docs/features/).

## Madurez actual

El checkout está en fase 0.6 alpha y la aceptación de la versión sigue incompleta.
Todavía no ofrece garantías de estabilidad de producción ni de compatibilidad futura
del formato. La madurez se establece mediante contratos cumplidos, gates aprobados y
comparaciones reproducibles con motores de referencia.

Los límites y pendientes actuales están documentados por funcionalidad. El
[README](README.md) describe cómo usar el checkout y el
[informe de aceptación](bench/results/mylsm-0.6.0.0-acceptance.md) delimita la evidencia
registrada hasta ahora. Este documento fija la dirección con la que deben evaluarse
las decisiones y prioridades de desarrollo.

# Frontera de efectos de host

## Responsabilidad

Mantener Bash, C y JavaScript limitados a la operación irreducible del host. Las decisiones
de política, interpretación del entorno, validación y transformación de datos viven en Bend,
con leyes y testigos para las decisiones puras cuando sea práctico.

Los efectos están en [src/effs](../../src/effs/); los adaptadores Bend, como
[Fs.bend](../../src/Fs.bend), [DbLock.bend](../../src/DbLock.bend) y
[UnixSocketIo.bend](../../src/coordinator/UnixSocketIo.bend), traducen sus resultados.
[scripts/mylsm.sh](../../scripts/mylsm.sh) delega la CLI en Bend.

## Contratos que conservar

- Devolver errores de host para que Bend los clasifique, sin convertir una operación
  no soportada en un éxito aparente.
- Conservar la propiedad de archivos y recursos al devolver resultados o errores.
- Respetar lecturas y escrituras parciales. Un error de escritura no revierte los bytes
  que el host ya recibió.
- Mantener el orden de append, sync, rename y sync del directorio padre que establece
  la capa Bend. Las utilidades de archivos no sustituyen ese protocolo de durabilidad.
- Usar exclusión real de proceso. La existencia de `LOCK` por sí sola no constituye un lock.

El contrato de `bend-kit-files`, sus límites de IO y las versiones nominales de bytes
están registrados en [hub-dependencies.json](../../tools/hub-dependencies.json).

## Plataformas

La ruta nativa implementa los efectos de filesystem, locking y sockets Unix. El efecto
de lock JavaScript usa `flock` mediante Bun FFI; los runtimes sin esa primitiva devuelven
un error de capacidad. Los sockets Unix del propietario no están soportados por los
efectos JavaScript actuales.

No deducir soporte completo de una plataforma a partir de una sola primitiva aprobada.
El [informe de aceptación](../../bench/results/mylsm-0.6.0.0-acceptance.md) delimita las
ejecuciones registradas en Darwin arm64 y Ubuntu arm64 en Docker.

## Comprobar cambios

Usar los fixtures dirigidos de [bench/smoke](../../bench/smoke/) y las matrices de
[bench/crash](../../bench/crash/). Por ejemplo:

```sh
bash bench/smoke/db_lock_js_unsupported.sh
bash bench/smoke/rename_noreplace_js_unsupported.sh
bun bench/smoke/js_bun_ffi.js
bash bench/crash/durable_commit.sh
```

Los fixtures de plataforma deben ejecutarse donde esté disponible la primitiva ejercitada.
Un caso `UnsupportedPlatform` comprueba rechazo explícito, no la ejecución de esa capacidad.
Las leyes de [FsPolicy](../../laws/FsPolicy.bend), [DbLock](../../laws/DbLock.bend) y
[UnixSocketPolicy](../../laws/UnixSocketPolicy.bend) cubren decisiones puras; no prueban
las implementaciones del sistema operativo.

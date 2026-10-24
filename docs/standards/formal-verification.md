# Verificación formal y evidencia runtime

## Flujo de trabajo

Establecer el contrato puro, expresarlo mediante leyes y testigos, implementar y comprobar
la integración con el host. Priorizar esta secuencia sobre organizar el trabajo por tests
runtime. Estos últimos cubren efectos, integración y propiedades fuera de la frontera formal.

Cada dominio tiene `laws/<Dominio>.bend` y `proofs/<Dominio>Proof.bend`. El módulo de
testigos importa su módulo de leyes como `Laws` y solo las dependencias que necesita.
Los nombres de leyes y testigos deben corresponder exactamente. Un ejemplo es el par
[Keys.bend](../../laws/Keys.bend) / [KeysProof.bend](../../proofs/KeysProof.bend).

Nunca usar `@unsafe` en leyes, testigos ni código cuya justificación dependa de ellos.
Conservar los comentarios de raíz de confianza y las limitaciones explícitas existentes.

## Qué demuestra cada comprobación

| Evidencia | Alcance |
| --- | --- |
| Teorema cuantificado | Propiedad sobre sus entradas abiertas dentro de los supuestos del kernel |
| Fixture cerrada | Comportamiento de los casos concretos expresados |
| Fuzzing | Casos ejecutados empíricamente por el corpus y semilla registrados |
| Integración o inyección de fallos | Comportamiento observado en el entorno y los puntos ejercitados |

No atribuir a las leyes pruebas de primitivas de Bend Base, del compilador, del filesystem
ni de efectos C/JavaScript. Las dependencias conservan su propia frontera de confianza;
los vectores cerrados de bytes no prueban su implementación para todas las entradas.

## Comandos y criterio de aceptación

Durante el desarrollo usar módulos dirigidos:

```sh
bend proofs/KeysProof.bend
bend proofs/KeysProof.bend --verdict
```

El hook `pre-push` ejecuta una sola vez el gate completo cuando las rutas cambiadas
afectan código Bend, efectos de host, el runner, el toolchain, las dependencias o la
configuración de hooks. Los cambios solo de documentación no lo disparan.
También se puede ejecutar manualmente dentro de `nix develop`, que proporciona
GNU `timeout` para limitar la ejecución de cada módulo:

```sh
./proofs/run.sh
lefthook run pre-push --all-files
```

[run.sh](../../proofs/run.sh) comprueba correspondencia de nombres y ejecuta los módulos
con `--verdict`. Requiere `FAIL=0`, `TIMEOUT=0` y que todos los módulos cuenten como `PASS`.
Typechecking exitoso sin un veredicto exitoso no satisface el gate.

El runner admite `MYLSM_PROOF_JOBS` (4 por defecto), `MYLSM_PROOF_TIMEOUT` (900 segundos
por módulo) y `MYLSM_PROOF_LOG_DIR` (`.mylsm/build/proofs` por defecto). Un timeout nunca
equivale a una prueba aprobada. Paralelizar comprobaciones independientes cuando sea correcto.

## Evidencia reproducible

Elegir smokes y matrices de fallos según la funcionalidad modificada; sus documentos
enlazan los fixtures correspondientes. Registrar mediciones en [bench/results](../../bench/results/)
con comando, revisión, toolchain, host, carga y muestras. Conservar fallos y limitaciones.
Un informe anterior no reemplaza ejecutar los gates requeridos para un cambio actual.

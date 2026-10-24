# Desarrollo en Bend

## Estructura

| Ubicación | Responsabilidad |
| --- | --- |
| [mylsm.bend](../../mylsm.bend) | Fachada importada por consumidores |
| [src](../../src/) | Motor y módulos internos |
| [laws](../../laws/) | Contratos puros agrupados por dominio |
| [proofs](../../proofs/) | Testigos correspondientes a las leyes |
| [app](../../app/) | CLI, demo, REPL y proceso propietario |
| [examples](../../examples/) | Consumidores de la fachada pública |
| [bench](../../bench/) | Integración, fallos y mediciones reproducibles |

Usar la última versión de Bend mediante la revisión fijada en
[flake.nix](../../flake.nix) y [flake.lock](../../flake.lock), y revalidar los gates al actualizar.
Consultar `bend guide` para sintaxis y convenciones. Las versiones de dependencias del
Hub y sus restricciones están en [tools/hub-dependencies.json](../../tools/hub-dependencies.json).

## Diseño

Preferir funciones puras, efectos aislados y módulos con una responsabilidad clara.
Usar nombres que expresen el dato o comportamiento; los comentarios nuevos requieren
aprobación individual del usuario. No incluir referencias de tickets en las fuentes.

Elegir estructuras según el acceso: arrays contiguos para recorridos, árboles balanceados
para acceso ordenado y estructura compartida para versiones inmutables. Evitar copias
innecesarias y estado mutable compartido; permitir mutación local encapsulada si simplifica
la implementación o reduce su costo.

Exponer trabajo independiente mediante divide y vencerás balanceado, mapas independientes
y reducciones asociativas. Agregar paralelismo cuando la carga y el runtime justifiquen
su costo, y comprobar la ganancia con mediciones representativas.

## Lint y ancho

El hook `pre-commit` de [lefthook.yml](../../lefthook.yml) ejecuta
[scripts/check-bend.sh](../../scripts/check-bend.sh) sobre las rutas Bend preparadas
para el commit, incluidas las de subdirectorios. El script usa `bolt` del entorno
Nix en `PATH`; `BOLT_BIN` permite elegir explícitamente otro ejecutable.

El gate rechaza cualquier salida no exitosa de Bolt y cualquier diagnóstico no exceptuado,
incluidas las advertencias. Conserva las excepciones de ancho del proyecto: filtra `S002`
y los avisos `S003` cuya línea de cabecera no supere 200 caracteres. Comprueba por separado
el máximo de 200 caracteres en cada línea de los archivos recibidos, incluidos comentarios
y literales. Un fallo del linter no se oculta al filtrar su salida.

```sh
lefthook run pre-commit --all-files
bash scripts/check-bend.sh src/Keys.bend
```

El script devuelve cero solo si todos sus controles pasan. Corregir los hallazgos restantes.
Una supresión exacta `# noqa: CODE` solo se permite ante un falso positivo y tras aprobar
el usuario su comentario explicativo. No debilitar reglas en `bolt.bend` para bajar el conteo.

El [README](../../README.md#development) describe instalación, disparadores de los hooks
y el alcance de los archivos parcialmente preparados.

Los gates formales se describen en [formal-verification.md](formal-verification.md);
las restricciones de efectos, en [host-effects.md](host-effects.md).

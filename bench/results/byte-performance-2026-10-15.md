# Resultados de rendimiento de MyLSM.Bytes

## Entorno y método

Para mantenimiento y fases se compararon baseline `d9ea63a0f360d921943cb4b3a85639b241a55f59` y candidato `6a031894a8af50d93cfb669c3b24196441db8c6c`. Los datos de ordenación y cursor se tomaron en sus commits limpios aislados, identificados en cada `metadata.txt` crudo. Todas las series usan el mismo Apple arm64, Bend 2.0.37, Apple Clang 19.1.7, compilación nativa por defecto y un hilo. Se alternaron cuatro bloques ABBA/BAAB y se conservaron ocho muestras por versión y carga. Los resultados crudos, logs y metadatos están bajo `bench/results/byte-performance-raw/`; la tabla normalizada está en `byte-performance-2026-10-15.tsv`.

Los casos públicos de mantenimiento usan una fixture SST de 16 000 claves y delta de 128 o 4 096 claves. La fixture se preparó una sola vez, se cerró y se copió antes de cada muestra. El reloj cubre `flush` o `compact`; luego se cierra y reabre la base y se comprueban las estadísticas visibles. El runner también registra RSS máximo y bytes en disco.

## Resultados

| Carga | Baseline mediana (rango) | Candidato mediana (rango) | Cambio | Muestras ganadas |
| --- | ---: | ---: | ---: | ---: |
| `order_unique`, 4 096 × 32 B | 26,5 ms (26–28) | 1 ms (1–2) | −96,2% | 8/8 |
| `order_unique`, 8 192 × 32 B | 121 ms (120–126) | 3 ms (2–6) | −97,5% | 8/8 |
| `order_unique`, 8 192 × 4 096 B | 142,5 ms (141–146) | 3 ms (2–6) | −97,9% | 8/8 |
| `scan_open`, delta 4 096 | 33,5 ms (33–36) | 1,5 ms (1–2) | −95,5% | 8/8 |
| `scan_next`, delta 4 096 × 4 096 B | 40,5 ms (40–42) | 2 ms (1–3) | −95,1% | 8/8 |
| `flush`, delta 128 | 5 246 ms (5 168–5 437) | 80,5 ms (78–90) | −98,5% | 8/8 |
| `compact`, delta 128 | 5 257,5 ms (5 162–5 432) | 80 ms (75–86) | −98,5% | 8/8 |
| `flush`, delta 4 096 | 5 427 ms (5 396–5 486) | 82,5 ms (80–94) | −98,5% | 8/8 |
| `compact`, delta 4 096 | 5 421,5 ms (5 369–5 625) | 81,5 ms (79–90) | −98,5% | 8/8 |

En mantenimiento, los bytes finales en disco coinciden por versión y carga: 1 585 152 bytes con delta 128 y 1 781 760 bytes con delta 4 096. El RSS mediano sube de 22 470 656 a 22 642 688 bytes con delta 128 y de 25 034 752 a 25 427 968 bytes con delta 4 096; son aumentos inferiores al 2%, no una mejora de memoria.

Las fases aisladas con fixture de 16 000 entradas dieron:

| Fase | Baseline mediana (rango) | Candidato mediana (rango) |
| --- | ---: | ---: |
| `ByteSstIo.read` | 3 120,5 ms (2 766–3 712) | 52 ms (43–250) |
| `ordered_entries`, 4 096 | 27 ms (27–31) | 1 ms (1–2) |
| `ByteSstFile.encode_file` | 18 ms (17–25) | 19 ms (17–21) |

Estas fases son medidas separadas y no se suman para estimar `flush`. El RSS máximo por fase cambia menos de 1% en lectura y codificación; la ordenación usa una entrada menor que 200 ms y su RSS es más ruidoso. Los datos observados no demuestran una reducción de memoria del escritor incremental.

## Decisiones

- **Ordenación balanceada: aceptar.** Los casos grandes y la operación pública `scan_open` superan ampliamente el umbral de tiempo y ganan las ocho muestras. La implementación mantiene prioridad de la mutación más reciente y tiene leyes/testigos en `laws/ByteMemTable.bend` y `proofs/ByteMemTableProof.bend`.
- **Evitar copias de valores al recorrer el cursor: aceptar.** `scan_next` con valores de 4 096 bytes mejora 95,1% y gana 8/8; los smokes de cursor y las leyes/testigos pasan. La igualdad de `Bytes.copy.bytes` sigue dependiendo de la primitiva Base y no se afirma como teorema de Bend.
- **Escritor incremental del SST: no implementar en esta iteración.** El candidato de ordenación ya baja el tiempo público de mantenimiento aproximadamente 98,5%; el RSS no muestra una regresión material que el cambio de streaming necesite corregir, y no existe una variante de escritor que demuestre la reducción de RSS de 15% exigida por el plan sin una regresión temporal. Cambiar el formato o la publicación sin esa evidencia aumentaría el riesgo sin una mejora medida.

## Límites de la evidencia

La fixture de mantenimiento inserta claves nuevas; no contiene reemplazos ni tombstones. No se ejecutó `scan_mixed`. La verificación del benchmark comprueba conteos, longitudes, estadísticas tras reopen y checksums estructurales, no un digest criptográfico de cada valor. Muchos casos pequeños duran menos de 200 ms y no se repitieron dentro de una misma ventana cronometrada; por eso las comparaciones de esos casos no se usan para aceptar cambios. `bend update` no pudo consultar la release remota porque falló DNS para `bend-lang.com`; ambos lados usaron la versión instalada y registrada, 2.0.37.

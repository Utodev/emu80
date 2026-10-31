# QUANTIKA: estado y cómo continuar

## Dónde está todo
- **Fuentes de las ROM:** `../quantika` (junto a emu80; repo propio, de momento con un solo commit y muchos cambios sin commitear).
  - Docs propias: README.md, NOTES.md, CLAUDE.md.
  - Regla absoluta: la palabra "M-S-X" no puede aparecer allí ni en las ROM, y `build.sh` falla si aparece.
  - Sin logo y sin pausa al arrancar.
- **Compilar:** `cd ../quantika && ./build.sh 2>&1 | python3 tools/fixjr.py` (sjasmplus.exe).
  - Genera `out/main_free.rom`, `out/sub_free.rom` y los .sym.
- **Instalar en emu80:** `../quantika/install.sh roms/msx` → `QUANTIKA.ROM` y `QUANTIKA_SUB.ROM`, que son las ROM por defecto (Models.pas).
  - `package.sh` de emu80 compila e instala quantika él solo.
- **Estructura:**
  - ROM principal: BIOS en la página 0 y FBASIC en la página 1. Los módulos se colocan con `tools/pack.py` según `layout_main.txt`.
  - Sub-ROM en el slot 3-1.
  - Servicios de FBASIC en la sub-ROM:
    - tabla en 0300h (`common/fbasicsub.inc`, lista de `jp` en `sub_free.asm`);
    - stubs en la ROM principal (`basic/substubs.asm`);
    - wrappers generados por `tools/mksubwrappers.py`. Cuidado con los choques de etiquetas entre la ROM principal y la sub-ROM (ya pasó con DeleteLine, SetText y SetPage).
- **ROM originales (solo como caja negra, nunca desensamblar):** `roms/msx/MSX2.rom`, `MSX2EXT.rom` y `PHILIPSDISK.rom`. Están en .gitignore y nunca se empaquetan.

## Herramientas de prueba (emu80)
- **`tests/msxfree.lpr`** → `tests/build/msxfree`. Se compila con:
  `fpc -O2 -Fusrc -FUtests/build -FEtests/build tests/msxfree.lpr`
  - Comandos: exec, basic, screen, pic, picdiff, tapeout, calls, trace.
  - Variables de entorno: MSXFREE_BREAK=addr[,addr], MSXFREE_BREAKSTACK=n, MSXFREE_DUMP=addr, MSXFREE_PIC, MSXFREE_VRAM, MSXFREE_PSGLOG, MSXFREE_CALLS.
  - Ejemplo de prueba BASIC: `tests/build/msxfree basic <carpeta_roms> "10 ...\nrun\n" 300`
   - Las carpetas de ROM llevan una subcarpeta `msx/` con `MSX2.rom` y `MSX2EXT.rom`.
    - Original: `tests/build/fbasic/orig`.
    - QUANTIKA: copiar `out/main_free.rom` como `MSX2.rom` y `out/sub_free.rom` como `MSX2EXT.rom`.
  - Ejemplo de cinta:
    `tests/build/msxfree picdiff tests/build/fbasic/orig <free> 25000 -tape "<fichero.cas>" -type 'run"cas:"\n'`
- **`tests/fbasic-difftests.sh`:** compara la original con QUANTIKA en todas las pruebas de `../quantika/tests`, tanto las .asm como las `basic/*.txt`.
  - Las cintas de prueba se generan con `tests/mkcas.py`.
- **`tests/run-tests.sh`:** la batería completa, que incluye la anterior. La última vez dio 501 ok, antes de los arreglos de FOR.
- **Juegos en cinta:** `to_be_ignored/MSX/games/tapes/*.cas`. El script `tapegames.sh` estaba en el scratchpad temporal, así que hay que rehacerlo si se ha perdido.

## Último trabajo (sin verificar del todo)
- **Bucle FOR con variable entera arreglado** en `basic/interp.asm` (StatementNext). Era un error grave: el bucle solo daba una vuelta.
  - Sobraba un `ex de,hl` antes de CompareIntegers.
  - El `add hl,de` + `jp pe` no detectaba el desbordamiento; se cambió por `or a / adc hl,de`.
  - Prueba nueva: `../quantika/tests/basic/forint.txt` (sale igual que la original).
- **Jet Set Willy:** el fallo de su cargador (línea 8) era ese FOR entero. Con el arreglo, picdiff da **12,0 % de píxeles distintos**: falta mirar la captura y averiguar la causa.
- **Pendiente tras cada arreglo:**
  - instalar las ROM en `roms/msx`;
  - pasar difftests y `run-tests.sh`;
  - volver a probar el lote de cintas;
  - si cambia `src/`: escribir `src/Release.inc`, compilar con `/mnt/c/lazarus/lazbuild.exe src/emu80.lpi` y hacer `mv -f src/emu80.exe emu80.exe`.
- `tests/msxfree.lpr` tiene la opción nueva MSXFREE_BREAKSTACK.

## Estado de las cintas
- **Head over Heels:** llega al título.
  - Necesitó un `ret` fijo en 4EF8h (`basic/compat.asm`) y la función SPRITE$.
  - Diferencia del 1,3 %: los extremos de los arcos de CIRCLE.
- **Jet Set Willy:** ver arriba.
- **Starquake y Cobra's Arc:** arreglados antes (DEF USR, escritura en cinta).
- **El resto del lote:** no conozco su estado actual; hay que volver a pasar todas las cintas.
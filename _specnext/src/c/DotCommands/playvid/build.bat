@rem build object file containing code and data ORGed into the main memory area at 0x8000

zcc +zxn -v -c -clib=sdcc_iy -SO3 --max-allocs-per-node200000 --opt-code-size --codesegCODE1 --constsegVARS1 --datasegVARS1 @zproject-ram.lst -o playvidp

@rem build dot with other source files destined for divmmc memory

zcc +zxn -v -m -startup=30 -clib=sdcc_iy -SO3 --max-allocs-per-node200000 --opt-code-size -gf=playvid.rxp @zproject-main.lst -o playvidp -pragma-include:zpragma.inc -subtype=dotn -Cm"--define=M4__CRT_APPEND_MMAP=1" -Cz"--clean --main-fence 0x9300" -create-app

@rem build video players

z88dk-z80asm -b -m=z80n video_256x192_m.asm
z88dk-z80asm -b -m=z80n video_256x192_m_palette.asm
z88dk-z80asm -b -m=z80n video_256x240.asm
z88dk-z80asm -b -m=z80n video_256x240_palette.asm
z88dk-z80asm -b -m=z80n video_320x240.asm
z88dk-z80asm -b -m=z80n video_320x240_palette.asm

@rem append video players to dot command

copy /b /y playvidp + video_320x240_palette.bin + video_320x240.bin + video_256x240_palette.bin + video_256x240.bin + video_256x192_m_palette.bin + video_256x192_m.bin PLAYVID

del playvidp *.o *.bin *.def

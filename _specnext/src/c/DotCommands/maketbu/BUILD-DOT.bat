@rem build a standard dot command < 8K but this time the bss, data and rodata sections are placed in main ram
@rem code is added to allocate a ram page to hold those sections and to initialize them

zcc +zxn -v -DSPECIALDOT -startup=30 -clib=sdcc_iy -SO3 --max-allocs-per-node200000 --opt-code-size @zproject-dot.lst -o pre --constsegsmc_compiler -pragma-include:zpragma-dot.inc -subtype=dot -create-app

@rem compress and append the data section to the dot command

z88dk-zx0 -f PRE_DATA.bin
copy /b PRE + PRE_DATA.bin.zx0 MAKETBU

@rem cleanup

@rem copy PRE.map MAKETBU.map
del /q PRE*

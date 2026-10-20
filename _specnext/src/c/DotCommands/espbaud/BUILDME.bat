@echo off

zcc +zxn -v -startup=30 -clib=sdcc_iy -SO3 --max-allocs-per-node200000 @zproject.lst -o espbaud -pragma-include:zpragma.inc -subtype=dot -Cz"--clean" -create-app
del /S espbaud_UNASSIGNED.bin zcc_opt.def

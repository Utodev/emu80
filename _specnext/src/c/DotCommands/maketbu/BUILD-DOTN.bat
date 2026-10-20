@rem build a dotn command where dot commands can be any size

zcc +zxn -v -startup=30 -clib=sdcc_iy -SO3 --max-allocs-per-node200000 --opt-code-size @zproject.lst -o maketbu -pragma-include:zpragma-dotn.inc -subtype=dotn -Cz"--clean" -create-app

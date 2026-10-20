all:
	zcc +zxn -v -c --codesegcode_dot --constsegrodata_dot -clib=sdcc_iy -SO3 --max-allocs-per-node200000 --opt-code-size config.c 
	zcc +zxn -v -startup=30 -clib=sdcc_iy -SO3 --max-allocs-per-node200000 --opt-code-size @zproject.lst -o config -pragma-include:zpragma.inc -subtype=dotn -Cz"--clean" -create-app

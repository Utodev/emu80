// prune stdio to what is needed

#pragma printf = ""

// do not create a heap for malloc

#pragma output CLIB_MALLOC_HEAP_SIZE = 0

// do not create extra space for opening FILEs

#pragma output CLIB_STDIO_HEAP_SIZE  = 0

// not returning to basic

#pragma output CRT_ON_EXIT = 0x10001   // halt

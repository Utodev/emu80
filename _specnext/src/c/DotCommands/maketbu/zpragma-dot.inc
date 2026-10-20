// Limit size of stdio

#pragma printf = "%s %u %c %X"
#pragma scanf = "%u %n"

// Room for one atexit function

#pragma output CLIB_EXIT_STACK_SIZE = 1

// Peel off data and bss sections from output binary

#pragma output CRT_ORG_DATA = 0x8000   // DATA + BSS org'd to 0x8000
#pragma output CRT_ORG_BSS  = -1       // BSS output separately from DATA

// Make sure data and bss sections are not initialized automatically by crt
// (this is the default but be explicit because code is being added to do init)

#pragma output CRT_INITIALIZE_BSS  = 0
#pragma output CRT_INITIALIZE_DATA = 0

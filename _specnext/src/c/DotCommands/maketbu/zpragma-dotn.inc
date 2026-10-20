// Limit size of stdio

#pragma printf = "%s %u %c %X"
#pragma scanf = "%u %n"

// Room for one atexit function

#pragma output CLIB_EXIT_STACK_SIZE = 1

// CONTROLS FOR DOT COMMANDS > 8K
// WE ONLY WANT TO USE 8K AT 0x8000 (LOGICAL PAGE 4) 

// Place stack at end of the 8K

#pragma output REGISTER_SP = 0x9FF0

// Logical -> Physical Lookup Table Only Needs To Cover Main Bank

#pragma output DOTN_LAST_PAGE = 11

// Only Want Page At 0x8000 Allocated

#pragma output DOTN_MAIN_ABSOLUTE_MASK = 0xEF

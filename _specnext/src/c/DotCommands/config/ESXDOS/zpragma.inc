// Use main memory starting at 0xe000

#pragma output CRT_ORG_MAIN = 0xe000

// Move stack to top of memory

#pragma output REGISTER_SP = 0

// Indicate this is for ESXDOS

#pragma output NEXTOS_VERSION = 0

// ESXDOS does not supply argv[0]

#pragma output CRT_ENABLE_COMMANDLINE_EX = 0

// Limit size of printf

#pragma printf = "%s %u"

// Room for one atexit function

#pragma output CLIB_EXIT_STACK_SIZE = 1

// Use main memory starting at 0xe000

#pragma output CRT_ORG_MAIN = 0xe000

// Move stack to top of memory

#pragma output REGISTER_SP = 0

// Indicate this is for NextZXOS 48k+

#pragma output NEXTOS_VERSION = -1

// Limit size of printf

#pragma printf = "%s %u"

// Room for one atexit function

#pragma output CLIB_EXIT_STACK_SIZE = 1

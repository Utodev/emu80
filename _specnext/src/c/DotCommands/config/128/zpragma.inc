// Move main bank org to mmu7

#pragma output CRT_ORG_MAIN = 0xe000

// Move stack to top of memory

#pragma output REGISTER_SP = 0

// Limit size of printf

#pragma printf = "%s %u"

// Room for one atexit function

#pragma output CLIB_EXIT_STACK_SIZE = 1

// Need enough pages to cover main bank in logical->physical table

#pragma output DOTN_LAST_PAGE = 11

// By default z88dk will allocate all main bank pages starting
// from the first occupied at address CRT_ORG_MAIN.  So here
// z88dk will be allocating pages for mmu7 only which is what we want.

// Load an alternate implementation if NextZXOS is in 48k mode

#pragma output DOTN_ENABLE_ALTERNATE = 1

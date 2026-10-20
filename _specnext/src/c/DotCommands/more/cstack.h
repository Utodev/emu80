#include <stdint.h>

#define CSTACK_SIZE 256
#define CSTACK_DATA_TYPE uint32_t
#define CSTACK_DEFAULT_VALUE 0

extern void cstack_init();
extern void cstack_push(CSTACK_DATA_TYPE);
extern CSTACK_DATA_TYPE cstack_pop();
extern unsigned int cstack_count();

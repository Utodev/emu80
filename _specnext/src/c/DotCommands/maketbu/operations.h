#ifndef _OPERATIONS_H
#define _OPERATIONS_H

#include <stdint.h>
#include <arch/zxn/esxdos.h>

extern uint32_t err_pos;
extern struct esx_dirent_lfn dirent;

extern void tbu_add(void);
extern void tbu_list(void);
extern void tbu_pull(unsigned int argc, unsigned char **argv);

#endif

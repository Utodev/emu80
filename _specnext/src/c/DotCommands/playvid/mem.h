#ifndef _MEM_H
#define _MEM_H

#include <adt/b_array.h>

extern b_array_t mem;                  // holds allocated memory pages
extern unsigned char mem_pages[224];   // mem array private data
extern unsigned char mem_start_page;   // first of 26 sequential memory pages for L2

extern void mem_init(void);
extern void mem_allocate_audio(void);
extern void mem_allocate_layer2(void);
extern void mem_free(void);

#endif

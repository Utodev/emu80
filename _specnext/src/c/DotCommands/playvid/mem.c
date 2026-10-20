#include <adt/b_array.h>
#include <stdlib.h>
#include <arch/zxn/esxdos.h>

#include "main.h"
#include "mem.h"

b_array_t mem;                     // keeps track of allocated pages for freeing later
unsigned char mem_pages[224];      // array holding allocated page numbers
unsigned char mem_start_page;      // first page of 26 sequentially allocated pages

static unsigned char n;
static unsigned char mem_seq_page;

void mem_init(void)
{
   b_array_init(&mem, mem_pages, sizeof(mem_pages));
}

void mem_allocate_audio(void)
{   
   // allocate one page for audio buffer
   
   if ((n = (unsigned char)esx_ide_bank_alloc(ESX_BANKTYPE_RAM)) == 0xff)
   {
      q_printf("X\n\ninsufficient memory\n");
      exit(ESX_EDEVICEBUSY);
   }
   
   b_array_push_back(&mem, n);
}

void mem_allocate_layer2(void)
{
   // allocation of ram required for two layer 2 80K screens (10 pages * 2)
   // more memory than needed will be acquired to simplify the player for now
   
   // allocate at least 26 contiguous pages with the first page having bit 4 reset
   // nextzxos allocation order is high page numbers to low page numbers
   
   // layer 2 starts on a bank number so first page must be even

   n = 0;
   mem_seq_page = 0;

   while ((mem_start_page = (unsigned char)esx_ide_bank_alloc(ESX_BANKTYPE_RAM)) != 0xff)
   {
      b_array_push_back(&mem, mem_start_page);
      
      n = (mem_start_page == mem_seq_page) ? (n + 1) : 1;
      mem_seq_page = mem_start_page - 1;
      
      if ((n >= 26) && ((mem_start_page & 0x11) == 0)) break;
   }

   if ((n < 26) || (mem_start_page & 0x11))
   {
      q_printf("X\n\ninsufficient memory\n");
      exit(ESX_EDEVICEBUSY);
   }
}

void mem_free(void)
{
   while ((n = (unsigned char)b_array_pop_back(&mem)) != 0xff)
      esx_ide_bank_free(ESX_BANKTYPE_RAM, n);
}

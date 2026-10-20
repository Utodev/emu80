#include <arch/zxn.h>
#include <string.h>

#include "mem.h"
#include "state.h"

extern unsigned char state_l2_palette[1024];

unsigned char state_register_i;

#define STATE_NR_STOP  19

struct state_nr state_nextreg[] = {

   // cpu speed, hw im2 not affected by state functions
   
   { 0x07, 0, 0x00, 0x03 },     //  0 cpu speed
   { 0xc0, 0, 0x1e, 0x01 },     //  1 hardware im2 mode
   
   // memory in mmu2, mmu3
   
   { 0x52, 0, 0x00, 0xff },     //  2 MMU2
   { 0x53, 0, 0x00, 0xff },     //  3 MMU3
   
   // nextreg controls
   
   { 0x05, 0, 0xfb, 0x00 },     //  4 50-60 Hz
   { 0x06, 0, 0x47, 0x00 },     //  5 disable hotkeys
   { 0x15, 0, 0x00, 0x02 },     //  6 SLU sprites disable   
   { 0x14, 0, 0x00, 0x00 },     //  7 global transparent colour (black)
   { 0x4a, 0, 0x00, 0x00 },     //  8 fallback colour (black)
   { 0x43, 0, 0x0b, 0x50 },     //  9 palette control
   { 0x40, 0, 0x00, 0x00 },     // 10 palette index
   { 0x12, 0, 0x00, 0x00 },     // 11 L2 active bank
   { 0x70, 0, 0x00, 0x00 },     // 12 L2 mode
   { 0x17, 0, 0x00, 0x00 },     // 13 L2 y scroll
   { 0x16, 0, 0x00, 0x00 },     // 14 L2 x scroll lsb
   { 0x71, 0, 0x00, 0x00 },     // 15 L2 x scroll msb
   { 0x68, 0, 0x7f, 0x80 },     // 16 disable ula
   { 0x6b, 0, 0x7f, 0x00 },     // 17 disable tilemap
   { 0x69, 0, 0x7f, 0x80 },     // 18 enable layer 2

   // L2 clipping rectangle handled separately
   // stop save nextreg here and manually fill in rest
   
   { 0x1c, 1, 0x00, 0x01 },     // 19 reset L2 clipping rectangle
   { 0x18, 0, 0x00, 0x00 },     // 20 L2 clip X1
   { 0x18, 0, 0x00, 0xff },     // 21 L2 clip X2
   { 0x18, 0, 0x00, 0x00 },     // 22 L2 clip Y1
   { 0x18, 0, 0x00, 0xbf }      // 23 L2 clip Y2
   
};

static unsigned char i;
static unsigned char *p;

void state_cls_l2(void)
{
   for (i = mem_start_page; i != mem_start_page + 26; ++i)
   {
      ZXN_WRITE_MMU3(i);
      memset((void *)0x6000, 0, 8192);

      if (i == mem_start_page + 9) i += 6;
   }
}

void state_save_l2_palette(void)
{
   i = 0;
   p = state_l2_palette - 1;
   
   ZXN_NEXTREGA(0x43, 0x90 | (state_nextreg[STATE_NR_43].old & 0x0f));  // L2 palette 0
   
   do
   {
      ZXN_NEXTREGA(0x40, i);       // palette index
      
      *++p = ZXN_READ_REG(0x41);   // 8-bits palette value
      *++p = ZXN_READ_REG(0x44);   // extra palette value
   }
   while (++i);

   ZXN_NEXTREGA(0x43, 0xd0 | (state_nextreg[STATE_NR_43].old & 0x0f));  // L2 palette 1
   
   do
   {
      ZXN_NEXTREGA(0x40, i);       // palette index

      *++p = ZXN_READ_REG(0x41);   // 8-bits palette value
      *++p = ZXN_READ_REG(0x44);   // extra palette value
   }
   while (++i);
}

void state_restore_l2_palette(void)
{
   i = 0;
   p = state_l2_palette - 1;
   
   ZXN_NEXTREGA(0x43, 0x10 | (state_nextreg[STATE_NR_43].old & 0x0f));  // L2 palette 0
   ZXN_NEXTREG(0x40, 0);   // palette index 0

   do
   {
      ZXN_NEXTREGA(0x44, *++p);
      ZXN_NEXTREGA(0x44, *++p);
   }
   while (++i);

   ZXN_NEXTREGA(0x43, 0x50 | (state_nextreg[STATE_NR_43].old & 0x0f));  // L2 palette 1
   ZXN_NEXTREG(0x40, 0);   // palette index 0

   do
   {
      ZXN_NEXTREGA(0x44, *++p);
      ZXN_NEXTREGA(0x44, *++p);
   }
   while (++i);
}

void state_init_l2_palette(void)
{
   i = 0;
   
   ZXN_NEXTREGA(0x43, 0x10 | (state_nextreg[STATE_NR_43].old & 0x0f));  // L2 palette 0
   ZXN_NEXTREG(0x40, 0);   // palette index 0
   
   do
   {
      ZXN_NEXTREGA(0x41, i);       // write fixed palette 8-bit colour
   }
   while (++i);

   ZXN_NEXTREGA(0x43, 0x50 | (state_nextreg[STATE_NR_43].old & 0x0f));  // L2 palette 1
   ZXN_NEXTREG(0x40, 0);   // palette index 0
   
   do
   {
      ZXN_NEXTREGA(0x41, i);       // write fixed palette 8-bit colour
   }
   while (++i);
}

void state_save_nextreg(void)
{   
   for (i = 2; i != STATE_NR_STOP; ++i)
   {
      state_nextreg[i].old = ZXN_READ_REG(state_nextreg[i].nextreg);
   }
   
   // save L2 clipping rectangle
   
   ZXN_NEXTREG(0x1c, 0x01);   // reset L2 clip index
   
   for (i = STATE_NR_18_X1; i != STATE_NR_18_Y2 + 1; ++i)
   {
      ZXN_NEXTREGA(0x18, state_nextreg[i].old = ZXN_READ_REG(0x18));
   }
   
   // corrections
   
   state_nextreg[STATE_NR_05].new = state_nextreg[STATE_NR_05].old & 0x04;   // current 50/60 Hz mode
}

void state_restore_nextreg(void)
{
   for (i = 2; i != sizeof(state_nextreg)/sizeof(*state_nextreg); ++i)
   {
      ZXN_WRITE_REG(state_nextreg[i].nextreg, state_nextreg[i].old);
   }
}

void state_init_nextreg(void)
{
   for (i = 2; i != sizeof(state_nextreg)/sizeof(*state_nextreg); ++i)
   {
      ZXN_WRITE_REG(state_nextreg[i].nextreg, (state_nextreg[i].old & state_nextreg[i].and) | state_nextreg[i].new);
   }
}

#ifndef _STATE_H
#define _STATE_H

struct state_nr
{
   unsigned char nextreg;
   unsigned char old;
   unsigned char and;
   unsigned char new;
};

extern struct state_nr state_nextreg[];

#define STATE_NR_07    0      //  0 cpu speed
#define STATE_NR_C0    1      //  1 hw im2 mode
#define STATE_NR_MMU2  2      //  2 MMU2
#define STATE_NR_MMU3  3      //  3 MMU3
#define STATE_NR_05    4      //  4 50-60 Hz
#define STATE_NR_43    9      //  9 palette control
#define STATE_NR_40    10     // 10 palette index
#define STATE_NR_12    11     // 11 L2 active page
#define STATE_NR_70    12     // 12 L2 mode
#define STATE_NR_17    13     // 13 L2 y scroll
#define STATE_NR_16    14     // 14 L2 x scroll lsb
#define STATE_NR_71    15     // 15 L2 x scroll msb
#define STATE_NR_18_X1 20     // 20 L2 clip X1 
#define STATE_NR_18_X2 21     // 21 L2 clip X2
#define STATE_NR_18_Y1 22     // 22 L2 clip Y1
#define STATE_NR_18_Y2 23     // 23 L2 clip Y2

extern void state_cls_l2(void);

extern void state_save_l2_palette(void);
extern void state_restore_l2_palette(void);
extern void state_init_l2_palette(void);

extern void state_save_nextreg(void);
extern void state_restore_nextreg(void);
extern void state_init_nextreg(void);

#endif

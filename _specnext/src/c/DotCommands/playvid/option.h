#ifndef _OPTION_H
#define _OPTION_H

#include <stdint.h>

struct option_flag
{
   unsigned char audio;
   unsigned char quiet;
   unsigned char info;
   unsigned char refresh;   // 1 = 50 Hz, 5 = 60 Hz
   unsigned char modifier;  // 1 = pause start, 2 = pause end, 4 = loop
};

extern struct option_flag option_flags;

extern uint32_t option_frame_start;
extern uint32_t option_frame_end;
extern uint32_t option_frame_count;

extern unsigned char option_process(unsigned char *s);

#endif

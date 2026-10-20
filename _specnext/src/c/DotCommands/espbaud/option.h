#ifndef OPTION_H
#define OPTION_H

#include <stdint.h>

struct flag
{
   unsigned char reset_hard;
   unsigned char version;
   unsigned char detect;
   unsigned char quiet;
   unsigned char permanent;
   unsigned char force;
   uint32_t      set_bps;   // non-zero indicates valid
};

extern struct flag flags;

extern void option_parse(unsigned char *s);

#endif

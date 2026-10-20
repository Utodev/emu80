#ifndef OPTION_H
#define OPTION_H

#include <stdint.h>

struct flag
{
   unsigned char xdna;
   unsigned char xadc_reset;
   unsigned char xadc;
};

extern struct flag flags;

extern void option_parse(unsigned char *s);

#endif

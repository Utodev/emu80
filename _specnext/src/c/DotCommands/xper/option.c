#include <arch/zxn/esxdos.h>
#include <errno.h>
#include <stdlib.h>

#include "option.h"

struct flag flags = { 0, 0, 0 };

void option_parse(unsigned char *s)
{
   if (*s == '-')
   {
      while (*++s)
      {
         switch (*s)
         {
            case 'd':
               flags.xdna = 1;
               break;
            
            case 'R':
            case 'r':
               flags.xadc_reset = 1;
               break;
            
            case 'x':
               flags.xadc = 1;
               break;

            default:
               exit(ESX_ENONSENSE);            
         }
      }
      
      return;
   }

   exit(ESX_ENONSENSE);
}

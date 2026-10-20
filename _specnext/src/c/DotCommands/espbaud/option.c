#include <arch/zxn/esxdos.h>
#include <stdlib.h>
#include <errno.h>

#include "option.h"

struct flag flags = { 0, 0, 0, 0, 0, 0, 0UL };

void option_parse(unsigned char *s)
{
   if (*s == '-')
   {
      while (*++s)
      {
         switch (*s)
         {
            case 'R':
               flags.reset_hard = 1;
               break;
            
            case 'd':
               flags.detect = 1;
               break;
            
            case 'q':
               flags.quiet = 1;
               break;
               
            case 'p':
               flags.permanent = 1;
               break;
               
            case 'v':
               flags.version = 1;
               break;
            
            case 'f':
               flags.force = 1;
               break;
            
            default:
               exit(ESX_ENONSENSE);            
         }
      }
      
      return;
   }
   else if (!flags.set_bps)
   {
      unsigned char *endp;
      
      // check for number
      
      errno = 0;
      flags.set_bps = strtoul(s, &endp, 10);
      
      if (!errno && !*endp) return;
   }
   
   exit(ESX_ENONSENSE);
}

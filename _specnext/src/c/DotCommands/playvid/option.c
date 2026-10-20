#include <ctype.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

#include <errno.h>
#include <arch/zxn/esxdos.h>

#include "option.h"
#include "sd.h"

uint32_t option_frame_start;
uint32_t option_frame_end = -1UL;
uint32_t option_frame_count;

struct option_flag option_flags;

unsigned char option_process(unsigned char *s)
{
   static unsigned char *endp;

   if (*s != '-') return 0;

   if (strcmp(s, "-50") == 0)
   {
      option_flags.refresh = 1;
      return 1;
   }
   
   if (strcmp(s, "-60") == 0)
   {
      option_flags.refresh = 5;
      return 1;
   }
   
   if (strncmp(s, "-f=", 3) == 0)
   {
      errno = 0;
      endp = s + 3;
      
      if (*endp != ',')
      {
         option_frame_start = strtol(endp, &endp, 0);
         if (errno || ((*endp != ',') && (*endp != '\0'))) exit(ESX_ENONSENSE);
      }
      
      if ((*endp == ',') && (*++endp != '\0'))
      {
         option_frame_end = strtol(endp, &endp, 0);
         if (errno || (*endp != '\0')) exit(ESX_ENONSENSE);
      }
      
      return 1;
   }
   
   if (strncmp(s, "-m=", 3) == 0)
   {
      for (s += 3; *s; ++s)
      {
         switch (tolower(*s))
         {
            case 's':
               option_flags.modifier |= 0x01;
               break;
            
            case 'e':
               option_flags.modifier |= 0x02;
               break;
            
            case 'l':
               option_flags.modifier |= 0x04;
               break;
            
            default:
               exit(ESX_ENONSENSE);
               break;
         }
      }
   
      return 1;
   }

   while (*++s)
   {
      switch (*s)
      {
         case 'a':
            option_flags.audio = 1;
            break;
            
         case 'q':
            option_flags.quiet = 1;
            break;
         
         case 'i':
            option_flags.info = 1;
            break;
         
         case '0':
         case '1':
         case '2':
         case '3':
         case '4':
         case '5':
            video_format = *s - '0' + 1;
            break;
         
         default:
            return 0;
      }
   }

   return 1;
}

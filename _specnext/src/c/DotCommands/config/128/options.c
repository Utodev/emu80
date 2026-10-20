#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <errno.h>
#include <arch/zxn.h>
#include <intrinsic.h>

#include "options.h"


// options search and sort

int sort_cmp_option(struct opt *a, struct opt *b)
{
   return stricmp(a->name, b->name);
}

int sort_opt_search(unsigned char *name, struct opt *a)
{
   if (a->type == OPT_TYPE_EXACT)
      return stricmp(name, a->name);
   
   return strnicmp(name, a->name, strlen(a->name));
}

// option arguments

static unsigned char *option_next_arg(unsigned char *idx, unsigned int argc, char **argv)
{
   if (++*idx < (unsigned char)argc) return strrstrip(strstrip(argv[*idx]));
   return 0;
}

static unsigned char *option_equal_arg(unsigned char *p)
{
   return strrstrip(strstrip(p));
}

static unsigned char *endp;

static unsigned char option_unsigned_number(unsigned char *p, unsigned int *res)
{
   if (p && *p)
   {
      errno = 0;
      *res = _strtou_(p, &endp, 0);
      
      if (errno == 0) return 1;  // success
   }
   
   return 0;                     // fail
}

// option error

unsigned int option_error(unsigned char *p)
{
   printf("Bad Parameter (%s)\n", p);
   return OPT_ACTION_OK;
}

// options

unsigned int option_exec_48k_helper(unsigned char t, unsigned char ct)
{
   ZXN_WRITE_REG(REG_MACHINE_TYPE, (ZXN_READ_REG(REG_MACHINE_TYPE) & 0x0f) | t);
   ZXN_WRITE_REG(REG_PERIPHERAL_3, (ZXN_READ_REG(REG_PERIPHERAL_3) & 0xbb) | ct);
   
   return OPT_ACTION_OK;
}

unsigned int option_exec_48k(void)
{
   // t=48, c=on, tmx=off
   return option_exec_48k_helper(0x80, 0x00);
}

unsigned int option_exec_128k(void)
{
   // t=128, c=on, tmx=off
   return option_exec_48k_helper(0xa0, 0x00);
}

unsigned int option_exec_plus3(void)
{
   // t=zxn, c=on, tmx=off
   return option_exec_48k_helper(0xb0, 0x00);
}

unsigned int option_exec_pentagon(void)
{
   // t=pent, c=off, tmx=off
   return option_exec_48k_helper(0xc0, 0x40);
}

unsigned int option_exec_zxn(void)
{
   // t=zxn, c=off, tmx=on
   return option_exec_48k_helper(0xb0, 0x44);
}

unsigned int option_exec_lock_helper(unsigned char val)
{
   if ((ZXN_READ_REG(REG_MACHINE_TYPE) & 0x6) == 0)
      return option_error("48k [un]lock");

   ZXN_WRITE_REG(REG_PERIPHERAL_3, (ZXN_READ_REG(REG_PERIPHERAL_3) & 0x7f) | val);
   return OPT_ACTION_OK;
}

unsigned int option_exec_lock(void)
{
   return option_exec_lock_helper(0);
}

unsigned int option_exec_unlock(void)
{
   return option_exec_lock_helper(0x80);
}

unsigned int option_exec_nextreg_helper(unsigned char *p)
{
   static unsigned int reg, val, mask;

   // nextreg reg,val[,mask]
   
   if (option_unsigned_number(p, &reg) && (reg < 256))
   {
      for (p = endp; isspace(*p) || (*p == ','); ++p) ;
      
      if (option_unsigned_number(p, &val) && (val < 256))
      {
         for (p = endp; isspace(*p) || (*p == ','); ++p) ;
         
         if (option_unsigned_number(p, &mask) && (mask < 256))
         {
            p = endp;
            val |= ZXN_READ_REG(reg) & mask;
         }
         
         if (*p == 0)
         {
            ZXN_WRITE_REG(reg, val);
            return OPT_ACTION_OK;
         }
      }
   }
   
   return option_error("nextreg");
}

unsigned int option_exec_nextreg(unsigned char *i, unsigned int argc, char **argv)
{
   return option_exec_nextreg_helper(option_next_arg(i, argc, argv));
}

unsigned int option_exec_nextreg_eq(unsigned char *i, unsigned int argc, char **argv)
{
   return option_exec_nextreg_helper(strchr(argv[*i], '=') + 1);
}

struct timing_type
{
   unsigned char *name;
   unsigned char value;
};

struct timing_type timing_types[] = {
   { "48", 0x80},
   { "48k", 0x80},
   { "128", 0xa0},
   { "128k", 0xa0},
   { "2", 0xa0},
   { "p", 0xc0},
   { "pent", 0xc0},
   { "pentagon", 0xc0},
   { "n", 0xb0},
   { "next", 0xb0},
   { "zxn", 0xb0},
   { "2A", 0xb0},
   { "2B", 0xb0},
   { "3", 0xb0},
   { "3E", 0xb0}
};

unsigned int option_exec_timing_helper(unsigned char *p)
{
   if (p && *p)
   {
      if (*p == '+') ++p;

      for (unsigned char i = 0; i != sizeof(timing_types) / sizeof(*timing_types); ++i)
      {
         if (stricmp(timing_types[i].name, p) == 0)
         {
            ZXN_NEXTREGA(REG_MACHINE_TYPE, (ZXN_READ_REG(REG_MACHINE_TYPE) & 0x0f) | timing_types[i].value);
            return OPT_ACTION_OK;
         }
      }
   }

   return option_error("timing");
}

unsigned int option_exec_timing(unsigned char *i, unsigned int argc, char **argv)
{
   return option_exec_timing_helper(option_next_arg(i, argc, argv));
}

unsigned int option_exec_timing_eq(unsigned char *i, unsigned int argc, char **argv)
{
   return option_exec_timing_helper(strchr(argv[*i], '=') + 1);
}

struct joy_type
{
   unsigned char *name;
   unsigned char value;
};

struct joy_type joy_types[] = {
   { "12345", 0x03 },
   { "s1", 0x03 },
   { "sinc1", 0x03 },
   { "sinclair1", 0x03 },
   { "67890", 0x00 },
   { "s2", 0x00 },
   { "sinc2", 0x00 },
   { "sinclair2", 0x00 },
   { "k", 0x01 },
   { "kemp", 0x01 },
   { "kempston", 0x01 },
   { "k1", 0x01 },
   { "kemp1", 0x01 },
   { "kempston1", 0x01 },
   { "k2", 0x04 },
   { "kemp2", 0x04 },
   { "kempston2", 0x04 },
   { "5678", 0x02 },
   { "c", 0x02 },
   { "cur", 0x02 },
   { "cursor", 0x02 },
   { "md1", 0x05 },
   { "md2", 0x06 }
};

unsigned int option_exec_joy_helper(unsigned char *p, unsigned char joy)
{
   static unsigned char mask, val;

   if (p && *p)
   {
      for (unsigned char i = 0; i != sizeof(joy_types) / sizeof(*joy_types); ++i)
      {
         // The compiler has not been modified to understand the size of
         // the new z80n instructions.  This loop has a nextreg instruction
         // that pushes the loop size out of range of a JR, causing an
         // assemble issue.  So NOPs have been manually inserted to increase
         // the size of the loop to avoid the JR substitution.

         intrinsic_nop();
         intrinsic_nop();
         
         if (stricmp(joy_types[i].name, p) == 0)
         {
            if (joy == 0)
            {
               mask = 0x37;
               val = (joy_types[i].value << 1) & 0x08;
               val |= (joy_types[i].value << 6) & 0xc0;
            }
            else
            {
               mask = 0xcd;
               val = (joy_types[i].value >> 1) & 0x02;
               val |= (joy_types[i].value << 4) & 0x30;
            }

            ZXN_NEXTREGA(REG_PERIPHERAL_1, (ZXN_READ_REG(REG_PERIPHERAL_1) & mask) | val);
            return OPT_ACTION_OK;
         }
      }
   }
   
   return option_error("joy");
}

unsigned int option_exec_joy0(unsigned char *i, unsigned int argc, char **argv)
{
   return option_exec_joy_helper(option_next_arg(i, argc, argv), 0); 
}

unsigned int option_exec_joy0_eq(unsigned char *i, unsigned int argc, char **argv)
{
   return option_exec_joy_helper(strchr(argv[*i], '=') + 1, 0);
}

unsigned int option_exec_joy1(unsigned char *i, unsigned int argc, char **argv)
{
   return option_exec_joy_helper(option_next_arg(i, argc, argv), 1);
}

unsigned int option_exec_joy1_eq(unsigned char *i, unsigned int argc, char **argv)
{
   return option_exec_joy_helper(strchr(argv[*i], '=') + 1, 1);
}

extern unsigned char original_cpu_speed;

unsigned int option_exec_turbo_35(void)
{
   original_cpu_speed = RTM_3MHZ;
   return OPT_ACTION_OK;
}

unsigned int option_exec_turbo_7(void)
{
   original_cpu_speed = RTM_7MHZ;
   return OPT_ACTION_OK;
}

unsigned int option_exec_turbo_14(void)
{
   original_cpu_speed = RTM_14MHZ;
   return OPT_ACTION_OK;
}

unsigned int option_exec_50hz(void)
{
   ZXN_NEXTREGA(REG_PERIPHERAL_1, ZXN_READ_REG(REG_PERIPHERAL_1) & 0xfb);
   return OPT_ACTION_OK;
}

unsigned int option_exec_60hz(void)
{
   ZXN_NEXTREGA(REG_PERIPHERAL_1, ZXN_READ_REG(REG_PERIPHERAL_1) | 0x04);
   return OPT_ACTION_OK;
}

struct scanline_type
{
   unsigned char *name;
   unsigned char value;
};

struct scanline_type scanline_types[] = {
   { "0", 0 },
   { "off", 0 },
   { "1", 0x03 },
   { "25", 0x03 },
   { "min", 0x03 },
   { "on", 0x02 },
   { "2", 0x02 },
   { "50", 0x02 },
   { "med", 0x02 },
   { "mid", 0x02 },
   { "medium", 0x02 },
   { "3", 0x01 },
   { "75", 0x01 },
   { "max", 0x01 },
   { "maximum", 0x01 }
};

unsigned int option_exec_scanline_helper(unsigned char *p)
{
   if (p && *p)
   {
      for (unsigned char i = 0; i != sizeof(scanline_types) / sizeof(*scanline_types); ++i)
      {
         if (stricmp(p, scanline_types[i].name) == 0)
         {
            ZXN_NEXTREGA(REG_PERIPHERAL_4, (ZXN_READ_REG(REG_PERIPHERAL_4) & 0xfc) | scanline_types[i].value);
            return OPT_ACTION_OK;
         }
      }
   }
   
   return option_error("scanline");
}

unsigned int option_exec_scanline(unsigned char *i, unsigned int argc, char **argv)
{
   return option_exec_scanline_helper(option_next_arg(i, argc, argv));
}

unsigned int option_exec_scanline_eq(unsigned char *i, unsigned int argc, char **argv)
{
   return option_exec_scanline_helper(strchr(argv[*i], '=') + 1);
}

struct contention_type
{
   unsigned char *name;
   unsigned char value;
};

struct contention_type contention_types[] =
{
   { "0", 0x40 },
   { "off", 0x40 },
   { "1", 0x00 },
   { "on", 0x00 }
};

unsigned int option_exec_contention_helper(unsigned char *p)
{
   if (p && *p)
   {
      for (unsigned char i = 0; i != sizeof(contention_types) / sizeof(*contention_types); ++i)
      {
         if (stricmp(p, contention_types[i].name) == 0)
         {
            ZXN_NEXTREGA(REG_PERIPHERAL_3, (ZXN_READ_REG(REG_PERIPHERAL_3) & 0xbf) | contention_types[i].value);
            return OPT_ACTION_OK;
         }
      }
   }
   
   return option_error("contention");
}

unsigned int option_exec_contention(unsigned char *i, unsigned int argc, char **argv)
{
   return option_exec_contention_helper(option_next_arg(i, argc, argv));
}

unsigned int option_exec_contention_eq(unsigned char *i, unsigned int argc, char **argv)
{
   return option_exec_contention_helper(strchr(argv[*i], '=') + 1);
}

struct ay_type
{
   unsigned char *name;
   unsigned char nextreg;
   unsigned char mask;
   unsigned char value;
};

// must have longer strings ahead of substrings

struct ay_type ay_types[] = {
   { "ts", REG_PERIPHERAL_3, 0xfd, 0x02 },
   { "turbosound", REG_PERIPHERAL_3, 0xfd, 0x02 },
   { "2", REG_PERIPHERAL_3, 0xfd, 0x02 },
   { "3", REG_PERIPHERAL_3, 0xfd, 0x02 },
   { "legacy", REG_PERIPHERAL_3, 0xfd, 0x00 },
   { "single", REG_PERIPHERAL_3, 0xfd, 0x00 },
   { "one", REG_PERIPHERAL_3, 0xfd, 0x00 },
   { "1", REG_PERIPHERAL_3, 0xfd, 0x00 },
   { "ay", REG_PERIPHERAL_2, 0xfc, 0x01 },
   { "ym", REG_PERIPHERAL_2, 0xfc, 0x00 },
   { "on", REG_PERIPHERAL_2, 0xfc, 0x00 },
   { "off", REG_PERIPHERAL_2, 0xfc, 0x03 },
   { "quiet", REG_PERIPHERAL_2, 0xfc, 0x03 },
   { "silent", REG_PERIPHERAL_2, 0xfc, 0x03 },
   { "mono", REG_PERIPHERAL_4, 0x1f, 0xe0 },
   { "m", REG_PERIPHERAL_4, 0x1f, 0xe0 },
   { "stereo", REG_PERIPHERAL_4, 0x1f, 0x00 },
   { "s", REG_PERIPHERAL_4, 0x1f, 0x00 },
   { "abc", REG_PERIPHERAL_3, 0xdf, 0x00 },
   { "acb", REG_PERIPHERAL_3, 0xdf, 0x20 }
};

unsigned int option_exec_aymode_helper(unsigned char *p)
{
   static unsigned char match;
   
   if (p && *p)
   {
      while (p && *p)
      {
         match = 0xff;
      
         for (unsigned char i = 0; i != sizeof(ay_types) / sizeof(*ay_types); ++i)
         {
            if (strnicmp(p, ay_types[i].name, strlen(ay_types[i].name)) == 0)
            {
               p += strlen(ay_types[i].name);
               while (isspace(*p)) ++p;
            
               if ((*p == 0) || (*p == ','))
                  match = i;
            
               while (isspace(*p) || (*p == ',')) ++p;
               break;
            }
         }
      
         if (match == 0xff)
            return option_error("aymode");
      
         ZXN_WRITE_REG(ay_types[match].nextreg, (ZXN_READ_REG(ay_types[match].nextreg) & ay_types[match].mask) | ay_types[match].value);
      }
      
      return OPT_ACTION_OK;
   }
   
   return option_error("aymode");
}

unsigned int option_exec_aymode(unsigned char *i, unsigned int argc, char **argv)
{
   return option_exec_aymode_helper(option_next_arg(i, argc, argv));
}

unsigned int option_exec_aymode_eq(unsigned char *i, unsigned int argc, char **argv)
{
   return option_exec_aymode_helper(strchr(argv[*i], '=') + 1);
}

struct ays_type
{
   unsigned char *name;
   unsigned char value;
};

struct ays_type ays_types[] = {
   { "m", 0xff },
   { "mono", 0xff },
   { "s", 0x00 },
   { "stereo", 0x00 }
};

unsigned int option_exec_ay_helper(unsigned char *p, unsigned char ay)
{
   static unsigned char mask;
   
   if (p && *p)
   {
      for (unsigned char i = 0; i != sizeof(ays_types) / sizeof(*ays_types); ++i)
      {
         if (stricmp(p, ays_types[i].name) == 0)
         {
            switch (ay)
            {
               case 0:
                  mask = 0x20;
                  break;
               
               case 1:
                  mask = 0x40;
                  break;
               
               default:
                  mask = 0x80;
                  break;
            }
            
            ZXN_NEXTREGA(REG_PERIPHERAL_4, (ZXN_READ_REG(REG_PERIPHERAL_4) & ~mask) |  (ays_types[i].value & mask));
            return OPT_ACTION_OK;
         }
      }
   }
   
   return option_error("ay");
}

unsigned int option_exec_ay0(unsigned char *i, unsigned int argc, char **argv)
{
   return option_exec_ay_helper(option_next_arg(i, argc, argv), 0);
}

unsigned int option_exec_ay0_eq(unsigned char *i, unsigned int argc, char **argv)
{
   return option_exec_ay_helper(strchr(argv[*i], '=') + 1, 0);
}

unsigned int option_exec_ay1(unsigned char *i, unsigned int argc, char **argv)
{
   return option_exec_ay_helper(option_next_arg(i, argc, argv), 1);
}

unsigned int option_exec_ay1_eq(unsigned char *i, unsigned int argc, char **argv)
{
   return option_exec_ay_helper(strchr(argv[*i], '=') + 1, 1);
}

unsigned int option_exec_ay2(unsigned char *i, unsigned int argc, char **argv)
{
   return option_exec_ay_helper(option_next_arg(i, argc, argv), 2);
}

unsigned int option_exec_ay2_eq(unsigned char *i, unsigned int argc, char **argv)
{
   return option_exec_ay_helper(strchr(argv[*i], '=') + 1, 2);
}

struct speaker_type
{
   unsigned char *name;
   unsigned char value;
};

struct speaker_type speaker_types[] = {
   { "0", 0x00 },
   { "off", 0x00 },
   { "1", 0x10 },
   { "on", 0x10 }
};

unsigned int option_exec_speaker_helper(unsigned char *p)
{
   if (p && *p)
   {
      for (unsigned char i = 0; i != sizeof(speaker_types) / sizeof(*speaker_types); ++i)
      {
         if (stricmp(p, speaker_types[i].name) == 0)
         {
            ZXN_NEXTREGA(REG_PERIPHERAL_3, (ZXN_READ_REG(REG_PERIPHERAL_3) & 0xef) | speaker_types[i].value);
            return OPT_ACTION_OK;
         }
      }
   }
   
   return option_error("speaker");
}

unsigned int option_exec_speaker(unsigned char *i, unsigned int argc, char **argv)
{
   return option_exec_speaker_helper(option_next_arg(i, argc, argv));
}

unsigned int option_exec_speaker_eq(unsigned char *i, unsigned int argc, char **argv)
{
   return option_exec_speaker_helper(strchr(argv[*i], '=') + 1);
}

struct timex_type
{
   unsigned char *name;
   unsigned char value;
};

struct timex_type timex_types[] = {
   { "0", 0x00 },
   { "off", 0x00 },
   { "1", 0x10 },
   { "on", 0x10 }
};

unsigned int option_exec_timex_helper(unsigned char *p)
{
   if (p && *p)
   {
      for (unsigned char i = 0; i != sizeof(timex_types) / sizeof(*timex_types); ++i)
      {
         if (stricmp(p, timex_types[i].name) == 0)
         {
            ZXN_NEXTREGA(REG_PERIPHERAL_3, (ZXN_READ_REG(REG_PERIPHERAL_3) & 0xfb) | timex_types[i].value);
            return OPT_ACTION_OK;
         }
      }
   }
   
   return option_error("timex");
}

unsigned int option_exec_timex(unsigned char *i, unsigned int argc, char **argv)
{
   return option_exec_timex_helper(option_next_arg(i, argc, argv));
}

unsigned int option_exec_timex_eq(unsigned char *i, unsigned int argc, char **argv)
{
   return option_exec_timex_helper(strchr(argv[*i], '=') + 1);
}

struct dac_type
{
   unsigned char *name;
   unsigned char value;
};

struct dac_type dac_types[] = {
   { "0", 0x00 },
   { "off", 0x00 },
   { "dis", 0x00 },
   { "disable", 0x00 },
   { "disabled", 0x00 },
   { "1", 0x08 },
   { "on", 0x08 },
   { "en", 0x08 },
   { "ena", 0x08 },
   { "enable", 0x08 },
   { "enabled", 0x08 }
};

unsigned int option_exec_dac_helper(unsigned char *p)
{
   if (p && *p)
   {
      for (unsigned char i = 0; i != sizeof(dac_types) / sizeof(*dac_types); ++i)
      {
         if (stricmp(p, dac_types[i].name) == 0)
         {
            ZXN_NEXTREGA(REG_PERIPHERAL_3, (ZXN_READ_REG(REG_PERIPHERAL_3) & 0xf7) | dac_types[i].value);
            return OPT_ACTION_OK;
         }
      }
   }
   
   return option_error("dac");
}

unsigned int option_exec_dac(unsigned char *i, unsigned int argc, char **argv)
{
   return option_exec_dac_helper(option_next_arg(i, argc, argv));
}

unsigned int option_exec_dac_eq(unsigned char *i, unsigned int argc, char **argv)
{
   return option_exec_dac_helper(strchr(argv[*i], '=') + 1);
}

struct dma_type
{
   unsigned char *name;
   unsigned char value;
};

struct dma_type dma_types[] = {
   { "zxn", 0 },
   { "z80", 0x40 }
};

unsigned int option_exec_dma_helper(unsigned char *p)
{
   if (p && *p)
   {
      for (unsigned char i = 0; i != sizeof(dma_types) / sizeof(*dma_types); ++i)
      {
         if (stricmp(p, dma_types[i].name) == 0)
         {
            ZXN_NEXTREGA(REG_PERIPHERAL_2, (ZXN_READ_REG(REG_PERIPHERAL_2) & 0xbf) | dma_types[i].value);
            return OPT_ACTION_OK;
         }
      }
   }
   
   return option_error("dma");
}

unsigned int option_exec_dma(unsigned char *i, unsigned int argc, char **argv)
{
   return option_exec_dma_helper(option_next_arg(i, argc, argv));
}

unsigned int option_exec_dma_eq(unsigned char *i, unsigned int argc, char **argv)
{
   return option_exec_dma_helper(strchr(argv[*i], '=') + 1);
}

unsigned int option_exec_help(void)
{
   flags.help = 1;
   return OPT_ACTION_OK;
}

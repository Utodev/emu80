/*
 * CONFIG
 * aralbrec@z88dk.org
*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <arch/zxn.h>

#include "info.h"
#include "options.h"


struct flag flags = {
   0              // help
};

static struct opt options[] = {
   { "48", OPT_TYPE_EXACT, (optfunc_t)option_exec_48k },
   { "48k", OPT_TYPE_EXACT, (optfunc_t)option_exec_48k },
   { "128", OPT_TYPE_EXACT, (optfunc_t)option_exec_128k },
   { "128k", OPT_TYPE_EXACT, (optfunc_t)option_exec_128k },
   { "2", OPT_TYPE_EXACT, (optfunc_t)option_exec_128k },
   { "+2", OPT_TYPE_EXACT, (optfunc_t)option_exec_128k },
   { "2a", OPT_TYPE_EXACT, (optfunc_t)option_exec_plus3 },
   { "+2a", OPT_TYPE_EXACT, (optfunc_t)option_exec_plus3 },
   { "2b", OPT_TYPE_EXACT, (optfunc_t)option_exec_plus3 },
   { "+2b", OPT_TYPE_EXACT, (optfunc_t)option_exec_plus3 },
   { "3", OPT_TYPE_EXACT, (optfunc_t)option_exec_plus3 },
   { "+3", OPT_TYPE_EXACT, (optfunc_t)option_exec_plus3 },
   { "3e", OPT_TYPE_EXACT, (optfunc_t)option_exec_plus3 },
   { "+3e", OPT_TYPE_EXACT, (optfunc_t)option_exec_plus3 },
   { "p", OPT_TYPE_EXACT, (optfunc_t)option_exec_pentagon },
   { "pent", OPT_TYPE_EXACT, (optfunc_t)option_exec_pentagon },
   { "pentagon", OPT_TYPE_EXACT, (optfunc_t)option_exec_pentagon },
   { "zxn", OPT_TYPE_EXACT, (optfunc_t)option_exec_zxn },
   { "next", OPT_TYPE_EXACT, (optfunc_t)option_exec_zxn },
   
   { "lock", OPT_TYPE_EXACT, (optfunc_t)option_exec_lock },
   { "unlock", OPT_TYPE_EXACT, (optfunc_t)option_exec_unlock },

   { "nr", OPT_TYPE_EXACT, (optfunc_t)option_exec_nextreg },
   { "nr=", OPT_TYPE_LEADING, (optfunc_t)option_exec_nextreg_eq },
   { "nextreg", OPT_TYPE_EXACT, (optfunc_t)option_exec_nextreg },
   { "nextreg=", OPT_TYPE_LEADING, (optfunc_t)option_exec_nextreg_eq },

   { "t", OPT_TYPE_EXACT, (optfunc_t)option_exec_timing },
   { "timing", OPT_TYPE_EXACT, (optfunc_t)option_exec_timing },
   { "t=", OPT_TYPE_LEADING, (optfunc_t)option_exec_timing_eq },
   { "timing=", OPT_TYPE_LEADING, (optfunc_t)option_exec_timing_eq },

   { "jl", OPT_TYPE_EXACT, (optfunc_t)option_exec_joy0 },
   { "jl=", OPT_TYPE_LEADING, (optfunc_t)option_exec_joy0_eq },
   { "joyl", OPT_TYPE_EXACT, (optfunc_t)option_exec_joy0 },
   { "joyl=", OPT_TYPE_LEADING, (optfunc_t)option_exec_joy0_eq },
   { "left", OPT_TYPE_EXACT, (optfunc_t)option_exec_joy0 },
   { "left=", OPT_TYPE_LEADING, (optfunc_t)option_exec_joy0_eq },
   { "j0", OPT_TYPE_EXACT, (optfunc_t)option_exec_joy0 },
   { "j0=", OPT_TYPE_LEADING, (optfunc_t)option_exec_joy0_eq },
   { "joy0", OPT_TYPE_EXACT, (optfunc_t)option_exec_joy0 },
   { "joy0=", OPT_TYPE_LEADING, (optfunc_t)option_exec_joy0_eq },

   { "jr", OPT_TYPE_EXACT, (optfunc_t)option_exec_joy1 },
   { "jr=", OPT_TYPE_LEADING, (optfunc_t)option_exec_joy1_eq },
   { "joyr", OPT_TYPE_EXACT, (optfunc_t)option_exec_joy1 },
   { "joyr=", OPT_TYPE_LEADING, (optfunc_t)option_exec_joy1_eq },
   { "right", OPT_TYPE_EXACT, (optfunc_t)option_exec_joy1 },
   { "right=", OPT_TYPE_LEADING, (optfunc_t)option_exec_joy1_eq },
   { "j1", OPT_TYPE_EXACT, (optfunc_t)option_exec_joy1 },
   { "j1=", OPT_TYPE_LEADING, (optfunc_t)option_exec_joy1_eq },
   { "joy1", OPT_TYPE_EXACT, (optfunc_t)option_exec_joy1 },
   { "joy1=", OPT_TYPE_LEADING, (optfunc_t)option_exec_joy1_eq },

   { "3.5", OPT_TYPE_EXACT, (optfunc_t)option_exec_turbo_35 },
   { "3.5MHz", OPT_TYPE_EXACT, (optfunc_t)option_exec_turbo_35 },
   { "7", OPT_TYPE_EXACT, (optfunc_t)option_exec_turbo_7 },
   { "7MHz", OPT_TYPE_EXACT, (optfunc_t)option_exec_turbo_7 },
   { "14", OPT_TYPE_EXACT, (optfunc_t)option_exec_turbo_14 },
   { "14MHz", OPT_TYPE_EXACT, (optfunc_t)option_exec_turbo_14 },

   { "50", OPT_TYPE_EXACT, (optfunc_t)option_exec_50hz },
   { "50hz", OPT_TYPE_EXACT, (optfunc_t)option_exec_50hz },
   { "60", OPT_TYPE_EXACT, (optfunc_t)option_exec_60hz },
   { "60hz", OPT_TYPE_EXACT, (optfunc_t)option_exec_60hz },
   
   { "dma", OPT_TYPE_EXACT, (optfunc_t)option_exec_dma },
   { "dma=", OPT_TYPE_LEADING, (optfunc_t)option_exec_dma_eq },

   { "sl", OPT_TYPE_EXACT, (optfunc_t)option_exec_scanline },
   { "sl=", OPT_TYPE_LEADING, (optfunc_t)option_exec_scanline_eq },
   { "scanline", OPT_TYPE_EXACT, (optfunc_t)option_exec_scanline },
   { "scanline=", OPT_TYPE_LEADING, (optfunc_t)option_exec_scanline_eq },
   { "scanlines", OPT_TYPE_EXACT, (optfunc_t)option_exec_scanline },
   { "scanlines=", OPT_TYPE_LEADING, (optfunc_t)option_exec_scanline_eq },

   { "c", OPT_TYPE_EXACT, (optfunc_t)option_exec_contention },
   { "c=", OPT_TYPE_LEADING, (optfunc_t)option_exec_contention_eq },
   { "con", OPT_TYPE_EXACT, (optfunc_t)option_exec_contention },
   { "con=", OPT_TYPE_LEADING, (optfunc_t)option_exec_contention_eq },
   { "contention", OPT_TYPE_EXACT, (optfunc_t)option_exec_contention },
   { "contention=", OPT_TYPE_LEADING, (optfunc_t)option_exec_contention_eq },

   { "aymode", OPT_TYPE_EXACT, (optfunc_t)option_exec_aymode },
   { "aymode=", OPT_TYPE_LEADING, (optfunc_t)option_exec_aymode_eq },
   { "ay", OPT_TYPE_EXACT, (optfunc_t)option_exec_aymode },
   { "ay=", OPT_TYPE_LEADING, (optfunc_t)option_exec_aymode_eq },
   { "audio", OPT_TYPE_EXACT, (optfunc_t)option_exec_aymode },
   { "audio=", OPT_TYPE_LEADING, (optfunc_t)option_exec_aymode_eq },
   { "sound", OPT_TYPE_EXACT, (optfunc_t)option_exec_aymode },
   { "sound=", OPT_TYPE_LEADING, (optfunc_t)option_exec_aymode_eq },

   { "ay0", OPT_TYPE_EXACT, (optfunc_t)option_exec_ay0 },
   { "ay0=", OPT_TYPE_LEADING, (optfunc_t)option_exec_ay0_eq },
   { "ay1", OPT_TYPE_EXACT, (optfunc_t)option_exec_ay1 },
   { "ay1=", OPT_TYPE_LEADING, (optfunc_t)option_exec_ay1_eq },
   { "ay2", OPT_TYPE_EXACT, (optfunc_t)option_exec_ay2 },
   { "ay2=", OPT_TYPE_LEADING, (optfunc_t)option_exec_ay2_eq },

   { "speaker", OPT_TYPE_EXACT, (optfunc_t)option_exec_speaker },
   { "speaker=", OPT_TYPE_LEADING, (optfunc_t)option_exec_speaker_eq },
   { "beeper", OPT_TYPE_EXACT, (optfunc_t)option_exec_speaker },
   { "beeper=", OPT_TYPE_LEADING, (optfunc_t)option_exec_speaker_eq },
   
   { "dac", OPT_TYPE_EXACT, (optfunc_t)option_exec_dac },
   { "dac=", OPT_TYPE_LEADING, (optfunc_t)option_exec_dac_eq },
   { "dacs", OPT_TYPE_EXACT, (optfunc_t)option_exec_dac },
   { "dacs=", OPT_TYPE_LEADING, (optfunc_t)option_exec_dac_eq },
   { "covox", OPT_TYPE_EXACT, (optfunc_t)option_exec_dac },
   { "covox=", OPT_TYPE_LEADING, (optfunc_t)option_exec_dac_eq },
   { "specdrum", OPT_TYPE_EXACT, (optfunc_t)option_exec_dac },
   { "specdrum=", OPT_TYPE_LEADING, (optfunc_t)option_exec_dac_eq },

   { "timex", OPT_TYPE_EXACT, (optfunc_t)option_exec_timex },
   { "timex=", OPT_TYPE_LEADING, (optfunc_t)option_exec_timex_eq },
   { "tmx", OPT_TYPE_EXACT, (optfunc_t)option_exec_timex },
   { "tmx=", OPT_TYPE_LEADING, (optfunc_t)option_exec_timex_eq },
   { "hi-res", OPT_TYPE_EXACT, (optfunc_t)option_exec_timex },
   { "hi-res=", OPT_TYPE_LEADING, (optfunc_t)option_exec_timex_eq },
   { "hires", OPT_TYPE_EXACT, (optfunc_t)option_exec_timex },
   { "hires=", OPT_TYPE_LEADING, (optfunc_t)option_exec_timex_eq },
   { "hi-col", OPT_TYPE_EXACT, (optfunc_t)option_exec_timex },
   { "hi-col=", OPT_TYPE_LEADING, (optfunc_t)option_exec_timex_eq },
   { "hicol", OPT_TYPE_EXACT, (optfunc_t)option_exec_timex },
   { "hicol=", OPT_TYPE_LEADING, (optfunc_t)option_exec_timex_eq },
   { "hi-colour", OPT_TYPE_EXACT, (optfunc_t)option_exec_timex },
   { "hi-colour=", OPT_TYPE_LEADING, (optfunc_t)option_exec_timex_eq },
   { "hi-color", OPT_TYPE_EXACT, (optfunc_t)option_exec_timex },
   { "hi-color=", OPT_TYPE_LEADING, (optfunc_t)option_exec_timex_eq },
   { "hicolour", OPT_TYPE_EXACT, (optfunc_t)option_exec_timex },
   { "hicolour=", OPT_TYPE_LEADING, (optfunc_t)option_exec_timex_eq },
   { "hicolor", OPT_TYPE_EXACT, (optfunc_t)option_exec_timex },
   { "hicolor=", OPT_TYPE_LEADING, (optfunc_t)option_exec_timex_eq },

   { "h", OPT_TYPE_EXACT, (optfunc_t)option_exec_help },
   { "help", OPT_TYPE_EXACT, (optfunc_t)option_exec_help }
};

unsigned char original_cpu_speed;

static void cleanup(void)
{
   ZXN_NEXTREGA(REG_TURBO_MODE, original_cpu_speed);
}

int main(unsigned int argc, char **argv)
{
   static struct opt *found;

   // initialization
   
   original_cpu_speed = ZXN_READ_REG(REG_TURBO_MODE);

#ifndef ESXDOS
#define RTM_28MHZ       3
   ZXN_NEXTREG(REG_TURBO_MODE, RTM_28MHZ);
#endif

   atexit(cleanup);
   
   // parse options
   
   qsort(options, sizeof(options)/sizeof(*options), sizeof(*options), sort_cmp_option);
   
   if (argc == 1)
   {
      // no options, print configuration information
      
      printf("\n"
             "Configuration\n"
             "-------------\n\n"
             
             "Core v%s\n"
             "%s\n\n"
             
             "Machine: %s\n"
             "Timing: %s\n\n"
             
             "Video: %s %s\n"
             "Scanlines: %s\n\n"
             
             "CPU Speed: %s\n"
             "DMA: %s Mode\n\n"
             
             "Timex Video: %s\n"
             "ULA Contention: %s\n\n"
             
             "Speaker: %s\n"
             "DACs: %s\n"
             "AY mode: %s\n\n"
             
             "AY0: %s\n"
             "AY1: %s\n"
             "AY2: %s\n\n"
             
             "Joy0: %s\n"
             "Joy1: %s\n\n"
             
             "config -h for help\n",

             info_core(),
             info_os(),
             
             info_machine(),
             info_timing(),
             
             info_refresh(), info_video(),
             info_scanlines(),
             
             info_cpu(),
             info_dma(),
             info_timex(),
             info_ula(),
             
             info_speaker(),
             info_dac(),
             info_aymode(),
             
             info_ay(0),
             info_ay(1),
             info_ay(2),
             
             info_joy(0),
             info_joy(1)
            );

      exit(0);
   }
   else
   {
      for (unsigned char i = 1; i < (unsigned char)argc; ++i)
      {
         unsigned int ret;
         
         // strip surrounding whitespace possibly from quoting
         
         argv[i] = strrstrip(strstrip(argv[i]));
         
         // accept one or two leading minus
         
         if (*argv[i] == '-') ++argv[i];
         if (*argv[i] == '-') ++argv[i];

         // check for option
         
         if ((found = bsearch(argv[i], options, sizeof(options)/sizeof(*options), sizeof(*options), sort_opt_search)) == 0)
            exit((int)"A Invalid optio" "\xee");
         
         // execute option
         
         //printf("\nargv[i] = %s\n", argv[i]);
         //printf("action = 0x%X\n\n", (unsigned int)(found->action));
         
         if ((ret = (found->action)(&i, argc, argv)) != OPT_ACTION_OK)
            exit(ret);
      }
   }
   
   // help
   
   if (flags.help)
   {
      // print help text
      
      printf("\n"
             "CONFIG - configure zxn hardware\n\n"
             "config\n"
             "Describe current configuration\n\n"
             "config [OPTION=VALUE]...\n"
             "Change current configuration\n\n"
             "PRESETS\n"
             "Select machine appropriate\n"
             "timing, contention, float bus\n\n"
             "48, 48k\n"
             "128, 128k, 2\n"
             "3, 2A, 2B, 3E\n"
             "p, pent, pentagon\n"
             "zxn\n\n"
             "NEXTREG\n\n"
             "nr=, nextreg=reg,val[,mask]\n"
             "  Write val to reg.  Optional\n"
             "  mask is ANDed with current\n"
             "  reg contents then val is ORed\n"
             "  with the result before write.\n\n"
             "CPU & DMA\n\n"
             "3.5\n"
             "  Set 3.5MHz\n\n"
             "7\n"
             "  Set 7MHz\n\n"
             "14\n"
             "  Set 14MHz\n\n"
             "dma=z80,zxn\n"
             "  Select DMA compatibility mode\n\n"
             "COMPATIBILITY\n\n"
             "t=, timing=48,128,next,pent...\n"
             "  Select display timing.\n"
             "  Some software expects to run\n"
             "  on specific machines for\n"
             "  proper display.\n\n"
             "tmx=, timex=on,off...\n"
             "  Timex video modes enable.\n"
             "  Disabling activates floating\n"
             "  bus reads on port 0xff.\n\n"
             "c=, con=, contention=on,off...\n"
             "  RAM Contention enable.\n"
             "  Some software expects RAM\n"
             "  contention for proper display\n\n"
             "lock\n"
             "  Lock 0x7ffd paging\n\n"
             "unlock\n"
             "  Unlock 0x7ffd paging\n\n"
             "DISPLAY\n\n"
             "50, 60\n"
             "  Select 50Hz or 60Hz display\n\n"
             "sl=,scanlines=0,25,50,75...\n"
             "  Enable scanlines\n\n"
             "AUDIO\n\n"
             "beeper=, speaker=on,off...\n"
             "  Internal speaker enable\n\n"
             "dacs=on,off...\n"
             "  Audio DACs enable\n\n"
             "aymode=[ay|ym|off],[abc|acb],\n"
             "  [mono|stereo],[1|2|3|ts]...\n"
             "  Chooses features for all AY\n"
             "  instances.  Mono, stereo, ABC\n"
             "  or ACB stereo, one or three\n"
             "  active.\n\n"
             "ay0=mono,stereo...\n"
             "ay1=mono,stereo...\n"
             "ay2=mono,stereo...\n"
             "  Affects specific AY instance.\n\n"
             "JOYSTICKS\n\n"
             "j0=,joy0=,left=\n"
             "j1=,joy1=,right=\n"
             "  [s1|sinc1|sinclair1|12345]\n"
             "  [s2|sinc2|sinclair2|67890]\n"
             "  [k|kemp|kempston|k1|kemp1]\n"
             "  [k2|kemp2|kempston2]\n"
             "  [c|cur|cursor|5678]\n"
             "  [md1]\n"
             "  [md2]\n\n"
             "config v1.1 z88dk.org\n"
            );
   }
   
   return 0;
}

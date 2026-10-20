#include <stdio.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <input.h>
#include <intrinsic.h>

#include <arch/zxn.h>
#include <arch/zxn/esxdos.h>

__sfr __at 0x6b IO_DMA;
__sfr __banked __at 0x193b IO_CTC_1;
__sfr __banked __at 0x1a3b IO_CTC_2;

#include "mem.h"
#include "main.h"
#include "option.h"
#include "sd.h"
#include "state.h"
#include "user_interaction.h"
#include "video.h"


uint32_t total_frame_count;
unsigned char (*play_video)(void);


void q_printf(unsigned char *format, ...)
{
   va_list v;
   va_start(v, format);
   
   if (option_flags.quiet == 0) vprintf(format, v);
}

void cleanup(void)
{
   ZXN_WRITE_MMU2(state_nextreg[STATE_NR_MMU2].old);
   ZXN_WRITE_MMU3(state_nextreg[STATE_NR_MMU3].old);

   if (fd != 0xff) esx_f_close(fd);
   
   mem_free();
   
   intrinsic_halt();   // no ula int while hardware im2 exited, reduce L2 artifacts
   intrinsic_di();     // no ints until im1 restored
   
   ZXN_NEXTREGA(0xc0, state_nextreg[STATE_NR_C0].old);
   
   state_restore_l2_palette();
   state_restore_nextreg();

   ZXN_NEXTREGA(0x07, state_nextreg[STATE_NR_07].old);

   // crt restores main memory space and im1
}

extern unsigned char main_help[];

unsigned char pause_key(void)
{
   unsigned char c;
   
   in_wait_key();
   intrinsic_halt();   // small delay needed for hw to go from CAPS to CAPS+SPACE for BREAK key
         
   c = in_inkey();
   in_wait_nokey();
   
   return c;
}

unsigned int main(unsigned int argc, unsigned char **argv)
{
   static unsigned char c;
   static unsigned char *s;
   static unsigned char **p;

   // cleanup
   
   state_nextreg[STATE_NR_07].old = ZXN_READ_REG(0x07) & 0x03;
   ZXN_NEXTREG(0x07, 0x03);   // 28 MHz

   state_nextreg[STATE_NR_C0].old = ZXN_READ_REG(0xc0);
   
   IO_CTC_1 = 0x03;    // RESET
   IO_CTC_1 = 0x03;
   
   IO_CTC_2 = 0x03;    // RESET
   IO_CTC_2 = 0x03;
   
   IO_DMA = 0x83;      // DISABLE
   IO_DMA = 0xc3;      // RESET

   state_save_nextreg();
   state_save_l2_palette();   // damages nextreg 0x43, 0x40
   
   ZXN_NEXTREGA(0x43, state_nextreg[STATE_NR_43].old);
   ZXN_NEXTREGA(0x40, state_nextreg[STATE_NR_40].old);
   
   mem_init();

   atexit(cleanup);
   
   // parse command line

   if (argc == 1)
   {
      strupr(argv[0]);
      
      // main_help[] only available before calling sd_enumerate_file_fragments()
      // VERSION is hard coded in main_help[] string in interrupts-common.asm
      
      printf(main_help, argv[0], argv[0]);
      
      exit(0);
   }

   p = argv;
   for (c = 1; c != (unsigned char)argc; ++c)
      if (option_process(strrstrip(strstrip(*++p))) == 0) break;
   
   q_printf("* ZX Spectrum Next VPlayer " VERSION " *\n\n");
   
   while (c != (unsigned char)argc)
   {
      s = strrstrip(strstrip(*p));
   
      q_printf("mapping %s - ", s);
      
      sd_enumerate_file_fragments(s);
      
      q_printf("ok\n");
      
      ++c;
      ++p;
   }
   
   memset((void *)&fm_entries[n_entries], 0, (FILEMAP_ENTRIES - n_entries) * sizeof(*fm_entries));   // zero array after last valid entry

   // determine video format

   sd_classify_video_format();

   // load player code
   // video players are 0x10000 - 0x9300 bytes
   
   q_printf("loading player - ");

   c = esx_m_gethandle();

   if (video_format && (esx_f_seek(c, (uint32_t)(video_format) * VIDEO_PLAYER_CODE_SIZE, ESX_SEEK_FWD) == -1UL))
   {
      q_printf("X\n\nseek error\n");
      exit(ESX_EIO);
   }

   if (esx_f_read(c, (void *)0x9300, VIDEO_PLAYER_CODE_SIZE) != VIDEO_PLAYER_CODE_SIZE)
   {
      q_printf("X\n\ndot load error\n");
      exit(ESX_EIO);
   }

   q_printf("ok\n");
   
   // information

   total_frame_count = filesz / (uint32_t)video_player_info.frame_size;

   if (option_flags.info || (option_flags.quiet == 0))
   {
      printf("\n%s\n", video_player_info.description);
      printf("frame total %lu\n", total_frame_count);
      
      if (n_entries == 1)
      {
         printf("file is not fragmented\n\n");
      }
      else
      {
         printf("file fragmented %u/%u\n\n", n_entries, FILEMAP_ENTRIES - 1);
      }

      if (option_flags.quiet) exit(0);
   }
   
   // compute the frame range to play
   
   if ((int32_t)option_frame_start < 0)
      option_frame_start += total_frame_count;
   
   if ((int32_t)option_frame_end < 0)
      option_frame_end += total_frame_count;
   
   if (((int32_t)option_frame_start < 0) ||
       ((int32_t)option_frame_end < 0) ||
       (option_frame_start >= total_frame_count) ||
       (option_frame_end >= total_frame_count) ||
       (option_frame_end < option_frame_start))
   {
      q_printf("frame out of range\n");
      exit(ESX_ENONSENSE);
   }
    
   option_frame_count = option_frame_end - option_frame_start + 1;

   // allocate memory
   // requires mmu2 to be unchanged from basic
   
   q_printf("allocating memory - ");

   mem_allocate_audio();     // audio buffer in position 0
   mem_allocate_layer2();    // 80K * 2 for double buffered layer 2

   q_printf("ok\n\n");

   // LET'S GOOOO
   
   // take care of options and video player L2 settings
   
   if (option_flags.refresh)
      state_nextreg[STATE_NR_05].new = option_flags.refresh - 1;
   
   state_nextreg[STATE_NR_70].new = video_player_info.mode;
   state_nextreg[STATE_NR_17].new = video_player_info.scroll_y;
   state_nextreg[STATE_NR_16].new = video_player_info.scroll_x_lsb;
   state_nextreg[STATE_NR_71].new = video_player_info.scroll_x_msb & 0x01;
   state_nextreg[STATE_NR_18_X1].new = video_player_info.clip_x1;
   state_nextreg[STATE_NR_18_X2].new = video_player_info.clip_x2;
   state_nextreg[STATE_NR_18_Y1].new = video_player_info.clip_y1;
   state_nextreg[STATE_NR_18_Y2].new = video_player_info.clip_y2;
   
   // from this point mmu2 and mmu3 can be changed so no more calls to printf or q_printf

   intrinsic_halt();           // change to hw im2 mode after ula interrupt

   ZXN_NEXTREGA(0xc0, (state_nextreg[STATE_NR_C0].old & 0x1e) + 1);   // enter hw im2 mode
   intrinsic_im_2();

// WHY ???  investigate may be hw bug
__asm
   call blahblah
   jr blah
blahblah:
   reti
blah:
__endasm;

   state_cls_l2();             // clear allocated l2 pages to black

   video_player_vars.w_layer2_page = mem_start_page + 16;   // L2 page to write to
   video_player_vars.w_layer2_palette = 0x50;               // use L2 palette 0, write to L2 palette 1, auto-inc
   
   state_nextreg[STATE_NR_12].new = mem_start_page / 2;     // active L2 bank
   state_nextreg[STATE_NR_43].new = 0x50;                   // use L2 palette 0, write to L2 palette 1, auto-inc
   
   state_nextreg[STATE_NR_MMU2].new = mem_pages[0];         // audio buffer page

   intrinsic_halt();           // reduce any glitches from L2 change

   state_init_l2_palette();    // initialize fixed l2 palette
   state_init_nextreg();       // set up nextreg for video playback

   // play video

   // select play function
   //
   // +6 for hdmi
   // +3 for 60 Hz
   // +0 for silent
   // +1 for mono
   // +2 for stereo
   
   c = 0;
   if ((ZXN_READ_REG(0x11) & 0x07) == 0x07) c += 6;
   if (state_nextreg[STATE_NR_05].new) c += 3;
   if (option_flags.audio == 0) c += 2;
   
   play_video = (unsigned char (*)(void))(video_player_jump_table[c]);
   
   in_wait_nokey();

   //
   
   do
   {
      G_AGAIN:
      
      v_frame_count = option_frame_count;

      while (v_frame_count)
      {
         c = in_inkey();
         in_wait_nokey();

         if ((c == 'q') || (c == 254)) return 0;  // BREAK or Q

         if (c)                                   // any key generates a pause
         {
            c = pause_key();
            if ((c == 'q') || (c == 254)) return 0;  // BREAK or Q
         }
      
         v_sector_start = (option_frame_start + option_frame_count - v_frame_count) * video_player_info.frame_size;

         memset((void *)0x4000, 0x80, 8192);      // clear audio buffer

         if (sd_open_stream() == 0)
         {
            // stream error
            exit(ESX_ENXIO);
         }

         v_frame_count = (option_flags.modifier & 0x01) ? -1UL : -v_frame_count;   // player wants a negative frame count

         if (play_video() == (unsigned char)0xff)
         {
            // fragment error
            exit(ESX_ENXIO);
         }
      
         v_frame_count = -v_frame_count;          // back to positive frame count
      
         esx_disk_stream_end();
      }
      
      // pause at start or end
      
      if (option_flags.modifier & 0x03)
      {
         c = pause_key();
         if ((c == 'q') || (c == 254)) return 0;  // BREAK or Q
      }
      
      if (option_flags.modifier & 0x01)
      {
         option_flags.modifier &= 0xfe;
         goto G_AGAIN;
      }
      
   }
   while (option_flags.modifier & 0x04);          // loop forever
   
   return 0;
}

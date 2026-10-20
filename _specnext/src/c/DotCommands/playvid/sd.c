#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <arch/zxn/esxdos.h>

#include "main.h"
#include "sd.h"
#include "user_interaction.h"
#include "video.h"

// FILEMAP

unsigned char fd = 0xff;                       // video file handle
extern struct esx_stat es;                     // file info

extern struct esx_filemap filemap;             // one esx filemap entry  \  must be located
extern struct esx_filemap_entry entry;         //                        /  at 0x4000 or above!!

uint16_t n_entries;                            // number of valid file fragments
uint32_t filesz;                               // total video size in sectors

// VIDEO CLASSIFICATION

unsigned char video_format;                    // video format 0 - 5

// 0 = 320x240 with palette 17fps 933 stereo samples (frame size = 155)
// 1 = 320x240 no palette 17fps 933 stereo samples (frame size = 154)
// 2 = 256x240 with palette 17 fps 1866 stereo samples (frame size = 129)
// 3 = 256x240 no palette 17fps 1866 stereo samples (frame size = 128)
// 4 = 256x192 with palette 25fps 933 mono samples (frame size = 99)
// 5 = 256x192 no palette 25fps 933 mono samples (frame size = 98)

static unsigned char video_format_size[] = { 155, 154, 129, 128, 99, 98 };

//

static uint32_t sum, total;
static struct sd_filemap *p;
static unsigned char r;

uint32_t block_units(uint32_t num)
{
   if (_esx_stream_card_flags & 0x02) return num;
   return num * 512UL;
}

void sd_enumerate_file_fragments(unsigned char *filename)
{
   // open file

   if ((fd = esx_f_open(filename, ESX_MODE_OPEN_EXIST | ESX_MODE_R)) == (unsigned char)0xff)
   {
      q_printf("X\n\nfile not found\n");
      exit(ESX_EINVAL);
   }

   // record file fragments one fragment at a time

   filemap.mapsz = 1;
   filemap.map = &entry;

   total = 0;   // track size of this file in sectors as reported by filemap

   user_interaction_spin();

//   r = esx_disk_filemap(fd, &filemap);
//   
//   while (r && (n_entries != FILEMAP_ENTRIES))

   entry.sectors = 0;
   esx_disk_filemap(fd, &filemap);

   while (entry.sectors && (n_entries != FILEMAP_ENTRIES))
   {
      // first of fragment

      p = &fm_entries[n_entries];
      ++n_entries;
      
      sum = entry.address;
      sum += block_units((uint32_t)entry.sectors);

      p->length = entry.sectors;
      p->address = entry.address;
      
      total += entry.sectors;

      // contiguous fragments

//      while (r = esx_disk_filemap(fd, &filemap))

      while (1)
      {
         entry.sectors = 0;
         esx_disk_filemap(fd, &filemap);
         
         if (entry.sectors == 0) break;

         user_interaction_spin();
         
         if (sum != entry.address) break;

         sum += block_units((uint32_t)entry.sectors);
         p->length += entry.sectors;
         
         total += entry.sectors;
      }
   }

   user_interaction_end();

   if (n_entries == FILEMAP_ENTRIES)
   {
      q_printf("X\n\nvideo too fragmented\n");
      exit(ESX_EOVERFLOW);
   }

   if (total)
   {
      // accumulate file size of all input files in sectors
      // only file size via stat gives exact size in bytes

      if (esx_f_fstat(fd, &es))
      {
         q_printf("X\n\nstat failed\n");
         exit(ESX_EACCES);
      }
   
      if (es.size % 512UL)
      {
         q_printf("X\n\ninvalid video format\n");
         exit(ESX_EWRTYPE);
      }

      es.size /= 512UL;   // file size now in sectors

      // if the video format is being forced, truncate
      // the file size to a whole number of frames

      if (video_format)
         es.size -= es.size % (uint32_t)video_format_size[video_format - 1];

      filesz += es.size;
      
      // Because FAT allocates in clusters the filemap will
      // overestimate the number of sectors occupied.
      //
      // Further, large files can be truncated to small and
      // this does not imply that previously allocated space
      // is freed.  That means the filemap could widely exceed
      // the occupied sectors of the file.
      //
      // So here we need to dial back the filemap to the actual
      // sectors occupied by the file.
      
      total -= es.size;   // number of sectors that should be removed

      while (total >= p->length)
      {
         total -= p->length;
         --p;
         --n_entries;
      }
      
      p->length -= total;
   }

   // close file
   
   esx_f_close(fd);
   fd = 0xff;
}

void sd_classify_video_format(void)
{
   if (n_entries == 0)
   {
      q_printf("\nempty video file\n");
      exit(ESX_EWRTYPE);
   }

   // accumulated file size must be multiple of video frame size
   
   if (video_format)
      --video_format;   // option override
   else
   {
      for (r = 0; r != sizeof(video_format_size)/sizeof(*video_format_size); ++r)
      {
         if ((filesz % (uint32_t)video_format_size[r]) == 0)
         {
            video_format = r;
            break;
         }
      }
      
      if (r == (unsigned char)(sizeof(video_format_size)/sizeof(*video_format_size)))
      {
         q_printf("\ninvalid video format\n");
         exit(ESX_EWRTYPE);
      }
   }
}

unsigned char sd_open_stream(void)
{
   // locate starting file fragment

   p = fm_entries - 1;
   sum = 0;
   
   do
   {
      sum += (++p)->length;
   }
   while (sum <= v_sector_start);

   // file fragment located

   v_file_fragment = p + 1;
   v_fragment_remaining = sum - v_sector_start;

   // open stream
   
   entry.address = p->address + block_units(p->length - v_fragment_remaining);

   return esx_disk_stream_start(&entry);   // 0 = fail
}

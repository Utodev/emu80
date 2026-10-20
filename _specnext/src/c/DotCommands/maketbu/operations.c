#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <arch/zxn/esxdos.h>

#include "maketbu.h"
#include "operations.h"
#include "user_interaction.h"

//

static unsigned char         i, j, type;
static unsigned char         num;
static uint16_t              checksum;
static uint16_t              secnum;

uint32_t                     err_pos;
struct esx_dirent_lfn        dirent;

//

void sprintf_core_filename(unsigned char *buffer)
{
   sprintf(buffer, "zxnext-%u-%u%02u%02u%s.bin", tbu_record->boardid + 2, tbu_record->core_major / 16, tbu_record->core_major & 0x0f, tbu_record->core_minor, (tbu_record->type) ? "" : "-ab");
}

//

void tbu_add(void)
{
   static uint16_t boardid, coreversion;
   
   if ((fdir = esx_f_opendir_ex(".", ESX_DIR_USE_LFN)) == 0xff)
      error_noreturn("Unable to open dir");

   while (esx_f_readdir(fdir, &dirent) == 1)
   {
      strlwr(dirent.name);
      type = 0xff;
      
      secnum = 0;
      if ((sscanf(dirent.name, "zxnext-%u-%u.bin%n", &boardid, &coreversion, &secnum) == 2) && (dirent.name[secnum] == 0))
      {
         type = 1;
      }

#ifndef __Z80

      // it's too easy to brick a machine if anti-brick cores are allowed
      
      else
      {
         secnum = 0;
         if ((sscanf(dirent.name, "zxnext-%u-%u-ab.bin%n", &boardid, &coreversion, &secnum) == 2) && (dirent.name[secnum] == 0))
         {
            type = 0;
         }
      }

#endif
   
      if (type != 0xff)
      {
         if ((boardid < 2) || (boardid > 4) || (coreversion < 30000) || (coreversion > 50000))
         {
            printf("Rejected %s - params out of range\n", dirent.name);
            continue;
         }
         
         for (tbu_record = (struct TBU_RECORD *)(tbu_header.records); tbu_record->length != 0xff; tbu_record = (struct TBU_RECORD *)((unsigned char *)(tbu_record) + tbu_record->length))
         {
            if ((tbu_record->boardid == (boardid - 2)) && (tbu_record->type == type) && (tbu_record->core_major == CORE_MAJOR(coreversion)) && (tbu_record->core_minor == CORE_MINOR(coreversion)))
            {
               printf("Skipping %s - duplicate\n", dirent.name);
               break;
            }
         }
      
         if (tbu_record->length == 0xff)
         {
            if (((unsigned char *)(tbu_record) - (unsigned char *)(tbu_header)) > (511 - sizeof(*tbu_record)))
            {
               printf("Cannot add %s - index full\n", dirent.name);
            }
            else
            {
               if ((fin = esx_f_open(dirent.name, ESX_MODE_OPEN_EXIST | ESX_MODE_R)) == 0xff)
               {
                  printf("Skipping %s - unable to open\n", dirent.name);
               }
               else
               {
                  tbu_record->length = sizeof(*tbu_record);
                  tbu_record->type = type;
                  tbu_record->boardid = boardid - 2;
                  tbu_record->core_major = CORE_MAJOR(coreversion);
                  tbu_record->core_minor = CORE_MINOR(coreversion);
                  tbu_record->sector_offset = 0;
                  tbu_record->sector_length = 0;
                  tbu_record->checksum = 0;
               
                  if (((err_pos = get_filesize(ftbu)) == (uint32_t)(-1)) || ((err_pos & 0x1ff) != 0))  // also positions file pointer at end of file
                     error_noreturn("Seek error or badly sized " FN_TBBLUE);

                  tbu_record->sector_offset = (err_pos / 512) - 1;
                  
                  printf("Adding %s\n", dirent.name);
                  
                  secnum = (tbu_record->boardid < 2) ? 959 : 4287;
                  
                  err_task = 1;
                  
                  do
                  {
                     memset(buffer, 0xff, 512);
                     
                     if (esx_f_read(fin, buffer, 512) == 0) break;
                     esx_f_write(ftbu, buffer, 512);
                  
                     tbu_record->checksum = fletcher16(tbu_record->checksum, 512, buffer);
                     ++tbu_record->sector_length;
                     
                     user_interaction_spin();
                  }
                  while (--secnum);
                  
                  // add flash record
                  
                  memset(buffer, 0xff, 512);
                  
                  while (secnum)
                  {
                     esx_f_write(ftbu, buffer, 512);
                     
                     tbu_record->checksum = fletcher16(tbu_record->checksum, 512, buffer);
                     ++tbu_record->sector_length;

                     user_interaction_spin();
                     
                     --secnum;
                  }
                  
                  secnum = 1 + sprintf(buffer, "ZX SPECTRUM NEXT%cZXN ISSUE %u %s", 0, tbu_record->boardid + 2, (tbu_record->type == 0) ? "ANTI-BRICK" : "ZX SPECTRUM NEXT");

                  memset(&f_record, 0xff, sizeof(f_record));
                  
                  f_record.length = sizeof(f_record);
                  f_record.type = tbu_record->type;
                  f_record.board_id = tbu_record->boardid;
                  f_record.core_version = tbu_record->core_major;
                  f_record.cv_minor = tbu_record->core_minor;
                  
                  memcpy(buffer + secnum, (void *)(&f_record), sizeof(f_record));
                  
                  esx_f_write(ftbu, buffer, 512);
                  
                  tbu_record->checksum = fletcher16(tbu_record->checksum, 512, buffer);
                  ++tbu_record->sector_length;
                  
                  // update tbu file index
                  
                  esx_f_seek(ftbu, 0, ESX_SEEK_SET);
                  esx_f_write(ftbu, &tbu_header, 512);
                  
                  err_task = 0;
                  
                  esx_f_close(fin);
                  fin = 0xff;

                  user_interaction_end();
               }
            }
         }
      }
   }
   
   esx_f_closedir(fdir);
   fdir = 0xff;
}

//

void tbu_list(void)
{
   num = 1;
         
   for (tbu_record = (struct TBU_RECORD *)(tbu_header.records); tbu_record->length != 0xff; tbu_record = (struct TBU_RECORD *)((unsigned char *)(tbu_record) + tbu_record->length))
   {
      sprintf_core_filename(buffer);
      printf("%u - %s, length = %u sectors, checksum = %04X\n", num, buffer, (uint16_t)tbu_record->sector_length, tbu_record->checksum);
      ++num;
   }
}

//

void tbu_pull(unsigned int argc, unsigned char **argv)
{   
   for (i = 2; i != argc; ++i)
   {
      if ((sscanf(argv[i], "%u%n", &secnum, &checksum) != 1) || (argv[i][checksum] != 0))
         error_noreturn("Aborting - invalid arg %s", argv[i]);
   
      if (num = secnum)
      {
         tbu_record = (struct TBU_RECORD *)(tbu_header.records);
      
         for (j = 1; j != num; ++j)
         {
            if (tbu_record->length == 0xff) break;
            tbu_record = (struct TBU_RECORD *)((unsigned char *)(tbu_record) + tbu_record->length);
         }
         
         err_pos = (tbu_record->sector_offset + 1) * 512;
         
         if (tbu_record->length == 0xff)
         {
            printf("Record %u not present\n", num);
         }
         else if (esx_f_seek(ftbu, err_pos, ESX_SEEK_SET) != err_pos)
         {
            error_noreturn("Abort - record %u data missing", num);
         }
         else
         {
            sprintf_core_filename(dirent.name);
         
            if ((fout = esx_f_open(dirent.name, ESX_MODE_OPEN_CREAT_TRUNC | ESX_MODE_W)) == 0xff)
            {
               printf("Skipping %u - cannot open %s\n", num, dirent.name); 
            }
            else
            {
               err_task = 2;
               
               checksum = 0;
               printf("%u - %s\n", num, dirent.name);
         
               for (secnum = (uint16_t)tbu_record->sector_length; secnum; --secnum)
               {
                  memset(buffer, 0xff, 512);
               
                  esx_f_read(ftbu, buffer, 512);
                  esx_f_write(fout, buffer, 512);
            
                  checksum = fletcher16(checksum, 512, buffer);
               
                  user_interaction_spin();
               }
            
               esx_f_close(fout);
               fout = 0xff;
               
               err_task = 0;
               user_interaction_end();

               if (tbu_record->checksum != checksum)
               {
                  printf("^ Checksum did not match %04X", checksum);
                  esx_f_unlink(dirent.name);
               }
            }
         }
      }
   }
}

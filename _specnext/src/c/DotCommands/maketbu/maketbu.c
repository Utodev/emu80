/*
ZX Spectrum Next Project
Copyright 2022 Alvin Albrecht

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

// TBBLUE.TBU Maker:
//    Issue 2 ZX Spectrum Next core
//    Issue 3 ZX Spectrum Next core
//    Issue 4 ZX Spectrum Next core

#include <stdio.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <arch/zxn.h>
#include <arch/zxn/esxdos.h>

#include "maketbu.h"
#include "operations.h"

///////////////
// FILE HANDLES

unsigned char fdir = 0xff;   // indicate file is unused with -1 value
unsigned char fin  = 0xff;   // indicate file is unused with -1 value
unsigned char fout = 0xff;   // indicate file is unused with -1 value
unsigned char ftbu = 0xff;   // indicate file is unused with -1 value

unsigned char buffer[512];   // one sector of a file and scratch space

/////////////////
// FILE STRUCTURE

struct TBU_HEADER   tbu_header;
struct TBU_RECORD  *tbu_record;
struct FLASH_RECORD f_record;

/////////////
// ERROR EXIT

unsigned char err_task = 0;   // bss variables are zeroed by default but this one is important so be explicit
unsigned char old_cpu_speed;

void cleanup(void)
{
   if (fdir != 0xff) esx_f_closedir(fdir);
   if (fin  != 0xff) esx_f_close(fin);
   if (fout != 0xff) esx_f_close(fout);
   if (ftbu != 0xff) esx_f_close(ftbu);

   // should really set those files to 0xff after close but this is run just before exit

   if (err_task == 1)
   {
      // add operation interrupted with partial append to TBBLUE.TBU
      
      esx_f_trunc(FN_TBBLUE, err_pos);
   }

   if (err_task == 2)
   {
      // pull operation interrupted with partial output file
      
      esx_f_unlink(dirent.name);
   }

   ZXN_NEXTREGA(0x07, old_cpu_speed);
}

#ifdef SPECIALDOT

   extern unsigned char errbuf[48];

#else

   #define errbuf buffer

#endif

void error_noreturn(const char *format, ...)
{
   va_list v;
   
   va_start(v, format);
   vsnprintf(errbuf, sizeof(errbuf) - 1, format, v);
   
   errbuf[strlen(errbuf) - 1] += 0x80;
   
   exit((int)errbuf);
}

///////////////
// CORE VERSION

unsigned char CORE_MAJOR(uint16_t version)
{
   return ((version / 10000) * 16) + ((version / 100) % 100);
}

unsigned char CORE_MINOR(uint16_t version)
{
   return version % 100;
}

///////////
// FILE OPS

uint32_t get_filesize(unsigned char f)
{
   // elected to go with a method compatible with pc
   // returns -1 on error
   
   // must also position file pointer at end of file
   
/*
   if (esx_f_seek(f, 0xffffffffUL, ESX_SEEK_SET) == (uint32_t)(-1))
      return (uint32_t)(-1);

   return esx_f_fgetpos(f);
*/

   return esx_f_seek(f, 0xffffffffUL, ESX_SEEK_SET);
}

unsigned char open_tbu_index(unsigned char mode)
{
   // attempt to open TBBLUE.TBU and read header
   
   if ((ftbu = esx_f_open(FN_TBBLUE, mode)) == 0xff)
      return 1;   // cannot create or open TBU
   
   if (esx_f_read(ftbu, &tbu_header, 512) != 512)
   {
      esx_f_close(ftbu);
      ftbu = 0xff;
      return 2;   // TBU header missing
   }
   
   return 0;      // OK and TBU header read
}

unsigned char validate_tbu(void)
{
   // verify TBU header
   
   if (strcmp(tbu_header.filetype, "TBUFILE") != 0) return 1;
   if (strcmp(tbu_header.machine, "ZX SPECTRUM NEXT") != 0) return 2;
   return 0;
}

///////
// MAIN

int main(unsigned int argc, unsigned char **argv)
{
   static unsigned char operation;

   // cleanup and run at 28 MHz
   
   old_cpu_speed = ZXN_READ_REG(0x07) & 0x03;
   ZXN_NEXTREG(0x07, 0x03);
   
   atexit(cleanup);

   // command line - find out what we are doing
   
   operation = 0;
   
   if (argc == 2)
   {
      if (strcasecmp(argv[1], "add") == 0)
         operation = 1;
      
      if (strcasecmp(argv[1], "list") == 0)
         operation = 2;
   }
   
   if ((argc >= 3) && (strcasecmp(argv[1], "pull") == 0))
      operation = 3;
   
   printf("\n");
   
   // help text
   
   if (operation == 0)
   {
      strupr(argv[0]);
      
      printf("%s V1.0\n\n"
             "Usage:\n\n"
             ".%s add\n create or append all bitstreams\n in dir to " FN_TBBLUE "\n\n"
             ".%s list\n print numbered list of all\n bitstreams stored in " FN_TBBLUE "\n\n"
             ".%s pull ...\n pull bitstreams from " FN_TBBLUE "\n by number\n\n"
             "Bitstream filenames are form\n \"zxnext-issue-core.bin\"\n issue = 2, 3, 4\n core = core version eg 30200\n\n"
             "\x7f" " 2022 ZX Spectrum Next Project\n\n",
             argv[0], argv[0], argv[0], argv[0]);
      exit(0);
   }
   
   // down to business
   
   switch (operation)
   {
      case 1:
         
         // ADD
         
         printf(FN_TBBLUE " ADD\n");
         
         if (open_tbu_index(ESX_MODE_OPEN_EXIST | ESX_MODE_RW))
         {
            // failed, create the TBU file
            
            if ((ftbu = esx_f_open(FN_TBBLUE, ESX_MODE_OPEN_CREAT_TRUNC | ESX_MODE_RW)) == 0xff)
               error_noreturn("Cannot create " FN_TBBLUE);
         
            sprintf(tbu_header.filetype, "TBUFILE");
            sprintf(tbu_header.machine, "ZX SPECTRUM NEXT");
            memset(tbu_header.records, 0xff, sizeof(tbu_header.records));
         
            if (esx_f_write(ftbu, &tbu_header, 512) != 512)
               error_noreturn("Unable to write " FN_TBBLUE);
         }
         
         if (validate_tbu())
            error_noreturn(FN_TBBLUE " is malformed");
         
         tbu_add();   // separate file due to length
         break;
   
      case 2:
      
         // LIST
         
         printf(FN_TBBLUE " LIST\n");
         
         if (open_tbu_index(ESX_MODE_OPEN_EXIST | ESX_MODE_R))
            error_noreturn("Invalid " FN_TBBLUE);
         
         if (validate_tbu())
            error_noreturn(FN_TBBLUE " is malformed");

         tbu_list();   // separate file due to length
         break;
      
      case 3:
      default:
      
         // PULL
         
         printf(FN_TBBLUE " PULL\n");
         
         if (open_tbu_index(ESX_MODE_OPEN_EXIST | ESX_MODE_R))
            error_noreturn("Invalid " FN_TBBLUE);
         
         if (validate_tbu())
            error_noreturn(FN_TBBLUE " is malformed");
         
         tbu_pull(argc, argv);
         break;
   }

   printf("\n");   
   return 0;
}

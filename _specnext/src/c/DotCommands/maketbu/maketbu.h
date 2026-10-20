#ifndef _MAKETBU_H
#define _MAKETBU_H

#include <stdint.h>
#include <arch/zxn/esxdos.h>

// FILES

extern unsigned char fdir;
extern unsigned char fin;
extern unsigned char fout;
extern unsigned char ftbu;

extern unsigned char buffer[512];

#define FN_TBBLUE "TBBLUE.TBU"

// ERROR

extern unsigned char err_task;
extern void error_noreturn(const char *format, ...);

// GLOBAL FUNCTIONS

extern uint16_t fletcher16(uint16_t checksum, uint16_t size, void *buffer) __z88dk_callee;

extern unsigned char CORE_MAJOR(uint16_t version);
extern unsigned char CORE_MINOR(uint16_t version);

extern uint32_t get_filesize(unsigned char f);

// TBBLUE.TBU

struct TBU_HEADER
{
   unsigned char filetype[8];       // "TBUFILE"
   unsigned char machine[17];       // "ZX SPECTRUM NEXT"
   unsigned char records[512-25];   // must be 512 bytes total size
};

extern struct TBU_HEADER tbu_header;

struct TBU_RECORD
{
   unsigned char length;          // 15, 0xff = end of records
   unsigned char type;            // 1 = ZX Spectrum Next (slot 1)
   unsigned char boardid;         // nextreg 0x0f
   unsigned char core_major;      // nextreg 0x01
   unsigned char core_minor;      // nextreg 0x0e
   uint32_t      sector_offset;   // from end of header
   uint32_t      sector_length;   // number of 512 byte sectors
   uint16_t      checksum;        // fletcher-16
};

extern struct TBU_RECORD *tbu_record;

// RECORD IN FLASH MEMORY WITH BITSTREAM

struct FLASH_RECORD {
   unsigned char length;       // 7
   unsigned char type;         // 0 = ZXN Anti-Brick, 1 = ZX Spectrum Next
   unsigned char board_id;     // nextreg 0x0F
   unsigned char core_version; // nextreg 0x01
   unsigned char cv_minor;     // nextreg 0x0E
   uint16_t      offset;       // unused (0xFFFF)
};

extern struct FLASH_RECORD f_record;

#endif

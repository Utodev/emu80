// zcc +zxn -v -startup=1 -clib=sdcc_iy -SO3 --max-allocs-per-node200000 --opt-code-size tm.c tm.asm -o tm -pragma-include:zpragma.inc -subtype=nex -Cz"--clean" -create-app

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <arch/zxn.h>
#include <input.h>
#include <intrinsic.h>

///////////////////////////////
// TILEMAP
///////////////////////////////

// The tilemap will be 80x32 with attributes so will occupy
// the topmost 5120 byts of bank 5 at address 0x6c00.

// The tile definitions will be placed at address 0x5c00.
// However the source font only defines characters 32 - 127
// which is the printable part of the ascii set so we will
// only be using those tile definitions stored in addresses
// 0x6000 - 0x6bff.

// The tilemap and used portion of tile definitions then occupy
// the top 8k of bank 5 (0x6000-0x7fff) which is well out of
// the way of the standard ula screen at 0x4000.

// Addresses of the tilemap and tile definitions are in "tm.asm"

struct __tilemap
{
   unsigned char tile;     // 8 bit tile number
   unsigned char flags;    // tile attribute (palette offset, rotation, etc)
};

extern struct __tilemap tilemap[32][80];

struct __tiles
{
   unsigned char bmp[32];          // each tile image is 32 bytes
};

extern struct __tiles tiles[256];  // 256 tile images in total


///////////////////////////////
// FONT
///////////////////////////////

// This BBC font comes from the z88dk library
// Codes 32 - 127 defined as UDGs one byte per eight pixels

extern unsigned char font_8x8_bbc_system[];

// Convert each UDG font char to a 32-byte tile using colour
// zero for reset pixel and colour 1 for set pixel

void copy_font_to_tile(unsigned char startcode, unsigned char endcode)
{
   static unsigned char *src;
   static unsigned char *dst;
   static unsigned char byte;
   
   for (unsigned char i = startcode; i <= endcode; ++i)
   {
      src = &font_8x8_bbc_system[(i - ' ') * 8];
      dst = (unsigned char *)&tiles[i];
      
      for (unsigned char y = 0; y != 8; ++y)
      {
         byte = *src;
         
         for (unsigned char x = 0; x != 4; ++x)
         {
            // each byte in a tile definition holds two pixels
            // so we look at two pixels from src at a time
            
            *dst = 0;          // reset pixels have colour 0 (out of 16)
            
            if (byte & 0x80)
               *dst |= 0x10;   // set pixel has colour 1 (out of 16)
            
            if (byte & 0x40)
               *dst |= 0x01;   // set pixel has colour 1 (out of 16)
            
            ++dst;             // next pair of tile pixels
            byte *= 4;         // shift over two bits of source byte
         }
         
         ++src;
      }
   }
}


///////////////////////////////
// TILE ROTATION
///////////////////////////////

// This function rotates the actual tile definition in memory.
// This will affect all printed tiles on screen immediately.

// When setting the rotation bit of a particular tile in the tilemap,
// only a specific tile on screen has hardware rotation applied.

void rotate_tiledef(unsigned char tilenum)
{
   static unsigned char buffer[32];
   static unsigned char *tiledef;
   static unsigned char byte;

   tiledef = (unsigned char *)&tiles[tilenum];  // location of tile definition
   memset(buffer, 0, sizeof(buffer));           // rotated tile will be built in this array

   for (unsigned char x = 0; x != 8; ++x)
   {
      for (unsigned char y = 0; y != 8; ++y)
      {
         byte  = tiledef[y*4 + x/2];
         
         if (x & 0x01)
            byte &= 0x0f;
         else
            byte /= 16;
         
         if (y & 0x01)
            byte *= 16;
         
         buffer[x*4 + (7-y)/2] |= byte;
      }
   }
   
   memcpy(tiledef, buffer, sizeof(buffer));     // copy rotated image to tile definition
}


///////////////////////////////
// ULA SPLAT
///////////////////////////////

// Place coloured blocks on the ULA display to obscure the tilemap

void ula_splat(void)
{
   unsigned char *p;
   
   // pick a random attribute square
   
   p = (unsigned char *)((unsigned int)((unsigned long)rand() * 768 / RAND_MAX) + 22528);
   
   // colour it but only if it's transparent so that ula text is not hidden
   
   if (*p == (INK_MAGENTA | PAPER_MAGENTA))
      *p = INK_GREEN | PAPER_GREEN;
}


///////////////////////////////
// MAIN
///////////////////////////////

unsigned int xscroll;          // current x scroll amount
unsigned int dx_scroll;        // current x scroll speed

unsigned char yscroll;         // current y scroll amount
unsigned char dy_scroll;       // current y scroll speed

// display synchronization to avoid tearing

void wait_for_line_224(void)
{
   while (ZXN_READ_REG(REG_ACTIVE_VIDEO_LINE_L) == 224) ;
   while (ZXN_READ_REG(REG_ACTIVE_VIDEO_LINE_L) != 224) ;
}

// change tile / ula display order

#define MODE_ULA_ON_TOP    0
#define MODE_INVERT_ORDER  1

void tiles_on_top_mode(unsigned char mode)
{
   // every tilemap entry is modified

   for (unsigned char x = 0; x != 80; ++x)
   {
      for (unsigned char y = 0; y != 32; ++y)
      {
         if (mode == MODE_ULA_ON_TOP)
            tilemap[y][x].flags |= 1;
         else
            tilemap[y][x].flags ^= 1;
      }
   }
}

// ula text

void print_ula_text(void)
{
   printf("\x15" "\x29"
          "\x16" "\x03" "\x04" "------------"
          "\x16" "\x03" "\x05" "TILEMAP TEST"
          "\x16" "\x03" "\x06" "------------"
          
          "\x16" "\x03" "\x08" "SPACE  : 40 / 80"
          
          "\x16" "\x03" "\x0a" "CAPS+1 : ULA on top / below"
          "\x16" "\x03" "\x0b" "CAPS+2 : ULA splat"
          
          "\x16" "\x03" "\x0d" "CAPS+0 : Reset display"
          
          "\x16" "\x03" "\x0f" "ARROWS : Scroll accelerate"
          
          "\x16" "\x03" "\x11" "ASCII  : Rotate char tile"
          
          "\x16" "\x03" "\x13" "BREAK  : Exit"
         );
}

// reset display

void reset_display(void)
{
   ZXN_NEXTREG(REG_FALLBACK_COLOR, 0x03);                        // fallback is blue
   ZXN_NEXTREG(REG_GLOBAL_TRANSPARENCY_COLOR, 0xe3);             // global transparent colour is 0xe3
   
   // make ink and paper magenta the transparent colour
   
   ZXN_NEXTREG(REG_PALETTE_CONTROL, RPC_SELECT_ULA_PALETTE_0);
   ZXN_NEXTREG(REG_PALETTE_INDEX, 3);                            // select index for magenta ink
   ZXN_NEXTREG(REG_PALETTE_VALUE_8, 0xe3);                       // make it transparent
   ZXN_NEXTREG(REG_PALETTE_INDEX, 19);                           // select index for magenta paper
   ZXN_NEXTREG(REG_PALETTE_VALUE_8, 0xe3);                       // make it transparent

   // place tiles in ula on top mode
   
   tiles_on_top_mode(MODE_ULA_ON_TOP);
   
   // clear ula screen to transparent
   
   zx_cls(INK_MAGENTA | PAPER_MAGENTA);
   zx_border(INK_MAGENTA);
   
   // print text
   
   print_ula_text();
   
   // stop scroll
   
   xscroll = 0;
   yscroll = 0;
   
   dx_scroll = 0;
   dy_scroll = 0;

   // turn on tilemap
   
   ZXN_NEXTREG(0x6e, 0x6c);    // tilemap base address is 0x6c00
   ZXN_NEXTREG(0x6f, 0x5c);    // tile definitions base address is 0x5c00 (code 32 starts at 0x6000)
   ZXN_NEXTREG(0x6b, 0xc0);    // enable tilemap in 80x32 mode
   
   // notice the tilemap's transparency index hasn't been set
   // this program depends on it being the reset value of 0xf
   // (or rather not 0 or 1) for emulator tests
}

void main(void)
{
   unsigned char i;
   
   // fill in tilemap palette 0
   
   // try to fill in different colours for each 16-colour offset
   // make sure colours 0 and 1 in each 16-colour group are contrasting
   
   ZXN_NEXTREG(REG_PALETTE_CONTROL, 0x30);
   ZXN_NEXTREG(REG_PALETTE_INDEX, 0);
   
   i = 0;
   do
   {
      unsigned char value;
      
      value = i & 0xfe;
      if (value == 0) value = 1;
      
      ZXN_NEXTREGA(REG_PALETTE_VALUE_8, (i & 1) ? value : ~value);
   }
   while (++i != 0);

   // copy bbc font
   
   copy_font_to_tile(32, 127);

   // fill up tilemap with random ascii
   // not random anymore to see how the 80x32 and 40x32 screens are laid out relative to each other

intrinsic_label(TILEMAP_BEGIN);

   for (unsigned char x = 0; x != 80; ++x)
   {
      for (unsigned char y = 0; y != 32; ++y)
      {
         //tilemap[y][x].tile = (unsigned char)((((unsigned long)rand() * 96) / RAND_MAX)) + ' ';
         if ((x == 0) || (x == 40))
         {
            tilemap[y][x].tile = '0' + (x == 40);
            tilemap[y][x].flags = ((rand() & 0x0f) << 4) + 3;   // random palette offset, rotate, ula over tile
         }
         else
         {
            tilemap[y][x].tile = (x%26) + 'A';
            tilemap[y][x].flags = ((rand() & 0x0f) << 4) + 1;   // random palette offset, ula over tile
         }
      }
   }

intrinsic_label(TILEMAP_END);

   // initialize display
   
   reset_display();

   while (1)
   {
      // synchronize
      
      wait_for_line_224();
      
      yscroll += dy_scroll;
      xscroll += dx_scroll;
      
      // scroll
      
      if (xscroll > 639)
         xscroll -= 640;
      
      ZXN_NEXTREGA(0x31, yscroll);
      ZXN_NEXTREGA(0x30, xscroll & 0xff);
      ZXN_NEXTREGA(0x2f, xscroll >> 8);
      
      // user input
      
      if ((i = in_inkey()) != 0)
      {
         switch (i)
         {
            // scroll
            
            case 8:  // CAPS+5
               dx_scroll++;
               if (dx_scroll == 640) dx_scroll = 0;
               continue;

            case 9:  // CAPS+8
               if (dx_scroll == 0) dx_scroll = 640;
               dx_scroll--;
               continue;
            
            case 10: // CAPS+6
               dy_scroll--;
               continue;
            
            case 11: // CAPS+7
               dy_scroll++;
               continue;
               
            // 40/80 mode and Exit
            
            case ' ':
               if (in_key_pressed(IN_KEY_SCANCODE_SPACE | 0x8000))
               {
                  ZXN_NEXTREG(0x6b, 0);                        // turn off tilemap (not necessary as reset follows)
                  ZXN_NEXTREG(REG_RESET, RR_SOFT_RESET);       // soft reset
               }
               
               ZXN_NEXTREGA(0x6b, ZXN_READ_REG(0x6b) ^ 0x40);  // swap 40/80 column mode
               break;
            
            // Toggle ULA on top
            
            case 7:  // CAPS+1
               tiles_on_top_mode(MODE_INVERT_ORDER);
               break;
            
            // Reset settings
            
            case 12:  // CAPS+0
               reset_display();
               break;
            
            // ULA splat
            
            case 6:  // CAPS+2
               ula_splat();
               continue;
            
            // Rotate char
            
            default:
               if ((i >= 32) && (i <= 127))
               {
                  rotate_tiledef(i);
                  continue;
               }
               break;
         }
         
         in_wait_nokey();
      }
   }
}

#include <stdio.h>
#include <string.h>
#include <arch/zxn.h>
#include <arch/zxn/esxdos.h>

#include "info.h"

unsigned char *info_core(void)
{
   static unsigned char buffer[10];  // = "15.15.255";
   unsigned char v;
   
   v = ZXN_READ_REG(REG_VERSION);   
   sprintf(buffer, "%u.%02u.%02u", v >> 4, v & 0x0f, ZXN_READ_REG(REG_SUB_VERSION));

   return buffer;
}

unsigned char *info_os(void)
{
   // static unsigned char buffer[18];  // = "NextZXOS v255.255";
   unsigned int v;
   
   v = esx_m_dosversion();
   
   if (v == ESX_DOSVERSION_ESXDOS) return "ESXDOS";

   return "NEXTZXOS";

/*
   // Version info is unavailable if basic's stack is gone

   if (v == ESX_DOSVERSION_NEXTOS_48K) return "NEXTZXOS 48K";
   
   sprintf(buffer, "NEXTZXOS v%u.%02u", ESX_DOSVERSION_NEXTOS_MAJOR(v), ESX_DOSVERSION_NEXTOS_MINOR(v));
   return buffer;
*/
}

static unsigned char *info_machine_helper(unsigned char id)
{
   switch (id)
   {
      case 0:
      case 1:
         return "48K";
         
      case 2:
         return "128K";
         
      case 3:
         return "ZX NEXT";
         
      case 4:
         return "PENTAGON";
         
      default:
         break;
   }
   
   return "unknown";
}

unsigned char *info_machine(void)
{
   return info_machine_helper(ZXN_READ_REG(REG_MACHINE_TYPE) & 0x07);
}

unsigned char *info_timing(void)
{
   return info_machine_helper((ZXN_READ_REG(REG_MACHINE_TYPE) >> 4) & 0x07);
}

unsigned char *info_refresh(void)
{
   return (ZXN_READ_REG(REG_PERIPHERAL_1) & 0x04) ? "60Hz" : "50Hz";
}

unsigned char *info_video(void)
{
   static unsigned char buffer[5];  // = "VGA0";
   unsigned char v;
   
   v = ZXN_READ_REG(REG_VIDEO_TIMING) & 0x07;
   
   strcpy(buffer, "VGA");
   buffer[3] = v + '0';
   
   return (v == 7) ? "HDMI" : buffer;
}

unsigned char *info_scanlines(void)
{
   switch (ZXN_READ_REG(REG_PERIPHERAL_4) & 0x03)
   {
      case 0:
         return "OFF";
      
      case 1:
         return "75%";
      
      case 2:
         return "50%";
      
      default:
         break;
   }
   
   return "25%";
}

extern unsigned char original_cpu_speed;

unsigned char *info_cpu(void)
{
   switch (original_cpu_speed & 0x03)
   {
      case 0:
         return "3.5MHz";
      
      case 1:
         return "7MHz";
      
      default:
         break;
   }
   
   return "14MHz";
}

unsigned char *info_dma(void)
{
   return (ZXN_READ_REG(REG_PERIPHERAL_2) & 0x40) ? "Z80 DMA" : "ZXN DMA";
}

unsigned char *info_timex(void)
{
   return (ZXN_READ_REG(REG_PERIPHERAL_3) & 0x04) ? "ON" : "OFF";
}

unsigned char *info_ula(void)
{
   return (ZXN_READ_REG(REG_PERIPHERAL_3) & 0x40) ? "OFF" : "ON";
}

unsigned char *info_speaker(void)
{
   return (ZXN_READ_REG(REG_PERIPHERAL_3) & 0x10) ? "ON" : "OFF";
}

unsigned char *info_dac(void)
{
   return (ZXN_READ_REG(REG_PERIPHERAL_3) & 0x08) ? "ENABLED" : "DISABLED";
}

unsigned char *info_aymode(void)
{
   static unsigned char buffer[13];  // = "AY8910 ABC x3";
   unsigned char v, x;
   
   v = ZXN_READ_REG(REG_PERIPHERAL_2) & 0x03;
   
   if (v & 0x02) return "OFF";
   
   x = ZXN_READ_REG(REG_PERIPHERAL_3);
   
   sprintf(buffer, "%s %s x%s", v ? "AY8910" : "YM2149", (x & 0x20) ? "ACB" : "ABC", (x & 0x02) ? "3" : "1");
   return buffer;
}

unsigned char *info_ay(unsigned char ay)
{
   unsigned char mask;

   if (ay == 0)
      mask = 0x20;
   else if (ay == 1)
      mask = 0x40;
   else
      mask = 0x80;
   
   return (ZXN_READ_REG(REG_PERIPHERAL_4) & mask) ? "MONO" : "STEREO";
}

unsigned char *info_joy(unsigned char joy)
{
   unsigned char v;
   
   v = ZXN_READ_REG(REG_PERIPHERAL_1);
   
   if (joy == 0)
      v = ((v >> 6) & 0x03) | ((v >> 1) & 0x04);
   else
      v = ((v >> 4) & 0x03) | ((v << 1) & 0x04);
   
   switch (v)
   {
      case 0:
         return "SINCLAIR 2";
      
      case 1:
         return "KEMPSTON 1";
      
      case 2:
         return "CURSOR";
      
      case 3:
         return "SINCLAIR 1";
      
      case 4:
         return "KEMPSTON 2";
      
      case 5:
         return "MD 1";
      
      case 6:
         return "MD 2";
      
      default:
         break;
   }
   
   return "UNKNOWN";
}

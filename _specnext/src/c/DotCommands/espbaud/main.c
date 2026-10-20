// ESPBAUD
// Allen Albright, thanks to Tim Gilberts and Robin Verhagen-Guest

#include <stdio.h>
#include <arch/zxn.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <z80.h>

#include "esp.h"
#include "main.h"
#include "option.h"
#include "uart.h"

// BUFFER

unsigned char buffer[256];

// CONDITIONAL PRINT

int m_printf(char *fmt, ...)
{
   va_list v;
   va_start(v, fmt);

   if (!flags.quiet)
   {
#ifdef __SCCZ80
      return vprintf(va_ptr(v,char *), v);
#else
      return vprintf(fmt, v);
#endif
   }

   return 0;
}

// ESP DETECT BPS

void main_esp_detect_bps(void)
{
   m_printf("Detecting ESP baud rate\n");
   
   if (!esp_detect_bps())
   {
      esp_bps = 115200UL;
      m_printf("\n  Failed, selecting default");
   }

   m_printf("\n  Setting uart to %lu\n", esp_bps);
   uart_set_prescaler(uart_compute_prescaler(esp_bps));
}

// MAIN AND CLEANUP

unsigned char old_cpu_speed;
unsigned char old_uart_select;

void cleanup(void)
{
   m_printf("\n");
   
   IO_153B = old_uart_select;
   ZXN_NEXTREGA(0x07, old_cpu_speed);
}

int main(int argc, char **argv)
{
   static unsigned char i;
   
   // restore state on exit
   
   old_cpu_speed = ZXN_READ_REG(0x07) & 0x03;
   ZXN_NEXTREG(0x07, 0x03);
   
   old_uart_select = IO_153B & 0x40;
   IO_153B = 0x00;
   
   atexit(cleanup);

   // parse command line
   
   for (i = 1; i < (unsigned char)argc; ++i)
      option_parse(strrstrip(strstrip(argv[i])));

   m_printf("\n");
   
   // print help
   
   if (!flags.reset_hard && !flags.version && !flags.detect && !flags.set_bps)
   {
      puts("ESPBAUD V1.1 (zx next)\n\n"
           "-R  = ESP Hard Reset\n\n"
           "-d  = Detect ESP bps\n"
           "bps = Set bps and finetune\n"
           "-v  = ESP version test\n\n"
           "-p  = ESP bps change permanent\n"
           "-f  = Set bps exactly\n"
           "-q  = quiet mode\n\n"
           "Z88DK.ORG");
      
      exit(0);
   }
   
   // implementation
   
   if (flags.reset_hard)
   {
      m_printf("Resetting ESP\n");
      
      ZXN_NEXTREG(0x02, 0x80);
      z80_delay_ms(100*8);       // 100ms, about 8x longer for 28MHz
      ZXN_NEXTREG(0x02, 0);
      z80_delay_ms(8000U*8U);      // 8s, about 8x longer for 28MHz
   }

   esp_response_time_ms = 66 + ESP_FW_RESPONSE_TIME_MS;   // two bit periods at 300bps
   uart_rx_readline_last(buffer, sizeof(buffer)-1);   // clear Rx

   if (flags.detect)
   {
      esp_bps = 0UL;
      main_esp_detect_bps();
   }
   
   esp_response_time_ms = 66 + ESP_FW_RESPONSE_TIME_MS;   // two bit periods at 300bps
   
   if (flags.set_bps)
   {
      static unsigned char ret;
      
      m_printf("Setting ESP to %lu", flags.set_bps);
      
      // verify that communication is established
      
      uart_tx("\r\nAT\r\n");
      
      if ((ret = esp_response_ok()) == ET_OK)
      {
         // beware different versions of esp firmware
         
         if (!flags.permanent)
         {
            sprintf(buffer, "\r\nAT+UART_CUR=%lu,8,1,0,0\r\n", flags.set_bps);
            uart_tx(buffer);
            
            if ((ret = esp_response_ok()) != ET_OK)
            {
               m_printf("\n  Trying perm change");
               flags.permanent = 1;
            }
         }
         
         if (flags.permanent)
         {
            sprintf(buffer, "\r\nAT+UART_DEF=%lu,8,1,0,0\r\n", flags.set_bps);
            uart_tx(buffer);
            
            if ((ret = esp_response_ok()) != ET_OK)
            {
               sprintf(buffer, "\r\nAT+UART=%lu,8,1,0,0\r\n", flags.set_bps);
               uart_tx(buffer);
               
               if ((ret = esp_response_ok()) != ET_OK)
               {
                  m_printf(" (fail)");
               }
            }
         }
         
         m_printf("\n  Any change is %s", (flags.permanent) ? ("permanent") : ("temporary"));
      }
      else
      {
         m_printf(" (fail)");
      }
      
      if ((ret == ET_OK) && !flags.force)
      {
         m_printf("\n");
         
         esp_bps = flags.set_bps;
         main_esp_detect_bps();
      }
      else
      {
         // set uart to indicated baud rate no matter what
      
         m_printf("\n  Setting uart to %lu\n", flags.set_bps);
         uart_set_prescaler(uart_compute_prescaler(flags.set_bps));
      }
   }

   if (flags.version)
   {
      m_printf("ESP AT+GMR follows...\n");
      uart_rx_readline_last(buffer, sizeof(buffer)-1);   // clear Rx
   
      //
      
      uart_tx(STRING_ESP_TX_AT_GMR);

      *buffer = 0;
      
      do
      {
         puts(buffer);   // deliberately not qualified by quiet option
         
         *buffer = 0;
         uart_rx_readline(buffer, sizeof(buffer)-1);
      }
      while (*buffer);
   }
  
   return 0;
}

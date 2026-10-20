// zcc +zxn -v -startup=30 -clib=sdcc_iy -SO3--max-allocs-per-node200000 --opt-code-size xper.c option.c -o xper -lm -subtype=dot -Cz"--clean" -create-app

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <arch/zxn.h>
#include <z80.h>

#include "option.h"

#pragma printf = "%s %f %llX %u"
#pragma output CLIB_EXIT_STACK_SIZE = 1

float xadc_temp(uint16_t t)
{
   // UG480 page 33
   return ((t * 503.975) / 4096.0) - 273.15;
}

float xadc_volt(uint16_t v)
{
   // UG480 page 34
   return (v / 4096.0) * 3.0;
}

struct XADC
{
   unsigned char *name;
   uint8_t address;           // XADC read address
   uint16_t value;            // filled in when XADC read
   float (*conv)(uint16_t);   // 0 = no measurement
};

struct XADC xadc[] = {
   { "\n* TEMPERATURE (abs max 125)", 0, 0, 0 },
   { "  cur T = ", 0, 0, xadc_temp },
   { "  min T = ", 0x24, 0, xadc_temp },
   { "  max T = ", 0x20, 0, xadc_temp },
   { "\n* VCCINT", 0, 0, 0 },
   { "  cur VCCINT = ", 0x01, 0, xadc_volt },
   { "  min VCCINT = ", 0x25, 0, xadc_volt },
   { "  max VCCINT = ", 0x21, 0, xadc_volt },
   { "\n* VCCAUX", 0, 0, 0 },
   { "  cur VCCAUX = ", 0x02, 0, xadc_volt },
   { "  min VCCAUX = ", 0x26, 0, xadc_volt },
   { "  max VCCAUX = ", 0x22, 0, xadc_volt },
   { "\n* VCCBRAM", 0, 0, 0 }, 
   { "  cur VCCBRAM = ", 0x06, 0, xadc_volt },
   { "  min VCCBRAM = ", 0x27, 0, xadc_volt },
   { "  max VCCBRAM = ", 0x23, 0, xadc_volt }
};

void read_xilinx_xadc(void)
{
   for (unsigned char i = 0; i != sizeof(xadc) / sizeof(struct XADC); ++i)
   {
      if (xadc[i].conv == 0)
      {
         printf("%s\n", xadc[i].name);
      }
      else
      {
         ZXN_NEXTREGA(0xf8, xadc[i].address);                                                // read XADC register
         xadc[i].value = (uint16_t)((ZXN_READ_REG(0xfa) * 256) + ZXN_READ_REG(0xf9)) / 16;   // ADC result is in top 12 bits
         
         printf("%s%.3f\n", xadc[i].name, xadc[i].conv(xadc[i].value));
      }
   }
}

uint8_t xdna_len;
uint64_t xdna;

void read_xilinx_dna(void)
{
   ZXN_NEXTREG(0xf0, 0xc1);  // select xilinx dna
   ZXN_NEXTREG(0xf0, 0);     // enter xilinx dna mode
   ZXN_NEXTREG(0xf0, 0);     // reload dna registers
   
   xdna_len = 0;
   
   for (unsigned char i = 0; i != 8; ++i)
      xdna_len = (xdna_len << 1) + ZXN_READ_REG(0xf0);
   
   xdna = 0;
   
   for (unsigned char i = xdna_len; i; --i)
      xdna = (xdna << 1) + ZXN_READ_REG(0xf0);
   
   ZXN_NEXTREG(0xf0, 0xc0);  // back to select mode
}

struct XADC_RESET
{
   unsigned char reg;
   uint16_t val;
};

struct XADC_RESET xadc_reset[] = {
   { 0x40, 0x0000 },   // Config Reg 0
   { 0x41, 0x00f0 },   // Config Reg 1
   { 0x42, 0x0000 },   // Config Reg 2
   
   { 0x48, 0x0000 },   // Sequencer Channel Selection (on-chip)
   { 0x49, 0x0000 },   // Sequencer Channel Selection (aux)
   { 0x4a, 0x0000 },   // Measurement Averaging (on-chip)
   { 0x4b, 0x0000 },   // Measurement Averaging (aux)
   { 0x4c, 0x0000 },   // Analog Input Mode (on-chip)
   { 0x4d, 0x0000 },   // Analog Input Mode (aux)
   { 0x4e, 0x0000 },   // Settling Time (on-chip)
   { 0x4f, 0x0000 },   // Settling Time (aux)
   
   { 0x50, 0x0000 },   // Upper Temperature Alarm
   { 0x51, 0x0000 },   // Upper VCCINT Alarm
   { 0x52, 0x0000 },   // Upper VCCAUX Alarm
   { 0x53, 0x0000 },   // OT Alarm Limit
   { 0x54, 0x0000 },   // Lower Temperature Alarm Reset
   { 0x55, 0x0000 },   // Lower VCCINT Alarm
   { 0x56, 0x0000 },   // Lower VCCAUX Alarm
   { 0x57, 0x0000 },   // OT Alarm Reset
   { 0x58, 0x0000 },   // Upper VCCBRAM Alarm
   { 0x5c, 0x0000 }    // Lower VCCBRAM Alarm
};

void reset_xilinx_xadc(void)
{
   // re-write all configuration registers

   for (unsigned char i = 0; i != sizeof(xadc_reset) / sizeof(struct XADC_RESET); ++i)
   {
      ZXN_NEXTREGA(0xf9, xadc_reset[i].val & 0xff);   // LSW of register value
      ZXN_NEXTREGA(0xfa, xadc_reset[i].val >> 8);     // MSW of register value
      ZXN_NEXTREGA(0xf8, xadc_reset[i].reg + 0x80);   // write register
   }

   // reset clears accumulated sensor data and restarts adc
   
   ZXN_NEXTREG(0xf0, 0xc2);   // select xilinx xadc
   ZXN_NEXTREG(0xf0, 0);      // enter xilinx xadc mode
   ZXN_NEXTREG(0xf0, 0x40);   // xadc reset
   ZXN_NEXTREG(0xf0, 0xc0);   // back to select mode
}

unsigned char old_cpu_speed;

void cleanup(void)
{
   ZXN_NEXTREGA(0x07, old_cpu_speed);          // restore original cpu speed
}

unsigned char board_issue;

int main(unsigned int argc, char **argv)
{
   // speed up
   
   old_cpu_speed = ZXN_READ_REG(0x07) & 0x03;  // remember the current cpu speed
   ZXN_NEXTREG(0x07, 0x03);                    // run at 28 MHz
   
   atexit(cleanup);                            // always run cleanup when program terminates

   // check options & help

   strupr(argv[0]);                            // capitalize name of dot command
   board_issue = (ZXN_READ_REG(0x0f) & 0x0f) + 2;

   if ((argc == 1) || (board_issue < 4))       // if no options or board issue too low
   {
      printf("\n"
             "%s 1.0\n\n"
             "Read Xilinx Peripherals\n\n"
             "* Xilinx DNA\n\n"
             "-d  reports the fpga unique id\n\n"
             "* Xilinx XADC\n\n"
             "-R  resets the xadc\n"
             "-x  reports status of sensors\n\n"
             ".%s -dx\n\n"
             "running on an issue %u board\n"
             "%s\n"
             "\x7f" " 2022 ZX Spectrum Next Project\n\n",
             argv[0], argv[0], board_issue,
             (board_issue < 4) ? "ISSUE 4 REQUIRED\n" : ""
            );
   
      exit(0);
   }

   // parse command line
   
   for (unsigned char i = 1; i < (unsigned char)argc; ++i)
      option_parse(strrstrip(strstrip(argv[i])));   // remove spaces around option (bizarre case)
   
   // actions
   
   if (flags.xdna)
   {
      read_xilinx_dna();
   
      printf("\n"
             "*** Xilinx DNA ***\n\n"
             "length    = %u bits\n"
             "unique id = %016llX\n",
             xdna_len, xdna
            );
   }
   
   if (flags.xadc_reset)
   {
      printf("\nXADC RESET\n");

      reset_xilinx_xadc();
      z80_delay_ms(100*8);   // some time for new data to be collected (*8 for 28 MHz)
   }
   
   if (flags.xadc)
   {
      printf("\n*** Xilinx XADC ***\n");
      read_xilinx_xadc();
   }
   
   printf("\n");
   return 0;
}

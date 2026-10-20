#include <stdio.h>
#include <stdlib.h>
#include <input.h>
#include <arch/zxn/esxdos.h>

#include "main.h"
#include "user_interaction.h"

static unsigned char cpos;
static unsigned char cursor[] = "-\\|/";

static void user_interaction_cursor(void)
{
   q_printf("%c" "\x08", cursor[cpos]);
   if (++cpos >= (sizeof(cursor) - 1)) cpos = 0;
}

void user_interaction(void)
{
   if (in_key_pressed(IN_KEY_SCANCODE_SPACE | 0x8000))
   {
      in_wait_nokey();
      
      q_printf("\n\nbreak\n");
      exit(ESX_EOK);
   }
}

void user_interaction_spin(void)
{
   user_interaction_cursor();
   user_interaction();
}

void user_interaction_end(void)
{
   q_printf(" " "\x08");
}

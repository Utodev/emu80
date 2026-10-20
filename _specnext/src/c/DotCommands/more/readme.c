// MORE dot command utility for Sinclair ZX Spectrum Next by Marco V.
#ifndef _NONEXT_
#include <arch/zxn.h>
#include <arch/zxn/esxdos.h>
#else
#include <arch/zx.h>
#include <arch/zx/esxdos.h>
#endif
#include <errno.h>
#include <input.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <z80.h>
#include "cstack.h"

// TODO: command name in argv[0]
#define PROGNAME "MORE\0"

#define DISPLAY_FILE_NAME_MAX_LEN 128

#define LF 10
#define CR 13
#define TAB 9

// global variables
unsigned char fin  = 0xff;   // file descriptor
char displayFileName[DISPLAY_FILE_NAME_MAX_LEN];
char *fileName;
uint32_t orig_pos;
uint32_t pos;
unsigned char turbo;
unsigned char peripheral2;
unsigned char rows;
unsigned char cols;
unsigned char row;
unsigned char col;
#ifdef _IDE_MODE_
struct esx_mode mode;
struct esx_mode forcedMode;
unsigned char forceCols;
bool forceMode = false;
unsigned char layer;
uint32_t fileSize = 0;
#endif
//bool clearScreen;

uint32_t getPerc(uint32_t current, uint32_t total)
{
	uint32_t result = current * 100 / total;
	return result;
}

void fillLineWithSpaces(void)
{
	for (; col<cols; col++)
		putchar(' ');
}

void fillPageWithSpaces(void)
{
	for (; row<rows-2; row++)
		for (col = 0; col<cols; col++)
			putchar(' ');
}

void cleanup(void)
{
	if (fin != 0xff)
	{
		esx_f_close(fin);
	}
#ifdef _IDE_MODE_
	if (forceMode)
	{
		//if (forcedMode.mode == ESX_MODE_SET_LAYER_1_HIRES && mode.mode != ESX_MODE_SET_LAYER_1_HIRES)
		if (forcedMode.mode != mode.mode && forcedMode.mode != ESX_MODE_SET_LAYER_0)
		{
			//printf("%c%c%c", 22, 0, 0);
			//row = 0;
			//col = 0;
			//fillPageWithSpaces();
			putchar(14);
		}
		esx_ide_mode_set(&mode);
	}
#endif

#ifndef _NONEXT_
	IO_NEXTREG_REG = REG_PERIPHERAL_2;
	IO_NEXTREG_DAT = peripheral2;

	IO_NEXTREG_REG = REG_TURBO_MODE;
	IO_NEXTREG_DAT = turbo;
#endif
}

void initialize(void)
{
	cstack_init();

#ifndef _NONEXT_	
	IO_NEXTREG_REG = REG_TURBO_MODE;
	turbo = IO_NEXTREG_DAT;
	IO_NEXTREG_DAT = 3; //RTM_14MHZ;

	IO_NEXTREG_REG = REG_PERIPHERAL_2;
	peripheral2 = IO_NEXTREG_DAT;
	IO_NEXTREG_DAT = IO_NEXTREG_DAT | RP2_ENABLE_TURBO;
#endif

	atexit(cleanup);

#ifdef _IDE_MODE_
	esx_ide_mode_get(&mode);
	//printf("rows: %u; cols: %u", mode.rows, mode.cols);
	cols = mode.cols;
	rows = mode.rows;
	layer = mode.mode8.layer;
#else
	cols = 32;
	rows = 22;
#endif
}

bool parseArgs(int argc, char **argv)
{
	char *fileNameNoDir;

	if (argc == 1)
		return 0;

	fileName = argv[argc-1];

	// Get displayed file name
	memset(displayFileName, ' ', DISPLAY_FILE_NAME_MAX_LEN);
	fileNameNoDir = strrchr(fileName, '/');
	if (fileNameNoDir == NULL)
	{
		fileNameNoDir = fileName;
	}
	else
	{
		// Skip '/'
		fileNameNoDir++;
	}
	memcpy(displayFileName, fileNameNoDir, strlen(fileNameNoDir));

	for (int i=1; i<argc-1; i++)
	{
#ifdef _IDE_MODE_
		if (strcmp(argv[i], "-85") == 0)
		{
			forceMode = true;
			forceCols = 85;
		}
		else
		if (strcmp(argv[i], "-64") == 0)
		{
			forceMode = true;
			forceCols = 64;
		}
		else
		if (strcmp(argv[i], "-128") == 0)
		{
			forceMode = true;
			forceCols = 128;
		}
		else
#endif
		// if (stricmp(argv[i], "-c") == 0)
		// {
		// 	clearScreen = true;
		// }
		// else
		{
			return 0;
		}
	}

	return 1;
}

unsigned char seek()
{
	esx_f_seek(fin, pos, ESX_SEEK_SET);
	if (errno)
	{
		printf("Seek failed\n");
		return -1;
	}
	return 0;
}

int main(int argc, char **argv)
{
	unsigned char quit = 0;
	char c;
	const char *progName = PROGNAME;
	struct esx_stat st;       // file info
	unsigned char fileMode = ESX_MODE_OPEN_EXIST | ESX_MODE_R;

	initialize();

	if (!parseArgs(argc, argv))
	{
		printf("\n%s v1.1 by Marco Varesio\n\n", progName);
#ifdef _IDE_MODE_
		printf("SYNOPSIS:\n .%s [-64|-85|-128] <FILE>\n", progName);
		printf("\nOPTIONS:\n");
		printf(" -64  force  64 columns mode\n");
		printf(" -85  force  85 columns mode\n");
		printf(" -128 force 128 columns mode\n");
#else
		printf("SYNOPSIS:\n .%s <FILE>\n", progName);
#endif
		printf("\nCOMMANDS:\n");
		printf(" 8/RIGHT/ENTER:   next page\n");
		printf(" 5/LEFT/0/DELETE: previous page\n");
		printf(" Q/SPACE:         exit\n\n");
		printf("Displays <FILE> one screen at a time\n");

		return 1;
	}

#ifdef _IDE_MODE_
	fileMode |= ESX_MODE_USE_HEADER;
	struct esx_p3_hdr h;
	fin = esx_f_open_p3(fileName, fileMode, &h);
#else
	fin = esx_f_open(fileName, fileMode);
#endif
	
    if (errno)
	{
		printf("Can't open %s\n", fileName);
		return errno;
	}	

	if (esx_f_fstat(fin, &st) != 0)
	{
		printf("Stat failed\n");
		return errno;
	}

	//printf("SIZE: %lu\n", st.size);

	if (st.size == 0)
	{
		printf("Empty file\n");
		return -1;
	}
	fileSize = st.size;

#ifdef _IDE_MODE_
	if (forceMode)
	{
		if (mode.cols == forceCols)
		{
			// Already in requested mode
			forceMode = false;
		}
		else
		{
			forcedMode.mode = ESX_MODE_SET_LAYER_1_HIRES;
			c = esx_ide_mode_set(&forcedMode);
			if (errno)
			{
				printf("Can't set mode");
				return errno;
			}

			// see new_commands.pdf
			// Set character width (85 => 6; 64 => 8)
			printf("%c%c", 30, forceCols == 128? 4 : forceCols == 85? 6 : 8);
			cols = forceCols;
			rows = 24;
			layer = 1;
		}
	}
	if (layer > 0)
	{
		printf("%c%c%c", 22, 0, 0);
		putchar(14);
	}
#endif

#ifdef _IDE_MODE_
	if (h.type != 0xff)
	fileSize -= 128;
#endif

	pos = 0;

	while (!quit)
	{
		printf("%c%c%c", 22, 0, 0);

		if (pos < fileSize)
		{
			orig_pos = pos;
		}
		
		row = 0;
		col = 0;
		
		while (1)
		{	
			if (pos >= fileSize)
			{
				// Ended before last col
				fillLineWithSpaces();
				// Ended before last row
				fillPageWithSpaces();

				break;
			}
			
			esx_f_read(fin, &c, 1);
			++pos;
			
			if (c == CR)
			{
				fillLineWithSpaces();

				// Check for LF
				if (pos < fileSize)
				{
					esx_f_read(fin, &c, 1);

					if (c == LF)
					{
						++pos;
					}
					else
					{
						if (seek() != 0)
						{
							return -1;
						}
					}
				}
			}
			else if (c == LF)
			{
				// LF without leading CR
				fillLineWithSpaces();
			}
			else
			{
				if (c == TAB)
				{
					c = ' ';
				}					
				else if (c < 32 || c > 127)
				{
					c = '?';
				}

				++col;

				putchar(c);
			}
			
			if (col == cols)
			{
				col = 0;
				++row;
			}
			
			if (row == rows-1)
			{
				break;
			}
		}

		// Inverse ON
		printf("%c%c", 20, 1);

		for (col = 0; col < cols-4; col++)
			putchar(displayFileName[col]);

		// Percentage
		printf("%3lu%%", getPerc(pos, fileSize));

		// Inverse OFF
		printf("%c%c", 20, 0);

		while(1)
		{
			if (in_key_pressed(IN_KEY_SCANCODE_SPACE) ||
				in_key_pressed(IN_KEY_SCANCODE_q))
			{
				quit = 1;
				break;
			}

			// Down
			else if (in_key_pressed(IN_KEY_SCANCODE_ENTER) ||
					 in_key_pressed(IN_KEY_SCANCODE_8))
			{
				if (pos < fileSize)
				{
					cstack_push(orig_pos);
					break;
				}
			}
			
			// Up
			else if (in_key_pressed(IN_KEY_SCANCODE_0) ||
					 in_key_pressed(IN_KEY_SCANCODE_5))
			{
				if (cstack_count() > 0)
				{
					pos = cstack_pop();

					if (seek() != 0)
					{
						return -1;
					}

					break;
				}
			}
			
		}
	}

	z80_delay_ms(250);
	
	return 0;
}


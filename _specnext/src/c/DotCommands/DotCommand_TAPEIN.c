///////////////////////////////////////////////////////////
//
///////////////////////////////////////////////////////////
#include "DotCommandShared.h"

///////////////////////////////////////////////////////////
//
///////////////////////////////////////////////////////////
bool optionHelp = false;
bool optionVerbose = false;
bool optionClose = false;
bool optionPause = false;
bool optionSimulate = false;
bool optionPointer = false;
uint32_t blockId = 0;
uint8_t fileArg = 0;

///////////////////////////////////////////////////////////
//
///////////////////////////////////////////////////////////
bool ProcessOptions(int argc, char **argv)
{
	for (uint8_t i = 1; i < argc; ++i)
	{
		char* arg = argv[i];

		if (stricmp(arg, "-h") == 0 || stricmp(arg, "--help") == 0)
		{
			optionHelp = true;
		}
		else if (stricmp(arg, "-v") == 0 || stricmp(arg, "--verbose") == 0)
		{
			argv[i] = NULL;
			optionVerbose = true;
		}
		else if (stricmp(arg, "-c") == 0 || stricmp(arg, "--close") == 0)
		{
			argv[i] = NULL;
			optionClose = true;
		}
		else if (stricmp(arg, "-r") == 0 || stricmp(arg, "--rewind") == 0)
		{
			argv[i] = NULL;
			optionPointer = true;
			blockId = 0;
		}
		else if (stricmp(arg, "-p") == 0 || stricmp(arg, "--pause") == 0)
		{
			argv[i] = NULL;
			optionPause = true;
		}
		else if (stricmp(arg, "-l") == 0 || stricmp(arg, "--simulate") == 0)
		{
			argv[i] = NULL;
			optionSimulate = true;
		}
		else if (stricmp(arg, "-s") == 0 || stricmp(arg, "--setptr") == 0)
		{
			argv[i] = NULL;
			if (i == (argc - 1))
			{
				optionHelp = true;
			}
			else
			{
				unsigned char *endptr;
				blockId = strtoul(argv[i+1], &endptr, 0);

				if (errno || *endptr || (blockId > 0xffff))
				{
					optionHelp = true;
				}
				else
				{
					optionPointer = true;
					argv[i] = NULL;
					argv[i+1] = NULL;
				}
			}
		}
		else
		{
			if (arg)
			{
				if (fileArg)
				{
					optionHelp = true;
				}
				else
				{
					fileArg = i;
				}
			}
		}
	}

	if (argc == 1)
	{
		optionVerbose = true;
	}

	return !optionHelp;
}

const char * ToggleName(uint8_t value)
{
	if (value)
	{
		return "ON";
	}
	else
	{
		return "OFF";
	}
}

///////////////////////////////////////////////////////////
//
///////////////////////////////////////////////////////////
int main(int argc, char **argv)
{
	CommonInit();

	if (ProcessOptions(argc, argv))
	{
		uint8_t flags = esx_m_tapein_flags(0);
		esx_m_tapein_flags(flags);

		if (optionClose)
		{
			esx_m_tapein_close();
		}

		if (fileArg)
		{
			if (esx_m_tapein_open(argv[fileArg]))
			{
				return errno;
			}
		}

		if (optionPause || optionSimulate)
		{
			if (optionPause)
			{
				flags ^= 0x01;
			}

			if (optionSimulate)
			{
				flags ^= 0x02;
			}

			esx_m_tapein_flags(flags);
		}

		if (optionPointer)
		{
			if (esx_m_tapein_setpos(blockId))
			{
				return errno;
			}
		}

		if (optionVerbose)
		{
			uint8_t drive;

			if (esx_m_tapein_info(&drive, pathname) == 0)
			{
				if (drive == '*')
				{
					printf("%s\n", pathname);
				}
				else
				{
					char letter = 'A'+(drive>>3);
					printf("%c:%s\n", letter, pathname);
				}
			}
			else
			{
				PrintFormatted("No tape input file\n");
			}

			PrintFormatted("Screen pause: %s\n", ToggleName(flags & 0x01));
			PrintFormatted("Loading simulation: %s\n", ToggleName(flags & 0x02));
		}
	}
	else
	{
		printf("TAPEIN v1.1 by Garry Lancaster\n");
		printf("Change tape input to .TAP file\n\n");
		printf("SYNOPSIS:\n .TAPEIN [OPTION]... [FILE]\n\n");
		printf("OPTIONS:\n");
		printf(" -v, --verbose\n");
		printf("     Verbose output\n");
		printf(" -h, --help\n");
		printf("     Display this help\n");
		printf(" -c, --close\n");
		printf("     Close input file\n");
		printf(" -r, --rewind\n");
		printf("     Rewind to start\n");
		printf(" -s, --setptr <block>\n");
		printf("     Set tape block pointer\n");
		printf(" -p, --pause\n");
		printf("     Toggle screen pause\n");
		printf(" -l, --simulate\n");
		printf("     Toggle loading simulation\n");
		printf("\nUse LOAD \"t:\" before loading\n");
	}

	return 0;
}

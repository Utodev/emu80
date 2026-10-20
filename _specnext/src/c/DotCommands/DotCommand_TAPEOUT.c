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
bool optionOverwrite = false;
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
		else if (stricmp(arg, "-o") == 0 || stricmp(arg, "--overwrite") == 0)
		{
			argv[i] = NULL;
			optionOverwrite = true;
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

///////////////////////////////////////////////////////////
//
///////////////////////////////////////////////////////////
int main(int argc, char **argv)
{
	CommonInit();

	if (ProcessOptions(argc, argv))
	{
		if (optionClose)
		{
			esx_m_tapeout_close();
		}

		if (fileArg)
		{
			if (optionOverwrite)
			{
				if (esx_m_tapeout_trunc(argv[fileArg]))
				{
					return errno;
				}
			}
			else
			{
				if (esx_m_tapeout_open(argv[fileArg]))
				{
					return errno;
				}
			}
		}

		if (optionVerbose)
		{
			uint8_t drive;

			if (esx_m_tapeout_info(&drive, pathname) == 0)
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
				PrintFormatted("No tape output file\n");
			}
		}
	}
	else
	{
		printf("TAPEOUT v1.1 by Garry Lancaster\n");
		printf("Change tape output to .TAP file\n\n");
		printf("SYNOPSIS:\n .TAPEOUT [OPTION]... [FILE]\n\n");
		printf("OPTIONS:\n");
		printf(" -v, --verbose\n");
		printf("     Verbose output\n");
		printf(" -h, --help\n");
		printf("     Display this help\n");
		printf(" -c, --close\n");
		printf("     Close input file\n");
		printf(" -o, --overwrite\n");
		printf("     Overwrite instead of append\n");
		printf("\nUse SAVE \"t:\" before saving\n");
	}

	return 0;
}

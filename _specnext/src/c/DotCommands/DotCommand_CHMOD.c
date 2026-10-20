///////////////////////////////////////////////////////////
//
///////////////////////////////////////////////////////////
#include "DotCommandShared.h"

///////////////////////////////////////////////////////////
//
///////////////////////////////////////////////////////////
bool optionHelp = false;
bool optionVerbose = false;
bool argPresent = false;
uint8_t optionSetBits = 0;
uint8_t optionClearBits = 0;

///////////////////////////////////////////////////////////
//
///////////////////////////////////////////////////////////
bool ProcessOptions(int argc, char **argv)
{
	if (argc == 1)
	{
		optionHelp = true;
	}

	for (uint8_t i = 1; i < argc; ++i)
	{
		char* arg = argv[i];

		if (stricmp(arg, "-?") == 0 || stricmp(arg, "--help") == 0)
		{
			optionHelp = true;
		}
		else if (stricmp(arg, "-v") == 0 || stricmp(arg, "--verbose") == 0)
		{
			argv[i] = NULL;
			optionVerbose = true;
		}
		else if (stricmp(arg, "+w") == 0 || stricmp(arg, "-r") == 0)
		{
			argv[i] = NULL;
			optionSetBits |= ESX_A_WRITE;
		}
		else if (stricmp(arg, "-w") == 0 || stricmp(arg, "+r") == 0)
		{
			argv[i] = NULL;
			optionClearBits |= ESX_A_WRITE;
		}
		else if (stricmp(arg, "+s") == 0)
		{
			argv[i] = NULL;
			optionSetBits |= ESX_A_SYSTEM;
		}
		else if (stricmp(arg, "-s") == 0)
		{
			argv[i] = NULL;
			optionClearBits |= ESX_A_SYSTEM;
		}
		else if (stricmp(arg, "+h") == 0)
		{
			argv[i] = NULL;
			optionSetBits |= ESX_A_HIDDEN;
		}
		else if (stricmp(arg, "-h") == 0)
		{
			argv[i] = NULL;
			optionClearBits |= ESX_A_HIDDEN;
		}
		else if (stricmp(arg, "+a") == 0)
		{
			argv[i] = NULL;
			optionSetBits |= ESX_A_ARCH;
		}
		else if (stricmp(arg, "-a") == 0)
		{
			argv[i] = NULL;
			optionClearBits |= ESX_A_ARCH;
		}
		else
		{
			argPresent = true;
		}
	}

	if ((optionSetBits & optionClearBits) != 0)
	{
		optionHelp = true;
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
		for (uint8_t i = 1; i < argc; ++i)
		{
			if (argv[i] != NULL)
			{
				char* path = MakeNicePath(argv[i]);
				uint8_t mask = optionSetBits | optionClearBits;
				uint8_t value = optionSetBits;

				if (optionVerbose)
				{
					PrintFormatted("Change '%s'\n", path);
				}

				if (esx_f_chmod(path, mask, value) != 0)
				{
					PrintErrorMessage(errno);
					break;
				}
			}
		}
	}
	else
	{
		printf("CHMOD v1.0 by Garry Lancaster\n");
		printf("Changes file/dir attributes\n\n");
		printf("\nSYNOPSIS:\n .CHMOD [OPTION]... FILE...\n");
		printf("OPTIONS:\n");
		printf(" -?, --help\n");
		printf("     Display this help\n");
		printf(" -v, --verbose\n");
		printf("     Verbose output\n");
		printf(" +r, -w\n");
		printf("     Make read-only\n");
		printf(" -r, +w\n");
		printf("     Make writable\n");
		printf(" +s, -s\n");
		printf("     Add/remove SYSTEM attrib\n");
		printf(" +h, -h\n");
		printf("     Add/remove HIDDEN attrib\n");
		printf(" +a, -a\n");
		printf("     Add/remove ARCHIVE attrib\n");
	}

	return 0;
}

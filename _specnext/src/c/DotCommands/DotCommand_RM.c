///////////////////////////////////////////////////////////
//
///////////////////////////////////////////////////////////
#include "DotCommandShared.h"

///////////////////////////////////////////////////////////
//
///////////////////////////////////////////////////////////
bool optionHelp = false;
bool optionVerbose = false;
bool optionParent = false;

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

		if (stricmp(arg, "-h") == 0 || stricmp(arg, "--help") == 0)
		{
			optionHelp = true;
		}
		else if (stricmp(arg, "-v") == 0 || stricmp(arg, "--verbose") == 0)
		{
			argv[i] = NULL;
			optionVerbose = true;
		}
		else if (stricmp(arg, "-p") == 0 || stricmp(arg, "--parents") == 0)
		{
			argv[i] = NULL;
			optionParent = true;
		}
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
				uint8_t r;

				if (optionVerbose)
				{
					PrintFormatted("Remove file '%s'\n", path);
				}

				r = esx_f_unlink(path);
				if (r != 0)
				{
					PrintErrorMessage(errno);
					break;
				}
			}
		}
	}
	else
	{
		printf("RM v1.0 by Gari Biasillo\n");
		printf("Remove files\n\n");
		printf("\nSYNOPSIS:\n .RM [OPTION]... FILE...\n");
		printf("OPTIONS:\n");
		printf(" -v, --verbose\n");
		printf("     Verbose output\n");
        printf(" -h, --help\n");
        printf("     Display this help\n");
	}

	return 0;
}

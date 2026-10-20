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
//			optionParent = true;
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
				uint8_t r;
				char* path = MakeNicePath(argv[i]);

				if (optionParent)
				{
					r = esx_f_mkdir(path);
				}
				else
				{
					r = esx_f_mkdir(path);
				}

				if (r == 0)
				{
					if (optionVerbose)
					{
						PrintFormatted("Make directory '%s'", path);
					}
				}
				else
				{
					PrintFormatted("Failed to make directory '%s'", path);

					if (optionVerbose)
					{
						PrintErrorMessage(errno);
					}
					break;
				}
			}
		}
	}
	else
	{
		printf("MKDIR v1.0 by Gari Biasillo\n");
		printf("Make new directories\n\n");
		printf("\nSYNOPSIS:\n .MKDIR [OPTION]... DIR...\n");
		printf("OPTIONS:\n");
    	//printf("\n -p, --parents  No error if existing, make parent directories as needed\n");
		printf(" -v, --verbose\n");
		printf("     Print a message for each created directory\n");
        printf(" -h, --help\n");
        printf("     Display this help\n");
	}

	return 0;
}

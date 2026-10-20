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
extern unsigned char _SYSVAR_LODDRV;
extern unsigned char _SYSVAR_SAVDRV;

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
		uint8_t numpaths = 0;

		for (uint8_t i = 1; i < argc; ++i)
		{
			if (argv[i] != NULL)
			{
				uint8_t r;
				const char * path = argv[i];

				if (strcmp(path, "...") == 0)
				{
					path = "../..";
				}
				else if (strcmp(path, "....") == 0)
				{
					path = "../../..";
				}
				else if (strcmp(path, ".....") == 0)
				{
					path = "../../../..";
				}

				r = esx_f_chdir(path);

				if (r == 0)
				{
					if ((path[0] != '\0') && (path[1] == ':'))
					{
						int16_t dosver = esx_m_dosversion();
						uint8_t drive = path[0] & ~0x20;

						if (dosver > 0)
						{
							esx_dos_set_drive(drive);
							_SYSVAR_LODDRV = drive;
							_SYSVAR_SAVDRV = drive;
						}
						else
						{
							esx_m_setdrv(((drive - 'A') << 3) + 1);
						}
					}

					esx_f_getcwd(pathname);
					if (optionVerbose)
					{
						PrintFormatted("%s\n", pathname);
					}
				}
				else
				{
					PrintFormatted("'%s' does not exist\n", path);
				}

				numpaths++;
			}
		}

		if (numpaths == 0)
		{
			esx_f_getcwd(pathname);
			PrintFormatted("%s\n", pathname);
		}
	}
	else
	{
		printf("CD v1.0 by Gari Biasillo\n");
		printf("Change current directory\n\n");
		printf("\nSYNOPSIS:\n .CD [OPTION]... DIR...\n");
		printf("OPTIONS:\n");
		printf(" -v, --verbose\n");
		printf("     Verbose output\n");
	printf(" -h, --help\n");
	printf("     Display this help\n");
		printf("\nINFO:\n");
	printf(" .CD ...  is the same as two cd .. commands\n");
	printf(" .CD ....  is the same as three cd .. commands\n");
	printf(" .CD .....  is the same as four cd .. commands\n");
	}

	return 0;
}

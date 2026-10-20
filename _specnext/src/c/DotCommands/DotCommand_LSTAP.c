///////////////////////////////////////////////////////////
//
///////////////////////////////////////////////////////////
#include "DotCommandShared.h"

///////////////////////////////////////////////////////////
//
///////////////////////////////////////////////////////////
bool optionHelp = false;
bool optionOutput = false;
bool optionInput = false;
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
                else if (stricmp(arg, "-o") == 0 || stricmp(arg, "--output") == 0)
                {
                        argv[i] = NULL;
                        optionOutput = true;
                }
                else if (stricmp(arg, "-i") == 0 || stricmp(arg, "--input") == 0)
                {
                        argv[i] = NULL;
                        optionInput = true;
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

        if ((optionInput && optionOutput) || (fileArg && (optionInput || optionOutput)))
        {
                optionHelp = true;
        }

        if (argc == 1)
        {
                optionHelp = true;
        }

        return !optionHelp;
}

///////////////////////////////////////////////////////////
//
///////////////////////////////////////////////////////////
void ShowBlockDetails(unsigned char * buffer, uint16_t blocklen)
{
        if (buffer[0] == 0)
        {
                unsigned char * tapename = buffer + 2;
                uint16_t word2 = *(uint16_t *)(buffer + 14);
                char varname[2];
                varname[0] = buffer[15] & 0x7f | 0x40;
                varname[1] = '\0';
                tapename[10] = '\0';

                switch(buffer[1])
                {
                        case 0:
                                printf("Prog: %s", tapename);
                                if ((word2 & 0x8000) == 0)
                                {
                                        printf(" LINE %04d", word2);
                                }
                                break;

                        case 1:
                                printf("Num : %s DATA %s()", tapename, varname);
                                break;

                        case 2:
                                printf("Char: %s DATA %s$()", tapename, varname);
                                break;

                        case 3:
                                printf("Bytes: %s  @ %05u", tapename, word2);
                                break;
                        case 4:
                                printf("Layer 1: %s", tapename);
                                break;
                        case 5:
                                printf("Layer 2: %s", tapename);
                                break;
                        default:
                                printf("flag=%03d, len=%05u",
                                        buffer[0], blocklen - 2);
                                break;
                }
        }
        else
        {
                printf("flag=%03d, len=%05u", buffer[0], blocklen - 2);
        }

        printf("\n");
}

///////////////////////////////////////////////////////////
//
///////////////////////////////////////////////////////////
int main(int argc, char **argv)
{
        CommonInit();

        if (ProcessOptions(argc, argv))
        {
                unsigned char * filename = pathname;
                uint16_t blk = 0;
                uint16_t blockptr = 0xffff;
                uint8_t drive;
                uint8_t handle;

                if (optionInput)
                {
                        if (esx_m_tapein_info(&drive, pathname))
                        {
                                printf("No tape input file\n");
                                return 0;
                        }

                        if (drive == '*')
                        {
                                printf("%s\n", pathname);
                        }
                        else
                        {
                                char letter = 'A'+(drive>>3);
                                printf("%c:%s\n", letter, pathname);
                        }

                        blockptr = esx_m_tapein_getpos();
                }

                if (optionOutput)
                {
                        if (esx_m_tapeout_info(&drive, pathname))
                        {
                                printf("No tape output file\n");
                                return 0;
                        }


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

                if (fileArg)
                {
                        filename = argv[fileArg];
                        printf("%s\n\n", filename);
                }

                handle = esx_f_open(filename, ESX_MODE_OPEN_EXIST | ESX_MODE_READ);
                if (errno)
                {
                        return errno;
                }

                for (blk = 0; true; blk++)
                {
                        uint16_t size;
                        uint16_t blocklen;
                        unsigned char buffer[19];

                        size = esx_f_read(handle, &blocklen, 2);
                        if (size < 2)
                                break;

                        size = esx_f_read(handle, buffer,
                                        (blocklen < 19) ? blocklen : 19);

                        esx_f_seek(handle, blocklen - size, ESX_SEEK_FWD);

                        if (errno)
                        {
                                return errno;
                        }

                        printf("%05d", blk);
                        if (blk == blockptr)
                        {
                                printf(">");
                        }
                        else
                        {
                                printf(" ");
                        }

                        ShowBlockDetails(buffer, blocklen);
                }

                esx_f_close(handle);
        }
        else
        {
                printf("LSTAP v1.1 by Garry Lancaster\n");
                printf("List contents of any .TAP file\n\n");
                printf("SYNOPSIS:\n .LSTAP [OPTION]... [FILE]\n\n");
                printf("OPTIONS:\n");
                printf(" -h, --help\n");
                printf("     Display this help\n");
                printf(" -i, --input\n");
                printf("     Use current input file\n");
                printf(" -o, --output\n");
                printf("     Use current output file\n");
        }

        return 0;
}

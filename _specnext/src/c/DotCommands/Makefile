PACKAGE_DIR=DOT
INSTALL_DIR=../../../dot
PACKAGE_SOURCE_DIR=PackagedSource
ESXDIR=/Applications/zesarux.app/Contents/MacOS/media/spectrum/esxdos_handler/0.8.6_TBBLUE

ifeq (1,0)
CLIB=new
CFLAGS=--opt-code-size
OPT=3
else
CLIB=sdcc_iy
CFLAGS=--opt-code-size
#CFLAGS=--max-allocs-per-node200000 --opt-code-size
OPT=3
endif

OPTIONS_PRE=+zxn -vn -m -startup=30 -clib=sdcc_iy -SO3 -pragma-include:dpragma.inc DotCommandShared.c
OPTIONS_POST=-Cz"--pages" -subtype=dot -create-app

#==============================================================================
#
#==============================================================================
.PHONY: depend clean
.SUFFIXES: .o .c
.SUFFIXES: .o .asm
SEGS =

#==============================================================================
#
#==============================================================================
default: dotcommand_cd dotcommand_mkdir dotcommand_rmdir dotcommand_rm dotcommand_chmod dotcommand_tapein dotcommand_tapeout dotcommand_lstap
	
all: default dotcommand_others

distro: all install

dotcommand_others: dotcommand_config dotcommand_cowsay dotcommand_dzx7 dotcommand_mv dotcommand_ls dotcommand_run dotcommand_strings dotcommand_extract dotcommand_find dotcommand_cp

dotcommand_cp: 
	@echo "\n**** Creating CP ****"
	make -C cp

dotcommand_find: 
	@echo "\n**** Creating FIND ****"
	make -C find/128

dotcommand_extract: 
	@echo "\n**** Creating EXTRACT ****"
	make -C extract

dotcommand_strings: 
	@echo "\n**** Creating STRINGS ****"
	make -C strings

dotcommand_cowsay: 
	@echo "\n**** Creating COWSAY ****"
	make -C cowsay

dotcommand_config: 
	@echo "\n**** Creating CONFIG ****"
	make -C config/128

dotcommand_ls:
	@echo "\n**** Creating LS ****"
	make -C ls/128

dotcommand_mv:
	@echo "\n**** Creating MV ****"
	make -C mv

dotcommand_run:
	@echo "\n**** Creating RUN ****"
	make -C run

dotcommand_dzx7:
	@echo "\n**** Creating DZX7 ****"
	make -C dzx7/128

dotcommand_cd: DotCommand_CD.c mmap.inc dpragma.inc Makefile
	@echo "\n**** Creating CD ****"
	zcc $(OPTIONS_PRE) DotCommand_CD.c -o CD $(OPTIONS_POST)

dotcommand_mkdir: DotCommand_MKDIR.c mmap.inc dpragma.inc Makefile
	@echo "\n**** Creating MKDIR ****"
	zcc $(OPTIONS_PRE) DotCommand_MKDIR.c -o MKDIR $(OPTIONS_POST)

dotcommand_rm: DotCommand_RM.c mmap.inc dpragma.inc Makefile
	@echo "\n**** Creating RM ****"
	zcc $(OPTIONS_PRE) DotCommand_RM.c -o RM $(OPTIONS_POST)

dotcommand_rmdir: DotCommand_RMDIR.c DotCommandShared.c mmap.inc dpragma.inc Makefile
	@echo "\n**** Creating RMDIR ****"
	zcc $(OPTIONS_PRE) DotCommand_RMDIR.c -o RMDIR $(OPTIONS_POST)

dotcommand_chmod: DotCommand_CHMOD.c DotCommandShared.c mmap.inc dpragma.inc Makefile
	@echo "\n**** Creating CHMOD ****"
	zcc $(OPTIONS_PRE) DotCommand_CHMOD.c -o CHMOD $(OPTIONS_POST)

dotcommand_tapein: DotCommand_TAPEIN.c DotCommandShared.c mmap.inc dpragma.inc Makefile
	@echo "\n**** Creating TAPEIN ****"
	zcc $(OPTIONS_PRE) DotCommand_TAPEIN.c -o TAPEIN $(OPTIONS_POST)

dotcommand_tapeout: DotCommand_TAPEOUT.c DotCommandShared.c mmap.inc dpragma.inc Makefile
	@echo "\n**** Creating TAPEOUT ****"
	zcc $(OPTIONS_PRE) DotCommand_TAPEOUT.c -o TAPEOUT $(OPTIONS_POST)

dotcommand_lstap: DotCommand_LSTAP.c DotCommandShared.c mmap.inc dpragma.inc Makefile
	@echo "\n**** Creating LSTAP ****"
	zcc $(OPTIONS_PRE) DotCommand_LSTAP.c -o LSTAP $(OPTIONS_POST)

#copy_zesarux:
#	@echo "**** Copying to ZEsarUX ESXDos Folder ***"
#	\cp -rp $(PACKAGE_DIR)/CD2 ${ESXDIR}/BIN
#	@echo "Complete\n"

package-source:
	@mkdir -p $(PACKAGE_SOURCE_DIR)
	@\cp -f *.c ${PACKAGE_SOURCE_DIR}
	@\cp -f *.h ${PACKAGE_SOURCE_DIR}
	@\cp -f Makefile ${PACKAGE_SOURCE_DIR}
	@\cp -f dpragma.inc ${PACKAGE_SOURCE_DIR}
	@\cp -f mmap.inc ${PACKAGE_SOURCE_DIR}

install:
	@\cp -fv CD ${INSTALL_DIR}
	@\cp -fv MKDIR ${INSTALL_DIR}
	@\cp -fv RMDIR ${INSTALL_DIR}
	@\cp -fv RM ${INSTALL_DIR}
	@\cp -fv TAPEIN ${INSTALL_DIR}
	@\cp -fv TAPEOUT ${INSTALL_DIR}
	@\cp -fv LSTAP ${INSTALL_DIR}
	@\cp -fv cowsay/COWSAY ${INSTALL_DIR}
	@\cp -fv config/128/CONFIG ${INSTALL_DIR}
	@\cp -fv cp/CP ${INSTALL_DIR}
	@\cp -fv find/128/FIND ${INSTALL_DIR}
	@\cp -fv run/RUN ${INSTALL_DIR}
	@\cp -fv mv/MV ${INSTALL_DIR}
	@\cp -fv extract/EXTRACT ${INSTALL_DIR}
	@\cp -fv strings/STRINGS ${INSTALL_DIR}
	@\cp -fv dzx7/128/DZX7 ${INSTALL_DIR}

package-dot:
	@echo "\n**** Packaging Dot Commands ****"
	@mkdir -p $(PACKAGE_DIR)
	@\cp -f CD ${PACKAGE_DIR}
	@\cp -f MKDIR ${PACKAGE_DIR}
	@\cp -f RMDIR ${PACKAGE_DIR}
	@\cp -f RM ${PACKAGE_DIR}
	@\cp -f TAPEIN ${PACKAGE_DIR}
	@\cp -f TAPEOUT ${PACKAGE_DIR}
	@\cp -f LSTAP ${PACKAGE_DIR}
	@\cp -f cowsay/COWSAY ${PACKAGE_DIR}
	@\cp -f config/128/CONFIG ${PACKAGE_DIR}
	@\cp -f cp/CP ${PACKAGE_DIR}
	@\cp -f find/128/FIND ${PACKAGE_DIR}
	@\cp -f run/RUN ${PACKAGE_DIR}
	@\cp -f mv/MV ${PACKAGE_DIR}
	@\cp -f extract/EXTRACT ${PACKAGE_DIR}
	@\cp -f strings/STRINGS ${PACKAGE_DIR}
	@\cp -f dzx7/128/DZX7 ${PACKAGE_DIR}

copy-flashair:
	@echo "\n**** Copying to Flashair ****"
	curl -s -F file=@$(PACKAGE_DIR)/CD -F submit=submit http://168.192.1.99/upload.cgi >/dev/null
	curl -s -F file=@$(PACKAGE_DIR)/MKDIR -F submit=submit http://168.192.1.99/upload.cgi >/dev/null
	curl -s -F file=@$(PACKAGE_DIR)/RMDIR -F submit=submit http://168.192.1.99/upload.cgi >/dev/null
	curl -s -F file=@$(PACKAGE_DIR)/RM -F submit=submit http://168.192.1.99/upload.cgi >/dev/null
	curl -s -F file=@$(PACKAGE_DIR)/TAPEIN -F submit=submit http://168.192.1.99/upload.cgi >/dev/null
	curl -s -F file=@$(PACKAGE_DIR)/TAPEOUT -F submit=submit http://168.192.1.99/upload.cgi >/dev/null
	curl -s -F file=@$(PACKAGE_DIR)/LSTAP -F submit=submit http://168.192.1.99/upload.cgi >/dev/null
	@echo "Complete\n"


#==============================================================================
#
#==============================================================================
.asm.o:
	zcc +zxn -m -vn -c -clib=$(CLIB) -SO$(OPT) $(CFLAGS) $(SEGS) $<
.c.o:
	zcc +zxn -m -vn -c -clib=$(CLIB) -SO$(OPT) $(CFLAGS) $(SEGS) $<

#==============================================================================
#
#==============================================================================
clean:
	-rm -f *.o *.bin *.font *.map *.sym zcc_proj.lst zcc_opt.def *.orig *.tap *.sna *.snx *.nex
	-rm -f CD RM RMDIR MKDIR CHMOD TAPEIN TAPEOUT LSTAP
	-rm -f cowsay/COWSAY cowsay/*.bin cowsay/zcc_opt.def
	-rm -f config/128/CONFIG config/128/*.bin config/128/*.o config/128/zcc_opt.def
	-rm -f cp/CP cp/*.bin cp/zcc_opt.def
	-rm -f strings/STRINGS strings/*.bin
	-rm -f find/128/FIND find/128/*.bin
	-rm -f ls/128/LS ls/128/*.bin
	-rm -f run/RUN rum/*.bin
	-rm -f mv/MV mv/*.bin mv/*.map
	-rm -f extract/EXTRACT extract/*.bin
	-rm -f dzx7/128/DZX7 dzx7/128/*.bin

depend: $(CSRC)
	makedepend $(INCL) $^

# DO NOT DELETE THIS LINE -- make depend needs it

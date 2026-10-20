#
# Makefile for dot commands
#

ASM = pasmo --nocase
RM = rm -f
BUILDDIR = ../build/dot

all:
	mkdir -p $(BUILDDIR)
	$(ASM) $$.asm $(BUILDDIR)/$$ $$.sym
	$(ASM) cpm.asm $(BUILDDIR)/CPM cpm.sym
	$(ASM) defrag.asm $(BUILDDIR)/DEFRAG defrag.sym
	$(ASM) lfn.asm $(BUILDDIR)/LFN lfn.sym
	$(ASM) mem.asm $(BUILDDIR)/MEM mem.sym
	$(ASM) -E MKDATA=1 mkp3d.asm $(BUILDDIR)/MKDATA mkdata.sym
	$(ASM) -E MKDATA=0 mkp3d.asm $(BUILDDIR)/MKSWAP mkswap.sym
	$(ASM) install.asm $(BUILDDIR)/INSTALL install.sym
	$(ASM) uninstall.asm $(BUILDDIR)/UNINSTALL uninstall.sym
	$(ASM) browse.asm $(BUILDDIR)/BROWSE browse.sym
	$(ASM) browseprefs.asm $(BUILDDIR)/BROWSEPREFS browseprefs.sym
	$(ASM) editprefs.asm $(BUILDDIR)/EDITPREFS editprefs.sym
	$(ASM) nextver.asm $(BUILDDIR)/NEXTVER nextver.sym
	$(ASM) bas2txt.asm $(BUILDDIR)/BAS2TXT bas2txt.sym
	$(ASM) txt2bas.asm $(BUILDDIR)/TXT2BAS txt2bas.sym
	$(ASM) core.asm $(BUILDDIR)/CORE core.sym
	$(ASM) makerun.asm $(BUILDDIR)/MAKERUN makerun.sym
	$(ASM) makelnk.asm $(BUILDDIR)/MAKELNK makelnk.sym
	$(ASM) clear.asm $(BUILDDIR)/CLEAR clear.sym
	$(ASM) metadata.asm $(BUILDDIR)/METADATA metadata.sym
	$(ASM) ret.asm $(BUILDDIR)/RET ret.sym
	$(ASM) crc32.asm $(BUILDDIR)/CRC32 crc32.sym

clean:
	$(RM) -rf $(BUILDDIR)
	$(RM) *.sym

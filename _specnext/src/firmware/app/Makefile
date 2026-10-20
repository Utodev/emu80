#
# ZX Spectrum Next Firmware
# Copyright 2020 Garry Lancaster, Fabio Belavenuto & Victor Trucco
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY#  without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

CC = sdcc
AS = sdasz80
LD = sdcc
CP = copy
RM = rm -f
MKDIR = mkdir -p
MKBIN = makebin
H2B = hex2bin
MIF = srec_cat
GREP = grep

SDIR = src
IDIR = inc
ODIR = obj

CFLAGS = -mz80 --opt-code-size  -I$(IDIR) -I..
LDFLAGS = -mz80 --code-loc 0x6010 --data-loc 0 --no-std-crt0

ROFLAGS = -D_FS_READONLY=1 -D_FS_MINIMIZE=1
RWFLAGS = -D_FS_READONLY=0 -D_FS_MINIMIZE=2

_OBJS0 = crt0.rel boot.rel vdp.rel vdplow.rel spi.rel flash.rel diskio.rel ffro.rel misc.rel modules.rel config.rel fwfile.rel switch.rel videomagic.rel
OBJS0 = $(patsubst %,$(ODIR)/%,$(_OBJS0))

_OBJS1 = crt0.rel editor.rel vdp.rel spi.rel diskio.rel ff.rel misc.rel config.rel configw.rel
OBJS1 = $(patsubst %,$(ODIR)/%,$(_OBJS1))

_OBJS2 = crt0.rel updater.rel vdp.rel spi.rel flash.rel flashw.rel diskio.rel ffro.rel misc.rel config.rel
OBJS2 = $(patsubst %,$(ODIR)/%,$(_OBJS2))

_OBJS3 = crt0.rel cores.rel vdp.rel spi.rel flash.rel flashw.rel diskio.rel ffro.rel misc.rel config.rel
OBJS3 = $(patsubst %,$(ODIR)/%,$(_OBJS3))

_OBJS4 = crt0.rel videotest.rel vdp.rel spi.rel diskio.rel ff.rel misc.rel fwfile.rel config.rel configw.rel layers.rel videomagic.rel
OBJS4 = $(patsubst %,$(ODIR)/%,$(_OBJS4))

_OBJS5 = crt0.rel reset.rel vdp.rel spi.rel diskio.rel ff.rel misc.rel config.rel configw.rel
OBJS5 = $(patsubst %,$(ODIR)/%,$(_OBJS5))

all:  dir boot.ihx editor.ihx updater.ihx cores.ihx videotest.ihx reset.ihx
	$(GREP) -i s__HEAP *.map

boot.ihx: $(OBJS0)
	$(LD) $(LDFLAGS) -o $@ $(OBJS0)
	$(H2B) -e bin $@

editor.ihx: $(OBJS1)
	$(LD) $(LDFLAGS) -o $@ $(OBJS1)
	$(H2B) -e bin $@

updater.ihx: $(OBJS2)
	$(LD) $(LDFLAGS) -o $@ $(OBJS2)
	$(H2B) -e bin $@

cores.ihx: $(OBJS3)
	$(LD) $(LDFLAGS) -o $@ $(OBJS3)
	$(H2B) -e bin $@

videotest.ihx: $(OBJS4)
	$(LD) $(LDFLAGS) -o $@ $(OBJS4)
	$(H2B) -e bin $@

reset.ihx: $(OBJS5)
	$(LD) $(LDFLAGS) -o $@ $(OBJS5)
	$(H2B) -e bin $@

.PHONY: clean dir

dir:
	$(MKDIR) obj

clean:
	$(RM) -r $(ODIR) *.map *.lk *.lst *.noi *.fw *.ihx *.bin

$(ODIR)/crt0.rel: $(SDIR)/crt0.s
	$(AS) -o $@ $<

$(ODIR)/spi.rel: $(SDIR)/spi.s
	$(AS) -o $@ $<

$(ODIR)/vdplow.rel: $(SDIR)/vdplow.s
	$(AS) -o $@ $<

$(ODIR)/switch.rel: $(SDIR)/switch.s
	$(AS) -o $@ $<

$(ODIR)/ffro.rel: $(SDIR)/ff/ff.c $(IDIR)/*.h ../hardware.h
	$(CC) $(CFLAGS) $(ROFLAGS) -c -o $@ $<

$(ODIR)/ff.rel: $(SDIR)/ff/ff.c $(IDIR)/*.h ../hardware.h
	$(CC) $(CFLAGS) $(RWFLAGS) -c -o $@ $<

$(ODIR)/%.rel: $(SDIR)/%.c $(IDIR)/*.h ../hardware.h
	$(CC) $(CFLAGS) -c -o $@ $<

$(ODIR)/%.rel: $(SDIR)/ff/%.c $(IDIR)/*.h ../hardware.h
	$(CC) $(CFLAGS) -c -o $@ $<

$(ODIR)/%.rel: $(SDIR)/ff/option/%.c
	$(CC) $(CFLAGS) -c -o $@ $<

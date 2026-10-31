The MSX ROMs:

- QUANTIKA.ROM and QUANTIKA_SUB.ROM: emu80's own 32K BIOS with FBASIC and 16K sub-ROM, the MSX 2's ROMs. They come with
  emu80.
- To use the original ROMs instead, look for MSX2.rom (the 32K BIOS + MSX-BASIC 2 of an MSX2 machine) and MSX2EXT.rom (its
  16K sub-ROM), put them here and choose them in Settings > Common > ROMs (or with `--rom "msx2,0,FILE"` and
  `--rom "msx2,1,FILE"`). They are not distributed, and git ignores them.
- PHILIPSDISK.rom: the 16K ROM of a Philips disk interface, for a disk drive: put it here and choose it in Settings >
  Common > ROMs (FLOPPY DISK, empty by default; or `--rom "msx2,2,FILE"`). It only works with the original MSX2.rom:
  with QUANTIKA.ROM there is no disk drive. Not distributed either.

Cartridges (.rom), tapes (.cas) and disks (.dsk) are opened from the menus, not from here.

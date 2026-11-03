{ Models: per-model hardware description of the supported Spectrums. }
unit Models;

{$mode objfpc}{$H+}

interface

type
  TSpectrumModel = (sm16K, sm48K, sm128K, smPlus2, smPlus2B, smPlus3, smZXUno, smZXNext,
    smCPC464, smCPC664, smCPC6128, smSAM, smMSX2, smC64);

  { How the picture is shown, as if the Spectrum's frames were the fields of
    an interlaced picture: each frame on its own (progressive, as the
    Spectrum sends it), two frames blended (Bob) or two frames' lines
    interleaved (Weave) }
  TDeinterlace = (dlProgressive, dlBob, dlWeave);

  { Which memory/port architecture the model uses }
  TMemoryKind = (mk48K, mk128K, mkPlus3, mkZXUno, mkZXNext, mkCPC, mkSAM, mkMSX, mkC64);

  TModelInfo = record
    Name: string;
    Memory: TMemoryKind;
    RomFiles: array[0..3] of string;
    RomCount: Integer;
    BasicRom: Integer;           // ROM holding the 48K BASIC (tape traps)
    ClockHz: Integer;
    FrameT: Integer;             // T-states per frame
    LineT: Integer;              // T-states per scanline
    PaperTopT: Integer;          // T-state the ULA fetches the top-left paper byte
    ContentionStartT: Integer;   // first contended T-state
    ContentionPattern: array[0..7] of Byte;
    InterruptLength: Integer;    // T-states /INT stays asserted
    IOContention: Boolean;       // ULA I/O contention applies
    NoMreqContention: Boolean;   // cycles without MREQ are contended
    FloatingBus: Boolean;
    HasAY: Boolean;
    HasFDC: Boolean;
    Ram16K: Boolean;             // no memory at 8000-FFFF
  end;

const
  ModelInfo: array[TSpectrumModel] of TModelInfo = (
    (Name: 'ZX Spectrum 16K'; Memory: mk48K;
     RomFiles: ('48.rom', '', '', ''); RomCount: 1; BasicRom: 0;
     ClockHz: 3500000; FrameT: 69888; LineT: 224; PaperTopT: 14336;
     ContentionStartT: 14335; ContentionPattern: (6, 5, 4, 3, 2, 1, 0, 0);
     InterruptLength: 32; IOContention: True; NoMreqContention: True;
     FloatingBus: True; HasAY: False; HasFDC: False; Ram16K: True),
    (Name: 'ZX Spectrum 48K'; Memory: mk48K;
     RomFiles: ('48.rom', '', '', ''); RomCount: 1; BasicRom: 0;
     ClockHz: 3500000; FrameT: 69888; LineT: 224; PaperTopT: 14336;
     ContentionStartT: 14335; ContentionPattern: (6, 5, 4, 3, 2, 1, 0, 0);
     InterruptLength: 32; IOContention: True; NoMreqContention: True;
     FloatingBus: True; HasAY: False; HasFDC: False),
    (Name: 'ZX Spectrum 128K'; Memory: mk128K;
     RomFiles: ('128-0.rom', '128-1.rom', '', ''); RomCount: 2; BasicRom: 1;
     ClockHz: 3546900; FrameT: 70908; LineT: 228; PaperTopT: 14362;
     ContentionStartT: 14361; ContentionPattern: (6, 5, 4, 3, 2, 1, 0, 0);
     InterruptLength: 36; IOContention: True; NoMreqContention: True;
     FloatingBus: True; HasAY: True; HasFDC: False),
    (Name: 'ZX Spectrum +2'; Memory: mk128K;
     RomFiles: ('plus2-0.rom', 'plus2-1.rom', '', ''); RomCount: 2; BasicRom: 1;
     ClockHz: 3546900; FrameT: 70908; LineT: 228; PaperTopT: 14362;
     ContentionStartT: 14361; ContentionPattern: (6, 5, 4, 3, 2, 1, 0, 0);
     InterruptLength: 36; IOContention: True; NoMreqContention: True;
     FloatingBus: True; HasAY: True; HasFDC: False),
    (Name: 'ZX Spectrum +2B'; Memory: mkPlus3;
     RomFiles: ('plus3-0.rom', 'plus3-1.rom', 'plus3-2.rom', 'plus3-3.rom'); RomCount: 4; BasicRom: 3;
     ClockHz: 3546900; FrameT: 70908; LineT: 228; PaperTopT: 14365;
     ContentionStartT: 14361; ContentionPattern: (1, 0, 7, 6, 5, 4, 3, 2);
     InterruptLength: 32; IOContention: False; NoMreqContention: False;
     FloatingBus: False; HasAY: True; HasFDC: False),
    (Name: 'ZX Spectrum +3'; Memory: mkPlus3;
     RomFiles: ('plus3-0.rom', 'plus3-1.rom', 'plus3-2.rom', 'plus3-3.rom'); RomCount: 4; BasicRom: 3;
     ClockHz: 3546900; FrameT: 70908; LineT: 228; PaperTopT: 14365;
     ContentionStartT: 14361; ContentionPattern: (1, 0, 7, 6, 5, 4, 3, 2);
     InterruptLength: 32; IOContention: False; NoMreqContention: False;
     FloatingBus: False; HasAY: True; HasFDC: True),
    { ZX-Uno: its BIOS (zxuno/FIRMWARE.ZX1) chooses the ROM (from
      zxuno/ROMS.ZX1) and the timing (48K, 128K or Pentagon); it starts
      with 48K timing }
    (Name: 'ZX-Uno'; Memory: mkZXUno;
     RomFiles: ('', '', '', ''); RomCount: 0; BasicRom: 0;
     ClockHz: 3500000; FrameT: 69888; LineT: 224; PaperTopT: 14336;
     ContentionStartT: 14335; ContentionPattern: (6, 5, 4, 3, 2, 1, 0, 0);
     InterruptLength: 32; IOContention: True; NoMreqContention: True;
     FloatingBus: True; HasAY: True; HasFDC: False),
    { ZX Spectrum Next: its ROMs (NextZXOS) come from the distribution in
      the specnext folder; +3 timing, as its firmware sets it }
    (Name: 'ZX Spectrum Next'; Memory: mkZXNext;
     RomFiles: ('', '', '', ''); RomCount: 0; BasicRom: 3;
     ClockHz: 3546900; FrameT: 70908; LineT: 228; PaperTopT: 14365;
     ContentionStartT: 14361; ContentionPattern: (1, 0, 7, 6, 5, 4, 3, 2);
     InterruptLength: 32; IOContention: False; NoMreqContention: False;
     FloatingBus: False; HasAY: True; HasFDC: False),
    { Amstrad CPC: a Z80 at 4 MHz held by the Gate Array to 1 MHz accesses;
      a frame is 312 lines of 64 us (the CRTC's power-on timing), which the
      CRTC may change; RomFiles: the 32K firmware (system and BASIC) and the
      AMSDOS disc ROM. The ULA fields mean nothing here. }
    (Name: 'Amstrad CPC 464'; Memory: mkCPC;
     RomFiles: ('cpc464.rom', '', '', ''); RomCount: 1; BasicRom: 0;
     ClockHz: 4000000; FrameT: 79872; LineT: 256; PaperTopT: 0;
     ContentionStartT: 0; ContentionPattern: (0, 0, 0, 0, 0, 0, 0, 0);
     InterruptLength: 0; IOContention: False; NoMreqContention: False;
     FloatingBus: False; HasAY: True; HasFDC: False),
    (Name: 'Amstrad CPC 664'; Memory: mkCPC;
     RomFiles: ('cpc664.rom', 'amsdos.rom', '', ''); RomCount: 2; BasicRom: 0;
     ClockHz: 4000000; FrameT: 79872; LineT: 256; PaperTopT: 0;
     ContentionStartT: 0; ContentionPattern: (0, 0, 0, 0, 0, 0, 0, 0);
     InterruptLength: 0; IOContention: False; NoMreqContention: False;
     FloatingBus: False; HasAY: True; HasFDC: True),
    (Name: 'Amstrad CPC 6128'; Memory: mkCPC;
     RomFiles: ('cpc6128.rom', 'amsdos.rom', '', ''); RomCount: 2; BasicRom: 0;
     ClockHz: 4000000; FrameT: 79872; LineT: 256; PaperTopT: 0;
     ContentionStartT: 0; ContentionPattern: (0, 0, 0, 0, 0, 0, 0, 0);
     InterruptLength: 0; IOContention: False; NoMreqContention: False;
     FloatingBus: False; HasAY: True; HasFDC: True),
    { SAM Coupe: a 6 MHz Z80B and the ASIC, 512K of RAM in 16K pages; a frame
      is 312 lines of 384 T-states (50 Hz); RomFiles: the 32K ROM (ROM0 and
      ROM1). It has a SAA1099, not an AY, and a WD1772 floppy controller; the
      ULA fields mean nothing here. }
    (Name: 'SAM Coup'#$C3#$A9; Memory: mkSAM;
     RomFiles: ('samcoupe.rom', '', '', ''); RomCount: 1; BasicRom: 0;
     ClockHz: 6000000; FrameT: 119808; LineT: 384; PaperTopT: 0;
     ContentionStartT: 0; ContentionPattern: (0, 0, 0, 0, 0, 0, 0, 0);
     InterruptLength: 0; IOContention: False; NoMreqContention: False;
     FloatingBus: False; HasAY: False; HasFDC: True),
    { MSX2 (PAL): a Z80 at 3.579545 MHz with the V9938 (128K of VRAM), 128K of RAM in a memory mapper, a
      clock chip; RomFiles (in roms/msx): the 32K BIOS with BASIC, the 16K sub-ROM and the disk interface's
      ROM (QUANTIKA_DISK.ROM works only with QUANTIKA's main ROM, PHILIPSDISK.rom only with the original one).
      By default the free ROMs (QUANTIKA, made by their own project); the original ones (MSX2.rom, MSX2EXT.rom,
      PHILIPSDISK.rom) are chosen in the settings. }
    (Name: 'MSX 2'; Memory: mkMSX;
     RomFiles: ('msx/QUANTIKA.ROM', 'msx/QUANTIKA_SUB.ROM', 'msx/QUANTIKA_DISK.ROM', ''); RomCount: 3; BasicRom: 0;
     ClockHz: 3579545; FrameT: 71364; LineT: 228; PaperTopT: 0;
     ContentionStartT: 0; ContentionPattern: (0, 0, 0, 0, 0, 0, 0, 0);
     InterruptLength: 0; IOContention: False; NoMreqContention: False;
     FloatingBus: False; HasAY: True; HasFDC: True),
    { Commodore 64 (PAL): a 6510 at 985248 Hz, the VIC-II (312 lines of 63 cycles), two CIAs, the SID and
      1541 disk drives; RomFiles (in roms/c64): the KERNAL, BASIC, the character generator and the drive's DOS.
      The ROMs are the user's (Kernal.rom, Basic.rom, Char.rom, VC1541.rom). The Z80 fields mean nothing here. }
    (Name: 'Commodore 64'; Memory: mkC64;
     RomFiles: ('c64/Kernal.rom', 'c64/Basic.rom', 'c64/Char.rom', 'c64/VC1541.rom'); RomCount: 4; BasicRom: 0;
     ClockHz: 985248; FrameT: 19656; LineT: 63; PaperTopT: 0;
     ContentionStartT: 0; ContentionPattern: (0, 0, 0, 0, 0, 0, 0, 0);
     InterruptLength: 0; IOContention: False; NoMreqContention: False;
     FloatingBus: False; HasAY: False; HasFDC: True)
  );

function ModelFromName(const S: string; Default: TSpectrumModel): TSpectrumModel;
function ModelKey(M: TSpectrumModel): string;
{ A ZX Spectrum (the 16K to the +3, the ZX-Uno, the Next), not one of the other machines }
function IsSpectrumModel(M: TSpectrumModel): Boolean;
{ An Amstrad CPC (not a Spectrum) }
function IsCPCModel(M: TSpectrumModel): Boolean;
{ A SAM Coupe (not a Spectrum) }
function IsSAMModel(M: TSpectrumModel): Boolean;
{ An MSX (not a Spectrum) }
function IsMSXModel(M: TSpectrumModel): Boolean;
{ A Commodore 64 (a 6510, not a Z80) }
function IsC64Model(M: TSpectrumModel): Boolean;
{ An MSX2 (the V9938 and a memory mapper) }
function IsMSX2Model(M: TSpectrumModel): Boolean;
{ The MSX2's ROM files by default become the original ones (msx/MSX2.rom, msx/MSX2EXT.rom): for the test
  tools that compare the original ROMs with the free ones }
procedure UseOriginalMsxRoms;

var
  { A second ROM folder, looked in for a ROM file missing from the ROM folder: the user's own (the macOS app's
    ~/Library/Application Support/ochenta/roms, as the app bundle's own roms can't be added to); '' = none }
  UserRomDir: string = '';

implementation

const
  Keys: array[TSpectrumModel] of string = ('16k', '48k', '128k', 'plus2', 'plus2b', 'plus3', 'zxuno',
    'zxnext', 'cpc464', 'cpc664', 'cpc6128', 'sam', 'msx2', 'c64');

procedure UseOriginalMsxRoms;
begin
  ModelInfo[smMSX2].RomFiles[0] := 'msx/MSX2.rom';
  ModelInfo[smMSX2].RomFiles[1] := 'msx/MSX2EXT.rom';
  ModelInfo[smMSX2].RomFiles[2] := 'msx/PHILIPSDISK.rom';
end;

function ModelKey(M: TSpectrumModel): string;
begin
  Result := Keys[M];
end;

function ModelFromName(const S: string; Default: TSpectrumModel): TSpectrumModel;
var
  M: TSpectrumModel;
begin
  for M := Low(TSpectrumModel) to High(TSpectrumModel) do
    if S = Keys[M] then Exit(M);
  Result := Default;
end;

function IsSpectrumModel(M: TSpectrumModel): Boolean;
begin
  Result := ModelInfo[M].Memory in [mk48K, mk128K, mkPlus3, mkZXUno, mkZXNext];
end;

function IsCPCModel(M: TSpectrumModel): Boolean;
begin
  Result := ModelInfo[M].Memory = mkCPC;
end;

function IsSAMModel(M: TSpectrumModel): Boolean;
begin
  Result := ModelInfo[M].Memory = mkSAM;
end;

function IsMSXModel(M: TSpectrumModel): Boolean;
begin
  Result := ModelInfo[M].Memory = mkMSX;
end;

function IsC64Model(M: TSpectrumModel): Boolean;
begin
  Result := ModelInfo[M].Memory = mkC64;
end;

function IsMSX2Model(M: TSpectrumModel): Boolean;
begin
  Result := M = smMSX2;
end;

end.

{ Models: per-model hardware description of the supported Spectrums. }
unit Models;

{$mode objfpc}{$H+}

interface

type
  TSpectrumModel = (sm16K, sm48K, sm128K, smPlus2, smPlus2B, smPlus3, smZXUno, smZXNext);

  { How the picture is shown, as if the Spectrum's frames were the fields of
    an interlaced picture: each frame on its own (progressive, as the
    Spectrum sends it), two frames blended (Bob) or two frames' lines
    interleaved (Weave) }
  TDeinterlace = (dlProgressive, dlBob, dlWeave);

  { Which memory/port architecture the model uses }
  TMemoryKind = (mk48K, mk128K, mkPlus3, mkZXUno, mkZXNext);

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
     FloatingBus: False; HasAY: True; HasFDC: False)
  );

function ModelFromName(const S: string; Default: TSpectrumModel): TSpectrumModel;
function ModelKey(M: TSpectrumModel): string;

implementation

const
  Keys: array[TSpectrumModel] of string = ('16k', '48k', '128k', 'plus2', 'plus2b', 'plus3', 'zxuno',
    'zxnext');

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

end.

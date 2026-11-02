{ ZXUnoRegsForm: the debugger's chips window. The ZX-Uno's registers (ports FC3B/FD3B), the ZX
  Spectrum Next's (ports 243B/253B), the SAM Coupe's main ports (paging
  LMPR and HMPR, video page and mode VMPR, border, line interrupt, status, the
  CLUT and the SAA1099's registers), the MSX's, the ZX Spectrum's (16K to +3: the ULA's port FE, the paging, Timex,
  ULAplus and the AY's registers) or the Amstrad CPC's (the Gate Array, the CRTC, the PPI and the PSG), a non-modal
  window opened from the debugger. Each register with its number, name, value (hex, editable:
  writing it is like an OUT to FD3B, or a NEXTREG) and, for the ones made
  of flags, the bits set. Updated while the machine runs. }
unit ZXUnoRegsForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Grids, ExtCtrls, StdCtrls, LCLType,
  Emulator, Models, Spectrum, Msx, MsxMachine;

type
  { A port or a chip's register (a SAM Coupe's as TSpectrum.SamRegister numbers them, an MSX's, or a
    Spectrum's or a CPC's as TSpectrum.ChipRegister does) }
  TSamRegInfo = record
    Code: Integer;
    Port: string;
    Name: string;
    Bits: string;
    ReadOnly: Boolean;
  end;

  TZXUnoRegsWindow = class(TForm)
  private
    FEmu: TEmulator;
    FGrid: TStringGrid;
    FTimer: TTimer;
    FNote: TLabel;
    FNext: Boolean;         // showing the Next's registers
    FSam: Boolean;          // showing the SAM Coupe's ports
    FMsx: Boolean;          // showing the MSX's ports
    FChips: Boolean;        // showing a ZX Spectrum's (16K to +3) or an Amstrad CPC's (FRows, TSpectrum.ChipRegister)
    FModel: TSpectrumModel; // the machine the rows are for
    FRows: array of TSamRegInfo;
    FOnChanged: TNotifyEvent;
    procedure AddRow(Code: Integer; const APort, AName, ABits: string; AReadOnly: Boolean = False);
    procedure FillChips;
    function SamMapping(Port: Integer): string;
    function MsxMapping(Code: Integer): string;
    procedure Fill;
    procedure Tick(Sender: TObject);
    procedure GridSelectEditor(Sender: TObject; ACol, ARow: Integer; var Editor: TWinControl);
    procedure GridEditingDone(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  public
    constructor CreateFor(AOwner: TComponent; AEmu: TEmulator);
    procedure UpdateValues;
    { A register was written: the debugger shows the memory the new paging gives }
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
  end;

implementation

type
  TRegInfo = record
    Reg: Byte;
    Name: string;
    Bits: string;   // names of bits 7..0 separated by spaces ('-' unused), '' = a number
  end;

const
  REGS: array[0..29] of TRegInfo = (
    (Reg: $00; Name: 'MASTERCONF';   Bits: 'LOCK MODE1 DISCONT MODE0 I2KB DISNMI DIVEN BOOTM'),
    (Reg: $01; Name: 'MASTERMAPPER'; Bits: ''),
    (Reg: $02; Name: 'FLASHSPI';     Bits: ''),
    (Reg: $03; Name: 'FLASHCS';      Bits: ''),
    (Reg: $04; Name: 'SCANCODE';     Bits: ''),
    (Reg: $05; Name: 'KEYBSTAT';     Bits: ''),
    (Reg: $06; Name: 'JOYCONF';      Bits: ''),
    (Reg: $07; Name: 'KEYMAP';       Bits: ''),
    (Reg: $0B; Name: 'SCANDBLCTRL';  Bits: 'CPU1 CPU0 - - - - - -'),
    (Reg: $0C; Name: 'RASTERLINE';   Bits: ''),
    (Reg: $0D; Name: 'RASTERCTRL';   Bits: 'INT - - - - DISVINT ENABLE LINE8'),
    (Reg: $0E; Name: 'DEVCONTROL';   Bits: 'DISD - DIROM1F DIROM7F DI1FFD DI7FFD DITAY DIAY'),
    (Reg: $0F; Name: 'DEVCTRL2';     Bits: '- - - - - DIRADAS DITIMEX DIULAPLUS'),
    (Reg: $40; Name: 'RADASCTRL';    Bits: ''),
    (Reg: $41; Name: 'RADASOFFSET';  Bits: ''),
    (Reg: $42; Name: 'RADASPADDING'; Bits: ''),
    (Reg: $43; Name: 'RADASPALBANK'; Bits: ''),
    (Reg: $A0; Name: 'DMACTRL';      Bits: ''),
    (Reg: $A1; Name: 'DMASRC';       Bits: ''),
    (Reg: $A2; Name: 'DMADST';       Bits: ''),
    (Reg: $A3; Name: 'DMAPRE';       Bits: ''),
    (Reg: $A4; Name: 'DMALEN';       Bits: ''),
    (Reg: $A5; Name: 'DMAPROB';      Bits: ''),
    (Reg: $A6; Name: 'DMASTAT';      Bits: ''),
    (Reg: $C6; Name: 'UARTDATA';     Bits: ''),
    (Reg: $C7; Name: 'UARTSTAT';     Bits: ''),
    (Reg: $FC; Name: 'COREADDR';     Bits: ''),
    (Reg: $FD; Name: 'COREBOOT';     Bits: ''),
    (Reg: $FE; Name: 'SCRATCH';      Bits: ''),
    (Reg: $FF; Name: 'COREID';       Bits: ''));

  NEXT_REGS: array[0..56] of TRegInfo = (
    (Reg: $00; Name: 'Machine ID';         Bits: ''),
    (Reg: $01; Name: 'Core version';       Bits: ''),
    (Reg: $02; Name: 'Reset';              Bits: 'EXPBUS - - IOTRAP MFNMI DIVNMI HARD SOFT'),
    (Reg: $03; Name: 'Machine type';       Bits: ''),
    (Reg: $05; Name: 'Peripheral 1';       Bits: 'J1 J1 J2 J2 J1H 60HZ J2H SCANDBL'),
    (Reg: $06; Name: 'Peripheral 2';       Bits: 'F8 BEEPINT F3 DIVNMI MFNMI PS2 AY1 AY0'),
    (Reg: $07; Name: 'CPU speed';          Bits: ''),
    (Reg: $08; Name: 'Peripheral 3';       Bits: 'UNLOCK7FFD NOCONT ACB SPEAKER DACS TIMEXRD TURBOSND ISSUE2'),
    (Reg: $09; Name: 'Peripheral 4';       Bits: 'AY2MONO AY1MONO AY0MONO SPRLOCK - HDMIMUTE SCAN1 SCAN0'),
    (Reg: $0A; Name: 'Peripheral 5';       Bits: 'MF1 MF0 - DIVAUTO MOUSEREV - DPI1 DPI0'),
    (Reg: $0B; Name: 'Joystick I/O mode';  Bits: ''),
    (Reg: $0E; Name: 'Core sub version';   Bits: ''),
    (Reg: $0F; Name: 'Board ID';           Bits: ''),
    (Reg: $12; Name: 'Layer 2 bank';       Bits: ''),
    (Reg: $13; Name: 'Layer 2 shadow bank'; Bits: ''),
    (Reg: $14; Name: 'Transparency';       Bits: ''),
    (Reg: $15; Name: 'Sprites and layers'; Bits: 'LORES SPR0 CLIP L2 L1 L0 OVER SPRITES'),
    (Reg: $1E; Name: 'Active line MSB';    Bits: ''),
    (Reg: $1F; Name: 'Active line LSB';    Bits: ''),
    (Reg: $22; Name: 'Line int control';   Bits: 'ULAINT - - - - DISULA LINEINT MSB'),
    (Reg: $23; Name: 'Line int value';     Bits: ''),
    (Reg: $40; Name: 'Palette index';      Bits: ''),
    (Reg: $42; Name: 'ULANext format';     Bits: ''),
    (Reg: $43; Name: 'Palette control';    Bits: 'NOAUTO P2 P1 P0 SPR2 L2_2 ULA2 ULANEXT'),
    (Reg: $4A; Name: 'Fallback colour';    Bits: ''),
    (Reg: $50; Name: 'MMU0 (0000)';        Bits: ''),
    (Reg: $51; Name: 'MMU1 (2000)';        Bits: ''),
    (Reg: $52; Name: 'MMU2 (4000)';        Bits: ''),
    (Reg: $53; Name: 'MMU3 (6000)';        Bits: ''),
    (Reg: $54; Name: 'MMU4 (8000)';        Bits: ''),
    (Reg: $55; Name: 'MMU5 (A000)';        Bits: ''),
    (Reg: $56; Name: 'MMU6 (C000)';        Bits: ''),
    (Reg: $57; Name: 'MMU7 (E000)';        Bits: ''),
    (Reg: $62; Name: 'Copper control';     Bits: 'MODE1 MODE0 - - - A10 A9 A8'),
    (Reg: $64; Name: 'Line count offset';  Bits: ''),
    (Reg: $68; Name: 'ULA control';        Bits: 'NOULA BLEND1 BLEND0 KEYS ULAPLUS HALFSCR - STENCIL'),
    (Reg: $69; Name: 'Display control 1';  Bits: 'L2 SHADOW T5 T4 T3 T2 T1 T0'),
    (Reg: $6B; Name: 'Tilemap control';    Bits: ''),
    (Reg: $70; Name: 'Layer 2 control';    Bits: ''),
    (Reg: $7F; Name: 'User register 0';    Bits: ''),
    (Reg: $82; Name: 'Port decode 0';      Bits: ''),
    (Reg: $83; Name: 'Port decode 1';      Bits: ''),
    (Reg: $84; Name: 'Port decode 2';      Bits: ''),
    (Reg: $85; Name: 'Port decode 3';      Bits: ''),
    (Reg: $8C; Name: 'Alternate ROM';      Bits: 'ALT WRITE LOCK1 LOCK0 NEXT:ALT NEXT:WRITE NEXT:LOCK1 NEXT:LOCK0'),
    (Reg: $8E; Name: '128K mapping';       Bits: ''),
    (Reg: $8F; Name: 'Mapping mode';       Bits: ''),
    (Reg: $B0; Name: 'Extended keys 0';    Bits: '; " , . UP DOWN LEFT RIGHT'),
    (Reg: $B1; Name: 'Extended keys 1';    Bits: 'DELETE EDIT BREAK INVVIDEO TRUEVIDEO GRAPH CAPSLOCK EXTEND'),
    (Reg: $B8; Name: 'DivMMC entry points 0'; Bits: '0038 0030 0028 0020 0018 0010 0008 0000'),
    (Reg: $B9; Name: 'DivMMC entries always'; Bits: '0038 0030 0028 0020 0018 0010 0008 0000'),
    (Reg: $BA; Name: 'DivMMC entries instant'; Bits: '0038 0030 0028 0020 0018 0010 0008 0000'),
    (Reg: $BB; Name: 'DivMMC entry points 1'; Bits: '3DXX 1FF8 056A 04D7 0562 04C6 0066I 0066D'),
    (Reg: $C0; Name: 'Interrupt control';  Bits: ''),
    (Reg: $C4; Name: 'INT enable 0';       Bits: 'EXPBUS - - - - - LINE ULA'),
    (Reg: $C8; Name: 'INT status 0';       Bits: '- - - - - - LINE ULA'),
    (Reg: $D8; Name: 'I/O traps';          Bits: ''));

const
  CLUT_BITS = '- GRN1 RED1 BLU1 BRIGHT GRN0 RED0 BLU0';

  SAM_REGS: array[0..42] of TSamRegInfo = (
    (Code: $FA; Port: 'FA'; Name: 'LMPR (low memory)'; Bits: 'WPRAM ROM1 RAM0 PG4 PG3 PG2 PG1 PG0'; ReadOnly: False),
    (Code: $FB; Port: 'FB'; Name: 'HMPR (high memory)'; Bits: 'EXTMEM MD3S1 MD3S0 PG4 PG3 PG2 PG1 PG0'; ReadOnly: False),
    (Code: $FC; Port: 'FC'; Name: 'VMPR (video page, mode)'; Bits: 'MIDI MODE1 MODE0 PG4 PG3 PG2 PG1 PG0'; ReadOnly: False),
    (Code: $FE; Port: 'FE'; Name: 'BORDER, beeper'; Bits: 'SOFF MIDI BRD3 BEEP MIC BRD2 BRD1 BRD0'; ReadOnly: False),
    (Code: $F9; Port: 'F9'; Name: 'LINE interrupt'; Bits: ''; ReadOnly: False),
    (Code: $1F9; Port: 'F9 (in)'; Name: 'STATUS (0 = asks)'; Bits: 'K8 K7 K6 MIDOUT FRAME MIDIIN MOUSE LINE'; ReadOnly: True),
    (Code: $100; Port: 'F8'; Name: 'CLUT 0'; Bits: CLUT_BITS; ReadOnly: False),
    (Code: $101; Port: '1F8'; Name: 'CLUT 1'; Bits: CLUT_BITS; ReadOnly: False),
    (Code: $102; Port: '2F8'; Name: 'CLUT 2'; Bits: CLUT_BITS; ReadOnly: False),
    (Code: $103; Port: '3F8'; Name: 'CLUT 3'; Bits: CLUT_BITS; ReadOnly: False),
    (Code: $104; Port: '4F8'; Name: 'CLUT 4'; Bits: CLUT_BITS; ReadOnly: False),
    (Code: $105; Port: '5F8'; Name: 'CLUT 5'; Bits: CLUT_BITS; ReadOnly: False),
    (Code: $106; Port: '6F8'; Name: 'CLUT 6'; Bits: CLUT_BITS; ReadOnly: False),
    (Code: $107; Port: '7F8'; Name: 'CLUT 7'; Bits: CLUT_BITS; ReadOnly: False),
    (Code: $108; Port: '8F8'; Name: 'CLUT 8'; Bits: CLUT_BITS; ReadOnly: False),
    (Code: $109; Port: '9F8'; Name: 'CLUT 9'; Bits: CLUT_BITS; ReadOnly: False),
    (Code: $10A; Port: 'AF8'; Name: 'CLUT 10'; Bits: CLUT_BITS; ReadOnly: False),
    (Code: $10B; Port: 'BF8'; Name: 'CLUT 11'; Bits: CLUT_BITS; ReadOnly: False),
    (Code: $10C; Port: 'CF8'; Name: 'CLUT 12'; Bits: CLUT_BITS; ReadOnly: False),
    (Code: $10D; Port: 'DF8'; Name: 'CLUT 13'; Bits: CLUT_BITS; ReadOnly: False),
    (Code: $10E; Port: 'EF8'; Name: 'CLUT 14'; Bits: CLUT_BITS; ReadOnly: False),
    (Code: $10F; Port: 'FF8'; Name: 'CLUT 15'; Bits: CLUT_BITS; ReadOnly: False),
    (Code: $200; Port: 'SAA 00'; Name: 'Amplitude, channel 0'; Bits: ''; ReadOnly: False),
    (Code: $201; Port: 'SAA 01'; Name: 'Amplitude, channel 1'; Bits: ''; ReadOnly: False),
    (Code: $202; Port: 'SAA 02'; Name: 'Amplitude, channel 2'; Bits: ''; ReadOnly: False),
    (Code: $203; Port: 'SAA 03'; Name: 'Amplitude, channel 3'; Bits: ''; ReadOnly: False),
    (Code: $204; Port: 'SAA 04'; Name: 'Amplitude, channel 4'; Bits: ''; ReadOnly: False),
    (Code: $205; Port: 'SAA 05'; Name: 'Amplitude, channel 5'; Bits: ''; ReadOnly: False),
    (Code: $208; Port: 'SAA 08'; Name: 'Frequency, channel 0'; Bits: ''; ReadOnly: False),
    (Code: $209; Port: 'SAA 09'; Name: 'Frequency, channel 1'; Bits: ''; ReadOnly: False),
    (Code: $20A; Port: 'SAA 0A'; Name: 'Frequency, channel 2'; Bits: ''; ReadOnly: False),
    (Code: $20B; Port: 'SAA 0B'; Name: 'Frequency, channel 3'; Bits: ''; ReadOnly: False),
    (Code: $20C; Port: 'SAA 0C'; Name: 'Frequency, channel 4'; Bits: ''; ReadOnly: False),
    (Code: $20D; Port: 'SAA 0D'; Name: 'Frequency, channel 5'; Bits: ''; ReadOnly: False),
    (Code: $210; Port: 'SAA 10'; Name: 'Octaves, channels 0 and 1'; Bits: '- OCT1_2 OCT1_1 OCT1_0 - OCT0_2 OCT0_1 OCT0_0'; ReadOnly: False),
    (Code: $211; Port: 'SAA 11'; Name: 'Octaves, channels 2 and 3'; Bits: '- OCT3_2 OCT3_1 OCT3_0 - OCT2_2 OCT2_1 OCT2_0'; ReadOnly: False),
    (Code: $212; Port: 'SAA 12'; Name: 'Octaves, channels 4 and 5'; Bits: '- OCT5_2 OCT5_1 OCT5_0 - OCT4_2 OCT4_1 OCT4_0'; ReadOnly: False),
    (Code: $214; Port: 'SAA 14'; Name: 'Tone enable'; Bits: '- - TONE5 TONE4 TONE3 TONE2 TONE1 TONE0'; ReadOnly: False),
    (Code: $215; Port: 'SAA 15'; Name: 'Noise enable'; Bits: '- - NOISE5 NOISE4 NOISE3 NOISE2 NOISE1 NOISE0'; ReadOnly: False),
    (Code: $216; Port: 'SAA 16'; Name: 'Noise generators'; Bits: '- - N1_1 N1_0 - - N0_1 N0_0'; ReadOnly: False),
    (Code: $218; Port: 'SAA 18'; Name: 'Envelope generator 0'; Bits: 'ENABLE - CLOCK RES SHAPE2 SHAPE1 SHAPE0 STEREO'; ReadOnly: False),
    (Code: $219; Port: 'SAA 19'; Name: 'Envelope generator 1'; Bits: 'ENABLE - CLOCK RES SHAPE2 SHAPE1 SHAPE0 STEREO'; ReadOnly: False),
    (Code: $21C; Port: 'SAA 1C'; Name: 'Sound enable, reset'; Bits: '- - - - - - RESET ENABLE'; ReadOnly: False));

  MSX_REGS: array[0..88] of TSamRegInfo = (
    (Code: $0000; Port: 'A8'; Name: 'Primary slot register'; Bits: 'P3 P3 P2 P2 P1 P1 P0 P0'; ReadOnly: False),
    (Code: $0001; Port: 'FFFF'; Name: 'Subslot register (slot 3)'; Bits: 'P3 P3 P2 P2 P1 P1 P0 P0'; ReadOnly: False),
    (Code: $0002; Port: 'AA'; Name: 'PPI port C'; Bits: 'CLICK CAPS CASOUT MOTOR- ROW3 ROW2 ROW1 ROW0'; ReadOnly: False),
    (Code: $0010; Port: 'FC+0'; Name: 'Mapper segment, page 0 (0000)'; Bits: ''; ReadOnly: False),
    (Code: $0011; Port: 'FC+1'; Name: 'Mapper segment, page 1 (4000)'; Bits: ''; ReadOnly: False),
    (Code: $0012; Port: 'FC+2'; Name: 'Mapper segment, page 2 (8000)'; Bits: ''; ReadOnly: False),
    (Code: $0013; Port: 'FC+3'; Name: 'Mapper segment, page 3 (C000)'; Bits: ''; ReadOnly: False),
    (Code: $0110; Port: 'A0'; Name: 'PSG register selected'; Bits: ''; ReadOnly: False),
    (Code: $0100; Port: 'PSG 0'; Name: 'A tone low'; Bits: ''; ReadOnly: False),
    (Code: $0101; Port: 'PSG 1'; Name: 'A tone high'; Bits: ''; ReadOnly: False),
    (Code: $0102; Port: 'PSG 2'; Name: 'B tone low'; Bits: ''; ReadOnly: False),
    (Code: $0103; Port: 'PSG 3'; Name: 'B tone high'; Bits: ''; ReadOnly: False),
    (Code: $0104; Port: 'PSG 4'; Name: 'C tone low'; Bits: ''; ReadOnly: False),
    (Code: $0105; Port: 'PSG 5'; Name: 'C tone high'; Bits: ''; ReadOnly: False),
    (Code: $0106; Port: 'PSG 6'; Name: 'Noise period'; Bits: ''; ReadOnly: False),
    (Code: $0107; Port: 'PSG 7'; Name: 'Mixer'; Bits: 'IOB IOA NC NB NA TC TB TA'; ReadOnly: False),
    (Code: $0108; Port: 'PSG 8'; Name: 'A volume'; Bits: ''; ReadOnly: False),
    (Code: $0109; Port: 'PSG 9'; Name: 'B volume'; Bits: ''; ReadOnly: False),
    (Code: $010A; Port: 'PSG 10'; Name: 'C volume'; Bits: ''; ReadOnly: False),
    (Code: $010B; Port: 'PSG 11'; Name: 'Envelope low'; Bits: ''; ReadOnly: False),
    (Code: $010C; Port: 'PSG 12'; Name: 'Envelope high'; Bits: ''; ReadOnly: False),
    (Code: $010D; Port: 'PSG 13'; Name: 'Envelope shape'; Bits: ''; ReadOnly: False),
    (Code: $010E; Port: 'PSG 14'; Name: 'I/O port A (joystick)'; Bits: ''; ReadOnly: False),
    (Code: $010F; Port: 'PSG 15'; Name: 'I/O port B'; Bits: ''; ReadOnly: False),
    (Code: $0200; Port: 'VDP R#0'; Name: 'Mode 0'; Bits: '- DG IE2 IE1 M5 M4 M3 -'; ReadOnly: False),
    (Code: $0201; Port: 'VDP R#1'; Name: 'Mode 1'; Bits: '- BL IE0 M1 M2 - SI MAG'; ReadOnly: False),
    (Code: $0202; Port: 'VDP R#2'; Name: 'Name table base'; Bits: ''; ReadOnly: False),
    (Code: $0203; Port: 'VDP R#3'; Name: 'Colour table base, low'; Bits: ''; ReadOnly: False),
    (Code: $0204; Port: 'VDP R#4'; Name: 'Pattern generator base'; Bits: ''; ReadOnly: False),
    (Code: $0205; Port: 'VDP R#5'; Name: 'Sprite attributes, low'; Bits: ''; ReadOnly: False),
    (Code: $0206; Port: 'VDP R#6'; Name: 'Sprite patterns base'; Bits: ''; ReadOnly: False),
    (Code: $0207; Port: 'VDP R#7'; Name: 'Text and border colour'; Bits: ''; ReadOnly: False),
    (Code: $0208; Port: 'VDP R#8'; Name: 'Mode 2'; Bits: 'MS LP TP CB VR - SPD BW'; ReadOnly: False),
    (Code: $0209; Port: 'VDP R#9'; Name: 'Mode 3'; Bits: 'LN - S1 S0 IL EO NT DC'; ReadOnly: False),
    (Code: $020A; Port: 'VDP R#10'; Name: 'Colour table base, high'; Bits: ''; ReadOnly: False),
    (Code: $020B; Port: 'VDP R#11'; Name: 'Sprite attributes, high'; Bits: ''; ReadOnly: False),
    (Code: $020C; Port: 'VDP R#12'; Name: 'Blink colour'; Bits: ''; ReadOnly: False),
    (Code: $020D; Port: 'VDP R#13'; Name: 'Blink times'; Bits: ''; ReadOnly: False),
    (Code: $020E; Port: 'VDP R#14'; Name: 'VRAM address, A16-A14'; Bits: ''; ReadOnly: False),
    (Code: $020F; Port: 'VDP R#15'; Name: 'Status register selected'; Bits: ''; ReadOnly: False),
    (Code: $0210; Port: 'VDP R#16'; Name: 'Palette pointer'; Bits: ''; ReadOnly: False),
    (Code: $0211; Port: 'VDP R#17'; Name: 'Indirect register pointer'; Bits: 'AII - R5 R4 R3 R2 R1 R0'; ReadOnly: False),
    (Code: $0212; Port: 'VDP R#18'; Name: 'Display adjust'; Bits: ''; ReadOnly: False),
    (Code: $0213; Port: 'VDP R#19'; Name: 'Line interrupt'; Bits: ''; ReadOnly: False),
    (Code: $0214; Port: 'VDP R#20'; Name: 'Colour burst 1'; Bits: ''; ReadOnly: False),
    (Code: $0215; Port: 'VDP R#21'; Name: 'Colour burst 2'; Bits: ''; ReadOnly: False),
    (Code: $0216; Port: 'VDP R#22'; Name: 'Colour burst 3'; Bits: ''; ReadOnly: False),
    (Code: $0217; Port: 'VDP R#23'; Name: 'Vertical scroll'; Bits: ''; ReadOnly: False),
    (Code: $0220; Port: 'VDP R#32'; Name: 'Command SX, low'; Bits: ''; ReadOnly: False),
    (Code: $0221; Port: 'VDP R#33'; Name: 'Command SX, high'; Bits: ''; ReadOnly: False),
    (Code: $0222; Port: 'VDP R#34'; Name: 'Command SY, low'; Bits: ''; ReadOnly: False),
    (Code: $0223; Port: 'VDP R#35'; Name: 'Command SY, high'; Bits: ''; ReadOnly: False),
    (Code: $0224; Port: 'VDP R#36'; Name: 'Command DX, low'; Bits: ''; ReadOnly: False),
    (Code: $0225; Port: 'VDP R#37'; Name: 'Command DX, high'; Bits: ''; ReadOnly: False),
    (Code: $0226; Port: 'VDP R#38'; Name: 'Command DY, low'; Bits: ''; ReadOnly: False),
    (Code: $0227; Port: 'VDP R#39'; Name: 'Command DY, high'; Bits: ''; ReadOnly: False),
    (Code: $0228; Port: 'VDP R#40'; Name: 'Command NX, low'; Bits: ''; ReadOnly: False),
    (Code: $0229; Port: 'VDP R#41'; Name: 'Command NX, high'; Bits: ''; ReadOnly: False),
    (Code: $022A; Port: 'VDP R#42'; Name: 'Command NY, low'; Bits: ''; ReadOnly: False),
    (Code: $022B; Port: 'VDP R#43'; Name: 'Command NY, high'; Bits: ''; ReadOnly: False),
    (Code: $022C; Port: 'VDP R#44'; Name: 'Command colour'; Bits: ''; ReadOnly: False),
    (Code: $022D; Port: 'VDP R#45'; Name: 'Command argument'; Bits: '- MXC MXS MXD DIY DIX EQ MAJ'; ReadOnly: False),
    (Code: $022E; Port: 'VDP R#46'; Name: 'Command code'; Bits: 'CM3 CM2 CM1 CM0 LO3 LO2 LO1 LO0'; ReadOnly: False),
    (Code: $0240; Port: 'VDP S#0'; Name: 'Status 0'; Bits: 'F 5S C S4 S3 S2 S1 S0'; ReadOnly: True),
    (Code: $0241; Port: 'VDP S#1'; Name: 'Status 1'; Bits: '- - - - - - - FH'; ReadOnly: True),
    (Code: $0242; Port: 'VDP S#2'; Name: 'Status 2'; Bits: 'TR VR HR BD - - EO CE'; ReadOnly: True),
    (Code: $0243; Port: 'VDP S#3'; Name: 'Collision X, low'; Bits: ''; ReadOnly: True),
    (Code: $0244; Port: 'VDP S#4'; Name: 'Collision X, high'; Bits: ''; ReadOnly: True),
    (Code: $0245; Port: 'VDP S#5'; Name: 'Collision Y, low'; Bits: ''; ReadOnly: True),
    (Code: $0246; Port: 'VDP S#6'; Name: 'Collision Y, high'; Bits: ''; ReadOnly: True),
    (Code: $0247; Port: 'VDP S#7'; Name: 'Status 7: colour read'; Bits: ''; ReadOnly: True),
    (Code: $0248; Port: 'VDP S#8'; Name: 'Border X, low'; Bits: ''; ReadOnly: True),
    (Code: $0249; Port: 'VDP S#9'; Name: 'Border X, high'; Bits: ''; ReadOnly: True),
    (Code: $0260; Port: 'Colour 0'; Name: 'Palette entry 0 (R G B, 0 to 7)'; Bits: ''; ReadOnly: False),
    (Code: $0261; Port: 'Colour 1'; Name: 'Palette entry 1 (R G B, 0 to 7)'; Bits: ''; ReadOnly: False),
    (Code: $0262; Port: 'Colour 2'; Name: 'Palette entry 2 (R G B, 0 to 7)'; Bits: ''; ReadOnly: False),
    (Code: $0263; Port: 'Colour 3'; Name: 'Palette entry 3 (R G B, 0 to 7)'; Bits: ''; ReadOnly: False),
    (Code: $0264; Port: 'Colour 4'; Name: 'Palette entry 4 (R G B, 0 to 7)'; Bits: ''; ReadOnly: False),
    (Code: $0265; Port: 'Colour 5'; Name: 'Palette entry 5 (R G B, 0 to 7)'; Bits: ''; ReadOnly: False),
    (Code: $0266; Port: 'Colour 6'; Name: 'Palette entry 6 (R G B, 0 to 7)'; Bits: ''; ReadOnly: False),
    (Code: $0267; Port: 'Colour 7'; Name: 'Palette entry 7 (R G B, 0 to 7)'; Bits: ''; ReadOnly: False),
    (Code: $0268; Port: 'Colour 8'; Name: 'Palette entry 8 (R G B, 0 to 7)'; Bits: ''; ReadOnly: False),
    (Code: $0269; Port: 'Colour 9'; Name: 'Palette entry 9 (R G B, 0 to 7)'; Bits: ''; ReadOnly: False),
    (Code: $026A; Port: 'Colour 10'; Name: 'Palette entry 10 (R G B, 0 to 7)'; Bits: ''; ReadOnly: False),
    (Code: $026B; Port: 'Colour 11'; Name: 'Palette entry 11 (R G B, 0 to 7)'; Bits: ''; ReadOnly: False),
    (Code: $026C; Port: 'Colour 12'; Name: 'Palette entry 12 (R G B, 0 to 7)'; Bits: ''; ReadOnly: False),
    (Code: $026D; Port: 'Colour 13'; Name: 'Palette entry 13 (R G B, 0 to 7)'; Bits: ''; ReadOnly: False),
    (Code: $026E; Port: 'Colour 14'; Name: 'Palette entry 14 (R G B, 0 to 7)'; Bits: ''; ReadOnly: False),
    (Code: $026F; Port: 'Colour 15'; Name: 'Palette entry 15 (R G B, 0 to 7)'; Bits: ''; ReadOnly: False));

{ The names of the bits set in Value, highest first }
function BitsSet(const Bits: string; Value: Byte): string;
var
  Names: TStringArray;
  I: Integer;
begin
  Result := '';
  if Bits = '' then Exit;
  Names := Bits.Split(' ');
  for I := 0 to Min(7, High(Names)) do
    if (Names[I] <> '-') and ((Value and ($80 shr I)) <> 0) then
    begin
      if Result <> '' then Result := Result + ' ';
      Result := Result + Names[I];
    end;
end;

constructor TZXUnoRegsWindow.CreateFor(AOwner: TComponent; AEmu: TEmulator);
var
  I: Integer;
begin
  inherited CreateNew(AOwner, 0);
  FEmu := AEmu;
  Width := 560;
  Height := 520;
  Position := poMainFormCenter;
  OnClose := @FormClose;
  KeyPreview := True;
  OnKeyDown := @FormKeyDown;

  FNote := TLabel.Create(Self);
  FNote.Parent := Self;
  FNote.Align := alBottom;
  FNote.BorderSpacing.Around := 6;
  FNote.WordWrap := True;

  FGrid := TStringGrid.Create(Self);
  FGrid.Parent := Self;
  FGrid.Align := alClient;
  FGrid.ColCount := 4;
  FGrid.FixedCols := 0;
  FGrid.FixedRows := 1;
  FGrid.Options := FGrid.Options + [goEditing, goColSizing] - [goRangeSelect];
  FGrid.Cells[0, 0] := 'Reg';
  FGrid.Cells[1, 0] := 'Name';
  FGrid.Cells[2, 0] := 'Value';
  FGrid.Cells[3, 0] := 'Bits set';
  FGrid.ColWidths[0] := 50;
  FGrid.ColWidths[1] := 130;
  FGrid.ColWidths[2] := 60;
  FGrid.ColWidths[3] := 290;
  FGrid.AutoAdvance := aaNone;
  FGrid.OnSelectEditor := @GridSelectEditor;
  FGrid.OnEditingDone := @GridEditingDone;

  FTimer := TTimer.Create(Self);
  FTimer.Interval := 200;
  FTimer.OnTimer := @Tick;
  Fill;
  UpdateValues;
end;

{ What the paging registers put in the four sections of the address space }
function TZXUnoRegsWindow.SamMapping(Port: Integer): string;

  function Section(S: Integer; const Name: string): string;
  var
    B: Integer;
  begin
    B := FEmu.Spec.SlotBank(S);
    if B = NO_MEMORY then Result := Name + ':none'
    else if B < 0 then Result := Name + ':ROM' + IntToStr(-1 - B)
    else Result := Name + ':RAM' + IntToStr(B);
  end;

begin
  case Port of
    $FA: Result := Section(0, 'A') + ' ' + Section(1, 'B');
    $FB: Result := Section(2, 'C') + ' ' + Section(3, 'D');
    $FC: Result := 'mode ' + IntToStr(((FEmu.Spec.SamRegister($FC) shr 5) and 3) + 1);
  else
    Result := '';
  end;
end;

{ Which slot each page of the CPU shows (the slot register) }
function TZXUnoRegsWindow.MsxMapping(Code: Integer): string;
var
  P, S, Sub: Integer;
begin
  Result := '';
  if (Code <> 0) and (Code <> 1) then Exit;
  for P := 0 to 3 do
  begin
    S := FEmu.Spec.MSXHw.Slots.PageSlot(P);
    Sub := FEmu.Spec.MSXHw.Slots.PageSub(P);
    if Sub >= 0 then Result := Result + Format('p%d:%d-%d ', [P, S, Sub])
    else Result := Result + Format('p%d:%d ', [P, S]);
  end;
end;

{ The rows for the machine shown: the ZX-Uno's registers, the Next's or the SAM Coupe's }
procedure TZXUnoRegsWindow.AddRow(Code: Integer; const APort, AName, ABits: string; AReadOnly: Boolean);
var
  N: Integer;
begin
  if not FEmu.Spec.ChipRegisterExists(Code) then Exit;
  N := Length(FRows);
  SetLength(FRows, N + 1);
  FRows[N].Code := Code;
  FRows[N].Port := APort;
  FRows[N].Name := AName;
  FRows[N].Bits := ABits;
  FRows[N].ReadOnly := AReadOnly;
end;

{ The rows of a ZX Spectrum (16K to +3) or an Amstrad CPC: those the machine has }
procedure TZXUnoRegsWindow.FillChips;
const
  PSG_NAMES: array[0..15] of string = ('A tone low', 'A tone high', 'B tone low', 'B tone high', 'C tone low',
    'C tone high', 'Noise period', 'Mixer', 'A volume', 'B volume', 'C volume', 'Envelope low', 'Envelope high',
    'Envelope shape', 'I/O port A', 'I/O port B');
  CRTC_NAMES: array[0..17] of string = ('Horizontal total', 'Horizontal displayed', 'HSYNC position',
    'Sync widths', 'Vertical total', 'Vertical total adjust', 'Vertical displayed', 'VSYNC position',
    'Interlace and skew', 'Maximum raster address', 'Cursor start', 'Cursor end', 'Start address, high',
    'Start address, low', 'Cursor, high', 'Cursor, low', 'Light pen, high', 'Light pen, low');
  MIXER_BITS = 'IOB IOA NC NB NA TC TB TA';
var
  I: Integer;
  Bits: string;
begin
  FRows := nil;
  if FEmu.Spec.Info.Memory = mkCPC then
  begin
    Caption := 'Amstrad CPC Chips';
    FNote.Caption := 'To change a value select it, type the new one (hex) and press Enter: it is written as an OUT ' +
      'to the port would (a pen as selecting it and giving it the colour, a CRTC register as selecting it at BCxx ' +
      'and writing it at BDxx: what was selected is selected again). A pen''s colour is the hardware one (0 to 1F). ' +
      'The PPI''s port B is an input.';
    AddRow($000, 'GA 7Fxx', 'Gate Array: pen selected (10: the border)', '');
    for I := 0 to 15 do AddRow($010 + I, 'Pen ' + IntToStr(I), Format('Pen %d colour', [I]), '');
    AddRow($020, 'Border', 'Border colour', '');
    AddRow($001, 'GA RMR', 'Gate Array: mode and ROMs', '- - - INTRESET UPPEROFF LOWEROFF MODE1 MODE0');
    AddRow($002, 'GA MMR', 'Gate Array: RAM configuration (6128)', '');
    AddRow($003, 'DFxx', 'Upper ROM selected', '');
    AddRow($030, 'BCxx', 'CRTC register selected', '');
    for I := 0 to 17 do AddRow($040 + I, 'CRTC ' + IntToStr(I), CRTC_NAMES[I], '');
    AddRow($060, 'F4xx', 'PPI port A (the PSG''s data)', '');
    AddRow($061, 'F5xx', 'PPI port B', 'CASIN PRN EXP LK4 LK3 LK2 LK1 VSYNC', True);
    AddRow($062, 'F6xx', 'PPI port C', 'BDIR BC1 CASOUT MOTOR KEY3 KEY2 KEY1 KEY0');
    AddRow($063, 'F7xx', 'PPI control', '');
    AddRow($070, 'PSG', 'PSG register selected', '');
    for I := 0 to 15 do
    begin
      if I = 7 then Bits := MIXER_BITS else Bits := '';
      if I = 14 then AddRow($080 + I, 'PSG 14', 'I/O port A (the keyboard)', '')
      else AddRow($080 + I, 'PSG ' + IntToStr(I), PSG_NAMES[I], Bits);
    end;
  end
  else
  begin
    Caption := 'ZX Spectrum Ports';
    FNote.Caption := 'To change a value select it, type the new one (hex) and press Enter: it is written as an OUT ' +
      'to the port would (7FFD keeps its lock; an AY register as selecting it at FFFD and writing it at BFFD: the ' +
      'register selected is selected again). FE shows the last value written to it.';
    AddRow($000, 'FE', 'ULA: border, MIC and EAR', '- - - EAR MIC BORDER2 BORDER1 BORDER0');
    AddRow($001, '7FFD', '128K paging', '- - LOCK ROM SCREEN RAM2 RAM1 RAM0');
    AddRow($002, '1FFD', '+2A/+3 paging, disk motor, printer', '- - - STROBE MOTOR ROMHI CONFIG SPECIAL');
    AddRow($003, 'FF', 'Timex screen mode', 'EXROM NOINT HRC2 HRC1 HRC0 MODE2 MODE1 MODE0');
    AddRow($004, 'BF3B', 'ULAplus register', '');
    AddRow($005, 'FF3B', 'ULAplus data', '');
    AddRow($100, 'FFFD', 'AY register selected', '');
    for I := 0 to 15 do
    begin
      if I = 7 then Bits := MIXER_BITS else Bits := '';
      AddRow($110 + I, 'AY ' + IntToStr(I), PSG_NAMES[I], Bits);
    end;
    AddRow($200, 'FFFD (2)', 'Second AY: register selected', '');
    for I := 0 to 15 do
    begin
      if I = 7 then Bits := MIXER_BITS else Bits := '';
      AddRow($210 + I, 'AY2 ' + IntToStr(I), 'Second AY: ' + PSG_NAMES[I], Bits);
    end;
  end;
  FGrid.RowCount := Length(FRows) + 1;
  for I := 0 to High(FRows) do
  begin
    FGrid.Cells[0, I + 1] := FRows[I].Port;
    FGrid.Cells[1, I + 1] := FRows[I].Name;
  end;
end;

{ The rows for the machine shown: the ZX-Uno's registers, the Next's, the SAM Coupe's, the MSX's, or a Spectrum's or a
  CPC's }
procedure TZXUnoRegsWindow.Fill;
var
  I: Integer;
begin
  FModel := FEmu.Spec.Model;
  FNext := FEmu.Spec.Model = smZXNext;
  FSam := FEmu.Spec.Model = smSAM;
  FMsx := IsMSXModel(FEmu.Spec.Model);
  FChips := not (FNext or FSam or FMsx or (FEmu.Spec.Model = smZXUno) or IsC64Model(FEmu.Spec.Model));
  if FChips then FillChips
  else if FMsx then
  begin
    Caption := 'MSX Ports';
    FNote.Caption := 'To change a value select it, type the new one (hex) and press Enter: the slot, mapper, PSG ' +
      'and VDP registers are written as an OUT to the port would (a palette entry is three digits, R G B). ' +
      'The VDP status registers can''t be changed.';
    FGrid.RowCount := Length(MSX_REGS) + 1;
    for I := 0 to High(MSX_REGS) do
    begin
      FGrid.Cells[0, I + 1] := MSX_REGS[I].Port;
      FGrid.Cells[1, I + 1] := MSX_REGS[I].Name;
    end;
  end
  else if FSam then
  begin
    Caption := 'SAM Coup'#$C3#$A9' Ports';
    FNote.Caption := 'To change a value select it, type the new one (hex) and press Enter: ' +
      'it is written as an OUT to the port would (LMPR and HMPR are the memory paging: the section ' +
      'A and B pages, and C and D, with the ROM bits). SAA rows are the sound chip''s registers.';
    FGrid.RowCount := Length(SAM_REGS) + 1;
    for I := 0 to High(SAM_REGS) do
    begin
      FGrid.Cells[0, I + 1] := SAM_REGS[I].Port;
      FGrid.Cells[1, I + 1] := SAM_REGS[I].Name;
    end;
  end
  else if FNext then
  begin
    Caption := 'ZX Spectrum Next Registers';
    FNote.Caption := 'To change a value select it, type the new one (hex) and press Enter: ' +
      'it is written as NEXTREG does (an OUT to 253B with the register selected at 243B).';
    FGrid.RowCount := Length(NEXT_REGS) + 1;
    for I := 0 to High(NEXT_REGS) do
    begin
      FGrid.Cells[0, I + 1] := IntToHex(NEXT_REGS[I].Reg, 2);
      FGrid.Cells[1, I + 1] := NEXT_REGS[I].Name;
    end;
  end
  else
  begin
    Caption := 'ZX-Uno Registers';
    FNote.Caption := 'To change a value select it, type the new one (hex) and press Enter: ' +
      'it is written like an OUT to FD3B with the register selected at FC3B.';
    FGrid.RowCount := Length(REGS) + 1;
    for I := 0 to High(REGS) do
    begin
      FGrid.Cells[0, I + 1] := IntToHex(REGS[I].Reg, 2);
      FGrid.Cells[1, I + 1] := REGS[I].Name;
    end;
  end;
end;

procedure TZXUnoRegsWindow.UpdateValues;
var
  I: Integer;
  V: Byte;
begin
  if FGrid.EditorMode then Exit;   // don't overwrite a value being typed
  FEmu.Lock;
  try
    // Another machine (a Spectrum's rows depend on the model, and on its Timex, ULAplus and AY)
    if (FEmu.Spec.Model <> FModel) or (FChips and (FGrid.RowCount <> Length(FRows) + 1)) then Fill;
    if FChips then
    begin
      // The rows the machine has may change with its settings (the AY on the 48K, ULAplus, Timex)
      I := Length(FRows);
      FillChips;
      if I <> Length(FRows) then FGrid.Invalidate;
      for I := 0 to High(FRows) do
      begin
        V := FEmu.Spec.ChipRegister(FRows[I].Code);
        FGrid.Cells[2, I + 1] := IntToHex(V, 2);
        FGrid.Cells[3, I + 1] := BitsSet(FRows[I].Bits, V);
      end;
    end
    else if FMsx then
      for I := 0 to High(MSX_REGS) do
      begin
        V := 0;
        if MSX_REGS[I].Code >= $260 then
        begin
          FGrid.Cells[2, I + 1] := IntToHex(FEmu.Spec.MSXHw.PortValue(MSX_REGS[I].Code), 3);
          FGrid.Cells[3, I + 1] := '';
        end
        else
        begin
          V := FEmu.Spec.MSXHw.PortValue(MSX_REGS[I].Code);
          FGrid.Cells[2, I + 1] := IntToHex(V, 2);
          FGrid.Cells[3, I + 1] := Trim(BitsSet(MSX_REGS[I].Bits, V) + '  ' + MsxMapping(MSX_REGS[I].Code));
        end;
      end
    else if FSam then
      for I := 0 to High(SAM_REGS) do
      begin
        V := FEmu.Spec.SamRegister(SAM_REGS[I].Code);
        FGrid.Cells[2, I + 1] := IntToHex(V, 2);
        FGrid.Cells[3, I + 1] := Trim(BitsSet(SAM_REGS[I].Bits, V) + '  ' + SamMapping(SAM_REGS[I].Code and $FF));
      end
    else if FNext then
      for I := 0 to High(NEXT_REGS) do
      begin
        V := FEmu.Spec.NextRegister(NEXT_REGS[I].Reg);
        FGrid.Cells[2, I + 1] := IntToHex(V, 2);
        FGrid.Cells[3, I + 1] := BitsSet(NEXT_REGS[I].Bits, V);
      end
    else
      for I := 0 to High(REGS) do
      begin
        V := FEmu.Spec.ZXUnoRegister(REGS[I].Reg);
        FGrid.Cells[2, I + 1] := IntToHex(V, 2);
        FGrid.Cells[3, I + 1] := BitsSet(REGS[I].Bits, V);
      end;
  finally
    FEmu.Unlock;
  end;
end;

procedure TZXUnoRegsWindow.Tick(Sender: TObject);
begin
  // Every Z80 machine has its chips: not the C64 (its debugger has a window of its own)
  if IsC64Model(FEmu.Spec.Model) then
  begin
    Close;
    Exit;
  end;
  if Visible then UpdateValues;
end;

{ Only the values can be edited }
procedure TZXUnoRegsWindow.GridSelectEditor(Sender: TObject; ACol, ARow: Integer;
  var Editor: TWinControl);
begin
  if (ACol <> 2) or (FChips and (ARow >= 1) and (ARow <= Length(FRows)) and FRows[ARow - 1].ReadOnly) or
     (FSam and (ARow >= 1) and SAM_REGS[ARow - 1].ReadOnly) or
     (FMsx and (ARow >= 1) and MSX_REGS[ARow - 1].ReadOnly) then Editor := nil
  else if Editor is TCustomEdit then
    if FMsx and (ARow >= 1) and (MSX_REGS[ARow - 1].Code >= $260) then TCustomEdit(Editor).MaxLength := 3
    else TCustomEdit(Editor).MaxLength := 2;
end;

procedure TZXUnoRegsWindow.GridEditingDone(Sender: TObject);
var
  Row, V: Integer;
begin
  Row := FGrid.Row;
  if (FGrid.Col <> 2) or (Row < 1) or (Row >= FGrid.RowCount) then Exit;
  V := StrToIntDef('$' + Trim(FGrid.Cells[2, Row]), -1);
  if FChips then
  begin
    if (Row <= Length(FRows)) and not FRows[Row - 1].ReadOnly and (V >= 0) and (V <= 255) then
    begin
      FEmu.Lock;
      try
        FEmu.Spec.SetChipRegister(FRows[Row - 1].Code, V);
      finally
        FEmu.Unlock;
      end;
    end;
    UpdateValues;
    if Assigned(FOnChanged) then FOnChanged(Self);
    Exit;
  end;
  if FSam and SAM_REGS[Row - 1].ReadOnly then V := -1;
  if FMsx and MSX_REGS[Row - 1].ReadOnly then V := -1;
  if FMsx and (V >= 0) and ((V <= 255) or ((V <= $777) and (MSX_REGS[Row - 1].Code >= $260))) then
  begin
    FEmu.Lock;
    try
      FEmu.Spec.MSXHw.SetPortValue(MSX_REGS[Row - 1].Code, V);
    finally
      FEmu.Unlock;
    end;
  end
  else if (V >= 0) and (V <= 255) and not FMsx then
  begin
    FEmu.Lock;
    try
      if FSam then FEmu.Spec.SetSamRegister(SAM_REGS[Row - 1].Code, V)
      else if FNext then FEmu.Spec.SetNextRegister(NEXT_REGS[Row - 1].Reg, V)
      else FEmu.Spec.SetZXUnoRegister(REGS[Row - 1].Reg, V);
    finally
      FEmu.Unlock;
    end;
  end;
  UpdateValues;
  if Assigned(FOnChanged) then FOnChanged(Self);
end;

procedure TZXUnoRegsWindow.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  CloseAction := caHide;
end;

{ Escape closes the window (while editing a value it only cancels the edit) }
procedure TZXUnoRegsWindow.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_ESCAPE) and not FGrid.EditorMode then
  begin
    Key := 0;
    Close;
  end;
end;

end.

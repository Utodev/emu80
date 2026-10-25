{ ZXUnoRegsForm: the ZX-Uno's registers (ports FC3B/FD3B), the ZX
  Spectrum Next's (ports 243B/253B) or the SAM Coupe's main ports (paging
  LMPR and HMPR, video page and mode VMPR, border, line interrupt, status, the
  CLUT and the SAA1099's registers), a non-modal window opened from the
  debugger. Each register with its number, name, value (hex, editable:
  writing it is like an OUT to FD3B, or a NEXTREG) and, for the ones made
  of flags, the bits set. Updated while the machine runs. }
unit ZXUnoRegsForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Grids, ExtCtrls, StdCtrls, LCLType,
  Emulator, Models, Spectrum;

type
  TZXUnoRegsWindow = class(TForm)
  private
    FEmu: TEmulator;
    FGrid: TStringGrid;
    FTimer: TTimer;
    FNote: TLabel;
    FNext: Boolean;         // showing the Next's registers
    FSam: Boolean;          // showing the SAM Coupe's ports
    FOnChanged: TNotifyEvent;
    function SamMapping(Port: Integer): string;
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

  { A SAM Coupe port, as TSpectrum.SamRegister numbers them }
  TSamRegInfo = record
    Code: Integer;
    Port: string;
    Name: string;
    Bits: string;
    ReadOnly: Boolean;
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

{ The rows for the machine shown: the ZX-Uno's registers, the Next's or the SAM Coupe's }
procedure TZXUnoRegsWindow.Fill;
var
  I: Integer;
begin
  FNext := FEmu.Spec.Model = smZXNext;
  FSam := FEmu.Spec.Model = smSAM;
  if FSam then
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
    if ((FEmu.Spec.Model = smZXNext) <> FNext) or ((FEmu.Spec.Model = smSAM) <> FSam) then Fill;
    if FSam then
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
  // Only a ZX-Uno, a Next or a SAM Coupe has these registers
  if not (FEmu.Spec.Model in [smZXUno, smZXNext, smSAM]) then
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
  if (ACol <> 2) or (FSam and (ARow >= 1) and SAM_REGS[ARow - 1].ReadOnly) then Editor := nil
  else if Editor is TCustomEdit then TCustomEdit(Editor).MaxLength := 2;
end;

procedure TZXUnoRegsWindow.GridEditingDone(Sender: TObject);
var
  Row, V: Integer;
begin
  Row := FGrid.Row;
  if (FGrid.Col <> 2) or (Row < 1) or (Row >= FGrid.RowCount) then Exit;
  V := StrToIntDef('$' + Trim(FGrid.Cells[2, Row]), -1);
  if FSam and SAM_REGS[Row - 1].ReadOnly then V := -1;
  if (V >= 0) and (V <= 255) then
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

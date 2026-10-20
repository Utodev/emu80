{ ZXUnoRegsForm: the ZX-Uno's registers (ports FC3B/FD3B), or the ZX
  Spectrum Next's (ports 243B/253B), a non-modal window opened from the
  debugger. Each register with its number, name, value (hex, editable:
  writing it is like an OUT to FD3B, or a NEXTREG) and, for the ones made
  of flags, the bits set. Updated while the machine runs. }
unit ZXUnoRegsForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Grids, ExtCtrls, StdCtrls, LCLType,
  Emulator, Models;

type
  TZXUnoRegsWindow = class(TForm)
  private
    FEmu: TEmulator;
    FGrid: TStringGrid;
    FTimer: TTimer;
    FNote: TLabel;
    FNext: Boolean;         // showing the Next's registers
    procedure Fill;
    procedure Tick(Sender: TObject);
    procedure GridSelectEditor(Sender: TObject; ACol, ARow: Integer; var Editor: TWinControl);
    procedure GridEditingDone(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  public
    constructor CreateFor(AOwner: TComponent; AEmu: TEmulator);
    procedure UpdateValues;
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

{ The rows for the machine shown: the ZX-Uno's registers or the Next's }
procedure TZXUnoRegsWindow.Fill;
var
  I: Integer;
begin
  FNext := FEmu.Spec.Model = smZXNext;
  if FNext then
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
    if (FEmu.Spec.Model = smZXNext) <> FNext then Fill;
    if FNext then
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
  // Only a ZX-Uno or a Next has these registers
  if not (FEmu.Spec.Model in [smZXUno, smZXNext]) then
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
  if ACol <> 2 then Editor := nil
  else if Editor is TCustomEdit then TCustomEdit(Editor).MaxLength := 2;
end;

procedure TZXUnoRegsWindow.GridEditingDone(Sender: TObject);
var
  Row, V: Integer;
begin
  Row := FGrid.Row;
  if (FGrid.Col <> 2) or (Row < 1) or (Row >= FGrid.RowCount) then Exit;
  V := StrToIntDef('$' + Trim(FGrid.Cells[2, Row]), -1);
  if (V >= 0) and (V <= 255) then
  begin
    FEmu.Lock;
    try
      if FNext then FEmu.Spec.SetNextRegister(NEXT_REGS[Row - 1].Reg, V)
      else FEmu.Spec.SetZXUnoRegister(REGS[Row - 1].Reg, V);
    finally
      FEmu.Unlock;
    end;
  end;
  UpdateValues;
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

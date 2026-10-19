{ ZXUnoRegsForm: the ZX-Uno's registers (ports FC3B/FD3B), a non-modal
  window opened from the debugger. Each register with its number, name,
  value (hex, editable: writing it is like an OUT to FD3B) and, for the
  ones made of flags, the bits set. Updated while the machine runs. }
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
  Caption := 'ZX-Uno Registers';
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
  FNote.Caption := 'To change a value select it, type the new one (hex) and press Enter: ' +
    'it is written like an OUT to FD3B with the register selected at FC3B.';

  FGrid := TStringGrid.Create(Self);
  FGrid.Parent := Self;
  FGrid.Align := alClient;
  FGrid.ColCount := 4;
  FGrid.RowCount := Length(REGS) + 1;
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
  for I := 0 to High(REGS) do
  begin
    FGrid.Cells[0, I + 1] := IntToHex(REGS[I].Reg, 2);
    FGrid.Cells[1, I + 1] := REGS[I].Name;
  end;
  FGrid.OnSelectEditor := @GridSelectEditor;
  FGrid.OnEditingDone := @GridEditingDone;

  FTimer := TTimer.Create(Self);
  FTimer.Interval := 200;
  FTimer.OnTimer := @Tick;
  UpdateValues;
end;

procedure TZXUnoRegsWindow.UpdateValues;
var
  I: Integer;
  V: Byte;
begin
  if FGrid.EditorMode then Exit;   // don't overwrite a value being typed
  FEmu.Lock;
  try
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
  // Only a ZX-Uno has these registers
  if FEmu.Spec.Model <> smZXUno then
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
  if (FGrid.Col <> 2) or (Row < 1) or (Row > Length(REGS)) then Exit;
  V := StrToIntDef('$' + Trim(FGrid.Cells[2, Row]), -1);
  if (V >= 0) and (V <= 255) then
  begin
    FEmu.Lock;
    try
      FEmu.Spec.SetZXUnoRegister(REGS[Row - 1].Reg, V);
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

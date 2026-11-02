{ C64Opcodes: the 6502's instruction set (the C64's 6510 runs it) as a table, made and used as the Z80's (Z80Opcodes):
  16x16 cells, the opcode's high digit on the left and the low one on top, each with the instruction (operands as n for
  a byte, nn for an address, e for a relative jump). The undocumented opcodes, all of them there, are dark red in bold.
  Resting the mouse on a cell for a second shows what the instruction does, as in the debugger (C64Help). A box on top
  finds instructions as they are typed: the cells that have it are light blue. There is one table: no tabs.

  The window is square and the letters as big as fit in a cell. }
unit C64Opcodes;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, Forms, Controls, Graphics, Grids, StdCtrls, ExtCtrls, LCLType,
  Cpu6510, C64Help, DelayHint;

type
  TC64OpcodesWindow = class(TForm)
  private
    FTop: TPanel;
    FFind: TEdit;
    FCount: TLabel;
    FGrid: TDrawGrid;
    FTexts: array[Byte] of string;          // every cell, made once
    FMatch: array[Byte] of Boolean;         // found by the box
    FHintCell: TPoint;
    FSplit: Boolean;            // the operands on two lines (after the comma)
    procedure FitCells;
    procedure FindChange(Sender: TObject);
    procedure GridDrawCell(Sender: TObject; ACol, ARow: Integer; ARect: TRect;
      AState: TGridDrawState);
    procedure GridMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure GridMouseLeave(Sender: TObject);
    procedure GridResize(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormShow(Sender: TObject);
  public
    constructor CreateNew(AOwner: TComponent; Num: Integer = 0); override;
    { The instruction in a cell, and its help }
    function CellText(Op: Byte): string;
    function CellHelp(Op: Byte): string;
  end;

procedure ShowC64Opcodes;

{ The instruction of an opcode with its operands as names: "LDA (n),Y", "JMP nn", "BNE e" }
function OpcodeText(Op: Byte): string;

var
  C64OpcodesWindow: TC64OpcodesWindow;

implementation

uses
  ModernUI;

function OpcodeText(Op: Byte): string;
var
  Operand: string;
begin
  case OpMode[Op] of
    amAcc: Operand := 'A';
    amImm: Operand := '#n';
    amZp: Operand := 'n';
    amZpx: Operand := 'n,X';
    amZpy: Operand := 'n,Y';
    amAbs: Operand := 'nn';
    amAbx: Operand := 'nn,X';
    amAby: Operand := 'nn,Y';
    amInd: Operand := '(nn)';
    amIzx: Operand := '(n,X)';
    amIzy: Operand := '(n),Y';
    amRel: Operand := 'e';
  else
    Operand := '';
  end;
  Result := OpName[Op];
  if Operand <> '' then Result := Result + ' ' + Operand;
end;

{ A cell's lines: the mnemonic, then the operands (split after the comma when that lets the letters be bigger) }
function CellLines(const Txt: string; Split: Boolean): TStringArray;
var
  P: Integer;
  Ops: string;
begin
  Result := nil;
  if Txt = '' then Exit;
  P := Pos(' ', Txt);
  if P = 0 then
  begin
    SetLength(Result, 1);
    Result[0] := Txt;
    Exit;
  end;
  Ops := Copy(Txt, P + 1, MaxInt);
  if Split and (Pos(',', Ops) > 0) then
  begin
    SetLength(Result, 3);
    Result[1] := Copy(Ops, 1, Pos(',', Ops));
    Result[2] := Copy(Ops, Pos(',', Ops) + 1, MaxInt);
  end
  else
  begin
    SetLength(Result, 2);
    Result[1] := Ops;
  end;
  Result[0] := Copy(Txt, 1, P - 1);
end;

function MatchColor: TColor;
begin
  Result := TC(RGBToColor(190, 220, 255));
end;

procedure ShowC64Opcodes;
begin
  if C64OpcodesWindow = nil then C64OpcodesWindow := TC64OpcodesWindow.CreateNew(Application);
  C64OpcodesWindow.Show;
  C64OpcodesWindow.BringToFront;
end;

constructor TC64OpcodesWindow.CreateNew(AOwner: TComponent; Num: Integer);
var
  Op: Integer;
  Lbl: TLabel;
begin
  inherited CreateNew(AOwner, Num);
  Caption := '6502 opcodes';
  Position := poMainFormCenter;
  KeyPreview := True;
  OnKeyDown := @FormKeyDown;
  OnShow := @FormShow;
  for Op := 0 to 255 do FTexts[Op] := OpcodeText(Op);

  // The search box
  FTop := TPanel.Create(Self);
  FTop.Parent := Self;
  FTop.Align := alTop;
  FTop.BevelOuter := bvNone;
  FTop.Height := 34;
  Lbl := TLabel.Create(Self);
  Lbl.Parent := FTop;
  Lbl.Caption := 'Find instruction:';
  Lbl.Left := 8;
  Lbl.AnchorVerticalCenterTo(FTop);
  FFind := TEdit.Create(Self);
  FFind.Parent := FTop;
  FFind.AnchorSideLeft.Control := Lbl;
  FFind.AnchorSideLeft.Side := asrRight;
  FFind.BorderSpacing.Left := 8;
  FFind.Width := 200;
  FFind.AnchorVerticalCenterTo(FTop);
  FFind.Hint := 'The cells with this text (LDA, (n),Y, #n...) turn light blue';
  FFind.ShowHint := True;
  FFind.OnChange := @FindChange;
  FCount := TLabel.Create(Self);
  FCount.Parent := FTop;
  FCount.AnchorSideLeft.Control := FFind;
  FCount.AnchorSideLeft.Side := asrRight;
  FCount.BorderSpacing.Left := 10;
  FCount.AnchorVerticalCenterTo(FTop);
  FCount.Font.Color := clGrayText;
  FCount.Caption := '';

  FGrid := TDrawGrid.Create(Self);
  FGrid.Parent := Self;
  FGrid.Align := alClient;
  FGrid.ColCount := 17;
  FGrid.RowCount := 17;
  FGrid.FixedCols := 1;
  FGrid.FixedRows := 1;
  FGrid.ScrollBars := ssNone;
  FGrid.Options := FGrid.Options - [goRangeSelect, goDrawFocusSelected];
  FGrid.OnDrawCell := @GridDrawCell;
  FGrid.OnMouseMove := @GridMouseMove;
  FGrid.OnMouseLeave := @GridMouseLeave;
  FGrid.OnResize := @GridResize;
  FHintCell := Point(-1, -1);
end;

function TC64OpcodesWindow.CellText(Op: Byte): string;
begin
  Result := FTexts[Op];
end;

function TC64OpcodesWindow.CellHelp(Op: Byte): string;
begin
  // What the debugger says over a mnemonic: the description, whether it is undocumented, the flags, the mode, the
  // bytes and the cycles
  Result := InstructionHelp6502(Op, '');
  if Result = '' then Result := FTexts[Op];
  Result := Format('%.2X  %s', [Op, FTexts[Op]]) + LineEnding + Result;
end;

{ Square, as big as fits on the screen without being huge }
procedure TC64OpcodesWindow.FormShow(Sender: TObject);
var
  S: Integer;
begin
  S := Min(Scale96ToForm(680), Min(Screen.WorkAreaHeight - 60, Screen.WorkAreaWidth - 40));
  ClientWidth := S;
  ClientHeight := S;
  FitCells;
end;

procedure TC64OpcodesWindow.GridResize(Sender: TObject);
begin
  FitCells;
end;

{ The cells share the grid's room, and the letters are the biggest that let every instruction fit in its cell (two
  lines: mnemonic, operands; or three, split after the comma) }
procedure TC64OpcodesWindow.FitCells;
var
  W, H, Hdr, CW, RH, HdrRow, I, Best, Size: Integer;
  Split: Boolean;
  C: TCanvas;

  { The biggest size that fits, with the operands on one line or two }
  function Fits(ASplit: Boolean): Integer;
  var
    Op, Widest, LineH, NLines: Integer;
    Line: string;
  begin
    if ASplit then NLines := 3 else NLines := 2;
    Result := 20;
    repeat
      C.Font.Size := Result;
      C.Font.Style := [fsBold];
      Hdr := C.TextWidth('W') + 6;
      HdrRow := C.TextHeight('Xg') + 2;
      CW := (W - Hdr) div 16;
      RH := (H - HdrRow) div 16;
      LineH := C.TextHeight('Xg') - 1;
      // The widest line of any cell (in bold, as they are drawn)
      Widest := 0;
      for Op := 0 to 255 do
        for Line in CellLines(FTexts[Op], ASplit) do Widest := Max(Widest, C.TextWidth(Line));
      if (Widest + 4 <= CW) and (LineH * NLines + 2 <= RH) then Exit;
      Dec(Result);
    until Result <= 5;
  end;

begin
  W := FGrid.ClientWidth - 2;
  H := FGrid.ClientHeight - 2;
  if (W < 100) or (H < 100) then Exit;
  C := FGrid.Canvas;
  C.Font.Assign(FGrid.Font);
  Best := Fits(False);
  Size := Fits(True);
  Split := Size > Best;
  if not Split then Size := Fits(False);   // its sizes again
  FSplit := Split;
  FGrid.Font.Size := Size;
  FGrid.ColWidths[0] := Hdr;
  for I := 1 to 16 do FGrid.ColWidths[I] := CW;
  FGrid.RowHeights[0] := HdrRow;
  for I := 1 to 16 do FGrid.RowHeights[I] := RH;
  FGrid.Invalidate;
end;

{ The cells with the text typed (any case) }
procedure TC64OpcodesWindow.FindChange(Sender: TObject);
var
  Op, N: Integer;
  Want: string;
begin
  Want := UpperCase(Trim(FFind.Text));
  N := 0;
  for Op := 0 to 255 do
  begin
    FMatch[Op] := (Want <> '') and (Pos(Want, UpperCase(FTexts[Op])) > 0);
    if FMatch[Op] then Inc(N);
  end;
  if Want = '' then FCount.Caption := ''
  else if N = 1 then FCount.Caption := '1 instruction'
  else FCount.Caption := Format('%d instructions', [N]);
  FGrid.Invalidate;
end;

procedure TC64OpcodesWindow.GridDrawCell(Sender: TObject; ACol, ARow: Integer; ARect: TRect;
  AState: TGridDrawState);
var
  C: TCanvas;
  Txt: string;
  Lines: TStringArray;
  Op, I, H: Integer;
begin
  C := FGrid.Canvas;
  C.Font := FGrid.Font;
  // Headers: the opcode's low digit on top, the high one on the left
  if (ACol = 0) or (ARow = 0) then
  begin
    C.Font.Style := [fsBold];
    if (ACol = 0) and (ARow > 0) then Txt := IntToHex(ARow - 1, 1)
    else if (ARow = 0) and (ACol > 0) then Txt := IntToHex(ACol - 1, 1)
    else Txt := '';
    C.TextOut(ARect.Left + (ARect.Width - C.TextWidth(Txt)) div 2,
      ARect.Top + (ARect.Height - C.TextHeight(Txt)) div 2, Txt);
    Exit;
  end;
  Op := (ARow - 1) * 16 + ACol - 1;
  Txt := FTexts[Op];
  if FMatch[Op] then C.Brush.Color := MatchColor else C.Brush.Color := TC(clWindow);
  C.FillRect(ARect);
  if Txt = '' then Exit;
  // The mnemonic on the first line, the operands below; every instruction in bold, the undocumented ones in dark red
  Lines := CellLines(Txt, FSplit);
  C.Font.Style := [fsBold];
  if OpIllegal[Op] then C.Font.Color := TC(RGBToColor(150, 0, 0))
  else C.Font.Color := TC(clWindowText);
  H := C.TextHeight('Xg') - 1;
  C.Brush.Style := bsClear;
  for I := 0 to High(Lines) do
    C.TextOut(ARect.Left + 2, ARect.Top + (ARect.Height - H * Length(Lines)) div 2 + I * H, Lines[I]);
  C.Brush.Style := bsSolid;
end;

procedure TC64OpcodesWindow.GridMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  Cell: TPoint;
  Help: string;
begin
  Cell := FGrid.MouseToCell(Point(X, Y));
  if (Cell.X = FHintCell.X) and (Cell.Y = FHintCell.Y) then Exit;
  FHintCell := Cell;
  if (Cell.X < 1) or (Cell.Y < 1) then
  begin
    DelayedHint.Cancel;
    Exit;
  end;
  Help := CellHelp((Cell.Y - 1) * 16 + Cell.X - 1);
  if Help = '' then DelayedHint.Cancel
  else DelayedHint.Request(FGrid, FGrid.CellRect(Cell.X, Cell.Y), Help);
end;

procedure TC64OpcodesWindow.GridMouseLeave(Sender: TObject);
begin
  FHintCell := Point(-1, -1);
  DelayedHint.Cancel;
end;

procedure TC64OpcodesWindow.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    Key := 0;
    Close;
  end;
end;

end.

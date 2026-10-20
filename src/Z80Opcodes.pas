{ Z80Opcodes: the Z80's instruction set as tables, one per prefix (Main,
  CB, ED, DD, FD), chosen with tabs: 16x16 cells, the opcode's high digit
  on the left and the low one on top, each with the instruction (operands
  as n, nn, d, e). Undocumented instructions are dark red in bold; the
  opcodes a prefix doesn't have are left empty. Resting the mouse on a cell
  for a second shows what the instruction does, as in the debugger. A box
  on top finds instructions as they are typed: the cells that have it are
  light blue, and so are the tabs of the tables that have some.

  The window is square and the letters as big as fit in a cell. }
unit Z80Opcodes;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, Forms, Controls, Graphics, Grids, StdCtrls, ExtCtrls, LCLType,
  Disasm, Z80Help, DelayHint;

type
  TOpcodeTable = (otMain, otCB, otED, otDD, otFD);

  TZ80OpcodesWindow = class(TForm)
  private
    FTop: TPanel;
    FFind: TEdit;
    FCount: TLabel;
    FTabs: TPaintBox;
    FGrid: TDrawGrid;
    FTable: TOpcodeTable;                                // the one shown
    FTexts: array[TOpcodeTable, Byte] of string;          // every cell, made once
    FUndoc: array[TOpcodeTable, Byte] of Boolean;
    FMatch: array[TOpcodeTable, Byte] of Boolean;         // found by the box
    FHasMatch: array[TOpcodeTable] of Boolean;
    FBytes: array[0..7] of Byte;
    FHintCell: TPoint;
    FSplit: Boolean;            // the operands on two lines (after the comma)
    function PeekBytes(Addr: Word): Byte;
    procedure SetBytes(Table: TOpcodeTable; Op: Byte);
    function MakeText(Table: TOpcodeTable; Op: Byte; out Undocumented: Boolean): string;
    function TabRect(T: TOpcodeTable): TRect;
    procedure ShowTable(T: TOpcodeTable);
    procedure FitCells;
    procedure FindChange(Sender: TObject);
    procedure TabsPaint(Sender: TObject);
    procedure TabsMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure GridDrawCell(Sender: TObject; ACol, ARow: Integer; ARect: TRect;
      AState: TGridDrawState);
    procedure GridMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure GridMouseLeave(Sender: TObject);
    procedure GridResize(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormShow(Sender: TObject);
  public
    constructor CreateNew(AOwner: TComponent; Num: Integer = 0); override;
    { The instruction in a cell ('' if the prefix has none there), whether it
      is undocumented, and its help }
    function CellText(Table: TOpcodeTable; Op: Byte; out Undocumented: Boolean): string;
    function CellHelp(Table: TOpcodeTable; Op: Byte): string;
  end;

procedure ShowZ80Opcodes;

var
  Z80OpcodesWindow: TZ80OpcodesWindow;

implementation

uses
  ModernUI;

const
  TABLE_NAMES: array[TOpcodeTable] of string = ('Main', 'CB', 'ED', 'DD', 'FD');
  PREFIX: array[TOpcodeTable] of Byte = (0, $CB, $ED, $DD, $FD);

{ A cell's lines: the mnemonic, then the operands (split after the comma
  when that lets the letters be bigger) }
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
  if Split and (Pos(',', Ops) > 0) and (Pos('prefix', Txt) = 0) then
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

procedure ShowZ80Opcodes;
begin
  if Z80OpcodesWindow = nil then Z80OpcodesWindow := TZ80OpcodesWindow.CreateNew(Application);
  Z80OpcodesWindow.Show;
  Z80OpcodesWindow.BringToFront;
end;

constructor TZ80OpcodesWindow.CreateNew(AOwner: TComponent; Num: Integer);
var
  T: TOpcodeTable;
  Op: Integer;
  Lbl: TLabel;
begin
  inherited CreateNew(AOwner, Num);
  Caption := 'Z80 opcodes';
  Position := poMainFormCenter;
  KeyPreview := True;
  OnKeyDown := @FormKeyDown;
  OnShow := @FormShow;
  for T := Low(TOpcodeTable) to High(TOpcodeTable) do
    for Op := 0 to 255 do FTexts[T, Op] := MakeText(T, Op, FUndoc[T, Op]);

  // The search box, for every table
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
  FFind.Hint := 'The cells with this text (LD, IXH, (IX+d)...) turn light blue, and so do the ' +
    'tabs of the tables that have some';
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

  // The tabs: drawn here, so that their titles can change colour
  FTabs := TPaintBox.Create(Self);
  FTabs.Parent := Self;
  FTabs.Align := alTop;
  FTabs.Top := 100;
  FTabs.Height := 26;
  FTabs.OnPaint := @TabsPaint;
  FTabs.OnMouseDown := @TabsMouseDown;

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
  FTable := otMain;
  FHintCell := Point(-1, -1);
end;

function TZ80OpcodesWindow.PeekBytes(Addr: Word): Byte;
begin
  Result := FBytes[Addr and 7];
end;

{ The instruction's bytes at address 0: the prefix, the opcode and zeros
  (DDCB/FDCB: d before the opcode) }
procedure TZ80OpcodesWindow.SetBytes(Table: TOpcodeTable; Op: Byte);
begin
  FillChar(FBytes, SizeOf(FBytes), 0);
  if Table = otMain then FBytes[0] := Op
  else
  begin
    FBytes[0] := PREFIX[Table];
    FBytes[1] := Op;
  end;
end;

function TZ80OpcodesWindow.MakeText(Table: TOpcodeTable; Op: Byte; out Undocumented: Boolean): string;
var
  Len: Integer;
  Note: string;
begin
  Undocumented := False;
  // The prefixes themselves
  if (Table = otMain) and (Op in [$CB, $DD, $ED, $FD]) then
    Exit(Format('%.2X prefix', [Op]));
  if (Table in [otDD, otFD]) and (Op = $CB) then
    Exit(Format('%.2XCB prefix', [PREFIX[Table]]));
  SetBytes(Table, Op);
  Note := UndocumentedNote(0, @PeekBytes);
  // Opcodes the prefix doesn't have: ED's that do nothing, DD/FD ones that
  // don't use HL (or another prefix)
  if (Table = otED) and (Pos('doesn''t exist', Note) > 0) then Exit('');
  if (Table in [otDD, otFD]) and ((Op in [$DD, $ED, $FD]) or (Pos('no effect', Note) > 0)) then
    Exit('');
  Undocumented := Note <> '';
  Result := Disassemble(0, @PeekBytes, Len);
  // The operands as names: d, nn, e (relative jumps), n
  Result := StringReplace(Result, '(IX+$00)', '(IX+d)', [rfReplaceAll]);
  Result := StringReplace(Result, '(IY+$00)', '(IY+d)', [rfReplaceAll]);
  if (Copy(Result, 1, 2) = 'JR') or (Copy(Result, 1, 4) = 'DJNZ') then
    Result := StringReplace(Result, '$' + IntToHex(Len, 4), 'e', [])
  else if Copy(Result, 1, 3) <> 'RST' then
  begin
    Result := StringReplace(Result, '$0000', 'nn', []);
    Result := StringReplace(Result, '$00', 'n', []);
  end;
end;

function TZ80OpcodesWindow.CellText(Table: TOpcodeTable; Op: Byte; out Undocumented: Boolean): string;
begin
  Undocumented := FUndoc[Table, Op];
  Result := FTexts[Table, Op];
end;

function TZ80OpcodesWindow.CellHelp(Table: TOpcodeTable; Op: Byte): string;
var
  Txt, Note: string;
begin
  Txt := FTexts[Table, Op];
  if Txt = '' then Exit('');
  if Pos('prefix', Txt) > 0 then
    Exit(Txt + LineEnding + 'The next byte is an instruction of the ' +
      Copy(Txt, 1, Pos(' ', Txt) - 1) + ' table.');
  SetBytes(Table, Op);
  Result := InstructionHelp(Txt);
  if Result = '' then Result := Txt;
  Result := Result + LineEnding + 'T-States: ' + InstructionTStates(0, @PeekBytes);
  Note := UndocumentedNote(0, @PeekBytes);
  if Note <> '' then Result := Result + LineEnding + 'Undocumented: ' + Note;
end;

{ Square, as big as fits on the screen without being huge }
procedure TZ80OpcodesWindow.FormShow(Sender: TObject);
var
  S: Integer;
begin
  S := Min(Scale96ToForm(680), Min(Screen.WorkAreaHeight - 60, Screen.WorkAreaWidth - 40));
  ClientWidth := S;
  ClientHeight := S;
  FitCells;
end;

procedure TZ80OpcodesWindow.GridResize(Sender: TObject);
begin
  FitCells;
end;

{ The cells share the grid's room, and the letters are the biggest that
  let every instruction fit in its cell (two lines: mnemonic, operands) }
procedure TZ80OpcodesWindow.FitCells;
var
  W, H, Hdr, CW, RH, HdrRow, I, Best, Size: Integer;
  Split: Boolean;
  C: TCanvas;

  { The biggest size that fits, with the operands on one line or two }
  function Fits(ASplit: Boolean): Integer;
  var
    T: TOpcodeTable;
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
      for T := Low(TOpcodeTable) to High(TOpcodeTable) do
        for Op := 0 to 255 do
          for Line in CellLines(FTexts[T, Op], ASplit) do Widest := Max(Widest, C.TextWidth(Line));
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
  FTabs.Font.Size := Max(9, Min(Size, 12));
  FGrid.ColWidths[0] := Hdr;
  for I := 1 to 16 do FGrid.ColWidths[I] := CW;
  FGrid.RowHeights[0] := HdrRow;
  for I := 1 to 16 do FGrid.RowHeights[I] := RH;
  FGrid.Invalidate;
end;

function TZ80OpcodesWindow.TabRect(T: TOpcodeTable): TRect;
var
  TW: Integer;
begin
  TW := Max(70, FTabs.Canvas.TextWidth('Main') + 30);
  Result := Rect(4 + Ord(T) * (TW + 2), 2, 4 + Ord(T) * (TW + 2) + TW, FTabs.Height);
end;

{ The tabs: the shown one white, the others grey; those with instructions
  found light blue, with their title in blue }
procedure TZ80OpcodesWindow.TabsPaint(Sender: TObject);
var
  T: TOpcodeTable;
  R: TRect;
  C: TCanvas;
  Found: Boolean;
begin
  C := FTabs.Canvas;
  C.Brush.Color := TC(clBtnFace);
  C.FillRect(FTabs.ClientRect);
  C.Pen.Color := TC(clGray);
  C.Line(0, FTabs.Height - 1, FTabs.Width, FTabs.Height - 1);
  for T := Low(TOpcodeTable) to High(TOpcodeTable) do
  begin
    R := TabRect(T);
    Found := (FFind.Text <> '') and FHasMatch[T];
    if Found then C.Brush.Color := MatchColor
    else if T = FTable then C.Brush.Color := TC(clWindow)
    else C.Brush.Color := TC(RGBToColor(225, 225, 225));
    C.Pen.Color := TC(clGray);
    if T = FTable then
      C.Rectangle(R.Left, R.Top, R.Right, R.Bottom + 1)   // open at the bottom
    else
      C.Rectangle(R.Left, R.Top + 2, R.Right, R.Bottom);
    C.Font := FTabs.Font;
    if T = FTable then C.Font.Style := [fsBold];
    if Found then C.Font.Color := TC(RGBToColor(0, 60, 200)) else C.Font.Color := TC(clWindowText);
    C.Brush.Style := bsClear;
    C.TextOut(R.Left + (R.Width - C.TextWidth(TABLE_NAMES[T])) div 2,
      R.Top + (R.Height - C.TextHeight(TABLE_NAMES[T])) div 2 + 1, TABLE_NAMES[T]);
    C.Brush.Style := bsSolid;
  end;
end;

procedure TZ80OpcodesWindow.TabsMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  T: TOpcodeTable;
begin
  for T := Low(TOpcodeTable) to High(TOpcodeTable) do
    if PtInRect(TabRect(T), Point(X, Y)) then ShowTable(T);
end;

procedure TZ80OpcodesWindow.ShowTable(T: TOpcodeTable);
begin
  FTable := T;
  FHintCell := Point(-1, -1);
  DelayedHint.Cancel;
  FTabs.Invalidate;
  FGrid.Invalidate;
end;

{ The cells with the text typed (any case); if the table shown has none
  but another one has, that one is shown }
procedure TZ80OpcodesWindow.FindChange(Sender: TObject);
var
  T, First: TOpcodeTable;
  Op, N: Integer;
  Want: string;
  Any: Boolean;
begin
  Want := UpperCase(Trim(FFind.Text));
  N := 0;
  Any := False;
  First := FTable;
  for T := High(TOpcodeTable) downto Low(TOpcodeTable) do
  begin
    FHasMatch[T] := False;
    for Op := 0 to 255 do
    begin
      FMatch[T, Op] := (Want <> '') and (FTexts[T, Op] <> '') and
        (Pos('prefix', FTexts[T, Op]) = 0) and (Pos(Want, UpperCase(FTexts[T, Op])) > 0);
      if FMatch[T, Op] then
      begin
        FHasMatch[T] := True;
        Inc(N);
      end;
    end;
    if FHasMatch[T] then
    begin
      First := T;
      Any := True;
    end;
  end;
  if Want = '' then FCount.Caption := ''
  else if N = 1 then FCount.Caption := '1 instruction'
  else FCount.Caption := Format('%d instructions', [N]);
  if Any and not FHasMatch[FTable] then ShowTable(First)
  else
  begin
    FTabs.Invalidate;
    FGrid.Invalidate;
  end;
end;

procedure TZ80OpcodesWindow.GridDrawCell(Sender: TObject; ACol, ARow: Integer; ARect: TRect;
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
  Txt := FTexts[FTable, Op];
  if FMatch[FTable, Op] then C.Brush.Color := MatchColor else C.Brush.Color := TC(clWindow);
  C.FillRect(ARect);
  if Txt = '' then Exit;
  // The mnemonic on the first line, the operands (or "prefix") below
  Lines := CellLines(Txt, FSplit);
  if Pos('prefix', Txt) > 0 then
    C.Font.Color := TC(clGray)
  else
  begin
    // Every instruction in bold; the undocumented ones in dark red
    C.Font.Style := [fsBold];
    if FUndoc[FTable, Op] then C.Font.Color := TC(RGBToColor(150, 0, 0))
    else C.Font.Color := TC(clWindowText);
  end;
  H := C.TextHeight('Xg') - 1;
  C.Brush.Style := bsClear;
  for I := 0 to High(Lines) do
    C.TextOut(ARect.Left + 2, ARect.Top + (ARect.Height - H * Length(Lines)) div 2 + I * H, Lines[I]);
  C.Brush.Style := bsSolid;
end;

procedure TZ80OpcodesWindow.GridMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
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
  Help := CellHelp(FTable, (Cell.Y - 1) * 16 + Cell.X - 1);
  if Help = '' then DelayedHint.Cancel
  else DelayedHint.Request(FGrid, FGrid.CellRect(Cell.X, Cell.Y), Help);
end;

procedure TZ80OpcodesWindow.GridMouseLeave(Sender: TObject);
begin
  FHintCell := Point(-1, -1);
  DelayedHint.Cancel;
end;

procedure TZ80OpcodesWindow.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    Key := 0;
    Close;
  end;
end;

end.

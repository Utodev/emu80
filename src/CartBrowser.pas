{ CartBrowser: the cartridge in the MSX's first slot: an Info tab (size, mapper, the ROM header, checksum) and a Hex tab
  with its bytes, which can be edited (the machine runs the changed ROM at once), have blocks imported from or exported
  to files of the PC, and be saved to the .rom file or to another one. }
unit CartBrowser;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, ComCtrls, StdCtrls, ExtCtrls, Dialogs, Graphics, LCLType,
  Emulator, Icons, PathTitle;

type
  { The bytes as a hex dump: offset, 16 bytes in hex, and as characters; editable (hex digits, or characters in the text
    column; Tab goes from one to the other), with a selection }
  TCartHexView = class(TCustomControl)
  private
    FData: PByte;
    FSize: Integer;
    FTopRow: Integer;
    FPos: Integer;
    FNibble: Integer;        // 0: the next digit is the high one
    FInText: Boolean;
    FSelA, FSelB: Integer;   // the selection (anchor and end), -1 for none
    FDragging: Boolean;
    FLineH, FCharW: Integer;
    FScroll: TScrollBar;
    FOnChange: TNotifyEvent;
    FOnMove: TNotifyEvent;
    procedure Measure;
    function Rows: Integer;
    function VisibleRows: Integer;
    procedure SetCursor(Value: Integer; Extend: Boolean);
    procedure EnsureVisible;
    procedure UpdateScroll;
    procedure ScrollChange(Sender: TObject);
    function ByteAt(X, Y: Integer; out InText: Boolean): Integer;
    procedure PutByte(Value: Byte);
    function HexX(Col: Integer): Integer;
    function TextX: Integer;
  protected
    procedure Paint; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure Resize; override;
    procedure DoEnter; override;
    procedure DoExit; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetData(AData: PByte; ASize: Integer);
    procedure GoTo_(Offset: Integer);
    function HasSel: Boolean;
    function SelFirst: Integer;
    function SelLast: Integer;
    property Cursor_: Integer read FPos;
    property Scroll: TScrollBar read FScroll write FScroll;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnMove: TNotifyEvent read FOnMove write FOnMove;
  end;

  TCartSavedEvent = procedure(const FileName: string) of object;

  TCartBrowserWindow = class(TForm)
  private
    FTitle: TPathTitle;
    FEmu: TEmulator;
    FToolBar: TToolBar;
    FImages: TImageList;
    FPages: TPageControl;
    FInfoTab, FHexTab: TTabSheet;
    FInfo: TMemo;
    FHex: TCartHexView;
    FScroll: TScrollBar;
    FStatus: TStatusBar;
    FFile: string;
    FDirty: Boolean;
    function AddButton(AIcon: TIconKind; const AHint: string; AHandler: TNotifyEvent): TToolButton;
    procedure AddSeparator;
    procedure FillInfo;
    procedure UpdateTitle;
    procedure UpdateStatus(Sender: TObject);
    procedure HexChanged(Sender: TObject);
    function SaveTo(const FileName: string): Boolean;
    procedure DoSave(Sender: TObject);
    procedure DoSaveAs(Sender: TObject);
    procedure DoImport(Sender: TObject);
    procedure DoExport(Sender: TObject);
    procedure DoGoTo(Sender: TObject);
    procedure DoRefresh(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  public
    constructor CreateFor(AOwner: TComponent; AEmu: TEmulator);
    { Show what the slot holds now; FileName is where it came from ('' if it is not known) }
    procedure Refresh(const FileName: string);
  end;

var
  CartBrowserWindow: TCartBrowserWindow;
  { The file of the cartridge in slot 1 ('' if it is not known), kept by the main window; and what it wants to be told when
    the browser saves the cartridge under another name }
  CartFileName: string;
  CartOnSaved: TCartSavedEvent;

{ Opens the browser on the cartridge in slot 1 }
procedure ShowCartBrowser(Emu: TEmulator);
{ The cartridge in the slot changed: show the new one if the browser is open }
procedure RefreshCartBrowser;

implementation

uses
  Math, Msx, MsxMachine, Models, Lang;

const
  BYTES_PER_ROW = 16;

procedure ShowCartBrowser(Emu: TEmulator);
begin
  if CartBrowserWindow = nil then
    CartBrowserWindow := TCartBrowserWindow.CreateFor(Application, Emu);
  CartBrowserWindow.Refresh(CartFileName);
  CartBrowserWindow.Show;
  CartBrowserWindow.BringToFront;
end;

procedure RefreshCartBrowser;
begin
  if (CartBrowserWindow <> nil) and CartBrowserWindow.Visible then CartBrowserWindow.Refresh(CartFileName);
end;

{ TCartHexView }

constructor TCartHexView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TabStop := True;
  Color := clWindow;
  Font.Name := 'Courier New';
  Font.Size := 10;
  FSelA := -1;
  FSelB := -1;
  Measure;
end;

procedure TCartHexView.Measure;
var
  B: Graphics.TBitmap;
begin
  // (a bitmap's canvas: the control has no window yet when it is made, and its own canvas needs one)
  B := Graphics.TBitmap.Create;
  try
    B.Canvas.Font.Assign(Font);
    FLineH := B.Canvas.TextHeight('0') + 2;
    FCharW := B.Canvas.TextWidth('0');
  finally
    B.Free;
  end;
end;

function TCartHexView.Rows: Integer;
begin
  Result := (FSize + BYTES_PER_ROW - 1) div BYTES_PER_ROW;
end;

function TCartHexView.VisibleRows: Integer;
begin
  Result := Max(1, ClientHeight div FLineH);
end;

function TCartHexView.HexX(Col: Integer): Integer;
begin
  // 8 digits of offset, two spaces, then bytes with an extra gap after the eighth
  Result := (10 + Col * 3 + Ord(Col >= 8)) * FCharW + 4;
end;

function TCartHexView.TextX: Integer;
begin
  Result := (10 + BYTES_PER_ROW * 3 + 2) * FCharW + 4;
end;

procedure TCartHexView.SetData(AData: PByte; ASize: Integer);
begin
  FData := AData;
  FSize := ASize;
  FPos := 0;
  FNibble := 0;
  FTopRow := 0;
  FSelA := -1;
  FSelB := -1;
  UpdateScroll;
  Invalidate;
end;

procedure TCartHexView.UpdateScroll;
begin
  if FScroll = nil then Exit;
  FScroll.OnChange := nil;
  FScroll.Min := 0;
  FScroll.Max := Max(0, Rows - 1);
  FScroll.PageSize := Min(VisibleRows, Max(1, Rows));
  FScroll.LargeChange := Max(1, VisibleRows - 1);
  FScroll.Position := FTopRow;
  FScroll.OnChange := @ScrollChange;
end;

procedure TCartHexView.ScrollChange(Sender: TObject);
begin
  FTopRow := FScroll.Position;
  Invalidate;
end;

procedure TCartHexView.Resize;
begin
  inherited Resize;
  UpdateScroll;
end;

function TCartHexView.HasSel: Boolean;
begin
  Result := (FSelA >= 0) and (FSelB >= 0);
end;

function TCartHexView.SelFirst: Integer;
begin
  Result := Min(FSelA, FSelB);
end;

function TCartHexView.SelLast: Integer;
begin
  Result := Max(FSelA, FSelB);
end;

procedure TCartHexView.EnsureVisible;
var
  Row: Integer;
begin
  Row := FPos div BYTES_PER_ROW;
  if Row < FTopRow then FTopRow := Row
  else if Row >= FTopRow + VisibleRows then FTopRow := Row - VisibleRows + 1;
  FTopRow := Max(0, Min(FTopRow, Max(0, Rows - 1)));
  UpdateScroll;
end;

procedure TCartHexView.SetCursor(Value: Integer; Extend: Boolean);
begin
  if FSize = 0 then Exit;
  Value := Max(0, Min(FSize - 1, Value));
  if Extend then
  begin
    if FSelA < 0 then FSelA := FPos;
    FSelB := Value;
  end
  else
  begin
    FSelA := -1;
    FSelB := -1;
  end;
  FPos := Value;
  FNibble := 0;
  EnsureVisible;
  Invalidate;
  if Assigned(FOnMove) then FOnMove(Self);
end;

procedure TCartHexView.GoTo_(Offset: Integer);
begin
  SetCursor(Offset, False);
  FTopRow := Max(0, Min(Offset div BYTES_PER_ROW - VisibleRows div 2, Max(0, Rows - 1)));
  UpdateScroll;
  Invalidate;
  SetFocus;
end;

procedure TCartHexView.Paint;
var
  Row, Col, Index, Y, X: Integer;
  S: string;
  B: Byte;
  Sel, Cur: Boolean;
begin
  Canvas.Font.Assign(Font);
  Canvas.Brush.Color := clWindow;
  Canvas.FillRect(0, 0, ClientWidth, ClientHeight);
  for Row := FTopRow to Min(Rows - 1, FTopRow + VisibleRows) do
  begin
    Y := (Row - FTopRow) * FLineH + 1;
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Color := clGrayText;
    Canvas.TextOut(4, Y, IntToHex(Row * BYTES_PER_ROW, 8));
    for Col := 0 to BYTES_PER_ROW - 1 do
    begin
      Index := Row * BYTES_PER_ROW + Col;
      if Index >= FSize then Break;
      B := FData[Index];
      Sel := HasSel and (Index >= SelFirst) and (Index <= SelLast);
      Cur := Index = FPos;
      // The hex digits
      X := HexX(Col);
      S := IntToHex(B, 2);
      if Sel then
      begin
        Canvas.Brush.Style := bsSolid;
        Canvas.Brush.Color := clHighlight;
        Canvas.FillRect(X, Y, X + 2 * FCharW, Y + FLineH);
        Canvas.Font.Color := clHighlightText;
      end
      else Canvas.Font.Color := clWindowText;
      if Cur and not FInText then
      begin
        Canvas.Brush.Style := bsSolid;
        Canvas.Brush.Color := clInactiveCaption;
        if Focused then Canvas.Brush.Color := clHighlight;
        Canvas.FillRect(X + FNibble * FCharW, Y, X + (FNibble + 1) * FCharW, Y + FLineH);
        Canvas.Brush.Style := bsClear;
        Canvas.Font.Color := clHighlightText;
        Canvas.TextOut(X, Y, S[1]);
        Canvas.TextOut(X + FCharW, Y, S[2]);
        if FNibble = 0 then
        begin
          Canvas.Font.Color := clWindowText;
          Canvas.TextOut(X + FCharW, Y, S[2]);
        end
        else
        begin
          Canvas.Font.Color := clWindowText;
          Canvas.TextOut(X, Y, S[1]);
        end;
      end
      else
      begin
        Canvas.Brush.Style := bsClear;
        Canvas.TextOut(X, Y, S);
      end;
      // The character
      X := TextX + Col * FCharW;
      if (B < 32) or (B > 126) then S := '.' else S := Chr(B);
      if Sel then
      begin
        Canvas.Brush.Style := bsSolid;
        Canvas.Brush.Color := clHighlight;
        Canvas.FillRect(X, Y, X + FCharW, Y + FLineH);
        Canvas.Font.Color := clHighlightText;
      end
      else Canvas.Font.Color := clWindowText;
      if Cur and FInText then
      begin
        Canvas.Brush.Style := bsSolid;
        if Focused then Canvas.Brush.Color := clHighlight else Canvas.Brush.Color := clInactiveCaption;
        Canvas.FillRect(X, Y, X + FCharW, Y + FLineH);
        Canvas.Font.Color := clHighlightText;
      end;
      Canvas.Brush.Style := bsClear;
      Canvas.TextOut(X, Y, S);
      // The cursor of the other column, as an outline
      if Cur then
      begin
        Canvas.Brush.Style := bsClear;
        Canvas.Pen.Color := clHighlight;
        if FInText then
          Canvas.Rectangle(HexX(Col) - 1, Y, HexX(Col) + 2 * FCharW + 1, Y + FLineH)
        else
          Canvas.Rectangle(X - 1, Y, X + FCharW + 1, Y + FLineH);
      end;
    end;
  end;
end;

function TCartHexView.ByteAt(X, Y: Integer; out InText: Boolean): Integer;
var
  Row, Col: Integer;
begin
  Row := FTopRow + Y div FLineH;
  InText := X >= TextX - FCharW div 2;
  if InText then Col := (X - TextX) div FCharW
  else
  begin
    Col := 0;
    while (Col < BYTES_PER_ROW - 1) and (X >= HexX(Col + 1) - FCharW div 2) do Inc(Col);
  end;
  Col := Max(0, Min(BYTES_PER_ROW - 1, Col));
  Result := Max(0, Min(FSize - 1, Row * BYTES_PER_ROW + Col));
end;

procedure TCartHexView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  T: Boolean;
  I: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if not Focused then SetFocus;
  if (Button <> mbLeft) or (FSize = 0) then Exit;
  I := ByteAt(X, Y, T);
  FInText := T;
  SetCursor(I, ssShift in Shift);
  FDragging := True;
end;

procedure TCartHexView.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  T: Boolean;
begin
  inherited MouseMove(Shift, X, Y);
  if FDragging and (FSize > 0) then
  begin
    if FSelA < 0 then FSelA := FPos;
    FSelB := ByteAt(X, Y, T);
    FPos := FSelB;
    EnsureVisible;
    Invalidate;
  end;
end;

procedure TCartHexView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if FDragging then
  begin
    FDragging := False;
    // A click without dragging selects nothing
    if HasSel and (FSelA = FSelB) then
    begin
      FSelA := -1;
      FSelB := -1;
      Invalidate;
    end;
    if Assigned(FOnMove) then FOnMove(Self);
  end;
end;

function TCartHexView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  FTopRow := Max(0, Min(FTopRow - (WheelDelta div 120) * 3, Max(0, Rows - 1)));
  UpdateScroll;
  Invalidate;
  Result := True;
end;

procedure TCartHexView.DoEnter;
begin
  inherited DoEnter;
  Invalidate;
end;

procedure TCartHexView.DoExit;
begin
  inherited DoExit;
  Invalidate;
end;

procedure TCartHexView.PutByte(Value: Byte);
begin
  if (FData = nil) or (FPos >= FSize) then Exit;
  if FData[FPos] <> Value then
  begin
    FData[FPos] := Value;
    if Assigned(FOnChange) then FOnChange(Self);
  end;
end;

procedure TCartHexView.KeyDown(var Key: Word; Shift: TShiftState);
var
  Ext: Boolean;
begin
  Ext := ssShift in Shift;
  case Key of
    VK_LEFT: SetCursor(FPos - 1, Ext);
    VK_RIGHT: SetCursor(FPos + 1, Ext);
    VK_UP: SetCursor(FPos - BYTES_PER_ROW, Ext);
    VK_DOWN: SetCursor(FPos + BYTES_PER_ROW, Ext);
    VK_PRIOR: SetCursor(FPos - BYTES_PER_ROW * (VisibleRows - 1), Ext);
    VK_NEXT: SetCursor(FPos + BYTES_PER_ROW * (VisibleRows - 1), Ext);
    VK_HOME: if ssCtrl in Shift then SetCursor(0, Ext) else SetCursor(FPos - FPos mod BYTES_PER_ROW, Ext);
    VK_END: if ssCtrl in Shift then SetCursor(FSize - 1, Ext) else SetCursor(FPos - FPos mod BYTES_PER_ROW + BYTES_PER_ROW - 1, Ext);
    VK_TAB:
      begin
        FInText := not FInText;
        FNibble := 0;
        Invalidate;
      end;
    VK_A: if ssCtrl in Shift then
      begin
        FSelA := 0;
        FSelB := FSize - 1;
        Invalidate;
      end
      else Exit;
  else
    Exit;
  end;
  Key := 0;
end;

procedure TCartHexView.UTF8KeyPress(var UTF8Key: TUTF8Char);
var
  C: Char;
  V: Integer;
begin
  inherited UTF8KeyPress(UTF8Key);
  if (FSize = 0) or (Length(UTF8Key) <> 1) then Exit;
  C := UTF8Key[1];
  if FInText then
  begin
    if (C >= ' ') and (C <= '~') then
    begin
      PutByte(Ord(C));
      SetCursor(FPos + 1, False);
      UTF8Key := '';
    end;
    Exit;
  end;
  V := Pos(UpCase(C), '0123456789ABCDEF') - 1;
  if V < 0 then Exit;
  if FNibble = 0 then
  begin
    PutByte((FData[FPos] and $0F) or (V shl 4));
    FNibble := 1;
    Invalidate;
  end
  else
  begin
    PutByte((FData[FPos] and $F0) or V);
    SetCursor(FPos + 1, False);
  end;
  UTF8Key := '';
end;

{ TCartBrowserWindow }

constructor TCartBrowserWindow.CreateFor(AOwner: TComponent; AEmu: TEmulator);
var
  Panel: TPanel;
begin
  inherited CreateNew(AOwner, 0);
  FEmu := AEmu;
  Caption := _('Cartridge browser');
  FTitle := TPathTitle.Create(Self);
  Width := 760;
  Height := 520;
  Position := poMainFormCenter;
  OnClose := @FormClose;
  OnCloseQuery := @FormCloseQuery;
  KeyPreview := True;
  OnKeyDown := @FormKeyDown;

  FImages := TImageList.Create(Self);
  LoadIcons(FImages);
  FToolBar := TToolBar.Create(Self);
  FToolBar.Parent := Self;
  FToolBar.Images := FImages;
  FToolBar.ShowCaptions := False;
  FToolBar.ShowHint := True;
  FToolBar.ButtonWidth := IconSize + 10;
  FToolBar.ButtonHeight := IconSize + 10;
  FToolBar.AutoSize := True;
  AddButton(ikSave, _('Save the cartridge to its file (Ctrl+S)'), @DoSave);
  AddButton(ikOpen, _('Save the cartridge as another file...'), @DoSaveAs);
  AddSeparator;
  AddButton(ikImportFolder, _('Import a block: write a file of the PC into the cartridge from the cursor...'), @DoImport);
  AddButton(ikFolderUp, _('Export a block: the selected bytes (or the range asked for) to a file of the PC...'), @DoExport);
  AddSeparator;
  AddButton(ikGoTo, _('Go to an offset... (Ctrl+G)'), @DoGoTo);
  AddButton(ikRefresh, _('Read the cartridge again (the changes not saved are lost)'), @DoRefresh);

  FStatus := TStatusBar.Create(Self);
  FStatus.Parent := Self;
  FStatus.SimplePanel := True;

  FPages := TPageControl.Create(Self);
  FPages.Parent := Self;
  FPages.Align := alClient;
  FInfoTab := FPages.AddTabSheet;
  FInfoTab.Caption := _('Info');
  FHexTab := FPages.AddTabSheet;
  FHexTab.Caption := _('Hex');

  FInfo := TMemo.Create(Self);
  FInfo.Parent := FInfoTab;
  FInfo.Align := alClient;
  FInfo.ReadOnly := True;
  FInfo.Font.Name := 'Courier New';
  FInfo.Font.Size := 10;
  FInfo.ScrollBars := ssAutoVertical;

  FScroll := TScrollBar.Create(Self);
  FScroll.Parent := FHexTab;
  FScroll.Kind := sbVertical;
  FScroll.Align := alRight;
  Panel := TPanel.Create(Self);
  Panel.Parent := FHexTab;
  Panel.Align := alClient;
  Panel.BevelOuter := bvNone;
  FHex := TCartHexView.Create(Self);
  FHex.Parent := Panel;
  FHex.Align := alClient;
  FHex.Scroll := FScroll;
  FHex.OnChange := @HexChanged;
  FHex.OnMove := @UpdateStatus;
end;

function TCartBrowserWindow.AddButton(AIcon: TIconKind; const AHint: string; AHandler: TNotifyEvent): TToolButton;
begin
  Result := TToolButton.Create(FToolBar);
  Result.Parent := FToolBar;
  Result.ImageIndex := Ord(AIcon);
  Result.Hint := AHint;
  Result.OnClick := AHandler;
  Result.Left := FToolBar.Width + 1000;
end;

procedure TCartBrowserWindow.AddSeparator;
var
  Sep: TToolButton;
begin
  Sep := TToolButton.Create(FToolBar);
  Sep.Parent := FToolBar;
  Sep.Style := tbsDivider;
  Sep.Left := FToolBar.Width + 1000;
end;

procedure TCartBrowserWindow.UpdateTitle;
var
  Mark: string;
begin
  if FDirty then Mark := ' *' else Mark := '';
  if FFile <> '' then FTitle.SetTitle(_('Cartridge browser - '), FFile, Mark)
  else FTitle.SetTitle(_('Cartridge browser - '), '', Mark);
  if FFile = '' then Caption := _('Cartridge browser') + Mark;
end;

procedure TCartBrowserWindow.UpdateStatus(Sender: TObject);
var
  Txt: string;
begin
  Txt := Format(_('Offset %.6X'), [FHex.Cursor_]);
  if FHex.HasSel then
    Txt := Txt + Format(_('   Selected %.6X-%.6X (%d bytes)'), [FHex.SelFirst, FHex.SelLast, FHex.SelLast - FHex.SelFirst + 1]);
  if FDirty then Txt := Txt + _('   Modified, not saved');
  FStatus.SimpleText := Txt;
end;

procedure TCartBrowserWindow.HexChanged(Sender: TObject);
begin
  FDirty := True;
  UpdateTitle;
  UpdateStatus(nil);
end;

function CartCrc32(P: PByte; N: Integer): LongWord;
var
  I, K: Integer;
  C: LongWord;
begin
  C := $FFFFFFFF;
  for I := 0 to N - 1 do
  begin
    C := C xor P[I];
    for K := 1 to 8 do
      if (C and 1) <> 0 then C := (C shr 1) xor $EDB88320 else C := C shr 1;
  end;
  Result := not C;
end;

procedure TCartBrowserWindow.FillInfo;
var
  Hw: TMsxMachine;
  D: PByte;
  Size, I: Integer;
  Sum: LongWord;
  L: TStringList;

  function Word_(Offset: Integer): Integer;
  begin
    Result := D[Offset] or (D[Offset + 1] shl 8);
  end;

  function Addr(V: Integer): string;
  begin
    if V = 0 then Result := '0000 (none)' else Result := IntToHex(V, 4);
  end;

begin
  L := TStringList.Create;
  try
    FEmu.Lock;
    try
      Hw := FEmu.Spec.MSXHw;
      D := Hw.CartridgeData(1);
      Size := Hw.CartridgeSize(1);
      if D = nil then
        L.Add(_('There is no cartridge in slot 1.'))
      else
      begin
        L.Add('Name:      ' + Hw.CartridgeName(1));
        if FFile <> '' then L.Add('File:      ' + FFile);
        L.Add(Format('Size:      %d bytes (%d KB)', [Size, (Size + 1023) div 1024]));
        L.Add('Mapper:    ' + MapperName(Hw.CartridgeMapper(1)));
        if Hw.CartridgeMapper(1) = mpAscii16 then
          L.Add(Format('Banks:     %d of 16K', [(Size + 16383) div 16384]))
        else if Hw.CartridgeMapper(1) <> mpPlain then
          L.Add(Format('Banks:     %d of 8K', [(Size + 8191) div 8192]))
        else
          L.Add(Format(_('Shown at: %.4Xh-%.4Xh'), [Hw.CartridgeBase(1), Min($FFFF, Hw.CartridgeBase(1) + Size - 1)]));
        L.Add('');
        if (Size >= 16) and (D[0] = Ord('A')) and (D[1] = Ord('B')) then
        begin
          L.Add('Header:    "AB" (a cartridge the BIOS starts)');
          L.Add('INIT:      ' + Addr(Word_(2)) + 'h');
          L.Add('STATEMENT: ' + Addr(Word_(4)) + 'h (CALL statements)');
          L.Add('DEVICE:    ' + Addr(Word_(6)) + 'h');
          L.Add('TEXT:      ' + Addr(Word_(8)) + 'h (a BASIC program)');
        end
        else if (Size >= 2) and (D[0] = Ord('C')) and (D[1] = Ord('D')) then
          L.Add('Header:    "CD" (a ROM that is not started: the BIOS looks for it as a disk ROM)')
        else
          L.Add('Header:    no "AB" at the start: the BIOS will not start this ROM');
        L.Add('');
        Sum := 0;
        for I := 0 to Size - 1 do Sum := (Sum + D[I]) and $FFFFFFFF;
        L.Add(Format('CRC32:     %.8X', [CartCrc32(D, Size)]));
        L.Add(Format('Byte sum:  %.8X', [Sum]));
        if FDirty then
        begin
          L.Add('');
          L.Add(_('The cartridge has been modified and not saved.'));
        end;
      end;
    finally
      FEmu.Unlock;
    end;
    FInfo.Lines.Assign(L);
  finally
    L.Free;
  end;
end;

procedure TCartBrowserWindow.Refresh(const FileName: string);
var
  D: PByte;
  Size: Integer;
begin
  FFile := FileName;
  FDirty := False;
  FEmu.Lock;
  try
    D := FEmu.Spec.MSXHw.CartridgeData(1);
    Size := FEmu.Spec.MSXHw.CartridgeSize(1);
  finally
    FEmu.Unlock;
  end;
  FHex.SetData(D, Size);
  FillInfo;
  UpdateTitle;
  UpdateStatus(nil);
end;

function TCartBrowserWindow.SaveTo(const FileName: string): Boolean;
var
  F: TFileStream;
begin
  Result := False;
  try
    FEmu.Lock;
    try
      F := TFileStream.Create(FileName, fmCreate);
      try
        if FEmu.Spec.MSXHw.CartridgeSize(1) > 0 then
          F.WriteBuffer(FEmu.Spec.MSXHw.CartridgeData(1)^, FEmu.Spec.MSXHw.CartridgeSize(1));
      finally
        F.Free;
      end;
    finally
      FEmu.Unlock;
    end;
    Result := True;
  except
    on E: Exception do
      MessageDlg(_('Could not save ') + ExtractFileName(FileName) + ':' + LineEnding + E.Message, mtError, [mbOK], 0);
  end;
end;

procedure TCartBrowserWindow.DoSave(Sender: TObject);
begin
  if FFile = '' then
  begin
    DoSaveAs(Sender);
    Exit;
  end;
  if SaveTo(FFile) then
  begin
    FDirty := False;
    UpdateTitle;
    UpdateStatus(nil);
    FillInfo;
  end;
end;

procedure TCartBrowserWindow.DoSaveAs(Sender: TObject);
var
  Dlg: TSaveDialog;
begin
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := _F('MSX cartridges (*.rom)|*.rom|All files|*.*');
    Dlg.DefaultExt := 'rom';
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    if FFile <> '' then Dlg.FileName := FFile;
    if Dlg.Execute and SaveTo(Dlg.FileName) then
    begin
      FFile := Dlg.FileName;
      CartFileName := FFile;
      FDirty := False;
      UpdateTitle;
      UpdateStatus(nil);
      FillInfo;
      if Assigned(CartOnSaved) then CartOnSaved(FFile);
    end;
  finally
    Dlg.Free;
  end;
end;

{ A number as hex (with $ or 0x, or just digits as hex) or decimal with a # in front }
function ParseNumber(const S: string; out V: Integer): Boolean;
var
  T: string;
begin
  T := Trim(S);
  if (T <> '') and (T[1] = '#') then V := StrToIntDef(Copy(T, 2, 20), -1)
  else
  begin
    if (Length(T) > 1) and (LowerCase(Copy(T, 1, 2)) = '0x') then T := Copy(T, 3, 20);
    if (T <> '') and (T[1] = '$') then T := Copy(T, 2, 20);
    V := StrToIntDef('$' + T, -1);
  end;
  Result := V >= 0;
end;

procedure TCartBrowserWindow.DoImport(Sender: TObject);
var
  Dlg: TOpenDialog;
  F: TFileStream;
  Txt: string;
  Off, N, Size: Integer;
  D: PByte;
begin
  Size := FHex.FSize;
  if Size = 0 then Exit;
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Options := Dlg.Options + [ofFileMustExist];
    if not Dlg.Execute then Exit;
    Txt := IntToHex(FHex.Cursor_, 6);
    if not InputQuery(_('Import a block'), _('Offset in the cartridge to write at (hex; # for decimal):'), Txt) then Exit;
    if not ParseNumber(Txt, Off) or (Off >= Size) then
    begin
      MessageDlg(_('That is not an offset inside the cartridge (0 to ') + IntToHex(Size - 1, 1) + ').', mtError, [mbOK], 0);
      Exit;
    end;
    F := TFileStream.Create(Dlg.FileName, fmOpenRead or fmShareDenyWrite);
    try
      N := F.Size;
      if Off + N > Size then
      begin
        if MessageDlg(Format(_('The file has %d bytes and only %d fit from that offset (a cartridge keeps its size): ' +
          'write the first %d?'), [N, Size - Off, Size - Off]), mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
        N := Size - Off;
      end;
      FEmu.Lock;
      try
        D := FEmu.Spec.MSXHw.CartridgeData(1);
        if (D <> nil) and (N > 0) then F.ReadBuffer(D[Off], N);
      finally
        FEmu.Unlock;
      end;
    finally
      F.Free;
    end;
    HexChanged(nil);
    FHex.Invalidate;
    FillInfo;
  finally
    Dlg.Free;
  end;
end;

procedure TCartBrowserWindow.DoExport(Sender: TObject);
var
  Dlg: TSaveDialog;
  F: TFileStream;
  Txt: string;
  First, Last, Size, P: Integer;
  Parts: TStringArray;
begin
  Size := FHex.FSize;
  if Size = 0 then Exit;
  if FHex.HasSel then
  begin
    First := FHex.SelFirst;
    Last := FHex.SelLast;
  end
  else
  begin
    Txt := '000000,' + IntToHex(Size, 6);
    if not InputQuery(_('Export a block'), _('No bytes are selected. Offset and length (hex; # for decimal):'), Txt) then Exit;
    Parts := Txt.Split(',');
    if (Length(Parts) <> 2) or not ParseNumber(Parts[0], First) or not ParseNumber(Parts[1], P) or (P < 1) or
       (First >= Size) then
    begin
      MessageDlg(_('Type the offset and the length separated by a comma, like 004000,2000.'), mtError, [mbOK], 0);
      Exit;
    end;
    Last := Min(Size - 1, First + P - 1);
  end;
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := _F('Binary files (*.bin)|*.bin|All files|*.*');
    Dlg.DefaultExt := 'bin';
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    Dlg.FileName := Format('%s_%.6X-%.6X.bin', [ChangeFileExt(ExtractFileName(FFile), ''), First, Last]);
    if not Dlg.Execute then Exit;
    try
      F := TFileStream.Create(Dlg.FileName, fmCreate);
      try
        FEmu.Lock;
        try
          F.WriteBuffer(FEmu.Spec.MSXHw.CartridgeData(1)[First], Last - First + 1);
        finally
          FEmu.Unlock;
        end;
      finally
        F.Free;
      end;
      FStatus.SimpleText := Format(_('Exported %d bytes (%.6X-%.6X) to %s'), [Last - First + 1, First, Last, Dlg.FileName]);
    except
      on E: Exception do
        MessageDlg(_('Could not write the file:') + LineEnding + E.Message, mtError, [mbOK], 0);
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TCartBrowserWindow.DoGoTo(Sender: TObject);
var
  Txt: string;
  V: Integer;
begin
  FPages.ActivePage := FHexTab;
  Txt := IntToHex(FHex.Cursor_, 6);
  if InputQuery(_('Go to'), _('Offset (hex; # for decimal):'), Txt) and ParseNumber(Txt, V) then FHex.GoTo_(V);
end;

procedure TCartBrowserWindow.DoRefresh(Sender: TObject);
var
  Hw: TMsxMachine;
begin
  // The ROM in the slot is the one being edited: only a file can bring back what it was
  if FFile = '' then
  begin
    FillInfo;
    Exit;
  end;
  if FDirty and (MessageDlg(_('Discard the changes and read ') + ExtractFileName(FFile) + ' again?', mtConfirmation,
     [mbYes, mbNo], 0) <> mrYes) then Exit;
  if FileExists(FFile) then
  begin
    FEmu.Lock;
    try
      Hw := FEmu.Spec.MSXHw;
      with TFileStream.Create(FFile, fmOpenRead or fmShareDenyWrite) do
      try
        if (Hw.CartridgeData(1) <> nil) and (Size = Hw.CartridgeSize(1)) then ReadBuffer(Hw.CartridgeData(1)^, Size);
      finally
        Free;
      end;
    finally
      FEmu.Unlock;
    end;
  end;
  Refresh(FFile);
end;

procedure TCartBrowserWindow.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  CloseAction := caHide;
end;

procedure TCartBrowserWindow.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  // The changes live in the running machine: closing the window keeps them, but they are in no file until saved
  CanClose := True;
  if FDirty and Visible then
    case MessageDlg(_('The cartridge has changes that are not saved to a file. Save them?'), mtConfirmation,
         [mbYes, mbNo, mbCancel], 0) of
      mrYes: begin DoSave(nil); CanClose := not FDirty; end;
      mrCancel: CanClose := False;
    end;
end;

procedure TCartBrowserWindow.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_ESCAPE) and (Shift = []) then
  begin
    Key := 0;
    Close;
  end
  else if (Key = VK_S) and (Shift = [ssCtrl]) then
  begin
    Key := 0;
    DoSave(nil);
  end
  else if (Key = VK_G) and (Shift = [ssCtrl]) then
  begin
    Key := 0;
    DoGoTo(nil);
  end;
end;

end.

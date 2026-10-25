{ MainModern.inc: the main window's modern interface (included by
  MainForm.pas). The same window and the same commands as the classic one:
  the menus become buttons on a dark header (each opens a copy of its menu,
  made when it opens, so it is always up to date), the toolbar becomes the
  palettes around the screen (machine, tape, media) and the status bar a
  dark bar below. The debuggers and browsers are the same windows. }

procedure TMainWindow.BuildModern;
const
  MACHINE: array[0..10] of record
    Icon: TIconKind;
    Caption, Hint: string;
  end = (
    (Icon: ikOpen; Caption: 'Open'; Hint: 'Open a tape, snapshot, disk or program (F2)'),
    (Icon: ikSave; Caption: 'Save'; Hint: 'Save snapshot (F3)'),
    (Icon: ikReset; Caption: 'Off/on'; Hint: 'Hard reset: switch the machine off and on (F6)'),
    (Icon: ikRefresh; Caption: 'Reset'; Hint: 'Reset (Shift+F6)'),
    (Icon: ikNMI; Caption: 'NMI'; Hint: 'Non-maskable interrupt (F5)'),
    (Icon: ikPause; Caption: 'Pause'; Hint: 'Pause emulation (F4)'),
    (Icon: ikTurbo; Caption: 'Turbo'; Hint: 'Run as fast as possible (Shift+F11)'),
    (Icon: ikRename; Caption: 'POKE'; Hint: 'POKE (F9)'),
    (Icon: ikDebugger; Caption: 'Debug'; Hint: 'Debugger (F12)'),
    (Icon: ikSettings; Caption: 'Settings'; Hint: 'Settings'),
    (Icon: ikKeyboard; Caption: 'Keyboard'; Hint: 'The keyboard guide: the keywords of the keys'));
var
  I, X, Y, BW, BH, Gap, Pad, W, RowH: Integer;
  Btn: TFlatButton;
  Lbl: TLabel;
  Box: TPaintBox;
  Handlers: array[0..10] of TNotifyEvent;
  Item: TMenuItem;

  function NewButton(AParent: TWinControl; AIcon: Integer; const ACaption, AHint: string;
    AHandler: TNotifyEvent; L, T, W, H: Integer): TFlatButton;
  begin
    Result := TFlatButton.Create(Self);
    Result.Parent := AParent;
    Result.Images := FBigImages;
    Result.ImageIndex := AIcon;
    Result.Caption := ACaption;
    Result.Hint := AHint;
    Result.OnClick := AHandler;
    Result.SetBounds(L, T, W, H);
  end;

begin
  FBigImages := TImageList.Create(Self);
  LoadIcons(FBigImages, MUIScale(24));
  FSmallImages := TImageList.Create(Self);
  LoadIcons(FSmallImages, MUIScale(16));
  FMirror := TPopupMenu.Create(Self);
  DarkMenu(FMirror);
  Gap := MUIScale(6);
  Pad := MUIScale(10);

  // Header: the name, the Spectrum's stripes, the menus, the model
  FMHeader := TDarkPanel.Create(Self);
  FMHeader.Parent := Self;
  FMHeader.Align := alTop;
  FMHeader.Height := MUIScale(40);
  FMHeader.Color := MUI_TITLE;
  Lbl := TLabel.Create(Self);
  Lbl.Parent := FMHeader;
  Lbl.Caption := 'emu80';
  Lbl.Font.Color := MUI_TEXT;
  Lbl.Font.Style := [fsBold];
  Lbl.Font.Height := -MUIScale(17);
  Lbl.Left := MUIScale(14);
  Lbl.Top := (FMHeader.Height - Lbl.Canvas.TextHeight('emu80')) div 2;
  // The four colours as little squares, two above and two below, after the name
  Lbl.Canvas.Font.Assign(Lbl.Font);
  Box := TPaintBox.Create(Self);
  Box.Parent := FMHeader;
  Box.SetBounds(Lbl.Left + Lbl.Canvas.TextWidth(Lbl.Caption) + MUIScale(10), MUIScale(11), MUIScale(18),
    MUIScale(18));
  Box.OnPaint := @PaintStripes;
  X := Box.Left + Box.Width + MUIScale(18);
  for I := 0 to FMenu.Items.Count - 1 do
  begin
    Item := FMenu.Items[I];
    // The Machine menu is the classic interface's: here its commands are buttons
    if Item.Caption = '&Machine' then Continue;
    // The Floppy and SD menus are the Media palette's: a button on each drive and on the card reader
    if (Item = FTapeTop) or (Item = FFloppyTop) or (Item = FSDTop) then Continue;
    if Item.Caption = '|' then
    begin
      Inc(X, MUIScale(10));
      Continue;
    end;
    Btn := NewButton(FMHeader, -1, StripHotKey(Item.Caption), '', @ModernMenuClick, X, MUIScale(7),
      0, MUIScale(26));
    Btn.IconTop := False;
    Btn.Tag := I;
    W := Btn.Canvas.TextWidth(Btn.Caption) + MUIScale(18);
    Btn.Width := W;
    Inc(X, W + MUIScale(3));
  end;
  FMModelBtn := NewButton(FMHeader, Ord(ikModel), '', 'Machine model (click to change)',
    @DoModelButton, 0, MUIScale(7), MUIScale(170), MUIScale(26));
  FMModelBtn.Images := FSmallImages;
  FMModelBtn.IconTop := False;
  FMModelBtn.Anchors := [akTop, akRight];
  FMModelBtn.AnchorSide[akRight].Control := FMHeader;
  FMModelBtn.AnchorSide[akRight].Side := asrRight;
  FMModelBtn.BorderSpacing.Right := MUIScale(12);
  // Left of it: back to the classic interface
  Btn := NewButton(FMHeader, Ord(ikTheme), '', 'Switch to the classic interface', @DoToggleTheme, 0,
    MUIScale(7), MUIScale(30), MUIScale(26));
  Btn.Images := FSmallImages;
  Btn.IconTop := False;
  Btn.Anchors := [akTop, akRight];
  Btn.AnchorSide[akRight].Control := FMModelBtn;
  Btn.AnchorSide[akRight].Side := asrLeft;
  Btn.BorderSpacing.Right := MUIScale(6);

  // Left: the machine palette, big buttons two by two
  FMLeft := TDarkPanel.Create(Self);
  FMLeft.Parent := Self;
  FMLeft.Align := alLeft;
  FMLeft.Width := MUIScale(156);
  FMMachine := TPaletteBox.Create(Self);
  FMMachine.Parent := FMLeft;
  FMMachine.Caption := 'Machine';
  BW := MUIScale(60);
  BH := MUIScale(58);
  FMMachine.SetBounds(Pad, Pad, 2 * BW + 3 * Gap, FMMachine.TitleHeight + Gap + 6 * (BH + Gap));
  Handlers[0] := @DoOpen;
  Handlers[1] := @DoSaveSnapshot;
  Handlers[2] := @DoHardReset;
  Handlers[3] := @DoReset;
  Handlers[4] := @DoNMI;
  Handlers[5] := @DoPause;
  Handlers[6] := @DoTurbo;
  Handlers[7] := @DoPoke;
  Handlers[8] := @DoDebugger;
  Handlers[9] := @DoSettings;
  Handlers[10] := @DoKeyboardGuide;
  for I := 0 to High(MACHINE) do
  begin
    Btn := NewButton(FMMachine, Ord(MACHINE[I].Icon), MACHINE[I].Caption, MACHINE[I].Hint, Handlers[I],
      Gap + (I mod 2) * (BW + Gap), FMMachine.TitleHeight + Gap + (I div 2) * (BH + Gap), BW, BH);
    if I = 5 then FMPause := Btn;
    if I = 6 then FMTurbo := Btn;
    if I = 10 then FMKeyboard := Btn;
  end;

  // Right: the tape and the media
  FMRight := TDarkPanel.Create(Self);
  FMRight.Parent := Self;
  FMRight.Align := alRight;
  FMRight.Width := MUIScale(244);
  W := FMRight.Width - 2 * Pad;
  FMTape := TPaletteBox.Create(Self);
  FMTape.Parent := FMRight;
  FMTape.Caption := 'Tape';
  FMTape.SetBounds(Pad, Pad, W, FMTape.TitleHeight + MUIScale(220));
  Y := FMTape.TitleHeight + Gap;
  FMCassette := TCassette.Create(Self);
  FMCassette.Parent := FMTape;
  FMCassette.SetBounds(Gap, Y, W - 2 * Gap, MUIScale(124));
  FMCassette.Hint := 'Click to insert a tape';
  FMCassette.ShowHint := True;
  FMCassette.OnClick := @DoTapeInsert;
  Inc(Y, MUIScale(124) + Gap);
  FMTapeLabel := TLabel.Create(Self);
  FMTapeLabel.Parent := FMTape;
  FMTapeLabel.Font.Color := MUI_DIM;
  FMTapeLabel.AutoSize := False;
  FMTapeLabel.WordWrap := False;
  // One line, a carousel when it is long (ModernTick)
  FMTapeLabel.SetBounds(Gap, Y - Gap div 2, W - 2 * Gap, MUIScale(18));
  Inc(Y, MUIScale(18) + Gap div 3);
  BW := (W - 6 * Gap) div 5;
  NewButton(FMTape, Ord(ikRewind), '', 'Rewind the tape', @DoTapeRewind, Gap, Y, BW,
    MUIScale(26));
  FMTapePlay := NewButton(FMTape, Ord(ikPlay), '', 'Play/pause tape (F8)', @DoTapePlay, Gap + (BW + Gap), Y, BW,
    MUIScale(26));
  NewButton(FMTape, Ord(ikStop), '', 'Stop tape (Shift+F8)', @DoTapeStop, Gap + 2 * (BW + Gap), Y, BW,
    MUIScale(26));
  FMRec := NewButton(FMTape, Ord(ikRecord), '', 'Record onto the tape (REC)', @DoTapeRecord,
    Gap + 3 * (BW + Gap), Y, BW, MUIScale(26));
  // In the place left, the Tape menu, with a button like those of the drives
  Btn := NewButton(FMTape, Ord(ikMenu), '', 'Tape menu', @ModernMenuClick, Gap + 4 * (BW + Gap), Y, BW,
    MUIScale(26));
  Btn.Images := FSmallImages;
  Btn.IconTop := False;
  Btn.Tag := FTapeTop.MenuIndex;
  Inc(Y, MUIScale(26) + Gap);
  BW := (W - 3 * Gap) div 2;
  Btn := NewButton(FMTape, Ord(ikTape), 'Browser', 'Tape browser (F7)', @DoTapeBrowser, Gap, Y, BW,
    MUIScale(30));
  Btn.Images := FSmallImages;
  Btn.IconTop := False;
  FMFast := NewButton(FMTape, -1, 'Fast', 'Fast loading: the ROM loader is skipped and blocks ' +
    'load at once', @DoFastLoad, 2 * Gap + BW, Y, BW, MUIScale(30));
  FMFast.IconTop := False;
  Inc(Y, MUIScale(30) + Gap);
  FMTape.Height := Y + Gap div 2;

  FMMedia := TPaletteBox.Create(Self);
  FMMedia.Parent := FMRight;
  FMMedia.Caption := 'Media';
  // The LEDs and what is in each drive above; below them three buttons: the
  // disk and SD card browsers, and fast floppy disk access
  // Two drives and an SD card reader drawn in a row each, with what is in them and a button to insert something;
  // below them three buttons: the disk and SD card browsers, and fast floppy disk access
  RowH := MUIScale(34);
  FMMedia.SetBounds(Pad, FMTape.Top + FMTape.Height + Pad, W, FMMedia.TitleHeight + 3 * RowH + MUIScale(60));
  BW := MUIScale(30);
  FMMediaBox := TPaintBox.Create(Self);
  FMMediaBox.Parent := FMMedia;
  FMMediaBox.SetBounds(Gap, FMMedia.TitleHeight + Gap, W - 3 * Gap - BW, 3 * RowH);
  FMMediaBox.OnPaint := @PaintModernMedia;
  // Clicking a drive (or the card reader) inserts something in it; its button opens its menu
  FMMediaBox.OnMouseUp := @ModernMediaClick;
  FMMediaBox.Cursor := crHandPoint;
  FMMediaBox.ShowHint := True;
  FMMediaBox.Hint := 'Click a drive or the card reader to insert a disk or an SD card image';
  for I := 0 to 2 do
  begin
    if I < 2 then
      FMMenuBtn[I] := NewButton(FMMedia, Ord(ikMenu), '', Format('Floppy menu (drive %s:)', [Chr(Ord('A') + I)]),
        @ModernMenuClick, W - Gap - BW, FMMedia.TitleHeight + Gap + I * RowH + (RowH - MUIScale(26)) div 2, BW, MUIScale(26))
    else
      FMMenuBtn[I] := NewButton(FMMedia, Ord(ikMenu), '', 'SD menu', @ModernMenuClick,
        W - Gap - BW, FMMedia.TitleHeight + Gap + I * RowH + (RowH - MUIScale(26)) div 2, BW, MUIScale(26));
    if I < 2 then FMMenuBtn[I].Tag := FFloppyTop.MenuIndex else FMMenuBtn[I].Tag := FSDTop.MenuIndex;
    FMMenuBtn[I].Images := FSmallImages;
    FMMenuBtn[I].IconTop := False;
  end;
  Y := FMMedia.TitleHeight + 2 * Gap + 3 * RowH;
  BW := (W - 4 * Gap) div 3;
  FMDiskBtn := NewButton(FMMedia, Ord(ikDisk), 'Disks', 'Disk browser', @DoDiskBrowser, Gap, Y, BW, MUIScale(32));
  FMDiskBtn.Images := FSmallImages;
  FMDiskBtn.IconTop := False;
  FMSDBtn := NewButton(FMMedia, Ord(ikSDCard), 'SD', 'SD card browser', @DoSDBrowser, 2 * Gap + BW, Y, BW,
    MUIScale(32));
  FMSDBtn.Images := FSmallImages;
  FMSDBtn.IconTop := False;
  FMFastDisk := NewButton(FMMedia, -1, 'Fast', 'Fast floppy disk access: no real drive timing',
    @DoFastDisk, 3 * Gap + 2 * BW, Y, BW, MUIScale(32));
  FMFastDisk.IconTop := False;
  FMMedia.Height := Y + MUIScale(32) + Gap;

  // Bottom: zoom, and what the status bar says
  FMBottom := TDarkPanel.Create(Self);
  FMBottom.Parent := Self;
  FMBottom.Align := alBottom;
  FMBottom.Height := MUIScale(36);
  FMBottom.Color := MUI_TITLE;
  Lbl := TLabel.Create(Self);
  Lbl.Parent := FMBottom;
  Lbl.Caption := 'Zoom';
  Lbl.Font.Color := MUI_DIM;
  Lbl.Left := MUIScale(14);
  Lbl.Top := (FMBottom.Height - Lbl.Canvas.TextHeight('Zoom')) div 2;
  for I := 1 to 4 do
  begin
    FMZoom[I] := NewButton(FMBottom, -1, Format('%dx', [I]), Format('Zoom %dx', [I]), @DoScale,
      MUIScale(56) + (I - 1) * MUIScale(40), MUIScale(6), MUIScale(36), MUIScale(24));
    FMZoom[I].IconTop := False;
    FMZoom[I].Tag := I;
  end;
  FMStatusBox := TPaintBox.Create(Self);
  FMStatusBox.Parent := FMBottom;
  FMStatusBox.Left := MUIScale(56) + 4 * MUIScale(40) + MUIScale(16);
  FMStatusBox.Top := 0;
  FMStatusBox.Height := FMBottom.Height;
  FMStatusBox.Anchors := [akLeft, akTop, akRight, akBottom];
  FMStatusBox.AnchorSide[akRight].Control := FMBottom;
  FMStatusBox.AnchorSide[akRight].Side := asrRight;
  FMStatusBox.OnPaint := @PaintModernStatus;

  // The least height the palettes need (the screen may be smaller), and
  // the width the header's menus and model need
  FModernMinHeight := FMHeader.Height + FMBottom.Height + FMMedia.Top + FMMedia.Height + Pad;
  FModernMinWidth := X + FMModelBtn.Width + MUIScale(72);
end;

{ The style in use: the classic menus, toolbar and status bar, or the
  modern header, palettes and bar }
procedure TMainWindow.ApplyStyle;
begin
  FModern := Settings.ModernUI;
  DisableAlign;
  try
    if FModern then Menu := nil else Menu := FMenu;
    FToolBar.Visible := not FModern;
    FStatus.Visible := not FModern;
    FMHeader.Visible := FModern;
    FMLeft.Visible := FModern;
    FMRight.Visible := FModern;
    FMBottom.Visible := FModern;
    if FModern then
    begin
      Color := MUI_BACK;
      FDisplay.BorderSpacing.Around := MUIScale(12);
    end
    else
    begin
      Color := clDefault;
      FDisplay.BorderSpacing.Around := 0;
    end;
  finally
    EnableAlign;
  end;
  ModernTick;
  SetDarkTitle(Self, FModern);
  // The other windows (debuggers, browsers, settings...) dark too, or back
  DarkTheme := FModern;
  ThemeAllForms;
  FDisplay.Invalidate;
end;

procedure TMainWindow.PaintStripes(Sender: TObject);
const
  COLOURS: array[0..3] of TColor = ($003D26D7, $005ED3F4, $0073B23B, $00FF901E);
var
  B: TPaintBox;
  I, Q, Gap: Integer;
begin
  B := Sender as TPaintBox;
  B.Canvas.Brush.Color := MUI_TITLE;
  B.Canvas.FillRect(0, 0, B.Width, B.Height);
  // Four squares: red and yellow above, green and cyan below
  Gap := MUIScale(2);
  Q := (B.Width - Gap) div 2;
  for I := 0 to 3 do
  begin
    B.Canvas.Brush.Color := COLOURS[I];
    B.Canvas.FillRect((I mod 2) * (Q + Gap), (I div 2) * (Q + Gap), (I mod 2) * (Q + Gap) + Q,
      (I div 2) * (Q + Gap) + Q);
  end;
end;

{ A header button: a copy of its menu, made now, below it }
procedure TMainWindow.ModernMenuClick(Sender: TObject);
var
  Btn: TFlatButton;
  P: TPoint;
begin
  Btn := Sender as TFlatButton;
  UpdateInstallNextItem(nil);
  FMirror.Items.Clear;
  MirrorItems(FMenu.Items[Btn.Tag], FMirror.Items);
  P := Btn.ClientToScreen(Point(0, Btn.Height));
  FMirror.Alignment := paLeft;
  FMirror.PopUp(P.X, P.Y);
end;

procedure TMainWindow.MirrorItems(Src, Dst: TMenuItem);
var
  I: Integer;
  S, N: TMenuItem;
begin
  for I := 0 to Src.Count - 1 do
  begin
    S := Src[I];
    // What the modern interface has as buttons is not in its menus; no separator is left first, last or doubled
    if FModernHide.IndexOf(S) >= 0 then Continue;
    if (S.Caption = '-') and ((Dst.Count = 0) or (Dst[Dst.Count - 1].Caption = '-')) then Continue;
    N := TMenuItem.Create(FMirror);
    N.Caption := S.Caption;
    N.ShortCut := S.ShortCut;
    N.Checked := S.Checked;
    N.RadioItem := S.RadioItem;
    N.Enabled := S.Enabled;
    N.Visible := S.Visible;
    N.Hint := S.Hint;
    N.Tag := PtrInt(S);
    if S.Count > 0 then MirrorItems(S, N)
    else if S.Caption <> '-' then N.OnClick := @MirrorClick;
    Dst.Add(N);
  end;
  if (Dst.Count > 0) and (Dst[Dst.Count - 1].Caption = '-') then Dst.Delete(Dst.Count - 1);
end;

procedure TMainWindow.MirrorClick(Sender: TObject);
begin
  // The menu's own entry does it
  TMenuItem(PtrInt((Sender as TMenuItem).Tag)).Click;
end;

{ Without the menu bar, its shortcuts (F2, F9...) are found here }
function TMainWindow.MenuShortcut(Key: Word; Shift: TShiftState): Boolean;
var
  Wanted: TShortCut;

  function Find(Item: TMenuItem): Boolean;
  var
    I: Integer;
  begin
    Result := False;
    for I := 0 to Item.Count - 1 do
    begin
      if not Item[I].Enabled or not Item[I].Visible then Continue;
      if (Item[I].Count = 0) and (Item[I].ShortCut = Wanted) and Assigned(Item[I].OnClick) then
      begin
        Item[I].Click;
        Exit(True);
      end;
      if Find(Item[I]) then Exit(True);
    end;
  end;

begin
  Wanted := ShortCut(Key, Shift * [ssShift, ssCtrl, ssAlt]);
  Result := (Wanted <> 0) and Find(FMenu.Items);
end;

{ The text of a name or message that may be longer than its room: the whole of it if it fits, else its start, and
  every so often it scrolls to the end and back (the carousel) }
function TMainWindow.MarqueeText(Index: Integer; const Full: string; C: TCanvas; Room: Integer): string;
begin
  if FMarquee[Index].Full <> Full then
  begin
    FMarquee[Index].Full := Full;
    FMarquee[Index].Offset := 0;
    FMarquee[Index].Pause := 12;       // 3 seconds before it first moves
  end;
  Result := Full;
  if C.TextWidth(Full) <= Room then
  begin
    FMarquee[Index].Offset := 0;
    Exit;
  end;
  with FMarquee[Index] do
  begin
    if Pause > 0 then
      Dec(Pause)
    else if C.TextWidth(Copy(Full, Offset + 1, MaxInt)) > Room then
      Inc(Offset)                      // a character a tick
    else
    begin
      // At the end: a moment, then to the start and a long wait
      Offset := 0;
      Pause := 40;
    end;
    Result := Copy(Full, Offset + 1, MaxInt);
  end;
end;

procedure TMainWindow.PaintModernMedia(Sender: TObject);
const
  NAMES: array[0..2] of string = ('A:', 'B:', 'SD');
var
  C: TCanvas;
  I, Y, RowH, Led, LedH, X0, DW, TX, TW: Integer;
  Has: Boolean;
  Dim: Boolean;

  { A colour, darker when the drive isn't there }
  function Cl(R, G, B: Integer): TColor;
  begin
    if Dim then Result := RGBToColor(R * 45 div 100, G * 45 div 100, B * 45 div 100)
    else Result := RGBToColor(R, G, B);
  end;

  { A 3.5" drive seen from the front: its body, the slot and, with a disk in, the disk coming out of the slot }
  procedure DrawDrive(X, Top, Wd, Ht: Integer; Disk: Boolean);
  var
    SlotY, SH, SX, SW, ST: Integer;
  begin
    C.Pen.Color := Cl(120, 120, 128);
    C.Brush.Color := Cl(68, 68, 74);
    C.RoundRect(X, Top, X + Wd, Top + Ht, MUIScale(5), MUIScale(5));
    SlotY := Top + Ht - MUIScale(8);
    if Disk then
    begin
      // A 3" disk goes in edge first, so what shows is its spine: a black edge, the label that wraps round
      // it (light, with a line of writing) and another black edge
      SH := MUIScale(12);
      SX := X + MUIScale(6);
      SW := Wd - MUIScale(14);
      ST := SlotY + MUIScale(2) - SH;
      C.Pen.Color := clBlack;
      C.Brush.Color := Cl(18, 18, 20);
      C.Rectangle(SX, ST, SX + SW, ST + SH);
      C.Pen.Color := Cl(150, 150, 140);
      C.Brush.Color := Cl(214, 211, 198);
      C.Rectangle(SX + 1, ST + MUIScale(3), SX + SW - 1, ST + SH - MUIScale(3));
      C.Pen.Color := Cl(70, 70, 70);
      C.MoveTo(SX + MUIScale(4), ST + SH div 2);
      C.LineTo(SX + SW - MUIScale(10), ST + SH div 2);
      C.Pen.Color := Cl(150, 40, 40);
      C.MoveTo(SX + SW - MUIScale(8), ST + SH div 2);
      C.LineTo(SX + SW - MUIScale(3), ST + SH div 2);
    end;
    // The slot, over the disk's lower edge
    C.Pen.Color := clBlack;
    C.Brush.Color := Cl(8, 8, 10);
    C.Rectangle(X + MUIScale(4), SlotY, X + Wd - MUIScale(6), SlotY + MUIScale(4));
    // The drive's button
    C.Pen.Color := Cl(150, 150, 156);
    C.Brush.Color := Cl(96, 96, 104);
    C.Rectangle(X + Wd - MUIScale(5), SlotY - MUIScale(1), X + Wd - MUIScale(1), SlotY + MUIScale(5));
  end;

  { An SD card reader: its slot and, with a card in, a thick card with the cut corner and the contacts }
  procedure DrawSD(X, Top, Wd, Ht: Integer; Card: Boolean);
  var
    CW, CH, CX, SlotY: Integer;
  begin
    C.Pen.Color := Cl(120, 120, 128);
    C.Brush.Color := Cl(68, 68, 74);
    C.RoundRect(X, Top, X + Wd, Top + Ht, MUIScale(5), MUIScale(5));
    SlotY := Top + Ht - MUIScale(6);
    if Card then
    begin
      // A card in a real reader sticks out of it by a little: its end, a bit narrower than the slot, with the
      // cut corner
      CW := Wd - MUIScale(22);
      CX := X + MUIScale(11);
      CH := MUIScale(7);
      C.Pen.Color := Cl(8, 20, 70);
      C.Brush.Color := Cl(30, 70, 170);
      C.Polygon([Point(CX, SlotY - CH), Point(CX + CW - MUIScale(5), SlotY - CH),
        Point(CX + CW, SlotY - CH + MUIScale(5)), Point(CX + CW, SlotY + MUIScale(2)), Point(CX, SlotY + MUIScale(2))]);
      // Its label's edge
      C.Pen.Color := Cl(200, 205, 230);
      C.Brush.Color := Cl(236, 238, 248);
      C.Rectangle(CX + MUIScale(4), SlotY - CH + MUIScale(3), CX + CW - MUIScale(9), SlotY);
    end;
    // The slot (narrow, as the card is)
    C.Pen.Color := clBlack;
    C.Brush.Color := Cl(8, 8, 10);
    C.Rectangle(X + MUIScale(8), SlotY, X + Wd - MUIScale(8), SlotY + MUIScale(4));
  end;

begin
  C := FMMediaBox.Canvas;
  C.Brush.Color := MUI_PANEL;
  C.FillRect(0, 0, FMMediaBox.Width, FMMediaBox.Height);
  C.Font.Assign(Font);
  RowH := FMMediaBox.Height div 3;
  Led := MUIScale(14);
  LedH := MUIScale(7);
  X0 := Led + MUIScale(30);
  DW := MUIScale(52);
  TX := X0 + DW + MUIScale(8);
  TW := FMMediaBox.Width - TX;
  for I := 0 to 2 do
  begin
    Y := I * RowH + (RowH - LedH) div 2;
    // The drive's LED: light red while it is read or written
    C.Pen.Color := $00202020;
    if (FMediaState and ($10 shl I)) <> 0 then C.Brush.Color := RGBToColor(255, 92, 92)
    else C.Brush.Color := RGBToColor(107, 34, 34);
    C.Rectangle(0, Y, Led, Y + LedH);
    C.Brush.Style := bsClear;
    C.Font.Color := MUI_TEXT;
    C.Font.Style := [fsBold];
    C.TextOut(Led + MUIScale(6), I * RowH + (RowH - C.TextHeight('A')) div 2, NAMES[I]);
    C.Font.Style := [];
    C.Brush.Style := bsSolid;
    Has := FMediaNames[I] <> '';
    Dim := not FMediaOn[I];
    if I < 2 then DrawDrive(X0, I * RowH + MUIScale(4), DW, RowH - MUIScale(8), Has)
    else DrawSD(X0, I * RowH + MUIScale(4), DW, RowH - MUIScale(8), Has);
    // What is in it (a carousel if it is long)
    C.Brush.Style := bsClear;
    if Has then C.Font.Color := MUI_DIM else C.Font.Color := $00808080;
    if Has then C.TextOut(TX, I * RowH + (RowH - C.TextHeight('A')) div 2, FMediaShown[I])
    else if Dim then C.TextOut(TX, I * RowH + (RowH - C.TextHeight('A')) div 2, 'not available')
    else C.TextOut(TX, I * RowH + (RowH - C.TextHeight('A')) div 2, 'empty');
    C.Brush.Style := bsSolid;
  end;
end;

{ A click on a drive or on the card reader inserts a disk or an SD card image in it }
procedure TMainWindow.ModernMediaClick(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Row: Integer;
begin
  if Button <> mbLeft then Exit;
  Row := Y div (FMMediaBox.Height div 3);
  if (Row < 0) or (Row > 2) or not FMediaOn[Row] then Exit;
  if Row < 2 then InsertDiskDialog(Row) else DoSDInsert(Sender);
end;

procedure TMainWindow.PaintModernStatus(Sender: TObject);
var
  C: TCanvas;
  Line: string;
begin
  C := FMStatusBox.Canvas;
  C.Brush.Color := MUI_TITLE;
  C.FillRect(0, 0, FMStatusBox.Width, FMStatusBox.Height);
  C.Font.Assign(Font);
  C.Font.Color := MUI_DIM;
  C.Brush.Style := bsClear;
  // The same as the classic status bar: model, speed, tape (or a message)
  Line := FStatus.Panels[0].Text + '    ' + FStatus.Panels[1].Text + '    ' + FStatus.Panels[2].Text;
  C.TextOut(0, (FMStatusBox.Height - C.TextHeight('A')) div 2, Line);
  C.Brush.Style := bsSolid;
end;

{ What the palettes show, from the machine: called with the status bar's
  timer }
procedure TMainWindow.ModernTick;
var
  Spec: TSpectrum;
  TapeText, TapeName: string;
  Progress: Double;
  Playing, HaveDisk, HaveCard, HaveTape, HaveKeys: Boolean;
  Names: array[0..2] of string;
  On_: array[0..2] of Boolean;
  I: Integer;
  Shown: string;
  AnyChange: Boolean;
begin
  if not FModern or (FMHeader = nil) then Exit;
  FEmu.Lock;
  try
    Spec := FEmu.Spec;
    HaveTape := Spec.Tape.Count > 0;
    if Spec.Tape.Count = 0 then
    begin
      TapeText := 'No tape';
      Progress := 0;
    end
    else
    begin
      TapeText := Format('Block %d of %d - %s', [Min(Spec.Tape.Current + 1, Spec.Tape.Count), Spec.Tape.Count,
        Spec.TapeStateText]);
      if Spec.Tape.Current < Spec.Tape.Count then
        TapeText := TapeText + ' - ' + Spec.Tape[Spec.Tape.Current].Description
      else
        TapeText := 'End of the tape';
      if Spec.Tape.FileName <> '' then TapeText := ExtractFileName(Spec.Tape.FileName) + ' - ' + TapeText;
      TapeText := StringReplace(TapeText, LineEnding, ' ', [rfReplaceAll]);
      Progress := Spec.Tape.Progress;
    end;
    Playing := Spec.Tape.Playing;
    TapeName := ChangeFileExt(ExtractFileName(Spec.Tape.FileName), '');
    HaveDisk := DefaultDrive(Spec) >= 0;
    HaveCard := Spec.DivMMCOn and (Spec.DivMMC.Card <> nil);
    On_[0] := FloppyAvailable;
    On_[1] := FloppyAvailable and Spec.DriveBOn;
    On_[2] := SDAvailable;
    for I := 0 to 1 do
      if On_[I] and (Spec.DiskAt(I) <> nil) then
      begin
        Names[I] := ExtractFileName(Spec.DiskAt(I).FileName);
        if Names[I] = '' then Names[I] := '(new disk)';
      end
      else
        Names[I] := '';
    if HaveCard and On_[2] then Names[2] := ExtractFileName(Spec.DivMMC.Card.FileName) else Names[2] := '';
  finally
    FEmu.Unlock;
  end;
  FMTapeLabel.Canvas.Font.Assign(FMTapeLabel.Font);
  TapeText := MarqueeText(3, TapeText, FMTapeLabel.Canvas, FMTapeLabel.Width);
  if FMTapeLabel.Caption <> TapeText then FMTapeLabel.Caption := TapeText;
  if FMCassette.Caption <> TapeName then FMCassette.Caption := TapeName;
  FMCassette.Loaded := HaveTape;
  FMCassette.Show(Progress, Playing);
  if FMDiskBtn.Enabled <> HaveDisk then FMDiskBtn.Enabled := HaveDisk;
  if FMSDBtn.Enabled <> HaveCard then FMSDBtn.Enabled := HaveCard;
  // The names of what is in the drives, as much as fits (they scroll now and then when it doesn't)
  FMMediaBox.Canvas.Font.Assign(Font);
  AnyChange := False;
  for I := 0 to 2 do
  begin
    FMediaNames[I] := Names[I];
    Shown := MarqueeText(I, Names[I], FMMediaBox.Canvas,
      FMMediaBox.Width - (MUIScale(14) + MUIScale(30) + MUIScale(52) + MUIScale(8)));
    if Shown <> FMediaShown[I] then
    begin
      FMediaShown[I] := Shown;
      AnyChange := True;
    end;
    // The drives and the card reader the machine has (the B: drive too if it is connected)
    if FMMenuBtn[I].Enabled <> On_[I] then FMMenuBtn[I].Enabled := On_[I];
    if FMediaOn[I] <> On_[I] then
    begin
      FMediaOn[I] := On_[I];
      AnyChange := True;
    end;
  end;
  if AnyChange then FMMediaBox.Invalidate;
  FMModelBtn.Caption := ModelInfo[FEmu.Spec.Model].Name;
  // The keyboard guide, under Settings, on every Spectrum, not the CPC or the SAM Coupe (the palette is one row shorter without it)
  HaveKeys := FEmu.Spec.Model in [sm16K..smZXNext];
  if FMKeyboard.Visible <> HaveKeys then
  begin
    FMKeyboard.Visible := HaveKeys;
    FMMachine.Height := FMMachine.TitleHeight + MUIScale(6) + (5 + Ord(HaveKeys)) * (MUIScale(58) + MUIScale(6));
  end;
  // The Play button shows a pause while the tape plays
  if Playing and (FMTapePlay.ImageIndex <> Ord(ikPause)) then
  begin
    FMTapePlay.ImageIndex := Ord(ikPause);
    FMTapePlay.Invalidate;
  end
  else if not Playing and (FMTapePlay.ImageIndex <> Ord(ikPlay)) then
  begin
    FMTapePlay.ImageIndex := Ord(ikPlay);
    FMTapePlay.Invalidate;
  end;
  FMPause.Down := FEmu.Paused;
  FMTurbo.Down := FEmu.Turbo;
  FMRec.Down := FEmu.Spec.Recording;
  FMFast.Down := Settings.FastLoad;
  FMFastDisk.Down := Settings.FastDisk;
  for I := 1 to 4 do
  begin
    FMZoom[I].Down := I = Settings.Scale;
    // Too big for the screen: not shown
    FMZoom[I].Visible := (I = 1) or ScaleFits(I);
  end;
  FMStatusBox.Invalidate;
end;

{ The first start: a note for 5 seconds (it can't be closed) that this is
  the modern interface and which button changes to the classic one }
procedure TMainWindow.ShowNotice;
begin
end;

procedure TMainWindow.NoticeEnd(Sender: TObject);
begin
  // The timer stays (this may be its own event), stopped
  if FNoticeTimer <> nil then FNoticeTimer.Enabled := False;
  FreeAndNil(FNotice);
end;

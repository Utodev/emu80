{ MainModern.inc: the main window's modern interface (included by
  MainForm.pas). The same window and the same commands as the classic one:
  the menus become buttons on a dark header (each opens a copy of its menu,
  made when it opens, so it is always up to date), the toolbar becomes the
  palettes around the screen (machine, tape, media) and the status bar a
  dark bar below. The debuggers and browsers are the same windows. }

procedure TMainWindow.BuildModern;
const
  MACHINE: array[0..9] of record
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
    (Icon: ikSettings; Caption: 'Settings'; Hint: 'Settings'));
var
  I, X, Y, BW, BH, Gap, Pad, W, RowH: Integer;
  Btn: TFlatButton;
  Lbl: TLabel;
  Box: TPaintBox;
  Handlers: array[0..9] of TNotifyEvent;
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
  Lbl.Caption := 'pzx';
  Lbl.Font.Color := MUI_TEXT;
  Lbl.Font.Style := [fsBold];
  Lbl.Font.Height := -MUIScale(17);
  Lbl.Left := MUIScale(14);
  Lbl.Top := (FMHeader.Height - Lbl.Canvas.TextHeight('pzx')) div 2;
  Box := TPaintBox.Create(Self);
  Box.Parent := FMHeader;
  Box.SetBounds(MUIScale(52), MUIScale(11), MUIScale(44), MUIScale(18));
  Box.OnPaint := @PaintStripes;
  X := MUIScale(108);
  for I := 0 to FMenu.Items.Count - 1 do
  begin
    Item := FMenu.Items[I];
    // The Machine menu is the classic interface's: here its commands are buttons
    if Item.Caption = '&Machine' then Continue;
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
  FMMachine.SetBounds(Pad, Pad, 2 * BW + 3 * Gap, FMMachine.TitleHeight + Gap + 5 * (BH + Gap));
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
  for I := 0 to High(MACHINE) do
  begin
    Btn := NewButton(FMMachine, Ord(MACHINE[I].Icon), MACHINE[I].Caption, MACHINE[I].Hint, Handlers[I],
      Gap + (I mod 2) * (BW + Gap), FMMachine.TitleHeight + Gap + (I div 2) * (BH + Gap), BW, BH);
    if I = 5 then FMPause := Btn;
    if I = 6 then FMTurbo := Btn;
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
  FMTape.SetBounds(Pad, Pad, W, FMTape.TitleHeight + MUIScale(274));
  Y := FMTape.TitleHeight + Gap;
  FMCassette := TCassette.Create(Self);
  FMCassette.Parent := FMTape;
  FMCassette.SetBounds(Gap, Y, W - 2 * Gap, MUIScale(124));
  FMCassette.Hint := 'Tape browser (F7)';
  FMCassette.ShowHint := True;
  FMCassette.OnClick := @DoTapeBrowser;
  Inc(Y, MUIScale(124) + Gap);
  FMTapeLabel := TLabel.Create(Self);
  FMTapeLabel.Parent := FMTape;
  FMTapeLabel.Font.Color := MUI_DIM;
  FMTapeLabel.AutoSize := False;
  FMTapeLabel.WordWrap := True;
  FMTapeLabel.SetBounds(Gap, Y, W - 2 * Gap, MUIScale(32));
  Inc(Y, MUIScale(32) + Gap);
  BW := (W - 6 * Gap) div 5;
  NewButton(FMTape, Ord(ikEject), '', 'Eject: insert a tape (.tap)', @DoTapeInsert, Gap, Y, BW,
    MUIScale(38));
  NewButton(FMTape, Ord(ikRewind), '', 'Rewind the tape', @DoTapeRewind, Gap + (BW + Gap), Y, BW,
    MUIScale(38));
  FMTapePlay := NewButton(FMTape, Ord(ikPlay), '', 'Play/pause tape (F8)', @DoTapePlay, Gap + 2 * (BW + Gap), Y, BW,
    MUIScale(38));
  NewButton(FMTape, Ord(ikStop), '', 'Stop tape (Shift+F8)', @DoTapeStop, Gap + 3 * (BW + Gap), Y, BW,
    MUIScale(38));
  FMRec := NewButton(FMTape, Ord(ikRecord), '', 'Record onto the tape (REC)', @DoTapeRecord,
    Gap + 4 * (BW + Gap), Y, BW, MUIScale(38));
  Inc(Y, MUIScale(38) + Gap);
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
  FMMedia.SetBounds(Pad, FMTape.Top + FMTape.Height + Pad, W, FMMedia.TitleHeight + MUIScale(126));
  FMMediaBox := TPaintBox.Create(Self);
  FMMediaBox.Parent := FMMedia;
  FMMediaBox.SetBounds(Gap, FMMedia.TitleHeight + Gap, W - 2 * Gap, MUIScale(72));
  FMMediaBox.OnPaint := @PaintModernMedia;
  BW := (W - 4 * Gap) div 3;
  FMDiskBtn := NewButton(FMMedia, Ord(ikDisk), 'Disks', 'Disk browser', @DoDiskBrowser, Gap,
    FMMedia.TitleHeight + MUIScale(80), BW, MUIScale(32));
  FMDiskBtn.Images := FSmallImages;
  FMDiskBtn.IconTop := False;
  FMSDBtn := NewButton(FMMedia, Ord(ikSDCard), 'SD', 'SD card browser', @DoSDBrowser, 2 * Gap + BW,
    FMMedia.TitleHeight + MUIScale(80), BW, MUIScale(32));
  FMSDBtn.Images := FSmallImages;
  FMSDBtn.IconTop := False;
  FMFastDisk := NewButton(FMMedia, -1, 'Fast', 'Fast floppy disk access: no real drive timing',
    @DoFastDisk, 3 * Gap + 2 * BW, FMMedia.TitleHeight + MUIScale(80), BW, MUIScale(32));
  FMFastDisk.IconTop := False;

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
  I, W: Integer;
begin
  B := Sender as TPaintBox;
  W := B.Width div 4;
  B.Canvas.Brush.Color := MUI_TITLE;
  B.Canvas.FillRect(0, 0, B.Width, B.Height);
  for I := 0 to 3 do
  begin
    // A slanted stripe each, as on the 128K's case
    B.Canvas.Brush.Color := COLOURS[I];
    B.Canvas.Pen.Color := COLOURS[I];
    B.Canvas.Polygon([Point(I * W + W div 2, 0), Point(I * W + W, 0), Point(I * W + W div 2, B.Height),
      Point(I * W, B.Height)]);
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

procedure TMainWindow.PaintModernMedia(Sender: TObject);
const
  NAMES: array[0..2] of string = ('A:', 'B:', 'SD');
var
  C: TCanvas;
  I, Y, RowH, Led, Room: Integer;
  Shown: string;
begin
  C := FMMediaBox.Canvas;
  C.Brush.Color := MUI_PANEL;
  C.FillRect(0, 0, FMMediaBox.Width, FMMediaBox.Height);
  C.Font.Assign(Font);
  RowH := FMMediaBox.Height div 3;
  Led := MUIScale(10);
  Room := FMMediaBox.Width;
  for I := 0 to 2 do
  begin
    Y := I * RowH + (RowH - Led) div 2;
    // The drive's LED: light red while it is read or written
    C.Pen.Color := $00202020;
    if (FMediaState and ($10 shl I)) <> 0 then C.Brush.Color := RGBToColor(255, 92, 92)
    else C.Brush.Color := RGBToColor(107, 34, 34);
    C.Ellipse(0, Y, Led, Y + Led);
    C.Brush.Style := bsClear;
    C.Font.Color := MUI_TEXT;
    C.Font.Style := [fsBold];
    C.TextOut(Led + MUIScale(8), I * RowH + (RowH - C.TextHeight('A')) div 2, NAMES[I]);
    C.Font.Style := [];
    if FMediaNames[I] <> '' then C.Font.Color := MUI_DIM else C.Font.Color := $00808080;
    // The name of what is in it, cut short (with ...) to the room there is
    if FMediaNames[I] <> '' then Shown := FMediaNames[I] else Shown := '-';
    while (Length(Shown) > 4) and (Led + MUIScale(36) + C.TextWidth(Shown) > Room) do
      Shown := Copy(Shown, 1, Length(Shown) - 4) + '...';
    C.TextOut(Led + MUIScale(36), I * RowH + (RowH - C.TextHeight('A')) div 2, Shown);
    C.Brush.Style := bsSolid;
  end;
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
  Playing, HaveDisk, HaveCard, HaveTape: Boolean;
  Names: array[0..2] of string;
  I: Integer;
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
        TapeText := TapeText + LineEnding + Spec.Tape[Spec.Tape.Current].Description
      else
        TapeText := 'End of the tape';
      if Spec.Tape.FileName <> '' then TapeText := ExtractFileName(Spec.Tape.FileName) + ' - ' + TapeText;
      Progress := Spec.Tape.Progress;
    end;
    Playing := Spec.Tape.Playing;
    TapeName := ChangeFileExt(ExtractFileName(Spec.Tape.FileName), '');
    HaveDisk := DefaultDrive(Spec) >= 0;
    HaveCard := Spec.DivMMCOn and (Spec.DivMMC.Card <> nil);
    for I := 0 to 1 do
      if (Spec.FDC.Disk(I) <> nil) and ((I = 0) or Spec.FDC.DriveB) then
      begin
        Names[I] := ExtractFileName(Spec.FDC.Disk(I).FileName);
        if Names[I] = '' then Names[I] := '(new disk)';
      end
      else
        Names[I] := '';
    if HaveCard then Names[2] := ExtractFileName(Spec.DivMMC.Card.FileName) else Names[2] := '';
  finally
    FEmu.Unlock;
  end;
  if FMTapeLabel.Caption <> TapeText then FMTapeLabel.Caption := TapeText;
  if FMCassette.Caption <> TapeName then FMCassette.Caption := TapeName;
  FMCassette.Loaded := HaveTape;
  FMCassette.Show(Progress, Playing);
  if FMDiskBtn.Enabled <> HaveDisk then FMDiskBtn.Enabled := HaveDisk;
  if FMSDBtn.Enabled <> HaveCard then FMSDBtn.Enabled := HaveCard;
  if (Names[0] <> FMediaNames[0]) or (Names[1] <> FMediaNames[1]) or (Names[2] <> FMediaNames[2]) then
  begin
    FMediaNames[0] := Names[0];
    FMediaNames[1] := Names[1];
    FMediaNames[2] := Names[2];
    FMMediaBox.Invalidate;
  end;
  FMModelBtn.Caption := ModelInfo[FEmu.Spec.Model].Name;
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
  FNotice := TModernNotice.Create(Self);
  FNotice.Images := FSmallImages;
  FNotice.IconIndex := Ord(ikTheme);
  FNotice.Parent := Self;
  FNotice.SetBounds(0, 0, MUIScale(430), MUIScale(84));
  // In the middle of the window
  FNotice.AnchorHorizontalCenterTo(Self);
  FNotice.AnchorVerticalCenterTo(Self);
  FNotice.BringToFront;
  FNoticeTimer := TTimer.Create(Self);
  FNoticeTimer.Interval := 5000;
  FNoticeTimer.OnTimer := @NoticeEnd;
  FNoticeTimer.Enabled := True;
end;

procedure TMainWindow.NoticeEnd(Sender: TObject);
begin
  // The timer stays (this may be its own event), stopped
  if FNoticeTimer <> nil then FNoticeTimer.Enabled := False;
  FreeAndNil(FNotice);
end;

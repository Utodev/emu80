{ MainC64.inc: the Commodore 64 in the main window (included by MainForm.pas): its keyboard and joystick, the disks,
  tapes and programs it opens and the drive menus. The machine itself is TC64 (C64.pas). }

{ Keys that make a character the C64 takes from the layout in use: the digits and the signs (the letters are the keys
  themselves) }
function C64CharKey(Key: Word): Boolean;
begin
  Result := ((Key >= VK_0) and (Key <= VK_9)) or ((Key >= VK_OEM_1) and (Key <= VK_OEM_3)) or
    ((Key >= VK_OEM_4) and (Key <= VK_OEM_8)) or (Key = VK_OEM_102);
end;

{ A C64 key is down: a PC key for it, or a chord (while one is held the SHIFT, CTRL and C= of the PC are not the
  C64's: the character wanted says which it needs) }
function TMainWindow.C64KeyHeld(K: Integer): Boolean;
begin
  Result := FC64ChordKeys[K] > 0;
  if not Result and ((FSamChordActive = 0) or not (K in [C64K_LSHIFT, C64K_RSHIFT, C64K_CTRL, C64K_CBM])) then
    Result := FC64KeyCount[K] > 0;
end;

procedure TMainWindow.UpdateKeyboardC64;
var
  Col, Row, Bit: Integer;
  Bits: Byte;
begin
  for Col := 0 to 7 do
  begin
    Bits := 0;
    for Row := 0 to 7 do
      if C64KeyHeld(Col * 8 + Row) then Bits := Bits or (1 shl Row);
    FEmu.Spec.C64Hw.SetKeyColumn(Col, Bits);
  end;
  Bits := 0;
  for Bit := 0 to 4 do
    if FC64Joy[Bit] > 0 then Bits := Bits or (1 shl Bit);
  // (3: both ports; some games read port 1 and most port 2)
  if Settings.C64JoyPort = 3 then
  begin
    FEmu.Spec.C64Hw.SetJoystick(1, Bits);
    FEmu.Spec.C64Hw.SetJoystick(2, Bits);
  end
  else
  begin
    FEmu.Spec.C64Hw.SetJoystick(Settings.C64JoyPort, Bits);
    FEmu.Spec.C64Hw.SetJoystick(3 - Settings.C64JoyPort, 0);
  end;
  FEmu.Spec.C64Hw.SetRestore(FC64Restore > 0);
end;

{ The PC's keys: each is the C64 key in its place (the letters, the digits with Ctrl, the cursor keys...); the
  digits and signs go by the character they make, as the C64's keyboard has them elsewhere (FormUTF8KeyPress).
  Shift+F1..F8 are the C64's F1..F8, the numeric keypad and the right Ctrl a joystick (and, if wanted, the cursor keys and Ctrl instead of the C64's own: Scroll Lock changes it). }
procedure TMainWindow.MapKeyC64(Key: Word; Down: Boolean);

  procedure Press(K: Integer);
  begin
    if Down then Inc(FC64KeyCount[K]) else if FC64KeyCount[K] > 0 then Dec(FC64KeyCount[K]);
  end;

  { The joystick: up, down, left, right, fire (bits 0-4) }
  procedure Joy(Bits: Byte);
  var
    B: Integer;
  begin
    for B := 0 to 4 do
      if (Bits and (1 shl B)) <> 0 then
      begin
        if Down then Inc(FC64Joy[B]) else if FC64Joy[B] > 0 then Dec(FC64Joy[B]);
      end;
  end;

const
  Letters: array['A'..'Z'] of Integer = (
    C64K_A, C64K_B, C64K_C, C64K_D, C64K_E, C64K_F, C64K_G, C64K_H, C64K_I, C64K_J, C64K_K, C64K_L, C64K_M,
    C64K_N, C64K_O, C64K_P, C64K_Q, C64K_R, C64K_S, C64K_T, C64K_U, C64K_V, C64K_W, C64K_X, C64K_Y, C64K_Z);
  Digits: array['0'..'9'] of Integer = (
    C64K_0, C64K_1, C64K_2, C64K_3, C64K_4, C64K_5, C64K_6, C64K_7, C64K_8, C64K_9);
  FKeyList: array[0..3] of Integer = (C64K_F1, C64K_F3, C64K_F5, C64K_F7);
var
  N: Integer;
begin
  // Shift+F1..F8: F1, F2 (SHIFT + F1), F3...; as a chord, so the PC's Shift is not the C64's SHIFT meanwhile
  if (Key <= High(FSamRoute)) and (FSamRoute[Key] = 2) then
  begin
    N := Key - VK_F1;
    if Down then
    begin
      Inc(FC64ChordKeys[FKeyList[N div 2]]);
      if Odd(N) then Inc(FC64ChordKeys[C64K_LSHIFT]);
      Inc(FSamChordActive);
    end
    else
    begin
      Dec(FC64ChordKeys[FKeyList[N div 2]]);
      if Odd(N) then Dec(FC64ChordKeys[C64K_LSHIFT]);
      Dec(FSamChordActive);
      FSamRoute[Key] := 0;
    end;
    Exit;
  end;
  // By character: the chord was pressed when the character came (FormUTF8KeyPress)
  if (Key <= High(FSamRoute)) and (FSamRoute[Key] = 1) then
  begin
    if not Down then
    begin
      if FSamChordKey[Key] >= 0 then
      begin
        Dec(FC64ChordKeys[FSamChordKey[Key]]);
        if FSamChordMod[Key] >= 0 then Dec(FC64ChordKeys[FSamChordMod[Key]]);
        Dec(FSamChordActive);
        FSamChordKey[Key] := -1;
      end;
      FSamRoute[Key] := 0;
    end;
    Exit;
  end;
  case Key of
    VK_A..VK_Z: Press(Letters[Chr(Key)]);
    VK_0..VK_9: Press(Digits[Chr(Key)]);
    VK_NUMPAD0, VK_NUMPAD5: if Settings.C64Joystick then Joy($10) else Press(Digits[Chr(Key - VK_NUMPAD0 + 48)]);
    VK_NUMPAD8: if Settings.C64Joystick then Joy($01) else Press(C64K_8);
    VK_NUMPAD2: if Settings.C64Joystick then Joy($02) else Press(C64K_2);
    VK_NUMPAD4: if Settings.C64Joystick then Joy($04) else Press(C64K_4);
    VK_NUMPAD6: if Settings.C64Joystick then Joy($08) else Press(C64K_6);
    VK_NUMPAD7: if Settings.C64Joystick then Joy($05) else Press(C64K_7);
    VK_NUMPAD9: if Settings.C64Joystick then Joy($09) else Press(C64K_9);
    VK_NUMPAD1: if Settings.C64Joystick then Joy($06) else Press(C64K_1);
    VK_NUMPAD3: if Settings.C64Joystick then Joy($0A) else Press(C64K_3);
    VK_RETURN: Press(C64K_RETURN);
    VK_SPACE: Press(C64K_SPACE);
    VK_SHIFT, VK_LSHIFT: Press(C64K_LSHIFT);
    VK_RSHIFT: Press(C64K_RSHIFT);
    VK_CONTROL, VK_LCONTROL: if Settings.C64CursorJoy then Joy($10) else Press(C64K_CTRL);
    VK_RCONTROL: if Settings.C64Joystick then Joy($10) else Press(C64K_CTRL);
    VK_ESCAPE, VK_PAUSE: Press(C64K_RUNSTOP);
    VK_TAB: Press(C64K_CBM);
    VK_BACK, VK_DELETE: Press(C64K_DEL);
    VK_INSERT: begin Press(C64K_DEL); Press(C64K_LSHIFT); end;
    VK_HOME: Press(C64K_HOME);
    VK_PRIOR:
      if Down then Inc(FC64Restore) else if FC64Restore > 0 then Dec(FC64Restore);
    VK_RIGHT: if Settings.C64CursorJoy then Joy($08) else Press(C64K_CRSR_RIGHT);
    VK_DOWN: if Settings.C64CursorJoy then Joy($02) else Press(C64K_CRSR_DOWN);
    VK_LEFT: if Settings.C64CursorJoy then Joy($04) else begin Press(C64K_CRSR_RIGHT); Press(C64K_LSHIFT); end;
    VK_UP: if Settings.C64CursorJoy then Joy($01) else begin Press(C64K_CRSR_DOWN); Press(C64K_LSHIFT); end;
    // Scroll Lock: the cursor keys and Ctrl are the joystick, or the C64's cursor keys and CTRL
    VK_SCROLL: if Down then Settings.C64CursorJoy := not Settings.C64CursorJoy;
    VK_ADD: Press(C64K_PLUS);
    VK_SUBTRACT: Press(C64K_MINUS);
    VK_MULTIPLY: Press(C64K_STAR);
    VK_DIVIDE: Press(C64K_SLASH);
    VK_DECIMAL: Press(C64K_PERIOD);
  end;
end;

{ The character a key made, as the C64's keys: pressed (with SHIFT if it needs it) until the PC key goes up }
procedure TMainWindow.ChordC64(VK: Word; const UTF8Key: TUTF8Char);
var
  K, M: Integer;
begin
  if (FSamChordKey[VK] < 0) and (Length(UTF8Key) = 1) and C64KeysForChar(UTF8Key[1], K, M) then
  begin
    FSamChordKey[VK] := K;
    FSamChordMod[VK] := M;
    Inc(FC64ChordKeys[K]);
    if M >= 0 then Inc(FC64ChordKeys[M]);
    Inc(FSamChordActive);
    UpdateKeyboard;
  end
  else if (FSamChordKey[VK] < 0) and (Length(UTF8Key) = 2) and (UTF8Key = #$C2#$A3) and C64KeysForChar(#$A3, K, M) then
  begin
    // The pound sign
    FSamChordKey[VK] := K;
    FSamChordMod[VK] := -1;
    Inc(FC64ChordKeys[K]);
    Inc(FSamChordActive);
    UpdateKeyboard;
  end;
end;

{ What kind of file a Commodore 64 takes: 1 a disk (.d64), 2 a program (.prg, .p00, .t64), 3 a tape (.tap with the C64's
  header: the Spectrum has .tap files too), 0 none }
function C64FileKind(const FileName: string): Integer;
var
  Ext: string;
  F: TFileStream;
  Head: array[0..11] of Char;
begin
  Result := 0;
  Ext := LowerCase(ExtractFileExt(FileName));
  if Ext = '.d64' then Result := 1
  else if (Ext = '.prg') or (Ext = '.p00') or (Ext = '.t64') then Result := 2
  else if Ext = '.tap' then
  begin
    try
      F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
      try
        if (F.Size > 20) and (F.Read(Head, 12) = 12) and (Head = 'C64-TAPE-RAW') then Result := 3;
      finally
        F.Free;
      end;
    except
      Result := 0;
    end;
  end;
end;

{ A disk into the drive 8 or 9, a program or a tape (File > Open and the command line); False if it was not done }
function TMainWindow.OpenC64File(const FileName: string; Kind: Integer; AutoStart: Boolean): Boolean;
var
  Disk: TD64Image;
begin
  Result := False;
  if not IsC64Model(FEmu.Spec.Model) then
  begin
    ChangeModel(smC64);
    if not IsC64Model(FEmu.Spec.Model) then Exit;
  end;
  FEmu.Lock;
  try
    try
      case Kind of
        1:
          begin
            Disk := TD64Image.Create;
            try
              Disk.LoadFromFile(FileName);
            except
              Disk.Free;
              raise;
            end;
            FEmu.Spec.C64Hw.InsertDisk(0, Disk);
            if not FEmu.Spec.C64Hw.DriveOn[0] then
              raise Exception.Create(_('The disk drive needs the 1541 ROM (VC1541.rom, in the roms/c64 folder).'));
            Settings.AddRecentDisk(FileName);
            if AutoStart then FEmu.Spec.AutoLoad(True);
          end;
        2:
          begin
            if AutoStart then FEmu.Spec.Reset(True);
            FEmu.Spec.C64Hw.LoadPrg(FileName, AutoStart);
          end;
        3:
          begin
            FEmu.Spec.C64Hw.InsertTape(FileName);
            if Settings.C64TapeNoDrive then
            begin
              FEmu.Spec.C64Hw.SetDriveEnabled(0, False);
              FEmu.Spec.C64Hw.SetDriveEnabled(1, False);
            end;
            Settings.AddRecentTape(FileName);
            if AutoStart then FEmu.Spec.AutoLoad(False);
          end;
      end;
    except
      on E: Exception do
      begin
        FEmu.Unlock;
        try
          MessageDlg(_('Could not open ') + ExtractFileName(FileName) + ':' + LineEnding + E.Message, mtError, [mbOK], 0);
        finally
          FEmu.Lock;
        end;
        Exit;
      end;
    end;
  finally
    FEmu.Unlock;
  end;
  Settings.AddRecent(FileName);
  FLastFile := FileName;
  NoteMediaFile(FileName);
  UpdateRecentMenu;
  UpdateRecentDisksMenu;
  UpdateChecks;
  Caption := 'emu80 - ' + ExtractFileName(FileName);
  Result := True;
end;

{ A .d64 into drive 8 (Drive 0) or 9 (Drive 1) }
procedure TMainWindow.InsertC64Disk(Drive: Integer; const FileName: string);
var
  Disk: TD64Image;
begin
  Disk := TD64Image.Create;
  try
    Disk.LoadFromFile(FileName);
  except
    on E: Exception do
    begin
      Disk.Free;
      MessageDlg(_('Could not open ') + ExtractFileName(FileName) + ':' + LineEnding + E.Message, mtError, [mbOK], 0);
      Exit;
    end;
  end;
  FEmu.Lock;
  try
    if (Drive = 1) and not Settings.C64Drive9 then
    begin
      // (a disk in the second drive connects it)
      Settings.C64Drive9 := True;
      FEmu.Spec.DriveBOn := True;
    end;
    FEmu.Spec.C64Hw.InsertDisk(Drive, Disk);
  finally
    FEmu.Unlock;
  end;
  Settings.AddRecent(FileName);
  Settings.AddRecentDisk(FileName);
  NoteMediaFile(FileName);
  UpdateRecentMenu;
  UpdateRecentDisksMenu;
  UpdateChecks;
end;

procedure TMainWindow.InsertC64DiskDialog(Drive: Integer);
var
  Dlg: TOpenDialog;
begin
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Filter := _F('Commodore 64 disk images (*.d64)|*.d64|All files|*.*');
    Dlg.InitialDir := Settings.LastDir;
    Dlg.Options := Dlg.Options + [ofFileMustExist];
    if Dlg.Execute then InsertC64Disk(Drive, Dlg.FileName);
  finally
    Dlg.Free;
  end;
end;

procedure TMainWindow.EjectC64Disk(Drive: Integer);
begin
  FEmu.Lock;
  try
    FEmu.Spec.C64Hw.EjectDisk(Drive);
  finally
    FEmu.Unlock;
  end;
  UpdateChecks;
end;

{ Save the disk in a drive: where it came from, or (AskName, or a new disk) in a file asked for }
procedure TMainWindow.SaveC64Disk(Drive: Integer; AskName: Boolean);
var
  Dlg: TSaveDialog;
  Target: string;
begin
  FEmu.Lock;
  try
    if FEmu.Spec.C64Hw.DiskAt(Drive) = nil then Exit;
    Target := FEmu.Spec.C64Hw.DiskAt(Drive).FileName;
  finally
    FEmu.Unlock;
  end;
  if AskName or (Target = '') then
  begin
    Dlg := TSaveDialog.Create(Self);
    try
      Dlg.Filter := _F('Commodore 64 disk images (*.d64)|*.d64');
      Dlg.DefaultExt := 'd64';
      Dlg.InitialDir := Settings.LastDir;
      Dlg.Options := Dlg.Options + [ofOverwritePrompt];
      if not Dlg.Execute then Exit;
      Target := Dlg.FileName;
    finally
      Dlg.Free;
    end;
  end;
  FEmu.Lock;
  try
    try
      FEmu.Spec.C64Hw.SaveDisk(Drive, Target);
    except
      on E: Exception do
      begin
        FEmu.Unlock;
        try
          MessageDlg(_('Could not save ') + ExtractFileName(Target) + ': ' + E.Message, mtError, [mbOK], 0);
        finally
          FEmu.Lock;
        end;
      end;
    end;
  finally
    FEmu.Unlock;
  end;
  UpdateChecks;
end;

{ A new, formatted disk }
procedure TMainWindow.NewC64Disk(Drive: Integer);
var
  Disk: TD64Image;
begin
  Disk := TD64Image.Create;
  Disk.Format('NEW DISK', '64');
  Disk.Dirty := False;
  FEmu.Lock;
  try
    if (Drive = 1) and not Settings.C64Drive9 then
    begin
      Settings.C64Drive9 := True;
      FEmu.Spec.DriveBOn := True;
    end;
    FEmu.Spec.C64Hw.InsertDisk(Drive, Disk);
  finally
    FEmu.Unlock;
  end;
  UpdateChecks;
end;

{ The tape's buttons: 0 play/pause, 1 stop, 2 rewind, 3 eject }
procedure TMainWindow.C64TapeAction(What: Integer);
begin
  FEmu.Lock;
  try
    case What of
      0: if FEmu.Spec.C64Hw.PlayDown then FEmu.Spec.C64Hw.StopTape else FEmu.Spec.C64Hw.PlayTape;
      1: FEmu.Spec.C64Hw.StopTape;
      2: FEmu.Spec.C64Hw.Tape.Rewind;
      3: FEmu.Spec.C64Hw.EjectTape;
    end;
  finally
    FEmu.Unlock;
  end;
end;

{ The text of the tape for the status bar and the modern interface: what is in the recorder, its place and what it does }
procedure TMainWindow.C64TapeInfo(out Line, TapeFile: string; out Progress: Double; out Playing, Have: Boolean);
var
  T: TC64Tape;
begin
  T := FEmu.Spec.C64Hw.Tape;
  Have := T.Present;
  Playing := Have and FEmu.Spec.C64Hw.TapePressed and FEmu.Spec.C64Hw.TapeMotor;
  TapeFile := ChangeFileExt(T.Name, '');
  Progress := 0;
  if not Have then
  begin
    Line := _('No tape');
    Exit;
  end;
  if T.Count > 0 then Progress := T.Pos / T.Count;
  Line := T.Name + ' - ' + Format('%d%%', [Round(Progress * 100)]) + ' ' + FEmu.Spec.TapeStateText;
end;

{ What the C64's settings do to the machine }
procedure TMainWindow.ApplyC64Settings;
begin
  if (FEmu.Spec.C64Hw = nil) then Exit;
  FEmu.Spec.C64Hw.AutoPlay := Settings.AutoPlayTape;
  FEmu.Spec.C64Hw.AutoSaveDisks := Settings.C64SaveDisk;
  if FEmu.Spec.C64Hw.DriveOn[1] <> Settings.C64Drive9 then FEmu.Spec.DriveBOn := Settings.C64Drive9;
end;

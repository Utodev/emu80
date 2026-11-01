{ SpectrumCPC.inc: the Amstrad CPC in TSpectrum (included by Spectrum.pas).
  The CPC's own hardware is TAmstrad (Amstrad.pas); here are the parts that
  join it to what the Spectrum models share: the Z80 and its bus, the PSG's
  sound, the tape, the disc controller, the debugger's view of memory. }

function TSpectrum.IsCPC: Boolean;
begin
  Result := FIsCPC;
end;

{ The tape runs in CPU T-states of a 3.5 MHz machine (a TZX's pulse lengths):
  the CPC's clock is 4 MHz, so its T-states are scaled by 7/8 }
function TSpectrum.CPCTapeT(ChipT: Integer): Integer;
begin
  Result := ChipT * FSpeed * 7 div 8;
end;

procedure TSpectrum.SetupCPC;
begin
  if (FCPC = nil) or (FCPC.Model <> FModel) then
  begin
    FreeAndNil(FCPC);
    FCPC := TAmstrad.Create(FModel);
  end;
  FCPC.LoadRoms(RomPath(0), RomPath(1));
  FCPCIoT := -1;
  FCPC.OnPsg := @CPCPsg;
  FCPC.OnTapeIn := @CPCTapeIn;
  FCPC.OnMotor := @CPCMotor;
  FCPC.OnTapeOut := @CPCTapeOut;
  FCPC.OnFdc := @CPCFdc;
  FTape.ClockHz := 3500000;
  FTape.StopIf48K := False;
  FDiv.UseMemory(nil, nil);
  FDivOn := False;
  FCurrahOn := False;
  FCpu.Z80N := False;
  Z80NMnemonics := False;
  FDiv.ControlReadable := False;
  FDiv.NextEntries := False;
end;

{ Typing for the CPC: keys are CPCK_* (line * 8 + bit) }
procedure TSpectrum.CPCAutoType(Frames: Integer; const Keys: array of Integer);
var
  N, I: Integer;
begin
  N := Length(FAutoKeys);
  SetLength(FAutoKeys, N + 1);
  FAutoKeys[N].Frames := Frames;
  FillChar(FAutoKeys[N].Rows, SizeOf(FAutoKeys[N].Rows), $FF);
  for I := 0 to High(Keys) do
    FAutoKeys[N].Rows[Keys[I] div 8] := FAutoKeys[N].Rows[Keys[I] div 8] and not (1 shl (Keys[I] mod 8));
end;

procedure TSpectrum.CPCSyncAutoKeys;
begin
  if FAutoKeyPos < Length(FAutoKeys) then
    Move(FAutoKeys[FAutoKeyPos].Rows, FCPC.AutoMatrix, SizeOf(FCPC.AutoMatrix))
  else
    FillChar(FCPC.AutoMatrix, SizeOf(FCPC.AutoMatrix), $FF);
end;

{ Text on the CPC's keyboard (UK layout): letters as they come (lower case
  unless SHIFT is held down), the symbols with or without SHIFT. \n is
  RETURN, \w a second's wait, ~ half a second's. }
function TSpectrum.CPCTypeText(const Text: string; out Error: string): Boolean;
const
  LETTERS: array['A'..'Z'] of Integer = (
    CPCK_A, CPCK_B, CPCK_C, CPCK_D, CPCK_E, CPCK_F, CPCK_G, CPCK_H, CPCK_I, CPCK_J, CPCK_K, CPCK_L,
    CPCK_M, CPCK_N, CPCK_O, CPCK_P, CPCK_Q, CPCK_R, CPCK_S, CPCK_T, CPCK_U, CPCK_V, CPCK_W, CPCK_X,
    CPCK_Y, CPCK_Z);
  DIGITS: array['0'..'9'] of Integer = (
    CPCK_0, CPCK_1, CPCK_2, CPCK_3, CPCK_4, CPCK_5, CPCK_6, CPCK_7, CPCK_8, CPCK_9);
  // Characters typed with SHIFT, and the key that gives them
  SHIFTED = '!"#$%&''()_=|{}`+*<>?';
  SHIFTED_KEYS: array[1..Length(SHIFTED)] of Integer = (
    CPCK_1, CPCK_2, CPCK_3, CPCK_4, CPCK_5, CPCK_6, CPCK_7, CPCK_8, CPCK_9, CPCK_0, CPCK_MINUS,
    CPCK_AT, CPCK_LBRACKET, CPCK_RBRACKET, CPCK_BACKSLASH, CPCK_SEMICOLON, CPCK_COLON, CPCK_COMMA,
    CPCK_DOT, CPCK_SLASH);
  // ... and without
  PLAIN = '-^@[]\;:,./';
  PLAIN_KEYS: array[1..Length(PLAIN)] of Integer = (
    CPCK_MINUS, CPCK_CARET, CPCK_AT, CPCK_LBRACKET, CPCK_RBRACKET, CPCK_BACKSLASH, CPCK_SEMICOLON,
    CPCK_COLON, CPCK_COMMA, CPCK_DOT, CPCK_SLASH);
var
  I, P: Integer;
  Ch: Char;

  { Down for 4 frames, up for 6: the firmware wants a key released before
    it takes a repeat of it }
  procedure Tap(const Keys: array of Integer);
  begin
    CPCAutoType(4, Keys);
    CPCAutoType(6, []);
  end;

begin
  Result := False;
  Error := '';
  I := 1;
  while I <= Length(Text) do
  begin
    Ch := Text[I];
    if (Ch = '\') and (I < Length(Text)) then
    begin
      Inc(I);
      case Text[I] of
        'n', 'N': Tap([CPCK_RETURN]);
        'w', 'W': CPCAutoType(50, []);
      else
        Error := 'unknown escape \' + Text[I];
        Exit;
      end;
    end
    else if Ch in ['a'..'z'] then Tap([LETTERS[UpCase(Ch)]])
    else if Ch in ['A'..'Z'] then Tap([CPCK_SHIFT, LETTERS[Ch]])
    else if Ch in ['0'..'9'] then Tap([DIGITS[Ch]])
    else if Ch = '~' then CPCAutoType(25, [])
    else if Ch = ' ' then Tap([CPCK_SPACE])
    else if (Ch = #13) or (Ch = #10) then Tap([CPCK_RETURN])
    else
    begin
      P := Pos(Ch, PLAIN);
      if P > 0 then Tap([PLAIN_KEYS[P]])
      else
      begin
        P := Pos(Ch, SHIFTED);
        if P = 0 then
        begin
          Error := 'can''t type "' + Ch + '"';
          Exit;
        end;
        Tap([CPCK_SHIFT, SHIFTED_KEYS[P]]);
      end;
    end;
    Inc(I);
  end;
  Result := True;
end;

{ The program to RUN" from the disc in drive A. In order: the file named as
  the disc image (GAME.DSK: GAME.BAS or GAME.BIN), one named almost so (GAME1.DSK:
  GAME.BIN), DISC, DISK, START, LOADER,
  GAME or RUN, the first BASIC program, a file with no extension, the
  smallest binary (a loader is a few hundred bytes). '' if the disc has no
  directory AMSDOS can read or no program in it (a boot disc: |CPM starts it);
  empty files and names that can't be typed (menu decorations) are skipped. }
function TSpectrum.CPCDiscProgram: string;
const
  PREFERRED: array[0..5] of string = ('DISC', 'DISK', 'START', 'LOADER', 'GAME', 'RUN');
var
  D: TPlus3Disk;
  I, K, BinSize: Integer;
  Name, Base, Ext, Stem, Bare, Same, Near, Pref, FirstBas, FirstOther, SmallBin: string;
  Typable: Boolean;
begin
  Result := '';
  if FFDC.Disk(0) = nil then Exit;
  Stem := UpperCase(ChangeFileExt(ExtractFileName(FFDC.Disk(0).FileName), ''));
  Same := '';
  Near := '';
  Pref := '';
  Bare := Stem;
  while (Bare <> '') and (Bare[Length(Bare)] in ['0'..'9']) do Delete(Bare, Length(Bare), 1);
  FirstBas := '';
  FirstOther := '';
  SmallBin := '';
  BinSize := MaxInt;
  try
    D := TPlus3Disk.Create(FFDC.Disk(0));
    try
      for I := 0 to D.Count - 1 do
      begin
        if (D[I].User <> 0) or D[I].System then Continue;
        Name := UpperCase(D[I].Name);
        K := Pos('.', Name);
        if K > 0 then
        begin
          Base := Copy(Name, 1, K - 1);
          Ext := Copy(Name, K + 1, 3);
        end
        else
        begin
          Base := Name;
          Ext := '';
        end;
        // Empty files are menu decorations ("1-------", "THE CRACKER"); the
        // rest has to be typed
        Typable := (Base <> '') and (D[I].Size > 0);
        for K := 1 to Length(Base) do
          if not (Base[K] in ['A'..'Z', '0'..'9', '-', '_', '+', '!', '#', '$', '%', '&', '@', '^']) then
            Typable := False;
        if not Typable then Continue;
        if (Ext <> '') and (Ext <> 'BAS') and (Ext <> 'BIN') then Continue;
        if (Base = Stem) and ((Same = '') or (Ext = 'BAS')) then Same := Base;
        // RASTAN.BIN on RASTAN1.DSK, GHOST.BIN on GHOSTB.DSK
        if ((Bare <> '') and (Base = Bare)) or ((Length(Base) >= 4) and (Pos(Base, Stem) = 1)) then
          if (Near = '') or (Ext = 'BAS') then Near := Base;
        for K := 0 to High(PREFERRED) do
          if (Base = PREFERRED[K]) and ((Pref = '') or (Ext = 'BAS')) then Pref := Base;
        if (Ext = 'BAS') and (FirstBas = '') then FirstBas := Base;
        if (Ext = '') and (FirstOther = '') then FirstOther := Base;
        if (Ext = 'BIN') and (D[I].Size < BinSize) then
        begin
          BinSize := D[I].Size;
          SmallBin := Base;
        end;
      end;
    finally
      D.Free;
    end;
  except
    on Exception do ;   // no directory to read: a boot disc, or a copy-protected one
  end;
  if Same <> '' then Result := Same
  else if Near <> '' then Result := Near
  else if Pref <> '' then Result := Pref
  else if FirstBas <> '' then Result := FirstBas
  else if FirstOther <> '' then Result := FirstOther
  else Result := SmallBin;
end;

{ Load what is inserted the way a user would: RUN" for a tape (the 664 and
  6128 want |TAPE first, as they start on the disc), and for a disc the file
  to run (the one called DISC, or the first program) }
procedure TSpectrum.CPCAutoLoad(FromDisk: Boolean);
var
  Err, Prog: string;
begin
  // The firmware is ready after a couple of seconds
  CPCAutoType(150, []);
  if not FromDisk then
  begin
    if FInfo.HasFDC then CPCTypeText('|tape\n', Err);
    CPCTypeText('run"\n', Err);
    // "Press PLAY then any key": the program starts the motor and the tape plays
    CPCAutoType(60, []);
    CPCTypeText('\n', Err);
  end
  else
  begin
    Prog := CPCDiscProgram;
    if Prog = '' then CPCTypeText('|cpm\n', Err)
    else CPCTypeText('run"' + Prog + '\n', Err);
  end;
end;

procedure TSpectrum.CPCReset(Hard: Boolean);
begin
  FNextSpeed := 1;
  SetSpeed(FUserSpeed);
  FCpu.Reset(Hard);
  FCpu.T := 0;
  FCPC.Reset(Hard);
  FAY.Reset;
  FFDC.Reset;
  FNMIRequest := False;
  FResetFrame := FFrameCount;
  FCPCArmed := False;
  FCPCOffPending := False;
  CancelAutoType;
  CPCSyncAutoKeys;
  FEventCount := 0;
  FBeeperLevel := 0;
  FSamplePos := 0;
  FAYTickT := 0;
  FRenderLine := 0;
  CPCPaging;
end;

{ The debugger's view of memory (Peek, Poke, MemoryAt, SlotBank) follows the
  Gate Array's banking }
procedure TSpectrum.CPCPaging;
var
  Slot: Integer;
begin
  for Slot := 0 to 3 do
  begin
    FSlotBank[Slot] := FCPC.SlotBank(Slot);
    FSlotContended[Slot] := False;
    FPage[Slot * 2] := FCPC.ReadPtr(Slot);
    FPage[Slot * 2 + 1] := FCPC.ReadPtr(Slot) + $2000;
    FPageRO[Slot * 2] := FSlotBank[Slot] < 0;
    FPageRO[Slot * 2 + 1] := FSlotBank[Slot] < 0;
    FPageScreen[Slot * 2] := False;
    FPageScreen[Slot * 2 + 1] := False;
  end;
end;

function TSpectrum.PeekRam(Addr: Word): Byte;
begin
  if FIsCPC then Result := FCPC.ReadRam(Addr) else Result := Peek(Addr);   // (Peek covers the MSX)
end;

procedure TSpectrum.PokeRam(Addr: Word; Value: Byte);
begin
  if FIsCPC then FCPC.Write(Addr, Value)
  else if FIsMSX then FMsxHw.Write(Addr, Value)
  else Poke(Addr, Value);
end;

procedure TSpectrum.CPCPsg(T: Integer; Reg, Value: Byte);
begin
  AddEvent(T, 1, Reg, Value);
end;

function TSpectrum.CPCTapeIn(T: Integer): Boolean;
begin
  CPCMotorSettle(T);
  FTape.AdvanceTo(CPCTapeT(T));
  Result := FTape.Playing and FTape.Level;
end;

{ "Press PLAY then any key:" is answered by the tape player when the tape is on automatic (Auto play): a key
  is pressed for the user a few frames after the prompt, so a program that loads its parts from the tape one
  after another (its screens may be black while it waits) doesn't wait for a user who can't see the prompt.
  Only when there is a tape with something in it to play. The routine is at 2760 (464) or 28D2 (664 and
  6128): the check is at the call that waits for the key. }
procedure TSpectrum.CPCCheckTraps;
var
  PC: Word;
  Hit: Boolean;
begin
  if not AutoPlayTape or (FTape.Count = 0) or not FTape.HasMore or AutoTyping then Exit;
  PC := FCpu.PC.W;
  if FModel = smCPC464 then
    Hit := (PC = $2771) and (Peek($2771) = $CD) and (Peek($2772) = $56) and (Peek($2773) = $1B)
  else
    Hit := (PC = $28E1) and (Peek($28E1) = $CD) and (Peek($28E2) = $DB) and (Peek($28E3) = $1C);
  if not Hit then Exit;
  CPCAutoType(3, []);
  CPCAutoType(4, [CPCK_SPACE]);
  CPCAutoType(4, []);
end;

{ The tape moves while the user has pressed Play (or Auto play does it when
  the program starts the motor) and the program has the motor on }
procedure TSpectrum.CPCTapeUpdate(ChipT: Integer);
begin
  if FCPCArmed and (FCPC.Motor or FCPCOffPending) and FTape.HasMore then
  begin
    // The motor goes on from where the tape was (a program may stop it in the middle of a block)
    if not FTape.Playing and not FTape.Resume(CPCTapeT(ChipT)) then FTape.Play(CPCTapeT(ChipT));
  end
  else if FTape.Playing then
  begin
    FTape.AdvanceTo(CPCTapeT(ChipT));
    FTape.Hold;
    AddEvent(ChipT, 0, 0, 0);      // the tape's sound stops with it
  end;
end;

{ The cassette output (REC): the signal's edges, while the motor is on, in the
  tape's time (a 3.5 MHz machine's T-states) }
procedure TSpectrum.CPCTapeOut(T: Integer; Level: Boolean);
begin
  if FRecorder.Active and FCPC.Motor then
    FRecorder.Edge(Int64(FCpuTBase) * 7 div 8 + CPCTapeT(T));
end;

{ The motor's relay doesn't answer a moment's switching off (the firmware's keyboard and sound interrupts write
  0 to the PPI's port C for a few microseconds every frame): the tape stops when the motor has been off for a
  millisecond, noticed when the tape is read or the frame ends }
const
  CPC_MOTOR_OFF_T = 4000;

procedure TSpectrum.CPCMotorSettle(T: Integer);
begin
  if FCPCOffPending and (T - FCPCOffT >= CPC_MOTOR_OFF_T) then
  begin
    FCPCOffPending := False;
    CPCTapeUpdate(T);
  end;
end;

procedure TSpectrum.CPCMotor(T: Integer; On_: Boolean);
begin
  if not On_ and FRecorder.Active then FRecorder.Flush;
  if On_ and AutoPlayTape and (FTape.Count > 0) then FCPCArmed := True;
  if On_ then
  begin
    // Back on soon enough: the tape never stopped
    if FCPCOffPending then
    begin
      FCPCOffPending := False;
      Exit;
    end;
  end
  else if FTape.Playing then
  begin
    FCPCOffPending := True;
    FCPCOffT := T;
    Exit;
  end;
  CPCTapeUpdate(T);
end;

{ The disc controller's ports: FA7E (motor), FB7E (status) and FB7F (data) }
function TSpectrum.CPCFdc(Write: Boolean; Reg: Integer; Value: Byte; T: Integer): Byte;
begin
  Result := $FF;
  FFDC.SetTime(FrameStartT + T);
  if Write then
  begin
    if Reg = 2 then FFDC.Motor := (Value and 1) <> 0
    else if Reg = 1 then FFDC.WriteData(Value);
  end
  else if Reg = 0 then Result := FFDC.ReadStatus
  else Result := FFDC.ReadData;
end;

function TSpectrum.ReadMemCPC(Addr: Word): Byte;
begin
  Result := FCPC.Read(Addr);
  if FDaadOn and (FDaadMap[Addr] <> 0) then DaadRead(Addr);
  if (FMemBreakpoints > 0) and not FSuppressBreaks and
     ((FBreakFlags[Addr] and (BP_READ or BP_DISABLED)) = BP_READ) and ConditionHolds(Addr) then
  begin
    FBreakHit := True;
    FBreakKind := bkMemory;
    FBreakInstr := FInstrPC;
    FBreakReason := Format('Read breakpoint at %.4X (instruction at %.4X)', [Addr, FInstrPC]);
  end;
end;

procedure TSpectrum.WriteMemCPC(Addr: Word; Value: Byte);
begin
  if (FMemBreakpoints > 0) and not FSuppressBreaks and
     ((FBreakFlags[Addr] and (BP_WRITE or BP_DISABLED)) = BP_WRITE) and ConditionHolds(Addr) then
  begin
    FBreakHit := True;
    FBreakKind := bkMemory;
    FBreakInstr := FInstrPC;
    FBreakReason := Format('Write breakpoint at %.4X (instruction at %.4X)', [Addr, FInstrPC]);
  end;
  FCPC.Write(Addr, Value);
end;

{ An I/O cycle takes 4 T-states, held to the 1 MHz grid; the chips see the
  access in its last T-states. At normal speed the instruction's timing table says when (FCPCIoT). }
function TSpectrum.ReadPortCPC(Port: Word; var T: Integer): Byte;
begin
  if FCPCIoT >= 0 then Result := FCPC.InPort(Port, FCPCIoT)
  else Result := FCPC.InPort(Port, U(T) + 3);
  LogPort(Port, Result, False);
  CheckPortBreak(Port, False);
  Inc(T, 4);
  if FContend then T := (T + 3) and not 3;
end;

procedure TSpectrum.WritePortCPC(Port: Word; Value: Byte; var T: Integer);
begin
  LogPort(Port, Value, True);
  CheckPortBreak(Port, True);
  if FCPCIoT >= 0 then FCPC.OutPort(Port, Value, FCPCIoT)
  else FCPC.OutPort(Port, Value, U(T) + 3);
  if ((Port and $C000) = $4000) or ((Port and $2000) = 0) then CPCPaging;
  Inc(T, 4);
  if FContend then T := (T + 3) and not 3;
end;

{ The CPC's Gate Array lets the Z80 at the memory once a microsecond: every instruction takes a whole
  number of them, and not just its T-states rounded up (OUT (C),r takes 4, not 3). The times, in
  microseconds ("NOPs"), are the CPC's (as Caprice32 has them, which programs that change the CRTC
  registers at a given character, as Pinball Dreams does, need); a prefix is a microsecond of its own. }
const
  CPC_NOPS: array[0..255] of Byte = (   // unprefixed (a prefix: its own microsecond)
    1, 3, 2, 2, 1, 1, 2, 1, 1, 3, 2, 2, 1, 1, 2, 1,   // 00
    3, 3, 2, 2, 1, 1, 2, 1, 3, 3, 2, 2, 1, 1, 2, 1,   // 10
    2, 3, 5, 2, 1, 1, 2, 1, 2, 3, 5, 2, 1, 1, 2, 1,   // 20
    2, 3, 4, 2, 3, 3, 3, 1, 2, 3, 4, 2, 1, 1, 2, 1,   // 30
    1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 2, 1,   // 40
    1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 2, 1,   // 50
    1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 2, 1,   // 60
    2, 2, 2, 2, 2, 2, 1, 2, 1, 1, 1, 1, 1, 1, 2, 1,   // 70
    1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 2, 1,   // 80
    1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 2, 1,   // 90
    1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 2, 1,   // A0
    1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 2, 1,   // B0
    2, 3, 3, 3, 3, 4, 2, 4, 2, 3, 3, 1, 3, 5, 2, 4,   // C0
    2, 3, 3, 3, 3, 4, 2, 4, 2, 1, 3, 3, 3, 1, 2, 4,   // D0
    2, 3, 3, 6, 3, 4, 2, 4, 2, 1, 3, 1, 3, 1, 2, 4,   // E0
    2, 3, 3, 1, 3, 4, 2, 4, 2, 2, 3, 1, 3, 1, 2, 4);   // F0
  CPC_NOPS_CB: array[0..255] of Byte = (   // after CB
    1, 1, 1, 1, 1, 1, 3, 1, 1, 1, 1, 1, 1, 1, 3, 1,   // 00
    1, 1, 1, 1, 1, 1, 3, 1, 1, 1, 1, 1, 1, 1, 3, 1,   // 10
    1, 1, 1, 1, 1, 1, 3, 1, 1, 1, 1, 1, 1, 1, 3, 1,   // 20
    1, 1, 1, 1, 1, 1, 3, 1, 1, 1, 1, 1, 1, 1, 3, 1,   // 30
    1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 2, 1,   // 40
    1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 2, 1,   // 50
    1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 2, 1,   // 60
    1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 2, 1,   // 70
    1, 1, 1, 1, 1, 1, 3, 1, 1, 1, 1, 1, 1, 1, 3, 1,   // 80
    1, 1, 1, 1, 1, 1, 3, 1, 1, 1, 1, 1, 1, 1, 3, 1,   // 90
    1, 1, 1, 1, 1, 1, 3, 1, 1, 1, 1, 1, 1, 1, 3, 1,   // A0
    1, 1, 1, 1, 1, 1, 3, 1, 1, 1, 1, 1, 1, 1, 3, 1,   // B0
    1, 1, 1, 1, 1, 1, 3, 1, 1, 1, 1, 1, 1, 1, 3, 1,   // C0
    1, 1, 1, 1, 1, 1, 3, 1, 1, 1, 1, 1, 1, 1, 3, 1,   // D0
    1, 1, 1, 1, 1, 1, 3, 1, 1, 1, 1, 1, 1, 1, 3, 1,   // E0
    1, 1, 1, 1, 1, 1, 3, 1, 1, 1, 1, 1, 1, 1, 3, 1);   // F0
  CPC_NOPS_ED: array[0..255] of Byte = (   // after ED
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,   // 00
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,   // 10
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,   // 20
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,   // 30
    3, 3, 3, 5, 1, 3, 1, 2, 3, 3, 3, 5, 1, 3, 1, 2,   // 40
    3, 3, 3, 5, 1, 3, 1, 2, 3, 3, 3, 5, 1, 3, 1, 2,   // 50
    3, 3, 3, 5, 1, 3, 1, 4, 3, 3, 3, 5, 1, 3, 1, 4,   // 60
    3, 3, 3, 5, 1, 3, 1, 1, 3, 3, 3, 5, 1, 3, 1, 1,   // 70
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,   // 80
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,   // 90
    4, 3, 4, 4, 1, 1, 1, 1, 4, 3, 4, 4, 1, 1, 1, 1,   // A0
    4, 3, 4, 4, 1, 1, 1, 1, 4, 3, 4, 4, 1, 1, 1, 1,   // B0
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,   // C0
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,   // D0
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,   // E0
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1);   // F0
  CPC_NOPS_XY: array[0..255] of Byte = (   // after DD or FD
    1, 3, 2, 2, 1, 1, 2, 1, 1, 3, 2, 2, 1, 1, 2, 1,   // 00
    3, 3, 2, 2, 1, 1, 2, 1, 3, 3, 2, 2, 1, 1, 2, 1,   // 10
    2, 3, 5, 2, 1, 1, 2, 1, 2, 3, 5, 2, 1, 1, 2, 1,   // 20
    2, 3, 4, 2, 5, 5, 5, 1, 2, 3, 4, 2, 1, 1, 2, 1,   // 30
    1, 1, 1, 1, 1, 1, 4, 1, 1, 1, 1, 1, 1, 1, 4, 1,   // 40
    1, 1, 1, 1, 1, 1, 4, 1, 1, 1, 1, 1, 1, 1, 4, 1,   // 50
    1, 1, 1, 1, 1, 1, 4, 1, 1, 1, 1, 1, 1, 1, 4, 1,   // 60
    4, 4, 4, 4, 4, 4, 1, 4, 1, 1, 1, 1, 1, 1, 4, 1,   // 70
    1, 1, 1, 1, 1, 1, 4, 1, 1, 1, 1, 1, 1, 1, 4, 1,   // 80
    1, 1, 1, 1, 1, 1, 4, 1, 1, 1, 1, 1, 1, 1, 4, 1,   // 90
    1, 1, 1, 1, 1, 1, 4, 1, 1, 1, 1, 1, 1, 1, 4, 1,   // A0
    1, 1, 1, 1, 1, 1, 4, 1, 1, 1, 1, 1, 1, 1, 4, 1,   // B0
    2, 3, 3, 3, 3, 4, 2, 4, 2, 3, 3, 1, 3, 5, 2, 4,   // C0
    2, 3, 3, 3, 3, 4, 2, 4, 2, 1, 3, 3, 3, 1, 2, 4,   // D0
    2, 3, 3, 6, 3, 4, 2, 4, 2, 1, 3, 1, 3, 1, 2, 4,   // E0
    2, 3, 3, 1, 3, 4, 2, 4, 2, 2, 3, 1, 3, 1, 2, 4);   // F0
  CPC_NOPS_XYCB: array[0..255] of Byte = (   // after DD CB d or FD CB d
    5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5,   // 00
    5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5,   // 10
    5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5,   // 20
    5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5,   // 30
    4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4,   // 40
    4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4,   // 50
    4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4,   // 60
    4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4,   // 70
    5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5,   // 80
    5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5,   // 90
    5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5,   // A0
    5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5,   // B0
    5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5,   // C0
    5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5,   // D0
    5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5,   // E0
    5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5);   // F0
  CPC_NOPS_TAKEN: array[0..255] of Byte = (   // more when a condition is met or a block instruction repeats (also after ED)
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,   // 00
    1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,   // 10
    1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0,   // 20
    1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0,   // 30
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,   // 40
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,   // 50
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,   // 60
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,   // 70
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,   // 80
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,   // 90
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,   // A0
    1, 2, 1, 1, 0, 0, 0, 0, 1, 2, 1, 1, 0, 0, 0, 0,   // B0
    2, 0, 0, 0, 2, 0, 0, 0, 2, 0, 0, 0, 2, 0, 0, 0,   // C0
    2, 0, 0, 0, 2, 0, 0, 0, 2, 0, 0, 0, 2, 0, 0, 0,   // D0
    2, 0, 0, 0, 2, 0, 0, 0, 2, 0, 0, 0, 2, 0, 0, 0,   // E0
    2, 0, 0, 0, 2, 0, 0, 0, 2, 0, 0, 0, 2, 0, 0, 0);   // F0

{ The microseconds the instruction at PC takes, the one in which its I/O is made (IoNops: the chips
  see it after that many, -1 if none), and whether an interrupt right after it is accepted a
  microsecond sooner (its last cycle overlaps the acknowledge) }
function TSpectrum.CPCInstrNops(out IoNops: Integer; out IntShort: Boolean): Integer;
var
  Addr: Word;
  Op: Byte;
  Pre: Integer;

  function Cond(Index: Integer): Boolean;
  var
    F: Byte;
  begin
    F := FCpu.F;
    case Index of
      0: Result := (F and FLAG_Z) = 0;
      1: Result := (F and FLAG_Z) <> 0;
      2: Result := (F and FLAG_C) = 0;
      3: Result := (F and FLAG_C) <> 0;
      4: Result := (F and FLAG_P) = 0;
      5: Result := (F and FLAG_P) <> 0;
      6: Result := (F and FLAG_S) = 0;
    else
      Result := (F and FLAG_S) <> 0;
    end;
  end;

  { An unprefixed (or DD/FD prefixed, Xy) opcode's microseconds }
  function Main(Op: Byte; Xy: Boolean): Integer;
  begin
    if Xy then Result := CPC_NOPS_XY[Op] else Result := CPC_NOPS[Op];
    case Op of
      $10: if FCpu.BC.H <> 1 then Inc(Result, CPC_NOPS_TAKEN[Op]);                        // DJNZ
      $20, $28, $30, $38: if Cond((Op shr 3) and 3) then Inc(Result, CPC_NOPS_TAKEN[Op]); // JR cc
      $C0, $C8, $D0, $D8, $E0, $E8, $F0, $F8:                                             // RET cc
        if Cond((Op shr 3) and 7) then Inc(Result, CPC_NOPS_TAKEN[Op]) else IntShort := True;
      $C4, $CC, $D4, $DC, $E4, $EC, $F4, $FC:                                             // CALL cc
        if Cond((Op shr 3) and 7) then Inc(Result, CPC_NOPS_TAKEN[Op]);
      $03, $13, $23, $33, $0B, $1B, $2B, $3B, $E3, $F9: IntShort := True;                 // INC/DEC rr, EX (SP),HL, LD SP,HL
      $D3: IoNops := Pre + 2;                                                             // OUT (n),A
      $DB: IoNops := Pre + 3;                                                             // IN A,(n)
    end;
  end;

begin
  IoNops := -1;
  IntShort := False;
  Addr := FCpu.PC.W;
  Op := FCPC.Read(Addr);
  Pre := 0;
  // DD and FD (one or more)
  while Op in [$DD, $FD] do
  begin
    Inc(Pre);
    Inc(Addr);
    Op := FCPC.Read(Addr);
  end;
  if Op = $CB then
  begin
    if Pre > 0 then Result := Pre + CPC_NOPS_XY[$CB] + CPC_NOPS_XYCB[FCPC.Read(Word(Addr + 2))]
    else Result := 1 + CPC_NOPS_CB[FCPC.Read(Word(Addr + 1))];
  end
  else if Op = $ED then
  begin
    Inc(Pre);
    Op := FCPC.Read(Word(Addr + 1));
    Result := Pre + CPC_NOPS_ED[Op];
    case Op of
      $40, $48, $50, $58, $60, $68, $70, $78: IoNops := Pre + 3;                          // IN r,(C)
      $41, $49, $51, $59, $61, $69, $71, $79: IoNops := Pre + 2;                          // OUT (C),r
      $A2, $AA, $B2, $BA: IoNops := Pre + 4;                                              // INI, IND, INIR, INDR
      $A3, $AB, $B3, $BB: IoNops := Pre + 3;                                              // OUTI, OUTD, OTIR, OTDR
      $47, $4F, $57, $5F, $A0, $A8: IntShort := True;                                     // LD I,A etc., LDI, LDD
    end;
    case Op of
      $B0, $B8: if FCpu.BC.W <> 1 then Inc(Result, CPC_NOPS_TAKEN[Op]);                   // LDIR, LDDR
      $B1, $B9:                                                                           // CPIR, CPDR
        if (FCpu.BC.W <> 1) and (FCpu.A <> FCPC.Read(FCpu.HL.W)) then
        begin
          Inc(Result, CPC_NOPS_TAKEN[Op]);
          IntShort := True;
        end;
      $B2, $BA, $B3, $BB: if FCpu.BC.H <> 1 then Inc(Result, CPC_NOPS_TAKEN[Op]);         // INIR, INDR, OTIR, OTDR
    end;
    if Op in [$B0, $B8] then IntShort := True;
  end
  else
    Result := Pre + Main(Op, Pre > 0);
end;

procedure TSpectrum.ExecuteOneCPC;
var
  StartT, Nops, IoNops: Integer;
begin
  if FTrackPrev then
  begin
    FPrevRegs := FCpu.GetRegs;
    FPrevPaging := PagingState;
  end;
  Inc(FStepCount);
  StartT := FCpu.T;
  if FCPC.IntLine and FCpu.IFF1 and FCpu.Interrupt then
  begin
    FCPC.IntAck;
    // The acknowledge and the RST take 5 microseconds (IM 2: 7), one less after some instructions
    if FContend then
    begin
      if FCpu.IM = 2 then Nops := 7 else Nops := 5;
      if FCPCIntShort then Dec(Nops);
      FCpu.T := StartT + Nops * 4;
    end;
    FCPCIntShort := False;
  end
  else
  begin
    if (FCpu.PC.W >= $2700) and (FCpu.PC.W < $2900) then CPCCheckTraps;
    FInstrPC := FCpu.PC.W;
    FSuppressBreaks := FProbeCovered;
    if FContend then
    begin
      // The CPC's own timing (see CPCInstrNops); the CPU's count is not used
      Nops := CPCInstrNops(IoNops, FCPCIntShort);
      if IoNops >= 0 then FCPCIoT := StartT + IoNops * 4;
      FCpu.Step;
      FCPCIoT := -1;
      FCpu.T := StartT + Nops * 4;
    end
    else
      FCpu.Step;
    FSuppressBreaks := False;
  end;
  FCPC.Sync(U(FCpu.T));
end;

procedure TSpectrum.FinishFrameCPC;
begin
  FCPC.EndFrame(FInfo.FrameT);
  if FRecorder.Active then FRecorder.Idle(Int64(FCpuTBase) * 7 div 8 + CPCTapeT(FInfo.FrameT));
  CPCMotorSettle(FInfo.FrameT);
  if FCPCOffPending then Dec(FCPCOffT, FInfo.FrameT);
  FTape.AdvanceTo(CPCTapeT(FInfo.FrameT));
  GenerateAudio;
  Inc(FCpuTBase, FrameLength);
  Dec(FCpu.T, FrameLength);
  FTape.EndFrame(CPCTapeT(FInfo.FrameT));
  if FPendingSpeed <> FSpeed then
  begin
    FCpu.T := FCpu.T div FSpeed * FPendingSpeed;
    FSpeed := FPendingSpeed;
    UpdateContend;
  end;
  FFDC.Tick;
  FRenderLine := 0;
  Inc(FFrameCount);
  AdvanceAutoKeys;
  CPCSyncAutoKeys;
end;

{ CPC .SNA snapshots (the format of CPCEmu and Winape, versions 1 to 3 with
  the memory dump in the file): the CPU, the Gate Array, CRTC, PPI and PSG
  registers and 64K or 128K of RAM. A snapshot taken with the memory in
  compressed chunks (some version 3 files) isn't read. Where the beam is
  isn't in the file: the machine goes on from the start of a frame. }

const
  SNA_HEADER = $100;

procedure TSpectrum.LoadCPCSna(const FileName: string);
var
  F: TFileStream;
  H: array[0..SNA_HEADER - 1] of Byte;
  Mem: array of Byte;
  Size, KB, Kind, I: Integer;
  CpcModel: TSpectrumModel;
  R: TCPCRegisters;
  Fl: Boolean;
begin
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    if F.Size < SNA_HEADER then raise Exception.Create(_('Invalid CPC snapshot'));
    F.ReadBuffer(H, SizeOf(H));
    if not CompareMem(@H[0], PChar('MV - SNA'), 8) then raise Exception.Create(_('Not a CPC snapshot'));
    KB := H[$6B] or (H[$6C] shl 8);
    Kind := H[$6D];
    if H[$10] >= 3 then
    begin
      if KB = 0 then
        raise Exception.Create(_('This snapshot keeps its memory in compressed chunks, which emu80 doesn''t read'));
    end;
    if (KB <> 64) and (KB <> 128) then
      raise Exception.CreateFmt(_('A CPC snapshot with %d KB of memory isn''t supported (64 or 128)'), [KB]);
    if Kind in [4, 5, 6] then
      raise Exception.Create(_('A snapshot of a CPC+ or a GX4000: emu80 emulates the original CPC range only'));
    Size := KB * 1024;
    if F.Size - SNA_HEADER < Size then raise Exception.Create(_('The snapshot is cut short'));
    SetLength(Mem, Size);
    F.ReadBuffer(Mem[0], Size);
  finally
    F.Free;
  end;
  // The model it says (a 128K dump is a 6128's whatever it says)
  if (Kind = 2) or (KB = 128) then CpcModel := smCPC6128
  else if Kind = 1 then CpcModel := smCPC664
  else CpcModel := smCPC464;
  if (FModel <> CpcModel) or (FCPC = nil) then SetModel(CpcModel) else Reset(True);
  FillChar(R, SizeOf(R), 0);
  R.PenSel := H[$2E];
  for I := 0 to 16 do R.Pens[I] := H[$2F + I];
  R.RomReg := H[$40];
  R.RamConfig := H[$41];
  R.CrtcSel := H[$42];
  for I := 0 to 17 do R.Crtc[I] := H[$43 + I];
  R.UpperRom := H[$55];
  for I := 0 to 3 do R.Ppi[I] := H[$56 + I];
  R.PsgSel := H[$5A];
  for I := 0 to 15 do R.Psg[I] := H[$5B + I];
  // The RAM first (the banks are not the visible memory: all of it goes in)
  for I := 0 to KB div 16 - 1 do Move(Mem[I * $4000], FCPC.RamBank(I)^[0], $4000);
  FCPC.SetRegisters(R);
  CPCPaging;
  FAY.Reset;
  for I := 0 to 15 do FAY.WriteRegister(I, R.Psg[I]);
  FAY.SelectRegister(R.PsgSel);
  // The CPU
  FCpu.A := H[$12]; FCpu.F := H[$11];
  FCpu.BC.L := H[$13]; FCpu.BC.H := H[$14];
  FCpu.DE.L := H[$15]; FCpu.DE.H := H[$16];
  FCpu.HL.L := H[$17]; FCpu.HL.H := H[$18];
  FCpu.R := H[$19]; FCpu.R7 := H[$19] and $80;
  FCpu.I := H[$1A];
  Fl := H[$1C] <> 0;
  FCpu.IFF1 := Fl;
  FCpu.IFF2 := H[$1B] <> 0;
  FCpu.IX.L := H[$1D]; FCpu.IX.H := H[$1E];
  FCpu.IY.L := H[$1F]; FCpu.IY.H := H[$20];
  FCpu.SP.L := H[$21]; FCpu.SP.H := H[$22];
  FCpu.PC.L := H[$23]; FCpu.PC.H := H[$24];
  FCpu.IM := H[$25];
  FCpu.F_ := H[$26]; FCpu.A_ := H[$27];
  FCpu.BC_.L := H[$28]; FCpu.BC_.H := H[$29];
  FCpu.DE_.L := H[$2A]; FCpu.DE_.H := H[$2B];
  FCpu.HL_.L := H[$2C]; FCpu.HL_.H := H[$2D];
  FCpu.Halted := False;
  FCpu.T := 0;
  FCpu.EIJust := False;
  FEventCount := 0;
end;

procedure TSpectrum.SaveCPCSna(const FileName: string);
var
  F: TFileStream;
  H: array[0..SNA_HEADER - 1] of Byte;
  R: TCPCRegisters;
  I, KB: Integer;
begin
  FCPC.GetRegisters(R);
  for I := 0 to 15 do R.Psg[I] := FAY.GetRegister(I);
  R.PsgSel := FAY.Selected;
  if FCPC.RamBanks = 8 then KB := 128 else KB := 64;
  FillChar(H, SizeOf(H), 0);
  Move(PChar('MV - SNA')^, H[0], 8);
  H[$10] := 1;                                   // version 1
  H[$11] := FCpu.F; H[$12] := FCpu.A;
  H[$13] := FCpu.BC.L; H[$14] := FCpu.BC.H;
  H[$15] := FCpu.DE.L; H[$16] := FCpu.DE.H;
  H[$17] := FCpu.HL.L; H[$18] := FCpu.HL.H;
  H[$19] := FCpu.GetR; H[$1A] := FCpu.I;
  H[$1B] := Ord(FCpu.IFF2); H[$1C] := Ord(FCpu.IFF1);
  H[$1D] := FCpu.IX.L; H[$1E] := FCpu.IX.H;
  H[$1F] := FCpu.IY.L; H[$20] := FCpu.IY.H;
  H[$21] := FCpu.SP.L; H[$22] := FCpu.SP.H;
  H[$23] := FCpu.PC.L; H[$24] := FCpu.PC.H;
  H[$25] := FCpu.IM;
  H[$26] := FCpu.F_; H[$27] := FCpu.A_;
  H[$28] := FCpu.BC_.L; H[$29] := FCpu.BC_.H;
  H[$2A] := FCpu.DE_.L; H[$2B] := FCpu.DE_.H;
  H[$2C] := FCpu.HL_.L; H[$2D] := FCpu.HL_.H;
  H[$2E] := R.PenSel;
  for I := 0 to 16 do H[$2F + I] := R.Pens[I];
  H[$40] := R.RomReg;
  H[$41] := R.RamConfig;
  H[$42] := R.CrtcSel;
  for I := 0 to 17 do H[$43 + I] := R.Crtc[I];
  H[$55] := R.UpperRom;
  for I := 0 to 3 do H[$56 + I] := R.Ppi[I];
  H[$5A] := R.PsgSel;
  for I := 0 to 15 do H[$5B + I] := R.Psg[I];
  H[$6B] := KB and $FF; H[$6C] := KB shr 8;
  case FModel of
    smCPC664: H[$6D] := 1;
    smCPC6128: H[$6D] := 2;
  else
    H[$6D] := 0;
  end;
  F := TFileStream.Create(FileName, fmCreate);
  try
    F.WriteBuffer(H, SizeOf(H));
    for I := 0 to KB div 16 - 1 do F.WriteBuffer(FCPC.RamBank(I)^[0], $4000);
  finally
    F.Free;
  end;
end;

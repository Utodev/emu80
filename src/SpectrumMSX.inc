{ SpectrumMSX.inc: the MSX in TSpectrum (included by Spectrum.pas). The
  MSX's own hardware is TMsxMachine (MsxMachine.pas, with the slots in Msx.pas
  and the video chip in MsxVdp.pas); here are the parts that join it to what
  the Spectrum models share: the Z80 and its bus, the PSG's sound and the
  click, the debugger's view of memory. }

procedure TSpectrum.SetupMSX;
var
  Path: string;
  Hw: TMsxMachine;

  { Whether the file has that text: the QUANTIKA main ROM (the default) says "with FBASIC" in its banner, and the
    QUANTIKA disk ROM has "QUANTIKA disk ROM" in its header }
  function FileHas(const FileName, Mark: string): Boolean;
  var
    F: TFileStream;
    Data: AnsiString;
  begin
    Result := False;
    try
      F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
      try
        SetLength(Data, F.Size);
        if F.Size > 0 then F.ReadBuffer(Data[1], F.Size);
      finally
        F.Free;
      end;
      Result := Pos(Mark, Data) > 0;
    except
      Result := False;
    end;
  end;

begin
  { A new machine when there is none; the old one stays until this one has its ROMs }
  if FMsxHw <> nil then Hw := FMsxHw else Hw := TMsxMachine.Create;
  try
    Hw.LoadBios(RomPath(0));
    Hw.SetCompat(FMsxCompat);
    Hw.LoadSubRom(RomPath(1));
    // The disk interface's ROM is optional: without it there is no drive (nor in the MSX1 layout: there is no expanded
    // slot for it). It must suit the main ROM: the QUANTIKA disk ROM works only with the QUANTIKA main ROM, and the
    // original disk ROM only with the original main ROM (it calls into the original BASIC: on QUANTIKA it would hang
    // at boot); a pair that does not match leaves the drive out
    Path := RomPath(2);
    FMsxOwnDisk := (Path <> '') and FileHas(Path, 'QUANTIKA disk ROM');
    if (Path <> '') and FileExists(Path) and not FMsxCompat and
      (FileHas(RomPath(0), 'with FBASIC') = FileHas(Path, 'QUANTIKA disk ROM')) then Hw.InstallDisk(Path, FWD, @MSXNow)
    else if Hw.HasDisk then Hw.RemoveDisk;
  except
    if Hw <> FMsxHw then Hw.Free;
    raise;
  end;
  if Hw <> FMsxHw then
  begin
    FMsxHw.Free;
    FMsxHw := Hw;
  end;
  FWD.ClockHz := FInfo.ClockHz;
  FWD.ReadyAlways := True;
  FMsxHw.OnPsg := @MSXPsg;
  FMsxHw.OnClick := @MSXClick;
  FMsxHw.OnTapeIn := @MSXTapeIn;
  FMsxHw.OnMotor := @MSXMotor;
  // The tape runs in 3.5 MHz T-states, a TZX's (MSXTapeT)
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

procedure TSpectrum.MSXReset(Hard: Boolean);
begin
  // Another slot layout (the MSX1 one or the MSX2's): the ROMs go in again, in their places
  if FMsxHw.Compat <> FMsxCompat then
  begin
    SetupMSX;
    Hard := True;
  end;
  FWD.Reset;
  FNextSpeed := 1;
  SetSpeed(FUserSpeed);
  FCpu.Reset(Hard);
  FCpu.T := 0;
  // The mapper ports are there unless the user says no, or (auto) a tape starts the machine: the programs on
  // tape are MSX1 ones, and some of them (the Spectrum conversions) write to FEh for their own purposes
  FMsxHw.MapperOn := (FMsxMapperMode = MSX_MAPPER_ON) or ((FMsxMapperMode = MSX_MAPPER_AUTO) and not FMsxTapeStart);
  FMsxTapeStart := False;
  FMsxHw.Reset(Hard);
  FMsxArmed := False;
  FMsxClick := False;
  FMsxDatePending := False;
  FMsxEnterFrom := -1;
  MSXSyncAutoKeys;
  FAY.Reset;
  FNMIRequest := False;
  FResetFrame := FFrameCount;
  CancelAutoType;
  FEventCount := 0;
  FBeeperLevel := 0;
  FSamplePos := 0;
  FAYTickT := 0;
  FRenderLine := 0;
  MSXPaging;
end;

{ The debugger's flat view of memory (FPage) has nothing to show for an MSX: its slots are not
  8K pages of one array. Peek and PeekRam go through the slots }
procedure TSpectrum.MSXPaging;
var
  I: Integer;
begin
  for I := 0 to 3 do
  begin
    FSlotBank[I] := NO_MEMORY;
    FSlotContended[I] := False;
  end;
  for I := 0 to 7 do
  begin
    FPage[I] := @FSamVoid[0];
    FPageRO[I] := True;
    FPageScreen[I] := False;
  end;
end;

procedure TSpectrum.MSXPsg(T: Integer; Reg, Value: Byte);
begin
  AddEvent(T, 1, Reg, Value);
end;

{ The click (bit 7 of PPI port C) is the EAR level of the speaker }
procedure TSpectrum.MSXClick(T: Integer; Level: Boolean);
begin
  FMsxClick := Level;
  MSXBeeper(T);
end;

{ The speaker: the click, and the tape's signal heard under it }
procedure TSpectrum.MSXBeeper(T: Integer);
var
  Level: Byte;
begin
  Level := 0;
  if FMsxClick then Level := 2;
  if FTape.Playing and FTape.Level then Level := Level or 4;
  AddEvent(T, 0, 0, Level);
end;

{ The tape runs in a 3.5 MHz machine's T-states (a TZX's pulse lengths): the MSX's clock is 3.579545 MHz }
function TSpectrum.MSXNow: Int64;
begin
  Result := FrameStartT + U(FCpu.T);
end;

function TSpectrum.MSXTapeT(ChipT: Integer): Integer;
begin
  Result := Int64(ChipT) * FSpeed * 3500000 div 3579545;
end;

function TSpectrum.MSXTapeIn(T: Integer): Boolean;
begin
  FTape.AdvanceTo(MSXTapeT(T));
  Result := FTape.Playing and FTape.Level;
end;

{ The tape moves while the user has pressed Play (or Auto play does it when the program starts the motor)
  and the program has the motor on }
procedure TSpectrum.MSXTapeUpdate(ChipT: Integer);
begin
  if FMsxArmed and FMsxHw.Motor and FTape.HasMore then
  begin
    if not FTape.Playing and not FTape.Resume(MSXTapeT(ChipT)) then FTape.Play(MSXTapeT(ChipT));
  end
  else if FTape.Playing then
  begin
    FTape.AdvanceTo(MSXTapeT(ChipT));
    FTape.Hold;
    MSXBeeper(ChipT);
  end;
end;

procedure TSpectrum.MSXMotor(T: Integer; On_: Boolean);
begin
  if On_ and AutoPlayTape and (FTape.Count > 0) then FMsxArmed := True;
  MSXTapeUpdate(T);
end;

{ Typing for the MSX: keys are MSXK_* (row * 8 + bit) }
procedure TSpectrum.MSXAutoType(Frames: Integer; const Keys: array of Integer);
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

procedure TSpectrum.MSXHoldKeys(Frames: Integer; const Keys: array of Integer);
begin
  MSXAutoType(Frames, Keys);
end;

procedure TSpectrum.MSXSyncAutoKeys;
begin
  if FAutoKeyPos < Length(FAutoKeys) then
    Move(FAutoKeys[FAutoKeyPos].Rows, FMsxHw.AutoMatrix, SizeOf(FMsxHw.AutoMatrix))
  else
    FillChar(FMsxHw.AutoMatrix, SizeOf(FMsxHw.AutoMatrix), $FF);
  // The ENTER for the date prompt
  if (FMsxEnterFrom >= 0) and (FFrameCount >= FMsxEnterFrom) and (FFrameCount < FMsxEnterFrom + 4) then
    FMsxHw.AutoMatrix[MSXK_RETURN div 8] := FMsxHw.AutoMatrix[MSXK_RETURN div 8] and not (1 shl (MSXK_RETURN mod 8));
end;

{ Text on the MSX's keyboard (international layout): letters go as capitals (SHIFT held; BASIC reads its
  keywords in either case), the symbols with or without SHIFT. \n is RETURN, \w a second's wait, ~ half a
  second's, \\ a backslash. }
function TSpectrum.MSXTypeText(const Text: string; out Error: string): Boolean;
const
  LETTERS: array['A'..'Z'] of Integer = (
    MSXK_A, MSXK_B, MSXK_C, MSXK_D, MSXK_E, MSXK_F, MSXK_G, MSXK_H, MSXK_I, MSXK_J, MSXK_K, MSXK_L,
    MSXK_M, MSXK_N, MSXK_O, MSXK_P, MSXK_Q, MSXK_R, MSXK_S, MSXK_T, MSXK_U, MSXK_V, MSXK_W, MSXK_X,
    MSXK_Y, MSXK_Z);
  DIGITS: array['0'..'9'] of Integer = (
    MSXK_0, MSXK_1, MSXK_2, MSXK_3, MSXK_4, MSXK_5, MSXK_6, MSXK_7, MSXK_8, MSXK_9);
  SHIFTED = '!@#$%^&*()_+:"<>?';
  SHIFTED_KEYS: array[1..Length(SHIFTED)] of Integer = (
    MSXK_1, MSXK_2, MSXK_3, MSXK_4, MSXK_5, MSXK_6, MSXK_7, MSXK_8, MSXK_9, MSXK_0, MSXK_MINUS, MSXK_EQUALS,
    MSXK_SEMICOLON, MSXK_QUOTE, MSXK_COMMA, MSXK_PERIOD, MSXK_SLASH);
  PLAIN = '-=;'',./[]\`';
  PLAIN_KEYS: array[1..Length(PLAIN)] of Integer = (
    MSXK_MINUS, MSXK_EQUALS, MSXK_SEMICOLON, MSXK_QUOTE, MSXK_COMMA, MSXK_PERIOD, MSXK_SLASH,
    MSXK_LBRACKET, MSXK_RBRACKET, MSXK_BACKSLASH, MSXK_GRAVE);
var
  I, P: Integer;
  Ch: Char;

  { Down for 4 frames, up for 4: the BIOS scans the keyboard once a frame and wants a key released first }
  procedure Tap(const Keys: array of Integer);
  begin
    MSXAutoType(4, Keys);
    MSXAutoType(4, []);
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
        'n', 'N': Tap([MSXK_RETURN]);
        'w', 'W': MSXAutoType(50, []);
        '\': Tap([MSXK_BACKSLASH]);
      else
        Error := 'unknown escape \' + Text[I];
        Exit;
      end;
    end
    else if Ch in ['a'..'z'] then Tap([MSXK_SHIFT, LETTERS[UpCase(Ch)]])
    else if Ch in ['A'..'Z'] then Tap([MSXK_SHIFT, LETTERS[Ch]])
    else if Ch in ['0'..'9'] then Tap([DIGITS[Ch]])
    else if Ch = '~' then MSXAutoType(25, [])
    else if Ch = ' ' then Tap([MSXK_SPACE])
    else if (Ch = #13) or (Ch = #10) then Tap([MSXK_RETURN])
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
        Tap([MSXK_SHIFT, SHIFTED_KEYS[P]]);
      end;
    end;
    Inc(I);
  end;
  Result := True;
end;

{ Load what is in the tape the way a user would: BLOAD"CAS:",R for a binary program, RUN"CAS:" for a BASIC
  one (the type is in the first block's description); the BIOS asks for nothing else, and the tape starts when
  the program switches the motor on (Auto play) }
procedure TSpectrum.MSXAutoLoad(FromDisk: Boolean);
var
  Err: string;
  I: Integer;
  Cmd: string;
begin
  // BASIC is ready after a couple of seconds; with the original disk interface the machine asks for the date first
  // (its ROM does, unless it boots a DOS disk): ENTER, when the prompt comes (ExecuteOneMSX), leaves it as it is.
  // QUANTIKA_DISK.ROM asks nothing
  FMsxDatePending := FMsxHw.HasDisk and FromDisk and not FMsxOwnDisk;
  if FromDisk then
  begin
    if FMsxHw.HasDisk then MSXAutoType(580, []) else MSXAutoType(190, []);
    Exit;       // the disk boots by itself
  end;
  // A program on tape may say BLOAD"NAME" without the CAS: device, which a machine with the disk interface sends to
  // the drive ("Disk I/O error"): the tape starts the machine without it, as a user holding
  // SHIFT at power-on does (the disk ROM looks at the key when it starts, a few seconds in)
  if FMsxHw.HasDisk then MSXAutoType(420, [MSXK_SHIFT]);
  MSXAutoType(130, []);
  Cmd := 'run"cas:"\n';
  for I := 0 to FTape.Count - 1 do
    if Pos('Binary', FTape[I].Description) = 1 then
    begin
      Cmd := 'bload"cas:",r\n';
      Break;
    end
    else if FTape[I].Kind = TZX_PULSES then Break;
  // A .tsx can say how it is loaded: TSX.LOAD (a custom info block, often empty), or the name it has been given, with
  // [RUN'CAS-'] or [BLOAD'CAS-',R] in it
  for I := 0 to FTape.Count - 1 do
    if (FTape[I].Kind = TZX_CUSTOM) and (Pos('TSX.LOAD: ', FTape[I].Text) = 1) and
       (Trim(Copy(FTape[I].Text, 11, MaxInt)) <> '') then
    begin
      Cmd := Trim(Copy(FTape[I].Text, 11, MaxInt)) + '\n';
      Break;
    end
    else if (FTape[I].Kind = TZX_CUSTOM) and (Pos('TOSEC.NAME: ', FTape[I].Text) = 1) then
      if Pos('BLOAD''CAS-'',R', FTape[I].Text) > 0 then Cmd := 'bload"cas:",r\n'
      else if Pos('RUN''CAS-''', FTape[I].Text) > 0 then Cmd := 'run"cas:"\n';
  MSXTypeText(Cmd, Err);
end;

function TSpectrum.ReadMemMSX(Addr: Word): Byte;
begin
  Result := FMsxHw.Read(Addr);
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

procedure TSpectrum.WriteMemMSX(Addr: Word; Value: Byte);
begin
  if (FMemBreakpoints > 0) and not FSuppressBreaks and
     ((FBreakFlags[Addr] and (BP_WRITE or BP_DISABLED)) = BP_WRITE) and ConditionHolds(Addr) then
  begin
    FBreakHit := True;
    FBreakKind := bkMemory;
    FBreakInstr := FInstrPC;
    FBreakReason := Format('Write breakpoint at %.4X (instruction at %.4X)', [Addr, FInstrPC]);
  end;
  FMsxHw.Write(Addr, Value);
end;

{ An I/O cycle takes 4 T-states and the MSX's hardware adds a wait state to it }
function TSpectrum.ReadPortMSX(Port: Word; var T: Integer): Byte;
begin
  Result := FMsxHw.InPort(Port, U(T) + 3);
  LogPort(Port, Result, False);
  CheckPortBreak(Port, False);
  Inc(T, 5);
end;

procedure TSpectrum.WritePortMSX(Port: Word; Value: Byte; var T: Integer);
begin
  LogPort(Port, Value, True);
  CheckPortBreak(Port, True);
  FMsxHw.OutPort(Port, Value, U(T) + 3);
  Inc(T, 5);
end;

procedure TSpectrum.ExecuteOneMSX;
begin
  if FTrackPrev then
  begin
    FPrevRegs := FCpu.GetRegs;
    FPrevPaging := PagingState;
  end;
  Inc(FStepCount);
  // The frame interrupt is a level: it stays until the status register is read
  if FMsxHw.IntLine and FCpu.IFF1 and FCpu.Interrupt then Exit;
  // The Philips disk ROM's date prompt (the CALL that prints it, at 5D48h in its page): ENTER in a few frames
  if FMsxDatePending and (FCpu.PC.W = $5D48) and (Pos('Disk', FMsxHw.Slots.Describe($5D48)) > 0) then
  begin
    FMsxDatePending := False;
    FMsxEnterFrom := FFrameCount + 20;
  end;
  FInstrPC := FCpu.PC.W;
  FSuppressBreaks := FProbeCovered;
  FCpu.Step;
  FSuppressBreaks := False;
  FMsxHw.Sync(U(FCpu.T));
end;

procedure TSpectrum.FinishFrameMSX;
begin
  FMsxHw.EndFrame;
  FTape.AdvanceTo(MSXTapeT(FInfo.FrameT));
  GenerateAudio;
  Inc(FCpuTBase, FrameLength);
  Dec(FCpu.T, FrameLength);
  FTape.EndFrame(MSXTapeT(FInfo.FrameT));
  if FPendingSpeed <> FSpeed then
  begin
    FCpu.T := FCpu.T div FSpeed * FPendingSpeed;
    FSpeed := FPendingSpeed;
    UpdateContend;
  end;
  FWD.Tick;
  FRenderLine := 0;
  Inc(FFrameCount);
  AdvanceAutoKeys;
  MSXSyncAutoKeys;
end;

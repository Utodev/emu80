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
  if FIsCPC then Result := FCPC.ReadRam(Addr) else Result := Peek(Addr);
end;

procedure TSpectrum.PokeRam(Addr: Word; Value: Byte);
begin
  if FIsCPC then FCPC.Write(Addr, Value) else Poke(Addr, Value);
end;

procedure TSpectrum.CPCPsg(T: Integer; Reg, Value: Byte);
begin
  AddEvent(T, 1, Reg, Value);
end;

function TSpectrum.CPCTapeIn(T: Integer): Boolean;
begin
  FTape.AdvanceTo(CPCTapeT(T));
  Result := FTape.Playing and FTape.Level;
end;

{ The tape moves while the user has pressed Play (or Auto play does it when
  the program starts the motor) and the program has the motor on }
procedure TSpectrum.CPCTapeUpdate(ChipT: Integer);
begin
  if FCPCArmed and FCPC.Motor and FTape.HasMore then
  begin
    if not FTape.Playing then FTape.Play(CPCTapeT(ChipT));
  end
  else if FTape.Playing then
  begin
    FTape.AdvanceTo(CPCTapeT(ChipT));
    FTape.Stop;
  end;
end;

{ The cassette output (REC): the signal's edges, while the motor is on, in the
  tape's time (a 3.5 MHz machine's T-states) }
procedure TSpectrum.CPCTapeOut(T: Integer; Level: Boolean);
begin
  if FRecorder.Active and FCPC.Motor then
    FRecorder.Edge(Int64(FCpuTBase) * 7 div 8 + CPCTapeT(T));
end;

procedure TSpectrum.CPCMotor(T: Integer; On_: Boolean);
begin
  if not On_ and FRecorder.Active then FRecorder.Flush;
  if On_ and AutoPlayTape and (FTape.Count > 0) then FCPCArmed := True;
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
  access in its last T-states }
function TSpectrum.ReadPortCPC(Port: Word; var T: Integer): Byte;
begin
  Result := FCPC.InPort(Port, U(T) + 3);
  LogPort(Port, Result, False);
  CheckPortBreak(Port, False);
  Inc(T, 4);
  if FContend then T := (T + 3) and not 3;
end;

procedure TSpectrum.WritePortCPC(Port: Word; Value: Byte; var T: Integer);
begin
  LogPort(Port, Value, True);
  CheckPortBreak(Port, True);
  FCPC.OutPort(Port, Value, U(T) + 3);
  if ((Port and $C000) = $4000) or ((Port and $2000) = 0) then CPCPaging;
  Inc(T, 4);
  if FContend then T := (T + 3) and not 3;
end;

procedure TSpectrum.ExecuteOneCPC;
begin
  if FTrackPrev then
  begin
    FPrevRegs := FCpu.GetRegs;
    FPrevPaging := PagingState;
  end;
  Inc(FStepCount);
  if FCPC.IntLine and FCpu.IFF1 and FCpu.Interrupt then
    FCPC.IntAck
  else
  begin
    FInstrPC := FCpu.PC.W;
    FSuppressBreaks := FProbeCovered;
    FCpu.Step;
    FSuppressBreaks := False;
  end;
  // The Gate Array stretches an instruction to a whole number of microseconds
  if FContend then FCpu.T := (FCpu.T + 3) and not 3;
  FCPC.Sync(U(FCpu.T));
end;

procedure TSpectrum.FinishFrameCPC;
begin
  FCPC.EndFrame(FInfo.FrameT);
  if FRecorder.Active then FRecorder.Idle(Int64(FCpuTBase) * 7 div 8 + CPCTapeT(FInfo.FrameT));
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
    if F.Size < SNA_HEADER then raise Exception.Create('Invalid CPC snapshot');
    F.ReadBuffer(H, SizeOf(H));
    if not CompareMem(@H[0], PChar('MV - SNA'), 8) then raise Exception.Create('Not a CPC snapshot');
    KB := H[$6B] or (H[$6C] shl 8);
    Kind := H[$6D];
    if H[$10] >= 3 then
    begin
      if KB = 0 then
        raise Exception.Create('This snapshot keeps its memory in compressed chunks, which emu80 doesn''t read');
    end;
    if (KB <> 64) and (KB <> 128) then
      raise Exception.CreateFmt('A CPC snapshot with %d KB of memory isn''t supported (64 or 128)', [KB]);
    if Kind in [4, 5, 6] then
      raise Exception.Create('A snapshot of a CPC+ or a GX4000: emu80 emulates the original CPC range only');
    Size := KB * 1024;
    if F.Size - SNA_HEADER < Size then raise Exception.Create('The snapshot is cut short');
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

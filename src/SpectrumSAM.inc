{ SpectrumSAM.inc: the SAM Coupe in TSpectrum (included by Spectrum.pas).
  The ASIC's registers and the picture are TSam (Sam.pas); here are the parts
  that join it to what the Spectrum models share: the Z80 and its bus, the
  memory pages the CPU reads and writes, the tape and the beeper. The memory
  is the same array of 16K banks as the Spectrum's (32 of them, 512K), and
  the ROM (32K) two of its ROM banks: ROM0 and ROM1. }

procedure TSpectrum.SetupSAM;
var
  S: TFileStream;
  FileName: string;
begin
  FileName := RomPath(0);
  if not FileExists(FileName) then
    raise Exception.CreateFmt(_('ROM file not found: %s') + LineEnding + LineEnding +
      _('The SAM Coup'#$C3#$A9'''s ROM is not distributed with emu80: put the 32K ROM (version 3.0) in the ROM ' +
      'folder as samcoupe.rom, or choose the file in Settings > Common > ROMs.'), [FileName]);
  S := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    if S.Size < 2 * SizeOf(TBank) then
      raise Exception.CreateFmt(_('%s is not a SAM Coupe ROM (it should be 32K)'), [FileName]);
    FillChar(FRom[0], SizeOf(TBank), $FF);
    FillChar(FRom[1], SizeOf(TBank), $FF);
    S.ReadBuffer(FRom[0], SizeOf(TBank));
    S.ReadBuffer(FRom[1], SizeOf(TBank));
  finally
    S.Free;
  end;
  if FSam = nil then FSam := TSam.Create;
  FSam.SetRam(@FRam[0], FSamKB div 16);
  FillChar(FSamVoid, SizeOf(FSamVoid), $FF);
  FTape.StopIf48K := False;
  FDiv.UseMemory(nil, nil);
  FDivOn := False;
  FCurrahOn := False;
  FCpu.Z80N := False;
  Z80NMnemonics := False;
  FDiv.ControlReadable := False;
  FDiv.NextEntries := False;
end;

procedure TSpectrum.SetSamMemory(KB: Integer);
begin
  if ((KB <> 256) and (KB <> 512)) or (KB = FSamKB) then Exit;
  FSamKB := KB;
  if FIsSAM then
  begin
    FSam.SetRam(@FRam[0], KB div 16);
    Reset(True);
  end;
end;

procedure TSpectrum.SAMReset(Hard: Boolean);
var
  I: Integer;
begin
  if Hard then
    for I := 0 to SAM_PAGES - 1 do FillChar(FRam[I], SizeOf(TBank), 0);
  FNextSpeed := 1;
  SetSpeed(FUserSpeed);
  FCpu.Reset(Hard);
  FCpu.T := 0;
  FSam.Reset;
  FSaa.Reset;
  FSaaAddr := 0;
  FNMIRequest := False;
  FResetFrame := FFrameCount;
  FBorder := 0;
  FUlaOut := 0;
  CancelAutoType;
  SAMSyncAutoKeys;
  FSamPlayFrame := -1;
  FreeAndNil(FSamSwapDisk);
  FRenderLine := 0;
  FRenderCell := 0;
  FEventCount := 0;
  FBeeperLevel := 0;
  FSamplePos := 0;
  FAYTickT := 0;
  SAMPaging;
end;

{ What the CPU sees in its four 16K sections, from LMPR and HMPR }
procedure TSpectrum.SAMPaging;
var
  Section, Page, Slot: Integer;
  ReadOnly: array[0..3] of Boolean;
begin
  for Section := 0 to 3 do
  begin
    Page := FSam.SectionPage(Section, ReadOnly[Section]);
    case Page of
      SAM_ROM0:
        begin
          FSlotBank[Section] := -1;
          FSlot[Section] := @FRom[0];
        end;
      SAM_ROM1:
        begin
          FSlotBank[Section] := -2;
          FSlot[Section] := @FRom[1];
        end;
      SAM_NO_RAM:
        begin
          FSlotBank[Section] := NO_MEMORY;
          FSlot[Section] := @FSamVoid;
        end;
    else
      FSlotBank[Section] := Page;
      FSlot[Section] := @FRam[Page];
    end;
    FSlotContended[Section] := False;
  end;
  for Slot := 0 to 7 do
  begin
    FPage[Slot] := @FSlot[Slot shr 1]^[(Slot and 1) * $2000];
    FPageRO[Slot] := ReadOnly[Slot shr 1];
    FPageScreen[Slot] := False;
  end;
end;

{ Every row of the picture is drawn when the beam has gone past its screen }
procedure TSpectrum.SAMRenderUpTo(T: Integer);
var
  Start, N: Integer;
begin
  FSam.FlashOn := FFlashOn;
  while FRenderLine < SCREEN_HEIGHT do
  begin
    Start := FSam.RowStartT(FRenderLine, BORDER_TOP);
    if T < Start then Exit;
    N := (T - Start) div 4;
    if N > SAM_CELLS then N := SAM_CELLS;
    if N > FRenderCell then
    begin
      FSam.DrawCells(FRenderLine, BORDER_TOP, BORDER_LEFT, FRenderCell, N, @FFrameBuffer[FRenderLine * FB_WIDTH]);
      FRenderCell := N;
    end;
    if FRenderCell < SAM_CELLS then Exit;
    Inc(FRenderLine);
    FRenderCell := 0;
  end;
end;

{ The ports the SAM decodes are 224-255 (the low byte); the keyboard and the
  ASIC's registers answer to any address with that low byte, the rest of the
  address being data (the keyboard rows, the CLUT entry) }
function TSpectrum.ReadPortSAM(Port: Word; var T: Integer): Byte;
var
  High3: Byte;
begin
  Result := $FF;
  // The ASIC takes the port access in its own time
  if FContend then Inc(T, FSam.WaitStates(T));
  // The floppy controller: E0-E7 drive 1, F0-F7 drive 2
  if (Port and $E8) = $E0 then
  begin
    FWD.SetTime(FrameStartT + U(T));
    Result := FWD.ReadReg(Port);
    LogPort(Port, Result, False);
    CheckPortBreak(Port, False);
    Inc(T, 4);
    Exit;
  end;
  case Port and $FF of
    $F8:
      // The beam's place, as with no light pen: A8 low the X (the first two bits are the CLUT
      // address's bit and the MIDI out's busy bit), high the Y, the screen's first line being 0
      if (Port and $100) = 0 then
        Result := (((U(T) mod SAM_LINE_T) * 256) div SAM_LINE_T) and $FC
      else
        Result := (U(T) div SAM_LINE_T - 64) and $FF;
    $F9:
      begin
        // The interrupts (0 = requesting) and the keyboard's upper keys
        Result := FSam.InterruptStatus(U(T));
        FSam.ReadKeyboard(Port shr 8, High3);
        Result := (Result and $1F) or High3;
      end;
    $1F:
      if FSamJoyOn then Result := KempstonState else Result := 0;
    $EF:
      if FSamClockOn then Result := FSam.ClockRead(Port shr 8);
    $FA: Result := FSam.LMPR;
    $FB: Result := FSam.HMPR;
    $FC: Result := FSam.VMPR or $80;   // bit 7: MIDI IN, idle high
    $FE:
      begin
        // Bits 5 (the light pen) and 7 high, and 6 (EAR) high unless the signal is low
        Result := FSam.ReadKeyboard(Port shr 8, High3) or $E0;
        // The mouse answers with the keys' last row
        if FSamMouseOn and ((Port shr 8) = $FF) then
          Result := Result and FSam.MouseRead(Int64(FFrameCount) * SAM_FRAME_T + T);
        FTape.AdvanceTo(T);
        Inc(FTapeReads);
        // EAR: the tape's signal, or what is sent out at the beeper's bit
        if FTape.Playing then
        begin
          if not FTape.Level then Result := Result and not $40;
        end
        else if (FUlaOut and $10) = 0 then
          Result := Result and not $40;
      end;
  end;
  LogPort(Port, Result, False);
  CheckPortBreak(Port, False);
  Inc(T, 4);
end;

procedure TSpectrum.WritePortSAM(Port: Word; Value: Byte; var T: Integer);
begin
  if FContend then Inc(T, FSam.WaitStates(T));
  LogPort(Port, Value, True);
  CheckPortBreak(Port, True);
  if (Port and $E8) = $E0 then
  begin
    FWD.SetTime(FrameStartT + U(T));
    FWD.WriteReg(Port, Value);
    Inc(T, 4);
    Exit;
  end;
  // The picture is drawn lazily: up to now it is with the old registers
  if ((Port and $FF) in [$F8, $FB, $FC, $FE]) then SAMRenderUpTo(U(T));
  case Port and $FF of
    $EF:
      if FSamClockOn then FSam.ClockWrite(Port shr 8, Value);
    $F8: FSam.SetClut(Port shr 8, Value);
    $F9: FSam.LineInt := Value;
    $FA:
      begin
        FSam.LMPR := Value;
        SAMPaging;
      end;
    $FB:
      begin
        FSam.HMPR := Value;
        SAMPaging;
      end;
    $FC: FSam.VMPR := Value;
    $FF:
      // The SAA1099: with A8 set the register to write, else its data
      if (Port and $100) <> 0 then FSaaAddr := Value and 31
      else AddEvent(U(T), 5, FSaaAddr, Value);
    $FE:
      begin
        FSam.Border := Value;
        FUlaOut := Value;
        // Bit 4 is the beeper, bit 3 the MIC output
        UpdateBeeper(U(T));
        if FRecorder.Active and (((Value and $18) <> 0) <> FMicLevel) then
        begin
          FMicLevel := not FMicLevel;
          // The 6 MHz machine's T-states in the 3.5 MHz ones a tape file counts
          FRecorder.Edge((FCpuTBase + T) * 7 div 12);
        end;
      end;
  end;
  Inc(T, 4);
end;

{ Typing for the SAM: keys are SAMK_* (row * 8 + bit) }
procedure TSpectrum.SAMAutoType(Frames: Integer; const Keys: array of Integer);
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

procedure TSpectrum.SAMSyncAutoKeys;
var
  Row: Integer;
begin
  if FSam = nil then Exit;
  for Row := 0 to 8 do
    if FAutoKeyPos < Length(FAutoKeys) then FSam.AutoKeys[Row] := not FAutoKeys[FAutoKeyPos].Rows[Row]
    else FSam.AutoKeys[Row] := 0;
end;

{ Text on the SAM's keyboard: every character its keyboard can make (SHIFT and SYMBOL as the
  ROM's key table has them). \n is RETURN, \w a second's wait, ~ half a second's, \\ and \~ a
  backslash and a tilde. }
function TSpectrum.SAMTypeText(const Text: string; out Error: string): Boolean;
var
  I, Key, Modifier: Integer;
  Ch: Char;

  { Down for 4 frames, up for 6: the ROM wants a key released before it takes
    a repeat of it }
  procedure Tap(const Keys: array of Integer);
  begin
    SAMAutoType(4, Keys);
    SAMAutoType(6, []);
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
        'n', 'N': Tap([SAMK_RETURN]);
        'w', 'W': SAMAutoType(50, []);
        '\': Tap([SAMK_SHIFT, SAMK_INV]);
        '~': Tap([SAMK_SHIFT, SAMK_0]);
      else
        Error := 'unknown escape \' + Text[I];
        Exit;
      end;
    end
    else if Ch = '~' then SAMAutoType(25, [])
    else if (Ch = #13) or (Ch = #10) then Tap([SAMK_RETURN])
    else if SamKeysForChar(Ch, Key, Modifier) then
    begin
      if Modifier >= 0 then Tap([Modifier, Key]) else Tap([Key]);
    end
    else
    begin
      Error := 'can''t type "' + Ch + '"';
      Exit;
    end;
    Inc(I);
  end;
  Result := True;
end;

{ Load what is inserted the way a user would: for a disk F9 (BOOT) once the ROM
  has shown its first screen and a key has taken it to BASIC; for a tape LOAD
  "" and Play }
procedure TSpectrum.SAMAutoLoad(FromDisk: Boolean);
var
  Err: string;
begin
  // The ROM's first screen waits for a key: RETURN takes it to BASIC
  SAMAutoType(150, []);
  SAMAutoType(4, [SAMK_RETURN]);
  SAMAutoType(40, []);
  if FromDisk then
    SAMAutoType(4, [SAMK_F9])
  else
  begin
    SAMTypeText('load ""\n', Err);
    // The tape starts moving after the command, well before the ROM's first edge
    FSamPlayFrame := FFrameCount + 150 + 4 + 40 + 9 * 10 + 20;
  end;
end;

{ A SAMDOS disk goes in drive 1 and boots, and when the DOS is in memory (its menu is up) the disk
  the user asked for takes its place }
procedure TSpectrum.SamDosThen(Dos, Disk: TDiskImage);
begin
  InsertDiskAt(0, Dos);
  AutoLoad(True);
  FSamSwapDisk := Disk;
  FSamSwapFrame := FFrameCount + 150 + 4 + 40 + 4 + 200;
end;

{ The trap of SAMDOS's loading: when the ROM asks the DOS to load a file (its hook 82, at the
  routine of the ROM 1 that calls it) and the file is on a SAMDOS disk in a drive, with fast disk
  access on, the file goes into memory at once and the ROM goes on as if the DOS had loaded it.
  Only whole files: the DOS reads a file in pieces from where it was left, which a trap can't know.
  The header was read before, by the DOS; its name is in the loaded header (at 4B50), the
  destination in HL and the length (in pages and a remainder) in CDE. }
procedure TSpectrum.SAMCheckTraps;
const
  DOSLD = $E2B6;
  HDL = $4B50;
var
  Name: string;
  I, D, Len, Addr, K, Page, Pages: Integer;
  Disk: TDiskImage;
  FS: TSamdosDisk;
  Body: TBytes;
  Found: Boolean;
  Cyl: Integer;
begin
  Cyl := 0;
  if (FCpu.PC.W <> DOSLD) or FWD.Timed or (FSlotBank[3] <> -2) then Exit;
  if (Peek(DOSLD) <> $CF) or (Peek(DOSLD + 1) <> $82) then Exit;
  // A file that runs when it has loaded (an AUTO loader, or a game's code) takes the disk over with its own
  // routines, which expect the DOS's state: the DOS loads it
  if (Peek(HDL + 31 + 6) <> $FF) and (Peek(HDL) = SAMDOS_TYPE_CODE) then Exit;
  Name := '';
  for I := 1 to 10 do Name := Name + Chr(Peek(HDL + I) and $7F);
  Name := TrimRight(Name);
  Len := FCpu.BC.L * 16384 + (FCpu.DE.W and $3FFF);
  // BOOT's file: what it loads takes over the disk with routines of its own that expect the DOS's own state
  if SameText(Name, 'AUTO') then Exit;
  Found := False;
  for D := 0 to 1 do
  begin
    Disk := DiskAt(D);
    if (Disk = nil) or not LooksLikeSamdos(Disk) then Continue;
    FS := TSamdosDisk.Create(Disk);
    try
      I := FS.FindFile(Name);
      if (I >= 0) and (FS[I].Length = Len) then
      begin
        Body := FS.ReadFile(I);
        Found := Length(Body) >= Len;
        Cyl := FS.LastCylinder(I);
      end;
    finally
      FS.Free;
    end;
    if Found then Break;
  end;
  if not Found then Exit;
  Addr := FCpu.HL.W;
  // The destination is in page form: from section C on, the pages one after the other from HMPR's
  // (the ROM 1 is over section D just now, so the RAM is written where it is)
  if Addr < $8000 then Exit;
  Pages := FSamKB div 16;
  for K := 0 to Len - 1 do
  begin
    Page := ((FSam.HMPR and $1F) + (Addr - $8000) shr 14) and $1F;
    if Page < Pages then FRam[Page][Addr and $3FFF] := Body[K];
    Inc(Addr);
  end;
  // As the DOS leaves them: the address in page form (8000-BFFF), HMPR on the page it ended in
  K := Addr - $8000;
  FCpu.HL.W := $8000 + (K and $3FFF);
  FSam.HMPR := (FSam.HMPR and $E0) or (((FSam.HMPR and $1F) + (K shr 14)) and $1F);
  SAMPaging;
  FWD.HeadMovedTo(D, Cyl);
  FCpu.F := FCpu.F or FLAG_C;
  FCpu.PC.W := DOSLD + 2;           // the RET after the DOS hook
  Inc(FSamTrapHits);
end;

{ The SAM Coupe's ASIC (registers and colours) and its sound generator into S
  (Save) or from it }
procedure TSpectrum.SAMStateIO(S: TStream; Save: Boolean);

  procedure IO(var Buf; Size: Integer);
  begin
    if Save then S.WriteBuffer(Buf, Size) else S.ReadBuffer(Buf, Size);
  end;

var
  Regs: array[0..31] of Byte;
  I: Integer;
begin
  IO(FSam.LMPR, 1); IO(FSam.HMPR, 1); IO(FSam.VMPR, 1);
  IO(FSam.Border, 1); IO(FSam.LineInt, 1);
  IO(FSam.Clut, SizeOf(FSam.Clut));
  IO(FSaaAddr, 1);
  for I := 0 to 31 do Regs[I] := FSaa.GetRegister(I);
  IO(Regs, SizeOf(Regs));
  if not Save then
  begin
    FSaa.Reset;
    for I := 0 to 27 do FSaa.WriteRegister(I, Regs[I]);
    FSaa.WriteRegister(28, Regs[28]);
    FUlaOut := FSam.Border;
  end;
end;

{ A snapshot of the SAM Coupe: the RAM, the CPU, the ASIC, the SAA1099. What is not
  in it: the disks and the tape (they stay as they are inserted) }
procedure TSpectrum.SAMSnapIO(S: TStream; Save: Boolean);

  procedure IO(var Buf; Size: Integer);
  begin
    if Save then S.WriteBuffer(Buf, Size) else S.ReadBuffer(Buf, Size);
  end;

var
  Banks, FrameT: Integer;
  EIJust: Boolean;
begin
  Banks := RamBanksUsed;
  IO(Banks, SizeOf(Banks));
  if Banks <> RamBanksUsed then raise Exception.Create(_('Not a snapshot of this machine'));
  IO(FRam, Banks * SizeOf(TBank));
  IO(FCpu.A, 1); IO(FCpu.F, 1); IO(FCpu.A_, 1); IO(FCpu.F_, 1);
  IO(FCpu.BC, 2); IO(FCpu.DE, 2); IO(FCpu.HL, 2); IO(FCpu.BC_, 2); IO(FCpu.DE_, 2);
  IO(FCpu.HL_, 2); IO(FCpu.IX, 2); IO(FCpu.IY, 2); IO(FCpu.SP, 2); IO(FCpu.PC, 2);
  IO(FCpu.WZ, 2);
  IO(FCpu.I, 1); IO(FCpu.R, 1); IO(FCpu.R7, 1); IO(FCpu.IM, 1);
  IO(FCpu.IFF1, 1); IO(FCpu.IFF2, 1); IO(FCpu.Halted, 1); IO(FCpu.Q, 1); IO(FCpu.LastQ, 1);
  EIJust := FCpu.EIJust;
  IO(EIJust, 1);
  FCpu.EIJust := EIJust;
  FrameT := U(FCpu.T);
  IO(FrameT, SizeOf(FrameT));
  if not Save then FCpu.T := FrameT * FSpeed;
  IO(FFlashCounter, SizeOf(FFlashCounter)); IO(FFlashOn, 1);
  SAMStateIO(S, Save);
end;

function TSpectrum.SamRegister(Reg: Integer): Byte;
begin
  Result := 0;
  if FSam = nil then Exit;
  case Reg of
    $F9: Result := FSam.LineInt;
    $FA: Result := FSam.LMPR;
    $FB: Result := FSam.HMPR;
    $FC: Result := FSam.VMPR;
    $FE: Result := FSam.Border;
    $1F9: Result := FSam.InterruptStatus(U(FCpu.T)) or $E0;
    $100..$10F: Result := FSam.Clut[Reg - $100];
    $200..$21F: Result := FSaa.GetRegister(Reg - $200);
  end;
end;

procedure TSpectrum.SetSamRegister(Reg: Integer; Value: Byte);
var
  T: Integer;
begin
  if FSam = nil then Exit;
  T := FCpu.T;
  case Reg of
    $F9, $FA, $FB, $FC, $FE: WritePortSAM(Reg, Value, T);
    $100..$10F: WritePortSAM($F8 + (Reg - $100) * $100, Value, T);
    $200..$21F: FSaa.WriteRegister(Reg - $200, Value);
  end;
end;

{ What a 16K section can hold, for the debugger's slot lists: ROM0 (-1) in section A, ROM1 (-2)
  in D, and in any a page of RAM (0 to 31, or 15 on a 256K machine). The pages come in
  pairs: B is the page after A's, D the one after C's. }
function TSpectrum.SamSlotCanHold(Slot, What: Integer): Boolean;
begin
  Result := False;
  if (FSam = nil) or (Slot < 0) or (Slot > 3) then Exit;
  if What < 0 then
    Result := ((Slot = 0) and (What = -1)) or ((Slot = 3) and (What = -2))
  else
    Result := What < FSamKB div 16;
end;

{ Puts it there as a program would, by writing LMPR or HMPR }
function TSpectrum.SetSamSlot(Slot, What: Integer): Boolean;
var
  L, H: Byte;
begin
  Result := SamSlotCanHold(Slot, What);
  if not Result then Exit;
  L := FSam.LMPR;
  H := FSam.HMPR;
  case Slot of
    0:
      if What < 0 then L := L and not $20
      else L := (L and $C0) or $20 or (What and $1F);
    1: L := (L and $E0) or ((What - 1) and $1F);
    2: H := (H and $E0) or (What and $1F);
  else
    if What = -2 then L := L or $40
    else
    begin
      L := L and not $40;
      H := (H and $E0) or ((What - 1) and $1F);
    end;
  end;
  SetSamRegister($FA, L);
  SetSamRegister($FB, H);
end;

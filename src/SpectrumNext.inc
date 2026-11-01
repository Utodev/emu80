{ SpectrumNext.inc: the ZX Spectrum Next part of TSpectrum (included by
  Spectrum.pas). Its registers, MMU and ports follow the distribution's
  docs/extra-hw/io-port-system/registers.txt and ports.txt. emu80 boots
  NextZXOS directly, as the firmware would leave the machine: the ROMs from
  the distribution's machines/next folder, +3 timing and paging, the DivMMC
  with automatic mapping. }

function TSpectrum.IsNext: Boolean;
begin
  Result := FInfo.Memory = mkZXNext;
end;

function TSpectrum.RamBanksUsed: Integer;
begin
  case FInfo.Memory of
    mkZXNext: Result := RAM_BANKS;
    mkZXUno: Result := ZXUNO_PAGES;
    mkSAM: Result := SAM_PAGES;
  else
    Result := 8;
  end;
end;

function TSpectrum.TurboOn: Boolean;
begin
  Result := TurboSound or (IsNext and ((FNextReg[$08] and 2) <> 0));
end;

procedure TSpectrum.NextLoadRoms;
var
  Dir: string;
  S: TFileStream;
  I: Integer;
begin
  FillChar(FNextSram, SizeOf(FNextSram), 0);
  if FNextFirmware then
  begin
    // The FPGA's boot ROM: it loads TBBLUE.FW from the card, which loads
    // the ROMs of the chosen machine into the SRAM
    if not FileExists(FNextBootRomFile) then
      raise Exception.CreateFmt(_('ROM file not found: %s'), [FNextBootRomFile]);
    S := TFileStream.Create(FNextBootRomFile, fmOpenRead or fmShareDenyWrite);
    try
      FillChar(FNextBootRom, SizeOf(FNextBootRom), $FF);
      S.Read(FNextBootRom, SizeOf(FNextBootRom));
    finally
      S.Free;
    end;
    Exit;
  end;
  Dir := IncludeTrailingPathDelimiter(FNextDir) + 'machines' + PathDelim + 'next' + PathDelim;
  if not FileExists(Dir + 'enNextZX.rom') then
    raise Exception.CreateFmt(_('ROM file not found: %s'), [Dir + 'enNextZX.rom']);
  // NextZXOS: four 16K ROMs (128K editor, syntax, +3DOS, 48K BASIC)
  S := TFileStream.Create(Dir + 'enNextZX.rom', fmOpenRead or fmShareDenyWrite);
  try
    for I := 0 to 3 do S.Read(FNextSram[I], SizeOf(TBank));
  finally
    S.Free;
  end;
  // Its DivMMC firmware, at the start of SRAM bank 4
  S := TFileStream.Create(Dir + 'enNxtmmc.rom', fmOpenRead or fmShareDenyWrite);
  try
    S.Read(FNextSram[4], $2000);
  finally
    S.Free;
  end;
  // Its Multiface, at the start of bank 5 (its RAM follows)
  if FileExists(Dir + 'enNextMf.rom') then
  begin
    S := TFileStream.Create(Dir + 'enNextMf.rom', fmOpenRead or fmShareDenyWrite);
    try
      S.Read(FNextSram[5], $2000);
    finally
      S.Free;
    end;
  end;
end;

{ A 16K bank of the SRAM: the first 16 (ROMs, DivMMC) or the RAM after them }
function TSpectrum.NextSramBank(Bank: Integer): PBank;
begin
  Bank := Bank and $7F;
  if Bank < 16 then Result := @FNextSram[Bank]
  else if Bank - 16 < RAM_BANKS then Result := @FRam[Bank - 16]
  else Result := @FNoMem;
end;

procedure TSpectrum.NextReset(Hard: Boolean);
const
  MMU_RESET: array[0..7] of Byte = (255, 255, 10, 11, 4, 5, 0, 1);
var
  I: Integer;
  Keep: array[0..255] of Byte;
begin
  if Hard then
  begin
    for I := 0 to RAM_BANKS - 1 do FillChar(FRam[I], SizeOf(TBank), 0);
    // Without the firmware to load them again, the ROMs stay
    if FNextFirmware then FillChar(FNextSram, SizeOf(FNextSram), 0)
    else
    begin
      FillChar(FNextSram[5][$2000], $2000, 0);
      for I := 6 to 15 do FillChar(FNextSram[I], SizeOf(TBank), 0);
    end;
  end;
  Move(FNextReg, Keep, SizeOf(Keep));
  FillChar(FNextReg, SizeOf(FNextReg), 0);
  FNextReg[$00] := FNextMachineId; // $08: an emulator (its firmware shows the TBBlue logo)
  FNextReg[$01] := $32;            // core 3.02.01 (as the distribution's)
  FNextReg[$0E] := $01;
  FNextReg[$0F] := $02;            // issue 4 board
  if Hard then FNextReg[$02] := 2 else FNextReg[$02] := 1;
  if FNextFirmware and Hard then
  begin
    // Power on: the boot ROM at 0000, the machine in configuration mode
    FNextBootOn := True;
    FNextReg[$03] := $00;
    FNextReg[$04] := 0;
  end
  else if FNextFirmware then
    FNextReg[$03] := Keep[$03] and $77   // a soft reset keeps the machine the firmware chose
  else
    FNextReg[$03] := $33;          // +3 display timing, +3 machine (NextZXOS)
  FNextReg[$05] := $40;            // joystick 1 Kempston
  FNextReg[$06] := $A0;
  // Without the firmware: its M1 (Multiface) and DRIVE (DivMMC) buttons on
  if not FNextFirmware then FNextReg[$06] := $A0 or $18;
  FNextReg[$08] := $1A;            // internal speaker, DACs, TurboSound
  FNextReg[$0A] := $11;            // DivMMC automap, default mouse dpi
  FNextReg[$0B] := $01;
  FNextReg[$12] := 8;              // Layer 2 banks
  FNextReg[$13] := 11;
  FNextReg[$14] := $E3;            // global transparency
  FNextReg[$4A] := $E3;
  FNextReg[$4B] := $E3;
  FNextReg[$4C] := $0F;
  FNextReg[$6E] := $6C;
  FNextReg[$6F] := $0C;
  FNextReg[$C4] := $81;            // ULA interrupt enabled
  FNextReg[$B8] := $83;            // DivMMC entry points: 0000 always, 0008 and 0038 with ROM 3
  FNextReg[$B9] := $01;
  FNextReg[$BA] := $00;
  FNextReg[$BB] := $CD;
  if not Hard then
  begin
    // Kept over a soft reset
    FNextReg[$8C] := (Keep[$8C] and $0F) or ((Keep[$8C] and $0F) shl 4);
    FNextReg[$8F] := Keep[$8F];
    FNextReg[$08] := Keep[$08] and $3F;
    FNextReg[$04] := Keep[$04];
    // The firmware's choices (joystick, 50/60 Hz, mouse...) stay too
    FNextReg[$05] := Keep[$05];
    FNextReg[$06] := Keep[$06];
    FNextReg[$0A] := Keep[$0A];
  end;
  for I := 0 to 7 do
  begin
    FNextMMU[I] := MMU_RESET[I];
    FNextReg[$50 + I] := MMU_RESET[I];
  end;
  FNextSel := 0;
  FPortDFFD := 0;
  FMfNmi := False;
  FMfOn := False;
  FMfInvisible := True;
  FNmiStackless := False;
  FDiv.NmiButton := False;
  FNexOpen := False;
  FNexData := nil;
  FNexName := '';
  NextSetDivEntries;
  // Display: palettes, clips, sprites, copper (the palettes keep their
  // colours over a soft reset)
  if Hard then NextVideoReset
  else
  begin
    FNextL2Port := 0;
    FNextL2Offset := 0;
    FillChar(FSprAttr, SizeOf(FSprAttr), 0);
    FCopperStopped := True;
  end;
  FillChar(FNextDac, SizeOf(FNextDac), $80);
  FDmaActive := False;
  FDmaQueueLen := 0;
  FDmaReadMask := $7F;
  FDmaTimingA := 3;
  FDmaTimingB := 3;
  FNextSpeed := 1;
  SetSpeed(FUserSpeed);
end;

const
  { The clip window NR 18-1B write }
  CLIP_OF_REG: array[$18..$1B] of Integer = (CLIP_L2, CLIP_SPR, CLIP_ULA, CLIP_TM);

function TSpectrum.NextReadReg(Reg: Byte): Byte;
var
  Rel: Integer;
begin
  case Reg of
    $03: Result := FNextReg[$03] and $7F;
    $07: Result := (FNextReg[$07] and 3) or ((FNextReg[$07] and 3) shl 4);
    $1E, $1F:
      begin
        // The line being drawn, 0 = the first line of the paper (moved by NR 64)
        Rel := (U(FCpu.T) - FInfo.PaperTopT + FInfo.FrameT) mod FInfo.FrameT;
        Rel := (Rel div FInfo.LineT + FNextReg[$64]) mod (FInfo.FrameT div FInfo.LineT);
        if Reg = $1E then Result := Rel shr 8 else Result := Rel and $FF;
      end;
    $22: Result := (FNextReg[$22] and 7) or (Ord(FCpu.T < FInfo.InterruptLength * FSpeed) shl 7);
    $50..$57: Result := FNextMMU[Reg - $50];
    $8E:
      begin
        Result := ((FPortDFFD and 1) shl 7) or ((FPort7FFD and 7) shl 4) or 8 or
          ((FPort1FFD and 1) shl 2);
        if (FPort1FFD and 1) = 0 then
          Result := Result or ((FPort1FFD shr 1) and 2) or ((FPort7FFD shr 4) and 1)
        else
          Result := Result or ((FPort1FFD shr 1) and 3);
      end;
    $C0: Result := (FNextReg[$C0] and $F9) or ((FCpu.IM and 3) shl 1);
    $B0: Result := ExtKeys and $FF;
    $B1: Result := ExtKeys shr 8;
    $18..$1B: Result := FNextClip[CLIP_OF_REG[Reg], FNextClipIdx[CLIP_OF_REG[Reg]]];
    $1C: Result := FNextClipIdx[CLIP_L2] or (FNextClipIdx[CLIP_SPR] shl 2) or
      (FNextClipIdx[CLIP_ULA] shl 4) or (FNextClipIdx[CLIP_TM] shl 6);
    $34: Result := FSprIndex;
    $41: Result := FNextPal[(FNextReg[$43] shr 4) and 7, FNextReg[$40]] shr 1;
    $44: Result := (FNextPal[(FNextReg[$43] shr 4) and 7, FNextReg[$40]] and 1) or
      ((FNextPal[(FNextReg[$43] shr 4) and 7, FNextReg[$40]] shr 2) and $80);
    $69: Result := (Ord((FNextL2Port and 2) <> 0) shl 7) or ((FPort7FFD and 8) shl 3) or
      (FTimexPort and $3F);
  else
    Result := FNextReg[Reg];
  end;
end;

procedure TSpectrum.NextWriteReg(Reg, Value: Byte);
begin
  case Reg of
    $00, $01, $0E, $0F, $1E, $1F, $B0, $B1: Exit;    // read only
    $03:
      begin
        // Any write switches the boot ROM off; the machine type changes only
        // in configuration mode, the display timing with bit 7. Type 111
        // goes back to configuration mode (Atic Atac writes its DivMMC NMI
        // entry into the SRAM that way)
        FNextBootOn := False;
        if (Value and 7) = 7 then FNextReg[$03] := FNextReg[$03] and $F8
        else if (FNextReg[$03] and 7) = 0 then FNextReg[$03] := (FNextReg[$03] and $F8) or (Value and 7);
        if (Value and $80) <> 0 then FNextReg[$03] := (FNextReg[$03] and $8F) or (Value and $70);
        NextUpdatePaging;
        Exit;
      end;
    $04:
      begin
        FNextReg[$04] := Value and $7F;
        NextUpdatePaging;
        Exit;
      end;
    $09:
      begin
        // Bit 3 clears the DivMMC's MAPRAM (port E3 bit 6) and reads as 0
        if (Value and 8) <> 0 then FDiv.ClearMapRam;
        FNextReg[$09] := Value and not 8;
        Exit;
      end;
    $02:
      begin
        // Reset (once the instruction is over)
        if (Value and 2) <> 0 then FNextResetReq := 2
        else if (Value and 1) <> 0 then FNextResetReq := 1;
        // The Multiface's and the DivMMC's NMIs, as their buttons (bits 3
        // and 2 read back as set until 0 is written)
        if (Value and 8) = 0 then FNextReg[$02] := FNextReg[$02] and not 8
        else if ((FNextReg[$02] and 8) = 0) and NextMfNmi then FNextReg[$02] := FNextReg[$02] or 8;
        if (Value and 4) = 0 then FNextReg[$02] := FNextReg[$02] and not 4
        else if ((FNextReg[$02] and 4) = 0) and NextDivNmi then FNextReg[$02] := FNextReg[$02] or 4;
        Exit;
      end;
    $10:
      begin
        // Start the selected core: the FPGA loads it, which for the Next's
        // own (slots 0-7) is a power on; other machines' aren't emulated
        FNextReg[$10] := Value and $1F;
        if (Value and $80) <> 0 then
        begin
          if (Value and $1F) >= 8 then FForeignCore := Value and $1F;
          FNextResetReq := 2;
        end;
        Exit;
      end;
    $07:
      begin
        FNextReg[$07] := Value and 3;
        FNextSpeed := 1 shl (Value and 3);
        SetSpeed(FUserSpeed);
        Exit;
      end;
    $50..$57:
      begin
        FNextMMU[Reg - $50] := Value;
        FNextReg[Reg] := Value;
        NextUpdatePaging;
        Exit;
      end;
    $69:
      begin
        // Display control: Layer 2 on (port 123B bit 1), ULA shadow screen
        // (7FFD bit 3) and the Timex modes
        FNextReg[$69] := Value;
        FNextL2Port := (FNextL2Port and not 2) or ((Value shr 6) and 2);
        FPort7FFD := (FPort7FFD and not 8) or ((Value shr 3) and 8);
        FTimexPort := (FTimexPort and $C0) or (Value and $3F);
        NextUpdatePaging;
        Exit;
      end;
    $8E:
      begin
        if (Value and 8) <> 0 then
        begin
          FPort7FFD := (FPort7FFD and not 7) or ((Value shr 4) and 7);
          FPortDFFD := (FPortDFFD and not 1) or (Value shr 7);
        end;
        if (Value and 4) = 0 then
        begin
          FPort1FFD := (FPort1FFD and not 5) or ((Value and 2) shl 1);
          FPort7FFD := (FPort7FFD and not $10) or ((Value and 1) shl 4);
        end
        else
          FPort1FFD := (FPort1FFD and not 7) or 1 or ((Value and 3) shl 1);
        // Without bit 3 the RAM in slots 6-7 stays (NextZXOS switches ROMs
        // this way all the time)
        NextPortPaging((Value and 8) <> 0);
        Exit;
      end;
    $8C:
      begin
        FNextReg[$8C] := Value;
        NextUpdatePaging;
        Exit;
      end;
    $B8..$BB:
      begin
        FNextReg[Reg] := Value;
        NextSetDivEntries;
        Exit;
      end;
    $18: begin NextClipWrite(CLIP_L2, Value); Exit; end;
    $19: begin NextClipWrite(CLIP_SPR, Value); Exit; end;
    $1A: begin NextClipWrite(CLIP_ULA, Value); Exit; end;
    $1B: begin NextClipWrite(CLIP_TM, Value); Exit; end;
    $1C:
      begin
        if (Value and 1) <> 0 then FNextClipIdx[CLIP_L2] := 0;
        if (Value and 2) <> 0 then FNextClipIdx[CLIP_SPR] := 0;
        if (Value and 4) <> 0 then FNextClipIdx[CLIP_ULA] := 0;
        if (Value and 8) <> 0 then FNextClipIdx[CLIP_TM] := 0;
        Exit;
      end;
    $34:
      begin
        FSprIndex := Value and 127;
        // In lockstep with port 303B (NR 09 bit 4): the pattern too
        if (FNextReg[$09] and $10) <> 0 then
          FSprPatAddr := (Value and $3F) * 256 + (Value shr 7) * 128;
        Exit;
      end;
    $35..$39, $75..$79:
      begin
        FSprAttr[FSprIndex, (Reg and 7) - 5] := Value;
        if Reg >= $75 then FSprIndex := (FSprIndex + 1) and 127;
        Exit;
      end;
    $40:
      begin
        FNextReg[$40] := Value;
        FNextPal44 := False;
        Exit;
      end;
    $41:
      begin
        FNextPal44 := False;
        NextPaletteWrite(Value, False);
        Exit;
      end;
    $43:
      begin
        FNextReg[$43] := Value;
        FNextPal44 := False;
        Exit;
      end;
    $44:
      begin
        NextPaletteWrite(Value, True);
        Exit;
      end;
    $60:
      begin
        NextCopperWrite(Value);
        Exit;
      end;
    $61:
      begin
        FCopperAddr := (FCopperAddr and $700) or Value;
        Exit;
      end;
    $62:
      begin
        FCopperAddr := (FCopperAddr and $FF) or ((Value and 7) shl 8);
        // A new start mode (the same one again changes nothing); started by
        // the CPU, the copper's clock starts now
        if (Value shr 6) <> (FNextReg[$62] shr 6) then
        begin
          case Value shr 6 of
            0: FCopperStopped := True;
            1, 3:
              begin
                FCopperPC := 0;
                FCopperStopped := False;
              end;
            2: FCopperStopped := False;
          end;
          if not FCopperInRun then FCopperClk := Max(FCopperClk, U(FCpu.T) * 4);
          FCopperDue := 0;
        end;
        FNextReg[$62] := Value;
        Exit;
      end;
    $63:
      begin
        NextCopperWrite(Value);
        Exit;
      end;
    $2C: begin NextDacWrite($0F, Value, U(FCpu.T)); FNextReg[Reg] := Value; Exit; end;
    $2D: begin NextDacWrite($DF, Value, U(FCpu.T)); FNextReg[Reg] := Value; Exit; end;
    $2E: begin NextDacWrite($4F, Value, U(FCpu.T)); FNextReg[Reg] := Value; Exit; end;
    $C8, $C9, $CA:
      begin
        // Writing set bits clears the interrupt status
        FNextReg[Reg] := FNextReg[Reg] and not Value;
        Exit;
      end;
  end;
  FNextReg[Reg] := Value;
end;

{ After a write to 7FFD, DFFD or 1FFD: the ROM in slots 0-1, the bank in
  6-7 (unless Bank is False: NR 8E without bit 3), or the four all-RAM
  banks; leaving all-RAM puts banks 5 and 2 back in the middle }
procedure TSpectrum.NextPortPaging(Bank: Boolean);
const
  SpecialMaps: array[0..3, 0..3] of Integer = (
    (0, 1, 2, 3), (4, 5, 6, 7), (4, 5, 6, 3), (4, 7, 6, 3));
var
  Slot, B: Integer;
begin
  if (FPort1FFD and 1) <> 0 then
  begin
    for Slot := 0 to 3 do
    begin
      B := SpecialMaps[(FPort1FFD shr 1) and 3, Slot];
      FNextMMU[Slot * 2] := B * 2;
      FNextMMU[Slot * 2 + 1] := B * 2 + 1;
    end;
    FNextSpecial := True;
  end
  else
  begin
    if FNextSpecial then
    begin
      FNextMMU[2] := 10; FNextMMU[3] := 11;
      FNextMMU[4] := 4; FNextMMU[5] := 5;
      FNextSpecial := False;
      Bank := True;
    end;
    FNextMMU[0] := 255;
    FNextMMU[1] := 255;
    if Bank then
    begin
      B := (FPort7FFD and 7) or ((FPortDFFD and $0F) shl 3);
      FNextMMU[6] := B * 2;
      FNextMMU[7] := B * 2 + 1;
    end;
  end;
  for Slot := 0 to 7 do FNextReg[$50 + Slot] := FNextMMU[Slot];
  NextUpdatePaging;
end;

{ The alternate ROM in use: the locked one (NR 8C bits 5-4), else as port
  7FFD's ROM bit }
function TSpectrum.NextAltRomIndex: Integer;
begin
  if (FNextReg[$8C] and $20) <> 0 then Result := 1
  else if (FNextReg[$8C] and $10) <> 0 then Result := 0
  else Result := (FPort7FFD shr 4) and 1;
end;

procedure TSpectrum.NextSetDivEntries;
begin
  FDiv.NextEntries := True;
  FDiv.Entry0 := FNextReg[$B8];
  FDiv.Valid0 := FNextReg[$B9];
  FDiv.Timing0 := FNextReg[$BA];
  FDiv.Entry1 := FNextReg[$BB];
end;

procedure TSpectrum.NextUpdatePaging;
var
  Slot, P, Rom: Integer;
begin
  if (FPort7FFD and $08) <> 0 then FScreenBank := 7 else FScreenBank := 5;
  // NR 8C's lock bits fix the ROM, else ports 7FFD and 1FFD choose it
  if (FNextReg[$8C] and $30) <> 0 then Rom := (FNextReg[$8C] shr 4) and 3
  else Rom := ((FPort7FFD shr 4) and 1) or ((FPort1FFD shr 1) and 2);
  // The DivMMC's ROM 3 entry points need the 48K BASIC at 0000
  FDiv.Rom3 := (FNextMMU[0] = 255) and (Rom = 3);
  for Slot := 0 to 7 do
  begin
    P := FNextMMU[Slot];
    if (Slot < 2) and (P = 255) then
    begin
      FPageRO[Slot] := True;
      FPageScreen[Slot] := False;
      if FNextBootOn then
        FPage[Slot] := @FNextBootRom[0]              // 8K, seen twice
      else if (FNextReg[$03] and 7) = 0 then
      begin
        // Configuration mode: the SRAM bank NR 04 chooses, writable
        FPage[Slot] := @NextSramBank(FNextReg[$04])^[(Slot and 1) * $2000];
        FPageRO[Slot] := False;
      end
      // The alternate ROM replaces it for reading (NR 8C 10xxxxxx)
      else if (FNextReg[$8C] and $C0) = $80 then
        FPage[Slot] := @FNextSram[6 + NextAltRomIndex][(Slot and 1) * $2000]
      else
        FPage[Slot] := @FNextSram[Rom][(Slot and 1) * $2000];
    end
    else if P < NEXT_PAGES then
    begin
      FPage[Slot] := @FRam[P shr 1][(P and 1) * $2000];
      FPageRO[Slot] := False;
      FPageScreen[Slot] := ((P shr 1) = FScreenBank) and not Odd(P);
    end
    else
    begin
      FPage[Slot] := @FNoMem[0];
      FPageRO[Slot] := True;
      FPageScreen[Slot] := False;
    end;
  end;
  // The Multiface over everything but the boot ROM and configuration mode:
  // its ROM at 0000, its RAM at 2000 (the DivMMC isn't seen meanwhile)
  FDiv.Hidden := FMfOn and not FNextBootOn and ((FNextReg[$03] and 7) <> 0);
  if FDiv.Hidden then
  begin
    FPage[0] := @FNextSram[5][0];
    FPageRO[0] := True;
    FPageScreen[0] := False;
    FPage[1] := @FNextSram[5][$2000];
    FPageRO[1] := False;
    FPageScreen[1] := False;
  end;
  // The 16K view (debugger, contention, tape traps): by the slot's first page
  for Slot := 0 to 3 do
  begin
    P := FNextMMU[Slot * 2];
    if (Slot = 0) and (P = 255) then
    begin
      FSlotBank[0] := -1 - Rom;
      FSlot[0] := @FNextSram[Rom];
      FSlotContended[0] := False;
    end
    else if P < NEXT_PAGES then
    begin
      FSlotBank[Slot] := P shr 1;
      FSlot[Slot] := @FRam[P shr 1];
      FSlotContended[Slot] := (P shr 1) in [4..7];
    end
    else
    begin
      FSlotBank[Slot] := NO_MEMORY;
      FSlot[Slot] := @FNoMem;
      FSlotContended[Slot] := False;
    end;
  end;
end;

{ The Multiface's ports, as NR 0A bits 7-6 choose its type: +3 (the
  Next's), 128 v87.2, 128 v87.12 or Multiface 1; the type is returned }
function TSpectrum.MfPorts(out EnablePort, DisablePort: Byte): Integer;
begin
  Result := FNextReg[$0A] shr 6;
  case Result of
    0: begin EnablePort := $3F; DisablePort := $BF; end;
    1: begin EnablePort := $BF; DisablePort := $3F; end;
  else
    begin EnablePort := $9F; DisablePort := $1F; end;
  end;
end;

{ The M1 button (or NR 02 bit 3): the Multiface's NMI; ignored while it or
  the DivMMC are in, and in configuration mode }
function TSpectrum.NextMfNmi: Boolean;
begin
  Result := not (FMfNmi or FMfOn or FDiv.Active or FDiv.NmiButton or ((FNextReg[$03] and 7) = 0));
  if not Result then Exit;
  FMfNmi := True;
  FMfInvisible := False;
  FNMIRequest := True;
end;

{ The DRIVE button (or NR 02 bit 2): the DivMMC's NMI, which maps it in at
  0066 (NR BB bits 1-0) until RETN }
function TSpectrum.NextDivNmi: Boolean;
begin
  Result := not (FMfNmi or FMfOn or FDiv.Active or FDiv.NmiButton or ((FNextReg[$03] and 7) = 0));
  if not Result then Exit;
  FDiv.NmiButton := True;
  FNMIRequest := True;
end;

{ Reading the Multiface's ports: the disable port pages it out; the enable
  port pages it in (unless invisible) and, on the +3 and 128 types, answers
  with the paging registers. False: it doesn't answer. }
function TSpectrum.NextMfPortRead(Port: Word; out Value: Byte): Boolean;
var
  Mode: Integer;
  En, Dis: Byte;
begin
  Result := False;
  Value := $FF;
  Mode := MfPorts(En, Dis);
  if (Port and $FF) = Dis then
  begin
    if Mode = 0 then FMfNmi := False;
    if FMfOn then
    begin
      FMfOn := False;
      NextUpdatePaging;
    end;
  end
  else if (Port and $FF) = En then
  begin
    FMfOn := not (FMfInvisible and (Mode <> 3));
    NextUpdatePaging;
    if FMfInvisible or (Mode = 3) then Exit;
    Result := True;
    if Mode = 0 then
      case Port shr 8 of
        $7F: Value := FPort7FFD;
        $1F: Value := FPort1FFD;
      end
    else
      Value := (FPort7FFD and 8) shl 4;
  end;
end;

{ Writing them ends its NMI; one of them makes it invisible }
procedure TSpectrum.NextMfPortWrite(Port: Word);
var
  Mode: Integer;
  En, Dis: Byte;
begin
  Mode := MfPorts(En, Dis);
  if ((Port and $FF) <> En) and ((Port and $FF) <> Dis) then Exit;
  FMfNmi := False;
  if (((Port and $FF) = Dis) and (Mode <> 0)) or (((Port and $FF) = En) and (Mode = 0)) then
    FMfInvisible := True;
end;

{ RETN: the end of an NMI; the Multiface and the DivMMC's automatic
  mapping let go, and the first RETN after a stackless NMI returns to NR
  C2-C3 }
procedure TSpectrum.Retn;
begin
  if not IsNext then Exit;
  // Only the first RETN after a stackless NMI
  if FNmiStackless then FCpu.PC.W := FNextReg[$C2] or (FNextReg[$C3] shl 8);
  FNmiStackless := False;
  FMfNmi := False;
  if FMfOn then
  begin
    FMfOn := False;
    NextUpdatePaging;
  end;
  // RETN ends the DivMMC's automatic mapping too (the Multiface leaves
  // with RETN after using esxDOS); CONMEM stays as port E3 says
  FDiv.NmiButton := False;
  FDiv.Mapped := False;
end;

const
  { The Next's flash: 16 MB (32 slots of 512K for cores), a W25Q128 }
  NEXT_FLASH_SIZE = 16 * 1024 * 1024;

{ A byte to the flash: a command (WREN, READ, FAST READ, PAGE PROGRAM, the
  erases...), its address and its data }
procedure TSpectrum.NextFlashWrite(Value: Byte);
var
  Size: Integer;
begin
  if FNextFlashIdx < Length(FNextFlashCmd) then FNextFlashCmd[FNextFlashIdx] := Value;
  Inc(FNextFlashIdx);
  if FNextFlashIdx = 4 then
    FNextFlashAddr := (FNextFlashCmd[1] shl 16) or (FNextFlashCmd[2] shl 8) or FNextFlashCmd[3];
  case FNextFlashCmd[0] of
    $06: FNextFlashWel := True;
    $04: FNextFlashWel := False;
    $02:
      // PAGE PROGRAM: the bytes after the address, within its 256-byte page
      if (FNextFlashIdx > 4) and FNextFlashWel then
      begin
        if FNextFlash = nil then
        begin
          SetLength(FNextFlash, NEXT_FLASH_SIZE);
          FillChar(FNextFlash[0], NEXT_FLASH_SIZE, $FF);
        end;
        FNextFlash[FNextFlashAddr and (NEXT_FLASH_SIZE - 1)] :=
          FNextFlash[FNextFlashAddr and (NEXT_FLASH_SIZE - 1)] and Value;
        FNextFlashAddr := (FNextFlashAddr and not $FF) or ((FNextFlashAddr + 1) and $FF);
      end;
    $20, $52, $D8:
      // Erase 4K, 32K or 64K at the address (all $FF), at once
      if (FNextFlashIdx = 4) and FNextFlashWel then
      begin
        case FNextFlashCmd[0] of
          $20: Size := $1000;
          $52: Size := $8000;
        else
          Size := $10000;
        end;
        if FNextFlash <> nil then
          FillChar(FNextFlash[(FNextFlashAddr and (NEXT_FLASH_SIZE - 1)) and not (Size - 1)], Size, $FF);
        FNextFlashWel := False;
      end;
    $60, $C7:
      if (FNextFlashIdx = 1) and FNextFlashWel then
      begin
        FNextFlash := nil;
        FNextFlashWel := False;
      end;
  end;
end;

{ A byte from the flash: status (never busy), JEDEC id, or data }
function TSpectrum.NextFlashRead: Byte;
const
  JEDEC: array[0..2] of Byte = ($EF, $40, $18);
begin
  Result := $FF;
  case FNextFlashCmd[0] of
    $05: Result := Ord(FNextFlashWel) shl 1;
    $9F: if FNextFlashReads < 3 then Result := JEDEC[FNextFlashReads];
    $AB: Result := $17;
    $90: if Odd(FNextFlashReads) then Result := $17 else Result := $EF;
    $03, $0B:
      if FNextFlashIdx >= 4 + Ord(FNextFlashCmd[0] = $0B) then
      begin
        if FNextFlash <> nil then Result := FNextFlash[FNextFlashAddr and (NEXT_FLASH_SIZE - 1)];
        Inc(FNextFlashAddr);
      end;
  end;
  Inc(FNextFlashReads);
end;

{ The line interrupt (NR 22-23): for line L (0 = the first line of the
  paper) at the end of line L - 1, as the ZX-Uno's raster interrupt }
function TSpectrum.NextLineIntActive: Boolean;
var
  Line, Lines, VC, T: Integer;
begin
  Line := FNextReg[$23] or ((FNextReg[$22] and 1) shl 8);
  Lines := FInfo.FrameT div FInfo.LineT;
  // Counted as the copper does (NR 64 moves line 0)
  Line := ((Line - FNextReg[$64]) mod Lines + Lines) mod Lines;
  if Line = 0 then VC := Lines - 1 else VC := Line - 1;
  Result := False;
  if VC >= Lines then Exit;
  T := (FInfo.PaperTopT + VC * FInfo.LineT + 128) mod FInfo.FrameT;
  Result := (U(FCpu.T) >= T) and (U(FCpu.T) < T + 32);
end;

procedure TSpectrum.WriteNextReg(Reg, Value: Byte; T: Integer);
begin
  NextRenderUpTo(U(T), NextVideoReg(Reg));
  NextWriteReg(Reg, Value);
end;

function TSpectrum.NextRegister(Reg: Byte): Byte;
begin
  Result := NextReadReg(Reg);
end;

procedure TSpectrum.SetNextRegister(Reg, Value: Byte);
begin
  NextWriteReg(Reg, Value);
end;

function TSpectrum.NextMMU(Slot: Integer): Byte;
begin
  Result := FNextMMU[Slot and 7];
end;

{ The 8-bit DACs (Specdrum, Covox, Soundrive... ports, as ports.txt maps
  them to channels A-D), as audio events }
procedure TSpectrum.NextDacWrite(Port: Word; Value: Byte; T: Integer);
var
  Mask: Byte;
begin
  case Port and $FF of
    $1F, $F1, $3F: Mask := 1;            // A
    $0F, $F3: Mask := 2;                 // B
    $DF, $FB: Mask := 1 or 8;            // A and D
    $B3: Mask := 2 or 4;                 // B and C
    $4F, $F9: Mask := 4;                 // C
    $5F: Mask := 8;                      // D
  else
    Exit;
  end;
  AddEvent(T, 3, Mask, Value);
end;

const
  { The handle a .nex program is given for its file (header 140-141) }
  NEX_HANDLE = $C8;

{ A .nex program (wiki.specnext.dev/NEX_file_format, V1.0 to V1.3 as
  sjasmplus writes them): its banks, loading screen, palette and copper
  code into memory, then the registers and paging as NextZXOS's loader
  leaves them (the 48K ROM, banks 5, 2 and the entry bank), and the program
  started. Whatever else is in memory (NextZXOS, if it is running) stays,
  as with .nexload. If the program asks for its file, it gets a handle that
  esxDOS's F_READ, F_SEEK, F_FGETPOS, F_FSTAT and F_CLOSE read from it; for
  DISK_FILEMAP (programs that stream it straight from the card) the file is
  also copied onto the SD card, as /TMP/EMU80NEX.NEX. }
procedure TSpectrum.LoadNex(const FileName: string);
const
  BANK_ORDER: array[0..7] of Integer = (5, 2, 0, 1, 3, 4, 6, 7);
var
  D: TBytes;
  S: TFileStream;
  Pos_, I, K, Bank, NBanks, BanksAt, Screen2: Integer;
  Flags, Entry: Byte;
  PC, SP, Handle, Cli: Word;
  Palette, V13, Copper: Boolean;

  procedure Need(Count: Integer);
  begin
    if Pos_ + Count > Length(D) then raise Exception.Create(_('The .nex file is cut short'));
  end;

  procedure ToBank(B, Offset, Count: Integer);
  begin
    Need(Count);
    Move(D[Pos_], FRam[B][Offset], Count);
    Inc(Pos_, Count);
  end;

begin
  S := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(D, S.Size);
    if S.Size > 0 then S.ReadBuffer(D[0], S.Size);
  finally
    S.Free;
  end;
  if (Length(D) < 512) or (D[0] <> Ord('N')) or (D[1] <> Ord('e')) or (D[2] <> Ord('x')) or
     (D[3] <> Ord('t')) then
    raise Exception.Create(_('Not a .nex file'));
  FNexOpen := False;
  FNexData := nil;
  FNexName := '';
  Flags := D[10];
  SP := D[12] or (D[13] shl 8);
  PC := D[14] or (D[15] shl 8);
  Entry := D[139];
  Handle := D[140] or (D[141] shl 8);
  // V1.3: where the banks start, the command line buffer, the extra screen
  // (1 = 320x256, 2 = 640x256, 3 = tilemap) and the copper code
  V13 := (D[4] = Ord('V')) and (D[5] = Ord('1')) and (D[7] >= Ord('3'));
  if V13 then
  begin
    BanksAt := D[144] or (D[145] shl 8) or (D[146] shl 16) or (D[147] shl 24);
    Cli := D[148] or (D[149] shl 8);
    if (D[150] or (D[151] shl 8)) = 0 then Cli := 0;
    Screen2 := D[152];
    Copper := D[153] <> 0;
  end
  else
  begin
    BanksAt := 0;
    Cli := 0;
    Screen2 := 0;
    Copper := False;
  end;
  // Header 134 = 0: the display as after a reset (the program sets it up)
  if D[134] = 0 then
  begin
    FCopperStopped := True;
    FNextReg[$62] := 0;
    FNextL2Port := 0;
    FNextL2Offset := 0;
    FillChar(FSprAttr, SizeOf(FSprAttr), 0);
    for I in [$15, $16, $17, $22, $23, $26, $27, $2F, $30, $31, $32, $33, $64, $68, $6B, $70, $71] do
      FNextReg[I] := 0;
    FNextReg[$12] := 8;
    FNextReg[$13] := 11;
    FNextReg[$14] := $E3;
    for I := 0 to 3 do
    begin
      FNextClip[I, 0] := 0;
      FNextClip[I, 1] := 255;
      FNextClip[I, 2] := 0;
      FNextClip[I, 3] := 191;
      FNextClipIdx[I] := 0;
    end;
    FNextClip[CLIP_TM, 1] := 159;
    FNextClip[CLIP_TM, 3] := 255;
  end;
  Pos_ := 512;
  // The palette (Layer 2, LoRes, tilemap screens) unless bit 7 says none
  Palette := ((Flags and $80) = 0) and ((Flags and (1 or 4 or $40)) <> 0);
  if Palette then
  begin
    Need(512);
    for I := 0 to 255 do
    begin
      if (Flags and 4) <> 0 then
        NextSetPal(PAL_ULA, I, (D[Pos_ + I * 2] shl 1) or (D[Pos_ + I * 2 + 1] and 1))
      else if ((Flags and $40) <> 0) and (Screen2 = 3) then
        NextSetPal(PAL_TM, I, (D[Pos_ + I * 2] shl 1) or (D[Pos_ + I * 2 + 1] and 1))
      else
        NextSetPal(PAL_L2, I, (D[Pos_ + I * 2] shl 1) or (D[Pos_ + I * 2 + 1] and 1));
    end;
    Inc(Pos_, 512);
  end;
  // Loading screens: Layer 2 in banks 9-11, the ULA ones in bank 5
  if (Flags and 1) <> 0 then
  begin
    for K := 0 to 2 do ToBank(9 + K, 0, 16384);
    FNextReg[$12] := 9;
    FNextReg[$70] := 0;
    FNextL2Port := (FNextL2Port and not 2) or 2;
  end;
  if (Flags and 2) <> 0 then ToBank(5, 0, 6912);
  if (Flags and 4) <> 0 then
  begin
    ToBank(5, 0, 6144);
    ToBank(5, $2000, 6144);
    FNextReg[$15] := FNextReg[$15] or $80;
  end;
  if (Flags and 8) <> 0 then
  begin
    ToBank(5, 0, 6144);
    ToBank(5, $2000, 6144);
    FTimexPort := 6 or (D[138] and $38);
  end;
  if (Flags and 16) <> 0 then
  begin
    ToBank(5, 0, 6144);
    ToBank(5, $2000, 6144);
    FTimexPort := 2;
  end;
  if (Flags and $40) <> 0 then
  begin
    if Screen2 = 3 then
    begin
      // A tilemap screen: its registers from the header (its data, before
      // the banks, is found through V1.3's bank offset)
      FNextReg[$6B] := D[154];
      FNextReg[$6C] := D[155];
      FNextReg[$6E] := D[156];
      FNextReg[$6F] := D[157];
    end
    else
    begin
      // Layer 2 320x256 or 640x256 (header 138: its palette offset)
      for K := 0 to 4 do ToBank(9 + K, 0, 16384);
      FNextReg[$12] := 9;
      if Screen2 = 2 then FNextReg[$70] := $20 or (D[138] and 15)
      else FNextReg[$70] := $10 or (D[138] and 15);
      FNextL2Port := FNextL2Port or 2;
    end;
  end;
  // V1.3 says where the banks are; the copper code is just before them
  if BanksAt >= 512 then Pos_ := BanksAt;
  if Copper then
  begin
    if BanksAt >= 512 + 2048 then Pos_ := BanksAt - 2048;
    Need(2048);
    for I := 0 to 1023 do FCopper[I] := (D[Pos_ + I * 2] shl 8) or D[Pos_ + I * 2 + 1];
    Inc(Pos_, 2048);
    // Started as the loader does: from the top, again every frame
    FCopperPC := 0;
    FCopperAddr := 0;
    FNextReg[$61] := 0;
    FNextReg[$62] := $C0;
    FCopperStopped := False;
    FCopperClk := U(FCpu.T) * 4;
    FCopperDue := 0;
    FCopperRestarted := False;
  end;
  FBorder := D[11] and 7;
  // The banks: 5, 2, 0, 1, 3, 4, 6, 7, then 8 upwards
  NBanks := 0;
  for K := 0 to 111 do
  begin
    if K < 8 then Bank := BANK_ORDER[K] else Bank := K;
    if (Bank < RAM_BANKS) and (D[18 + Bank] <> 0) then
    begin
      ToBank(Bank, 0, 16384);
      Inc(NBanks);
    end;
  end;
  if PC = 0 then Exit;   // only loaded
  // The machine as the loader leaves it: the 48K ROM, banks 5 and 2, the
  // entry bank at C000, interrupts off
  FPort7FFD := $10 or (Entry and 7);
  FPortDFFD := (Entry shr 3) and $0F;
  FPort1FFD := 4;
  FNextMMU[0] := 255;
  FNextMMU[1] := 255;
  FNextMMU[2] := 10;
  FNextMMU[3] := 11;
  FNextMMU[4] := 4;
  FNextMMU[5] := 5;
  FNextMMU[6] := Entry * 2;
  FNextMMU[7] := Entry * 2 + 1;
  for I := 0 to 7 do FNextReg[$50 + I] := FNextMMU[I];
  FNextSpecial := False;
  FDiv.Mapped := False;
  FMfOn := False;
  FMfNmi := False;
  NextUpdatePaging;
  FCpu.IFF1 := False;
  FCpu.IFF2 := False;
  FCpu.IM := 1;
  FCpu.Halted := False;
  FCpu.SP.W := SP;
  FCpu.PC.W := PC;
  // Its file, at the data after the banks: the handle in BC or in memory
  if Handle <> 0 then
  begin
    FNexData := D;
    FNexPos := Pos_;
    FNexOpen := True;
    FNexName := ExtractFileName(FileName);
    NexOnCard;
    if Handle < $4000 then FCpu.BC.W := NEX_HANDLE
    else Poke(Handle, NEX_HANDLE);
  end;
  // No command line
  if Cli <> 0 then Poke(Cli, 0);
end;

{ The open .nex file onto the SD card, for DISK_FILEMAP: its sectors there }
procedure TSpectrum.NexOnCard;
var
  Vol: TFatVolume;
  Dir: LongWord;
  E: TFatEntries;
  I: Integer;
begin
  FNexMap := nil;
  FNexMapPos := 0;
  if FDiv.Card = nil then Exit;
  try
    Vol := TFatVolume.Create(FDiv.Card.Stream);
    try
      Dir := Vol.FindDir('/TMP', True);
      Vol.PutFile(Dir, 'EMU80NEX.NEX', FNexData);
      E := Vol.ListDir(Dir);
      for I := 0 to High(E) do
        if SameText(E[I].ShortName, 'EMU80NEX.NEX') then FNexMap := Vol.FileMap(E[I]);
    finally
      Vol.Free;
    end;
  except
    FNexMap := nil;     // no room, or not a FAT card: no map to give
  end;
end;

{ RST 8 with the .nex file's handle in A: the esxDOS call done from the
  file (the function code is the byte after the RST). False: not ours. }
function TSpectrum.NexFileCall: Boolean;
const
  F_OPEN = $9A; F_CLOSE = $9B; F_READ = $9D; F_SEEK = $9F; F_FGETPOS = $A0; F_FSTAT = $A1;
  DISK_FILEMAP = $85;
  ESX_EACCES = 8;     // "access denied": what isn't done here
var
  Ret, Addr, Buf: Word;
  Dot: Boolean;
  Max, N: Integer;
  Fn: Byte;
  Count, I: Integer;
  Pos_: Int64;
  Name: string;

  procedure PutByte(A: Word; V: Byte);
  begin
    if not FPageRO[A shr 13] then FPage[A shr 13][A and $1FFF] := V;
  end;

  procedure SetPos(P: Int64);
  begin
    if P < 0 then P := 0;
    if P > Length(FNexData) then P := Length(FNexData);
    FNexPos := P;
    FCpu.BC.W := P shr 16;
    FCpu.DE.W := P and $FFFF;
  end;

begin
  Result := False;
  Ret := Peek(FCpu.SP.W) or (Peek(FCpu.SP.W + 1) shl 8);
  Fn := Peek(Ret);
  // The program opening its own .nex by name, to read more of it (as
  // streaming games do): the file loaded from the PC, from its start
  if Fn = F_OPEN then
  begin
    if Ret < $4000 then Buf := FCpu.HL.W else Buf := FCpu.IX.W;
    Name := '';
    for I := 0 to 255 do
    begin
      N := Peek(Word(Buf + I));
      if N = 0 then Break;
      Name := Name + Chr(N);
    end;
    Name := StringReplace(Name, '/', PathDelim, [rfReplaceAll]);
    if (FNexName = '') or not SameText(ExtractFileName(Name), FNexName) then Exit;
    Result := True;
    FNexOpen := True;
    FNexPos := 0;
    FNexMapPos := 0;
    FCpu.A := NEX_HANDLE;
    FCpu.F := FCpu.F and not 1;
    FCpu.SP.W := FCpu.SP.W + 2;
    FCpu.PC.W := Ret + 1;
    Inc(FCpu.T, 40);
    Exit;
  end;
  if not FNexOpen or (FCpu.A <> NEX_HANDLE) then Exit;
  if not (Fn in [DISK_FILEMAP, F_CLOSE, $9E, F_READ, F_SEEK, F_FGETPOS, F_FSTAT]) then Exit;
  Result := True;
  // Programs give addresses in IX; dot commands (in the DivMMC's RAM) in HL
  Dot := Ret < $4000;
  if Dot then Buf := FCpu.HL.W else Buf := FCpu.IX.W;
  FCpu.F := FCpu.F and not 1;                 // carry clear: done
  case Fn of
    F_CLOSE:
      // Kept: the program may open it again
      FNexOpen := False;
    F_READ:
      begin
        Count := FCpu.BC.W;
        if Count > Length(FNexData) - FNexPos then Count := Length(FNexData) - FNexPos;
        Addr := Buf;
        for I := 0 to Count - 1 do
        begin
          PutByte(Addr, FNexData[FNexPos + I]);
          Inc(Addr);
        end;
        Inc(FNexPos, Count);
        FCpu.BC.W := Count;
        FCpu.DE.W := Count;
        FCpu.HL.W := Addr;
        Inc(FCpu.T, 100 + Count * 4);
      end;
    F_SEEK:
      begin
        FNexMapPos := 0;
        Pos_ := (Int64(FCpu.BC.W) shl 16) or FCpu.DE.W;
        if Dot then I := FCpu.HL.L else I := FCpu.IX.L;
        case I of
          1: SetPos(FNexPos + Pos_);
          2: SetPos(FNexPos - Pos_);
        else
          SetPos(Pos_);
        end;
      end;
    F_FGETPOS: SetPos(FNexPos);
    F_FSTAT:
      begin
        // '*', $81, attributes, time and date (MS-DOS), size
        Addr := Buf;
        PutByte(Addr, Ord('*'));
        PutByte(Addr + 1, $81);
        PutByte(Addr + 2, $20);
        for I := 3 to 6 do PutByte(Addr + I, 0);
        for I := 0 to 3 do PutByte(Addr + 7 + I, (Length(FNexData) shr (I * 8)) and $FF);
      end;
    DISK_FILEMAP:
      if FNexMap = nil then
      begin
        FCpu.F := FCpu.F or 1;
        FCpu.A := ESX_EACCES;
      end
      else
      begin
        // 4-byte card address (in blocks) and 2-byte sector count each
        Max := FCpu.DE.W;
        N := 0;
        Addr := Buf;
        while (N < Max) and (FNexMapPos < Length(FNexMap)) do
        begin
          for I := 0 to 3 do PutByte(Addr + I, (FNexMap[FNexMapPos] shr (I * 8)) and $FF);
          PutByte(Addr + 4, FNexMap[FNexMapPos + 1] and $FF);
          PutByte(Addr + 5, FNexMap[FNexMapPos + 1] shr 8);
          Inc(Addr, 6);
          Inc(FNexMapPos, 2);
          Inc(N);
        end;
        FCpu.DE.W := Max - N;
        FCpu.HL.W := Addr;
        FCpu.A := 2;                      // card 0, block addressing (SDHC)
      end;
  else
    begin
      // F_WRITE: the file is the PC's, read only
      FCpu.F := FCpu.F or 1;
      FCpu.A := ESX_EACCES;
    end;
  end;
  // Back after the function code
  FCpu.SP.W := FCpu.SP.W + 2;
  FCpu.PC.W := Ret + 1;
  Inc(FCpu.T, 40);
end;

{ SpectrumChips.inc: the ports and the chips' registers of the ZX Spectrum (16K to +3) and the Amstrad CPC, for the
  debugger's chips window (ZXUnoRegsForm). A code names each one:

  ZX Spectrum: $000 port FE (the last value written: border, MIC, EAR), $001 7FFD, $002 1FFD, $003 FF (Timex), $004
  BF3B and $005 FF3B (ULAplus), $100 the AY's register selected (FFFD) and $110 + N its register N, $200 and $210 + N
  the same for the second AY (TurboSound).

  Amstrad CPC: $000 the Gate Array's pen selected, $010 + N pen N (16: the border), $001 its mode and ROM register
  (RMR), $002 its RAM configuration (MMR), $003 the upper ROM (DFxx), $030 the CRTC's register selected and $040 + N
  its register N (0 to 17), $060 to $063 the PPI's ports A, B, C and its control, $070 the PSG's register selected and
  $080 + N its register N.

  Writing one is as an OUT to its port would do it (7FFD keeps its lock, the paging follows), with what was selected
  (the AY's register, the CRTC's, the pen) put back afterwards. }

procedure TSpectrum.DebugOut(Port: Word; Value: Byte);
var
  T: Integer;
begin
  T := FCpu.T;
  FDebugOut := True;
  try
    WritePort(Port, Value, T);
  finally
    FDebugOut := False;
  end;
end;

function TSpectrum.ChipRegisterExists(Code: Integer): Boolean;
begin
  if FIsCPC then
    Result := ((Code >= 0) and (Code <= $FF) and (Byte(Code) in [$000..$003, $030, $060..$063, $070])) or ((Code >= $010) and (Code <= $020)) or
      ((Code >= $040) and (Code <= $040 + 17)) or ((Code >= $080) and (Code <= $08F))
  else
    case Code of
      $000: Result := True;
      $001: Result := FInfo.Memory in [mk128K, mkPlus3];
      $002: Result := FInfo.Memory = mkPlus3;
      $003: Result := HasTimex;
      $004, $005: Result := HasULAPlus;
      $100, $110..$11F: Result := HasAY;
      $200, $210..$21F: Result := HasAY and TurboSound;
    else
      Result := False;
    end;
end;

function TSpectrum.ChipRegister(Code: Integer): Byte;
var
  R: TCPCRegisters;
begin
  Result := 0;
  if FIsCPC then
  begin
    FCPC.GetRegisters(R);
    case Code of
      $000: Result := R.PenSel;
      $001: Result := R.RomReg;
      $002: Result := R.RamConfig;
      $003: Result := R.UpperRom;
      $010..$020: Result := R.Pens[Code - $010];
      $030: Result := R.CrtcSel;
      $040..$040 + 17: Result := R.Crtc[Code - $040];
      $060..$063: Result := R.Ppi[Code - $060];
      $070: Result := R.PsgSel;
      $080..$08F: Result := R.Psg[Code - $080];
    end;
    Exit;
  end;
  case Code of
    $000: Result := FUlaOut;
    $001: Result := FPort7FFD;
    $002: Result := FPort1FFD;
    $003: Result := FTimexPort;
    $004: Result := FULAPlusReg;
    $005: Result := FULAPlusMode;
    $100: Result := FAY.Selected;
    $110..$11F: Result := FAY.GetRegister(Code - $110);
    $200: Result := FAY2.Selected;
    $210..$21F: Result := FAY2.GetRegister(Code - $210);
  end;
end;

procedure TSpectrum.SetChipRegister(Code: Integer; Value: Byte);
var
  R: TCPCRegisters;
  OldChip: Integer;
  OldSel: Byte;
begin
  if not ChipRegisterExists(Code) then Exit;
  if FIsCPC then
  begin
    FCPC.GetRegisters(R);
    case Code of
      $000: DebugOut($7F00, Value and $1F);
      $001: DebugOut($7F00, $80 or (Value and $1F));
      $002: DebugOut($7F00, $C0 or (Value and $3F));
      $003: DebugOut($DF00, Value);
      $010..$020:
        begin
          // Select the pen (16: the border), give it the colour, select the one there was
          if Code = $020 then DebugOut($7F00, $10) else DebugOut($7F00, Code - $010);
          DebugOut($7F00, $40 or (Value and $1F));
          DebugOut($7F00, R.PenSel and $1F);
        end;
      $030: DebugOut($BC00, Value);
      $040..$040 + 17:
        begin
          DebugOut($BC00, Code - $040);
          DebugOut($BD00, Value);
          DebugOut($BC00, R.CrtcSel);
        end;
      $060..$063: DebugOut($F400 + (Code - $060) * $100, Value);
      $070: FCPC.SetPsg(-1, Value);
      $080..$08F: FCPC.SetPsg(Code - $080, Value);
    end;
    Exit;
  end;
  case Code of
    $000: DebugOut($00FE, Value);
    $001: DebugOut($7FFD, Value);
    $002: DebugOut($1FFD, Value);
    $003: DebugOut($00FF, Value);
    $004: DebugOut($BF3B, Value);
    $005: DebugOut($FF3B, Value);
    $100: FAY.SelectRegister(Value);
    $200: FAY2.SelectRegister(Value);
    $110..$11F, $210..$21F:
      begin
        // As an OUT to FFFD and one to BFFD, on that chip; then the chip and the register there were
        OldChip := FAYChip;
        if Code >= $200 then FAYChip := 1 else FAYChip := 0;
        OldSel := ActiveAY.Selected;
        DebugOut($FFFD, Code and $0F);
        DebugOut($BFFD, Value);
        ActiveAY.SelectRegister(OldSel);
        FAYChip := OldChip;
      end;
  end;
end;

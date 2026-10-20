{ NextDma.inc: the ZX Spectrum Next's zxnDMA (port 6B, and 0B for Z80 DMA
  programs), as docs/extra-hw/dma/zxndma.txt describes it (included by
  Spectrum.pas). A transfer without the prescaler runs at once, the CPU
  waiting meanwhile; with it (sampled sound), one byte every prescaler
  cycles, in burst mode while the CPU carries on. }

const
  { What the next byte written to the port is (a register's following bytes) }
  DMA_A_LO = 1; DMA_A_HI = 2; DMA_LEN_LO = 3; DMA_LEN_HI = 4; DMA_A_TIMING = 5;
  DMA_B_TIMING = 6; DMA_PRESCALER = 7; DMA_B_LO = 8; DMA_B_HI = 9; DMA_MASK = 10;
  DMA_IGNORE = 11;

procedure TSpectrum.DmaQueue(What: Integer);
begin
  if FDmaQueueLen < Length(FDmaQueue) then
  begin
    FDmaQueue[FDmaQueueLen] := What;
    Inc(FDmaQueueLen);
  end;
end;

procedure TSpectrum.DmaWrite(Value: Byte);
var
  What, I: Integer;
begin
  // A byte that belongs to the last register written
  if FDmaQueueLen > 0 then
  begin
    What := FDmaQueue[0];
    Dec(FDmaQueueLen);
    for I := 0 to FDmaQueueLen - 1 do FDmaQueue[I] := FDmaQueue[I + 1];
    case What of
      DMA_A_LO: FDmaPortA := (FDmaPortA and $FF00) or Value;
      DMA_A_HI: FDmaPortA := (FDmaPortA and $00FF) or (Value shl 8);
      DMA_LEN_LO: FDmaLength := (FDmaLength and $FF00) or Value;
      DMA_LEN_HI: FDmaLength := (FDmaLength and $00FF) or (Value shl 8);
      DMA_A_TIMING: FDmaTimingA := 4 - (Value and 3);
      DMA_B_TIMING:
        begin
          FDmaTimingB := 4 - (Value and 3);
          if (Value and $20) <> 0 then
          begin
            // The prescaler follows, before anything else queued
            for I := FDmaQueueLen downto 1 do FDmaQueue[I] := FDmaQueue[I - 1];
            FDmaQueue[0] := DMA_PRESCALER;
            Inc(FDmaQueueLen);
          end;
        end;
      DMA_PRESCALER: FDmaPrescaler := Value;
      DMA_B_LO: FDmaPortB := (FDmaPortB and $FF00) or Value;
      DMA_B_HI: FDmaPortB := (FDmaPortB and $00FF) or (Value shl 8);
      DMA_MASK:
        begin
          FDmaReadMask := Value and $7F;
          FDmaReadIdx := 0;
        end;
    end;
    Exit;
  end;
  if (Value and $80) = 0 then
  begin
    if (Value and 3) <> 0 then
    begin
      // WR0: direction, port A address, block length
      FDmaAtoB := (Value and 4) <> 0;
      if (Value and 8) <> 0 then DmaQueue(DMA_A_LO);
      if (Value and $10) <> 0 then DmaQueue(DMA_A_HI);
      if (Value and $20) <> 0 then DmaQueue(DMA_LEN_LO);
      if (Value and $40) <> 0 then DmaQueue(DMA_LEN_HI);
    end
    else if (Value and 7) = 4 then
    begin
      // WR1: port A memory or IO, increments, decrements or stays
      FDmaAIO := (Value and 8) <> 0;
      FDmaAMode := (Value shr 4) and 3;
      if (Value and $40) <> 0 then DmaQueue(DMA_A_TIMING);
    end
    else
    begin
      // WR2: the same for port B
      FDmaBIO := (Value and 8) <> 0;
      FDmaBMode := (Value shr 4) and 3;
      if (Value and $40) <> 0 then DmaQueue(DMA_B_TIMING);
    end;
    Exit;
  end;
  case Value and 3 of
    0:
      begin
        // WR3: enable (and the Z80 DMA's mask and match bytes, unused)
        if (Value and 8) <> 0 then DmaQueue(DMA_IGNORE);
        if (Value and $10) <> 0 then DmaQueue(DMA_IGNORE);
        if (Value and $40) <> 0 then DmaStart;
      end;
    1:
      begin
        // WR4: continuous or burst, port B address
        FDmaBurst := ((Value shr 5) and 3) = 2;
        if (Value and 4) <> 0 then DmaQueue(DMA_B_LO);
        if (Value and 8) <> 0 then DmaQueue(DMA_B_HI);
        if (Value and $10) <> 0 then DmaQueue(DMA_IGNORE);
      end;
    2:
      // WR5: restart at the end of the block
      if (Value and $C7) = $82 then FDmaRestart := (Value and $20) <> 0;
    3:
      // WR6: commands
      case Value of
        $C3:
          begin
            FDmaActive := False;
            FDmaRestart := False;
            FDmaPrescaler := 0;
            FDmaTimingA := 3;
            FDmaTimingB := 3;
          end;
        $C7: FDmaTimingA := 3;
        $CB: FDmaTimingB := 3;
        $CF:
          begin
            // Load the addresses into the counters
            FDmaA := FDmaPortA;
            FDmaB := FDmaPortB;
            FDmaCount := 0;
          end;
        $D3: FDmaCount := 0;
        $87: DmaStart;
        $83: FDmaActive := False;
        $BB: DmaQueue(DMA_MASK);
        $A7: FDmaReadIdx := 0;
      end;
  end;
end;

{ Reading the port: the registers the read mask chose, in turn }
function TSpectrum.DmaRead: Byte;
var
  I, Bit: Integer;
begin
  Result := $FF;
  if FDmaReadMask = 0 then Exit;
  for I := 0 to 7 do
  begin
    Bit := (FDmaReadIdx + I) mod 7;
    if (FDmaReadMask and (1 shl Bit)) <> 0 then
    begin
      case Bit of
        0: Result := $1A or Ord(FDmaCount = 0) or (Ord(not FDmaActive) shl 5);
        1: Result := FDmaCount and $FF;
        2: Result := FDmaCount shr 8;
        3: Result := FDmaA and $FF;
        4: Result := FDmaA shr 8;
        5: Result := FDmaB and $FF;
        6: Result := FDmaB shr 8;
      end;
      FDmaReadIdx := (Bit + 1) mod 7;
      Exit;
    end;
  end;
end;

procedure TSpectrum.DmaStart;
begin
  if FDmaLength = 0 then Exit;
  FDmaActive := True;
  if FDmaPrescaler = 0 then
    DmaRun(MaxInt)
  else
  begin
    FDmaNextT := FCpuTBase + FCpu.T;
    // Continuous mode keeps the CPU waiting until it is over
    if not FDmaBurst then DmaRun(MaxInt);
  end;
end;

{ One byte from one port to the other; False at the end of the block }
function TSpectrum.DmaByte: Boolean;
var
  Src, Dst: Word;
  SrcIO, DstIO: Boolean;
  V: Byte;
  T: Integer;
begin
  if FDmaAtoB then
  begin
    Src := FDmaA; SrcIO := FDmaAIO; Dst := FDmaB; DstIO := FDmaBIO;
  end
  else
  begin
    Src := FDmaB; SrcIO := FDmaBIO; Dst := FDmaA; DstIO := FDmaAIO;
  end;
  T := FCpu.T;
  if SrcIO then V := ReadPort(Src, T) else V := ReadMem(Src, T);
  if DstIO then WritePort(Dst, V, T) else WriteMem(Dst, V, T);
  Inc(FCpu.T, FDmaTimingA + FDmaTimingB);
  case FDmaAMode of
    0: Dec(FDmaA);
    1: Inc(FDmaA);
  end;
  case FDmaBMode of
    0: Dec(FDmaB);
    1: Inc(FDmaB);
  end;
  Inc(FDmaCount);
  Result := FDmaCount < FDmaLength;
  if not Result and FDmaRestart then
  begin
    FDmaA := FDmaPortA;
    FDmaB := FDmaPortB;
    FDmaCount := 0;
    Result := True;
  end;
end;

{ Transfer up to Count bytes (those due, with the prescaler) }
procedure TSpectrum.DmaRun(Count: Integer);
var
  Now_: Int64;
begin
  while FDmaActive and (Count > 0) do
  begin
    if FDmaPrescaler > 0 then
    begin
      Now_ := FCpuTBase + FCpu.T;
      if Now_ < FDmaNextT then
      begin
        // Burst mode: the CPU runs until the next byte is due
        if FDmaBurst then Exit;
        Inc(FCpu.T, FDmaNextT - Now_);
      end;
      Inc(FDmaNextT, FDmaPrescaler);
    end;
    if not DmaByte then FDmaActive := False;
    Dec(Count);
    // An endless restart with no prescaler would never give the CPU back
    if FDmaRestart and (FDmaPrescaler = 0) and (FDmaCount = 0) then FDmaActive := False;
  end;
end;

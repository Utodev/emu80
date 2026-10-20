{ PzxSnap.inc: pzx's own snapshots, .pzs (included by Spectrum.pas): the
  only ones for the machines that .z80 and .sna can't hold, the ZX Spectrum
  Next (2 MB, its registers, display, copper, DMA) and the ZX-Uno (its 512K
  of SRAM and registers), and a choice for the others (all their state,
  the DivMMC's RAM, ULAplus, three AY chips...). The file: "PZXSNAP", a
  version byte, the model's key (a length byte and its --model name), then
  the machine compressed with zlib, in the order of SnapIO. SD cards and
  disks aren't in it, nor the ZX-Uno's flash (made again from its BIOS and
  ROMs files). }

const
  PZS_MAGIC: array[0..6] of Char = 'PZXSNAP';
  PZS_VERSION = 1;

function TSpectrum.NeedsOwnSnapshot: Boolean;
begin
  Result := IsNext or IsZXUno;
end;

{ The machine into S (Save) or from it, field by field }
procedure TSpectrum.SnapIO(S: TStream; Save: Boolean);

  procedure IO(var Buf; Size: Integer);
  begin
    if Save then S.WriteBuffer(Buf, Size) else S.ReadBuffer(Buf, Size);
  end;

var
  AYs: array[0..2] of TAY8912;
  Regs: array[0..15] of Byte;
  Sel, B, Control: Byte;
  I, K, Banks, FrameT: Integer;
  EIJust, Mapped: Boolean;
  DS: ^TDivState;
begin
  // The RAM kept (the SRAM pages of the ZX-Uno, the Next's 1792K)
  Banks := RamBanksUsed;
  IO(Banks, SizeOf(Banks));
  if Banks <> RamBanksUsed then raise Exception.Create('Not a snapshot of this machine');
  IO(FRam, Banks * SizeOf(TBank));
  // The CPU, and where it is in the frame
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
  // Ports, the ULA, ULAplus
  IO(FPort7FFD, 1); IO(FPort1FFD, 1); IO(FPortDFFD, 1); IO(FBorder, 1); IO(FUlaOut, 1);
  IO(FTimexPort, 1); IO(FScreenBank, SizeOf(FScreenBank));
  IO(FFlashCounter, SizeOf(FFlashCounter)); IO(FFlashOn, 1);
  IO(FULAPlusReg, 1); IO(FULAPlusMode, 1); IO(FULAPlusPal, SizeOf(FULAPlusPal));
  // The DivMMC (its memory is in the machine's SRAM)
  Control := FDiv.Control;
  Mapped := FDiv.Mapped;
  IO(Control, 1);
  IO(Mapped, 1);
  if NeedsOwnSnapshot then
  begin
    if not Save then
    begin
      FDiv.Reset(True);                 // MAPRAM too, as the snapshot says
      FDiv.SetControl(Control);
      FDiv.Mapped := Mapped;
    end;
  end
  else
  begin
    // The other models: the DivMMC has its own 128K of RAM
    New(DS);
    try
      FDiv.SaveState(DS^);
      IO(DS^.Ram, SizeOf(DS^.Ram));
      if not Save then
      begin
        DS^.Control := Control;
        DS^.Mapped := Mapped;
        FDiv.LoadState(DS^);
      end;
    finally
      Dispose(DS);
    end;
  end;
  // The AY chips: their registers, which one and which register
  AYs[0] := FAY; AYs[1] := FAY2; AYs[2] := FAY3;
  for I := 0 to 2 do
  begin
    for K := 0 to 15 do Regs[K] := AYs[I].GetRegister(K);
    Sel := AYs[I].Selected;
    IO(Regs, SizeOf(Regs));
    IO(Sel, 1);
    if not Save then
    begin
      AYs[I].Reset;
      for K := 0 to 15 do AYs[I].WriteRegister(K, Regs[K]);
      AYs[I].SelectRegister(Sel);
    end;
  end;
  IO(FAYChip, SizeOf(Integer)); IO(FAYPan, SizeOf(FAYPan));

  if IsZXUno then
  begin
    // Its registers and the SPI flash's state (not its contents)
    IO(FZXReg, SizeOf(FZXReg)); IO(FZXUnoReg, 1);
    IO(FSpiBus, SizeOf(FSpiBus)); IO(FSpiIndex, SizeOf(Integer)); IO(FSpiAddr, SizeOf(Integer));
    IO(FSpiNext, 1); IO(FSpiStatus, 1); IO(FCoreIdPos, SizeOf(Integer));
    IO(FZXCustomRun, 1); IO(FZXKbdBat, 1);
    Exit;
  end;
  if not IsNext then
  begin
    // The Currah µSpeech's ROM paged in or not
    B := Ord(FCurrah.Paged);
    IO(B, 1);
    FCurrah.Paged := B <> 0;
    Exit;
  end;

  // The Next: registers, memory, boot ROM, Multiface
  IO(FNextReg, SizeOf(FNextReg)); IO(FNextSel, 1); IO(FNextMMU, SizeOf(FNextMMU));
  IO(FNextSpeed, SizeOf(FNextSpeed)); IO(FNextSpecial, 1);
  IO(FNextSram, SizeOf(FNextSram)); IO(FNextBootRom, SizeOf(FNextBootRom)); IO(FNextBootOn, 1);
  IO(FMfNmi, 1); IO(FMfOn, 1); IO(FMfInvisible, 1);
  B := Ord(FDiv.NmiButton);
  IO(B, 1);
  FDiv.NmiButton := B <> 0;
  // Display: palettes, clip windows, Layer 2, sprites, copper
  IO(FNextPal, SizeOf(FNextPal)); IO(FNextPal44, 1);
  IO(FNextClip, SizeOf(FNextClip)); IO(FNextClipIdx, SizeOf(FNextClipIdx));
  IO(FNextL2Port, 1); IO(FNextL2Offset, 1);
  IO(FSprAttr, SizeOf(FSprAttr)); IO(FSprPattern, SizeOf(FSprPattern));
  IO(FSprIndex, SizeOf(Integer)); IO(FSprAttrIdx, SizeOf(Integer)); IO(FSprPatAddr, SizeOf(Integer));
  IO(FSprStatus, 1);
  IO(FCopper, SizeOf(FCopper)); IO(FCopperAddr, SizeOf(Integer)); IO(FCopperPC, SizeOf(Integer));
  IO(FCopperStopped, 1); IO(FCopperClk, SizeOf(Integer)); IO(FCopperDue, SizeOf(Integer));
  IO(FCopperRestarted, 1);
  // zxnDMA and the DACs
  IO(FDmaQueue, SizeOf(FDmaQueue)); IO(FDmaQueueLen, SizeOf(Integer));
  IO(FDmaPortA, 2); IO(FDmaPortB, 2); IO(FDmaLength, 2); IO(FDmaA, 2); IO(FDmaB, 2); IO(FDmaCount, 2);
  IO(FDmaAtoB, 1); IO(FDmaAIO, 1); IO(FDmaBIO, 1); IO(FDmaBurst, 1); IO(FDmaRestart, 1); IO(FDmaActive, 1);
  IO(FDmaAMode, SizeOf(Integer)); IO(FDmaBMode, SizeOf(Integer));
  IO(FDmaTimingA, SizeOf(Integer)); IO(FDmaTimingB, SizeOf(Integer));
  IO(FDmaPrescaler, SizeOf(Integer)); IO(FDmaNextT, SizeOf(Int64));
  IO(FDmaReadMask, SizeOf(Integer)); IO(FDmaReadIdx, SizeOf(Integer));
  IO(FNextDac, SizeOf(FNextDac));
end;

class function TSpectrum.OwnSnapshotModel(const FileName: string): TSpectrumModel;
var
  F: TFileStream;
  Magic: array[0..6] of Char;
  V, Len: Byte;
  Key: string;
  M: TSpectrumModel;
begin
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    F.ReadBuffer(Magic, SizeOf(Magic));
    F.ReadBuffer(V, 1);
    if not CompareMem(@Magic, @PZS_MAGIC, SizeOf(Magic)) or (V <> PZS_VERSION) then
      raise Exception.Create('Not a pzx snapshot');
    F.ReadBuffer(Len, 1);
    SetLength(Key, Len);
    if Len > 0 then F.ReadBuffer(Key[1], Len);
  finally
    F.Free;
  end;
  for M := Low(TSpectrumModel) to High(TSpectrumModel) do
    if Key = ModelKey(M) then Exit(M);
  raise Exception.CreateFmt('A pzx snapshot of an unknown machine (%s)', [Key]);
end;

procedure TSpectrum.SaveOwnSnapshot(const FileName: string);
var
  F: TFileStream;
  Z: TCompressionStream;
  V: Byte;
  Key: string;
begin
  F := TFileStream.Create(FileName, fmCreate);
  try
    F.WriteBuffer(PZS_MAGIC, SizeOf(PZS_MAGIC));
    V := PZS_VERSION;
    F.WriteBuffer(V, 1);
    Key := ModelKey(FModel);
    V := Length(Key);
    F.WriteBuffer(V, 1);
    F.WriteBuffer(Key[1], Length(Key));
    Z := TCompressionStream.Create(clDefault, F);
    try
      SnapIO(Z, True);
    finally
      Z.Free;
    end;
  finally
    F.Free;
  end;
end;

procedure TSpectrum.LoadOwnSnapshot(const FileName: string);
var
  F: TFileStream;
  Z: TDecompressionStream;
  P, I: Integer;
  Skip: array[0..263] of Byte;
  Len: Byte;
begin
  if OwnSnapshotModel(FileName) <> FModel then
    raise Exception.Create('The snapshot is of another machine');
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    // The header, already checked
    F.ReadBuffer(Skip, SizeOf(PZS_MAGIC) + 1);
    F.ReadBuffer(Len, 1);
    if Len > 0 then F.ReadBuffer(Skip, Len);
    Z := TDecompressionStream.Create(F);
    try
      try
        SnapIO(Z, False);
      except
        // Half loaded: start the machine again rather than run that
        Reset(True);
        raise;
      end;
    finally
      Z.Free;
    end;
  finally
    F.Free;
  end;
  // What follows from it: colours, paging, speed, timing
  for I := 0 to 63 do SetULAPlusEntry(I, FULAPlusPal[I]);
  FNMIRequest := False;
  FEventCount := 0;
  if IsZXUno then
  begin
    FDivOn := (FZXReg[0] and 2) <> 0;
    Issue2 := (FZXReg[0] and 8) <> 0;
    SetZXUnoTiming;
    FNextSpeed := 1 shl ((FZXReg[$0B] shr 6) and 3);
    SetSpeed(FUserSpeed);
    FUnoAutoLoad := -1;
    UpdatePaging;
  end
  else if not IsNext then
    UpdatePaging
  else
  begin
    for P := 0 to 7 do
      for I := 0 to 255 do FNextPalRGB[P, I] := Rgb9(FNextPal[P, I] and $1FF);
    FNexOpen := False;
    FNexData := nil;
    FNextResetReq := 0;
    NextSetDivEntries;
    NextUpdatePaging;
    SetSpeed(FUserSpeed);
  end;
  RestartRender;
end;

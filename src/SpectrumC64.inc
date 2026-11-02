{ SpectrumC64.inc: the Commodore 64 in TSpectrum (included by Spectrum.pas). The machine itself is TC64 (C64.pas, with
  the 6510, the VIC-II, the CIAs, the SID and the 1541 drives); here are the parts that join it to what the models
  share: the model's setup and ROMs, the frame loop, the picture and sound the emulator thread takes, memory for the
  debuggers and the tape. }

procedure TSpectrum.SetupC64;
var
  Hw: TC64;
begin
  if FC64 <> nil then Hw := FC64 else Hw := TC64.Create;
  try
    Hw.LoadRoms(RomPath(0), RomPath(1), RomPath(2), RomPath(3));
  except
    if Hw <> FC64 then Hw.Free;
    raise;
  end;
  if Hw <> FC64 then
  begin
    FC64.Free;
    FC64 := Hw;
  end;
  FC64.OnDaadRead := @DaadRead;
  FDiv.UseMemory(nil, nil);
  FDivOn := False;
  FCurrahOn := False;
  FCpu.Z80N := False;
  Z80NMnemonics := False;
  FDiv.ControlReadable := False;
  FDiv.NextEntries := False;
  SetLength(FSamples, 4096);
end;

procedure TSpectrum.C64Reset(Hard: Boolean);
begin
  FC64.Reset(Hard);
  FResetFrame := FFrameCount;
  CancelAutoType;
end;

{ After the frame: its sound (as the SID made it), for the emulator thread }
procedure TSpectrum.FinishFrameC64;
var
  I, N: Integer;
  P: PSmallInt;
begin
  N := FC64.SampleCount;
  if N > Length(FSamples) then SetLength(FSamples, N + 64);
  P := PSmallInt(FC64.Samples);
  for I := 0 to N - 1 do
  begin
    if FMuted then
    begin
      FSamples[I].L := 0;
      FSamples[I].R := 0;
    end
    else
    begin
      FSamples[I].L := Round(P[I * 2] * FVolume);
      FSamples[I].R := Round(P[I * 2 + 1] * FVolume);
    end;
  end;
  FSampleCount := N;
  Inc(FFrameCount);
end;

function TSpectrum.RunFrameC64: Boolean;
begin
  FBreakHit := False;
  FBreakKind := bkNone;
  Result := FC64.RunFrame;
  if not Result then
  begin
    case FC64.BreakKind of
      cbkExec: FBreakKind := bkExec;
      cbkRunTo: FBreakKind := bkRunTo;
      cbkDaad: FBreakKind := bkDaad;
    else
      FBreakKind := bkMemory;
    end;
    FBreakInstr := FC64.BreakInstr;
    FBreakHit := True;
    Exit;
  end;
  FinishFrameC64;
end;

procedure TSpectrum.StepInstructionC64;
var
  Frames: Int64;
begin
  Frames := FC64.Frames;
  FC64.StepInstruction;
  if FC64.Frames <> Frames then FinishFrameC64;
end;

function TSpectrum.C64TapeText: string;
begin
  if not FC64.Tape.Present then Exit('stopped');
  if FC64.TapePressed and FC64.TapeMotor then Result := 'playing'
  else if FC64.TapePressed then Result := _('play pressed, waiting for the motor')
  else if FC64.Tape.AtEnd then Result := _('end of tape')
  else Result := 'stopped';
end;

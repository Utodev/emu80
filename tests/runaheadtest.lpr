{ runaheadtest: RunAhead on the Z80 machines (the 48K, 128K, +3, ZX-Uno, Next, CPC 464 and 6128, SAM Coupe and MSX2). On
  each, two machines run the same little program (after a HALT, every frame: a counter in RAM, the border, and the
  sound chip: the AY, the SAA1099 or the PSG), one with RunAhead (2 frames) and one without: frame after frame the
  machine itself (the CPU, the 64K the CPU sees) and its sound must be the same in both, and the picture shown by the
  first must be the one the second shows 2 frames later. A machine whose ROMs are not there is skipped.
    runaheadtest <roms folder> [specnext folder] }
program runaheadtest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Models, Spectrum;

const
  FRAMES_AHEAD = 2;
  FRAMES = 40;
  PIC = FB_WIDTH * SCREEN_HEIGHT;

type
  TPicture = array of LongWord;
  TFamily = (fmSpectrum, fmSam, fmCpc, fmMsx);

var
  Failures: Integer = 0;

procedure Check(Cond: Boolean; const What: string);
begin
  if Cond then WriteLn('ok    ', What)
  else
  begin
    WriteLn('FAIL  ', What);
    Inc(Failures);
  end;
end;

function Fingerprint(Sp: TSpectrum): string;
var
  J: Integer;
  H: QWord;
begin
  H := 0;
  for J := 0 to $FFFF do H := H * 31 + Sp.Peek(J);
  Result := Format('PC=%.4x SP=%.4x AF=%.2x%.2x HL=%.4x T=%d frame=%d mem=%x', [Sp.Cpu.PC.W, Sp.Cpu.SP.W, Sp.Cpu.A,
    Sp.Cpu.F, Sp.Cpu.HL.W, Sp.Cpu.T, Sp.FrameCount, H]);
end;

function SameSamples(A, B: TSpectrum): Boolean;
begin
  Result := (A.SampleCount = B.SampleCount) and (CompareByte(A.Samples^, B.Samples^, A.SampleCount * 4) = 0);
end;

{ The program at Base: HALT (a NOP where no interrupt comes: the Next without its card), a counter at Base + 100h up
  by one, then the family's own part, and again }
procedure PutProgram(Sp: TSpectrum; Family: TFamily; Base: Word; WithHalt: Boolean);
var
  HEAD: array[0..7] of Byte = ($76, $3A, $00, $81, $3C, $32, $00, $81);
const
  // OUT (FE),A, and the AY: mixer, volume A, tone A = the counter
  SPECTRUM: array[0..36] of Byte = ($D3, $FE, $5F, $01, $FD, $FF, $3E, $07, $ED, $79, $06, $BF, $3E, $3E, $ED, $79,
    $06, $FF, $3E, $08, $ED, $79, $06, $BF, $3E, $0F, $ED, $79, $06, $FF, $AF, $ED, $79, $06, $BF, $ED, $59);
  // OUT (FE),A, and the SAA1099: enabled, channel 0's frequency on, its amplitude, octave and frequency
  SAM: array[0..59] of Byte = ($D3, $FE, $5F, $01, $FF, $01,
    $3E, $1C, $ED, $79, $06, $00, $3E, $01, $ED, $79, $06, $01,
    $3E, $14, $ED, $79, $06, $00, $3E, $01, $ED, $79, $06, $01,
    $3E, $00, $ED, $79, $06, $00, $3E, $FF, $ED, $79, $06, $01,
    $3E, $10, $ED, $79, $06, $00, $3E, $03, $ED, $79, $06, $01,
    $3E, $08, $ED, $79, $06, $00);
  SAM_END: array[0..1] of Byte = ($ED, $59);
  // The border (pen 16 of the Gate Array)
  CPC: array[0..10] of Byte = ($5F, $01, $10, $7F, $ED, $49, $7B, $E6, $1F, $F6, $40);
  CPC_END: array[0..1] of Byte = ($ED, $79);
  // The border (VDP R#7), and the PSG: mixer, volume A, tone A = the counter
  MSX: array[0..24] of Byte = ($5F, $D3, $99, $3E, $87, $D3, $99, $3E, $07, $D3, $A0, $3E, $3E, $D3, $A1, $3E, $08,
    $D3, $A0, $3E, $0F, $D3, $A1, $AF, $D3);
  MSX_END: array[0..3] of Byte = ($A0, $7B, $D3, $A1);
var
  Code: array of Byte;
  N: Integer;

  procedure Put(const B: array of Byte);
  var
    K: Integer;
  begin
    for K := 0 to High(B) do
    begin
      SetLength(Code, N + 1);
      Code[N] := B[K];
      Inc(N);
    end;
  end;

begin
  N := 0;
  if not WithHalt then HEAD[0] := 0;
  HEAD[3] := (Base shr 8) + 1;
  HEAD[7] := (Base shr 8) + 1;
  Put(HEAD);
  case Family of
    fmSpectrum: Put(SPECTRUM);
    fmSam: begin Put(SAM); Put(SAM_END); end;
    fmCpc: begin Put(CPC); Put(CPC_END); end;
    fmMsx: begin Put(MSX); Put(MSX_END); end;
  end;
  // JR back to the start
  Put([$18, Byte(-(N + 2))]);
  for N := 0 to High(Code) do Sp.PokeRam(Base + N, Code[N]);
  Sp.PokeRam(Base + $100, 0);
  Sp.Cpu.PC.W := Base;
  Sp.Cpu.IFF1 := True;
  Sp.Cpu.IFF2 := True;
  Sp.Cpu.Halted := False;
end;

function MakeMachine(Model: TSpectrumModel; const Roms, Distro: string): TSpectrum;
begin
  if Model = smZXNext then
  begin
    Result := TSpectrum.Create(sm48K, Roms);
    Result.NextDir := Distro;
    Result.SetModel(smZXNext);
    Result.Reset(True);
  end
  else
    Result := TSpectrum.Create(Model, Roms);
end;

procedure TryModel(Model: TSpectrumModel; Family: TFamily; Boot: Integer; const Roms, Distro: string;
  Base: Word = $8000; WithHalt: Boolean = True);
var
  Normal, Ahead: TSpectrum;
  Pics, Shows: array of TPicture;
  I, SameState, SameSound, SamePic, Shown: Integer;
  Name: string;
begin
  Name := ModelInfo[Model].Name;
  try
    Normal := MakeMachine(Model, Roms, Distro);
    Ahead := MakeMachine(Model, Roms, Distro);
  except
    on E: Exception do
    begin
      WriteLn('SKIP  ', Name, ': ', E.Message);
      Exit;
    end;
  end;
  try
    Ahead.RunAhead := FRAMES_AHEAD;
    for I := 1 to Boot do
    begin
      Normal.RunFrame;
      Ahead.RunFrame;
    end;
    PutProgram(Normal, Family, Base, WithHalt);
    PutProgram(Ahead, Family, Base, WithHalt);
    for I := 1 to 20 do
    begin
      Normal.RunFrame;
      Ahead.RunFrame;
    end;
    SetLength(Pics, FRAMES + FRAMES_AHEAD + 1);
    SetLength(Shows, FRAMES + 1);
    SameState := 0;
    SameSound := 0;
    SamePic := 0;
    Shown := 0;
    for I := 0 to FRAMES + FRAMES_AHEAD do
    begin
      Normal.RunFrame;
      SetLength(Pics[I], PIC);
      Normal.CopyFrameBuffer(@Pics[I][0]);
      if I > FRAMES then Continue;
      Ahead.RunFrame;
      if Fingerprint(Normal) = Fingerprint(Ahead) then Inc(SameState)
      else if SameState = I then WriteLn('      ', Name, ' frame ', I, ': ', Fingerprint(Normal), ' / ', Fingerprint(Ahead));
      if SameSamples(Normal, Ahead) then Inc(SameSound);
      if Ahead.AheadShown then Inc(Shown);
      SetLength(Shows[I], PIC);
      Ahead.CopyFrameBuffer(@Shows[I][0]);
    end;
    for I := 0 to FRAMES do
      if CompareByte(Shows[I][0], Pics[I + FRAMES_AHEAD][0], PIC * 4) = 0 then Inc(SamePic);
    // (the picture must change from frame to frame, or the last check proves nothing)
    Check(CompareByte(Pics[0][0], Pics[1][0], PIC * 4) <> 0, Name + ': the program changes the picture every frame');
    Check(Shown = FRAMES + 1, Format('%s: RunAhead is used (%d of %d frames)', [Name, Shown, FRAMES + 1]));
    Check(SameState = FRAMES + 1, Format('%s: the machine is the same with RunAhead and without (%d of %d frames)',
      [Name, SameState, FRAMES + 1]));
    Check(SameSound = FRAMES + 1, Format('%s: the sound is the same: the real frame''s (%d of %d frames)',
      [Name, SameSound, FRAMES + 1]));
    Check(SamePic = FRAMES + 1, Format('%s: the picture shown is the one of %d frames later (%d of %d frames)',
      [Name, FRAMES_AHEAD, SamePic, FRAMES + 1]));
    Ahead.RunAhead := 0;
    Ahead.RunFrame;
    Check(not Ahead.AheadShown, Name + ': switched off, the picture is the real one again');
  finally
    Normal.Free;
    Ahead.Free;
  end;
end;

var
  Roms, Distro: string;
begin
  Roms := ParamStr(1);
  Distro := ParamStr(2);
  TryModel(sm48K, fmSpectrum, 150, Roms, Distro);
  TryModel(sm128K, fmSpectrum, 150, Roms, Distro);
  TryModel(smPlus3, fmSpectrum, 200, Roms, Distro);
  TryModel(smZXUno, fmSpectrum, 400, Roms, Distro);
  if (Distro <> '') and DirectoryExists(Distro) then TryModel(smZXNext, fmSpectrum, 100, Roms, Distro, $8000, False)
  else WriteLn('SKIP  ZX Spectrum Next: no specnext folder given');
  TryModel(smCPC464, fmCpc, 200, Roms, Distro);
  TryModel(smCPC6128, fmCpc, 200, Roms, Distro);
  TryModel(smSAM, fmSam, 300, Roms, Distro);
  TryModel(smMSX2, fmMsx, 700, Roms, Distro, $C000);
  if Failures > 0 then
  begin
    WriteLn(Failures, ' failure(s)');
    Halt(1);
  end;
end.

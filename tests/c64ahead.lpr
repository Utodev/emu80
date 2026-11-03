{ c64ahead: RunAhead on the Commodore 64. Two machines run the same BASIC program (the border changes colour every
  frame), one with RunAhead (2 frames) and one without: frame after frame the machine itself (the RAM, the registers,
  the colour RAM, the picture drawn, the drive) and its sound must be the same in both (running ahead leaves nothing
  behind), and the picture shown by the first must be the one the second shows 2 frames later.
    c64ahead <roms folder> }
program c64ahead;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Models, Spectrum, C64, C64Vic;

const
  FRAMES_AHEAD = 2;
  FRAMES = 60;
  PIC = VIC_WIDTH * 2 * VIC_HEIGHT;

type
  TPicture = array[0..PIC - 1] of LongWord;

var
  Normal, Ahead: TSpectrum;
  Pics, Shows: array of TPicture;
  Failures: Integer = 0;
  I, SameState, SameSound, SamePic, Shown: Integer;

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
  C: TC64;
  J: Integer;
  H: QWord;
begin
  C := Sp.C64Hw;
  Result := Format('PC=%.4x A=%.2x X=%.2x Y=%.2x SP=%.2x P=%.2x cyc=%d', [C.Cpu.PC, C.Cpu.A, C.Cpu.X, C.Cpu.Y, C.Cpu.SP,
    C.Cpu.P, C.Cpu.Cycles]);
  H := 0;
  for J := 0 to $FFFF do H := H * 31 + C.PeekRam(J);
  for J := 0 to 1023 do H := H * 31 + C.Vic.ColorRam[J];
  for J := 0 to High(C.Vic.Frame) do H := H * 31 + C.Vic.Frame[J];
  for J := 0 to $7FF do H := H * 31 + C.Drive[0].Peek(J);
  Result := Result + Format(' hash=%x raster=%d drive PC=%.4x', [H, C.Vic.Raster, C.Drive[0].Cpu.PC]);
end;

function SameSamples: Boolean;
begin
  Result := (Normal.C64Hw.SampleCount = Ahead.C64Hw.SampleCount) and
    (CompareByte(Normal.C64Hw.Samples^, Ahead.C64Hw.Samples^, Normal.C64Hw.SampleCount * 4) = 0);
end;

begin
  Normal := TSpectrum.Create(smC64, ParamStr(1));
  Ahead := TSpectrum.Create(smC64, ParamStr(1));
  Ahead.C64Hw.RunAhead := FRAMES_AHEAD;
  for I := 1 to 150 do
  begin
    Normal.RunFrame;
    Ahead.RunFrame;
  end;
  // The border follows the jiffy clock (one more every frame), and a voice plays (the sound must be the real one)
  Normal.C64Hw.TypeText('POKE54296,15:POKE54277,9:POKE54278,240:POKE54273,20:POKE54276,33'#13 +
    '10 POKE53280,PEEK(162):GOTO10'#13'RUN'#13);
  Ahead.C64Hw.TypeText('POKE54296,15:POKE54277,9:POKE54278,240:POKE54273,20:POKE54276,33'#13 +
    '10 POKE53280,PEEK(162):GOTO10'#13'RUN'#13);
  for I := 1 to 150 do
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
    Normal.C64Hw.CopyFrame(@Pics[I][0]);
    if I > FRAMES then Continue;
    Ahead.RunFrame;
    if Fingerprint(Normal) = Fingerprint(Ahead) then Inc(SameState);
    if SameSamples then Inc(SameSound);
    if Ahead.C64Hw.AheadShown then Inc(Shown);
    Ahead.C64Hw.CopyFrame(@Shows[I][0]);
  end;
  for I := 0 to FRAMES do
    if CompareByte(Shows[I], Pics[I + FRAMES_AHEAD], SizeOf(TPicture)) = 0 then Inc(SamePic);
  Check(Shown = FRAMES + 1, Format('RunAhead is used while the program runs (%d of %d frames)', [Shown, FRAMES + 1]));
  Check(SameState = FRAMES + 1, Format('the machine is the same with RunAhead and without (%d of %d frames)',
    [SameState, FRAMES + 1]));
  Check(SameSound = FRAMES + 1, Format('the sound is the same: the real frame''s (%d of %d frames)', [SameSound, FRAMES + 1]));
  Check(SamePic = FRAMES + 1, Format('the picture shown is the one of %d frames later (%d of %d frames)',
    [FRAMES_AHEAD, SamePic, FRAMES + 1]));
  // Switched off, the real picture again
  Ahead.C64Hw.RunAhead := 0;
  Ahead.RunFrame;
  Normal.RunFrame;
  Check(not Ahead.C64Hw.AheadShown, 'switched off, the picture is the real one again');
  Normal.Free;
  Ahead.Free;
  if Failures > 0 then Halt(1);
end.

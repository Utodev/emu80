{ c64sound: the SID through TSpectrum: a triangle wave on voice 1 (set from BASIC) must come out at its frequency. }
program c64sound;

{$mode objfpc}{$H+}

uses
  SysUtils, Models, Spectrum, C64;

var
  Sp: TSpectrum;
  I, J, N, Crossings, Peak: Integer;
  S: PSmallInt;
  Prev: Integer;
  Freq: Double;
begin
  Sp := TSpectrum.Create(smC64, ParamStr(1));
  for I := 1 to 150 do Sp.RunFrame;
  Sp.C64Hw.TypeText('POKE54296,15:POKE54277,0:POKE54278,240:POKE54273,29:POKE54272,0:POKE54276,17'#13);
  for I := 1 to 40 do Sp.RunFrame;
  Crossings := 0;
  N := 0;
  Peak := 0;
  Prev := 0;
  for I := 1 to 100 do
  begin
    Sp.RunFrame;
    S := PSmallInt(Sp.Samples);
    for J := 0 to Sp.SampleCount - 1 do
    begin
      if (Prev < 0) and (S[J * 2] >= 0) then Inc(Crossings);
      Prev := S[J * 2];
      if Abs(Prev) > Peak then Peak := Abs(Prev);
    end;
    Inc(N, Sp.SampleCount);
  end;
  Freq := Crossings / (N / 44100);
  WriteLn('crossings ', Crossings, ' over ', N, ' samples: ', Freq:0:1, ' Hz, peak ', Peak);
  if (Freq > 400) and (Freq < 470) and (Peak > 1000) then WriteLn('ok: the SID plays 436 Hz')
  else
  begin
    WriteLn('FAIL');
    Halt(1);
  end;
end.

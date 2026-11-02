{ c64tape: loads a program from a .tap on the C64's datasette (LOAD and RUN, with PLAY pressed) and checks it ran.
    c64tape <roms folder> <.tap> <text the program prints> }
program c64tape;

{$mode objfpc}{$H+}

uses
  SysUtils, Models, Spectrum, C64;

var
  Sp: TSpectrum;
  I, J: Integer;
  Screen: string;
  Frames: Integer;
  C: Byte;
begin
  Sp := TSpectrum.Create(smC64, ParamStr(1));
  Sp.C64Hw.InsertTape(ParamStr(2));
  Sp.AutoLoad(False);
  Frames := 0;
  for I := 1 to 6000 do
  begin
    Sp.RunFrame;
    Inc(Frames);
    Screen := '';
    for J := 0 to 999 do
    begin
      C := Sp.C64Hw.PeekRam($0400 + J) and $7F;
      if C < 32 then Screen := Screen + Chr(C + 64) else if C < 64 then Screen := Screen + Chr(C) else Screen := Screen + '#';
    end;
    if (Pos(UpperCase(ParamStr(3)), Screen) > 0) and (not Sp.C64Hw.TapeMotor) and (I > 100) then Break;
  end;
  for J := 0 to 24 do WriteLn(Trim(Copy(Screen, J * 40 + 1, 40)));
  if Pos(UpperCase(ParamStr(3)), Screen) > 0 then
    WriteLn('ok: ', ParamStr(3), ' after ', Frames, ' frames, tape position ', Sp.C64Hw.Tape.Pos, ' of ', Sp.C64Hw.Tape.Count)
  else
  begin
    WriteLn('FAIL: not found after ', Frames, ' frames, tape ', Sp.C64Hw.Tape.Pos, ' of ', Sp.C64Hw.Tape.Count);
    Halt(1);
  end;
end.

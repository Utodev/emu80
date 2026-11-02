{ c64save: SAVE to a blank formatted .d64 through the 1541's own DOS (the write head, GCR written back into the image), then
  LOAD it again and LIST: the program must come back. Also the second drive (device 9).
    c64save <roms folder> }
program c64save;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Models, Spectrum, C64, C64Disk;

var
  Sp: TSpectrum;
  D, D2: TD64Image;
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

procedure Run(Frames: Integer);
var
  I: Integer;
begin
  for I := 1 to Frames do Sp.RunFrame;
end;

function ScreenText: string;
var
  J: Integer;
  C: Byte;
begin
  Result := '';
  for J := 0 to 999 do
  begin
    C := Sp.C64Hw.PeekRam($0400 + J) and $7F;
    if C < 32 then Result := Result + Chr(C + 64) else if C < 64 then Result := Result + Chr(C) else Result := Result + '#';
  end;
end;

begin
  Sp := TSpectrum.Create(smC64, ParamStr(1));
  D := TD64Image.Create;
  D.Format('TEST DISK', '64');
  Sp.C64Hw.InsertDisk(0, D);
  Run(150);
  Sp.C64Hw.TypeText('10 PRINT"SAVED OK"'#13);
  Run(30);
  Sp.C64Hw.TypeText('SAVE"PROG",8'#13);
  Run(900);
  Check(Pos('SAVING', ScreenText) > 0, 'SAVING was shown');
  Check(D.Dirty, 'the image was changed by the drive');
  Sp.C64Hw.TypeText('NEW'#13);
  Run(30);
  Sp.C64Hw.TypeText('LOAD"PROG",8'#13);
  Run(900);
  Sp.C64Hw.TypeText('RUN'#13);
  Run(60);
  Check(Pos('SAVED OK', ScreenText) > 0, 'the saved program loads and runs');
  Sp.C64Hw.TypeText('LOAD"$",8'#13);
  Run(500);
  Sp.C64Hw.TypeText('LIST'#13);
  Run(60);
  Check(Pos('"PROG"', ScreenText) > 0, 'the directory lists PROG');
  // The second drive
  D2 := TD64Image.Create;
  D2.Format('SECOND', '99');
  Sp.C64Hw.SetDriveEnabled(1, True);
  Sp.C64Hw.InsertDisk(1, D2);
  Sp.Reset(True);
  Run(150);
  Sp.C64Hw.TypeText('LOAD"$",9'#13);
  Run(500);
  Sp.C64Hw.TypeText('LIST'#13);
  Run(60);
  Check(Pos('"SECOND', ScreenText) > 0, 'drive 9 answers: ' + Trim(Copy(ScreenText, 41, 40)));
  Sp.Free;
  if Failures > 0 then
  begin
    WriteLn(Failures, ' failure(s)');
    Halt(1);
  end;
end.

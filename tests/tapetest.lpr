{ tapetest: fast loading on the 48K when the tape is started with Play:
  a tape already loaded (so at its end), a hard reset, LOAD "" typed, then
  Play (which starts the tape again) must load it at once, not in real
  time, and the right blocks (the DAAD Ready test game, whose database is at
  8400); and .pzs snapshots of the 48K and the 128K.

    tapetest <roms folder> <tests/daad folder> }
program tapetest;

{$mode objfpc}{$H+}

uses
  SysUtils, Models, Spectrum;

var
  Sp: TSpectrum;
  Err, Snap: string;
  I, T: Integer;
  PC: Word;
  Failures: Integer = 0;

procedure Check(Cond: Boolean; const What: string);
begin
  if not Cond then
  begin
    WriteLn('FAIL  ', What);
    Inc(Failures);
  end;
end;

procedure Frames(N: Integer);
var
  I: Integer;
begin
  for I := 1 to N do Sp.RunFrame;
end;

begin
  Sp := TSpectrum.Create(sm48K, ParamStr(1));
  try
    Sp.FastLoad := True;
    Sp.AutoPlayTape := True;
    Sp.Tape.LoadTAP(IncludeTrailingPathDelimiter(ParamStr(2)) + 'test48.tap');
    Sp.AutoLoad;
    Frames(300);
    Check(Sp.Tape.Current = Sp.Tape.Count, 'opening the tape loads it all');
    Sp.Reset(True);
    Frames(100);
    Sp.TypeText('j""\n', Err);
    while Sp.AutoTyping do Sp.RunFrame;
    Frames(20);
    Check(Sp.Peek($8401) = 0, 'nothing loaded with the tape at its end');
    Sp.PlayTape;
    // Fast loading: in a few frames, not the minutes of real time
    for I := 1 to 25 do Sp.RunFrame;
    Check((Sp.Peek($8401) = $11) and (Sp.Peek($8402) = $5F), 'Play with fast loading loads at once');
    Check(not Sp.Tape.Playing, 'fast loading stops the tape');

    // A .pzs snapshot of the 48K with the game: saved, reset, loaded back
    Snap := GetTempDir + 'tapetest.pzs';
    Frames(50);
    PC := Sp.Cpu.PC.W;
    Sp.SaveOwnSnapshot(Snap);
    Check(TSpectrum.OwnSnapshotModel(Snap) = sm48K, '.pzs: of the 48K');
    Sp.Reset(True);
    Sp.LoadOwnSnapshot(Snap);
    Check((Sp.Peek($8401) = $11) and (Sp.Cpu.PC.W = PC), '.pzs: the 48K''s memory and CPU');

    // The 128K: its paging (bank 3 at C000, the shadow screen) and memory
    Sp.SetModel(sm128K);
    Frames(50);
    T := Sp.Cpu.T;
    Sp.WritePort($7FFD, $0B, T);
    Sp.Poke($C000, $AB);
    Sp.SaveOwnSnapshot(Snap);
    Sp.Reset(True);
    Sp.LoadOwnSnapshot(Snap);
    Check((Sp.SlotBank(3) = 3) and (Sp.Peek($C000) = $AB), '.pzs: the 128K''s paging and memory');
    DeleteFile(Snap);
  finally
    Sp.Free;
  end;
  if Failures = 0 then WriteLn('Tape fast loading after Play, .pzs of the 48K and 128K: all passed')
  else Halt(1);
end.

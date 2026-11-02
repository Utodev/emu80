{ c64daad: the Adventure Debugger's view of a DAAD game on the Commodore 64: loads a game from its .d64 (the interpreter
  loads the database at 3880), reads the database, follows the interpreter (the fetch instruction is learnt), and checks that
  each stop is on a condact the database has, with the flags at 02A7 (flag 38 is the player's location).

    c64daad <roms folder> <game .d64> [<loader file name: DAAD>] }
program c64daad;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Models, Spectrum, Daad, C64, C64Disk;

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

var
  Sp: TSpectrum;
  D: TD64Image;
  I, Stops, Good, Loc: Integer;
  Game: TDaadGame;
  Mem: TDaadMemory;
  Map: array[0..65535] of Byte;
  Loader: string;
  Ok: Boolean;
begin
  if ParamCount < 2 then
  begin
    WriteLn('usage: c64daad <roms folder> <game .d64> [loader name]');
    Halt(2);
  end;
  Loader := 'DAAD';
  if ParamCount >= 3 then Loader := ParamStr(3);
  Sp := TSpectrum.Create(smC64, ParamStr(1));
  D := TD64Image.Create;
  D.LoadFromFile(ParamStr(2));
  Sp.C64Hw.InsertDisk(0, D);
  Sp.C64Hw.TypeText('LOAD"' + Loader + '",8,1'#13);
  // The game loads (a real drive: about a minute), then runs
  for I := 1 to 7500 do
  begin
    Sp.RunFrame;
    if (I = 400) then Sp.C64Hw.TypeText('RUN'#13);
  end;
  for I := 0 to 65535 do Mem[I] := Sp.PeekRam(I);
  Game := TDaadGame.Create;
  Check(Game.Load(Mem, MACHINE_C64), 'the database is found');
  Check(Game.Base = DDB_BASE_C64, 'at 3880: ' + IntToHex(Game.Base, 4));
  WriteLn('version ', Game.Version, ' language ', Game.Language, ' locations ', Game.NumLocations, ' objects ', Game.NumObjects,
    ' processes ', Game.NumProcesses, ' entries ', Length(Game.Entries), ' condacts ', Length(Game.Condacts));
  Game.BuildMap(@Map);
  Sp.SetDaadMap(@Map);
  Sp.DaadStop := dsNext;
  Stops := 0;
  Good := 0;
  // Step through condacts: every stop must be one of the database's
  for I := 1 to 400 do
  begin
    Ok := Sp.RunFrame;
    if (not Ok) and (Sp.BreakKind = bkDaad) then
    begin
      Inc(Stops);
      if GetEnvironmentVariable('C64V') <> '' then WriteLn('frame ', I, ' stop at ', IntToHex(Sp.DaadFetch, 4), ' ', Game.CondactText(Game.Condacts[Game.CondactAt(Sp.DaadFetch)]));
      if Sp.DaadFetch >= 0 then
        if Game.CondactAt(Sp.DaadFetch) >= 0 then Inc(Good);
      Sp.DaadStop := dsNext;
      Sp.SkipBreakpointOnce;
      if Stops >= 200 then Break;
    end;
    // (a game waiting for the player keeps asking: type something so it goes on)
    if (I = 100) then Sp.C64Hw.TypeText('MIRAR'#13);
    if (I = 200) then Sp.C64Hw.TypeText('INVENTARIO'#13);
    if (I = 300) then Sp.C64Hw.TypeText('NORTE'#13);
  end;
  Check(Stops >= 20, 'the interpreter was followed: stops ' + IntToStr(Stops));
  Check(Good = Stops, 'every stop is on a condact of the database (' + IntToStr(Good) + ' of ' + IntToStr(Stops) + ')');
  Check(Sp.DaadFetchPC >= 0, 'the fetch instruction was learnt: ' + IntToHex(Sp.DaadFetchPC, 4));
  Loc := Sp.PeekRam(C64_DAAD_FLAGS + Game.LocationFlag);
  Check(Loc < Game.NumLocations, 'flag ' + IntToStr(Game.LocationFlag) + ' (the location) holds a location: ' + IntToStr(Loc));
  Game.Free;
  Sp.Free;
  if Failures > 0 then
  begin
    WriteLn(Failures, ' failure(s)');
    Halt(1);
  end;
end.

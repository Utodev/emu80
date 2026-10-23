{ divmmctest: a new SD card with ESXDOS (FAT16 written by FatFS), booted on
  the emulated DivMMC: ESXDOS must list the card with .ls and save a BASIC
  program onto it (SD card writes), which FatFS then reads back. The image
  file must stay as it was until the card is saved.

    divmmctest <roms folder> <esxdos folder> <scratch card file> }
program divmmctest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Models, Spectrum, FatFS, Plus3FS;

var
  Failures: Integer = 0;

procedure Check(Cond: Boolean; const What: string);
begin
  if not Cond then
  begin
    WriteLn('FAIL  ', What);
    Inc(Failures);
  end;
end;

function ScreenText(Spec: TSpectrum): string;
var
  Row, Col, Line, Ch, Addr: Integer;
  Cell: array[0..7] of Byte;
  Match: Boolean;
  Screen: PBank;
  Font: array[0..767] of Byte;
  F: TFileStream;
begin
  Result := '';
  F := TFileStream.Create(Spec.RomDir + DirectorySeparator + '48.rom', fmOpenRead or fmShareDenyWrite);
  try
    F.Position := $3D00;
    F.ReadBuffer(Font, SizeOf(Font));
  finally
    F.Free;
  end;
  if (Spec.Port7FFD and 8) <> 0 then Screen := Spec.RamBank(7) else Screen := Spec.RamBank(5);
  for Row := 0 to 23 do
  begin
    for Col := 0 to 31 do
    begin
      for Line := 0 to 7 do
      begin
        Addr := ((Row and $18) shl 8) or (Line shl 8) or ((Row and 7) shl 5) or Col;
        Cell[Line] := Screen^[Addr];
      end;
      Result := Result + '?';
      for Ch := 0 to 95 do
      begin
        Match := True;
        for Line := 0 to 7 do
          if (Cell[Line] <> Font[Ch * 8 + Line]) and (Cell[Line] <> (Font[Ch * 8 + Line] xor $FF)) then
          begin
            Match := False;
            Break;
          end;
        if Match then
        begin
          Result[Length(Result)] := Chr(32 + Ch);
          Break;
        end;
      end;
    end;
    Result := TrimRight(Result) + LineEnding;
  end;
end;


var
  F: TFileStream;
  V: TFatVolume;
  E: TFatEntries;
  Sp: TSpectrum;
  I: Integer;
  Err, Text: string;
  Data: TBytes;
  Found: Boolean;
  Dir: LongWord;
  Entry: TFatEntry;
  FreeBefore, Free0: Int64;
begin
  F := TFileStream.Create(ParamStr(3), fmCreate);
  try
    FormatCard(F, 32, 'EMU80 TEST');
    V := TFatVolume.Create(F);
    try
      V.MakeDir(0, 'SYS');
      V.MakeDir(0, 'BIN');
      V.MakeDir(0, 'TMP');
      E := V.ListDir(0);
      CopyTree(V, E[0].Cluster, IncludeTrailingPathDelimiter(ParamStr(2)) + 'SYS');
      CopyTree(V, E[1].Cluster, IncludeTrailingPathDelimiter(ParamStr(2)) + 'BIN');
      Check(Length(V.ListDir(E[0].Cluster)) > 5, 'SYS copied onto the card');
      // Folders made inside another one, as the SD card browser imports them
      V.FindDir('GAMES/ARCADE', True, E[2].Cluster);
      Check(V.FindDir('/TMP/GAMES/ARCADE', False) = V.FindDir('ARCADE', False,
        V.FindDir('GAMES', False, E[2].Cluster)), 'folders made inside a folder');
    finally
      V.Free;
    end;
  finally
    F.Free;
  end;

  Sp := TSpectrum.Create(sm48K, ParamStr(1));
  Sp.DivMMC.LoadRom(IncludeTrailingPathDelimiter(ParamStr(2)) + 'ESXMMC.BIN');
  Sp.DivMMC.InsertCard(ParamStr(3));
  Sp.DivMMCOn := True;
  Sp.Reset(True);
  Sp.AutoType(330, []);
  Sp.TypeText('.ls\n', Err);
  for I := 1 to 450 do Sp.RunFrame;
  Text := ScreenText(Sp);
  Check((Pos('SYS', Text) > 0) and (Pos('BIN', Text) > 0) and (Pos('<DIR>', Text) > 0),
    'ESXDOS boots and lists the card with .ls');
  // 10 PRINT 1 / SAVE *"test"
  Sp.TypeText('10P1\nS*"test"\n', Err);
  for I := 1 to 300 do Sp.RunFrame;
  Check(Sp.DivMMC.Card.Modified, 'the card is marked as modified');
  // Not in the file yet
  F := TFileStream.Create(ParamStr(3), fmOpenRead or fmShareDenyNone);
  try
    V := TFatVolume.Create(F);
    try
      E := V.ListDir(0);
      Found := False;
      for I := 0 to High(E) do
        if E[I].ShortName = 'TEST' then Found := True;
      Check(not Found, 'the image file is unchanged before saving');
    finally
      V.Free;
    end;
  finally
    F.Free;
  end;
  Sp.DivMMC.Card.Save;
  Check(not Sp.DivMMC.Card.Modified, 'saved');
  Sp.DivMMC.EjectCard;
  Sp.Free;

  F := TFileStream.Create(ParamStr(3), fmOpenReadWrite);
  try
    V := TFatVolume.Create(F);
    try
      FreeBefore := V.FreeBytes;
      E := V.ListDir(0);
      Found := False;
      for I := 0 to High(E) do
        if E[I].ShortName = 'TEST' then
        begin
          Found := True;
          Data := V.ReadFile(E[I]);
          Check(HasPlus3Header(Data) and (Data[15] = 0) and (Data[16] = 13),
            'the saved program has its +3DOS header');
        end;
      Check(Found, 'ESXDOS saved TEST onto the card');

      // Long names (the Next's card): folders made by their path, a file
      // replaced by its long name, and a folder deleted with what it holds
      Dir := V.FindDir('/Long folder name/Sub folder', True);
      SetLength(Data, 3);
      Data[0] := 1; Data[1] := 2; Data[2] := 3;
      V.PutFileLong(Dir, 'A long file name.bin', Data);
      Data[0] := 9;
      V.PutFileLong(Dir, 'A long file name.bin', Data);
      E := V.ListDir(Dir);
      Check((Length(E) = 1) and (E[0].LongName = 'A long file name.bin') and (V.ReadFile(E[0])[0] = 9),
        'long names: a file replaced by its long name');
      Check(V.FindName(0, 'Long folder name', Entry) and IsDirectory(Entry), 'long names: the folder');
      V.DeleteTree(Entry);
      Check(not V.FindName(0, 'Long folder name', Entry), 'a folder deleted with all it holds');
      Free0 := V.FreeBytes;
      Check(Free0 = FreeBefore, 'its clusters freed');
    finally
      V.Free;
    end;
  finally
    F.Free;
  end;
  if Failures = 0 then WriteLn('DivMMC with ESXDOS: all passed')
  else WriteLn('DivMMC with ESXDOS: ', Failures, ' failed');
  if Failures > 0 then Halt(1);
end.

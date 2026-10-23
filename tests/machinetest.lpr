{ machinetest: headless runner for the Spectrum machine.

    machinetest <model> <frames> <out.ppm> [file.tap|.sna|.z80|.dsk] [keys]

  Runs the given model for a number of frames, optionally loading a file
  first, and writes the final screen as a PPM image. Keys is an optional
  list of "frame:key" presses (e.g. "100:ENTER,150:J"), each held 5 frames;
  "*:key" presses the key whenever "scroll?" is on screen. Keys "auto" loads
  the tape or disk the way the GUI does (LOAD "" or the Loader menu). }
program machinetest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Models, Spectrum, Snapshot, DSK;

type
  TKeyPress = record
    Frame: Integer;      // first frame; -1 = press when "scroll?" is shown
    Row, Mask: Byte;
  end;

const
  KeyNames: array[0..39] of string = (
    'CAPS', 'Z', 'X', 'C', 'V', 'A', 'S', 'D', 'F', 'G',
    'Q', 'W', 'E', 'R', 'T', '1', '2', '3', '4', '5',
    '0', '9', '8', '7', '6', 'P', 'O', 'I', 'U', 'Y',
    'ENTER', 'L', 'K', 'J', 'H', 'SPACE', 'SYM', 'M', 'N', 'B');

procedure WritePPM(Spec: TSpectrum; const FileName: string);
var
  Pixels: array of LongWord;
  S: TFileStream;
  Header: string;
  Row: array of Byte;
  X, Y: Integer;
  P: LongWord;
begin
  SetLength(Pixels, FB_WIDTH * SCREEN_HEIGHT);   // the frame buffer is twice as wide
  Spec.CopyFrameBuffer(@Pixels[0]);
  S := TFileStream.Create(FileName, fmCreate);
  try
    Header := Format('P6'#10'%d %d'#10'255'#10, [SCREEN_WIDTH, SCREEN_HEIGHT]);
    S.WriteBuffer(Header[1], Length(Header));
    SetLength(Row, SCREEN_WIDTH * 3);
    for Y := 0 to SCREEN_HEIGHT - 1 do
    begin
      for X := 0 to SCREEN_WIDTH - 1 do
      begin
        P := Pixels[Y * FB_WIDTH + X * 2];
        Row[X * 3] := (P shr 16) and $FF;
        Row[X * 3 + 1] := (P shr 8) and $FF;
        Row[X * 3 + 2] := P and $FF;
      end;
      S.WriteBuffer(Row[0], Length(Row));
    end;
  finally
    S.Free;
  end;
end;

{ Recognise screen text by matching each cell against the 48K ROM font. }
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

function ParseKeys(const Spec: string): specialize TArray<TKeyPress>;
var
  Parts: TStringList;
  I, K, Colon: Integer;
  Name: string;
begin
  Result := nil;
  Parts := TStringList.Create;
  try
    Parts.CommaText := Spec;
    SetLength(Result, Parts.Count);
    for I := 0 to Parts.Count - 1 do
    begin
      Colon := Pos(':', Parts[I]);
      if Copy(Parts[I], 1, Colon - 1) = '*' then
        Result[I].Frame := -1
      else
        Result[I].Frame := StrToInt(Copy(Parts[I], 1, Colon - 1));
      Name := UpperCase(Copy(Parts[I], Colon + 1, MaxInt));
      Result[I].Row := 0;
      Result[I].Mask := 0;
      for K := 0 to 39 do
        if KeyNames[K] = Name then
        begin
          Result[I].Row := K div 5;
          Result[I].Mask := 1 shl (K mod 5);
        end;
      if Result[I].Mask = 0 then raise Exception.Create('Unknown key ' + Name);
    end;
  finally
    Parts.Free;
  end;
end;

var
  Spec: TSpectrum;
  Model: TSpectrumModel;
  Frames, F, I: Integer;
  Ext, RomDir: string;
  Keys: specialize TArray<TKeyPress>;
  Disk: TDiskImage;
  Started: QWord;
  TextEvery, ScrollUntil: Integer;
  TextLog: TStringList;
begin
  if ParamCount < 3 then
  begin
    WriteLn('Usage: machinetest <48k|128k|plus2|plus2b|plus3> <frames> <out.ppm> [file] [keys]');
    Halt(1);
  end;
  Model := ModelFromName(ParamStr(1), sm48K);
  Frames := StrToInt(ParamStr(2));
  RomDir := ExtractFilePath(ParamStr(0)) + 'roms';
  if not DirectoryExists(RomDir) then RomDir := 'roms';
  Spec := TSpectrum.Create(Model, RomDir);
  Keys := nil;
  if (ParamCount >= 5) and (ParamStr(5) <> 'auto') then Keys := ParseKeys(ParamStr(5));
  if (ParamCount >= 4) and (ParamStr(4) <> '-') then
  begin
    Ext := LowerCase(ExtractFileExt(ParamStr(4)));
    if Ext = '.sna' then LoadSNA(Spec, ParamStr(4))
    else if Ext = '.z80' then LoadZ80(Spec, ParamStr(4))
    else if Ext = '.tap' then Spec.Tape.LoadTAP(ParamStr(4))
    else if Ext = '.dsk' then
    begin
      Disk := TDiskImage.Create;
      Disk.LoadFromFile(ParamStr(4));
      Spec.FDC.InsertDisk(0, Disk);
    end;
  end;
  // EMU80_SLOW=1 loads tapes in real time instead of through the ROM trap
  Spec.FastLoad := GetEnvironmentVariable('EMU80_SLOW') <> '1';
  if (ParamCount >= 5) and (ParamStr(5) = 'auto') then Spec.AutoLoad;
  TextEvery := StrToIntDef(GetEnvironmentVariable('EMU80_TEXT_EVERY'), 0);
  TextLog := TStringList.Create;
  Started := GetTickCount64;
  ScrollUntil := -1;
  for F := 0 to Frames - 1 do
  begin
    if (F mod 10 = 0) and (F > ScrollUntil + 20) and (Pos('scroll?', ScreenText(Spec)) > 0) then
      ScrollUntil := F + 5;
    for I := 0 to 7 do Spec.Keyboard[I] := $FF;
    for I := 0 to High(Keys) do
      if ((Keys[I].Frame < 0) and (F < ScrollUntil)) or
         ((F >= Keys[I].Frame) and (F < Keys[I].Frame + 5)) then
        Spec.Keyboard[Keys[I].Row] := Spec.Keyboard[Keys[I].Row] and not Keys[I].Mask;
    Spec.RunFrame;
    if (TextEvery > 0) and ((F + 1) mod TextEvery = 0) then
      TextLog.Add(Format('--- frame %d', [F + 1]) + LineEnding + ScreenText(Spec));
  end;
  TextLog.Add('--- final' + LineEnding + ScreenText(Spec));
  TextLog.SaveToFile(ChangeFileExt(ParamStr(3), '.txt'));
  TextLog.Free;
  WriteLn(Format('%s: %d frames in %d ms, PC=%.4x, tape block %d/%d', [Spec.Info.Name, Frames,
    GetTickCount64 - Started, Spec.Cpu.PC.W, Spec.Tape.Current, Spec.Tape.Count]));
  WritePPM(Spec, ParamStr(3));
  Spec.Free;
end.

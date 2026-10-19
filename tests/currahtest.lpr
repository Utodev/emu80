{ currahtest: a 48K with the Currah µSpeech. Its ROM must show its message
  when the machine starts, and LET s$="..." must make the SP0256 speak
  (sound well above the silence before it) and then go quiet again.

    currahtest <roms folder> [file.wav to write the speech to] }
program currahtest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Math, Models, Spectrum;

type
  TStereo = packed record
    L, R: SmallInt;
  end;
  PStereoArray = ^TStereoArray;
  TStereoArray = array[0..65535] of TStereo;

var
  Failures: Integer = 0;
  Wave: TMemoryStream;

procedure Check(Cond: Boolean; const What: string);
begin
  if not Cond then
  begin
    WriteLn('FAIL  ', What);
    Inc(Failures);
  end;
end;

{ The screen as text: each cell matched against the ROM font }
function ScreenText(Spec: TSpectrum): string;
var
  Row, Col, Line, Ch, Addr: Integer;
  Cell: array[0..7] of Byte;
  Match: Boolean;
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
  for Row := 0 to 23 do
  begin
    for Col := 0 to 31 do
    begin
      for Line := 0 to 7 do
      begin
        Addr := ((Row and $18) shl 8) or (Line shl 8) or ((Row and 7) shl 5) or Col;
        Cell[Line] := Spec.RamBank(5)^[Addr];
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

{ Run Frames frames; the RMS level of the sound in them }
function RunFrames(Sp: TSpectrum; Frames: Integer): Double;
var
  I, K, N: Integer;
  Sum: Double;
  P: PStereoArray;
begin
  Sum := 0;
  N := 0;
  for I := 1 to Frames do
  begin
    Sp.RunFrame;
    P := Sp.Samples;
    for K := 0 to Sp.SampleCount - 1 do
      Sum := Sum + Sqr(Double(P^[K].L));
    Inc(N, Sp.SampleCount);
    if Wave <> nil then
      for K := 0 to Sp.SampleCount - 1 do Wave.WriteBuffer(P^[K].L, 2);
  end;
  if N = 0 then Result := 0 else Result := Sqrt(Sum / N);
end;

procedure SaveWave(const FileName: string);
var
  F: TFileStream;
  Rate, Size: LongWord;

  procedure W32(V: LongWord); begin F.WriteBuffer(V, 4); end;
  procedure W16(V: Word); begin F.WriteBuffer(V, 2); end;

begin
  Rate := 44100;
  Size := Wave.Size;
  F := TFileStream.Create(FileName, fmCreate);
  try
    F.WriteBuffer(PChar('RIFF')^, 4); W32(36 + Size);
    F.WriteBuffer(PChar('WAVEfmt ')^, 8); W32(16); W16(1); W16(1); W32(Rate); W32(Rate * 2);
    W16(2); W16(16);
    F.WriteBuffer(PChar('data')^, 4); W32(Size);
    Wave.Position := 0;
    F.CopyFrom(Wave, Size);
  finally
    F.Free;
  end;
end;

var
  Sp: TSpectrum;
  Dir, Err, Text: string;
  Quiet, Speech, After: Double;
begin
  Dir := IncludeTrailingPathDelimiter(ParamStr(1));
  if ParamCount >= 2 then Wave := TMemoryStream.Create else Wave := nil;
  Sp := TSpectrum.Create(sm48K, ParamStr(1));
  try
    Sp.Volume := 1;
    Sp.Currah.LoadRoms(Dir + 'currah.rom', Dir + 'sp0256-al2.rom');
    Sp.CurrahOn := True;
    Sp.Reset(True);
    RunFrames(Sp, 150);
    Text := ScreenText(Sp);
    Check(Pos('CURRAH', UpperCase(Text)) > 0, 'the uSpeech ROM shows its message at start-up');
    // Key voices start after the first ENTER; switch them off, then speak
    Sp.TypeText('\n', Err);
    RunFrames(Sp, 60);
    Sp.TypeText('Lkeys=0\n', Err);
    while Sp.AutoTyping do RunFrames(Sp, 1);
    RunFrames(Sp, 100);
    Quiet := RunFrames(Sp, 25);
    Sp.TypeText('Ls$="he(ll)(oo)"\n', Err);
    while Sp.AutoTyping do RunFrames(Sp, 1);
    Speech := RunFrames(Sp, 30);
    RunFrames(Sp, 100);
    After := RunFrames(Sp, 25);
    WriteLn(Format('  level: quiet %.0f, speaking %.0f, after %.0f', [Quiet, Speech, After]));
    Check(Speech > 300, 'LET s$ makes it speak');
    Check(Speech > 10 * Max(Quiet, 1), 'the speech is well above the silence');
    Check(After < Speech / 10, 'it goes quiet afterwards');
    if Failures = 0 then WriteLn('Currah uSpeech: all passed');
    if Wave <> nil then SaveWave(ParamStr(2));
  finally
    Sp.Free;
    Wave.Free;
  end;
  if Failures > 0 then
  begin
    Write(Text);
    Halt(1);
  end;
end.

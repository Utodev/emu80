{ c64run: boots the C64 on the real ROMs and shows its screen as text.
    c64run <roms/c64 folder> [frames] [d64 file] [command] }
program c64run;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Cpu6510, C64, C64Disk, C64Vic;

function ScreenText(M: TC64): string;
var
  Row, Col: Integer;
  C: Byte;
begin
  Result := '';
  for Row := 0 to 24 do
  begin
    for Col := 0 to 39 do
    begin
      C := M.PeekRam($0400 + Row * 40 + Col) and $7F;
      if C < 32 then Result := Result + Chr(C + 64)
      else if C < 64 then Result := Result + Chr(C)
      else Result := Result + '#';
    end;
    Result := TrimRight(Result) + LineEnding;
  end;
end;

procedure DumpPpm(M: TC64; const Name: string);
var
  F: TFileStream;
  I: Integer;
  C: LongWord;
  B: array[0..2] of Byte;
  H: string;
begin
  F := TFileStream.Create(Name, fmCreate);
  H := 'P6'#10 + IntToStr(VIC_WIDTH) + ' ' + IntToStr(VIC_HEIGHT) + #10'255'#10;
  F.WriteBuffer(H[1], Length(H));
  for I := 0 to VIC_WIDTH * VIC_HEIGHT - 1 do
  begin
    C := M.Vic.Frame[I];
    B[0] := (C shr 16) and $FF; B[1] := (C shr 8) and $FF; B[2] := C and $FF;
    F.WriteBuffer(B, 3);
  end;
  F.Free;
end;

var
  M: TC64;
  I, Frames, K: Integer;
  Cmd: string;
  D: TD64Image;
begin
  M := TC64.Create;
  M.LoadRoms(ParamStr(1) + '/Kernal.rom', ParamStr(1) + '/Basic.rom', ParamStr(1) + '/Char.rom', ParamStr(1) + '/VC1541.rom');
  M.Reset(True);
  Frames := 150;
  if ParamCount >= 2 then Frames := StrToInt(ParamStr(2));
  if (ParamCount >= 3) and (LowerCase(ExtractFileExt(ParamStr(3))) = '.tap') then
  begin
    M.InsertTape(ParamStr(3));
    M.AutoLoad(False);
  end
  else if (ParamCount >= 3) and (ParamStr(3) <> '-') then
  begin
    D := TD64Image.Create;
    D.LoadFromFile(ParamStr(3));
    M.InsertDisk(0, D);
  end;
  for I := 1 to Frames do
  begin
    M.RunFrame;
    if (ParamCount >= 4) and (I >= 120) and ((I - 120) mod 400 = 0) then
    begin
      K := (I - 120) div 400 + 1;
      Cmd := ParamStr(4);
      while (K > 1) and (Pos('|', Cmd) > 0) do begin Delete(Cmd, 1, Pos('|', Cmd)); Dec(K); end;
      if K <= 1 then begin if Pos('|', Cmd) > 0 then Cmd := Copy(Cmd, 1, Pos('|', Cmd) - 1); M.TypeText(Cmd + #13); end;
    end;
  end;
  if GetEnvironmentVariable('C64TRACE') <> '' then
  begin
    for K := 1 to 40000 do
    begin
      if K mod 1 = 0 then Write(IntToHex(M.Cpu.PC, 4), ' ');
      M.StepInstruction;
    end;
    WriteLn;
  end;
  Write(ScreenText(M));
  if GetEnvironmentVariable('C64DBG') <> '' then
  begin
    WriteLn('drive PC=', IntToHex(M.Drive[0].Cpu.PC, 4), ' P=', IntToHex(M.Drive[0].Cpu.P, 2), ' on=', M.DriveOn[0], ' rom=', M.Drive[0].RomLoaded);
    WriteLn('via1 IFR=', IntToHex(M.Drive[0].Via1.IFR, 2), ' IER=', IntToHex(M.Drive[0].Via1.IER, 2), ' PCR=', IntToHex(M.Drive[0].Via1.PCR, 2));
    WriteLn('via1 pins B=', IntToHex(M.Drive[0].Via1.PortBPins, 2), ' ddrb=', IntToHex(M.Drive[0].Via1.Peek(2), 2), ' drive.clk=', M.Drive[0].ClkLow, ' drive.data=', M.Drive[0].DataLow);
    WriteLn('ST=', IntToHex(M.PeekRam($90), 2), ' AE/AF=', IntToHex(M.PeekRam($AE) + M.PeekRam($AF) * 256, 4), ' C3/C4=', IntToHex(M.PeekRam($AE) + M.PeekRam($AF) * 256, 4), ' sp=', IntToHex(M.Cpu.SP, 2), ' stack=', IntToHex(M.PeekRam($1FF), 2), IntToHex(M.PeekRam($1FE), 2), IntToHex(M.PeekRam($1FD), 2), IntToHex(M.PeekRam($1FC), 2));
    WriteLn('iec atn=', M.Iec.AtnLow, ' clk=', M.Iec.ClkLow, ' data=', M.Iec.DataLow, ' cia2 pra=', IntToHex(M.Cia2.PRA, 2), ' ddra=', IntToHex(M.Cia2.DDRA, 2));
  end;
  if GetEnvironmentVariable('C64PPM') <> '' then DumpPpm(M, GetEnvironmentVariable('C64PPM'));
  WriteLn('PC=', IntToHex(M.Cpu.PC, 4), ' frames=', M.Frames, ' drive0 track=', M.Drive[0].Track div 2 + 1, ' led=', M.Drive[0].Led,
    ' motor=', M.Drive[0].Motor);
end.

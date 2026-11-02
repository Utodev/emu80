{ c64game: loads a tape or .t64, waits, presses SPACE and the joystick's fire/direction, and dumps the screen.
    c64game <roms/c64 folder> <file> <frames before SPACE> <frames after> <out.ppm> [joybits] }
program c64game;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Cpu6510, C64, C64Vic;

var
  M: TC64;

procedure Dump(const Name: string);
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
  I, Wait, After: Integer;
  Joy: Byte;
  Last, Cur: string;
  LastR, K, JoyPort, Cnt: Integer;
  Hist: array[0..4095] of Integer;
  Seen: TStringList;
begin
  M := TC64.Create;
  M.LoadRoms(ParamStr(1) + '/Kernal.rom', ParamStr(1) + '/Basic.rom', ParamStr(1) + '/Char.rom', ParamStr(1) + '/VC1541.rom');
  M.Reset(True);
  M.InsertTape(ParamStr(2));
  M.AutoLoad(False);
  Wait := StrToInt(ParamStr(3));
  After := StrToInt(ParamStr(4));
  Joy := 0;
  JoyPort := 2;
  if GetEnvironmentVariable('C64PORT') <> '' then JoyPort := StrToInt(GetEnvironmentVariable('C64PORT'));
  if ParamCount >= 6 then Joy := StrToInt(ParamStr(6));
  for I := 1 to Wait do M.RunFrame;
  if GetEnvironmentVariable('C64HIST') <> '' then
  begin
    for K := 0 to 3999 do Hist[K] := 0;
    for I := 1 to 20000 do
    begin
      M.StepInstruction;
      Inc(Hist[M.Cpu.PC shr 4]);
    end;
    for K := 0 to 4095 do
      if Hist[K] > 400 then WriteLn('hist ', IntToHex(K * 16, 4), ' ', Hist[K]);
    WriteLn('I/O: irq vec $0314=', IntToHex(M.PeekRam($314) + M.PeekRam($315) * 256, 4), ' $FFFE ram=', IntToHex(M.PeekRam($FFFE) + M.PeekRam($FFFF) * 256, 4), ' D018=', IntToHex(M.Vic.Peek($18), 2), ' D011=', IntToHex(M.Vic.Peek($11), 2), ' D01A=', IntToHex(M.Vic.Peek($1A), 2), ' CIA1 icr mask?');
    Cur := '';
    for I := 0 to 47 do Cur := Cur + IntToHex(M.PeekRam($10CA + I), 2) + ' ';
    WriteLn('ram 10CA: ', Cur);
    Cur := '';
    for I := 0 to 31 do Cur := Cur + IntToHex(M.PeekRam($3548 + I), 2) + ' ';
    WriteLn('ram 3548: ', Cur);
    WriteLn('D019=', IntToHex(M.Vic.Peek($19), 2), ' D01A=', IntToHex(M.Vic.Peek($1A), 2), ' vicirq=', M.Vic.Irq, ' raster cmp=', M.Vic.RasterCompare, ' DC0D peek=', IntToHex(M.Cia1.Peek($0D), 2), ' DD0D=', IntToHex(M.Cia2.Peek($0D), 2));
    Cur := '';
    for I := 1 to 60 do begin Cur := Cur + IntToHex(M.Cpu.PC, 4) + ':' + IntToHex(M.Peek(M.Cpu.PC), 2) + ' sp' + IntToHex(M.Cpu.SP, 2) + ' a' + IntToHex(M.Cpu.A, 2) + ' f' + IntToHex(M.Cpu.P, 2) + ' | '; M.StepInstruction; end;
    WriteLn('next pcs: ', Cur);
    WriteLn('zp $00-$0F: ', IntToHex(M.PeekRam(0), 2), ' ', IntToHex(M.PeekRam(1), 2), ' DC0D irq=', M.Cia1.Irq, ' CIA2 irq=', M.Cia2.Irq);
  end;
  if GetEnvironmentVariable('C64BP') <> '' then
  begin
    M.SetBreakpoint($DC00, C64_BP_READ);
    M.SetBreakpoint($DC01, C64_BP_READ);
    M.SetBreakpoint($DC0D, C64_BP_READ);
    Seen := TStringList.Create;
    Seen.Sorted := True;
    Seen.Duplicates := dupIgnore;
    Cnt := 0;
    while Cnt < 200 do
    begin
      if M.RunFrame then Inc(Cnt)
      else
      begin
        Seen.Add(IntToHex(M.BreakInstr, 4) + ' reads ' + IntToHex(M.BreakAddr, 4));
        M.SkipBreakpointOnce;
      end;
    end;
    Cur := '';
    for I := 0 to 127 do Cur := Cur + IntToHex(M.PeekRam($0370 + I), 2) + ' ';
    WriteLn('ram 0370: ', Cur);
    Cur := '';
    for I := 0 to 63 do Cur := Cur + IntToHex(M.PeekRam($03D0 + I), 2) + ' ';
    WriteLn('ram 03D0: ', Cur);
    M.SetJoystick(2, $10);
    WriteLn('fire on port2: DDRA=', IntToHex(M.Cia1.DDRA, 2), ' PRA=', IntToHex(M.Cia1.PRA, 2), ' DDRB=', IntToHex(M.Cia1.DDRB, 2), ' PRB=', IntToHex(M.Cia1.PRB, 2), ' DC00 peek=', IntToHex(M.Cia1.Peek(0), 2), ' DC01 peek=', IntToHex(M.Cia1.Peek(1), 2));
    M.SetJoystick(2, 0);
    WriteLn('no fire: DC00 peek=', IntToHex(M.Cia1.Peek(0), 2));
    WriteLn('readers of DC00/DC01/DC0D in 200 frames:');
    for I := 0 to Seen.Count - 1 do WriteLn('  ', Seen[I]);
  end;
  Dump(ParamStr(5) + '.pre.ppm');
  if GetEnvironmentVariable('C64NOSPACE') = '' then
  begin
    M.SetKeyColumn(7, $10);
    for I := 1 to 10 do M.RunFrame;
    M.SetKeyColumn(7, 0);
  end;
  for I := 1 to After do
  begin
    if (I > 100) and (I mod 100 < 50) then K := Joy else K := 0;
    if JoyPort = 3 then begin M.SetJoystick(1, K); M.SetJoystick(2, K); end else M.SetJoystick(JoyPort, K);
    M.RunFrame;
    if GetEnvironmentVariable('C64SPR') <> '' then
    begin
      Cnt := 0;
      for K := 0 to 43 * VIC_WIDTH - 1 do
        if (M.Vic.Frame[K + 8 * VIC_WIDTH] and $FFFFFF) <> 0 then Inc(Cnt);
      if (Cnt > 0) and (Cnt < 20000) then Write('top-pixels frame ', I, ': ', Cnt, '  ');
      if I mod 50 = 0 then
      begin
        Cur := '';
        for K := 0 to 15 do Cur := Cur + IntToHex(M.Vic.Peek(K), 2) + ' ';
        WriteLn; WriteLn('frame ', I, ' joy=', IntToHex(Joy, 2), ' spr ', Cur, ' en=', IntToHex(M.Vic.Peek($15), 2));
      end;
    end;
  end;
  Dump(ParamStr(5));
  WriteLn('PC=', IntToHex(M.Cpu.PC, 4));
  // One frame, instruction by instruction: the VIC-II's registers each time they change
  if GetEnvironmentVariable('C64LOG') <> '' then
  begin
    for K := 1 to 2 do
    begin
    WriteLn('--- frame ', K);
    Last := '';
    LastR := M.Vic.Raster;
    repeat
      M.StepInstruction;
      Cur := '';
      for I := 0 to $2E do
        if ((GetEnvironmentVariable('C64LOGSPR') = '') and (I in [$11, $15, $16, $17, $18, $1A, $1B, $1C, $1D, $20, $21, $22, $23, $24])) or
           ((GetEnvironmentVariable('C64LOGSPR') <> '') and (I in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, $15, $17, $1D])) then Cur := Cur + IntToHex(I, 2) + '=' + IntToHex(M.Vic.Peek(I), 2) + ' ';
      if (GetEnvironmentVariable('C64LOGSPR') <> '') and (M.Vic.Raster > 70) and (M.Vic.Raster < 300) then Continue;
      Cur := Cur + 'bank=' + IntToStr(M.Cia2.PRA and 3) + ' ddra=' + IntToHex(M.Cia2.DDRA, 2) + ' irq=' + IntToHex(M.Vic.Peek($19), 2) + ' msk=' + IntToHex(M.Vic.Peek($1A), 2) + ' P=' + IntToHex(M.Cpu.P, 2) + ' PC=' + IntToHex(M.Cpu.PC, 4);
      if Cur <> Last then
      begin
        WriteLn('r=', M.Vic.Raster, ' c=', M.Vic.Cycle, ' ', Cur, '');
        Last := Cur;
      end;
      if (K = 1) and (M.Vic.Raster >= 74) and (M.Vic.Raster <= 77) then
        WriteLn('  t r=', M.Vic.Raster, ' c=', M.Vic.Cycle, ' PC=', IntToHex(M.Cpu.PC, 4), ' P=', IntToHex(M.Cpu.P, 2), ' irqflags=', IntToHex(M.Vic.Peek($19), 2), ' $D012cmp=', IntToHex(M.Vic.RasterCompare, 3), ' irqline=', M.Vic.Irq);
      if (M.Vic.Raster = 61) and (M.Vic.Cycle < 8) then
        WriteLn('r61 pix row53: ', IntToHex(M.Vic.Frame[53 * VIC_WIDTH + 100], 8), ' ', IntToHex(M.Vic.Frame[53 * VIC_WIDTH + 101], 8), ' ', IntToHex(M.Vic.Frame[53 * VIC_WIDTH + 102], 8), ' bg0=', IntToHex(M.Vic.Peek($21), 2), ' bank=', M.Cia2.PRA and 3, ' reg18=', IntToHex(M.Vic.Peek($18), 2), ' reg11=', IntToHex(M.Vic.Peek($11), 2));
      if M.Vic.Raster < LastR then Break;
      LastR := M.Vic.Raster;
    until False;
    end;
    Cur := '';
    for I := 0 to 15 do Cur := Cur + IntToHex(M.Vic.Peek(I), 2) + ' ';
    WriteLn('sprites x/y: ', Cur);
    for K := 0 to 7 do
    begin
      Cur := '';
      for I := 0 to 39 do Cur := Cur + IntToHex(M.PeekRam($4800 + K * 40 + I), 2);
      WriteLn('scr4800 row', K, ': ', Cur);
      Cur := '';
      for I := 0 to 39 do Cur := Cur + IntToHex(M.PeekRam($0800 + K * 40 + I), 2);
      WriteLn('scr0800 row', K, ': ', Cur);
      Cur := '';
      for I := 0 to 39 do Cur := Cur + IntToHex(M.Vic.ColorRam[K * 40 + I] and 15, 1);
      WriteLn('color row', K, ': ', Cur);
    end;
    Cur := '';
    for I := 0 to 7 do Cur := Cur + IntToHex(M.PeekRam($3860 + I), 2) + ' ';
    WriteLn('glyph L at 3860: ', Cur);
    Cur := '';
    for I := 0 to 7 do Cur := Cur + IntToHex(M.PeekRam($7860 + I), 2) + ' ';
    WriteLn('glyph L at 7860: ', Cur);
    WriteLn('end of log frame row53: ', IntToHex(M.Vic.Frame[53 * VIC_WIDTH + 100], 8));
    for I := 1 to 4 do
    begin
      M.RunFrame;
      WriteLn('RunFrame ', I, ' row53: ', IntToHex(M.Vic.Frame[53 * VIC_WIDTH + 100], 8), ' bank=', M.Cia2.PRA and 3, ' reg18=', IntToHex(M.Vic.Peek($18), 2));
    end;
    Dump(ParamStr(5) + '.log.ppm');
    WriteLn('x msb ', IntToHex(M.Vic.Peek($10), 2), ' color ', IntToHex(M.Vic.Peek($27), 2), ' ', IntToHex(M.Vic.Peek($28), 2), ' ', IntToHex(M.Vic.Peek($29), 2), ' ', IntToHex(M.Vic.Peek($2A), 2));
  end;
end.

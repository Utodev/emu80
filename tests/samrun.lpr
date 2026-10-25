{ samrun: runs a SAM Coupe for N frames and saves the picture (a tool for
  trying the machine, a disk or a tape without the GUI).

    samrun <roms folder> <frames> <out.png> [frames:out.png ...]

  The roms folder has samcoupe.rom (the 32K ROM). Extra arguments take more
  pictures at those frame counts. Environment: SAMRUN_DISK=file inserts a disk
  image; SAMRUN_KEYS="frame:KEY,frame:KEY" presses keys (held for 6 frames);
  SAMRUN_PORTS=1 lists the last port accesses; SAMRUN_AUTO=disk (or tape, with
  SAMRUN_TAPE=file) loads what is inserted the way the GUI does; SAMRUN_SWAP=frame:file puts another disk in drive 1 at that frame; SAMRUN_TYPE=text
  types text once the ROM has started (\n is RETURN); SAMRUN_REC=1 records the MIC
  output onto the tape from the start, and writes it to SAMRUN_SAVETAPE=file.tzx at the end. }
program samrun;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Math, StrUtils, Models, Spectrum, Sam, ScreenCapture, DSK, DiskFormat;

const
  KEY_NAMES: array[0..71] of string = (
    'SHIFT', 'Z', 'X', 'C', 'V', 'F1', 'F2', 'F3', 'A', 'S', 'D', 'F', 'G', 'F4', 'F5', 'F6',
    'Q', 'W', 'E', 'R', 'T', 'F7', 'F8', 'F9', '1', '2', '3', '4', '5', 'ESC', 'TAB', 'CAPS',
    '0', '9', '8', '7', '6', 'MINUS', 'PLUS', 'DELETE', 'P', 'O', 'I', 'U', 'Y', 'EQUALS', 'QUOTE', 'F0',
    'RETURN', 'L', 'K', 'J', 'H', 'SEMICOLON', 'COLON', 'EDIT', 'SPACE', 'SYMBOL', 'M', 'N', 'B', 'COMMA',
    'PERIOD', 'INV', 'CTRL', 'UP', 'DOWN', 'LEFT', 'RIGHT', '', '', '');

var
  Presses: array of record At, Key: Integer; end;
  Sp: TSpectrum;
  Disk: TDiskImage;
  Problem: TDiskProblem;
  Err, Keys, Item: string;
  K, Peak, PeakR: Integer;
  F: array of LongWord;
  Frames, I, P, Done: Integer;
  LastBlock: Integer = -1;
  Shots: array of record At: Integer; Name: string; end;

procedure Shot(const Name: string);
begin
  SetLength(F, FB_WIDTH * SCREEN_HEIGHT);
  Sp.CopyFrameBuffer(@F[0]);
  SavePNG(F, Name, 1, True);
end;

begin
  if ParamCount < 3 then
  begin
    WriteLn('usage: samrun <roms> <frames> <out.png> [frames:out.png ...]');
    Halt(2);
  end;
  Frames := StrToInt(ParamStr(2));
  SetLength(Shots, 1);
  Shots[0].At := Frames;
  Shots[0].Name := ParamStr(3);
  for I := 4 to ParamCount do
  begin
    P := Pos(':', ParamStr(I));
    SetLength(Shots, Length(Shots) + 1);
    Shots[High(Shots)].At := StrToInt(Copy(ParamStr(I), 1, P - 1));
    Shots[High(Shots)].Name := Copy(ParamStr(I), P + 1, MaxInt);
  end;
  Keys := GetEnvironmentVariable('SAMRUN_KEYS');
  while Keys <> '' do
  begin
    P := Pos(',', Keys);
    if P = 0 then P := Length(Keys) + 1;
    Item := Copy(Keys, 1, P - 1);
    Delete(Keys, 1, P);
    SetLength(Presses, Length(Presses) + 1);
    Presses[High(Presses)].At := StrToInt(Copy(Item, 1, Pos(':', Item) - 1));
    Presses[High(Presses)].Key := -1;
    for K := 0 to High(KEY_NAMES) do
      if (KEY_NAMES[K] <> '') and (KEY_NAMES[K] = UpperCase(Copy(Item, Pos(':', Item) + 1, MaxInt))) then
        Presses[High(Presses)].Key := K;
    if Presses[High(Presses)].Key < 0 then
    begin
      WriteLn('unknown key in ', Item);
      Halt(2);
    end;
  end;
  Sp := TSpectrum.Create(smSAM, ParamStr(1));
  try
    if GetEnvironmentVariable('SAMRUN_DISK') <> '' then
    begin
      Disk := LoadDiskImage(GetEnvironmentVariable('SAMRUN_DISK'), Problem, Err);
      if Disk = nil then
      begin
        WriteLn('disk: ', Err);
        Halt(1);
      end;
      WriteLn('disk kind: ', DiskKindName(ClassifyDisk(Disk)));
      Sp.InsertDiskAt(0, Disk);
    end;
    if GetEnvironmentVariable('SAMRUN_TAPE') <> '' then
      Sp.Tape.LoadFile(GetEnvironmentVariable('SAMRUN_TAPE'));
    if GetEnvironmentVariable('SAMRUN_AUTO') = 'disk' then Sp.AutoLoad(True)
    else if GetEnvironmentVariable('SAMRUN_AUTO') = 'tape' then Sp.AutoLoad(False);
    if GetEnvironmentVariable('SAMRUN_REC') <> '' then Sp.Recording := True;
    if GetEnvironmentVariable('SAMRUN_TYPE') <> '' then
    begin
      if GetEnvironmentVariable('SAMRUN_AUTO') = '' then
      begin
        Sp.Reset(True);
        Sp.AutoType(150, []);
        Sp.TypeText('\n~', Err);
      end;
      Sp.TypeText('~' + StringReplace(GetEnvironmentVariable('SAMRUN_TYPE'), '|', #10, [rfReplaceAll]), Err);
      if Err <> '' then WriteLn('type: ', Err);
    end;
    Done := 0;
    Peak := 0;
    PeakR := 0;
    for I := 1 to Frames do
    begin
      if (GetEnvironmentVariable('SAMRUN_SWAP') <> '') and
         (I = StrToIntDef(Copy(GetEnvironmentVariable('SAMRUN_SWAP'), 1, Pos(':', GetEnvironmentVariable('SAMRUN_SWAP')) - 1), -1)) then
      begin
        Disk := LoadDiskImage(Copy(GetEnvironmentVariable('SAMRUN_SWAP'), Pos(':', GetEnvironmentVariable('SAMRUN_SWAP')) + 1, MaxInt), Problem, Err);
        if Disk <> nil then Sp.InsertDiskAt(0, Disk) else WriteLn('swap: ', Err);
      end;
      for P := 0 to High(Presses) do
      begin
        if I = Presses[P].At then
          Sp.SAM.Keys[Presses[P].Key div 8] := Sp.SAM.Keys[Presses[P].Key div 8] or (1 shl (Presses[P].Key mod 8));
        if I = Presses[P].At + 6 then
          Sp.SAM.Keys[Presses[P].Key div 8] := Sp.SAM.Keys[Presses[P].Key div 8] and not (1 shl (Presses[P].Key mod 8));
      end;
      Sp.RunFrame;
      if (GetEnvironmentVariable('SAMRUN_TRACE') <> '') and (Sp.Tape.Count > 0) and (Sp.Tape.Current <> LastBlock) then
      begin
        LastBlock := Sp.Tape.Current;
        WriteLn(Format('frame %d: tape block %d, PC=%.4X', [Done + 1, LastBlock, Sp.Cpu.PC.W]));
      end;
      if I > Frames - 50 then
        for K := 0 to Sp.SampleCount - 1 do
        begin
          if Abs(PSmallInt(Sp.Samples)[K * 2]) > Peak then Peak := Abs(PSmallInt(Sp.Samples)[K * 2]);
          if Abs(PSmallInt(Sp.Samples)[K * 2 + 1]) > PeakR then PeakR := Abs(PSmallInt(Sp.Samples)[K * 2 + 1]);
        end;
      Inc(Done);
      for P := 0 to High(Shots) do
        if Shots[P].At = Done then Shot(Shots[P].Name);
    end;
    if GetEnvironmentVariable('SAMRUN_PORTS') <> '' then
      for I := Min(Sp.PortLogCount, 12) - 1 downto 0 do
        WriteLn(Format('  PC=%.4X %s port %.4X = %.2X', [Sp.PortLog(I).PC, IfThen(Sp.PortLog(I).Write, 'OUT', 'IN '),
          Sp.PortLog(I).Port, Sp.PortLog(I).Value]));
    if GetEnvironmentVariable('SAMRUN_SAVETAPE') <> '' then
    begin
      Sp.Recording := False;
      WriteLn('tape blocks recorded: ', Sp.Tape.Count);
      for K := 0 to Min(Sp.Tape.Count - 1, 11) do
        WriteLn(Format('  block %d: kind %.2X, %d pulses, first %d %d %d, pause %d ms',
          [K, Sp.Tape.Blocks[K].Kind, Length(Sp.Tape.Blocks[K].Pulses),
           Sp.Tape.Blocks[K].Pulses[0], Sp.Tape.Blocks[K].Pulses[1], Sp.Tape.Blocks[K].Pulses[2], Sp.Tape.Blocks[K].PauseMs]));
      if Sp.Tape.Count > 0 then Sp.Tape.SaveTZX(GetEnvironmentVariable('SAMRUN_SAVETAPE'));
    end;
    if GetEnvironmentVariable('SAMRUN_SCAN') <> '' then
      for K := 0 to 31 do
        for I := 0 to $3FFF - 40 do
          if (Sp.RamBank(K)^[I + 2] = 95) and (Sp.RamBank(K)^[I] in [2, 3]) and (Sp.RamBank(K)^[I + 3] > 0) then
            WriteLn(Format('  DDB-like header in page %d at %.4X: %d %d %d objs=%d locs=%d msgs=%d sys=%d procs=%d', [K, I,
              Sp.RamBank(K)^[I], Sp.RamBank(K)^[I + 1], Sp.RamBank(K)^[I + 2], Sp.RamBank(K)^[I + 3], Sp.RamBank(K)^[I + 4],
              Sp.RamBank(K)^[I + 5], Sp.RamBank(K)^[I + 6], Sp.RamBank(K)^[I + 7]]));
    if Sp.Tape.Count > 0 then
      WriteLn(Format('tape: %d blocks, playing=%s, block %d, level=%s', [Sp.Tape.Count, BoolToStr(Sp.Tape.Playing, True),
        Sp.Tape.Current, BoolToStr(Sp.Tape.Level, True)]));
    WriteLn(Format('sound peak (last 50 frames): L=%d R=%d', [Peak, PeakR]));
    WriteLn(Format('ran %d frames; PC=%.4X SP=%.4X LMPR=%.2X HMPR=%.2X VMPR=%.2X IM=%d IFF1=%s', [Done,
      Sp.Cpu.PC.W, Sp.Cpu.SP.W, Sp.SAM.LMPR, Sp.SAM.HMPR, Sp.SAM.VMPR, Sp.Cpu.IM, BoolToStr(Sp.Cpu.IFF1, True)]));
    // SAMRUN_DUMP=addr:len (hex): the bytes the CPU sees there
    if GetEnvironmentVariable('SAMRUN_DUMP') <> '' then
    begin
      Item := GetEnvironmentVariable('SAMRUN_DUMP');
      P := StrToInt('$' + Copy(Item, 1, Pos(':', Item) - 1));
      K := StrToInt('$' + Copy(Item, Pos(':', Item) + 1, 9));
      for I := 0 to K - 1 do
      begin
        if I mod 16 = 0 then Write(Format(LineEnding + '%.4X:', [P + I]));
        Write(Format(' %.2X', [Sp.Peek((P + I) and $FFFF)]));
      end;
      WriteLn;
    end;
  finally
    Sp.Free;
  end;
end.

{ msxfree: tools for the QUANTIKA ROMs (the MSX2's default ROMs, from ../quantika). They compare the free ROMs with the original ones as black
  boxes (the same program on two ROM folders) and list how real software uses the BIOS.

    msxfree screen <roms folder> [frames] [-cart FILE] [-type TEXT]
        boots the MSX2 and prints the text on screen (the VDP's name table) and the mapper state
    msxfree trace <roms folder> <frames> [-cart FILE] [-type TEXT]
        lists the addresses of the BIOS (slot 0, 0000h-7FFFh) that code outside of it enters, with the
        number of times and the first caller: the BIOS entry points a program really uses
    msxfree compare <roms A> <roms B> [frames] [-cart FILE] [-type TEXT]
        boots both folders and prints what is different: the screen text and the system variables
        (F380h-FFFFh). Exit code 1 if they differ.
    msxfree pic <roms folder> <frames> <file.ppm> [-cart FILE] [-type TEXT]
        writes the picture after that many frames
    msxfree picdiff <roms A> <roms B> <frames> [-cart FILE] [-type TEXT]
        prints how many pixels differ (%) between the two pictures after that many frames
  MSXFREE_COMPAT=1 uses the MSX1 slot layout (no expanded slot, no disk);
  MSXFREE_HOLD=shift|ctrl holds that key from power on for 300 frames (MSXFREE_HOLDFRAMES: more); MSXFREE_DRIVEB=0: no drive B connected;
  MSXFREE_CTRLC=frame[:letter][,...] presses CTRL+C (or CTRL+that letter) at those frames;
  MSXFREE_TIMED=1 runs the disk drive at real speed (seek and rotation times; the default is fast disk access);
  -tape FILE puts a .cas or .tsx in and plays it; -disk FILE puts a disk image (.dsk) in drive A: (the folder
  needs a disk ROM, msx/PHILIPSDISK.rom, that suits its main ROM: QUANTIKA_DISK.ROM under that name for QUANTIKA); MSXFREE_KEYS=frame=text[|frame=text...] types more
  text at those frames of the run that types -type
    msxfree exec <roms folder> <file.bin> [frames] [-type TEXT] [-tape FILE.cas]
        boots (700 frames), loads the program at C000h, runs it from there and prints the screen text
        and the registers after that many frames (100); the program ends in a loop (JR $) and may
        leave results in RAM from D000h, printed as 32 bytes a line (256); MSXFREE_SAVEDISK=FILE
        saves the disk of drive A: (-disk) into FILE afterwards (screen and basic too)
    msxfree systrace <roms folder> <frames> <start> <lo> <hi> [-disk FILE] [-type TEXT]
        from the first time PC is <start> on, prints each jump into <lo>..<hi> (hex) from outside it, once;
        MSXFREE_DUMPFILE=FILE saves the 64K the CPU sees at the end
    msxfree calls <roms folder> <frames> <address> [-cart FILE] [-tape FILE] [-type TEXT]
        prints AF, BC, DE, HL and the caller each time the program enters that address (the first 200, or
        MSXFREE_CALLS)
    msxfree basic <roms folder> <text> [frames]
        boots until "Ok" is on the screen, types the text (\n is RETURN, see TSpectrum.TypeText), runs
        that many frames more (300) and prints the screen
    msxfree tapeout <roms folder> <text> [frames]
        as basic, but watches the cassette output (PPI port C bit 5) and prints what was written: one line of
        hex bytes for each block (1200 baud: a 0 is one long cycle, a 1 two short ones; start bit, 8 bits,
        stop bits), so what two ROMs write to the tape can be compared
    msxfree jumps <roms folder>
        prints the BIOS jump table (0000h-0159h: the target of every JP) after boot, to compare the table

  <roms folder> has msx/MSX2.rom, msx/MSX2EXT.rom and optionally msx/PHILIPSDISK.rom (the folder
  tests/build/freeroms, written by tests/run-tests.sh and tests/fbasic-difftests.sh, has the QUANTIKA ROMs under the
  original names). }
program msxfree;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Types, Models, Spectrum, Msx, MsxMachine, MsxVdp, DSK, DiskFormat;

type
  TEntry = record
    Count: Integer;
    Caller: Word;
  end;

var
  CartFile, TypeText, TapeFile, DiskFile: string;
  TheDisk: TDiskImage = nil;            // the disk in drive A: (MSXFREE_SAVEDISK saves it after exec)

function ReadAll(const FileName: string): TBytes;
var
  F: TFileStream;
begin
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, F.Size);
    if F.Size > 0 then F.ReadBuffer(Result[0], F.Size);
  finally
    F.Free;
  end;
end;

{ A machine booted on a ROM folder, with the cartridge (if any) in slot 1 and the text typed once BASIC is up }
function Boot(const Roms: string): TSpectrum;
var
  Data: TBytes;
  Disk: TDiskImage;
  Problem: TDiskProblem;
  Err: string;
begin
  Result := TSpectrum.Create(smMSX2, Roms);
  // MSXFREE_COMPAT=1: the MSX1 slot layout (no expanded slot)
  if GetEnvironmentVariable('MSXFREE_COMPAT') <> '' then
  begin
    Result.MsxCompat := True;
    Result.Reset(True);
  end;
  Result.SetFastDisk(GetEnvironmentVariable('MSXFREE_TIMED') = '');
  if GetEnvironmentVariable('MSXFREE_DRIVEB') = '0' then Result.DriveBOn := False;
  if GetEnvironmentVariable('MSXFREE_HOLD') = 'shift' then Result.MSXHoldKeys(StrToIntDef(GetEnvironmentVariable('MSXFREE_HOLDFRAMES'), 300), [MSXK_SHIFT])
  else if GetEnvironmentVariable('MSXFREE_HOLD') = 'ctrl' then Result.MSXHoldKeys(StrToIntDef(GetEnvironmentVariable('MSXFREE_HOLDFRAMES'), 300), [MSXK_CTRL]);
  if DiskFile <> '' then
  begin
    Disk := LoadDiskImage(DiskFile, Problem, Err);
    if Disk = nil then
    begin
      WriteLn('the disk ', DiskFile, ': ', Err);
      Halt(2);
    end;
    Result.InsertDiskAt(0, Disk);
    TheDisk := Disk;
  end;
  if TapeFile <> '' then
  begin
    Result.Tape.LoadFile(TapeFile);       // .cas or .tsx
    Result.PlayTape;
  end;
  if CartFile <> '' then
  begin
    Data := ReadAll(CartFile);
    Result.MSXHw.InsertCartridge(1, ExtractFileName(CartFile), Data[0], Length(Data), True, mpPlain);
    Result.Reset(True);
    // the frames are counted from the moment the cartridge runs: the BIOSes take different times to boot
    repeat
      Result.StepInstruction;
    until ((Result.MSXHw.Slots.PrimaryReg shr ((Result.Cpu.PC.W shr 14) * 2)) and 3 = 1) or
      (Result.FrameCount > 3000);
  end;
end;

var
  VWatchHits: Integer = 0;
  AWatchHits: Integer = 0;

procedure RunFrames(Sp: TSpectrum; Frames: Integer; ForceType: Boolean);
var
  I, VAddr: Integer;
  F: Int64;
  V: Byte;
  PC: Word;
  Err: string;
  Keys: TStringList;
  CtrlAt: string;
  Ch: Char;
begin
  Keys := nil;
  if GetEnvironmentVariable('MSXFREE_KEYS') <> '' then
  begin
    Keys := TStringList.Create;
    Keys.Delimiter := '|';
    Keys.StrictDelimiter := True;
    Keys.DelimitedText := GetEnvironmentVariable('MSXFREE_KEYS');
  end;
  for I := 1 to Frames do
  begin
    // MSXFREE_AWATCH=1: the PC and the new value each time port A8h (the slot register) changes (60 times at most)
    if (GetEnvironmentVariable('MSXFREE_AWATCH') <> '') and (AWatchHits < 60) and
      (Sp.FrameCount >= StrToIntDef(GetEnvironmentVariable('MSXFREE_FROM'), 0)) then
    begin
      F := Sp.FrameCount;
      while (Sp.FrameCount = F) and (AWatchHits < 60) do
      begin
        V := Sp.MSXHw.Slots.PrimaryReg;
        PC := Sp.Cpu.PC.W;
        Sp.StepInstruction;
        if Sp.MSXHw.Slots.PrimaryReg <> V then
        begin
          Inc(AWatchHits);
          WriteLn(Format('awatch A8 %.2X -> %.2X at PC %.4X (next PC %.4X) frame %d', [V, Sp.MSXHw.Slots.PrimaryReg, PC,
            Sp.Cpu.PC.W, Sp.FrameCount]));
        end;
      end;
    end
    else
    // MSXFREE_VWATCH=address: the PC each time an instruction changes that VRAM byte (20 times at most)
    if (GetEnvironmentVariable('MSXFREE_VWATCH') <> '') and (VWatchHits < 20) and
      (Sp.FrameCount >= StrToIntDef(GetEnvironmentVariable('MSXFREE_FROM'), 0)) then
    begin
      VAddr := StrToInt('$' + GetEnvironmentVariable('MSXFREE_VWATCH'));
      F := Sp.FrameCount;
      while (Sp.FrameCount = F) and (VWatchHits < 20) do
      begin
        V := Sp.MSXHw.Vdp.VramByte(VAddr);
        PC := Sp.Cpu.PC.W;
        Sp.StepInstruction;
        if Sp.MSXHw.Vdp.VramByte(VAddr) <> V then
        begin
          Inc(VWatchHits);
          WriteLn(Format('vwatch %.4X: %.2X -> %.2X at PC %.4X HL=%.4X DE=%.4X BC=%.4X A8=%.2X frame %d stack %.4X %.4X %.4X %.4X',
            [VAddr, V, Sp.MSXHw.Vdp.VramByte(VAddr), PC, Sp.Cpu.HL.W, Sp.Cpu.DE.W, Sp.Cpu.BC.W,
            Sp.MSXHw.Slots.PrimaryReg, Sp.FrameCount, Sp.Peek(Sp.Cpu.SP.W) + 256 * Sp.Peek(Sp.Cpu.SP.W + 1),
            Sp.Peek(Sp.Cpu.SP.W + 2) + 256 * Sp.Peek(Sp.Cpu.SP.W + 3), Sp.Peek(Sp.Cpu.SP.W + 4) + 256 * Sp.Peek(Sp.Cpu.SP.W + 5),
            Sp.Peek(Sp.Cpu.SP.W + 6) + 256 * Sp.Peek(Sp.Cpu.SP.W + 7)]));
        end;
      end;
    end
    else
      Sp.RunFrame;
    if ForceType and (I = 400) and (TypeText <> '') then Sp.TypeText(TypeText, Err);
    // MSXFREE_KEYS=frame=text[|frame=text...]: more text typed at those frames (of the run that types -type)
    if ForceType and (Keys <> nil) and (Keys.IndexOfName(IntToStr(I)) >= 0) then
      Sp.TypeText(Keys.Values[IntToStr(I)], Err);
    // MSXFREE_CTRLC=frame[:letter][,...]: CTRL+C (or CTRL+letter) pressed at those frames
    CtrlAt := ',' + GetEnvironmentVariable('MSXFREE_CTRLC') + ',';
    for Ch in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' do
      if (Pos(',' + IntToStr(I) + ':' + Ch + ',', CtrlAt) > 0)
        or ((Ch = 'C') and (Pos(',' + IntToStr(I) + ',', CtrlAt) > 0)) then
      begin
        Sp.MSXHoldKeys(4, [MSXK_CTRL, MSXK_A + Ord(Ch) - Ord('A')]);
        Sp.MSXHoldKeys(4, []);
      end;
  end;
  Keys.Free;
end;

function ScreenText(V: TMsxVdp): string;
var
  Line: string;
  NT, Row, Col, W, H: Integer;
  C: Byte;
begin
  Result := '';
  if V.DisplayMode = DM_T2 then begin W := 80; NT := (V.Reg(2) and $7C) shl 10; end
  else if V.Mode = 2 then begin W := 40; NT := (V.Reg(2) and $F) shl 10; end
  else begin W := 32; NT := (V.Reg(2) and $F) shl 10; end;
  H := 24;
  for Row := 0 to H - 1 do
  begin
    Line := '';
    for Col := 0 to W - 1 do
    begin
      C := V.VramByte(NT + Row * W + Col);
      if (C >= 32) and (C < 127) then Line := Line + Chr(C) else Line := Line + ' ';
    end;
    Result := Result + Format('%.2d|', [Row + 1]) + TrimRight(Line) + LineEnding;
  end;
end;

procedure DoScreen(const Roms: string; Frames: Integer);
var
  Sp: TSpectrum;
begin
  Sp := Boot(Roms);
  try
    RunFrames(Sp, Frames, True);
    Write(ScreenText(Sp.MSXHw.Vdp));
    WriteLn('mode=', Sp.MSXHw.Vdp.Mode, ' PC=', IntToHex(Sp.Cpu.PC.W, 4), ' A8=', IntToHex(Sp.MSXHw.Slots.PrimaryReg, 2),
      ' disk=', Ord(Sp.MSXHw.HasDisk));
    // MSXFREE_VRAM=file: the 128K of VRAM too
    if GetEnvironmentVariable('MSXFREE_VRAM') <> '' then
      with TFileStream.Create(GetEnvironmentVariable('MSXFREE_VRAM'), fmCreate) do
      try
        for Frames := 0 to $1FFFF do WriteByte(Sp.MSXHw.Vdp.VramByte(Frames));
      finally
        Free;
      end;
    // MSXFREE_REGS=1: the VDP's registers R#0-R#23 too
    if GetEnvironmentVariable('MSXFREE_REGS') <> '' then
    begin
      for Frames := 0 to 23 do Write(IntToHex(Sp.MSXHw.Vdp.Reg(Frames), 2), ' ');
      WriteLn;
    end;
    if (GetEnvironmentVariable('MSXFREE_SAVEDISK') <> '') and (TheDisk <> nil) then
      SaveRawDisk(TheDisk, GetEnvironmentVariable('MSXFREE_SAVEDISK'));
  finally
    Sp.Free;
  end;
end;

procedure DoTrace(const Roms: string; Frames: Integer);
var
  Sp: TSpectrum;
  Counts: array[0..$FFFF] of TEntry;
  I: Integer;
  Frame: Int64;
  PC, Prev: Word;
  PrevIn, NowIn: Boolean;
  Watched: string;
  Err, Keys: string;
  Spent: array[0..$FFFF] of Int64;
  Entry: Word;

  function InBios(Addr: Word): Boolean;
  begin
    Result := Pos(Watched, Sp.MSXHw.Slots.Describe(Addr)) > 0;
  end;

  function IsReturn(Addr: Word): Boolean;
  var
    Op: Byte;
  begin
    Op := Sp.Peek(Addr);
    Result := (Op = $C9) or (Op and $C7 = $C0) or ((Op = $ED) and (Sp.Peek(Addr + 1) in [$45, $4D]));
  end;

begin
  // MSXFREE_TRACEROM: the device watched ("BIOS" by default; "Sub-ROM" for the sub-ROM)
  Watched := GetEnvironmentVariable('MSXFREE_TRACEROM');
  if Watched = '' then Watched := 'BIOS';
  FillChar(Counts, SizeOf(Counts), 0);
  FillChar(Spent, SizeOf(Spent), 0);
  Entry := 0;
  Sp := Boot(Roms);
  try
    PrevIn := True;
    Prev := 0;
    Frame := 0;
    repeat
      Sp.StepInstruction;
      PC := Sp.Cpu.PC.W;
      NowIn := InBios(PC);
      // a RET back into the BIOS (from a hook or from the RAM primitives) is not an entry
      // (MSXFREE_FROM=frame: only from that frame on)
      if NowIn and not PrevIn and not IsReturn(Prev) and
        (Sp.FrameCount >= StrToIntDef(GetEnvironmentVariable('MSXFREE_FROM'), 0)) then
      begin
        Inc(Counts[PC].Count);
        if Counts[PC].Count = 1 then Counts[PC].Caller := Prev;
      end;
      // MSXFREE_PROFILE=1: instructions run inside the ROM, by the entry they came in through
      if NowIn and (GetEnvironmentVariable('MSXFREE_PROFILE') <> '') and
        (Sp.FrameCount >= StrToIntDef(GetEnvironmentVariable('MSXFREE_FROM'), 0)) then
      begin
        if not PrevIn then Entry := PC;
        Inc(Spent[Entry]);
      end;
      Prev := PC;
      PrevIn := NowIn;
      if Sp.FrameCount <> Frame then
      begin
        Frame := Sp.FrameCount;
        if (Frame = 400) and (TypeText <> '') then Sp.TypeText(TypeText, Err);
        // MSXFREE_KEYS as the other commands
        if Pos('|' + IntToStr(Frame) + '=', '|' + GetEnvironmentVariable('MSXFREE_KEYS')) > 0 then
        begin
          Keys := '|' + GetEnvironmentVariable('MSXFREE_KEYS') + '|';
          Keys := Copy(Keys, Pos('|' + IntToStr(Frame) + '=', Keys) + Length(IntToStr(Frame)) + 2, MaxInt);
          Sp.TypeText(Copy(Keys, 1, Pos('|', Keys) - 1), Err);
        end;
      end;
    until Frame >= Frames;
    for I := 0 to $FFFF do
      if (Counts[I].Count = 0) and (Spent[I] > 0) then
        WriteLn(IntToHex(I, 4), ' (a return into the ROM) instructions ', Spent[I]);
    for I := 0 to $FFFF do
      if Counts[I].Count > 0 then
        WriteLn(IntToHex(I, 4), ' x', Counts[I].Count, ' first from ', IntToHex(Counts[I].Caller, 4),
          ' instructions ', Spent[I]);
  finally
    Sp.Free;
  end;
end;

function SysVars(Sp: TSpectrum): TBytes;
var
  I: Integer;
begin
  SetLength(Result, $10000 - $F380);
  for I := $F380 to $FFFF do Result[I - $F380] := Sp.Peek(I);
end;

function DoCompare(const A, B: string; Frames: Integer): Integer;
var
  SA, SB: TSpectrum;
  TA, TB: string;
  VA, VB: TBytes;
  I, N: Integer;
begin
  Result := 0;
  SA := Boot(A);
  SB := Boot(B);
  try
    RunFrames(SA, Frames, True);
    RunFrames(SB, Frames, True);
    TA := ScreenText(SA.MSXHw.Vdp);
    TB := ScreenText(SB.MSXHw.Vdp);
    if TA <> TB then
    begin
      WriteLn('SCREEN differs. A:'); Write(TA); WriteLn('B:'); Write(TB);
      Result := 1;
    end
    else WriteLn('screen text: same');
    VA := SysVars(SA);
    VB := SysVars(SB);
    N := 0;
    for I := 0 to High(VA) do
      if VA[I] <> VB[I] then
      begin
        Inc(N);
        if N <= 80 then WriteLn(Format('%.4X: A=%.2X B=%.2X', [I + $F380, VA[I], VB[I]]));
      end;
    WriteLn(N, ' system variable bytes differ');
    if N > 0 then Result := 1;
  finally
    SA.Free;
    SB.Free;
  end;
end;

function Picture(const Roms: string; Frames: Integer): TLongWordDynArray;
var
  Sp: TSpectrum;
begin
  Sp := Boot(Roms);
  try
    RunFrames(Sp, Frames, True);
    SetLength(Result, FB_WIDTH * SCREEN_HEIGHT);
    Sp.CopyFrameBuffer(@Result[0]);
  finally
    Sp.Free;
  end;
end;

{ A picture as a PPM file (every second pixel of the frame buffer's width) }
procedure WritePpm(const P: TLongWordDynArray; const FileName: string);
var
  F: TFileStream;
  Hdr: string;
  Row: array of Byte;
  X, Y: Integer;
begin
  F := TFileStream.Create(FileName, fmCreate);
  try
    Hdr := Format('P6'#10'%d %d'#10'255'#10, [FB_WIDTH div 2, SCREEN_HEIGHT]);
    F.WriteBuffer(Hdr[1], Length(Hdr));
    SetLength(Row, FB_WIDTH div 2 * 3);
    for Y := 0 to SCREEN_HEIGHT - 1 do
    begin
      for X := 0 to FB_WIDTH div 2 - 1 do
      begin
        Row[X * 3] := (P[Y * FB_WIDTH + X * 2] shr 16) and $FF;
        Row[X * 3 + 1] := (P[Y * FB_WIDTH + X * 2] shr 8) and $FF;
        Row[X * 3 + 2] := P[Y * FB_WIDTH + X * 2] and $FF;
      end;
      F.WriteBuffer(Row[0], Length(Row));
    end;
  finally
    F.Free;
  end;
end;

procedure DoPic(const Roms: string; Frames: Integer; const FileName: string);
begin
  WritePpm(Picture(Roms, Frames), FileName);
end;

procedure DoPicDiff(const A, B: string; Frames: Integer);
var
  PA, PB: TLongWordDynArray;
  I, N: Integer;
begin
  PA := Picture(A, Frames);
  PB := Picture(B, Frames);
  N := 0;
  for I := 0 to High(PA) do if PA[I] <> PB[I] then Inc(N);
  WriteLn(Format('%.1f%% of the pixels differ', [N * 100.0 / Length(PA)]));
end;

{ MSXFREE_PSGLOG: every write to the PSG while the program runs (frame, register, value) }
type
  TPsgLogger = class
    Sp: TSpectrum;
    Lines: TStringList;
    procedure Log(T: Integer; Reg, Value: Byte);
  end;

procedure TPsgLogger.Log(T: Integer; Reg, Value: Byte);
begin
  Lines.Add(Format('psg %d R%d=%.2X', [Sp.FrameCount, Reg, Value]));
end;

procedure DoExec(const Roms, FileName: string; Frames: Integer);
var
  Err: string;
  Sp: TSpectrum;
  Data: TBytes;
  I: Integer;
  Pic: TLongWordDynArray;
  Logger: TPsgLogger;
begin
  Logger := nil;
  Sp := Boot(Roms);
  try
    RunFrames(Sp, 700, False);
    Data := ReadAll(FileName);
    for I := 0 to High(Data) do Sp.MSXHw.Write($C000 + I, Data[I]);
    if GetEnvironmentVariable('MSXFREE_PSGLOG') <> '' then
    begin
      Logger := TPsgLogger.Create;
      Logger.Sp := Sp;
      Logger.Lines := TStringList.Create;
      Sp.MSXHw.OnPsg := @Logger.Log;
    end;
    Sp.Cpu.PC.W := $C000;
    Sp.Cpu.Halted := False;
    // MSXFREE_TRACE=n prints the PC of the first n instructions
    for I := 1 to StrToIntDef(GetEnvironmentVariable('MSXFREE_TRACE'), 0) do
    begin
      Write(IntToHex(Sp.Cpu.PC.W, 4), ' ');
      Sp.StepInstruction;
    end;
    if TypeText <> '' then
    begin
      RunFrames(Sp, 5, False);
      Sp.TypeText(StringReplace(TypeText, '\n', #13, [rfReplaceAll]), Err);
    end;
    RunFrames(Sp, Frames, False);
    if GetEnvironmentVariable('MSXFREE_PIC') <> '' then     // MSXFREE_PIC=file.ppm: the picture at the end
    begin
      SetLength(Pic, FB_WIDTH * SCREEN_HEIGHT);
      Sp.CopyFrameBuffer(@Pic[0]);
      WritePpm(Pic, GetEnvironmentVariable('MSXFREE_PIC'));
    end;
    if GetEnvironmentVariable('MSXFREE_VRAM') <> '' then    // MSXFREE_VRAM=file: the 128K of VRAM at the end
    begin
      SetLength(Data, $20000);
      for I := 0 to $1FFFF do Data[I] := Sp.MSXHw.Vdp.VramByte(I);
      with TFileStream.Create(GetEnvironmentVariable('MSXFREE_VRAM'), fmCreate) do
      try
        WriteBuffer(Data[0], Length(Data));
      finally
        Free;
      end;
    end;
    if Logger <> nil then Write(Logger.Lines.Text);
    Write(ScreenText(Sp.MSXHw.Vdp));
    WriteLn('mode=', Sp.MSXHw.Vdp.Mode, ' dm=', Sp.MSXHw.Vdp.DisplayMode, ' PC=', IntToHex(Sp.Cpu.PC.W, 4));
    for I := 0 to 255 do
    begin
      if I mod 32 = 0 then Write(IntToHex($D000 + I, 4), ':');
      Write(' ', IntToHex(Sp.Peek($D000 + I), 2));
      if I mod 32 = 31 then WriteLn;
    end;
    if (GetEnvironmentVariable('MSXFREE_SAVEDISK') <> '') and (TheDisk <> nil) then
      SaveRawDisk(TheDisk, GetEnvironmentVariable('MSXFREE_SAVEDISK'));
  finally
    Sp.Free;
  end;
end;

// DoSysTrace: from the first time the program reaches Start on, the jumps (a PC that is not the one after the
// last) into Lo..Hi from outside it: each place jumped to, where from, how many times; the primary slots
// (A8h) at the first time. Used to see what a program on a disk asks of the disk system.
procedure DoSysTrace(const Roms: string; Frames: Integer; Start, Lo, Hi: Word);
var
  Sp: TSpectrum;
  Prev, PC: Word;
  On: Boolean;
  Seen: TStringList;
  Key: string;
  I: Integer;
begin
  Sp := Boot(Roms);
  Seen := TStringList.Create;
  try
    Prev := 0;
    On := False;
    while Sp.FrameCount < Frames do
    begin
      PC := Sp.Cpu.PC.W;
      if not On and (PC = Start) then On := True;
      if On and (PC >= Lo) and (PC <= Hi) and ((Prev < Lo) or (Prev > Hi)) then
      begin
        Key := IntToHex(PC, 4) + ' from ' + IntToHex(Prev, 4) + ' p1 ' + Sp.MSXHw.Slots.Describe($4000);
        I := Seen.IndexOf(Key);
        if I < 0 then Seen.AddObject(Key, TObject(PtrInt(Sp.FrameCount)));
      end;
      Prev := PC;
      Sp.StepInstruction;
    end;
    for I := 0 to Seen.Count - 1 do WriteLn(Seen[I], ' frame ', PtrInt(Seen.Objects[I]));
    // MSXFREE_DUMPFILE=file: the 64K the CPU sees at the end, into that file
    if GetEnvironmentVariable('MSXFREE_DUMPFILE') <> '' then
      with TFileStream.Create(GetEnvironmentVariable('MSXFREE_DUMPFILE'), fmCreate) do
      try
        for I := 0 to $FFFF do WriteByte(Sp.Peek(I));
      finally
        Free;
      end;
  finally
    Seen.Free;
    Sp.Free;
  end;
end;

procedure DoCalls(const Roms: string; Frames: Integer; Addr: Word);
var
  Sp: TSpectrum;
  N, I: Integer;
  Prev: Word;
  Max: Integer;
  Typed: Boolean;
  Err, Keys: string;
  LastFrame: Int64;
begin
  LastFrame := -1;
  Max := StrToIntDef(GetEnvironmentVariable('MSXFREE_CALLS'), 200);
  Sp := Boot(Roms);
  try
    N := 0;
    Prev := 0;
    Typed := False;
    while (Sp.FrameCount < Frames) and (N < Max) do
    begin
      // -type is typed at frame 400, as the other commands do
      if not Typed and (Sp.FrameCount >= 400) then
      begin
        Typed := True;
        if TypeText <> '' then Sp.TypeText(TypeText, Err);
      end;
      // MSXFREE_KEYS as the other commands
      if Sp.FrameCount <> LastFrame then
      begin
        LastFrame := Sp.FrameCount;
        Keys := '|' + GetEnvironmentVariable('MSXFREE_KEYS') + '|';
        if Pos('|' + IntToStr(LastFrame) + '=', Keys) > 0 then
        begin
          Keys := Copy(Keys, Pos('|' + IntToStr(LastFrame) + '=', Keys) + Length(IntToStr(LastFrame)) + 2, MaxInt);
          Sp.TypeText(Copy(Keys, 1, Pos('|', Keys) - 1), Err);
        end;
      end;
      // MSXFREE_FROM=frame: only the calls from that frame on
      if (Sp.Cpu.PC.W = Addr) and (Prev <> Addr) and (Sp.FrameCount >= StrToIntDef(GetEnvironmentVariable('MSXFREE_FROM'), 0)) then
      begin
        Inc(N);
        // MSXFREE_DUMPFILE=file: the 64K the CPU sees at each call, into that file (the last call's stays)
      if GetEnvironmentVariable('MSXFREE_DUMPFILE') <> '' then
        with TFileStream.Create(GetEnvironmentVariable('MSXFREE_DUMPFILE'), fmCreate) do
        try
          for I := 0 to $FFFF do WriteByte(Sp.Peek(I));
        finally
          Free;
        end;
      // MSXFREE_SLOTS=1: and what the four pages show
      if GetEnvironmentVariable('MSXFREE_SLOTS') <> '' then
        WriteLn('pages: ', Sp.MSXHw.Slots.Describe($0000), ' | ', Sp.MSXHw.Slots.Describe($4000), ' | ',
          Sp.MSXHw.Slots.Describe($8000), ' | ', Sp.MSXHw.Slots.Describe($C000));
      WriteLn(Format('AF=%.4X BC=%.4X DE=%.4X HL=%.4X from %.4X SP=%.4X (stack %.4X %.4X %.4X %.4X) frame %d',
          [Sp.Cpu.GetAF, Sp.Cpu.BC.W, Sp.Cpu.DE.W, Sp.Cpu.HL.W, Prev, Sp.Cpu.SP.W,
          Sp.Peek(Sp.Cpu.SP.W) + 256 * Sp.Peek(Sp.Cpu.SP.W + 1), Sp.Peek(Sp.Cpu.SP.W + 2) + 256 * Sp.Peek(Sp.Cpu.SP.W + 3),
          Sp.Peek(Sp.Cpu.SP.W + 4) + 256 * Sp.Peek(Sp.Cpu.SP.W + 5), Sp.Peek(Sp.Cpu.SP.W + 6) + 256 * Sp.Peek(Sp.Cpu.SP.W + 7),
          Sp.FrameCount]));
      end;
      Prev := Sp.Cpu.PC.W;
      Sp.StepInstruction;
    end;
  finally
    Sp.Free;
  end;
end;

{ The blocks written to the tape: the lengths of the halves of the signal decoded into bytes }
procedure DoTapeOut(const Roms, Text: string; Frames: Integer);
const
  GAP = 20000;            // T-states without an edge: the end of a block
  LONGHALF = 1100;        // longer: a half of a 1200 Hz cycle
var
  Sp: TSpectrum;
  I, B, K: Integer;
  Err, Line: string;
  Level, Now_: Boolean;
  LastT, T: Int64;
  Halves: array of Integer;

  procedure FlushBlock;
  var
    P, Bit: Integer;
    V: Integer;
  begin
    P := 0;
    Line := '';
    if GetEnvironmentVariable('MSXFREE_HALVES') <> '' then      // the lengths themselves (to look at)
    begin
      for Bit := 0 to Length(Halves) - 1 do Write(Halves[Bit], ' ');
      WriteLn;
    end;
    while (P < Length(Halves)) and (Halves[P] < LONGHALF) do Inc(P);   // the header
    while P + 1 < Length(Halves) do
    begin
      Inc(P, 2);                                                       // the start bit
      V := 0;
      for Bit := 0 to 7 do
      begin
        if P >= Length(Halves) then Break;
        if Halves[P] >= LONGHALF then Inc(P, 2)
        else begin V := V or (1 shl Bit); Inc(P, 4); end;
      end;
      Line := Line + IntToHex(V, 2) + ' ';
      while (P < Length(Halves)) and (Halves[P] < LONGHALF) do Inc(P); // the stop bits
    end;
    if Line <> '' then WriteLn(TrimRight(Line));
    SetLength(Halves, 0);
  end;

begin
  Sp := Boot(Roms);
  try
    I := 0;
    repeat
      RunFrames(Sp, 10, False);
      Inc(I, 10);
    until (Pos('Ok', ScreenText(Sp.MSXHw.Vdp)) > 0) or (I > 3000);
    RunFrames(Sp, 20, False);
    Sp.TypeText(StringReplace(Text, '\n', #13, [rfReplaceAll]), Err);
    if Err <> '' then WriteLn('type: ', Err);
    Level := (Sp.MSXHw.PortValue(2) and $20) <> 0;
    LastT := (Int64(Sp.FrameCount) * Sp.Info.FrameT + Sp.Cpu.T);
    SetLength(Halves, 0);
    B := Sp.FrameCount + Frames + Length(Text) * 8;
    while Sp.FrameCount < B do
    begin
      Sp.StepInstruction;
      Now_ := (Sp.MSXHw.PortValue(2) and $20) <> 0;
      if Now_ <> Level then
      begin
        T := (Int64(Sp.FrameCount) * Sp.Info.FrameT + Sp.Cpu.T);
        if T - LastT > GAP then FlushBlock
        else
        begin
          K := Length(Halves);
          SetLength(Halves, K + 1);
          Halves[K] := T - LastT;
        end;
        LastT := T;
        Level := Now_;
      end;
    end;
    FlushBlock;
  finally
    Sp.Free;
  end;
end;

procedure DoBasic(const Roms, Text: string; Frames: Integer);
var
  Sp: TSpectrum;
  I, Hits: Integer;
  PrevPC: Word;
  Err, Brks: string;
begin
  Sp := Boot(Roms);
  try
    I := 0;
    repeat
      RunFrames(Sp, 10, False);
      Inc(I, 10);
    until (Pos('Ok', ScreenText(Sp.MSXHw.Vdp)) > 0) or (I > 3000);
    RunFrames(Sp, 20, False);
    Sp.TypeText(StringReplace(Text, '\n', #13, [rfReplaceAll]), Err);
    if Err <> '' then WriteLn('type: ', Err);
    // MSXFREE_BREAK=address[,address...]: the registers each time the PC gets there (40 times at most, or MSXFREE_HITS)
    if GetEnvironmentVariable('MSXFREE_BREAK') <> '' then
    begin
      Brks := ',' + UpperCase(GetEnvironmentVariable('MSXFREE_BREAK')) + ',';
      Hits := 0;
      while (Sp.FrameCount < Frames + Length(Text) * 8 + 2000) and (Hits < StrToIntDef(GetEnvironmentVariable('MSXFREE_HITS'), 40)) do
      begin
        if Pos(',' + IntToHex(Sp.Cpu.PC.W, 4) + ',', Brks) > 0 then
        begin
          Inc(Hits);
          WriteLn(Format('break %.4X AF=%.4X BC=%.4X DE=%.4X HL=%.4X SP=%.4X (HL)=%.2X %.2X %.2X stack %.4X %.4X %.4X prev %.4X frame %d', [Sp.Cpu.PC.W, Sp.Cpu.GetAF,
            Sp.Cpu.BC.W, Sp.Cpu.DE.W, Sp.Cpu.HL.W, Sp.Cpu.SP.W, Sp.Peek(Sp.Cpu.HL.W), Sp.Peek(Sp.Cpu.HL.W + 1),
            Sp.Peek(Sp.Cpu.HL.W + 2), Sp.Peek(Sp.Cpu.SP.W) + 256 * Sp.Peek(Sp.Cpu.SP.W + 1),
            Sp.Peek(Sp.Cpu.SP.W + 2) + 256 * Sp.Peek(Sp.Cpu.SP.W + 3),
            Sp.Peek(Sp.Cpu.SP.W + 4) + 256 * Sp.Peek(Sp.Cpu.SP.W + 5), PrevPC, Sp.FrameCount]));
          if GetEnvironmentVariable('MSXFREE_BREAKIX') <> '' then
            WriteLn(Format('  IX=%.4X IY=%.4X BC2=%.4X DE2=%.4X HL2=%.4X', [Sp.Cpu.IX.W, Sp.Cpu.IY.W,
              Sp.Cpu.BC_.W, Sp.Cpu.DE_.W, Sp.Cpu.HL_.W]));
          // MSXFREE_BREAKTEXT=n: n bytes at HL
          if GetEnvironmentVariable('MSXFREE_BREAKTEXT') <> '' then
          begin
            Write('  text:');
            for I := 0 to StrToInt(GetEnvironmentVariable('MSXFREE_BREAKTEXT')) - 1 do
              Write(' ', IntToHex(Sp.Peek(Sp.Cpu.HL.W + I), 2));
            WriteLn;
          end;
          // MSXFREE_BREAKSTACK=n: n more stack bytes after the 6 shown
          if GetEnvironmentVariable('MSXFREE_BREAKSTACK') <> '' then
          begin
            Write('  stack+6:');
            for I := 6 to 5 + StrToInt(GetEnvironmentVariable('MSXFREE_BREAKSTACK')) do
              Write(' ', IntToHex(Sp.Peek(Sp.Cpu.SP.W + I), 2));
            WriteLn;
          end;
        end;
        PrevPC := Sp.Cpu.PC.W;
        Sp.StepInstruction;
      end;
    end;
    // MSXFREE_STOP=1: stop at the last break (MSXFREE_HITS), for MSXFREE_VRAM / MSXFREE_DUMP of that moment
    if GetEnvironmentVariable('MSXFREE_STOP') = '' then
      RunFrames(Sp, Frames + Length(Text) * 8, False);
    if (GetEnvironmentVariable('MSXFREE_SAVEDISK') <> '') and (TheDisk <> nil) then
      SaveRawDisk(TheDisk, GetEnvironmentVariable('MSXFREE_SAVEDISK'));
    if GetEnvironmentVariable('MSXFREE_VRAM') <> '' then
      with TFileStream.Create(GetEnvironmentVariable('MSXFREE_VRAM'), fmCreate) do
      try
        for I := 0 to $1FFFF do WriteByte(Sp.MSXHw.Vdp.VramByte(I));
      finally
        Free;
      end;
    Write(ScreenText(Sp.MSXHw.Vdp));
    // MSXFREE_DUMP=address: 256 bytes of memory from there
    if GetEnvironmentVariable('MSXFREE_DUMP') <> '' then
    begin
      Frames := StrToInt('$' + GetEnvironmentVariable('MSXFREE_DUMP'));
      for I := 0 to 255 do
      begin
        if I mod 16 = 0 then Write(IntToHex(Frames + I, 4), ':');
        Write(' ', IntToHex(Sp.Peek(Frames + I), 2));
        if I mod 16 = 15 then WriteLn;
      end;
    end;
  finally
    Sp.Free;
  end;
end;

procedure DoJumps(const Roms: string);
var
  Sp: TSpectrum;
  A: Integer;
begin
  Sp := Boot(Roms);
  try
    RunFrames(Sp, 5, False);
    A := 0;
    while A < $15C + 3 * 11 do
    begin
      if Sp.Peek(A) = $C3 then
        WriteLn(IntToHex(A, 4), ' JP ', IntToHex(Sp.Peek(A + 1) + 256 * Sp.Peek(A + 2), 4));
      Inc(A, 3);
    end;
    WriteLn('002B=', IntToHex(Sp.Peek($2B), 2), ' 002C=', IntToHex(Sp.Peek($2C), 2), ' 002D=', IntToHex(Sp.Peek($2D), 2),
      ' 002E=', IntToHex(Sp.Peek($2E), 2));
  finally
    Sp.Free;
  end;
end;

var
  Cmd: string;
  I, Frames, Code: Integer;
  Pos0: array of string;
begin
  UseOriginalMsxRoms;                   // (the emulator's default is the free ROMs)
  CartFile := '';
  TypeText := '';
  TapeFile := '';
  DiskFile := '';
  SetLength(Pos0, 0);
  I := 1;
  while I <= ParamCount do
  begin
    if (ParamStr(I) = '-cart') and (I < ParamCount) then begin CartFile := ParamStr(I + 1); Inc(I); end
    else if (ParamStr(I) = '-type') and (I < ParamCount) then begin TypeText := ParamStr(I + 1); Inc(I); end
    else if (ParamStr(I) = '-tape') and (I < ParamCount) then begin TapeFile := ParamStr(I + 1); Inc(I); end
    else if (ParamStr(I) = '-disk') and (I < ParamCount) then begin DiskFile := ParamStr(I + 1); Inc(I); end
    else
    begin
      SetLength(Pos0, Length(Pos0) + 1);
      Pos0[High(Pos0)] := ParamStr(I);
    end;
    Inc(I);
  end;
  if Length(Pos0) < 2 then
  begin
    WriteLn('usage: msxfree screen|trace|compare|jumps <roms folder> ... (see the top of tests/msxfree.lpr)');
    Halt(2);
  end;
  Cmd := Pos0[0];
  Code := 0;
  if Cmd = 'screen' then
  begin
    if Length(Pos0) > 2 then Frames := StrToInt(Pos0[2]) else Frames := 600;
    DoScreen(Pos0[1], Frames);
  end
  else if Cmd = 'trace' then DoTrace(Pos0[1], StrToInt(Pos0[2]))
  else if Cmd = 'compare' then
  begin
    if Length(Pos0) > 3 then Frames := StrToInt(Pos0[3]) else Frames := 600;
    Code := DoCompare(Pos0[1], Pos0[2], Frames);
  end
  else if Cmd = 'jumps' then DoJumps(Pos0[1])
  else if Cmd = 'basic' then
  begin
    if Length(Pos0) > 3 then Frames := StrToInt(Pos0[3]) else Frames := 300;
    DoBasic(Pos0[1], Pos0[2], Frames);
  end
  else if Cmd = 'tapeout' then
  begin
    if Length(Pos0) > 3 then Frames := StrToInt(Pos0[3]) else Frames := 3000;
    DoTapeOut(Pos0[1], Pos0[2], Frames);
  end
  else if Cmd = 'systrace' then DoSysTrace(Pos0[1], StrToInt(Pos0[2]), StrToInt('$' + Pos0[3]), StrToInt('$' + Pos0[4]), StrToInt('$' + Pos0[5]))
  else if Cmd = 'calls' then DoCalls(Pos0[1], StrToInt(Pos0[2]), StrToInt('$' + Pos0[3]))
  else if Cmd = 'exec' then
  begin
    if Length(Pos0) > 3 then Frames := StrToInt(Pos0[3]) else Frames := 100;
    DoExec(Pos0[1], Pos0[2], Frames);
  end
  else if Cmd = 'pic' then DoPic(Pos0[1], StrToInt(Pos0[2]), Pos0[3])
  else if Cmd = 'picdiff' then DoPicDiff(Pos0[1], Pos0[2], StrToInt(Pos0[3]))
  else
  begin
    WriteLn('unknown command ', Cmd);
    Halt(2);
  end;
  Halt(Code);
end.

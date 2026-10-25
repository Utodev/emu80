{ samtest: the SAM Coupe. Its ASIC (paging, the four screen modes, the CLUT,
  interrupts, the keyboard matrix), the WD1772 disk controller, the SAA1099,
  the tape's pulse scale, the disk image formats and which machine can use
  which, and the snapshots; with a ROM of its own making (a NOP sled), so it
  needs none. If a real ROM and a boot disk are given, they are run too: the
  ROM must start up, BASIC answer, and SAMDOS boot from the disk.

    samtest <roms folder> <scratch folder> [<folder with samcoupe.rom and SAMDOSVersion2.0.dsk>] }
program samtest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Math, Models, Spectrum, Sam, SAA1099, WD1772, DSK, Tape, DiskFormat, SamdosFS, Daad;

type
  TFrameCopy = array of LongWord;

var
  Failures: Integer = 0;
  Scratch, RomsDir: string;

procedure Check(Cond: Boolean; const What: string);
begin
  if Cond then WriteLn('ok    ', What)
  else
  begin
    WriteLn('FAIL  ', What);
    Inc(Failures);
  end;
end;

{ A SAM Coupe on a ROM of NOPs }
function NewSam: TSpectrum;
var
  F: TFileStream;
  Rom: array of Byte;
  Dir: string;
begin
  Dir := Scratch + DirectorySeparator + 'fakeroms';
  ForceDirectories(Dir);
  SetLength(Rom, 32768);
  FillChar(Rom[0], Length(Rom), 0);
  F := TFileStream.Create(Dir + DirectorySeparator + 'samcoupe.rom', fmCreate);
  try
    F.WriteBuffer(Rom[0], Length(Rom));
  finally
    F.Free;
  end;
  Result := TSpectrum.Create(smSAM, Dir);
end;

procedure Out_(Sp: TSpectrum; Port: Word; Value: Byte);
var
  T: Integer;
begin
  T := 0;
  Sp.WritePort(Port, Value, T);
end;

function In_(Sp: TSpectrum; Port: Word): Byte;
var
  T: Integer;
begin
  T := 0;
  Result := Sp.ReadPort(Port, T);
end;

{ ---- paging ---- }

procedure TestPaging;
var
  Sp: TSpectrum;
  P: Integer;
  Distinct: Boolean;
begin
  WriteLn('--- paging (LMPR, HMPR)');
  Sp := NewSam;
  try
    // After reset: ROM0 in section A, RAM page 1 in B, 0 in... C is HMPR page 0 and D page 1
    Check(Sp.SlotBank(0) = -1, 'ROM0 is paged in at 0000 after a reset');
    Check(Sp.SlotBank(1) = 1, 'page 1 is at 4000 (the page after the one in section A)');
    Check(Sp.SlotBank(2) = 0, 'page 0 is at 8000 (HMPR 0)');
    Check(Sp.SlotBank(3) = 1, 'page 1 is at C000');
    // RAM into section A (LMPR bit 5), page 4: A = 4, B = 5
    Out_(Sp, $00FA, $24);
    Check((Sp.SlotBank(0) = 4) and (Sp.SlotBank(1) = 5), 'LMPR $24: pages 4 and 5 at 0000 and 4000');
    Sp.Poke($0000, $5A);
    Check(Sp.RamBank(4)^[0] = $5A, 'RAM in section A is written (page 4)');
    // Write protect (LMPR bit 7)
    Out_(Sp, $00FA, $A4);
    Sp.WriteMem($0000, $11, 0);
    Check(Sp.RamBank(4)^[0] = $5A, 'WPRAM: section A ignores writes');
    // ROM1 over section D (LMPR bit 6)
    Out_(Sp, $00FA, $64);
    Check(Sp.SlotBank(3) = -2, 'LMPR bit 6: ROM1 at C000');
    // HMPR: section C = page 7, D = page 8
    Out_(Sp, $00FA, $24);
    Out_(Sp, $00FB, $07);
    Check((Sp.SlotBank(2) = 7) and (Sp.SlotBank(3) = 8), 'HMPR 7: pages 7 and 8 at 8000 and C000');
    Sp.Poke($8000, $77);
    Check(Sp.RamBank(7)^[0] = $77, 'writing at 8000 lands in page 7');
    // The ports read back
    Check(In_(Sp, $00FA) = $24, 'LMPR reads back');
    Check(In_(Sp, $00FB) = $07, 'HMPR reads back');
    // 256K: pages above 15 aren't there
    Sp.SamMemoryKB := 256;
    Out_(Sp, $00FB, $10);
    Check(Sp.SlotBank(2) = NO_MEMORY, 'a 256K machine has nothing in page 16');
    Sp.SamMemoryKB := 512;
    Out_(Sp, $00FB, $10);
    Check(Sp.SlotBank(2) = 16, 'a 512K machine has page 16');
    // Writing in every page and reading it back: the pages are distinct
    Out_(Sp, $00FA, $20);     // RAM in section A: pages 0 and 1; HMPR chooses 8000 and C000
    for P := 2 to 31 do
    begin
      Out_(Sp, $00FB, P);
      Sp.WriteMem($8000, P + 100, 0);
    end;
    Distinct := True;
    for P := 2 to 31 do
    begin
      Out_(Sp, $00FB, P);
      if Sp.ReadMem($8000, 0) <> P + 100 then
      begin
        WriteLn('  page ', P, ' reads ', Sp.ReadMem($8000, 0));
        Distinct := False;
      end;
    end;
    Check(Distinct, 'the pages 2-31 are 30 distinct ones of 16K');
    // The debugger's slot lists and registers (the same as writing the ports)
    Out_(Sp, $00FA, 0);
    Out_(Sp, $00FB, 0);
    Check(Sp.CPCSlotCanHold(0, -1) and Sp.CPCSlotCanHold(3, -2) and Sp.CPCSlotCanHold(2, 31),
      'section A can hold ROM0, D ROM1, any a page');
    Check(not Sp.CPCSlotCanHold(0, -2) and not Sp.CPCSlotCanHold(3, -1) and not Sp.CPCSlotCanHold(2, 32),
      'and no more than that');
    Check(Sp.SetCPCSlot(2, 9) and (Sp.SlotBank(2) = 9) and (Sp.SlotBank(3) = 10), 'a slot chosen: page 9 at 8000 and 10 at C000');
    Check(Sp.SetCPCSlot(3, -2) and (Sp.SlotBank(3) = -2), 'ROM1 chosen for section D');
    Check(Sp.SetCPCSlot(3, 4) and (Sp.SlotBank(3) = 4) and (Sp.SlotBank(2) = 3), 'page 4 at C000 puts 3 at 8000 (they go in pairs)');
    Check(Sp.SetCPCSlot(0, 5) and (Sp.SlotBank(0) = 5) and (Sp.SlotBank(1) = 6), 'RAM at 0000: pages 5 and 6');
    Check(Sp.SetCPCSlot(0, -1) and (Sp.SlotBank(0) = -1), 'ROM0 back at 0000');
    Check(Sp.SetCPCSlot(1, 12) and (Sp.SlotBank(1) = 12), 'page 12 at 4000 (A gets 11)');
    Sp.SetSamRegister($FB, 17);
    Check((Sp.SamRegister($FB) = 17) and (Sp.SlotBank(2) = 17), 'a register written from the debugger pages');
    Sp.SetSamRegister($100 + 6, 55);
    Check(Sp.SAM.Clut[6] = 55, '... and the CLUT');
    Sp.SetSamRegister($200 + 8, 99);
    Check(Sp.SamRegister($208) = 99, '... and the SAA1099''s registers');
    Check(not Sp.SetSlot3Bank(3), 'the +3''s slot 3 bank means nothing here');
  finally
    Sp.Free;
  end;
end;

{ ---- contention, the beam's place, the mouse, the clock, the characters ---- }

procedure TestExtras;
var
  Sp: TSpectrum;
  K, M, I, Y: Integer;
  B: array[0..8] of Byte;
  F: array of LongWord;
  T: Integer;
begin
  WriteLn('--- contention, beam, mouse, clock, characters');
  Sp := NewSam;
  try
    // The ASIC holds RAM accesses to a 4 T-state grid (8 while it draws the picture)
    Check(Sp.SAM.WaitStates(10) in [0..3], 'in the border an access waits for the 4 T-state grid');
    Sp.SAM.VMPR := $60 or 5;          // mode 3, screen on
    T := (SAM_TOP_LINES + 10) * SAM_LINE_T + SAM_LEFT_T + 10;
    Check(Sp.SAM.WaitStates(T) in [0..7], 'while the picture is drawn it waits for the 8 T-state grid');
    I := 0;
    for K := 0 to 7 do I := Max(I, Sp.SAM.WaitStates(T + K));
    Check(I = 7, 'in the picture the longest wait is 7 T-states');
    Sp.SAM.Border := $80;             // screen off
    Check(Sp.SAM.WaitStates(T) in [0..3], 'with the screen off the picture holds nothing back');
    Sp.SAM.Border := 0;
    // The beam: the vertical place from port 1F8 (the screen's first line is 0), the horizontal from F8
    T := 0;
    Y := (SAM_TOP_LINES + 20) * SAM_LINE_T + 5;
    Check(Sp.ReadPort($01F8, Y) = 20, 'port 1F8 is the line of the beam (0 = the first of the screen)');
    // The characters: the SAM keys that make them
    Check(SamKeysForChar('a', K, M) and (K = SAMK_A) and (M < 0), 'a is the A key');
    Check(SamKeysForChar('A', K, M) and (K = SAMK_A) and (M = SAMK_SHIFT), 'A is SHIFT and the A key');
    Check(SamKeysForChar('"', K, M) and (K = SAMK_QUOTE) and (M < 0), 'the quote has its own key');
    Check(SamKeysForChar('?', K, M) and (K = SAMK_Z) and (M = SAMK_SYMBOL), '? is SYMBOL and Z');
    Check(SamKeysForChar('[', K, M) and (K = SAMK_R) and (M = SAMK_SYMBOL), '[ is SYMBOL and R');
    Check(SamKeysForChar('\', K, M) and (K = SAMK_INV) and (M = SAMK_SHIFT), 'the backslash is SHIFT and INV');
    Check(SamKeysForChar('@', K, M) and (K = SAMK_2) and (M = SAMK_SHIFT), '@ is SHIFT and 2');
    Check(not SamKeysForChar(#7, K, M), 'a control character has no key');
    // The mouse: through the keyboard port with the high byte $FF, in a sequence of nibbles
    Sp.SamMouseOn := True;
    Sp.SAM.MouseMoved(5, -3);         // 5 to the right, 3 up
    Sp.SAM.MouseButtons := 1;
    for I := 0 to 8 do B[I] := In_(Sp, $FFFE);
    Check(((B[0] and 15) = 15) and ((B[2] and 15) = 14), 'the mouse: a pressed button reads 0');
    Check(((B[3] and 15) = 0) and ((B[4] and 15) = 0) and ((B[5] and 15) = 5), 'the mouse: X is 5');
    Check(((B[6] and 15) = 0) and ((B[7] and 15) = 0) and ((B[8] and 15) = 3), 'the mouse: Y is 3 (up)');
    Sp.SAM.MouseMoved(-1, 0);
    Check(In_(Sp, $FFFE) and $0F = $0F, 'the next sequence starts at the header');
    for I := 1 to 7 do In_(Sp, $FFFE);
    Sp.SamMouseOn := False;
    Check(In_(Sp, $FFFE) and $0F = $0F, 'a mouse that is not connected leaves the keys alone');
    // The clock: digits of 4 bits that follow the PC's
    Sp.SamClockOn := True;
    Check((In_(Sp, $00EF) and $F0) = $F0, 'the clock answers with nibbles');
    I := (In_(Sp, $0AEF) and 15) + 10 * (In_(Sp, $0BEF) and 15);
    Check(I = StrToInt(FormatDateTime('yy', Now)), 'the clock''s year is the PC''s');
    Sp.SamClockOn := False;
    Check(In_(Sp, $0AEF) = $FF, 'with no clock the port is free');
  finally
    Sp.Free;
  end;
  // A change in the middle of a line shows from that cell on (the cells are what the ASIC draws as the beam goes by)
  Sp := NewSam;
  try
    SetLength(F, FB_WIDTH);
    Sp.SAM.VMPR := $60 or 5;
    Sp.SAM.Border := 1;
    Sp.SAM.DrawCells(BORDER_TOP + 100, BORDER_TOP, BORDER_LEFT, 0, 8, @F[0]);
    Sp.SAM.Border := 2;
    Sp.SAM.DrawCells(BORDER_TOP + 100, BORDER_TOP, BORDER_LEFT, 8, SAM_CELLS, @F[0]);
    Check(F[2] <> F[FB_WIDTH - 2], 'the border changes colour in the middle of a line');
    Check(F[2] = F[40], 'the first cells have the colour they were drawn with');
  finally
    Sp.Free;
  end;
end;

{ ---- SAMDOS's file system ---- }

procedure TestSamdos(const Dir: string);
var
  Disk: TDiskImage;
  FS: TSamdosDisk;
  Data, Back: TBytes;
  I: Integer;
  Free0: Integer;
  Problem: TDiskProblem;
  Err, Path: string;
begin
  WriteLn('--- the SAMDOS file system');
  Disk := NewSamDisk;
  try
    FS := TSamdosDisk.Create(Disk);
    try
      Check(FS.Count = 0, 'a new SAM disk has no files');
      Free0 := FS.FreeBytes;
      Check(Free0 = 1560 * 510, 'all the sectors after the directory are free');
      SetLength(Data, 40000);
      for I := 0 to High(Data) do Data[I] := (I * 7 + I shr 8) and 255;
      FS.WriteFile('Test Code', Data, SAMDOS_TYPE_CODE, 32768 + 100);
      Check(FS.Count = 1, 'a file written appears in the directory');
      Check(FS[0].Name = 'Test Code', 'its name');
      Check(FS[0].Length = 40000, 'its length (more than a page)');
      Back := FS.ReadFile(0);
      Check((Length(Back) = 40000) and CompareMem(@Back[0], @Data[0], 40000), 'it reads back as it was written');
      Check(FS.FreeBytes = Free0 - 79 * 510, 'it took 79 sectors (40009 bytes of 510)');
      FS.RenameFile(0, 'Renamed');
      Check(FS.FindFile('renamed') = 0, 'a file renamed is found by its new name, whatever the case');
      FS.WriteFile('Second', Data, SAMDOS_TYPE_BASIC, 0);
      Check(FS.Count = 2, 'a second file');
      FS.DeleteFile(0);
      Check((FS.Count = 1) and (FS[0].Name = 'Second'), 'a file deleted is gone');
      Check(FS.FreeBytes = Free0 - 79 * 510, 'and its sectors are free again');
      try
        FS.WriteFile('Second', Data);
        Check(False, 'two files with one name');
      except
        Check(True, 'two files with one name are refused');
      end;
    finally
      FS.Free;
    end;
  finally
    Disk.Free;
  end;
  Path := IncludeTrailingPathDelimiter(Dir) + 'SAMDOSVersion2.0.dsk';
  if FileExists(Path) then
  begin
    Disk := LoadDiskImage(Path, Problem, Err);
    try
      FS := TSamdosDisk.Create(Disk);
      try
        Check(FS.Count = 20, Format('the SAMDOS disk has its 20 files (%d)', [FS.Count]));
        I := FS.FindFile('auto');
        Check((I >= 0) and (FS[I].FileType = SAMDOS_TYPE_BASIC) and (FS[I].Length = 3701), 'AUTO is a BASIC program of 3701 bytes');
        Check((I >= 0) and (Length(FS.ReadFile(I)) = 3701), 'and its data is read');
        I := FS.FindFile('screen1');
        Check((I >= 0) and (FS[I].FileType = SAMDOS_TYPE_SCREEN) and (Length(FS.ReadFile(I)) = FS[I].Length), 'a SCREEN$ file reads whole');
      finally
        FS.Free;
      end;
    finally
      Disk.Free;
    end;
  end;
end;

{ ---- the SAMDOS load trap ---- }

{ Boots SAMDOS, leaves for BASIC and loads SCREEN1 with fast disk access on or off: the picture after Frames frames }
function SamdosScreen(const Dir: string; Fast: Boolean; Frames: Integer; out Mode, Hits: Integer): TFrameCopy;
var
  Sp: TSpectrum;
  Disk: TDiskImage;
  Problem: TDiskProblem;
  Err: string;
  I: Integer;
begin
  Sp := TSpectrum.Create(smSAM, Dir);
  try
    Sp.SetFastDisk(Fast);
    Disk := LoadDiskImage(IncludeTrailingPathDelimiter(Dir) + 'SAMDOSVersion2.0.dsk', Problem, Err);
    Sp.InsertDiskAt(0, Disk);
    Sp.AutoLoad(True);
    for I := 1 to 700 do Sp.RunFrame;
    Sp.TypeText('l~~\n~', Err);
    for I := 1 to 300 do Sp.RunFrame;
    Sp.TypeText('load "screen1" screen$\n', Err);
    for I := 1 to Frames do Sp.RunFrame;
    SetLength(Result, FB_WIDTH * SCREEN_HEIGHT);
    Sp.CopyFrameBuffer(@Result[0]);
    Mode := Sp.SAM.ScreenMode;
    Hits := Sp.SamTrapHits;
  finally
    Sp.Free;
  end;
end;

procedure TestSamdosTrap(const Dir: string);
var
  A, B: TFrameCopy;
  MA, MB, HA, HB, I, Same: Integer;
begin
  WriteLn('--- the SAMDOS load trap');
  if not FileExists(IncludeTrailingPathDelimiter(Dir) + 'SAMDOSVersion2.0.dsk') then
  begin
    WriteLn('(no SAMDOSVersion2.0.dsk there: skipped)');
    Exit;
  end;
  A := SamdosScreen(Dir, True, 4000, MA, HA);     // the file goes into memory at once
  B := SamdosScreen(Dir, False, 4000, MB, HB);   // the DOS reads it sector by sector, as the real disk does
  Same := 0;
  for I := 0 to High(A) do
    if A[I] = B[I] then Inc(Same);
  Check(Same * 100 > Length(A) * 97, Format('the trapped load gives the picture the DOS gives (%d%% the same)', [Same * 100 div Length(A)]));
  Check(MA = MB, 'and the same screen mode');
  Check(HA >= 1, 'the trap took the file');
  Check(HB = 0, 'and it does nothing with fast disk access off');
end;

{ ---- interrupts and the keyboard ---- }

procedure TestInterruptsAndKeyboard;
var
  Sp: TSpectrum;
  S: Byte;
begin
  WriteLn('--- interrupts and keyboard');
  Sp := NewSam;
  try
    S := Sp.SAM.InterruptStatus(10);
    Check((S and $08) = 0, 'FRAME is requested at the start of the frame');
    S := Sp.SAM.InterruptStatus(5000);
    Check(S = $1F, 'nothing is requested in the middle of the frame');
    Sp.SAM.LineInt := 100;
    // At the end of the screen of the line before: line 99 of the screen
    S := Sp.SAM.InterruptStatus((SAM_TOP_LINES + 99) * SAM_LINE_T + SAM_LINE_INT_T + 10);
    Check((S and $01) = 0, 'LINE is requested after the screen line before the one in port F9');
    S := Sp.SAM.InterruptStatus((SAM_TOP_LINES + 99) * SAM_LINE_T + SAM_LINE_INT_T + 400);
    Check((S and $01) <> 0, '... and only for a moment');
    Sp.SAM.LineInt := 200;
    Check(Sp.SAM.InterruptStatus((SAM_TOP_LINES + 199) * SAM_LINE_T + 200) = $1F, 'a line above 191 is no interrupt');
    // The keyboard: Z (row 0, bit 1), seen with A8 low
    Check(In_(Sp, $FEFE) and $1F = $1F, 'no key down: all the lines high');
    Sp.SAM.Keys[SAMK_Z div 8] := 1 shl (SAMK_Z mod 8);
    Check((In_(Sp, $FEFE) and $02) = 0, 'Z shows in line K2 of the first row');
    Check((In_(Sp, $FDFE) and $02) <> 0, '... and not in another row');
    Check((In_(Sp, $FFFE) and $1F) = $1F, '... nor in the control row');
    Sp.SAM.Keys[SAMK_Z div 8] := 0;
    // F1 is K6: read at port F9 (bits 5-7)
    Sp.SAM.Keys[SAMK_F1 div 8] := 1 shl (SAMK_F1 mod 8);
    Check((In_(Sp, $FEF9) and $20) = 0, 'F1 shows in K6 at the status port');
    Sp.SAM.Keys[SAMK_F1 div 8] := 0;
    // Ctrl is in the ninth row, read with the whole high byte set
    Sp.SAM.Keys[8] := 1;
    Check((In_(Sp, $FFFE) and $01) = 0, 'Ctrl shows when the whole high byte is set');
    Sp.SAM.Keys[8] := 0;
    // The joystick (Kempston, port 31)
    Sp.SamJoystickOn := True;
    Sp.KempstonState := $11;
    Check(In_(Sp, $001F) = $11, 'the Kempston joystick reads at port 31');
    Sp.SamJoystickOn := False;
    Check(In_(Sp, $001F) = 0, '... and not without it');
  finally
    Sp.Free;
  end;
end;

{ ---- the picture ---- }

function Pixel(var F: array of LongWord; X, Y: Integer): LongWord;
begin
  Result := F[Y * FB_WIDTH + X] and $FFFFFF;
end;

procedure Frames(Sp: TSpectrum; var F: array of LongWord);
begin
  Sp.RunFrame;
  Sp.RunFrame;
  Sp.CopyFrameBuffer(@F[0]);
end;

procedure TestVideo;
var
  Sp: TSpectrum;
  F: array of LongWord;
  X0: Integer;
const
  WHITE = 127;     // the CLUT entry of bright white
begin
  WriteLn('--- the screen modes');
  Sp := NewSam;
  try
    SetLength(F, FB_WIDTH * SCREEN_HEIGHT);
    X0 := BORDER_LEFT * 2;
    Out_(Sp, $00F8 + 1 * $100, 16);
    Check(Sp.SAM.Clut[1] = 16, 'the CLUT takes a colour at port F8 + 256 * entry');
    // Mode 4: 256 pixels of 4 bits (VMPR bits 6-5 = 11), the high nibble first
    Out_(Sp, $00F8 + 15 * $100, WHITE);
    Out_(Sp, $00F8 + 2 * $100, 32);
    Out_(Sp, $00FC, $60 or 5);
    FillChar(Sp.RamBank(5)^, SizeOf(TBank), 0);
    FillChar(Sp.RamBank(6)^, SizeOf(TBank), 0);
    Sp.RamBank(5)^[0] := $1F;             // line 0: entries 1 and 15
    Sp.RamBank(5)^[128] := $22;           // line 1: entries 2 and 2
    Frames(Sp, F);
    Check(Pixel(F, X0, BORDER_TOP) = Pixel(F, X0 + 1, BORDER_TOP), 'mode 4: a pixel is two columns wide');
    Check(Pixel(F, X0 + 2, BORDER_TOP) = $FFFFFF, 'mode 4: the low nibble is the second pixel (entry 15, white)');
    Check(Pixel(F, X0, BORDER_TOP) <> Pixel(F, X0 + 2, BORDER_TOP), 'mode 4: the high nibble is another colour (entry 1)');
    Check(Pixel(F, X0, BORDER_TOP + 1) = Pixel(F, X0 + 3, BORDER_TOP + 1), 'mode 4: line 1 is 128 bytes after line 0');
    Check(Pixel(F, X0, BORDER_TOP + 1) <> 0, '... in the colour of entry 2');
    // Mode 3: 512 pixels of 2 bits, 4 to the byte: %11 00 10 01 = entries 3, 0, 2, 1 (VMPR bits 6-5 = 10)
    Out_(Sp, $00FC, $40 or 5);
    Out_(Sp, $00F8 + 3 * $100, WHITE);
    Sp.RamBank(5)^[0] := $C9;
    Frames(Sp, F);
    Check(Pixel(F, X0, BORDER_TOP) = $FFFFFF, 'mode 3: the first pixel is entry 3 (white)');
    Check(Pixel(F, X0 + 1, BORDER_TOP) = 0, 'mode 3: the second is entry 0 (black), a column of its own');
    Check(Pixel(F, X0 + 2, BORDER_TOP) <> 0, 'mode 3: the third is entry 2');
    // HMPR bits 5 and 6 choose which 4 entries mode 3 uses: here 4-7
    Out_(Sp, $00F8 + 7 * $100, 0);
    Out_(Sp, $00FB, $20);
    Frames(Sp, F);
    Check(Pixel(F, X0, BORDER_TOP) = 0, 'mode 3: HMPR bit 5 moves the colours to entries 4-7 (entry 7 is black)');
    Out_(Sp, $00FB, $00);
    // Mode 1: the Spectrum''s layout, the attributes at $1800 of the page (VMPR bits 6-5 = 00)
    Out_(Sp, $00FC, $00 or 5);
    FillChar(Sp.RamBank(5)^, SizeOf(TBank), 0);
    Sp.RamBank(5)^[0] := $80;             // the first pixel of line 0
    Sp.RamBank(5)^[$1800] := $07;         // ink 7, paper 0
    Out_(Sp, $00F8 + 7 * $100, WHITE);
    Out_(Sp, $00F8 + 0 * $100, 0);
    Frames(Sp, F);
    Check(Pixel(F, X0, BORDER_TOP) = $FFFFFF, 'mode 1: ink 7 is the CLUT''s entry 7');
    Check(Pixel(F, X0 + 2, BORDER_TOP) = 0, 'mode 1: a clear pixel is paper');
    // Mode 2: a row of attributes for each line, at $2000 (VMPR bits 6-5 = 01)
    Out_(Sp, $00FC, $20 or 5);
    FillChar(Sp.RamBank(5)^, SizeOf(TBank), 0);
    Sp.RamBank(5)^[32] := $80;            // line 1, 32 bytes a line
    Sp.RamBank(5)^[$2000 + 32] := $07;
    Frames(Sp, F);
    Check(Pixel(F, X0, BORDER_TOP + 1) = $FFFFFF, 'mode 2: line 1''s pixels, and its own attribute at $2000');
    Check(Pixel(F, X0, BORDER_TOP) = 0, 'mode 2: line 0, with no attribute, is paper 0');
    // The border: the CLUT entry port FE says, bits 0-2
    Out_(Sp, $00FE, 7);
    Frames(Sp, F);
    Check(Pixel(F, 4, 4) = $FFFFFF, 'the border has the colour of the entry port FE gives');
    // Screen off (port FE bit 7, modes 3 and 4): the border all over
    Out_(Sp, $00FC, $60 or 5);
    Out_(Sp, $00FE, 7 or $80);
    Frames(Sp, F);
    Check(Pixel(F, X0 + 10, BORDER_TOP + 40) = $FFFFFF, 'screen off: the border shows where the screen was');
    // The video page 5 in 256K and 512K is the same page; page 20 isn't in a 256K machine
    Sp.SamMemoryKB := 256;
    Out_(Sp, $00FC, $60 or 20);
    Out_(Sp, $00FE, 0);
    Frames(Sp, F);
    Check(Pixel(F, X0, BORDER_TOP + 20) = Pixel(F, X0 + 5, BORDER_TOP + 30), 'a video page that isn''t there draws a flat picture');
  finally
    Sp.Free;
  end;
end;

{ ---- the WD1772 ---- }

function NewMgt: TDiskImage;
var
  Raw: TBytes;
  I: Integer;
  F: TFileStream;
  Problem: TDiskProblem;
  Err: string;
  Path: string;
begin
  SetLength(Raw, RAW_SAM_SIZE);
  for I := 0 to High(Raw) do Raw[I] := (I * 7 + I div 512) and $FF;
  Path := Scratch + DirectorySeparator + 'test.mgt';
  F := TFileStream.Create(Path, fmCreate);
  try
    F.WriteBuffer(Raw[0], Length(Raw));
  finally
    F.Free;
  end;
  Result := LoadDiskImage(Path, Problem, Err);
end;

procedure WaitNotBusy(W: TWD1772; Port: Word; var Now: Int64);
var
  N: Integer;
begin
  N := 0;
  repeat
    W.SetTime(Now);
    Inc(Now, 100);
    Inc(N);
  until ((W.ReadReg(Port) and 1) = 0) or (N > 5000000);
end;

procedure TestWD1772;
var
  W: TWD1772;
  Disk: TDiskImage;
  Now: Int64;
  I, N: Integer;
  St: Byte;
  Got: array[0..511] of Byte;

  { A read sector command, with the data read as it is ready }
  function ReadSector(Track, Sector: Byte; Port: Word): Boolean;
  begin
    W.WriteReg(Port or 1, Track);
    W.WriteReg(Port or 2, Sector);
    W.WriteReg(Port, $80);
    N := 0;
    I := 0;
    while (I < 512) and (N < 5000000) do
    begin
      Inc(Now, 50);
      W.SetTime(Now);
      Inc(N);
      St := W.ReadReg(Port);
      if (St and 2) <> 0 then
      begin
        Got[I] := W.ReadReg(Port or 3);
        Inc(I);
      end;
    end;
    WaitNotBusy(W, Port, Now);
    Result := I = 512;
  end;

begin
  WriteLn('--- WD1772');
  W := TWD1772.Create;
  W.ClockHz := 6000000;
  Disk := NewMgt;
  try
    Now := 1000000;
    W.SetTime(Now);
    St := W.ReadReg($E0);
    Check((St and $80) <> 0, 'no disk: the status says not ready');
    W.InsertDisk(0, Disk);
    // Restore: track 0, the head step done, the track register 0
    W.WriteReg($E0, $00);
    WaitNotBusy(W, $E0, Now);
    St := W.ReadReg($E0);
    Check((St and $04) <> 0, 'restore: track 0 is reported');
    Check(W.ReadReg($E1) = 0, 'restore: the track register is 0');
    // The index hole passes: the status bit changes over a turn
    N := 0;
    for I := 0 to 400 do
    begin
      Inc(Now, 3000000 div 200);
      W.SetTime(Now);
      if (W.ReadReg($E0) and 2) <> 0 then Inc(N);
    end;
    Check((N > 0) and (N < 400), 'the index hole is seen sometimes, not always');
    // Seek to track 5
    W.WriteReg($E3, 5);
    W.WriteReg($E0, $10);
    WaitNotBusy(W, $E0, Now);
    Check(W.ReadReg($E1) = 5, 'seek: the track register is the destination');
    Check((W.ReadReg($E0) and $04) = 0, 'seek: no longer on track 0');
    // Read sector 3 of track 5, side 0
    W.WriteReg($E0, $00);
    WaitNotBusy(W, $E0, Now);
    W.WriteReg($E3, 5);
    W.WriteReg($E0, $10);
    WaitNotBusy(W, $E0, Now);
    Check(ReadSector(5, 3, $E0), 'read sector: 512 bytes come');
    N := 0;
    for I := 0 to 511 do
      if Got[I] = Disk.Track(5, 0)^.Sectors[2].Data[I] then Inc(N);
    Check(N = 512, 'read sector: they are the sector''s contents');
    Check((W.ReadReg($E0) and $1C) = 0, 'read sector: no error bits');
    // The other side is read with the ports 4-7
    Check(ReadSector(5, 3, $E4), 'read sector, side 2');
    N := 0;
    for I := 0 to 511 do
      if Got[I] = Disk.Track(5, 1)^.Sectors[2].Data[I] then Inc(N);
    Check(N = 512, 'side 2: the other side''s contents');
    // A sector that isn't there
    W.WriteReg($E2, 99);
    W.WriteReg($E0, $80);
    WaitNotBusy(W, $E0, Now);
    Check((W.ReadReg($E0) and $10) <> 0, 'a missing sector: record not found');
    // Read address
    W.WriteReg($E0, $C0);
    I := 0;
    N := 0;
    while (I < 6) and (N < 100000) do
    begin
      Inc(Now, 50);
      W.SetTime(Now);
      Inc(N);
      if (W.ReadReg($E0) and 2) <> 0 then
      begin
        Got[I] := W.ReadReg($E3);
        Inc(I);
      end;
    end;
    WaitNotBusy(W, $E0, Now);
    Check((I = 6) and (Got[0] = 5) and (Got[3] = 2), 'read address: track 5, N = 2 (512 bytes)');
    // Write a sector and read it back
    W.WriteReg($E1, 5);
    W.WriteReg($E2, 4);
    W.WriteReg($E0, $A0);
    I := 0;
    N := 0;
    while (I < 512) and (N < 100000) do
    begin
      Inc(Now, 50);
      W.SetTime(Now);
      Inc(N);
      if (W.ReadReg($E0) and 2) <> 0 then
      begin
        W.WriteReg($E3, (I * 3 + 1) and $FF);
        Inc(I);
      end;
    end;
    WaitNotBusy(W, $E0, Now);
    Check(Disk.Modified, 'write sector: the disk is marked modified');
    Check(ReadSector(5, 4, $E0), 'write sector: read back');
    N := 0;
    for I := 0 to 511 do
      if Got[I] = (I * 3 + 1) and $FF then Inc(N);
    Check(N = 512, 'write sector: what was written is read');
    // Write protected
    Disk.WriteProtected := True;
    W.WriteReg($E0, $A0);
    Check((W.ReadReg($E0) and $40) <> 0, 'write protected: the status says so');
    Disk.WriteProtected := False;
    // Drive 2 isn't the same drive
    W.SetTime(Now);
    Check((W.ReadReg($F0) and $80) <> 0, 'drive 2 has no disk: not ready');
  finally
    W.Free;
  end;
end;

{ ---- the SAA1099 ---- }

procedure TestSAA;
var
  S: TSAA1099;
  L, R, Prev: Single;
  I, Crossings, Loud: Integer;
  F: Double;
begin
  WriteLn('--- SAA1099');
  S := TSAA1099.Create;
  try
    // A tone: octave 3, frequency 33: middle C, 261.5 Hz as the manual's table says
    S.WriteRegister(28, 1);
    S.WriteRegister(20, 1);
    S.WriteRegister(0, $FF);
    S.WriteRegister(8, 33);
    S.WriteRegister(16, 3);
    Crossings := 0;
    Prev := 0;
    Loud := 0;
    for I := 1 to 44100 do
    begin
      S.Sample(44100, L, R);
      if (Prev <= 0) and (L > 0) then Inc(Crossings);
      Prev := L;
      if L > 0 then Inc(Loud);
    end;
    F := Crossings;
    Check(Abs(F - 261.5) < 3, Format('octave 3, tone 33 is middle C (%d Hz measured)', [Crossings]));
    Check((Loud > 20000) and (Loud < 24000), 'the wave is a square one: half the time high');
    // Left and right amplitudes: right off
    S.WriteRegister(0, $0F);
    S.Sample(44100, L, R);
    Check(R = 0, 'amplitude 0 on the right: silence on that side');
    // Off: sound enable 0
    S.WriteRegister(0, $FF);
    S.WriteRegister(28, 0);
    Loud := 0;
    for I := 1 to 4410 do
    begin
      S.Sample(44100, L, R);
      if (L <> 0) or (R <> 0) then Inc(Loud);
    end;
    Check(Loud = 0, 'sound disabled: no output');
    // Noise
    S.WriteRegister(28, 1);
    S.WriteRegister(20, 0);
    S.WriteRegister(21, 1);
    Loud := 0;
    for I := 1 to 4410 do
    begin
      S.Sample(44100, L, R);
      if L > 0 then Inc(Loud);
    end;
    Check((Loud > 500) and (Loud < 3900), 'noise: the output is high sometimes');
  finally
    S.Free;
  end;
end;

{ ---- tape ---- }

var
  EdgeCount: Integer;
  EdgeTimes: array[0..7] of Integer;

procedure OnEdge(T: Integer; Level: Boolean);
begin
  if EdgeCount <= High(EdgeTimes) then EdgeTimes[EdgeCount] := T;
  Inc(EdgeCount);
end;

type
  TEdgeSink = class
    procedure Edge(T: Integer; Level: Boolean);
  end;

procedure TEdgeSink.Edge(T: Integer; Level: Boolean);
begin
  OnEdge(T, Level);
end;

procedure TestTapeScale;
var
  Tape: TTape;
  Sink: TEdgeSink;
begin
  WriteLn('--- the tape on a 6 MHz machine');
  Tape := TTape.Create;
  Sink := TEdgeSink.Create;
  try
    Tape.OnEdge := @Sink.Edge;
    Tape.AddPulses([1000, 2000, 500], 0);
    EdgeCount := 0;
    Tape.Play(0);
    Tape.AdvanceTo(1000000);
    Check((EdgeCount >= 3) and (EdgeTimes[1] = 1000) and (EdgeTimes[2] = 3000), 'at 3.5 MHz the pulses are as the TZX says');
    Tape.Rewind;
    Tape.SetPulseScale(12, 7);
    EdgeCount := 0;
    Tape.Play(0);
    Tape.AdvanceTo(1000000);
    Check((EdgeCount >= 3) and (EdgeTimes[1] = 1714) and (EdgeTimes[2] = 5142), 'at 6 MHz they are 12/7 as long');
  finally
    Sink.Free;
    Tape.Free;
  end;
end;

{ ---- disk images ---- }

procedure WriteFile(const Name: string; const Data: TBytes);
var
  F: TFileStream;
begin
  F := TFileStream.Create(Name, fmCreate);
  try
    if Length(Data) > 0 then F.WriteBuffer(Data[0], Length(Data));
  finally
    F.Free;
  end;
end;

procedure TestDiskFormats;
var
  Disk, Back, Cpc, P3: TDiskImage;
  Problem: TDiskProblem;
  Err, Path, Raw1: string;
  Bytes: TBytes;
  A, B: TBytes;
  Msg: string;

  function Slurp(const FileName: string): TBytes;
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

begin
  WriteLn('--- disk image formats');
  Disk := NewMgt;
  try
    Check(Disk <> nil, 'an 819200-byte file is an MGT image');
    Check(ClassifyDisk(Disk) = dkSAM, 'it has the geometry of a SAM Coupe disk');
    Check((Disk.Cylinders = 80) and (Disk.Sides = 2), '80 cylinders, 2 sides');
    Check((Length(Disk.Track(0, 0)^.Sectors) = 10) and (Disk.Track(0, 0)^.Sectors[0].R = 1), '10 sectors a track, from 1');
    // The sides alternate in an MGT: track 0 side 1 follows track 0 side 0
    Check(Disk.Track(0, 1)^.Sectors[0].Data[0] = ((10 * 512) * 7 + 10) and $FF, 'the sides alternate in the file');
    // Round trips
    Raw1 := Scratch + DirectorySeparator + 'a.mgt';
    Check(SaveDiskImage(Disk, Raw1) = '', 'save as MGT');
    A := Slurp(Scratch + DirectorySeparator + 'test.mgt');
    B := Slurp(Raw1);
    Check((Length(A) = Length(B)) and CompareMem(@A[0], @B[0], Length(A)), 'the MGT saved is the one loaded, byte for byte');
    Path := Scratch + DirectorySeparator + 'a.sad';
    Check(SaveDiskImage(Disk, Path) = '', 'save as SAD');
    Back := LoadDiskImage(Path, Problem, Err);
    Check((Back <> nil) and (ClassifyDisk(Back) = dkSAM), 'the SAD loads as a SAM disk');
    Check((Back <> nil) and (Back.Track(40, 1)^.Sectors[6].Data[3] = Disk.Track(40, 1)^.Sectors[6].Data[3]) and
      (Back.Track(79, 0)^.Sectors[9].Data[511] = Disk.Track(79, 0)^.Sectors[9].Data[511]), 'its sectors are the MGT''s');
    Back.Free;
    // The extended DSK (what SAMdisk writes): a SAM disk with the CPC's container
    Path := Scratch + DirectorySeparator + 'sam-edsk.dsk';
    Disk.SaveToFile(Path);
    Back := LoadDiskImage(Path, Problem, Err);
    Check((Back <> nil) and (ClassifyDisk(Back) = dkSAM), 'an extended DSK with SAM geometry is a SAM disk (the signature isn''t enough)');
    Check((Back <> nil) and CheckDiskForMachine(Back, Path, dmSAM, Msg), 'the SAM Coupe takes it');
    Check((Back <> nil) and not CheckDiskForMachine(Back, Path, dmCPC, Msg) and (Pos('Amstrad CPC', Msg) > 0),
      'the CPC refuses it, saying so: ' + Msg);
    Check((Back <> nil) and not CheckDiskForMachine(Back, Path, dmSpectrum, Msg) and (Pos('+3', Msg) > 0),
      'the +3 refuses it too');
    Back.Free;
  finally
    Disk.Free;
  end;
  // CPC and +3 disks: each is what it is, and the SAM Coupe can have them
  Cpc := TDiskImage.Create;
  P3 := TDiskImage.Create;
  try
    Cpc.CreateCPCFormatted;
    P3.CreatePlus3Formatted;
    Check(ClassifyDisk(Cpc) = dkCPC, 'a CPC disk (sectors C1-C9) is a CPC disk');
    Check(ClassifyDisk(P3) = dkPlus3, 'a +3 disk is a +3 disk');
    Path := Scratch + DirectorySeparator + 'cpc.dsk';
    Cpc.SaveToFile(Path);
    Back := LoadDiskImage(Path, Problem, Err);
    Check(Back <> nil, 'a CPC DSK loads');
    Check((Back <> nil) and CheckDiskForMachine(Back, Path, dmSAM, Msg), 'the SAM Coupe can have it (its software reads the format)');
    Check((Back <> nil) and CheckDiskForMachine(Back, Path, dmCPC, Msg), 'and the CPC');
    Back.Free;
    Path := Scratch + DirectorySeparator + 'p3.dsk';
    P3.SaveToFile(Path);
    Back := LoadDiskImage(Path, Problem, Err);
    Check((Back <> nil) and CheckDiskForMachine(Back, Path, dmSpectrum, Msg), 'a +3 disk goes in the +3');
    Check((Back <> nil) and CheckDiskForMachine(Back, Path, dmSAM, Msg), '... and in the SAM Coupe');
    Back.Free;
  finally
    Cpc.Free;
    P3.Free;
  end;
  // What isn't a disk
  SetLength(Bytes, 0);
  Path := Scratch + DirectorySeparator + 'empty.dsk';
  WriteFile(Path, Bytes);
  Back := LoadDiskImage(Path, Problem, Err);
  Check((Back = nil) and (Problem = dpCorrupt), 'an empty file is corrupt: ' + Err);
  SetLength(Bytes, 3000);
  FillChar(Bytes[0], 3000, 1);
  WriteFile(Path, Bytes);
  Back := LoadDiskImage(Path, Problem, Err);
  Check((Back = nil) and (Problem = dpUnknown), 'a file of a size no disk has is unknown: ' + Err);
  SetLength(Bytes, 5000);
  FillChar(Bytes[0], 5000, 0);
  Bytes[0] := $50; Bytes[1] := $4B; Bytes[2] := 3; Bytes[3] := 4;
  WriteFile(Path, Bytes);
  Back := LoadDiskImage(Path, Problem, Err);
  Check((Back = nil) and (Problem = dpCompressed) and (Pos('zip', Err) > 0), 'a zip is said to be one: ' + Err);
  // A DSK header cut short
  SetLength(Bytes, 300);
  FillChar(Bytes[0], 300, 0);
  Move(PChar('EXTENDED CPC DSK File')^, Bytes[0], 21);
  Bytes[$30] := 200;
  Bytes[$31] := 2;
  WriteFile(Path, Bytes);
  Back := LoadDiskImage(Path, Problem, Err);
  Check(((Back = nil) and (Problem = dpCorrupt)) or ((Back <> nil)), 'a DSK header with nothing after it doesn''t crash');
  Back.Free;
  // A SAD cut short
  SetLength(Bytes, 100);
  FillChar(Bytes[0], 100, 0);
  Move(PChar('Aley''s disk backup')^, Bytes[0], 18);
  Bytes[18] := 2; Bytes[19] := 80; Bytes[20] := 10; Bytes[21] := 8;
  WriteFile(Path, Bytes);
  Back := LoadDiskImage(Path, Problem, Err);
  Check((Back = nil) and (Problem = dpCorrupt), 'a SAD without its data is corrupt: ' + Err);
  Check(LoadDiskImage(Scratch + DirectorySeparator + 'nothere.dsk', Problem, Err) = nil, 'a file that isn''t there');
  Check(Problem = dpUnreadable, '... is unreadable');
end;

{ ---- machines ---- }

procedure TestMachines;
var
  Sp: TSpectrum;
  Raised: Boolean;
  Fake: string;
begin
  WriteLn('--- changing machines');
  Fake := Scratch + DirectorySeparator + 'fakeroms' + DirectorySeparator + 'samcoupe.rom';
  Sp := NewSam;
  Sp.Free;
  Sp := TSpectrum.Create(smPlus3, RomsDir);
  try
    // No ROM: the machine stays as it was, and says why
    Raised := False;
    if not FileExists(IncludeTrailingPathDelimiter(RomsDir) + 'samcoupe.rom') then
    begin
      try
        Sp.SetModel(smSAM);
      except
        on E: Exception do Raised := Pos('samcoupe.rom', E.Message) > 0;
      end;
      Check(Raised and (Sp.Model = smPlus3) and (Sp.SAM = nil), 'no SAM ROM: the error names it and the machine stays a +3');
    end;
    Sp.RomFile[smSAM, 0] := Fake;
    Sp.SetModel(smSAM);
    Check((Sp.Model = smSAM) and (Sp.SAM <> nil), 'with the ROM given the SAM Coupe starts');
    Check(IsSAMModel(Sp.Model) and not IsCPCModel(Sp.Model), 'it is a SAM, not a CPC');
    Sp.SetModel(smPlus3);
    Check((Sp.Model = smPlus3) and (Sp.SAM = nil), 'back to the +3: the ASIC is gone');
    Sp.SetModel(smCPC6128);
    Sp.SetModel(smSAM);
    Check(Sp.CPC = nil, 'from a CPC to the SAM Coupe: no CPC hardware left');
    Sp.SetModel(smCPC464);
    Check((Sp.CPC <> nil) and (Sp.SAM = nil), 'and back to a CPC');
  finally
    Sp.Free;
  end;
end;

{ Is the text in any page of the RAM }
function RamHas(Sp: TSpectrum; const Text: string): Boolean;
var
  Bank, I, J: Integer;
  P: PByte;
begin
  Result := False;
  for Bank := 0 to 31 do
  begin
    P := PByte(Sp.RamBank(Bank));
    for I := 0 to SizeOf(TBank) - Length(Text) do
    begin
      J := 1;
      while (J <= Length(Text)) and (P[I + J - 1] = Ord(Text[J])) do Inc(J);
      if J > Length(Text) then Exit(True);
    end;
  end;
end;

procedure TestSnapshot;
var
  Sp: TSpectrum;
  MS: TMemoryStream;
begin
  WriteLn('--- snapshot');
  Sp := NewSam;
  try
    Out_(Sp, $00FB, $03);
    Sp.Poke($8000, $A5);
    Out_(Sp, $00F8 + 5 * $100, 99);
    Out_(Sp, $00F9, 77);
    Out_(Sp, $01FF, 8);
    Out_(Sp, $00FF, 200);
    Sp.Cpu.BC.W := $1234;
    MS := TMemoryStream.Create;
    try
      Sp.SAMSnapIO(MS, True);
      Out_(Sp, $00FB, $09);
      Sp.Poke($8000, 0);
      Out_(Sp, $00F8 + 5 * $100, 1);
      Sp.Cpu.BC.W := 0;
      MS.Position := 0;
      Sp.SAMSnapIO(MS, False);
      Check(Sp.Cpu.BC.W = $1234, 'the CPU comes back');
      Check(Sp.SAM.HMPR = 3, 'HMPR comes back');
      Check(Sp.SAM.Clut[5] = 99, 'the CLUT comes back');
      Check(Sp.SAM.LineInt = 77, 'the line interrupt comes back');
      Check(Sp.RamBank(3)^[0] = $A5, 'the RAM comes back');
    finally
      MS.Free;
    end;
  finally
    Sp.Free;
  end;
end;

{ ---- the real ROM and SAMDOS ---- }

{ The colour that covers most of the picture, and how many pixels it covers }
function Dominant(Sp: TSpectrum; out Count: Integer): LongWord;
var
  F: array of LongWord;
  I, J, Best, N: Integer;
  Seen: array of LongWord;
  Counts: array of Integer;
begin
  SetLength(F, FB_WIDTH * SCREEN_HEIGHT);
  Sp.CopyFrameBuffer(@F[0]);
  SetLength(Seen, 0);
  SetLength(Counts, 0);
  for I := 0 to High(F) do
  begin
    N := -1;
    for J := 0 to High(Seen) do
      if Seen[J] = (F[I] and $FFFFFF) then
      begin
        N := J;
        Break;
      end;
    if N < 0 then
    begin
      SetLength(Seen, Length(Seen) + 1);
      SetLength(Counts, Length(Counts) + 1);
      N := High(Seen);
      Seen[N] := F[I] and $FFFFFF;
    end;
    Inc(Counts[N]);
  end;
  Best := 0;
  for J := 1 to High(Seen) do
    if Counts[J] > Counts[Best] then Best := J;
  Count := Counts[Best];
  Result := Seen[Best];
end;

procedure TestRealRom(const Dir: string);
var
  Sp: TSpectrum;
  Disk: TDiskImage;
  Problem: TDiskProblem;
  Err, Path: string;
  I, Count: Integer;
  Colour: LongWord;
begin
  WriteLn('--- the real ROM');
  Sp := TSpectrum.Create(smSAM, Dir);
  try
    for I := 1 to 240 do Sp.RunFrame;
    Check(Sp.SAM.ScreenMode = 4, 'the ROM starts up in mode 4 (its first screen)');
    Check(Sp.SAM.Clut[7] <> 0, 'the ROM has loaded the CLUT');
    // A key takes it to BASIC
    Sp.TypeText('\n~', Err);
    for I := 1 to 300 do Sp.RunFrame;
    Sp.TypeText('mode 2\n', Err);
    for I := 1 to 300 do Sp.RunFrame;
    Check(Sp.SAM.ScreenMode = 2, 'BASIC answers: a typed MODE 2 changed the screen mode');
    // Interrupts are what keep the frame counter of BASIC going
    Check(Sp.Cpu.IFF1 and (Sp.Cpu.IM = 1), 'interrupts are on, mode 1');
    // Every character the keyboard can make, typed (a PC keyboard of any layout gets them by their
    // character): a REM line has them as they are
    Sp.TypeText('10 rem ?[]{}<>|^\\@#$%&''()*_/!"+-=;:,.AZ09\n', Err);
    for I := 1 to 600 do Sp.RunFrame;
    Check(RamHas(Sp, '?[]{}<>|^\@#$%&''()*_/!"+-=;:,.AZ09'), 'every character can be typed on the SAM''s keyboard');
    // The tape: SAVE a program with REC on, then LOAD it from the tape (after a reset) and run it
    Sp.Reset(True);
    for I := 1 to 250 do Sp.RunFrame;
    Sp.Recording := True;
    Sp.TypeText('\n~10 mode 2\nsave "prog"\n~~~~~~ ', Err);
    for I := 1 to 4000 do Sp.RunFrame;
    Sp.Recording := False;
    Check(Sp.Tape.Count > 10, Format('SAVE records the signal (%d blocks)', [Sp.Tape.Count]));
    // The tape goes through a .tzx file and back, as a user's would
    Sp.Tape.SaveTZX(IncludeTrailingPathDelimiter(Scratch) + 'sam-save.tzx');
    Sp.Tape.LoadFile(IncludeTrailingPathDelimiter(Scratch) + 'sam-save.tzx');
    Sp.AutoLoad(False);
    for I := 1 to 400 do Sp.RunFrame;
    for I := 1 to 1400 do Sp.RunFrame;
    Sp.TypeText('run\n', Err);
    for I := 1 to 600 do Sp.RunFrame;
    Check(Sp.SAM.ScreenMode = 2, 'the tape loads the program back and it runs (it switched to mode 2)');
    Path := IncludeTrailingPathDelimiter(Dir) + 'SAMDOSVersion2.0.dsk';
    if FileExists(Path) then
    begin
      Disk := LoadDiskImage(Path, Problem, Err);
      Check(Disk <> nil, 'the SAMDOS disk loads: ' + Err);
      if Disk <> nil then
      begin
        Sp.InsertDiskAt(0, Disk);
        Sp.AutoLoad(True);
        for I := 1 to 1200 do Sp.RunFrame;
        Colour := Dominant(Sp, Count);
        Check((Colour <> 0) and (Count > FB_WIDTH * SCREEN_HEIGHT div 2), 'SAMDOS boots: a menu on a coloured screen');
        Check(Sp.DiskAt(0) = Disk, 'the disk is still in drive 1');
      end;
    end
    else
      WriteLn('(no SAMDOSVersion2.0.dsk there: the boot test is skipped)');
  finally
    Sp.Free;
  end;
end;

{ A DAAD game on the SAM Coupe: its database is at 0100, with machine code 9; the Adventure
  Debugger's reader finds it, and the spy sees the interpreter run its entries }
procedure TestDaad(const Dir: string);
var
  Sp: TSpectrum;
  Dos, Game: TDiskImage;
  Problem: TDiskProblem;
  Err: string;
  I: Integer;
  Mem: TDaadMemory;
  G: TDaadGame;
  Map: array[0..$FFFF] of Byte;
  Seen: Boolean;
begin
  WriteLn('--- a DAAD game');
  Dos := LoadDiskImage(IncludeTrailingPathDelimiter(Dir) + 'SAMDOSVersion2.0.dsk', Problem, Err);
  Game := LoadDiskImage(IncludeTrailingPathDelimiter(Dir) + 'DAAD.MGT', Problem, Err);
  if (Dos = nil) or (Game = nil) then
  begin
    WriteLn('(no SAMDOSVersion2.0.dsk and DAAD.MGT there: skipped)');
    Dos.Free;
    Game.Free;
    Exit;
  end;
  Sp := TSpectrum.Create(smSAM, Dir);
  G := TDaadGame.Create;
  try
    Sp.InsertDiskAt(0, Dos);
    Sp.AutoLoad(True);
    for I := 1 to 900 do Sp.RunFrame;
    // SAMDOS is in memory: its menu's "exit to BASIC" (the first screen again: a key), and the game's disk
    Sp.InsertDiskAt(0, Game);
    Sp.TypeText('l~~~~~\n~~load "auto"\n', Err);
    for I := 1 to 2600 do Sp.RunFrame;
    for I := 0 to $FFFF do Mem[I] := Sp.PeekRam(I);
    Check(G.Load(Mem, MACHINE_SAM), 'the database is found (machine code 9)');
    Check(G.Base = $0100, 'it is at 0100');
    Check(G.Machine = MACHINE_SAM, 'the machine is the SAM Coupe''s');
    Check(G.NumProcesses = 7, Format('it has 7 processes (%d)', [G.NumProcesses]));
    Check(Length(G.Entries) > 0, Format('and entries to follow (%d)', [Length(G.Entries)]));
    // The interpreter's reads of the database are what the debugger watches
    G.BuildMap(@Map);
    Sp.SetDaadMap(@Map);
    Sp.TypeText('~x\n~i\n', Err);
    Seen := False;
    for I := 1 to 400 do
    begin
      Sp.RunFrame;
      if Sp.DaadEntry(0) >= 0 then Seen := True;
    end;
    Check(Seen, 'the spy sees the interpreter run an entry of the database');
  finally
    G.Free;
    Sp.Free;
  end;
end;

begin
  if ParamCount < 2 then
  begin
    WriteLn('usage: samtest <roms folder> <scratch folder> [<folder with samcoupe.rom and SAMDOSVersion2.0.dsk>]');
    Halt(2);
  end;
  RomsDir := ParamStr(1);
  Scratch := ParamStr(2);
  ForceDirectories(Scratch);
  TestPaging;
  TestInterruptsAndKeyboard;
  TestVideo;
  TestExtras;
  if ParamCount >= 3 then TestSamdos(ParamStr(3)) else TestSamdos('');
  TestWD1772;
  TestSAA;
  TestTapeScale;
  TestDiskFormats;
  TestMachines;
  TestSnapshot;
  if (ParamCount >= 3) and FileExists(IncludeTrailingPathDelimiter(ParamStr(3)) + 'samcoupe.rom') then
    begin
      TestRealRom(ParamStr(3));
      TestSamdosTrap(ParamStr(3));
      TestDaad(ParamStr(3));
    end
  else
    WriteLn('(no real ROM given: the ROM and SAMDOS tests are skipped)');
  if Failures > 0 then
  begin
    WriteLn(Failures, ' test(s) failed');
    Halt(1);
  end;
  WriteLn('SAM Coupe: all passed');
end.

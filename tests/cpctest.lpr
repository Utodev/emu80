{ cpctest: boots the Amstrad CPC models headless: the firmware's banner on
  screen, the memory map, the interrupt rate and the keyboard.

    cpctest <roms folder> [png folder] }
program cpctest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Models, Spectrum, Amstrad, ScreenCapture, Tape, DSK, Plus3FS, Snapshot, FramePresenter;

var
  Failures: Integer = 0;
  OutDir: string = '';

procedure Check(Cond: Boolean; const What: string);
begin
  if not Cond then
  begin
    WriteLn('FAIL  ', What);
    Inc(Failures);
  end
  else WriteLn('ok    ', What);
end;

procedure Frames(Sp: TSpectrum; N: Integer);
var
  I: Integer;
begin
  for I := 1 to N do Sp.RunFrame;
end;

{ Pixels of a colour in the picture }
function CountColour(const F: array of LongWord; C: LongWord): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(F) do if F[I] = C then Inc(Result);
end;

procedure Shot(Sp: TSpectrum; const Name: string);
var
  F: array of LongWord;
begin
  if OutDir = '' then Exit;
  SetLength(F, FB_WIDTH * SCREEN_HEIGHT);
  Sp.CopyFrameBuffer(@F[0]);
  SavePNG(F, OutDir + Name + '.png', 1, True);
end;

procedure Boot(M: TSpectrumModel; const Name: string);
var
  Sp: TSpectrum;
  F: array of LongWord;
  Blue, Yellow: Integer;
begin
  WriteLn('--- ', ModelInfo[M].Name);
  Sp := TSpectrum.Create(M, ParamStr(1));
  try
    Frames(Sp, 250);
    SetLength(F, FB_WIDTH * SCREEN_HEIGHT);
    Sp.CopyFrameBuffer(@F[0]);
    Shot(Sp, Name);
    Blue := CountColour(F, $FF000080);
    Yellow := CountColour(F, $FFFFFF00);
    WriteLn('blue=', Blue, ' yellow=', Yellow, ' PC=', IntToHex(Sp.Cpu.PC.W, 4));
    Check(Blue > 100000, Name + ': blue paper');
    Check(Yellow > 200, Name + ': yellow text');
  finally
    Sp.Free;
  end;
end;

{ Press a key for a few frames: Key is line * 8 + bit }
procedure Tap(Sp: TSpectrum; Key: Integer; Shift: Boolean = False);
begin
  if Shift then Sp.CPC.KeyMatrix[2] := Sp.CPC.KeyMatrix[2] and not (1 shl 5);
  Sp.CPC.KeyMatrix[Key div 8] := Sp.CPC.KeyMatrix[Key div 8] and not (1 shl (Key mod 8));
  Frames(Sp, 4);
  Sp.CPC.KeyMatrix[Key div 8] := Sp.CPC.KeyMatrix[Key div 8] or (1 shl (Key mod 8));
  Sp.CPC.KeyMatrix[2] := Sp.CPC.KeyMatrix[2] or (1 shl 5);
  Frames(Sp, 4);
end;

const
  LetterKeys: array[0..25] of Integer = (CPCK_A, CPCK_B, CPCK_C, CPCK_D, CPCK_E, CPCK_F, CPCK_G,
    CPCK_H, CPCK_I, CPCK_J, CPCK_K, CPCK_L, CPCK_M, CPCK_N, CPCK_O, CPCK_P, CPCK_Q, CPCK_R, CPCK_S,
    CPCK_T, CPCK_U, CPCK_V, CPCK_W, CPCK_X, CPCK_Y, CPCK_Z);
  DigitKeys: array[0..9] of Integer = (CPCK_0, CPCK_1, CPCK_2, CPCK_3, CPCK_4, CPCK_5, CPCK_6,
    CPCK_7, CPCK_8, CPCK_9);

procedure TypeText(Sp: TSpectrum; const Text: string);
var
  I: Integer;
  C: Char;
begin
  for I := 1 to Length(Text) do
  begin
    C := UpCase(Text[I]);
    case C of
      'A'..'Z': Tap(Sp, LetterKeys[Ord(C) - 65]);
      '0'..'9': Tap(Sp, DigitKeys[Ord(C) - 48]);
      ' ': Tap(Sp, CPCK_SPACE);
      ',': Tap(Sp, CPCK_COMMA);
      '.': Tap(Sp, CPCK_DOT);
      '|': Tap(Sp, CPCK_AT, True);
      '"': Tap(Sp, CPCK_2, True);
      #13: Tap(Sp, CPCK_RETURN);
    end;
  end;
end;

procedure TestKeyboardAndSound;
var
  Sp: TSpectrum;
  P: ^SmallInt;
  I, F, Nonzero: Integer;
begin
  WriteLn('--- keyboard, BASIC and sound (6128)');
  Sp := TSpectrum.Create(smCPC6128, ParamStr(1));
  try
    Frames(Sp, 200);
    TypeText(Sp, 'POKE 40960,7'#13);
    Frames(Sp, 20);
    Check(Sp.Peek($A000) = 7, 'typed POKE 40960,7 reached memory');
    TypeText(Sp, 'MODE 2'#13);
    Frames(Sp, 20);
    TypeText(Sp, 'PRINT 12345'#13);
    Frames(Sp, 20);
    Shot(Sp, 'cpc6128-mode2');
    TypeText(Sp, 'MODE 0'#13);
    TypeText(Sp, 'PEN 3'#13);
    TypeText(Sp, 'PRINT 99'#13);
    Frames(Sp, 20);
    Shot(Sp, 'cpc6128-mode0');
    Nonzero := 0;
    TypeText(Sp, 'SOUND 1,100,60'#13);
    for F := 1 to 20 do
    begin
      Sp.RunFrame;
      P := Sp.Samples;
      for I := 0 to Sp.SampleCount * 2 - 1 do
      begin
        if P^ <> 0 then Inc(Nonzero);
        Inc(P);
      end;
    end;
    WriteLn('non-zero samples: ', Nonzero);
    Check(Nonzero > 1000, 'SOUND makes the PSG produce samples');
  finally
    Sp.Free;
  end;
end;

procedure TestBanking;
var
  Sp: TSpectrum;
  T: Integer;
begin
  WriteLn('--- 6128 banking');
  Sp := TSpectrum.Create(smCPC6128, ParamStr(1));
  try
    Frames(Sp, 2);
    T := 0;
    // Everything RAM
    Sp.WritePort($7F00, $8C, T);          // lower and upper ROM off, mode 0
    Sp.WritePort($7F00, $C0, T);          // config 0: banks 0 1 2 3
    Sp.WriteMem($4000, $11, 0);
    Sp.WritePort($7F00, $C4, T);          // config 4: bank 4 at 4000
    Check(Sp.Peek($4000) <> $11, 'config 4 shows bank 4, not bank 1');
    Sp.WriteMem($4000, $22, 0);
    Sp.WritePort($7F00, $C0, T);
    Check(Sp.Peek($4000) = $11, 'config 0 shows bank 1 again');
    Sp.WritePort($7F00, $C4, T);
    Check(Sp.Peek($4000) = $22, 'bank 4 kept its byte');
    Sp.WritePort($7F00, $C2, T);          // config 2: banks 4 5 6 7
    Check(Sp.Peek($0000) = $22, 'config 2: bank 4 at 0000 (RAM, ROM off)');
    Sp.WritePort($7F00, $C0, T);
    Sp.WritePort($7F00, $88, T);          // lower ROM on (bit 2 clear), upper off
    Check(Sp.Peek($0000) = $01, 'lower ROM (LD BC,nn at 0000) when enabled');
    Sp.WriteMem($0000, $55, 0);
    Check(Sp.Peek($0000) = $01, 'writes under the ROM go to RAM, not ROM');
    Sp.WritePort($7F00, $8C, T);
    Check(Sp.Peek($0000) = $55, 'the RAM under the ROM kept the write');
  finally
    Sp.Free;
  end;
  Sp := TSpectrum.Create(smCPC464, ParamStr(1));
  try
    T := 0;
    Frames(Sp, 2);
    Sp.WritePort($7F00, $8C, T);
    Sp.WritePort($7F00, $C4, T);          // a 464 has no banking
    Sp.WriteMem($4000, $33, 0);
    Sp.WritePort($7F00, $C0, T);
    Check(Sp.Peek($4000) = $33, '464: banking port does nothing');
  finally
    Sp.Free;
  end;
end;

procedure TestTapeRoundTrip(M: TSpectrumModel);
var
  Sp: TSpectrum;
  Tmp: string;
  I: Integer;
begin
  WriteLn('--- CDT recording and loading (', ModelInfo[M].Name, ')');
  Tmp := GetTempDir + 'cpctest.cdt';
  Sp := TSpectrum.Create(M, ParamStr(1));
  try
    Frames(Sp, 200);
    if ModelInfo[M].HasFDC then TypeText(Sp, '|tape'#13);
    Frames(Sp, 20);
    TypeText(Sp, '10 poke 40960,77'#13);
    Sp.Recording := True;
    TypeText(Sp, 'save"t'#13);
    Frames(Sp, 60);
    TypeText(Sp, #13);
    for I := 1 to 20 do Frames(Sp, 50);
    Sp.Recording := False;
    WriteLn('recorded blocks: ', Sp.Tape.Count);
    Check(Sp.Tape.Count > 4, 'the recorder kept pulses');
    Sp.Tape.SaveTZX(Tmp);
  finally
    Sp.Free;
  end;
  Sp := TSpectrum.Create(M, ParamStr(1));
  try
    Sp.Tape.LoadFile(Tmp);
    WriteLn('reloaded blocks: ', Sp.Tape.Count);
    Frames(Sp, 200);
    if ModelInfo[M].HasFDC then TypeText(Sp, '|tape'#13);
    Frames(Sp, 20);
    TypeText(Sp, 'load"t'#13);
    Frames(Sp, 60);
    TypeText(Sp, #13);
    for I := 1 to 30 do Frames(Sp, 50);
    Shot(Sp, 'cpc-load-' + ModelKey(M));
    TypeText(Sp, 'run'#13);
    Frames(Sp, 30);
    Check(Sp.Peek($A000) = 77, 'the program saved to tape loaded and ran');
  finally
    Sp.Free;
  end;
end;

function Checksum(Sp: TSpectrum): LongWord;
var
  F: array of LongWord;
  I: Integer;
begin
  SetLength(F, FB_WIDTH * SCREEN_HEIGHT);
  Sp.CopyFrameBuffer(@F[0]);
  Result := 0;
  for I := 0 to High(F) do Result := Result * 31 + F[I];
end;

procedure TestSnapshot(M: TSpectrumModel);
var
  Sp: TSpectrum;
  Tmp: string;
  PC1, PC2: Word;
  C1, C2: LongWord;
  R1, R2: Byte;
begin
  WriteLn('--- snapshot (', ModelInfo[M].Name, ')');
  Tmp := GetTempDir + 'cpctest.pzs';
  Sp := TSpectrum.Create(M, ParamStr(1));
  try
    Frames(Sp, 200);
    TypeText(Sp, 'mode 1'#13);
    TypeText(Sp, 'for i=1 to 20:print i;:next'#13);
    Frames(Sp, 60);
    Sp.SaveOwnSnapshot(Tmp);
    TypeText(Sp, 'cls:print "different"'#13);
    Frames(Sp, 100);
    PC1 := Sp.Cpu.PC.W; C1 := Checksum(Sp); R1 := Sp.Cpu.R;
    Sp.LoadOwnSnapshot(Tmp);
    Frames(Sp, 3);
    Check(Checksum(Sp) <> C1, 'the restored picture is the one saved, not the later one');
    Sp.LoadOwnSnapshot(Tmp);
    TypeText(Sp, 'cls:print "different"'#13);
    Frames(Sp, 100);
    PC2 := Sp.Cpu.PC.W; C2 := Checksum(Sp); R2 := Sp.Cpu.R;
    Check((PC1 = PC2) and (C1 = C2) and (R1 = R2), 'run after restoring = the same run as the first time');
    Check(TSpectrum.OwnSnapshotModel(Tmp) = M, 'the snapshot names its model');
  finally
    Sp.Free;
  end;
end;

procedure TestModelSwitch;
var
  Sp: TSpectrum;
  Failed: Boolean;
begin
  WriteLn('--- switching between the Spectrum and the CPC');
  Sp := TSpectrum.Create(sm48K, ParamStr(1));
  try
    Frames(Sp, 100);
    Sp.SetModel(smCPC464);
    Frames(Sp, 250);
    Check(Sp.CPC <> nil, 'CPC hardware present on a CPC model');
    Sp.SetModel(sm128K);
    Frames(Sp, 100);
    Check(Sp.CPC = nil, 'no CPC hardware on a Spectrum');
    Sp.SetModel(smCPC6128);
    Frames(Sp, 250);
    Sp.SetModel(smPlus3);
    Frames(Sp, 100);
    Sp.SetModel(smCPC664);
    Frames(Sp, 250);
    Check(Sp.Peek($0000) = $01, '664 firmware at 0000 (LD BC,nn)');
    Sp.SetModel(sm48K);
    Frames(Sp, 100);
    Check(Sp.Peek($0000) = $F3, 'back to the 48K ROM');
    // Missing firmware: the error leaves the machine as it was
    Sp.RomFile[smCPC464, 0] := 'no-such-file.rom';
    Failed := False;
    try
      Sp.SetModel(smCPC464);
    except
      Failed := True;
    end;
    Check(Failed, 'a missing CPC firmware raises');
    Check(Sp.Model = sm48K, '... and the model is still the 48K');
    Frames(Sp, 50);
    Check(Sp.CPC = nil, '... with no CPC hardware');
  finally
    Sp.Free;
  end;
end;

procedure TestSpeed;
var
  Sp: TSpectrum;
  F: array of LongWord;
begin
  WriteLn('--- CPU speed x4');
  Sp := TSpectrum.Create(smCPC6128, ParamStr(1));
  try
    Sp.SetSpeed(4);
    Frames(Sp, 250);
    SetLength(F, FB_WIDTH * SCREEN_HEIGHT);
    Sp.CopyFrameBuffer(@F[0]);
    Check(CountColour(F, $FFFFFF00) > 200, 'the banner is on screen at 4x');
    TypeText(Sp, 'poke 40960,9'#13);
    Frames(Sp, 20);
    Check(Sp.Peek($A000) = 9, 'typing works at 4x');
  finally
    Sp.Free;
  end;
end;

procedure TestTapeFormats;
var
  T: TTape;
  Data: TBytes;
  Tmp: string;
  Failed: Boolean;
begin
  WriteLn('--- tape files: writing and reading TZX/CDT');
  Tmp := GetTempDir + 'cpctest-formats.cdt';
  T := TTape.Create;
  try
    // A Spectrum standard block, a pulse sequence and a pause
    SetLength(Data, 4);
    Data[0] := $FF; Data[1] := 1; Data[2] := 2; Data[3] := $FF xor 1 xor 2;
    T.AddBlock(Data);
    T.AddPulses([1000, 2000, 3000], 10);
    T.SaveTZX(Tmp);
    T.Clear;
    T.LoadFile(Tmp);
    Check(T.Count = 3, 'the CDT has the 3 blocks written (standard, pulses, pause): ' + IntToStr(T.Count));
    Check(T.CountKind(TZX_STANDARD) = 1, 'a Spectrum standard-speed block is counted (the CPC can''t load it)');
    Check(T.CountKind(TZX_PULSES) = 1, 'the pulse block came back');
    // A block that can't be written says so
    T.Clear;
    T.AddPulses([100], 0);
    Failed := False;
    try
      // CSW blocks can only come from a file: an unknown kind stands for it
      T.AddBlock(Data);
      T.Blocks[0].Kind := TZX_CSW;
      T.SaveTZX(Tmp);
    except
      Failed := True;
    end;
    Check(Failed, 'a CSW block can''t be saved as TZX: it says so');
  finally
    T.Free;
  end;
  DeleteFile(Tmp);
end;

procedure TestDisk(M: TSpectrumModel);
var
  Sp: TSpectrum;
  D: TDiskImage;
  Tmp: string;
begin
  WriteLn('--- disc: SAVE, and loading it again from the saved image (', ModelInfo[M].Name, ')');
  Tmp := GetTempDir + 'cpctest.dsk';
  Sp := TSpectrum.Create(M, ParamStr(1));
  try
    D := TDiskImage.Create;
    D.CreateCPCFormatted;
    Sp.FDC.InsertDisk(0, D);
    Sp.FDC.Timed := False;
    Frames(Sp, 250);
    TypeText(Sp, '10 poke 40960,66'#13);
    TypeText(Sp, 'save"prog'#13);
    Frames(Sp, 200);
    D.SaveToFile(Tmp);
  finally
    Sp.Free;
  end;
  Sp := TSpectrum.Create(M, ParamStr(1));
  try
    D := TDiskImage.Create;
    D.LoadFromFile(Tmp);
    Sp.FDC.InsertDisk(0, D);
    Sp.FDC.Timed := False;
    Frames(Sp, 250);
    TypeText(Sp, 'run"prog'#13);
    Frames(Sp, 200);
    Check(Sp.Peek($A000) = 66, 'the program SAVEd to the disc ran from the disc image');
  finally
    Sp.Free;
  end;
  DeleteFile(Tmp);
end;

{ The detection routine programs use (Rhino's, as in Amstrad Diagnostics), run
  with port accesses at the start of a VSYNC }
function DetectCRTC(Sp: TSpectrum): Integer;
var
  T, Guard: Integer;
  A, D: Byte;
begin
  T := 0;
  Sp.WritePort($BC0C, $0C, T);
  Sp.WritePort($BD00, $34, T);
  Guard := 0;
  while Sp.CPC.Vsync and (Guard < 2000000) do begin Sp.StepInstruction; Inc(Guard); end;
  while not Sp.CPC.Vsync and (Guard < 4000000) do begin Sp.StepInstruction; Inc(Guard); end;
  D := Sp.ReadPort($BE00, T);
  A := Sp.ReadPort($BF00, T);
  if A = D then
  begin
    Sp.WritePort($F782, $82, T);
    Sp.WritePort($F600, $0F, T);
    Sp.WritePort($F782, $82, T);
    if Sp.ReadPort($F600, T) = $0F then Result := 3 else Result := 4;
  end
  else if A = $34 then Result := 0
  else if (D and $1F) <> 0 then Result := 2
  else Result := 1;
end;

procedure TestCRTC;
var
  Sp: TSpectrum;
  Typ, T: Integer;
  F0, F1: array of LongWord;
  I, Diff: Integer;
begin
  WriteLn('--- CRTC types');
  Sp := TSpectrum.Create(smCPC6128, ParamStr(1));
  try
    Frames(Sp, 200);
    for Typ := 0 to 4 do
    begin
      Sp.CPC.CrtcType := Typ;
      Check(DetectCRTC(Sp) = Typ, 'a detection routine finds CRTC type ' + IntToStr(Typ));
    end;
    // Reading the registers
    T := 0;
    Sp.CPC.CrtcType := 0;
    Sp.WritePort($BC0C, $0C, T); Sp.WritePort($BD00, $3F, T);
    Check(Sp.ReadPort($BF00, T) = $3F, 'type 0 reads R12');
    Sp.WritePort($BC01, $01, T); 
    Sp.CPC.CrtcType := 1;
    Sp.WritePort($BC0C, $0C, T);
    Check(Sp.ReadPort($BF00, T) = 0, 'type 1 can''t read R12');
    Sp.WritePort($BC0E, $0E, T); Sp.WritePort($BD00, $2A, T);
    Check(Sp.ReadPort($BF00, T) = $2A, 'type 1 reads R14');
    // R3: the HD6845S keeps the VSYNC width, the UM6845R doesn't
    Sp.CPC.CrtcType := 0;
    Sp.WritePort($BC03, $03, T); Sp.WritePort($BD00, $48, T);
    Check(Sp.CPC.CrtcReg(3) = $48, 'type 0 keeps R3''s VSYNC width');
    Sp.CPC.CrtcType := 1;
    Check(Sp.CPC.CrtcReg(3) = $08, 'type 1 loses it (and gets it back going to type 0)');
    Sp.CPC.CrtcType := 0;
    Check(Sp.CPC.CrtcReg(3) = $48, 'the register written is kept when the type changes');
    // The picture is the same on every type with the firmware's values
    SetLength(F0, FB_WIDTH * SCREEN_HEIGHT);
    SetLength(F1, FB_WIDTH * SCREEN_HEIGHT);
    Sp.Reset(True);
    Sp.CPC.CrtcType := 0;
    Frames(Sp, 200);
    Sp.CopyFrameBuffer(@F0[0]);
    Sp.Reset(True);
    Sp.CPC.CrtcType := 2;
    Frames(Sp, 200);
    Sp.CopyFrameBuffer(@F1[0]);
    Diff := 0;
    for I := 0 to High(F0) do if F0[I] <> F1[I] then Inc(Diff);
    Check(Diff = 0, 'the firmware shows the same picture on type 0 and type 2');
  finally
    Sp.Free;
  end;
end;

{ A file made on the PC with an AMSDOS header, written into a CPC disc image
  the way the Disk browser does, loads and runs on the CPC }
procedure TestAmsdosFile;
var
  Sp: TSpectrum;
  D: TDiskImage;
  P: TPlus3Disk;
  Code, WithHdr: TBytes;
begin
  WriteLn('--- a binary with an AMSDOS header imported into a CPC disc');
  SetLength(Code, 6);
  Code[0] := $3E; Code[1] := 77;                  // LD A,77
  Code[2] := $32; Code[3] := $00; Code[4] := $70; // LD (7000),A
  Code[5] := $C9;                                 // RET
  WithHdr := AddAmsdosHeader(Code, 'PROG.BIN', $9000, $9000);
  Check(HasAmsdosHeader(WithHdr), 'the header it makes is recognised');
  Check(not HasAmsdosHeader(Code), 'and a file without one is not');
  Check(Length(WithHdr) = Length(Code) + 128, 'the header is 128 bytes');
  D := TDiskImage.Create;
  D.CreateCPCFormatted;
  P := TPlus3Disk.Create(D);
  P.WriteFile('PROG.BIN', WithHdr);
  P.Free;
  Sp := TSpectrum.Create(smCPC6128, ParamStr(1));
  try
    Sp.FDC.InsertDisk(0, D);
    Sp.FDC.Timed := False;
    Frames(Sp, 250);
    // BASIC keeps what is between its program and HIMEM: lower HIMEM under the code
    TypeText(Sp, 'memory 36863'#13);
    TypeText(Sp, 'load"prog.bin'#13);
    Frames(Sp, 400);
    Check(Sp.Peek($9000) = $3E, 'AMSDOS loaded it at the address in its header');
    TypeText(Sp, 'call 36864'#13);
    Frames(Sp, 200);
    Check(Sp.Peek($7000) = 77, 'and the code ran');
  finally
    Sp.Free;
  end;
end;

{ The .SCR the screenshot menu writes (16K behind an AMSDOS header) loads with
  LOAD on a CPC and gives the same picture }
procedure TestScreenFile;
var
  Sp: TSpectrum;
  D: TDiskImage;
  P: TPlus3Disk;
  F: TFileStream;
  B: TBytes;
  Tmp: string;
  Y, X, Same: Integer;
begin
  WriteLn('--- .SCR screenshot of the CPC');
  Tmp := GetTempDir + 'cpctest.scr';
  Sp := TSpectrum.Create(smCPC6128, ParamStr(1));
  try
    Frames(Sp, 250);
    TypeText(Sp, 'mode 1'#13);
    TypeText(Sp, 'for i=1 to 30:print "hello ";i;:next'#13);
    Frames(Sp, 300);
    SaveSCR(Sp, Tmp);
  finally
    Sp.Free;
  end;
  F := TFileStream.Create(Tmp, fmOpenRead);
  try
    SetLength(B, F.Size);
    F.ReadBuffer(B[0], F.Size);
  finally
    F.Free;
  end;
  Check((Length(B) = 128 + 16384) and HasAmsdosHeader(B), 'the file is an AMSDOS header and 16K');
  D := TDiskImage.Create;
  D.CreateCPCFormatted;
  P := TPlus3Disk.Create(D);
  P.WriteFile('SCREEN.SCR', B);
  P.Free;
  Sp := TSpectrum.Create(smCPC6128, ParamStr(1));
  try
    Sp.FDC.InsertDisk(0, D);
    Sp.FDC.Timed := False;
    Frames(Sp, 250);
    TypeText(Sp, 'mode 1'#13);
    TypeText(Sp, 'load"screen.scr"'#13);
    Frames(Sp, 500);
    // Character row 8 (rasters 0-7), which the new session's own text doesn't touch
    Same := 0;
    for Y := 64 to 71 do
      for X := 0 to 79 do
        if Sp.Peek($C000 + (Y and 7) * $800 + (Y shr 3) * 80 + X) = B[128 + (Y and 7) * $800 + (Y shr 3) * 80 + X] then
          Inc(Same);
    Check(Same = 8 * 80, 'loading it again gives the same screen memory (a row of text)');
  finally
    Sp.Free;
  end;
  DeleteFile(Tmp);
end;

{ A CPC .SNA: saved, loaded into another machine (even of another model, which
  the snapshot changes), the same picture and the same memory }
procedure TestSna(M: TSpectrumModel);
var
  Sp: TSpectrum;
  Tmp: string;
  C1: LongWord;
  Mem1: array[0..$FFFF] of Byte;
  I, Diff: Integer;
  F: TFileStream;
  Size: Int64;
begin
  WriteLn('--- CPC .SNA (', ModelInfo[M].Name, ')');
  Tmp := GetTempDir + 'cpctest.sna';
  Sp := TSpectrum.Create(M, ParamStr(1));
  try
    Frames(Sp, 250);
    TypeText(Sp, 'mode 1'#13);
    TypeText(Sp, 'ink 1,2:pen 1:print "snapshot ";:for i=1 to 5:print i;:next'#13);
    Frames(Sp, 200);
    SaveSNA(Sp, Tmp);
    C1 := Checksum(Sp);
    for I := 0 to $FFFF do Mem1[I] := Sp.Peek(I);
  finally
    Sp.Free;
  end;
  F := TFileStream.Create(Tmp, fmOpenRead);
  Size := F.Size;
  F.Free;
  if M = smCPC6128 then Check(Size = $100 + 128 * 1024, 'a 128K snapshot is 256 + 131072 bytes')
  else Check(Size = $100 + 64 * 1024, 'a 64K snapshot is 256 + 65536 bytes');
  Sp := TSpectrum.Create(sm48K, ParamStr(1));
  try
    LoadSNA(Sp, Tmp);
    Check(Sp.Model = M, 'loading it switches to the model it came from');
    Frames(Sp, 3);
    Diff := 0;
    for I := 0 to $FFFF do if Sp.Peek(I) <> Mem1[I] then Inc(Diff);
    Check(Diff < 400, 'the memory is the one saved (the screen and BASIC variables a few frames on: ' + IntToStr(Diff) + ' bytes differ)');
    Check(Checksum(Sp) = C1, 'the picture is the same, colours included');
    TypeText(Sp, 'print 6*7'#13);
    Frames(Sp, 100);
    Shot(Sp, 'cpc-sna-' + ModelKey(M));
  finally
    Sp.Free;
  end;
  DeleteFile(Tmp);
end;

{ The monochrome monitors (any machine): a white picture is green or orange, black
  stays black, and black and white is grey }
procedure TestMonitors;
var
  Cur, Prev: array of LongWord;
  Dest: array of LongWord;
  O: TPresentOptions;
  I: Integer;

  procedure Present;
  begin
    PresentFrame(@Cur[0], @Prev[0], False, 1, O, PByte(@Dest[0]), SCREEN_WIDTH * 4);
  end;

begin
  WriteLn('--- monitors');
  SetLength(Cur, FB_WIDTH * SCREEN_HEIGHT);
  SetLength(Prev, FB_WIDTH * SCREEN_HEIGHT);
  SetLength(Dest, SCREEN_WIDTH * SCREEN_HEIGHT);
  for I := 0 to High(Cur) do
  begin
    Cur[I] := $FFFFFFFF;
    Prev[I] := $FFFFFFFF;
  end;
  Cur[0] := $FF000000; Cur[1] := $FF000000;
  Cur[4] := $FFFF0000; Cur[5] := $FFFF0000;
  FillChar(O, SizeOf(O), 0);
  O.Monitor := 2;
  Present;
  Check(((Dest[7] shr 8) and $FF > 200) and ((Dest[7] shr 16) and $FF < 80), 'green phosphor: white is a bright green');
  Check((Dest[0] and $00FFFFFF) = 0, '... and black stays black');
  O.Monitor := 3;
  Present;
  Check(((Dest[7] shr 16) and $FF > 200) and ((Dest[7] and $FF) < 40) and ((Dest[7] shr 8) and $FF < (Dest[7] shr 16) and $FF),
    'orange phosphor: white is orange');
  O.Monitor := 1;
  Present;
  Check(((Dest[2] shr 16) and $FF) = ((Dest[2] shr 8) and $FF), 'black and white: a colour is grey');
  O.Monitor := 0;
  Present;
  Check((Dest[2] shr 16) and $FF > (Dest[2] shr 8) and $FF + 100, 'colour: it is left as it is');
end;

begin
  if ParamCount < 1 then
  begin
    WriteLn('usage: cpctest <roms folder> [png folder]');
    Halt(2);
  end;
  if ParamCount >= 2 then OutDir := IncludeTrailingPathDelimiter(ParamStr(2));
  Boot(smCPC464, 'cpc464');
  Boot(smCPC664, 'cpc664');
  Boot(smCPC6128, 'cpc6128');
  TestBanking;
  TestModelSwitch;
  TestSpeed;
  TestCRTC;
  TestMonitors;
  TestTapeFormats;
  TestDisk(smCPC664);
  TestDisk(smCPC6128);
  TestAmsdosFile;
  TestScreenFile;
  TestKeyboardAndSound;
  TestSna(smCPC464);
  TestSna(smCPC6128);
  TestSnapshot(smCPC464);
  TestSnapshot(smCPC6128);
  TestTapeRoundTrip(smCPC464);
  TestTapeRoundTrip(smCPC6128);
  if Failures > 0 then Halt(1);
end.

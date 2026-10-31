{ msxrun: boots an MSX2 on the real BIOS and checks that MSX BASIC starts: the
  BIOS must initialise the slots, find the RAM, program the VDP, and show its
  banner in Screen 0 (the text is read from the VDP's name table). The BIOS
  isn't distributed (roms/msx/MSX2.rom): without it the test says it can't run
  and exits with 0.

    msxrun <roms folder> }
program msxrun;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Models, Spectrum, MsxMachine, MsxVdp, DSK, DiskFormat, Tape;

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

function ScreenText(V: TMsxVdp): string;
var
  NT, Row, Col: Integer;
  C: Byte;
begin
  Result := '';
  NT := (V.Reg(2) and $F) shl 10;
  for Row := 0 to 23 do
  begin
    for Col := 0 to 39 do
    begin
      C := V.VramByte(NT + Row * 40 + Col);
      if (C >= 32) and (C < 127) then Result := Result + Chr(C) else Result := Result + ' ';
    end;
    Result := Result + LineEnding;
  end;
end;

{ MSX-DOS 1 from its disk, on the Philips disk interface: the date prompt, the A> prompt and DIR }
procedure TestDos(const RomsDir: string);
var
  Sp: TSpectrum;
  D: TDiskImage;
  P: TDiskProblem;
  E, Txt: string;
  I: Integer;
  Dsk: string;
begin
  Dsk := IncludeTrailingPathDelimiter(RomsDir) + 'msx' + DirectorySeparator + 'msxdos1.dsk';
  // (or the one of the test set: to_be_ignored/MSX/MSXDOS 1.DSK, next to the roms folder)
  if not FileExists(Dsk) then
    Dsk := ExtractFilePath(ExcludeTrailingPathDelimiter(ExpandFileName(RomsDir))) + 'to_be_ignored' + DirectorySeparator +
      'MSX' + DirectorySeparator + 'MSXDOS 1.DSK';
  if not FileExists(Dsk) or not FileExists(IncludeTrailingPathDelimiter(RomsDir) + 'msx' + DirectorySeparator + 'PHILIPSDISK.rom') then
  begin
    WriteLn('SKIP  roms/msx/PHILIPSDISK.rom or msxdos1.dsk is missing: the MSX-DOS boot test cannot run (not an emulator failure)');
    Exit;
  end;
  Sp := TSpectrum.Create(smMSX2, RomsDir);
  try
    Check(Sp.MSXHw.HasDisk, 'the disk interface is installed when its ROM is there');
    D := LoadDiskImage(Dsk, P, E);
    Check(D <> nil, 'the MSX-DOS 1 disk loads as a raw image');
    if D = nil then Exit;
    Sp.InsertDiskAt(0, D);
    Sp.Reset(True);
    for I := 1 to 1500 do Sp.RunFrame;
    Txt := ScreenText(Sp.MSXHw.Vdp);
    Check(Pos('MSX-DOS version 1.03', Txt) > 0, 'a DOS disk boots: the kernel loads COMMAND.COM from the disk (no date prompt)');
    Sp.TypeText('\n~\ndir\n', E);
    for I := 1 to 900 do Sp.RunFrame;
    Txt := ScreenText(Sp.MSXHw.Vdp);
    Check(Pos('A>DIR', Txt) > 0, 'and gets to the A> prompt, where DIR is typed');
    Check(Pos('COMMAND  COM', Txt) > 0, 'DIR lists the files of the FAT12 disk');
    Check(Pos('20 files', Txt) > 0, 'and counts them');
  finally
    Sp.Free;
  end;
end;

{ A BASIC program on a .cas tape (an ASCII file made here), loaded by the auto load: the date prompt of the disk ROM
  is answered, RUN"CAS:" typed, and the tape played as a signal (the MSX's BIOS reads it) }
procedure TestCas(const RomsDir: string);
const
  HDR: array[0..7] of Byte = ($1F, $A6, $DE, $BA, $CC, $13, $7D, $74);
var
  Sp: TSpectrum;
  S: TMemoryStream;
  B, Id: Byte;
  I: Integer;
  Prog: string;
  Txt: string;
begin
  S := TMemoryStream.Create;
  Sp := TSpectrum.Create(smMSX2, RomsDir);
  try
    S.WriteBuffer(HDR, 8);
    Id := $EA;
    for I := 1 to 10 do S.WriteBuffer(Id, 1);
    S.WriteBuffer(PChar('TEST  ')^, 6);            // 8 + 16 = 24: the next header on the boundary
    S.WriteBuffer(HDR, 8);
    Prog := '10 PRINT "CAS LOAD OK"'#13#10'20 END'#13#10;
    while Length(Prog) < 256 do Prog := Prog + #26;      // an ASCII file's blocks are 256 bytes, ended by ^Z
    S.WriteBuffer(Prog[1], Length(Prog));
    B := 0;
    while (S.Position mod 8) <> 0 do S.WriteBuffer(B, 1);
    S.Position := 0;
    Sp.Tape.LoadCASFromStream(S);
    Check(Sp.Tape.Count = 6, 'the tape has the blocks of a header and a data block');
    Sp.AutoLoad;
    for I := 1 to 9000 do Sp.RunFrame;
    Txt := ScreenText(Sp.MSXHw.Vdp);
    if Pos('CAS LOAD OK', Txt) = 0 then WriteLn(Txt);
    Check(Pos('CAS LOAD OK', Txt) > 0, 'RUN"CAS:" loads and runs a BASIC program from the tape signal');
  finally
    Sp.Free;
    S.Free;
  end;
end;

{ The MSX2: BASIC 2.1 from its ROMs (roms/msx/MSX2.rom and MSX2EXT.rom), its V9938 and 128K mapper; the BIOS's
  own CHGMOD (a few bytes of Z80 in RAM) puts the VDP in every screen mode }
procedure TestMsx2(const RomsDir: string);
var
  Sp: TSpectrum;
  I, Mode: Integer;
  Txt: string;
  Code: array[0..6] of Byte;
const
  MODES: array[0..4] of record Screen, Dm: Integer; end = ((Screen: 1; Dm: 0), (Screen: 2; Dm: 4),
    (Screen: 5; Dm: 12), (Screen: 7; Dm: 20), (Screen: 8; Dm: 28));
begin
  if not FileExists(IncludeTrailingPathDelimiter(RomsDir) + 'msx' + DirectorySeparator + 'MSX2.rom') or
     not FileExists(IncludeTrailingPathDelimiter(RomsDir) + 'msx' + DirectorySeparator + 'MSX2EXT.rom') then
  begin
    WriteLn('SKIP  roms/msx/MSX2.rom or MSX2EXT.rom is missing: the MSX2 boot test cannot run (not an emulator failure)');
    Exit;
  end;
  Sp := TSpectrum.Create(smMSX2, RomsDir);
  try
    Check(IsMSX2Model(Sp.Model), 'the model is an MSX2');
    Check(Sp.MSXHw.Vdp.VramSize = 131072, 'with 128K of VRAM');
    for I := 1 to 600 do Sp.RunFrame;
    Txt := ScreenText(Sp.MSXHw.Vdp);
    Check(Pos('MSX BASIC version 2.1', Txt) > 0, 'the BIOS starts MSX-BASIC 2.1 (it needs the sub-ROM and the mapper RAM)');
    Check(Pos('Ok', Txt) > 0, 'and shows its Ok prompt');
    Check(Sp.Peek($002D) = 1, 'the BIOS says it is an MSX2 (version byte 1)');
    for Mode := 0 to High(MODES) do
    begin
      // LD A,screen ; CALL 005Fh (CHGMOD) ; JR $
      Code[0] := $3E; Code[1] := MODES[Mode].Screen; Code[2] := $CD; Code[3] := $5F; Code[4] := 0; Code[5] := $18; Code[6] := $FE;
      for I := 0 to 6 do Sp.MSXHw.Write($C000 + I, Code[I]);
      Sp.Cpu.PC.W := $C000;
      for I := 1 to 150 do Sp.RunFrame;
      Check(Sp.MSXHw.Vdp.DisplayMode = MODES[Mode].Dm, Format('CHGMOD %d sets the display mode of SCREEN %d', [MODES[Mode].Screen, MODES[Mode].Screen]));
    end;
  finally
    Sp.Free;
  end;
end;

var
  Sp: TSpectrum;
  RomsDir, Txt, Err: string;
  I: Integer;
  Frame: array of LongWord;
  NonBlack: Integer;
begin
  UseOriginalMsxRoms;                   // (the emulator's default is the free ROMs)
  if ParamCount < 1 then
  begin
    WriteLn('usage: msxrun <roms folder>');
    Halt(2);
  end;
  RomsDir := ParamStr(1);
  if not FileExists(IncludeTrailingPathDelimiter(RomsDir) + 'msx' + DirectorySeparator + 'MSX2.rom') then
  begin
    WriteLn('SKIP  roms/msx/MSX2.rom is missing: the MSX2 boot test cannot run (not an emulator failure)');
    Halt(0);
  end;
  Sp := TSpectrum.Create(smMSX2, RomsDir);
  try
    Check(IsMSXModel(Sp.Model), 'the model is an MSX');
    for I := 1 to 560 do Sp.RunFrame;
    // (the MSX2 has a clock: the disk ROM does not ask for the date)
    Txt := ScreenText(Sp.MSXHw.Vdp);
    WriteLn(Txt);
    Check(Sp.MSXHw.Vdp.Mode = 2, 'the BIOS leaves the VDP in Text mode (Screen 0)');
    Check(Pos('MSX BASIC', Txt) > 0, 'the banner names MSX BASIC');
    Check(Pos('Ok', Txt) > 0, 'BASIC shows its Ok prompt');
    if Sp.MSXHw.HasDisk then
      Check(Pos('Disk BASIC version', Txt) > 0, 'with the disk interface it is Disk BASIC');
    SetLength(Frame, FB_WIDTH * SCREEN_HEIGHT);
    Sp.CopyFrameBuffer(@Frame[0]);
    NonBlack := 0;
    for I := 0 to High(Frame) do if Frame[I] <> VDP_PALETTE[Sp.MSXHw.Vdp.Backdrop] then Inc(NonBlack);
    Check(NonBlack > 500, 'the picture has text pixels over the backdrop');
  finally
    Sp.Free;
  end;
  TestDos(RomsDir);
  TestCas(RomsDir);
  TestMsx2(RomsDir);
  if Failures > 0 then
  begin
    WriteLn(Failures, ' MSX boot test(s) failed');
    Halt(1);
  end;
  WriteLn('MSX boot tests: all passed');
end.

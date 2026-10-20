{ nexthwtest: more of the ZX Spectrum Next's hardware, set up by writing
  its registers and ports directly (no distribution needed: the machine
  starts in its boot ROM, and configuration mode lets the test write the
  Multiface's ROM): the three AY chips, the extended keys (NR B0-B1), the
  Multiface's NMI, a .nex file with copper code and a file handle, the SPI
  flash, and a .pzs snapshot saved and loaded.

    nexthwtest <roms folder> <scratch folder> }
program nexthwtest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Models, Spectrum;

var
  Failures: Integer = 0;
  Sp: TSpectrum;

procedure Check(Cond: Boolean; const What: string);
begin
  if not Cond then
  begin
    WriteLn('FAIL  ', What);
    Inc(Failures);
  end;
end;

procedure Out_(Port: Word; Value: Byte);
var
  T: Integer;
begin
  T := Sp.Cpu.T;
  Sp.WritePort(Port, Value, T);
end;

function In_(Port: Word): Byte;
var
  T: Integer;
begin
  T := Sp.Cpu.T;
  Result := Sp.ReadPort(Port, T);
end;

procedure NextReg(Reg, Value: Byte);
begin
  Out_($243B, Reg);
  Out_($253B, Value);
end;

{ Bytes into memory as the CPU sees it (configuration mode: the SRAM) }
procedure Put(Addr: Word; const Bytes: array of Byte);
var
  I: Integer;
begin
  for I := 0 to High(Bytes) do Sp.WriteMem(Addr + I, Bytes[I], Sp.Cpu.T);
end;

{ Run until the CPU is back in its loop at 8100 }
procedure RunFrames(N: Integer);
var
  I: Integer;
begin
  for I := 1 to N do Sp.RunFrame;
end;

procedure TestAY;
begin
  // TurboSound on (NR 08 bit 1): FF, FE and FD choose the chips
  NextReg($08, $02);
  Out_($FFFD, $FF); Out_($FFFD, 0); Out_($BFFD, $55);
  Out_($FFFD, $FE); Out_($FFFD, 0); Out_($BFFD, $66);
  Out_($FFFD, $FD); Out_($FFFD, 0); Out_($BFFD, $77);
  Check(In_($BFF5) shr 6 = 1, 'port BFF5 says AY 2 is active');
  Check(In_($FFFD) = $77, 'third AY chip register');
  Out_($FFFD, $FE); Out_($FFFD, 0);
  Check(In_($FFFD) = $66, 'second AY chip register');
  Out_($FFFD, $FF); Out_($FFFD, 0);
  Check(In_($FFFD) = $55, 'first AY chip register');
end;

procedure TestKeys;
begin
  // UP: CAPS SHIFT + 7 in the matrix, and NR B0 bit 3
  Sp.ExtKeys := 1 shl EXT_UP;
  Check(Sp.NextRegister($B0) = $08, 'NR B0 has UP');
  Check(In_($EFFE) and $08 = 0, 'UP presses 7');
  Check(In_($FEFE) and $01 = 0, 'UP presses CAPS SHIFT');
  // NR 68 bit 4: only in NR B0, not in the matrix
  NextReg($68, $10);
  Check(In_($EFFE) and $1F = $1F, 'NR 68 bit 4 keeps UP out of the matrix');
  NextReg($68, $00);
  Sp.ExtKeys := 1 shl EXT_EDIT;
  Check(Sp.NextRegister($B1) = $40, 'NR B1 has EDIT');
  Check(In_($F7FE) and $01 = 0, 'EDIT presses 1');
  Sp.ExtKeys := 0;
end;

procedure TestMultiface;
const
  // At 0066 in its ROM: LD A,$AA / LD ($2000),A (its RAM) / LD A,($2000) /
  // LD ($8000),A / RETN
  MF_CODE: array[0..10] of Byte = ($3E, $AA, $32, $00, $20, $3A, $00, $20, $32, $00, $80);
begin
  // Configuration mode with SRAM bank 5 (the Multiface's) at 0000
  NextReg($03, $00);
  NextReg($04, 5);
  Put($0066, MF_CODE);
  Put($0066 + Length(MF_CODE), [$ED, $45]);
  // Out of it: the (empty) ROM at 0000, a loop at 8100
  NextReg($03, $33);
  Put($8100, [$18, $FE]);
  Sp.Cpu.PC.W := $8100;
  Sp.Cpu.SP.W := $9000;
  Sp.Cpu.IFF1 := False;
  Sp.Cpu.IFF2 := False;
  Sp.Poke($8000, 0);
  // The M1 button does nothing until NR 06 bit 3 lets it
  Sp.RequestNMI;
  RunFrames(1);
  Check(Sp.Peek($8000) = 0, 'M1 button off without NR 06 bit 3');
  NextReg($06, $08);
  Sp.RequestNMI;
  RunFrames(1);
  Check(Sp.Peek($8000) = $AA, 'the Multiface''s NMI ran its ROM, with its RAM at 2000');
  Check(Sp.Cpu.PC.W = $8100, 'back from the Multiface');
  Check(Sp.Peek($2000) = 0, 'the Multiface paged out after RETN');
  // NR 02 bit 3: the same by software
  Sp.Poke($8000, 0);
  NextReg($02, $08);
  RunFrames(1);
  Check(Sp.Peek($8000) = $AA, 'NR 02 bit 3 makes the Multiface''s NMI');
  Check(Sp.NextRegister($02) and $08 <> 0, 'NR 02 bit 3 reads back');
  NextReg($02, $00);
  Check(Sp.NextRegister($02) and $08 = 0, 'NR 02 bit 3 cleared');
end;

{ A V1.3 .nex: bank 2 with its code, copper code, the handle in BC and 4
  bytes of data after the banks }
procedure TestNex(const Dir: string);
const
  // LD A,C / LD IX,9000 / LD BC,4 / RST 8 / DB F_READ / JR $
  CODE: array[0..12] of Byte = ($79, $DD, $21, $00, $90, $01, $04, $00, $CF, $9D, $18, $FE, 0);
var
  H, Bank: TBytes;
  F: TFileStream;
  FileName: string;
begin
  SetLength(H, 512);
  FillChar(H[0], 512, 0);
  Move(PChar('NextV1.3')^, H[0], 8);
  H[9] := 1;                  // one bank
  H[10] := $80;               // no palette, no screen
  H[12] := $00; H[13] := $C0; // SP
  H[14] := $00; H[15] := $80; // PC
  H[18 + 2] := 1;             // bank 2
  H[139] := 0;                // entry bank
  H[140] := 1;                // the handle in BC
  H[144] := (512 + 2048) and $FF; H[145] := (512 + 2048) shr 8;
  H[153] := 1;                // copper code
  SetLength(Bank, 16384);
  FillChar(Bank[0], 16384, 0);
  Move(CODE[0], Bank[0], Length(CODE));
  FileName := IncludeTrailingPathDelimiter(Dir) + 'nexthwtest.nex';
  F := TFileStream.Create(FileName, fmCreate);
  try
    F.WriteBuffer(H[0], 512);
    // Copper: MOVE NR 4A,$1C then HALT (WAIT for a line that never comes)
    SetLength(H, 2048);
    FillChar(H[0], 2048, 0);
    H[0] := $4A; H[1] := $1C; H[2] := $FF; H[3] := $FF;
    F.WriteBuffer(H[0], 2048);
    F.WriteBuffer(Bank[0], 16384);
    F.WriteBuffer(PChar('DATA')^, 4);
  finally
    F.Free;
  end;
  Sp.LoadNex(FileName);
  Check(Sp.NextRegister($62) shr 6 = 3, '.nex copper code started');
  RunFrames(2);
  Check(Sp.NextRegister($4A) = $1C, '.nex copper code ran');
  Check((Sp.Peek($9000) = Ord('D')) and (Sp.Peek($9003) = Ord('A')), '.nex file read through its handle');
  Check(Sp.Cpu.BC.W = 4, 'F_READ says 4 bytes');
  DeleteFile(FileName);
end;

procedure SpiOut(const Bytes: array of Byte);
var
  I: Integer;
begin
  for I := 0 to High(Bytes) do Out_($EB, Bytes[I]);
end;

{ The SPI flash (port E7 bit 7, data at EB) and starting a core from it }
procedure TestFlash;
var
  Id: array[0..2] of Byte;
  I: Integer;
begin
  Out_($E7, $7F);                         // the flash alone
  Out_($EB, $9F);
  for I := 0 to 2 do Id[I] := In_($EB);
  Check((Id[0] = $EF) and (Id[2] = $18), 'flash: JEDEC id');
  Out_($E7, $FF);
  Out_($E7, $7F); Out_($EB, $06); Out_($E7, $FF);                 // write enable
  Out_($E7, $7F);
  SpiOut([$02, $08, $00, $00, $12, $34]);  // page program at 080000
  Out_($E7, $FF);
  Out_($E7, $7F);
  SpiOut([$03, $08, $00, $00]);
  Check((In_($EB) = $12) and (In_($EB) = $34), 'flash: page program and read');
  Out_($E7, $FF);
  // Two devices chosen: neither (the SD card isn't)
  Out_($E7, $7E);
  Out_($E7, $FF);
  // Starting another machine's core (slot 8): the Next starts again
  NextReg($10, $88);
  Check(Sp.ForeignCore = 8, 'starting an extra core is noticed');
  Sp.ForeignCore := -1;
end;

procedure TestSnapshot(const Dir: string);
var
  FileName: string;
begin
  FileName := IncludeTrailingPathDelimiter(Dir) + 'nexthwtest.pzs';
  Sp.Poke($8000, $12);
  NextReg($4A, $E0);
  NextReg($57, 30);            // MMU slot 7: page 30
  Sp.Poke($E000, $34);
  Sp.Cpu.HL.W := $5678;
  Sp.SaveOwnSnapshot(FileName);
  Sp.Poke($8000, 0);
  Sp.Poke($E000, 0);
  NextReg($4A, 0);
  NextReg($57, 1);
  Sp.Cpu.HL.W := 0;
  Sp.LoadOwnSnapshot(FileName);
  Check(Sp.Peek($8000) = $12, 'snapshot: memory');
  Check((Sp.NextMMU(7) = 30) and (Sp.Peek($E000) = $34), 'snapshot: MMU and its page');
  Check(Sp.NextRegister($4A) = $E0, 'snapshot: Next register');
  Check(Sp.Cpu.HL.W = $5678, 'snapshot: CPU registers');
  DeleteFile(FileName);
end;

begin
  Sp := TSpectrum.Create(sm48K, ParamStr(1));
  try
    Sp.NextFirmwareBoot := True;
    Sp.SetModel(smZXNext);
    TestAY;
    TestKeys;
    TestMultiface;
    TestNex(ParamStr(2));
    TestFlash;
    TestSnapshot(ParamStr(2));
    if Failures = 0 then
      WriteLn('ZX Spectrum Next AY, keys, Multiface, .nex and snapshots: all passed');
  finally
    Sp.Free;
  end;
  if Failures > 0 then Halt(1);
end.

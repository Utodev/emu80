{ msxtest: the MSX slot, memory mapper and I/O architecture (Msx.pas): primary
  and secondary slot selection, the inverted register at FFFFh, ROM and RAM
  devices, the memory mapper's segments, the debugger's description of an
  address and the port space. It needs no ROM.

    msxtest }
program msxtest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Msx, Tape, DSK, DiskFormat, FatFS, MsxDisk, MsxVdp, MsxMachine;

var
  Failures: Integer = 0;
  I_K: TMsxMapperKind;

procedure Check(Cond: Boolean; const What: string);
begin
  if Cond then WriteLn('ok    ', What)
  else
  begin
    WriteLn('FAIL  ', What);
    Inc(Failures);
  end;
end;

type
  TPortProbe = class
    Last: Byte;
    function Rd(Port: Byte): Byte;
    procedure Wr(Port: Byte; Value: Byte);
  end;

function TPortProbe.Rd(Port: Byte): Byte;
begin
  Result := Port xor $55;
end;

procedure TPortProbe.Wr(Port: Byte; Value: Byte);
begin
  Last := Value;
end;

procedure TestSlots;
var
  S: TMsxSlots;
  Bios, Sub: array[0..32767] of Byte;
  M: TMsxMapper;
  I: Integer;
begin
  for I := 0 to High(Bios) do Bios[I] := I and $FF;
  FillChar(Sub, SizeOf(Sub), $AA);
  M := TMsxMapper.Create(8);
  S := TMsxSlots.Create;
  try
    S.Install(0, 0, TMsxRom.Create('BIOS', Bios, 32768, 0));
    S.SetExpanded(3, True);
    S.Install(3, 0, TMsxMapperRam.Create(M));
    S.Install(3, 1, TMsxRom.Create('SubROM', Sub, 16384, 0));
    S.Install(1, 0, TMsxRam.Create('RAM', 65536, 0));
    S.Reset;

    Check(S.Read($0001) = 1, 'slot 0 BIOS visible in page 0 after reset');
    Check(S.Read($4002) = 2, 'BIOS second page at 4000h reads ROM offset 2');
    Check(S.Read($8000) = $FF, 'slot 0 beyond the 32K BIOS floats high');

    { page 1 -> primary slot 1 RAM }
    S.SetPrimaryReg($04);
    S.Write($4100, $5A);
    Check(S.Read($4100) = $5A, 'RAM in slot 1 stores a byte');
    S.SetPrimaryReg($00);
    Check(S.Read($4100) <> $5A, 'a different slot in the page hides the RAM');

    { expanded slot 3 in page 3: FFFF register is inverted }
    S.SetPrimaryReg($C0);
    S.Write($FFFF, $00);
    Check(S.Read($FFFF) = $FF, 'FFFFh reads back inverted (written 00 -> FF)');
    S.Write($FFFF, $40);
    Check(S.Read($FFFF) = $BF, 'FFFFh reads back inverted (written 40 -> BF)');
    Check(S.PageSub(3) = 1, 'bits 6-7 of the register (01) pick subslot 1 for page 3');
    Check(S.PageSlot(3) = 3, 'page 3 is primary slot 3');
    Check(S.IsExpanded(3) and (not S.IsExpanded(1)), 'only slot 3 is expanded');

    { sub-ROM in 3-1, shown in page 0 }
    S.SetPrimaryReg($C3);
    S.Write($FFFF, $01);
    Check(S.PageSlot(0) = 3, 'page 0 now points at primary slot 3');
    Check(S.PageSub(0) = 1, 'secondary register selects subslot 1 for page 0');
    Check(S.Read($0000) = $AA, 'subslot 3-1 holds the sub-ROM in page 0');
    Check(S.Describe($0003) = '3-1 SubROM +00003', 'Describe names slot, device and offset');
    Check(S.Read($4001) = 1, 'page 1 shows primary slot 0: the BIOS second 16K');
    Check(S.Describe($8000) = '0 BIOS', 'Describe beyond the ROM names no offset');
    S.SetPrimaryReg($C2);
    Check(S.Describe($0010) = '2 empty', 'Describe of a slot with nothing');

    { reading FFFF in a non-expanded slot reads memory, not a register }
    S.SetPrimaryReg($40);
    S.Write($FFFF, $12);
    Check(S.Read($FFFF) = $12, 'FFFFh of a non-expanded slot is ordinary memory (RAM in slot 1)');
    S.SetPrimaryReg($C0);
    S.Write($FFFF, $00);
    S.Write($C000, 1);
    Check(S.Read($C000) = 1, 'mapper RAM in 3-0 stores a byte');
  finally
    S.Free;
    M.Free;
  end;
end;

procedure TestMapper;
var
  M: TMsxMapper;
  S: TMsxSlots;
  Ram: TMsxMapperRam;
begin
  M := TMsxMapper.Create(8);
  S := TMsxSlots.Create;
  try
    Ram := TMsxMapperRam.Create(M);
    S.Install(3, 0, Ram);
    S.SetPrimaryReg($FF);
    S.Reset;
    S.SetPrimaryReg($FF);
    Check(M.Segment(0) = 3, 'mapper powers up with segments 3,2,1,0 (page 0)');
    Check(M.Segment(3) = 0, 'mapper powers up with segments 3,2,1,0 (page 3)');
    M.WritePort($FC, 5);
    S.Write($0000, $11);
    M.WritePort($FC, 6);
    S.Write($0000, $22);
    M.WritePort($FC, 5);
    Check(S.Read($0000) = $11, 'segment 5 keeps its own byte');
    M.WritePort($FC, 6);
    Check(S.Read($0000) = $22, 'segment 6 keeps its own byte');
    M.WritePort($FD, 6);
    Check(S.Read($4000) = $22, 'the same segment shows in another page');
    M.WritePort($FE, 13);
    Check(M.Segment(2) = 5, 'segment number is masked to the mapper size (13 and 7 = 5)');
    Check(M.ReadPort($FE) = (5 or $F8), 'unused high bits read as 1 on a 128K mapper');
    Check(Ram.PhysicalOffset($0003) = 6 * 16384 + 3, 'physical offset follows the segment');
    Check(S.Describe($0003) = '3 Mapper RAM +18003', 'Describe shows the mapper physical offset (slot not expanded)');
  finally
    S.Free;
    M.Free;
  end;
  try
    M := TMsxMapper.Create(6);
    M.Free;
    Check(False, 'a mapper of 6 segments is rejected');
  except
    on Exception do Check(True, 'a mapper of 6 segments is rejected');
  end;
end;

procedure TestCartridges;
var
  Rom: array of Byte;
  I: Integer;
  C: TMsxMegaRom;
  Code: array[0..65535] of Byte;
begin
  SetLength(Rom, 8 * 8192);
  for I := 0 to 7 do FillChar(Rom[I * 8192], 8192, I);   // bank N reads N everywhere
  C := TMsxMegaRom.Create('k', mpKonami, Rom[0], Length(Rom));
  try
    Check((C.Read($4000) = 0) and (C.Read($6000) = 1) and (C.Read($8000) = 2) and (C.Read($A000) = 3),
      'Konami starts with banks 0-3');
    C.Write($6000, 5);
    C.Write($8000, 6);
    C.Write($A000, 7);
    Check((C.Read($6000) = 5) and (C.Read($8000) = 6) and (C.Read($A000) = 7), 'Konami banks 1-3 are selectable');
    C.Write($4000, 4);
    Check(C.Read($4000) = 0, 'Konami bank 0 at 4000h is fixed');
    C.Write($8000, 9);
    Check(C.Read($8000) = 1, 'a bank number past the end wraps (9 mod 8)');
    Check(C.PhysicalOffset($8003) = 8195, 'physical offset follows the bank');
    Check(C.Read($C000) = $FF, 'nothing above BFFFh');
  finally
    C.Free;
  end;
  C := TMsxMegaRom.Create('a8', mpAscii8, Rom[0], Length(Rom));
  try
    C.Write($6000, 3); C.Write($6800, 4); C.Write($7000, 5); C.Write($7800, 6);
    Check((C.Read($4000) = 3) and (C.Read($6000) = 4) and (C.Read($8000) = 5) and (C.Read($A000) = 6),
      'ASCII8 selects the four banks at 6000h, 6800h, 7000h, 7800h');
    C.Write($8000, 1);
    Check(C.Read($8000) = 5, 'ASCII8 ignores writes where it has no register');
  finally
    C.Free;
  end;
  C := TMsxMegaRom.Create('a16', mpAscii16, Rom[0], Length(Rom));
  try
    C.Write($6000, 1); C.Write($7000, 3);
    Check((C.Read($4000) = 2) and (C.Read($6000) = 3) and (C.Read($8000) = 6) and (C.Read($A000) = 7),
      'ASCII16 selects two 16K banks (1 -> 8K banks 2,3; 3 -> 6,7)');
  finally
    C.Free;
  end;
  C := TMsxMegaRom.Create('scc', mpKonamiScc, Rom[0], Length(Rom));
  try
    C.Write($5000, 2); C.Write($7000, 3); C.Write($9000, 4); C.Write($B000, 5);
    Check((C.Read($4000) = 2) and (C.Read($6000) = 3) and (C.Read($8000) = 4) and (C.Read($A000) = 5),
      'Konami SCC selects at 5000h, 7000h, 9000h, B000h');
  finally
    C.Free;
  end;
  { The guess: by the writes the code does }
  FillChar(Code, SizeOf(Code), 0);
  Check(GuessMapper(Code, 32768) = mpPlain, '32K is a plain ROM');
  for I := 0 to 3 do
  begin
    Code[100 + I * 4] := $32; Code[101 + I * 4] := 0; Code[102 + I * 4] := $60 + I * 8;   // 6000, 6800, 7000, 7800
  end;
  Check(GuessMapper(Code, 65536) = mpAscii8, 'writes to 6000/6800/7000/7800 -> ASCII8');
  FillChar(Code, SizeOf(Code), 0);
  Code[100] := $32; Code[101] := 0; Code[102] := $60;
  Code[110] := $32; Code[111] := 0; Code[112] := $80;
  Code[120] := $32; Code[121] := 0; Code[122] := $A0;
  Check(GuessMapper(Code, 65536) = mpKonami, 'writes to 6000/8000/A000 -> Konami');
  FillChar(Code, SizeOf(Code), 0);
  Code[100] := $32; Code[101] := 0; Code[102] := $50;
  Code[110] := $32; Code[111] := 0; Code[112] := $90;
  Code[120] := $32; Code[121] := 0; Code[122] := $B0;
  Check(GuessMapper(Code, 65536) = mpKonamiScc, 'writes to 5000/9000/B000 -> Konami SCC');
  FillChar(Code, SizeOf(Code), 0);
  Code[100] := $32; Code[101] := 0; Code[102] := $60;
  Code[110] := $32; Code[111] := 0; Code[112] := $70;
  Check(GuessMapper(Code, 65536) = mpAscii16, 'writes to 6000 and 7000 only -> ASCII16');
  Check(MapperName(mpAscii8) = 'ascii8', 'mapper names');
  Check(MapperFromName('KonamiScc', I_K) and (I_K = mpKonamiScc), 'mapper names are read without case');
end;

procedure TestCas;
var
  T: TTape;
  S: TMemoryStream;
  B: array[0..7] of Byte;
  I: Integer;
  Id: Byte;
  Pad: array[0..5] of Byte;
begin
  T := TTape.Create;
  S := TMemoryStream.Create;
  try
    { header + 10 x D0 + name "TEST  " + 0 padding to 8; header + 3 data bytes }
    B[0] := $1F; B[1] := $A6; B[2] := $DE; B[3] := $BA; B[4] := $CC; B[5] := $13; B[6] := $7D; B[7] := $74;
    S.WriteBuffer(B, 8);
    Id := $D0;
    for I := 1 to 10 do S.WriteBuffer(Id, 1);
    S.WriteBuffer(PChar('TEST  ')^, 6);
    FillChar(Pad, SizeOf(Pad), 0);
    S.WriteBuffer(Pad, 6);                 // 8 + 16 + 6 = 30 -> the next header at 32
    S.WriteBuffer(Pad, 2);
    S.WriteBuffer(B, 8);
    Id := $55;
    S.WriteBuffer(Id, 1); Id := $AA; S.WriteBuffer(Id, 1); Id := $00; S.WriteBuffer(Id, 1);
    S.Position := 0;
    T.LoadCASFromStream(S);
    { per CAS block: a pause, a tone, the pulses }
    Check(T.Count = 6, 'a .cas of two blocks makes 6 tape blocks (pause, tone and data each)');
    Check(T[0].Kind = TZX_PAUSE, 'first a silence');
    Check((T[1].Kind = TZX_TONE) and (T[1].PilotCount = 9600), 'a file header has a long pilot tone (2 s)');
    Check(Pos('Binary', T[2].Description) = 1, 'the header block is described as a binary file');
    Check(Pos('TEST', T[2].Description) > 0, 'with its name');
    Check((T[4].Kind = TZX_TONE) and (T[4].PilotCount = 4800), 'a data block has a short pilot tone (1 s)');
    { 3 bytes: each 1 start bit (0: 2 pulses) + 8 data + 2 stop bits (1: 4 pulses each) }
    { 0x55 = 01010101: bits LSB first 1,0,1,0,1,0,1,0 -> 4 ones (16) + 4 zeros (8) }
    Check(Length(T[5].Pulses) > 3 * 11 * 2, 'the data block has pulses for its bits');
    Check(T[5].Pulses[0] = 1458, 'a start bit (0) is 2 pulses of 1200 Hz half cycles');
    Check(T[5].Pulses[2] = 729, 'then the first data bit of 0x55 (1) is 4 pulses of 2400 Hz half cycles');
  finally
    S.Free;
    T.Free;
  end;
end;

function SizeOfFile(const Name: string): Int64;
var
  S: TFileStream;
begin
  S := TFileStream.Create(Name, fmOpenRead);
  try
    Result := S.Size;
  finally
    S.Free;
  end;
end;

procedure TestMsxDisk;
var
  D: TDiskImage;
  St: TDiskImageStream;
  V: TFatVolume;
  Entries: TFatEntries;
  Data, Back: TBytes;
  I: Integer;
  F: string;
  Prob: TDiskProblem;
  Err: string;
  L: TDiskImage;
begin
  D := NewMsxDisk(True);
  try
    Check((D.Cylinders = 80) and (D.Sides = 2), 'a new MSX disk is 80 cylinders of 2 sides');
    Check(MsxGeometryOK(D), 'with 9 sectors of 512 bytes a track');
    St := TDiskImageStream.Create(D);
    try
      Check(St.Size = 737280, 'seen as a stream of 737280 bytes');
      V := TFatVolume.Create(St);
      try
        Check(Length(V.ListDir(0)) = 0, 'its root directory is empty');
        SetLength(Data, 5000);
        for I := 0 to High(Data) do Data[I] := (I * 7) and $FF;
        V.WriteFile(0, 'HELLO.BIN', Data);
        Entries := V.ListDir(0);
        Check((Length(Entries) = 1) and (Entries[0].Size = 5000), 'a file written to the root is listed with its size');
        Back := V.ReadFile(Entries[0]);
        Check((Length(Back) = 5000) and CompareMem(@Back[0], @Data[0], 5000), 'and reads back the same');
        Check(D.Modified, 'the disk is marked as changed');
      finally
        V.Free;
      end;
    finally
      St.Free;
    end;
    { saved raw and loaded again, the file is still there }
    F := GetTempDir + 'msxtest_disk.dsk';
    Check(SaveDiskImage(D, F) = '', 'a raw disk is saved');
    Check(SizeOfFile(F) = 737280, 'as 737280 raw bytes (not an extended DSK)');
    L := LoadDiskImage(F, Prob, Err);
    Check(L <> nil, 'and loads again');
    if L <> nil then
    begin
      St := TDiskImageStream.Create(L);
      try
        V := TFatVolume.Create(St);
        try
          Entries := V.ListDir(0);
          Check((Length(Entries) = 1) and (Entries[0].ShortName = 'HELLO.BIN'), 'with the file in it');
        finally
          V.Free;
        end;
      finally
        St.Free;
      end;
      Check(L.RawImage, 'and is still a raw image');
      L.Free;
    end;
    DeleteFile(F);
  finally
    D.Free;
  end;
  D := NewMsxDisk(False);
  try
    Check((D.Cylinders = 40) and (D.Sides = 2), 'a new 360K MSX disk is 40 cylinders of 2 sides');
  finally
    D.Free;
  end;
end;

{ The V9938: registers, the 128K of VRAM, the palette, the display modes and the commands }
procedure Reg(V: TMsxVdp; R, Value: Integer);
begin
  V.WriteControl(Value);
  V.WriteControl($80 or R);
end;

procedure SetAddr(V: TMsxVdp; Addr: Integer; Write: Boolean);
begin
  Reg(V, 14, Addr shr 14);
  V.WriteControl(Addr and $FF);
  if Write then V.WriteControl(((Addr shr 8) and $3F) or $40) else V.WriteControl((Addr shr 8) and $3F);
end;

procedure Cmd(V: TMsxVdp; SX, SY, DX, DY, NX, NY, Clr, Arg, Command: Integer);
begin
  Reg(V, 32, SX and $FF); Reg(V, 33, SX shr 8);
  Reg(V, 34, SY and $FF); Reg(V, 35, SY shr 8);
  Reg(V, 36, DX and $FF); Reg(V, 37, DX shr 8);
  Reg(V, 38, DY and $FF); Reg(V, 39, DY shr 8);
  Reg(V, 40, NX and $FF); Reg(V, 41, NX shr 8);
  Reg(V, 42, NY and $FF); Reg(V, 43, NY shr 8);
  Reg(V, 44, Clr);
  Reg(V, 45, Arg);
  Reg(V, 46, Command);
end;

procedure TestVdp;
var
  V: TMsxVdp;
  Out: TVdpOut;
  Wide: Boolean;
begin
  V := TMsxVdp.Create;
  try
    Check(V.VramSize = 131072, 'the V9938 has 128K of VRAM');
    { the 17-bit address: A16-A14 from R#14 }
    SetAddr(V, $1A000, True);
    V.WriteData($5A);
    V.WriteData($A5);
    Check((V.VramByte($1A000) = $5A) and (V.VramByte($1A001) = $A5), 'VRAM above 64K is written through R#14');
    Reg(V, 0, 6);                    // Graphics 4
    SetAddr(V, $3FFF, True);
    V.WriteData(1);
    V.WriteData(2);
    Check((V.VramByte($3FFF) = 1) and (V.VramByte($4000) = 2), 'in the V9938 modes the address carries into R#14 at the end of each 16K');
    Check(V.Reg(14) = 1, 'so R#14 moved on');
    Reg(V, 14, 0);
    Reg(V, 0, 0);                    // Graphics 1, the TMS9918A's: the address wraps at 16K, R#14 stays
    SetAddr(V, $3FFF, True);
    V.WriteData(1);
    V.WriteData(2);
    Check((V.VramByte($3FFF) = 1) and (V.VramByte(0) = 2) and (V.Reg(14) = 0), 'in the TMS9918A modes it wraps without carrying (the MSX1 games rely on it)');
    SetAddr(V, $1A000, False);
    Check((V.ReadData = $5A) and (V.ReadData = $A5), 'and reads back');
    { the modes }
    Reg(V, 1, 0);
    Reg(V, 0, $04); Check(V.DisplayMode = DM_G3, 'M4 = Graphics 3 (screen 4)');
    Reg(V, 0, $06); Check(V.DisplayMode = DM_G4, 'M4 M3 = Graphics 4 (screen 5)');
    Reg(V, 0, $08); Check(V.DisplayMode = DM_G5, 'M5 = Graphics 5 (screen 6)');
    Reg(V, 0, $0A); Check(V.DisplayMode = DM_G6, 'M5 M3 = Graphics 6 (screen 7)');
    Reg(V, 0, $0E); Check(V.DisplayMode = DM_G7, 'M5 M4 M3 = Graphics 7 (screen 8)');
    Reg(V, 0, $04); Reg(V, 1, $10); Check(V.DisplayMode = DM_T2, 'M4 M1 = Text 2 (80 columns)');
    Reg(V, 0, $02); Reg(V, 1, 0); Check(V.DisplayMode = DM_G2, 'M3 = Graphics 2 (screen 2)');
    Reg(V, 9, $80); Check(V.Lines = 212, 'R#9 bit 7: 212 lines');
    Reg(V, 9, 0); Check(V.Lines = 192, 'and 192 without it');
    { the palette: R#16 the index, port 9Ah two bytes (red and blue, green) }
    Reg(V, 16, 5);
    V.WritePalette($70);     // red 7, blue 0
    V.WritePalette($03);     // green 3
    Check(V.PaletteRGB(5) = $FF6D00, 'a palette write sets RGB: red 7, green 3, blue 0');
    Check(V.Reg(16) = 6, 'and moves to the next colour');
    { the indirect register port }
    Reg(V, 17, 7);          // R#7 and increment
    V.WriteIndirect($44);
    Check(V.Reg(7) = $44, 'port 9Bh writes the register R#17 names');
    Check((V.Reg(17) and $3F) = 8, 'and moves R#17 on');
    { Graphics 4: LMMV fills a rectangle; the pixels are 4 bits, the left one in the high nibble }
    Reg(V, 0, $06); Reg(V, 1, 0);
    Cmd(V, 0, 0, 10, 20, 5, 3, 9, 0, $80);        // LMMV IMP: 5x3 of colour 9 at (10,20)
    Check(V.VramByte(20 * 128 + 5) = $99, 'LMMV fills (a whole byte of two pixels)');
    Check(V.VramByte(22 * 128 + 7) and $F0 = $90, 'to the last row and the 5th pixel (left nibble of byte 7)');
    Check((V.VramByte(22 * 128 + 7) and $0F) = 0, 'and not the pixel beyond');
    Check(V.VramByte(23 * 128 + 5) = 0, 'nor the next row');
    { LMMM copies it, HMMV fills bytes }
    Cmd(V, 10, 20, 100, 50, 5, 3, 0, 0, $90);      // LMMM IMP
    Check(V.VramByte(50 * 128 + 50) = $99, 'LMMM copies a rectangle');
    Cmd(V, 0, 0, 0, 100, 8, 2, $37, 0, $C0);       // HMMV: bytes of $37
    Check((V.VramByte(100 * 128) = $37) and (V.VramByte(101 * 128 + 3) = $37), 'HMMV fills with the byte');
    { PSET and POINT with the logical operations }
    Cmd(V, 0, 0, 200, 5, 0, 0, 6, 0, $50);         // PSET
    Cmd(V, 200, 5, 0, 0, 0, 0, 0, 0, $40);         // POINT: the colour goes to S#7
    Reg(V, 15, 7);
    Check(V.ReadStatus = 6, 'PSET and POINT: the colour read back is 6');
    Reg(V, 15, 0);
    Cmd(V, 0, 0, 200, 5, 0, 0, 3, 0, $52);         // PSET OR: 6 or 3 = 7
    Cmd(V, 200, 5, 0, 0, 0, 0, 0, 0, $40);
    Reg(V, 15, 7);
    Check(V.ReadStatus = 7, 'logical OR: 6 or 3 = 7');
    Reg(V, 15, 0);
    { LINE: from (0,150) 30 long, horizontal (the long side along X) }
    Cmd(V, 0, 0, 0, 150, 30, 0, 12, 0, $70);
    Check((V.VramByte(150 * 128) = $CC) and (V.VramByte(150 * 128 + 14) = $CC), 'LINE draws along X');
    { Graphics 7: one byte a pixel, and the VRAM interleaved (the byte at A is at (A and 1) * 64K + A div 2) }
    Reg(V, 0, $0E);
    Cmd(V, 0, 0, 3, 2, 4, 1, $E0, 0, $80);
    Check((V.VramByte($10000 + ((2 * 256 + 3) div 2)) = $E0) and (V.VramByte((2 * 256 + 4) div 2) = $E0),
      'Graphics 7 LMMV: a pixel a byte, in the interleaved VRAM');
    { the picture: a Graphics 4 line, 256 pixels doubled }
    Reg(V, 0, $06); Reg(V, 1, $40);
    Reg(V, 2, $1F);
    Cmd(V, 0, 0, 0, 0, 4, 1, 5, 0, $80);
    V.RenderLine(0, Out, Wide);
    Check(not Wide, 'a Graphics 4 line is 256 pixels (each shown twice)');
    Check((Out[0] = V.PaletteRGB(5)) and (Out[1] = V.PaletteRGB(5)) and (Out[8] <> V.PaletteRGB(5)), 'with the colour of the pixels');
    { a PAL V9938 interrupt: the line interrupt flag is set at the line of R#19 }
    Reg(V, 19, 100);
    V.LineReached(99);
    Reg(V, 15, 1);
    Check((V.ReadStatus and 1) = 0, 'no line interrupt flag before the line');
    V.LineReached(100);
    Reg(V, 15, 1);
    Check((V.ReadStatus and 1) = 1, 'the line interrupt flag (S#1 bit 0) is set at the line of R#19');
    Reg(V, 15, 1);
    Check((V.ReadStatus and 1) = 0, 'and clears when read');
  finally
    V.Free;
  end;
end;

procedure TestIO;
var
  IO: TMsxIO;
  P: TPortProbe;
begin
  IO := TMsxIO.Create;
  P := TPortProbe.Create;
  try
    IO.Clear;
    Check(IO.Read($99) = $FF, 'an unmapped port reads FFh');
    IO.Map($98, 2, @P.Rd, @P.Wr);
    Check(IO.Read($98) = $98 xor $55, 'mapped reader for the first port');
    Check(IO.Read($99) = $99 xor $55, 'mapped reader for the second port');
    IO.Write($99, $77);
    Check(P.Last = $77, 'mapped writer gets the value');
    Check(IO.Read($9A) = $FF, 'the port after the range is not mapped');
  finally
    P.Free;
    IO.Free;
  end;
end;

{ The MSX1 slot layout (Compat): no expanded slot, so FFFFh is RAM as it is in an MSX1 }
procedure TestCompatLayout;
var
  M: TMsxMachine;
begin
  M := TMsxMachine.Create;
  try
    M.SetPortValue($0000, $FF);                  // every page in slot 3
    M.Write($FFFF, $55);
    Check(M.Read($FFFF) = $AA, 'the MSX2 layout: FFFFh is the subslot register (reads back inverted)');
    M.SetCompat(True);
    Check(M.Compat, 'the MSX1 layout is on');
    M.SetPortValue($0000, $FF);
    M.Write($FFFF, $55);
    Check(M.Read($FFFF) = $55, 'the MSX1 layout: FFFFh is RAM');
    M.Write($8000, $12);
    Check(M.Read($8000) = $12, 'the MSX1 layout: RAM in page 2');
    M.SetCompat(False);
    M.SetPortValue($0000, $FF);
    M.Write($FFFF, $00);
    Check(M.Read($FFFF) = $FF, 'back to the MSX2 layout: FFFFh is the subslot register again');
  finally
    M.Free;
  end;
end;

begin
  TestSlots;
  TestCompatLayout;
  TestMapper;
  TestCartridges;
  TestVdp;
  TestCas;
  TestMsxDisk;
  TestIO;
  if Failures > 0 then
  begin
    WriteLn(Failures, ' MSX test(s) failed');
    Halt(1);
  end;
  WriteLn('MSX architecture tests: all passed');
end.

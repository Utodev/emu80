{ MsxVdp: the video chip of the MSX2, the Yamaha V9938, which includes the TMS9918A's modes (Graphics I and II,
  Text and Multicolor, 32 sprites with collision and the fifth sprite flag,
  a status register and the frame interrupt)
  (128K of VRAM, 47 registers and 10 status registers, the palette of 512
  colours, Graphics 3 to 7 and Text 2, sprites of mode 2, the line interrupt,
  vertical scroll and the commands that move, fill and draw in VRAM).

  Written from the TMS9918A and V9938 data books and the MSX Technical Data
  Book, and checked against how openMSX behaves (the read-ahead latch, the
  two-byte protocol of the control port, the status flags that clear when read,
  the interleaved VRAM of Graphics 6 and 7); no code of openMSX is used.

  The chip draws a line at a time: RenderLine gives the 512 pixels of the line
  as RGB (256-pixel modes twice each; Wide says it has 512 of its own), and
  the machine decides where in the frame that line comes. The commands are
  executed at once (the CE flag is never seen set, except while the CPU is
  still to send or take data), which is faster than the real chip: the
  architecture keeps the command state apart so that a timed version can come. }
unit MsxVdp;

{$mode objfpc}{$H+}

interface

const
  VDP_VRAM_SIZE = $4000;           // the TMS9918A's
  V9938_VRAM_SIZE = $20000;        // the MSX2 of this project: 128K
  VDP_LINE_WIDTH = 256;
  VDP_SCREEN_LINES = 192;

  { The display modes: M5 M4 M3 M1 M2 as bits 4..0 }
  DM_G1 = 0;  DM_MC = 1;  DM_T1 = 2;  DM_G2 = 4;  DM_G3 = 8;  DM_T2 = 10;
  DM_G4 = 12; DM_G5 = 16; DM_G6 = 20; DM_G7 = 28;

  { The TMS9918A's 15 colours as RGB; colour 0 is transparent }
  VDP_PALETTE: array[0..15] of LongWord = (
    $000000, $000000, $21C842, $5EDC78, $5455ED, $7D76FC, $D4524D, $42EBF5,
    $FC5554, $FF7978, $D4C154, $E6CE80, $21B03B, $C95BBA, $CCCCCC, $FFFFFF);

type
  TVdpLine = array[0..VDP_LINE_WIDTH - 1] of Byte;
  TVdpOut = array[0..511] of LongWord;
  TVdpIdx = array[0..511] of Byte;

  TMsxVdp = class
  private
    FVram: array of Byte;
    FVramMask: Integer;
    FReg: array[0..63] of Byte;
    FStatus: array[0..9] of Byte;
    FAddr: Integer;                   // the address within the 16K the control port sets; R#14 gives the rest
    FLatch: Boolean;                  // the first byte of a control-port pair has been written
    FFirst: Byte;
    FReadAhead: Byte;
    FPalRGB: array[0..15] of LongWord;
    FPalLatch: Boolean;
    FPalFirst: Byte;
    FVBlank, FHBlank: Boolean;        // what the beam is doing, for status register 2
    FCmdRunning: Boolean;             // a command waits for the CPU's data (HMMC, LMMC) or for it to take data (LMCM)
    FCmdKind: Byte;
    FCmdOp: Byte;
    FCmdX, FCmdY, FCmdNX, FCmdNY: Integer;   // where the transfer is, and what is left of it
    FCmdDX, FCmdDirX, FCmdDirY: Integer;
    FTransferReady: Boolean;
    FCmdData: Byte;
    FCmdCount: Integer;
    function PhysAddr(Addr: Integer): Integer;
    function VramRead(Addr: Integer): Byte;
    procedure VramWrite(Addr: Integer; Value: Byte);
    function NameMask: Integer;
    { The TMS9918A's modes, where the address wraps at 16K without carrying into R#14 (the games made for the MSX1 rely on it) }
    function IsTmsMode: Boolean;
    procedure DrawSprites1(Y: Integer; var Idx: TVdpIdx; var Behind: TVdpIdx);
    procedure DrawSprites2(Y: Integer; var Idx: TVdpIdx; var Behind: TVdpIdx);
    procedure WriteRegister(Reg: Integer; Value: Byte);
    { Commands }
    function ScreenWidth: Integer;
    function BitsPerPixel: Integer;
    function PixelAddr(X, Y: Integer; out Shift: Integer): Integer;
    function GetPixel(X, Y: Integer): Byte;
    procedure PutPixel(X, Y: Integer; Color, Op: Byte);
    function GetByte(X, Y: Integer): Byte;
    procedure PutByte(X, Y: Integer; Value: Byte);
    procedure StartCommand(Value: Byte);
    procedure FinishCommand;
    procedure CmdFill(Logical: Boolean);
    procedure CmdCopy(Logical: Boolean);
    procedure CmdYmmm;
    procedure CmdLine;
    procedure CmdSearch;
    procedure CmdTransferNext(Value: Byte);
    function Reg16(Low: Integer; Mask: Integer): Integer;
    procedure SetReg16(Low: Integer; Value: Integer);
  public
    constructor Create;
    procedure Reset;
    procedure WriteData(Value: Byte);
    function ReadData: Byte;
    procedure WriteControl(Value: Byte);
    function ReadStatus: Byte;
    { The V9938's palette port (9Ah) and indirect register port (9Bh) }
    procedure WritePalette(Value: Byte);
    procedure WriteIndirect(Value: Byte);
    { The frame flag: set when the beam enters the bottom border }
    procedure SetFrameFlag;
    { The line interrupt: the beam is at display line Y (the V9938 compares it with R#19) }
    procedure LineReached(Y: Integer);
    function IntLine: Boolean;
    { Whether the screen is shown (register 1 bit 6); when not, only the backdrop }
    function DisplayOn: Boolean;
    function Backdrop: Byte;
    function BackdropRGB: LongWord;
    { Draws line Y (0 to Lines - 1) of the picture as RGB into Out; Wide: it is 512 pixels (else 256 twice) }
    procedure RenderLine(Y: Integer; var Out: TVdpOut; out Wide: Boolean);
    function Reg(I: Integer): Byte;
    { The debugger's view: a register changed as an OUT would, and a status register read without side effects }
    procedure SetReg(I: Integer; Value: Byte);
    procedure SetPalEntry(Index: Integer; R, G, B: Integer);
    function StatusReg(I: Integer): Byte;
    function VramByte(Addr: Integer): Byte;
    procedure PokeVram(Addr: Integer; Value: Byte);
    { 0 Graphics I, 1 Graphics II, 2 Text, 3 Multicolor (the TMS9918A's modes); 4 and up: the V9938's }
    function Mode: Integer;
    function DisplayMode: Integer;
    function VramSize: Integer;
    function Status: Byte;
    function AddressRegister: Word;
    { Lines of picture: 192, or 212 on the V9938 with R#9 bit 7 }
    function Lines: Integer;
    function PaletteRGB(Index: Integer): LongWord;
    property CommandsStarted: Integer read FCmdCount;
    property VBlank: Boolean read FVBlank write FVBlank;
    property HBlank: Boolean read FHBlank write FHBlank;
  end;

implementation

uses
  SysUtils;

const
  { The 3-bit levels of the V9938's palette as 8 bits }
  LEVEL: array[0..7] of Byte = (0, 36, 73, 109, 146, 182, 219, 255);

constructor TMsxVdp.Create;
begin
  inherited Create;
  SetLength(FVram, V9938_VRAM_SIZE);
  FVramMask := Length(FVram) - 1;
  Reset;
end;

procedure TMsxVdp.Reset;
var
  I: Integer;
begin
  FillChar(FReg, SizeOf(FReg), 0);
  FillChar(FStatus, SizeOf(FStatus), 0);
  FAddr := 0;
  FLatch := False;
  FFirst := 0;
  FReadAhead := 0;
  FPalLatch := False;
  FCmdRunning := False;
  FTransferReady := False;
  { The palette at power on: the TMS9918A's colours, until the BIOS programs its own }
  for I := 0 to 15 do FPalRGB[I] := VDP_PALETTE[I];
end;

function TMsxVdp.VramSize: Integer;
begin
  Result := Length(FVram);
end;

{ In Graphics 6 and 7 the two 64K halves of the VRAM are interleaved: the byte at address A is in the
  half that bit 0 of A says, at A div 2 }
function TMsxVdp.PhysAddr(Addr: Integer): Integer;
begin
  Addr := Addr and FVramMask;
  if ((DisplayMode = DM_G6) or (DisplayMode = DM_G7)) then
    Result := ((Addr and 1) shl 16) or (Addr shr 1)
  else
    Result := Addr;
end;

function TMsxVdp.VramRead(Addr: Integer): Byte;
begin
  Result := FVram[PhysAddr(Addr)];
end;

procedure TMsxVdp.VramWrite(Addr: Integer; Value: Byte);
begin
  FVram[PhysAddr(Addr)] := Value;
end;

function TMsxVdp.DisplayMode: Integer;
begin
  { M5 M4 M3 are R#0 bits 3-1 (as mode bits 4-2), M1 and M2 R#1 bits 4 and 3 (as bits 1 and 0) }
  Result := ((FReg[0] and $0E) shl 1) or ((FReg[1] and $18) shr 3);
end;

function TMsxVdp.Mode: Integer;
begin
  case DisplayMode of
    DM_G1: Result := 0;
    DM_G2: Result := 1;
    DM_T1: Result := 2;
    DM_MC: Result := 3;
  else
    Result := 4 + DisplayMode;
  end;
end;

function TMsxVdp.IsTmsMode: Boolean;
begin
  Result := DisplayMode in [DM_G1, DM_G2, DM_T1, DM_MC];
end;

function TMsxVdp.NameMask: Integer;
begin
  Result := $7F;
end;

function TMsxVdp.Lines: Integer;
begin
  if (FReg[9] and $80) <> 0 then Result := 212 else Result := 192;
end;

{ The CPU's side: the 17-bit address is A16-A14 from R#14 and A13-A0 from the control port }
procedure TMsxVdp.WriteData(Value: Byte);
begin
  FLatch := False;
  FReadAhead := Value;
  VramWrite(((FReg[14] and 7) shl 14) or FAddr, Value);
  FAddr := (FAddr + 1) and $3FFF;
  if (FAddr = 0) and not IsTmsMode then FReg[14] := (FReg[14] + 1) and 7;
end;

function TMsxVdp.ReadData: Byte;
begin
  FLatch := False;
  Result := FReadAhead;
  FReadAhead := VramRead(((FReg[14] and 7) shl 14) or FAddr);
  FAddr := (FAddr + 1) and $3FFF;
  if (FAddr = 0) and not IsTmsMode then FReg[14] := (FReg[14] + 1) and 7;
end;

procedure TMsxVdp.WriteRegister(Reg: Integer; Value: Byte);
begin
  Reg := Reg and 63;
  if Reg = 44 then
  begin
    // The data register of the transfer commands: it is the next byte when one is waiting for it
    FReg[44] := Value;
    if FCmdRunning and FTransferReady and ((FCmdKind = $B) or (FCmdKind = $F)) then CmdTransferNext(Value);
    Exit;
  end;
  FReg[Reg] := Value;
  if Reg = 46 then StartCommand(Value);
end;

procedure TMsxVdp.WriteControl(Value: Byte);
begin
  if not FLatch then
  begin
    FFirst := Value;
    FLatch := True;
    Exit;
  end;
  FLatch := False;
  if (Value and $80) <> 0 then
    WriteRegister(Value and $3F, FFirst)
  else
  begin
    FAddr := (Integer(Value and $3F) shl 8) or FFirst;
    if (Value and $40) = 0 then
    begin
      // Read setup: the byte is fetched at once and the address moves on
      FReadAhead := VramRead(((FReg[14] and 7) shl 14) or FAddr);
      FAddr := (FAddr + 1) and $3FFF;
      if (FAddr = 0) and not IsTmsMode then FReg[14] := (FReg[14] + 1) and 7;
    end;
  end;
end;

procedure TMsxVdp.WriteIndirect(Value: Byte);
var
  R: Integer;
begin
  R := FReg[17] and $3F;
  WriteRegister(R, Value);
  if (FReg[17] and $80) = 0 then FReg[17] := (FReg[17] and $C0) or ((R + 1) and $3F);
end;

procedure TMsxVdp.SetPalEntry(Index: Integer; R, G, B: Integer);
begin
  FPalRGB[Index] := (LongWord(LEVEL[R and 7]) shl 16) or (LongWord(LEVEL[G and 7]) shl 8) or LEVEL[B and 7];
end;

procedure TMsxVdp.WritePalette(Value: Byte);
var
  I: Integer;
begin
  I := FReg[16] and 15;
  if not FPalLatch then
  begin
    FPalFirst := Value;
    FPalLatch := True;
    Exit;
  end;
  FPalLatch := False;
  SetPalEntry(I, (FPalFirst shr 4) and 7, Value and 7, FPalFirst and 7);
  FReg[16] := (I + 1) and 15;
end;

function TMsxVdp.PaletteRGB(Index: Integer): LongWord;
begin
  Result := FPalRGB[Index and 15];
end;

function TMsxVdp.ReadStatus: Byte;
var
  S: Integer;
begin
  FLatch := False;
  S := FReg[15] and 15;
  case S of
    0:
      begin
        Result := FStatus[0];
        FStatus[0] := FStatus[0] and $1F;
      end;
    1:
      begin
        Result := FStatus[1] and 1;          // FH; the chip's ID (V9938) is 0
        FStatus[1] := FStatus[1] and not 1;
      end;
    2:
      begin
        Result := $0C;
        if FTransferReady then Result := Result or $80;
        if FVBlank then Result := Result or $40;
        if FHBlank then Result := Result or $20;
        if (FStatus[2] and $10) <> 0 then Result := Result or $10;
        if FCmdRunning then Result := Result or 1;
      end;
    7:
      begin
        Result := FCmdData;
        if FCmdRunning and (FCmdKind = $A) then CmdTransferNext(0);
      end;
  else
    if S < 10 then Result := FStatus[S] else Result := 0;
  end;
end;

procedure TMsxVdp.SetFrameFlag;
begin
  FStatus[0] := FStatus[0] or $80;
end;

procedure TMsxVdp.LineReached(Y: Integer);
begin
  if (Y = ((FReg[19] - FReg[23]) and 255)) then FStatus[1] := FStatus[1] or 1;
end;

function TMsxVdp.IntLine: Boolean;
begin
  Result := ((FStatus[0] and $80) <> 0) and ((FReg[1] and $20) <> 0);
  if ((FStatus[1] and 1) <> 0) and ((FReg[0] and $10) <> 0) then Result := True;
end;

function TMsxVdp.DisplayOn: Boolean;
begin
  Result := (FReg[1] and $40) <> 0;
end;

function TMsxVdp.Backdrop: Byte;
begin
  if DisplayMode = DM_G7 then Result := FReg[7] else Result := FReg[7] and 15;
end;

{ A Graphics 7 colour byte (GGGRRRBB) as RGB }
function G7Color(B: Byte): LongWord;
var
  Blue: Integer;
begin
  Blue := B and 3;
  Result := (LongWord(LEVEL[(B shr 2) and 7]) shl 16) or (LongWord(LEVEL[B shr 5]) shl 8) or
    LongWord(Blue * 85);
end;

function TMsxVdp.BackdropRGB: LongWord;
begin
  if DisplayMode = DM_G7 then Result := G7Color(FReg[7])
  else Result := PaletteRGB(FReg[7] and 15);
end;

function TMsxVdp.Reg(I: Integer): Byte;
begin
  Result := FReg[I and 63];
end;

procedure TMsxVdp.SetReg(I: Integer; Value: Byte);
begin
  WriteRegister(I and 63, Value);
end;

function TMsxVdp.StatusReg(I: Integer): Byte;
begin
  Result := FStatus[I mod 10];
end;

function TMsxVdp.VramByte(Addr: Integer): Byte;
begin
  Result := FVram[Addr and FVramMask];
end;

procedure TMsxVdp.PokeVram(Addr: Integer; Value: Byte);
begin
  FVram[Addr and FVramMask] := Value;
end;

function TMsxVdp.Status: Byte;
begin
  Result := FStatus[0];
end;

function TMsxVdp.AddressRegister: Word;
begin
  Result := FAddr;
end;

{ ---- Sprites ---- }

{ Mode 1 (the TMS9918A's, and the V9938's in Graphics 1, Multicolor and Graphics 2): the first four sprites in the
  list that touch the line, a fifth sets the 5S flag. Where two sprites both have a pixel set that is a
  collision. Idx gets the colour of the sprite on top (0 where none shows); Behind marks pixels a sprite occupies. }
procedure TMsxVdp.DrawSprites1(Y: Integer; var Idx: TVdpIdx; var Behind: TVdpIdx);
var
  Attr, PatBase, Size, Mag, N, Count, SY, SX, Pat, Col, Dy, Row, Bit, PX, Width: Integer;
  Bits: Word;
  Taken: TVdpIdx;
begin
  FillChar(Taken, SizeOf(Taken), 0);
  Attr := ((FReg[11] and 3) shl 15) or (FReg[5] shl 7);
  PatBase := (FReg[6] and $3F) shl 11;
  if (FReg[1] and 2) <> 0 then Size := 16 else Size := 8;
  if (FReg[1] and 1) <> 0 then Mag := 2 else Mag := 1;
  Width := Size * Mag;
  Count := 0;
  for N := 0 to 31 do
  begin
    SY := FVram[(Attr + N * 4) and FVramMask];
    if SY = $D0 then Break;
    if SY > $E0 then SY := SY - 256;    // the sprites that come in from the top
    Dy := Y - (SY + 1);
    if (Dy < 0) or (Dy >= Width) then Continue;
    Inc(Count);
    if Count > 4 then
    begin
      if (FStatus[0] and $40) = 0 then FStatus[0] := (FStatus[0] and $A0) or $40 or N;
      Break;
    end;
    SX := FVram[(Attr + N * 4 + 1) and FVramMask];
    Pat := FVram[(Attr + N * 4 + 2) and FVramMask];
    Col := FVram[(Attr + N * 4 + 3) and FVramMask];
    if (Col and $80) <> 0 then SX := SX - 32;
    Col := Col and 15;
    Row := Dy div Mag;
    if Size = 16 then
    begin
      Pat := Pat and $FC;
      Bits := (Word(FVram[(PatBase + Pat * 8 + Row) and FVramMask]) shl 8) or
        FVram[(PatBase + Pat * 8 + Row + 16) and FVramMask];
    end
    else
      Bits := Word(FVram[(PatBase + Pat * 8 + Row) and FVramMask]) shl 8;
    for Bit := 0 to Width - 1 do
    begin
      if (Bits and ($8000 shr (Bit div Mag))) = 0 then Continue;
      PX := SX + Bit;
      if (PX < 0) or (PX > 255) then Continue;
      if Taken[PX] <> 0 then
      begin
        FStatus[0] := FStatus[0] or $20;      // collision
        Continue;
      end;
      Taken[PX] := 1;
      Behind[PX] := 1;
      Idx[PX] := Col;
    end;
  end;
end;

{ Mode 2 (Graphics 3 to 7): eight sprites a line, a colour for each line of each sprite (the table of 16 bytes
  each that is 512 bytes before the attribute table) with the bits CC (combine with the sprite below: OR the
  colours), IC (ignore collisions) and EC (early clock); a ninth sets 5S. }
procedure TMsxVdp.DrawSprites2(Y: Integer; var Idx: TVdpIdx; var Behind: TVdpIdx);
var
  Attr, ColBase, PatBase, Size, Mag, N, Count, SY, SX, Pat, Dy, Row, Bit, PX, Width: Integer;
  ColByte, Colour: Byte;
  Bits: Word;
  Taken: TVdpIdx;
begin
  if (FReg[8] and 2) <> 0 then Exit;       // sprites off
  FillChar(Taken, SizeOf(Taken), 0);
  Attr := ((FReg[11] and 3) shl 15) or ((FReg[5] and $FC) shl 7);
  ColBase := Attr - $200;
  PatBase := (FReg[6] and $3F) shl 11;
  if (FReg[1] and 2) <> 0 then Size := 16 else Size := 8;
  if (FReg[1] and 1) <> 0 then Mag := 2 else Mag := 1;
  Width := Size * Mag;
  Count := 0;
  for N := 0 to 31 do
  begin
    SY := FVram[(Attr + N * 4) and FVramMask];
    if SY = $D8 then Break;
    Dy := (Y - (SY + 1)) and 255;
    if Dy >= Width then Continue;
    Inc(Count);
    if Count > 8 then
    begin
      if (FStatus[0] and $40) = 0 then FStatus[0] := (FStatus[0] and $A0) or $40 or N;
      Break;
    end;
    SX := FVram[(Attr + N * 4 + 1) and FVramMask];
    Pat := FVram[(Attr + N * 4 + 2) and FVramMask];
    Row := Dy div Mag;
    ColByte := FVram[(ColBase + N * 16 + Row) and FVramMask];
    if (ColByte and $80) <> 0 then SX := SX - 32;
    Colour := ColByte and 15;
    if Size = 16 then
    begin
      Pat := Pat and $FC;
      Bits := (Word(FVram[(PatBase + Pat * 8 + Row) and FVramMask]) shl 8) or
        FVram[(PatBase + Pat * 8 + Row + 16) and FVramMask];
    end
    else
      Bits := Word(FVram[(PatBase + Pat * 8 + Row) and FVramMask]) shl 8;
    for Bit := 0 to Width - 1 do
    begin
      if (Bits and ($8000 shr (Bit div Mag))) = 0 then Continue;
      PX := SX + Bit;
      if (PX < 0) or (PX > 255) then Continue;
      if Taken[PX] <> 0 then
      begin
        if (ColByte and $20) = 0 then FStatus[0] := FStatus[0] or $20;      // collision, unless IC
        if (ColByte and $40) <> 0 then Idx[PX] := Idx[PX] or Colour;        // CC: the colours combine
        Continue;
      end;
      Taken[PX] := 1;
      if Colour <> 0 then
      begin
        Behind[PX] := 1;
        Idx[PX] := Colour;
      end;
    end;
  end;
end;

{ ---- The picture ---- }

procedure TMsxVdp.RenderLine(Y: Integer; var Out: TVdpOut; out Wide: Boolean);
var
  Idx, Sprites, Covered: TVdpIdx;
  DMode, Yv, X, TX, Name, Col, Fg, BgC, Bits, NT, CT, PG, Third, Row, Index, Mask, Base: Integer;
  Direct, Transparent: Boolean;
  B: Byte;
  Bd: Byte;
  BdRGB: LongWord;
begin
  Wide := False;
  Direct := False;
  DMode := DisplayMode;
  Bd := FReg[7] and 15;
  BdRGB := BackdropRGB;
  if not DisplayOn then
  begin
    for X := 0 to 511 do Out[X] := BdRGB;
    Exit;
  end;
  Yv := (Y + FReg[23]) and 255;
  Row := Yv and 7;
  FillChar(Idx, SizeOf(Idx), Bd);
  NT := (FReg[2] and NameMask) shl 10;
  case DMode of
    DM_G1:
      begin
        CT := ((FReg[10] and 7) shl 14) or (FReg[3] shl 6);
        PG := (FReg[4] and $3F) shl 11;
        for TX := 0 to 31 do
        begin
          Name := FVram[(NT + (Yv shr 3) * 32 + TX) and FVramMask];
          Bits := FVram[(PG + Name * 8 + Row) and FVramMask];
          Col := FVram[(CT + (Name shr 3)) and FVramMask];
          Fg := Col shr 4;
          BgC := Col and 15;
          if Fg = 0 then Fg := Bd;
          if BgC = 0 then BgC := Bd;
          for X := 0 to 7 do
            if (Bits and ($80 shr X)) <> 0 then Idx[TX * 8 + X] := Fg else Idx[TX * 8 + X] := BgC;
        end;
      end;
    DM_G2, DM_G3:
      begin
        Third := Yv shr 6;
        CT := ((FReg[3] and $80) shl 6) or ((FReg[10] and 7) shl 14);
        PG := (FReg[4] and $3C) shl 11;
        for TX := 0 to 31 do
        begin
          Name := FVram[(NT + (Yv shr 3) * 32 + TX) and FVramMask];
          Index := (Third shl 8) or Name;
          Mask := ((FReg[4] and 3) shl 8) or $FF;
          Bits := FVram[(PG + (Index and Mask) * 8 + Row) and FVramMask];
          Mask := ((FReg[3] and $7F) shl 3) or 7;
          Col := FVram[(CT + (Index and Mask) * 8 + Row) and FVramMask];
          Fg := Col shr 4;
          BgC := Col and 15;
          if Fg = 0 then Fg := Bd;
          if BgC = 0 then BgC := Bd;
          for X := 0 to 7 do
            if (Bits and ($80 shr X)) <> 0 then Idx[TX * 8 + X] := Fg else Idx[TX * 8 + X] := BgC;
        end;
      end;
    DM_T1:
      begin
        PG := (FReg[4] and $3F) shl 11;
        Fg := FReg[7] shr 4;
        BgC := FReg[7] and 15;
        if Fg = 0 then Fg := Bd;
        if BgC = 0 then BgC := Bd;
        FillChar(Idx, 256, BgC);
        for TX := 0 to 39 do
        begin
          Name := FVram[(NT + (Yv shr 3) * 40 + TX) and FVramMask];
          Bits := FVram[(PG + Name * 8 + Row) and FVramMask];
          for X := 0 to 5 do
            if (Bits and ($80 shr X)) <> 0 then Idx[8 + TX * 6 + X] := Fg;
        end;
      end;
    DM_T2:
      begin
        // 80 columns: 6 pixels each in 512, 16 pixels of margin either side
        Wide := True;
        NT := (FReg[2] and $7C) shl 10;
        PG := (FReg[4] and $3F) shl 11;
        Fg := FReg[7] shr 4;
        BgC := FReg[7] and 15;
        FillChar(Idx, SizeOf(Idx), BgC);
        for TX := 0 to 79 do
        begin
          Name := FVram[(NT + (Yv shr 3) * 80 + TX) and FVramMask];
          Bits := FVram[(PG + Name * 8 + Row) and FVramMask];
          for X := 0 to 5 do
            if (Bits and ($80 shr X)) <> 0 then Idx[16 + TX * 6 + X] := Fg;
        end;
      end;
    DM_MC:
      begin
        PG := (FReg[4] and $3F) shl 11;
        for TX := 0 to 31 do
        begin
          Name := FVram[(NT + (Yv shr 3) * 32 + TX) and FVramMask];
          Col := FVram[(PG + Name * 8 + ((Yv shr 3) and 3) * 2 + ((Yv and 7) shr 2)) and FVramMask];
          Fg := Col shr 4;
          BgC := Col and 15;
          if Fg = 0 then Fg := Bd;
          if BgC = 0 then BgC := Bd;
          for X := 0 to 3 do Idx[TX * 8 + X] := Fg;
          for X := 4 to 7 do Idx[TX * 8 + X] := BgC;
        end;
      end;
    DM_G4:
      begin
        Base := ((FReg[2] and $60) shl 10) + Yv * 128;
        for X := 0 to 127 do
        begin
          B := FVram[(Base + X) and FVramMask];
          Idx[X * 2] := B shr 4;
          Idx[X * 2 + 1] := B and 15;
        end;
      end;
    DM_G5:
      begin
        Wide := True;
        Base := ((FReg[2] and $60) shl 10) + Yv * 128;
        for X := 0 to 127 do
        begin
          B := FVram[(Base + X) and FVramMask];
          Idx[X * 4] := B shr 6;
          Idx[X * 4 + 1] := (B shr 4) and 3;
          Idx[X * 4 + 2] := (B shr 2) and 3;
          Idx[X * 4 + 3] := B and 3;
        end;
      end;
    DM_G6:
      begin
        Wide := True;
        Base := ((FReg[2] and $20) shl 11) + Yv * 256;
        for X := 0 to 255 do
        begin
          B := VramRead(Base + X);
          Idx[X * 2] := B shr 4;
          Idx[X * 2 + 1] := B and 15;
        end;
      end;
    DM_G7:
      begin
        Direct := True;
        Base := ((FReg[2] and $20) shl 11) + Yv * 256;
        for X := 0 to 255 do Idx[X] := VramRead(Base + X);
      end;
  end;
  // Sprites: not in the text modes
  FillChar(Sprites, SizeOf(Sprites), 0);
  FillChar(Covered, SizeOf(Covered), 0);
  if (DMode <> DM_T1) and (DMode <> DM_T2) then
  begin
    if (DMode >= DM_G3) and (DMode <> DM_T2) then DrawSprites2(Y, Sprites, Covered)
    else DrawSprites1(Y, Sprites, Covered);
  end;
  // To RGB. On the V9938 colour 0 is transparent (it shows the backdrop) unless R#8 bit 5 (TP) is set
  Transparent := (FReg[8] and $20) = 0;
  for X := 0 to 511 do
  begin
    if Wide then Index := X else Index := X shr 1;
    if Direct then
      Out[X] := G7Color(Idx[Index])
    else if Transparent and (Idx[Index] = 0) and (DMode >= DM_G4) then
      Out[X] := BdRGB
    else
      Out[X] := PaletteRGB(Idx[Index]);
  end;
  if not Wide then
    for X := 0 to 255 do
      if (Covered[X] <> 0) and (Sprites[X] <> 0) then
      begin
        Out[X * 2] := PaletteRGB(Sprites[X]);
        Out[X * 2 + 1] := PaletteRGB(Sprites[X]);
      end;
end;

{ ---- Commands ---- }

function TMsxVdp.Reg16(Low: Integer; Mask: Integer): Integer;
begin
  Result := (FReg[Low] or (FReg[Low + 1] shl 8)) and Mask;
end;

procedure TMsxVdp.SetReg16(Low: Integer; Value: Integer);
begin
  FReg[Low] := Value and $FF;
  FReg[Low + 1] := (Value shr 8) and $FF;
end;

function TMsxVdp.ScreenWidth: Integer;
begin
  case DisplayMode of
    DM_G5, DM_G6: Result := 512;
  else
    Result := 256;
  end;
end;

function TMsxVdp.BitsPerPixel: Integer;
begin
  case DisplayMode of
    DM_G5: Result := 2;
    DM_G7: Result := 8;
  else
    Result := 4;
  end;
end;

{ The address of the byte with the pixel, and the shift of the pixel in it }
function TMsxVdp.PixelAddr(X, Y: Integer; out Shift: Integer): Integer;
begin
  case DisplayMode of
    DM_G5:
      begin
        Result := (Y shl 7) + (X shr 2);
        Shift := (3 - (X and 3)) * 2;
      end;
    DM_G6:
      begin
        Result := (Y shl 8) + (X shr 1);
        Shift := (1 - (X and 1)) * 4;
      end;
    DM_G7:
      begin
        Result := (Y shl 8) + X;
        Shift := 0;
      end;
  else
    begin
      Result := (Y shl 7) + (X shr 1);
      Shift := (1 - (X and 1)) * 4;
    end;
  end;
end;

function TMsxVdp.GetPixel(X, Y: Integer): Byte;
var
  Shift, A: Integer;
begin
  A := PixelAddr(X, Y and 1023, Shift);
  Result := (VramRead(A) shr Shift) and ((1 shl BitsPerPixel) - 1);
end;

procedure TMsxVdp.PutPixel(X, Y: Integer; Color, Op: Byte);
var
  Shift, A, Mask: Integer;
  Old, Src, New: Byte;
begin
  A := PixelAddr(X, Y and 1023, Shift);
  Mask := (1 shl BitsPerPixel) - 1;
  Color := Color and Mask;
  // The T versions (bit 3 of the operation) leave the pixel alone where the source is colour 0
  if ((Op and 8) <> 0) and (Color = 0) then Exit;
  Old := (VramRead(A) shr Shift) and Mask;
  Src := Color;
  case Op and 7 of
    1: New := Old and Src;
    2: New := Old or Src;
    3: New := Old xor Src;
    4: New := (not Src) and Mask;
  else
    New := Src;
  end;
  VramWrite(A, (VramRead(A) and not (Mask shl Shift)) or (New shl Shift));
end;

{ Byte-wise (the H commands): the byte that holds the pixel }
function TMsxVdp.GetByte(X, Y: Integer): Byte;
var
  Shift: Integer;
begin
  Result := VramRead(PixelAddr(X, Y and 1023, Shift));
end;

procedure TMsxVdp.PutByte(X, Y: Integer; Value: Byte);
var
  Shift: Integer;
begin
  VramWrite(PixelAddr(X, Y and 1023, Shift), Value);
end;

procedure TMsxVdp.FinishCommand;
begin
  FCmdRunning := False;
  FTransferReady := False;
  FReg[46] := FReg[46] and $0F;
end;

{ Fills a rectangle: LMMV pixel by pixel with the logical operation, HMMV by bytes }
procedure TMsxVdp.CmdFill(Logical: Boolean);
var
  DX, DY, NX, NY, DirX, DirY, I, J, X, Y, W, Ppb: Integer;
begin
  W := ScreenWidth;
  DX := Reg16(36, $1FF);
  DY := Reg16(38, $3FF);
  NX := Reg16(40, $3FF);
  NY := Reg16(42, $3FF);
  if NX = 0 then NX := W;
  if NY = 0 then NY := 1024;
  if (FReg[45] and 4) <> 0 then DirX := -1 else DirX := 1;
  if (FReg[45] and 8) <> 0 then DirY := -1 else DirY := 1;
  Ppb := 8 div BitsPerPixel;
  for J := 0 to NY - 1 do
  begin
    Y := DY + DirY * J;
    if (Y < 0) or (Y > 1023) then Break;
    for I := 0 to NX - 1 do
    begin
      X := DX + DirX * I;
      if (X < 0) or (X >= W) then Break;
      if Logical then PutPixel(X, Y, FReg[44], FCmdOp)
      else if ((X mod Ppb) = 0) or (I = 0) then PutByte(X, Y, FReg[44]);
    end;
  end;
  SetReg16(42, 0);
  SetReg16(38, (DY + DirY * NY) and $3FF);
end;

{ Copies a rectangle: LMMM pixel by pixel with the operation, HMMM by bytes }
procedure TMsxVdp.CmdCopy(Logical: Boolean);
var
  SX, SY, DX, DY, NX, NY, DirX, DirY, I, J, W, Ppb, SXi, DXi: Integer;
begin
  W := ScreenWidth;
  SX := Reg16(32, $1FF);
  SY := Reg16(34, $3FF);
  DX := Reg16(36, $1FF);
  DY := Reg16(38, $3FF);
  NX := Reg16(40, $3FF);
  NY := Reg16(42, $3FF);
  if NX = 0 then NX := W;
  if NY = 0 then NY := 1024;
  if (FReg[45] and 4) <> 0 then DirX := -1 else DirX := 1;
  if (FReg[45] and 8) <> 0 then DirY := -1 else DirY := 1;
  Ppb := 8 div BitsPerPixel;
  for J := 0 to NY - 1 do
  begin
    if ((SY + DirY * J) < 0) or ((SY + DirY * J) > 1023) or ((DY + DirY * J) < 0) or ((DY + DirY * J) > 1023) then Break;
    for I := 0 to NX - 1 do
    begin
      SXi := SX + DirX * I;
      DXi := DX + DirX * I;
      if (SXi < 0) or (SXi >= W) or (DXi < 0) or (DXi >= W) then Break;
      if Logical then
        PutPixel(DXi, DY + DirY * J, GetPixel(SXi, SY + DirY * J), FCmdOp)
      else if ((DXi mod Ppb) = 0) or (I = 0) then
        PutByte(DXi, DY + DirY * J, GetByte(SXi, SY + DirY * J));
    end;
  end;
  SetReg16(42, 0);
  SetReg16(34, (SY + DirY * NY) and $3FF);
  SetReg16(38, (DY + DirY * NY) and $3FF);
end;

{ YMMM: lines of bytes from (DX, SY) to (DX, DY), to the edge of the screen in the direction of X }
procedure TMsxVdp.CmdYmmm;
var
  SY, DX, DY, NY, DirX, DirY, J, X, W, Ppb: Integer;
begin
  W := ScreenWidth;
  SY := Reg16(34, $3FF);
  DX := Reg16(36, $1FF);
  DY := Reg16(38, $3FF);
  NY := Reg16(42, $3FF);
  if NY = 0 then NY := 1024;
  if (FReg[45] and 4) <> 0 then DirX := -1 else DirX := 1;
  if (FReg[45] and 8) <> 0 then DirY := -1 else DirY := 1;
  Ppb := 8 div BitsPerPixel;
  for J := 0 to NY - 1 do
  begin
    if ((SY + DirY * J) < 0) or ((SY + DirY * J) > 1023) or ((DY + DirY * J) < 0) or ((DY + DirY * J) > 1023) then Break;
    X := DX - (DX mod Ppb);
    while (X >= 0) and (X < W) do
    begin
      PutByte(X, DY + DirY * J, GetByte(X, SY + DirY * J));
      Inc(X, DirX * Ppb);
    end;
  end;
  SetReg16(42, 0);
  SetReg16(34, (SY + DirY * NY) and $3FF);
  SetReg16(38, (DY + DirY * NY) and $3FF);
end;

{ LINE: from (DX, DY), NX the long side and NY the short one, the long side along Y if MAJ }
procedure TMsxVdp.CmdLine;
var
  X, Y, Long, Short, DirX, DirY, I, Err: Integer;
  Major: Boolean;
begin
  X := Reg16(36, $1FF);
  Y := Reg16(38, $3FF);
  Long := Reg16(40, $3FF);
  Short := Reg16(42, $3FF);
  if (FReg[45] and 4) <> 0 then DirX := -1 else DirX := 1;
  if (FReg[45] and 8) <> 0 then DirY := -1 else DirY := 1;
  Major := (FReg[45] and 1) <> 0;       // the long side is vertical
  Err := 0;
  for I := 0 to Long do
  begin
    if (X < 0) or (X >= ScreenWidth) or (Y < 0) or (Y > 1023) then Break;
    PutPixel(X, Y, FReg[44], FCmdOp);
    Err := Err + Short;
    if Major then
    begin
      Y := Y + DirY;
      if Err * 2 >= Long then
      begin
        X := X + DirX;
        Err := Err - Long;
      end;
    end
    else
    begin
      X := X + DirX;
      if Err * 2 >= Long then
      begin
        Y := Y + DirY;
        Err := Err - Long;
      end;
    end;
  end;
end;

{ SRCH: along the line from (SX, SY) for the colour CLR; the X where it is found goes to S#8 and S#9, and the
  BD flag is set }
procedure TMsxVdp.CmdSearch;
var
  X, Y, DirX: Integer;
  Equal, Hit: Boolean;
begin
  X := Reg16(32, $1FF);
  Y := Reg16(34, $3FF);
  if (FReg[45] and 4) <> 0 then DirX := -1 else DirX := 1;
  Equal := (FReg[45] and 2) = 0;        // EQ 0: stop at the colour, 1: stop at another
  FStatus[2] := FStatus[2] and not $10;
  while (X >= 0) and (X < ScreenWidth) do
  begin
    Hit := (GetPixel(X, Y) = (FReg[44] and ((1 shl BitsPerPixel) - 1))) = Equal;
    if Hit then
    begin
      FStatus[2] := FStatus[2] or $10;
      FStatus[8] := X and $FF;
      FStatus[9] := (X shr 8) and 1;
      Exit;
    end;
    Inc(X, DirX);
  end;
end;

procedure TMsxVdp.StartCommand(Value: Byte);
begin
  Inc(FCmdCount);
  FCmdKind := Value shr 4;
  FCmdOp := Value and $0F;
  FCmdRunning := False;
  FTransferReady := False;
  case FCmdKind of
    0: ;
    4: FCmdData := GetPixel(Reg16(32, $1FF), Reg16(34, $3FF));                  // POINT
    5: PutPixel(Reg16(36, $1FF), Reg16(38, $3FF), FReg[44], FCmdOp);              // PSET
    6: CmdSearch;
    7: CmdLine;
    8: CmdFill(True);
    9: CmdCopy(True);
    $C: CmdFill(False);
    $D: CmdCopy(False);
    $E: CmdYmmm;
    $B, $F, $A:
      begin
        // The CPU sends the pixels (LMMC) or bytes (HMMC), the first in R#44 already, or takes them (LMCM) from S#7
        if FCmdKind = $A then FCmdX := Reg16(32, $1FF) else FCmdX := Reg16(36, $1FF);
        if FCmdKind = $A then FCmdY := Reg16(34, $3FF) else FCmdY := Reg16(38, $3FF);
        FCmdNX := Reg16(40, $3FF);
        FCmdNY := Reg16(42, $3FF);
        if FCmdNX = 0 then FCmdNX := ScreenWidth;
        if FCmdNY = 0 then FCmdNY := 1024;
        FCmdDX := FCmdX;
        if (FReg[45] and 4) <> 0 then FCmdDirX := -1 else FCmdDirX := 1;
        if (FReg[45] and 8) <> 0 then FCmdDirY := -1 else FCmdDirY := 1;
        FCmdRunning := True;
        FTransferReady := True;
        if FCmdKind = $A then FCmdData := GetPixel(FCmdX, FCmdY)
        else CmdTransferNext(FReg[44]);
        Exit;
      end;
  end;
  FinishCommand;
end;

{ The next pixel or byte of a transfer: for HMMC and LMMC Value goes to the VRAM; for LMCM the next one is read
  (the CPU has taken the one in S#7) }
procedure TMsxVdp.CmdTransferNext(Value: Byte);
var
  Step: Integer;
begin
  case FCmdKind of
    $B: PutPixel(FCmdX, FCmdY, Value, FCmdOp);
    $F: PutByte(FCmdX, FCmdY, Value);
  end;
  if FCmdKind = $F then Step := 8 div BitsPerPixel else Step := 1;
  Inc(FCmdX, FCmdDirX * Step);
  Dec(FCmdNX, Step);
  if (FCmdNX <= 0) or (FCmdX < 0) or (FCmdX >= ScreenWidth) then
  begin
    FCmdX := FCmdDX;
    FCmdNX := Reg16(40, $3FF);
    if FCmdNX = 0 then FCmdNX := ScreenWidth;
    Inc(FCmdY, FCmdDirY);
    Dec(FCmdNY);
  end;
  if (FCmdNY <= 0) or (FCmdY < 0) or (FCmdY > 1023) then
  begin
    FinishCommand;
    Exit;
  end;
  if FCmdKind = $A then FCmdData := GetPixel(FCmdX, FCmdY);
  FTransferReady := True;
end;

end.

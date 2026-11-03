{ C64Vic: the MOS 6569 (PAL VIC-II), cycle by cycle after Christian Bauer's "The MOS 6567/6569 video
  controller (VIC-II) and its application in the Commodore 64": 63 cycles of 8 pixels in each of 312
  raster lines, the character/bitmap/multicolour/extended modes, the bad lines (which stop the CPU), the
  8 sprites with their DMA, the border flip-flops (so the 38-column and 24-row tricks and the opened
  borders work), collisions and the raster interrupt.

  The picture is made as the beam goes: Tick is one cycle, and renders its 8 pixels. The frame buffer is
  the centre of the picture, VIC_WIDTH x VIC_HEIGHT pixels. }
unit C64Vic;

{$mode objfpc}{$H+}
{$R-}{$Q-}

interface

uses
  Classes, Cpu6510;

const
  VIC_WIDTH = 352;       // visible pixels: 320 + 16 of border at each side
  VIC_HEIGHT = 288;      // 200 + 44 of border above and below
  VIC_LINES = 312;
  VIC_CROP = 8;          // lines at the top and at the bottom of the picture kept as plain border (raster lines 15 to 286
                         // are seen, as on a monitor: the sprites of a score in the opened lower border too)
  VIC_CYCLES = 63;
  { The raster line the first row of the frame buffer is, and the x coordinate (as sprites count) of its first column }
  VIC_FIRST_LINE = 7;
  VIC_FIRST_X = 8;

type
  { A read by the VIC-II: a 14-bit address in its 16K bank }
  TVicRead = function(Addr: Word): Byte of object;

  TVic = class
  private
    FReg: array[0..63] of Byte;
    FRaster, FCycle: Integer;
    FVC, FVCBase, FVMLI, FRC: Integer;
    FDisplayState, FBadLine, FDenSeen: Boolean;
    FMatrix: array[0..39] of Word;
    FMainBorder, FVertBorder: Boolean;
    FPrevPix, FPrevFg: array[0..7] of Byte;   // the last cycle's pixels, for the horizontal scroll
    FCurPix, FCurFg: array[0..7] of Byte;
    FSprMC, FSprMCBase: array[0..7] of Integer;
    FSprDma, FSprDisp, FSprYFlip: array[0..7] of Boolean;
    FSprDispR: array[0..7] of Boolean;        // as it is displayed in this line
    FSprData: array[0..7] of LongWord;        // the data being displayed
    FSprFetch: array[0..7] of LongWord;       // the data fetched for the next line
    FSprPtr: array[0..7] of Integer;
    FSprPending: array[0..7] of Boolean;
    FIrqFlags, FIrqMask: Byte;
    FSprSprColl, FSprBgColl: Byte;
    FBaLow: Boolean;
    FBaRun: Integer;
    FFrameReady: Boolean;
    FLastFetch: Byte;
    FOnRead: TVicRead;
    FX0: array[1..VIC_CYCLES] of Integer;
    FSprBa: array[1..VIC_CYCLES] of Byte;     // sprites whose DMA holds BA low in each cycle
    FRasterIrqDone: Boolean;
    function GetIrq: Boolean;
    procedure MakeGfx(CData: Word; GData: Byte);
    procedure RenderCycle;
    procedure SpriteCycle;
    procedure SetFlag(Bit: Byte);
    function Fetch(Addr: Word): Byte; inline;
  public
    ColorRam: array[0..1023] of Byte;         // 4 bits each
    Frame: array[0..VIC_WIDTH * VIC_HEIGHT - 1] of LongWord;
    constructor Create;
    procedure Reset;
    { The whole state, for the debugger's step back: written to S (Save) or read back from it. The fields it copies as
      blocks (see StateIO) are plain values: no strings or dynamic arrays may go in between them }
    procedure StateIO(S: TStream; Save: Boolean);
    { One cycle of the clock }
    procedure Tick;
    function Read(Reg: Byte): Byte;
    function Peek(Reg: Byte): Byte;
    procedure Write(Reg, Value: Byte);
    property OnRead: TVicRead read FOnRead write FOnRead;
    function RasterCompare: Integer;
    property Irq: Boolean read GetIrq;
    property BaLow: Boolean read FBaLow;
    property BaRun: Integer read FBaRun;
    property Raster: Integer read FRaster;
    property Cycle: Integer read FCycle;
    property FrameReady: Boolean read FFrameReady write FFrameReady;
    property LastFetch: Byte read FLastFetch;
    property VideoCounter: Integer read FVC;
    property RowCounter: Integer read FRC;
    property BadLine: Boolean read FBadLine;
  end;

const
  { Pepto's colours of the C64 }
  C64_PALETTE: array[0..15] of LongWord = (
    $FF000000, $FFFFFFFF, $FF68372B, $FF70A4B2, $FF6F3D86, $FF588D43, $FF352879, $FFB8C76F,
    $FF6F4F25, $FF433900, $FF9A6759, $FF444444, $FF6C6C6C, $FF9AD284, $FF6C5EB5, $FF959595);

implementation

const
  { The cycle each sprite's pointer is read in (its data follows in the next cycle) }
  SPR_CYCLE: array[0..7] of Integer = (58, 60, 62, 1, 3, 5, 7, 9);

constructor TVic.Create;
var
  C, I, K, N: Integer;
begin
  inherited Create;
  for C := 1 to VIC_CYCLES do
  begin
    FX0[C] := 24 + 8 * (C - 16);
    if FX0[C] < 0 then Inc(FX0[C], 504);
  end;
  // BA is held low from 3 cycles before a sprite's first access to its second one
  FillChar(FSprBa, SizeOf(FSprBa), 0);
  for I := 0 to 7 do
    for K := 0 to 4 do
    begin
      N := SPR_CYCLE[I] - 3 + K;
      while N < 1 do Inc(N, VIC_CYCLES);
      while N > VIC_CYCLES do Dec(N, VIC_CYCLES);
      FSprBa[N] := FSprBa[N] or (1 shl I);
    end;
  Reset;
end;

procedure TVic.Reset;
var
  I: Integer;
begin
  FillChar(FReg, SizeOf(FReg), 0);
  FillChar(FMatrix, SizeOf(FMatrix), 0);
  FillChar(FPrevPix, SizeOf(FPrevPix), 0);
  FillChar(FPrevFg, SizeOf(FPrevFg), 0);
  FRaster := 0;
  FCycle := VIC_CYCLES;
  FVC := 0; FVCBase := 0; FVMLI := 0; FRC := 7;
  FDisplayState := False; FBadLine := False; FDenSeen := False;
  FMainBorder := True; FVertBorder := True;
  for I := 0 to 7 do
  begin
    FSprDma[I] := False; FSprDisp[I] := False; FSprYFlip[I] := True; FSprDispR[I] := False;
    FSprMC[I] := 0; FSprMCBase[I] := 0; FSprData[I] := 0; FSprFetch[I] := 0; FSprPending[I] := False;
  end;
  FIrqFlags := 0; FIrqMask := 0;
  FSprSprColl := 0; FSprBgColl := 0;
  FBaLow := False; FBaRun := 0;
  FFrameReady := False;
  FReg[$11] := $1B;
  FReg[$18] := $14;
  FillChar(Frame, SizeOf(Frame), 0);
end;

function TVic.GetIrq: Boolean;
begin
  Result := (FIrqFlags and FIrqMask and $0F) <> 0;
end;

procedure TVic.SetFlag(Bit: Byte);
begin
  FIrqFlags := FIrqFlags or Bit;
end;

function TVic.RasterCompare: Integer;
begin
  Result := FReg[$12] or ((FReg[$11] and $80) shl 1);
end;

function TVic.Fetch(Addr: Word): Byte;
begin
  Result := FOnRead(Addr and $3FFF);
  FLastFetch := Result;
end;

function TVic.Peek(Reg: Byte): Byte;
begin
  Reg := Reg and $3F;
  case Reg of
    $11: Result := (FReg[$11] and $7F) or ((FRaster shr 1) and $80);
    $12: Result := FRaster and $FF;
    $13, $14: Result := 0;                     // light pen
    $16: Result := FReg[$16] or $C0;
    $18: Result := FReg[$18] or 1;
    $19:
      begin
        Result := FIrqFlags or $70;
        if GetIrq then Result := Result or $80;
      end;
    $1A: Result := FIrqMask or $F0;
    $1E: Result := FSprSprColl;
    $1F: Result := FSprBgColl;
    $20..$2E: Result := FReg[Reg] or $F0;
    $2F..$3F: Result := $FF;
  else
    Result := FReg[Reg];
  end;
end;

function TVic.Read(Reg: Byte): Byte;
begin
  Result := Peek(Reg);
  case Reg and $3F of
    $1E: FSprSprColl := 0;
    $1F: FSprBgColl := 0;
  end;
end;

procedure TVic.Write(Reg, Value: Byte);
var
  I, Old: Integer;
begin
  Reg := Reg and $3F;
  if Reg > $2E then Exit;
  case Reg of
    $19: begin FIrqFlags := FIrqFlags and not (Value and $0F); Exit; end;
    $1A: begin FIrqMask := Value and $0F; Exit; end;
    $1E, $1F: Exit;
    $17:
      for I := 0 to 7 do
        if (Value and (1 shl I)) = 0 then FSprYFlip[I] := True;
  end;
  Old := RasterCompare;
  FReg[Reg] := Value;
  // A raster compare that becomes true raises its interrupt at once (once a line): a handler that sets the next
  // line a little late (Mikie's chain of raster interrupts) still gets it
  if ((Reg = $11) or (Reg = $12)) and (RasterCompare <> Old) and (RasterCompare = FRaster) and not FRasterIrqDone then
  begin
    FRasterIrqDone := True;
    SetFlag(1);
  end;
end;

{ The 8 pixels of a cycle's graphics (colours and whether each is foreground) from the character/bitmap data }
procedure TVic.MakeGfx(CData: Word; GData: Byte);
var
  K, V, Col, Chr, Mode: Integer;
  Ecm, Bmm, Mcm, Bit: Boolean;
  Bg: array[0..3] of Byte;
begin
  Ecm := (FReg[$11] and $40) <> 0;
  Bmm := (FReg[$11] and $20) <> 0;
  Mcm := (FReg[$16] and $10) <> 0;
  Col := (CData shr 8) and $0F;
  Chr := CData and $FF;
  Bg[0] := FReg[$21] and $0F;
  Bg[1] := FReg[$22] and $0F;
  Bg[2] := FReg[$23] and $0F;
  Bg[3] := FReg[$24] and $0F;
  Mode := Ord(Ecm) * 4 + Ord(Bmm) * 2 + Ord(Mcm);
  case Mode of
    0:       // standard text
      for K := 0 to 7 do
      begin
        Bit := ((GData shr (7 - K)) and 1) <> 0;
        FCurFg[K] := Ord(Bit);
        if Bit then FCurPix[K] := Col else FCurPix[K] := Bg[0];
      end;
    1:       // multicolour text
      if (Col and 8) = 0 then
        for K := 0 to 7 do
        begin
          Bit := ((GData shr (7 - K)) and 1) <> 0;
          FCurFg[K] := Ord(Bit);
          if Bit then FCurPix[K] := Col else FCurPix[K] := Bg[0];
        end
      else
        for K := 0 to 7 do
        begin
          V := (GData shr (6 - (K and 6))) and 3;
          FCurFg[K] := Ord(V >= 2);
          case V of
            0: FCurPix[K] := Bg[0];
            1: FCurPix[K] := Bg[1];
            2: FCurPix[K] := Bg[2];
          else
            FCurPix[K] := Col and 7;
          end;
        end;
    2:       // standard bitmap
      for K := 0 to 7 do
      begin
        Bit := ((GData shr (7 - K)) and 1) <> 0;
        FCurFg[K] := Ord(Bit);
        if Bit then FCurPix[K] := Chr shr 4 else FCurPix[K] := Chr and $0F;
      end;
    3:       // multicolour bitmap
      for K := 0 to 7 do
      begin
        V := (GData shr (6 - (K and 6))) and 3;
        FCurFg[K] := Ord(V >= 2);
        case V of
          0: FCurPix[K] := Bg[0];
          1: FCurPix[K] := Chr shr 4;
          2: FCurPix[K] := Chr and $0F;
        else
          FCurPix[K] := Col;
        end;
      end;
    4:       // extended colour text
      for K := 0 to 7 do
      begin
        Bit := ((GData shr (7 - K)) and 1) <> 0;
        FCurFg[K] := Ord(Bit);
        if Bit then FCurPix[K] := Col else FCurPix[K] := Bg[Chr shr 6];
      end;
  else
    // Invalid modes: black, but the sequencer still knows what is foreground
    for K := 0 to 7 do
    begin
      if (Mode and 1) <> 0 then
        FCurFg[K] := Ord(((GData shr (6 - (K and 6))) and 3) >= 2)
      else
        FCurFg[K] := (GData shr (7 - K)) and 1;
      FCurPix[K] := 0;
    end;
  end;
end;

{ The sprite accesses of the cycle, and the per-line sprite bookkeeping }
procedure TVic.SpriteCycle;
var
  I, Mask: Integer;
  Match: Boolean;
  B0, B1, B2: Byte;
  Base: Integer;
begin
  case FCycle of
    15:
      for I := 0 to 7 do
        if FSprYFlip[I] then FSprMCBase[I] := (FSprMCBase[I] + 2) and 63;
    16:
      for I := 0 to 7 do
      begin
        if FSprYFlip[I] then FSprMCBase[I] := (FSprMCBase[I] + 1) and 63;
        if FSprMCBase[I] = 63 then FSprDma[I] := False;
      end;
    55, 56:
      for I := 0 to 7 do
      begin
        Mask := 1 shl I;
        if FCycle = 55 then
        begin
          if (FReg[$17] and Mask) <> 0 then FSprYFlip[I] := not FSprYFlip[I] else FSprYFlip[I] := True;
        end;
        if ((FReg[$15] and Mask) <> 0) and (FReg[1 + 2 * I] = (FRaster and $FF)) and not FSprDma[I] then
        begin
          FSprDma[I] := True;
          FSprMCBase[I] := 0;
          if (FReg[$17] and Mask) <> 0 then FSprYFlip[I] := False;
        end;
      end;
    58:
      for I := 0 to 7 do
      begin
        Mask := 1 shl I;
        FSprMC[I] := FSprMCBase[I];
        Match := ((FReg[$15] and Mask) <> 0) and (FReg[1 + 2 * I] = (FRaster and $FF));
        if FSprDma[I] then
        begin
          if Match then FSprDisp[I] := True;
        end
        else
          FSprDisp[I] := False;
      end;
  end;
  // The pointer and data accesses
  for I := 0 to 7 do
  begin
    if FCycle = SPR_CYCLE[I] then
    begin
      Base := ((FReg[$18] and $F0) shl 6) or $3F8;
      FSprPtr[I] := Fetch(Base + I);
      if FSprDma[I] then
      begin
        B0 := Fetch(FSprPtr[I] * 64 + FSprMC[I]);
        FSprMC[I] := (FSprMC[I] + 1) and 63;
        FSprFetch[I] := B0 shl 16;
      end;
    end
    else if FCycle = (SPR_CYCLE[I] mod VIC_CYCLES) + 1 then
    begin
      if FSprDma[I] then
      begin
        B1 := Fetch(FSprPtr[I] * 64 + FSprMC[I]);
        B2 := Fetch(FSprPtr[I] * 64 + ((FSprMC[I] + 1) and 63));
        FSprMC[I] := (FSprMC[I] + 2) and 63;
        FSprFetch[I] := (FSprFetch[I] and $FF0000) or (B1 shl 8) or B2;
        if I >= 3 then FSprData[I] := FSprFetch[I] else FSprPending[I] := True;
      end;
    end;
  end;
end;

procedure TVic.RenderCycle;
var
  K, X, XS, I, First, Dx, Wd, P, Pair, Col, Left, Right, Top, Bottom: Integer;
  Pix, Fg: Byte;
  Border: Boolean;
  Visible: Boolean;
  Row, Offs: Integer;
  SprMask, SprCol: Byte;
  Den: Boolean;
  OutPix: array[0..7] of Byte;
  OutFg: array[0..7] of Byte;
  Any: Boolean;
begin
  XS := FReg[$16] and 7;
  // Graphics delayed by the horizontal scroll
  for K := 0 to 7 do
    if K >= XS then
    begin
      OutPix[K] := FCurPix[K - XS];
      OutFg[K] := FCurFg[K - XS];
    end
    else
    begin
      OutPix[K] := FPrevPix[8 + K - XS];
      OutFg[K] := FPrevFg[8 + K - XS];
    end;
  // (the pixels carried over keep whether they are foreground: with the screen scrolled, every character puts some
  // in the next cycle, and the sprites behind the characters and the collisions need it)
  for K := 0 to 7 do
  begin
    FPrevPix[K] := FCurPix[K];
    FPrevFg[K] := FCurFg[K];
  end;
  if (FReg[$16] and 8) <> 0 then begin Left := 24; Right := 344; end else begin Left := 31; Right := 335; end;
  if (FReg[$11] and 8) <> 0 then begin Top := 51; Bottom := 251; end else begin Top := 55; Bottom := 247; end;
  Den := (FReg[$11] and $10) <> 0;
  Row := FRaster - VIC_FIRST_LINE;
  Visible := (Row >= 0) and (Row < VIC_HEIGHT) and (FCycle >= 14) and (FCycle <= 57);
  Any := False;
  for I := 0 to 7 do if FSprDispR[I] then Any := True;
  Offs := Row * VIC_WIDTH + (FX0[FCycle] - VIC_FIRST_X);
  for K := 0 to 7 do
  begin
    X := FX0[FCycle] + K;
    if X >= 504 then Dec(X, 504);
    // The border flip-flops
    if X = Right then FMainBorder := True;
    if X = Left then
    begin
      if FRaster = Bottom then FVertBorder := True;
      if (FRaster = Top) and Den then FVertBorder := False;
      if not FVertBorder then FMainBorder := False;
    end;
    Pix := OutPix[K];
    Fg := OutFg[K];
    if Any then
    begin
      SprMask := 0;
      First := -1;
      for I := 0 to 7 do
        if FSprDispR[I] then
        begin
          Dx := X - (FReg[2 * I] or ((FReg[$10] shr I) and 1) shl 8);
          if Dx < 0 then Inc(Dx, 504);
          if (FReg[$1D] and (1 shl I)) <> 0 then Wd := 48 else Wd := 24;
          if Dx < Wd then
          begin
            if (FReg[$1D] and (1 shl I)) <> 0 then P := Dx shr 1 else P := Dx;
            if (FReg[$1C] and (1 shl I)) <> 0 then
            begin
              Pair := (FSprData[I] shr (22 - (P and not 1))) and 3;
              case Pair of
                0: Col := -1;
                1: Col := FReg[$25] and $0F;
                2: Col := FReg[$27 + I] and $0F;
              else
                Col := FReg[$26] and $0F;
              end;
            end
            else if ((FSprData[I] shr (23 - P)) and 1) <> 0 then Col := FReg[$27 + I] and $0F
            else Col := -1;
            if Col >= 0 then
            begin
              SprMask := SprMask or (1 shl I);
              if First < 0 then
              begin
                First := I;
                SprCol := Col;
              end;
            end;
          end;
        end;
      if SprMask <> 0 then
      begin
        if (SprMask and (SprMask - 1)) <> 0 then
        begin
          if FSprSprColl = 0 then SetFlag(4);
          FSprSprColl := FSprSprColl or SprMask;
        end;
        if Fg <> 0 then
        begin
          if FSprBgColl = 0 then SetFlag(2);
          FSprBgColl := FSprBgColl or SprMask;
        end;
        if not (((FReg[$1B] shr First) and 1 <> 0) and (Fg <> 0)) then Pix := SprCol;
      end;
    end;
    // The border is in front of everything, the sprites too (they show over it only where it is opened); the collisions
    // under it are still detected
    if FMainBorder then Pix := FReg[$20] and $0F;
    // (the outer lines of the border are always flat: no sprites peeking out above or below)
    if (Row < VIC_CROP) or (Row >= VIC_HEIGHT - VIC_CROP) then Pix := FReg[$20] and $0F;
    if Visible then Frame[Offs + K] := C64_PALETTE[Pix and 15];
  end;
end;

procedure TVic.Tick;
var
  CData: Word;
  GData: Byte;
  Cond, Within: Boolean;
  Addr: Word;
  I, SprBa, Top, Bottom: Integer;
begin
  Inc(FCycle);
  if FCycle > VIC_CYCLES then
  begin
    FCycle := 1;
    Inc(FRaster);
    if FRaster >= VIC_LINES then
    begin
      FRaster := 0;
      FFrameReady := True;
    end;
    if FRaster = 0 then
    begin
      FVCBase := 0;
      FDenSeen := False;
    end;
    // The sprites' data fetched at the end of the last line start being displayed
    for I := 0 to 7 do
    begin
      if FSprPending[I] then
      begin
        FSprData[I] := FSprFetch[I];
        FSprPending[I] := False;
      end;
      FSprDispR[I] := FSprDisp[I];
    end;
  end;

  // The raster interrupt: at the first cycle of the line (the second of line 0)
  if (FCycle = 1) then FRasterIrqDone := False;
  if (FRaster = RasterCompare) and (((FCycle = 1) and (FRaster > 0)) or ((FCycle = 2) and (FRaster = 0))) then
  begin
    FRasterIrqDone := True;
    SetFlag(1);
  end;

  // Bad line condition
  if (FRaster = $30) and ((FReg[$11] and $10) <> 0) then FDenSeen := True;
  Cond := (FRaster >= $30) and (FRaster <= $F7) and ((FRaster and 7) = (FReg[$11] and 7)) and FDenSeen;
  FBadLine := Cond;
  Within := (FCycle >= 12) and (FCycle <= 54);
  if Cond and Within then FDisplayState := True;

  if FCycle = 14 then
  begin
    FVC := FVCBase;
    FVMLI := 0;
    if Cond then FRC := 0;
  end;

  // BA: low during the bad line's c-accesses (from 3 cycles before them) and the sprites' DMA
  SprBa := 0;
  for I := 0 to 7 do
    if FSprDma[I] and ((FSprBa[FCycle] and (1 shl I)) <> 0) then SprBa := SprBa or (1 shl I);
  FBaLow := (Cond and Within) or (SprBa <> 0);
  if FBaLow then Inc(FBaRun) else FBaRun := 0;

  SpriteCycle;

  // c-access of the column the next g-access shows
  if Cond and (FCycle = 15) then FMatrix[0] := Fetch(((FReg[$18] and $F0) shl 6) or (FVC and $3FF)) or
    (Word(ColorRam[FVC and $3FF] and $0F) shl 8);

  // g-access
  if (FCycle >= 16) and (FCycle <= 55) then
  begin
    if FDisplayState then
    begin
      CData := FMatrix[FVMLI];
      if (FReg[$11] and $20) <> 0 then
        Addr := ((FReg[$18] and 8) shl 10) or (FVC shl 3) or FRC
      else if (FReg[$11] and $40) <> 0 then
        Addr := ((FReg[$18] and $0E) shl 10) or ((CData and $3F) shl 3) or FRC
      else
        Addr := ((FReg[$18] and $0E) shl 10) or ((CData and $FF) shl 3) or FRC;
      if (FReg[$11] and $20) <> 0 then Addr := Addr and $3FFF;
      GData := Fetch(Addr);
      FVC := (FVC + 1) and $3FF;
      Inc(FVMLI);
      // The c-access of the next column
      if Cond and (FCycle <= 54) and (FVMLI < 40) then
        FMatrix[FVMLI] := Fetch(((FReg[$18] and $F0) shl 6) or FVC) or (Word(ColorRam[FVC] and $0F) shl 8);
    end
    else
    begin
      CData := 0;
      if (FReg[$11] and $40) <> 0 then GData := Fetch($39FF) else GData := Fetch($3FFF);
    end;
  end
  else
  begin
    CData := 0;
    if (FReg[$11] and $40) <> 0 then GData := Fetch($39FF) else GData := Fetch($3FFF);
  end;
  MakeGfx(CData, GData);
  RenderCycle;

  if FCycle = 58 then
  begin
    if FRC = 7 then
    begin
      FVCBase := FVC;
      if not Cond then FDisplayState := False;
    end;
    if FDisplayState then FRC := (FRC + 1) and 7;
  end;
  if FCycle = VIC_CYCLES then
  begin
    // The vertical border flip-flop, checked at the end of the line
    if (FReg[$11] and 8) <> 0 then begin Bottom := 251; Top := 51; end else begin Bottom := 247; Top := 55; end;
    if FRaster = Bottom then FVertBorder := True
    else if (FRaster = Top) and ((FReg[$11] and $10) <> 0) then FVertBorder := False;
  end;
end;

procedure TVic.StateIO(S: TStream; Save: Boolean);
begin
  // FReg to FRasterIrqDone (FOnRead among them: the same handler), the colour RAM and the picture as drawn so far
  StateBlock(S, Save, FReg, PtrUInt(@FRasterIrqDone) + SizeOf(FRasterIrqDone) - PtrUInt(@FReg));
  StateBlock(S, Save, ColorRam, SizeOf(ColorRam));
  StateBlock(S, Save, Frame, SizeOf(Frame));
end;

end.

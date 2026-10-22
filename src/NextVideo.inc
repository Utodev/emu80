{ NextVideo.inc: the ZX Spectrum Next's display (included by Spectrum.pas):
  its eight palettes, the ULA (with ULANext, Timex modes and LoRes), the
  tilemap, Layer 2, the 128 sprites, clip windows, scrolls, the layer
  priorities of NR 15, the copper and port 123B's Layer 2 memory mapping.
  Each frame line is composed when the beam has passed it, at 640 pixels
  across the 320x256 area (the frame buffer is twice as wide), as
  registers.txt, ports.txt and tilemap.txt in the distribution describe. A
  register written while the beam is in a line (by the CPU or the copper)
  splits it: what was drawn stays, the rest is drawn with the new value. }

const
  { Palettes, numbered as NR 43 bits 6-4 }
  PAL_ULA = 0; PAL_L2 = 1; PAL_SPR = 2; PAL_TM = 3;
  { Clip windows }
  CLIP_L2 = 0; CLIP_SPR = 1; CLIP_ULA = 2; CLIP_TM = 3;
  { The 320x256 area in the frame: 16 lines and 16 pixels into it }
  NEXT_AREA_TOP = BORDER_TOP - 32;
  NEXT_AREA_LEFT = BORDER_LEFT - 32;

function Rgb9(V: Word): LongWord; inline;
begin
  Result := $FF000000 or ((((V shr 6) and 7) * 255 div 7) shl 16) or
    ((((V shr 3) and 7) * 255 div 7) shl 8) or ((V and 7) * 255 div 7);
end;

{ An 8-bit RRRGGGBB colour as 9 bits: the low blue bit is the OR of the two }
function Nine(V: Byte): Word; inline;
begin
  Result := (V shl 1) or Ord((V and 3) <> 0);
end;

procedure TSpectrum.NextSetPal(Pal, Index: Integer; Value: Word);
begin
  FNextPal[Pal, Index] := Value;
  FNextPalRGB[Pal, Index] := Rgb9(Value and $1FF);
end;

procedure TSpectrum.NextVideoReset;
const
  ULA_COLOURS: array[0..15] of Byte = ($00, $02, $A0, $A2, $14, $16, $B4, $B6,
    $00, $03, $E0, $E7, $1C, $1F, $FC, $FF);
var
  P, I: Integer;
begin
  // Every palette RRRGGGBB = its index; the ULA's 32 the Spectrum's colours
  for P := 0 to 7 do
    for I := 0 to 255 do NextSetPal(P, I, Nine(I));
  for P := 0 to 1 do
    for I := 0 to 31 do NextSetPal(P * 4 + PAL_ULA, I, Nine(ULA_COLOURS[I and 15]));
  FNextPal44 := False;
  for I := 0 to 3 do
  begin
    FNextClip[I, 0] := 0;
    FNextClip[I, 1] := 255;
    FNextClip[I, 2] := 0;
    FNextClip[I, 3] := 191;
    FNextClipIdx[I] := 0;
  end;
  FNextClip[CLIP_TM, 1] := 159;
  FNextClip[CLIP_TM, 3] := 255;
  FNextL2Port := 0;
  FNextL2Offset := 0;
  FillChar(FSprAttr, SizeOf(FSprAttr), 0);
  FSprIndex := 0;
  FSprAttrIdx := 0;
  FSprPatAddr := 0;
  FSprStatus := 0;
  FCopperAddr := 0;
  FCopperPC := 0;
  FCopperStopped := True;
  FCopperClk := 0;
  FCopperDue := 0;
end;

{ NR 41 (8-bit colour) and NR 44 (9-bit, two writes) }
procedure TSpectrum.NextPaletteWrite(Value: Byte; NineBits: Boolean);
var
  Pal, Index: Integer;
begin
  Pal := (FNextReg[$43] shr 4) and 7;
  Index := FNextReg[$40];
  if not NineBits then
    NextSetPal(Pal, Index, Nine(Value))
  else if not FNextPal44 then
  begin
    FNextPal44 := True;
    NextSetPal(Pal, Index, Value shl 1);
    Exit;
  end
  else
  begin
    FNextPal44 := False;
    // Bit 0 the low blue bit; bit 7 a Layer 2 priority colour
    NextSetPal(Pal, Index, (FNextPal[Pal, Index] and $1FE) or (Value and 1) or
      (Ord(((Value and $80) <> 0) and ((Pal and 3) = PAL_L2)) shl 9));
  end;
  if (FNextReg[$43] and $80) = 0 then FNextReg[$40] := Byte(Index + 1);
end;

procedure TSpectrum.NextClipWrite(Layer: Integer; Value: Byte);
begin
  FNextClip[Layer, FNextClipIdx[Layer]] := Value;
  FNextClipIdx[Layer] := (FNextClipIdx[Layer] + 1) and 3;
end;

{ Port 57: the sprite's attributes, 4 or 5 bytes, then the next sprite }
procedure TSpectrum.NextSpriteAttr(Value: Byte);
begin
  FSprAttr[FSprIndex, FSprAttrIdx] := Value;
  Inc(FSprAttrIdx);
  // A 4-byte sprite (attribute 3 bit 6 clear) has no fifth byte
  if (FSprAttrIdx = 4) and ((FSprAttr[FSprIndex, 3] and $40) = 0) then
  begin
    FSprAttr[FSprIndex, 4] := 0;
    FSprAttrIdx := 5;
  end;
  if FSprAttrIdx >= 5 then
  begin
    FSprAttrIdx := 0;
    FSprIndex := (FSprIndex + 1) and 127;
  end;
end;

{ Port 123B maps Layer 2 over 0000-3FFF (or 0000-BFFF) for reads and/or
  writes: the 16K RAM bank there, if so }
function TSpectrum.NextL2Bank(Addr: Word; Write: Boolean; out Bank: Integer): Boolean;
var
  Seg: Integer;
begin
  Result := False;
  if Write then Result := (FNextL2Port and 1) <> 0 else Result := (FNextL2Port and 4) <> 0;
  if not Result then Exit;
  if (FNextL2Port and $C0) = $C0 then
  begin
    Result := Addr < $C000;
    Seg := Addr shr 14;
  end
  else
  begin
    Result := Addr < $4000;
    Seg := FNextL2Port shr 6;
  end;
  if not Result then Exit;
  if (FNextL2Port and 8) <> 0 then Bank := FNextReg[$13] else Bank := FNextReg[$12];
  Inc(Bank, FNextL2Offset + Seg);
  Result := Bank < RAM_BANKS;
end;

{ NR 60: copper memory, a byte at a time (even addresses the high byte) }
procedure TSpectrum.NextCopperWrite(Value: Byte);
var
  I: Integer;
begin
  I := (FCopperAddr shr 1) and 1023;
  if not Odd(FCopperAddr) then FCopper[I] := (FCopper[I] and $00FF) or (Value shl 8)
  else FCopper[I] := (FCopper[I] and $FF00) or Value;
  FCopperAddr := (FCopperAddr + 1) and $7FF;
end;

{ The frame T-state of the raster position (vertical line V as the copper
  and the line interrupt count it: 0 = the ULA's first pixel row, moved by
  NR 64; horizontal H in 8-pixel steps from its left edge), at or after
  FromT: the copper's time compare (COPPER-v0.1c.TXT: 16 dot clocks, 4
  T-states, per step) }
function TSpectrum.NextRasterTime(V, H, FromT: Integer): Integer;
var
  Lines, Rel, Target: Integer;
begin
  Lines := FInfo.FrameT div FInfo.LineT;
  // Raster time: T-states since the ULA's first pixel row
  Rel := ((FromT - FInfo.PaperTopT) mod FInfo.FrameT + FInfo.FrameT) mod FInfo.FrameT;
  Target := (((V - FNextReg[$64]) mod Lines + Lines) mod Lines) * FInfo.LineT + H * 4;
  Result := FromT + ((Target - Rel) mod FInfo.FrameT + FInfo.FrameT) mod FInfo.FrameT;
end;

{ The copper (NR 60-64) up to frame T-state T: it runs on its own clock (4
  per T-state), WAIT holding it until its raster position, a MOVE taking two
  clocks and splitting the line being drawn there }
procedure TSpectrum.NextCopperRun(T: Integer);
var
  Limit, At, Restart, Lines, Pos_, Line, H: Integer;
  Instr: Word;
  Mode3: Boolean;
begin
  if T > FInfo.FrameT then T := FInfo.FrameT;
  Limit := T * 4;
  Lines := FInfo.FrameT div FInfo.LineT;
  while not FCopperStopped and (FCopperClk < Limit) do
  begin
    Mode3 := (FNextReg[$62] shr 6) = 3;
    Instr := FCopper[FCopperPC];
    if (Instr and $8000) <> 0 then
    begin
      // WAIT for line (bits 8-0) and position (bits 14-9): now, if the
      // raster is in that line at or past it; a line that doesn't exist never
      At := MaxInt;
      if (Instr and $1FF) < Lines then
      begin
        Pos_ := ((FCopperClk div 4 - FInfo.PaperTopT) mod FInfo.FrameT + FInfo.FrameT) mod FInfo.FrameT;
        Line := (Pos_ div FInfo.LineT + FNextReg[$64]) mod Lines;
        H := (Pos_ mod FInfo.LineT) div 4;
        if (Line = Integer(Instr and $1FF)) and (H >= (Instr shr 9) and $3F) then
          At := FCopperClk
        else
          At := NextRasterTime(Instr and $1FF, (Instr shr 9) and $3F, FCopperClk div 4 + 1) * 4;
      end;
    end
    else
      At := FCopperClk;
    // Mode 11: back to the start when the raster reaches 0,0
    if Mode3 and not FCopperRestarted then
    begin
      Restart := NextRasterTime(0, 0, FCopperClk div 4) * 4;
      if (Restart <= At) and (Restart <= Limit) then
      begin
        FCopperClk := Restart;
        FCopperPC := 0;
        FCopperRestarted := True;
        Continue;
      end;
    end;
    if At > Limit then
    begin
      FCopperDue := At;
      if Mode3 and not FCopperRestarted then
        FCopperDue := Min(At, NextRasterTime(0, 0, FCopperClk div 4) * 4);
      FCopperClk := Limit;
      Exit;
    end;
    FCopperClk := At;
    if (Instr and $8000) <> 0 then
      Inc(FCopperClk)
    else if Instr = 0 then
      Inc(FCopperClk)                     // NOOP
    else
    begin
      // MOVE: the picture so far with the old value, if the register
      // changes the picture (copper lists also write others, such as
      // the user register 7F to wait, tens of thousands of times a frame)
      if NextVideoReg((Instr shr 8) and $7F) then NextDrawTo(FCopperClk div 4, True);
      FCopperInRun := True;
      NextWriteReg((Instr shr 8) and $7F, Instr and $FF);
      FCopperInRun := False;
      Inc(FCopperClk, 2);
    end;
    FCopperPC := (FCopperPC + 1) and 1023;
  end;
  FCopperDue := FCopperClk;
end;

{ Draw what the beam has passed by frame T-state T: whole lines, and with
  Split the part of the current one (a register is about to change) }
procedure TSpectrum.NextDrawTo(T: Integer; Split: Boolean);
var
  StartT, X: Integer;
begin
  while FRenderLine < SCREEN_HEIGHT do
  begin
    // The frame buffer line from its left edge, 4 pixels a T-state
    StartT := FInfo.PaperTopT + (FRenderLine - BORDER_TOP) * FInfo.LineT - BORDER_LEFT div 2;
    if StartT + FB_WIDTH div 4 <= T then
    begin
      NextRenderLine(FRenderLine, FNextDrawnX, FB_WIDTH);
      FNextDrawnX := 0;
      FRenderCell := 0;
      Inc(FRenderLine);
      Continue;
    end;
    if Split and (T > StartT) then
    begin
      X := (T - StartT) * 4;
      // Not for less than 2 T-states
      if X - FNextDrawnX >= 8 then
      begin
        NextRenderLine(FRenderLine, FNextDrawnX, X);
        FNextDrawnX := X;
      end;
    end;
    Exit;
  end;
end;

procedure TSpectrum.NextRenderUpTo(T: Integer; Split: Boolean);
begin
  NextCopperRun(T);
  NextDrawTo(T, Split);
end;

{ The registers that change the picture: writing them splits the line }
function TSpectrum.NextVideoReg(Reg: Byte): Boolean;
begin
  case Reg of
    $12..$1C, $26, $27, $2F..$39, $40..$44, $4A..$4C, $64, $68..$71, $75..$79:
      Result := True;
  else
    Result := False;
  end;
end;

{ Frame line Line, from frame buffer pixel X0 to before X1 }
procedure TSpectrum.NextRenderLine(Line, X0, X1: Integer);
var
  WY, X, Y, S, I, K, Px, Py, Col, Row, Addr, Bank, Idx, Cols, SX, SY: Integer;
  UlaPal, L2Pal, SprPal, TmPal, Prio, Pri, ScrollX: Integer;
  BorderC, Fallback, C, Ink, Paper: LongWord;
  TransRGB: Word;
  UlaOn, TmOn, L2On, SprOn, LoRes, HiRes, HiColour, NextMode, Visible, Over: Boolean;
  Pixels, Attr, B, InkMask: Byte;
  ULay, L, Sp: array[0..639] of LongWord;     // 0 = transparent
  UT: array[0..639] of Boolean;            // ULA pixel under the tilemap
  LPri: array[0..639] of Boolean;
  SprLine: array[0..319] of LongWord;
  Dst: array[0..FB_WIDTH - 1] of LongWord;
  // Sprites
  AnX, AnY, APat, APo, AScaleX, AScaleY: Integer;
  AXm, AYm, ARot, AVis, AUnified, AFour: Boolean;
  Xm, Ym, Rot, Four, Relative: Boolean;
  Pat, Po, ScX, ScY, OX, OY, Tx, Ty, T2, W, H, CX1, CX2, CY1, CY2: Integer;

  function UlaColour(Index: Integer): LongWord; inline;
  begin
    if (FNextPal[UlaPal, Index] shr 1) = TransRGB then Result := 0
    else Result := FNextPalRGB[UlaPal, Index];
  end;

  procedure CopyOut;
  begin
    if X1 > X0 then Move(Dst[X0], FFrameBuffer[Line * FB_WIDTH + X0], (X1 - X0) * SizeOf(LongWord));
  end;

begin
  if X1 > FB_WIDTH then X1 := FB_WIDTH;
  if X0 >= X1 then Exit;
  WY := Line - NEXT_AREA_TOP;
  TransRGB := FNextReg[$14];
  if (FNextReg[$43] and 2) <> 0 then UlaPal := 4 + PAL_ULA else UlaPal := PAL_ULA;
  if (FNextReg[$43] and 4) <> 0 then L2Pal := 4 + PAL_L2 else L2Pal := PAL_L2;
  if (FNextReg[$43] and 8) <> 0 then SprPal := 4 + PAL_SPR else SprPal := PAL_SPR;
  if (FNextReg[$6B] and $10) <> 0 then TmPal := 4 + PAL_TM else TmPal := PAL_TM;
  NextMode := (FNextReg[$43] and 1) <> 0;     // ULANext
  Fallback := Rgb9(Nine(FNextReg[$4A]));
  // The border: paper colours (ULANext: from 128; full ink: the fallback)
  if NextMode then
  begin
    if FNextReg[$42] = $FF then BorderC := Fallback
    else BorderC := FNextPalRGB[UlaPal, 128 + FBorder];
  end
  else
    BorderC := FNextPalRGB[UlaPal, 16 + FBorder];
  if (FNextPal[UlaPal, 16 + FBorder] shr 1) = TransRGB then BorderC := Fallback;
  if (WY < 0) or (WY >= 256) then
  begin
    for X := 0 to FB_WIDTH - 1 do Dst[X] := BorderC;
    CopyOut;
    Exit;
  end;

  UlaOn := (FNextReg[$68] and $80) = 0;
  LoRes := (FNextReg[$15] and $80) <> 0;
  HiRes := (FTimexPort and 4) <> 0;
  HiColour := not HiRes and ((FTimexPort and 2) <> 0);
  FillChar(ULay, SizeOf(ULay), 0);
  FillChar(UT, SizeOf(UT), 0);
  FillChar(L, SizeOf(L), 0);
  FillChar(LPri, SizeOf(LPri), 0);
  FillChar(Sp, SizeOf(Sp), 0);

  // ULA (or LoRes): the border, and the 256x192 picture in the middle
  if UlaOn then
  begin
    for S := 0 to 639 do ULay[S] := BorderC;
    Py := WY - 32;
    if (Py >= 0) and (Py < 192) and (Py >= FNextClip[CLIP_ULA, 2]) and (Py <= FNextClip[CLIP_ULA, 3]) then
    begin
      if LoRes then
      begin
        Py := (Py + FNextReg[$33]) mod 192;
        Row := Py shr 1;
        for X := 0 to 255 do
        begin
          Px := (X + FNextReg[$32]) and 255;
          if Row < 48 then Addr := Row * 128 + (Px shr 1)
          else Addr := $2000 + (Row - 48) * 128 + (Px shr 1);
          C := UlaColour(FRam[5][Addr]);
          ULay[(X + 32) * 2] := C;
          ULay[(X + 32) * 2 + 1] := C;
        end;
      end
      else
      begin
        Py := (Py + FNextReg[$27]) mod 192;
        Addr := ((Py and $C0) shl 5) or ((Py and 7) shl 8) or ((Py and $38) shl 2);
        if HiRes then
        begin
          K := (FTimexPort shr 3) and 7;
          Ink := UlaColour(8 + K);
          Paper := UlaColour(24 + 7 - K);
          for S := 0 to 511 do
          begin
            Col := ((S shr 4) + (FNextReg[$26] shr 3)) and 31;
            if Odd(S shr 3) then Pixels := FRam[FScreenBank][$2000 + Addr + Col]
            else Pixels := FRam[FScreenBank][Addr + Col];
            if (Pixels and ($80 shr (S and 7))) <> 0 then ULay[64 + S] := Ink else ULay[64 + S] := Paper;
          end;
        end
        else
        begin
          if NextMode then
          begin
            InkMask := FNextReg[$42];
            K := 0;
            while (K < 8) and ((InkMask and (1 shl K)) <> 0) do Inc(K);
          end;
          for X := 0 to 255 do
          begin
            Px := (X + FNextReg[$26]) and 255;
            Col := Px shr 3;
            if (FTimexPort and 1) <> 0 then Pixels := FRam[FScreenBank][$2000 + Addr + Col]
            else Pixels := FRam[FScreenBank][Addr + Col];
            if HiColour then Attr := FRam[FScreenBank][$2000 + Addr + Col]
            else if (FTimexPort and 1) <> 0 then
              Attr := FRam[FScreenBank][$3800 + (Py shr 3) * 32 + Col]
            else
              Attr := FRam[FScreenBank][$1800 + (Py shr 3) * 32 + Col];
            if NextMode then
            begin
              Ink := UlaColour(Attr and InkMask);
              if InkMask = $FF then Paper := Fallback
              else Paper := UlaColour(128 + (Attr shr K));
            end
            else
            begin
              Ink := UlaColour((Attr and 7) or ((Attr shr 3) and 8));
              Paper := UlaColour(16 + ((Attr shr 3) and 15));
              if FFlashOn and ((Attr and $80) <> 0) then
              begin
                C := Ink; Ink := Paper; Paper := C;
              end;
            end;
            if (Pixels and ($80 shr (Px and 7))) <> 0 then C := Ink else C := Paper;
            ULay[(X + 32) * 2] := C;
            ULay[(X + 32) * 2 + 1] := C;
          end;
        end;
      end;
      // Clipped at the sides
      for X := 0 to 255 do
        if (X < FNextClip[CLIP_ULA, 0]) or (X > FNextClip[CLIP_ULA, 1]) then
        begin
          ULay[(X + 32) * 2] := 0;
          ULay[(X + 32) * 2 + 1] := 0;
        end;
    end;
  end;

  // Tilemap: on the ULA's layer, above it unless a tile says otherwise
  TmOn := (FNextReg[$6B] and $80) <> 0;
  if TmOn and (WY >= FNextClip[CLIP_TM, 2]) and (WY <= FNextClip[CLIP_TM, 3]) then
  begin
    if (FNextReg[$6B] and $40) <> 0 then Cols := 80 else Cols := 40;
    Row := ((WY + FNextReg[$31]) and 255);
    ScrollX := (FNextReg[$2F] and 3) shl 8 or FNextReg[$30];
    for S := 0 to 639 do
    begin
      if (S shr 1 < FNextClip[CLIP_TM, 0] * 2) or (S shr 1 > FNextClip[CLIP_TM, 1] * 2 + 1) then Continue;
      if Cols = 80 then Px := (S + ScrollX) mod 640 else Px := ((S shr 1) + ScrollX) mod 320;
      Col := Px shr 3;
      // The entry: tile number and attribute (or NR 6C's)
      if (FNextReg[$6B] and $20) <> 0 then
      begin
        Addr := (FNextReg[$6E] and $3F) shl 8 + (Row shr 3) * Cols + Col;
        if (FNextReg[$6E] and $80) <> 0 then Idx := FRam[7][Addr and $1FFF]
        else Idx := FRam[5][Addr and $3FFF];
        Attr := FNextReg[$6C];
      end
      else
      begin
        Addr := (FNextReg[$6E] and $3F) shl 8 + ((Row shr 3) * Cols + Col) * 2;
        if (FNextReg[$6E] and $80) <> 0 then
        begin
          Idx := FRam[7][Addr and $1FFF];
          Attr := FRam[7][(Addr + 1) and $1FFF];
        end
        else
        begin
          Idx := FRam[5][Addr and $3FFF];
          Attr := FRam[5][(Addr + 1) and $3FFF];
        end;
      end;
      if ((FNextReg[$6B] and 2) <> 0) and ((Attr and 1) <> 0) then Inc(Idx, 256);
      Tx := Px and 7;
      Ty := Row and 7;
      if (Attr and 8) <> 0 then Tx := 7 - Tx;
      if (Attr and 4) <> 0 then Ty := 7 - Ty;
      if (Attr and 2) <> 0 then
      begin
        T2 := Tx; Tx := Ty; Ty := 7 - T2;
      end;
      if (FNextReg[$6B] and 8) <> 0 then
      begin
        // Text mode: one bit per pixel, 7 bits of palette offset
        Addr := (FNextReg[$6F] and $3F) shl 8 + Idx * 8 + Ty;
        if (FNextReg[$6F] and $80) <> 0 then B := FRam[7][Addr and $1FFF] else B := FRam[5][Addr and $3FFF];
        K := ((Attr shr 1) shl 1) or Ord((B and ($80 shr Tx)) <> 0);
        if (FNextPal[TmPal, K] shr 1) = TransRGB then Continue;
      end
      else
      begin
        Addr := (FNextReg[$6F] and $3F) shl 8 + Idx * 32 + Ty * 4 + Tx shr 1;
        if (FNextReg[$6F] and $80) <> 0 then B := FRam[7][Addr and $1FFF] else B := FRam[5][Addr and $3FFF];
        if Odd(Tx) then B := B and 15 else B := B shr 4;
        if B = (FNextReg[$4C] and 15) then Continue;
        K := (Attr and $F0) or B;
      end;
      // A tile under the ULA (attribute bit 0, unless forced on top)
      if ((Attr and 1) <> 0) and ((FNextReg[$6B] and 3) = 0) and UlaOn and (ULay[S] <> 0) then
        Continue;
      ULay[S] := FNextPalRGB[TmPal, K];
    end;
  end;

  // Layer 2
  L2On := ((FNextL2Port and 2) <> 0) or ((FNextReg[$69] and $80) <> 0);
  if L2On then
  begin
    Bank := FNextReg[$12];
    case (FNextReg[$70] shr 4) and 3 of
      0:
        begin
          Py := WY - 32;
          if (Py >= 0) and (Py < 192) and (Py >= FNextClip[CLIP_L2, 2]) and (Py <= FNextClip[CLIP_L2, 3]) then
          begin
            Py := (Py + FNextReg[$17]) mod 192;
            for X := FNextClip[CLIP_L2, 0] to FNextClip[CLIP_L2, 1] do
            begin
              Px := (X + FNextReg[$16]) and 255;
              Addr := Py * 256 + Px;
              K := Bank + Addr shr 14;
              if K >= RAM_BANKS then Continue;
              Idx := (FRam[K][Addr and $3FFF] + (FNextReg[$70] and 15) shl 4) and 255;
              if (FNextPal[L2Pal, Idx] and $1FF) shr 1 = TransRGB then Continue;
              L[(X + 32) * 2] := FNextPalRGB[L2Pal, Idx];
              L[(X + 32) * 2 + 1] := FNextPalRGB[L2Pal, Idx];
              LPri[(X + 32) * 2] := (FNextPal[L2Pal, Idx] and $200) <> 0;
              LPri[(X + 32) * 2 + 1] := LPri[(X + 32) * 2];
            end;
          end;
        end;
      1, 2:
        if (WY >= FNextClip[CLIP_L2, 2]) and (WY <= FNextClip[CLIP_L2, 3]) then
        begin
          Py := (WY + FNextReg[$17]) and 255;
          ScrollX := (FNextReg[$71] and 1) shl 8 or FNextReg[$16];
          for S := 0 to 639 do
          begin
            if (S shr 1 < FNextClip[CLIP_L2, 0] * 2) or (S shr 1 > FNextClip[CLIP_L2, 1] * 2 + 1) then Continue;
            if ((FNextReg[$70] shr 4) and 3) = 1 then
            begin
              Px := ((S shr 1) + ScrollX) mod 320;
              Addr := Px * 256 + Py;
              K := Bank + Addr shr 14;
              if K >= RAM_BANKS then Continue;
              Idx := (FRam[K][Addr and $3FFF] + (FNextReg[$70] and 15) shl 4) and 255;
            end
            else
            begin
              Px := (S + ScrollX * 2) mod 640;
              Addr := (Px shr 1) * 256 + Py;
              K := Bank + Addr shr 14;
              if K >= RAM_BANKS then Continue;
              B := FRam[K][Addr and $3FFF];
              if Odd(Px) then B := B and 15 else B := B shr 4;
              Idx := ((FNextReg[$70] and 15) shl 4) or B;
            end;
            if (FNextPal[L2Pal, Idx] and $1FF) shr 1 = TransRGB then Continue;
            L[S] := FNextPalRGB[L2Pal, Idx];
            LPri[S] := (FNextPal[L2Pal, Idx] and $200) <> 0;
          end;
        end;
    end;
  end;

  // Sprites (at 320 pixels across): later ones on top, or the first if NR 15 bit 6
  SprOn := (FNextReg[$15] and 1) <> 0;
  if SprOn then
  begin
    FillChar(SprLine, SizeOf(SprLine), 0);
    Over := (FNextReg[$15] and 2) <> 0;
    if not Over then
    begin
      CX1 := FNextClip[CLIP_SPR, 0] + 32;
      CX2 := FNextClip[CLIP_SPR, 1] + 32;
      CY1 := FNextClip[CLIP_SPR, 2] + 32;
      CY2 := FNextClip[CLIP_SPR, 3] + 32;
    end
    else if (FNextReg[$15] and $20) <> 0 then
    begin
      CX1 := FNextClip[CLIP_SPR, 0] * 2;
      CX2 := FNextClip[CLIP_SPR, 1] * 2 + 1;
      CY1 := FNextClip[CLIP_SPR, 2];
      CY2 := FNextClip[CLIP_SPR, 3];
    end
    else
    begin
      CX1 := 0; CX2 := 319; CY1 := 0; CY2 := 255;
    end;
    if (WY >= CY1) and (WY <= CY2) then
    begin
      AVis := False; AnX := 0; AnY := 0; APat := 0; APo := 0; AScaleX := 0; AScaleY := 0;
      AXm := False; AYm := False; ARot := False; AUnified := False; AFour := False;
      for K := 0 to 127 do
      begin
        if (FNextReg[$15] and $40) <> 0 then I := 127 - K else I := K;
        Relative := ((FSprAttr[I, 3] and $40) <> 0) and ((FSprAttr[I, 4] and $C0) = $40);
        Xm := (FSprAttr[I, 2] and 8) <> 0;
        Ym := (FSprAttr[I, 2] and 4) <> 0;
        Rot := (FSprAttr[I, 2] and 2) <> 0;
        Po := FSprAttr[I, 2] shr 4;
        Pat := FSprAttr[I, 3] and $3F;
        if not Relative then
        begin
          // An anchor
          X := FSprAttr[I, 0] or ((FSprAttr[I, 2] and 1) shl 8);
          if (FSprAttr[I, 3] and $40) <> 0 then
          begin
            Y := FSprAttr[I, 1] or ((FSprAttr[I, 4] and 1) shl 8);
            Four := (FSprAttr[I, 4] and $80) <> 0;
            if Four then Pat := Pat * 2 + ((FSprAttr[I, 4] shr 6) and 1);
            ScX := (FSprAttr[I, 4] shr 3) and 3;
            ScY := (FSprAttr[I, 4] shr 1) and 3;
          end
          else
          begin
            Y := FSprAttr[I, 1];
            Four := False;
            ScX := 0;
            ScY := 0;
          end;
          Visible := (FSprAttr[I, 3] and $80) <> 0;
          AVis := Visible; AnX := X; AnY := Y; APat := Pat; APo := Po; AFour := Four;
          AScaleX := ScX; AScaleY := ScY; AXm := Xm; AYm := Ym; ARot := Rot;
          AUnified := ((FSprAttr[I, 3] and $40) <> 0) and ((FSprAttr[I, 4] and $20) <> 0);
        end
        else
        begin
          // Relative to the last anchor
          Visible := AVis and ((FSprAttr[I, 3] and $80) <> 0);
          OX := ShortInt(FSprAttr[I, 0]);
          OY := ShortInt(FSprAttr[I, 1]);
          Four := AFour;
          if Four then Pat := Pat * 2 + ((FSprAttr[I, 4] shr 5) and 1);
          if (FSprAttr[I, 4] and 1) <> 0 then Inc(Pat, APat);
          if (FSprAttr[I, 2] and 1) <> 0 then Po := (Po + APo) and 15;
          ScX := (FSprAttr[I, 4] shr 3) and 3;
          ScY := (FSprAttr[I, 4] shr 1) and 3;
          if AUnified then
          begin
            // The anchor's mirrors, rotation and scale apply to the whole
            if ARot then
            begin
              T2 := OX; OX := -OY; OY := T2;
            end;
            if AXm then OX := -OX;
            if AYm then OY := -OY;
            OX := OX shl AScaleX;
            OY := OY shl AScaleY;
            Xm := Xm xor AXm;
            Ym := Ym xor AYm;
            Rot := Rot xor ARot;
            ScX := AScaleX;
            ScY := AScaleY;
          end;
          X := (AnX + OX) and $1FF;
          Y := (AnY + OY) and $1FF;
        end;
        if not Visible then Continue;
        W := 16 shl ScX;
        H := 16 shl ScY;
        Ty := (WY - Y) and $1FF;
        if Ty >= H then Continue;
        Ty := Ty shr ScY;
        for Tx := 0 to W - 1 do
        begin
          Px := (X + Tx) and $1FF;
          if (Px < CX1) or (Px > CX2) or (Px > 319) then Continue;
          SX := Tx shr ScX;
          SY := Ty;
          if Xm then SX := 15 - SX;
          if Ym then SY := 15 - SY;
          if Rot then
          begin
            T2 := SX; SX := SY; SY := 15 - T2;
          end;
          if Four then
          begin
            B := FSprPattern[(Pat * 128 + SY * 8 + SX shr 1) and $3FFF];
            if Odd(SX) then B := B and 15 else B := B shr 4;
            if B = (FNextReg[$4B] and 15) then Continue;
            Idx := (Po shl 4) or B;
          end
          else
          begin
            B := FSprPattern[(Pat * 256 + SY * 16 + SX) and $3FFF];
            if B = FNextReg[$4B] then Continue;
            Idx := (B + Po shl 4) and 255;
          end;
          SprLine[Px] := FNextPalRGB[SprPal, Idx];
        end;
      end;
      for X := 0 to 319 do
      begin
        Sp[X * 2] := SprLine[X];
        Sp[X * 2 + 1] := SprLine[X];
      end;
    end;
  end;

  // Mixing, in the order NR 15 says (a Layer 2 priority colour on top of all)
  Prio := (FNextReg[$15] shr 2) and 7;
  for S := 0 to 639 do
  begin
    if LPri[S] then
      C := L[S]
    else
      case Prio of
        0: if Sp[S] <> 0 then C := Sp[S] else if L[S] <> 0 then C := L[S] else C := ULay[S];
        1: if L[S] <> 0 then C := L[S] else if Sp[S] <> 0 then C := Sp[S] else C := ULay[S];
        2: if Sp[S] <> 0 then C := Sp[S] else if ULay[S] <> 0 then C := ULay[S] else C := L[S];
        3: if L[S] <> 0 then C := L[S] else if ULay[S] <> 0 then C := ULay[S] else C := Sp[S];
        4: if ULay[S] <> 0 then C := ULay[S] else if Sp[S] <> 0 then C := Sp[S] else C := L[S];
        5: if ULay[S] <> 0 then C := ULay[S] else if L[S] <> 0 then C := L[S] else C := Sp[S];
      else
        // Blending: ULA + Layer 2, each channel clamped
        begin
          if Sp[S] <> 0 then C := Sp[S]
          else if (ULay[S] <> 0) and (L[S] <> 0) then
          begin
            Pri := Ord(Prio = 7) * 5;
            C := $FF000000;
            for K := 0 to 2 do
            begin
              Idx := ((ULay[S] shr (K * 8)) and $FF) * 7 div 255 + ((L[S] shr (K * 8)) and $FF) * 7 div 255 - Pri;
              if Idx < 0 then Idx := 0;
              if Idx > 7 then Idx := 7;
              C := C or LongWord((Idx * 255 div 7) shl (K * 8));
            end;
          end
          else if L[S] <> 0 then C := L[S]
          else C := ULay[S];
        end;
      end;
    if C = 0 then C := Fallback;
    FNextLine[S] := C;
  end;
  // Into the frame: the area 32 pixels (64 frame buffer pixels) in, the
  // border around it
  for X := 0 to NEXT_AREA_LEFT * 2 - 1 do
  begin
    Dst[X] := BorderC;
    Dst[FB_WIDTH - 1 - X] := BorderC;
  end;
  Move(FNextLine[0], Dst[NEXT_AREA_LEFT * 2], 640 * SizeOf(LongWord));
  CopyOut;
end;

{ nextvideotest: the ZX Spectrum Next's display layers and DMA, set up by
  writing its registers and ports directly (no distribution needed: the
  machine sits in its boot ROM): a zxnDMA copy, a Layer 2 pixel, a sprite,
  a tile, the fallback colour where everything is transparent, and the
  copper changing it in the middle of a line.

    nextvideotest <roms folder> }
program nextvideotest;

{$mode objfpc}{$H+}

uses
  SysUtils, Models, Spectrum;

var
  Failures: Integer = 0;
  Sp: TSpectrum;
  Pixels: array of LongWord;

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

procedure NextReg(Reg, Value: Byte);
begin
  Out_($243B, Reg);
  Out_($253B, Value);
end;

{ The colour at (X, Y) of the 320x256 area, after a frame }
function Pixel(X, Y: Integer): LongWord;
begin
  Result := Pixels[(Y + 16) * FB_WIDTH + (X + 16) * 2] and $FFFFFF;
end;

procedure Frame;
begin
  // The CPU idles in the boot ROM; the display is drawn as the frame goes
  Sp.RunFrame;
  Sp.CopyFrameBuffer(@Pixels[0]);
end;

const
  // WAIT 100,16 / MOVE NR 4A,$1C / WAIT 101,0 / MOVE NR 4A,$E0 / HALT
  COPPER: array[0..9] of Byte = ($A0, $64, $4A, $1C, $80, $65, $4A, $E0, $FF, $FF);
var
  I: Integer;
begin
  Sp := TSpectrum.Create(sm48K, ParamStr(1));
  try
    Sp.NextFirmwareBoot := True;
    Sp.SetModel(smZXNext);
    SetLength(Pixels, FB_WIDTH * SCREEN_HEIGHT);
    // Leave configuration mode, all RAM at 4000-FFFF as after NextZXOS
    NextReg($03, $33);
    // zxnDMA: 16 bytes from 8000 to 9000, memory to memory, both incrementing
    for I := 0 to 15 do Sp.Poke($8000 + I, I + 1);
    Out_($6B, $83);                       // disable
    Out_($6B, $7D);                       // WR0: A->B, port A address and length follow
    Out_($6B, $00); Out_($6B, $80);       // A = 8000
    Out_($6B, 16); Out_($6B, 0);          // length 16
    Out_($6B, $14);                       // WR1: A memory, increments
    Out_($6B, $10);                       // WR2: B memory, increments
    Out_($6B, $AD);                       // WR4: continuous, port B address follows
    Out_($6B, $00); Out_($6B, $90);       // B = 9000
    Out_($6B, $CF);                       // load
    Out_($6B, $87);                       // enable
    Check((Sp.Peek($9000) = 1) and (Sp.Peek($900F) = 16) and (Sp.Peek($9010) = 0), 'zxnDMA copies memory');

    // Fallback colour where all layers are transparent: ULA off
    NextReg($68, $80);
    NextReg($4A, $E0);                    // red
    Frame;
    Check(Pixel(100, 100) = $FF0000, 'fallback colour with every layer transparent');

    // Layer 2 (256x192, bank 8): a pixel of colour $1C (green) at 10,20
    NextReg($12, 8);
    Sp.RamBank(8)^[20 * 256 + 10] := $1C;
    Sp.RamBank(8)^[20 * 256 + 11] := $E3;    // transparent: the fallback shows
    Out_($123B, $02);                     // Layer 2 on
    Frame;
    Check(Pixel(32 + 10, 32 + 20) = $00FF00, 'Layer 2 pixel');
    Check(Pixel(32 + 11, 32 + 20) = $FF0000, 'Layer 2 transparent pixel');
    Out_($123B, $00);

    // A sprite: pattern 0 all colour 3 (blue in the default palette) but
    // its top-left pixel transparent, at 50,60, over the border allowed
    Out_($303B, 0);
    for I := 0 to 255 do
      if I = 0 then Out_($5B, $E3) else Out_($5B, $03);
    Out_($303B, 0);
    Out_($57, 50);                        // X
    Out_($57, 60);                        // Y
    Out_($57, 0);                         // no palette offset, mirror, rotation
    Out_($57, $80);                       // visible, pattern 0, 4 bytes
    NextReg($15, $03);                    // sprites on, over the border
    Frame;
    Check(Pixel(55, 65) = $0000FF, 'sprite pixel');
    Check(Pixel(50, 60) = $FF0000, 'sprite transparent pixel');
    Check(Pixel(70, 80) = $FF0000, 'nothing outside the sprite');
    NextReg($15, $00);

    // Tilemap 40x32, no attributes: tile 1 all colour 2 at row 0, column 1
    NextReg($6E, $40);                    // map at 4000 in bank 5
    NextReg($6F, $50);                    // tiles at 5000
    FillChar(Sp.RamBank(5)^[0], 40 * 32, 0);
    Sp.RamBank(5)^[1] := 1;
    FillChar(Sp.RamBank(5)^[$1000], 32, $FF);     // tile 0: transparent (15)
    FillChar(Sp.RamBank(5)^[$1000 + 32], 32, $22);
    NextReg($4C, 15);
    NextReg($6B, $A0);                    // on, 40x32, 8-bit entries
    Frame;
    // Colour 2 in the default palette: RRRGGGBB 00000010, blue 5 of 7
    Check(Pixel(8 + 3, 4) = $0000B6, 'tile pixel');
    Check(Pixel(3, 4) = $FF0000, 'transparent tile');

    // The copper within a line: the fallback colour green from position 16
    // (paper pixel 128) of line 100, red again from line 101
    NextReg($6B, 0);
    NextReg($4A, $E0);
    NextReg($61, 0);
    NextReg($62, 0);
    for I := 0 to High(COPPER) do NextReg($63, COPPER[I]);
    NextReg($62, $C0);
    Frame;
    Frame;
    Check(Pixel(32 + 100, 32 + 99) = $FF0000, 'copper: line 99 as it was');
    Check(Pixel(32 + 120, 32 + 100) = $FF0000, 'copper: line 100 before the WAIT position');
    Check(Pixel(32 + 136, 32 + 100) = $00FF00, 'copper: line 100 after it');
    Check(Pixel(10, 32 + 101) = $00FF00, 'copper: line 101''s left border');
    Check(Pixel(32 + 50, 32 + 101) = $FF0000, 'copper: line 101 from its first pixel');
    NextReg($62, 0);
    if Failures = 0 then WriteLn('ZX Spectrum Next display, copper and DMA: all passed');
  finally
    Sp.Free;
  end;
  if Failures > 0 then Halt(1);
end.

{ videotest: ULAplus, Timex screen modes and Radastan. Sets screen memory
  and the ports, draws a frame (without running any code) and checks the
  frame buffer, which is twice as wide as the picture (FB_WIDTH).

    videotest <roms folder> }
program videotest;

{$mode objfpc}{$H+}

uses
  SysUtils, Models, Spectrum;

var
  Failures: Integer = 0;
  Sp: TSpectrum;
  Frame: array of LongWord;

procedure Check(Cond: Boolean; const What: string);
begin
  if not Cond then
  begin
    WriteLn('FAIL  ', What);
    Inc(Failures);
  end;
end;

procedure OutPort(Port: Word; Value: Byte);
var
  T: Integer;
begin
  T := 0;
  Sp.WritePort(Port, Value, T);
end;

function InPort(Port: Word): Byte;
var
  T: Integer;
begin
  T := 0;
  Result := Sp.ReadPort(Port, T);
end;

{ Draw the whole frame with what is in memory and the ports now }
procedure Draw;
begin
  Sp.RestartRender;
  Sp.RenderUpTo(MaxInt);
  Sp.CopyFrameBuffer(@Frame[0]);
end;

{ Frame buffer pixel at paper X (0-511, in half pixels) and line Y (0-191) }
function Px(X, Y: Integer): LongWord;
begin
  Result := Frame[(BORDER_TOP + Y) * FB_WIDTH + BORDER_LEFT * 2 + X] and $FFFFFF;
end;

function BorderPx: LongWord;
begin
  Result := Frame[2 * FB_WIDTH + 2] and $FFFFFF;
end;

procedure SetEntry(Index, Value: Byte);
begin
  OutPort($BF3B, Index);
  OutPort($FF3B, Value);
end;

procedure Clear;
var
  A: Integer;
begin
  for A := $4000 to $7FFF do Sp.Poke(A, 0);
end;

begin
  SetLength(Frame, FB_WIDTH * SCREEN_HEIGHT);
  Sp := TSpectrum.Create(sm48K, ParamStr(1));
  try
    Sp.Reset(True);

    // Standard screen: every pixel twice
    Clear;
    Sp.Poke($4000, $80);
    Sp.Poke($5800, $38);    // ink 0, paper 7
    Draw;
    Check((Px(0, 0) = 0) and (Px(1, 0) = 0) and (Px(2, 0) = Px(3, 0)) and (Px(2, 0) <> 0),
      'standard screen, pixels doubled');

    // Options off: the ports do nothing
    OutPort($BF3B, $40);
    OutPort($FF3B, 1);
    OutPort($00FF, 6);
    Draw;
    Check((Px(0, 0) = 0) and (Px(2, 0) <> 0), 'ULAplus and Timex off: standard screen');

    // ULAplus: GGGRRRBB, FLASH and BRIGHT choose the palette
    Sp.ULAPlusEnabled := True;
    SetEntry(0, $03);       // palette 0, ink 0: blue
    SetEntry(15, $1C);      // palette 0, paper 7: red
    SetEntry(48 + 1, $E0);  // palette 3 (FLASH+BRIGHT), ink 1: green
    OutPort($BF3B, $40);
    OutPort($FF3B, 1);
    Sp.Poke($4001, $80);
    Sp.Poke($5801, $C1);    // FLASH, BRIGHT, ink 1
    Draw;
    Check(Px(0, 0) = $0000FF, Format('ULAplus ink: %.6X', [Px(0, 0)]));
    Check(Px(2, 0) = $FF0000, Format('ULAplus paper: %.6X', [Px(2, 0)]));
    Check(Px(16, 0) = $00FF00, Format('ULAplus palette 3 ink: %.6X', [Px(16, 0)]));
    OutPort($BF3B, 0);
    Check(InPort($FF3B) = $03, 'ULAplus palette entry read back');
    OutPort($BF3B, $40);
    Check(InPort($FF3B) = 1, 'ULAplus mode read back');
    OutPort($FF3B, 0);
    Sp.ULAPlusEnabled := False;

    // Timex: second screen at 6000
    Sp.TimexEnabled := True;
    Clear;
    Sp.Poke($6000, $80);
    Sp.Poke($7800, $38);
    OutPort($00FF, 1);
    Draw;
    Check((Px(0, 0) = 0) and (Px(2, 0) <> 0), 'Timex second screen');
    Check(InPort($00FF) = 1, 'Timex register read back on port FF');

    // Timex hi-colour: an attribute per 8x1 cell at 6000
    Clear;
    Sp.Poke($4000, $FF);
    Sp.Poke($4100, $FF);    // line 1
    Sp.Poke($6000, $02);    // red ink
    Sp.Poke($6100, $04);    // green ink
    OutPort($00FF, 2);
    Draw;
    Check(Px(0, 0) = (Palette[2] and $FFFFFF), 'Timex hi-colour, line 0');
    Check(Px(0, 1) = (Palette[4] and $FFFFFF), 'Timex hi-colour, line 1');

    // Timex hi-res: 512 pixels, columns from 4000 and 6000; ink from bits 3-5
    Clear;
    Sp.Poke($4000, $80);
    Sp.Poke($6000, $01);
    OutPort($00FF, 6 or (1 shl 3));   // blue on yellow
    Draw;
    Check(Px(0, 0) = (Palette[9] and $FFFFFF), 'Timex hi-res, first pixel ink');
    Check(Px(1, 0) = (Palette[14] and $FFFFFF), 'Timex hi-res, second pixel paper');
    Check(Px(15, 0) = (Palette[9] and $FFFFFF), 'Timex hi-res, 16th pixel from 6000');
    Check(BorderPx = (Palette[14] and $FFFFFF), 'Timex hi-res border is the paper');
    OutPort($00FF, 0);
    Sp.TimexEnabled := False;

    // Radastan: 128x96, 4 bits per pixel, ULAplus palette 0-15
    Sp.RadastanEnabled := True;
    Clear;
    SetEntry(1, $1C);
    SetEntry(2, $E0);
    Sp.Poke($4000, $12);
    OutPort($BF3B, $40);
    OutPort($FF3B, 3);
    Draw;
    Check((Px(0, 0) = $FF0000) and (Px(3, 0) = $FF0000) and (Px(4, 0) = $00FF00) and
      (Px(7, 0) = $00FF00), 'Radastan pixels (each 2x2)');
    Check(Px(0, 1) = $FF0000, 'Radastan pixel, second line');
    OutPort($FF3B, 0);
    Draw;
    Check(Px(0, 0) <> $FF0000, 'Radastan off');
    // The ZX-Uno register 40h switches it on too
    OutPort($FC3B, $40);
    OutPort($FD3B, 3);
    Draw;
    Check(Px(0, 0) = $FF0000, 'Radastan on with the ZX-Uno register');
  finally
    Sp.Free;
  end;
  if Failures = 0 then
    WriteLn('ULAplus, Timex and Radastan: all passed')
  else
  begin
    WriteLn('ULAplus, Timex and Radastan: ', Failures, ' failures');
    Halt(1);
  end;
end.

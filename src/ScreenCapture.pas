{ ScreenCapture: save the Spectrum screen as a .SCR file (the 6912 bytes of
  screen memory) or as a PNG image of the display. }
unit ScreenCapture;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, FPImage, FPWritePNG, Models, Spectrum;

{ Screen memory being displayed (bank 5, or 7 on 128K models showing it); on
  an Amstrad CPC the 16K of screen memory the CRTC shows, behind an AMSDOS
  header (a binary for &C000, as CPC screen files have): the picture's
  pixels, not its palette }
procedure SaveSCR(Spec: TSpectrum; const FileName: string);

{ Pixels: FB_WIDTH x SCREEN_HEIGHT $AARRGGBB, as from CopyFrameBuffer (twice
  as wide as the picture). Scale 1 or 2 (2 shows the Timex 512-pixel hi-res
  in full); without the border only the 256x192 paper area is saved. Fine:
  an Amstrad CPC's picture, whose 640-pixel mode uses all the columns: at 1x
  each pair of columns is averaged, and the area without the border is the
  320x200 screen. }
procedure SavePNG(const Pixels: array of LongWord; const FileName: string; Scale: Integer;
  Border: Boolean; Fine: Boolean = False);

implementation

function Mix2(A, B: LongWord): LongWord;
begin
  Result := $FF000000 or ((((A shr 16) and $FF) + ((B shr 16) and $FF)) shr 1) shl 16 or
    ((((A shr 8) and $FF) + ((B shr 8) and $FF)) shr 1) shl 8 or (((A and $FF) + (B and $FF)) shr 1);
end;

procedure SaveCPCSCR(Spec: TSpectrum; const FileName: string);
var
  Block: array[0..16383] of Byte;
  Header: array[0..127] of Byte;
  Page, I, Sum: Integer;
  Name: string;
  F: TFileStream;
begin
  // The CRTC's start address (R12 bits 4-5) is the 16K block of the screen
  Page := (Spec.CPC.CrtcReg(12) shr 4) and 3;
  Move(Spec.CPC.RamBank(Page)^[0], Block[0], SizeOf(Block));
  FillChar(Header, SizeOf(Header), 0);
  Name := UpperCase(ChangeFileExt(ExtractFileName(FileName), ''));
  FillChar(Header[1], 11, Ord(' '));
  for I := 1 to Min(Length(Name), 8) do
    if Name[I] in ['A'..'Z', '0'..'9'] then Header[I] := Ord(Name[I]) else Header[I] := Ord('_');
  Header[9] := Ord('S'); Header[10] := Ord('C'); Header[11] := Ord('R');
  Header[18] := 2;                 // binary
  Header[21] := $00; Header[22] := $C0;   // loads at C000
  Header[24] := $00; Header[25] := $40;   // logical length
  Header[26] := $00; Header[27] := $00;   // entry address (none)
  Header[64] := $00; Header[65] := $40; Header[66] := $00;   // length (3 bytes)
  Sum := 0;
  for I := 0 to 66 do Inc(Sum, Header[I]);
  Header[67] := Sum and $FF;
  Header[68] := (Sum shr 8) and $FF;
  F := TFileStream.Create(FileName, fmCreate);
  try
    F.WriteBuffer(Header, SizeOf(Header));
    F.WriteBuffer(Block, SizeOf(Block));
  finally
    F.Free;
  end;
end;

procedure SaveSCR(Spec: TSpectrum; const FileName: string);
var
  Bank: Integer;
  F: TFileStream;
begin
  if Spec.CPC <> nil then
  begin
    SaveCPCSCR(Spec, FileName);
    Exit;
  end;
  if (Spec.Info.Memory <> mk48K) and ((Spec.Port7FFD and $08) <> 0) then Bank := 7 else Bank := 5;
  F := TFileStream.Create(FileName, fmCreate);
  try
    F.WriteBuffer(Spec.RamBank(Bank)^[0], 6912);
  finally
    F.Free;
  end;
end;

procedure SavePNG(const Pixels: array of LongWord; const FileName: string; Scale: Integer;
  Border: Boolean; Fine: Boolean);
var
  Img: TFPMemoryImage;
  Writer: TFPWriterPNG;
  X0, Y0, W, H, X, Y: Integer;
  P: LongWord;
  C: TFPColor;
begin
  if Border then
  begin
    X0 := 0; Y0 := 0; W := SCREEN_WIDTH; H := SCREEN_HEIGHT;
  end
  else if Fine then
  begin
    X0 := 16; Y0 := BORDER_TOP; W := 320; H := 200;   // 2 characters of border: 16 pixels
  end
  else
  begin
    X0 := BORDER_LEFT; Y0 := BORDER_TOP; W := 256; H := 192;
  end;
  Img := TFPMemoryImage.Create(W * Scale, H * Scale);
  Writer := TFPWriterPNG.Create;
  try
    Writer.UseAlpha := False;
    Writer.WordSized := False;   // 8 bits per channel
    for Y := 0 to H * Scale - 1 do
      for X := 0 to W * Scale - 1 do
      begin
        P := Pixels[(Y0 + Y div Scale) * FB_WIDTH + X0 * 2 + X * 2 div Scale];
        if Fine and (Scale = 1) then
          P := Mix2(P, Pixels[(Y0 + Y) * FB_WIDTH + X0 * 2 + X * 2 + 1]);
        C.Red := ((P shr 16) and $FF) * $101;
        C.Green := ((P shr 8) and $FF) * $101;
        C.Blue := (P and $FF) * $101;
        C.Alpha := $FFFF;
        Img.Colors[X, Y] := C;
      end;
    Img.SaveToFile(FileName, Writer);
  finally
    Writer.Free;
    Img.Free;
  end;
end;

end.

{ ScreenCapture: save the Spectrum screen as a .SCR file (the 6912 bytes of
  screen memory) or as a PNG image of the display. }
unit ScreenCapture;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, FPImage, FPWritePNG, Models, Spectrum;

{ Screen memory being displayed (bank 5, or 7 on 128K models showing it) }
procedure SaveSCR(Spec: TSpectrum; const FileName: string);

{ Pixels: FB_WIDTH x SCREEN_HEIGHT $AARRGGBB, as from CopyFrameBuffer (twice
  as wide as the picture). Scale 1 or 2 (2 shows the Timex 512-pixel hi-res
  in full); without the border only the 256x192 paper area is saved. }
procedure SavePNG(const Pixels: array of LongWord; const FileName: string; Scale: Integer;
  Border: Boolean);

implementation

procedure SaveSCR(Spec: TSpectrum; const FileName: string);
var
  Bank: Integer;
  F: TFileStream;
begin
  if (Spec.Info.Memory <> mk48K) and ((Spec.Port7FFD and $08) <> 0) then Bank := 7 else Bank := 5;
  F := TFileStream.Create(FileName, fmCreate);
  try
    F.WriteBuffer(Spec.RamBank(Bank)^[0], 6912);
  finally
    F.Free;
  end;
end;

procedure SavePNG(const Pixels: array of LongWord; const FileName: string; Scale: Integer;
  Border: Boolean);
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

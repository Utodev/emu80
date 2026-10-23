{ FramePresenter: from the machine's picture (the frame buffer of
  TSpectrum, 352x288 pixels, twice as wide for the Timex hi-res) to what is
  shown: scaled by a whole number, in black and white if asked, with
  scanlines, and with the Spectrum's frames taken as the fields of an
  interlaced picture (progressive, Bob or Weave). It needs no window system:
  the main window and the embeddable library draw with it, so there is one
  implementation of it. }
unit FramePresenter;

{$mode objfpc}{$H+}
{$R-}{$Q-}

interface

uses
  Models, Spectrum;

type
  TPresentOptions = record
    Deinterlace: TDeinterlace;
    Scanlines: Boolean;
    { The Amstrad CPC's picture, whose columns are all different (the 640-pixel
      mode): at 1x each pair is averaged }
    Fine: Boolean;
    { The monitor: 0 colour; 1 black and white, 2 green phosphor, 3 orange
      phosphor (the picture as shades of grey or of its phosphor) }
    Monitor: Byte;
  end;

{ The largest whole scale that fits an area (at least 1) }
function FitScale(AreaW, AreaH: Integer): Integer;

{ Cur and Prev: the latest frame and the one before (FB_WIDTH x
  SCREEN_HEIGHT pixels, $00RRGGBB); CurOdd: Cur is the odd field. The picture
  is written as 32-bit $FFRRGGBB pixels, SCREEN_WIDTH * Scale wide and
  SCREEN_HEIGHT * Scale high, rows Stride bytes apart from Dest. }
procedure PresentFrame(Cur, Prev: PLongWord; CurOdd: Boolean; Scale: Integer;
  const Options: TPresentOptions; Dest: PByte; Stride: Integer);

implementation

function FitScale(AreaW, AreaH: Integer): Integer;
begin
  Result := AreaW div SCREEN_WIDTH;
  if AreaH div SCREEN_HEIGHT < Result then Result := AreaH div SCREEN_HEIGHT;
  if Result < 1 then Result := 1;
end;

procedure PresentFrame(Cur, Prev: PLongWord; CurOdd: Boolean; Scale: Integer;
  const Options: TPresentOptions; Dest: PByte; Stride: Integer);
var
  X, Y, I, K, F, Src, OutW: Integer;
  Lines, Darks: array[0..1] of array of LongWord;
  Field: array[0..1] of PLongWord;
  P, Q, Grey: LongWord;
  Scan, Weave, Blend: Boolean;
  Row: PByte;

  function Darker(P: LongWord): LongWord;
  begin
    Result := $FF000000 or ((((P shr 16) and $FF) * 5) shr 3) shl 16 or
      ((((P shr 8) and $FF) * 5) shr 3) shl 8 or (((P and $FF) * 5) shr 3);
  end;

begin
  if Scale < 1 then Scale := 1;
  OutW := SCREEN_WIDTH * Scale;
  // Scanlines: from 2x, the lower rows of every Spectrum line are darker
  Scan := Options.Scanlines and (Scale >= 2);
  // Bob shows both fields blended (the mean of each colour); Weave the odd
  // field's lines over the even one's, each half of a line's rows (at 1x,
  // with no room for both, they are blended as Bob)
  Blend := (Options.Deinterlace = dlBob) or ((Options.Deinterlace = dlWeave) and (Scale < 2));
  Weave := (Options.Deinterlace = dlWeave) and (Scale >= 2);
  // The odd field above
  if CurOdd then
  begin
    Field[0] := Cur;
    Field[1] := Prev;
  end
  else
  begin
    Field[0] := Prev;
    Field[1] := Cur;
  end;
  for K := 0 to 1 do
  begin
    SetLength(Lines[K], OutW);
    SetLength(Darks[K], OutW);
  end;
  for Y := 0 to SCREEN_HEIGHT - 1 do
  begin
    // Build one scaled line (two with Weave: one from each field), then
    // copy it Scale times. The frame buffer is twice as wide (Timex
    // hi-res): each output pixel takes its column
    for K := 0 to Ord(Weave) do
      for X := 0 to OutW - 1 do
      begin
        Src := Y * FB_WIDTH + X * 2 div Scale;
        if Weave then
          P := Field[K][Src]
        else if Blend then
        begin
          P := Cur[Src];
          Q := Prev[Src];
          P := ((((P shr 16) and $FF) + ((Q shr 16) and $FF)) shr 1) shl 16 or
            ((((P shr 8) and $FF) + ((Q shr 8) and $FF)) shr 1) shl 8 or
            (((P and $FF) + (Q and $FF)) shr 1) or $FF000000;
        end
        else
        begin
          P := Cur[Src];
          if Options.Fine and (Scale = 1) then
          begin
            Q := Cur[Src + 1];
            P := ((((P shr 16) and $FF) + ((Q shr 16) and $FF)) shr 1) shl 16 or
              ((((P shr 8) and $FF) + ((Q shr 8) and $FF)) shr 1) shl 8 or
              (((P and $FF) + (Q and $FF)) shr 1) or $FF000000;
          end;
        end;
        if Options.Monitor <> 0 then
        begin
          // A monochrome monitor: the brightness of the colour, in grey or in
          // its phosphor's colour
          Grey := (((P shr 16) and $FF) * 77 + ((P shr 8) and $FF) * 150 + (P and $FF) * 29) shr 8;
          case Options.Monitor of
            2: P := $FF000000 or ((Grey * 40 div 255) shl 16) or (Grey shl 8) or (Grey * 60 div 255);
            3: P := $FF000000 or (Grey shl 16) or ((Grey * 150 div 255) shl 8) or (Grey * 10 div 255);
          else
            P := $FF000000 or (Grey shl 16) or (Grey shl 8) or Grey;
          end;
        end;
        Lines[K][X] := P or $FF000000;
        if Scan then Darks[K][X] := Darker(P);
      end;
    for I := 0 to Scale - 1 do
    begin
      Row := Dest + (Y * Scale + I) * Stride;
      // Weave: the upper half of the rows from the odd field, the lower
      // half from the even one
      if Weave and (I * 2 >= Scale) then F := 1 else F := 0;
      if Scan and (I >= (Scale + 1) div 2) then
        Move(Darks[F][0], Row^, OutW * 4)
      else
        Move(Lines[F][0], Row^, OutW * 4);
    end;
  end;
end;

end.

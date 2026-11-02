{ c64spec: the Commodore 64 through TSpectrum (the way the emulator uses it): boots and checks the screen and sound. }
program c64spec;

{$mode objfpc}{$H+}

uses
  SysUtils, Models, Spectrum, C64, C64Vic;

var
  Sp: TSpectrum;
  I, NonZero, Total: Integer;
  Buf: array of LongWord;
  S: PSmallInt;
begin
  Sp := TSpectrum.Create(smC64, ParamStr(1));
  SetLength(Buf, FB_WIDTH * SCREEN_HEIGHT);
  Total := 0;
  for I := 1 to 150 do
  begin
    Sp.RunFrame;
    Inc(Total, Sp.SampleCount);
  end;
  Sp.CopyFrameBuffer(@Buf[0]);
  NonZero := 0;
  for I := 0 to High(Buf) do if Buf[I] <> C64_PALETTE[0] then Inc(NonZero);
  WriteLn('samples/frame ', Total div 150, ' pixels not black ', NonZero, ' model ', Sp.Info.Name);
  for I := 0 to 5 do begin Write(I, ': '); for NonZero := 0 to 39 do Write(Chr(Sp.C64Hw.PeekRam($0400 + 40 * I + NonZero) and 63 + 32 * Ord((Sp.C64Hw.PeekRam($0400 + 40 * I + NonZero) and 63) < 32) * 2)); WriteLn; end;
  if Sp.C64Hw.PeekRam($0400 + 40 * 5) = 18 then WriteLn('ok: READY.') else WriteLn('FAIL: no READY');
  Sp.Free;
end.

{ c64back: the debugger's step back on the Commodore 64. The machine is kept (SaveState) while the 1541 is reading a
  directory, runs on for a while, is put back (LoadState) and runs the same again: it must end exactly as the first time
  (the RAM, the registers, the colour RAM, the picture, the drive's RAM and CPU).
    c64back <roms folder> }
program c64back;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Models, Spectrum, C64, C64Disk, C64Vic;

const
  STEPS = 200000;      // about ten frames

var
  Sp: TSpectrum;
  D: TD64Image;
  St: TMachineState;
  A, B: string;
  Failures: Integer = 0;
  I: Integer;

procedure Check(Cond: Boolean; const What: string);
begin
  if Cond then WriteLn('ok    ', What)
  else
  begin
    WriteLn('FAIL  ', What);
    Inc(Failures);
  end;
end;

procedure Run(Frames: Integer);
var
  I: Integer;
begin
  for I := 1 to Frames do Sp.RunFrame;
end;

{ What the run left: the 6510's registers, the RAM, the colour RAM, the picture and the first drive }
function Fingerprint: string;
var
  C: TC64;
  J: Integer;
  H: QWord;
begin
  C := Sp.C64Hw;
  Result := Format('PC=%.4x A=%.2x X=%.2x Y=%.2x SP=%.2x P=%.2x cyc=%d', [C.Cpu.PC, C.Cpu.A, C.Cpu.X, C.Cpu.Y, C.Cpu.SP,
    C.Cpu.P, C.Cpu.Cycles]);
  H := 0;
  for J := 0 to $FFFF do H := H * 31 + C.PeekRam(J);
  Result := Result + Format(' ram=%x', [H]);
  H := 0;
  for J := 0 to 1023 do H := H * 31 + C.Vic.ColorRam[J];
  for J := 0 to High(C.Vic.Frame) do H := H * 31 + C.Vic.Frame[J];
  Result := Result + Format(' vic=%x raster=%d', [H, C.Vic.Raster]);
  H := 0;
  for J := 0 to $7FF do H := H * 31 + C.Drive[0].Peek(J);
  Result := Result + Format(' drive PC=%.4x cyc=%d ram=%x track=%d', [C.Drive[0].Cpu.PC, C.Drive[0].Cpu.Cycles, H,
    C.Drive[0].Track]);
end;

begin
  Sp := TSpectrum.Create(smC64, ParamStr(1));
  D := TD64Image.Create;
  D.Format('TEST DISK', '64');
  Sp.C64Hw.InsertDisk(0, D);
  Run(150);
  Sp.C64Hw.TypeText('LOAD"$",8'#13);
  Run(40);
  Check(not Sp.C64Hw.Typing, 'the command was typed');
  Check(Sp.C64Hw.Drive[0].Motor, 'the drive is working');
  St := Sp.SaveState;
  for I := 1 to STEPS do Sp.StepInstruction;
  Run(20);
  A := Fingerprint;
  Check(Sp.LoadState(St), 'the state is put back');
  for I := 1 to STEPS do Sp.StepInstruction;
  Run(20);
  B := Fingerprint;
  WriteLn('      ', A);
  if A <> B then WriteLn('      ', B);
  Check(A = B, 'the second run ends as the first');
  St.Free;
  Sp.Free;
  if Failures > 0 then Halt(1);
end.

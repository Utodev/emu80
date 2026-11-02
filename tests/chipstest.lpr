{ chipstest: the debugger's chips window on the ZX Spectrum and the Amstrad CPC (TSpectrum.ChipRegister and
  SetChipRegister: written as an OUT, kept out of the port log, what was selected selected again), and the C64's log
  of the accesses to its chips (the debugger's ports zone).
    chipstest <roms folder> }
program chipstest;

{$mode objfpc}{$H+}

uses
  SysUtils, Models, Spectrum, C64;

var
  Sp: TSpectrum;
  Failures: Integer = 0;
  I, N: Integer;
  A: TC64IoAccess;
  Ok: Boolean;

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

begin
  // ZX Spectrum 128K
  Sp := TSpectrum.Create(sm128K, ParamStr(1));
  Run(50);
  Check(Sp.ChipRegisterExists($001) and not Sp.ChipRegisterExists($002), 'the 128K has 7FFD and not 1FFD');
  N := Sp.PortLogCount;
  Sp.SetChipRegister($000, 2);
  Check(Sp.ChipRegister($000) = 2, 'FE written: border 2');
  Sp.SetChipRegister($001, 3);
  Check((Sp.Port7FFD and 7) = 3, '7FFD written: bank 3 at C000');
  Check(Sp.SlotBank(3) = 3, 'the paging follows');
  Sp.SetChipRegister($100, 5);
  Sp.SetChipRegister($117, $2A);
  Check(Sp.ChipRegister($117) = $2A, 'AY register 7 written');
  Check(Sp.ChipRegister($100) = 5, 'the AY register selected is selected again');
  Check(Sp.PortLogCount = N, 'the writes are not in the port log');
  Sp.Free;

  // ZX Spectrum 48K: no paging, no AY
  Sp := TSpectrum.Create(sm48K, ParamStr(1));
  Check(not Sp.ChipRegisterExists($001) and not Sp.ChipRegisterExists($110), 'the 48K has no 7FFD and no AY');
  Sp.Free;

  // Amstrad CPC 6128
  Sp := TSpectrum.Create(smCPC6128, ParamStr(1));
  Run(50);
  Sp.SetChipRegister($030, 12);
  Sp.SetChipRegister($041, 32);
  Check(Sp.ChipRegister($041) = 32, 'CRTC R1 written');
  Check(Sp.ChipRegister($030) = 12, 'the CRTC register selected is selected again');
  Sp.SetChipRegister($000, 3);
  Sp.SetChipRegister($015, $0B);
  Sp.SetChipRegister($020, $14);
  Check(Sp.ChipRegister($015) = $0B, 'pen 5 given colour 0B');
  Check(Sp.ChipRegister($020) = $14, 'the border given colour 14');
  Check(Sp.ChipRegister($000) = 3, 'the pen selected is selected again');
  Sp.SetChipRegister($088, 15);
  Check(Sp.ChipRegister($088) = 15, 'PSG register 8 written');
  Sp.Free;

  // Commodore 64: the accesses to the chips
  if FileExists(IncludeTrailingPathDelimiter(ParamStr(1)) + 'c64' + PathDelim + 'Kernal.rom') then
  begin
    Sp := TSpectrum.Create(smC64, ParamStr(1));
    Run(200);    // past the KERNAL's RAM test (no interrupts): at READY.
    N := Sp.C64Hw.IoLogCount;
    Check(N = C64_IO_LOG, 'the C64 logs the accesses to its chips');
    Ok := True;
    for I := 0 to N - 1 do
    begin
      A := Sp.C64Hw.IoLog(I);
      if not ((A.Addr < 2) or ((A.Addr >= $D000) and (A.Addr <= $DFFF) and ((A.Addr and $0C00) <> $0800))) then
        Ok := False;
    end;
    Check(Ok, 'only the chips and the 6510''s port, not the colour RAM');
    Sp.StepInstruction;
    Check(Sp.C64Hw.IoLog(0).Step <= Sp.C64Hw.InstrCount, 'each access knows its instruction');
    Sp.Free;
  end;
  if Failures > 0 then Halt(1);
end.

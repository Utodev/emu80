{ poketest: what the debugger (and POKE) may write: RAM always, ROM only
  with ROM changes allowed, and RAM paged at 0000-3FFF (the +3's special
  modes, the DivMMC's RAM at 2000) as RAM.

    poketest <roms folder> <esxdos folder> }
program poketest;

{$mode objfpc}{$H+}

uses
  SysUtils, Models, Spectrum;

var
  Failures: Integer = 0;

procedure Check(Cond: Boolean; const What: string);
begin
  if not Cond then
  begin
    WriteLn('FAIL  ', What);
    Inc(Failures);
  end;
end;

procedure OutPort(Sp: TSpectrum; Port: Word; Value: Byte);
var
  T: Integer;
begin
  T := 0;
  Sp.WritePort(Port, Value, T);
end;

var
  Sp: TSpectrum;
  Old: Byte;
begin
  // 48K: ROM at 0000, RAM above
  Sp := TSpectrum.Create(sm48K, ParamStr(1));
  try
    Check(Sp.MemoryAt($0000) = maRom, '48K: ROM at 0000');
    Check(Sp.MemoryAt($8000) = maRam, '48K: RAM at 8000');
    Old := Sp.Peek($0001);
    Sp.Poke($0001, Old xor $FF);
    Check(Sp.Peek($0001) = Old, 'ROM unchanged without ROM changes allowed');
    Sp.RomWritable := True;
    Sp.Poke($0001, Old xor $FF);
    Check(Sp.Peek($0001) = Old xor $FF, 'ROM changed with ROM changes allowed');
    Sp.RomWritable := False;
    Sp.Poke($8000, $5A);
    Check(Sp.Peek($8000) = $5A, 'RAM written');

    // DivMMC paged in with CONMEM: EEPROM at 0000 (like ROM), RAM at 2000
    Sp.DivMMC.LoadRom(IncludeTrailingPathDelimiter(ParamStr(2)) + 'ESXMMC.BIN');
    Sp.DivMMCOn := True;
    OutPort(Sp, $00E3, $80 or 2);
    Check(Sp.MemoryAt($0100) = maRom, 'DivMMC: EEPROM like ROM');
    Check(Sp.MemoryAt($2100) = maRam, 'DivMMC: its RAM at 2000 is RAM');
    Sp.Poke($2100, $A5);
    Check(Sp.Peek($2100) = $A5, 'DivMMC RAM written without ROM changes allowed');
    OutPort(Sp, $00E3, 0);
    Check(Sp.MemoryAt($2100) = maRom, 'DivMMC paged out: ROM again');
  finally
    Sp.Free;
  end;

  // +3 special mode (1FFD bit 0): RAM banks 0-3 from 0000
  Sp := TSpectrum.Create(smPlus3, ParamStr(1));
  try
    Check(Sp.MemoryAt($0000) = maRom, '+3: ROM at 0000');
    OutPort(Sp, $1FFD, 1);
    Check(Sp.MemoryAt($0000) = maRam, '+3 special mode: RAM at 0000');
    Sp.Poke($0010, $C3);
    Check(Sp.Peek($0010) = $C3, '+3 special mode: 0000-3FFF written without ROM changes allowed');
  finally
    Sp.Free;
  end;

  if Failures = 0 then WriteLn('Memory writes (ROM, RAM paged at 0000): all passed')
  else
  begin
    WriteLn('Memory writes: ', Failures, ' failures');
    Halt(1);
  end;
end.

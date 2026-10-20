{ nexttest: the ZX Spectrum Next booting from a card made from the
  distribution (skipped if the specnext folder has none), through its
  firmware (with the TBBlue logo) and directly: it must reach NextBASIC,
  run a POKE typed there, SAVE a file on the card and open the Multiface
  with the M1 button; an empty config.ini on the card is mended.

    nexttest <roms folder> <specnext folder> <scratch card file> }
program nexttest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Models, Spectrum, NextCard, FatFS;

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

{ Pixels set on the ULA screen: something is shown }
function InkCount(Sp: TSpectrum): Integer;
var
  I, B: Integer;
begin
  Result := 0;
  for I := 0 to 6143 do
  begin
    B := Sp.RamBank(5)^[I];
    while B <> 0 do
    begin
      Inc(Result, B and 1);
      B := B shr 1;
    end;
  end;
end;

procedure Run(Sp: TSpectrum; Frames: Integer);
var
  I: Integer;
begin
  for I := 1 to Frames do Sp.RunFrame;
end;

procedure WaitTyping(Sp: TSpectrum);
begin
  while Sp.AutoTyping do Sp.RunFrame;
end;

{ The size of a file in the card's root, -1 if it isn't there }
function CardFileSize(Sp: TSpectrum; const Name: string): Integer;
var
  V: TFatVolume;
  E: TFatEntries;
  I: Integer;
begin
  Result := -1;
  V := TFatVolume.Create(Sp.DivMMC.Card.Stream);
  try
    E := V.ListDir(0);
    for I := 0 to High(E) do
      if SameText(E[I].ShortName, Name) then Result := E[I].Size;
  finally
    V.Free;
  end;
end;

{ An empty config.ini (as older versions of pzx left it) is mended }
procedure TestRepair(const Distro, Card: string);
var
  F: TFileStream;
  V: TFatVolume;
  L: TStringList;
  E: TFatEntries;
  Dir: LongWord;
  I, Size: Integer;
begin
  F := TFileStream.Create(Card, fmOpenReadWrite);
  try
    V := TFatVolume.Create(F);
    try
      Dir := V.FindDir('/machines/next', False);
      E := V.ListDir(Dir);
      for I := 0 to High(E) do
        if SameText(E[I].ShortName, 'CONFIG.INI') then V.Delete(E[I]);
      V.WriteFile(Dir, 'CONFIG.INI', nil);
      L := RepairNextCard(V, Distro);
      try
        Check((L.Count = 1) and SameText(L[0], '/machines/next/config.ini'), 'card repair: ' + L.Text);
      finally
        L.Free;
      end;
      Size := -1;
      E := V.ListDir(Dir);
      for I := 0 to High(E) do
        if SameText(E[I].ShortName, 'CONFIG.INI') then Size := E[I].Size;
      Check(Size > 0, 'card repair: config.ini written again');
    finally
      V.Free;
    end;
  finally
    F.Free;
  end;
end;

{ Boot (through the firmware, or NextZXOS directly) to NextBASIC and POKE }
procedure Boot(const Roms, Distro, Card: string; Firmware: Boolean);
var
  Sp: TSpectrum;
  Err, Mode: string;
  I: Integer;
  Seen: Boolean;
begin
  if Firmware then Mode := 'firmware: ' else Mode := 'direct: ';
  Sp := TSpectrum.Create(sm48K, Roms);
  try
    Sp.NextDir := Distro;
    Sp.NextFirmwareBoot := Firmware;
    Sp.SetModel(smZXNext);
    Sp.DivMMC.InsertCard(Card);
    Sp.Reset(True);
    if Firmware then
    begin
      // Its boot screen, with the machine ID that makes it show the TBBlue logo
      Run(Sp, 250);
      Check(Sp.NextRegister($00) = $08, Mode + 'the machine says it is an emulator (TBBlue logo)');
    end;
    // The welcome screen, then the menu
    if Firmware then Run(Sp, 1300) else Run(Sp, 1500);
    Check(InkCount(Sp) > 2000, Mode + 'NextZXOS shows its welcome screen');
    Check(Sp.NextRegister($07) and 3 = 3, Mode + 'NextZXOS runs at 28 MHz');
    Sp.TypeText(' ', Err);
    WaitTyping(Sp);
    Run(Sp, 150);
    // NextBASIC, a POKE in it
    Sp.TypeText('n', Err);
    WaitTyping(Sp);
    Run(Sp, 150);
    Sp.TypeText('POKE 32768,42\n', Err);
    WaitTyping(Sp);
    Run(Sp, 100);
    Check(Sp.Peek(32768) = 42, Mode + 'POKE in NextBASIC');
    // SAVE: NextZXOS asks the card for its status (CMD13) after each block
    Sp.TypeText('SAVE "pzxtest.bas"\n', Err);
    WaitTyping(Sp);
    Run(Sp, 150);
    Check(CardFileSize(Sp, 'PZXTEST.BAS') > 0, Mode + 'SAVE writes the file on the card');
    // The M1 button: NextZXOS's Multiface menu (NR 06 lets the button work)
    Check(Sp.NextRegister($06) and $08 <> 0, Mode + 'NextZXOS lets the M1 button work');
    Sp.RequestNMI;
    Seen := False;
    for I := 1 to 20000 do
    begin
      Sp.StepInstruction;
      Seen := Seen or Sp.MultifaceOn;
    end;
    Check(Seen, Mode + 'the M1 button opens the Multiface');
  finally
    Sp.Free;
  end;
end;

begin
  if not NextDistroReady(ParamStr(2)) then
  begin
    WriteLn('ZX Spectrum Next: skipped (no distribution in ', ParamStr(2), ')');
    Exit;
  end;
  MakeNextCard(ParamStr(2), ParamStr(3), 256);
  TestRepair(ParamStr(2), ParamStr(3));
  Boot(ParamStr(1), ParamStr(2), ParamStr(3), True);
  Boot(ParamStr(1), ParamStr(2), ParamStr(3), False);
  if Failures = 0 then WriteLn('ZX Spectrum Next (firmware, NextZXOS): all passed')
  else Halt(1);
end.

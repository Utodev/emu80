{ zxunotest: the ZX-Uno with its real BIOS (zxuno/FIRMWARE.ZX1) and ROMs
  (zxuno/ROMS.ZX1): the BIOS must read the flash, set the machine up (out
  of boot mode, registers locked, DivMMC on with ESXDOS) and start the 48K;
  loading a tape must work (the DAAD Ready test game, whose database is at
  8400), and a .pzs snapshot of it must bring it back; its boot menu (Break) and setup (Edit) must work with the
  Spectrum's keys, the setup saving its settings to the flash, and saved
  settings must choose the ROM started.

    zxunotest <roms folder> <tests/daad folder> }
program zxunotest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Models, Spectrum;

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

function ScreenText(Spec: TSpectrum): string;
var
  Row, Col, Line, Ch, Addr: Integer;
  Cell: array[0..7] of Byte;
  Match: Boolean;
  Screen: PBank;
  Font: array[0..767] of Byte;
  F: TFileStream;
begin
  Result := '';
  F := TFileStream.Create(Spec.RomDir + DirectorySeparator + '48.rom', fmOpenRead or fmShareDenyWrite);
  try
    F.Position := $3D00;
    F.ReadBuffer(Font, SizeOf(Font));
  finally
    F.Free;
  end;
  if (Spec.Port7FFD and 8) <> 0 then Screen := Spec.RamBank(7) else Screen := Spec.RamBank(5);
  for Row := 0 to 23 do
  begin
    for Col := 0 to 31 do
    begin
      for Line := 0 to 7 do
      begin
        Addr := ((Row and $18) shl 8) or (Line shl 8) or ((Row and 7) shl 5) or Col;
        Cell[Line] := Screen^[Addr];
      end;
      Result := Result + '?';
      for Ch := 0 to 95 do
      begin
        Match := True;
        for Line := 0 to 7 do
          if (Cell[Line] <> Font[Ch * 8 + Line]) and (Cell[Line] <> (Font[Ch * 8 + Line] xor $FF)) then
          begin
            Match := False;
            Break;
          end;
        if Match then
        begin
          Result[Length(Result)] := Chr(32 + Ch);
          Break;
        end;
      end;
    end;
    Result := TrimRight(Result) + LineEnding;
  end;
end;


var
  Sp: TSpectrum;
  I: Integer;
  Text, Snap: string;
  Reg0: Byte;

procedure Frames(N: Integer);
var
  K: Integer;
begin
  for K := 1 to N do Sp.RunFrame;
end;

procedure SetReg(Reg, Value: Byte);
var
  T: Integer;
begin
  T := 0;
  Sp.WritePort($FC3B, Reg, T);
  Sp.WritePort($FD3B, Value, T);
end;

{ Interrupts over 50 frames with RASTERCTRL = Ctrl and the raster line at 96 }
function Interrupts(Ctrl: Byte): Integer;
var
  F0: Integer;
begin
  SetReg($0C, 96);
  SetReg($0D, Ctrl);
  Frames(2);
  F0 := Sp.Peek($5C78) + Sp.Peek($5C79) * 256;
  Frames(50);
  Result := (Sp.Peek($5C78) + Sp.Peek($5C79) * 256 - F0 + 65536) mod 65536;
end;

{ Power on, press keys (CAPS + Key2) while the BIOS shows its boot screen }
procedure Boot(Key2: Integer);
begin
  Sp.Reset(True);
  Frames(15);
  if Key2 >= 0 then Sp.AutoType(20, [KEY_CAPS, Key2]);
end;

begin
  Sp := TSpectrum.Create(smZXUno, ParamStr(1));
  // As with no joystick chosen: the ZX-Uno's own Kempston port must still
  // answer (its BIOS reads it with the keyboard)
  Sp.KempstonEnabled := False;
  try
    // Default: the BIOS shows its boot screen and starts the 48K ROM, in
    // about two seconds (the keyboard's power-on AA makes its timer short)
    Frames(150);
    Check((Sp.ZXUnoRegister(0) and $80) <> 0, 'the BIOS started the ROM within 3 seconds');
    Frames(550);
    Check((Sp.ZXUnoRegister(0) and 1) = 0, 'the BIOS left boot mode');
    Check((Sp.ZXUnoRegister(0) and $80) <> 0, 'the BIOS locked MASTERCONF');
    Check(Sp.DivMMCOn and ((Sp.ZXUnoRegister(0) and 2) <> 0), 'DivMMC on');
    Check((Sp.ZXUnoRegister($0E) and 4) <> 0, '48K mode (no 128K paging)');
    Check(Sp.Cpu.PC.W < $4000, Format('running the ROM (PC %.4X)', [Sp.Cpu.PC.W]));
    Text := ScreenText(Sp);
    Check(Pos('1982 Sinclair Research', Text) > 0, '48K BASIC on screen:' + LineEnding + Text);

    // Raster interrupts (RASTERLINE 0Ch, RASTERCTRL 0Dh): the 48K ROM counts
    // its interrupts in FRAMES
    Check(Interrupts(6) in [49..51], Format('raster only, ULA one off: one a frame (%d)', [Interrupts(6)]));
    Check(Interrupts(2) in [99..101], Format('raster and ULA: two a frame (%d)', [Interrupts(2)]));
    Check(Interrupts(4) = 0, Format('none (%d)', [Interrupts(4)]));
    Check(Interrupts(0) in [49..51], Format('back to the ULA''s (%d)', [Interrupts(0)]));

    // Loading a tape
    Sp.FastLoad := True;
    Sp.AutoPlayTape := True;
    Sp.Tape.LoadTAP(IncludeTrailingPathDelimiter(ParamStr(2)) + 'test48.tap');
    Sp.AutoLoad;
    Frames(1500);
    Check((Sp.Peek($8401) = $11) and (Sp.Peek($8402) = $5F), 'tape loaded (the game''s database at 8400)');

    // A .pzs snapshot of it: saved, the machine started again, loaded back
    Snap := GetTempDir + 'zxunotest.pzs';
    Reg0 := Sp.ZXUnoRegister(0);
    Text := ScreenText(Sp);
    Sp.SaveOwnSnapshot(Snap);
    Check(TSpectrum.OwnSnapshotModel(Snap) = smZXUno, 'snapshot: of the ZX-Uno');
    Sp.Reset(True);
    Frames(10);
    Sp.LoadOwnSnapshot(Snap);
    Frames(2);
    Check((Sp.Peek($8401) = $11) and (Sp.Peek($8402) = $5F), 'snapshot: the game''s memory');
    Check(Sp.ZXUnoRegister(0) = Reg0, 'snapshot: MASTERCONF');
    Check(ScreenText(Sp) = Text, 'snapshot: the game''s screen');
    DeleteFile(Snap);

    // Break: the boot menu; the third machine is the 128K
    Boot(KEY_SPACE);
    Frames(150);
    for I := 1 to 2 do
    begin
      Sp.AutoType(6, [KEY_CAPS, KEY_6]);
      Frames(20);
    end;
    Sp.AutoType(6, [KEY_ENTER]);
    Frames(600);
    // 128K timing and paging (ESXDOS then pages the 48K BASIC ROM in, as on a 128K)
    Check(((Sp.ZXUnoRegister(0) and $10) <> 0) and ((Sp.ZXUnoRegister($0E) and 4) = 0),
      'boot menu: the 128K started');

    // Edit: the BIOS setup; Exit > Save Changes & Exit > Yes saves the settings
    Boot(KEY_1);
    Frames(150);
    for I := 1 to 5 do
    begin
      Sp.AutoType(6, [KEY_CAPS, KEY_8]);
      Frames(20);
    end;
    Sp.AutoType(6, [KEY_ENTER]);
    Frames(60);
    Sp.AutoType(6, [KEY_CAPS, KEY_5]);
    Frames(20);
    Sp.AutoType(6, [KEY_ENTER]);
    Frames(100);
    Check(Sp.ZXUnoBiosChanged, 'BIOS setup: settings saved to the flash');

    // Saved settings: the active ROM (the 128K, third) is started
    Text := Sp.ZXUnoBiosSettings;
    Sp.ZXUnoBiosSettings := '02' + Copy(Text, 3, MaxInt);
    Sp.SetModel(smZXUno);
    Frames(700);
    Check(((Sp.ZXUnoRegister(0) and $10) <> 0) and ((Sp.ZXUnoRegister($0E) and 4) = 0),
      'saved settings: the 128K started');

    // A custom ROM replaces the one the BIOS chose (the 128K), as a 48K
    Sp.ZXUnoCustomRom := Sp.RomDir + DirectorySeparator + '48.rom';
    Sp.SetModel(smZXUno);
    Frames(700);
    Check(((Sp.ZXUnoRegister(0) and $50) = 0) and ((Sp.ZXUnoRegister($0E) and $3C) = $3C),
      'custom ROM: 48K timing, no paging');
    Text := ScreenText(Sp);
    Check(Pos('1982 Sinclair Research', Text) > 0, 'custom ROM: 48K BASIC on screen:' +
      LineEnding + Text);
  finally
    Sp.Free;
  end;
  if Failures = 0 then
    WriteLn('ZX-Uno: all passed')
  else
  begin
    WriteLn('ZX-Uno: ', Failures, ' failures');
    Halt(1);
  end;
end.

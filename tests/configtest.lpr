{ Settings kept in the file, and the Next's machine ID (NR 00): the hidden
  realspecnext option's entries (the file's value, the accepted warning, what
  a command line value leaves alone), and that NR 00 follows the ID set.

    configtest <roms folder> }
program configtest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Models, Spectrum, Config;

var
  Failures: Integer = 0;
  Dir, IniFile: string;

procedure Check(Cond: Boolean; const What: string);
begin
  if not Cond then
  begin
    WriteLn('FAIL  ', What);
    Inc(Failures);
  end;
end;

procedure WriteIni(const Text: string);
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.Text := Text;
    L.SaveToFile(IniFile);
  finally
    L.Free;
  end;
end;

function IniText: string;
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.LoadFromFile(IniFile);
    Result := LowerCase(L.Text);
  finally
    L.Free;
  end;
end;

function Fresh: TSettings;
begin
  Result := TSettings.Create;
  Result.UseFile(IniFile);
  Result.Load;
end;

var
  S: TSettings;
  Sp: TSpectrum;
  Id: Byte;
  I: Integer;
  Backup: string;
begin
  Dir := IncludeTrailingPathDelimiter(GetTempDir) + 'pzx-configtest-' + IntToStr(GetProcessID) + PathDelim;
  ForceDirectories(Dir);
  IniFile := Dir + 'pzx.ini';
  try
    // Nothing set: it is off, and saving doesn't write it
    DeleteFile(IniFile);
    S := Fresh;
    Check(not S.RealSpecNext and not S.RealSpecNextIni and not S.RealSpecNextOk, 'off by default');
    S.Save;
    Check(Pos('realspecnext', IniText) = 0, 'saving doesn''t write it when it is off');
    S.Free;

    // In the file: it applies, and saving keeps it
    WriteIni('[ZXNext]'#10'realspecnext=1'#10);
    S := Fresh;
    Check(S.RealSpecNext and S.RealSpecNextIni and not S.RealSpecNextCmd and not S.RealSpecNextOk,
      'realspecnext=1 in [ZXNext] is read, not accepted yet');
    S.Save;
    Check(Pos('realspecnext=1', IniText) > 0, 'saving keeps the file''s entry');

    // The warning accepted: kept in the file at once, and read back
    S.AcceptRealSpecNext;
    Check(Pos('realspecnextok=1', IniText) > 0, 'the acceptance is written at once');
    S.Free;
    S := Fresh;
    Check(S.RealSpecNext and S.RealSpecNextOk, 'the acceptance persists');
    S.Free;

    // Refused (the option from the file): its entry goes from the file
    WriteIni('[ZXNext]'#10'realspecnext=1'#10'[Machine]'#10'issue=2'#10);
    S := Fresh;
    S.ForgetRealSpecNext;
    S.RealSpecNext := False;
    Check(Pos('realspecnext', IniText) = 0, 'refused: the file''s entry is deleted');
    Check(Pos('issue=2', IniText) > 0, 'the rest of the file stays');
    S.Save;
    Check(Pos('realspecnext', IniText) = 0, 'saving doesn''t bring it back');
    S.Free;
    S := Fresh;
    Check(not S.RealSpecNext, 'and the next start has it off');
    S.Free;

    // From the command line only: nothing of it reaches the file
    DeleteFile(IniFile);
    S := Fresh;
    S.RealSpecNext := True;
    S.RealSpecNextCmd := True;
    S.Save;
    Check(Pos('realspecnext', IniText) = 0, 'a command line value isn''t saved to the file');
    S.Free;

    // Both: the command line's value counts; refusing it leaves the file alone
    WriteIni('[ZXNext]'#10'realspecnext=1'#10);
    S := Fresh;
    S.RealSpecNext := False;
    S.RealSpecNextCmd := True;
    S.Save;
    Check(Pos('realspecnext=1', IniText) > 0, 'a command line off leaves the file''s entry');
    S.Free;

    // The card each hardware remembers
    WriteIni('[Media]'#10'sdcard=normal.img'#10'zxunocard=uno.img'#10'[ZXNext]'#10'nextcard=next.img'#10);
    S := Fresh;
    Check((S.SDCardFile = 'normal.img') and (S.ZXUnoCard = 'uno.img') and (S.NextCard = 'next.img'),
      'the standard models, the ZX-Uno and the Next each have their own card');
    S.ZXUnoCard := 'other.img';
    S.Save;
    Check(Pos('zx_unocard=other.img', IniText) > 0, 'the ZX-Uno''s card is saved (as zx_unocard)');
    S.Free;
    S := Fresh;
    Check((S.ZXUnoCard = 'other.img') and (S.SDCardFile = 'normal.img'), 'and read back, the others untouched');
    S.Free;

    // The old black and white option is the black and white monitor
    WriteIni('[General]'#10'bw=1'#10);
    S := Fresh;
    Check(S.Monitor = 1, 'bw=1 of an older file is the black and white monitor');
    S.Save;
    Check((Pos('monitor=bw', IniText) > 0) and (Pos(#10'bw=', IniText) = 0), '... and is saved as monitor=bw');
    S.Free;

    // The names: ZX Spectrum options start zx_, Amstrad CPC ones cpc_; a file
    // with the older names is read, and written again with the new ones
    WriteIni('[Hardware]'#10'turbosound=1'#10'currah=1'#10'cpcjoystick=0'#10'[Machine]'#10'joystick=sinclair1'#10 +
      'issue=2'#10'contention=0'#10'deinterlace=bob'#10'[ROMs]'#10'zxunoroms=u.zx1'#10);
    S := Fresh;
    Check(S.TurboSound and S.Currah and not S.CPCJoystick, 'old [Hardware] names are read');
    Check((S.Joystick = jkSinclair1) and S.Issue2 and not S.Contention and (S.Deinterlace = dlBob),
      'old [Machine] names are read');
    Check(S.ZXUnoRoms = 'u.zx1', 'old [ROMs] names are read');
    S.CPCCrtc := 3;
    S.Monitor := 3;
    S.CPCWaitStates := False;
    S.Save;
    Check((Pos('zx_turbosound=1', IniText) > 0) and (Pos('zx_joystick=sinclair1', IniText) > 0) and
      (Pos('cpc_joystick=0', IniText) > 0) and (Pos('zx_unoroms=u.zx1', IniText) > 0),
      'saved with the new names');
    Check((Pos('cpc_crtc=3', IniText) > 0) and (Pos('monitor=orange', IniText) > 0) and (Pos('cpc_waitstates=0', IniText) > 0) and
      (Pos('[amstradcpc]', IniText) > 0) and (Pos('[zxspectrum]', IniText) > 0),
      'the CPC options have their section, as the ZX Spectrum ones');
    Check((Pos(#10'turbosound=', IniText) = 0) and (Pos(#10'currah=', IniText) = 0) and
      (Pos(#10'cpcjoystick=', IniText) = 0) and (Pos(#10'joystick=', IniText) = 0) and
      (Pos(#10'issue=', IniText) = 0), 'and the old names are gone');
    Backup := S.Snapshot;
    S.Free;
    S := Fresh;
    Check((S.CPCCrtc = 3) and (S.Monitor = 3) and not S.CPCWaitStates and S.TurboSound and (S.Joystick = jkSinclair1),
      'read back from the new names');
    // What a Cancel after an Apply does: the settings as they were
    S.Monitor := 2;
    S.Joystick := jkFuller;
    S.Restore(Backup);
    Check((S.Monitor = 3) and (S.Joystick = jkSinclair1), 'Restore puts the settings back as Snapshot took them');
    Check(CurrentOptionName('turbosound') = 'zx_turbosound', 'the command line takes an old name as the new');
    Check(CurrentOptionName('no-divmmc') = 'no-zx_divmmc', '... also with no-');
    Check(CurrentOptionName('speed') = 'speed', 'common options keep their names');
    S.Free;

    // NR 00: the emulator's ID unless told otherwise
    Sp := TSpectrum.Create(sm48K, ParamStr(1));
    try
      Sp.NextFirmwareBoot := True;
      Sp.SetModel(smZXNext);
      Sp.WriteMem($0000, 0, 0);
      Sp.Cpu.T := 0;
      Sp.WritePort($243B, 0, Sp.Cpu.T);
      Id := Sp.ReadPort($253B, Sp.Cpu.T);
      Check(Id = $08, Format('the Next says it is an emulator by default (%.2X)', [Id]));
      Sp.NextMachineId := $0A;
      Sp.SetModel(smZXNext);
      Sp.WritePort($243B, 0, Sp.Cpu.T);
      Id := Sp.ReadPort($253B, Sp.Cpu.T);
      Check(Id = $0A, Format('with the real ID set it says it is a real one (%.2X)', [Id]));
    finally
      Sp.Free;
    end;
  finally
    DeleteFile(IniFile);
    RemoveDir(Dir);
  end;
  if Failures = 0 then
    WriteLn('Settings file and the Next''s ID: all passed')
  else
    Halt(1);
end.

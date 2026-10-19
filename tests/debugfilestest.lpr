{ debugfilestest: breakpoints (memory and ports, with types, conditions and
  switched off ones), watches and DAAD breakpoints saved as JSON and loaded
  back.

    debugfilestest <roms folder> <scratch folder> }
program debugfilestest;

{$mode objfpc}{$H+}

uses
  SysUtils, Models, Spectrum, DebugFiles;

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

var
  Sp: TSpectrum;
  Dir, Err: string;
  W: TWordArray;
  D, D2: TDaadBreakDataArray;
begin
  Dir := IncludeTrailingPathDelimiter(ParamStr(2));
  Sp := TSpectrum.Create(sm48K, ParamStr(1));
  try
    Check(Sp.SetBreakCondition($8000, 'A = 3', Err), 'condition: ' + Err);
    Sp.Breakpoint[$8000] := BP_EXEC;
    Sp.Breakpoint[$5C3A] := BP_WRITE or BP_DISABLED;
    Sp.Breakpoint[$9000] := BP_READ or BP_WRITE;
    Sp.PortBreakpoint[$00FE] := BP_WRITE;
    // A range: one breakpoint over A000-A0FF
    Sp.SetBreakRange($A000, $A0FF, False);
    Check(Sp.SetBreakCondition($A000, 'B = 1', Err), 'range condition: ' + Err);
    Sp.Breakpoint[$A000] := BP_WRITE;
    Check((Sp.Breakpoint[$A080] = BP_WRITE) and (Sp.BreakCondition($A0FF) = 'B = 1'),
      'the range covers every address');
    Sp.Breakpoint[$A010] := BP_WRITE or BP_DISABLED;
    Check(Sp.Breakpoint[$A0FF] = BP_WRITE or BP_DISABLED, 'switching off any address switches the range');
    Sp.Breakpoint[$A010] := BP_WRITE;
    SaveBreakpoints(Sp, Dir + 'bp.json');
    Sp.ClearBreakpoints;
    Check(Sp.Breakpoint[$8000] = 0, 'cleared');
    Check(LoadBreakpoints(Sp, Dir + 'bp.json', Err), 'breakpoints loaded: ' + Err);
    Check(Sp.Breakpoint[$8000] = BP_EXEC, 'execution breakpoint');
    Check(Sp.BreakCondition($8000) = 'A = 3', 'its condition: ' + Sp.BreakCondition($8000));
    Check(Sp.Breakpoint[$5C3A] = BP_WRITE or BP_DISABLED, 'switched off write breakpoint');
    Check(Sp.Breakpoint[$9000] = BP_READ or BP_WRITE, 'access breakpoint');
    Check(Sp.PortBreakpoint[$00FE] = BP_WRITE, 'port breakpoint');
    Check((Sp.BreakRangeLast($A000, False) = $A0FF) and (Sp.Breakpoint[$A0FF] = BP_WRITE) and
      (Sp.BreakCondition($A0FF) = 'B = 1'), 'range loaded');
    Sp.Breakpoint[$A055] := 0;
    Check((Sp.Breakpoint[$A000] = 0) and (Sp.BreakRangeLast($A000, False) = $A000),
      'removing any address removes the range');
    Check(not LoadWatches(Dir + 'bp.json', W, Err), 'a breakpoints file is not a watches file');
  finally
    Sp.Free;
  end;

  SaveWatches([$5C3A, $8000], Dir + 'w.json');
  Check(LoadWatches(Dir + 'w.json', W, Err) and (Length(W) = 2) and (W[0] = $5C3A) and (W[1] = $8000),
    'watches: ' + Err);

  SetLength(D, 2);
  D[0].Addr := $8A69; D[0].Enabled := True; D[0].Condition := 'f0 = 3'; D[0].Condact := 'P1 E5';
  D[1].Addr := $8B00; D[1].Enabled := False; D[1].Condition := ''; D[1].Condact := '';
  SaveDaadBreaks(D, Dir + 'daad.json');
  Check(LoadDaadBreaks(Dir + 'daad.json', D2, Err) and (Length(D2) = 2) and (D2[0].Addr = $8A69) and
    D2[0].Enabled and (D2[0].Condition = 'f0 = 3') and not D2[1].Enabled, 'DAAD breakpoints: ' + Err);

  if Failures = 0 then WriteLn('Breakpoint and watch files: all passed')
  else
  begin
    WriteLn('Breakpoint and watch files: ', Failures, ' failures');
    Halt(1);
  end;
end.

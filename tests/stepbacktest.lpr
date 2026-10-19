{ stepbacktest: the debugger's step back puts the whole machine back (the
  CPU, the memory, the 128K paging), and a label added in the debugger
  (a user symbol) is kept when the code is exported as assembler.

    stepbacktest <roms folder> }
program stepbacktest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Models, Spectrum, Z80Core, Disasm, AsmExport, Symbols;

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

type
  TLabels = class
    Sp: TSpectrum;
    function Peek(Addr: Word): Byte;
    function LabelFor(Addr: Word; Kind: TOperandKind): string;
  end;

function TLabels.Peek(Addr: Word): Byte;
begin
  Result := Sp.Peek(Addr);
end;

function TLabels.LabelFor(Addr: Word; Kind: TOperandKind): string;
begin
  Result := UserSymbols.Lookup(Addr);
end;

procedure TestModel(Model: TSpectrumModel; const RomDir: string);
var
  Sp: TSpectrum;
  State: TMachineState;
  Mem: array[0..$FFFF] of Byte;
  Regs: TZ80Regs;
  T, I, Diff: Integer;
  Name: string;
begin
  Name := ModelInfo[Model].Name;
  Sp := TSpectrum.Create(Model, RomDir);
  try
    for I := 1 to 120 do Sp.RunFrame;
    State := Sp.SaveState;
    for I := 0 to $FFFF do Mem[I] := Sp.Peek(I);
    Regs := Sp.Cpu.GetRegs;
    T := Sp.Cpu.T;
    // Run on (the ROM writes to memory: FRAMES, the stack...)
    for I := 1 to 20000 do Sp.StepInstruction;
    Diff := 0;
    for I := 0 to $FFFF do if Sp.Peek(I) <> Mem[I] then Inc(Diff);
    Check(Diff > 0, Name + ': the memory changed while running');
    Check(Sp.LoadState(State), Name + ': state put back');
    Diff := 0;
    for I := 0 to $FFFF do if Sp.Peek(I) <> Mem[I] then Inc(Diff);
    Check(Diff = 0, Format('%s: %d bytes differ after the step back', [Name, Diff]));
    Check((Sp.Cpu.PC.W = Regs.PC) and (Sp.Cpu.SP.W = Regs.SP) and (Sp.Cpu.GetAF = (Regs.A shl 8) or Regs.F) and
      (Sp.Cpu.HL.W = Regs.HL) and (Sp.Cpu.T = T), Name + ': the registers are back');
    State.Free;
  finally
    Sp.Free;
  end;
end;

procedure TestLabel(const RomDir: string);
var
  L: TLabels;
  Src: TStringList;
begin
  L := TLabels.Create;
  L.Sp := TSpectrum.Create(sm48K, RomDir);
  try
    UserSymbols.Clear;
    UserSymbols.SetName($0038, 'MY_INT');
    Src := ExportAsm($0038, 32, @L.Peek, @L.LabelFor);
    try
      Check(Pos('MY_INT:', Src.Text) > 0, 'the label is in the exported source');
    finally
      Src.Free;
    end;
    UserSymbols.SetName($0038, '');
    Check((UserSymbols.Lookup($0038) = '') and (UserSymbols.Count = 0), 'an empty name removes the label');
  finally
    L.Sp.Free;
    L.Free;
  end;
end;

begin
  TestModel(sm48K, ParamStr(1));
  TestModel(sm128K, ParamStr(1));
  TestLabel(ParamStr(1));
  if Failures = 0 then WriteLn('Step back and labels: all passed')
  else
  begin
    WriteLn(Failures, ' failures');
    Halt(1);
  end;
end.

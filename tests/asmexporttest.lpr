{ asmexporttest: the 48K ROM disassembled as sjasmplus source (with the
  labels of 48.sym) must assemble back to the same 16K. Without sjasmplus
  (the SJASMPLUS variable or on the PATH) only the source is checked.

    asmexporttest <roms folder> <output .asm> }
program asmexporttest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Disasm, AsmExport, Symbols;

type
  THost = class
    Mem: array[0..$3FFF] of Byte;
    Syms: TSymbolTable;
    function Peek(Addr: Word): Byte;
    function LabelFor(Addr: Word; Kind: TOperandKind): string;
  end;

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

function THost.Peek(Addr: Word): Byte;
begin
  Result := Mem[Addr and $3FFF];
end;

function THost.LabelFor(Addr: Word; Kind: TOperandKind): string;
begin
  if Kind = okImmediate then Result := '' else Result := Syms.Lookup(Addr);
end;

var
  H: THost;
  F: TFileStream;
  L: TStringList;
  Dir: string;
begin
  Dir := IncludeTrailingPathDelimiter(ParamStr(1));
  H := THost.Create;
  H.Syms := TSymbolTable.Create;
  F := TFileStream.Create(Dir + '48.rom', fmOpenRead or fmShareDenyWrite);
  try
    F.ReadBuffer(H.Mem, SizeOf(H.Mem));
  finally
    F.Free;
  end;
  H.Syms.LoadFromFile(Dir + '48.sym');
  L := ExportAsm(0, $4000, @H.Peek, @H.LabelFor);
  try
    Check(L.IndexOf(#9'ORG $0000') >= 0, 'ORG');
    Check(L.IndexOf('START:') >= 0, 'labels from the symbol file');
    Check(Pos(#9'DI'#9'; 0000', L.Text) > 0, 'first instruction');
    L.SaveToFile(ParamStr(2));
  finally
    L.Free;
  end;
  if Failures = 0 then WriteLn('Assembler export: all passed')
  else
  begin
    WriteLn('Assembler export: ', Failures, ' failures');
    Halt(1);
  end;
end.

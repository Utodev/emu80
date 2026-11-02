{ C64Disasm: the 6510 disassembler of the Commodore 64 debugger (illegal opcodes marked with a *), and the
  names of the C64's own addresses: the KERNAL jump table and the registers of the VIC-II, SID and CIAs. }
unit C64Disasm;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Cpu6510, Symbols;

type
  TPeekFunc = function(Addr: Word): Byte of object;

{ One instruction at Addr: its text; Len its bytes; Target the address it refers to (-1 if none) }
function Disassemble6502(Addr: Word; Peek: TPeekFunc; out Len: Integer; out Target: Integer): string;
{ The instruction at Addr is a JSR (step over runs it as a whole) }
function IsSubroutineCall(Addr: Word; Peek: TPeekFunc): Boolean;
{ The names of the machine's addresses (KERNAL entry points, chip registers); '' if none }
function C64AddressName(Addr: Word): string;
{ The address of a name of those (case-insensitive) }
function C64FindName(const Name: string; out Addr: Word): Boolean;
{ A table with the names above, for lookups with the user's symbols }
function BuiltinSymbols: TSymbolTable;

implementation

const
  KERNAL_NAMES: array[0..38] of string = ('CINT', 'IOINIT', 'RAMTAS', 'RESTOR', 'VECTOR', 'SETMSG', 'SECOND', 'TKSA',
    'MEMTOP', 'MEMBOT', 'SCNKEY', 'SETTMO', 'ACPTR', 'CIOUT', 'UNTLK', 'UNLSN', 'LISTN', 'TALK', 'READST', 'SETLFS',
    'SETNAM', 'OPEN', 'CLOSE', 'CHKIN', 'CKOUT', 'CLRCHN', 'CHRIN', 'CHROUT', 'LOAD', 'SAVE', 'SETTIM', 'RDTIM',
    'STOP', 'GETIN', 'CLALL', 'UDTIM', 'SCREEN', 'PLOT', 'IOBASE');

  VIC_NAMES: array[0..46] of string = ('SPR0_X', 'SPR0_Y', 'SPR1_X', 'SPR1_Y', 'SPR2_X', 'SPR2_Y', 'SPR3_X', 'SPR3_Y',
    'SPR4_X', 'SPR4_Y', 'SPR5_X', 'SPR5_Y', 'SPR6_X', 'SPR6_Y', 'SPR7_X', 'SPR7_Y', 'SPR_X_MSB', 'VIC_CTRL1', 'VIC_RASTER',
    'LIGHTPEN_X', 'LIGHTPEN_Y', 'SPR_ENABLE', 'VIC_CTRL2', 'SPR_Y_EXP', 'VIC_MEMORY', 'VIC_IRQ_FLAGS', 'VIC_IRQ_MASK',
    'SPR_PRIORITY', 'SPR_MULTICOLOR', 'SPR_X_EXP', 'SPR_SPR_COLL', 'SPR_BG_COLL', 'BORDER_COLOR', 'BACKGROUND_COLOR0',
    'BACKGROUND_COLOR1', 'BACKGROUND_COLOR2', 'BACKGROUND_COLOR3', 'SPR_MCOLOR0', 'SPR_MCOLOR1', 'SPR0_COLOR', 'SPR1_COLOR',
    'SPR2_COLOR', 'SPR3_COLOR', 'SPR4_COLOR', 'SPR5_COLOR', 'SPR6_COLOR', 'SPR7_COLOR');

  SID_NAMES: array[0..28] of string = ('V1_FREQ_LO', 'V1_FREQ_HI', 'V1_PW_LO', 'V1_PW_HI', 'V1_CONTROL', 'V1_AD', 'V1_SR',
    'V2_FREQ_LO', 'V2_FREQ_HI', 'V2_PW_LO', 'V2_PW_HI', 'V2_CONTROL', 'V2_AD', 'V2_SR', 'V3_FREQ_LO', 'V3_FREQ_HI',
    'V3_PW_LO', 'V3_PW_HI', 'V3_CONTROL', 'V3_AD', 'V3_SR', 'FILTER_CUT_LO', 'FILTER_CUT_HI', 'FILTER_RES_ROUTE',
    'FILTER_MODE_VOL', 'POT_X', 'POT_Y', 'OSC3', 'ENV3');

  CIA_NAMES: array[0..15] of string = ('PRA', 'PRB', 'DDRA', 'DDRB', 'TA_LO', 'TA_HI', 'TB_LO', 'TB_HI', 'TOD_10THS',
    'TOD_SEC', 'TOD_MIN', 'TOD_HR', 'SDR', 'ICR', 'CRA', 'CRB');

var
  Builtin: TSymbolTable;

procedure BuildBuiltin;
var
  I: Integer;
begin
  Builtin := TSymbolTable.Create;
  for I := 0 to High(KERNAL_NAMES) do Builtin.Add($FF81 + I * 3, KERNAL_NAMES[I]);
  for I := 0 to High(VIC_NAMES) do Builtin.Add($D000 + I, VIC_NAMES[I]);
  for I := 0 to High(SID_NAMES) do Builtin.Add($D400 + I, SID_NAMES[I]);
  for I := 0 to 15 do
  begin
    Builtin.Add($DC00 + I, 'CIA1_' + CIA_NAMES[I]);
    Builtin.Add($DD00 + I, 'CIA2_' + CIA_NAMES[I]);
  end;
  Builtin.Add($0000, 'DDR_6510');
  Builtin.Add($0001, 'PORT_6510');
  Builtin.Add($0314, 'IRQ_VECTOR');
  Builtin.Add($0316, 'BRK_VECTOR');
  Builtin.Add($0318, 'NMI_VECTOR');
  Builtin.Add($FFFA, 'NMI_HW_VECTOR');
  Builtin.Add($FFFC, 'RESET_HW_VECTOR');
  Builtin.Add($FFFE, 'IRQ_HW_VECTOR');
  Builtin.Add($D800, 'COLOR_RAM');
  Builtin.Add($0400, 'SCREEN_RAM');
  Builtin.Add($0286, 'CURRENT_COLOR');
  Builtin.Add($00C6, 'KEYBUF_COUNT');
  Builtin.Add($0277, 'KEYBUF');
  Builtin.Add($0090, 'STATUS');
  Builtin.Add($00AE, 'LOAD_END_LO');
end;

function BuiltinSymbols: TSymbolTable;
begin
  Result := Builtin;
end;

function C64AddressName(Addr: Word): string;
begin
  Result := Builtin.Lookup(Addr);
end;

function C64FindName(const Name: string; out Addr: Word): Boolean;
begin
  Result := Builtin.Find(Name, Addr);
end;

function Hex2(V: Byte): string;
begin
  Result := '$' + IntToHex(V, 2);
end;

function Hex4(V: Word): string;
begin
  Result := '$' + IntToHex(V, 4);
end;

function IsSubroutineCall(Addr: Word; Peek: TPeekFunc): Boolean;
begin
  Result := Peek(Addr) = $20;
end;

function Disassemble6502(Addr: Word; Peek: TPeekFunc; out Len: Integer; out Target: Integer): string;
var
  Op: Byte;
  Mode: TAddrMode;
  Lo, Hi: Byte;
  A: Word;
  Operand: string;
begin
  Op := Peek(Addr);
  Mode := OpMode[Op];
  Len := OpLength(Op);
  Lo := Peek(Word(Addr + 1));
  Hi := Peek(Word(Addr + 2));
  A := Lo or (Hi shl 8);
  Target := -1;
  Operand := '';
  case Mode of
    amImp: ;
    amAcc: Operand := 'A';
    amImm: Operand := '#' + Hex2(Lo);
    amZp: begin Operand := Hex2(Lo); Target := Lo; end;
    amZpx: begin Operand := Hex2(Lo) + ',X'; Target := Lo; end;
    amZpy: begin Operand := Hex2(Lo) + ',Y'; Target := Lo; end;
    amAbs: begin Operand := Hex4(A); Target := A; end;
    amAbx: begin Operand := Hex4(A) + ',X'; Target := A; end;
    amAby: begin Operand := Hex4(A) + ',Y'; Target := A; end;
    amInd: begin Operand := '(' + Hex4(A) + ')'; Target := A; end;
    amIzx: begin Operand := '(' + Hex2(Lo) + ',X)'; Target := Lo; end;
    amIzy: begin Operand := '(' + Hex2(Lo) + '),Y'; Target := Lo; end;
    amRel:
      begin
        Target := Word(Addr + 2 + ShortInt(Lo));
        Operand := Hex4(Target);
      end;
  end;
  Result := OpName[Op];
  if OpIllegal[Op] then Result := '*' + Result else Result := ' ' + Result;
  if Operand <> '' then Result := Result + ' ' + Operand;
end;

initialization
  BuildBuiltin;

finalization
  Builtin.Free;

end.

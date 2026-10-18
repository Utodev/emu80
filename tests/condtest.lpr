{ condtest: checks breakpoint condition parsing and evaluation (BreakExpr). }
program condtest;

{$mode objfpc}{$H+}

uses
  SysUtils, Z80Core, BreakExpr;

type
  TNullBus = class(TZ80Bus)
    function ReadMem(Addr: Word; T: Integer): Byte; override;
    procedure WriteMem(Addr: Word; Value: Byte; T: Integer); override;
    function ReadPort(Port: Word; var T: Integer): Byte; override;
    procedure WritePort(Port: Word; Value: Byte; var T: Integer); override;
  end;

function TNullBus.ReadMem(Addr: Word; T: Integer): Byte; begin Result := 0; end;
procedure TNullBus.WriteMem(Addr: Word; Value: Byte; T: Integer); begin end;
function TNullBus.ReadPort(Port: Word; var T: Integer): Byte; begin Result := $FF; end;
procedure TNullBus.WritePort(Port: Word; Value: Byte; var T: Integer); begin end;

type
  { Memory for @: byte N holds N xor $55 }
  TFakeMem = class
    function Peek(Addr: Word): Byte;
  end;

function TFakeMem.Peek(Addr: Word): Byte;
begin
  Result := Byte(Addr) xor $55;
end;

{ Symbols: START = 8000, BC = 1234 (a symbol named like a register) }
function FakeSymbol(const Name: string; out Value: Word): Boolean;
begin
  Result := True;
  if UpperCase(Name) = 'START' then Value := $8000
  else if UpperCase(Name) = 'BC' then Value := $1234
  else if UpperCase(Name) = 'MAIN.LOOP' then Value := $8010
  else Result := False;
end;

var
  Cpu: TZ80;
  Failures: Integer = 0;
  Cond: TBreakCondition;
  Err: string;

procedure Check(const Text: string; Expected: Boolean);
var
  Cond: TBreakCondition;
  Error: string;
begin
  Cond := CompileCondition(Text, Error);
  if Cond = nil then
  begin
    WriteLn('FAIL  ', Text, '  (', Error, ')');
    Inc(Failures);
    Exit;
  end;
  if Cond.Holds(Cpu) <> Expected then
  begin
    WriteLn('FAIL  ', Text, '  gave ', not Expected);
    Inc(Failures);
  end;
  Cond.Free;
end;

procedure CheckError(const Text: string);
var
  Cond: TBreakCondition;
  Error: string;
begin
  Cond := CompileCondition(Text, Error);
  if Cond <> nil then
  begin
    WriteLn('FAIL  ', Text, '  should be an error');
    Inc(Failures);
    Cond.Free;
  end;
end;

begin
  Cpu := TZ80.Create(TNullBus.Create);
  ConditionPeek := @TFakeMem.Create.Peek;
  ConditionSymbol := @FakeSymbol;
  Cpu.A := $03; Cpu.F := $41;            // Z and C set
  Cpu.BC.W := $289A; Cpu.DE.W := $1203; Cpu.HL.W := $C000;
  Cpu.IX.W := $5C3A; Cpu.SP.W := $FF40; Cpu.PC.W := $8000;
  Cpu.BC_.W := $1111; Cpu.A_ := $77;
  Cpu.IFF1 := True; Cpu.IFF2 := False; Cpu.IM := 1;

  Check('BC=289A', True);
  Check('bc=289a', True);
  Check('BC = $289A', True);
  Check('BC=289Ah', True);
  Check('A=3 AND E=3', True);
  Check('A=3 and E=4', False);
  Check('A=10 and #C=0', False);
  Check('#Z=1', True);
  Check('#z=0', False);
  Check('#N=0 AND #PV=0', True);
  Check('NOT A=3', False);
  Check('NOT (A=4)', True);
  Check('A=3 OR E=9', True);
  Check('A=4 XOR E=3', True);
  Check('A=3 XOR E=3', False);
  Check('(A=4 OR B=28) AND C=9A', True);
  Check('HL>=C000 AND HL<C100', True);
  Check('SP<>FF40', False);
  Check('C=9A', True);                    // register C, not the hex number C
  Check('C=$C', False);
  Check('IXH=5C', True);
  Check('BC''=1111 AND A''=77', True);
  Check('IFF1=1 AND IFF2=0', True);
  Check('IM=1', True);
  Check('PC=8000', True);
  Check('HL+1=C001', True);
  Check('D-1=11', True);
  Check('A = E * 1', True);
  Check('E = A * 2', False);
  Check('D = E * 6', True);                // 12 = 3 * 6
  Check('BC = DE + HL', False);
  Check('HL = DE + 1', False);
  Check('DE + 1 = 1204', True);
  Check('HL / 100 = C0', True);
  Check('B MOD 10 = 8', True);
  Check('C & 0F = 0A', True);           // F alone is the flags register
  Check('(A | 4) = 7', True);
  Check('A + 2 * 3 = 9', True);            // * before +
  Check('A * 0 = 0 AND A / 0 = 0', True);
  CheckError('A * ');
  // Symbols: register first, then symbol, then hex; # forces the symbol
  Check('PC = START', True);
  Check('PC = #START', True);
  Check('BC = 289A', True);               // BC is the register
  Check('#BC = 1234', True);              // the symbol BC
  Check('PC + 10 = #main.loop', True);
  CheckError('#NOPE = 1');
  // @: byte in memory
  Check('@0 = 55', True);
  Check('A = @56', True);                 // 56 xor 55 = 3
  Check('@(HL+1) = 54', True);            // C001 -> 01 xor 55
  Check('@HL + 1 = 56', True);
  // Decimal with a dot
  Check('A = .3', True);
  Check('E + .17 = .20', True);
  Check('HL = .49152', True);
  CheckError('A = .');
  // Arithmetic wraps: 8 bits for 8-bit values, 16 bits otherwise
  Check('A - 4 = FF', True);
  Check('B * 10 = 80', True);             // 28 * 16 = 280 -> 80
  Check('HL + 4000 = 0', True);           // C000 + 4000 = 10000 -> 0
  Check('-A = FD', True);
  Check('A - 4 = FFFF', False);
  Check('A + 100 = 103', True);           // 100 is 16-bit: no 8-bit wrap
  Check('C & 7 = 2', True);               // bitwise and: 9A & 7
  // T counts the times the breakpoint is reached
  Cond := CompileCondition('T=3', Err);
  if (Cond = nil) or Cond.Holds(Cpu) or Cond.Holds(Cpu) or not Cond.Holds(Cpu) or
     Cond.Holds(Cpu) or (Cond.Hits <> 4) or not Cond.UsesHits then
  begin
    WriteLn('FAIL  T=3 hit counting');
    Inc(Failures);
  end;
  Cond.Free;
  CheckError('');
  CheckError('A=');
  CheckError('A=3 AND');
  CheckError('(A=3');
  CheckError('#Q=1');
  CheckError('A=3)');
  CheckError('XYZ=1');

  if Failures = 0 then WriteLn('Breakpoint conditions: all passed')
  else WriteLn('Breakpoint conditions: ', Failures, ' failed');
  if Failures > 0 then Halt(1);
end.

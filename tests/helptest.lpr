{ helptest: every instruction the disassembler writes has a description
  (Z80Help), and every condact name of DAAD and PAW has one (DaadHelp). }
program helptest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Disasm, Z80Help, Daad, DaadHelp;

type
  TMem = class
    Bytes: array[0..7] of Byte;
    function Peek(Addr: Word): Byte;
  end;

function TMem.Peek(Addr: Word): Byte;
begin
  Result := Bytes[Addr and 7];
end;

var
  Mem: TMem;
  Failures: Integer = 0;
  Seen: TStringList;

procedure TryBytes(const Bytes: array of Byte);
var
  I, Len: Integer;
  Text: string;
begin
  FillChar(Mem.Bytes, SizeOf(Mem.Bytes), $05);
  for I := 0 to High(Bytes) do Mem.Bytes[I] := Bytes[I];
  Text := Disassemble(0, @Mem.Peek, Len);
  if InstructionHelp(Text) <> '' then Exit;
  if Seen.IndexOf(Text) >= 0 then Exit;
  Seen.Add(Text);
  WriteLn('FAIL  no help for ', Text);
  Inc(Failures);
end;

procedure CheckText(const Instr, Part: string);
begin
  if Pos(Part, InstructionHelp(Instr)) = 0 then
  begin
    WriteLn('FAIL  help for ', Instr, ' lacks "', Part, '": ', InstructionHelp(Instr));
    Inc(Failures);
  end;
end;

procedure CheckT(const Bytes: array of Byte; const Want: string);
var
  I: Integer;
begin
  FillChar(Mem.Bytes, SizeOf(Mem.Bytes), 0);
  for I := 0 to High(Bytes) do Mem.Bytes[I] := Bytes[I];
  if InstructionTStates(0, @Mem.Peek) <> Want then
  begin
    WriteLn('FAIL  T-states of ', Disassemble(0, @Mem.Peek, I), ': ',
      InstructionTStates(0, @Mem.Peek), ', not ', Want);
    Inc(Failures);
  end;
end;

var
  Op, Op2: Integer;
  Name: string;
begin
  Seen := TStringList.Create;
  Mem := TMem.Create;
  for Op := 0 to 255 do
  begin
    TryBytes([Op]);
    TryBytes([$CB, Op]);
    TryBytes([$ED, Op]);
    for Op2 := 0 to 255 do
    begin
      TryBytes([$DD, Op, Op2]);
      TryBytes([$FD, Op, Op2]);
    end;
    TryBytes([$DD, $CB, $05, Op]);
    TryBytes([$FD, $CB, $05, Op]);
  end;
  CheckText('LD A,(IX+$05)', 'the byte at IX+05 into A');
  CheckText('LD HL,($5C78)', 'the 16-bit word at 5C78 into HL');
  CheckText('JR NZ,$0048', 'if Z is reset');
  CheckText('ADD A,B', 'Flags: S, Z, H, P/V (overflow) and C set by the result; N reset');
  CheckText('RLC (IX+$05),B', 'also copied to B');
  CheckText('LD A,I', 'P/V = IFF2');
  CheckT([$00], '4');
  CheckT([$20, $05], '7 or 12');
  CheckT([$10, $05], '8 or 13');
  CheckT([$C4, $00, $80], '10 or 17');
  CheckT([$ED, $B0], '16 or 21');
  CheckT([$DD, $7E, $05], '19');
  CheckT([$FD, $36, $05, $01], '19');
  CheckT([$DD, $CB, $05, $46], '20');
  CheckT([$DD, $CB, $05, $C6], '23');
  CheckT([$CB, $46], '12');
  CheckT([$ED, $57], '9');
  CheckT([$DD, $E9], '8');
  for Name in CONDACT_NAMES do
    if CondactHelp(Name, False) = '' then
    begin
      WriteLn('FAIL  no help for the DAAD condact ', Name);
      Inc(Failures);
    end;
  for Name in PAW_CONDACT_NAMES do
    if CondactHelp(Name, True) = '' then
    begin
      WriteLn('FAIL  no help for the PAW condact ', Name);
      Inc(Failures);
    end;
  if Pos('PSI', CondactHelp('MOVE', True)) = 0 then
  begin
    WriteLn('FAIL  PAW MOVE: ', CondactHelp('MOVE', True));
    Inc(Failures);
  end;
  if Pos('Succeeds if the current location is the same as locno', CondactHelp('AT', False)) = 0 then
  begin
    WriteLn('FAIL  AT: ', CondactHelp('AT', False));
    Inc(Failures);
  end;
  Seen.Free;
  if Failures = 0 then WriteLn('Instruction and condact help: all passed')
  else
  begin
    WriteLn(Failures, ' failures');
    Halt(1);
  end;
end.

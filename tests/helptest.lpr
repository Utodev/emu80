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

procedure CheckUndoc(const Bytes: array of Byte; Want: Boolean);
var
  I: Integer;
begin
  FillChar(Mem.Bytes, SizeOf(Mem.Bytes), 0);
  for I := 0 to High(Bytes) do Mem.Bytes[I] := Bytes[I];
  if (UndocumentedNote(0, @Mem.Peek) <> '') <> Want then
  begin
    WriteLn('FAIL  undocumented ', Disassemble(0, @Mem.Peek, I), ': ', Want);
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
  CheckUndoc([$CB, $30], True);          // SLL B
  CheckUndoc([$CB, $20], False);         // SLA B
  CheckUndoc([$ED, $44], False);         // NEG
  CheckUndoc([$ED, $4C], True);          // NEG duplicate
  CheckUndoc([$ED, $63], False);         // LD (nn),HL: listed officially
  CheckUndoc([$ED, $70], True);          // IN F,(C)
  CheckUndoc([$ED, $00], True);          // does nothing
  CheckUndoc([$DD, $21], False);         // LD IX,nn
  CheckUndoc([$DD, $26], True);          // LD IXH,n
  CheckUndoc([$DD, $00], True);          // the prefix does nothing
  CheckUndoc([$DD, $CB, $05, $06], False);   // RLC (IX+5)
  CheckUndoc([$DD, $CB, $05, $00], True);    // RLC (IX+5),B
  CheckUndoc([$FD, $CB, $05, $46], False);   // BIT 0,(IY+5)
  CheckUndoc([$FD, $CB, $05, $40], True);    // BIT duplicate
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
    if CondactHelp(Name, aeDAAD) = '' then
    begin
      WriteLn('FAIL  no help for the DAAD condact ', Name);
      Inc(Failures);
    end;
  for Name in PAW_CONDACT_NAMES do
    if CondactHelp(Name, aePAW) = '' then
    begin
      WriteLn('FAIL  no help for the PAW condact ', Name);
      Inc(Failures);
    end;
  if Pos('I already have it', CondactHelp('GET', aeQuill)) = 0 then
  begin
    WriteLn('FAIL  Quill GET: ', CondactHelp('GET', aeQuill));
    Inc(Failures);
  end;
  for Name in PAW_CONDACT_NAMES do
    if CondactHelp(Name, aeQuill) = '' then
    begin
      WriteLn('FAIL  no help for the Quill (PAW) condact ', Name);
      Inc(Failures);
    end;
  if Pos('PSI', CondactHelp('MOVE', aePAW)) = 0 then
  begin
    WriteLn('FAIL  PAW MOVE: ', CondactHelp('MOVE', aePAW));
    Inc(Failures);
  end;
  if Pos('Succeeds if the current location is the same as locno', CondactHelp('AT', aeDAAD)) = 0 then
  begin
    WriteLn('FAIL  AT: ', CondactHelp('AT', aeDAAD));
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

{ Z80Help: what an instruction does, for the debugger's hints: a short
  description with its operands, the registers (or memory) it changes and
  how it affects the flags. Takes the text the disassembler writes (such as
  "LD A,(IX+$05)" or "JR NZ,$0048"). }
unit Z80Help;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Disasm;

function InstructionHelp(const Instr: string): string;

{ The T-states of the instruction at Addr without contention: "4", or
  "7 or 12" for one that takes longer when a condition holds or a block
  instruction repeats }
function InstructionTStates(Addr: Word; Peek: TPeekFunc): string;

{ What a flag of F means (Index 0 = S, bit 7 ... 7 = C, bit 0) }
function FlagHelp(Index: Integer): string;

implementation

const
  F_NONE = 'not affected';
  F_ADD8 = 'S, Z, H, P/V (overflow) and C set by the result; N reset';
  F_SUB8 = 'S, Z, H, P/V (overflow) and C (borrow) set by the result; N set';
  F_CP = 'as SUB (A is not changed): S, Z (set if equal), H, P/V (overflow), C (set if A is ' +
    'smaller, unsigned); N set; bits 5 and 3 come from the operand';
  F_AND = 'S, Z and P/V (parity) set by the result; H set; N and C reset';
  F_ORXOR = 'S, Z and P/V (parity) set by the result; H, N and C reset';
  F_INC = 'S, Z, H and P/V (overflow) set by the result; N reset; C not affected';
  F_DEC = 'S, Z, H and P/V (overflow) set by the result; N set; C not affected';
  F_ADD16 = 'H (carry from bit 11) and C set by the result; N reset; S, Z and P/V not affected';
  F_ADC16 = 'S, Z, H, P/V (overflow) and C set by the 16-bit result; N reset';
  F_SBC16 = 'S, Z, H, P/V (overflow) and C (borrow) set by the 16-bit result; N set';
  F_ROTA = 'C gets the bit moved out; H and N reset; S, Z and P/V not affected';
  F_ROT = 'C gets the bit moved out; S, Z and P/V (parity) set by the result; H and N reset';
  F_RLD = 'S, Z and P/V (parity) set by A; H and N reset; C not affected';
  F_BIT = 'Z set if the bit is 0 (P/V the same; S set if bit 7 is tested and is 1); H set; ' +
    'N reset; C not affected';
  F_LDI = 'P/V set if BC is not 0 afterwards; H and N reset; S, Z and C not affected';
  F_LDIR = 'H, P/V and N reset; S, Z and C not affected';
  F_CPI = 'S, Z (set if A = (HL)) and H set by A - (HL); P/V set if BC is not 0 afterwards; ' +
    'N set; C not affected';
  F_CPIR = 'as CPI for the last comparison: Z set if A was found, P/V set if BC is not 0 ' +
    '(it stopped on a match); N set; C not affected';
  F_INI = 'Z set if B reaches 0; N is bit 7 of the value moved; S, H, P/V and C as the ' +
    'undocumented rules say';
  F_INIR = 'Z set (B is 0 at the end); N is bit 7 of the last value; the others undocumented';
  F_INC_ = 'S, Z and P/V (parity) set by the value read; H and N reset; C not affected';
  F_LDAI = 'S and Z set by the value; P/V = IFF2 (the interrupt state); H and N reset; ' +
    'C not affected';
  F_DAA = 'S, Z, H, P/V (parity) and C set by the corrected result; N not affected';
  F_CPL = 'H and N set; the others not affected';
  F_NEG = 'as 0 - A: S, Z, H, P/V (set if A was 80), C (set if A was not 0); N set';
  F_SCF = 'C set; H and N reset; S, Z and P/V not affected';
  F_CCF = 'C inverted; H gets the previous C; N reset; S, Z and P/V not affected';
  F_POPAF = 'all of them: F is loaded from the stack';
  F_EXAF = 'all of them: F is swapped with F''';

function Is16(const S: string): Boolean;
begin
  Result := (S = 'AF') or (S = 'BC') or (S = 'DE') or (S = 'HL') or (S = 'SP') or (S = 'IX') or
    (S = 'IY') or (S = 'AF''');
end;

function IsReg(const S: string): Boolean;
const
  REGS: array[0..20] of string = ('A', 'B', 'C', 'D', 'E', 'H', 'L', 'I', 'R', 'F', 'IXH', 'IXL',
    'IYH', 'IYL', 'AF', 'BC', 'DE', 'HL', 'SP', 'IX', 'IY');
var
  R: string;
begin
  for R in REGS do
    if S = R then Exit(True);
  Result := Is16(S);
end;

function IsMem(const S: string): Boolean;
begin
  Result := (S <> '') and (S[1] = '(');
end;

{ "(IX+$05)" -> "IX+05" }
function Inner(const S: string): string;
begin
  Result := StringReplace(Copy(S, 2, Length(S) - 2), '$', '', [rfReplaceAll]);
end;

function Num(const S: string): string;
begin
  Result := StringReplace(S, '$', '', [rfReplaceAll]);
end;

{ An operand as a source: a register, a number or memory }
function Src(const S: string; Wide: Boolean): string;
begin
  if IsMem(S) then
  begin
    if Wide then Result := 'the 16-bit word at ' + Inner(S) else Result := 'the byte at ' + Inner(S);
  end
  else if IsReg(S) then Result := S
  else Result := 'the value ' + Num(S);
end;

{ An operand as a destination, for "Changes:" }
function Dst(const S: string; Wide: Boolean): string;
begin
  if IsMem(S) then
  begin
    if Wide then Result := 'memory at ' + Inner(S) + ' (2 bytes)' else Result := 'memory at ' + Inner(S);
  end
  else Result := S;
end;

function CondText(const C: string): string;
begin
  if C = 'NZ' then Result := 'if Z is reset (not zero)'
  else if C = 'Z' then Result := 'if Z is set (zero)'
  else if C = 'NC' then Result := 'if C is reset (no carry)'
  else if C = 'C' then Result := 'if C is set (carry)'
  else if C = 'PO' then Result := 'if P/V is reset (parity odd, no overflow)'
  else if C = 'PE' then Result := 'if P/V is set (parity even, overflow)'
  else if C = 'P' then Result := 'if S is reset (positive)'
  else if C = 'M' then Result := 'if S is set (minus)'
  else Result := '';
end;

function InstructionHelp(const Instr: string): string;
var
  Mnem, Rest, Desc, Changes, Flags, Copy_, Last: string;
  Ops: array of string;
  P: Integer;
  Wide: Boolean;

  function Op(N: Integer): string;
  begin
    if N < Length(Ops) then Result := Ops[N] else Result := '';
  end;

  procedure Set3(const ADesc, AChanges, AFlags: string);
  begin
    Desc := ADesc;
    Changes := AChanges;
    Flags := AFlags;
  end;

begin
  Result := '';
  P := Pos(' ', Instr);
  if P = 0 then
  begin
    Mnem := Instr;
    Rest := '';
  end
  else
  begin
    Mnem := Copy(Instr, 1, P - 1);
    Rest := Trim(Copy(Instr, P + 1, MaxInt));
  end;
  Ops := nil;
  while Rest <> '' do
  begin
    P := Pos(',', Rest);
    SetLength(Ops, Length(Ops) + 1);
    if P = 0 then
    begin
      Ops[High(Ops)] := Rest;
      Rest := '';
    end
    else
    begin
      Ops[High(Ops)] := Copy(Rest, 1, P - 1);
      Rest := Copy(Rest, P + 1, MaxInt);
    end;
  end;
  Last := '';
  if Length(Ops) > 0 then Last := Ops[High(Ops)];
  Desc := '';
  Changes := 'nothing';
  Flags := F_NONE;
  Copy_ := '';

  // 8-bit arithmetic and logic: "ADD A,B" or "SUB B"
  if (Mnem = 'ADD') or (Mnem = 'ADC') or (Mnem = 'SUB') or (Mnem = 'SBC') or (Mnem = 'AND') or
     (Mnem = 'OR') or (Mnem = 'XOR') or (Mnem = 'CP') then
  begin
    Wide := Is16(Op(0)) and (Length(Ops) = 2);
    if Wide then
    begin
      if Mnem = 'ADD' then
        Set3(Format('Add: %s = %s + %s.', [Op(0), Op(0), Op(1)]), Op(0), F_ADD16)
      else if Mnem = 'ADC' then
        Set3(Format('Add with carry: %s = %s + %s + C.', [Op(0), Op(0), Op(1)]), Op(0), F_ADC16)
      else
        Set3(Format('Subtract with carry: %s = %s - %s - C.', [Op(0), Op(0), Op(1)]), Op(0), F_SBC16);
    end
    else if Mnem = 'ADD' then
      Set3(Format('Add: A = A + %s.', [Src(Last, False)]), 'A', F_ADD8)
    else if Mnem = 'ADC' then
      Set3(Format('Add with carry: A = A + %s + C.', [Src(Last, False)]), 'A', F_ADD8)
    else if Mnem = 'SUB' then
      Set3(Format('Subtract: A = A - %s.', [Src(Last, False)]), 'A', F_SUB8)
    else if Mnem = 'SBC' then
      Set3(Format('Subtract with carry (borrow): A = A - %s - C.', [Src(Last, False)]), 'A', F_SUB8)
    else if Mnem = 'AND' then
      Set3(Format('Logical AND: A = A AND %s (only the bits set in both stay set).',
        [Src(Last, False)]), 'A', F_AND)
    else if Mnem = 'OR' then
      Set3(Format('Logical OR: A = A OR %s (the bits set in either are set).', [Src(Last, False)]),
        'A', F_ORXOR)
    else if Mnem = 'XOR' then
    begin
      if Last = 'A' then
        Set3('Exclusive OR of A with itself: A = 0 (a short way of clearing A).', 'A', F_ORXOR)
      else
        Set3(Format('Exclusive OR: A = A XOR %s (the bits set in only one of them are set).',
          [Src(Last, False)]), 'A', F_ORXOR);
    end
    else
      Set3(Format('Compare A with %s: subtracts it from A only to set the flags.',
        [Src(Last, False)]), 'only the flags', F_CP);
  end
  else if Mnem = 'LD' then
  begin
    Wide := Is16(Op(0)) or Is16(Op(1));
    if (Op(0) = 'A') and (Op(1) = 'I') then
      Set3('Load: copies I (the interrupt vector page) into A.', 'A', F_LDAI)
    else if (Op(0) = 'A') and (Op(1) = 'R') then
      Set3('Load: copies R (the memory refresh counter) into A.', 'A', F_LDAI)
    else if Op(0) = 'SP' then
      Set3(Format('Load the stack pointer: SP = %s.', [Src(Op(1), True)]), 'SP', F_NONE)
    else
      Set3(Format('Load: copies %s into %s.', [Src(Op(1), Wide), Dst(Op(0), Wide)]),
        Dst(Op(0), Wide), F_NONE);
  end
  else if Mnem = 'PUSH' then
    Set3(Format('Push %s onto the stack: SP = SP - 2, then %s is stored at SP.', [Op(0), Op(0)]),
      'SP and the 2 bytes below the old SP', F_NONE)
  else if Mnem = 'POP' then
  begin
    Set3(Format('Pop %s from the stack: %s is loaded from SP, then SP = SP + 2.', [Op(0), Op(0)]),
      Op(0) + ', SP', F_NONE);
    if Op(0) = 'AF' then Flags := F_POPAF;
  end
  else if Mnem = 'EX' then
  begin
    if Op(0) = 'AF' then
      Set3('Exchange AF with the alternate AF''.', 'AF, AF''', F_EXAF)
    else if Op(0) = '(SP)' then
      Set3(Format('Exchange %s with the word at the top of the stack (SP is not changed).', [Op(1)]),
        Op(1) + ', the 2 bytes at SP', F_NONE)
    else
      Set3('Exchange DE and HL.', 'DE, HL', F_NONE);
  end
  else if Mnem = 'EXX' then
    Set3('Exchange BC, DE and HL with the alternate BC'', DE'' and HL''.',
      'BC, DE, HL, BC'', DE'', HL''', F_NONE)
  else if (Mnem = 'LDI') or (Mnem = 'LDD') or (Mnem = 'LDIR') or (Mnem = 'LDDR') then
  begin
    if (Mnem = 'LDI') or (Mnem = 'LDIR') then Rest := 'increased' else Rest := 'decreased';
    Desc := Format('Block copy: the byte at HL goes to DE; HL and DE are %s and BC decreased.', [Rest]);
    if Length(Mnem) = 4 then
    begin
      Desc := Desc + ' Repeats until BC is 0 (BC = 0 at the start copies 64K).';
      Flags := F_LDIR;
    end
    else Flags := F_LDI;
    Changes := 'memory at DE, DE, HL, BC';
  end
  else if (Mnem = 'CPI') or (Mnem = 'CPD') or (Mnem = 'CPIR') or (Mnem = 'CPDR') then
  begin
    if (Mnem = 'CPI') or (Mnem = 'CPIR') then Rest := 'increased' else Rest := 'decreased';
    Desc := Format('Block search: compares A with the byte at HL; HL is %s and BC decreased.', [Rest]);
    if Length(Mnem) = 4 then
    begin
      Desc := Desc + ' Repeats until a match (Z set) or BC is 0.';
      Flags := F_CPIR;
    end
    else Flags := F_CPI;
    Changes := 'HL, BC';
  end
  else if Mnem = 'INC' then
  begin
    if Is16(Op(0)) then
      Set3(Format('Increase %s by one (from FFFF it goes to 0000).', [Op(0)]), Op(0), F_NONE)
    else
      Set3(Format('Increase %s by one.', [Src(Op(0), False)]), Dst(Op(0), False), F_INC);
  end
  else if Mnem = 'DEC' then
  begin
    if Is16(Op(0)) then
      Set3(Format('Decrease %s by one (from 0000 it goes to FFFF).', [Op(0)]), Op(0), F_NONE)
    else
      Set3(Format('Decrease %s by one.', [Src(Op(0), False)]), Dst(Op(0), False), F_DEC);
  end
  else if Mnem = 'DAA' then
    Set3('Decimal adjust A: corrects A after a BCD addition or subtraction (uses N and H).', 'A', F_DAA)
  else if Mnem = 'CPL' then
    Set3('Complement A: every bit of A is inverted (A = A XOR FF).', 'A', F_CPL)
  else if Mnem = 'NEG' then
    Set3('Negate A: A = 0 - A (two''s complement).', 'A', F_NEG)
  else if Mnem = 'CCF' then
    Set3('Complement the carry flag: C is inverted.', 'only the flags', F_CCF)
  else if Mnem = 'SCF' then
    Set3('Set the carry flag.', 'only the flags', F_SCF)
  else if Mnem = 'NOP' then
    Set3('No operation: does nothing for 4 T-states.', 'nothing', F_NONE)
  else if Mnem = 'NOP*' then
    Set3('A prefix with no effect (DD or FD before another prefix): works as a NOP.', 'nothing', F_NONE)
  else if Mnem = 'HALT' then
    Set3('Halt: the CPU repeats NOPs until an interrupt (or NMI) comes; then it carries on ' +
      'after the HALT.', 'nothing (R keeps counting)', F_NONE)
  else if Mnem = 'DI' then
    Set3('Disable interrupts: IFF1 and IFF2 are reset (the NMI still works).', 'IFF1, IFF2', F_NONE)
  else if Mnem = 'EI' then
    Set3('Enable interrupts: IFF1 and IFF2 are set; an interrupt is only accepted after the ' +
      'next instruction.', 'IFF1, IFF2', F_NONE)
  else if Mnem = 'IM' then
  begin
    if Op(0) = '2' then
      Desc := 'Interrupt mode 2: the interrupt calls the address stored at I * 256 + the byte ' +
        'on the data bus (on the Spectrum, usually FF).'
    else if Op(0) = '1' then
      Desc := 'Interrupt mode 1: the interrupt calls 0038 (RST 38), as the Spectrum''s ROM uses.'
    else
      Desc := 'Interrupt mode 0: the interrupt runs the instruction on the data bus (on the ' +
        'Spectrum, FF: RST 38).';
    Changes := 'the interrupt mode';
  end
  else if (Mnem = 'RLCA') or (Mnem = 'RLA') or (Mnem = 'RRCA') or (Mnem = 'RRA') then
  begin
    if Mnem = 'RLCA' then Desc := 'Rotate A left: bit 7 goes to bit 0 and to C.'
    else if Mnem = 'RLA' then Desc := 'Rotate A left through the carry: bit 7 goes to C, C to bit 0.'
    else if Mnem = 'RRCA' then Desc := 'Rotate A right: bit 0 goes to bit 7 and to C.'
    else Desc := 'Rotate A right through the carry: bit 0 goes to C, C to bit 7.';
    Changes := 'A';
    Flags := F_ROTA;
  end
  else if (Mnem = 'RLC') or (Mnem = 'RL') or (Mnem = 'RRC') or (Mnem = 'RR') or (Mnem = 'SLA') or
          (Mnem = 'SRA') or (Mnem = 'SLL') or (Mnem = 'SRL') then
  begin
    Rest := Src(Op(0), False);
    if Mnem = 'RLC' then Desc := Format('Rotate %s left: bit 7 goes to bit 0 and to C.', [Rest])
    else if Mnem = 'RL' then Desc := Format('Rotate %s left through the carry: bit 7 goes to C, C to bit 0.', [Rest])
    else if Mnem = 'RRC' then Desc := Format('Rotate %s right: bit 0 goes to bit 7 and to C.', [Rest])
    else if Mnem = 'RR' then Desc := Format('Rotate %s right through the carry: bit 0 goes to C, C to bit 7.', [Rest])
    else if Mnem = 'SLA' then Desc := Format('Shift %s left: bit 7 goes to C, bit 0 becomes 0 (multiplies by 2).', [Rest])
    else if Mnem = 'SRA' then Desc := Format('Shift %s right keeping the sign: bit 0 goes to C, bit 7 stays (signed divide by 2).', [Rest])
    else if Mnem = 'SLL' then Desc := Format('Undocumented shift left of %s: bit 7 goes to C, bit 0 becomes 1.', [Rest])
    else Desc := Format('Shift %s right: bit 0 goes to C, bit 7 becomes 0 (unsigned divide by 2).', [Rest]);
    Changes := Dst(Op(0), False);
    Flags := F_ROT;
    if Length(Ops) > 1 then Copy_ := Op(1);
  end
  else if (Mnem = 'RLD') or (Mnem = 'RRD') then
  begin
    if Mnem = 'RLD' then
      Desc := 'Rotate digits left: the low 4 bits of (HL) go to its high 4 bits, those to the ' +
        'low 4 bits of A, and those of A to the low 4 bits of (HL).'
    else
      Desc := 'Rotate digits right: the low 4 bits of A go to the high 4 bits of (HL), those ' +
        'to its low 4 bits, and those to the low 4 bits of A.';
    Changes := 'A, memory at HL';
    Flags := F_RLD;
  end
  else if Mnem = 'BIT' then
    Set3(Format('Test bit %s of %s: Z is set if it is 0.', [Op(0), Src(Op(1), False)]),
      'only the flags', F_BIT)
  else if (Mnem = 'SET') or (Mnem = 'RES') then
  begin
    if Mnem = 'SET' then Rest := 'Set bit %s of %s to 1.' else Rest := 'Reset bit %s of %s to 0.';
    Set3(Format(Rest, [Op(0), Src(Op(1), False)]), Dst(Op(1), False), F_NONE);
    if Length(Ops) > 2 then Copy_ := Op(2);
  end
  else if (Mnem = 'JP') or (Mnem = 'JR') then
  begin
    if Length(Ops) = 2 then
      Desc := Format('Jump to %s %s.', [Num(Op(1)), CondText(Op(0))])
    else if IsMem(Op(0)) then
      Desc := Format('Jump to the address in %s (PC = %s).', [Inner(Op(0)), Inner(Op(0))])
    else
      Desc := Format('Jump to %s.', [Num(Op(0))]);
    if Mnem = 'JR' then Desc := Desc + ' Relative jump: up to 128 bytes back or 127 forward.';
    Changes := 'PC';
  end
  else if Mnem = 'DJNZ' then
    Set3(Format('Decrease B and jump to %s if it is not 0 (a loop of B times).', [Num(Op(0))]),
      'B, PC', F_NONE)
  else if Mnem = 'CALL' then
  begin
    if Length(Ops) = 2 then
      Desc := Format('Call the subroutine at %s %s: the return address is pushed onto the stack.',
        [Num(Op(1)), CondText(Op(0))])
    else
      Desc := Format('Call the subroutine at %s: the return address is pushed onto the stack.',
        [Num(Op(0))]);
    Changes := 'PC, SP, the 2 bytes below the old SP';
  end
  else if Mnem = 'RET' then
  begin
    if Length(Ops) = 1 then
      Desc := Format('Return from a subroutine %s: PC is popped from the stack.', [CondText(Op(0))])
    else
      Desc := 'Return from a subroutine: PC is popped from the stack.';
    Changes := 'PC, SP';
  end
  else if Mnem = 'RETI' then
    Set3('Return from an interrupt: PC is popped from the stack (IFF1 also gets IFF2).', 'PC, SP, IFF1', F_NONE)
  else if Mnem = 'RETN' then
    Set3('Return from a non-maskable interrupt (NMI): PC is popped from the stack and IFF1 ' +
      'gets IFF2 back.', 'PC, SP, IFF1', F_NONE)
  else if Mnem = 'RST' then
    Set3(Format('Restart: calls %s (a one-byte CALL); the return address is pushed onto the stack.',
      [Num(Op(0))]), 'PC, SP, the 2 bytes below the old SP', F_NONE)
  else if Mnem = 'IN' then
  begin
    if Op(1) = '(C)' then
    begin
      if Op(0) = 'F' then
        Set3('Read the port in BC only to set the flags (undocumented).', 'only the flags', F_INC_)
      else
        Set3(Format('Read the port in BC (B is the high byte) into %s.', [Op(0)]), Op(0), F_INC_);
    end
    else
      Set3(Format('Read port A * 256 + %s into A (A is the high byte of the port).',
        [Inner(Op(1))]), 'A', F_NONE);
  end
  else if Mnem = 'OUT' then
  begin
    if Op(0) = '(C)' then
      Desc := Format('Write %s to the port in BC (B is the high byte).', [Src(Op(1), False)])
    else
      Desc := Format('Write A to port A * 256 + %s (A is the high byte of the port).', [Inner(Op(0))]);
    Changes := 'nothing in the CPU (the port)';
  end
  else if (Mnem = 'INI') or (Mnem = 'IND') or (Mnem = 'INIR') or (Mnem = 'INDR') then
  begin
    if (Mnem = 'INI') or (Mnem = 'INIR') then Rest := 'increased' else Rest := 'decreased';
    Desc := Format('Block input: reads the port in BC into the byte at HL; B is decreased and HL %s.', [Rest]);
    if Length(Mnem) = 4 then
    begin
      Desc := Desc + ' Repeats until B is 0.';
      Flags := F_INIR;
    end
    else Flags := F_INI;
    Changes := 'memory at HL, HL, B';
  end
  else if (Mnem = 'OUTI') or (Mnem = 'OUTD') or (Mnem = 'OTIR') or (Mnem = 'OTDR') then
  begin
    if (Mnem = 'OUTI') or (Mnem = 'OTIR') then Rest := 'increased' else Rest := 'decreased';
    Desc := Format('Block output: B is decreased, then the byte at HL is written to the port in ' +
      'BC; HL is %s.', [Rest]);
    if Copy(Mnem, 1, 2) = 'OT' then
    begin
      Desc := Desc + ' Repeats until B is 0.';
      Flags := F_INIR;
    end
    else Flags := F_INI;
    Changes := 'HL, B';
  end
  else
    Exit;

  // DDCB rotations, SET and RES with a register: the result also goes there
  if Copy_ <> '' then
  begin
    Desc := Desc + Format(' Undocumented: the result is also copied to %s.', [Copy_]);
    Changes := Changes + ', ' + Copy_;
  end;
  Result := Instr + LineEnding + Desc + LineEnding + 'Changes: ' + Changes + LineEnding +
    'Flags: ' + Flags;
end;

const
  { Unprefixed opcodes: T-states (conditional ones: when not taken) }
  MAIN_T: array[0..255] of Byte = (
    4, 10, 7, 6, 4, 4, 7, 4, 4, 11, 7, 6, 4, 4, 7, 4,
    8, 10, 7, 6, 4, 4, 7, 4, 12, 11, 7, 6, 4, 4, 7, 4,
    7, 10, 16, 6, 4, 4, 7, 4, 7, 11, 16, 6, 4, 4, 7, 4,
    7, 10, 13, 6, 11, 11, 10, 4, 7, 11, 13, 6, 4, 4, 7, 4,
    4, 4, 4, 4, 4, 4, 7, 4, 4, 4, 4, 4, 4, 4, 7, 4,
    4, 4, 4, 4, 4, 4, 7, 4, 4, 4, 4, 4, 4, 4, 7, 4,
    4, 4, 4, 4, 4, 4, 7, 4, 4, 4, 4, 4, 4, 4, 7, 4,
    7, 7, 7, 7, 7, 7, 4, 7, 4, 4, 4, 4, 4, 4, 7, 4,
    4, 4, 4, 4, 4, 4, 7, 4, 4, 4, 4, 4, 4, 4, 7, 4,
    4, 4, 4, 4, 4, 4, 7, 4, 4, 4, 4, 4, 4, 4, 7, 4,
    4, 4, 4, 4, 4, 4, 7, 4, 4, 4, 4, 4, 4, 4, 7, 4,
    4, 4, 4, 4, 4, 4, 7, 4, 4, 4, 4, 4, 4, 4, 7, 4,
    5, 10, 10, 10, 10, 11, 7, 11, 5, 10, 10, 0, 10, 17, 7, 11,
    5, 10, 10, 11, 10, 11, 7, 11, 5, 4, 10, 11, 10, 0, 7, 11,
    5, 10, 10, 19, 10, 11, 7, 11, 5, 4, 10, 4, 10, 0, 7, 11,
    5, 10, 10, 4, 10, 11, 7, 11, 5, 6, 10, 4, 10, 0, 7, 11);

{ When the condition holds (0 = not conditional) }
function TakenT(Op: Byte): Integer;
begin
  case Op of
    $10: Result := 13;                                        // DJNZ
    $20, $28, $30, $38: Result := 12;                         // JR cc
    $C0, $C8, $D0, $D8, $E0, $E8, $F0, $F8: Result := 11;     // RET cc
    $C4, $CC, $D4, $DC, $E4, $EC, $F4, $FC: Result := 17;     // CALL cc
  else
    Result := 0;
  end;
end;

{ The unprefixed opcode reads or writes (HL) }
function UsesMemHL(Op: Byte): Boolean;
begin
  case Op of
    $34, $35, $36: Result := True;
    $40..$75, $77..$7F: Result := ((Op and 7) = 6) or (((Op shr 3) and 7) = 6);
    $80..$BF: Result := (Op and 7) = 6;
  else
    Result := False;
  end;
end;

function InstructionTStates(Addr: Word; Peek: TPeekFunc): string;
var
  Op, Op2: Byte;
  T, T2, Extra: Integer;
begin
  Op := Peek(Addr);
  T2 := 0;
  case Op of
    $CB:
      begin
        Op2 := Peek(Word(Addr + 1));
        if (Op2 and 7) <> 6 then T := 8
        else if Op2 in [$40..$7F] then T := 12     // BIT n,(HL)
        else T := 15;
      end;
    $ED:
      begin
        Op2 := Peek(Word(Addr + 1));
        T := 8;
        case Op2 of
          $40..$7F:
            case Op2 and 7 of
              0, 1: T := 12;                          // IN r,(C) / OUT (C),r
              2: T := 15;                             // ADC/SBC HL,rr
              3: T := 20;                             // LD (nn),rr / LD rr,(nn)
              4, 6: T := 8;                           // NEG, IM
              5: T := 14;                             // RETN, RETI
              7:
                case (Op2 shr 3) and 7 of
                  0..3: T := 9;                       // LD I,A ... LD A,R
                  4, 5: T := 18;                      // RRD, RLD
                end;
            end;
          $A0..$A3, $A8..$AB: T := 16;                // LDI, CPI, INI, OUTI...
          $B0..$B3, $B8..$BB:
            begin
              T := 16;                                // the last time
              T2 := 21;                               // repeating
            end;
        end;
      end;
    $DD, $FD:
      begin
        Op2 := Peek(Word(Addr + 1));
        if Op2 in [$DD, $ED, $FD] then
          T := 4                                      // prefix with no effect
        else if Op2 = $CB then
        begin
          // DDCB d op: BIT 20, the rest 23
          if Peek(Word(Addr + 3)) in [$40..$7F] then T := 20 else T := 23;
        end
        else
        begin
          // HL becomes IX/IY (4 more); (HL) becomes (IX+d) (the displacement
          // adds 12, 9 for LD (IX+d),n)
          if Op2 = $36 then Extra := 9
          else if UsesMemHL(Op2) then Extra := 12
          else Extra := 4;
          T := MAIN_T[Op2] + Extra;
          T2 := TakenT(Op2);
          if T2 > 0 then Inc(T2, Extra);
        end;
      end;
  else
    T := MAIN_T[Op];
    T2 := TakenT(Op);
  end;
  if T2 > 0 then Result := Format('%d or %d', [T, T2]) else Result := IntToStr(T);
end;

function FlagHelp(Index: Integer): string;
begin
  case Index of
    0: Result := 'S - Sign (bit 7): a copy of bit 7 of the result; set when it is negative ' +
      '(80-FF as a signed number).';
    1: Result := 'Z - Zero (bit 6): set when the result is 0 (and by BIT when the bit is 0, by ' +
      'CP when both are equal).';
    2: Result := '5 - Undocumented (bit 5, also called Y or F5): usually a copy of bit 5 of the ' +
      'result (of the operand for CP; other rules for block instructions and BIT).';
    3: Result := 'H - Half carry (bit 4): carry from bit 3 to bit 4 (or borrow), used by DAA.';
    4: Result := '3 - Undocumented (bit 3, also called X or F3): usually a copy of bit 3 of the ' +
      'result (of the operand for CP; other rules for block instructions and BIT).';
    5: Result := 'P/V - Parity or overflow (bit 2): the parity of the result after logic ' +
      'operations, rotations and IN (set = even), signed overflow after arithmetic, IFF2 after ' +
      'LD A,I and LD A,R, and BC <> 0 after block copies and searches.';
    6: Result := 'N - Add/subtract (bit 1): set if the last operation was a subtraction; DAA ' +
      'uses it.';
  else
    Result := 'C - Carry (bit 0): carry out of bit 7 (or borrow), and the bit moved out by ' +
      'rotations and shifts; SCF sets it, CCF inverts it.';
  end;
end;

end.

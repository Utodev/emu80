{ C64Help: what each 6510 instruction does, shown by the C64 debugger when the mouse rests on a mnemonic (as Z80Help does for
  the Z80): a description, the flags it changes, its addressing mode and its cycles. }
unit C64Help;

{$mode objfpc}{$H+}

interface

{ The help for the opcode Op (its operand, if any, is Operand as the disassembler writes it) }
function InstructionHelp6502(Op: Byte; const Operand: string): string;
{ The meaning of the flag with bit number Bit (7 = N ... 0 = C) }
function FlagHelp6502(Bit: Integer): string;
{ The cycles of the instruction as text }
function CyclesText(Op: Byte): string;

implementation

uses
  SysUtils, Cpu6510;

function Describe(const M: string; out Flags: string): string;
begin
  Flags := '';
  Result := '';
  case M of
    'LDA': begin Result := 'Load the accumulator: A := M'; Flags := 'N Z'; end;
    'LDX': begin Result := 'Load X: X := M'; Flags := 'N Z'; end;
    'LDY': begin Result := 'Load Y: Y := M'; Flags := 'N Z'; end;
    'STA': Result := 'Store the accumulator: M := A';
    'STX': Result := 'Store X: M := X';
    'STY': Result := 'Store Y: M := Y';
    'TAX': begin Result := 'Transfer A to X: X := A'; Flags := 'N Z'; end;
    'TAY': begin Result := 'Transfer A to Y: Y := A'; Flags := 'N Z'; end;
    'TXA': begin Result := 'Transfer X to A: A := X'; Flags := 'N Z'; end;
    'TYA': begin Result := 'Transfer Y to A: A := Y'; Flags := 'N Z'; end;
    'TSX': begin Result := 'Transfer the stack pointer to X: X := SP'; Flags := 'N Z'; end;
    'TXS': Result := 'Transfer X to the stack pointer: SP := X (no flags change)';
    'PHA': Result := 'Push the accumulator on the stack';
    'PHP': Result := 'Push the status register on the stack (with B and the unused bit set)';
    'PLA': begin Result := 'Pull the accumulator from the stack'; Flags := 'N Z'; end;
    'PLP': begin Result := 'Pull the status register from the stack'; Flags := 'all'; end;
    'AND': begin Result := 'Logical AND: A := A and M'; Flags := 'N Z'; end;
    'ORA': begin Result := 'Logical OR: A := A or M'; Flags := 'N Z'; end;
    'EOR': begin Result := 'Exclusive OR: A := A xor M'; Flags := 'N Z'; end;
    'BIT': begin Result := 'Test bits: Z is set if A and M = 0; N and V are copies of bits 7 and 6 of M'; Flags := 'N V Z'; end;
    'ADC': begin Result := 'Add with carry: A := A + M + C (decimal mode adds in BCD)'; Flags := 'N V Z C'; end;
    'SBC': begin Result := 'Subtract with borrow: A := A - M - (1 - C) (decimal mode subtracts in BCD)'; Flags := 'N V Z C'; end;
    'CMP': begin Result := 'Compare A with M (A - M, the result is discarded)'; Flags := 'N Z C'; end;
    'CPX': begin Result := 'Compare X with M (X - M, the result is discarded)'; Flags := 'N Z C'; end;
    'CPY': begin Result := 'Compare Y with M (Y - M, the result is discarded)'; Flags := 'N Z C'; end;
    'INC': begin Result := 'Increment memory: M := M + 1'; Flags := 'N Z'; end;
    'INX': begin Result := 'Increment X'; Flags := 'N Z'; end;
    'INY': begin Result := 'Increment Y'; Flags := 'N Z'; end;
    'DEC': begin Result := 'Decrement memory: M := M - 1'; Flags := 'N Z'; end;
    'DEX': begin Result := 'Decrement X'; Flags := 'N Z'; end;
    'DEY': begin Result := 'Decrement Y'; Flags := 'N Z'; end;
    'ASL': begin Result := 'Arithmetic shift left: bit 7 goes to C, bit 0 is cleared'; Flags := 'N Z C'; end;
    'LSR': begin Result := 'Logical shift right: bit 0 goes to C, bit 7 is cleared'; Flags := 'N Z C'; end;
    'ROL': begin Result := 'Rotate left through the carry: bit 7 goes to C, C goes to bit 0'; Flags := 'N Z C'; end;
    'ROR': begin Result := 'Rotate right through the carry: bit 0 goes to C, C goes to bit 7'; Flags := 'N Z C'; end;
    'JMP': Result := 'Jump: PC := the address (JMP (addr) reads it from memory; its high byte does not cross a page)';
    'JSR': Result := 'Jump to a subroutine: pushes the address of its last byte, then PC := the address';
    'RTS': Result := 'Return from a subroutine: pulls the address and goes to the next byte';
    'RTI': begin Result := 'Return from an interrupt: pulls the status register, then PC'; Flags := 'all'; end;
    'BRK': begin Result := 'Software interrupt: pushes PC+2 and the status (B set), sets I, and jumps through ($FFFE)'; Flags := 'I'; end;
    'BCC': Result := 'Branch if the carry is clear (C = 0)';
    'BCS': Result := 'Branch if the carry is set (C = 1)';
    'BEQ': Result := 'Branch if equal (Z = 1)';
    'BNE': Result := 'Branch if not equal (Z = 0)';
    'BMI': Result := 'Branch if minus (N = 1)';
    'BPL': Result := 'Branch if plus (N = 0)';
    'BVC': Result := 'Branch if the overflow is clear (V = 0)';
    'BVS': Result := 'Branch if the overflow is set (V = 1)';
    'CLC': begin Result := 'Clear the carry'; Flags := 'C'; end;
    'SEC': begin Result := 'Set the carry'; Flags := 'C'; end;
    'CLD': begin Result := 'Clear the decimal mode'; Flags := 'D'; end;
    'SED': begin Result := 'Set the decimal mode (ADC and SBC work in BCD)'; Flags := 'D'; end;
    'CLI': begin Result := 'Clear the interrupt disable: IRQs are allowed'; Flags := 'I'; end;
    'SEI': begin Result := 'Set the interrupt disable: IRQs are ignored'; Flags := 'I'; end;
    'CLV': begin Result := 'Clear the overflow'; Flags := 'V'; end;
    'NOP': Result := 'No operation';
    // The illegal opcodes
    'SLO': begin Result := 'ASL memory, then ORA the result into A'; Flags := 'N Z C'; end;
    'RLA': begin Result := 'ROL memory, then AND the result into A'; Flags := 'N Z C'; end;
    'SRE': begin Result := 'LSR memory, then EOR the result into A'; Flags := 'N Z C'; end;
    'RRA': begin Result := 'ROR memory, then ADC the result into A'; Flags := 'N V Z C'; end;
    'SAX': Result := 'Store A and X: M := A and X';
    'LAX': begin Result := 'Load A and X with M'; Flags := 'N Z'; end;
    'DCP': begin Result := 'DEC memory, then CMP it with A'; Flags := 'N Z C'; end;
    'ISC': begin Result := 'INC memory, then SBC it from A'; Flags := 'N V Z C'; end;
    'ANC': begin Result := 'A := A and M, then C := N'; Flags := 'N Z C'; end;
    'ALR': begin Result := 'A := A and M, then LSR A'; Flags := 'N Z C'; end;
    'ARR': begin Result := 'A := A and M, then ROR A (C and V come from bits 6 and 5)'; Flags := 'N V Z C'; end;
    'ANE': begin Result := 'A := (A or $EE) and X and M (unstable)'; Flags := 'N Z'; end;
    'LXA': begin Result := 'A, X := (A or $EE) and M (unstable)'; Flags := 'N Z'; end;
    'AXS': begin Result := 'X := (A and X) - M, without borrow'; Flags := 'N Z C'; end;
    'SHA': Result := 'Store A and X and (high byte of the address + 1) (unstable)';
    'SHX': Result := 'Store X and (high byte of the address + 1) (unstable)';
    'SHY': Result := 'Store Y and (high byte of the address + 1) (unstable)';
    'TAS': Result := 'SP := A and X, then store SP and (high byte of the address + 1) (unstable)';
    'LAS': begin Result := 'A, X, SP := M and SP'; Flags := 'N Z'; end;
    'KIL': Result := 'Halts the processor until a reset';
  end;
end;

function ModeText(Mode: TAddrMode): string;
begin
  case Mode of
    amImp: Result := 'implied';
    amAcc: Result := 'accumulator';
    amImm: Result := 'immediate';
    amZp: Result := 'zero page';
    amZpx: Result := 'zero page, X';
    amZpy: Result := 'zero page, Y';
    amAbs: Result := 'absolute';
    amAbx: Result := 'absolute, X';
    amAby: Result := 'absolute, Y';
    amInd: Result := 'indirect';
    amIzx: Result := '(zero page, X) indirect';
    amIzy: Result := '(zero page) indirect, Y';
    amRel: Result := 'relative';
  else
    Result := '';
  end;
end;

function IsBranch(Op: Byte): Boolean;
begin
  Result := OpMode[Op] = amRel;
end;

function IsStore(const M: string): Boolean;
begin
  Result := (M = 'STA') or (M = 'STX') or (M = 'STY') or (M = 'SAX') or (M = 'SHA') or (M = 'SHX') or (M = 'SHY') or (M = 'TAS');
end;

function IsRmw(const M: string): Boolean;
begin
  Result := (M = 'ASL') or (M = 'LSR') or (M = 'ROL') or (M = 'ROR') or (M = 'INC') or (M = 'DEC') or (M = 'SLO') or
    (M = 'RLA') or (M = 'SRE') or (M = 'RRA') or (M = 'DCP') or (M = 'ISC');
end;

function CyclesText(Op: Byte): string;
var
  M: string;
  Mode: TAddrMode;
  N: Integer;
  Extra: Boolean;
begin
  M := OpName[Op];
  Mode := OpMode[Op];
  if M = 'KIL' then Exit('never ends');
  if IsBranch(Op) then Exit('2 (+1 if the branch is taken, +1 more if it crosses a page)');
  if M = 'BRK' then Exit('7');
  if (M = 'JSR') or (M = 'RTS') or (M = 'RTI') then Exit('6');
  if (M = 'PHA') or (M = 'PHP') then Exit('3');
  if (M = 'PLA') or (M = 'PLP') then Exit('4');
  if M = 'JMP' then
  begin
    if Mode = amInd then Exit('5') else Exit('3');
  end;
  Extra := False;
  if IsRmw(M) then
    case Mode of
      amAcc: N := 2;
      amZp: N := 5;
      amZpx, amAbs: N := 6;
      amAbx, amAby: N := 7;
    else
      N := 8;
    end
  else if IsStore(M) then
    case Mode of
      amZp: N := 3;
      amZpx, amZpy, amAbs: N := 4;
      amAbx, amAby: N := 5;
    else
      N := 6;
    end
  else
    case Mode of
      amImp, amAcc, amImm: N := 2;
      amZp: N := 3;
      amZpx, amZpy, amAbs: N := 4;
      amAbx, amAby: begin N := 4; Extra := True; end;
      amIzx: N := 6;
      amIzy: begin N := 5; Extra := True; end;
    else
      N := 2;
    end;
  Result := IntToStr(N);
  if Extra then Result := Result + ' (+1 if it crosses a page)';
end;

function InstructionHelp6502(Op: Byte; const Operand: string): string;
var
  M, Flags: string;
begin
  M := OpName[Op];
  Result := Describe(M, Flags);
  if Result = '' then Exit('');
  if OpIllegal[Op] then Result := M + ': ' + Result + LineEnding + 'Undocumented (illegal) opcode' else Result := M + ': ' + Result;
  if Flags = 'all' then Flags := 'N V - B D I Z C (as pulled)';
  if Flags <> '' then Result := Result + LineEnding + 'Flags: ' + Flags
  else Result := Result + LineEnding + 'Flags: none';
  Result := Result + LineEnding + 'Mode: ' + ModeText(OpMode[Op]) + LineEnding + 'Bytes: ' + IntToStr(OpLength(Op)) +
    LineEnding + 'Cycles: ' + CyclesText(Op);
end;

function FlagHelp6502(Bit: Integer): string;
begin
  case Bit of
    7: Result := 'N (negative): a copy of bit 7 of the last result';
    6: Result := 'V (overflow): signed overflow of ADC / SBC, or bit 6 of the operand of BIT';
    5: Result := 'The unused bit, always 1';
    4: Result := 'B (break): 1 in the status pushed by BRK and PHP, 0 when an interrupt pushes it';
    3: Result := 'D (decimal): ADC and SBC work in BCD';
    2: Result := 'I (interrupt disable): the IRQ is ignored while it is set (the NMI is not)';
    1: Result := 'Z (zero): the last result was zero';
    0: Result := 'C (carry): the carry or the inverted borrow of the last operation, or the bit shifted out';
  else
    Result := '';
  end;
end;

end.

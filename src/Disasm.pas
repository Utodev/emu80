{ Disasm: Z80 disassembler, including undocumented instructions and the
  CB, ED, DD/FD and DDCB/FDCB prefixes. Numbers are shown in hex with "$". }
unit Disasm;

{$mode objfpc}{$H+}
{$R-}{$Q-}

interface

uses
  SysUtils;

type
  TPeekFunc = function(Addr: Word): Byte of object;

  TCondition = (cdNone, cdTaken, cdNotTaken);

  { What a 16-bit operand is used for }
  TOperandKind = (okNone,
    okJump,      // target of JP, JR, CALL or DJNZ
    okMemory,    // address in brackets: LD A,($5C78)
    okImmediate  // plain value: LD HL,$4000
  );

var
  { Show the ZX Spectrum Next's Z80N instructions (otherwise those ED
    opcodes are NOP*) }
  Z80NMnemonics: Boolean = False;

{ Disassemble the instruction at Addr. Len receives its length in bytes. }
function Disassemble(Addr: Word; Peek: TPeekFunc; out Len: Integer): string;
{ Also returns the 16-bit operand (shown in the text as "$XXXX") and its kind;
  Operand is -1 when there is none. }
function DisassembleEx(Addr: Word; Peek: TPeekFunc; out Len: Integer; out Operand: Integer;
  out Kind: TOperandKind): string;

{ For conditional jumps, calls and returns at Addr: whether the condition holds
  for the given flags (and B, for DJNZ). }
function ConditionAt(Addr: Word; Peek: TPeekFunc; F, B: Byte): TCondition;

{ True if "step over" should run to the following instruction instead of
  stepping into it: CALL, RST, DJNZ, HALT and repeating block instructions. }
function IsStepOver(Addr: Word; Peek: TPeekFunc): Boolean;
{ An instruction of the ZX Spectrum Next's Z80N set (only while Z80NMnemonics
  is on): the ED opcodes it adds, not every instruction the Z80 didn't have }
function IsZ80N(Addr: Word; Peek: TPeekFunc): Boolean;

implementation

const
  R8: array[0..7] of string = ('B', 'C', 'D', 'E', 'H', 'L', '(HL)', 'A');
  RP: array[0..3] of string = ('BC', 'DE', 'HL', 'SP');
  RP2: array[0..3] of string = ('BC', 'DE', 'HL', 'AF');
  CC: array[0..7] of string = ('NZ', 'Z', 'NC', 'C', 'PO', 'PE', 'P', 'M');
  ALU: array[0..7] of string = ('ADD A,', 'ADC A,', 'SUB ', 'SBC A,', 'AND ', 'XOR ', 'OR ', 'CP ');
  ROT: array[0..7] of string = ('RLC', 'RRC', 'RL', 'RR', 'SLA', 'SRA', 'SLL', 'SRL');
  IMODE: array[0..7] of string = ('0', '0', '1', '2', '0', '0', '1', '2');
  BLOCK: array[0..3, 0..3] of string = (
    ('LDI', 'CPI', 'INI', 'OUTI'), ('LDD', 'CPD', 'IND', 'OUTD'),
    ('LDIR', 'CPIR', 'INIR', 'OTIR'), ('LDDR', 'CPDR', 'INDR', 'OTDR'));

function Hex2(V: Integer): string;
begin
  Result := '$' + IntToHex(V and $FF, 2);
end;

function Hex4(V: Integer): string;
begin
  Result := '$' + IntToHex(V and $FFFF, 4);
end;

function Disassemble(Addr: Word; Peek: TPeekFunc; out Len: Integer): string;
var
  Operand: Integer;
  Kind: TOperandKind;
begin
  Result := DisassembleEx(Addr, Peek, Len, Operand, Kind);
end;

function DisassembleEx(Addr: Word; Peek: TPeekFunc; out Len: Integer; out Operand: Integer;
  out Kind: TOperandKind): string;
var
  Op, X, Y, Z, P, Q: Byte;
  Index: string;      // '' for HL, 'IX' or 'IY' after a DD/FD prefix
  Disp: ShortInt;
  HasDisp: Boolean;

  function Next: Byte;
  begin
    Result := Peek(Word(Addr + Len));
    Inc(Len);
  end;

  function Imm8: string;
  begin
    Result := Hex2(Next);
  end;

  function Imm16: string;
  var
    Lo: Byte;
  begin
    Lo := Next;
    Operand := Lo or (Next shl 8);
    Result := Hex4(Operand);
  end;

  { (HL) becomes (IX+d); the displacement is read on first use }
  function MemHL: string;
  begin
    if Index = '' then Exit('(HL)');
    if not HasDisp then
    begin
      Disp := ShortInt(Next);
      HasDisp := True;
    end;
    if Disp < 0 then
      Result := Format('(%s-%s)', [Index, Hex2(-Disp)])
    else
      Result := Format('(%s+%s)', [Index, Hex2(Disp)]);
  end;

  { 8-bit register; H/L become IXH/IXL unless (IX+d) is also used }
  function Reg(N: Integer; UsesMem: Boolean): string;
  begin
    if N = 6 then Exit(MemHL);
    Result := R8[N];
    if (Index <> '') and not UsesMem and (N in [4, 5]) then
      Result := Index + R8[N];
  end;

  function RegPair(N: Integer): string;
  begin
    if (N = 2) and (Index <> '') then Result := Index else Result := RP[N];
  end;

  function RegPair2(N: Integer): string;
  begin
    if (N = 2) and (Index <> '') then Result := Index else Result := RP2[N];
  end;

  function Relative: string;
  var
    D: ShortInt;
  begin
    D := ShortInt(Next);
    Operand := Word(Addr + Len + D);
    Result := Hex4(Operand);
  end;

  function DecodeCB: string;
  var
    Op2: Byte;
    Target: string;
  begin
    if Index <> '' then
    begin
      // DDCB d op: displacement comes before the opcode
      Target := MemHL;
      Op2 := Next;
    end
    else
    begin
      Op2 := Next;
      Target := R8[Op2 and 7];
    end;
    X := Op2 shr 6;
    Y := (Op2 shr 3) and 7;
    Z := Op2 and 7;
    case X of
      0: Result := ROT[Y] + ' ' + Target;
      1: Result := Format('BIT %d,%s', [Y, Target]);
      2: Result := Format('RES %d,%s', [Y, Target]);
    else
      Result := Format('SET %d,%s', [Y, Target]);
    end;
    // Undocumented: indexed ops (except BIT) also copy the result to a register
    if (Index <> '') and (Z <> 6) and (X <> 1) then
      Result := Result + ',' + R8[Z];
  end;

  function DecodeED: string;
  var
    Op2: Byte;
  var
    H: Byte;
  begin
    Op2 := Next;
    if Z80NMnemonics then
    begin
      Result := '';
      case Op2 of
        $23: Result := 'SWAPNIB';
        $24: Result := 'MIRROR A';
        $27: Result := 'TEST ' + Imm8;
        $28: Result := 'BSLA DE,B';
        $29: Result := 'BSRA DE,B';
        $2A: Result := 'BSRL DE,B';
        $2B: Result := 'BSRF DE,B';
        $2C: Result := 'BRLC DE,B';
        $30: Result := 'MUL D,E';
        $31: Result := 'ADD HL,A';
        $32: Result := 'ADD DE,A';
        $33: Result := 'ADD BC,A';
        $34: Result := 'ADD HL,' + Imm16;
        $35: Result := 'ADD DE,' + Imm16;
        $36: Result := 'ADD BC,' + Imm16;
        $8A:
          begin
            // Big-endian
            H := Next;
            Operand := (H shl 8) or Next;
            Result := 'PUSH ' + Hex4(Operand);
          end;
        $90: Result := 'OUTINB';
        $91:
          begin
            Result := 'NEXTREG ' + Imm8;
            Result := Result + ',' + Imm8;
          end;
        $92: Result := 'NEXTREG ' + Imm8 + ',A';
        $93: Result := 'PIXELDN';
        $94: Result := 'PIXELAD';
        $95: Result := 'SETAE';
        $98: Result := 'JP (C)';
        $A4: Result := 'LDIX';
        $A5: Result := 'LDWS';
        $AC: Result := 'LDDX';
        $B4: Result := 'LDIRX';
        $B7: Result := 'LDPIRX';
        $BC: Result := 'LDDRX';
      end;
      if Result <> '' then Exit;
    end;
    X := Op2 shr 6;
    Y := (Op2 shr 3) and 7;
    Z := Op2 and 7;
    P := Y shr 1;
    Q := Y and 1;
    Result := 'NOP*';
    if X = 1 then
      case Z of
        0: if Y = 6 then Result := 'IN F,(C)' else Result := 'IN ' + R8[Y] + ',(C)';
        1: if Y = 6 then Result := 'OUT (C),0' else Result := 'OUT (C),' + R8[Y];
        2: if Q = 0 then Result := 'SBC HL,' + RP[P] else Result := 'ADC HL,' + RP[P];
        3: if Q = 0 then Result := 'LD (' + Imm16 + '),' + RP[P]
           else Result := 'LD ' + RP[P] + ',(' + Imm16 + ')';
        4: Result := 'NEG';
        5: if Y = 1 then Result := 'RETI' else Result := 'RETN';
        6: Result := 'IM ' + IMODE[Y];
        7: case Y of
             0: Result := 'LD I,A';
             1: Result := 'LD R,A';
             2: Result := 'LD A,I';
             3: Result := 'LD A,R';
             4: Result := 'RRD';
             5: Result := 'RLD';
           end;
      end
    else if (X = 2) and (Z <= 3) and (Y >= 4) then
      Result := BLOCK[Y - 4, Z];
  end;

  function Classify(const Text: string): string;
  begin
    Result := Text;
    if Operand < 0 then
      Kind := okNone
    else if Pos('(' + Hex4(Operand) + ')', Text) > 0 then
      Kind := okMemory
    else if (Copy(Text, 1, 2) = 'JP') or (Copy(Text, 1, 2) = 'JR') or
            (Copy(Text, 1, 4) = 'CALL') or (Copy(Text, 1, 4) = 'DJNZ') then
      Kind := okJump
    else
      Kind := okImmediate;
  end;

begin
  Len := 0;
  Operand := -1;
  Kind := okNone;
  Index := '';
  HasDisp := False;
  Disp := 0;
  Op := Next;
  if Op in [$DD, $FD] then
  begin
    if Op = $DD then Index := 'IX' else Index := 'IY';
    Op := Peek(Word(Addr + Len));
    if Op in [$DD, $ED, $FD] then
      Exit('NOP*');   // prefix with no effect
    Inc(Len);
  end;
  if Op = $ED then Exit(Classify(DecodeED));
  if Op = $CB then Exit(DecodeCB);

  X := Op shr 6;
  Y := (Op shr 3) and 7;
  Z := Op and 7;
  P := Y shr 1;
  Q := Y and 1;
  case X of
    0:
      case Z of
        0: case Y of
             0: Result := 'NOP';
             1: Result := 'EX AF,AF''';
             2: Result := 'DJNZ ' + Relative;
             3: Result := 'JR ' + Relative;
           else
             Result := 'JR ' + CC[Y - 4] + ',' + Relative;
           end;
        1: if Q = 0 then Result := 'LD ' + RegPair(P) + ',' + Imm16
           else Result := 'ADD ' + RegPair(2) + ',' + RegPair(P);
        2: case Y of
             0: Result := 'LD (BC),A';
             1: Result := 'LD A,(BC)';
             2: Result := 'LD (DE),A';
             3: Result := 'LD A,(DE)';
             4: Result := 'LD (' + Imm16 + '),' + RegPair(2);
             5: Result := 'LD ' + RegPair(2) + ',(' + Imm16 + ')';
             6: Result := 'LD (' + Imm16 + '),A';
           else
             Result := 'LD A,(' + Imm16 + ')';
           end;
        3: if Q = 0 then Result := 'INC ' + RegPair(P) else Result := 'DEC ' + RegPair(P);
        4: Result := 'INC ' + Reg(Y, False);
        5: Result := 'DEC ' + Reg(Y, False);
        6: begin
             Result := 'LD ' + Reg(Y, False) + ',';   // (IX+d) displacement before n
             Result := Result + Imm8;
           end;
      else
        case Y of
          0: Result := 'RLCA';
          1: Result := 'RRCA';
          2: Result := 'RLA';
          3: Result := 'RRA';
          4: Result := 'DAA';
          5: Result := 'CPL';
          6: Result := 'SCF';
        else
          Result := 'CCF';
        end;
      end;
    1:
      if (Y = 6) and (Z = 6) then
        Result := 'HALT'
      else
        Result := 'LD ' + Reg(Y, Z = 6) + ',' + Reg(Z, Y = 6);
    2:
      Result := ALU[Y] + Reg(Z, False);
  else
    case Z of
      0: Result := 'RET ' + CC[Y];
      1: if Q = 0 then Result := 'POP ' + RegPair2(P)
         else case P of
           0: Result := 'RET';
           1: Result := 'EXX';
           2: Result := 'JP (' + RegPair(2) + ')';
         else
           Result := 'LD SP,' + RegPair(2);
         end;
      2: Result := 'JP ' + CC[Y] + ',' + Imm16;
      3: case Y of
           0: Result := 'JP ' + Imm16;
           2: Result := 'OUT (' + Imm8 + '),A';
           3: Result := 'IN A,(' + Imm8 + ')';
           4: Result := 'EX (SP),' + RegPair(2);
           5: Result := 'EX DE,HL';
           6: Result := 'DI';
           7: Result := 'EI';
         else
           Result := '';   // CB handled above
         end;
      4: Result := 'CALL ' + CC[Y] + ',' + Imm16;
      5: if Q = 0 then Result := 'PUSH ' + RegPair2(P)
         else Result := 'CALL ' + Imm16;   // P=0; prefixes handled above
      6: Result := ALU[Y] + Imm8;
    else
      Result := 'RST ' + Hex2(Y * 8);
    end;
  end;
  Result := Classify(Result);
end;

function ConditionAt(Addr: Word; Peek: TPeekFunc; F, B: Byte): TCondition;
const
  FlagMask: array[0..3] of Byte = ($40, $01, $04, $80);   // Z, C, P/V, S
var
  Op, Y: Byte;
  Holds: Boolean;
begin
  Result := cdNone;
  Op := Peek(Addr);
  Y := (Op shr 3) and 7;
  if Op = $10 then
    Holds := Byte(B - 1) <> 0                       // DJNZ
  else if (Op and $E7) = $20 then
    Holds := ((F and FlagMask[(Y - 4) shr 1]) <> 0) = Odd(Y - 4)   // JR cc
  else if ((Op and $C7) = $C0) or ((Op and $C7) = $C2) or ((Op and $C7) = $C4) then
    Holds := ((F and FlagMask[Y shr 1]) <> 0) = Odd(Y)             // RET/JP/CALL cc
  else
    Exit;
  if Holds then Result := cdTaken else Result := cdNotTaken;
end;

function IsZ80N(Addr: Word; Peek: TPeekFunc): Boolean;
begin
  Result := Z80NMnemonics and (Peek(Addr) = $ED) and
    (Peek(Word(Addr + 1)) in [$23, $24, $27..$2C, $30..$36, $8A, $90..$95, $98, $A4, $A5, $AC, $B4,
    $B7, $BC]);
end;

function IsStepOver(Addr: Word; Peek: TPeekFunc): Boolean;
var
  Op, Op2: Byte;
begin
  Op := Peek(Addr);
  case Op of
    $CD, $C4, $CC, $D4, $DC, $E4, $EC, $F4, $FC,   // CALL
    $C7, $CF, $D7, $DF, $E7, $EF, $F7, $FF,        // RST
    $10, $76:                                      // DJNZ, HALT
      Result := True;
    $ED:
      begin
        Op2 := Peek(Word(Addr + 1));
        Result := (Op2 in [$B0..$B3, $B8..$BB]) or     // repeating block instructions
          (Z80NMnemonics and (Op2 in [$B4, $B7, $BC]));
      end;
  else
    Result := False;
  end;
end;

end.

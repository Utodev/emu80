{ Cpu6510: the MOS 6510 (a 6502 with an I/O port, which the machine provides as memory
  addresses 0 and 1), cycle by cycle: every cycle of an instruction is a Read or a Write
  on the bus, in the order the real chip does them (the dummy reads and the double write of
  the read-modify-write instructions too), so the machine can run the video chip, the CIAs
  and the disk drive's CPU in step, and steal cycles from the CPU as the VIC-II does.
  Undocumented opcodes are emulated (the stable ones; the unstable are given the values
  commonly used). The same core runs the 1541's 6502. }
unit Cpu6510;

{$mode objfpc}{$H+}
{$R-}{$Q-}

interface

uses
  Classes;

const
  P_C = $01;
  P_Z = $02;
  P_I = $04;
  P_D = $08;
  P_B = $10;
  P_U = $20;
  P_V = $40;
  P_N = $80;

type
  { Memory as the CPU sees it: one call is one cycle of the CPU's clock }
  T6502Bus = class
  public
    function Read(Addr: Word): Byte; virtual; abstract;
    procedure Write(Addr: Word; Value: Byte); virtual; abstract;
  end;

  { A read without side effects (for looking ahead) }
  TCpuPeek = function(Addr: Word): Byte of object;

  TAddrMode = (amImp, amAcc, amImm, amZp, amZpx, amZpy, amAbs, amAbx, amAby, amInd, amIzx, amIzy, amRel);

  T6502Regs = record
    A, X, Y, SP, P: Byte;
    PC: Word;
  end;

  T6510 = class
  private
    FBus: T6502Bus;
    procedure Push(V: Byte); inline;
    function Pull: Byte; inline;
    procedure SetNZ(V: Byte); inline;
    procedure DoAdc(V: Byte);
    procedure DoSbc(V: Byte);
    procedure DoCompare(Reg, V: Byte);
    function DoAsl(V: Byte): Byte;
    function DoLsr(V: Byte): Byte;
    function DoRol(V: Byte): Byte;
    function DoRor(V: Byte): Byte;
    procedure Interrupt(Vector: Word; Brk: Boolean);
  public
    A, X, Y, SP: Byte;
    PC: Word;
    P: Byte;                 // bit 5 always 1, B (bit 4) only on the stack
    IRQ: Boolean;            // the IRQ line (a level: held low while something asks)
    NMIEdge: Boolean;        // an NMI edge has been seen (the machine sets it; cleared when taken)
    Jammed: Boolean;         // a KIL opcode: stopped until reset
    Cycles: Int64;           // cycles run since the last Reset
    LastOp: Byte;            // opcode of the last instruction
    InstrPC: Word;           // its address
    constructor Create(ABus: T6502Bus);
    procedure Reset;         // (reads the reset vector)
    { The whole state, for the debugger's step back: written to S (Save) or read back from it. The fields it copies as
      blocks (see StateIO) are plain values: no strings or dynamic arrays may go in between them }
    procedure StateIO(S: TStream; Save: Boolean);
    { Run one instruction, or take an interrupt }
    procedure Step;
    { The cycles the next Step will take (an interrupt's 7, a page crossed, a branch taken), read through Peek; the
      1541 runs an instruction only once the computer's clock has reached its last cycle }
    function NextCycles(Peek: TCpuPeek): Integer;
    function GetRegs: T6502Regs;
    procedure SetRegs(const R: T6502Regs);
    property Bus: T6502Bus read FBus write FBus;
  end;

var
  { The opcode table: mnemonic and addressing mode (also used by the disassembler) }
  OpName: array[0..255] of string[3];
  OpMode: array[0..255] of TAddrMode;
  OpIllegal: array[0..255] of Boolean;

function OpLength(Op: Byte): Integer;

{ For the chips' StateIO: Size bytes from Buf written to S (Save) or read from it into Buf }
procedure StateBlock(S: TStream; Save: Boolean; var Buf; Size: Integer);

implementation

uses
  SysUtils;

const
  TABLE =
    'BRK imp ORA izx KIL imp SLO izx NOP zp ORA zp ASL zp SLO zp PHP imp ORA imm ASL acc ANC imm NOP abs ORA abs ASL abs SLO abs ' +
    'BPL rel ORA izy KIL imp SLO izy NOP zpx ORA zpx ASL zpx SLO zpx CLC imp ORA aby NOP imp SLO aby NOP abx ORA abx ASL abx SLO abx ' +
    'JSR abs AND izx KIL imp RLA izx BIT zp AND zp ROL zp RLA zp PLP imp AND imm ROL acc ANC imm BIT abs AND abs ROL abs RLA abs ' +
    'BMI rel AND izy KIL imp RLA izy NOP zpx AND zpx ROL zpx RLA zpx SEC imp AND aby NOP imp RLA aby NOP abx AND abx ROL abx RLA abx ' +
    'RTI imp EOR izx KIL imp SRE izx NOP zp EOR zp LSR zp SRE zp PHA imp EOR imm LSR acc ALR imm JMP abs EOR abs LSR abs SRE abs ' +
    'BVC rel EOR izy KIL imp SRE izy NOP zpx EOR zpx LSR zpx SRE zpx CLI imp EOR aby NOP imp SRE aby NOP abx EOR abx LSR abx SRE abx ' +
    'RTS imp ADC izx KIL imp RRA izx NOP zp ADC zp ROR zp RRA zp PLA imp ADC imm ROR acc ARR imm JMP ind ADC abs ROR abs RRA abs ' +
    'BVS rel ADC izy KIL imp RRA izy NOP zpx ADC zpx ROR zpx RRA zpx SEI imp ADC aby NOP imp RRA aby NOP abx ADC abx ROR abx RRA abx ' +
    'NOP imm STA izx NOP imm SAX izx STY zp STA zp STX zp SAX zp DEY imp NOP imm TXA imp ANE imm STY abs STA abs STX abs SAX abs ' +
    'BCC rel STA izy KIL imp SHA izy STY zpx STA zpx STX zpy SAX zpy TYA imp STA aby TXS imp TAS aby SHY abx STA abx SHX aby SHA aby ' +
    'LDY imm LDA izx LDX imm LAX izx LDY zp LDA zp LDX zp LAX zp TAY imp LDA imm TAX imp LXA imm LDY abs LDA abs LDX abs LAX abs ' +
    'BCS rel LDA izy KIL imp LAX izy LDY zpx LDA zpx LDX zpy LAX zpy CLV imp LDA aby TSX imp LAS aby LDY abx LDA abx LDX aby LAX aby ' +
    'CPY imm CMP izx NOP imm DCP izx CPY zp CMP zp DEC zp DCP zp INY imp CMP imm DEX imp AXS imm CPY abs CMP abs DEC abs DCP abs ' +
    'BNE rel CMP izy KIL imp DCP izy NOP zpx CMP zpx DEC zpx DCP zpx CLD imp CMP aby NOP imp DCP aby NOP abx CMP abx DEC abx DCP abx ' +
    'CPX imm SBC izx NOP imm ISC izx CPX zp SBC zp INC zp ISC zp INX imp SBC imm NOP imp SBC imm CPX abs SBC abs INC abs ISC abs ' +
    'BEQ rel SBC izy KIL imp ISC izy NOP zpx SBC zpx INC zpx ISC zpx SED imp SBC aby NOP imp ISC aby NOP abx SBC abx INC abx ISC abx';

  { Mnemonic numbers for the fast dispatch }
  K_BRK = 0; K_ORA = 1; K_KIL = 2; K_SLO = 3; K_NOP = 4; K_ASL = 5; K_PHP = 6; K_ANC = 7; K_BPL = 8; K_CLC = 9;
  K_JSR = 10; K_AND = 11; K_RLA = 12; K_BIT = 13; K_ROL = 14; K_PLP = 15; K_BMI = 16; K_SEC = 17; K_RTI = 18;
  K_EOR = 19; K_SRE = 20; K_LSR = 21; K_PHA = 22; K_ALR = 23; K_JMP = 24; K_BVC = 25; K_CLI = 26; K_RTS = 27;
  K_ADC = 28; K_RRA = 29; K_ROR = 30; K_PLA = 31; K_ARR = 32; K_BVS = 33; K_SEI = 34; K_STA = 35; K_SAX = 36;
  K_STY = 37; K_STX = 38; K_DEY = 39; K_TXA = 40; K_ANE = 41; K_BCC = 42; K_SHA = 43; K_TYA = 44; K_TXS = 45;
  K_TAS = 46; K_SHY = 47; K_SHX = 48; K_LDY = 49; K_LDA = 50; K_LDX = 51; K_LAX = 52; K_TAY = 53; K_TAX = 54;
  K_LXA = 55; K_BCS = 56; K_CLV = 57; K_TSX = 58; K_LAS = 59; K_CPY = 60; K_CMP = 61; K_DCP = 62; K_DEC = 63;
  K_INY = 64; K_DEX = 65; K_AXS = 66; K_BNE = 67; K_CLD = 68; K_CPX = 69; K_SBC = 70; K_ISC = 71; K_INC = 72;
  K_INX = 73; K_BEQ = 74; K_SED = 75;

  KIND_NAMES = 'BRK ORA KIL SLO NOP ASL PHP ANC BPL CLC JSR AND RLA BIT ROL PLP BMI SEC RTI EOR SRE LSR PHA ALR JMP BVC CLI RTS ' +
    'ADC RRA ROR PLA ARR BVS SEI STA SAX STY STX DEY TXA ANE BCC SHA TYA TXS TAS SHY SHX LDY LDA LDX LAX TAY TAX LXA BCS ' +
    'CLV TSX LAS CPY CMP DCP DEC INY DEX AXS BNE CLD CPX SBC ISC INC INX BEQ SED';

var
  OpKind: array[0..255] of Byte;
  OpWrites: array[0..255] of Boolean;   // the store instructions: indexed modes always take the extra cycle

function OpLength(Op: Byte): Integer;
begin
  case OpMode[Op] of
    amImp, amAcc: Result := 1;
    amImm, amZp, amZpx, amZpy, amIzx, amIzy, amRel: Result := 2;
  else
    Result := 3;
  end;
end;

procedure BuildTables;
var
  I, K, P: Integer;
  Items, Kinds: TStringArray;
  S, M: string;

  function Split(const Text: string): TStringArray;
  var
    Q, Start: Integer;
  begin
    SetLength(Result, 0);
    Start := 1;
    for Q := 1 to Length(Text) + 1 do
      if (Q > Length(Text)) or (Text[Q] = ' ') then
      begin
        if Q > Start then
        begin
          SetLength(Result, Length(Result) + 1);
          Result[High(Result)] := Copy(Text, Start, Q - Start);
        end;
        Start := Q + 1;
      end;
  end;

begin
  Items := Split(TABLE);
  Kinds := Split(KIND_NAMES);
  for I := 0 to 255 do
  begin
    S := Items[I * 2];
    M := Items[I * 2 + 1];
    OpName[I] := S;
    if M = 'imp' then OpMode[I] := amImp
    else if M = 'acc' then OpMode[I] := amAcc
    else if M = 'imm' then OpMode[I] := amImm
    else if M = 'zp' then OpMode[I] := amZp
    else if M = 'zpx' then OpMode[I] := amZpx
    else if M = 'zpy' then OpMode[I] := amZpy
    else if M = 'abs' then OpMode[I] := amAbs
    else if M = 'abx' then OpMode[I] := amAbx
    else if M = 'aby' then OpMode[I] := amAby
    else if M = 'ind' then OpMode[I] := amInd
    else if M = 'izx' then OpMode[I] := amIzx
    else if M = 'izy' then OpMode[I] := amIzy
    else OpMode[I] := amRel;
    OpKind[I] := 0;
    for K := 0 to High(Kinds) do
      if Kinds[K] = S then
      begin
        OpKind[I] := K;
        Break;
      end;
    P := OpKind[I];
    OpWrites[I] := P in [K_STA, K_STX, K_STY, K_SAX, K_SHA, K_SHX, K_SHY, K_TAS];
    OpIllegal[I] := P in [K_KIL, K_SLO, K_ANC, K_RLA, K_SRE, K_ALR, K_RRA, K_ARR, K_SAX, K_ANE, K_SHA, K_TAS, K_SHY,
      K_SHX, K_LAX, K_LXA, K_LAS, K_DCP, K_AXS, K_ISC];
    // The NOPs that are not $EA, and the second SBC
    if (P = K_NOP) and (I <> $EA) then OpIllegal[I] := True;
    if I = $EB then OpIllegal[I] := True;
    // The names shown: those of "No More Secrets" (NMOS 6510 Unintended Opcodes, groepaz, 2015); the table keeps the
    // older ones the dispatch is built on
    if S = 'KIL' then OpName[I] := 'JAM'
    else if S = 'AXS' then OpName[I] := 'SBX'
    else if S = 'LXA' then OpName[I] := 'LAX';
  end;
end;

{ T6510 }

constructor T6510.Create(ABus: T6502Bus);
begin
  inherited Create;
  FBus := ABus;
  P := P_U or P_I;
  SP := $FF;
end;

procedure T6510.Reset;
begin
  Jammed := False;
  IRQ := False;
  NMIEdge := False;
  P := P_U or P_I;
  SP := $FD;
  Cycles := 0;
  // Seven cycles: the last two read the reset vector
  FBus.Read(PC);
  FBus.Read(PC);
  FBus.Read($0100 or SP);
  FBus.Read($0100 or Byte(SP - 1));
  FBus.Read($0100 or Byte(SP - 2));
  PC := FBus.Read($FFFC) or (FBus.Read($FFFD) shl 8);
  Inc(Cycles, 7);
end;

function T6510.GetRegs: T6502Regs;
begin
  Result.A := A;
  Result.X := X;
  Result.Y := Y;
  Result.SP := SP;
  Result.P := P;
  Result.PC := PC;
end;

procedure T6510.SetRegs(const R: T6502Regs);
begin
  A := R.A;
  X := R.X;
  Y := R.Y;
  SP := R.SP;
  P := R.P or P_U;
  PC := R.PC;
end;

procedure T6510.Push(V: Byte);
begin
  FBus.Write($0100 or SP, V);
  Dec(SP);
end;

function T6510.Pull: Byte;
begin
  Inc(SP);
  Result := FBus.Read($0100 or SP);
end;

procedure T6510.SetNZ(V: Byte);
begin
  P := (P and not (P_N or P_Z)) or (V and P_N);
  if V = 0 then P := P or P_Z;
end;

procedure T6510.DoAdc(V: Byte);
var
  T, Al, Ah: Integer;
begin
  if (P and P_D) = 0 then
  begin
    T := A + V + (P and P_C);
    P := P and not (P_C or P_V);
    if ((not (A xor V)) and (A xor T) and $80) <> 0 then P := P or P_V;
    if T > $FF then P := P or P_C;
    A := T and $FF;
    SetNZ(A);
  end
  else
  begin
    T := A + V + (P and P_C);
    Al := (A and $0F) + (V and $0F) + (P and P_C);
    if Al > 9 then Inc(Al, 6);
    Ah := (A shr 4) + (V shr 4);
    if Al > $0F then Inc(Ah);
    P := P and not (P_C or P_V or P_N or P_Z);
    if (T and $FF) = 0 then P := P or P_Z;
    if (Ah and 8) <> 0 then P := P or P_N;
    if ((not (A xor V)) and (A xor (Ah shl 4)) and $80) <> 0 then P := P or P_V;
    if Ah > 9 then Inc(Ah, 6);
    if Ah > $0F then P := P or P_C;
    A := ((Ah shl 4) or (Al and $0F)) and $FF;
  end;
end;

procedure T6510.DoSbc(V: Byte);
var
  T, Tmp: Integer;
begin
  T := A - V - (1 - (P and P_C));
  if (P and P_D) = 0 then
  begin
    P := P and not (P_C or P_V);
    if ((A xor V) and (A xor T) and $80) <> 0 then P := P or P_V;
    if T >= 0 then P := P or P_C;
    A := T and $FF;
    SetNZ(A);
  end
  else
  begin
    // Flags as in binary mode, the result in BCD
    Tmp := (A and $0F) - (V and $0F) - (1 - (P and P_C));
    if (Tmp and $10) <> 0 then
      Tmp := ((Tmp - 6) and $0F) or ((A and $F0) - (V and $F0) - $10)
    else
      Tmp := (Tmp and $0F) or ((A and $F0) - (V and $F0));
    if (Tmp and $100) <> 0 then Dec(Tmp, $60);
    P := P and not (P_C or P_V);
    if ((A xor V) and (A xor T) and $80) <> 0 then P := P or P_V;
    if T >= 0 then P := P or P_C;
    SetNZ(T and $FF);
    A := Tmp and $FF;
  end;
end;

procedure T6510.DoCompare(Reg, V: Byte);
var
  T: Integer;
begin
  T := Reg - V;
  P := P and not P_C;
  if T >= 0 then P := P or P_C;
  SetNZ(T and $FF);
end;

function T6510.DoAsl(V: Byte): Byte;
begin
  P := (P and not P_C) or (V shr 7);
  Result := V shl 1;
  SetNZ(Result);
end;

function T6510.DoLsr(V: Byte): Byte;
begin
  P := (P and not P_C) or (V and 1);
  Result := V shr 1;
  SetNZ(Result);
end;

function T6510.DoRol(V: Byte): Byte;
begin
  Result := (V shl 1) or (P and P_C);
  P := (P and not P_C) or (V shr 7);
  SetNZ(Result);
end;

function T6510.DoRor(V: Byte): Byte;
begin
  Result := (V shr 1) or ((P and P_C) shl 7);
  P := (P and not P_C) or (V and 1);
  SetNZ(Result);
end;

procedure T6510.Interrupt(Vector: Word; Brk: Boolean);
begin
  // (BRK has already read its opcode and the byte after it)
  if not Brk then
  begin
    FBus.Read(PC);
    FBus.Read(PC);
  end;
  Push(PC shr 8);
  Push(PC and $FF);
  if Brk then Push(P or P_B or P_U) else Push((P or P_U) and not P_B);
  P := P or P_I;
  PC := FBus.Read(Vector) or (FBus.Read(Vector + 1) shl 8);
end;

const
  { The cycles of each opcode, without a page crossed or a branch taken (the stores and the read-modify-write
    instructions always take their indexed modes' extra cycle) }
  OP_CYCLES: array[0..255] of Byte = (
    7, 6, 2, 8, 3, 3, 5, 5, 3, 2, 2, 2, 4, 4, 6, 6,  2, 5, 2, 8, 4, 4, 6, 6, 2, 4, 2, 7, 4, 4, 7, 7,
    6, 6, 2, 8, 3, 3, 5, 5, 4, 2, 2, 2, 4, 4, 6, 6,  2, 5, 2, 8, 4, 4, 6, 6, 2, 4, 2, 7, 4, 4, 7, 7,
    6, 6, 2, 8, 3, 3, 5, 5, 3, 2, 2, 2, 3, 4, 6, 6,  2, 5, 2, 8, 4, 4, 6, 6, 2, 4, 2, 7, 4, 4, 7, 7,
    6, 6, 2, 8, 3, 3, 5, 5, 4, 2, 2, 2, 5, 4, 6, 6,  2, 5, 2, 8, 4, 4, 6, 6, 2, 4, 2, 7, 4, 4, 7, 7,
    2, 6, 2, 6, 3, 3, 3, 3, 2, 2, 2, 2, 4, 4, 4, 4,  2, 6, 2, 6, 4, 4, 4, 4, 2, 5, 2, 5, 5, 5, 5, 5,
    2, 6, 2, 6, 3, 3, 3, 3, 2, 2, 2, 2, 4, 4, 4, 4,  2, 5, 2, 5, 4, 4, 4, 4, 2, 4, 2, 4, 4, 4, 4, 4,
    2, 6, 2, 8, 3, 3, 5, 5, 2, 2, 2, 2, 4, 4, 6, 6,  2, 5, 2, 8, 4, 4, 6, 6, 2, 4, 2, 7, 4, 4, 7, 7,
    2, 6, 2, 8, 3, 3, 5, 5, 2, 2, 2, 2, 4, 4, 6, 6,  2, 5, 2, 8, 4, 4, 6, 6, 2, 4, 2, 7, 4, 4, 7, 7);

function T6510.NextCycles(Peek: TCpuPeek): Integer;
var
  Op: Byte;
  Base: Word;
  T: Byte;
  Taken: Boolean;
begin
  if Jammed then Exit(1);
  if NMIEdge or (IRQ and ((P and P_I) = 0)) then Exit(7);
  Op := Peek(PC);
  Result := OP_CYCLES[Op];
  case OpMode[Op] of
    amAbx, amAby:
      // (a page crossed costs a cycle only to the instructions that just read)
      if Result = 4 then
      begin
        Base := Peek(Word(PC + 1)) or (Peek(Word(PC + 2)) shl 8);
        if OpMode[Op] = amAbx then T := X else T := Y;
        if ((Base + T) xor Base) and $FF00 <> 0 then Inc(Result);
      end;
    amIzy:
      if Result = 5 then
      begin
        T := Peek(Word(PC + 1));
        Base := Peek(T) or (Peek(Byte(T + 1)) shl 8);
        if ((Base + Y) xor Base) and $FF00 <> 0 then Inc(Result);
      end;
    amRel:
      begin
        case Op of
          $10: Taken := (P and P_N) = 0;
          $30: Taken := (P and P_N) <> 0;
          $50: Taken := (P and P_V) = 0;
          $70: Taken := (P and P_V) <> 0;
          $90: Taken := (P and P_C) = 0;
          $B0: Taken := (P and P_C) <> 0;
          $D0: Taken := (P and P_Z) = 0;
        else
          Taken := (P and P_Z) <> 0;
        end;
        if Taken then
        begin
          Inc(Result);
          Base := Word(PC + 2);
          if (Word(Base + ShortInt(Peek(Word(PC + 1)))) xor Base) and $FF00 <> 0 then Inc(Result);
        end;
      end;
  end;
end;

procedure T6510.Step;
var
  Op, Kind, Lo, Hi, T: Byte;
  Mode: TAddrMode;
  EA, Base: Word;
  V, R: Byte;
  Crossed: Boolean;
  Rel: ShortInt;
  Tmp: Integer;

  procedure Branch(Cond: Boolean);
  var
    NewPC: Word;
  begin
    Rel := ShortInt(FBus.Read(PC));
    Inc(PC);
    if Cond then
    begin
      FBus.Read(PC);
      NewPC := Word(PC + Rel);
      if (NewPC xor PC) and $FF00 <> 0 then
        FBus.Read((PC and $FF00) or (NewPC and $FF));
      PC := NewPC;
    end;
  end;

begin
  if Jammed then
  begin
    FBus.Read(PC);
    Exit;
  end;
  // Interrupts are taken between instructions: an NMI edge, or the IRQ line while I is clear
  if NMIEdge then
  begin
    NMIEdge := False;
    Interrupt($FFFA, False);
    Exit;
  end;
  if IRQ and ((P and P_I) = 0) then
  begin
    Interrupt($FFFE, False);
    Exit;
  end;
  InstrPC := PC;
  Op := FBus.Read(PC);
  Inc(PC);
  LastOp := Op;
  Kind := OpKind[Op];
  Mode := OpMode[Op];
  EA := 0;
  Crossed := False;

  { The effective address, with the cycles of the mode }
  case Mode of
    amImm:
      begin
        EA := PC;
        Inc(PC);
      end;
    amZp:
      begin
        EA := FBus.Read(PC);
        Inc(PC);
      end;
    amZpx:
      begin
        Lo := FBus.Read(PC);
        Inc(PC);
        FBus.Read(Lo);
        EA := Byte(Lo + X);
      end;
    amZpy:
      begin
        Lo := FBus.Read(PC);
        Inc(PC);
        FBus.Read(Lo);
        EA := Byte(Lo + Y);
      end;
    amAbs:
      begin
        Lo := FBus.Read(PC);
        Hi := FBus.Read(PC + 1);
        Inc(PC, 2);
        EA := Lo or (Hi shl 8);
      end;
    amAbx, amAby:
      begin
        Lo := FBus.Read(PC);
        Hi := FBus.Read(PC + 1);
        Inc(PC, 2);
        Base := Lo or (Hi shl 8);
        if Mode = amAbx then T := X else T := Y;
        EA := Word(Base + T);
        Crossed := (EA xor Base) and $FF00 <> 0;
        // The cycle that reads before the carry is added: needed on a page crossing, and always by stores and
        // read-modify-write instructions
        if Crossed or OpWrites[Op] or (Kind in [K_ASL, K_LSR, K_ROL, K_ROR, K_INC, K_DEC, K_SLO, K_SRE, K_RLA,
          K_RRA, K_DCP, K_ISC]) then
          FBus.Read((Base and $FF00) or (EA and $FF));
      end;
    amInd:
      begin
        Lo := FBus.Read(PC);
        Hi := FBus.Read(PC + 1);
        Inc(PC, 2);
        Base := Lo or (Hi shl 8);
        // (the 6502 does not carry into the high byte of the pointer)
        EA := FBus.Read(Base) or (FBus.Read((Base and $FF00) or Byte(Base + 1)) shl 8);
      end;
    amIzx:
      begin
        Lo := FBus.Read(PC);
        Inc(PC);
        FBus.Read(Lo);
        T := Byte(Lo + X);
        EA := FBus.Read(T) or (FBus.Read(Byte(T + 1)) shl 8);
      end;
    amIzy:
      begin
        Lo := FBus.Read(PC);
        Inc(PC);
        Base := FBus.Read(Lo) or (FBus.Read(Byte(Lo + 1)) shl 8);
        EA := Word(Base + Y);
        Crossed := (EA xor Base) and $FF00 <> 0;
        if Crossed or OpWrites[Op] or (Kind in [K_SLO, K_SRE, K_RLA, K_RRA, K_DCP, K_ISC]) then
          FBus.Read((Base and $FF00) or (EA and $FF));
      end;
    amImp, amAcc:
      FBus.Read(PC);   // the cycle that reads the next opcode and drops it
    amRel: ;
  end;

  case Kind of
    K_LDA: begin A := FBus.Read(EA); SetNZ(A); end;
    K_LDX: begin X := FBus.Read(EA); SetNZ(X); end;
    K_LDY: begin Y := FBus.Read(EA); SetNZ(Y); end;
    K_LAX: begin A := FBus.Read(EA); X := A; SetNZ(A); end;
    K_STA: FBus.Write(EA, A);
    K_STX: FBus.Write(EA, X);
    K_STY: FBus.Write(EA, Y);
    K_SAX: FBus.Write(EA, A and X);
    K_ADC: DoAdc(FBus.Read(EA));
    K_SBC: DoSbc(FBus.Read(EA));
    K_AND: begin A := A and FBus.Read(EA); SetNZ(A); end;
    K_ORA: begin A := A or FBus.Read(EA); SetNZ(A); end;
    K_EOR: begin A := A xor FBus.Read(EA); SetNZ(A); end;
    K_CMP: DoCompare(A, FBus.Read(EA));
    K_CPX: DoCompare(X, FBus.Read(EA));
    K_CPY: DoCompare(Y, FBus.Read(EA));
    K_BIT:
      begin
        V := FBus.Read(EA);
        P := (P and not (P_N or P_V or P_Z)) or (V and (P_N or P_V));
        if (A and V) = 0 then P := P or P_Z;
      end;
    K_ASL, K_LSR, K_ROL, K_ROR:
      if Mode = amAcc then
      begin
        case Kind of
          K_ASL: A := DoAsl(A);
          K_LSR: A := DoLsr(A);
          K_ROL: A := DoRol(A);
        else
          A := DoRor(A);
        end;
      end
      else
      begin
        V := FBus.Read(EA);
        FBus.Write(EA, V);
        case Kind of
          K_ASL: V := DoAsl(V);
          K_LSR: V := DoLsr(V);
          K_ROL: V := DoRol(V);
        else
          V := DoRor(V);
        end;
        FBus.Write(EA, V);
      end;
    K_INC, K_DEC:
      begin
        V := FBus.Read(EA);
        FBus.Write(EA, V);
        if Kind = K_INC then Inc(V) else Dec(V);
        SetNZ(V);
        FBus.Write(EA, V);
      end;
    K_INX: begin Inc(X); SetNZ(X); end;
    K_INY: begin Inc(Y); SetNZ(Y); end;
    K_DEX: begin Dec(X); SetNZ(X); end;
    K_DEY: begin Dec(Y); SetNZ(Y); end;
    K_TAX: begin X := A; SetNZ(X); end;
    K_TAY: begin Y := A; SetNZ(Y); end;
    K_TXA: begin A := X; SetNZ(A); end;
    K_TYA: begin A := Y; SetNZ(A); end;
    K_TSX: begin X := SP; SetNZ(X); end;
    K_TXS: SP := X;
    K_PHA: Push(A);
    K_PHP: Push(P or P_B or P_U);
    K_PLA:
      begin
        FBus.Read($0100 or SP);
        A := Pull;
        SetNZ(A);
      end;
    K_PLP:
      begin
        FBus.Read($0100 or SP);
        P := (Pull and not P_B) or P_U;
      end;
    K_CLC: P := P and not P_C;
    K_SEC: P := P or P_C;
    K_CLI: P := P and not P_I;
    K_SEI: P := P or P_I;
    K_CLV: P := P and not P_V;
    K_CLD: P := P and not P_D;
    K_SED: P := P or P_D;
    K_NOP:
      if Mode in [amImm, amZp, amZpx, amAbs, amAbx] then FBus.Read(EA);
    K_JMP: PC := EA;
    K_JSR:
      begin
        FBus.Read($0100 or SP);
        Dec(PC);
        Push(PC shr 8);
        Push(PC and $FF);
        PC := EA;
      end;
    K_RTS:
      begin
        FBus.Read($0100 or SP);
        Lo := Pull;
        Hi := Pull;
        PC := Lo or (Hi shl 8);
        FBus.Read(PC);
        Inc(PC);
      end;
    K_RTI:
      begin
        FBus.Read($0100 or SP);
        P := (Pull and not P_B) or P_U;
        Lo := Pull;
        Hi := Pull;
        PC := Lo or (Hi shl 8);
      end;
    K_BRK:
      begin
        Inc(PC);
        Interrupt($FFFE, True);
      end;
    K_BPL: Branch((P and P_N) = 0);
    K_BMI: Branch((P and P_N) <> 0);
    K_BVC: Branch((P and P_V) = 0);
    K_BVS: Branch((P and P_V) <> 0);
    K_BCC: Branch((P and P_C) = 0);
    K_BCS: Branch((P and P_C) <> 0);
    K_BNE: Branch((P and P_Z) = 0);
    K_BEQ: Branch((P and P_Z) <> 0);

    { Undocumented }
    K_KIL: Jammed := True;
    K_SLO:
      begin
        V := FBus.Read(EA);
        FBus.Write(EA, V);
        V := DoAsl(V);
        FBus.Write(EA, V);
        A := A or V;
        SetNZ(A);
      end;
    K_RLA:
      begin
        V := FBus.Read(EA);
        FBus.Write(EA, V);
        V := DoRol(V);
        FBus.Write(EA, V);
        A := A and V;
        SetNZ(A);
      end;
    K_SRE:
      begin
        V := FBus.Read(EA);
        FBus.Write(EA, V);
        V := DoLsr(V);
        FBus.Write(EA, V);
        A := A xor V;
        SetNZ(A);
      end;
    K_RRA:
      begin
        V := FBus.Read(EA);
        FBus.Write(EA, V);
        V := DoRor(V);
        FBus.Write(EA, V);
        DoAdc(V);
      end;
    K_DCP:
      begin
        V := FBus.Read(EA);
        FBus.Write(EA, V);
        Dec(V);
        FBus.Write(EA, V);
        DoCompare(A, V);
      end;
    K_ISC:
      begin
        V := FBus.Read(EA);
        FBus.Write(EA, V);
        Inc(V);
        FBus.Write(EA, V);
        DoSbc(V);
      end;
    K_ANC:
      begin
        A := A and FBus.Read(EA);
        SetNZ(A);
        P := (P and not P_C) or (A shr 7);
      end;
    K_ALR:
      begin
        A := A and FBus.Read(EA);
        A := DoLsr(A);
      end;
    K_ARR:
      begin
        V := A and FBus.Read(EA);
        A := (V shr 1) or ((P and P_C) shl 7);
        SetNZ(A);
        P := P and not (P_C or P_V);
        if (A and $40) <> 0 then P := P or P_C;
        if (((A shr 6) xor (A shr 5)) and 1) <> 0 then P := P or P_V;
      end;
    K_AXS:
      begin
        V := FBus.Read(EA);
        Tmp := (A and X) - V;
        P := P and not P_C;
        if Tmp >= 0 then P := P or P_C;
        X := Tmp and $FF;
        SetNZ(X);
      end;
    K_ANE:
      begin
        A := (A or $EE) and X and FBus.Read(EA);
        SetNZ(A);
      end;
    K_LXA:
      begin
        A := (A or $EE) and FBus.Read(EA);
        X := A;
        SetNZ(A);
      end;
    K_LAS:
      begin
        A := FBus.Read(EA) and SP;
        X := A;
        SP := A;
        SetNZ(A);
      end;
    K_SHA, K_SHX, K_SHY, K_TAS:
      begin
        case Kind of
          K_SHA: R := A and X;
          K_SHX: R := X;
          K_SHY: R := Y;
        else
          begin
            SP := A and X;
            R := SP;
          end;
        end;
        // The value is ANDed with the high byte of the base address + 1; on a page crossing that byte
        // becomes the address's high byte
        V := R and Byte((Base shr 8) + 1);
        if (EA xor Base) and $FF00 <> 0 then EA := (EA and $FF) or (Word(V) shl 8);
        FBus.Write(EA, V);
      end;
  end;
end;

procedure StateBlock(S: TStream; Save: Boolean; var Buf; Size: Integer);
begin
  if Save then S.WriteBuffer(Buf, Size) else S.ReadBuffer(Buf, Size);
end;

procedure T6510.StateIO(S: TStream; Save: Boolean);
begin
  // The registers and the lines, A to InstrPC
  StateBlock(S, Save, A, PtrUInt(@InstrPC) + SizeOf(InstrPC) - PtrUInt(@A));
end;

initialization
  BuildTables;

end.

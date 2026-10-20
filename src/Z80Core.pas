{ Z80Core: T-state accurate Z80 CPU emulation.

  Every memory and I/O access goes through a TZ80Bus, which applies the
  machine's contention and advances the T-state counter, so timing is exact
  at M-cycle level. The access pattern of each instruction follows the
  well-documented FUSE core so it can be verified with the FUSE test suite. }
unit Z80Core;

{$mode objfpc}{$H+}
{$R-}{$Q-}

interface

const
  FLAG_C = $01;
  FLAG_N = $02;
  FLAG_P = $04;
  FLAG_V = FLAG_P;
  FLAG_3 = $08;
  FLAG_H = $10;
  FLAG_5 = $20;
  FLAG_Z = $40;
  FLAG_S = $80;

type
  TRegPair = packed record
    case Integer of
      0: (W: Word);
      1: (L, H: Byte);
  end;
  PRegPair = ^TRegPair;

  { Programmer-visible register set (for debuggers) }
  TZ80Regs = record
    A, F, A_, F_, I, R, IM: Byte;
    BC, DE, HL, BC_, DE_, HL_, IX, IY, SP, PC: Word;
    IFF1, IFF2: Boolean;
  end;

  { Memory and I/O as seen by the CPU. T is the CPU's T-state counter. }
  TZ80Bus = class
  public
    { Contention for an MREQ cycle at Addr, then advance T by Time. }
    procedure Contend(Addr: Word; Time: Integer; var T: Integer); virtual;
    { Contention for a cycle where the address is on the bus without MREQ. }
    procedure ContendNoMreq(Addr: Word; Time: Integer; var T: Integer); virtual;
    { Raw accesses; timing already accounted for by the CPU. }
    function ReadMem(Addr: Word; T: Integer): Byte; virtual; abstract;
    { Opcode fetch (M1). Same as ReadMem unless a bus wants to tell them apart. }
    function FetchMem(Addr: Word; T: Integer): Byte; virtual;
    procedure WriteMem(Addr: Word; Value: Byte; T: Integer); virtual; abstract;
    { Full I/O cycle (4 T-states plus contention). }
    function ReadPort(Port: Word; var T: Integer): Byte; virtual; abstract;
    procedure WritePort(Port: Word; Value: Byte; var T: Integer); virtual; abstract;
    { Z80N NEXTREG: write a Next register (no I/O cycle; nothing by default) }
    procedure WriteNextReg(Reg, Value: Byte; T: Integer); virtual;
    { RETN has just run (its PC popped): the Next's Multiface and DivMMC
      let go of the memory then }
    procedure Retn; virtual;
  end;

  TZ80 = class
  private
    FBus: TZ80Bus;
    FEIJust: Boolean;     // last instruction was EI: no interrupt accepted yet
    FIFF2Read: Boolean;   // last instruction was LD A,I or LD A,R
    function IR: Word; inline;
    function ReadByte(Addr: Word): Byte; inline;
    procedure WriteByte(Addr: Word; Value: Byte); inline;
    procedure NoMreq(Addr: Word; Count: Integer);
    function FetchOpcode: Byte;
    procedure Push(const RP: TRegPair);
    procedure Pop(var RP: TRegPair);
    function GetReg(Index: Integer): Byte;
    procedure SetReg(Index: Integer; Value: Byte);
    function GetRegX(Index: Integer; const XY: TRegPair): Byte;
    procedure SetRegX(Index: Integer; var XY: TRegPair; Value: Byte);
    function Condition(Index: Integer): Boolean;
    { Flag helpers }
    procedure Alu(Op: Integer; Value: Byte);
    procedure DoAdd(Value: Byte);
    procedure DoAdc(Value: Byte);
    procedure DoSub(Value: Byte);
    procedure DoSbc(Value: Byte);
    procedure DoCp(Value: Byte);
    function DoInc(Value: Byte): Byte;
    function DoDec(Value: Byte): Byte;
    function Rotate(Op: Integer; Value: Byte): Byte;
    procedure DoBit(Bit: Integer; Value, Bits35: Byte);
    procedure Add16(var Dest: TRegPair; Value: Word);
    procedure Adc16(Value: Word);
    procedure Sbc16(Value: Word);
    procedure Daa;
    procedure BlockRepeatFlags;
    procedure BlockIORepeatFlags(Value: Byte);
    { Instruction groups }
    procedure Jr;
    procedure ExecBase(Op: Byte);
    procedure ExecCB;
    procedure ExecED;
    function ExecZ80N(Op: Byte): Boolean;
    procedure ExecIndex(var XY: TRegPair);
    procedure ExecIndexCB(var XY: TRegPair);
    function ReadIndexAddr(const XY: TRegPair): Word;
  public
    A, F, A_, F_: Byte;
    BC, DE, HL, BC_, DE_, HL_, IX, IY, SP, PC, WZ: TRegPair;
    I, R, R7: Byte;
    IFF1, IFF2: Boolean;
    IM: Byte;
    Halted: Boolean;
    { The ZX Spectrum Next's Z80N: its extra ED instructions (otherwise they
      are NOPs, as on the Z80) }
    Z80N: Boolean;
    Q, LastQ: Byte;
    T: Integer;
    constructor Create(ABus: TZ80Bus);
    procedure Reset(Hard: Boolean);
    { Execute one instruction (or one HALT cycle). }
    procedure Step;
    { Accept a maskable interrupt if enabled. The caller is responsible for
      checking that /INT is still asserted. Returns True if accepted. }
    function Interrupt: Boolean;
    { Accept an NMI; Stackless (the Next's NR C0 bit 3): SP goes down but
      the return address isn't written to memory (the bus keeps it) }
    procedure NMI(Stackless: Boolean = False);
    function GetR: Byte;
    function GetRegs: TZ80Regs;
    function GetAF: Word;
    procedure SetAF(Value: Word);
    { Copy the whole CPU state (not the bus) from another CPU }
    procedure CopyStateFrom(Src: TZ80);
    property Bus: TZ80Bus read FBus write FBus;
    property EIJust: Boolean read FEIJust write FEIJust;
  end;

var
  SZ53Table, ParityTable, SZ53PTable: array[Byte] of Byte;

implementation

const
  HalfcarryAddTable: array[0..7] of Byte = (0, FLAG_H, FLAG_H, FLAG_H, 0, 0, 0, FLAG_H);
  HalfcarrySubTable: array[0..7] of Byte = (0, 0, FLAG_H, 0, FLAG_H, 0, FLAG_H, FLAG_H);
  OverflowAddTable: array[0..7] of Byte = (0, 0, 0, FLAG_V, FLAG_V, 0, 0, 0);
  OverflowSubTable: array[0..7] of Byte = (0, FLAG_V, 0, 0, 0, 0, FLAG_V, 0);

procedure InitTables;
var
  I, J, K: Integer;
  Parity: Byte;
begin
  for I := 0 to 255 do
  begin
    SZ53Table[I] := I and (FLAG_3 or FLAG_5 or FLAG_S);
    J := I;
    Parity := 0;
    for K := 0 to 7 do
    begin
      Parity := Parity xor (J and 1);
      J := J shr 1;
    end;
    if Parity <> 0 then ParityTable[I] := 0 else ParityTable[I] := FLAG_P;
    SZ53PTable[I] := SZ53Table[I] or ParityTable[I];
  end;
  SZ53Table[0] := SZ53Table[0] or FLAG_Z;
  SZ53PTable[0] := SZ53PTable[0] or FLAG_Z;
end;

{ TZ80Bus }

procedure TZ80Bus.Contend(Addr: Word; Time: Integer; var T: Integer);
begin
  Inc(T, Time);
end;

function TZ80Bus.FetchMem(Addr: Word; T: Integer): Byte;
begin
  Result := ReadMem(Addr, T);
end;

procedure TZ80Bus.ContendNoMreq(Addr: Word; Time: Integer; var T: Integer);
begin
  Inc(T, Time);
end;

procedure TZ80Bus.WriteNextReg(Reg, Value: Byte; T: Integer);
begin
end;

procedure TZ80Bus.Retn;
begin
end;

{ TZ80 }

constructor TZ80.Create(ABus: TZ80Bus);
begin
  inherited Create;
  FBus := ABus;
  Reset(True);
end;

procedure TZ80.Reset(Hard: Boolean);
begin
  A := $FF; F := $FF; A_ := $FF; F_ := $FF;
  I := 0; R := 0; R7 := 0;
  PC.W := 0;
  SP.W := $FFFF;
  IFF1 := False; IFF2 := False; IM := 0;
  Halted := False;
  FIFF2Read := False;
  FEIJust := False;
  Q := 0; LastQ := 0;
  if Hard then
  begin
    BC.W := 0; DE.W := 0; HL.W := 0;
    BC_.W := 0; DE_.W := 0; HL_.W := 0;
    IX.W := 0; IY.W := 0;
    WZ.W := 0;
  end;
end;

function TZ80.GetR: Byte;
begin
  Result := (R and $7F) or (R7 and $80);
end;

function TZ80.GetRegs: TZ80Regs;
begin
  Result.A := A; Result.F := F; Result.A_ := A_; Result.F_ := F_;
  Result.I := I; Result.R := GetR; Result.IM := IM;
  Result.BC := BC.W; Result.DE := DE.W; Result.HL := HL.W;
  Result.BC_ := BC_.W; Result.DE_ := DE_.W; Result.HL_ := HL_.W;
  Result.IX := IX.W; Result.IY := IY.W; Result.SP := SP.W; Result.PC := PC.W;
  Result.IFF1 := IFF1; Result.IFF2 := IFF2;
end;

function TZ80.GetAF: Word;
begin
  Result := (A shl 8) or F;
end;

procedure TZ80.CopyStateFrom(Src: TZ80);
begin
  A := Src.A; F := Src.F; A_ := Src.A_; F_ := Src.F_;
  BC := Src.BC; DE := Src.DE; HL := Src.HL;
  BC_ := Src.BC_; DE_ := Src.DE_; HL_ := Src.HL_;
  IX := Src.IX; IY := Src.IY; SP := Src.SP; PC := Src.PC; WZ := Src.WZ;
  I := Src.I; R := Src.R; R7 := Src.R7;
  IFF1 := Src.IFF1; IFF2 := Src.IFF2; IM := Src.IM;
  Halted := Src.Halted;
  Q := Src.Q; LastQ := Src.LastQ;
  T := Src.T;
  FEIJust := Src.FEIJust;
  FIFF2Read := Src.FIFF2Read;
end;

procedure TZ80.SetAF(Value: Word);
begin
  A := Value shr 8;
  F := Value and $FF;
end;

function TZ80.IR: Word;
begin
  Result := (I shl 8) or GetR;
end;

function TZ80.ReadByte(Addr: Word): Byte;
begin
  FBus.Contend(Addr, 3, T);
  Result := FBus.ReadMem(Addr, T);
end;

procedure TZ80.WriteByte(Addr: Word; Value: Byte);
begin
  FBus.Contend(Addr, 3, T);
  FBus.WriteMem(Addr, Value, T);
end;

procedure TZ80.NoMreq(Addr: Word; Count: Integer);
var
  N: Integer;
begin
  for N := 1 to Count do
    FBus.ContendNoMreq(Addr, 1, T);
end;

function TZ80.FetchOpcode: Byte;
begin
  FBus.Contend(PC.W, 4, T);
  Result := FBus.FetchMem(PC.W, T);
  Inc(PC.W);
  Inc(R);
end;

procedure TZ80.Push(const RP: TRegPair);
begin
  Dec(SP.W);
  WriteByte(SP.W, RP.H);
  Dec(SP.W);
  WriteByte(SP.W, RP.L);
end;

procedure TZ80.Pop(var RP: TRegPair);
begin
  RP.L := ReadByte(SP.W);
  Inc(SP.W);
  RP.H := ReadByte(SP.W);
  Inc(SP.W);
end;

function TZ80.GetReg(Index: Integer): Byte;
begin
  case Index of
    0: Result := BC.H;
    1: Result := BC.L;
    2: Result := DE.H;
    3: Result := DE.L;
    4: Result := HL.H;
    5: Result := HL.L;
  else
    Result := A;
  end;
end;

procedure TZ80.SetReg(Index: Integer; Value: Byte);
begin
  case Index of
    0: BC.H := Value;
    1: BC.L := Value;
    2: DE.H := Value;
    3: DE.L := Value;
    4: HL.H := Value;
    5: HL.L := Value;
  else
    A := Value;
  end;
end;

function TZ80.GetRegX(Index: Integer; const XY: TRegPair): Byte;
begin
  case Index of
    4: Result := XY.H;
    5: Result := XY.L;
  else
    Result := GetReg(Index);
  end;
end;

procedure TZ80.SetRegX(Index: Integer; var XY: TRegPair; Value: Byte);
begin
  case Index of
    4: XY.H := Value;
    5: XY.L := Value;
  else
    SetReg(Index, Value);
  end;
end;

function TZ80.Condition(Index: Integer): Boolean;
begin
  case Index of
    0: Result := (F and FLAG_Z) = 0;
    1: Result := (F and FLAG_Z) <> 0;
    2: Result := (F and FLAG_C) = 0;
    3: Result := (F and FLAG_C) <> 0;
    4: Result := (F and FLAG_P) = 0;
    5: Result := (F and FLAG_P) <> 0;
    6: Result := (F and FLAG_S) = 0;
  else
    Result := (F and FLAG_S) <> 0;
  end;
end;

{ Flag helpers }

procedure TZ80.DoAdd(Value: Byte);
var
  Temp: Word;
  Lookup: Byte;
begin
  Temp := A + Value;
  Lookup := ((A and $88) shr 3) or ((Value and $88) shr 2) or ((Temp and $88) shr 1);
  A := Temp and $FF;
  F := HalfcarryAddTable[Lookup and 7] or OverflowAddTable[Lookup shr 4] or SZ53Table[A];
  if (Temp and $100) <> 0 then F := F or FLAG_C;
  Q := F;
end;

procedure TZ80.DoAdc(Value: Byte);
var
  Temp: Word;
  Lookup: Byte;
begin
  Temp := A + Value + (F and FLAG_C);
  Lookup := ((A and $88) shr 3) or ((Value and $88) shr 2) or ((Temp and $88) shr 1);
  A := Temp and $FF;
  F := HalfcarryAddTable[Lookup and 7] or OverflowAddTable[Lookup shr 4] or SZ53Table[A];
  if (Temp and $100) <> 0 then F := F or FLAG_C;
  Q := F;
end;

procedure TZ80.DoSub(Value: Byte);
var
  Temp: Word;
  Lookup: Byte;
begin
  Temp := Word(A - Value);
  Lookup := ((A and $88) shr 3) or ((Value and $88) shr 2) or ((Temp and $88) shr 1);
  A := Temp and $FF;
  F := FLAG_N or HalfcarrySubTable[Lookup and 7] or OverflowSubTable[Lookup shr 4] or SZ53Table[A];
  if (Temp and $100) <> 0 then F := F or FLAG_C;
  Q := F;
end;

procedure TZ80.DoSbc(Value: Byte);
var
  Temp: Word;
  Lookup: Byte;
begin
  Temp := Word(A - Value - (F and FLAG_C));
  Lookup := ((A and $88) shr 3) or ((Value and $88) shr 2) or ((Temp and $88) shr 1);
  A := Temp and $FF;
  F := FLAG_N or HalfcarrySubTable[Lookup and 7] or OverflowSubTable[Lookup shr 4] or SZ53Table[A];
  if (Temp and $100) <> 0 then F := F or FLAG_C;
  Q := F;
end;

procedure TZ80.DoCp(Value: Byte);
var
  Temp: Word;
  Lookup: Byte;
begin
  Temp := Word(A - Value);
  Lookup := ((A and $88) shr 3) or ((Value and $88) shr 2) or ((Temp and $88) shr 1);
  if (Temp and $100) <> 0 then
    F := FLAG_C
  else if Temp = 0 then
    F := FLAG_Z
  else
    F := 0;
  F := F or FLAG_N or HalfcarrySubTable[Lookup and 7] or OverflowSubTable[Lookup shr 4] or
    (Value and (FLAG_3 or FLAG_5)) or (Temp and FLAG_S);
  Q := F;
end;

procedure TZ80.Alu(Op: Integer; Value: Byte);
begin
  case Op of
    0: DoAdd(Value);
    1: DoAdc(Value);
    2: DoSub(Value);
    3: DoSbc(Value);
    4: begin A := A and Value; F := FLAG_H or SZ53PTable[A]; Q := F; end;
    5: begin A := A xor Value; F := SZ53PTable[A]; Q := F; end;
    6: begin A := A or Value; F := SZ53PTable[A]; Q := F; end;
  else
    DoCp(Value);
  end;
end;

function TZ80.DoInc(Value: Byte): Byte;
begin
  Result := Byte(Value + 1);
  F := (F and FLAG_C) or SZ53Table[Result];
  if Result = $80 then F := F or FLAG_V;
  if (Result and $0F) = 0 then F := F or FLAG_H;
  Q := F;
end;

function TZ80.DoDec(Value: Byte): Byte;
begin
  F := (F and FLAG_C) or FLAG_N;
  if (Value and $0F) = 0 then F := F or FLAG_H;
  Result := Byte(Value - 1);
  F := F or SZ53Table[Result];
  if Result = $7F then F := F or FLAG_V;
  Q := F;
end;

{ CB rotate/shift group: RLC RRC RL RR SLA SRA SLL SRL }
function TZ80.Rotate(Op: Integer; Value: Byte): Byte;
var
  Carry: Byte;
begin
  case Op of
    0: begin Carry := Value shr 7; Result := Byte(Value shl 1) or Carry; end;
    1: begin Carry := Value and 1; Result := (Value shr 1) or Byte(Value shl 7); end;
    2: begin Carry := Value shr 7; Result := Byte(Value shl 1) or (F and FLAG_C); end;
    3: begin Carry := Value and 1; Result := (Value shr 1) or Byte(F shl 7); end;
    4: begin Carry := Value shr 7; Result := Byte(Value shl 1); end;
    5: begin Carry := Value and 1; Result := (Value and $80) or (Value shr 1); end;
    6: begin Carry := Value shr 7; Result := Byte(Value shl 1) or 1; end;
  else
    begin Carry := Value and 1; Result := Value shr 1; end;
  end;
  F := Carry or SZ53PTable[Result];
  Q := F;
end;

procedure TZ80.DoBit(Bit: Integer; Value, Bits35: Byte);
begin
  F := (F and FLAG_C) or FLAG_H or (Bits35 and (FLAG_3 or FLAG_5));
  if (Value and (1 shl Bit)) = 0 then F := F or FLAG_P or FLAG_Z;
  if (Bit = 7) and ((Value and $80) <> 0) then F := F or FLAG_S;
  Q := F;
end;

procedure TZ80.Add16(var Dest: TRegPair; Value: Word);
var
  Temp: LongWord;
  Lookup: Byte;
begin
  Temp := LongWord(Dest.W) + Value;
  Lookup := ((Dest.W and $0800) shr 11) or ((Value and $0800) shr 10) or ((Temp and $0800) shr 9);
  WZ.W := Dest.W + 1;
  Dest.W := Temp and $FFFF;
  F := (F and (FLAG_V or FLAG_Z or FLAG_S)) or ((Temp shr 8) and (FLAG_3 or FLAG_5)) or
    HalfcarryAddTable[Lookup];
  if (Temp and $10000) <> 0 then F := F or FLAG_C;
  Q := F;
end;

procedure TZ80.Adc16(Value: Word);
var
  Temp: LongWord;
  Lookup: Byte;
begin
  Temp := LongWord(HL.W) + Value + (F and FLAG_C);
  Lookup := ((HL.W and $8800) shr 11) or ((Value and $8800) shr 10) or ((Temp and $8800) shr 9);
  WZ.W := HL.W + 1;
  HL.W := Temp and $FFFF;
  F := OverflowAddTable[Lookup shr 4] or (HL.H and (FLAG_3 or FLAG_5 or FLAG_S)) or
    HalfcarryAddTable[Lookup and 7];
  if (Temp and $10000) <> 0 then F := F or FLAG_C;
  if HL.W = 0 then F := F or FLAG_Z;
  Q := F;
end;

procedure TZ80.Sbc16(Value: Word);
var
  Temp: LongWord;
  Lookup: Byte;
begin
  Temp := LongWord(HL.W) - Value - (F and FLAG_C);
  Lookup := ((HL.W and $8800) shr 11) or ((Value and $8800) shr 10) or ((Temp and $8800) shr 9);
  WZ.W := HL.W + 1;
  HL.W := Temp and $FFFF;
  F := FLAG_N or OverflowSubTable[Lookup shr 4] or (HL.H and (FLAG_3 or FLAG_5 or FLAG_S)) or
    HalfcarrySubTable[Lookup and 7];
  if (Temp and $10000) <> 0 then F := F or FLAG_C;
  if HL.W = 0 then F := F or FLAG_Z;
  Q := F;
end;

procedure TZ80.Daa;
var
  Add, Carry: Byte;
begin
  Add := 0;
  Carry := F and FLAG_C;
  if ((F and FLAG_H) <> 0) or ((A and $0F) > 9) then Add := 6;
  if (Carry <> 0) or (A > $99) then Add := Add or $60;
  if A > $99 then Carry := FLAG_C;
  if (F and FLAG_N) <> 0 then DoSub(Add) else DoAdd(Add);
  F := (F and not (FLAG_C or FLAG_P)) or Carry or ParityTable[A];
  Q := F;
end;

{ Undocumented flags of a block instruction that repeats (and so can be
  interrupted): bits 3 and 5 come from the high byte of PC. }
procedure TZ80.BlockRepeatFlags;
begin
  F := (F and not (FLAG_3 or FLAG_5)) or (PC.H and (FLAG_3 or FLAG_5));
  Q := F;
end;

{ INIR/INDR/OTIR/OTDR when repeating also alter H and P. Value is the byte
  transferred and B has already been decremented. }
procedure TZ80.BlockIORepeatFlags(Value: Byte);
begin
  BlockRepeatFlags;
  if (F and FLAG_C) <> 0 then
  begin
    F := F and not FLAG_H;
    if (Value and $80) <> 0 then
    begin
      F := F xor ((ParityTable[Byte(BC.H - 1) and 7] xor FLAG_P) and FLAG_P);
      if (BC.H and $0F) = $00 then F := F or FLAG_H;
    end
    else
    begin
      F := F xor ((ParityTable[Byte(BC.H + 1) and 7] xor FLAG_P) and FLAG_P);
      if (BC.H and $0F) = $0F then F := F or FLAG_H;
    end;
  end
  else
    F := F xor ((ParityTable[BC.H and 7] xor FLAG_P) and FLAG_P);
  Q := F;
end;

procedure TZ80.Jr;
var
  Offset: ShortInt;
begin
  Offset := ShortInt(ReadByte(PC.W));
  NoMreq(PC.W, 5);
  PC.W := Word(PC.W + Offset + 1);
  WZ.W := PC.W;
end;

{ Main execution }

procedure TZ80.Step;
var
  Op: Byte;
begin
  FEIJust := False;
  FIFF2Read := False;
  Op := FetchOpcode;
  LastQ := Q;
  Q := 0;
  ExecBase(Op);
end;

function TZ80.Interrupt: Boolean;
begin
  Result := False;
  if not IFF1 or FEIJust then Exit;
  // NMOS quirk: LD A,I / LD A,R interrupted reports IFF2 as reset
  if FIFF2Read then F := F and not FLAG_P;
  if Halted then
  begin
    Inc(PC.W);
    Halted := False;
  end;
  IFF1 := False;
  IFF2 := False;
  Inc(R);
  Inc(T, 7);
  Push(PC);
  if IM = 2 then
  begin
    // Data bus floats to $FF on the Spectrum
    WZ.W := (I shl 8) or $FF;
    PC.L := ReadByte(WZ.W);
    PC.H := ReadByte(Word(WZ.W + 1));
  end
  else
    PC.W := $0038;
  WZ.W := PC.W;
  Q := 0;
  Result := True;
end;

procedure TZ80.NMI(Stackless: Boolean);
begin
  if Halted then
  begin
    Inc(PC.W);
    Halted := False;
  end;
  IFF1 := False;
  Inc(R);
  Inc(T, 5);
  if Stackless then
  begin
    Dec(SP.W, 2);
    Inc(T, 6);
  end
  else
    Push(PC);
  Q := 0;
  PC.W := $0066;
end;

procedure TZ80.ExecBase(Op: Byte);
var
  B1, B2: Byte;
  W: TRegPair;
  Temp: Word;
begin
  case Op of
    $00: ;
    $01, $11, $21, $31:
      begin
        W.L := ReadByte(PC.W); Inc(PC.W);
        W.H := ReadByte(PC.W); Inc(PC.W);
        case Op of
          $01: BC := W;
          $11: DE := W;
          $21: HL := W;
        else
          SP := W;
        end;
      end;
    $02:
      begin
        WZ.L := Byte(BC.W + 1); WZ.H := A;
        WriteByte(BC.W, A);
      end;
    $12:
      begin
        WZ.L := Byte(DE.W + 1); WZ.H := A;
        WriteByte(DE.W, A);
      end;
    $03, $13, $23, $33, $0B, $1B, $2B, $3B:
      begin
        NoMreq(IR, 2);
        case Op of
          $03: Inc(BC.W);
          $13: Inc(DE.W);
          $23: Inc(HL.W);
          $33: Inc(SP.W);
          $0B: Dec(BC.W);
          $1B: Dec(DE.W);
          $2B: Dec(HL.W);
        else
          Dec(SP.W);
        end;
      end;
    $04, $0C, $14, $1C, $24, $2C, $3C:
      SetReg(Op shr 3, DoInc(GetReg(Op shr 3)));
    $05, $0D, $15, $1D, $25, $2D, $3D:
      SetReg(Op shr 3, DoDec(GetReg(Op shr 3)));
    $06, $0E, $16, $1E, $26, $2E, $3E:
      begin
        B1 := ReadByte(PC.W); Inc(PC.W);
        SetReg(Op shr 3, B1);
      end;
    $07:
      begin
        A := Byte(A shl 1) or (A shr 7);
        F := (F and (FLAG_P or FLAG_Z or FLAG_S)) or (A and (FLAG_C or FLAG_3 or FLAG_5));
        Q := F;
      end;
    $08:
      begin
        B1 := A; A := A_; A_ := B1;
        B1 := F; F := F_; F_ := B1;
      end;
    $09: begin NoMreq(IR, 7); Add16(HL, BC.W); end;
    $19: begin NoMreq(IR, 7); Add16(HL, DE.W); end;
    $29: begin NoMreq(IR, 7); Add16(HL, HL.W); end;
    $39: begin NoMreq(IR, 7); Add16(HL, SP.W); end;
    $0A:
      begin
        WZ.W := BC.W + 1;
        A := ReadByte(BC.W);
      end;
    $1A:
      begin
        WZ.W := DE.W + 1;
        A := ReadByte(DE.W);
      end;
    $0F:
      begin
        F := (F and (FLAG_P or FLAG_Z or FLAG_S)) or (A and FLAG_C);
        A := (A shr 1) or Byte(A shl 7);
        F := F or (A and (FLAG_3 or FLAG_5));
        Q := F;
      end;
    $10:
      begin
        NoMreq(IR, 1);
        Dec(BC.H);
        if BC.H <> 0 then
          Jr
        else
        begin
          FBus.Contend(PC.W, 3, T);
          Inc(PC.W);
        end;
      end;
    $17:
      begin
        B1 := A;
        A := Byte(A shl 1) or (F and FLAG_C);
        F := (F and (FLAG_P or FLAG_Z or FLAG_S)) or (A and (FLAG_3 or FLAG_5)) or (B1 shr 7);
        Q := F;
      end;
    $18: Jr;
    $1F:
      begin
        B1 := A;
        A := (A shr 1) or Byte(F shl 7);
        F := (F and (FLAG_P or FLAG_Z or FLAG_S)) or (A and (FLAG_3 or FLAG_5)) or (B1 and FLAG_C);
        Q := F;
      end;
    $20, $28, $30, $38:
      if Condition((Op shr 3) and 3) then
        Jr
      else
      begin
        FBus.Contend(PC.W, 3, T);
        Inc(PC.W);
      end;
    $22:
      begin
        W.L := ReadByte(PC.W); Inc(PC.W);
        W.H := ReadByte(PC.W); Inc(PC.W);
        WriteByte(W.W, HL.L);
        Inc(W.W);
        WZ.W := W.W;
        WriteByte(W.W, HL.H);
      end;
    $27: Daa;
    $2A:
      begin
        W.L := ReadByte(PC.W); Inc(PC.W);
        W.H := ReadByte(PC.W); Inc(PC.W);
        HL.L := ReadByte(W.W);
        Inc(W.W);
        WZ.W := W.W;
        HL.H := ReadByte(W.W);
      end;
    $2F:
      begin
        A := A xor $FF;
        F := (F and (FLAG_C or FLAG_P or FLAG_Z or FLAG_S)) or (A and (FLAG_3 or FLAG_5)) or
          FLAG_N or FLAG_H;
        Q := F;
      end;
    $32:
      begin
        W.L := ReadByte(PC.W); Inc(PC.W);
        W.H := ReadByte(PC.W); Inc(PC.W);
        WZ.L := Byte(W.W + 1); WZ.H := A;
        WriteByte(W.W, A);
      end;
    $34:
      begin
        B1 := ReadByte(HL.W);
        NoMreq(HL.W, 1);
        WriteByte(HL.W, DoInc(B1));
      end;
    $35:
      begin
        B1 := ReadByte(HL.W);
        NoMreq(HL.W, 1);
        WriteByte(HL.W, DoDec(B1));
      end;
    $36:
      begin
        B1 := ReadByte(PC.W); Inc(PC.W);
        WriteByte(HL.W, B1);
      end;
    $37:
      begin
        F := (F and (FLAG_P or FLAG_Z or FLAG_S)) or (((LastQ xor F) or A) and (FLAG_3 or FLAG_5)) or
          FLAG_C;
        Q := F;
      end;
    $3A:
      begin
        WZ.L := ReadByte(PC.W); Inc(PC.W);
        WZ.H := ReadByte(PC.W); Inc(PC.W);
        A := ReadByte(WZ.W);
        Inc(WZ.W);
      end;
    $3F:
      begin
        B1 := (F and (FLAG_P or FLAG_Z or FLAG_S)) or (((LastQ xor F) or A) and (FLAG_3 or FLAG_5));
        if (F and FLAG_C) <> 0 then B1 := B1 or FLAG_H else B1 := B1 or FLAG_C;
        F := B1;
        Q := F;
      end;
    $76:
      begin
        Halted := True;
        Dec(PC.W);
      end;
    $40..$75, $77..$7F:
      if (Op and 7) = 6 then
        SetReg((Op shr 3) and 7, ReadByte(HL.W))
      else if ((Op shr 3) and 7) = 6 then
        WriteByte(HL.W, GetReg(Op and 7))
      else
        SetReg((Op shr 3) and 7, GetReg(Op and 7));
    $80..$BF:
      if (Op and 7) = 6 then
        Alu((Op shr 3) and 7, ReadByte(HL.W))
      else
        Alu((Op shr 3) and 7, GetReg(Op and 7));
    $C0, $C8, $D0, $D8, $E0, $E8, $F0, $F8:
      begin
        NoMreq(IR, 1);
        if Condition((Op shr 3) and 7) then
        begin
          Pop(PC);
          WZ.W := PC.W;
        end;
      end;
    $C1: Pop(BC);
    $D1: Pop(DE);
    $E1: Pop(HL);
    $F1:
      begin
        Pop(W);
        A := W.H; F := W.L;
      end;
    $C2, $CA, $D2, $DA, $E2, $EA, $F2, $FA:
      begin
        WZ.L := ReadByte(PC.W); Inc(PC.W);
        WZ.H := ReadByte(PC.W);
        if Condition((Op shr 3) and 7) then
          PC.W := WZ.W
        else
          Inc(PC.W);
      end;
    $C3:
      begin
        WZ.L := ReadByte(PC.W); Inc(PC.W);
        WZ.H := ReadByte(PC.W);
        PC.W := WZ.W;
      end;
    $C4, $CC, $D4, $DC, $E4, $EC, $F4, $FC, $CD:
      begin
        WZ.L := ReadByte(PC.W); Inc(PC.W);
        WZ.H := ReadByte(PC.W);
        if (Op = $CD) or Condition((Op shr 3) and 7) then
        begin
          NoMreq(PC.W, 1);
          Inc(PC.W);
          Push(PC);
          PC.W := WZ.W;
        end
        else
          Inc(PC.W);
      end;
    $C5: begin NoMreq(IR, 1); Push(BC); end;
    $D5: begin NoMreq(IR, 1); Push(DE); end;
    $E5: begin NoMreq(IR, 1); Push(HL); end;
    $F5:
      begin
        NoMreq(IR, 1);
        W.H := A; W.L := F;
        Push(W);
      end;
    $C6, $CE, $D6, $DE, $E6, $EE, $F6, $FE:
      begin
        B1 := ReadByte(PC.W); Inc(PC.W);
        Alu((Op shr 3) and 7, B1);
      end;
    $C7, $CF, $D7, $DF, $E7, $EF, $F7, $FF:
      begin
        NoMreq(IR, 1);
        Push(PC);
        PC.W := Op and $38;
        WZ.W := PC.W;
      end;
    $C9:
      begin
        Pop(PC);
        WZ.W := PC.W;
      end;
    $CB: ExecCB;
    $D3:
      begin
        B1 := ReadByte(PC.W); Inc(PC.W);
        Temp := B1 or (A shl 8);
        WZ.H := A; WZ.L := Byte(B1 + 1);
        FBus.WritePort(Temp, A, T);
      end;
    $D9:
      begin
        W := BC; BC := BC_; BC_ := W;
        W := DE; DE := DE_; DE_ := W;
        W := HL; HL := HL_; HL_ := W;
      end;
    $DB:
      begin
        B1 := ReadByte(PC.W); Inc(PC.W);
        Temp := B1 or (A shl 8);
        A := FBus.ReadPort(Temp, T);
        WZ.W := Temp + 1;
      end;
    $DD: ExecIndex(IX);
    $E3:
      begin
        B1 := ReadByte(SP.W);
        B2 := ReadByte(Word(SP.W + 1));
        NoMreq(Word(SP.W + 1), 1);
        WriteByte(Word(SP.W + 1), HL.H);
        WriteByte(SP.W, HL.L);
        NoMreq(SP.W, 2);
        HL.L := B1; HL.H := B2;
        WZ.W := HL.W;
      end;
    $E9: PC.W := HL.W;
    $EB:
      begin
        W := DE; DE := HL; HL := W;
      end;
    $ED: ExecED;
    $F3:
      begin
        IFF1 := False; IFF2 := False;
      end;
    $F9:
      begin
        NoMreq(IR, 2);
        SP.W := HL.W;
      end;
    $FB:
      begin
        IFF1 := True; IFF2 := True;
        FEIJust := True;
      end;
    $FD: ExecIndex(IY);
  end;
end;

procedure TZ80.ExecCB;
var
  Op, V, Y, Z: Byte;
begin
  Op := FetchOpcode;
  Y := (Op shr 3) and 7;
  Z := Op and 7;
  if Z = 6 then
  begin
    V := ReadByte(HL.W);
    NoMreq(HL.W, 1);
    case Op shr 6 of
      0: WriteByte(HL.W, Rotate(Y, V));
      1: DoBit(Y, V, WZ.H);
      2: WriteByte(HL.W, V and not (1 shl Y));
      3: WriteByte(HL.W, V or (1 shl Y));
    end;
  end
  else
    case Op shr 6 of
      0: SetReg(Z, Rotate(Y, GetReg(Z)));
      1: begin V := GetReg(Z); DoBit(Y, V, V); end;
      2: SetReg(Z, GetReg(Z) and not (1 shl Y));
      3: SetReg(Z, GetReg(Z) or (1 shl Y));
    end;
end;

procedure TZ80.ExecED;
var
  Op, B1, B2, Lookup: Byte;
  W: TRegPair;
  Delta: Integer;
  Repeating: Boolean;
begin
  Op := FetchOpcode;
  if Z80N and ExecZ80N(Op) then Exit;
  case Op of
    $40, $48, $50, $58, $60, $68, $70, $78:
      begin
        WZ.W := BC.W + 1;
        B1 := FBus.ReadPort(BC.W, T);
        F := (F and FLAG_C) or SZ53PTable[B1];
        Q := F;
        if Op <> $70 then SetReg((Op shr 3) and 7, B1);
      end;
    $41, $49, $51, $59, $61, $69, $71, $79:
      begin
        if Op = $71 then B1 := 0 else B1 := GetReg((Op shr 3) and 7);
        FBus.WritePort(BC.W, B1, T);
        WZ.W := BC.W + 1;
      end;
    $42: begin NoMreq(IR, 7); Sbc16(BC.W); end;
    $52: begin NoMreq(IR, 7); Sbc16(DE.W); end;
    $62: begin NoMreq(IR, 7); Sbc16(HL.W); end;
    $72: begin NoMreq(IR, 7); Sbc16(SP.W); end;
    $4A: begin NoMreq(IR, 7); Adc16(BC.W); end;
    $5A: begin NoMreq(IR, 7); Adc16(DE.W); end;
    $6A: begin NoMreq(IR, 7); Adc16(HL.W); end;
    $7A: begin NoMreq(IR, 7); Adc16(SP.W); end;
    $43, $53, $63, $73:
      begin
        case Op of
          $43: W := BC;
          $53: W := DE;
          $63: W := HL;
        else
          W := SP;
        end;
        WZ.L := ReadByte(PC.W); Inc(PC.W);
        WZ.H := ReadByte(PC.W); Inc(PC.W);
        WriteByte(WZ.W, W.L);
        Inc(WZ.W);
        WriteByte(WZ.W, W.H);
      end;
    $4B, $5B, $6B, $7B:
      begin
        WZ.L := ReadByte(PC.W); Inc(PC.W);
        WZ.H := ReadByte(PC.W); Inc(PC.W);
        W.L := ReadByte(WZ.W);
        Inc(WZ.W);
        W.H := ReadByte(WZ.W);
        case Op of
          $4B: BC := W;
          $5B: DE := W;
          $6B: HL := W;
        else
          SP := W;
        end;
      end;
    $44, $4C, $54, $5C, $64, $6C, $74, $7C:
      begin
        B1 := A;
        A := 0;
        DoSub(B1);
      end;
    $45, $4D, $55, $5D, $65, $6D, $75, $7D:
      begin
        IFF1 := IFF2;
        Pop(PC);
        // RETN (not RETI, ED 4D) ends an NMI
        if Op <> $4D then FBus.Retn;
        WZ.W := PC.W;
      end;
    $46, $4E, $66, $6E: IM := 0;
    $56, $76: IM := 1;
    $5E, $7E: IM := 2;
    $47: begin NoMreq(IR, 1); I := A; end;
    $4F: begin NoMreq(IR, 1); R := A; R7 := A; end;
    $57, $5F:
      begin
        NoMreq(IR, 1);
        if Op = $57 then A := I else A := GetR;
        F := (F and FLAG_C) or SZ53Table[A];
        if IFF2 then F := F or FLAG_V;
        Q := F;
        FIFF2Read := True;
      end;
    $67:
      begin
        B1 := ReadByte(HL.W);
        NoMreq(HL.W, 4);
        WriteByte(HL.W, Byte(A shl 4) or (B1 shr 4));
        A := (A and $F0) or (B1 and $0F);
        F := (F and FLAG_C) or SZ53PTable[A];
        Q := F;
        WZ.W := HL.W + 1;
      end;
    $6F:
      begin
        B1 := ReadByte(HL.W);
        NoMreq(HL.W, 4);
        WriteByte(HL.W, Byte(B1 shl 4) or (A and $0F));
        A := (A and $F0) or (B1 shr 4);
        F := (F and FLAG_C) or SZ53PTable[A];
        Q := F;
        WZ.W := HL.W + 1;
      end;
    $A0, $A8, $B0, $B8:  // LDI LDD LDIR LDDR
      begin
        if (Op and 8) = 0 then Delta := 1 else Delta := -1;
        Repeating := (Op and $10) <> 0;
        B1 := ReadByte(HL.W);
        WriteByte(DE.W, B1);
        NoMreq(DE.W, 2);
        Dec(BC.W);
        B1 := Byte(B1 + A);
        F := (F and (FLAG_C or FLAG_Z or FLAG_S)) or (B1 and FLAG_3);
        if BC.W <> 0 then F := F or FLAG_V;
        if (B1 and $02) <> 0 then F := F or FLAG_5;
        Q := F;
        if Repeating and (BC.W <> 0) then
        begin
          NoMreq(DE.W, 5);
          Dec(PC.W, 2);
          WZ.W := PC.W + 1;
          BlockRepeatFlags;
        end;
        HL.W := Word(HL.W + Delta);
        DE.W := Word(DE.W + Delta);
      end;
    $A1, $A9, $B1, $B9:  // CPI CPD CPIR CPDR
      begin
        if (Op and 8) = 0 then Delta := 1 else Delta := -1;
        Repeating := (Op and $10) <> 0;
        B1 := ReadByte(HL.W);
        B2 := Byte(A - B1);
        Lookup := ((A and $08) shr 3) or ((B1 and $08) shr 2) or ((B2 and $08) shr 1);
        NoMreq(HL.W, 5);
        Dec(BC.W);
        F := (F and FLAG_C) or HalfcarrySubTable[Lookup] or (B2 and FLAG_S) or FLAG_N;
        if BC.W <> 0 then F := F or FLAG_V;
        if B2 = 0 then F := F or FLAG_Z;
        if (F and FLAG_H) <> 0 then Dec(B2);
        F := F or (B2 and FLAG_3);
        if (B2 and $02) <> 0 then F := F or FLAG_5;
        Q := F;
        if Repeating and ((F and (FLAG_V or FLAG_Z)) = FLAG_V) then
        begin
          NoMreq(HL.W, 5);
          Dec(PC.W, 2);
          WZ.W := PC.W + 1;
          BlockRepeatFlags;
        end
        else
          WZ.W := Word(WZ.W + Delta);
        HL.W := Word(HL.W + Delta);
      end;
    $A2, $AA, $B2, $BA:  // INI IND INIR INDR
      begin
        if (Op and 8) = 0 then Delta := 1 else Delta := -1;
        Repeating := (Op and $10) <> 0;
        NoMreq(IR, 1);
        B1 := FBus.ReadPort(BC.W, T);
        WriteByte(HL.W, B1);
        WZ.W := Word(BC.W + Delta);
        Dec(BC.H);
        B2 := Byte(B1 + BC.L + Delta);
        F := SZ53Table[BC.H];
        if (B1 and $80) <> 0 then F := F or FLAG_N;
        if B2 < B1 then F := F or FLAG_H or FLAG_C;
        if ParityTable[(B2 and 7) xor BC.H] <> 0 then F := F or FLAG_P;
        Q := F;
        if Repeating and (BC.H <> 0) then
        begin
          NoMreq(HL.W, 5);
          Dec(PC.W, 2);
          WZ.W := PC.W + 1;
          BlockIORepeatFlags(B1);
        end;
        HL.W := Word(HL.W + Delta);
      end;
    $A3, $AB, $B3, $BB:  // OUTI OUTD OTIR OTDR
      begin
        if (Op and 8) = 0 then Delta := 1 else Delta := -1;
        Repeating := (Op and $10) <> 0;
        NoMreq(IR, 1);
        B1 := ReadByte(HL.W);
        Dec(BC.H);
        WZ.W := Word(BC.W + Delta);
        FBus.WritePort(BC.W, B1, T);
        HL.W := Word(HL.W + Delta);
        B2 := Byte(B1 + HL.L);
        F := SZ53Table[BC.H];
        if (B1 and $80) <> 0 then F := F or FLAG_N;
        if B2 < B1 then F := F or FLAG_H or FLAG_C;
        if ParityTable[(B2 and 7) xor BC.H] <> 0 then F := F or FLAG_P;
        Q := F;
        if Repeating and (BC.H <> 0) then
        begin
          NoMreq(BC.W, 5);
          Dec(PC.W, 2);
          WZ.W := PC.W + 1;
          BlockIORepeatFlags(B1);
        end;
      end;
  end;
  // All other ED opcodes are 8 T-state NOPs
end;

{ The Z80N's extra ED instructions (wiki.specnext.dev/Extended_Z80_instruction_set);
  False if Op isn't one. Their T-states are the wiki's; the block copies set
  the flags as LDI/LDD do (core 3.02 testing). }
function TZ80.ExecZ80N(Op: Byte): Boolean;
var
  B1, Src: Byte;
  W: TRegPair;
  N, Delta: Integer;
  Repeating: Boolean;
begin
  Result := True;
  case Op of
    $23: A := Byte((A shl 4) or (A shr 4));                       // SWAPNIB
    $24:                                                          // MIRROR A
      begin
        B1 := 0;
        for N := 0 to 7 do
          if (A and (1 shl N)) <> 0 then B1 := B1 or ($80 shr N);
        A := B1;
      end;
    $27:                                                          // TEST n
      begin
        B1 := ReadByte(PC.W); Inc(PC.W);
        B1 := A and B1;
        F := SZ53PTable[B1] or FLAG_H;
        Q := F;
      end;
    $28: DE.W := Word(DE.W shl (BC.H and 31));                    // BSLA DE,B
    $29: DE.W := Word(SarLongint(SmallInt(DE.W), BC.H and 31));   // BSRA DE,B
    $2A: DE.W := DE.W shr (BC.H and 31);                          // BSRL DE,B
    $2B: DE.W := Word(not (Word(not DE.W) shr (BC.H and 31)));    // BSRF DE,B
    $2C:                                                          // BRLC DE,B
      begin
        N := BC.H and 15;
        DE.W := Word((DE.W shl N) or (DE.W shr (16 - N)));
      end;
    $30: DE.W := Word(DE.H * DE.L);                               // MUL D,E
    $31: HL.W := Word(HL.W + A);                                  // ADD HL,A
    $32: DE.W := Word(DE.W + A);                                  // ADD DE,A
    $33: BC.W := Word(BC.W + A);                                  // ADD BC,A
    $34, $35, $36:                                                // ADD rr,nn
      begin
        W.L := ReadByte(PC.W); Inc(PC.W);
        W.H := ReadByte(PC.W); Inc(PC.W);
        NoMreq(PC.W, 2);
        case Op of
          $34: HL.W := Word(HL.W + W.W);
          $35: DE.W := Word(DE.W + W.W);
        else
          BC.W := Word(BC.W + W.W);
        end;
      end;
    $8A:                                                          // PUSH nn
      begin
        W.H := ReadByte(PC.W); Inc(PC.W);
        W.L := ReadByte(PC.W); Inc(PC.W);
        NoMreq(IR, 3);
        Dec(SP.W);
        WriteByte(SP.W, W.H);
        Dec(SP.W);
        WriteByte(SP.W, W.L);
      end;
    $90:                                                          // OUTINB
      begin
        NoMreq(IR, 1);
        B1 := ReadByte(HL.W);
        FBus.WritePort(BC.W, B1, T);
        HL.W := Word(HL.W + 1);
      end;
    $91:                                                          // NEXTREG n,m
      begin
        W.L := ReadByte(PC.W); Inc(PC.W);
        W.H := ReadByte(PC.W); Inc(PC.W);
        Inc(T, 6);
        FBus.WriteNextReg(W.L, W.H, T);
      end;
    $92:                                                          // NEXTREG n,A
      begin
        W.L := ReadByte(PC.W); Inc(PC.W);
        Inc(T, 6);
        FBus.WriteNextReg(W.L, A, T);
      end;
    $93:                                                          // PIXELDN
      if (HL.H and 7) <> 7 then
        Inc(HL.H)
      else if (HL.L and $E0) <> $E0 then
      begin
        HL.H := HL.H and $F8;
        HL.L := Byte(HL.L + $20);
      end
      else
      begin
        HL.H := Byte((HL.H and $F8) + 8);
        HL.L := HL.L and $1F;
      end;
    $94:                                                          // PIXELAD
      HL.W := $4000 or ((DE.H and $C0) shl 5) or ((DE.H and 7) shl 8) or
        ((DE.H and $38) shl 2) or (DE.L shr 3);
    $95: A := $80 shr (DE.L and 7);                               // SETAE
    $98:                                                          // JP (C)
      begin
        B1 := FBus.ReadPort(BC.W, T);
        Inc(T);
        PC.W := (PC.W and $C000) or (Word(B1) shl 6);
        WZ.W := PC.W;
      end;
    $A4, $AC, $B4, $BC, $B7:                     // LDIX LDDX LDIRX LDDRX LDPIRX
      begin
        if Op = $B7 then Src := ReadByte((HL.W and $FFF8) or (DE.L and 7))
        else Src := ReadByte(HL.W);
        if Src <> A then WriteByte(DE.W, Src) else Inc(T, 3);
        NoMreq(DE.W, 2);
        Dec(BC.W);
        if (Op = $AC) or (Op = $BC) then Delta := -1 else Delta := 1;
        Repeating := Op in [$B4, $BC, $B7];
        F := F and (FLAG_C or FLAG_Z or FLAG_S or FLAG_3 or FLAG_5);
        if BC.W <> 0 then F := F or FLAG_V;
        Q := F;
        if Repeating and (BC.W <> 0) then
        begin
          NoMreq(DE.W, 5);
          Dec(PC.W, 2);
        end;
        if Op <> $B7 then HL.W := Word(HL.W + Delta);
        DE.W := Word(DE.W + 1);
      end;
    $A5:                                                          // LDWS
      begin
        B1 := ReadByte(HL.W);
        WriteByte(DE.W, B1);
        HL.L := Byte(HL.L + 1);
        DE.H := DoInc(DE.H);
      end;
  else
    Result := False;
  end;
end;

{ Read the displacement of an (IX+d)/(IY+d) operand and return the address. }
function TZ80.ReadIndexAddr(const XY: TRegPair): Word;
var
  D: ShortInt;
begin
  D := ShortInt(ReadByte(PC.W));
  NoMreq(PC.W, 5);
  Inc(PC.W);
  WZ.W := Word(XY.W + D);
  Result := WZ.W;
end;

procedure TZ80.ExecIndex(var XY: TRegPair);
var
  Op, B1: Byte;
  D: ShortInt;
  W: TRegPair;
  Addr: Word;
begin
  Op := FetchOpcode;
  case Op of
    $09: begin NoMreq(IR, 7); Add16(XY, BC.W); end;
    $19: begin NoMreq(IR, 7); Add16(XY, DE.W); end;
    $29: begin NoMreq(IR, 7); Add16(XY, XY.W); end;
    $39: begin NoMreq(IR, 7); Add16(XY, SP.W); end;
    $21:
      begin
        XY.L := ReadByte(PC.W); Inc(PC.W);
        XY.H := ReadByte(PC.W); Inc(PC.W);
      end;
    $22:
      begin
        W.L := ReadByte(PC.W); Inc(PC.W);
        W.H := ReadByte(PC.W); Inc(PC.W);
        WriteByte(W.W, XY.L);
        Inc(W.W);
        WZ.W := W.W;
        WriteByte(W.W, XY.H);
      end;
    $2A:
      begin
        W.L := ReadByte(PC.W); Inc(PC.W);
        W.H := ReadByte(PC.W); Inc(PC.W);
        XY.L := ReadByte(W.W);
        Inc(W.W);
        WZ.W := W.W;
        XY.H := ReadByte(W.W);
      end;
    $23: begin NoMreq(IR, 2); Inc(XY.W); end;
    $2B: begin NoMreq(IR, 2); Dec(XY.W); end;
    $24: XY.H := DoInc(XY.H);
    $25: XY.H := DoDec(XY.H);
    $2C: XY.L := DoInc(XY.L);
    $2D: XY.L := DoDec(XY.L);
    $26:
      begin
        XY.H := ReadByte(PC.W); Inc(PC.W);
      end;
    $2E:
      begin
        XY.L := ReadByte(PC.W); Inc(PC.W);
      end;
    $34, $35:
      begin
        Addr := ReadIndexAddr(XY);
        B1 := ReadByte(Addr);
        NoMreq(Addr, 1);
        if Op = $34 then B1 := DoInc(B1) else B1 := DoDec(B1);
        WriteByte(Addr, B1);
      end;
    $36:
      begin
        D := ShortInt(ReadByte(PC.W)); Inc(PC.W);
        B1 := ReadByte(PC.W);
        NoMreq(PC.W, 2);
        Inc(PC.W);
        WZ.W := Word(XY.W + D);
        WriteByte(WZ.W, B1);
      end;
    $44, $45, $4C, $4D, $54, $55, $5C, $5D, $7C, $7D,
    $60..$65, $67, $68..$6D, $6F:
      SetRegX((Op shr 3) and 7, XY, GetRegX(Op and 7, XY));
    $46, $4E, $56, $5E, $66, $6E, $7E:
      SetReg((Op shr 3) and 7, ReadByte(ReadIndexAddr(XY)));
    $70..$75, $77:
      begin
        Addr := ReadIndexAddr(XY);
        WriteByte(Addr, GetReg(Op and 7));
      end;
    $84, $85, $8C, $8D, $94, $95, $9C, $9D, $A4, $A5, $AC, $AD, $B4, $B5, $BC, $BD:
      Alu((Op shr 3) and 7, GetRegX(Op and 7, XY));
    $86, $8E, $96, $9E, $A6, $AE, $B6, $BE:
      Alu((Op shr 3) and 7, ReadByte(ReadIndexAddr(XY)));
    $CB: ExecIndexCB(XY);
    $E1: Pop(XY);
    $E3:
      begin
        W.L := ReadByte(SP.W);
        W.H := ReadByte(Word(SP.W + 1));
        NoMreq(Word(SP.W + 1), 1);
        WriteByte(Word(SP.W + 1), XY.H);
        WriteByte(SP.W, XY.L);
        NoMreq(SP.W, 2);
        XY := W;
        WZ.W := W.W;
      end;
    $E5: begin NoMreq(IR, 1); Push(XY); end;
    $E9: PC.W := XY.W;
    $F9: begin NoMreq(IR, 2); SP.W := XY.W; end;
  else
    begin
      // Prefix has no effect: run the opcode as an unprefixed one
      LastQ := 0;
      Q := 0;
      ExecBase(Op);
    end;
  end;
end;

procedure TZ80.ExecIndexCB(var XY: TRegPair);
var
  Op, V, Y, Z: Byte;
begin
  FBus.Contend(PC.W, 3, T);
  WZ.W := Word(XY.W + ShortInt(FBus.ReadMem(PC.W, T)));
  Inc(PC.W);
  FBus.Contend(PC.W, 3, T);
  Op := FBus.ReadMem(PC.W, T);
  NoMreq(PC.W, 2);
  Inc(PC.W);
  Y := (Op shr 3) and 7;
  Z := Op and 7;
  V := ReadByte(WZ.W);
  NoMreq(WZ.W, 1);
  case Op shr 6 of
    0: V := Rotate(Y, V);
    1:
      begin
        DoBit(Y, V, WZ.H);
        Exit;
      end;
    2: V := V and not (1 shl Y);
    3: V := V or (1 shl Y);
  end;
  WriteByte(WZ.W, V);
  // Undocumented: result is also copied to a register
  if Z <> 6 then SetReg(Z, V);
end;

initialization
  InitTables;
end.

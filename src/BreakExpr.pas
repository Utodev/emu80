{ BreakExpr: breakpoint conditions, e.g. "BC=289A", "A=3 AND E=3",
  "NOT (#Z=1 OR HL>=C000)", "A=@8400", "@(HL+1)=.30".

  - Numbers are hex ("289A", "$289A", "289Ah"); with a dot they are decimal
    (".30" is thirty).
  - Registers, case-insensitive: A F B C D E H L I R IXH IXL IYH IYL, AF BC DE
    HL IX IY SP PC, the alternate set with an apostrophe (A' F' AF' BC' DE'
    HL'), IFF1 IFF2 IM.
  - A name is a register first, then a symbol (user symbols, then the ROM
    labels), then a hex number: "C" is the register (write "0C" for the
    number), "BC" the register even if there is a symbol BC ("#BC" is the
    symbol). Symbols are looked up when the condition is set.
  - Flags with "#": #S #Z #5 #H #3 #P (or #V, #PV) #N #C, worth 0 or 1. Any
    other "#name" is a symbol.
  - @x: the byte in memory at address x ("A=@8400", "@(IX+2)=0").
  - T: how many times the breakpoint has been reached, this time included
    ("T=3" stops the third time). The count starts again when the condition
    is set.
  - Operators, from lowest to highest precedence: OR XOR, AND, NOT,
    = <> < > <= >=, + - | (bitwise or), * / MOD & (bitwise and), then the
    prefixes - and @. Comparisons bind tighter than AND/OR (unlike Pascal) so
    "A=3 AND E=3" means what it says. AND/OR/XOR/NOT are logical; & and |
    work on the bits ("A = C & 7"). Arithmetic wraps like the Z80's: at 8
    bits when both sides are 8-bit values (8-bit registers, flags, @x,
    numbers up to FF), at 16 bits otherwise ("A - 1" with A=0 is FF, "DE + 1"
    with DE=FFFF is 0). Parentheses group. }
unit BreakExpr;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Z80Core;

type
  TExprNode = class
  public
    Wide: Boolean;    // a 16-bit value (arithmetic on it wraps at 16 bits, else at 8)
    function Eval(Cpu: TZ80): Integer; virtual; abstract;
  end;

  { Memory reader for @, and symbol lookup for names in conditions }
  TConditionPeek = function(Addr: Word): Byte of object;
  TConditionSymbol = function(const Name: string; out Value: Word): Boolean;

  TBreakCondition = class
  private
    FText: string;
    FRoot: TExprNode;
    FHits: Integer;
    FUsesHits: Boolean;
  public
    destructor Destroy; override;
    { The breakpoint has been reached: count it and say whether the
      condition holds for the CPU's current state }
    function Holds(Cpu: TZ80): Boolean;
    property Text: string read FText;
    { Times the breakpoint has been reached (the T of the condition) }
    property Hits: Integer read FHits;
    { The condition uses T }
    property UsesHits: Boolean read FUsesHits;
  end;

{ Compile a condition. Returns nil and sets Error if it is not valid. }
function CompileCondition(const Text: string; out Error: string): TBreakCondition;

var
  { Set by the machine: reads memory for @ }
  ConditionPeek: TConditionPeek;
  { Set by the application: finds a symbol by name (case-insensitive) }
  ConditionSymbol: TConditionSymbol;

implementation

type
  TRegKind = (rkA, rkF, rkB, rkC, rkD, rkE, rkH, rkL, rkI, rkR, rkIXH, rkIXL, rkIYH, rkIYL,
    rkAF, rkBC, rkDE, rkHL, rkIX, rkIY, rkSP, rkPC, rkA_, rkF_, rkAF_, rkBC_, rkDE_, rkHL_,
    rkIFF1, rkIFF2, rkIM);

  TBinOp = (boOr, boXor, boAnd, boEq, boNe, boLt, boGt, boLe, boGe, boAdd, boSub,
    boBitOr, boMul, boDiv, boMod, boBitAnd);

  TConstNode = class(TExprNode)
    Value: Integer;
    function Eval(Cpu: TZ80): Integer; override;
  end;

  TRegNode = class(TExprNode)
    Reg: TRegKind;
    function Eval(Cpu: TZ80): Integer; override;
  end;

  { T: the hit count of the condition it belongs to }
  THitsNode = class(TExprNode)
    Hits: PInteger;
    function Eval(Cpu: TZ80): Integer; override;
  end;

  { @x: the byte at an address }
  TPeekNode = class(TExprNode)
    Child: TExprNode;
    destructor Destroy; override;
    function Eval(Cpu: TZ80): Integer; override;
  end;

  TFlagNode = class(TExprNode)
    Mask: Byte;
    function Eval(Cpu: TZ80): Integer; override;
  end;

  TNotNode = class(TExprNode)
    Child: TExprNode;
    destructor Destroy; override;
    function Eval(Cpu: TZ80): Integer; override;
  end;

  TNegNode = class(TExprNode)
    Child: TExprNode;
    destructor Destroy; override;
    function Eval(Cpu: TZ80): Integer; override;
  end;

  TBinNode = class(TExprNode)
    Op: TBinOp;
    Left, Right: TExprNode;
    destructor Destroy; override;
    function Eval(Cpu: TZ80): Integer; override;
  end;

  EExprError = class(Exception);

const
  REG_NAMES: array[TRegKind] of string = ('A', 'F', 'B', 'C', 'D', 'E', 'H', 'L', 'I', 'R',
    'IXH', 'IXL', 'IYH', 'IYL', 'AF', 'BC', 'DE', 'HL', 'IX', 'IY', 'SP', 'PC', 'A''', 'F''',
    'AF''', 'BC''', 'DE''', 'HL''', 'IFF1', 'IFF2', 'IM');

{ Nodes }

function TConstNode.Eval(Cpu: TZ80): Integer;
begin
  Result := Value;
end;

function TRegNode.Eval(Cpu: TZ80): Integer;
begin
  case Reg of
    rkA: Result := Cpu.A;
    rkF: Result := Cpu.F;
    rkB: Result := Cpu.BC.H;
    rkC: Result := Cpu.BC.L;
    rkD: Result := Cpu.DE.H;
    rkE: Result := Cpu.DE.L;
    rkH: Result := Cpu.HL.H;
    rkL: Result := Cpu.HL.L;
    rkI: Result := Cpu.I;
    rkR: Result := Cpu.GetR;
    rkIXH: Result := Cpu.IX.H;
    rkIXL: Result := Cpu.IX.L;
    rkIYH: Result := Cpu.IY.H;
    rkIYL: Result := Cpu.IY.L;
    rkAF: Result := Cpu.GetAF;
    rkBC: Result := Cpu.BC.W;
    rkDE: Result := Cpu.DE.W;
    rkHL: Result := Cpu.HL.W;
    rkIX: Result := Cpu.IX.W;
    rkIY: Result := Cpu.IY.W;
    rkSP: Result := Cpu.SP.W;
    rkPC: Result := Cpu.PC.W;
    rkA_: Result := Cpu.A_;
    rkF_: Result := Cpu.F_;
    rkAF_: Result := (Cpu.A_ shl 8) or Cpu.F_;
    rkBC_: Result := Cpu.BC_.W;
    rkDE_: Result := Cpu.DE_.W;
    rkHL_: Result := Cpu.HL_.W;
    rkIFF1: Result := Ord(Cpu.IFF1);
    rkIFF2: Result := Ord(Cpu.IFF2);
  else
    Result := Cpu.IM;
  end;
end;

function THitsNode.Eval(Cpu: TZ80): Integer;
begin
  Result := Hits^;
end;

destructor TPeekNode.Destroy;
begin
  Child.Free;
  inherited Destroy;
end;

function TPeekNode.Eval(Cpu: TZ80): Integer;
begin
  if Assigned(ConditionPeek) then
    Result := ConditionPeek(Word(Child.Eval(Cpu)))
  else
    Result := 0;
end;

function TFlagNode.Eval(Cpu: TZ80): Integer;
begin
  Result := Ord((Cpu.F and Mask) <> 0);
end;

destructor TNotNode.Destroy;
begin
  Child.Free;
  inherited Destroy;
end;

function TNotNode.Eval(Cpu: TZ80): Integer;
begin
  // Logical NOT: conditions are 0 (false) or anything else (true)
  Result := Ord(Child.Eval(Cpu) = 0);
end;

destructor TNegNode.Destroy;
begin
  Child.Free;
  inherited Destroy;
end;

function TNegNode.Eval(Cpu: TZ80): Integer;
begin
  if Wide then Result := -Child.Eval(Cpu) and $FFFF else Result := -Child.Eval(Cpu) and $FF;
end;

destructor TBinNode.Destroy;
begin
  Left.Free;
  Right.Free;
  inherited Destroy;
end;

function TBinNode.Eval(Cpu: TZ80): Integer;
var
  L, R: Integer;
begin
  L := Left.Eval(Cpu);
  // AND/OR short-circuit like Pascal's boolean evaluation
  if (Op = boAnd) and (L = 0) then Exit(0);
  if (Op = boOr) and (L <> 0) then Exit(1);
  R := Right.Eval(Cpu);
  case Op of
    boOr: Result := Ord(R <> 0);
    boXor: Result := Ord((L <> 0) xor (R <> 0));
    boAnd: Result := Ord(R <> 0);
    boEq: Result := Ord(L = R);
    boNe: Result := Ord(L <> R);
    boLt: Result := Ord(L < R);
    boGt: Result := Ord(L > R);
    boLe: Result := Ord(L <= R);
    boGe: Result := Ord(L >= R);
    boAdd: Result := L + R;
    boSub: Result := L - R;
    boBitOr: Result := L or R;
    boMul: Result := L * R;
    boDiv: if R = 0 then Result := 0 else Result := L div R;
    boMod: if R = 0 then Result := 0 else Result := L mod R;
  else
    Result := L and R;
  end;
  // Arithmetic wraps like the Z80's registers
  if Op >= boAdd then
  begin
    if Wide then Result := Result and $FFFF else Result := Result and $FF;
  end;
end;

{ TBreakCondition }

destructor TBreakCondition.Destroy;
begin
  FRoot.Free;
  inherited Destroy;
end;

function TBreakCondition.Holds(Cpu: TZ80): Boolean;
begin
  Inc(FHits);
  Result := FRoot.Eval(Cpu) <> 0;
end;

{ Parser: recursive descent over the text }

type
  TParser = class
    S: string;
    P: Integer;
    Hits: PInteger;       // T counter of the condition being compiled
    UsesHits: Boolean;
    procedure SkipSpaces;
    function Peek: Char;
    function Word: string;          // identifier-like token at P (not consumed)
    function SymbolWord: string;    // a symbol name at P: also dots (not consumed)
    function TryKeyword(const K: string): Boolean;
    function TryOp(const Op: string): Boolean;
    function ParseOr: TExprNode;
    function ParseAnd: TExprNode;
    function ParseNot: TExprNode;
    function ParseCompare: TExprNode;
    function ParseAdd: TExprNode;
    function ParseMul: TExprNode;
    function ParsePrimary: TExprNode;
  end;

function MakeBin(Op: TBinOp; L, R: TExprNode): TExprNode;
var
  N: TBinNode;
begin
  N := TBinNode.Create;
  N.Op := Op;
  N.Left := L;
  N.Right := R;
  // Arithmetic is as wide as its widest side; comparisons and logic give 0/1
  N.Wide := (Op >= boAdd) and (L.Wide or R.Wide);
  Result := N;
end;

function MakeConst(V: Integer): TExprNode;
begin
  Result := TConstNode.Create;
  TConstNode(Result).Value := V;
  Result.Wide := V > $FF;
end;

procedure TParser.SkipSpaces;
begin
  while (P <= Length(S)) and (S[P] in [' ', #9]) do Inc(P);
end;

function TParser.Peek: Char;
begin
  SkipSpaces;
  if P <= Length(S) then Result := S[P] else Result := #0;
end;

function TParser.Word: string;
var
  Q: Integer;
begin
  SkipSpaces;
  Q := P;
  while (Q <= Length(S)) and (S[Q] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) do Inc(Q);
  if (Q <= Length(S)) and (S[Q] = '''') then Inc(Q);   // alternate register: BC'
  Result := UpperCase(Copy(S, P, Q - P));
end;

function TParser.SymbolWord: string;
var
  Q: Integer;
begin
  SkipSpaces;
  Q := P;
  while (Q <= Length(S)) and (S[Q] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '.', '?', '!']) do Inc(Q);
  Result := Copy(S, P, Q - P);
end;

function TParser.TryKeyword(const K: string): Boolean;
begin
  Result := Word = K;
  if Result then Inc(P, Length(K));
end;

function TParser.TryOp(const Op: string): Boolean;
begin
  SkipSpaces;
  Result := Copy(S, P, Length(Op)) = Op;
  if Result then Inc(P, Length(Op));
end;

function TParser.ParseOr: TExprNode;
begin
  Result := ParseAnd;
  try
    repeat
      if TryKeyword('OR') then Result := MakeBin(boOr, Result, ParseAnd)
      else if TryKeyword('XOR') then Result := MakeBin(boXor, Result, ParseAnd)
      else Break;
    until False;
  except
    Result.Free;
    raise;
  end;
end;

function TParser.ParseAnd: TExprNode;
begin
  Result := ParseNot;
  try
    while TryKeyword('AND') do Result := MakeBin(boAnd, Result, ParseNot);
  except
    Result.Free;
    raise;
  end;
end;

function TParser.ParseNot: TExprNode;
var
  N: TNotNode;
begin
  if TryKeyword('NOT') then
  begin
    N := TNotNode.Create;
    try
      N.Child := ParseNot();   // () needed: the bare name is the result variable
    except
      N.Free;
      raise;
    end;
    Result := N;
  end
  else
    Result := ParseCompare;
end;

function TParser.ParseCompare: TExprNode;
var
  Op: TBinOp;
begin
  Result := ParseAdd;
  try
    // Two-character operators first
    if TryOp('<>') then Op := boNe
    else if TryOp('<=') then Op := boLe
    else if TryOp('>=') then Op := boGe
    else if TryOp('=') then Op := boEq
    else if TryOp('<') then Op := boLt
    else if TryOp('>') then Op := boGt
    else Exit;
    Result := MakeBin(Op, Result, ParseAdd);
  except
    Result.Free;
    raise;
  end;
end;

function TParser.ParseAdd: TExprNode;
begin
  Result := ParseMul;
  try
    repeat
      if TryOp('+') then Result := MakeBin(boAdd, Result, ParseMul)
      else if TryOp('-') then Result := MakeBin(boSub, Result, ParseMul)
      else if TryOp('|') then Result := MakeBin(boBitOr, Result, ParseMul)
      else Break;
    until False;
  except
    Result.Free;
    raise;
  end;
end;

function TParser.ParseMul: TExprNode;
begin
  Result := ParsePrimary;
  try
    repeat
      if TryOp('*') then Result := MakeBin(boMul, Result, ParsePrimary)
      else if TryOp('/') then Result := MakeBin(boDiv, Result, ParsePrimary)
      else if TryOp('&') then Result := MakeBin(boBitAnd, Result, ParsePrimary)
      else if TryKeyword('MOD') then Result := MakeBin(boMod, Result, ParsePrimary)
      else Break;
    until False;
  except
    Result.Free;
    raise;
  end;
end;

function TParser.ParsePrimary: TExprNode;
const
  FLAGS: array[0..10] of string = ('S', 'Z', '5', 'H', '3', 'P', 'V', 'PV', 'N', 'C', 'Y');
  MASKS: array[0..10] of Byte = ($80, $40, $20, $10, $08, $04, $04, $04, $02, $01, $20);
var
  W, Num: string;
  R: TRegKind;
  I, V: Integer;
  C: TConstNode;
  RN: TRegNode;
  FN: TFlagNode;
  NN: TNegNode;
  PN: TPeekNode;
  Addr: Word;
begin
  case Peek of
    '(':
      begin
        Inc(P);
        Result := ParseOr;
        if not TryOp(')') then
        begin
          Result.Free;
          raise EExprError.Create('missing ")"');
        end;
        Exit;
      end;
    '-':
      begin
        Inc(P);
        NN := TNegNode.Create;
        try
          NN.Child := ParsePrimary();
          NN.Wide := NN.Child.Wide;
        except
          NN.Free;
          raise;
        end;
        Exit(NN);
      end;
    '#':
      begin
        Inc(P);
        W := Word;
        for I := 0 to High(FLAGS) do
          if W = FLAGS[I] then
          begin
            Inc(P, Length(W));
            FN := TFlagNode.Create;
            FN.Mask := MASKS[I];
            Exit(FN);
          end;
        // Any other #name is a symbol (names may contain dots: main.loop)
        W := SymbolWord;
        if (W <> '') and Assigned(ConditionSymbol) and ConditionSymbol(W, Addr) then
        begin
          Inc(P, Length(W));
          Exit(MakeConst(Addr));
        end;
        raise EExprError.CreateFmt('"#%s" is not a flag (#S #Z #5 #H #3 #P #N #C) or a symbol', [W]);
      end;
    '@':
      begin
        Inc(P);
        PN := TPeekNode.Create;
        try
          PN.Child := ParsePrimary();
        except
          PN.Free;
          raise;
        end;
        Exit(PN);
      end;
    '.':
      begin
        // Decimal number
        Inc(P);
        W := Word;
        V := StrToIntDef(W, -1);
        if (W = '') or (V < 0) or (W[1] in ['A'..'Z']) then
          raise EExprError.Create('bad decimal number after "."');
        Inc(P, Length(W));
        Exit(MakeConst(V));
      end;
    '$':
      begin
        Inc(P);
        W := Word;
        V := StrToIntDef('$' + W, -1);
        if (W = '') or (V < 0) then raise EExprError.Create('bad hex number after "$"');
        Inc(P, Length(W));
        Exit(MakeConst(V));
      end;
    #0:
      raise EExprError.Create('unexpected end of condition');
  end;

  W := Word;
  if W = '' then raise EExprError.CreateFmt('unexpected "%s"', [Peek]);
  if W = 'T' then
  begin
    Inc(P);
    UsesHits := True;
    Result := THitsNode.Create;
    THitsNode(Result).Hits := Hits;
    Result.Wide := True;
    Exit;
  end;
  // Register names take precedence over hex numbers
  for R := Low(TRegKind) to High(TRegKind) do
    if W = REG_NAMES[R] then
    begin
      Inc(P, Length(W));
      RN := TRegNode.Create;
      RN.Reg := R;
      RN.Wide := R in [rkAF, rkBC, rkDE, rkHL, rkIX, rkIY, rkSP, rkPC, rkAF_, rkBC_, rkDE_, rkHL_];
      Exit(RN);
    end;
  if (W = 'AND') or (W = 'OR') or (W = 'XOR') or (W = 'NOT') or (W = 'MOD') then
    raise EExprError.CreateFmt('value expected before "%s"', [W]);
  // Then a symbol (a name starting with a digit is always a number)
  if not (W[1] in ['0'..'9']) and Assigned(ConditionSymbol) and ConditionSymbol(W, Addr) then
  begin
    Inc(P, Length(W));
    Exit(MakeConst(Addr));
  end;
  // Hex number, with an optional "h" suffix
  Num := W;
  if (Length(Num) > 1) and (Num[Length(Num)] = 'H') then Delete(Num, Length(Num), 1);
  V := StrToIntDef('$' + Num, -1);
  if (V < 0) or (V > $FFFF) then
    raise EExprError.CreateFmt('"%s" is not a register, a symbol or a hex number', [W]);
  Inc(P, Length(W));
  Result := MakeConst(V);
end;

function CompileCondition(const Text: string; out Error: string): TBreakCondition;
var
  Parser: TParser;
  Root: TExprNode;
begin
  Result := nil;
  Error := '';
  Parser := TParser.Create;
  Result := TBreakCondition.Create;
  try
    Parser.S := Text;
    Parser.P := 1;
    Parser.Hits := @Result.FHits;
    try
      Root := Parser.ParseOr;
      if Parser.Peek <> #0 then
      begin
        Error := Format('unexpected "%s" at position %d', [Copy(Text, Parser.P, 10), Parser.P]);
        Root.Free;
        FreeAndNil(Result);
        Exit;
      end;
      Result.FText := Trim(Text);
      Result.FRoot := Root;
      Result.FUsesHits := Parser.UsesHits;
    except
      on E: EExprError do
      begin
        Error := E.Message;
        FreeAndNil(Result);
      end;
    end;
  finally
    Parser.Free;
  end;
end;

end.

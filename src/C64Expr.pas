{ C64Expr: expressions of the 6510 debugger (breakpoint conditions, the addresses typed in its boxes): "A=3 AND X>10",
  "@C000=FF", "#Z=1 OR PC>=E000".

  - Numbers are hex ("C000", "$C000"); with a dot they are decimal (".30").
  - Registers: A X Y SP PC; flags with "#": #N #V #B #D #I #Z #C (worth 0 or 1).
  - @x: the byte of memory at address x ("@(PC+1)=0").
  - T: how many times the breakpoint has been reached (the count starts when the condition is set).
  - Operators, lowest to highest precedence: OR XOR, AND, NOT, = <> < > <= >=, + - |, * / MOD &, the prefixes - and @.
    Comparisons bind tighter than AND/OR. Parentheses group. }
unit C64Expr;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

const
  P_C_ = $01; P_Z_ = $02; P_I_ = $04; P_D_ = $08; P_B_ = $10; P_V_ = $40; P_N_ = $80;

type
  TPeekFunc = function(Addr: Word): Byte of object;

  { The CPU's state an expression reads }
  TExprState = record
    A, X, Y, SP, P: Byte;
    PC: Word;
    Hits: Integer;
    Peek: TPeekFunc;
  end;

  TNode = class
  public
    function Eval(const S: TExprState): Integer; virtual; abstract;
    destructor Destroy; override;
  end;

  TC64Condition = class
  private
    FText: string;
    FRoot: TNode;
    FHits: Integer;
    FUsesHits: Boolean;
  public
    destructor Destroy; override;
    { The breakpoint has been reached: count it and say whether the condition holds }
    function Holds(var S: TExprState): Boolean;
    property Text: string read FText;
    property Hits: Integer read FHits;
    property UsesHits: Boolean read FUsesHits;
  end;

{ nil (and Error says why) if the text is not a condition }
function CompileC64Condition(const Text: string; out Error: string): TC64Condition;
{ The value of a one-off expression (an address in a box) }
function EvalC64Expression(const Text: string; const S: TExprState; out Value: Integer; out Error: string): Boolean;

implementation

type
  EExpr = class(Exception);

  TConst = class(TNode)
    V: Integer;
    function Eval(const S: TExprState): Integer; override;
  end;

  TReg = class(TNode)
    Name: string;
    function Eval(const S: TExprState): Integer; override;
  end;

  TFlag = class(TNode)
    Mask: Byte;
    function Eval(const S: TExprState): Integer; override;
  end;

  THitsNode = class(TNode)
    function Eval(const S: TExprState): Integer; override;
  end;

  TUnary = class(TNode)
    Op: Char;               // '@', '-', '!'
    Child: TNode;
    function Eval(const S: TExprState): Integer; override;
    destructor Destroy; override;
  end;

  TBinary = class(TNode)
    Op: string;
    L, R: TNode;
    function Eval(const S: TExprState): Integer; override;
    destructor Destroy; override;
  end;

destructor TNode.Destroy;
begin
  inherited Destroy;
end;

function TConst.Eval(const S: TExprState): Integer;
begin
  Result := V;
end;

function TReg.Eval(const S: TExprState): Integer;
begin
  if Name = 'A' then Result := S.A
  else if Name = 'X' then Result := S.X
  else if Name = 'Y' then Result := S.Y
  else if Name = 'SP' then Result := S.SP
  else if Name = 'P' then Result := S.P
  else Result := S.PC;
end;

function TFlag.Eval(const S: TExprState): Integer;
begin
  Result := Ord((S.P and Mask) <> 0);
end;

function THitsNode.Eval(const S: TExprState): Integer;
begin
  Result := S.Hits;
end;

destructor TUnary.Destroy;
begin
  Child.Free;
  inherited Destroy;
end;

function TUnary.Eval(const S: TExprState): Integer;
var
  V: Integer;
begin
  V := Child.Eval(S);
  case Op of
    '@': if Assigned(S.Peek) then Result := S.Peek(Word(V)) else Result := 0;
    '-': Result := -V;
  else
    Result := Ord(V = 0);
  end;
end;

destructor TBinary.Destroy;
begin
  L.Free;
  R.Free;
  inherited Destroy;
end;

function TBinary.Eval(const S: TExprState): Integer;
var
  A, B: Integer;
begin
  A := L.Eval(S);
  B := R.Eval(S);
  if Op = 'OR' then Result := Ord((A <> 0) or (B <> 0))
  else if Op = 'XOR' then Result := Ord((A <> 0) <> (B <> 0))
  else if Op = 'AND' then Result := Ord((A <> 0) and (B <> 0))
  else if Op = '=' then Result := Ord(A = B)
  else if Op = '<>' then Result := Ord(A <> B)
  else if Op = '<' then Result := Ord(A < B)
  else if Op = '>' then Result := Ord(A > B)
  else if Op = '<=' then Result := Ord(A <= B)
  else if Op = '>=' then Result := Ord(A >= B)
  else if Op = '+' then Result := A + B
  else if Op = '-' then Result := A - B
  else if Op = '|' then Result := A or B
  else if Op = '*' then Result := A * B
  else if Op = '/' then
  begin
    if B = 0 then Result := 0 else Result := A div B;
  end
  else if Op = 'MOD' then
  begin
    if B = 0 then Result := 0 else Result := A mod B;
  end
  else Result := A and B;
end;

{ The parser }
type
  TParser = class
  private
    FText: string;
    FPos: Integer;
    FUsesHits: Boolean;
    procedure SkipBlanks;
    function Peek: Char;
    function Word_: string;
    function Accept(const Op: string): Boolean;
    function ParseOr: TNode;
    function ParseAnd: TNode;
    function ParseNot: TNode;
    function ParseCompare: TNode;
    function ParseAdd: TNode;
    function ParseMul: TNode;
    function ParsePrefix: TNode;
    function ParseAtom: TNode;
    function Bin(const Op: string; L, R: TNode): TNode;
  public
    constructor Create(const AText: string);
    function Parse: TNode;
    property UsesHits: Boolean read FUsesHits;
  end;

constructor TParser.Create(const AText: string);
begin
  inherited Create;
  FText := AText;
  FPos := 1;
end;

procedure TParser.SkipBlanks;
begin
  while (FPos <= Length(FText)) and (FText[FPos] in [' ', #9]) do Inc(FPos);
end;

function TParser.Peek: Char;
begin
  SkipBlanks;
  if FPos <= Length(FText) then Result := FText[FPos] else Result := #0;
end;

function TParser.Word_: string;
var
  P: Integer;
begin
  SkipBlanks;
  P := FPos;
  while (P <= Length(FText)) and (FText[P] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) do Inc(P);
  Result := UpperCase(Copy(FText, FPos, P - FPos));
end;

function TParser.Bin(const Op: string; L, R: TNode): TNode;
var
  B: TBinary;
begin
  B := TBinary.Create;
  B.Op := Op;
  B.L := L;
  B.R := R;
  Result := B;
end;

{ A word-operator (OR, AND...) or a symbol operator at the position; moves past it }
function TParser.Accept(const Op: string): Boolean;
var
  W: string;
begin
  SkipBlanks;
  if Op[1] in ['A'..'Z'] then
  begin
    W := Word_;
    Result := W = Op;
    if Result then Inc(FPos, Length(Op));
  end
  else
  begin
    Result := Copy(FText, FPos, Length(Op)) = Op;
    if Result then Inc(FPos, Length(Op));
  end;
end;

function TParser.ParseOr: TNode;
var
  L: TNode;
begin
  L := ParseAnd;
  while True do
  begin
    if Accept('OR') then L := Bin('OR', L, ParseAnd)
    else if Accept('XOR') then L := Bin('XOR', L, ParseAnd)
    else Break;
  end;
  Result := L;
end;

function TParser.ParseAnd: TNode;
var
  L: TNode;
begin
  L := ParseNot;
  while Accept('AND') do L := Bin('AND', L, ParseNot);
  Result := L;
end;

function TParser.ParseNot: TNode;
var
  U: TUnary;
begin
  if Accept('NOT') then
  begin
    U := TUnary.Create;
    U.Op := '!';
    U.Child := ParseNot;
    Result := U;
  end
  else
    Result := ParseCompare;
end;

function TParser.ParseCompare: TNode;
var
  L: TNode;
begin
  L := ParseAdd;
  while True do
  begin
    if Accept('<>') then L := Bin('<>', L, ParseAdd)
    else if Accept('<=') then L := Bin('<=', L, ParseAdd)
    else if Accept('>=') then L := Bin('>=', L, ParseAdd)
    else if Accept('!=') then L := Bin('<>', L, ParseAdd)
    else if Accept('==') then L := Bin('=', L, ParseAdd)
    else if Accept('=') then L := Bin('=', L, ParseAdd)
    else if Accept('<') then L := Bin('<', L, ParseAdd)
    else if Accept('>') then L := Bin('>', L, ParseAdd)
    else Break;
  end;
  Result := L;
end;

function TParser.ParseAdd: TNode;
var
  L: TNode;
begin
  L := ParseMul;
  while True do
  begin
    if Accept('+') then L := Bin('+', L, ParseMul)
    else if Accept('-') then L := Bin('-', L, ParseMul)
    else if Accept('|') then L := Bin('|', L, ParseMul)
    else Break;
  end;
  Result := L;
end;

function TParser.ParseMul: TNode;
var
  L: TNode;
begin
  L := ParsePrefix;
  while True do
  begin
    if Accept('*') then L := Bin('*', L, ParsePrefix)
    else if Accept('/') then L := Bin('/', L, ParsePrefix)
    else if Accept('MOD') then L := Bin('MOD', L, ParsePrefix)
    else if Accept('&') then L := Bin('&', L, ParsePrefix)
    else Break;
  end;
  Result := L;
end;

function TParser.ParsePrefix: TNode;
var
  U: TUnary;
begin
  if Accept('-') then
  begin
    U := TUnary.Create;
    U.Op := '-';
    U.Child := ParsePrefix;
    Result := U;
  end
  else if Accept('@') then
  begin
    U := TUnary.Create;
    U.Op := '@';
    U.Child := ParsePrefix;
    Result := U;
  end
  else
    Result := ParseAtom;
end;

function TParser.ParseAtom: TNode;
var
  W: string;
  C: TConst;
  R: TReg;
  F: TFlag;
  V: Integer;
  Dec_: Boolean;
begin
  SkipBlanks;
  if Peek = '(' then
  begin
    Inc(FPos);
    Result := ParseOr;
    if Peek <> ')' then raise EExpr.Create('A ")" is missing');
    Inc(FPos);
    Exit;
  end;
  if Peek = '#' then
  begin
    Inc(FPos);
    W := Word_;
    Inc(FPos, Length(W));
    F := TFlag.Create;
    if W = 'N' then F.Mask := P_N_
    else if W = 'V' then F.Mask := P_V_
    else if W = 'B' then F.Mask := P_B_
    else if W = 'D' then F.Mask := P_D_
    else if W = 'I' then F.Mask := P_I_
    else if W = 'Z' then F.Mask := P_Z_
    else if W = 'C' then F.Mask := P_C_
    else
    begin
      F.Free;
      raise EExpr.Create('Unknown flag #' + W + ' (N V B D I Z C)');
    end;
    Result := F;
    Exit;
  end;
  if Peek = '$' then
  begin
    Inc(FPos);
    W := Word_;
    Inc(FPos, Length(W));
    if (W = '') or not TryStrToInt('$' + W, V) then raise EExpr.Create('Not a hexadecimal number: $' + W);
    C := TConst.Create;
    C.V := V;
    Result := C;
    Exit;
  end;
  Dec_ := False;
  if Peek = '.' then
  begin
    Dec_ := True;
    Inc(FPos);
  end;
  W := Word_;
  if W = '' then raise EExpr.Create('A value is missing');
  Inc(FPos, Length(W));
  if Dec_ then
  begin
    if not TryStrToInt(W, V) then raise EExpr.Create('Not a decimal number: .' + W);
    C := TConst.Create;
    C.V := V;
    Result := C;
    Exit;
  end;
  if (W = 'A') or (W = 'X') or (W = 'Y') or (W = 'SP') or (W = 'PC') or (W = 'P') then
  begin
    R := TReg.Create;
    R.Name := W;
    Result := R;
    Exit;
  end;
  if W = 'T' then
  begin
    FUsesHits := True;
    Result := THitsNode.Create;
    Exit;
  end;
  if not TryStrToInt('$' + W, V) then raise EExpr.Create('Not a register or a number: ' + W);
  C := TConst.Create;
  C.V := V;
  Result := C;
end;

function TParser.Parse: TNode;
begin
  Result := ParseOr;
  SkipBlanks;
  if FPos <= Length(FText) then
  begin
    Result.Free;
    raise EExpr.Create('Unexpected "' + Copy(FText, FPos, 8) + '"');
  end;
end;

destructor TC64Condition.Destroy;
begin
  FRoot.Free;
  inherited Destroy;
end;

function TC64Condition.Holds(var S: TExprState): Boolean;
begin
  Inc(FHits);
  S.Hits := FHits;
  Result := FRoot.Eval(S) <> 0;
end;

function CompileC64Condition(const Text: string; out Error: string): TC64Condition;
var
  P: TParser;
  Root: TNode;
begin
  Result := nil;
  Error := '';
  P := TParser.Create(Text);
  try
    try
      Root := P.Parse;
    except
      on E: EExpr do
      begin
        Error := E.Message;
        Exit;
      end;
    end;
    Result := TC64Condition.Create;
    Result.FText := Text;
    Result.FRoot := Root;
    Result.FUsesHits := P.UsesHits;
  finally
    P.Free;
  end;
end;

function EvalC64Expression(const Text: string; const S: TExprState; out Value: Integer; out Error: string): Boolean;
var
  P: TParser;
  Root: TNode;
begin
  Result := False;
  Error := '';
  Value := 0;
  P := TParser.Create(Text);
  try
    try
      Root := P.Parse;
    except
      on E: EExpr do
      begin
        Error := E.Message;
        Exit;
      end;
    end;
    Value := Root.Eval(S);
    Root.Free;
    Result := True;
  finally
    P.Free;
  end;
end;

end.

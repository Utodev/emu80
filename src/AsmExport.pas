{ AsmExport: a memory range disassembled as source for sjasmplus, which
  assembles back to the same bytes. Jump, call and memory targets get a
  label (the symbol at that address, or Lxxxx inside the range); labels
  outside the range are defined with EQU. Encodings an assembler would not
  produce (redundant prefixes, undocumented ED duplicates, DDCB copies to
  a register...) are written as DB with the instruction in a comment. }
unit AsmExport;

{$mode objfpc}{$H+}
{$R-}{$Q-}

interface

uses
  Classes, SysUtils, Disasm;

type
  { The symbol for Addr ('' = none); Kind says how the value is used }
  TLabelFunc = function(Addr: Word; Kind: TOperandKind): string of object;

{ Source for Len bytes from Start }
function ExportAsm(Start: Word; Len: Integer; Peek: TPeekFunc; LabelFor: TLabelFunc): TStringList;

implementation

type
  TLine = record
    Addr: Word;
    Len: Integer;
    Text: string;
    Operand: Integer;
    Kind: TOperandKind;
    Raw: Boolean;      // written as DB
  end;

{ A name sjasmplus accepts as a label }
function CleanName(const S: string): string;
var
  Ch: Char;
begin
  Result := '';
  for Ch in S do
    if Ch in ['A'..'Z', 'a'..'z', '0'..'9', '_', '.', '?', '!', '@'] then Result := Result + Ch
    else Result := Result + '_';
  if (Result = '') or (Result[1] in ['0'..'9', '.']) then Result := '_' + Result;
  // sjasmplus operator keywords can't be labels
  if Pos(',' + LowerCase(Result) + ',', ',abs,and,high,low,mod,norel,not,or,shl,shr,xor,') > 0 then
    Result := Result + '_';
end;

{ Whether an assembler writes this instruction back with the same bytes }
function Canonical(Addr: Word; Peek: TPeekFunc; const Text: string; Len: Integer): Boolean;
const
  ED_OK: set of Byte = [$40..$6F, $72..$7B, $A0..$A3, $A8..$AB, $B0..$B3, $B8..$BB];
  ED_DUPS: set of Byte = [$4C, $4E, $54, $55, $5C, $5D, $63, $64, $65, $66, $6B, $6C, $6D, $6E,
    $74, $75, $76, $77];
var
  Op, Op2: Byte;
begin
  Result := False;
  if Pos('*', Text) > 0 then Exit;
  Op := Peek(Addr);
  if Op = $ED then
  begin
    Op2 := Peek(Word(Addr + 1));
    Exit((Op2 in ED_OK) and not (Op2 in ED_DUPS));
  end;
  if Op in [$DD, $FD] then
  begin
    // The prefix must be used (IX/IY in the text), and DDCB ops that also
    // copy the result to a register are left as bytes
    if (Pos('IX', Text) = 0) and (Pos('IY', Text) = 0) then Exit;
    if (Peek(Word(Addr + 1)) = $CB) and (Pos('),', Text) > 0) then Exit;
    // LD IXH,(IX+d) and the like can't exist; DD 66/6E etc. read H/L
    if (Pos('(IX', Text) > 0) or (Pos('(IY', Text) > 0) then
      if (Pos('IXH', Text) > 0) or (Pos('IXL', Text) > 0) or (Pos('IYH', Text) > 0) or
         (Pos('IYL', Text) > 0) then Exit;
  end;
  Result := Len > 0;
end;

function HexByte(V: Byte): string;
begin
  Result := '$' + IntToHex(V, 2);
end;

function ExportAsm(Start: Word; Len: Integer; Peek: TPeekFunc; LabelFor: TLabelFunc): TStringList;
var
  Lines: array of TLine;
  Starts: TBits;           // instruction starts, by offset from Start
  Names: TStringList;      // address (hex) = label, for every label used
  Defined: TStringList;    // labels already given a value
  Used: TStringList;       // every label name given out (unique)
  N, Off, I, K, ILen, Operand: Integer;
  Text, Name, Bytes: string;
  Kind: TOperandKind;
  A: Word;

  { Name for Addr made unique: another address with the same symbol gets
    the address appended }
  function Unique(const AName: string; Addr: Integer): string;
  begin
    Result := AName;
    if Used.IndexOf(Result) >= 0 then Result := AName + '_' + IntToHex(Addr, 4);
    Used.Add(Result);
  end;

  function InRange(Addr: Integer): Boolean;
  begin
    Off := Integer(Word(Addr - Start));
    Result := Off < Len;
  end;

  { The label for a target ('' = keep the number) }
  function TargetName(Addr: Integer; AKind: TOperandKind): string;
  var
    Key: string;
  begin
    Key := IntToHex(Addr, 4);
    Result := Names.Values[Key];
    if Result <> '' then Exit;
    Result := LabelFor(Addr, AKind);
    if Result <> '' then Result := CleanName(Result)
    else if (AKind in [okJump, okMemory]) and InRange(Addr) and Starts[Integer(Word(Addr - Start))] then
      Result := 'L' + Key;
    if Result <> '' then
    begin
      Result := Unique(Result, Addr);
      Names.Values[Key] := Result;
    end;
  end;

begin
  Result := TStringList.Create;
  Names := TStringList.Create;
  Defined := TStringList.Create;
  Used := TStringList.Create;
  Used.Sorted := True;
  Used.CaseSensitive := False;
  Starts := TBits.Create(Len + 1);
  try
    // Pass 1: the instructions; one running past the end becomes bytes
    Lines := nil;
    Off := 0;
    while Off < Len do
    begin
      A := Word(Start + Off);
      Text := DisassembleEx(A, Peek, ILen, Operand, Kind);
      SetLength(Lines, Length(Lines) + 1);
      N := High(Lines);
      Lines[N].Addr := A;
      Lines[N].Operand := Operand;
      Lines[N].Kind := Kind;
      if Off + ILen > Len then
      begin
        ILen := Len - Off;
        Lines[N].Raw := True;
      end
      else
        Lines[N].Raw := not Canonical(A, Peek, Text, ILen);
      Lines[N].Len := ILen;
      Lines[N].Text := Text;
      Starts[Off] := True;
      Inc(Off, ILen);
    end;

    // Pass 2: the labels of the targets
    for N := 0 to High(Lines) do
      if not Lines[N].Raw and (Lines[N].Operand >= 0) then
      begin
        Name := TargetName(Lines[N].Operand, Lines[N].Kind);
        if Name <> '' then
          Lines[N].Text := StringReplace(Lines[N].Text, '$' + IntToHex(Lines[N].Operand, 4), Name, []);
      end;
    // Symbols at instruction starts are shown even if nothing refers to them
    for N := 0 to High(Lines) do
      if Names.Values[IntToHex(Lines[N].Addr, 4)] = '' then
      begin
        Name := LabelFor(Lines[N].Addr, okJump);
        if Name <> '' then
          Names.Values[IntToHex(Lines[N].Addr, 4)] := Unique(CleanName(Name), Lines[N].Addr);
      end;

    Result.Add(Format('; Disassembled by pzx: %.4X-%.4X (%d bytes), for sjasmplus',
      [Start, Word(Start + Len - 1), Len]));
    Result.Add('');
    // Labels that are not at an instruction start of the range
    for I := 0 to Names.Count - 1 do
    begin
      K := StrToInt('$' + Names.Names[I]);
      if not (InRange(K) and Starts[Integer(Word(K - Start))]) then
      begin
        Result.Add(Format('%s EQU $%s', [Names.ValueFromIndex[I], Names.Names[I]]));
        Defined.Add(Names.ValueFromIndex[I]);
      end;
    end;
    if Defined.Count > 0 then Result.Add('');
    Result.Add(Format(#9'ORG $%.4X', [Start]));
    Result.Add('');
    for N := 0 to High(Lines) do
    begin
      Name := Names.Values[IntToHex(Lines[N].Addr, 4)];
      if (Name <> '') and (Defined.IndexOf(Name) < 0) then
      begin
        Result.Add(Name + ':');
        Defined.Add(Name);
      end;
      if Lines[N].Raw then
      begin
        Bytes := '';
        for K := 0 to Lines[N].Len - 1 do
        begin
          if K > 0 then Bytes := Bytes + ',';
          Bytes := Bytes + HexByte(Peek(Word(Lines[N].Addr + K)));
        end;
        Result.Add(Format(#9'DB %s'#9'; %.4X %s', [Bytes, Lines[N].Addr, Lines[N].Text]));
      end
      else
        Result.Add(Format(#9'%s'#9'; %.4X', [Lines[N].Text, Lines[N].Addr]));
    end;
  finally
    Starts.Free;
    Names.Free;
    Defined.Free;
    Used.Free;
  end;
end;

end.

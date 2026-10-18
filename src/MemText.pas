{ MemText: memory as text for the debugger's export and import: "$XX"
  values separated by commas, 16 per line. }
unit MemText;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes;

{ Lines of "$3E,$01,..." (each line but the last ends with a comma) }
function FormatValues(const Data: array of Byte): string;
{ Values of such a text; spaces and line breaks don't matter. False with the
  reason if a value is not "$" and one or two hex digits. }
function ParseValues(const Text: string; out Values: TBytes; out Error: string): Boolean;

implementation

function FormatValues(const Data: array of Byte): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(Data) do
  begin
    Result := Result + '$' + IntToHex(Data[I], 2);
    if I < High(Data) then
    begin
      Result := Result + ',';
      if (I + 1) mod 16 = 0 then Result := Result + LineEnding;
    end;
  end;
  Result := Result + LineEnding;
end;

function ParseValues(const Text: string; out Values: TBytes; out Error: string): Boolean;
var
  S, Tok: string;
  I, P, N, V: Integer;
begin
  Result := False;
  Values := nil;
  Error := '';
  SetLength(S, Length(Text));
  N := 0;
  for I := 1 to Length(Text) do
    if not (Text[I] in [' ', #9, #13, #10]) then
    begin
      Inc(N);
      S[N] := Text[I];
    end;
  SetLength(S, N);
  if S = '' then
  begin
    Error := 'the file has no values';
    Exit;
  end;
  if S[Length(S)] = ',' then Delete(S, Length(S), 1);
  SetLength(Values, Length(S) div 2 + 1);
  N := 0;
  P := 1;
  while P <= Length(S) + 1 do
  begin
    I := P;
    while (P <= Length(S)) and (S[P] <> ',') do Inc(P);
    Tok := Copy(S, I, P - I);
    V := -1;
    if (Length(Tok) in [2, 3]) and (Tok[1] = '$') then V := StrToIntDef(Tok, -1);
    if (V < 0) or (V > 255) then
    begin
      Error := Format('value %d is "%s": expected $ and one or two hex digits', [N + 1, Tok]);
      Values := nil;
      Exit;
    end;
    Values[N] := V;
    Inc(N);
    Inc(P);   // past the comma
  end;
  SetLength(Values, N);
  Result := True;
end;

end.

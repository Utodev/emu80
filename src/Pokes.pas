{ Pokes: parsing of POKE lists such as "35899,0 : 36000,201". }
unit Pokes;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TPokePair = record
    Addr: Word;
    Value: Byte;
  end;
  TPokeList = array of TPokePair;

{ Parse "address,value" pairs separated by ':' or ';'. Numbers are decimal,
  or hex with $, # or 0x. Returns False with Error set if the text is wrong. }
function ParsePokes(const Text: string; out Pokes: TPokeList; out Error: string): Boolean;

implementation

uses
  Lang;


function ParseNumber(S: string; out V: Integer): Boolean;
begin
  S := UpperCase(Trim(S));
  if (S <> '') and ((S[1] = '$') or (S[1] = '#')) then S := '$' + Copy(S, 2, MaxInt)
  else if Copy(S, 1, 2) = '0X' then S := '$' + Copy(S, 3, MaxInt);
  V := StrToIntDef(S, -1);
  Result := (S <> '') and (S <> '$') and (V >= 0);
end;

function ParsePokes(const Text: string; out Pokes: TPokeList; out Error: string): Boolean;
var
  Parts: TStringList;
  I, P, A, V: Integer;
  Item: string;
begin
  Result := False;
  Pokes := nil;
  Error := '';
  Parts := TStringList.Create;
  try
    Parts.Delimiter := ':';
    Parts.StrictDelimiter := True;
    Parts.DelimitedText := StringReplace(Text, ';', ':', [rfReplaceAll]);
    for I := 0 to Parts.Count - 1 do
    begin
      Item := Trim(Parts[I]);
      if Item = '' then Continue;
      // "POKE 35899,0" is accepted too
      if UpperCase(Copy(Item, 1, 4)) = 'POKE' then Item := Trim(Copy(Item, 5, MaxInt));
      P := Pos(',', Item);
      if P = 0 then
      begin
        Error := Format(_('"%s": expected address,value'), [Item]);
        Exit;
      end;
      if not ParseNumber(Copy(Item, 1, P - 1), A) or (A > $FFFF) then
      begin
        Error := Format(_('"%s": bad address'), [Item]);
        Exit;
      end;
      if not ParseNumber(Copy(Item, P + 1, MaxInt), V) or (V > 255) then
      begin
        Error := Format(_('"%s": value must be 0-255'), [Item]);
        Exit;
      end;
      SetLength(Pokes, Length(Pokes) + 1);
      Pokes[High(Pokes)].Addr := A;
      Pokes[High(Pokes)].Value := V;
    end;
  finally
    Parts.Free;
  end;
  if Length(Pokes) = 0 then
  begin
    Error := _('Nothing to POKE');
    Exit;
  end;
  Result := True;
end;

end.

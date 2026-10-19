{ memtexttest: the debugger's memory export/import text format. }
program memtexttest;

{$mode objfpc}{$H+}

uses
  SysUtils, MemText;

var
  Failures: Integer = 0;
  Data, Values: TBytes;
  Text, Err: string;
  I: Integer;

procedure Check(Ok: Boolean; const What: string);
begin
  if not Ok then
  begin
    WriteLn('FAIL  ', What);
    Inc(Failures);
  end;
end;

procedure CheckBad(const T: string);
begin
  Check(not ParseValues(T, Values, Err) and (Err <> ''), 'rejects "' + T + '"');
end;

begin
  SetLength(Data, 40);
  for I := 0 to High(Data) do Data[I] := I * 7;
  Text := FormatValues(Data);
  Check(Pos('$00,$07,$0E', Text) = 1, 'format starts with $00,$07,$0E');
  Check(Pos('$69,' + LineEnding + '$70', Text) > 0, 'line break after 16 values');
  Check(ParseValues(Text, Values, Err) and (Length(Values) = 40), 'round trip length');
  for I := 0 to High(Data) do
    if Values[I] <> Data[I] then Check(False, 'round trip value ' + IntToStr(I));
  Check(ParseValues('$1, $FF ,' + LineEnding + ' $a0,', Values, Err) and (Length(Values) = 3) and
    (Values[2] = $A0), 'spaces, lower case and a final comma');
  CheckBad('');
  CheckBad('$1,,$2');
  Check(ParseValues('12, $34,255,0', Values, Err) and (Length(Values) = 4) and (Values[0] = 12) and
    (Values[1] = $34) and (Values[2] = 255), 'decimal values');
  CheckBad('256,$34');
  CheckBad('1A,$34');
  CheckBad('-1');
  CheckBad('$123');
  CheckBad('$G1');
  CheckBad('$12;$34');
  CheckBad('$12 $34');
  if Failures = 0 then WriteLn('Memory export/import format: all passed')
  else WriteLn('Memory export/import format: ', Failures, ' failed');
  if Failures > 0 then Halt(1);
end.

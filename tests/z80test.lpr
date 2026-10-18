{ z80test: runs the FUSE Z80 core test suite (tests.in) against Z80Core and
  prints results in the tests.expected format, so the output can be diffed:

    z80test tests.in > out.txt && diff -i out.txt tests.expected

  The suite comes from the FUSE emulator (z80/tests/ in its source tree). }
program z80test;

{$mode objfpc}{$H+}
{$R-}{$Q-}

uses
  SysUtils, Classes, Z80Core;

type
  { Flat 64K RAM with no contention that logs every bus event. }
  TTestBus = class(TZ80Bus)
  public
    Memory: array[0..$FFFF] of Byte;
    procedure Contend(Addr: Word; Time: Integer; var T: Integer); override;
    procedure ContendNoMreq(Addr: Word; Time: Integer; var T: Integer); override;
    function ReadMem(Addr: Word; T: Integer): Byte; override;
    procedure WriteMem(Addr: Word; Value: Byte; T: Integer); override;
    function ReadPort(Port: Word; var T: Integer): Byte; override;
    procedure WritePort(Port: Word; Value: Byte; var T: Integer); override;
  end;

var
  Bus: TTestBus;
  Cpu: TZ80;
  Tokens: TStringList;
  TokenPos: Integer;
  Lines: TStringList;
  LinePos: Integer;

procedure Event(T: Integer; const Kind: string; Addr: Word);
begin
  WriteLn(Format('%5d %s %.4x', [T, Kind, Addr]));
end;

procedure EventData(T: Integer; const Kind: string; Addr: Word; Value: Byte);
begin
  WriteLn(Format('%5d %s %.4x %.2x', [T, Kind, Addr, Value]));
end;

procedure TTestBus.Contend(Addr: Word; Time: Integer; var T: Integer);
begin
  Event(T, 'MC', Addr);
  Inc(T, Time);
end;

procedure TTestBus.ContendNoMreq(Addr: Word; Time: Integer; var T: Integer);
begin
  Event(T, 'MC', Addr);
  Inc(T, Time);
end;

function TTestBus.ReadMem(Addr: Word; T: Integer): Byte;
begin
  Result := Memory[Addr];
  EventData(T, 'MR', Addr, Result);
end;

procedure TTestBus.WriteMem(Addr: Word; Value: Byte; T: Integer);
begin
  EventData(T, 'MW', Addr, Value);
  Memory[Addr] := Value;
end;

procedure PortPre(Port: Word; var T: Integer);
begin
  if (Port and $C000) = $4000 then Event(T, 'PC', Port);
  Inc(T);
end;

procedure PortPost(Port: Word; var T: Integer);
var
  N: Integer;
begin
  if (Port and 1) <> 0 then
  begin
    if (Port and $C000) = $4000 then
      for N := 1 to 3 do
      begin
        Event(T, 'PC', Port);
        Inc(T);
      end
    else
      Inc(T, 3);
  end
  else
  begin
    Event(T, 'PC', Port);
    Inc(T, 3);
  end;
end;

function TTestBus.ReadPort(Port: Word; var T: Integer): Byte;
begin
  Result := Port shr 8;
  PortPre(Port, T);
  EventData(T, 'PR', Port, Result);
  PortPost(Port, T);
end;

procedure TTestBus.WritePort(Port: Word; Value: Byte; var T: Integer);
begin
  PortPre(Port, T);
  EventData(T, 'PW', Port, Value);
  PortPost(Port, T);
end;

function NextToken: string;
begin
  while TokenPos >= Tokens.Count do
  begin
    Tokens.Clear;
    TokenPos := 0;
    if LinePos >= Lines.Count then Exit('');
    ExtractStrings([' ', #9], [], PChar(Lines[LinePos]), Tokens);
    Inc(LinePos);
  end;
  Result := Tokens[TokenPos];
  Inc(TokenPos);
end;

function NextHex: Integer;
begin
  Result := StrToInt('$' + NextToken);
end;

function RunTest: Boolean;
var
  Name, Token: string;
  Addr, Value, EndT, I: Integer;
  Initial: array[0..$FFFF] of Byte;
begin
  // Skip blank lines up to the test name
  while (LinePos < Lines.Count) and (Trim(Lines[LinePos]) = '') do Inc(LinePos);
  if LinePos >= Lines.Count then Exit(False);
  Name := Trim(Lines[LinePos]);
  Inc(LinePos);
  Tokens.Clear;
  TokenPos := 0;

  Cpu.Reset(True);
  Cpu.T := 0;
  for I := 0 to $FFFF do
    case I and 3 of
      0: Bus.Memory[I] := $DE;
      1: Bus.Memory[I] := $AD;
      2: Bus.Memory[I] := $BE;
      3: Bus.Memory[I] := $EF;
    end;

  Cpu.SetAF(NextHex);
  Cpu.BC.W := NextHex;
  Cpu.DE.W := NextHex;
  Cpu.HL.W := NextHex;
  Value := NextHex;
  Cpu.A_ := Value shr 8; Cpu.F_ := Value and $FF;
  Cpu.BC_.W := NextHex;
  Cpu.DE_.W := NextHex;
  Cpu.HL_.W := NextHex;
  Cpu.IX.W := NextHex;
  Cpu.IY.W := NextHex;
  Cpu.SP.W := NextHex;
  Cpu.PC.W := NextHex;
  Cpu.WZ.W := NextHex;
  Cpu.I := NextHex;
  Value := NextHex;
  Cpu.R := Value; Cpu.R7 := Value;
  Cpu.IFF1 := StrToInt(NextToken) <> 0;
  Cpu.IFF2 := StrToInt(NextToken) <> 0;
  Cpu.IM := StrToInt(NextToken);
  Cpu.Halted := StrToInt(NextToken) <> 0;
  EndT := StrToInt(NextToken);

  // Memory blocks: "addr byte byte ... -1", terminated by a lone "-1"
  repeat
    Token := NextToken;
    if Token = '-1' then Break;
    Addr := StrToInt('$' + Token);
    repeat
      Token := NextToken;
      if Token = '-1' then Break;
      Bus.Memory[Addr and $FFFF] := StrToInt('$' + Token);
      Inc(Addr);
    until False;
  until False;

  Move(Bus.Memory, Initial, SizeOf(Initial));
  WriteLn(Name);

  while Cpu.T < EndT do
    Cpu.Step;

  WriteLn(Format('%.4x %.4x %.4x %.4x %.4x %.4x %.4x %.4x %.4x %.4x %.4x %.4x %.4x',
    [Cpu.GetAF, Cpu.BC.W, Cpu.DE.W, Cpu.HL.W, (Cpu.A_ shl 8) or Cpu.F_, Cpu.BC_.W,
     Cpu.DE_.W, Cpu.HL_.W, Cpu.IX.W, Cpu.IY.W, Cpu.SP.W, Cpu.PC.W, Cpu.WZ.W]));
  WriteLn(Format('%.2x %.2x %d %d %d %d %d',
    [Cpu.I, Cpu.GetR, Ord(Cpu.IFF1), Ord(Cpu.IFF2), Cpu.IM, Ord(Cpu.Halted), Cpu.T]));

  I := 0;
  while I <= $FFFF do
  begin
    if Bus.Memory[I] <> Initial[I] then
    begin
      Write(Format('%.4x ', [I]));
      while (I <= $FFFF) and (Bus.Memory[I] <> Initial[I]) do
      begin
        Write(Format('%.2x ', [Bus.Memory[I]]));
        Inc(I);
      end;
      WriteLn('-1');
    end
    else
      Inc(I);
  end;
  WriteLn;
  Result := True;
end;

begin
  if ParamCount < 1 then
  begin
    WriteLn(StdErr, 'Usage: z80test <tests.in>');
    Halt(1);
  end;
  Lines := TStringList.Create;
  Tokens := TStringList.Create;
  Lines.LoadFromFile(ParamStr(1));
  Bus := TTestBus.Create;
  Cpu := TZ80.Create(Bus);
  while RunTest do ;
end.

{ z80ntest: the Z80N's extra instructions (ZX Spectrum Next), each run on a
  plain 64K bus: result, flags where they are defined, and T-states as
  wiki.specnext.dev/Extended_Z80_instruction_set gives them. Without Z80N
  they must stay 8 T-state NOPs. }
program z80ntest;

{$mode objfpc}{$H+}

uses
  SysUtils, Z80Core;

type
  TTestBus = class(TZ80Bus)
  public
    Mem: array[0..65535] of Byte;
    PortIn: Byte;
    LastPort: Word;
    LastOut: Byte;
    NextReg, NextVal: Integer;
    function ReadMem(Addr: Word; T: Integer): Byte; override;
    procedure WriteMem(Addr: Word; Value: Byte; T: Integer); override;
    function ReadPort(Port: Word; var T: Integer): Byte; override;
    procedure WritePort(Port: Word; Value: Byte; var T: Integer); override;
    procedure WriteNextReg(Reg, Value: Byte; T: Integer); override;
  end;

function TTestBus.ReadMem(Addr: Word; T: Integer): Byte;
begin
  Result := Mem[Addr];
end;

procedure TTestBus.WriteMem(Addr: Word; Value: Byte; T: Integer);
begin
  Mem[Addr] := Value;
end;

function TTestBus.ReadPort(Port: Word; var T: Integer): Byte;
begin
  Inc(T, 4);
  LastPort := Port;
  Result := PortIn;
end;

procedure TTestBus.WritePort(Port: Word; Value: Byte; var T: Integer);
begin
  Inc(T, 4);
  LastPort := Port;
  LastOut := Value;
end;

procedure TTestBus.WriteNextReg(Reg, Value: Byte; T: Integer);
begin
  NextReg := Reg;
  NextVal := Value;
end;

var
  Bus: TTestBus;
  Cpu: TZ80;
  Failures: Integer = 0;

procedure Check(Cond: Boolean; const What: string);
begin
  if not Cond then
  begin
    WriteLn('FAIL  ', What);
    Inc(Failures);
  end;
end;

{ Put the bytes at 8000, run one instruction; its T-states }
function Run(const Code: array of Byte): Integer;
var
  I: Integer;
begin
  for I := 0 to High(Code) do Bus.Mem[$8000 + I] := Code[I];
  Cpu.PC.W := $8000;
  Cpu.T := 0;
  Cpu.Step;
  Result := Cpu.T;
end;

procedure Expect(const Name: string; T, WantT: Integer; Cond: Boolean);
begin
  Check(Cond, Name);
  Check(T = WantT, Format('%s: %d T-states, %d expected', [Name, T, WantT]));
end;

var
  T, I: Integer;
begin
  Bus := TTestBus.Create;
  Cpu := TZ80.Create(Bus);
  Cpu.Z80N := True;
  Cpu.SP.W := $FF00;

  Cpu.A := $A5; Cpu.F := 0;
  T := Run([$ED, $23]);
  Expect('SWAPNIB', T, 8, Cpu.A = $5A);
  Cpu.A := $01;
  T := Run([$ED, $24]);
  Expect('MIRROR A', T, 8, Cpu.A = $80);
  Cpu.A := $F0;
  T := Run([$ED, $27, $0F]);
  Expect('TEST n (zero)', T, 11, (Cpu.A = $F0) and ((Cpu.F and FLAG_Z) <> 0) and (Cpu.PC.W = $8003));
  Cpu.A := $F0;
  Run([$ED, $27, $80]);
  Check(((Cpu.F and FLAG_Z) = 0) and ((Cpu.F and FLAG_S) <> 0), 'TEST n (sign)');

  Cpu.DE.W := $0001; Cpu.BC.H := 4;
  T := Run([$ED, $28]);
  Expect('BSLA DE,B', T, 8, Cpu.DE.W = $0010);
  Cpu.DE.W := $8000; Cpu.BC.H := 4;
  Run([$ED, $29]);
  Check(Cpu.DE.W = $F800, 'BSRA DE,B');
  Cpu.DE.W := $8000; Cpu.BC.H := 4;
  Run([$ED, $2A]);
  Check(Cpu.DE.W = $0800, 'BSRL DE,B');
  Cpu.DE.W := $0000; Cpu.BC.H := 4;
  Run([$ED, $2B]);
  Check(Cpu.DE.W = $F000, 'BSRF DE,B');
  Cpu.DE.W := $8001; Cpu.BC.H := 4;
  Run([$ED, $2C]);
  Check(Cpu.DE.W = $0018, 'BRLC DE,B');
  Cpu.DE.W := $8001; Cpu.BC.H := 32 + 1;   // only the low 5 bits count
  Run([$ED, $28]);
  Check(Cpu.DE.W = $0002, 'BSLA uses B and 31');

  Cpu.DE.W := $FF10;
  T := Run([$ED, $30]);
  Expect('MUL D,E', T, 8, Cpu.DE.W = $0FF0);

  Cpu.HL.W := $10F0; Cpu.A := $20;
  T := Run([$ED, $31]);
  Expect('ADD HL,A', T, 8, Cpu.HL.W = $1110);
  Cpu.DE.W := $FFFF; Cpu.A := $02;
  Run([$ED, $32]);
  Check(Cpu.DE.W = $0001, 'ADD DE,A');
  Cpu.BC.W := $1000; Cpu.A := $FF;
  Run([$ED, $33]);
  Check(Cpu.BC.W = $10FF, 'ADD BC,A');
  Cpu.HL.W := $1000;
  T := Run([$ED, $34, $34, $12]);
  Expect('ADD HL,nn', T, 16, (Cpu.HL.W = $2234) and (Cpu.PC.W = $8004));
  Cpu.DE.W := $0001;
  Run([$ED, $35, $FF, $FF]);
  Check(Cpu.DE.W = $0000, 'ADD DE,nn');
  Cpu.BC.W := $0100;
  Run([$ED, $36, $00, $02]);
  Check(Cpu.BC.W = $0300, 'ADD BC,nn');

  Cpu.SP.W := $FF00;
  T := Run([$ED, $8A, $12, $34]);
  Expect('PUSH nn', T, 23, (Cpu.SP.W = $FEFE) and (Bus.Mem[$FEFE] = $34) and (Bus.Mem[$FEFF] = $12));

  Cpu.HL.W := $9000; Cpu.BC.W := $12FE; Bus.Mem[$9000] := $77;
  T := Run([$ED, $90]);
  Expect('OUTINB', T, 16, (Bus.LastOut = $77) and (Bus.LastPort = $12FE) and (Cpu.HL.W = $9001) and
    (Cpu.BC.W = $12FE));

  T := Run([$ED, $91, $07, $03]);
  Expect('NEXTREG n,n', T, 20, (Bus.NextReg = 7) and (Bus.NextVal = 3) and (Cpu.PC.W = $8004));
  Cpu.A := $55;
  T := Run([$ED, $92, $40]);
  Expect('NEXTREG n,A', T, 17, (Bus.NextReg = $40) and (Bus.NextVal = $55));

  Cpu.HL.W := $4000;
  T := Run([$ED, $93]);
  Expect('PIXELDN (next line)', T, 8, Cpu.HL.W = $4100);
  Cpu.HL.W := $4700;
  Run([$ED, $93]);
  Check(Cpu.HL.W = $4020, 'PIXELDN (next character row)');
  Cpu.HL.W := $47E0;
  Run([$ED, $93]);
  Check(Cpu.HL.W = $4800, 'PIXELDN (next third)');
  Cpu.DE.W := Word(191 shl 8) or 255;
  T := Run([$ED, $94]);
  Expect('PIXELAD', T, 8, Cpu.HL.W = $57FF);
  Cpu.DE.L := 3;
  T := Run([$ED, $95]);
  Expect('SETAE', T, 8, Cpu.A = $10);

  Bus.PortIn := $81; Cpu.BC.W := $00FF;
  T := Run([$ED, $98]);
  Expect('JP (C)', T, 13, Cpu.PC.W = ($8000 and $C000) or ($81 shl 6));

  // Block copies: a byte equal to A isn't written
  for I := 0 to 3 do Bus.Mem[$9000 + I] := I + 1;
  FillChar(Bus.Mem[$A000], 8, 0);
  Cpu.HL.W := $9000; Cpu.DE.W := $A000; Cpu.BC.W := 4; Cpu.A := 2;
  T := Run([$ED, $A4]);
  Expect('LDIX', T, 16, (Bus.Mem[$A000] = 1) and (Cpu.HL.W = $9001) and (Cpu.DE.W = $A001) and
    (Cpu.BC.W = 3));
  T := Run([$ED, $A4]);
  Check((Bus.Mem[$A001] = 0) and (Cpu.DE.W = $A002), 'LDIX skips the byte equal to A');
  FillChar(Bus.Mem[$A000], 8, 0);
  Cpu.HL.W := $9000; Cpu.DE.W := $A000; Cpu.BC.W := 4; Cpu.A := 2;
  T := Run([$ED, $B4]);
  Check((T = 21) and (Cpu.PC.W = $8000), 'LDIRX repeats (21 T-states)');
  repeat
    Cpu.T := 0;
    Cpu.Step;
  until Cpu.PC.W <> $8000;
  Check((Bus.Mem[$A000] = 1) and (Bus.Mem[$A001] = 0) and (Bus.Mem[$A002] = 3) and
    (Bus.Mem[$A003] = 4) and (Cpu.BC.W = 0) and (Cpu.T = 16), 'LDIRX copies, skipping A');
  Cpu.HL.W := $9003; Cpu.DE.W := $A004; Cpu.BC.W := 1; Cpu.A := 0;
  Run([$ED, $AC]);
  Check((Bus.Mem[$A004] = 4) and (Cpu.HL.W = $9002) and (Cpu.DE.W = $A005), 'LDDX (HL down, DE up)');
  // LDPIRX: the byte from the 8-byte table at HL chosen by E
  for I := 0 to 7 do Bus.Mem[$9008 + I] := $10 + I;
  FillChar(Bus.Mem[$B000], 16, 0);
  Cpu.HL.W := $9008; Cpu.DE.W := $B006; Cpu.BC.W := 4; Cpu.A := $17;
  Run([$ED, $B7]);
  repeat
    Cpu.Step;
  until Cpu.PC.W <> $8000;
  Check((Bus.Mem[$B006] = $16) and (Bus.Mem[$B007] = 0) and (Bus.Mem[$B008] = $10) and
    (Bus.Mem[$B009] = $11) and (Cpu.HL.W = $9008) and (Cpu.DE.W = $B00A), 'LDPIRX');
  // LDWS: L and D move on
  Bus.Mem[$90FF] := $99;
  Cpu.HL.W := $90FF; Cpu.DE.W := $C010;
  T := Run([$ED, $A5]);
  Expect('LDWS', T, 14, (Bus.Mem[$C010] = $99) and (Cpu.HL.W = $9000) and (Cpu.DE.W = $C110));

  // Without Z80N they are NOPs
  Cpu.Z80N := False;
  Cpu.A := $A5;
  T := Run([$ED, $23]);
  Expect('SWAPNIB is a NOP on the Z80', T, 8, Cpu.A = $A5);

  Bus.Free;
  Cpu.Free;
  if Failures = 0 then WriteLn('Z80N instructions: all passed')
  else Halt(1);
end.

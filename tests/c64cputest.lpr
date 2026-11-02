{ c64cputest: the 6510 core (flags, decimal mode, addressing modes and their cycle counts, interrupts, the undocumented
  opcodes) on a bare 64K of RAM, the GCR coding of the .d64 images and the debugger's expressions. No ROMs needed. }
program c64cputest;

{$mode objfpc}{$H+}

uses
  SysUtils, Cpu6510, C64Disk, C64Expr;

type
  TRamBus = class(T6502Bus)
  public
    M: array[0..65535] of Byte;
    function Read(Addr: Word): Byte; override;
    procedure Write(Addr: Word; Value: Byte); override;
  end;

function TRamBus.Read(Addr: Word): Byte;
begin
  Result := M[Addr];
end;

procedure TRamBus.Write(Addr: Word; Value: Byte);
begin
  M[Addr] := Value;
end;

var
  Cpu: T6510;
  Failures: Integer = 0;

procedure Check(Cond: Boolean; const What: string);
begin
  if not Cond then
  begin
    WriteLn('FAIL  ', What);
    Inc(Failures);
  end;
end;

type
  TCountBus = class(TRamBus)
  public
    Count: Int64;
    function Read(Addr: Word): Byte; override;
    procedure Write(Addr: Word; Value: Byte); override;
  end;

function TCountBus.Read(Addr: Word): Byte;
begin
  Inc(Count);
  Result := M[Addr];
end;

procedure TCountBus.Write(Addr: Word; Value: Byte);
begin
  Inc(Count);
  M[Addr] := Value;
end;

var
  CB: TCountBus;

{ Run the bytes at $0200 for N instructions }
procedure Run(const Code: array of Byte; N: Integer);
var
  I: Integer;
begin
  for I := 0 to High(Code) do CB.M[$0200 + I] := Code[I];
  Cpu.PC := $0200;
  Cpu.IRQ := False;
  Cpu.NMIEdge := False;
  for I := 1 to N do Cpu.Step;
end;

{ Cycles of the code run }
function Cyc(const Code: array of Byte; N: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to High(Code) do CB.M[$0200 + I] := Code[I];
  Cpu.PC := $0200;
  CB.Count := 0;
  for I := 1 to N do Cpu.Step;
  Result := CB.Count;
end;

procedure TestCpu;
var
  S: TExprState;
  V: Integer;
  Err: string;
  C: TC64Condition;
begin
  CB := TCountBus.Create;
  Cpu := T6510.Create(CB);
  Cpu.SP := $FF;
  Cpu.P := P_U;
  // Cycle counts
  Check(Cyc([$A9, $01], 1) = 2, 'LDA # takes 2 cycles');
  Check(Cyc([$A5, $10], 1) = 3, 'LDA zp takes 3');
  Check(Cyc([$B5, $10], 1) = 4, 'LDA zp,X takes 4');
  Check(Cyc([$AD, $00, $30], 1) = 4, 'LDA abs takes 4');
  Cpu.X := 0;
  Check(Cyc([$BD, $00, $30], 1) = 4, 'LDA abs,X takes 4 without a page crossing');
  Cpu.X := $FF;
  Check(Cyc([$BD, $10, $30], 1) = 5, 'LDA abs,X takes 5 across a page');
  Check(Cyc([$9D, $00, $30], 1) = 5, 'STA abs,X takes 5');
  Check(Cyc([$81, $10], 1) = 6, 'STA (zp,X) takes 6');
  Cpu.Y := 0;
  CB.M[$10] := 0; CB.M[$11] := $30;
  Check(Cyc([$B1, $10], 1) = 5, 'LDA (zp),Y takes 5');
  Check(Cyc([$E6, $10], 1) = 5, 'INC zp takes 5 (read, write, write)');
  Check(Cyc([$EE, $00, $30], 1) = 6, 'INC abs takes 6');
  Check(Cyc([$20, $00, $03], 1) = 6, 'JSR takes 6');
  Cpu.SP := $FF;
  CB.M[$0300] := $60;
  Check(Cyc([$20, $00, $03, $EA], 2) = 12, 'JSR + RTS take 6 + 6');
  Check(Cyc([$48], 1) = 3, 'PHA takes 3');
  Check(Cyc([$68], 1) = 4, 'PLA takes 4');
  Check(Cyc([$4C, $00, $03], 1) = 3, 'JMP takes 3');
  Check(Cyc([$6C, $00, $04], 1) = 5, 'JMP () takes 5');
  Cpu.P := P_U;
  Check(Cyc([$D0, $05], 1) = 3, 'BNE taken takes 3');
  Cpu.P := P_U or P_Z;
  Check(Cyc([$D0, $05], 1) = 2, 'BNE not taken takes 2');
  Cpu.P := P_U;
  Check(Cyc([$00, $00], 1) = 7, 'BRK takes 7');
  // Flags and arithmetic
  Cpu.P := P_U;
  Run([$A9, $80], 1);
  Check((Cpu.P and P_N) <> 0, 'LDA #$80 sets N');
  Cpu.P := P_U;
  Cpu.A := $50;
  Run([$69, $50], 1);
  Check((Cpu.A = $A0) and ((Cpu.P and P_V) <> 0) and ((Cpu.P and P_N) <> 0), 'ADC $50+$50 = $A0 with V and N');
  Cpu.P := P_U or P_C;
  Cpu.A := $50;
  Run([$E9, $F0], 1);
  Check((Cpu.A = $60) and ((Cpu.P and P_C) = 0), 'SBC $50-$F0 = $60 with a borrow');
  Cpu.P := P_U or P_D;
  Cpu.A := $19;
  Run([$69, $28], 1);
  Check(Cpu.A = $47, 'decimal ADC $19+$28 = $47');
  Cpu.P := P_U or P_D;
  Cpu.A := $99;
  Run([$69, $01], 1);
  Check((Cpu.A = $00) and ((Cpu.P and P_C) <> 0), 'decimal ADC $99+$01 = $00 with a carry');
  Cpu.P := P_U or P_D or P_C;
  Cpu.A := $46;
  Run([$E9, $12], 1);
  Check(Cpu.A = $34, 'decimal SBC $46-$12 = $34');
  Cpu.P := P_U;
  Cpu.A := $10;
  Run([$C9, $10], 1);
  Check(((Cpu.P and P_Z) <> 0) and ((Cpu.P and P_C) <> 0), 'CMP equal sets Z and C');
  // Stack, flags, JSR/RTS
  Cpu.SP := $FF;
  Cpu.P := P_U or P_C or P_N;
  Run([$08, $28], 2);
  Check((Cpu.P and (P_C or P_N)) = (P_C or P_N), 'PHP/PLP keep the flags');
  Cpu.SP := $FF;
  CB.M[$0300] := $A2; CB.M[$0301] := $07; CB.M[$0302] := $60;
  Run([$20, $00, $03, $EA], 3);
  Check((Cpu.X = 7) and (Cpu.PC = $0203), 'JSR/RTS return after the call');
  // Interrupts
  CB.M[$FFFE] := $00; CB.M[$FFFF] := $05;
  CB.M[$FFFA] := $00; CB.M[$FFFB] := $06;
  Cpu.SP := $FF;
  Cpu.P := P_U;
  Cpu.PC := $0200;
  CB.M[$0200] := $EA;
  Cpu.IRQ := True;
  Cpu.Step;
  Check(Cpu.PC = $0500, 'an IRQ goes to the vector');
  Check((Cpu.P and P_I) <> 0, 'the IRQ sets I');
  Cpu.IRQ := False;
  Cpu.NMIEdge := True;
  Cpu.Step;
  Check(Cpu.PC = $0600, 'an NMI goes to its vector');
  // Illegal opcodes
  CB.M[$10] := $55;
  Cpu.P := P_U;
  Run([$A7, $10], 1);
  Check((Cpu.A = $55) and (Cpu.X = $55), 'LAX loads A and X');
  Cpu.A := $F0; Cpu.X := $3C;
  Run([$87, $20], 1);
  Check(CB.M[$20] = $30, 'SAX stores A and X');
  CB.M[$30] := $05;
  Cpu.A := $04;
  Run([$C7, $30], 1);
  Check((CB.M[$30] = $04) and ((Cpu.P and P_Z) <> 0), 'DCP decrements and compares');
  CB.M[$31] := $01;
  Cpu.A := $10;
  Run([$07, $31], 1);
  Check((CB.M[$31] = $02) and (Cpu.A = $12), 'SLO shifts and ORs');
  // The undocumented opcodes' names, and instruction lengths
  Check(OpLength($20) = 3, 'JSR is 3 bytes');
  Check(OpLength($A9) = 2, 'LDA # is 2 bytes');
  Check(OpLength($EA) = 1, 'NOP is 1 byte');
  Check(OpIllegal[$A7] and not OpIllegal[$A5], 'LAX is illegal, LDA is not');
  // Expressions
  FillChar(S, SizeOf(S), 0);
  S.A := 3; S.X := 20; S.PC := $C000; S.P := P_Z;
  Check(EvalC64Expression('A=3 AND X>10', S, V, Err) and (V = 1), 'expression: A=3 AND X>10');
  Check(EvalC64Expression('PC>=E000 OR #Z=1', S, V, Err) and (V = 1), 'expression: PC>=E000 OR #Z=1');
  Check(EvalC64Expression('(A+1)*2', S, V, Err) and (V = 8), 'expression: (A+1)*2');
  Check(EvalC64Expression('.10+$10', S, V, Err) and (V = 26), 'expression: .10+$10');
  Check(not EvalC64Expression('A=', S, V, Err), 'expression: a missing value is an error');
  C := CompileC64Condition('T=3', Err);
  Check(C <> nil, 'condition: T=3 compiles');
  if C <> nil then
  begin
    Check(not C.Holds(S) and not C.Holds(S) and C.Holds(S), 'condition: T=3 holds the third time');
    C.Free;
  end;
  Cpu.Free;
  CB.Free;
end;

procedure TestDisk;
var
  D: TD64Image;
  G: TGcrTrack;
  I, Sync, Longest, Run_: Integer;
  Buf: array[0..255] of Byte;
  Back: array[0..255] of Byte;
begin
  D := TD64Image.Create;
  D.Format('TEST', '99');
  Check(D.Tracks = 35, 'a new disk has 35 tracks');
  Check(D.DiskName = 'TEST', 'the disk name is kept');
  Check(Length(D.Data) = D64_SIZE_35, 'a 35 track disk is 174848 bytes');
  G := D.Gcr[1];
  Check(Length(G) = 7692, 'track 1 has 7692 GCR bytes');
  Check(Length(D.Gcr[18]) = 7142, 'track 18 has 7142 GCR bytes');
  Check(Length(D.Gcr[35]) = 6250, 'track 35 has 6250 GCR bytes');
  // 21 sync marks of 5 bytes on track 1 (two for each sector)
  Sync := 0;
  Run_ := 0;
  Longest := 0;
  for I := 0 to High(G) do
    if G[I] = $FF then
    begin
      Inc(Run_);
      if Run_ > Longest then Longest := Run_;
    end
    else
    begin
      if Run_ >= 5 then Inc(Sync);
      Run_ := 0;
    end;
  Check(Sync = 42, 'track 1 has 42 sync marks, two per sector: ' + IntToStr(Sync));
  Check(Longest = 5, 'a sync mark is 5 bytes of $FF');
  // Writing a sector into the track and reading it back through TrackWritten
  for I := 0 to 255 do Buf[I] := (I * 7 + 3) and $FF;
  D.WriteSector(5, 3, Buf);
  G := D.Gcr[5];
  D.TrackWritten(5);
  D.ReadSector(5, 3, Back);
  Check(CompareByte(Buf, Back, 256) = 0, 'a sector survives the GCR coding and reading back');
  D.Free;
end;

begin
  TestCpu;
  TestDisk;
  if Failures > 0 then
  begin
    WriteLn(Failures, ' failure(s)');
    Halt(1);
  end;
  WriteLn('ok    the 6510 core, the .d64 GCR coding and the debugger''s expressions');
end.

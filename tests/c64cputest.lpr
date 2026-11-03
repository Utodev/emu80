{ c64cputest: the 6510 core (flags, decimal mode, addressing modes and their cycle counts, those of every documented
  opcode as the Commodore 64 Programmer's Reference Guide gives them, interrupts, the undocumented opcodes) on a bare 64K
  of RAM, the cycles foreseen for the next instruction (NextCycles, which the 1541 runs by), the CIA's time of day clock
  and timer outputs, the VIC-II's border over the sprites and the sprites behind scrolled characters, the SID's voice 3 as the
  CPU reads it, the GCR coding of the .d64 images, the debugger's expressions (with symbols) and the ROM
  labels of roms/c64.sym (its folder is the first argument; skipped without it). No ROMs needed. }
program c64cputest;

{$mode objfpc}{$H+}

uses
  SysUtils, Cpu6510, C64Disk, C64Expr, C64Disasm, C64Help, C64Cia, C64Vic, C64Sid;

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
  V, I, N: Integer;
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
  // The undocumented opcodes: the names of "No More Secrets", all 256 opcodes disassembled, the help's note
  Check((OpName[$02] = 'JAM') and (OpName[$CB] = 'SBX') and (OpName[$AB] = 'LAX') and (OpName[$EB] = 'SBC') and
    (OpName[$8B] = 'ANE') and (OpName[$9B] = 'TAS'), 'the undocumented opcodes have the names of No More Secrets');
  N := 0;
  for I := 0 to 255 do
    if OpIllegal[I] then
    begin
      Inc(N);
      if Pos('Undocumented: ', InstructionHelp6502(I, '')) = 0 then Check(False, 'no undocumented note for $' + IntToHex(I, 2));
    end;
  Check(N = 105, 'there are 105 undocumented opcodes: ' + IntToStr(N));
  Check(Pos('ATX, LXA, OAL', InstructionHelp6502($AB, '')) > 0, 'LAX # has its own note');
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

type
  TNames = class
    function Find(const Name: string; out Addr: Word): Boolean;
  end;

{ As the debugger looks names up: the ROMs' labels, then the KERNAL's and the chips' names }
function TNames.Find(const Name: string; out Addr: Word): Boolean;
begin
  Result := C64FindRomLabel(Name, Addr) or C64FindName(Name, Addr);
end;

procedure TestSymbols;
var
  Names: TNames;
  S: TExprState;
  V: Integer;
  Err: string;
  C: TC64Condition;
begin
  Names := TNames.Create;
  C64ExprSymbols := @Names.Find;
  FillChar(S, SizeOf(S), 0);
  S.PC := $FFD2;
  S.A := 3;
  Check(EvalC64Expression('PC = CHROUT', S, V, Err) and (V = 1), 'expression: PC = CHROUT (a KERNAL name)');
  Check(EvalC64Expression('VIC_RASTER', S, V, Err) and (V = $D012), 'expression: VIC_RASTER is D012');
  Check(EvalC64Expression('A = 3', S, V, Err) and (V = 1), 'expression: A is still the register');
  C := CompileC64Condition('PC=NO_SUCH_NAME', Err);
  Check(C = nil, 'condition: an unknown name is an error');
  C.Free;
  if ParamCount >= 1 then
  begin
    Check(LoadC64RomSymbols(IncludeTrailingPathDelimiter(ParamStr(1)) + 'c64.sym', True), 'roms/c64.sym loads');
    Check(C64RomLabel($A474, True, True) = 'READY', 'c64.sym: A474 is READY with BASIC paged in');
    Check(C64RomLabel($A474, False, True) = '', 'c64.sym: no BASIC label at A474 with RAM there');
    Check(C64RomLabel($E716, True, True) = 'PRT', 'c64.sym: E716 is PRT with the KERNAL paged in');
    Check(C64RomLabel($E716, True, False) = '', 'c64.sym: no KERNAL label at E716 with RAM there');
    Check(C64RomLabel($0001, False, False) = 'R6510', 'c64.sym: the RAM labels apply always');
    Check(C64RomDescription($A474) = 'do warm start', 'c64.sym: the description of READY');
    Check(EvalC64Expression('PC = BSOUT', S, V, Err) and (V = 1), 'expression: PC = BSOUT (a label of c64.sym)');
  end;
  C64ExprSymbols := nil;
  Names.Free;
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

{ The cycles of every documented opcode, as the table "Instruction addressing modes and related execution times" of the
  Programmer's Reference Guide gives them (with the extra one of the indexed reads that cross a page, and the branches) }
procedure TestTimings;
const
  // Opcode, cycles, 1 = one more across a page
  T: array[0..142] of array[0..2] of Integer = (
  ($00,7,0),($01,6,0),($05,3,0),($06,5,0),($08,3,0),($09,2,0),($0A,2,0),($0D,4,0),($0E,6,0),
  ($11,5,1),($15,4,0),($16,6,0),($18,2,0),($19,4,1),($1D,4,1),($1E,7,0),
  ($20,6,0),($21,6,0),($24,3,0),($25,3,0),($26,5,0),($28,4,0),($29,2,0),($2A,2,0),($2C,4,0),($2D,4,0),($2E,6,0),
  ($31,5,1),($35,4,0),($36,6,0),($38,2,0),($39,4,1),($3D,4,1),($3E,7,0),
  ($40,6,0),($41,6,0),($45,3,0),($46,5,0),($48,3,0),($49,2,0),($4A,2,0),($4C,3,0),($4D,4,0),($4E,6,0),
  ($51,5,1),($55,4,0),($56,6,0),($58,2,0),($59,4,1),($5D,4,1),($5E,7,0),
  ($60,6,0),($61,6,0),($65,3,0),($66,5,0),($68,4,0),($69,2,0),($6A,2,0),($6C,5,0),($6D,4,0),($6E,6,0),
  ($71,5,1),($75,4,0),($76,6,0),($78,2,0),($79,4,1),($7D,4,1),($7E,7,0),
  ($81,6,0),($84,3,0),($85,3,0),($86,3,0),($88,2,0),($8A,2,0),($8C,4,0),($8D,4,0),($8E,4,0),
  ($91,6,0),($94,4,0),($95,4,0),($96,4,0),($98,2,0),($99,5,0),($9A,2,0),($9D,5,0),
  ($A0,2,0),($A1,6,0),($A2,2,0),($A4,3,0),($A5,3,0),($A6,3,0),($A8,2,0),($A9,2,0),($AA,2,0),($AC,4,0),($AD,4,0),
  ($AE,4,0),($B1,5,1),($B4,4,0),($B5,4,0),($B6,4,0),($B8,2,0),($B9,4,1),($BA,2,0),($BC,4,1),($BD,4,1),($BE,4,1),
  ($C0,2,0),($C1,6,0),($C4,3,0),($C5,3,0),($C6,5,0),($C8,2,0),($C9,2,0),($CA,2,0),($CC,4,0),($CD,4,0),($CE,6,0),
  ($D1,5,1),($D5,4,0),($D6,6,0),($D8,2,0),($D9,4,1),($DD,4,1),($DE,7,0),
  ($E0,2,0),($E1,6,0),($E4,3,0),($E5,3,0),($E6,5,0),($E8,2,0),($E9,2,0),($EA,2,0),($EC,4,0),($ED,4,0),($EE,6,0),
  ($F1,5,1),($F5,4,0),($F6,6,0),($F8,2,0),($F9,4,1),($FD,4,1),($FE,7,0));
  BRANCHES: array[0..7] of Byte = ($10, $30, $50, $70, $90, $B0, $D0, $F0);

  function One(Op, Index: Integer): Integer;
  begin
    FillChar(CB.M, SizeOf(CB.M), 0);
    CB.M[$0200] := Op;
    CB.M[$0201] := $20;
    CB.M[$0202] := $30;
    if (Op and $1F) = $11 then CB.M[$0201] := $10;      // (zp),Y: the pointer at $10 is $3020
    CB.M[$10] := $20; CB.M[$11] := $30;
    CB.M[$20] := $00; CB.M[$21] := $30;
    Cpu.PC := $0200; Cpu.X := Index; Cpu.Y := Index; Cpu.SP := $F0; Cpu.P := P_U;
    Cpu.IRQ := False; Cpu.NMIEdge := False;
    CB.Count := 0;
    Cpu.Step;
    Result := CB.Count;
  end;

  function Branch(At: Word; Op, Offset, P: Byte): Integer;
  begin
    FillChar(CB.M, SizeOf(CB.M), 0);
    CB.M[At] := Op;
    CB.M[At + 1] := Offset;
    Cpu.PC := At; Cpu.P := P;
    CB.Count := 0;
    Cpu.Step;
    Result := CB.Count;
  end;

var
  I, N, Op: Integer;
  Flag, Taken: Byte;
begin
  CB := TCountBus.Create;
  Cpu := T6510.Create(CB);
  for I := 0 to High(T) do
  begin
    N := One(T[I][0], 0);
    Check(N = T[I][1], Format('opcode $%.2X takes %d cycles (%d)', [T[I][0], T[I][1], N]));
    if T[I][2] = 1 then
    begin
      N := One(T[I][0], $FF);
      Check(N = T[I][1] + 1, Format('opcode $%.2X takes %d cycles across a page (%d)', [T[I][0], T[I][1] + 1, N]));
    end;
  end;
  for I := 0 to 7 do
  begin
    Op := BRANCHES[I];
    // The flag each one tests (N, V, C, Z), set or clear so that it is taken
    case Op shr 6 of
      0: Flag := P_N;
      1: Flag := P_V;
      2: Flag := P_C;
    else
      Flag := P_Z;
    end;
    if (Op and $20) = 0 then Taken := P_U else Taken := P_U or Flag;
    Check(Branch($0200, Op, $10, Taken xor Flag) = 2, Format('branch $%.2X not taken takes 2', [Op]));
    Check(Branch($0200, Op, $10, Taken) = 3, Format('branch $%.2X taken takes 3', [Op]));
    Check(Branch($02F0, Op, $20, Taken) = 4, Format('branch $%.2X taken across a page takes 4', [Op]));
  end;
  Cpu.Free;
  CB.Free;
end;

{ The CIA as Appendix M describes it }
procedure TestCia;
var
  C: TCia;
  I: Integer;
begin
  C := TCia.Create(1);
  // TOD: 11:59:59.9 AM goes to 12:00:00.0 PM, and 12:59:59.9 PM to 1:00:00.0 PM
  C.Write($E, $80);                               // CRA bit 7: 50 Hz, 5 pulses of the TOD input (one a cycle here) a tenth
  C.Write($B, $11); C.Write($A, $59); C.Write(9, $59); C.Write(8, 9);
  for I := 1 to 5 do C.Tick;
  Check(C.Read($B) = $92, Format('TOD: 11 AM is followed by 12 PM ($%.2X)', [C.Peek($B)]));
  Check((C.Read($A) = 0) and (C.Read(9) = 0) and (C.Read(8) = 0), 'TOD: 12:00:00.0');
  C.Write($B, $92); C.Write($A, $59); C.Write(9, $59); C.Write(8, 9);
  for I := 1 to 5 do C.Tick;
  Check(C.Read($B) = $81, Format('TOD: 12 PM is followed by 1 PM ($%.2X)', [C.Peek($B)]));
  C.Read(8);
  // The unused bits of the TOD registers read as 0
  C.Write($B, $FF); C.Write($A, $FF); C.Write(9, $FF); C.Write(8, $FF);
  Check((C.Read($B) = $9F) and (C.Read($A) = $7F) and (C.Read(9) = $7F) and (C.Read(8) = $0F),
    'TOD: the unused bits are forced to 0 on a read');
  // Timer A on PB6: in pulse mode (OUTMODE = 0) a single cycle high at each underflow
  C.Write(4, 3); C.Write(5, 0);
  C.Write($E, $03);                               // start, PBON, pulse, continuous
  for I := 1 to 4 do
  begin
    C.Tick;
    if I < 4 then Check((C.PortBPins and $40) = 0, 'PB6 is low between the underflows in pulse mode');
  end;
  Check((C.PortBPins and $40) <> 0, 'PB6 goes high for the cycle of an underflow in pulse mode');
  C.Tick;
  Check((C.PortBPins and $40) = 0, 'and only for one cycle');
  // ... and in toggle mode it flips at each underflow, high when the timer starts
  C.Write($E, $00);
  C.Write($E, $07);
  Check((C.PortBPins and $40) <> 0, 'PB6 is high when the timer starts in toggle mode');
  for I := 1 to 4 do C.Tick;
  Check((C.PortBPins and $40) = 0, 'and an underflow toggles it');
  C.Free;
end;

{ The VIC-II's border covers the sprites }
type
  TVicMem = class
    function Read(Addr: Word): Byte;
  end;

function TVicMem.Read(Addr: Word): Byte;
begin
  // Sprite pointers 0 (data at 0, all set) and everything else $FF: a sprite is a solid block
  if (Addr and $3F8) = $3F8 then Result := 0 else Result := $FF;
end;

type
  { The screen at $0400 and its sprite pointers ($07F8, all 0) and everything else $FF: solid characters }
  TVicSolid = class
    function Read(Addr: Word): Byte;
  end;

function TVicSolid.Read(Addr: Word): Byte;
begin
  if (Addr >= $07F8) and (Addr <= $07FF) then Result := 0 else Result := $FF;
end;

procedure TestVic;
var
  Solid: TVicSolid;
  V: TVic;
  M: TVicMem;
  I, X, Y, Seen: Integer;
  InBorder, OnScreen: LongWord;
begin
  M := TVicMem.Create;
  V := TVic.Create;
  V.OnRead := @M.Read;
  V.Write($16, 8);                                // 40 columns
  V.Write($20, 2);                                // red border
  V.Write($21, 6);                                // blue background
  V.Write($27, 1);                                // white sprite 0
  V.Write($15, 1);
  V.Write(0, 10);                                 // X 10: its first 14 pixels in the left border, then 10 on the screen
  V.Write(1, 100);
  for I := 1 to 3 * VIC_LINES * VIC_CYCLES do V.Tick;
  Y := 110 - VIC_FIRST_LINE;
  InBorder := V.Frame[Y * VIC_WIDTH + (16 - VIC_FIRST_X)];
  OnScreen := V.Frame[Y * VIC_WIDTH + (28 - VIC_FIRST_X)];
  Check(InBorder = C64_PALETTE[2], 'a sprite is behind the border');
  Check(OnScreen = C64_PALETTE[1], Format('and is seen where the border is not ($%.8X)', [OnScreen]));
  V.Free;
  // A sprite behind the characters (all of them solid) stays hidden with the screen scrolled sideways: the pixels a
  // character puts in the next cycle are foreground too
  Solid := TVicSolid.Create;
  V := TVic.Create;
  V.OnRead := @Solid.Read;
  V.Write($16, 8 + 3);
  V.Write($21, 6);
  V.Write($27, 1);
  V.Write($1B, 1);
  V.Write($15, 1);
  V.Write(0, 100);
  V.Write(1, 100);
  for I := 1 to 3 * VIC_LINES * VIC_CYCLES do V.Tick;
  Seen := 0;
  for Y := 102 to 118 do
    for X := 100 to 123 do
      if V.Frame[(Y - VIC_FIRST_LINE) * VIC_WIDTH + (X - VIC_FIRST_X)] = C64_PALETTE[1] then Inc(Seen);
  Check(Seen = 0, Format('a sprite behind solid characters is hidden with XSCROLL 3 (%d pixels seen)', [Seen]));
  V.Free;
  Solid.Free;
  M.Free;
end;

{ The 1541 runs an instruction once the computer's clock has reached its last cycle: the cycles T6510.NextCycles
  foresees must be those Step takes, for every opcode (page crossed or not, branch taken or not, an interrupt) }
type
  TCycleBus = class(T6502Bus)
  public
    M: array[0..65535] of Byte;
    N: Integer;
    function Read(Addr: Word): Byte; override;
    procedure Write(Addr: Word; Value: Byte); override;
    function Peek(Addr: Word): Byte;
  end;

function TCycleBus.Read(Addr: Word): Byte;
begin
  Inc(N);
  Result := M[Addr];
end;

procedure TCycleBus.Write(Addr: Word; Value: Byte);
begin
  Inc(N);
  M[Addr] := Value;
end;

function TCycleBus.Peek(Addr: Word): Byte;
begin
  Result := M[Addr];
end;

procedure TestNextCycles;
var
  B: TCycleBus;
  C: T6510;
  Op, K, I, Pred, Bad: Integer;
begin
  B := TCycleBus.Create;
  C := T6510.Create(B);
  RandSeed := 1541;
  for I := 0 to 65535 do B.M[I] := Random(256);
  Bad := 0;
  for Op := 0 to 255 do
    for K := 1 to 300 do
    begin
      for I := 0 to 255 do B.M[I] := Random(256);
      C.Jammed := False;
      C.NMIEdge := Random(20) = 0;
      C.IRQ := Random(4) = 0;
      C.A := Random(256); C.X := Random(256); C.Y := Random(256); C.SP := Random(256); C.P := Random(256) or P_U;
      C.PC := Random(65536);
      B.M[C.PC] := Op;
      B.M[Word(C.PC + 1)] := Random(256);
      B.M[Word(C.PC + 2)] := Random(256);
      Pred := C.NextCycles(@B.Peek);
      B.N := 0;
      C.Step;
      if B.N <> Pred then
      begin
        if Bad < 5 then Check(False, Format('opcode $%.2X takes %d cycles, %d foreseen', [Op, B.N, Pred]));
        Inc(Bad);
      end;
    end;
  C.Free;
  B.Free;
end;

{ The SID's voice 3 as the CPU reads it (OSC3, ENV3) }
procedure TestSid;
var
  S: TSid;
  I, Diff, Last, V: Integer;
  Buf: array[0..2047] of SmallInt;
begin
  S := TSid.Create(985248);
  // Noise on voice 3 as a random number generator: it changes within a frame
  S.Write(0, $0E, $FF); S.Write(0, $0F, $FF);
  S.Write(0, $12, $80);
  Diff := 0;
  Last := -1;
  for I := 1 to 100 do
  begin
    V := S.Read(I * 100, $1B);
    if V <> Last then Inc(Diff);
    Last := V;
  end;
  Check(Diff > 50, Format('OSC3 gives new random numbers as the frame goes (%d different of 100)', [Diff]));
  // The sawtooth goes up as the frame goes
  S.Write(10000, $12, $20);
  S.Write(10000, $0E, $00); S.Write(10000, $0F, $01);    // 256 a cycle: the top 8 bits go up by 1 every 256 cycles
  Last := S.Read(10000 + 256 * 5, $1B);
  V := S.Read(10000 + 256 * 10, $1B);
  Check(V - Last = 5, Format('OSC3 follows the sawtooth (%d, %d)', [Last, V]));
  // ENV3: the attack goes up as the frame goes
  S.Write(13000, $13, $00); S.Write(13000, $14, $F0); S.Write(13000, $12, $21);
  V := S.Read(13000 + 9 * 20, $1C);
  Check(V >= 18, Format('ENV3 follows the attack (%d)', [V]));
  // Combined waveforms read as the AND of the parts (not quieter)
  S.Write(14000, $0E, $00); S.Write(14000, $0F, $80);
  S.Write(14000, $12, $08);                               // TEST: the accumulator to 0
  S.Write(14001, $12, $30);                               // triangle + sawtooth
  V := S.Read(14001 + 192, $1B);                          // the accumulator at $600000: $C00 AND $600
  Check(V = $40, Format('OSC3 of triangle + sawtooth is the AND of the two ($%.2X)', [V]));
  S.Generate(19656, 44100, @Buf[0], 882);
  S.EndFrame(19656);
  // Noise with another waveform locks up (the TEST bit brings it back)
  S.Write(0, $12, $08); S.Write(1, $12, $00);
  S.Write(2, $0E, $FF); S.Write(2, $0F, $FF);
  S.Write(2, $12, $A0);                                   // noise + sawtooth
  S.Write(19000, $12, $80);                               // noise alone
  Diff := 0;
  for I := 1 to 20 do Diff := Diff or S.Read(19000 + I * 30, $1B);
  Check(Diff = 0, Format('noise with another waveform locks up ($%.2X)', [Diff]));
  S.Write(19600, $12, $88); S.Write(19601, $12, $80);
  Diff := 0;
  for I := 1 to 10 do Diff := Diff or S.Read(19601 + I * 4, $1B);
  Check(Diff <> 0, 'and the TEST bit unlocks it');
  S.Generate(19656, 44100, @Buf[0], 882);
  S.EndFrame(19656);
  S.Free;
end;

begin
  TestCpu;
  TestTimings;
  TestCia;
  TestVic;
  TestNextCycles;
  TestSid;
  TestSymbols;
  TestDisk;
  if Failures > 0 then
  begin
    WriteLn(Failures, ' failure(s)');
    Halt(1);
  end;
  WriteLn('ok    the 6510 core (and its timings as the Programmer''s Reference Guide gives them, foreseen too), the CIA, the VIC-II''s border, the SID''s voice 3, the .d64 GCR coding, the debugger''s expressions and the ROM labels');
end.

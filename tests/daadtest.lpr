{ daadtest: the DAAD debugger's view of a game. Loads the DAAD Ready test
  game (48K and 128K interpreters), reads its database and follows the
  interpreter: the fetch instruction learnt must be CHECK (from the
  interpreter's symbols), each stop must be on a condact the database has,
  in the process being run (the same while the stack stays, the one called
  after a PROCESS), with IX pointing at the flags (flag 38, the player's
  location, a valid location), and stepping over a PROCESS must come back
  to the next condact of the same entry.

    daadtest <roms folder> <tests/daad folder> }
program daadtest;

{$mode objfpc}{$H+}

uses
  SysUtils, StrUtils, Classes, Models, Spectrum, Daad, DaadExport;

var
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
  TFlags = class
    F: array[0..255] of Byte;
    function Read(N: Byte): Byte;
  end;

function TFlags.Read(N: Byte): Byte;
begin
  Result := F[N];
end;

{ Breakpoint conditions: "f0 = 3 AND f10>11" }
procedure TestConditions;
var
  Flags: TFlags;

  function Eval(const Text: string): Integer;   // 1 holds, 0 not, -1 invalid
  var
    C: TDaadCondition;
    Err: string;
  begin
    C := TDaadCondition.Parse(Text, Err);
    if C = nil then Exit(-1);
    Result := Ord(C.Holds(@Flags.Read));
    C.Free;
  end;

  procedure Expect(const Text: string; Want: Integer);
  begin
    Check(Eval(Text) = Want, Format('condition "%s" gives %d, expected %d', [Text, Eval(Text), Want]));
  end;

begin
  Flags := TFlags.Create;
  FillChar(Flags.F, SizeOf(Flags.F), 0);
  Flags.F[0] := 3;
  Flags.F[10] := 12;
  Flags.F[5] := 10;
  Expect('f0 = 3 AND f10>11', 1);
  Expect('f0=3 and f10>12', 0);
  Expect('F0 == 3', 1);
  Expect('f0 <> 3 OR f10 >= 12', 1);
  Expect('f0 != 3 or f10 <= 11', 0);
  Expect('NOT f0 = 4', 1);
  Expect('NOT (f0 = 3 AND f10 > 11)', 0);
  Expect('@f5 = 12', 1);          // flag 5 is 10, flag 10 is 12
  Expect('f1 < f0', 1);
  Expect('3 = f0', 1);
  Expect('(f0 = 1 OR f0 = 3) AND f255 = 0', 1);
  Expect('', -1);
  Expect('f0', -1);
  Expect('f256 = 1', -1);
  Expect('f0 = ', -1);
  Expect('f0 = 3 AND', -1);
  Expect('(f0 = 3', -1);
  Expect('A = 3', -1);
  Expect('f0 = 3 f1 = 2', -1);
  Flags.Free;
end;

{ A small PAW database built in memory: header, signature, a response
  table and process 1, condacts whose parameters differ from DAAD's, a
  text with an abbreviation }
procedure TestPAW;
var
  Mem: TDaadMemory;
  Game: TDaadGame;
  Map: array[0..$FFFF] of Byte;
  Top: Word;
  I: Integer;
  Src: TStringList;

  procedure W(A, V: Word);
  begin
    Mem[A] := V and $FF;
    Mem[A + 1] := V shr 8;
  end;

  procedure Bytes(A: Word; const B: array of Byte);
  var
    K: Integer;
  begin
    for K := 0 to High(B) do Mem[A + K] := B[K];
  end;

  procedure Text(A: Word; const S: string);
  var
    K: Integer;
  begin
    for K := 1 to Length(S) do Mem[A + K - 1] := Ord(S[K]) xor $FF;
    Mem[A + Length(S)] := 31 xor $FF;
  end;

begin
  FillChar(Mem, SizeOf(Mem), 0);
  Top := $9300;
  W($FFFD, Top);
  for I := 0 to 5 do Mem[Top + 311 + I * 2] := 16 + I;   // signature
  Mem[Top + 324] := 1;    // objects
  Mem[Top + 325] := 2;    // locations
  Mem[Top + 326] := 2;    // messages
  Mem[Top + 327] := 1;    // system messages
  Mem[Top + 328] := 2;    // processes
  W(Top + 332, $A000);    // abbreviations: 0 (compressed), then "the " and "lamp"
  Bytes($A000, [0, Ord('x') or $80, Ord('t'), Ord('h'), Ord('e'), Ord(' ') or $80,
    Ord('l'), Ord('a'), Ord('m'), Ord('p') or $80]);
  W($FFD9, $A100);        // process table
  W($A100, $A200);        // process 0: the response table
  W($A102, $A300);        // process 1
  // Response table: LOOK _ -> DESC (no parameter in PAW), MESSAGE 1, PARSE (none)
  Bytes($A200, [20, 255]); W($A202, $A400); Mem[$A204] := 0;
  Bytes($A400, [19, 38, 1, 73, 255]);
  // Process 1: _ _ -> INVEN (18: SFX in DAAD, with 2 parameters), DONE
  Bytes($A300, [255, 255]); W($A302, $A500); Mem[$A304] := 0;
  Bytes($A500, [18, 22, 255]);
  W($FFDF, $A600);        // messages
  W($A602, $A700);
  Text($A700, 'take ');
  Mem[$A705] := (165 + 1) xor $FF;   // abbreviation 2: "lamp"
  Mem[$A706] := 31 xor $FF;
  W($FFE5, $A800);        // vocabulary: LOOK, verb 20
  Text($A800, 'LOOK ');
  Mem[$A805] := 20;
  Mem[$A806] := 0;
  Mem[$A807] := 0;

  Game := TDaadGame.Create;
  try
    Check(Game.Load(Mem) and Game.IsPAW, 'PAW database found');
    Check((Game.NumProcesses = 2) and (Length(Game.Entries) = 2), 'PAW processes and entries');
    Check(Length(Game.Condacts) = 5, Format('PAW condacts: %d', [Length(Game.Condacts)]));
    if Length(Game.Condacts) = 5 then
    begin
      Check(Trim(Game.CondactText(Game.Condacts[0])) = 'DESC', 'PAW DESC without parameter');
      Check(DelSpace1(Game.CondactText(Game.Condacts[1])) = 'MESSAGE 1', 'PAW MESSAGE 1');
      Check(Trim(Game.CondactText(Game.Condacts[2])) = 'PARSE', 'PAW PARSE without parameter');
      Check(Trim(Game.CondactText(Game.Condacts[3])) = 'INVEN', 'PAW INVEN (not SFX)');
      Check(Game.CondactMessage(Game.Condacts[1]) = 'take lamp',
        'PAW text with an abbreviation: "' + Game.CondactMessage(Game.Condacts[1]) + '"');
    end;
    Check(Game.VocWord(20, 0) = 'LOOK', 'PAW vocabulary');
    Game.BuildMap(@Map);
    Check((Map[$A200] and DAAD_INPUT) <> 0, 'PAW: the response table marks the player''s input');
    Check((Map[$A400] and DAAD_CONDACT) <> 0, 'PAW condact in the map');
    // Source: as a PAW game, and converted to DAAD as PAWS2DAAD does
    Src := ExportDaadSource(Game, True);
    try
      Check((Pos('INVEN', Src.Text) > 0) and (Pos('/PRO 1', Src.Text) > 0) and
        (Pos('PAWS2DAAD', Src.Text) = 0), 'PAW game exported as SCE');
    finally
      Src.Free;
    end;
    Src := ExportDaadSource(Game, False, True);
    try
      Check(Pos('/PRO 3    ; PAW process 1', Src.Text) > 0, 'PAW process 1 becomes DAAD process 3');
      Check(Pos('/PRO 5    ; PAW process 0', Src.Text) > 0, 'PAW response table becomes process 5');
      Check((Pos('/PRO 6 ; Initialisation', Src.Text) > 0) and (Pos('#define fDarkF', Src.Text) > 0),
        'DAAD template processes and definitions added');
      Check(Pos('it was INVEN', Src.Text) > 0, 'PAW INVEN converted');
      Check(Pos('RESTART  ; PAWS2DAAD note: it was DESC', Src.Text) > 0, 'PAW DESC converted');
      Check(Pos(';> _       _     MINUS   5       1', Src.Text) > 0, 'auto-decrement flags entry');
    finally
      Src.Free;
    end;
  finally
    Game.Free;
  end;
end;

procedure TakeMemory(Sp: TSpectrum; var Mem: TDaadMemory);
var
  A: Integer;
begin
  for A := 0 to $FFFF do Mem[A] := Sp.Peek(A);
end;

{ Run until the interpreter fetches a condact (or Frames frames pass) }
function RunToStop(Sp: TSpectrum; Frames: Integer): Boolean;
var
  I: Integer;
begin
  for I := 1 to Frames do
    if not Sp.RunFrame then
      Exit(Sp.BreakKind = bkDaad);
  Result := False;
end;

{ The condact the machine stopped at, in the entry being run }
function Current(Sp: TSpectrum; Game: TDaadGame): Integer;
var
  Recent: array[0..DAAD_ENTRY_HISTORY - 1] of Integer;
  I: Integer;
begin
  for I := 0 to High(Recent) do Recent[I] := Sp.DaadEntry(I);
  Result := Game.CondactIn(Sp.DaadFetch, Recent);
end;

function ProcessOf(Game: TDaadGame; C: Integer): Integer;
begin
  Result := Game.Entries[Game.Condacts[C].Entry].Process;
end;

procedure TestGame(Model: TSpectrumModel; const RomDir, TapFile, Name: string; CheckPC: Word);
var
  Sp: TSpectrum;
  Mem: TDaadMemory;
  Game: TDaadGame;
  Map: array[0..$FFFF] of Byte;
  I, C, Steps, Entry, Over: Integer;
  Loaded: Boolean;
  SP0: Word;
  Seen: set of Byte;
  Err: string;
  Prev, PrevSP, Commands: Integer;
  Breaks: array of TDaadBreak;
  Src: TStringList;
  Text: string;
begin
  Sp := TSpectrum.Create(Model, RomDir);
  Game := TDaadGame.Create;
  try
    Sp.FastLoad := True;
    Sp.AutoPlayTape := True;
    Sp.Reset(True);
    Sp.Tape.LoadTAP(TapFile);
    Sp.AutoLoad;
    // Loaded when the database is in memory and the game is waiting for input
    Loaded := False;
    for I := 1 to 1500 do
    begin
      Sp.RunFrame;
      if (I mod 50 = 0) then
      begin
        TakeMemory(Sp, Mem);
        if Game.Load(Mem) then
        begin
          Loaded := True;
          Break;
        end;
      end;
    end;
    Check(Loaded, Name + ': database found at 8400');
    if not Loaded then Exit;
    Check(Game.Version = 3, Name + ': DDB version 3');
    Check(Game.NumProcesses >= 3, Name + ': processes');
    Check(Length(Game.Condacts) > 50, Name + ': condacts read');
    // The 128K interpreters of DAAD v2 put their interrupt table at
    // 8300-8400, overwriting the version byte
    I := Mem[DDB_BASE];
    Mem[DDB_BASE] := $82;
    Check(Game.Load(Mem) and (Game.Base = DDB_BASE) and (Length(Game.Condacts) > 50),
      Name + ': found with its first byte overwritten');
    Mem[DDB_BASE] := I;
    Game.Load(Mem);
    // Source export: every section and process, in both formats
    for I := 0 to 1 do
    begin
      Src := ExportDaadSource(Game, I = 1);
      try
        Text := Src.Text;
        Check((Pos('/VOC', Text) > 0) and (Pos('/STX', Text) > 0) and (Pos('/OBJ', Text) > 0) and
          (Pos('/CON', Text) > 0) and (Pos('/END', Text) > 0), Name + ': source sections');
        Check(Pos(Format('/PRO %d', [Game.NumProcesses - 1]), Text) > 0, Name + ': every process exported');
        if I = 0 then
          Check(Pos('> _      _      ', Text) > 0, Name + ': DSF entries')
        else
          Check(Pos('/TOK', Text) > 0, Name + ': SCE tokens');
      finally
        Src.Free;
      end;
    end;
    Src := ExportDaadProcess(Game, 1, False);
    try
      Check((Pos('/PRO 1', Src.Text) > 0) and (Pos('/PRO 2', Src.Text) = 0), Name + ': one process exported');
    finally
      Src.Free;
    end;
    WriteLn(Format('  %s: v%d, %d processes, %d entries, %d condacts, %d objects, %d locations',
      [Name, Game.Version, Game.NumProcesses, Length(Game.Entries), Length(Game.Condacts),
       Game.NumObjects, Game.NumLocations]));

    Game.BuildMap(@Map);
    Sp.SetDaadMap(@Map);
    Sp.DaadStop := dsNext;
    // The game waits for a command at first: type one
    for I := 1 to 200 do Sp.RunFrame;
    Sp.DaadStop := dsNext;
    Check(RunToStop(Sp, 100) or (Sp.DaadStop = dsNext), Name + ': running');
    if Sp.BreakKind <> bkDaad then
    begin
      Sp.TypeText('i\n', Err);
      Check(RunToStop(Sp, 600), Name + ': stops at a condact after a command');
    end;
    if Sp.BreakKind <> bkDaad then Exit;
    // The fetch instruction learnt is CHECK in the interpreter's symbols
    Check(Sp.DaadFetchPC = CheckPC, Format('%s: fetch instruction %.4X (CHECK is %.4X)',
      [Name, Sp.DaadFetchPC, CheckPC]));

    // Single steps: always on a condact, with IX at the flags
    Seen := [];
    Over := -1;
    Prev := -1;
    PrevSP := 0;
    Commands := 0;
    for Steps := 1 to 1500 do
    begin
      C := Current(Sp, Game);
      Check(C >= 0, Format('%s: step %d at %.4X is a condact', [Name, Steps, Sp.DaadFetch]));
      if C < 0 then Break;
      Check(Sp.Peek(Word(Sp.Cpu.IX.W + 38)) < Game.NumLocations,
        Name + ': IX points at the flags (flag 38 is a location)');
      Include(Seen, Game.Condacts[C].Opcode);
      // Which process: the same while the stack stays, the one called after
      // a PROCESS (DRC shares condacts between entries of different processes)
      if Prev >= 0 then
      begin
        if (Game.Condacts[Prev].Opcode = OP_PROCESS) and (Sp.Cpu.SP.W < PrevSP) then
          Check(ProcessOf(Game, C) = Game.Condacts[Prev].Params[0],
            Format('%s: after PROCESS %d, at %.4X in process %d', [Name, Game.Condacts[Prev].Params[0],
            Sp.DaadFetch, ProcessOf(Game, C)]))
        else if (Sp.Cpu.SP.W = PrevSP) and (Game.Condacts[Prev].Opcode <> OP_PROCESS) then
          Check(ProcessOf(Game, C) = ProcessOf(Game, Prev),
            Format('%s: %.4X stays in process %d', [Name, Sp.DaadFetch, ProcessOf(Game, Prev)]));
      end;
      Prev := C;
      PrevSP := Sp.Cpu.SP.W;
      if (Game.Condacts[C].Opcode = OP_PROCESS) and (Over < 0) then Over := C;
      Sp.DaadStop := dsNext;
      Sp.SkipBreakpointOnce;
      if not RunToStop(Sp, 600) then
      begin
        // Waiting for the player: give it another command
        Inc(Commands);
        Prev := -1;
        if Odd(Commands) then Sp.TypeText('mirar\n', Err) else Sp.TypeText('n\n', Err);
        Sp.DaadStop := dsNext;
        if not RunToStop(Sp, 600) then Break;
      end;
    end;
    Check(Steps >= 1500, Name + ': 1500 steps');
    Check(Commands >= 2, Name + ': commands typed');
    Check(OP_PROCESS in Seen, Name + ': a PROCESS was run');

    // Stop after player input: runs freely while the game waits for an
    // order, and stops at the condact after PARSE once one is typed
    Sp.DaadStopAfterParse := True;
    Sp.DaadStop := dsNone;
    Sp.SkipBreakpointOnce;
    I := 0;
    while (I < 20) and RunToStop(Sp, 600) do
    begin
      // Finish the turn (stops after earlier orders in the buffer)
      Inc(I);
      Sp.SkipBreakpointOnce;
    end;
    Check(not RunToStop(Sp, 300), Name + ': waits for an order without stopping');
    Sp.TypeText('mirar\n', Err);
    Check(RunToStop(Sp, 600), Name + ': stops after the order is read');
    C := Current(Sp, Game);
    Check((C >= 0) and (Game.Condacts[C].Opcode <> 73), Name + ': stops after PARSE');
    Sp.DaadStopAfterParse := False;
    Sp.TypeText('', Err);

    // Breakpoints, on the PARSE run every turn: one whose condition never
    // holds doesn't stop, one whose condition holds does
    C := -1;
    for I := 0 to High(Game.Condacts) do
      if Game.Condacts[I].Opcode = 73 then
      begin
        C := I;
        Break;
      end;
    Check(C >= 0, Name + ': the game has a PARSE');
    if C >= 0 then
    begin
      SetLength(Breaks, 1);
      Breaks[0].Addr := Game.Condacts[C].Addr;
      Breaks[0].Cond := TDaadCondition.Parse('f38 = 254 AND f1 >= 0', Err);
      Sp.SetDaadBreaks(Breaks);
      Sp.DaadStop := dsNone;
      Sp.SkipBreakpointOnce;
      Sp.TypeText('mirar\n', Err);
      Check(not RunToStop(Sp, 600), Name + ': breakpoint with a false condition');
      Breaks[0].Cond.Free;
      Breaks[0].Cond := TDaadCondition.Parse('f38 < 254 AND NOT f33 = 300', Err);
      Sp.SetDaadBreaks(Breaks);
      Sp.TypeText('mirar\n', Err);
      Check(RunToStop(Sp, 600) and Sp.DaadBreakHit and (Sp.DaadFetch = Breaks[0].Addr),
        Name + ': breakpoint with a true condition stops on it');
      SetLength(Breaks, 0);
      Sp.SetDaadBreaks(Breaks);
      Sp.SkipBreakpointOnce;
    end;

    // Step over a PROCESS: comes back to the condact after it, same entry
    Sp.TypeText('mirar\n', Err);
    for I := 1 to 2000 do
    begin
      Sp.DaadStop := dsNext;
      Sp.SkipBreakpointOnce;
      if not RunToStop(Sp, 600) then Break;
      C := Current(Sp, Game);
      if (C >= 0) and (Game.Condacts[C].Opcode = OP_PROCESS) then Break;
    end;
    C := Current(Sp, Game);
    Check((C >= 0) and (Game.Condacts[C].Opcode = OP_PROCESS), Name + ': found a PROCESS');
    if (C >= 0) and (Game.Condacts[C].Opcode = OP_PROCESS) then
    begin
      Entry := Game.Condacts[C].Entry;
      SP0 := Sp.Cpu.SP.W;
      Sp.DaadSP := SP0;
      Sp.DaadStop := dsOver;
      Sp.SkipBreakpointOnce;
      Check(RunToStop(Sp, 600), Name + ': step over stops');
      C := Current(Sp, Game);
      Check((C >= 0) and ((Game.Condacts[C].Entry = Entry) or (Sp.Cpu.SP.W >= SP0)),
        Format('%s: step over the PROCESS comes back (at %.4X)', [Name, Sp.DaadFetch]));
    end;
  finally
    Game.Free;
    Sp.Free;
  end;
end;

begin
  TestConditions;
  TestPAW;
  TestGame(sm48K, ParamStr(1), IncludeTrailingPathDelimiter(ParamStr(2)) + 'test48.tap', '48K', $6234);
  TestGame(sm128K, ParamStr(1), IncludeTrailingPathDelimiter(ParamStr(2)) + 'test128.tap', '128K', $653A);
  if Failures = 0 then
    WriteLn('DAAD debugger: all passed')
  else
  begin
    WriteLn('DAAD debugger: ', Failures, ' failures');
    Halt(1);
  end;
end.

{ quilltest: The Quill in the Adventure Debugger. A small Quill (version C)
  database built in memory: its tables, words, texts and condacts (the
  actions numbered as The Quill does, read as PAW's), and its export to a
  DAAD source. With a folder of Quill games (snapshots and tapes), each one
  is loaded and followed: the machine must stop at one of its condacts with
  IX at the flags.

    quilltest <roms folder> [games folder] }
program quilltest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Models, Spectrum, Snapshot, Daad, DaadExport;

var
  Failures: Integer = 0;
  Followed: Integer = 0;   // real games followed to a condact

procedure Check(Cond: Boolean; const What: string);
begin
  if not Cond then
  begin
    WriteLn('FAIL  ', What);
    Inc(Failures);
  end;
end;

procedure TestBuilt;
const
  TOP = 27356;
  ATTR = TOP + 169;
var
  Mem: TDaadMemory;
  Game: TDaadGame;
  Src: TStringList;
  I: Integer;

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

  procedure Voc(A: Word; const S: string; Id: Byte);
  var
    K: Integer;
  begin
    for K := 1 to 4 do
      if K <= Length(S) then Mem[A + K - 1] := Ord(S[K]) xor $FF else Mem[A + K - 1] := 32 xor $FF;
    Mem[A + 4] := Id;
  end;

begin
  FillChar(Mem, SizeOf(Mem), 0);
  for I := 0 to 5 do Mem[ATTR + I * 2] := 16 + I;   // signature
  Mem[ATTR + 13] := 4;     // objects that can be carried
  Mem[ATTR + 14] := 1;     // objects
  Mem[ATTR + 15] := 2;     // locations
  Mem[ATTR + 16] := 1;     // messages
  Mem[ATTR + 17] := 1;     // system messages
  W(ATTR + 18, $A000);     // event table
  W(ATTR + 20, $A100);     // status table
  W(ATTR + 22, $A200);     // objects
  W(ATTR + 24, $A300);     // locations
  W(ATTR + 26, $A400);     // messages
  W(ATTR + 28, $A500);     // system messages
  W(ATTR + 30, $A600);     // connections
  W(ATTR + 32, $A700);     // vocabulary
  W(ATTR + 34, $A800);     // initially at
  W(ATTR + 36, $A900);     // object words
  Mem[ATTR + 42] := 1;     // abbreviations: not compressed
  // Event table: GET LAMP -> PRESENT 0 | GET 0, OK ; LOOK _ -> | DESC
  Bytes($A000, [50, 200]); W($A002, $B000);
  Bytes($A004, [51, 255]); W($A006, $B100);
  Mem[$A008] := 0;
  Bytes($B000, [4, 0, 255, 24, 0, 5, 255]);   // PRESENT 0, 255, GET 0 (C 24), OK (5), 255
  Bytes($B100, [255, 1, 255]);                // no conditions, DESC
  // Status table: AT 1 | GOTO 0 (C 21), MESSAGE 0 (C 22)
  Bytes($A100, [255, 255]); W($A102, $B200);
  Mem[$A104] := 0;
  Bytes($B200, [0, 1, 255, 21, 0, 22, 0, 255]);
  W($A200, $C000); Text($C000, 'a lamp');
  W($A300, $C100); Text($C100, 'A dark room.');
  W($A302, $C200); Text($C200, 'A hall.');
  W($A400, $C300); Text($C300, 'Hello.');
  W($A500, $C400); Text($C400, 'It is dark.');
  W($A600, $C500); W($A602, $C510);
  Bytes($C500, [2, 1, 255]);                  // N to 1
  Bytes($C510, [3, 0, 255]);                  // S to 0
  Voc($A700, 'N', 2); Voc($A705, 'S', 3); Voc($A70A, 'GET', 50); Voc($A70F, 'LOOK', 51);
  Voc($A714, 'LAMP', 200);
  Mem[$A719] := 0;
  Mem[$A800] := 0;                            // the lamp starts at 0
  Mem[$A900] := 200;                          // the lamp's word
  Game := TDaadGame.Create;
  try
    Check(Game.Load(Mem), 'built: a game is found');
    Check(Game.IsQuill and (Game.QuillVersion = 3) and (Game.Engine = aeQuill), 'built: a Quill C game');
    Check((Game.NumProcesses = 2) and (Length(Game.Entries) = 3), 'built: two tables, three entries');
    Check(Game.CondactText(Game.Condacts[0]) = 'PRESENT 0', 'built: condition PRESENT 0');
    Check(Game.CondactText(Game.Condacts[1]) = 'GET     0', 'built: action GET 0, got ' +
      Game.CondactText(Game.Condacts[1]));
    Check(Game.CondactText(Game.Condacts[2]) = 'OK', 'built: action OK');
    Check(Game.CondactText(Game.Condacts[3]) = 'DESC', 'built: action DESC');
    Check(Game.CondactText(Game.Condacts[5]) = 'GOTO    0', 'built: action GOTO 0');
    Check(Game.CondactMessage(Game.Condacts[6]) = 'Hello.', 'built: MESSAGE 0''s text');
    Check(Game.VocWord(200, 2) = 'LAMP', 'built: a word');
    Check(Game.LocationText(1) = 'A hall.', 'built: a location');
    Check(Game.SysMessageText(0) = 'It is dark.', 'built: a system message');
    Check((Game.FlagCount = 37) and (Game.ObjectsOffset = 37) and (Game.LocationFlag = 35),
      'built: The Quill''s flags');
    Check(QuillToPAW(21, False, 3) = 37, 'C action 21 is PAW 37 (GOTO)');
    Check(QuillToPAW(12, False, 1) = 37, 'A action 12 is PAW 37 (GOTO)');
    Check(QuillToPAW(7, True, 1) = 7, 'conditions are the same');
    Src := ExportDaadSource(Game, False, True);
    try
      Check(Pos('/PRO 5    ; Quill event table', Src.Text) > 0, 'export: event table as process 5');
      Check(Pos('/PRO 4    ; Quill status table', Src.Text) > 0, 'export: status table as process 4');
      Check(Pos('4 letters', Src.Text) > 0, 'export: the note on 4-letter words');
      Check(Pos('LAMP    200  noun', Src.Text) > 0, 'export: LAMP is a noun');
      Check(Pos('GET     50   verb', Src.Text) > 0, 'export: GET is a verb');
      Check(Pos('N       2    noun', Src.Text) > 0, 'export: N is a noun (up to 39)');
      Check(Pos('RESTART', Src.Text) > 0, 'export: DESC becomes RESTART');
      Check(Pos('ABILITY 4 255', Src.Text) > 0, 'export: the objects that can be carried');
    finally
      Src.Free;
    end;
  finally
    Game.Free;
  end;
end;

{ A real game: loaded (a tape with LOAD ""), found, and followed }
procedure TestGame(const RomDir, FileName: string);
var
  Sp: TSpectrum;
  Mem: TDaadMemory;
  Game: TDaadGame;
  Map: array[0..$FFFF] of Byte;
  A, I: Integer;
  Err, Name: string;
begin
  Name := ExtractFileName(FileName);
  Sp := TSpectrum.Create(sm48K, RomDir);
  Game := TDaadGame.Create;
  try
    if SameText(ExtractFileExt(FileName), '.tap') then
    begin
      Sp.FastLoad := True;
      for I := 1 to 150 do Sp.RunFrame;
      Sp.Tape.LoadTAP(FileName);
      Sp.TypeText('j""\n', Err);
      for I := 1 to 2500 do Sp.RunFrame;
    end
    else
      LoadZ80(Sp, FileName);
    for I := 1 to 100 do Sp.RunFrame;
    for A := 0 to $FFFF do Mem[A] := Sp.Peek(A);
    Check(Game.Load(Mem) and Game.IsQuill, Name + ': a Quill game');
    if not Game.Valid then Exit;
    Game.BuildMap(@Map);
    Sp.SetDaadMap(@Map);
    // A key first, for a game waiting for one after its introduction
    Sp.TypeText('\n', Err);
    for I := 1 to 100 do Sp.RunFrame;
    // Some lose the first key of an order: a second try
    for A := 1 to 2 do
      if Sp.BreakKind <> bkDaad then
      begin
        Sp.TypeText('look\n', Err);
        Sp.DaadStop := dsNext;
        for I := 1 to 400 do
        begin
          Sp.RunFrame;
          if Sp.BreakKind = bkDaad then Break;
        end;
      end;
    // Some tapes need more than LOAD "" (they stay in BASIC): only the
    // games that stop are checked, and at least one must
    if Sp.BreakKind <> bkDaad then
      WriteLn(Format('  %s: Quill %s found, not followed (it didn''t stop at a condact)',
        [Name, Copy('A?C', Game.QuillVersion, 1)]))
    else
    begin
      Inc(Followed);
      Check(Game.CondactAt(Sp.DaadFetch) >= 0, Name + ': on a condact of the database');
      Check(Sp.Cpu.IX.W = $5B00, Name + ': IX at the flags');
      WriteLn(Format('  %s: Quill %s, %d entries, %d condacts, %d objects, %d locations',
        [Name, Copy('A?C', Game.QuillVersion, 1), Length(Game.Entries), Length(Game.Condacts),
         Game.NumObjects, Game.NumLocations]));
    end;
  finally
    Game.Free;
    Sp.Free;
  end;
end;

var
  Info: TSearchRec;
begin
  TestBuilt;
  if (ParamCount > 1) and DirectoryExists(ParamStr(2)) then
    if FindFirst(IncludeTrailingPathDelimiter(ParamStr(2)) + '*', faAnyFile, Info) = 0 then
    begin
      repeat
        // Snapshots and tapes only
        if ((Info.Attr and faDirectory) = 0) and
           (Pos(UpperCase(ExtractFileExt(Info.Name)), '.TAP.Z80.SNA') > 0) then
          TestGame(ParamStr(1), IncludeTrailingPathDelimiter(ParamStr(2)) + Info.Name);
      until FindNext(Info) <> 0;
      FindClose(Info);
      Check(Followed > 0, 'no game was followed to a condact');
    end;
  if Failures = 0 then WriteLn('The Quill: all passed')
  else
  begin
    WriteLn('The Quill: ', Failures, ' failures');
    Halt(1);
  end;
end.

{ DaadExport: the source of a DAAD or PAW game read from memory, for the
  Adventure Debugger. Two formats, as unDRC and unDAAD write them:
    DSF  DAAD Ready / DRC: texts in quotes with #n, #k...; entries start
         with ">"; indirection is @n; v3 code (INDIR, XMES) and Maluva
         (EXTERN with a third byte) as DRC writes it.
    SCE  the original DAAD compiler: texts on the line after their number
         with \r, \k...; a /TOK section; indirection is [n].
  A PAW game is written as it is (its condacts, no object attributes), or
  converted to DAAD (DSF only) as PAWS2DAAD does: condacts DAAD lacks
  replaced (with a "PAWS2DAAD note" comment), and the processes arranged as
  DAAD's empty database (DAAD Ready's BLANK_EN.DSF) has them: its processes
  0, 1, 2 and 6, the PAW response table as 5, PAW processes 1 and 2 as 3
  and 4, PAW processes 3-6 after the last one, the rest with their numbers.
  The DSF file is ISO-8859-1 and the SCE file code page 437 (MS-DOS), as
  their compilers expect.
  A Quill game (PAW's predecessor, read with PAW's condact numbers) is only
  converted to DAAD (DSF): its event table becomes process 5 and its status
  table process 4 (DAAD's process 1 calls it every turn, before the order,
  as The Quill runs it); its words, which have no type, become nouns
  (up to 39, which DAAD lets act as verbs) or verbs or nouns as they are
  used (see QuillVocabulary); objects weigh 1, and those whose word is 200 or more (The Quill's
  wearable ones) are wearable. }
unit DaadExport;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Daad;

{ The whole source. ToDaad: a PAW game converted to DAAD (DSF only). }
function ExportDaadSource(Game: TDaadGame; Sce: Boolean; ToDaad: Boolean = False): TStringList;
{ One process, as in the /PRO section of the source }
function ExportDaadProcess(Game: TDaadGame; Proc: Integer; Sce: Boolean;
  ToDaad: Boolean = False): TStringList;
{ Lines (UTF-8) to the file in the encoding of the format }
procedure SaveDaadSource(Lines: TStrings; const FileName: string; Sce: Boolean);

implementation

{$I DaadTemplate.inc}

const
  WORD_TYPES: array[0..6] of string = ('verb', 'adverb', 'noun', 'adjective', 'preposition',
    'conjugation', 'pronoun');
  // Maluva commands (EXTERN n command) as DRC writes them
  MALUVA: array[0..10] of string = ('XPICTURE', 'XSAVE', 'XLOAD', 'XMES', 'XPART', 'XBEEP',
    'XSPLITSCR', 'XUNDONE', 'XNEXTCLS', 'XNEXTRESET', 'XSPEED');
  // PAW: DESC, END, DONE, OK and NOTDONE end an entry
  PAW_TERMINATORS = [19, 21, 22, 23, 103];
  NOTE = '; PAWS2DAAD note: ';
  INDENT = '                ';
  // PAW's auto-decrement flags, as DAAD's version 1 did them: added (as a
  // comment) after the first entry of process 1, as PAWS2DAAD explains
  AUTO_FLAGS: array[0..10] of string = (
    '; PAWS2DAAD note: PAW decremented flags 5 to 10 by itself, DAAD does not.',
    '; If the game uses them, remove the semicolons of this entry.',
    ';> _       _     MINUS   5       1       ; Update auto flags',
    ';                MINUS   6       1       ; These are not supported anymore',
    ';                MINUS   7       1       ; as we use the low section as',
    ';                MINUS   8       1       ; a small stack',
    ';                NOTZERO 0               ; But should you need them',
    ';                MINUS   9       1       ; this is the Version 1 DAAD code!',
    ';                ABSENT  0',
    ';                MINUS   10      1',
    '');

{ The vocabulary type of a condact's parameter, -1 if not a word }
function WordParam(Game: TDaadGame; Opcode, K: Integer): Integer;
begin
  Result := -1;
  case Opcode of
    36: if not Game.IsPAW then   // SYNONYM verb noun (TIMEOUT in PAW)
          if K = 0 then Result := 0 else Result := 2;
    17: Result := 1;                                  // ADVERB
    69: Result := 2;                                  // NOUN2
    16, 70: Result := 3;                              // ADJECT1, ADJECT2
    68: Result := 4;                                  // PREP
  end;
end;

function LocText(Loc: Integer; Sce: Boolean): string;
begin
  if Sce then Exit(IntToStr(Loc));
  case Loc of
    252: Result := 'NOT_CREATED';
    253: Result := 'WORN';
    254: Result := 'CARRIED';
    255: Result := 'HERE';
  else
    Result := IntToStr(Loc);
  end;
end;

function Separator: string;
begin
  Result := ';---------------------------------------------------------------------------';
end;

{ A word for an entry or a parameter; PAW's "any word" (*) is DAAD's _ }
function WordOf(Game: TDaadGame; Id, Kind: Integer; ToDaad: Boolean): string;
begin
  Result := Game.VocWord(Id, Kind);
  if ToDaad and (Result = '*') then Result := '_';
end;

{ The process a PAW process becomes in DAAD (see the unit's comment) }
function DaadProcess(Game: TDaadGame; P: Integer): Integer;
begin
  if Game.IsQuill then
  begin
    if P = 0 then Result := 5 else Result := 4;
    Exit;
  end;
  case P of
    0: Result := 5;
    1: Result := 3;
    2: Result := 4;
    3..6: Result := Max(7, Game.NumProcesses) + P - 3;
  else
    Result := P;
  end;
end;

{ A PAW condact as DAAD has it: lines of source (the first one, the
  condact; the others, more condacts or comments) }
function PawToDaad(Game: TDaadGame; const C: TDaadCondact; const Name, Params: string): TStringArray;
var
  Was: string;

  procedure Lines(const A: array of string);
  var
    I: Integer;
  begin
    SetLength(Result, Length(A));
    for I := 0 to High(A) do Result[I] := A[I];
  end;

begin
  Was := Trim(Name + ' ' + Params);
  if Name = 'DESC' then Lines(['RESTART  ' + NOTE + 'it was DESC'])
  else if Name = 'INVEN' then
    Lines(['SYSMESS  9', 'LISTAT   CARRIED', 'SYSMESS  10', 'LISTAT   WORN',
      'DONE     ' + NOTE + 'it was INVEN'])
  else if Name = 'TIMEOUT' then Lines(['HASAT    TIMEOUT  ' + NOTE + 'it was TIMEOUT'])
  else if (Name = 'SAVE') or (Name = 'LOAD') or (Name = 'PARSE') then
    Lines([Format('%-8s 0  %sit was just %s', [Name, NOTE, Name])])
  else if Name = 'PROMPT' then
    Lines([Format('LET      fPrompt %d  %sit was %s', [C.Params[0], NOTE, Was])])
  else if Name = 'EXTERN' then
    Lines([Format('EXTERN   %d 0  %sit was %s (one parameter in PAW)', [C.Params[0], NOTE, Was])])
  else if Name = 'INPUT' then
    Lines([Format('INPUT    %d 0  %sit was %s (one parameter in PAW)', [C.Params[0], NOTE, Was])])
  else if Name = 'RESET' then
    Lines(['RESET    ' + NOTE + 'it was ' + Was + ' (no parameter in DAAD)'])
  else if (Name = 'TURNS') or (Name = 'SCORE') or (Name = 'CHARSET') or (Name = 'MODE') or
    (Name = 'GRAPHIC') or (Name = 'LINE') or (Name = 'PROTECT') then
    Lines([NOTE + 'it was ' + Was + ' (not in DAAD)'])
  else if Name = 'PROCESS' then
  begin
    Was := Format('PROCESS  %d', [DaadProcess(Game, C.Params[0])]);
    if DaadProcess(Game, C.Params[0]) <> C.Params[0] then
      Was := Was + Format('  %sit was PROCESS %d', [NOTE, C.Params[0]]);
    Lines([Was]);
  end
  else
    Lines([Format('%-8s %s', [Name, Params])]);
end;

var
  { The Quill: the DAAD type each word got in the vocabulary (QuillVocabulary) }
  QuillTypes: record
    Ready: Boolean;
    Verb, Noun: array[0..255] of Boolean;
    Number: array[0..255] of Integer;   // its number in DAAD
  end;

{ A Quill word can be the verb (Verb) or the noun of an entry in DAAD }
function QuillWordFits(Id: Integer; Verb: Boolean): Boolean;
begin
  if (Id = 255) or not QuillTypes.Ready then Exit(True);
  if Verb then Result := QuillTypes.Verb[Id] or (QuillTypes.Noun[Id] and (QuillTypes.Number[Id] <= 39))
  else Result := QuillTypes.Noun[Id];
end;

procedure AddProcess(Game: TDaadGame; P: Integer; Sce, ToDaad: Boolean; L: TStrings);
var
  E, K, N, J, Off, Line: Integer;
  En: TDaadEntry;
  C: TDaadCondact;
  Name, Params, Head, Indir2, Verb, Noun: string;
  First, Ended: Boolean;
  Out: TStringArray;
  EntryStart, Line2: Integer;
begin
  if ToDaad and Game.IsQuill then
  begin
    if P = 0 then L.Add('/PRO 5    ; Quill event table')
    else L.Add('/PRO 4    ; Quill status table');
  end
  else if ToDaad then L.Add(Format('/PRO %d    ; PAW process %d', [DaadProcess(Game, P), P]))
  else L.Add(Format('/PRO %d', [P]));
  for E := 0 to Game.Processes[P].EntryCount - 1 do
  begin
    En := Game.Entries[Game.Processes[P].FirstEntry + E];
    Verb := WordOf(Game, En.Verb, 0, ToDaad);
    Noun := WordOf(Game, En.Noun, 2, ToDaad);
    // PAW processes 1 and 2 (The Quill's status table) run every entry:
    // DAAD's must be "_ _"
    if ToDaad and (P in [1, 2]) and ((Verb <> '_') or (Noun <> '_')) then
    begin
      L.Add(Format('%sit was: > %s %s', [NOTE, Verb, Noun]));
      Verb := '_';
      Noun := '_';
    end;
    EntryStart := L.Count;
    if Sce then
    begin
      L.Add('');
      L.Add(Format('%s %s', [Verb, Noun]));
      Head := ' ';
    end
    else
      Head := Format('> %-6s %-6s ', [Verb, Noun]);
    First := True;
    Ended := False;
    Indir2 := '';
    for K := 0 to En.CondactCount - 1 do
    begin
      C := Game.Condacts[En.FirstCondact + K];
      // v3: INDIR f makes the next condact's second parameter @f
      if not Game.IsPAW and (Game.Version >= 3) and (C.Opcode = OP_INDIR) then
      begin
        Indir2 := IntToStr(C.Params[0]);
        Continue;
      end;
      if Game.IsPAW then Name := PAW_CONDACT_NAMES[C.Opcode] else Name := CONDACT_NAMES[C.Opcode];
      if Game.IsPAW then
      else if (Game.Version >= 3) and (C.Opcode = OP_XMES) then Name := 'XMES'
      else if (Game.Version >= 3) and (C.Opcode = OP_SETAT) then Name := 'SETAT';
      Params := '';
      for N := 0 to C.ParamCount - 1 do
      begin
        J := WordParam(Game, C.Opcode, N);
        if (J >= 0) and not C.Indirect then
          Params := Params + WordOf(Game, C.Params[N], J, ToDaad)
        else if (N = 0) and C.Indirect then
        begin
          if Sce then Params := Params + '[' + IntToStr(C.Params[N]) + ']'
          else Params := Params + '@' + IntToStr(C.Params[N]);
        end
        else if (N = 1) and (Indir2 <> '') then
        begin
          if Sce then Params := Params + '[' + Indir2 + ']' else Params := Params + '@' + Indir2;
        end
        else
          Params := Params + IntToStr(C.Params[N]);
        Params := Params + ' ';
      end;
      Params := TrimRight(Params);
      Indir2 := '';
      if Game.IsPAW then
      else if not Sce then
      begin
        // v3 XMES and Maluva's XMES: the text is in an XMB file, not in memory
        if (Game.Version >= 3) and (C.Opcode = OP_XMES) then
        begin
          Off := C.Params[0] + C.Params[1] * 256;
          Params := Format('"[XMB offset %d]" ; XMES %d %d: its text is in the XMB file',
            [Off, C.Params[0], C.Params[1]]);
        end
        else if (Game.Version = 2) and (C.Opcode = OP_EXTERN) and (C.ParamCount = 3) then
        begin
          if C.Params[1] = 3 then
          begin
            Off := C.Params[0] + C.Params[2] * 256;
            Name := 'XMES';
            Params := Format('"[XMB offset %d]" ; EXTERN %d 3 %d: its text is in the XMB file',
              [Off, C.Params[0], C.Params[2]]);
          end
          else
          begin
            Name := MALUVA[C.Params[1]];
            Params := Format('%s%d %d ; EXTERN %d %d %d', [Copy('@', 1, Ord(C.Indirect)),
              C.Params[0], C.Params[2], C.Params[0], C.Params[1], C.Params[2]]);
          end;
        end;
      end
      else if (Game.Version = 2) and (C.Opcode = OP_EXTERN) and (C.ParamCount = 3) then
        Params := Params + ' ; Maluva: one more byte, ' + IntToStr(C.Params[2]);
      if ToDaad then Out := PawToDaad(Game, C, Name, Params)
      else
      begin
        SetLength(Out, 1);
        Out[0] := Format('%-8s %s', [Name, Params]);
      end;
      for Line := 0 to High(Out) do
      begin
        // PAWS2DAAD leaves what follows a terminator as a comment
        if Ended then Out[Line] := NOTE + 'condact after terminator: ' + Out[Line];
        if First and not Sce then L.Add(TrimRight(Head + Out[Line]))
        else if Sce then L.Add(TrimRight(Head + Out[Line]))
        else L.Add(TrimRight(INDENT + Out[Line]));
        First := False;
      end;
      if ToDaad and (C.Opcode in PAW_TERMINATORS) then Ended := True;
    end;
    if First and not Sce then L.Add(TrimRight(Head));   // an entry with no condacts
    // The Quill: a word that got the other type in DAAD (QuillVocabulary)
    // can't be written: the entry is left as a comment
    if ToDaad and Game.IsQuill and not (QuillWordFits(En.Verb, True) and QuillWordFits(En.Noun, False)) then
    begin
      for Line2 := EntryStart to L.Count - 1 do L[Line2] := '; ' + L[Line2];
      L.Insert(EntryStart, Format('%sthe words of this entry (%s %s) have the other type in DAAD',
        [NOTE, Verb, Noun]));
    end;
    if not Sce then L.Add('');
  end;
end;

procedure QuillTypesOf(Game: TDaadGame); forward;

function ExportDaadProcess(Game: TDaadGame; Proc: Integer; Sce: Boolean; ToDaad: Boolean): TStringList;
begin
  Result := TStringList.Create;
  if Game.IsQuill then
    Result.Add(Format('; Process %d, exported by ochenta from the Quill game in memory', [Proc]))
  else if Game.IsPAW then
    Result.Add(Format('; Process %d, exported by ochenta from the PAW game in memory', [Proc]))
  else
    Result.Add(Format('; Process %d, exported by ochenta from the DAAD game in memory', [Proc]));
  if ToDaad then
    Result.Add(Format('; Converted from %s to DAAD: check it before using it',
      [EngineName(Game.Engine)]));
  if Game.IsQuill then QuillTypesOf(Game);
  Result.Add('');
  AddProcess(Game, Proc, Sce, ToDaad and Game.IsPAW, Result);
end;

{ An object's noun and adjective (The Quill: one word, version A none) }
function ObjectNoun(Game: TDaadGame; I: Integer; ToDaad: Boolean): string;
begin
  if Game.IsQuill then
  begin
    if Game.PosObjectWords = 0 then Exit('_');
    // A word that is a verb in DAAD can't be an object's
    if not QuillWordFits(Game.ByteAt(Word(Game.PosObjectWords + I)), False) then Exit('_');
    Exit(WordOf(Game, Game.ByteAt(Word(Game.PosObjectWords + I)), 2, ToDaad));
  end;
  Result := WordOf(Game, Game.ByteAt(Word(Game.PosObjectWords + I * 2)), 2, ToDaad);
end;

function ObjectAdjective(Game: TDaadGame; I: Integer; ToDaad: Boolean): string;
begin
  if Game.IsQuill then Exit('_');
  Result := WordOf(Game, Game.ByteAt(Word(Game.PosObjectWords + I * 2 + 1)), 3, ToDaad);
end;

{ The Quill's words (4 letters and a number) with a DAAD type. DAAD lets
  nouns up to 39 act as verbs, and DRC wants one type per word: words up to
  39 are nouns; the others verbs (the first word of an entry, a connection),
  nouns (the second word, an object's word, or unused), and those used both
  ways become nouns with a free number up to 39 (or verbs, with a note, if
  there is none left) }
procedure QuillVocabulary(Game: TDaadGame; const Voc: array of TStringList; Notes: TStrings);
var
  AsVerb, AsNoun, Used: array[0..255] of Boolean;
  NewId: array[0..255] of Integer;
  E, I, Id, K, B, Free: Integer;
  A: Word;
  S: string;
begin
  FillChar(AsVerb, SizeOf(AsVerb), 0);
  FillChar(AsNoun, SizeOf(AsNoun), 0);
  FillChar(Used, SizeOf(Used), 0);
  for E := 0 to High(Game.Entries) do
  begin
    AsVerb[Game.Entries[E].Verb] := True;
    AsNoun[Game.Entries[E].Noun] := True;
  end;
  for I := 0 to Game.NumLocations - 1 do
  begin
    A := Game.WordAt(Word(Game.PosConnections + I * 2));
    K := 0;
    while (Game.ByteAt(A) <> 255) and (K < 64) do
    begin
      AsVerb[Game.ByteAt(A)] := True;
      A := Word(A + 2);
      Inc(K);
    end;
  end;
  if Game.PosObjectWords <> 0 then
    for I := 0 to Game.NumObjects - 1 do AsNoun[Game.ByteAt(Word(Game.PosObjectWords + I))] := True;
  A := Game.PosVocabulary;
  I := 0;
  while (Game.ByteAt(A) <> 0) and (I < 4000) do
  begin
    Used[Game.ByteAt(Word(A + 4))] := True;
    A := Word(A + 5);
    Inc(I);
  end;
  // Words up to 39 are nouns (verbs too); the others verbs if only used as
  // verbs, else nouns. Then the numbers for those used both ways.
  for Id := 0 to 255 do
  begin
    NewId[Id] := Id;
    QuillTypes.Verb[Id] := (Id >= 40) and AsVerb[Id] and not AsNoun[Id];
    QuillTypes.Noun[Id] := not QuillTypes.Verb[Id];
  end;
  QuillTypes.Ready := True;
  for Id := 0 to 255 do QuillTypes.Number[Id] := Id;
  Free := 1;
  for Id := 40 to 254 do
    if Used[Id] and AsVerb[Id] and AsNoun[Id] then
    begin
      while (Free <= 39) and Used[Free] do Inc(Free);
      if Free <= 39 then
      begin
        NewId[Id] := Free;
        QuillTypes.Number[Id] := Free;
        QuillTypes.Verb[Id] := False;
        QuillTypes.Noun[Id] := True;
        Used[Free] := True;
        Notes.Add(Format('; Word %d is a verb and a noun in the game: noun %d here (DAAD lets ' +
          'nouns up to 39 act as verbs).', [Id, Free]));
      end
      else
      begin
        QuillTypes.Verb[Id] := True;
        QuillTypes.Noun[Id] := False;
        Notes.Add(Format('; PAWS2DAAD note: word %d is a verb and a noun in the game, and there ' +
          'is no free noun number up to 39 for it: it is a verb here, and the entries (or ' +
          'objects) that use it as a noun are left as comments.', [Id]));
      end;
    end;
  A := Game.PosVocabulary;
  I := 0;
  while (Game.ByteAt(A) <> 0) and (I < 4000) do
  begin
    S := '';
    for K := 0 to 3 do
    begin
      B := 255 - Game.ByteAt(Word(A + K));
      if B in [32..126] then S := S + Chr(B);
    end;
    S := TrimRight(S);
    Id := Game.ByteAt(Word(A + 4));
    A := Word(A + 5);
    Inc(I);
    // 255 is "no word" (_), which DAAD has without saying so
    if Id = 255 then Continue;
    if QuillTypes.Verb[Id] then
      Voc[0].AddObject(Format('%.3d %s', [Id, S]), TObject(PtrInt(Id)))
    else
      Voc[2].AddObject(Format('%.3d %s', [NewId[Id], S]), TObject(PtrInt(NewId[Id])));
  end;
end;

{ The DAAD types of The Quill's words, for a process exported by itself }
procedure QuillTypesOf(Game: TDaadGame);
var
  Voc: array[0..6] of TStringList;
  Notes: TStringList;
  K: Integer;
begin
  for K := 0 to 6 do Voc[K] := TStringList.Create;
  Notes := TStringList.Create;
  try
    QuillVocabulary(Game, Voc, Notes);
  finally
    for K := 0 to 6 do Voc[K].Free;
    Notes.Free;
  end;
end;

function ExportDaadSource(Game: TDaadGame; Sce: Boolean; ToDaad: Boolean): TStringList;
var
  L: TStringList;
  I, K, T, Id, Kind, Loc, B, Last: Integer;
  A, Weights, Attrs: Word;
  S, Txt, Attr: string;
  Voc: array[0..6] of TStringList;
  Pro: array of Integer;   // ToDaad: the PAW process of each DAAD one, -1 the template's
  QuillNotes: TStringList; // The Quill: what was done with its words

  procedure Texts(const Section, Comment: string; Count: Integer; Table: Word);
  var
    N: Integer;
  begin
    L.Add(Separator);
    L.Add(Format('/%s    ;%s', [Section, Comment]));
    for N := 0 to Count - 1 do
    begin
      Txt := Game.SourceText(Game.WordAt(Word(Table + N * 2)), Sce);
      if Sce then
      begin
        L.Add('/' + IntToStr(N));
        L.Add(Txt);
      end
      else
        L.Add(Format('/%d "%s"', [N, Txt]));
    end;
  end;

  procedure AddLines(const A: array of string);
  var
    N: Integer;
  begin
    for N := 0 to High(A) do L.Add(A[N]);
  end;

begin
  ToDaad := ToDaad and Game.IsPAW and not Sce;
  L := TStringList.Create;
  Result := L;
  L.Add(Separator);
  if Game.IsQuill then
    L.Add(Format('; Exported by ochenta from the Quill game in memory (database version %s)',
      [Copy('A?C', Game.QuillVersion, 1)]))
  else if Game.IsPAW then L.Add('; Exported by ochenta from the PAW game in memory')
  else
  begin
    L.Add('; Exported by ochenta from the DAAD game in memory');
    L.Add(Format('; DAAD version %d, %s, DDB at %.4Xh', [Game.Version,
      Copy('English Spanish', Game.Language * 8 + 1, 7), Game.Base]));
  end;
  L.Add(Format('; Objects %d, locations %d, messages %d, system messages %d, processes %d',
    [Game.NumObjects, Game.NumLocations, Game.NumMessages, Game.NumSysMessages, Game.NumProcesses]));
  if ToDaad then
  begin
    L.Add('; Converted to DAAD as PAWS2DAAD does, with the processes of DAAD Ready''s');
    L.Add('; empty database: check every "PAWS2DAAD note" and test the game.');
  end;
  if Game.IsQuill then
  begin
    L.Add('; The Quill: the event table is process 5 and the status table process 4.');
    L.Add(Format('; Objects that can be carried: %d (in DAAD, ABILITY %d 255 in process 6).',
      [Game.QuillCarry, Game.QuillCarry]));
  end;
  if not Sce and (Game.Version >= 3) then
    L.Add('; A DAAD v3 database: compile it with DRF''s -v3 option');
  if not Sce and not Game.IsPAW then
  begin
    L.Add('; PAUSE and BEEP durations are as in the database: DRC scales them for');
    L.Add('; the target (x0.975 for ZX 48K and ESXDOS, x0.5 for 128K, +3, Next and Uno)');
    L.Add('; XMES texts are in the XMB file, not in memory: they are left as markers');
  end;
  L.Add(Separator);
  L.Add('');
  if ToDaad then
  begin
    AddLines(TEMPLATE_HEADER);
    L.Add('');
  end;
  L.Add('/CTL');
  L.Add('_');

  // Tokens: only the original compiler takes them (DRC makes its own)
  if Sce and not Game.IsPAW and (Game.PosTokens <> 0) then
  begin
    L.Add('/TOK');
    for T := 0 to 127 do
      if Game.Token(T) <> '' then L.Add(StringReplace(Game.Token(T), ' ', '_', [rfReplaceAll]));
  end;

  // Vocabulary, by type and number
  for K := 0 to 6 do Voc[K] := TStringList.Create;
  QuillNotes := TStringList.Create;
  try
    if Game.IsQuill then QuillVocabulary(Game, Voc, QuillNotes)
    else
    begin
    A := Game.PosVocabulary;
    I := 0;
    while (Game.ByteAt(A) <> 0) and (I < 4000) do
    begin
      S := '';
      for K := 0 to 4 do
      begin
        B := 255 - Game.ByteAt(Word(A + K));
        if not Game.IsPAW and (B in [16..31]) then S := S + SPANISH[B]
        else if B in [32..126] then S := S + Chr(B);
      end;
      Id := Game.ByteAt(Word(A + 5));
      Kind := Game.ByteAt(Word(A + 6));
      if Kind <= 6 then
        Voc[Kind].AddObject(Format('%.3d %s', [Id, TrimRight(S)]), TObject(PtrInt(Id)));
      A := Word(A + 7);
      Inc(I);
    end;
    end;
    L.Add(Separator);
    L.Add('/VOC    ;Vocabulary');
    if Game.IsQuill then
    begin
      L.Add('; PAWS2DAAD note: The Quill''s words have 4 letters and DAAD''s 5: make them');
      L.Add('; longer where the fifth letter tells words apart (EXAMine, LANTern...).');
      L.Add('; The Quill''s words have no type: those up to 39 are nouns (DAAD lets them');
      L.Add('; act as verbs, as directions do), the others verbs or nouns as the game');
      L.Add('; uses them.');
      L.AddStrings(QuillNotes);
    end;
    for K := 0 to 6 do
    begin
      if Voc[K].Count = 0 then Continue;
      Voc[K].Sort;
      L.Add('');
      L.Add('; ' + UpperCase(WORD_TYPES[K]) + 'S');
      for I := 0 to Voc[K].Count - 1 do
      begin
        S := Copy(Voc[K][I], 5, MaxInt);
        L.Add(Format('%-8s%-5d%s', [S, PtrInt(Voc[K].Objects[I]), WORD_TYPES[K]]));
      end;
    end;
  finally
    for K := 0 to 6 do Voc[K].Free;
    QuillNotes.Free;
  end;

  if Game.IsQuill then
  begin
    // Version A's are one after another: by address
    L.Add(Separator);
    L.Add('/STX    ;System messages');
    for I := 0 to Game.NumSysMessages - 1 do
      L.Add(Format('/%d "%s"', [I, Game.SourceText(Game.SysMessageAddr(I), False)]));
  end
  else
    Texts('STX', 'System messages', Game.NumSysMessages, Game.PosSysMessages);
  // DAAD has more system messages than PAW: those of the empty database
  if ToDaad then
    for I := Game.NumSysMessages to High(TEMPLATE_STX) do
      L.Add(Format('/%d "%s"   ; from the DAAD empty database', [I, TEMPLATE_STX[I]]));
  Texts('MTX', 'User messages', Game.NumMessages, Game.PosMessages);
  Texts('OTX', 'Object texts', Game.NumObjects, Game.PosObjects);
  Texts('LTX', 'Location texts', Game.NumLocations, Game.PosLocations);

  // Connections: direction word and destination
  L.Add(Separator);
  L.Add('/CON    ;Connections');
  for I := 0 to Game.NumLocations - 1 do
  begin
    A := Game.WordAt(Word(Game.PosConnections + I * 2));
    S := '/' + IntToStr(I);
    if Sce then L.Add(S);
    K := 0;
    while (Game.ByteAt(A) <> 255) and (K < 64) do
    begin
      Txt := WordOf(Game, Game.ByteAt(A), 0, ToDaad) + ' ' + IntToStr(Game.ByteAt(Word(A + 1)));
      if Sce then L.Add(Txt) else S := S + ' ' + Txt;
      A := Word(A + 2);
      Inc(K);
    end;
    if not Sce then L.Add(S);
  end;

  // Objects: where they start, weight, container, wearable, the 16 user
  // attributes (15 to 0; PAW has none), noun and adjective
  if Game.IsQuill then
  begin
    Weights := 0;
    Attrs := 0;
  end
  else if Game.IsPAW then
  begin
    Weights := Game.WordAt($FFEB);
    Attrs := 0;
  end
  else
  begin
    Weights := Game.WordAt(Word(Game.Base + 28));
    Attrs := Game.WordAt(Word(Game.Base + 30));
  end;
  L.Add(Separator);
  L.Add('/OBJ    ;Objects');
  L.Add(';obj  starts at   weight  c w  5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0   noun     adjective');
  for I := 0 to Game.NumObjects - 1 do
  begin
    Loc := Game.ByteAt(Word(Game.PosInitiallyAt + I));
    if Game.IsQuill then
    begin
      // Weight 1; wearable if its word is 200 or more
      B := 1;
      if (Game.PosObjectWords <> 0) and (Game.ByteAt(Word(Game.PosObjectWords + I)) in [200..254]) then
        B := B or $80;
    end
    else
      B := Game.ByteAt(Word(Weights + I));
    Attr := '';
    for K := 15 downto 0 do
      if not Game.IsPAW and ((Game.WordAt(Word(Attrs + I * 2)) and (1 shl K)) <> 0) then
        Attr := Attr + 'Y '
      else
        Attr := Attr + '_ ';
    S := Format('/%-4d %11s %7d   %s %s  %s  %-8s %s', [I, LocText(Loc, Sce), B and $3F,
      Copy('_Y', Ord((B and $40) <> 0) + 1, 1), Copy('_Y', Ord((B and $80) <> 0) + 1, 1), Attr,
      ObjectNoun(Game, I, ToDaad), ObjectAdjective(Game, I, ToDaad)]);
    L.Add(TrimRight(S));
  end;

  if ToDaad then
  begin
    // DAAD's processes in order: the template's and the PAW ones moved
    Last := 6;
    for I := 0 to Game.NumProcesses - 1 do Last := Max(Last, DaadProcess(Game, I));
    SetLength(Pro, Last + 1);
    for I := 0 to Last do Pro[I] := -2;   // none
    for I := 0 to 2 do Pro[I] := -1;
    Pro[6] := -1;
    for I := 0 to Game.NumProcesses - 1 do Pro[DaadProcess(Game, I)] := I;
    for I := 0 to Last do
    begin
      L.Add(Separator);
      case Pro[I] of
        -2: L.Add(Format('/PRO %d', [I]));
        -1:
          case I of
            0: AddLines(TEMPLATE_PRO0);
            1:
              for K := 0 to High(TEMPLATE_PRO1) do
              begin
                L.Add(TEMPLATE_PRO1[K]);
                if K = 1 then AddLines(AUTO_FLAGS);   // after its first entry
              end;
            2: AddLines(TEMPLATE_PRO2);
            6: AddLines(TEMPLATE_PRO6);
          end;
      else
        AddProcess(Game, Pro[I], False, True, L);
      end;
    end;
  end
  else
    for I := 0 to Game.NumProcesses - 1 do
    begin
      L.Add(Separator);
      AddProcess(Game, I, Sce, False, L);
    end;
  L.Add(Separator);
  L.Add('/END');
end;

{ UTF-8 text in ISO-8859-1 or code page 437; other characters as "?" }
function Encode(const S: string; Sce: Boolean): RawByteString;
const
  // Latin-1 code points of the characters DAAD has, and their CP437 bytes
  LATIN: array[0..15] of Integer = ($AA, $A1, $BF, $AB, $BB, $E1, $E9, $ED, $F3, $FA, $F1, $D1,
    $E7, $C7, $FC, $DC);
  CP437: array[0..15] of Byte = ($A6, $AD, $A8, $AE, $AF, $A0, $82, $A1, $A2, $A3, $A4, $A5,
    $87, $80, $81, $9A);
var
  U: UnicodeString;
  I, K, Code: Integer;
  Ch: AnsiChar;
begin
  U := UTF8Decode(S);
  SetLength(Result, Length(U));
  for I := 1 to Length(U) do
  begin
    Code := Ord(U[I]);
    if Code < 128 then Ch := AnsiChar(Code)
    else
    begin
      Ch := '?';
      for K := 0 to High(LATIN) do
        if LATIN[K] = Code then
        begin
          if Sce then Ch := AnsiChar(CP437[K]) else Ch := AnsiChar(Code);
          Break;
        end;
    end;
    Result[I] := Ch;
  end;
end;

procedure SaveDaadSource(Lines: TStrings; const FileName: string; Sce: Boolean);
var
  F: TFileStream;
  I: Integer;
  Line: RawByteString;
begin
  F := TFileStream.Create(FileName, fmCreate);
  try
    for I := 0 to Lines.Count - 1 do
    begin
      Line := Encode(Lines[I], Sce) + #13#10;
      F.WriteBuffer(Line[1], Length(Line));
    end;
  finally
    F.Free;
  end;
end;

end.

{ Daad: reads the database (DDB) of a DAAD game from a copy of the
  Spectrum's memory, for the DAAD debugger.

  The DDB is usually at 8400 (DAAD v2 and v3, as written by DC 2.0+ and
  DRC); older games have it elsewhere (La Diosa de Cozumel at 8380), so the
  rest of memory is searched too. Its header (all addresses absolute,
  little endian):
    0  version (2 or 3)        1  machine (high nibble, 1 = ZX) and language
    2  95                      3  objects   4 locations   5 user messages
    6  system messages         7  processes
    8  tokens                 10  process table   12 object texts
   14  location texts         16  user messages   18 system messages
   20  connections            22  vocabulary      24 objects' initial location
   26  object words           28  object weights  30 object attributes
   32  file length
  A process is a list of 4-byte entries (verb, noun, address of its
  condacts) ended by a 0 verb; an entry's condacts end with 255 (DRC leaves
  it out after DONE, OK, NOTDONE, SKIP, RESTART and REDO). A condact is its
  opcode (bit 7: the first parameter is a flag number holding the value)
  and 0 to 2 parameters. Texts are XORed with 255; bytes below 128 are
  tokens (compressed text). }
unit Daad;

{$mode objfpc}{$H+}
{$R-}{$Q-}

interface

uses
  SysUtils;

const
  DDB_BASE = $8400;
  { Object locations with a meaning }
  LOC_NOT_CREATED = 252;
  LOC_WORN = 253;
  LOC_CARRIED = 254;

type
  TDaadMemory = array[0..$FFFF] of Byte;
  PDaadMemory = ^TDaadMemory;

  TDaadCondact = record
    Addr: Word;
    Opcode: Byte;          // without the indirection bit
    Indirect: Boolean;
    ParamCount: Integer;
    Params: array[0..2] of Byte;
    Entry: Integer;
  end;

  TDaadEntry = record
    Header: Word;          // address of its verb byte
    Verb, Noun: Byte;
    Code: Word;            // address of its first condact
    Process: Integer;
    FirstCondact, CondactCount: Integer;
  end;

  TDaadProcess = record
    Table: Word;
    FirstEntry, EntryCount: Integer;
  end;

  { Reads flag N for a condition }
  TDaadFlagReader = function(N: Byte): Byte of object;

  { A breakpoint condition on flags: "f0 = 3 AND f10>11". fN is flag N, @fN
    the flag whose number is in flag N; numbers are decimal; = (or ==), <>
    (or !=), <, >, <=, >=; AND, OR, NOT and parentheses. }
  TDaadCondition = class
  private
    FCode: array of Integer;   // RPN: operations and their operands
  public
    { nil (and Error says why) if Text is not a valid condition }
    class function Parse(const Text: string; out Error: string): TDaadCondition;
    function Holds(Flag: TDaadFlagReader): Boolean;
  end;

  TDaadGame = class
  private
    FMem: TDaadMemory;
    FValid: Boolean;
    FCondactAt: array[0..$FFFF] of Integer;   // condact index + 1, 0 if none
    FTokens: array[0..127] of string;
    FBadEntry: Boolean;      // an entry's condacts don't end
    function W(Addr: Word): Word;
    function ParamsOf(Opcode: Byte): Integer;
    procedure ReadTokens;
    procedure ReadProcesses;
    function TextAt(Addr: Word): string;
    function TryAt(A: Word): Boolean;
    function TryPAW: Boolean;
    function PAWTextAt(Addr: Word): string;
  public
    IsPAW: Boolean;           // a PAW game (DAAD's predecessor) instead of DAAD
    PosAbbreviations: Word;   // PAW: compressed text
    Base: Word;               // address of the header
    Version: Integer;
    Language: Integer;        // 0 English, 1 Spanish
    NumObjects, NumLocations, NumMessages, NumSysMessages, NumProcesses: Integer;
    PosTokens, PosProcesses, PosObjects, PosLocations, PosMessages, PosSysMessages,
      PosConnections, PosVocabulary, PosInitiallyAt, PosObjectWords: Word;
    Processes: array of TDaadProcess;
    Entries: array of TDaadEntry;
    Condacts: array of TDaadCondact;
    { Read the game in Mem. False if there is no DAAD database (at 8400, or
      anywhere else in memory). }
    function Load(const Mem: TDaadMemory): Boolean;
    property Valid: Boolean read FValid;
    { Index of the condact that starts at Addr, -1 if none. DRC may share
      condacts between entries: then the first entry in Recent (header
      addresses of the entries run lately, newest first) that has it. }
    function CondactAt(Addr: Word): Integer;
    function CondactIn(Addr: Word; const Recent: array of Integer): Integer;
    { DAAD_* flags (Spectrum unit) for every address }
    procedure BuildMap(Map: PByte);
    { The condact as written in a DAAD source: "MES 3", "LET 10 @5"... }
    function CondactText(const C: TDaadCondact): string;
    { The text a condact prints (MES, MESSAGE, SYSMESS, DESC), '' if none }
    function CondactMessage(const C: TDaadCondact): string;
    { A word of the vocabulary: Kind 0 verb, 2 noun ('_' for 255) }
    function VocWord(Id, Kind: Integer): string;
    { Every word of a kind, as "id WORD/SYNONYM", sorted by id }
    function VocWords(Kind: Integer): TStringArray;
    function ObjectText(N: Integer): string;
    function LocationText(N: Integer): string;
    function MessageText(N: Integer): string;
    function SysMessageText(N: Integer): string;
    { For exporting the source: a byte of the copy of memory, a token ('' if
      none), and a text with the escapes of a DSF (#n, #k...) or of an SCE
      (\r, \k...) }
    function ByteAt(Addr: Word): Byte;
    function WordAt(Addr: Word): Word;
    function Token(N: Integer): string;
    function SourceText(Addr: Word; Sce: Boolean): string;
  end;

const
  CONDACT_NAMES: array[0..127] of string = (
    'AT', 'NOTAT', 'ATGT', 'ATLT', 'PRESENT', 'ABSENT', 'WORN', 'NOTWORN',
    'CARRIED', 'NOTCARR', 'CHANCE', 'ZERO', 'NOTZERO', 'EQ', 'GT', 'LT',
    'ADJECT1', 'ADVERB', 'SFX', 'DESC', 'QUIT', 'END', 'DONE', 'OK',
    'ANYKEY', 'SAVE', 'LOAD', 'DPRINT', 'DISPLAY', 'CLS', 'DROPALL', 'AUTOG',
    'AUTOD', 'AUTOW', 'AUTOR', 'PAUSE', 'SYNONYM', 'GOTO', 'MESSAGE', 'REMOVE',
    'GET', 'DROP', 'WEAR', 'DESTROY', 'CREATE', 'SWAP', 'PLACE', 'SET',
    'CLEAR', 'PLUS', 'MINUS', 'LET', 'NEWLINE', 'PRINT', 'SYSMESS', 'ISAT',
    'SETCO', 'SPACE', 'HASAT', 'HASNAT', 'LISTOBJ', 'EXTERN', 'RAMSAVE', 'RAMLOAD',
    'BEEP', 'PAPER', 'INK', 'BORDER', 'PREP', 'NOUN2', 'ADJECT2', 'ADD',
    'SUB', 'PARSE', 'LISTAT', 'PROCESS', 'SAME', 'MES', 'WINDOW', 'NOTEQ',
    'NOTSAME', 'MODE', 'WINAT', 'TIME', 'PICTURE', 'DOALL', 'MOUSE', 'GFX',
    'ISNOTAT', 'WEIGH', 'PUTIN', 'TAKEOUT', 'NEWTEXT', 'ABILITY', 'WEIGHT', 'RANDOM',
    'INPUT', 'SAVEAT', 'BACKAT', 'PRINTAT', 'WHATO', 'CALL', 'PUTO', 'NOTDONE',
    'AUTOP', 'AUTOT', 'MOVE', 'WINSIZE', 'REDO', 'CENTRE', 'EXIT', 'INKEY',
    'BIGGER', 'SMALLER', 'ISDONE', 'ISNDONE', 'SKIP', 'RESTART', 'TAB', 'COPYOF',
    'DUMB', 'COPYOO', 'DUMB', 'COPYFO', 'DUMB', 'COPYFF', 'COPYBF', 'RESET');

  CONDACT_PARAMS: array[0..127] of Byte = (
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2,
    1, 1, 2, 1, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0,
    0, 0, 0, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 1,
    1, 2, 2, 2, 0, 1, 1, 2, 1, 0, 1, 1, 0, 2, 0, 1,
    2, 1, 1, 1, 1, 1, 1, 2, 2, 1, 1, 1, 2, 1, 1, 2,
    2, 1, 2, 2, 1, 1, 1, 2, 2, 2, 2, 2, 0, 2, 1, 1,
    2, 0, 0, 2, 0, 1, 1, 0, 1, 1, 1, 2, 0, 0, 1, 0,
    2, 2, 0, 0, 1, 0, 1, 2, 0, 2, 0, 2, 0, 2, 2, 0);

  { PAW's condacts: some share DAAD's names but not their numbers or
    parameters }
  PAW_CONDACT_NAMES: array[0..107] of string = (
    'AT', 'NOTAT', 'ATGT', 'ATLT', 'PRESENT', 'ABSENT', 'WORN', 'NOTWORN',
    'CARRIED', 'NOTCARR', 'CHANCE', 'ZERO', 'NOTZERO', 'EQ', 'GT', 'LT',
    'ADJECT1', 'ADVERB', 'INVEN', 'DESC', 'QUIT', 'END', 'DONE', 'OK',
    'ANYKEY', 'SAVE', 'LOAD', 'TURNS', 'SCORE', 'CLS', 'DROPALL', 'AUTOG',
    'AUTOD', 'AUTOW', 'AUTOR', 'PAUSE', 'TIMEOUT', 'GOTO', 'MESSAGE', 'REMOVE',
    'GET', 'DROP', 'WEAR', 'DESTROY', 'CREATE', 'SWAP', 'PLACE', 'SET',
    'CLEAR', 'PLUS', 'MINUS', 'LET', 'NEWLINE', 'PRINT', 'SYSMESS', 'ISAT',
    'COPYOF', 'COPYOO', 'COPYFO', 'COPYFF', 'LISTOBJ', 'EXTERN', 'RAMSAVE', 'RAMLOAD',
    'BEEP', 'PAPER', 'INK', 'BORDER', 'PREP', 'NOUN2', 'ADJECT2', 'ADD',
    'SUB', 'PARSE', 'LISTAT', 'PROCESS', 'SAME', 'MES', 'CHARSET', 'NOTEQ',
    'NOTSAME', 'MODE', 'LINE', 'TIME', 'PICTURE', 'DOALL', 'PROMPT', 'GRAPHIC',
    'ISNOTAT', 'WEIGH', 'PUTIN', 'TAKEOUT', 'NEWTEXT', 'ABILITY', 'WEIGHT', 'RANDOM',
    'INPUT', 'SAVEAT', 'BACKAT', 'PRINTAT', 'WHATO', 'RESET', 'PUTO', 'NOTDONE',
    'AUTOP', 'AUTOT', 'MOVE', 'PROTECT');

  PAW_CONDACT_PARAMS: array[0..107] of Byte = (
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2,
    1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 1,
    1, 2, 2, 2, 0, 1, 1, 2, 2, 2, 2, 2, 0, 1, 0, 1,
    2, 1, 1, 1, 1, 1, 1, 2, 2, 0, 1, 1, 2, 1, 1, 2,
    2, 2, 1, 2, 1, 1, 1, 1, 2, 2, 2, 2, 0, 2, 1, 1,
    1, 0, 0, 2, 0, 1, 1, 0, 1, 1, 1, 0);

  OP_DESC = 19; OP_MESSAGE = 38; OP_SYSMESS = 54; OP_EXTERN = 61; OP_PROCESS = 75;
  OP_MES = 77; OP_XMES = 120; OP_INDIR = 122; OP_SETAT = 124;

  { Names of the system flags (as in the DAAD Ready templates) }
  function FlagName(N: Integer; PAW: Boolean = False): string;
  { Meaning of an object location: 'carried', 'worn', 'not created' or '' }
  function LocationName(Loc: Integer): string;
  { The kind of vocabulary word a flag holds (0 verb, 1 adverb, 2 noun, 3
    adjective, 4 preposition), -1 for other flags }
  function FlagWordKind(N: Integer): Integer;

const
  // Characters 16-31 of DAAD texts: ª ¡ ¿ « » á é í ó ú ñ Ñ ç Ç ü Ü
  SPANISH: array[16..31] of string = (#$C2#$AA, #$C2#$A1, #$C2#$BF, #$C2#$AB, #$C2#$BB,
    #$C3#$A1, #$C3#$A9, #$C3#$AD, #$C3#$B3, #$C3#$BA, #$C3#$B1, #$C3#$91, #$C3#$A7,
    #$C3#$87, #$C3#$BC, #$C3#$9C);

implementation

const
  // DRC leaves out the 255 after these (DONE, OK, NOTDONE, SKIP, RESTART, REDO)
  TERMINATORS = [22, 23, 103, 116, 117, 108];
  MAX_ENTRIES = 2000;
  MAX_CONDACTS = 1000;

function FlagName(N: Integer; PAW: Boolean): string;
begin
  case N of
    0: Result := 'fDark';
    1: Result := 'fObjectsCarried';
    // PAW's flag 28 is free for the game
    28: if PAW then Result := '' else Result := 'fDarkF';
    29: Result := 'fGFlags';
    30: Result := 'fScore';
    31: Result := 'fTurns';
    32: Result := 'fTurnsHi';
    33: Result := 'fVerb';
    34: Result := 'fNoun';
    35: Result := 'fAdject1';
    36: Result := 'fAdverb';
    37: Result := 'fMaxCarr';
    38: Result := 'fPlayer';
    41: Result := 'fStream';
    42: Result := 'fPrompt';
    43: Result := 'fPrep';
    44: Result := 'fNoun2';
    45: Result := 'fAdject2';
    46: Result := 'fCPronounNoun';
    47: Result := 'fCPronounAdject';
    48: Result := 'fTimeout';
    49: Result := 'fTimeoutFlags';
    50: Result := 'fDoallObjNo';
    51: Result := 'fRefObject';
    52: Result := 'fStrength';
    53: Result := 'fObjFlags';
    54: Result := 'fRefObjLoc';
    55: Result := 'fRefObjWeight';
    56: Result := 'fRefObjIsContainer';
    57: Result := 'fRefObjIsWearable';
    58: Result := 'fRefObjAttr1';
    59: Result := 'fRefObjAttr2';
    60: Result := 'fInkeyKey1';
    61: Result := 'fInkeyKey2';
    62: Result := 'fScreenMode';
    63: Result := 'fCurrentWindow';
  else
    Result := '';
  end;
end;

function FlagWordKind(N: Integer): Integer;
begin
  case N of
    33: Result := 0;            // fVerb
    34, 44, 46: Result := 2;    // fNoun, fNoun2, fCPronounNoun
    35, 45, 47: Result := 3;    // fAdject1, fAdject2, fCPronounAdject
    36: Result := 1;            // fAdverb
    43: Result := 4;            // fPrep
  else
    Result := -1;
  end;
end;

{ TDaadCondition }

const
  // RPN operations (values below are constants, flags are OP_FLAG n)
  C_CONST = 0; C_FLAG = 1; C_INDIRECT = 2; C_EQ = 3; C_NE = 4; C_LT = 5; C_GT = 6;
  C_LE = 7; C_GE = 8; C_AND = 9; C_OR = 10; C_NOT = 11;

class function TDaadCondition.Parse(const Text: string; out Error: string): TDaadCondition;
var
  P: Integer;
  Code: array of Integer;

  procedure Emit(Op: Integer; Arg: Integer = 0);
  begin
    SetLength(Code, Length(Code) + 2);
    Code[High(Code) - 1] := Op;
    Code[High(Code)] := Arg;
  end;

  procedure SkipSpaces;
  begin
    while (P <= Length(Text)) and (Text[P] in [' ', #9]) do Inc(P);
  end;

  function Keyword(const W: string): Boolean;
  begin
    SkipSpaces;
    Result := SameText(Copy(Text, P, Length(W)), W) and
      ((P + Length(W) > Length(Text)) or not (Text[P + Length(W)] in ['A'..'Z', 'a'..'z', '0'..'9', '_']));
    if Result then Inc(P, Length(W));
  end;

  function Fail(const Msg: string): Boolean;
  begin
    if Error = '' then Error := Msg;
    Result := False;
  end;

  function Number(out V: Integer): Boolean;
  var
    Start: Integer;
  begin
    SkipSpaces;
    Start := P;
    while (P <= Length(Text)) and (Text[P] in ['0'..'9']) do Inc(P);
    Result := (P > Start) and TryStrToInt(Copy(Text, Start, P - Start), V);
  end;

  function Operand: Boolean;
  var
    V: Integer;
    Indirect: Boolean;
  begin
    SkipSpaces;
    Indirect := (P <= Length(Text)) and (Text[P] = '@');
    if Indirect then Inc(P);
    if (P <= Length(Text)) and (Text[P] in ['f', 'F']) then
    begin
      Inc(P);
      if not Number(V) or (V > 255) then Exit(Fail(Format('a flag number (0-255) after "f", at %d', [P])));
      if Indirect then Emit(C_INDIRECT, V) else Emit(C_FLAG, V);
      Result := True;
    end
    else if Indirect then
      Result := Fail(Format('a flag ("@f5") at %d', [P]))
    else if Number(V) then
    begin
      Emit(C_CONST, V);
      Result := True;
    end
    else
      Result := Fail(Format('a flag ("f5") or a number at %d', [P]));
  end;

  function Expr: Boolean; forward;

  function Comparison: Boolean;
  var
    Op: Integer;
  begin
    SkipSpaces;
    if Keyword('NOT') then
    begin
      if not Comparison() then Exit(False);   // () : a call, not the result
      Emit(C_NOT);
      Exit(True);
    end;
    if (P <= Length(Text)) and (Text[P] = '(') then
    begin
      Inc(P);
      if not Expr then Exit(False);
      SkipSpaces;
      if (P > Length(Text)) or (Text[P] <> ')') then Exit(Fail(Format('")" at %d', [P])));
      Inc(P);
      Exit(True);
    end;
    if not Operand then Exit(False);
    SkipSpaces;
    Op := -1;
    if Copy(Text, P, 2) = '==' then begin Op := C_EQ; Inc(P, 2); end
    else if (Copy(Text, P, 2) = '<>') or (Copy(Text, P, 2) = '!=') then begin Op := C_NE; Inc(P, 2); end
    else if Copy(Text, P, 2) = '<=' then begin Op := C_LE; Inc(P, 2); end
    else if Copy(Text, P, 2) = '>=' then begin Op := C_GE; Inc(P, 2); end
    else if Copy(Text, P, 1) = '=' then begin Op := C_EQ; Inc(P); end
    else if Copy(Text, P, 1) = '<' then begin Op := C_LT; Inc(P); end
    else if Copy(Text, P, 1) = '>' then begin Op := C_GT; Inc(P); end;
    if Op < 0 then Exit(Fail(Format('a comparison (=, <>, <, >, <=, >=) at %d', [P])));
    if not Operand then Exit(False);
    Emit(Op);
    Result := True;
  end;

  function Term: Boolean;
  begin
    if not Comparison then Exit(False);
    while Keyword('AND') do
    begin
      if not Comparison then Exit(False);
      Emit(C_AND);
    end;
    Result := True;
  end;

  function Expr: Boolean;
  begin
    if not Term then Exit(False);
    while Keyword('OR') do
    begin
      if not Term then Exit(False);
      Emit(C_OR);
    end;
    Result := True;
  end;

begin
  Result := nil;
  Error := '';
  P := 1;
  if Trim(Text) = '' then
  begin
    Error := 'empty condition';
    Exit;
  end;
  if not Expr then Exit;
  SkipSpaces;
  if P <= Length(Text) then
  begin
    Error := Format('unexpected "%s" at %d', [Copy(Text, P, 10), P]);
    Exit;
  end;
  Result := TDaadCondition.Create;
  Result.FCode := Code;
end;

function TDaadCondition.Holds(Flag: TDaadFlagReader): Boolean;
var
  Stack: array[0..63] of Integer;
  SP, I, A, B: Integer;
begin
  SP := 0;
  I := 0;
  while I < Length(FCode) do
  begin
    case FCode[I] of
      C_CONST: begin Stack[SP] := FCode[I + 1]; Inc(SP); end;
      C_FLAG: begin Stack[SP] := Flag(FCode[I + 1]); Inc(SP); end;
      C_INDIRECT: begin Stack[SP] := Flag(Flag(FCode[I + 1])); Inc(SP); end;
      C_NOT: Stack[SP - 1] := Ord(Stack[SP - 1] = 0);
    else
      Dec(SP);
      A := Stack[SP - 1];
      B := Stack[SP];
      case FCode[I] of
        C_EQ: A := Ord(A = B);
        C_NE: A := Ord(A <> B);
        C_LT: A := Ord(A < B);
        C_GT: A := Ord(A > B);
        C_LE: A := Ord(A <= B);
        C_GE: A := Ord(A >= B);
        C_AND: A := Ord((A <> 0) and (B <> 0));
        C_OR: A := Ord((A <> 0) or (B <> 0));
      end;
      Stack[SP - 1] := A;
    end;
    Inc(I, 2);
    if SP > High(Stack) then Exit(False);
  end;
  Result := (SP = 1) and (Stack[0] <> 0);
end;

function LocationName(Loc: Integer): string;
begin
  case Loc of
    LOC_NOT_CREATED: Result := 'not created';
    LOC_WORN: Result := 'worn';
    LOC_CARRIED: Result := 'carried';
  else
    Result := '';
  end;
end;

{ TDaadGame }

function TDaadGame.W(Addr: Word): Word;
begin
  Result := FMem[Addr] or (FMem[Word(Addr + 1)] shl 8);
end;

function TDaadGame.ParamsOf(Opcode: Byte): Integer;
begin
  if IsPAW then
  begin
    if Opcode <= High(PAW_CONDACT_PARAMS) then Result := PAW_CONDACT_PARAMS[Opcode]
    else Result := 0;
    Exit;
  end;
  Result := CONDACT_PARAMS[Opcode];
  if Version >= 3 then
    case Opcode of
      OP_XMES, OP_SETAT: Result := 2;
      OP_INDIR: Result := 1;   // the flag whose value is the next condact's second parameter
    end;
end;

function TDaadGame.Load(const Mem: TDaadMemory): Boolean;
var
  A, Best, BestEntries: Integer;
begin
  Move(Mem, FMem, SizeOf(FMem));
  IsPAW := False;
  // Usually at 8400; older games elsewhere (La Diosa de Cozumel: 8380)
  Result := TryAt(DDB_BASE);
  if Result then Exit;
  Best := -1;
  BestEntries := 0;
  for A := $5B00 to $FF00 do
    if (A <> DDB_BASE) and (FMem[A + 2] = 95) and ((FMem[A + 1] shr 4) = 1) and TryAt(A) and
       (Length(Entries) > BestEntries) then
    begin
      Best := A;
      BestEntries := Length(Entries);
    end;
  Result := (Best >= 0) and TryAt(Best);
  // Not DAAD: a PAW game?
  if not Result then Result := TryPAW;
end;

{ PAW (48K): the addresses of its tables are in the last bytes of memory
  (FFD9 processes, FFDB objects, FFDD locations, FFDF messages, FFE1 system
  messages, FFE3 connections, FFE5 vocabulary, FFE7 objects' initial
  locations, FFE9 object words) and FFFD points at the database, whose
  counts are at +324 (objects, locations, messages, system messages,
  processes) and the abbreviations at +332; +311 holds the colour codes
  16, 17... 21, every other byte, as a signature. Process 0 is the response
  table. }
function TDaadGame.TryPAW: Boolean;
var
  Top, Attr: Word;
  I, E: Integer;
begin
  Result := False;
  FValid := False;
  SetLength(Processes, 0);
  SetLength(Entries, 0);
  SetLength(Condacts, 0);
  FillChar(FCondactAt, SizeOf(FCondactAt), 0);
  Top := W($FFFD);
  if (Top < $4000 - 311) or (Top > $FFFF - 340) then Exit;
  Attr := Top + 311;
  for I := 0 to 5 do
    if FMem[Word(Attr + I * 2)] <> 16 + I then Exit;
  IsPAW := True;
  Base := Top;
  Version := 0;
  Language := -1;
  NumObjects := FMem[Word(Top + 324)];
  NumLocations := FMem[Word(Top + 325)];
  NumMessages := FMem[Word(Top + 326)];
  NumSysMessages := FMem[Word(Top + 327)];
  NumProcesses := FMem[Word(Top + 328)];
  PosAbbreviations := W(Word(Top + 332));
  PosProcesses := W($FFD9);
  PosObjects := W($FFDB);
  PosLocations := W($FFDD);
  PosMessages := W($FFDF);
  PosSysMessages := W($FFE1);
  PosConnections := W($FFE3);
  PosVocabulary := W($FFE5);
  PosInitiallyAt := W($FFE7);
  PosObjectWords := W($FFE9);
  PosTokens := 0;
  if (NumProcesses = 0) or (NumLocations = 0) or (PosProcesses < $4000) then
  begin
    IsPAW := False;
    Exit;
  end;
  ReadProcesses;
  if (Length(Entries) = 0) or FBadEntry then
  begin
    IsPAW := False;
    Exit;
  end;
  for E := 0 to High(Entries) do
    if Entries[E].Code < $4000 then
    begin
      IsPAW := False;
      Exit;
    end;
  FValid := True;
  Result := True;
end;

{ PAW texts: XORed with 255, ended by 31; 16-23 are colour codes (with one
  or two bytes after them) and, when the text is compressed, bytes from 165
  are abbreviations }
function TDaadGame.PAWTextAt(Addr: Word): string;
var
  C: Byte;
  Guard, N, Skip: Integer;
  A: Word;
  Compressed: Boolean;
begin
  Result := '';
  Compressed := (PosAbbreviations <> 0) and (FMem[PosAbbreviations] = 0);
  Guard := 0;
  Skip := 0;
  repeat
    C := FMem[Addr] xor $FF;
    Addr := Word(Addr + 1);
    Inc(Guard);
    if Skip > 0 then
    begin
      Dec(Skip);
      Continue;
    end;
    case C of
      31: Break;
      13: Result := Result + '#n';
      6: Result := Result + ' ';
      16..21: Skip := 1;
      22, 23: Skip := 2;
      32..126: Result := Result + Chr(C);
      165..255:
        if Compressed then
        begin
          // Abbreviation C - 164: skip that many entries (ended by bit 7)
          A := PosAbbreviations;
          N := C - 164;
          while (N > 0) and (A < $FFFF) do
          begin
            while (FMem[A] and $80) = 0 do A := Word(A + 1);
            A := Word(A + 1);
            Dec(N);
          end;
          while ((FMem[A] and $80) = 0) and (Length(Result) < 2000) do
          begin
            if FMem[A] in [32..126] then Result := Result + Chr(FMem[A]);
            A := Word(A + 1);
          end;
          if (FMem[A] and $7F) in [32..126] then Result := Result + Chr(FMem[A] and $7F);
        end;
    end;
  until Guard > 2000;
end;

{ The database with its header at A. Its first byte (the version) is not
  trusted: the 128K interpreters' interrupt table (8300-8400) overwrites
  it at 8400. }
function TDaadGame.TryAt(A: Word): Boolean;
var
  I, E: Integer;
begin
  FValid := False;
  Result := False;
  Base := A;
  SetLength(Processes, 0);
  SetLength(Entries, 0);
  SetLength(Condacts, 0);
  FillChar(FCondactAt, SizeOf(FCondactAt), 0);
  if ((FMem[A + 1] shr 4) <> 1) or (FMem[A + 2] <> 95) or (A > $FF00) then Exit;
  Language := FMem[A + 1] and $0F;
  NumObjects := FMem[A + 3];
  NumLocations := FMem[A + 4];
  NumMessages := FMem[A + 5];
  NumSysMessages := FMem[A + 6];
  NumProcesses := FMem[A + 7];
  if (NumProcesses = 0) or (NumLocations = 0) then Exit;
  // Every table is after the header
  for I := 0 to 11 do
    if W(A + 8 + I * 2) < A + 34 then Exit;
  PosTokens := W(A + 8);
  PosProcesses := W(A + 10);
  PosObjects := W(A + 12);
  PosLocations := W(A + 14);
  PosMessages := W(A + 16);
  PosSysMessages := W(A + 18);
  PosConnections := W(A + 20);
  PosVocabulary := W(A + 22);
  PosInitiallyAt := W(A + 24);
  PosObjectWords := W(A + 26);
  if PosProcesses > $FFFF - NumProcesses * 2 then Exit;
  for I := 0 to NumProcesses - 1 do
    if W(PosProcesses + I * 2) < A + 34 then Exit;
  Version := FMem[A];
  if not (Version in [2, 3]) then
  begin
    // Overwritten: version 2 never uses the opcodes added by version 3
    Version := 2;
    ReadProcesses;
    for I := 0 to High(Condacts) do
      if Condacts[I].Opcode in [OP_XMES, OP_INDIR, OP_SETAT] then
      begin
        Version := 3;
        Break;
      end;
    SetLength(Processes, 0);
    SetLength(Entries, 0);
    SetLength(Condacts, 0);
    FillChar(FCondactAt, SizeOf(FCondactAt), 0);
  end;
  ReadTokens;
  ReadProcesses;
  if (Length(Entries) = 0) or FBadEntry then Exit;
  for E := 0 to High(Entries) do
    if Entries[E].Code < A + 34 then Exit;
  FValid := True;
  Result := True;
end;

procedure TDaadGame.ReadTokens;
var
  A: Word;
  N, Guard: Integer;
  C: Byte;
  S: string;
begin
  for N := 0 to 127 do FTokens[N] := '';
  // The table starts one byte after its address
  A := PosTokens + 1;
  N := 0;
  S := '';
  Guard := 0;
  while (N < 128) and (Guard < 4096) do
  begin
    C := FMem[A];
    Inc(A);
    Inc(Guard);
    if C = 0 then Break;
    if (C and $7F) in [16..31] then S := S + SPANISH[C and $7F]
    else if (C and $7F) = Ord('_') then S := S + ' '
    else S := S + Chr(C and $7F);
    if C > 127 then
    begin
      FTokens[N] := S;
      Inc(N);
      S := '';
    end;
  end;
end;

procedure TDaadGame.ReadProcesses;
var
  P, E, N, K: Integer;
  Table, A, Hdr: Word;
  Op: Byte;
  C: TDaadCondact;
begin
  FBadEntry := False;
  SetLength(Processes, NumProcesses);
  for P := 0 to NumProcesses - 1 do
  begin
    Table := W(PosProcesses + P * 2);
    Processes[P].Table := Table;
    Processes[P].FirstEntry := Length(Entries);
    Processes[P].EntryCount := 0;
    for E := 0 to MAX_ENTRIES do
    begin
      Hdr := Word(Table + E * 4);
      if FMem[Hdr] = 0 then Break;
      if E = MAX_ENTRIES then
      begin
        FBadEntry := True;
        Exit;
      end;
      SetLength(Entries, Length(Entries) + 1);
      with Entries[High(Entries)] do
      begin
        Header := Hdr;
        Verb := FMem[Hdr];
        Noun := FMem[Word(Hdr + 1)];
        Code := W(Word(Hdr + 2));
        Process := P;
        FirstCondact := Length(Condacts);
        CondactCount := 0;
      end;
      Inc(Processes[P].EntryCount);
      A := Entries[High(Entries)].Code;
      for N := 0 to MAX_CONDACTS do
      begin
        if FMem[A] = 255 then Break;
        if N = MAX_CONDACTS then
        begin
          FBadEntry := True;
          Break;
        end;
        C.Addr := A;
        if IsPAW then
        begin
          // No indirection in PAW; an unknown opcode is not PAW code
          if FMem[A] > High(PAW_CONDACT_PARAMS) then
          begin
            FBadEntry := True;
            Break;
          end;
          C.Opcode := FMem[A];
          C.Indirect := False;
        end
        else
        begin
          C.Opcode := FMem[A] and $7F;
          C.Indirect := FMem[A] > 127;
        end;
        C.ParamCount := ParamsOf(C.Opcode);
        C.Entry := High(Entries);
        C.Params[0] := 0; C.Params[1] := 0; C.Params[2] := 0;
        for K := 0 to C.ParamCount - 1 do C.Params[K] := FMem[Word(A + 1 + K)];
        // Maluva (v2): EXTERN n 3 (XMES) and EXTERN n 5 (XBEEP) take a third byte
        if not IsPAW and (Version = 2) and (C.Opcode = OP_EXTERN) and (C.Params[1] in [3, 5]) then
        begin
          C.ParamCount := 3;
          C.Params[2] := FMem[Word(A + 3)];
        end;
        SetLength(Condacts, Length(Condacts) + 1);
        Condacts[High(Condacts)] := C;
        Inc(Entries[High(Entries)].CondactCount);
        if FCondactAt[A] = 0 then FCondactAt[A] := Length(Condacts);
        Op := C.Opcode;
        A := Word(A + 1 + C.ParamCount);
        if not IsPAW and (Op in TERMINATORS) and (FMem[A] <> 255) then Break;
      end;
    end;
  end;
end;

function TDaadGame.CondactAt(Addr: Word): Integer;
begin
  Result := FCondactAt[Addr] - 1;
end;

function TDaadGame.CondactIn(Addr: Word; const Recent: array of Integer): Integer;
var
  R, E, C: Integer;
begin
  for R := 0 to High(Recent) do
    for E := 0 to High(Entries) do
      if Entries[E].Header = Recent[R] then
      begin
        for C := Entries[E].FirstCondact to Entries[E].FirstCondact + Entries[E].CondactCount - 1 do
          if Condacts[C].Addr = Addr then Exit(C);
        Break;
      end;
  Result := CondactAt(Addr);
end;

procedure TDaadGame.BuildMap(Map: PByte);
var
  I, K: Integer;
  A: Word;
begin
  FillChar(Map^, $10000, 0);
  // Where the player's order has been read (DAAD_INPUT): after PARSE in
  // DAAD; in PAW when the response table (process 0) is scanned
  if IsPAW then
    Map[Processes[0].Table] := 16
  else
    for I := 0 to High(Condacts) do
      if Condacts[I].Opcode = 73 then Map[Condacts[I].Addr] := Map[Condacts[I].Addr] or 16;
  for I := 0 to High(Entries) do
    Map[Word(Entries[I].Header + 2)] := Map[Word(Entries[I].Header + 2)] or 4;   // DAAD_ENTRY
  for I := 0 to High(Condacts) do
  begin
    A := Condacts[I].Addr;
    Map[A] := Map[A] or 1;   // DAAD_CONDACT
    for K := 1 to Condacts[I].ParamCount do
      Map[Word(A + K)] := Map[Word(A + K)] or 2;   // DAAD_STREAM
  end;
  // The end marks are read too
  for I := 0 to High(Entries) do
    if Entries[I].CondactCount > 0 then
    begin
      with Condacts[Entries[I].FirstCondact + Entries[I].CondactCount - 1] do
        A := Word(Addr + 1 + ParamCount);
      if FMem[A] = 255 then Map[A] := Map[A] or 2;
    end
    else if FMem[Entries[I].Code] = 255 then
      Map[Entries[I].Code] := Map[Entries[I].Code] or 2;
end;

function TDaadGame.CondactText(const C: TDaadCondact): string;
var
  K: Integer;
begin
  if IsPAW then Result := PAW_CONDACT_NAMES[C.Opcode] else Result := CONDACT_NAMES[C.Opcode];
  if IsPAW then
  else if (Version >= 3) and (C.Opcode = OP_XMES) then Result := 'XMES'
  else if (Version >= 3) and (C.Opcode = OP_INDIR) then Result := 'INDIR'
  else if (Version >= 3) and (C.Opcode = OP_SETAT) then Result := 'SETAT';
  for K := 0 to C.ParamCount - 1 do
  begin
    if K = 0 then Result := Format('%-8s', [Result]) else Result := Result + ' ';
    if (K = 0) and C.Indirect then Result := Result + '@';
    Result := Result + IntToStr(C.Params[K]);
  end;
end;

function TDaadGame.CondactMessage(const C: TDaadCondact): string;
begin
  Result := '';
  if C.Indirect then Exit;
  // PAW's DESC has no parameter (the current location)
  if IsPAW and (C.Opcode = OP_DESC) then Exit;
  case C.Opcode of
    OP_MES, OP_MESSAGE: Result := MessageText(C.Params[0]);
    OP_SYSMESS: Result := SysMessageText(C.Params[0]);
    OP_DESC: Result := LocationText(C.Params[0]);
  end;
end;

function TDaadGame.TextAt(Addr: Word): string;
var
  C: Byte;
  D, Guard: Integer;
begin
  if IsPAW then Exit(PAWTextAt(Addr));
  Result := '';
  Guard := 0;
  repeat
    C := FMem[Addr];
    Addr := Word(Addr + 1);
    Inc(Guard);
    if C < 128 then
      Result := Result + FTokens[C xor $7F]
    else
    begin
      D := 255 - C;
      case D of
        10: Break;                      // end of the text
        13: Result := Result + '#n';
        11: Result := Result + '#b';
        12: Result := Result + '#k';
        14: Result := Result + '#g';
        15: Result := Result + '#t';
        16..31: Result := Result + SPANISH[D];
        127: Result := Result + '#f';
        32..126: Result := Result + Chr(D);
      end;
    end;
  until Guard > 2000;
end;

function TDaadGame.VocWord(Id, Kind: Integer): string;
var
  A: Word;
  Guard: Integer;

  function Find(K: Integer): string;
  var
    J: Integer;
    D: Integer;
  begin
    Result := '';
    A := PosVocabulary;
    Guard := 0;
    while (FMem[A] <> 0) and (Guard < 4000) do
    begin
      if (FMem[Word(A + 5)] = Id) and (FMem[Word(A + 6)] = K) then
      begin
        for J := 0 to 4 do
        begin
          D := 255 - FMem[Word(A + J)];
          if D in [16..31] then Result := Result + SPANISH[D]
          else if D in [32..126] then Result := Result + Chr(D);
        end;
        Exit(TrimRight(Result));
      end;
      A := Word(A + 7);
      Inc(Guard);
    end;
  end;

begin
  if Id = 255 then Exit('_');
  if IsPAW and (Id = 1) then Exit('*');   // PAW: any word
  Result := Find(Kind);
  // Nouns up to 39 can be used as verbs (N, S..., as DRC allows)
  if (Result = '') and (Kind = 0) and (Id <= 39) then Result := Find(2);
  if Result = '' then Result := IntToStr(Id);
end;

function TDaadGame.VocWords(Kind: Integer): TStringArray;
var
  A: Word;
  Ids: array[0..255] of string;
  I, J, D, Guard, N: Integer;
  S: string;
begin
  for I := 0 to 255 do Ids[I] := '';
  A := PosVocabulary;
  Guard := 0;
  while (FMem[A] <> 0) and (Guard < 4000) do
  begin
    if FMem[Word(A + 6)] = Kind then
    begin
      S := '';
      for J := 0 to 4 do
      begin
        D := 255 - FMem[Word(A + J)];
        if D in [16..31] then S := S + SPANISH[D]
        else if D in [32..126] then S := S + Chr(D);
      end;
      S := TrimRight(S);
      I := FMem[Word(A + 5)];
      if Ids[I] = '' then Ids[I] := S else Ids[I] := Ids[I] + '/' + S;
    end;
    A := Word(A + 7);
    Inc(Guard);
  end;
  N := 0;
  SetLength(Result, 256);
  for I := 0 to 255 do
    if Ids[I] <> '' then
    begin
      Result[N] := Format('%.3d %s', [I, Ids[I]]);
      Inc(N);
    end;
  SetLength(Result, N);
end;

function TDaadGame.ByteAt(Addr: Word): Byte;
begin
  Result := FMem[Addr];
end;

function TDaadGame.WordAt(Addr: Word): Word;
begin
  Result := W(Addr);
end;

function TDaadGame.Token(N: Integer): string;
begin
  if (N >= 0) and (N <= 127) then Result := FTokens[N] else Result := '';
end;

function TDaadGame.SourceText(Addr: Word; Sce: Boolean): string;
var
  C: Byte;
  D, Guard: Integer;
  Esc: string;
begin
  if Sce then Esc := '\' else Esc := '#';
  if IsPAW then
  begin
    // PAW's newlines come as #n; quotes are escaped in a DSF
    Result := PAWTextAt(Addr);
    if Sce then Result := StringReplace(Result, '#n', '\r', [rfReplaceAll])
    else Result := StringReplace(Result, '"', '\"', [rfReplaceAll]);
    Exit;
  end;
  Result := '';
  Guard := 0;
  repeat
    C := FMem[Addr];
    Addr := Word(Addr + 1);
    Inc(Guard);
    if C < 128 then
      Result := Result + FTokens[C xor $7F]
    else
    begin
      D := 255 - C;
      case D of
        10: Break;
        13: if Sce then Result := Result + '\r' else Result := Result + '#n';
        11: Result := Result + Esc + 'b';
        12: Result := Result + Esc + 'k';
        14: Result := Result + Esc + 'g';
        15: Result := Result + Esc + 't';
        16..31: Result := Result + SPANISH[D];
        127: Result := Result + Esc + 'f';
        34: if Sce then Result := Result + '"' else Result := Result + '\"';
        32, 33, 35..126: Result := Result + Chr(D);
      end;
    end;
  until Guard > 2000;
end;

function TDaadGame.ObjectText(N: Integer): string;
begin
  if (N < 0) or (N >= NumObjects) then Exit('');
  Result := TextAt(W(Word(PosObjects + N * 2)));
end;

function TDaadGame.LocationText(N: Integer): string;
begin
  if (N < 0) or (N >= NumLocations) then Exit('');
  Result := TextAt(W(Word(PosLocations + N * 2)));
end;

function TDaadGame.MessageText(N: Integer): string;
begin
  if (N < 0) or (N >= NumMessages) then Exit('');
  Result := TextAt(W(Word(PosMessages + N * 2)));
end;

function TDaadGame.SysMessageText(N: Integer): string;
begin
  if (N < 0) or (N >= NumSysMessages) then Exit('');
  Result := TextAt(W(Word(PosSysMessages + N * 2)));
end;

end.

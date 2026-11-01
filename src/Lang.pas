{ The interface's languages: the texts are written in English in the sources,
  as _('Text'), and are looked up here in the table of the language in use
  (English, or a text without translation, is returned as it is).
  The tables are in LangData.inc, made from the lang/*.po files by
  tools/lang.py (see CLAUDE.md). }
unit Lang;

{$mode objfpc}{$H+}

interface

type
  TLanguage = (lgAuto, lgEnglish, lgSpanish, lgFrench, lgPortuguese, lgGerman);

const
  LANGUAGE_CODES: array[TLanguage] of string = ('auto', 'en', 'es', 'fr', 'pt', 'de');
  { Each language in its own words (the first, for Automatic, is translated where it is shown) }
  LANGUAGE_NAMES: array[TLanguage] of string = ('Automatic', 'English', 'Espa'#$C3#$B1'ol',
    'Fran'#$C3#$A7'ais', 'Portugu'#$C3#$AA's', 'Deutsch');

{ The text in the language in use }
function _(const S: string): string;
{ A file dialog's filter ('Description (*.ext)|*.ext|...'): only the descriptions are translated }
function _F(const S: string): string;
{ The short text of a button: its own entry ('btn:' + text), else the English text }
function _B(const S: string): string;
{ The language of a code (auto, en, es...); False if it isn't one }
function LanguageFromCode(const Code: string; out L: TLanguage): Boolean;
{ The operating system's language, if it is one of ours (else English) }
function OSLanguage: TLanguage;
{ Is the left Ctrl key down now? }
function LeftCtrlHeld: Boolean;
{ Chooses the language (lgAuto: the system's); to be called before any window exists }
procedure SetLanguage(L: TLanguage);
function CurrentLanguage: TLanguage;

implementation

uses
  SysUtils, Classes{$IFDEF UNIX}, dynlibs{$ENDIF};

{$I LangData.inc}

type
  PLangString = ^string;

var
  { The tables (LangData.inc) are arrays of pairs English, translation, in
    the order of the English texts' bytes (tools/lang.py): a binary search }
  Table, LclTable: PLangString;
  TableCount, LclCount: Integer;
  Current: TLanguage = lgEnglish;

function FindPair(Base: PLangString; Count: Integer; const S: string; out Index: Integer): Boolean;
var
  Lo, Hi, Mid, C: Integer;
begin
  Result := False;
  Lo := 0;
  Hi := Count - 1;
  while Lo <= Hi do
  begin
    Mid := (Lo + Hi) shr 1;
    C := CompareStr(S, (Base + 2 * Mid)^);
    if C = 0 then
    begin
      Index := Mid;
      Exit(True);
    end
    else if C < 0 then Hi := Mid - 1
    else Lo := Mid + 1;
  end;
end;

function _(const S: string): string;
var
  I: Integer;
begin
  Result := S;
  if (Table <> nil) and FindPair(Table, TableCount, S, I) then Result := (Table + 2 * I + 1)^;
end;

function _F(const S: string): string;
var
  I, Start, N: Integer;
begin
  Result := '';
  Start := 1;
  N := 0;
  for I := 1 to Length(S) + 1 do
    if (I > Length(S)) or (S[I] = '|') then
    begin
      if N > 0 then Result := Result + '|';
      if Odd(N) then Result := Result + Copy(S, Start, I - Start)
      else Result := Result + _(Copy(S, Start, I - Start));
      Inc(N);
      Start := I + 1;
    end;
end;

function _B(const S: string): string;
begin
  Result := _('btn:' + S);
  if Result = 'btn:' + S then Result := S;
end;

function LanguageFromCode(const Code: string; out L: TLanguage): Boolean;
var
  C: TLanguage;
begin
  Result := False;
  for C := Low(TLanguage) to High(TLanguage) do
    if SameText(Code, LANGUAGE_CODES[C]) then
    begin
      L := C;
      Result := True;
      Exit;
    end;
end;

{$IFDEF WINDOWS}
function WinGetUserDefaultUILanguage: Word; stdcall; external 'kernel32' name 'GetUserDefaultUILanguage';
function WinGetAsyncKeyState(vKey: LongInt): SmallInt; stdcall; external 'user32' name 'GetAsyncKeyState';
{$ENDIF}

function OSLanguage: TLanguage;
var
  Code: string;
  C: TLanguage;
begin
  Result := lgEnglish;
  Code := '';
  {$IFDEF WINDOWS}
  // The primary language of the Windows display language
  case WinGetUserDefaultUILanguage and $3FF of
    $0A: Code := 'es';
    $0C: Code := 'fr';
    $16: Code := 'pt';
    $07: Code := 'de';
  end;
  {$ELSE}
  // LC_ALL, LC_MESSAGES, LANGUAGE and LANG say it as es_ES.UTF-8
  Code := GetEnvironmentVariable('LC_ALL');
  if Code = '' then Code := GetEnvironmentVariable('LC_MESSAGES');
  if Code = '' then Code := GetEnvironmentVariable('LANGUAGE');
  if Code = '' then Code := GetEnvironmentVariable('LANG');
  Code := LowerCase(Copy(Code, 1, 2));
  {$ENDIF}
  for C := lgSpanish to High(TLanguage) do
    if Code = LANGUAGE_CODES[C] then Result := C;
end;

{$IFDEF WINDOWS}
function LeftCtrlHeld: Boolean;
begin
  Result := WinGetAsyncKeyState($A2) < 0;     // VK_LCONTROL
end;
{$ELSE}
type
  TXOpenDisplay = function(Name: PChar): Pointer; cdecl;
  TXCloseDisplay = function(Display: Pointer): LongInt; cdecl;
  TXQueryKeymap = function(Display: Pointer; Keys: PChar): LongInt; cdecl;
  TXKeysymToKeycode = function(Display: Pointer; KeySym: PtrUInt): Byte; cdecl;

{ X11 is loaded when there is one: without it (or on Wayland alone) it is False }
function LeftCtrlHeld: Boolean;
var
  Lib: TLibHandle;
  OpenD: TXOpenDisplay;
  CloseD: TXCloseDisplay;
  Query: TXQueryKeymap;
  ToCode: TXKeysymToKeycode;
  Dpy: Pointer;
  Keys: array[0..31] of Byte;
  Code: Byte;
begin
  Result := False;
  Lib := LoadLibrary('libX11.so.6');
  if Lib = NilHandle then Exit;
  try
    OpenD := TXOpenDisplay(GetProcedureAddress(Lib, 'XOpenDisplay'));
    CloseD := TXCloseDisplay(GetProcedureAddress(Lib, 'XCloseDisplay'));
    Query := TXQueryKeymap(GetProcedureAddress(Lib, 'XQueryKeymap'));
    ToCode := TXKeysymToKeycode(GetProcedureAddress(Lib, 'XKeysymToKeycode'));
    if not (Assigned(OpenD) and Assigned(CloseD) and Assigned(Query) and Assigned(ToCode)) then Exit;
    Dpy := OpenD(nil);
    if Dpy = nil then Exit;
    try
      FillChar(Keys, SizeOf(Keys), 0);
      Query(Dpy, @Keys[0]);
      Code := ToCode(Dpy, $FFE3);              // XK_Control_L
      Result := (Code <> 0) and ((Keys[Code shr 3] and (1 shl (Code and 7))) <> 0);
    finally
      CloseD(Dpy);
    end;
  except
    Result := False;
  end;
end;
{$ENDIF}

{ The stock texts of the LCL (the dialogs' buttons...), by their English value }
function TranslateLclString(Name, Value: AnsiString; Hash: LongInt; Arg: Pointer): AnsiString;
var
  I: Integer;
begin
  Result := Value;
  if (LclTable <> nil) and FindPair(LclTable, LclCount, Value, I) then Result := (LclTable + 2 * I + 1)^;
end;

procedure SetLanguage(L: TLanguage);
begin
  if L = lgAuto then L := OSLanguage;
  Current := L;
  Table := nil;
  LclTable := nil;
  case L of
    lgSpanish:
      begin
        Table := @LANG_ES[0]; TableCount := Length(LANG_ES) div 2;
        LclTable := @LCL_ES[0]; LclCount := Length(LCL_ES) div 2;
      end;
    lgFrench:
      begin
        Table := @LANG_FR[0]; TableCount := Length(LANG_FR) div 2;
        LclTable := @LCL_FR[0]; LclCount := Length(LCL_FR) div 2;
      end;
    lgPortuguese:
      begin
        Table := @LANG_PT[0]; TableCount := Length(LANG_PT) div 2;
        LclTable := @LCL_PT[0]; LclCount := Length(LCL_PT) div 2;
      end;
    lgGerman:
      begin
        Table := @LANG_DE[0]; TableCount := Length(LANG_DE) div 2;
        LclTable := @LCL_DE[0]; LclCount := Length(LCL_DE) div 2;
      end;
  end;
  if LclTable <> nil then SetUnitResourceStrings('lclstrconsts', @TranslateLclString, nil);
end;

function CurrentLanguage: TLanguage;
begin
  Result := Current;
end;

end.

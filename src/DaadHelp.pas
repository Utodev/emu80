{ DaadHelp: what a condact does, for the Adventure Debugger's hints: DAAD's
  from DaadHelp.inc (tools/make-daad-help.py), PAW's from PawHelp.inc
  (tools/make-paw-help.py, from PAW's technical guide), The Quill's from
  QuillHelp.inc (tools/make-quill-help.py, from its manual). }
unit DaadHelp;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Daad;

{ The help for a condact by name ('' if there is none) }
function CondactHelp(const Name: string; Engine: TAdvEngine): string;

implementation

{$I DaadHelp.inc}
{$I PawHelp.inc}
{$I QuillHelp.inc}

const
  { Condacts DAAD has but its documentation doesn't describe }
  EXTRA_NAMES: array[0..2] of string = ('EXTERN', 'CALL', 'DUMB');
  EXTRA_TEXTS: array[0..2] of string = (
    'EXTERN value routine' + LineEnding +
      'Calls external machine code (the routine number says which one) with the value as ' +
      'parameter. What it does depends on the interpreter and the game.',
    'CALL address' + LineEnding +
      'Calls machine code at that address of the database.',
    'Unused condact number: it does nothing.');

function CondactHelp(const Name: string; Engine: TAdvEngine): string;
var
  I: Integer;
begin
  Result := '';
  // The Quill's manual describes its condacts; PAW's text for any other
  if Engine = aeQuill then
    for I := 0 to QUILL_HELP_COUNT - 1 do
      if QUILL_HELP_NAMES[I] = Name then Exit(QUILL_HELP_TEXTS[I]);
  if Engine in [aePAW, aeQuill] then
  begin
    for I := 0 to PAW_HELP_COUNT - 1 do
      if PAW_HELP_NAMES[I] = Name then Exit(PAW_HELP_TEXTS[I]);
    Exit;
  end;
  for I := 0 to DAAD_HELP_COUNT - 1 do
    if DAAD_HELP_NAMES[I] = Name then Exit(DAAD_HELP_TEXTS[I]);
  for I := 0 to High(EXTRA_NAMES) do
    if EXTRA_NAMES[I] = Name then Exit(EXTRA_TEXTS[I]);
end;

end.

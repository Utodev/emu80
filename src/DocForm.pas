{ DocForm: shows the text files that come with pzx, README.TXT (how pzx
  works and its command line options) and LICENSE, in non-modal windows. }
unit DocForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, Graphics;

const
  DOC_FILE = 'README.TXT';
  LICENSE_FILE = 'LICENSE';

{ Full path of one of pzx's text files, or '' if it can't be found }
function PzxFile(const Name: string): string;
procedure ShowDocumentation;
procedure ShowLicense;

implementation

var
  DocWindow, LicenseWindow: TForm;

function PzxFile(const Name: string): string;
var
  Dir: string;
begin
  Dir := ExtractFilePath(ParamStr(0));
  Result := Dir + Name;
  if FileExists(Result) then Exit;
  Result := Dir + '..' + PathDelim + Name;     // executable built inside src
  if FileExists(Result) then Exit;
  Result := Dir + '../Resources/' + Name;      // macOS app bundle
  if FileExists(Result) then Exit;
  Result := IncludeTrailingPathDelimiter(GetCurrentDir) + Name;
  if FileExists(Result) then Exit;
  Result := '';
end;

{ A window with the text of a file, created once and then brought back }
procedure ShowTextFile(var Window: TForm; const Name, ACaption: string);
var
  Memo: TMemo;
  FileName: string;
begin
  if Window = nil then
  begin
    Window := TForm.CreateNew(Application, 0);
    Window.Caption := ACaption;
    Window.Width := 820;
    Window.Height := 700;
    Window.Position := poMainFormCenter;
    Memo := TMemo.Create(Window);
    Memo.Parent := Window;
    Memo.Align := alClient;
    Memo.ReadOnly := True;
    Memo.ScrollBars := ssAutoBoth;
    Memo.WordWrap := False;
    {$IFDEF WINDOWS}
    Memo.Font.Name := 'Consolas';
    {$ELSE}
    {$IFDEF DARWIN}
    Memo.Font.Name := 'Menlo';
    {$ELSE}
    Memo.Font.Name := 'Monospace';
    {$ENDIF}
    {$ENDIF}
    Memo.Font.Size := 10;
    FileName := PzxFile(Name);
    if FileName <> '' then
      Memo.Lines.LoadFromFile(FileName)
    else
      Memo.Lines.Text := Name + ' was not found next to the pzx executable.';
  end;
  Window.Show;
  Window.BringToFront;
end;

procedure ShowDocumentation;
begin
  ShowTextFile(DocWindow, DOC_FILE, 'pzx documentation');
end;

procedure ShowLicense;
begin
  ShowTextFile(LicenseWindow, LICENSE_FILE, 'pzx license (GNU GPL v3)');
end;

end.

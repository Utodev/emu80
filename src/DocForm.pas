{ DocForm: shows the files that come with emu80, README.md (how emu80 works and
  its command line options, in the Markdown viewer, with Find) and LICENSE
  (plain text), in non-modal windows. }
unit DocForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Graphics, LCLType, MdView;

const
  DOC_FILE = 'README.md';
  LICENSE_FILE = 'LICENSE';

{ Full path of one of emu80's text files, or '' if it can't be found }
function Emu80File(const Name: string): string;
procedure ShowDocumentation;
procedure ShowLicense;

implementation

var
  DocWindow, LicenseWindow: TForm;

function Emu80File(const Name: string): string;
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
    FileName := Emu80File(Name);
    if FileName <> '' then
      Memo.Lines.LoadFromFile(FileName)
    else
      Memo.Lines.Text := Name + ' was not found next to the emu80 executable.';
  end;
  Window.Show;
  Window.BringToFront;
end;

type
  { The documentation window: the viewer with a Find box above it }
  TDocWindow = class(TForm)
  private
    FView: TMdView;
    FFind: TEdit;
    FNotFound: TLabel;
    procedure FindNext(Sender: TObject);
    procedure FindChange(Sender: TObject);
    procedure FindKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  public
    constructor CreateDoc(AOwner: TComponent);
  end;

constructor TDocWindow.CreateDoc(AOwner: TComponent);
var
  Bar: TPanel;
  Lbl: TLabel;
  Btn: TButton;
  FileName: string;
begin
  inherited CreateNew(AOwner, 0);
  Caption := 'emu80 documentation';
  Width := 860;
  Height := 720;
  Position := poMainFormCenter;
  KeyPreview := True;
  OnKeyDown := @FormKeyDown;
  Bar := TPanel.Create(Self);
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.BevelOuter := bvNone;
  Bar.AutoSize := True;
  Bar.BorderSpacing.Around := 4;
  Lbl := TLabel.Create(Self);
  Lbl.Parent := Bar;
  Lbl.Caption := 'Find:';
  Lbl.Align := alLeft;
  Lbl.Layout := tlCenter;
  Lbl.BorderSpacing.Right := 6;
  FFind := TEdit.Create(Self);
  FFind.Parent := Bar;
  FFind.Align := alLeft;
  FFind.Width := 220;
  FFind.Left := 100;
  FFind.OnKeyDown := @FindKeyDown;
  FFind.OnChange := @FindChange;
  Btn := TButton.Create(Self);
  Btn.Parent := Bar;
  Btn.Caption := 'Next';
  Btn.Align := alLeft;
  Btn.Left := 400;
  Btn.AutoSize := True;
  Btn.BorderSpacing.Left := 6;
  Btn.OnClick := @FindNext;
  FNotFound := TLabel.Create(Self);
  FNotFound.Parent := Bar;
  FNotFound.Align := alLeft;
  FNotFound.Left := 500;
  FNotFound.Layout := tlCenter;
  FNotFound.BorderSpacing.Left := 10;
  FNotFound.Font.Color := clMaroon;
  FView := TMdView.Create(Self);
  FView.Parent := Self;
  FView.Align := alClient;
  FileName := Emu80File(DOC_FILE);
  if FileName <> '' then FView.LoadFromFile(FileName)
  else FView.LoadFromText(DOC_FILE + ' was not found next to the emu80 executable.');
  ActiveControl := FView;
end;

procedure TDocWindow.FindNext(Sender: TObject);
begin
  if FView.Find(FFind.Text) then FNotFound.Caption := ''
  else if FFind.Text <> '' then FNotFound.Caption := 'Not found (Next starts again at the top)';
end;

procedure TDocWindow.FindChange(Sender: TObject);
begin
  // Typing searches again from the top
  FView.Find('');
  FindNext(nil);
end;

procedure TDocWindow.FindKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    FindNext(nil);
    Key := 0;
  end;
end;

procedure TDocWindow.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_F) and (ssCtrl in Shift) then
  begin
    FFind.SetFocus;
    FFind.SelectAll;
    Key := 0;
  end
  else if (Key = VK_F3) then
  begin
    FindNext(nil);
    Key := 0;
  end
  else if Key = VK_ESCAPE then
  begin
    Close;
    Key := 0;
  end;
end;

procedure ShowDocumentation;
begin
  if DocWindow = nil then DocWindow := TDocWindow.CreateDoc(Application);
  DocWindow.Show;
  DocWindow.BringToFront;
end;

procedure ShowLicense;
begin
  ShowTextFile(LicenseWindow, LICENSE_FILE, 'emu80 license (GNU GPL v3)');
end;

end.

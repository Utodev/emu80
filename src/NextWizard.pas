{ NextWizard: when the ZX Spectrum Next's distribution isn't there (pzx
  can't include it), a few steps to get it: where to download it, then the
  file downloaded, unpacked into the specnext folder and checked. Closing
  the window or Escape stops it at any step. }
unit NextWizard;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Dialogs, Graphics, LCLType,
  LCLIntf, FileUtil, Zipper;

{ Ask whether to install the distribution into Dir and guide through it
  (all in one window, so it takes the theme in use). True: it is there now. }
function InstallNextDistro(const Dir: string): Boolean;

implementation

uses
  NextCard, ModernUI;

type
  TNextWizard = class(TForm)
  private
    FDir: string;
    FStep: Integer;
    FText: TLabel;
    FLink: TLabel;
    FBar: TProgressBar;
    FNext, FCancel: TButton;
    FBusy: Boolean;
    FDone: Boolean;
    procedure ShowStep;
    procedure NextClick(Sender: TObject);
    procedure LinkClick(Sender: TObject);
    procedure KeyDownHandler(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure CloseQueryHandler(Sender: TObject; var CanClose: Boolean);
    procedure UnzipProgress(Sender: TObject; const Pct: Double);
    function Unpack(const ZipFile: string): Boolean;
  public
    constructor CreateWizard(const ADir: string);
  end;

constructor TNextWizard.CreateWizard(const ADir: string);
begin
  inherited CreateNew(nil, 0);
  FDir := ADir;
  Caption := 'ZX Spectrum Next distribution';
  BorderStyle := bsDialog;
  Position := poMainFormCenter;
  ClientWidth := ScaleX(520, 96);
  ClientHeight := ScaleY(170, 96);
  KeyPreview := True;
  OnKeyDown := @KeyDownHandler;
  OnCloseQuery := @CloseQueryHandler;

  FText := TLabel.Create(Self);
  FText.Parent := Self;
  FText.AutoSize := False;
  FText.WordWrap := True;
  FText.SetBounds(ScaleX(16, 96), ScaleY(16, 96), ClientWidth - ScaleX(32, 96), ScaleY(100, 96));

  // The download page, opened in the system's browser
  FLink := TLabel.Create(Self);
  FLink.Parent := Self;
  FLink.Caption := NEXT_DOWNLOAD_URL;
  FLink.Font.Style := [fsUnderline];
  FLink.Cursor := crHandPoint;
  FLink.Hint := 'Open it in the browser';
  FLink.ShowHint := True;
  FLink.OnClick := @LinkClick;
  // Its own colour: a link's, readable on either theme
  FLink.Tag := THEME_OWN_COLOURS;
  if DarkTheme then FLink.Font.Color := $00FFC678 else FLink.Font.Color := clBlue;
  FLink.Left := ScaleX(16, 96);
  FLink.Top := ScaleY(84, 96);

  FBar := TProgressBar.Create(Self);
  FBar.Parent := Self;
  FBar.SetBounds(ScaleX(16, 96), ScaleY(120, 96), ClientWidth - ScaleX(32, 96), ScaleY(18, 96));
  FBar.Max := 100;

  FCancel := TButton.Create(Self);
  FCancel.Parent := Self;
  FCancel.Caption := 'Cancel';
  FCancel.Cancel := True;
  FCancel.ModalResult := mrCancel;
  FCancel.SetBounds(ClientWidth - ScaleX(96, 96), ClientHeight - ScaleY(40, 96), ScaleX(80, 96),
    ScaleY(28, 96));
  FNext := TButton.Create(Self);
  FNext.Parent := Self;
  FNext.Caption := 'Next >';
  FNext.Default := True;
  FNext.OnClick := @NextClick;
  FNext.SetBounds(FCancel.Left - ScaleX(88, 96), FCancel.Top, ScaleX(80, 96), ScaleY(28, 96));
  FStep := 0;
  ShowStep;
end;

procedure TNextWizard.ShowStep;
begin
  FLink.Visible := FStep = 1;
  FBar.Visible := FStep = 3;
  FNext.Visible := FStep < 4;
  FNext.Enabled := FStep < 3;
  FCancel.Enabled := FStep <> 3;
  if FStep = 0 then FNext.Caption := '&Yes' else FNext.Caption := '&Next >';
  case FStep of
    0: FCancel.Caption := '&No';
    4: FCancel.Caption := '&Close';
  else
    FCancel.Caption := 'Cancel';
  end;
  case FStep of
    0: FText.Caption := 'The ZX Spectrum Next distribution files are not available (they can''t ' +
         'come with pzx).' + LineEnding + LineEnding + 'Do you want to know how to install them?';
    1: FText.Caption := 'Step 1 of 2. Go to the page below and look for "Full distribution ' +
         'downloads": the lightweight one is enough.' + LineEnding + LineEnding +
         'When you have downloaded it, press Next.';
    2: FText.Caption := 'Step 2 of 2. When you press Next, choose the distribution file you ' +
         'have downloaded (a .zip file).' + LineEnding + LineEnding +
         'It will be unpacked into:' + LineEnding + FDir;
    3: FText.Caption := 'Unpacking the distribution into:' + LineEnding + FDir;
    4: FText.Caption := 'That file is not a ZX Spectrum Next distribution. What was unpacked ' +
         'from it has been deleted.';
  end;
end;

procedure TNextWizard.LinkClick(Sender: TObject);
begin
  OpenURL(NEXT_DOWNLOAD_URL);
end;

procedure TNextWizard.KeyDownHandler(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_ESCAPE) and not FBusy then
  begin
    Key := 0;
    ModalResult := mrCancel;
  end;
end;

procedure TNextWizard.CloseQueryHandler(Sender: TObject; var CanClose: Boolean);
begin
  // Not in the middle of unpacking
  CanClose := not FBusy;
end;

procedure TNextWizard.UnzipProgress(Sender: TObject; const Pct: Double);
begin
  if Round(Pct) <> FBar.Position then
  begin
    FBar.Position := Round(Pct);
    Application.ProcessMessages;
  end;
end;

procedure TNextWizard.NextClick(Sender: TObject);
var
  Dlg: TOpenDialog;
  ZipFile: string;
begin
  if FStep < 2 then
  begin
    Inc(FStep);
    ShowStep;
    Exit;
  end;
  // Step 2: the file
  Dlg := TOpenDialog.Create(nil);
  try
    Dlg.Title := 'The ZX Spectrum Next distribution downloaded';
    Dlg.Filter := 'Zip files (*.zip)|*.zip|All files|*.*';
    Dlg.Options := Dlg.Options + [ofFileMustExist];
    if not Dlg.Execute then Exit;
    ZipFile := Dlg.FileName;
  finally
    Dlg.Free;
  end;
  FStep := 3;
  ShowStep;
  FBusy := True;
  try
    FDone := Unpack(ZipFile);
  finally
    FBusy := False;
  end;
  if FDone then
    ModalResult := mrOK
  else
  begin
    // Said here, and the end
    FStep := 4;
    ShowStep;
  end;
end;

{ Unpacked into the folder, and checked: a distribution inside one folder
  of the zip is moved up. What doesn't make a distribution is deleted. }
function TNextWizard.Unpack(const ZipFile: string): Boolean;
var
  Before, After, Sub: TStringList;
  Info: TSearchRec;
  I: Integer;
  Inner, Entry: string;
  UnZip: TUnZipper;

  procedure List(L: TStringList);
  begin
    L.Clear;
    if FindFirst(IncludeTrailingPathDelimiter(FDir) + '*', faAnyFile, Info) = 0 then
    begin
      repeat
        if (Info.Name <> '.') and (Info.Name <> '..') then L.Add(Info.Name);
      until FindNext(Info) <> 0;
      FindClose(Info);
    end;
  end;

  procedure Remove(const Path: string);
  begin
    if DirectoryExists(Path) then DeleteDirectory(Path, False) else DeleteFile(Path);
  end;

begin
  Result := False;
  ForceDirectories(FDir);
  Before := TStringList.Create;
  After := TStringList.Create;
  Sub := TStringList.Create;
  try
    List(Before);
    Screen.Cursor := crHourGlass;
    try
      UnZip := TUnZipper.Create;
      try
        UnZip.FileName := ZipFile;
        UnZip.OutputPath := FDir;
        UnZip.OnProgress := @UnzipProgress;
        UnZip.UnZipAllFiles;
      finally
        UnZip.Free;
      end;
    except
      // Not a zip (or a broken one): nothing of it is kept
    end;
    Screen.Cursor := crDefault;
    List(After);
    // Only what was unpacked now
    for I := After.Count - 1 downto 0 do
      if Before.IndexOf(After[I]) >= 0 then After.Delete(I);
    // The distribution inside a single folder: moved up into this one
    if not NextDistroReady(FDir) and (After.Count = 1) and
       NextDistroReady(IncludeTrailingPathDelimiter(FDir) + After[0]) then
    begin
      Inner := IncludeTrailingPathDelimiter(FDir) + After[0];
      if FindFirst(IncludeTrailingPathDelimiter(Inner) + '*', faAnyFile, Info) = 0 then
      begin
        repeat
          if (Info.Name <> '.') and (Info.Name <> '..') then Sub.Add(Info.Name);
        until FindNext(Info) <> 0;
        FindClose(Info);
      end;
      for Entry in Sub do
        if not FileExists(IncludeTrailingPathDelimiter(FDir) + Entry) and
           not DirectoryExists(IncludeTrailingPathDelimiter(FDir) + Entry) then
        begin
          RenameFile(IncludeTrailingPathDelimiter(Inner) + Entry, IncludeTrailingPathDelimiter(FDir) + Entry);
          After.Add(Entry);
        end;
      Remove(Inner);
      After.Delete(0);
    end;
    Result := NextDistroReady(FDir);
    if not Result then
      for Entry in After do Remove(IncludeTrailingPathDelimiter(FDir) + Entry);
  finally
    Screen.Cursor := crDefault;
    Before.Free;
    After.Free;
    Sub.Free;
  end;
end;

function InstallNextDistro(const Dir: string): Boolean;
var
  W: TNextWizard;
begin
  W := TNextWizard.CreateWizard(Dir);
  try
    Result := (W.ShowModal = mrOK) and NextDistroReady(Dir);
  finally
    W.Free;
  end;
end;

end.

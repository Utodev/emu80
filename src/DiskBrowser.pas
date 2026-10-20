{ DiskBrowser: the files on the disk in drive A: or B: (+3DOS), with their
  type, start address or autostart line and length. Files can be renamed,
  deleted, exported to the PC and imported from it. }
unit DiskBrowser;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, ComCtrls, StdCtrls, ExtCtrls, Dialogs, LCLType, Emulator, DSK,
  Plus3FS, Icons, Spectrum, PathTitle;

type
  TDiskBrowserWindow = class(TForm)
  private
    FTitle: TPathTitle;                // the title, with the file's path
    FEmu: TEmulator;
    FDrive: Integer;
    FToolBar: TToolBar;
    FImages: TImageList;
    FDriveCombo: TComboBox;
    FDriveList: string;    // drives in the combo ("A", "AB"...)
    FList: TListView;
    FStatus: TStatusBar;
    FTimer: TTimer;
    FLastDisk: TDiskImage;
    FLastModified: Boolean;
    FQuiet: Boolean;       // WithDisk: no error message, just FLastError
    FLastError: string;
    function AddButton(AIcon: TIconKind; const AHint: string; AHandler: TNotifyEvent): TToolButton;
    procedure AddSeparator;
    { Run Action on the file system of the disk in the drive, with the
      emulator locked. False (with a message) if there is no usable disk. }
    function WithDisk(AAction: Integer; Index: Integer = -1; const Arg: string = '';
      const Data: TBytes = nil): Boolean;
    function SelectedIndex: Integer;
    procedure DriveChange(Sender: TObject);
    { The drive list: only drives with a disk; moves to another drive if
      this one has none any more }
    procedure UpdateDrives;
    procedure Tick(Sender: TObject);
    procedure DoRefresh(Sender: TObject);
    procedure DoRename(Sender: TObject);
    procedure DoDelete(Sender: TObject);
    procedure DoExport(Sender: TObject);
    procedure DoImport(Sender: TObject);
    procedure DoImportFolder(Sender: TObject);
    procedure FormDropFiles(Sender: TObject; const FileNames: array of string);
    function ImportExists(const AName: string): Boolean;
    function ImportWrite(const AName: string; const Data: TBytes; Replace: Boolean): string;
    procedure ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
  public
    constructor CreateFor(AOwner: TComponent; AEmu: TEmulator);
    procedure ShowDrive(Drive: Integer);
    procedure Refresh;
  end;

var
  DiskBrowserWindow: TDiskBrowserWindow;

{ Open the browser on Drive, or (Drive = -1) on A: if it has a disk, else
  on B:. Does nothing if there is no disk to browse. }
procedure ShowDiskBrowser(Emu: TEmulator; Drive: Integer = -1);
{ A drive can be browsed: it has a disk (and B: is connected). Call with the
  emulator locked. }
function DriveAvailable(Spec: TSpectrum; Drive: Integer): Boolean;
{ The drive the browser opens on, -1 if neither has a disk (emulator locked) }
function DefaultDrive(Spec: TSpectrum): Integer;

type
  TBytesArray = array of TBytes;
  { For ImportFromPC: whether a file is already there, and writing one
    (Replace: the one there goes first); '' or an error message }
  TImportExists = function(const AName: string): Boolean of object;
  TImportWrite = function(const AName: string; const Data: TBytes; Replace: Boolean): string of object;
  { Making a folder (Path: "GAMES" or "GAMES/ARCADE", inside the browser's
    folder); '' or an error message }
  TImportMakeDir = function(const Path: string): string of object;

{ Shared with the SD card browser: the name and header of a file imported
  from the PC (DefaultHeader: the header box ticked at first; Remaining:
  files still to import after this one, ForAll: use the same choices for
  them), and a name suggested from its PC file name }
function AskImport(const FileName: string; Size: Integer; var AName: string; out Header: Boolean;
  out Addr: Word; DefaultHeader: Boolean; Remaining: Integer; out ForAll: Boolean;
  LongNames: Boolean = False): Boolean;
function SuggestName(const FileName: string): string;
{ Import files and folders of the PC with Exists and Write: Paths (dropped
  on the browser), else the ones chosen in a dialog (PickFolder: a folder,
  else several files). With MakeDir, folders are made again with their
  contents (Exists and Write then get names like "GAMES/ARCADE/JET.TAP");
  without it (a +3 disk has no folders) the files in them are all imported
  side by side; the files in a folder made again are copied as they are,
  without asking (no +3DOS header). LongNames: the PC's names are kept
  (the ZX Spectrum Next's card), else they become 8.3 ones. A progress bar
  shows meanwhile, and the program can't be used. Dir: the browser's last
  PC folder (updated). Returns a status text. }
function ImportFromPC(var Dir: string; DefaultHeader: Boolean; Exists: TImportExists;
  Write: TImportWrite; MakeDir: TImportMakeDir = nil; Paths: TStrings = nil;
  PickFolder: Boolean = False; LongNames: Boolean = False): string;
{ Export files to the PC: one with a save dialog, several into a folder;
  asks before overwriting, and once whether to keep +3DOS headers. Dir: the
  browser's last PC folder (updated). Returns a status text. }
function ExportToPC(const Names: array of string; Datas: TBytesArray; var Dir: string): string;
{ Overwrite AName? Yes, No or Cancel; with Many also Yes to all, which sets
  All (and then answers Yes) }
function AskOverwrite(const AName: string; Many: Boolean; var All: Boolean): Integer;

implementation

uses
  Config;

const
  ACT_LIST = 0;
  ACT_READ = 1;
  ACT_WRITE = 2;
  ACT_RENAME = 3;
  ACT_DELETE = 4;
  ACT_FIND = 5;      // FoundIndex := the file called Arg, -1 if none
  ACT_REPLACE = 6;   // as ACT_WRITE, deleting the file with that name first

var
  // Result of the last ACT_READ and ACT_FIND
  ReadData: TBytes;
  FoundIndex: Integer;

{ The folder to open a dialog in: the browser's last one, else the last one
  used anywhere }
function StartDir(const Dir: string): string;
begin
  if (Dir <> '') and DirectoryExists(Dir) then Result := Dir else Result := Settings.LastDir;
end;

function AskOverwrite(const AName: string; Many: Boolean; var All: Boolean): Integer;
var
  Buttons: TMsgDlgButtons;
begin
  if All then Exit(mrYes);
  Buttons := [mbYes, mbNo, mbCancel];
  if Many then Buttons := Buttons + [mbYesToAll];
  Result := MessageDlg('Overwrite', Format('%s already exists. Overwrite it?', [AName]),
    mtConfirmation, Buttons, 0);
  if Result = mrYesToAll then
  begin
    All := True;
    Result := mrYes;
  end;
end;

{ A progress window over the program, which can't be used meanwhile }
type
  TImportProgress = class
  private
    FForm: TForm;
    FBar: TProgressBar;
    FLabel: TLabel;
    FDisabled: TList;
  public
    constructor Create(Total: Integer);
    destructor Destroy; override;
    procedure Step(Done: Integer; const What: string);
  end;

constructor TImportProgress.Create(Total: Integer);
var
  I: Integer;
begin
  inherited Create;
  FDisabled := TList.Create;
  FForm := TForm.CreateNew(nil, 0);
  FForm.Caption := 'Importing';
  FForm.BorderStyle := bsDialog;
  FForm.BorderIcons := [];
  FForm.Position := poMainFormCenter;
  FForm.FormStyle := fsStayOnTop;
  FForm.ClientWidth := 420;
  FForm.ClientHeight := 70;
  FLabel := TLabel.Create(FForm);
  FLabel.Parent := FForm;
  FLabel.SetBounds(12, 10, 396, 18);
  FBar := TProgressBar.Create(FForm);
  FBar.Parent := FForm;
  FBar.SetBounds(12, 34, 396, 22);
  FBar.Max := Total;
  // Everything else waits: no clicks or keys until it is over
  for I := 0 to Screen.FormCount - 1 do
    if Screen.Forms[I].Enabled and (Screen.Forms[I] <> FForm) then
    begin
      FDisabled.Add(Screen.Forms[I]);
      Screen.Forms[I].Enabled := False;
    end;
  FForm.Show;
  Application.ProcessMessages;
end;

destructor TImportProgress.Destroy;
var
  I: Integer;
begin
  for I := 0 to FDisabled.Count - 1 do TForm(FDisabled[I]).Enabled := True;
  FDisabled.Free;
  FForm.Free;
  inherited Destroy;
end;

procedure TImportProgress.Step(Done: Integer; const What: string);
begin
  FBar.Position := Done;
  FLabel.Caption := What;
  Application.ProcessMessages;
end;

function ImportFromPC(var Dir: string; DefaultHeader: Boolean; Exists: TImportExists;
  Write: TImportWrite; MakeDir: TImportMakeDir; Paths: TStrings; PickFolder: Boolean;
  LongNames: Boolean): string;
var
  Files, Prefixes, Folders: TStringList;
  Progress: TImportProgress;

  { The name on the card or disk for a PC name }
  function CardName(const PCName: string): string;
  begin
    if LongNames then Result := ExtractFileName(ExcludeTrailingPathDelimiter(PCName))
    else Result := SuggestName(PCName);
  end;

  // A file, or a folder with what is in it (Prefix: the folders it is in)
  procedure Add(const Path, Prefix: string);
  var
    Info: TSearchRec;
    Names: TStringList;
    Sub: string;
    K: Integer;
  begin
    if not DirectoryExists(Path) then
    begin
      if FileExists(Path) then
      begin
        Files.Add(Path);
        Prefixes.Add(Prefix);
      end;
      Exit;
    end;
    Sub := Prefix;
    if Assigned(MakeDir) then
    begin
      Sub := Prefix + CardName(Path);
      if Folders.IndexOf(Sub) < 0 then Folders.Add(Sub);
      Sub := Sub + '/';
    end;
    Names := TStringList.Create;
    try
      if FindFirst(IncludeTrailingPathDelimiter(Path) + '*', faAnyFile, Info) = 0 then
      try
        repeat
          if (Info.Name <> '.') and (Info.Name <> '..') then Names.Add(Info.Name);
        until FindNext(Info) <> 0;
      finally
        FindClose(Info);
      end;
      Names.Sort;
      for K := 0 to Names.Count - 1 do
        Add(IncludeTrailingPathDelimiter(Path) + Names[K], Sub);
    finally
      Names.Free;
    end;
  end;

var
  Dlg: TOpenDialog;
  DirDlg: TSelectDirectoryDialog;
  Data: TBytes;
  S: TFileStream;
  I, Done, Answer: Integer;
  AName, Error: string;
  Header, ForAll, SameHeader, OverwriteAll: Boolean;
  Addr: Word;
begin
  Result := '';
  Progress := nil;
  Files := TStringList.Create;
  Prefixes := TStringList.Create;
  Folders := TStringList.Create;
  try
    if Paths = nil then
    begin
      Paths := TStringList.Create;
      try
        if PickFolder then
        begin
          DirDlg := TSelectDirectoryDialog.Create(nil);
          try
            DirDlg.Title := 'Import a folder and its contents';
            DirDlg.InitialDir := StartDir(Dir);
            if not DirDlg.Execute then Exit;
            Paths.Add(DirDlg.FileName);
            // Next time the dialog opens where this folder is
            Dir := ExtractFileDir(ExcludeTrailingPathDelimiter(DirDlg.FileName));
          finally
            DirDlg.Free;
          end;
        end
        else
        begin
          Dlg := TOpenDialog.Create(nil);
          try
            Dlg.InitialDir := StartDir(Dir);
            Dlg.Filter := 'All files|*.*';
            Dlg.Options := Dlg.Options + [ofFileMustExist, ofAllowMultiSelect];
            if not Dlg.Execute then Exit;
            Paths.Assign(Dlg.Files);
            if Paths.Count > 0 then Dir := ExtractFileDir(Paths[0]);
          finally
            Dlg.Free;
          end;
        end;
        for I := 0 to Paths.Count - 1 do Add(Paths[I], '');
      finally
        Paths.Free;
      end;
    end
    else
    begin
      if Paths.Count > 0 then Dir := ExtractFileDir(ExcludeTrailingPathDelimiter(Paths[0]));
      for I := 0 to Paths.Count - 1 do Add(Paths[I], '');
    end;

    // Many files (a folder): a progress bar
    if (Folders.Count > 0) or (Files.Count > 1) then
      Progress := TImportProgress.Create(Folders.Count + Files.Count);
    // The folders first (parents come before what is in them)
    for I := 0 to Folders.Count - 1 do
    begin
      if Progress <> nil then Progress.Step(I, Folders[I]);
      Error := MakeDir(Folders[I]);
      if Error <> '' then
      begin
        MessageDlg('Could not create the folder ' + Folders[I] + ': ' + Error, mtError, [mbOK], 0);
        Exit('');
      end;
    end;

    Done := 0;
    ForAll := False;
    SameHeader := False;
    OverwriteAll := False;
    Addr := 32768;
    for I := 0 to Files.Count - 1 do
    begin
      if Progress <> nil then Progress.Step(Folders.Count + I, Prefixes[I] + ExtractFileName(Files[I]));
      try
        S := TFileStream.Create(Files[I], fmOpenRead or fmShareDenyWrite);
        try
          SetLength(Data, S.Size);
          if S.Size > 0 then S.ReadBuffer(Data[0], S.Size);
        finally
          S.Free;
        end;
      except
        on E: Exception do
        begin
          MessageDlg('Could not read ' + ExtractFileName(Files[I]) + ': ' + E.Message, mtError, [mbOK], 0);
          Continue;
        end;
      end;
      AName := CardName(Files[I]);
      if Prefixes[I] <> '' then
        // In a folder imported with its contents: copied as it is
      else if HasPlus3Header(Data) or (Length(Data) > 65535) then
      begin
        // Copied as it is
        if not ForAll then
        begin
          if LongNames then Error := 'Name (the file is copied as it is):'
          else Error := 'Name (8.3; the file is copied as it is):';
          if not InputQuery('Import ' + ExtractFileName(Files[I]), Error, AName) then Break;
        end;
      end
      else if ForAll then
      begin
        if SameHeader then Data := AddPlus3Header(Data, FT_BYTES, Addr, 32768);
      end
      else
      begin
        if not AskImport(Files[I], Length(Data), AName, Header, Addr, DefaultHeader,
          Files.Count - 1 - I, ForAll, LongNames) then Break;
        SameHeader := Header;
        if Header then Data := AddPlus3Header(Data, FT_BYTES, Addr, 32768);
      end;
      AName := Prefixes[I] + AName;
      Answer := mrNo;
      if Exists(AName) then
      begin
        if LongNames then Answer := AskOverwrite(AName, Files.Count > 1, OverwriteAll)
        else Answer := AskOverwrite(UpperCase(AName), Files.Count > 1, OverwriteAll);
        if Answer = mrCancel then Break;
        if Answer = mrNo then Continue;
      end;
      Error := Write(AName, Data, Answer = mrYes);
      if Error <> '' then
      begin
        MessageDlg('Could not import ' + ExtractFileName(Files[I]) + ': ' + Error, mtError, [mbOK], 0);
        Break;
      end;
      Inc(Done);
      if (Files.Count = 1) and (Folders.Count = 0) then
      begin
        if LongNames then Result := 'imported ' + AName else Result := 'imported ' + UpperCase(AName);
      end;
    end;
    if (Files.Count > 1) or (Done = 0) or (Folders.Count > 0) then
      Result := Format('imported %d of %d files', [Done, Files.Count]);
    if Folders.Count = 1 then Result := Result + ', 1 folder'
    else if Folders.Count > 1 then Result := Result + Format(', %d folders', [Folders.Count]);
  finally
    Progress.Free;
    Files.Free;
    Prefixes.Free;
    Folders.Free;
  end;
end;

function ExportToPC(const Names: array of string; Datas: TBytesArray; var Dir: string): string;
var
  Dlg: TSaveDialog;
  DirDlg: TSelectDirectoryDialog;
  I, Answer, WithHeader, Done: Integer;
  Target: string;
  OverwriteAll: Boolean;
  S: TFileStream;
begin
  Result := '';
  if Length(Names) = 0 then Exit;
  // Usually what is wanted is the data (a .bin, a screen...), without the
  // 128-byte +3DOS header in front
  WithHeader := 0;
  for I := 0 to High(Datas) do
    if HasPlus3Header(Datas[I]) then Inc(WithHeader);
  if WithHeader > 0 then
  begin
    if Length(Names) = 1 then
      Answer := MessageDlg('Export', 'The file has a +3DOS header. Keep it in the exported file?' +
        LineEnding + LineEnding + 'No: just the data (' + IntToStr(Length(Datas[0]) - PLUS3_HEADER_SIZE) +
        ' bytes).', mtConfirmation, [mbYes, mbNo, mbCancel], 0)
    else
      Answer := MessageDlg('Export', Format('%d of the files have a +3DOS header. Keep it in the ' +
        'exported files?', [WithHeader]) + LineEnding + LineEnding + 'No: just their data.',
        mtConfirmation, [mbYes, mbNo, mbCancel], 0);
    if Answer = mrCancel then Exit;
    if Answer = mrNo then
      for I := 0 to High(Datas) do
        if HasPlus3Header(Datas[I]) then Datas[I] := Copy(Datas[I], PLUS3_HEADER_SIZE, MaxInt);
  end;
  if Length(Names) = 1 then
  begin
    Dlg := TSaveDialog.Create(nil);
    try
      Dlg.FileName := Names[0];
      Dlg.InitialDir := StartDir(Dir);
      Dlg.Filter := 'All files|*.*';
      Dlg.Options := Dlg.Options + [ofOverwritePrompt];
      if not Dlg.Execute then Exit;
      Target := Dlg.FileName;
      Dir := ExtractFileDir(Target);
    finally
      Dlg.Free;
    end;
  end
  else
  begin
    DirDlg := TSelectDirectoryDialog.Create(nil);
    try
      DirDlg.Title := Format('Export %d files to the folder', [Length(Names)]);
      DirDlg.InitialDir := StartDir(Dir);
      if not DirDlg.Execute then Exit;
      Dir := DirDlg.FileName;
    finally
      DirDlg.Free;
    end;
  end;
  Done := 0;
  OverwriteAll := False;
  for I := 0 to High(Names) do
  begin
    if Length(Names) > 1 then
    begin
      Target := IncludeTrailingPathDelimiter(Dir) + Names[I];
      if FileExists(Target) then
      begin
        Answer := AskOverwrite(Target, True, OverwriteAll);
        if Answer = mrCancel then Break;
        if Answer = mrNo then Continue;
      end;
    end;
    try
      S := TFileStream.Create(Target, fmCreate);
      try
        if Length(Datas[I]) > 0 then S.WriteBuffer(Datas[I][0], Length(Datas[I]));
      finally
        S.Free;
      end;
      Inc(Done);
    except
      on E: Exception do
      begin
        MessageDlg('Could not save ' + Target + ': ' + E.Message, mtError, [mbOK], 0);
        Break;
      end;
    end;
  end;
  if Length(Names) = 1 then
  begin
    if Done = 1 then Result := Format('Exported %s (%d bytes)', [ExtractFileName(Target), Length(Datas[0])]);
  end
  else
    Result := Format('Exported %d of %d files to %s', [Done, Length(Names), Dir]);
end;

function DriveAvailable(Spec: TSpectrum; Drive: Integer): Boolean;
begin
  Result := (Spec.FDC.Disk(Drive) <> nil) and ((Drive = 0) or Spec.FDC.DriveB);
end;

function DefaultDrive(Spec: TSpectrum): Integer;
begin
  if DriveAvailable(Spec, 0) then Result := 0
  else if DriveAvailable(Spec, 1) then Result := 1
  else Result := -1;
end;

procedure ShowDiskBrowser(Emu: TEmulator; Drive: Integer);
begin
  Emu.Lock;
  try
    if (Drive < 0) or not DriveAvailable(Emu.Spec, Drive) then Drive := DefaultDrive(Emu.Spec);
  finally
    Emu.Unlock;
  end;
  if Drive < 0 then Exit;   // no disk anywhere
  if DiskBrowserWindow = nil then
    DiskBrowserWindow := TDiskBrowserWindow.CreateFor(Application, Emu);
  DiskBrowserWindow.ShowDrive(Drive);
  DiskBrowserWindow.Show;
  DiskBrowserWindow.BringToFront;
end;

constructor TDiskBrowserWindow.CreateFor(AOwner: TComponent; AEmu: TEmulator);

  procedure AddColumn(const ACaption: string; AWidth: Integer; Right: Boolean = False);
  var
    Col: TListColumn;
  begin
    Col := FList.Columns.Add;
    Col.Caption := ACaption;
    Col.Width := AWidth;
    if Right then Col.Alignment := taRightJustify;
  end;

begin
  inherited CreateNew(AOwner, 0);
  FEmu := AEmu;
  Caption := 'Disk browser';
  FTitle := TPathTitle.Create(Self);
  Width := 640;
  Height := 400;
  Position := poMainFormCenter;
  OnClose := @FormClose;
  AllowDropFiles := True;
  OnDropFiles := @FormDropFiles;

  FImages := TImageList.Create(Self);
  LoadIcons(FImages);
  FToolBar := TToolBar.Create(Self);
  FToolBar.Parent := Self;
  FToolBar.Images := FImages;
  FToolBar.ShowCaptions := False;
  FToolBar.ShowHint := True;
  FToolBar.ButtonWidth := IconSize + 10;
  FToolBar.ButtonHeight := IconSize + 10;
  FToolBar.AutoSize := True;
  FDriveCombo := TComboBox.Create(Self);
  FDriveCombo.Parent := FToolBar;
  FDriveCombo.Style := csDropDownList;
  FDriveCombo.Width := 70;

  FDriveCombo.Hint := 'Drive (the ones with a disk)';
  FDriveCombo.ShowHint := True;
  FDriveCombo.OnChange := @DriveChange;
  FDriveCombo.Left := 1000;
  AddSeparator;
  AddButton(ikRefresh, 'Read the directory again', @DoRefresh);
  AddSeparator;
  AddButton(ikOpen, 'Import files from the PC onto the disk... (or drop files and folders here)', @DoImport);
  AddButton(ikImportFolder, 'Import the files in a folder of the PC (and its subfolders) onto the disk...',
    @DoImportFolder);
  AddButton(ikSave, 'Export the selected files to the PC...', @DoExport);
  AddButton(ikRename, 'Rename the selected file... (F2)', @DoRename);
  AddButton(ikDelete, 'Delete the selected files (Del)', @DoDelete);

  FStatus := TStatusBar.Create(Self);
  FStatus.Parent := Self;
  FStatus.SimplePanel := True;

  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.ViewStyle := vsReport;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.HideSelection := False;
  FList.MultiSelect := True;
  FList.OnDblClick := @DoExport;
  FList.OnKeyDown := @ListKeyDown;
  AddColumn('Name', 110);
  AddColumn('Type', 110);
  AddColumn('Start / line', 90, True);
  AddColumn('Length', 70, True);
  AddColumn('Size on disk', 90, True);
  AddColumn('Attributes', 90);

  FTimer := TTimer.Create(Self);
  FTimer.Interval := 1000;
  FTimer.OnTimer := @Tick;
end;

function TDiskBrowserWindow.AddButton(AIcon: TIconKind; const AHint: string;
  AHandler: TNotifyEvent): TToolButton;
begin
  Result := TToolButton.Create(FToolBar);
  Result.Parent := FToolBar;
  Result.ImageIndex := Ord(AIcon);
  Result.Hint := AHint;
  Result.OnClick := AHandler;
  Result.Left := FToolBar.Width + 1000;   // append at the right
end;

procedure TDiskBrowserWindow.AddSeparator;
var
  Sep: TToolButton;
begin
  Sep := TToolButton.Create(FToolBar);
  Sep.Parent := FToolBar;
  Sep.Style := tbsDivider;
  Sep.Left := FToolBar.Width + 1000;
end;

procedure TDiskBrowserWindow.ShowDrive(Drive: Integer);
begin
  FDrive := Drive;
  UpdateDrives;
  Refresh;
end;

procedure TDiskBrowserWindow.UpdateDrives;
var
  D: Integer;
  Avail: array[0..1] of Boolean;
  Wanted: string;
begin
  FEmu.Lock;
  try
    for D := 0 to 1 do Avail[D] := DriveAvailable(FEmu.Spec, D);
  finally
    FEmu.Unlock;
  end;
  if not Avail[FDrive] and Avail[1 - FDrive] then FDrive := 1 - FDrive;
  Wanted := '';
  for D := 0 to 1 do
    if Avail[D] then Wanted := Wanted + Chr(Ord('A') + D);
  // Rebuild the list only when it changes, not to disturb an open drop-down
  if (FDriveList <> Wanted) or (FDriveCombo.Items.Count = 0) then
  begin
    FDriveCombo.Items.Clear;
    for D := 0 to 1 do
      if Avail[D] then FDriveCombo.Items.AddObject(Chr(Ord('A') + D) + ':', TObject(PtrInt(D)));
    FDriveList := Wanted;
  end;
  FDriveCombo.ItemIndex := FDriveCombo.Items.IndexOfObject(TObject(PtrInt(FDrive)));
  FDriveCombo.Enabled := FDriveCombo.Items.Count > 1;
end;

procedure TDiskBrowserWindow.DriveChange(Sender: TObject);
begin
  if FDriveCombo.ItemIndex < 0 then Exit;
  FDrive := PtrInt(FDriveCombo.Items.Objects[FDriveCombo.ItemIndex]);
  Refresh;
end;

function TDiskBrowserWindow.SelectedIndex: Integer;
begin
  if FList.Selected = nil then Result := -1
  else Result := PtrInt(FList.Selected.Data);
end;

function TDiskBrowserWindow.WithDisk(AAction: Integer; Index: Integer; const Arg: string;
  const Data: TBytes): Boolean;
var
  Suffix: string;
  Disk: TDiskImage;
  FS: TPlus3Disk;
  I, Selected: Integer;
  Item: TListItem;
  F: TPlus3File;
  Attr, StartText: string;
  Error: string;
begin
  Result := False;
  Error := '';
  FLastError := '';
  FEmu.Lock;
  try
    Disk := FEmu.Spec.FDC.Disk(FDrive);
    FLastDisk := Disk;
    if Disk = nil then
    begin
      Error := Format('There is no disk in drive %s:', [Chr(Ord('A') + FDrive)]);
      FList.Items.Clear;
      FStatus.SimpleText := Error;
      Exit;
    end;
    FLastModified := Disk.Modified;
    try
      FS := TPlus3Disk.Create(Disk);
      try
        case AAction of
          ACT_READ: ReadData := FS.ReadFile(Index);
          ACT_WRITE: FS.WriteFile(Arg, Data);
          ACT_RENAME: FS.RenameFile(Index, Arg);
          ACT_DELETE: FS.DeleteFile(Index);
          ACT_FIND: FoundIndex := FS.FindFile(Arg);
          ACT_REPLACE:
            begin
              I := FS.FindFile(Arg);
              if I >= 0 then FS.DeleteFile(I);
              FS.WriteFile(Arg, Data);
            end;
        end;
        // Show the directory as it is now
        Selected := SelectedIndex;
        FList.Items.BeginUpdate;
        try
          FList.Items.Clear;
          for I := 0 to FS.Count - 1 do
          begin
            F := FS[I];
            Item := FList.Items.Add;
            Item.Caption := F.Name;
            Item.Data := Pointer(PtrInt(I));
            Item.SubItems.Add(FileTypeName(F));
            StartText := '';
            if F.HasHeader then
              case F.FileType of
                FT_BYTES: StartText := IntToStr(F.Param1);
                FT_PROGRAM: if F.Param1 < 32768 then StartText := 'LINE ' + IntToStr(F.Param1);
              end;
            Item.SubItems.Add(StartText);
            if F.HasHeader then Item.SubItems.Add(IntToStr(F.DataLength))
            else Item.SubItems.Add(IntToStr(F.Size));
            Item.SubItems.Add(IntToStr(F.Size));
            Attr := '';
            if F.ReadOnly then Attr := Attr + 'read-only ';
            if F.System then Attr := Attr + 'system ';
            if F.User <> 0 then Attr := Attr + Format('user %d', [F.User]);
            Item.SubItems.Add(Trim(Attr));
            if I = Selected then Item.Selected := True;
          end;
        finally
          FList.Items.EndUpdate;
        end;
        FStatus.SimpleText := Format('%d files, %dK free', [FS.Count, FS.FreeBytes div 1024]);
        if Disk.Modified then Suffix := ' (modified)' else Suffix := '';
        if Disk.FileName <> '' then
          FTitle.SetTitle(Format('Disk browser - %s: ', [Chr(Ord('A') + FDrive)]),
            ExpandFileName(Disk.FileName), Suffix)
        else
          FTitle.SetTitle(Format('Disk browser - %s: (new disk)', [Chr(Ord('A') + FDrive)]) + Suffix, '', '');
        FLastModified := Disk.Modified;
        Result := True;
      finally
        FS.Free;
      end;
    except
      on E: Exception do Error := E.Message;
    end;
  finally
    FEmu.Unlock;
  end;
  FLastError := Error;
  if (Error <> '') and (AAction <> ACT_LIST) then
  begin
    if not FQuiet then MessageDlg(Error, mtError, [mbOK], 0);
  end
  else if Error <> '' then
    FStatus.SimpleText := 'Can''t read the disk: ' + Error;
end;

procedure TDiskBrowserWindow.Refresh;
begin
  WithDisk(ACT_LIST);
end;

procedure TDiskBrowserWindow.Tick(Sender: TObject);
var
  Disk: TDiskImage;
  DiskChanged: Boolean;
begin
  if not Visible then Exit;
  UpdateDrives;
  // Follow disk changes, and writes made by the emulated +3
  FEmu.Lock;
  try
    Disk := FEmu.Spec.FDC.Disk(FDrive);
    DiskChanged := (Disk <> FLastDisk) or ((Disk <> nil) and (Disk.Modified <> FLastModified));
  finally
    FEmu.Unlock;
  end;
  if DiskChanged then Refresh;
end;

procedure TDiskBrowserWindow.DoRefresh(Sender: TObject);
begin
  Refresh;
end;

procedure TDiskBrowserWindow.DoRename(Sender: TObject);
var
  Index: Integer;
  NewName: string;
begin
  Index := SelectedIndex;
  if Index < 0 then Exit;
  NewName := FList.Selected.Caption;
  if not InputQuery('Rename', 'New name (up to 8 characters, optional extension of 3):',
    NewName) then Exit;
  WithDisk(ACT_RENAME, Index, NewName);
end;

procedure TDiskBrowserWindow.DoDelete(Sender: TObject);
var
  Indexes: array of Integer;
  I: Integer;
  Question: string;
begin
  // The selected files, from the last one (deleting doesn't move the others)
  Indexes := nil;
  for I := FList.Items.Count - 1 downto 0 do
    if FList.Items[I].Selected then
    begin
      SetLength(Indexes, Length(Indexes) + 1);
      Indexes[High(Indexes)] := PtrInt(FList.Items[I].Data);
    end;
  if Length(Indexes) = 0 then Exit;
  if Length(Indexes) = 1 then Question := Format('Delete %s from the disk?', [FList.Selected.Caption])
  else Question := Format('Delete the %d selected files from the disk?', [Length(Indexes)]);
  if MessageDlg(Question, mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  for I := 0 to High(Indexes) do
    if not WithDisk(ACT_DELETE, Indexes[I]) then Break;
end;

procedure TDiskBrowserWindow.ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Shift <> [] then Exit;
  case Key of
    VK_DELETE: DoDelete(nil);
    VK_F2: DoRename(nil);
  else
    Exit;
  end;
  Key := 0;
end;

procedure TDiskBrowserWindow.DoExport(Sender: TObject);
var
  Names: array of string;
  Datas: TBytesArray;
  Items: array of TListItem;
  I, N: Integer;
  Status: string;
begin
  Items := nil;
  for I := 0 to FList.Items.Count - 1 do
    if FList.Items[I].Selected then
    begin
      SetLength(Items, Length(Items) + 1);
      Items[High(Items)] := FList.Items[I];
    end;
  N := Length(Items);
  if N = 0 then Exit;
  SetLength(Names, N);
  SetLength(Datas, N);
  for I := 0 to N - 1 do
  begin
    Names[I] := Items[I].Caption;
    if not WithDisk(ACT_READ, PtrInt(Items[I].Data)) then Exit;
    Datas[I] := ReadData;
  end;
  Status := ExportToPC(Names, Datas, Settings.DiskBrowserDir);
  if Status <> '' then FStatus.SimpleText := Status;
end;

{ Name and header for a file from the PC: a +3DOS name, and either a header
  for bytes (CODE) at an address or none at all }
function AskImport(const FileName: string; Size: Integer; var AName: string; out Header: Boolean;
  out Addr: Word; DefaultHeader: Boolean; Remaining: Integer; out ForAll: Boolean;
  LongNames: Boolean): Boolean;
var
  Dlg: TForm;
  NameEdit, AddrEdit: TEdit;
  HeaderCheck, AllCheck: TCheckBox;
  Lbl: TLabel;
  Btn: TButton;
  V: Integer;
  Raw: array[0..10] of Byte;
  Error: string;
begin
  Result := False;
  Header := False;
  ForAll := False;
  Addr := 32768;
  Dlg := TForm.CreateNew(nil, 0);
  try
    Dlg.Caption := 'Import ' + ExtractFileName(FileName);
    Dlg.BorderStyle := bsDialog;
    Dlg.Position := poMainFormCenter;
    Dlg.ClientWidth := 380;
    Dlg.ClientHeight := 170;
    Lbl := TLabel.Create(Dlg);
    Lbl.Parent := Dlg;
    Lbl.Caption := Format('Name on the disk (%d bytes):', [Size]);
    Lbl.SetBounds(10, 14, 200, 18);
    NameEdit := TEdit.Create(Dlg);
    NameEdit.Parent := Dlg;
    NameEdit.SetBounds(210, 10, 160, 24);
    NameEdit.Text := AName;
    HeaderCheck := TCheckBox.Create(Dlg);
    HeaderCheck.Parent := Dlg;
    HeaderCheck.Caption := 'Bytes (CODE) with a +3DOS header, at address:';
    HeaderCheck.SetBounds(10, 50, 300, 24);
    HeaderCheck.Checked := DefaultHeader;
    AddrEdit := TEdit.Create(Dlg);
    AddrEdit.Parent := Dlg;
    AddrEdit.SetBounds(10, 80, 100, 24);
    // A screen loads at 16384; anything else by default at 32768
    if (Size = 6912) or SameText(ExtractFileExt(FileName), '.scr') then AddrEdit.Text := '16384'
    else AddrEdit.Text := '32768';
    Lbl := TLabel.Create(Dlg);
    Lbl.Parent := Dlg;
    Lbl.Caption := '(decimal; $ for hex). Unticked: no header.';
    Lbl.SetBounds(120, 84, 250, 18);
    AllCheck := TCheckBox.Create(Dlg);
    AllCheck.Parent := Dlg;
    AllCheck.Caption := Format('The same for the other %d files (their own names)', [Remaining]);
    AllCheck.SetBounds(10, 108, 360, 24);
    AllCheck.Visible := Remaining > 0;
    if Remaining > 0 then Dlg.ClientHeight := Dlg.ClientHeight + 24;
    Btn := TButton.Create(Dlg);
    Btn.Parent := Dlg;
    Btn.Caption := 'Import';
    Btn.Default := True;
    Btn.ModalResult := mrOK;
    Btn.SetBounds(210, Dlg.ClientHeight - 40, 75, 28);
    Btn := TButton.Create(Dlg);
    Btn.Parent := Dlg;
    Btn.Caption := 'Cancel';
    Btn.Cancel := True;
    Btn.ModalResult := mrCancel;
    Btn.SetBounds(295, Dlg.ClientHeight - 40, 75, 28);
    repeat
      if Dlg.ShowModal <> mrOK then Exit;
      // A long name: anything a FAT name can be
      if LongNames then
      begin
        if (Trim(NameEdit.Text) = '') or (LastDelimiter('/\:*?"<>|', NameEdit.Text) > 0) then
        begin
          MessageDlg('Invalid name.', mtError, [mbOK], 0);
          Continue;
        end;
      end
      else if not MakeRawName(NameEdit.Text, Raw, Error) then
      begin
        MessageDlg('Invalid name: ' + Error + '.', mtError, [mbOK], 0);
        Continue;
      end;
      V := StrToIntDef(Trim(AddrEdit.Text), -1);
      if HeaderCheck.Checked and ((V < 0) or (V > 65535)) then
      begin
        MessageDlg('The address must be 0 to 65535.', mtError, [mbOK], 0);
        Continue;
      end;
      if HeaderCheck.Checked and (Size > 65535) then
      begin
        MessageDlg('A file with a header can''t be longer than 65535 bytes.', mtError, [mbOK], 0);
        Continue;
      end;
      Break;
    until False;
    AName := NameEdit.Text;
    Header := HeaderCheck.Checked;
    ForAll := AllCheck.Checked;
    if Header then Addr := V;
    Result := True;
  finally
    Dlg.Free;
  end;
end;

{ A +3DOS name from a PC file name: up to 8 + 3 usable characters }
function SuggestName(const FileName: string): string;
var
  Base, Ext, S: string;
  Ch: Char;
begin
  Base := '';
  for Ch in UpperCase(ChangeFileExt(ExtractFileName(FileName), '')) do
    if Ch in ['A'..'Z', '0'..'9', '_', '-'] then Base := Base + Ch;
  Ext := '';
  for Ch in UpperCase(ExtractFileExt(FileName)) do
    if Ch in ['A'..'Z', '0'..'9'] then Ext := Ext + Ch;
  if Base = '' then Base := 'FILE';
  S := Copy(Base, 1, 8);
  if Ext <> '' then S := S + '.' + Copy(Ext, 1, 3);
  Result := S;
end;

procedure TDiskBrowserWindow.DoImport(Sender: TObject);
var
  Status: string;
begin
  // +3DOS files usually have a header: ticked by default
  Status := ImportFromPC(Settings.DiskBrowserDir, True, @ImportExists, @ImportWrite);
  if Status <> '' then FStatus.SimpleText := FStatus.SimpleText + '   -  ' + Status;
end;

procedure TDiskBrowserWindow.DoImportFolder(Sender: TObject);
var
  Status: string;
begin
  // A +3 disk has no folders: the files in them all go side by side
  Status := ImportFromPC(Settings.DiskBrowserDir, True, @ImportExists, @ImportWrite, nil, nil, True);
  if Status <> '' then FStatus.SimpleText := FStatus.SimpleText + '   -  ' + Status;
end;

procedure TDiskBrowserWindow.FormDropFiles(Sender: TObject; const FileNames: array of string);
var
  Paths: TStringList;
  I: Integer;
  Status: string;
begin
  Paths := TStringList.Create;
  try
    for I := 0 to High(FileNames) do Paths.Add(FileNames[I]);
    Status := ImportFromPC(Settings.DiskBrowserDir, True, @ImportExists, @ImportWrite, nil, Paths);
  finally
    Paths.Free;
  end;
  if Status <> '' then FStatus.SimpleText := FStatus.SimpleText + '   -  ' + Status;
end;

function TDiskBrowserWindow.ImportExists(const AName: string): Boolean;
begin
  FoundIndex := -1;
  Result := WithDisk(ACT_FIND, -1, AName) and (FoundIndex >= 0);
end;

function TDiskBrowserWindow.ImportWrite(const AName: string; const Data: TBytes;
  Replace: Boolean): string;
var
  Act: Integer;
begin
  if Replace then Act := ACT_REPLACE else Act := ACT_WRITE;
  FQuiet := True;
  try
    if WithDisk(Act, -1, AName, Data) then Result := ''
    else if FLastError <> '' then Result := FLastError
    else Result := 'there is no disk';
  finally
    FQuiet := False;
  end;
end;

procedure TDiskBrowserWindow.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  CloseAction := caHide;
end;

end.

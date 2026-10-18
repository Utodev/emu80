{ DiskBrowser: the files on the disk in drive A: or B: (+3DOS), with their
  type, start address or autostart line and length. Files can be renamed,
  deleted, exported to the PC and imported from it. }
unit DiskBrowser;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, ComCtrls, StdCtrls, ExtCtrls, Dialogs, Emulator, DSK,
  Plus3FS, Icons, Spectrum;

type
  TDiskBrowserWindow = class(TForm)
  private
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

{ Shared with the SD card browser: the name and header of a file imported
  from the PC, and a name suggested from its PC file name }
function AskImport(const FileName: string; Size: Integer; var AName: string; out Header: Boolean;
  out Addr: Word): Boolean;
function SuggestName(const FileName: string): string;

implementation

uses
  Config;

const
  ACT_LIST = 0;
  ACT_READ = 1;
  ACT_WRITE = 2;
  ACT_RENAME = 3;
  ACT_DELETE = 4;

var
  // Result of the last ACT_READ
  ReadData: TBytes;

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
  Width := 640;
  Height := 400;
  Position := poMainFormCenter;
  OnClose := @FormClose;

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
  AddButton(ikOpen, 'Import a file from the PC onto the disk...', @DoImport);
  AddButton(ikSave, 'Export the selected file to the PC...', @DoExport);
  AddButton(ikRename, 'Rename the selected file...', @DoRename);
  AddButton(ikDelete, 'Delete the selected file', @DoDelete);

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
  FList.OnDblClick := @DoExport;
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
        if Disk.FileName <> '' then
          Caption := Format('Disk browser - %s: %s', [Chr(Ord('A') + FDrive), ExtractFileName(Disk.FileName)])
        else
          Caption := Format('Disk browser - %s: (new disk)', [Chr(Ord('A') + FDrive)]);
        if Disk.Modified then Caption := Caption + ' (modified)';
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
  if (Error <> '') and (AAction <> ACT_LIST) then
    MessageDlg(Error, mtError, [mbOK], 0)
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
  Index: Integer;
begin
  Index := SelectedIndex;
  if Index < 0 then Exit;
  if MessageDlg(Format('Delete %s from the disk?', [FList.Selected.Caption]), mtConfirmation,
    [mbYes, mbNo], 0) <> mrYes then Exit;
  WithDisk(ACT_DELETE, Index);
end;

procedure TDiskBrowserWindow.DoExport(Sender: TObject);
var
  Index: Integer;
  Dlg: TSaveDialog;
  Data: TBytes;
  S: TFileStream;
  Answer: Integer;
begin
  Index := SelectedIndex;
  if Index < 0 then Exit;
  if not WithDisk(ACT_READ, Index) then Exit;
  Data := ReadData;
  // Usually what is wanted is the data (a .bin, a screen...), without the
  // 128-byte +3DOS header in front
  if HasPlus3Header(Data) then
  begin
    Answer := MessageDlg('Export', 'The file has a +3DOS header. Keep it in the exported file?' +
      LineEnding + LineEnding + 'No: just the data (' + IntToStr(Length(Data) - PLUS3_HEADER_SIZE) +
      ' bytes).', mtConfirmation, [mbYes, mbNo, mbCancel], 0);
    if Answer = mrCancel then Exit;
    if Answer = mrNo then Data := Copy(Data, PLUS3_HEADER_SIZE, MaxInt);
  end;
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.FileName := FList.Selected.Caption;
    Dlg.InitialDir := Settings.LastDir;
    Dlg.Filter := 'All files|*.*';
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    if not Dlg.Execute then Exit;
    try
      S := TFileStream.Create(Dlg.FileName, fmCreate);
      try
        if Length(Data) > 0 then S.WriteBuffer(Data[0], Length(Data));
      finally
        S.Free;
      end;
      FStatus.SimpleText := Format('Exported %s (%d bytes)', [ExtractFileName(Dlg.FileName), Length(Data)]);
    except
      on E: Exception do MessageDlg('Could not save: ' + E.Message, mtError, [mbOK], 0);
    end;
  finally
    Dlg.Free;
  end;
end;

{ Name and header for a file from the PC: a +3DOS name, and either a header
  for bytes (CODE) at an address or none at all }
function AskImport(const FileName: string; Size: Integer; var AName: string; out Header: Boolean;
  out Addr: Word): Boolean;
var
  Dlg: TForm;
  NameEdit, AddrEdit: TEdit;
  HeaderCheck: TCheckBox;
  Lbl: TLabel;
  Btn: TButton;
  V: Integer;
  Raw: array[0..10] of Byte;
  Error: string;
begin
  Result := False;
  Header := False;
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
    HeaderCheck.Checked := True;
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
    Btn := TButton.Create(Dlg);
    Btn.Parent := Dlg;
    Btn.Caption := 'Import';
    Btn.Default := True;
    Btn.ModalResult := mrOK;
    Btn.SetBounds(210, 130, 75, 28);
    Btn := TButton.Create(Dlg);
    Btn.Parent := Dlg;
    Btn.Caption := 'Cancel';
    Btn.Cancel := True;
    Btn.ModalResult := mrCancel;
    Btn.SetBounds(295, 130, 75, 28);
    repeat
      if Dlg.ShowModal <> mrOK then Exit;
      if not MakeRawName(NameEdit.Text, Raw, Error) then
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
  Dlg: TOpenDialog;
  Data: TBytes;
  S: TFileStream;
  AName: string;
  Header: Boolean;
  Addr: Word;
begin
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.InitialDir := Settings.LastDir;
    Dlg.Filter := 'All files|*.*';
    Dlg.Options := Dlg.Options + [ofFileMustExist];
    if not Dlg.Execute then Exit;
    try
      S := TFileStream.Create(Dlg.FileName, fmOpenRead or fmShareDenyWrite);
      try
        SetLength(Data, S.Size);
        if S.Size > 0 then S.ReadBuffer(Data[0], S.Size);
      finally
        S.Free;
      end;
    except
      on E: Exception do
      begin
        MessageDlg('Could not read the file: ' + E.Message, mtError, [mbOK], 0);
        Exit;
      end;
    end;
    AName := SuggestName(Dlg.FileName);
    if HasPlus3Header(Data) then
    begin
      // Already a +3DOS file: copy it as it is
      if not InputQuery('Import', 'The file has a +3DOS header and is copied as it is.' +
        LineEnding + 'Name on the disk:', AName) then Exit;
    end
    else
    begin
      if not AskImport(Dlg.FileName, Length(Data), AName, Header, Addr) then Exit;
      if Header then Data := AddPlus3Header(Data, FT_BYTES, Addr, 32768);
    end;
    if WithDisk(ACT_WRITE, -1, AName, Data) then
      FStatus.SimpleText := FStatus.SimpleText + Format('   -  imported %s', [UpperCase(AName)]);
  finally
    Dlg.Free;
  end;
end;

procedure TDiskBrowserWindow.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  CloseAction := caHide;
end;

end.

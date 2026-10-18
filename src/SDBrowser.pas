{ SDBrowser: the files on the DivMMC's SD card (FAT): folders to walk
  through, and for each file its size, date, attributes and, when it has a
  +3DOS header (as ESXDOS saves BASIC files), its type, start address or
  autostart line and length. Files can be renamed, deleted, exported to the
  PC and imported from it, and folders created. }
unit SDBrowser;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, ComCtrls, StdCtrls, ExtCtrls, Dialogs, Graphics, Emulator, FatFS,
  Plus3FS, Icons;

type
  TSDBrowserWindow = class(TForm)
  private
    FEmu: TEmulator;
    FToolBar: TToolBar;
    FImages: TImageList;
    FPathLabel: TLabel;
    FList: TListView;
    FStatus: TStatusBar;
    FPath: array of record
      Cluster: LongWord;
      Name: string;
    end;
    FEntries: TFatEntries;    // what the list shows (without "..")
    FCardFile: string;
    function AddButton(AIcon: TIconKind; const AHint: string; AHandler: TNotifyEvent): TToolButton;
    procedure AddSeparator;
    function DirCluster: LongWord;
    { The selected entry (index in FEntries), -1 for none or ".." }
    function SelectedIndex: Integer;
    function OpenVolume(out Volume: TFatVolume): Boolean;
    procedure ShowError(const Msg: string);
    procedure ListDblClick(Sender: TObject);
    procedure DoUp(Sender: TObject);
    procedure DoRefresh(Sender: TObject);
    procedure DoNewFolder(Sender: TObject);
    procedure DoImport(Sender: TObject);
    procedure DoExport(Sender: TObject);
    procedure DoRename(Sender: TObject);
    procedure DoDelete(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
  public
    constructor CreateFor(AOwner: TComponent; AEmu: TEmulator);
    procedure Refresh;
  end;

var
  SDBrowserWindow: TSDBrowserWindow;

procedure ShowSDBrowser(Emu: TEmulator);

implementation

uses
  Config, DiskBrowser;

procedure ShowSDBrowser(Emu: TEmulator);
begin
  if SDBrowserWindow = nil then
    SDBrowserWindow := TSDBrowserWindow.CreateFor(Application, Emu);
  SDBrowserWindow.Refresh;
  SDBrowserWindow.Show;
  SDBrowserWindow.BringToFront;
end;

constructor TSDBrowserWindow.CreateFor(AOwner: TComponent; AEmu: TEmulator);

  procedure AddColumn(const ACaption: string; AWidth: Integer; Right: Boolean = False);
  var
    Col: TListColumn;
  begin
    Col := FList.Columns.Add;
    Col.Caption := ACaption;
    Col.Width := AWidth;
    if Right then Col.Alignment := taRightJustify;
  end;

var
  PathPanel: TPanel;
begin
  inherited CreateNew(AOwner, 0);
  FEmu := AEmu;
  Caption := 'SD card browser';
  Width := 820;
  Height := 460;
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
  AddButton(ikFolderUp, 'Up to the parent folder', @DoUp);
  AddButton(ikRefresh, 'Read the card again', @DoRefresh);
  AddSeparator;
  AddButton(ikNewFolder, 'New folder...', @DoNewFolder);
  AddButton(ikOpen, 'Import a file from the PC into this folder...', @DoImport);
  AddButton(ikSave, 'Export the selected file to the PC...', @DoExport);
  AddButton(ikRename, 'Rename the selected file or folder...', @DoRename);
  AddButton(ikDelete, 'Delete the selected file (or empty folder)', @DoDelete);

  PathPanel := TPanel.Create(Self);
  PathPanel.Parent := Self;
  PathPanel.Align := alTop;
  PathPanel.Top := 1000;
  PathPanel.Height := 26;
  PathPanel.BevelOuter := bvNone;
  FPathLabel := TLabel.Create(Self);
  FPathLabel.Parent := PathPanel;
  FPathLabel.Left := 8;
  FPathLabel.Top := 5;
  FPathLabel.Font.Style := [fsBold];

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
  FList.OnDblClick := @ListDblClick;
  AddColumn('Name', 190);
  AddColumn('Size', 80, True);
  AddColumn('Type', 110);
  AddColumn('Start / line', 85, True);
  AddColumn('Length', 65, True);
  AddColumn('Date', 120);
  AddColumn('Attributes', 75);
  AddColumn('8.3 name', 90);

  SetLength(FPath, 1);
  FPath[0].Cluster := 0;
  FPath[0].Name := '';
end;

function TSDBrowserWindow.AddButton(AIcon: TIconKind; const AHint: string;
  AHandler: TNotifyEvent): TToolButton;
begin
  Result := TToolButton.Create(FToolBar);
  Result.Parent := FToolBar;
  Result.ImageIndex := Ord(AIcon);
  Result.Hint := AHint;
  Result.OnClick := AHandler;
  Result.Left := FToolBar.Width + 1000;   // append at the right
end;

procedure TSDBrowserWindow.AddSeparator;
var
  Sep: TToolButton;
begin
  Sep := TToolButton.Create(FToolBar);
  Sep.Parent := FToolBar;
  Sep.Style := tbsDivider;
  Sep.Left := FToolBar.Width + 1000;
end;

function TSDBrowserWindow.DirCluster: LongWord;
begin
  Result := FPath[High(FPath)].Cluster;
end;

function TSDBrowserWindow.SelectedIndex: Integer;
begin
  if FList.Selected = nil then Result := -1
  else Result := PtrInt(FList.Selected.Data);
end;

procedure TSDBrowserWindow.ShowError(const Msg: string);
begin
  MessageDlg(Msg, mtError, [mbOK], 0);
end;

{ The card's file system; call with the emulator locked }
function TSDBrowserWindow.OpenVolume(out Volume: TFatVolume): Boolean;
var
  Card: TObject;
begin
  Volume := nil;
  Card := FEmu.Spec.DivMMC.Card;
  if Card = nil then
  begin
    FStatus.SimpleText := 'There is no SD card in the DivMMC.';
    Exit(False);
  end;
  if FEmu.Spec.DivMMC.Card.FileName <> FCardFile then
  begin
    // Another card: start at its root
    FCardFile := FEmu.Spec.DivMMC.Card.FileName;
    SetLength(FPath, 1);
  end;
  try
    Volume := TFatVolume.Create(FEmu.Spec.DivMMC.Card.Stream);
    Result := True;
  except
    on E: Exception do
    begin
      FStatus.SimpleText := 'Can''t read the card: ' + E.Message;
      Result := False;
    end;
  end;
end;

procedure TSDBrowserWindow.Refresh;
var
  Vol: TFatVolume;
  I, P: Integer;
  Item: TListItem;
  E: TFatEntry;
  Head: TBytes;
  Path, Attr, Start, TypeText, LenText: string;
  Info: TPlus3File;
  Selected: string;
begin
  Selected := '';
  if FList.Selected <> nil then Selected := FList.Selected.Caption;
  FEmu.Lock;
  try
    FList.Items.BeginUpdate;
    try
      FList.Items.Clear;
      FEntries := nil;
      if not OpenVolume(Vol) then
      begin
        FPathLabel.Caption := '';
        Exit;
      end;
      try
        try
          FEntries := Vol.ListDir(DirCluster);
        except
          on Ex: Exception do
          begin
            FStatus.SimpleText := 'Can''t read the folder: ' + Ex.Message;
            Exit;
          end;
        end;
        if Length(FPath) > 1 then
        begin
          Item := FList.Items.Add;
          Item.Caption := '..';
          Item.Data := Pointer(PtrInt(-1));
          Item.SubItems.Add('');
          Item.SubItems.Add('Parent folder');
        end;
        for I := 0 to High(FEntries) do
        begin
          E := FEntries[I];
          Item := FList.Items.Add;
          Item.Caption := DisplayName(E);
          Item.Data := Pointer(PtrInt(I));
          TypeText := '';
          Start := '';
          LenText := '';
          if IsDirectory(E) then
          begin
            Item.SubItems.Add('');
            TypeText := 'Folder';
          end
          else
          begin
            Item.SubItems.Add(IntToStr(E.Size));
            // ESXDOS keeps BASIC files with a +3DOS header
            try
              Head := Vol.ReadStart(E, PLUS3_HEADER_SIZE);
            except
              Head := nil;
            end;
            if HasPlus3Header(Head) then
            begin
              Info := Default(TPlus3File);
              Info.HasHeader := True;
              Info.FileType := Head[15];
              Info.DataLength := Head[16] or (Head[17] shl 8);
              Info.Param1 := Head[18] or (Head[19] shl 8);
              TypeText := FileTypeName(Info);
              if Info.FileType = FT_BYTES then Start := IntToStr(Info.Param1)
              else if (Info.FileType = FT_PROGRAM) and (Info.Param1 < 32768) then
                Start := 'LINE ' + IntToStr(Info.Param1);
              LenText := IntToStr(Info.DataLength);
            end;
          end;
          Item.SubItems.Add(TypeText);
          Item.SubItems.Add(Start);
          Item.SubItems.Add(LenText);
          if E.Stamp <> 0 then Item.SubItems.Add(FormatDateTime('yyyy-mm-dd hh:nn', E.Stamp))
          else Item.SubItems.Add('');
          Attr := '';
          if (E.Attr and $01) <> 0 then Attr := Attr + 'R';
          if (E.Attr and $02) <> 0 then Attr := Attr + 'H';
          if (E.Attr and $04) <> 0 then Attr := Attr + 'S';
          if (E.Attr and $20) <> 0 then Attr := Attr + 'A';
          Item.SubItems.Add(Attr);
          if E.LongName <> '' then Item.SubItems.Add(E.ShortName) else Item.SubItems.Add('');
          if Item.Caption = Selected then Item.Selected := True;
        end;
        Path := '';
        for P := 1 to High(FPath) do Path := Path + '/' + FPath[P].Name;
        FPathLabel.Caption := ExtractFileName(FCardFile) + ':  ' + Path + '/';
        FStatus.SimpleText := Format('FAT%d   %d items   %s free of %s', [Vol.FatType,
          Length(FEntries), FormatFloat('#,##0', Vol.FreeBytes div 1024) + 'K',
          FormatFloat('#,##0', Vol.TotalBytes div 1024) + 'K']);
        Caption := 'SD card browser - ' + ExtractFileName(FCardFile);
      finally
        Vol.Free;
      end;
    finally
      FList.Items.EndUpdate;
    end;
  finally
    FEmu.Unlock;
  end;
end;

procedure TSDBrowserWindow.ListDblClick(Sender: TObject);
var
  I, N: Integer;
begin
  if FList.Selected = nil then Exit;
  I := SelectedIndex;
  if I < 0 then
  begin
    DoUp(Sender);
    Exit;
  end;
  if IsDirectory(FEntries[I]) then
  begin
    N := Length(FPath);
    SetLength(FPath, N + 1);
    FPath[N].Cluster := FEntries[I].Cluster;
    FPath[N].Name := FEntries[I].ShortName;
    Refresh;
  end
  else
    DoExport(Sender);
end;

procedure TSDBrowserWindow.DoUp(Sender: TObject);
begin
  if Length(FPath) <= 1 then Exit;
  SetLength(FPath, Length(FPath) - 1);
  Refresh;
end;

procedure TSDBrowserWindow.DoRefresh(Sender: TObject);
begin
  Refresh;
end;

procedure TSDBrowserWindow.DoNewFolder(Sender: TObject);
var
  AName, Error: string;
  Vol: TFatVolume;
begin
  AName := '';
  if not InputQuery('New folder', 'Name (up to 8 characters, optional extension of 3):', AName) then Exit;
  Error := '';
  FEmu.Lock;
  try
    if OpenVolume(Vol) then
      try
        try
          Vol.MakeDir(DirCluster, AName);
        except
          on E: Exception do Error := E.Message;
        end;
      finally
        Vol.Free;
      end;
  finally
    FEmu.Unlock;
  end;
  if Error <> '' then ShowError('Could not create the folder: ' + Error);
  Refresh;
end;

procedure TSDBrowserWindow.DoImport(Sender: TObject);
var
  Dlg: TOpenDialog;
  Data: TBytes;
  S: TFileStream;
  AName, Error: string;
  Header: Boolean;
  Addr: Word;
  Vol: TFatVolume;
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
        ShowError('Could not read the file: ' + E.Message);
        Exit;
      end;
    end;
    AName := SuggestName(Dlg.FileName);
    if HasPlus3Header(Data) or (Length(Data) > 65535) then
    begin
      // Copied as it is
      if not InputQuery('Import', 'Name on the card (8.3):', AName) then Exit;
    end
    else
    begin
      if not AskImport(Dlg.FileName, Length(Data), AName, Header, Addr) then Exit;
      if Header then Data := AddPlus3Header(Data, FT_BYTES, Addr, 32768);
    end;
    Error := '';
    FEmu.Lock;
    try
      if OpenVolume(Vol) then
        try
          try
            Vol.WriteFile(DirCluster, AName, Data);
          except
            on E: Exception do Error := E.Message;
          end;
        finally
          Vol.Free;
        end;
    finally
      FEmu.Unlock;
    end;
    if Error <> '' then ShowError('Could not import: ' + Error);
    Refresh;
  finally
    Dlg.Free;
  end;
end;

procedure TSDBrowserWindow.DoExport(Sender: TObject);
var
  I, Answer: Integer;
  Data: TBytes;
  Vol: TFatVolume;
  Dlg: TSaveDialog;
  S: TFileStream;
  Error: string;
begin
  I := SelectedIndex;
  if (I < 0) or IsDirectory(FEntries[I]) then Exit;
  Error := '';
  Data := nil;
  FEmu.Lock;
  try
    if OpenVolume(Vol) then
      try
        try
          Data := Vol.ReadFile(FEntries[I]);
        except
          on E: Exception do Error := E.Message;
        end;
      finally
        Vol.Free;
      end;
  finally
    FEmu.Unlock;
  end;
  if Error <> '' then
  begin
    ShowError('Could not read the file: ' + Error);
    Exit;
  end;
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
    Dlg.FileName := DisplayName(FEntries[I]);
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
      on E: Exception do ShowError('Could not save: ' + E.Message);
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TSDBrowserWindow.DoRename(Sender: TObject);
var
  I: Integer;
  NewName, Error: string;
  Vol: TFatVolume;
begin
  I := SelectedIndex;
  if I < 0 then Exit;
  NewName := FEntries[I].ShortName;
  if not InputQuery('Rename', 'New name (8.3; a long name is dropped):', NewName) then Exit;
  Error := '';
  FEmu.Lock;
  try
    if OpenVolume(Vol) then
      try
        try
          Vol.Rename(DirCluster, FEntries[I], NewName);
        except
          on E: Exception do Error := E.Message;
        end;
      finally
        Vol.Free;
      end;
  finally
    FEmu.Unlock;
  end;
  if Error <> '' then ShowError('Could not rename: ' + Error);
  Refresh;
end;

procedure TSDBrowserWindow.DoDelete(Sender: TObject);
var
  I: Integer;
  Error: string;
  Vol: TFatVolume;
begin
  I := SelectedIndex;
  if I < 0 then Exit;
  if MessageDlg(Format('Delete %s from the card?', [DisplayName(FEntries[I])]), mtConfirmation,
    [mbYes, mbNo], 0) <> mrYes then Exit;
  Error := '';
  FEmu.Lock;
  try
    if OpenVolume(Vol) then
      try
        try
          Vol.Delete(FEntries[I]);
        except
          on E: Exception do Error := E.Message;
        end;
      finally
        Vol.Free;
      end;
  finally
    FEmu.Unlock;
  end;
  if Error <> '' then ShowError('Could not delete: ' + Error);
  Refresh;
end;

procedure TSDBrowserWindow.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  CloseAction := caHide;
end;

end.

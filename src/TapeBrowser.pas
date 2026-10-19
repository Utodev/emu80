{ TapeBrowser: lists the blocks of the loaded tape and lets the user pick
  where to play from, move or delete blocks and save the edited tape. }
unit TapeBrowser;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, ComCtrls, StdCtrls, ExtCtrls, Dialogs, LCLType,
  Emulator, Tape, Icons;

type
  TTapeBrowserWindow = class(TForm)
  private
    FEmu: TEmulator;
    FList: TListView;
    FToolBar: TToolBar;
    FImages: TImageList;
    FFastRadio, FRealRadio: TRadioButton;
    FRecButton: TToolButton;
    FSyncing: Boolean;
    FTimer: TTimer;
    FLastChange: Integer;
    FLastCount: Integer;
    FStatus: TStatusBar;
    FCurrent: Integer;          // block the tape is at (Count: at the end)
    FPlaying: Boolean;
    procedure ListCustomDrawItem(Sender: TCustomListView; Item: TListItem;
      State: TCustomDrawState; var DefaultDraw: Boolean);
    function AddButton(AIcon: TIconKind; const AHint: string; AHandler: TNotifyEvent): TToolButton;
    procedure AddSeparator;
    procedure Tick(Sender: TObject);
    procedure DoLoadMode(Sender: TObject);
    procedure SyncLoadMode;
    procedure ListDblClick(Sender: TObject);
    procedure DoPlay(Sender: TObject);
    procedure DoStop(Sender: TObject);
    procedure DoRecord(Sender: TObject);
    procedure DoRewind(Sender: TObject);
    procedure DoSetPosition(Sender: TObject);
    procedure DoMoveUp(Sender: TObject);
    procedure DoMoveDown(Sender: TObject);
    procedure DoDelete(Sender: TObject);
    procedure ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure DoSave(Sender: TObject);
    procedure MoveSelected(Delta: Integer);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
  public
    constructor CreateFor(AOwner: TComponent; AEmu: TEmulator);
    procedure Refresh(Force: Boolean);
  end;

var
  TapeBrowserWindow: TTapeBrowserWindow;
  { Called when the browser changes a setting (fast loading), so the main
    window can update its menu }
  OnTapeSettingsChanged: TNotifyEvent;

procedure ShowTapeBrowser(Emu: TEmulator);

implementation

uses
  Config;

procedure ShowTapeBrowser(Emu: TEmulator);
begin
  if TapeBrowserWindow = nil then
    TapeBrowserWindow := TTapeBrowserWindow.CreateFor(Application, Emu);
  TapeBrowserWindow.Refresh(True);
  TapeBrowserWindow.Show;
  TapeBrowserWindow.BringToFront;
end;

constructor TTapeBrowserWindow.CreateFor(AOwner: TComponent; AEmu: TEmulator);
var
  Col: TListColumn;
  Bottom: TPanel;
begin
  inherited CreateNew(AOwner, 0);
  FEmu := AEmu;
  Caption := 'Tape browser';
  Width := 520;
  Height := 380;
  Position := poMainFormCenter;
  FormStyle := fsStayOnTop;
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

  AddButton(ikPlay, 'Play', @DoPlay);
  AddButton(ikStop, 'Stop', @DoStop);
  FRecButton := AddButton(ikRecord, 'Record onto the tape (REC): blocks are added at the end',
    @DoRecord);
  FRecButton.Style := tbsCheck;
  AddButton(ikRewind, 'Rewind', @DoRewind);
  AddButton(ikPlayFrom, 'Play from the selected block (or double-click it)', @DoSetPosition);
  AddSeparator;
  AddButton(ikMoveUp, 'Move the selected block up', @DoMoveUp);
  AddButton(ikMoveDown, 'Move the selected block down', @DoMoveDown);
  AddButton(ikDelete, 'Delete the selected block (Del)', @DoDelete);
  AddSeparator;
  AddButton(ikSave, 'Save the tape as...', @DoSave);

  // Loading mode, the same setting as Tape > Fast loading
  Bottom := TPanel.Create(Self);
  Bottom.Parent := Self;
  Bottom.Align := alBottom;
  Bottom.Height := 32;
  Bottom.BevelOuter := bvNone;
  FFastRadio := TRadioButton.Create(Self);
  FFastRadio.Parent := Bottom;
  FFastRadio.Caption := 'Fast loading';
  FFastRadio.SetBounds(10, 6, 200, 22);
  FFastRadio.OnClick := @DoLoadMode;
  FRealRadio := TRadioButton.Create(Self);
  FRealRadio.Parent := Bottom;
  FRealRadio.Caption := 'Real-time loading';
  FRealRadio.SetBounds(220, 6, 200, 22);
  FRealRadio.OnClick := @DoLoadMode;
  SyncLoadMode;

  // Where the tape is
  FStatus := TStatusBar.Create(Self);
  FStatus.Parent := Self;
  FStatus.SimplePanel := True;
  FCurrent := -1;

  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.OnCustomDrawItem := @ListCustomDrawItem;
  FList.ViewStyle := vsReport;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.HideSelection := False;
  FList.OnDblClick := @ListDblClick;
  FList.OnKeyDown := @ListKeyDown;
  Col := FList.Columns.Add;
  Col.Caption := '';
  Col.Width := 24;
  Col := FList.Columns.Add;
  Col.Caption := '#';
  Col.Width := 36;
  Col := FList.Columns.Add;
  Col.Caption := 'Block';
  Col.Width := 250;
  Col := FList.Columns.Add;
  Col.Caption := 'Length';
  Col.Width := 70;
  Col := FList.Columns.Add;
  Col.Caption := 'Checksum';
  Col.Width := 70;

  FTimer := TTimer.Create(Self);
  FTimer.Interval := 200;
  FTimer.OnTimer := @Tick;
  FLastChange := -1;
end;

function TTapeBrowserWindow.AddButton(AIcon: TIconKind; const AHint: string;
  AHandler: TNotifyEvent): TToolButton;
begin
  Result := TToolButton.Create(FToolBar);
  Result.Parent := FToolBar;
  Result.ImageIndex := Ord(AIcon);
  Result.Hint := AHint;
  Result.OnClick := AHandler;
  Result.Left := FToolBar.Width + 1000;   // append at the right
end;

procedure TTapeBrowserWindow.AddSeparator;
var
  Sep: TToolButton;
begin
  Sep := TToolButton.Create(FToolBar);
  Sep.Parent := FToolBar;
  Sep.Style := tbsDivider;
  Sep.Left := FToolBar.Width + 1000;
end;

procedure TTapeBrowserWindow.ListCustomDrawItem(Sender: TCustomListView; Item: TListItem;
  State: TCustomDrawState; var DefaultDraw: Boolean);
begin
  DefaultDraw := True;
  if Item.Index <> FCurrent then Exit;
  if FPlaying then Sender.Canvas.Brush.Color := RGBToColor(200, 240, 200)
  else Sender.Canvas.Brush.Color := RGBToColor(255, 245, 190);
end;

procedure TTapeBrowserWindow.Refresh(Force: Boolean);
var
  Tp: TTape;
  I, Selected: Integer;
  Item: TListItem;
  Block: TTapeBlock;
begin
  FEmu.Lock;
  try
    Tp := FEmu.Spec.Tape;
    if not Force and (Tp.ChangeCount = FLastChange) then Exit;
    FLastChange := Tp.ChangeCount;
    if Tp.FileName <> '' then
      Caption := 'Tape browser - ' + ExtractFileName(Tp.FileName)
    else
      Caption := 'Tape browser';
    if Tp.Modified then Caption := Caption + ' (modified)';
    Selected := -1;
    if FList.Selected <> nil then Selected := FList.Selected.Index;
    FList.Items.BeginUpdate;
    try
      if Force or (FLastCount <> Tp.Count) then
      begin
        FList.Items.Clear;
        for I := 0 to Tp.Count - 1 do
        begin
          Item := FList.Items.Add;
          Item.SubItems.Add('');
          Item.SubItems.Add('');
          Item.SubItems.Add('');
          Item.SubItems.Add('');
        end;
        FLastCount := Tp.Count;
      end;
      // The tape's position: its block in green while playing, yellow when
      // stopped; the status bar says it in words
      if (Tp.Current <> FCurrent) and (Tp.Current < Tp.Count) and (Tp.Current < FList.Items.Count) then
        FList.Items[Tp.Current].MakeVisible(False);
      FCurrent := Tp.Current;
      FPlaying := Tp.Playing;
      if Tp.Count = 0 then FStatus.SimpleText := 'No blocks'
      else if Tp.Current >= Tp.Count then
        FStatus.SimpleText := 'At the end of the tape (Play starts it again from the first block)'
      else if Tp.Playing then
        FStatus.SimpleText := Format('Playing block %d of %d', [Tp.Current + 1, Tp.Count])
      else
        FStatus.SimpleText := Format('Stopped at block %d of %d', [Tp.Current + 1, Tp.Count]);
      for I := 0 to Tp.Count - 1 do
      begin
        Block := Tp[I];
        Item := FList.Items[I];
        if I = Tp.Current then
        begin
          if Tp.Playing then Item.Caption := '>' else Item.Caption := '*';
        end
        else
          Item.Caption := '';
        Item.SubItems[0] := IntToStr(I + 1);
        Item.SubItems[1] := Block.Description;
        Item.SubItems[2] := IntToStr(Length(Block.Data));
        if Block.ChecksumOK then Item.SubItems[3] := 'OK' else Item.SubItems[3] := 'Bad';
      end;
    finally
      FList.Items.EndUpdate;
    end;
    FList.Invalidate;   // the highlighted block may have changed
    if (Selected >= 0) and (Selected < FList.Items.Count) then
      FList.Selected := FList.Items[Selected];
  finally
    FEmu.Unlock;
  end;
end;

procedure TTapeBrowserWindow.Tick(Sender: TObject);
begin
  if not Visible then Exit;
  Refresh(False);
  SyncLoadMode;
  FRecButton.Down := FEmu.Spec.Recording;
end;

{ Show the current setting (it can also change from the main menu) }
procedure TTapeBrowserWindow.SyncLoadMode;
begin
  FSyncing := True;
  try
    if Settings.FastLoad then FFastRadio.Checked := True else FRealRadio.Checked := True;
  finally
    FSyncing := False;
  end;
end;

procedure TTapeBrowserWindow.DoLoadMode(Sender: TObject);
begin
  if FSyncing or (Settings.FastLoad = FFastRadio.Checked) then Exit;
  Settings.FastLoad := FFastRadio.Checked;
  FEmu.Lock;
  try
    FEmu.Spec.FastLoad := Settings.FastLoad;
  finally
    FEmu.Unlock;
  end;
  if Assigned(OnTapeSettingsChanged) then OnTapeSettingsChanged(Self);
end;

procedure TTapeBrowserWindow.ListDblClick(Sender: TObject);
begin
  DoSetPosition(Sender);
end;

procedure TTapeBrowserWindow.DoPlay(Sender: TObject);
begin
  FEmu.Lock;
  try
    FEmu.Spec.Tape.Play(FEmu.Spec.Cpu.T);
  finally
    FEmu.Unlock;
  end;
  Refresh(False);
end;

procedure TTapeBrowserWindow.DoStop(Sender: TObject);
begin
  FEmu.Lock;
  try
    FEmu.Spec.Tape.Stop;
  finally
    FEmu.Unlock;
  end;
  Refresh(False);
end;

procedure TTapeBrowserWindow.DoRecord(Sender: TObject);
begin
  FEmu.Lock;
  try
    FEmu.Spec.Recording := not FEmu.Spec.Recording;
  finally
    FEmu.Unlock;
  end;
  FRecButton.Down := FEmu.Spec.Recording;
  if Assigned(OnTapeSettingsChanged) then OnTapeSettingsChanged(Self);
end;

procedure TTapeBrowserWindow.DoRewind(Sender: TObject);
begin
  FEmu.Lock;
  try
    FEmu.Spec.Tape.Rewind;
  finally
    FEmu.Unlock;
  end;
  Refresh(False);
end;

procedure TTapeBrowserWindow.DoSetPosition(Sender: TObject);
begin
  if FList.Selected = nil then Exit;
  FEmu.Lock;
  try
    FEmu.Spec.Tape.SelectBlock(FList.Selected.Index);
  finally
    FEmu.Unlock;
  end;
  Refresh(False);
end;

procedure TTapeBrowserWindow.MoveSelected(Delta: Integer);
var
  Index: Integer;
begin
  if FList.Selected = nil then Exit;
  Index := FList.Selected.Index;
  if (Index + Delta < 0) or (Index + Delta >= FList.Items.Count) then Exit;
  FEmu.Lock;
  try
    FEmu.Spec.Tape.MoveBlock(Index, Index + Delta);
  finally
    FEmu.Unlock;
  end;
  Refresh(True);
  FList.Selected := FList.Items[Index + Delta];
  FList.Selected.MakeVisible(False);
end;

procedure TTapeBrowserWindow.DoMoveUp(Sender: TObject);
begin
  MoveSelected(-1);
end;

procedure TTapeBrowserWindow.DoMoveDown(Sender: TObject);
begin
  MoveSelected(1);
end;

procedure TTapeBrowserWindow.ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_DELETE) and (Shift = []) then
  begin
    DoDelete(nil);
    Key := 0;
  end;
end;

procedure TTapeBrowserWindow.DoDelete(Sender: TObject);
var
  Index: Integer;
begin
  if FList.Selected = nil then Exit;
  Index := FList.Selected.Index;
  if MessageDlg(Format('Delete block %d (%s)?', [Index + 1, FList.Selected.SubItems[1]]),
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  FEmu.Lock;
  try
    FEmu.Spec.Tape.DeleteBlock(Index);
  finally
    FEmu.Unlock;
  end;
  Refresh(True);
  if FList.Items.Count > 0 then
  begin
    if Index >= FList.Items.Count then Index := FList.Items.Count - 1;
    FList.Selected := FList.Items[Index];
  end;
end;

procedure TTapeBrowserWindow.DoSave(Sender: TObject);
var
  Dlg: TSaveDialog;
begin
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := 'Tape images (*.tap)|*.tap';
    Dlg.DefaultExt := 'tap';
    Dlg.InitialDir := Settings.LastDir;
    Dlg.FileName := ExtractFileName(FEmu.Spec.Tape.FileName);
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    if not Dlg.Execute then Exit;
    FEmu.Lock;
    try
      FEmu.Spec.Tape.SaveTAP(Dlg.FileName);
    finally
      FEmu.Unlock;
    end;
  finally
    Dlg.Free;
  end;
  Refresh(True);
end;

procedure TTapeBrowserWindow.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  CloseAction := caHide;
end;

end.

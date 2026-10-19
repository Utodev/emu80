{ MainForm: main window. Display, keyboard, menus, quick toolbar and
  status bar. Controls are created in code so no .lfm is needed. }
unit MainForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs, Menus, ComCtrls, StdCtrls,
  ExtCtrls, LCLType, LCLIntf, GraphType, Models, Spectrum, Emulator, Config, Icons, PokeForm,
  Pokes, ScreenCapture, DocForm;

type
  TMainWindow = class(TForm)
  private
    FEmu: TEmulator;
    FBitmap: TBitmap;
    FPixels: array of LongWord;
    FDisplay: TPaintBox;
    FToolBar: TToolBar;
    FImages: TImageList;
    FModelButton: TToolButton;
    FModelMenu: TPopupMenu;
    FModelPopupItems: array[TSpectrumModel] of TMenuItem;
    FPauseButton: TToolButton;
    FRecButton: TToolButton;
    FDiskButton: TToolButton;
    FSDButton: TToolButton;
    FDiskBrowserItem, FSDBrowserItem: TMenuItem;
    FRecItem: TMenuItem;
    FTurboButton: TToolButton;
    FStatus: TStatusBar;
    FStatusTimer: TTimer;
    FLedTimer: TTimer;
    { What the media panel shows: present (bits 0-2: A, B, SD) and busy
      (bits 4-6), redrawn only when it changes }
    FMediaState: Integer;
    FTempCard: string;          // image of a card made from a folder ('' if none)
    FTempFolder: string;        // that folder
    FMenu: TMainMenu;
    FModelItems: array[TSpectrumModel] of TMenuItem;
    FRecentMenu: TMenuItem;
    FRecentSymbolsMenu: TMenuItem;
    FRecentDisksMenu, FRecentDisksMenuB, FRecentCardsMenu: TMenuItem;
    FDriveBItems: array of TMenuItem;   // Floppy menu entries for drive B
    FFastLoadItem, FAutoPlayItem, FMuteItem, FPauseItem, FTurboItem: TMenuItem;
    FMonoItem: TMenuItem;
    FSaveToTapeItem, FFastDiskItem, FDriveBItem, FBorderShotItem: TMenuItem;
    FLastFile: string;          // last file opened, for the POKE history
    FStarted: Boolean;          // command line processed
    FFullerBits: Byte;
    FScaleItems: array[1..4] of TMenuItem;
    FKeyCount: array[0..39] of Integer;
    FPCKeyDown: array[0..255] of Boolean;
    FPCKeyTime: array[0..255] of QWord;     // when each PC key went down
    FPendingUp: array[0..255] of QWord;     // delayed key-up due time, 0 = none
    FKeyTimer: TTimer;
    FKempstonBits: Byte;
    FMouseLast: TPoint;          // last position over the display (Kempston mouse)
    FMouseHave: Boolean;
    FMouseRemX, FMouseRemY: Integer;   // movement not yet worth a Spectrum pixel
    procedure KeyTimerTick(Sender: TObject);
    procedure LedTick(Sender: TObject);
    procedure DrawMediaPanel(StatusBar: TStatusBar; Panel: TStatusPanel; const Rect: TRect);
    procedure ReleasePCKey(Key: Word);
    procedure BuildMenu;
    procedure BuildToolBar;
    function AddItem(AParent: TMenuItem; const ACaption: string; AHandler: TNotifyEvent;
      AShortCut: TShortCut = 0): TMenuItem;
    function AddButton(AIcon: TIconKind; const AHint: string; AHandler: TNotifyEvent): TToolButton;
    procedure AddSeparator;
    procedure UpdateRecentMenu;
    procedure UpdateRecentSymbolsMenu;
    procedure DoLoadRecentSymbols(Sender: TObject);
    procedure UpdateChecks;
    procedure ApplySettings;
    procedure SetScale(Scale: Integer);
    function DisplayScale: Integer;
    procedure RenderBitmap;
    procedure FrameReady(Sender: TObject);
    procedure PaintDisplay(Sender: TObject);
    procedure StatusTick(Sender: TObject);
    procedure UpdateKeyboard;
    procedure MapKey(Key: Word; Down: Boolean);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormDeactivate(Sender: TObject);
    procedure FormDropFiles(Sender: TObject; const FileNames: array of string);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormShow(Sender: TObject);
    procedure ResizeAfterShow(Data: PtrInt);
    procedure StartUp(Data: PtrInt);
    procedure TapeSettingsChanged(Sender: TObject);
    procedure ReleaseAllKeys;
    // Menu and toolbar handlers
    procedure DoOpen(Sender: TObject);
    procedure DoOpenRecent(Sender: TObject);
    procedure DoSaveSnapshot(Sender: TObject);
    procedure DoQuit(Sender: TObject);
    procedure DoModel(Sender: TObject);
    procedure DoModelButton(Sender: TObject);
    procedure DoReset(Sender: TObject);
    procedure DoHardReset(Sender: TObject);
    procedure DoNMI(Sender: TObject);
    procedure DoPause(Sender: TObject);
    procedure DoTurbo(Sender: TObject);
    procedure DoTapeBrowser(Sender: TObject);
    procedure DoTapePlay(Sender: TObject);
    procedure DoTapeStop(Sender: TObject);
    procedure DoTapeRewind(Sender: TObject);
    procedure DoTapeEject(Sender: TObject);
    procedure DoTapeSave(Sender: TObject);
    procedure DoTapeRecord(Sender: TObject);
    procedure DoFastLoad(Sender: TObject);
    procedure DoAutoPlay(Sender: TObject);
    procedure DoDiskInsert(Sender: TObject);
    function InsertDiskFile(Drive: Integer; const FileName: string): Boolean;
    procedure UpdateRecentDisksMenu;
    { The game file just loaded, for default names (DAAD/PAW source export) }
    procedure NoteMediaFile(const FileName: string);
    procedure AddDriveBItem(Item: TMenuItem);
    procedure DoInsertRecentDisk(Sender: TObject);
    procedure DoInsertRecentCard(Sender: TObject);
    procedure DoDiskBrowser(Sender: TObject);
    procedure DoSDBrowser(Sender: TObject);
    procedure DoSDInsert(Sender: TObject);
    procedure DoSDNew(Sender: TObject);
    procedure DoSDEject(Sender: TObject);
    procedure DoSDSave(Sender: TObject);
    procedure DoDiskSaveSame(Sender: TObject);
    { A modified SD card: ask to save it. False if the user cancels. }
    function ConfirmCardChanges: Boolean;
    function SaveCardAs: Boolean;
    { DivMMC on or off as the settings say (a change powers the machine
      off and on); False with a message if the firmware is missing }
    function ApplyDivMMC: Boolean;
    function InsertSDCard(const FileName: string; Remember: Boolean = True): Boolean;
    procedure DoSDFolder(Sender: TObject);
    { A temporary card with esxDOS and the files of a PC folder in its root }
    function UseFolderAsCard(const Folder: string): Boolean;
    { Delete the temporary card's image once it is no longer in use }
    procedure DropTempCard;
    procedure DoDiskEject(Sender: TObject);
    procedure DoDiskSave(Sender: TObject);
    procedure DoDiskNew(Sender: TObject);
    procedure DoMute(Sender: TObject);
    procedure DoMonochrome(Sender: TObject);
    procedure DoDocumentation(Sender: TObject);
    procedure ApplyRomFiles;
    procedure DisplayMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure DisplayMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer);
    procedure DisplayMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer);
    procedure DisplayMouseLeave(Sender: TObject);
    procedure DoPoke(Sender: TObject);
    procedure ApplyPokes(const Pokes: TPokeList);
    procedure DoNewTape(Sender: TObject);
    procedure DoSaveToTape(Sender: TObject);
    procedure DoFastDisk(Sender: TObject);
    procedure DoDriveB(Sender: TObject);
    procedure DoScreenshotSCR(Sender: TObject);
    procedure DoScreenshotPNG(Sender: TObject);
    procedure DoScreenshotBorder(Sender: TObject);
    function ConfirmTapeChanges: Boolean;
    procedure DoScale(Sender: TObject);
    procedure DoSettings(Sender: TObject);
    procedure DoAbout(Sender: TObject);
    procedure DoLicense(Sender: TObject);
    procedure DoDebugger(Sender: TObject);
    procedure DoDaadDebugger(Sender: TObject);
    procedure DoClearBreakpoints(Sender: TObject);
    procedure DoLoadSymbols(Sender: TObject);
    procedure DoClearSymbols(Sender: TObject);
    procedure ProcessCommandLine;
    function CommandLineAddress(const AText: string; out Addr: Word): Boolean;
    { --sdadd: copy PC files ("SOURCE,FOLDER") onto the SD card, then switch
      the machine off and on so the firmware sees them }
    procedure AddFilesToCard(Specs: TStrings; var Errors: string);
  public
    { A ROM or system variable label of the ROM paged in now }
    function FindRomLabel(const AName: string; out Addr: Word): Boolean;
  private
    function LoadSymbols(const FileName: string): Boolean;
    procedure EmulatorBreak(Sender: TObject);
    function ConfirmDiskChanges(Drive: Integer): Boolean;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure OpenFile(const FileName: string; AutoStart: Boolean = True);
    procedure ChangeModel(M: TSpectrumModel);
    procedure ApplyZXUnoFiles(Reload: Boolean);
    function ReleasedSide(Key: Word): Word;
    procedure StoreZXUnoBios;
    property Emu: TEmulator read FEmu;
  end;

var
  MainWindow: TMainWindow;

implementation

uses
  Snapshot, DSK, TapeBrowser, SettingsForm, DebuggerForm, DaadForm, Symbols, BreakExpr, DiskBrowser,
  SDBrowser, FatFS, DebugFiles;

{ Names in breakpoint conditions: user symbols first, then ROM labels }
function LookupConditionSymbol(const Name: string; out Value: Word): Boolean;
begin
  Result := UserSymbols.Find(Name, Value);
  if not Result and (MainWindow <> nil) then Result := MainWindow.FindRomLabel(Name, Value);
end;

const
  OPEN_FILTER = 'All supported files|*.tap;*.sna;*.z80;*.dsk|Tape images (*.tap)|*.tap|' +
    'Snapshots (*.sna;*.z80)|*.sna;*.z80|+3 disk images (*.dsk)|*.dsk|All files|*.*';

{ TMainWindow }

{ --config FILE / --config-add FILE must be known before the settings load }
procedure ReadSettingsOptions;
var
  I: Integer;
  Arg, Value: string;
begin
  I := 1;
  while I <= ParamCount do
  begin
    Arg := ParamStr(I);
    Value := '';
    if Pos('=', Arg) > 0 then
    begin
      Value := Copy(Arg, Pos('=', Arg) + 1, MaxInt);
      Arg := Copy(Arg, 1, Pos('=', Arg) - 1);
    end;
    while (Arg <> '') and (Arg[1] = '-') do Delete(Arg, 1, 1);
    Arg := LowerCase(Arg);
    if (Arg = 'config') or (Arg = 'config-add') then
    begin
      if Value = '' then
      begin
        Inc(I);
        if I <= ParamCount then Value := ParamStr(I);
      end;
      if Value <> '' then
      begin
        if Arg = 'config' then
        begin
          // A settings file asked for by name must exist (an extra one may not)
          if not FileExists(Value) then
          begin
            MessageDlg('pzx', 'The settings file given with --config does not exist.' +
              LineEnding + LineEnding + 'File: ' + ExtractFileName(Value) + LineEnding +
              'Folder: ' + ExtractFilePath(ExpandFileName(Value)), mtError, [mbOK], 0);
            Halt(1);
          end;
          Settings.UseFile(Value);
        end
        else
          Settings.UseOverlay(Value);
      end;
    end;
    Inc(I);
  end;
end;

{ Cards made from folders that a pzx closed abruptly left behind (one still
  in use by another pzx can't be deleted, and stays) }
procedure RemoveStaleTempCards;
var
  Info: TSearchRec;
  Dir: string;
begin
  Dir := IncludeTrailingPathDelimiter(GetTempDir);
  if FindFirst(Dir + 'pzx-sd-*.img', faAnyFile, Info) = 0 then
  try
    repeat
      DeleteFile(Dir + Info.Name);
    until FindNext(Info) <> 0;
  finally
    FindClose(Info);
  end;
end;

constructor TMainWindow.Create(AOwner: TComponent);
var
  Err: string;
begin
  inherited CreateNew(AOwner, 0);
  Caption := 'pzx - ZX Spectrum emulator';
  Position := poScreenCenter;
  // Sizes here are real screen pixels (whole zoom factors); don't let LCL
  // multiply them by the desktop DPI scale
  Scaled := False;
  KeyPreview := True;
  AllowDropFiles := True;
  OnKeyDown := @FormKeyDown;
  OnKeyUp := @FormKeyUp;
  OnDeactivate := @FormDeactivate;
  OnDropFiles := @FormDropFiles;
  OnClose := @FormClose;
  OnShow := @FormShow;

  ReadSettingsOptions;
  Settings.Load;
  RemoveStaleTempCards;
  Err := '';
  try
    FEmu := TEmulator.Create(Settings.Model, Settings.RomDir);
  except
    on E: Exception do
    begin
      // Fall back to the ROMs next to the executable (a ZX-Uno without its
      // BIOS: the 48K)
      Err := E.Message;
      Settings.RomDir := DefaultRomDir;
      if Settings.Model = smZXUno then Settings.Model := sm48K;
      FEmu := TEmulator.Create(Settings.Model, Settings.RomDir);
    end;
  end;
  ApplyZXUnoFiles(True);
  FEmu.OnFrame := @FrameReady;
  OnTapeSettingsChanged := @TapeSettingsChanged;
  ConditionSymbol := @LookupConditionSymbol;
  FEmu.OnBreak := @EmulatorBreak;

  FBitmap := TBitmap.Create;
  FBitmap.PixelFormat := pf32bit;
  FBitmap.SetSize(SCREEN_WIDTH, SCREEN_HEIGHT);
  SetLength(FPixels, FB_WIDTH * SCREEN_HEIGHT);

  BuildMenu;
  BuildToolBar;

  FStatus := TStatusBar.Create(Self);
  FStatus.Parent := Self;
  FStatus.SimplePanel := False;
  with FStatus.Panels.Add do Width := 140;
  with FStatus.Panels.Add do Width := 70;
  with FStatus.Panels.Add do Width := 260;
  // Media: A, B and SD with a drive LED each (drawn in DrawMediaPanel)
  with FStatus.Panels.Add do
  begin
    Width := 170;
    Style := psOwnerDraw;
  end;
  FStatus.OnDrawPanel := @DrawMediaPanel;
  FLedTimer := TTimer.Create(Self);
  FLedTimer.Interval := 100;
  FLedTimer.OnTimer := @LedTick;

  FDisplay := TPaintBox.Create(Self);
  FDisplay.Parent := Self;
  FDisplay.Align := alClient;
  FDisplay.OnPaint := @PaintDisplay;
  FDisplay.OnMouseMove := @DisplayMouseMove;
  FDisplay.OnMouseDown := @DisplayMouseDown;
  FDisplay.OnMouseUp := @DisplayMouseUp;
  FDisplay.OnMouseLeave := @DisplayMouseLeave;

  FKeyTimer := TTimer.Create(Self);
  FKeyTimer.Interval := 10;
  FKeyTimer.Enabled := False;
  FKeyTimer.OnTimer := @KeyTimerTick;

  FStatusTimer := TTimer.Create(Self);
  FStatusTimer.Interval := 250;
  FStatusTimer.OnTimer := @StatusTick;

  // The card that was in the DivMMC last time
  if (Settings.SDCardFile <> '') and FileExists(Settings.SDCardFile) then
  begin
    FEmu.Lock;
    try
      try
        FEmu.Spec.DivMMC.InsertCard(Settings.SDCardFile);
      except
        Settings.SDCardFile := '';
      end;
    finally
      FEmu.Unlock;
    end;
  end;
  ApplySettings;
  SetScale(Settings.Scale);
  UpdateRecentMenu;
  UpdateRecentSymbolsMenu;
  UpdateRecentDisksMenu;
  UpdateChecks;
  FEmu.Start;
  if Err <> '' then
    MessageDlg('ROM folder not usable, using the default one instead.' + LineEnding + Err,
      mtWarning, [mbOK], 0);
end;

destructor TMainWindow.Destroy;
begin
  FEmu.Free;
  // The card is closed now: its temporary image can go
  if FTempCard <> '' then DeleteFile(FTempCard);
  FBitmap.Free;
  inherited Destroy;
end;

function TMainWindow.AddItem(AParent: TMenuItem; const ACaption: string; AHandler: TNotifyEvent;
  AShortCut: TShortCut): TMenuItem;
begin
  Result := TMenuItem.Create(Self);
  Result.Caption := ACaption;
  Result.OnClick := AHandler;
  Result.ShortCut := AShortCut;
  AParent.Add(Result);
end;

procedure TMainWindow.BuildMenu;
var
  TopItem, Item: TMenuItem;
  M: TSpectrumModel;
  S: Integer;
begin
  FMenu := TMainMenu.Create(Self);
  Menu := FMenu;

  TopItem := AddItem(FMenu.Items, '&File', nil);
  AddItem(TopItem, '&Open...', @DoOpen, ShortCut(VK_F2, []));
  FRecentMenu := AddItem(TopItem, 'Open &recent', nil);
  AddItem(TopItem, '&Save snapshot...', @DoSaveSnapshot, ShortCut(VK_F3, []));
  AddItem(TopItem, '-', nil);
  Item := AddItem(TopItem, 'Screens&hot', nil);
  AddItem(Item, 'Save as &SCR...', @DoScreenshotSCR);
  AddItem(Item, 'Save as PNG &1x...', @DoScreenshotPNG).Tag := 1;
  AddItem(Item, 'Save as PNG &2x...', @DoScreenshotPNG).Tag := 2;
  AddItem(Item, '-', nil);
  FBorderShotItem := AddItem(Item, 'Include &border in PNG', @DoScreenshotBorder);
  AddItem(TopItem, '-', nil);
  AddItem(TopItem, 'E&xit', @DoQuit);

  TopItem := AddItem(FMenu.Items, '&Machine', nil);
  for M := Low(TSpectrumModel) to High(TSpectrumModel) do
  begin
    FModelItems[M] := AddItem(TopItem, ModelInfo[M].Name, @DoModel);
    FModelItems[M].Tag := Ord(M);
    FModelItems[M].RadioItem := True;
    FModelItems[M].GroupIndex := 1;
  end;
  AddItem(TopItem, '-', nil);
  AddItem(TopItem, '&NMI', @DoNMI, ShortCut(VK_F5, []));
  AddItem(TopItem, '&Hard reset', @DoHardReset, ShortCut(VK_F6, []));
  AddItem(TopItem, '&Reset', @DoReset, ShortCut(VK_F6, [ssShift]));
  AddItem(TopItem, '-', nil);
  FPauseItem := AddItem(TopItem, '&Pause', @DoPause, ShortCut(VK_F4, []));
  AddItem(TopItem, '-', nil);
  AddItem(TopItem, '&POKE...', @DoPoke, ShortCut(VK_P, [ssCtrl]));

  TopItem := AddItem(FMenu.Items, '&Tape', nil);
  AddItem(TopItem, 'Tape &browser...', @DoTapeBrowser, ShortCut(VK_F7, []));
  AddItem(TopItem, '&Play', @DoTapePlay, ShortCut(VK_F8, []));
  AddItem(TopItem, '&Stop', @DoTapeStop, ShortCut(VK_F8, [ssShift]));
  FRecItem := AddItem(TopItem, 'Re&cord (REC)', @DoTapeRecord);
  AddItem(TopItem, '&Rewind', @DoTapeRewind);
  AddItem(TopItem, '&Eject', @DoTapeEject);
  AddItem(TopItem, 'Save tape &as...', @DoTapeSave);
  AddItem(TopItem, '-', nil);
  AddItem(TopItem, '&New blank tape', @DoNewTape);
  AddItem(TopItem, '-', nil);
  FFastLoadItem := AddItem(TopItem, '&Fast loading', @DoFastLoad);
  FAutoPlayItem := AddItem(TopItem, '&Auto play/stop', @DoAutoPlay);
  FSaveToTapeItem := AddItem(TopItem, 'SA&VE writes to the tape', @DoSaveToTape);

  TopItem := AddItem(FMenu.Items, 'F&loppy', nil);
  FDiskBrowserItem := AddItem(TopItem, 'Disk &browser...', @DoDiskBrowser);
  AddItem(TopItem, '-', nil);
  Item := AddItem(TopItem, 'Insert disk in drive &A:...', @DoDiskInsert);
  Item.Tag := 0;
  FRecentDisksMenu := AddItem(TopItem, 'Insert &recent disk (A:)', nil);
  // Drive B's entries show only while it is connected (UpdateChecks)
  Item := AddItem(TopItem, 'Insert disk in drive &B:...', @DoDiskInsert);
  Item.Tag := 1;
  AddDriveBItem(Item);
  FRecentDisksMenuB := AddItem(TopItem, 'Insert recent disk (B:)', nil);
  AddDriveBItem(FRecentDisksMenuB);
  Item := AddItem(TopItem, '&New disk in A: (formatted)', @DoDiskNew);
  Item.Tag := 0;
  Item := AddItem(TopItem, 'New disk in B: (formatted)', @DoDiskNew);
  Item.Tag := 1;
  AddDriveBItem(Item);
  AddItem(TopItem, '-', nil);
  Item := AddItem(TopItem, '&Save disk A:', @DoDiskSaveSame);
  Item.Tag := 0;
  Item := AddItem(TopItem, 'Save disk A: &as...', @DoDiskSave);
  Item.Tag := 0;
  Item := AddItem(TopItem, 'Save disk B:', @DoDiskSaveSame);
  Item.Tag := 1;
  AddDriveBItem(Item);
  Item := AddItem(TopItem, 'Save disk B: as...', @DoDiskSave);
  Item.Tag := 1;
  AddDriveBItem(Item);
  AddItem(TopItem, '-', nil);
  Item := AddItem(TopItem, '&Eject disk A:', @DoDiskEject);
  Item.Tag := 0;
  Item := AddItem(TopItem, 'Eject disk B:', @DoDiskEject);
  Item.Tag := 1;
  AddDriveBItem(Item);
  AddItem(TopItem, '-', nil);
  FFastDiskItem := AddItem(TopItem, '&Fast floppy disk access', @DoFastDisk);
  FDriveBItem := AddItem(TopItem, 'Drive &B: connected', @DoDriveB);

  // DivMMC SD card (the interface is switched on in Settings > Hardware)
  TopItem := AddItem(FMenu.Items, '&SD', nil);
  FSDBrowserItem := AddItem(TopItem, 'SD card &browser...', @DoSDBrowser);
  AddItem(TopItem, '-', nil);
  AddItem(TopItem, '&Insert SD card image...', @DoSDInsert);
  FRecentCardsMenu := AddItem(TopItem, 'Insert &recent SD card', nil);
  AddItem(TopItem, 'Use a PC &folder as SD card...', @DoSDFolder);
  AddItem(TopItem, '&New SD card...', @DoSDNew).Tag := 0;
  AddItem(TopItem, 'New SD card with &ESXDOS...', @DoSDNew).Tag := 1;
  AddItem(TopItem, '-', nil);
  AddItem(TopItem, '&Save SD card', @DoSDSave).Tag := 0;
  AddItem(TopItem, 'Save SD card &as...', @DoSDSave).Tag := 1;
  AddItem(TopItem, '-', nil);
  AddItem(TopItem, 'E&ject SD card', @DoSDEject);

  TopItem := AddItem(FMenu.Items, '&Debug', nil);
  AddItem(TopItem, '&Debugger...', @DoDebugger, ShortCut(VK_F12, []));
  AddItem(TopItem, '&Clear all breakpoints', @DoClearBreakpoints);
  AddItem(TopItem, '-', nil);
  AddItem(TopItem, '&Load symbols...', @DoLoadSymbols);
  FRecentSymbolsMenu := AddItem(TopItem, 'Load &recent symbols', nil);
  AddItem(TopItem, 'C&lear symbols', @DoClearSymbols);
  AddItem(TopItem, '-', nil);
  AddItem(TopItem, 'D&AAD/PAW debugger...', @DoDaadDebugger, ShortCut(VK_F11, []));

  TopItem := AddItem(FMenu.Items, '&Options', nil);
  FMonoItem := AddItem(TopItem, '&Black and white display', @DoMonochrome);
  Item := AddItem(TopItem, '&Window size', nil);
  for S := 1 to 4 do
  begin
    FScaleItems[S] := AddItem(Item, Format('%dx', [S]), @DoScale);
    FScaleItems[S].Tag := S;
    FScaleItems[S].RadioItem := True;
    FScaleItems[S].GroupIndex := 2;
  end;
  FMuteItem := AddItem(TopItem, '&Mute sound', @DoMute);
  FTurboItem := AddItem(TopItem, '&Turbo speed', @DoTurbo, ShortCut(VK_F11, [ssShift]));
  AddItem(TopItem, '-', nil);
  AddItem(TopItem, 'S&ettings...', @DoSettings);

  TopItem := AddItem(FMenu.Items, '&Help', nil);
  AddItem(TopItem, '&Documentation', @DoDocumentation, ShortCut(VK_F1, []));
  AddItem(TopItem, '-', nil);
  AddItem(TopItem, '&License (GPL v3)', @DoLicense);
  AddItem(TopItem, '&About pzx...', @DoAbout);
end;

function TMainWindow.AddButton(AIcon: TIconKind; const AHint: string; AHandler: TNotifyEvent): TToolButton;
begin
  Result := TToolButton.Create(FToolBar);
  Result.Parent := FToolBar;
  Result.ImageIndex := Ord(AIcon);
  Result.Hint := AHint;
  Result.OnClick := AHandler;
  // Toolbar lays buttons out by position, so append at the far right
  Result.Left := FToolBar.Width + 1000;
end;

procedure TMainWindow.AddSeparator;
var
  Sep: TToolButton;
begin
  Sep := TToolButton.Create(FToolBar);
  Sep.Parent := FToolBar;
  Sep.Style := tbsDivider;
  Sep.Left := FToolBar.Width + 1000;
end;

procedure TMainWindow.BuildToolBar;
var
  M: TSpectrumModel;
  Item: TToolButton;
begin
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

  AddButton(ikOpen, 'Open a tape, snapshot or disk (F2)', @DoOpen);
  AddButton(ikSave, 'Save snapshot (F3)', @DoSaveSnapshot);
  AddSeparator;

  // Machine model: a chip button that drops down the list of models
  FModelMenu := TPopupMenu.Create(Self);
  for M := Low(TSpectrumModel) to High(TSpectrumModel) do
  begin
    FModelPopupItems[M] := TMenuItem.Create(FModelMenu);
    FModelPopupItems[M].Caption := ModelInfo[M].Name;
    FModelPopupItems[M].Tag := Ord(M);
    FModelPopupItems[M].RadioItem := True;
    FModelPopupItems[M].GroupIndex := 1;
    FModelPopupItems[M].OnClick := @DoModel;
    FModelMenu.Items.Add(FModelPopupItems[M]);
  end;
  FModelButton := AddButton(ikModel, 'Machine model', @DoModelButton);
  AddSeparator;

  AddButton(ikReset, 'Hard reset: switch the machine off and on (F6)', @DoHardReset);
  AddButton(ikNMI, 'Non-maskable interrupt (F5)', @DoNMI);
  FPauseButton := AddButton(ikPause, 'Pause emulation (F4)', @DoPause);
  FPauseButton.Style := tbsCheck;
  FTurboButton := AddButton(ikTurbo, 'Run as fast as possible (Shift+F11)', @DoTurbo);
  FTurboButton.Style := tbsCheck;
  AddSeparator;
  AddButton(ikTape, 'Tape browser (F7)', @DoTapeBrowser);
  AddButton(ikPlay, 'Play tape (F8)', @DoTapePlay);
  AddButton(ikStop, 'Stop tape (Shift+F8)', @DoTapeStop);
  FRecButton := AddButton(ikRecord, 'Record onto the tape (REC)', @DoTapeRecord);
  FRecButton.Style := tbsCheck;
  AddSeparator;
  FDiskButton := AddButton(ikDisk, 'Disk browser', @DoDiskBrowser);
  FSDButton := AddButton(ikSDCard, 'SD card browser (DivMMC)', @DoSDBrowser);
  AddSeparator;
  AddButton(ikDebugger, 'Debugger (F12)', @DoDebugger);
  AddButton(ikSettings, 'Settings', @DoSettings);
end;

procedure TMainWindow.ApplySettings;
begin
  FEmu.Lock;
  try
    FEmu.Spec.FastLoad := Settings.FastLoad;
    FEmu.Spec.AutoPlayTape := Settings.AutoPlayTape;
    FEmu.Spec.KempstonEnabled := Settings.Joystick = jkKempston;
    FEmu.Spec.MouseEnabled := Settings.KempstonMouse;
    FEmu.Spec.AYOn48K := Settings.AY48;
    FEmu.Spec.FullerEnabled := Settings.Joystick = jkFuller;
    FEmu.Spec.Issue2 := Settings.Issue2;
    FEmu.Spec.SetSpeed(Settings.CpuSpeed);
    FEmu.Spec.SaveToTape := Settings.SaveToTape;
    FEmu.Spec.SetFastDisk(Settings.FastDisk);
    FEmu.Spec.FDC.DriveB := Settings.DriveB;
    FEmu.Spec.FloppyNoise := Settings.FloppyNoise;
    FEmu.Spec.Volume := Settings.Volume / 100;
    FEmu.Spec.TurboSound := Settings.TurboSound;
    FEmu.Spec.ContentionOn := Settings.Contention;
    FEmu.Spec.SnowOn := Settings.UlaSnow;
    FEmu.Spec.RomWritable := Settings.AllowRomEdit;
    FEmu.Spec.ULAPlusEnabled := Settings.ULAPlus;
    FEmu.Spec.TimexEnabled := Settings.Timex;
    FEmu.Spec.RadastanEnabled := Settings.Radastan;
  finally
    FEmu.Unlock;
  end;
  FEmu.Sound := Settings.Sound;
  ApplyRomFiles;
  ApplyDivMMC;
end;

function TMainWindow.ApplyDivMMC: Boolean;
var
  Firmware, Err: string;
begin
  Result := True;
  // The ZX-Uno has its own DivMMC, which its BIOS switches on
  if FEmu.Spec.Info.Memory = mkZXUno then Exit;
  if Settings.DivMMC = FEmu.Spec.DivMMCOn then Exit;
  Err := '';
  if Settings.DivMMC then
  begin
    Firmware := DivMMCFirmwareFile;
    if (Firmware = '') or not FileExists(Firmware) then
      Err := 'The DivMMC firmware (esxdos/ESXMMC.BIN) was not found.'
    else
    begin
      FEmu.Lock;
      try
        try
          FEmu.Spec.DivMMC.LoadRom(Firmware);
          FEmu.Spec.DivMMCOn := True;
          FEmu.Spec.Reset(True);    // like switching on with the interface fitted
        except
          on E: Exception do Err := E.Message;
        end;
      finally
        FEmu.Unlock;
      end;
    end;
    if Err <> '' then
    begin
      Settings.DivMMC := False;
      Result := False;
      MessageDlg('DivMMC: ' + Err, mtError, [mbOK], 0);
    end;
  end
  else
  begin
    FEmu.Lock;
    try
      FEmu.Spec.DivMMCOn := False;
      FEmu.Spec.Reset(True);
    finally
      FEmu.Unlock;
    end;
  end;
  if FMuteItem <> nil then UpdateChecks;
end;

function TMainWindow.InsertSDCard(const FileName: string; Remember: Boolean): Boolean;
var
  Err: string;
begin
  Result := False;
  if (FEmu.Spec.DivMMC.Card <> nil) and
     SameFileName(ExpandFileName(FEmu.Spec.DivMMC.Card.FileName), ExpandFileName(FileName)) then
  begin
    MessageDlg('That SD card image is already inserted.', mtInformation, [mbOK], 0);
    Exit;
  end;
  if not ConfirmCardChanges then Exit;
  Err := '';
  FEmu.Lock;
  try
    try
      FEmu.Spec.DivMMC.InsertCard(FileName);
    except
      on E: Exception do Err := E.Message;
    end;
  finally
    FEmu.Unlock;
  end;
  if Err <> '' then
  begin
    MessageDlg('Could not open the SD card image:' + LineEnding + Err, mtError, [mbOK], 0);
    Exit(False);
  end;
  if Remember then
  begin
    Settings.SDCardFile := FileName;
    Settings.AddRecentCard(FileName);
    UpdateRecentDisksMenu;
  end;
  DropTempCard;
  // A card is no use without the interface
  if not Settings.DivMMC then
  begin
    Settings.DivMMC := True;
    ApplyDivMMC;
  end;
  if SDBrowserWindow <> nil then SDBrowserWindow.Refresh;
  Result := True;
end;

{ ROM files chosen in the settings; reloads the machine if its ROMs changed }
procedure TMainWindow.ApplyRomFiles;
var
  M: TSpectrumModel;
  I: Integer;
  RomsChanged: Boolean;
  Err: string;
begin
  Err := '';
  FEmu.Lock;
  try
    RomsChanged := False;
    for M := Low(TSpectrumModel) to High(TSpectrumModel) do
      for I := 0 to 3 do
        if FEmu.Spec.RomFile[M, I] <> Settings.RomFiles[M, I] then
        begin
          FEmu.Spec.RomFile[M, I] := Settings.RomFiles[M, I];
          if M = FEmu.Spec.Model then RomsChanged := True;
        end;
    if RomsChanged then
      try
        FEmu.Spec.SetModel(FEmu.Spec.Model);
      except
        on E: Exception do
        begin
          // Back to the standard ROMs for this model
          Err := E.Message;
          for I := 0 to 3 do
          begin
            Settings.RomFiles[FEmu.Spec.Model, I] := '';
            FEmu.Spec.RomFile[FEmu.Spec.Model, I] := '';
          end;
          FEmu.Spec.SetModel(FEmu.Spec.Model);
        end;
      end;
  finally
    FEmu.Unlock;
  end;
  if Err <> '' then
    MessageDlg(Err + LineEnding + 'Using the standard ROMs for this model.', mtError, [mbOK], 0);
end;

procedure TMainWindow.UpdateChecks;
var
  M: TSpectrumModel;
  S, I: Integer;
begin
  M := FEmu.Spec.Model;
  FModelItems[M].Checked := True;
  FModelPopupItems[M].Checked := True;
  FModelButton.Hint := 'Machine: ' + ModelInfo[M].Name + ' (click to change)';
  FFastLoadItem.Checked := Settings.FastLoad;
  FAutoPlayItem.Checked := Settings.AutoPlayTape;
  FMuteItem.Checked := not Settings.Sound;
  FMonoItem.Checked := Settings.Monochrome;
  // The Spectrum draws its own pointer: hide the PC one over the picture
  if Settings.KempstonMouse then FDisplay.Cursor := crNone else FDisplay.Cursor := crDefault;
  FSaveToTapeItem.Checked := Settings.SaveToTape;
  FFastDiskItem.Checked := Settings.FastDisk;
  FDriveBItem.Checked := Settings.DriveB;
  for I := 0 to High(FDriveBItems) do FDriveBItems[I].Visible := Settings.DriveB;
  FBorderShotItem.Checked := Settings.ScreenshotBorder;
  FPauseItem.Checked := FEmu.Paused;
  FRecItem.Checked := FEmu.Spec.Recording;
  FRecButton.Down := FEmu.Spec.Recording;
  FPauseButton.Down := FEmu.Paused;
  FTurboItem.Checked := FEmu.Turbo;
  FTurboButton.Down := FEmu.Turbo;
  for S := 1 to 4 do FScaleItems[S].Checked := S = Settings.Scale;
end;

procedure TMainWindow.SetScale(Scale: Integer);
var
  Work: TRect;
  ExtraW, ExtraH: Integer;
begin
  // Space taken by toolbar, status bar etc., measured from the live layout
  ExtraW := Max(0, ClientWidth - FDisplay.Width);
  ExtraH := Max(FToolBar.Height + FStatus.Height, ClientHeight - FDisplay.Height);
  // Keep the window on screen: drop to the largest whole zoom that fits
  Work := Screen.WorkAreaRect;
  while (Scale > 1) and ((SCREEN_WIDTH * Scale + ExtraW + 40 > Work.Right - Work.Left) or
    (SCREEN_HEIGHT * Scale + ExtraH + 80 > Work.Bottom - Work.Top)) do
    Dec(Scale);
  Settings.Scale := Scale;
  WindowState := wsNormal;
  ClientWidth := SCREEN_WIDTH * Scale + ExtraW;
  ClientHeight := SCREEN_HEIGHT * Scale + ExtraH;
end;

procedure TMainWindow.ResizeAfterShow(Data: PtrInt);
begin
  // Toolbar and status bar heights are only final once the window is shown
  SetScale(Settings.Scale);
end;

procedure TMainWindow.UpdateRecentSymbolsMenu;
var
  I: Integer;
  Item: TMenuItem;
begin
  FRecentSymbolsMenu.Clear;
  for I := 0 to Settings.RecentSymbols.Count - 1 do
  begin
    Item := AddItem(FRecentSymbolsMenu, Format('&%d %s', [I + 1, Settings.RecentSymbols[I]]),
      @DoLoadRecentSymbols);
    Item.Tag := I;
  end;
  FRecentSymbolsMenu.Enabled := Settings.RecentSymbols.Count > 0;
end;

procedure TMainWindow.DoLoadRecentSymbols(Sender: TObject);
var
  Index: Integer;
begin
  Index := (Sender as TComponent).Tag;
  if Index < Settings.RecentSymbols.Count then LoadSymbols(Settings.RecentSymbols[Index]);
end;

procedure TMainWindow.UpdateRecentMenu;
var
  I: Integer;
  Item: TMenuItem;
begin
  FRecentMenu.Clear;
  for I := 0 to Settings.RecentFiles.Count - 1 do
  begin
    Item := AddItem(FRecentMenu, Format('&%d %s', [I + 1, Settings.RecentFiles[I]]), @DoOpenRecent);
    Item.Tag := I;
  end;
  FRecentMenu.Enabled := Settings.RecentFiles.Count > 0;
end;

{ Display }

function TMainWindow.DisplayScale: Integer;
begin
  // Whole-number zoom only: the largest that fits, never below 1x
  Result := Min(FDisplay.Width div SCREEN_WIDTH, FDisplay.Height div SCREEN_HEIGHT);
  if Result < 1 then Result := 1;
end;

procedure TMainWindow.RenderBitmap;
var
  Scale, X, Y, I, Stride, BytesPP: Integer;
  RShift, GShift, BShift, AShift: Byte;
  Data, Row: PByte;
  Line, Dark: array of LongWord;
  P, Native: LongWord;
  Direct, Mono, Scan: Boolean;
  Grey: LongWord;
begin
  Scale := DisplayScale;
  Mono := Settings.Monochrome;
  // Scanlines: from 2x, the lower rows of every Spectrum line are darker
  Scan := Settings.Scanlines and (Scale >= 2);
  if (FBitmap.Width <> SCREEN_WIDTH * Scale) or (FBitmap.Height <> SCREEN_HEIGHT * Scale) then
    FBitmap.SetSize(SCREEN_WIDTH * Scale, SCREEN_HEIGHT * Scale);
  SetLength(Line, SCREEN_WIDTH * Scale);
  SetLength(Dark, SCREEN_WIDTH * Scale);
  FBitmap.BeginUpdate(False);
  try
    Data := FBitmap.RawImage.Data;
    with FBitmap.RawImage.Description do
    begin
      Stride := BytesPerLine;
      BytesPP := BitsPerPixel div 8;
      RShift := RedShift; GShift := GreenShift; BShift := BlueShift; AShift := AlphaShift;
      // Our pixels are $AARRGGBB; most platforms store 32-bit BGRA, which matches
      Direct := (BitsPerPixel = 32) and (RShift = 16) and (GShift = 8) and (BShift = 0) and
        (ByteOrder = riboLSBFirst);
    end;
    for Y := 0 to SCREEN_HEIGHT - 1 do
    begin
      // Build one scaled line, then copy it Scale times. The frame buffer
      // is twice as wide (Timex hi-res): each output pixel takes its column
      for X := 0 to SCREEN_WIDTH * Scale - 1 do
      begin
        P := FPixels[Y * FB_WIDTH + X * 2 div Scale];
        if Mono then
        begin
          Grey := (((P shr 16) and $FF) * 77 + ((P shr 8) and $FF) * 150 + (P and $FF) * 29) shr 8;
          P := $FF000000 or (Grey shl 16) or (Grey shl 8) or Grey;
        end;
        if Direct then
          Native := P
        else
          Native := (((P shr 16) and $FF) shl RShift) or (((P shr 8) and $FF) shl GShift) or
            ((P and $FF) shl BShift) or (LongWord($FF) shl AShift);
        Line[X] := Native;
        if Scan then
          Dark[X] := (((((P shr 16) and $FF) * 5) shr 3) shl RShift) or
            (((((P shr 8) and $FF) * 5) shr 3) shl GShift) or ((((P and $FF) * 5) shr 3) shl BShift) or
            (LongWord($FF) shl AShift);
      end;
      for I := 0 to Scale - 1 do
      begin
        Row := @Data[(Y * Scale + I) * Stride];
        if Scan and (I >= (Scale + 1) div 2) then
        begin
          if BytesPP = 4 then
            Move(Dark[0], Row^, Length(Dark) * 4)
          else
            for X := 0 to High(Dark) do
              Move(Dark[X], Row[X * BytesPP], BytesPP);
        end
        else if BytesPP = 4 then
          Move(Line[0], Row^, Length(Line) * 4)
        else
          for X := 0 to High(Line) do
            Move(Line[X], Row[X * BytesPP], BytesPP);
      end;
    end;
  finally
    FBitmap.EndUpdate(False);
  end;
end;

procedure TMainWindow.FrameReady(Sender: TObject);
begin
  FEmu.CopyDisplay(@FPixels[0]);
  RenderBitmap;
  FDisplay.Invalidate;
end;

procedure TMainWindow.PaintDisplay(Sender: TObject);
var
  R: TRect;
begin
  if FBitmap.Width <> SCREEN_WIDTH * DisplayScale then RenderBitmap;   // window resized
  R.Left := (FDisplay.Width - FBitmap.Width) div 2;
  R.Top := (FDisplay.Height - FBitmap.Height) div 2;
  R.Right := R.Left + FBitmap.Width;
  R.Bottom := R.Top + FBitmap.Height;
  FDisplay.Canvas.Brush.Color := clBlack;
  FDisplay.Canvas.FillRect(0, 0, FDisplay.Width, Max(R.Top, 0));
  FDisplay.Canvas.FillRect(0, R.Bottom, FDisplay.Width, FDisplay.Height);
  FDisplay.Canvas.FillRect(0, R.Top, Max(R.Left, 0), R.Bottom);
  FDisplay.Canvas.FillRect(R.Right, R.Top, FDisplay.Width, R.Bottom);
  // Same size as the target: no stretching or smoothing by the platform
  FDisplay.Canvas.Draw(R.Left, R.Top, FBitmap);
end;

procedure TMainWindow.StatusTick(Sender: TObject);
var
  TapeText: string;
  Spec: TSpectrum;
  HaveDisk, HaveCard: Boolean;
begin
  FEmu.Lock;
  try
    Spec := FEmu.Spec;
    if Spec.Recording then
      TapeText := Format('Recording (%d blocks)', [Spec.Tape.Count])
    else if Spec.Tape.Count = 0 then
      TapeText := 'No tape'
    else
    begin
      TapeText := Format('Tape %d/%d', [Min(Spec.Tape.Current + 1, Spec.Tape.Count), Spec.Tape.Count]);
      if Spec.Tape.Playing then TapeText := TapeText + ' playing';
      if Spec.Tape.Current < Spec.Tape.Count then
        TapeText := TapeText + ': ' + Spec.Tape[Spec.Tape.Current].Description;
    end;
    // The disk browser needs a disk in A:, the SD browser a card
    // The browsers need something to browse: from the toolbar and the menus
    HaveDisk := DefaultDrive(Spec) >= 0;
    HaveCard := Spec.DivMMCOn and (Spec.DivMMC.Card <> nil);
    if FDiskButton.Enabled <> HaveDisk then FDiskButton.Enabled := HaveDisk;
    if FDiskBrowserItem.Enabled <> HaveDisk then FDiskBrowserItem.Enabled := HaveDisk;
    if FSDButton.Enabled <> HaveCard then FSDButton.Enabled := HaveCard;
    if FSDBrowserItem.Enabled <> HaveCard then FSDBrowserItem.Enabled := HaveCard;
    FStatus.Panels[0].Text := Spec.Info.Name;
  finally
    FEmu.Unlock;
  end;
  if (FPauseButton.Down <> FEmu.Paused) or (FRecButton.Down <> FEmu.Spec.Recording) then
    UpdateChecks;
  if FEmu.Paused then
    FStatus.Panels[1].Text := 'Paused'
  else
    FStatus.Panels[1].Text := Format('%d fps', [FEmu.Fps]);
  if FEmu.Spec.Speed > 1 then
    FStatus.Panels[1].Text := FStatus.Panels[1].Text + Format(' CPU x%d', [FEmu.Spec.Speed]);
  FStatus.Panels[2].Text := TapeText;
end;

{ Media present and busy, like the LEDs of a drive: lit while it is read or
  written (and a moment after) }
procedure TMainWindow.LedTick(Sender: TObject);
const
  LIT_MS = 150;
var
  State: Integer;
  Now: QWord;
  Spec: TSpectrum;
begin
  State := 0;
  Now := GetTickCount64;
  FEmu.Lock;
  try
    Spec := FEmu.Spec;
    if Spec.FDC.Disk(0) <> nil then
    begin
      State := State or 1;
      if Now - Spec.FDC.LastAccess(0) < LIT_MS then State := State or $10;
    end;
    if (Spec.FDC.Disk(1) <> nil) and Spec.FDC.DriveB then
    begin
      State := State or 2;
      if Now - Spec.FDC.LastAccess(1) < LIT_MS then State := State or $20;
    end;
    if Spec.DivMMCOn and (Spec.DivMMC.Card <> nil) then
    begin
      State := State or 4;
      if Now - Spec.DivMMC.Card.LastAccess < LIT_MS then State := State or $40;
    end;
  finally
    FEmu.Unlock;
  end;
  if State <> FMediaState then
  begin
    FMediaState := State;
    FStatus.Invalidate;
  end;
end;

procedure TMainWindow.DrawMediaPanel(StatusBar: TStatusBar; Panel: TStatusPanel;
  const Rect: TRect);
const
  NAMES: array[0..2] of string = ('A', 'B', 'SD');
var
  C: TCanvas;
  I, X, LedW, LedH, Y: Integer;
begin
  C := StatusBar.Canvas;
  C.Brush.Style := bsSolid;
  C.Brush.Color := StatusBar.Color;
  C.FillRect(Rect);
  LedW := Max(10, C.TextHeight('A') * 2 div 3);
  LedH := Max(5, LedW div 2);
  X := Rect.Left + 4;
  for I := 0 to 2 do
  begin
    if (FMediaState and (1 shl I)) = 0 then Continue;
    C.Brush.Style := bsClear;
    C.Font.Color := clWindowText;
    C.TextOut(X, Rect.Top + (Rect.Bottom - Rect.Top - C.TextHeight(NAMES[I])) div 2, NAMES[I]);
    Inc(X, C.TextWidth(NAMES[I]) + 4);
    // The LED: light red while reading, dark red when idle
    Y := Rect.Top + (Rect.Bottom - Rect.Top - LedH) div 2;
    C.Brush.Style := bsSolid;
    if (FMediaState and ($10 shl I)) <> 0 then C.Brush.Color := RGBToColor(255, 90, 90)
    else C.Brush.Color := RGBToColor(90, 0, 0);
    C.Pen.Color := RGBToColor(90, 90, 90);
    C.Rectangle(X, Y, X + LedW, Y + LedH);
    Inc(X, LedW + 14);
  end;
end;

{ Keyboard }

procedure TMainWindow.UpdateKeyboard;
var
  Row, Bit: Integer;
  Value: Byte;
begin
  for Row := 0 to 7 do
  begin
    Value := $FF;
    for Bit := 0 to 4 do
      if FKeyCount[Row * 5 + Bit] > 0 then Value := Value and not (1 shl Bit);
    FEmu.Spec.Keyboard[Row] := Value;
  end;
  FEmu.Spec.KempstonState := FKempstonBits;
  FEmu.Spec.FullerState := not FFullerBits;
end;

procedure TMainWindow.MapKey(Key: Word; Down: Boolean);

  procedure Press(K: Integer);
  begin
    if Down then Inc(FKeyCount[K]) else if FKeyCount[K] > 0 then Dec(FKeyCount[K]);
  end;

  procedure Joy(Bit: Byte);
  begin
    if Down then FKempstonBits := FKempstonBits or Bit else FKempstonBits := FKempstonBits and not Bit;
  end;

const
  Letters: array['A'..'Z'] of Integer = (
    KEY_A, KEY_B, KEY_C, KEY_D, KEY_E, KEY_F, KEY_G, KEY_H, KEY_I, KEY_J, KEY_K, KEY_L, KEY_M,
    KEY_N, KEY_O, KEY_P, KEY_Q, KEY_R, KEY_S, KEY_T, KEY_U, KEY_V, KEY_W, KEY_X, KEY_Y, KEY_Z);
  Digits: array['0'..'9'] of Integer = (
    KEY_0, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9);
  // Directions: left, right, down, up, fire
  KEMPSTON_BITS: array[0..4] of Byte = ($02, $01, $04, $08, $10);
  FULLER_BITS: array[0..4] of Byte = ($04, $08, $02, $01, $80);
  SINCLAIR1_KEYS: array[0..4] of Integer = (KEY_6, KEY_7, KEY_8, KEY_9, KEY_0);
  SINCLAIR2_KEYS: array[0..4] of Integer = (KEY_1, KEY_2, KEY_3, KEY_4, KEY_5);
  CURSOR_KEYS: array[0..4] of Integer = (KEY_5, KEY_8, KEY_6, KEY_7, KEY_0);
var
  Dir: Integer;
begin
  // Cursor keys and Ctrl (either) as a joystick
  if (Settings.Joystick <> jkNone) and
     (Key in [VK_LEFT, VK_RIGHT, VK_UP, VK_DOWN, VK_CONTROL, VK_LCONTROL, VK_RCONTROL]) then
  begin
    case Key of
      VK_LEFT: Dir := 0;
      VK_RIGHT: Dir := 1;
      VK_DOWN: Dir := 2;
      VK_UP: Dir := 3;
    else
      Dir := 4;   // fire
    end;
    case Settings.Joystick of
      jkKempston: Joy(KEMPSTON_BITS[Dir]);
      jkFuller:
        if Down then FFullerBits := FFullerBits or FULLER_BITS[Dir]
        else FFullerBits := FFullerBits and not FULLER_BITS[Dir];
      jkSinclair1: Press(SINCLAIR1_KEYS[Dir]);
      jkSinclair2: Press(SINCLAIR2_KEYS[Dir]);
      jkCursor: Press(CURSOR_KEYS[Dir]);
    end;
    Exit;
  end;
  case Key of
    VK_A..VK_Z: Press(Letters[Chr(Key)]);
    VK_0..VK_9: Press(Digits[Chr(Key)]);
    VK_NUMPAD0..VK_NUMPAD9: Press(Digits[Chr(Ord('0') + Key - VK_NUMPAD0)]);
    VK_RETURN: Press(KEY_ENTER);
    VK_SPACE: Press(KEY_SPACE);
    // Shift and Ctrl (FormKeyDown/Up tell left from right)
    VK_SHIFT, VK_LSHIFT: Press(KEY_CAPS);
    VK_RSHIFT: if Settings.ShiftSides then Press(KEY_SYM) else Press(KEY_CAPS);
    VK_LCONTROL: if Settings.ShiftSides then Press(KEY_CAPS) else Press(KEY_SYM);
    VK_CONTROL, VK_RCONTROL: Press(KEY_SYM);
    VK_BACK: begin Press(KEY_CAPS); Press(KEY_0); end;
    VK_LEFT: begin Press(KEY_CAPS); Press(KEY_5); end;
    VK_DOWN: begin Press(KEY_CAPS); Press(KEY_6); end;
    VK_UP: begin Press(KEY_CAPS); Press(KEY_7); end;
    VK_RIGHT: begin Press(KEY_CAPS); Press(KEY_8); end;
    VK_ESCAPE: begin Press(KEY_CAPS); Press(KEY_SPACE); end;    // BREAK
    VK_TAB: begin Press(KEY_CAPS); Press(KEY_SYM); end;         // extended mode
    VK_OEM_COMMA: begin Press(KEY_SYM); Press(KEY_N); end;
    VK_OEM_PERIOD: begin Press(KEY_SYM); Press(KEY_M); end;
    VK_OEM_MINUS, VK_SUBTRACT: begin Press(KEY_SYM); Press(KEY_J); end;
    VK_OEM_PLUS: begin Press(KEY_SYM); Press(KEY_L); end;
    VK_ADD: begin Press(KEY_SYM); Press(KEY_K); end;
    VK_MULTIPLY: begin Press(KEY_SYM); Press(KEY_B); end;
    VK_DIVIDE, VK_OEM_2: begin Press(KEY_SYM); Press(KEY_V); end;
    VK_OEM_1: begin Press(KEY_SYM); Press(KEY_O); end;           // ;
    VK_OEM_7: begin Press(KEY_SYM); Press(KEY_P); end;           // "
  end;
end;

{ Which Shift or Ctrl went down: the left or the right one }
function SidedKey(Key: Word): Word;
begin
  Result := Key;
  if Key = VK_SHIFT then
  begin
    if GetKeyState(VK_RSHIFT) < 0 then Result := VK_RSHIFT else Result := VK_LSHIFT;
  end
  else if Key = VK_CONTROL then
  begin
    if GetKeyState(VK_RCONTROL) < 0 then Result := VK_RCONTROL else Result := VK_LCONTROL;
  end;
end;

{ Which Shift or Ctrl went up: the one down that no longer is }
function TMainWindow.ReleasedSide(Key: Word): Word;
var
  L, R: Word;
begin
  Result := Key;
  if Key = VK_SHIFT then
  begin
    L := VK_LSHIFT;
    R := VK_RSHIFT;
  end
  else if Key = VK_CONTROL then
  begin
    L := VK_LCONTROL;
    R := VK_RCONTROL;
  end
  else
    Exit;
  if FPCKeyDown[R] and (GetKeyState(R) >= 0) then Result := R
  else if FPCKeyDown[L] then Result := L
  else Result := R;
end;

procedure TMainWindow.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key >= VK_F1) and (Key <= VK_F24) then Exit;    // leave function keys to the menu
  if (Key = VK_MENU) or (ssAlt in Shift) then Exit;
  Key := SidedKey(Key);
  if Key <= High(FPCKeyDown) then
  begin
    if FPendingUp[Key] <> 0 then ReleasePCKey(Key);   // finish a pending tap first
    if not FPCKeyDown[Key] then
    begin
      FPCKeyDown[Key] := True;
      FPCKeyTime[Key] := GetTickCount64;
      MapKey(Key, True);
      UpdateKeyboard;
    end;
  end;
  Key := 0;
end;

procedure TMainWindow.ReleasePCKey(Key: Word);
begin
  FPendingUp[Key] := 0;
  if FPCKeyDown[Key] then
  begin
    FPCKeyDown[Key] := False;
    MapKey(Key, False);
    UpdateKeyboard;
  end;
end;

procedure TMainWindow.FormKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
const
  MIN_HOLD_MS = 60;   // the ROM scans the keyboard once per 20 ms frame
var
  Held: QWord;
begin
  if (Key >= VK_F1) and (Key <= VK_F24) then Exit;
  Key := ReleasedSide(Key);
  if (Key <= High(FPCKeyDown)) and FPCKeyDown[Key] then
  begin
    Held := GetTickCount64 - FPCKeyTime[Key];
    if Held >= MIN_HOLD_MS then
      ReleasePCKey(Key)
    else
    begin
      // Too short for the Spectrum to notice: release it a little later
      FPendingUp[Key] := FPCKeyTime[Key] + MIN_HOLD_MS;
      FKeyTimer.Enabled := True;
    end;
  end;
  Key := 0;
end;

procedure TMainWindow.KeyTimerTick(Sender: TObject);
var
  K: Integer;
  Now: QWord;
  Pending: Boolean;
begin
  Now := GetTickCount64;
  Pending := False;
  for K := 0 to High(FPendingUp) do
    if FPendingUp[K] <> 0 then
    begin
      if Now >= FPendingUp[K] then ReleasePCKey(K) else Pending := True;
    end;
  FKeyTimer.Enabled := Pending;
end;

procedure TMainWindow.ReleaseAllKeys;
var
  I: Integer;
begin
  for I := 0 to High(FPCKeyDown) do
  begin
    FPCKeyDown[I] := False;
    FPendingUp[I] := 0;
  end;
  for I := 0 to High(FKeyCount) do FKeyCount[I] := 0;
  FKempstonBits := 0;
  FFullerBits := 0;
  UpdateKeyboard;
end;

procedure TMainWindow.FormDeactivate(Sender: TObject);
begin
  // Key-up events are lost while another window has focus
  ReleaseAllKeys;
end;

procedure TMainWindow.FormDropFiles(Sender: TObject; const FileNames: array of string);
begin
  if Length(FileNames) > 0 then OpenFile(FileNames[0]);
end;

procedure TMainWindow.FormShow(Sender: TObject);
begin
  // Size again once the window has settled: the platform may have changed
  // the toolbar height or rescaled the window
  Application.QueueAsyncCall(@ResizeAfterShow, 0);
  // The command line can open windows (debugger, documentation), so it runs
  // once the main window exists
  if not FStarted then
  begin
    FStarted := True;
    Application.QueueAsyncCall(@StartUp, 0);
  end;
end;

procedure TMainWindow.TapeSettingsChanged(Sender: TObject);
begin
  UpdateChecks;
end;

procedure TMainWindow.StartUp(Data: PtrInt);
var
  OldScale: Integer;
begin
  OldScale := Settings.Scale;
  ProcessCommandLine;
  if Settings.Scale <> OldScale then SetScale(Settings.Scale);
end;

procedure TMainWindow.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  if not ConfirmTapeChanges or not ConfirmDiskChanges(0) or not ConfirmDiskChanges(1) or
     not ConfirmCardChanges then
  begin
    CloseAction := caNone;
    Exit;
  end;
  Settings.Model := FEmu.Spec.Model;
  StoreZXUnoBios;
  if Settings.SaveOnExit then Settings.Save;
end;

{ The ZX-Uno's files and saved BIOS settings to the machine; Reload: start
  it again with them (if it is the ZX-Uno) }
procedure TMainWindow.ApplyZXUnoFiles(Reload: Boolean);
var
  Err: string;
begin
  Err := '';
  FEmu.Lock;
  try
    FEmu.Spec.ZXUnoFirmware := ZXUnoFirmwareFile;
    FEmu.Spec.ZXUnoRoms := ZXUnoRomsFile;
    FEmu.Spec.ZXUnoCustomRom := Settings.ZXUnoCustomRom;
    FEmu.Spec.ZXUnoEsxdos := DivMMCFirmwareFile;
    if not FEmu.Spec.ZXUnoBiosChanged then FEmu.Spec.ZXUnoBiosSettings := Settings.ZXUnoBios;
    if Reload and (FEmu.Spec.Model = smZXUno) then
      try
        FEmu.Spec.SetModel(smZXUno);
      except
        on E: Exception do Err := E.Message;
      end;
  finally
    FEmu.Unlock;
  end;
  if Err <> '' then MessageDlg('ZX-Uno: ' + Err, mtError, [mbOK], 0);
end;

{ What the ZX-Uno's BIOS saved in its flash goes into the settings }
procedure TMainWindow.StoreZXUnoBios;
begin
  if FEmu.Spec.ZXUnoBiosChanged then Settings.ZXUnoBios := FEmu.Spec.ZXUnoBiosSettings;
end;

{ Files }

procedure TMainWindow.OpenFile(const FileName: string; AutoStart: Boolean);
var
  Ext: string;
  Disk: TDiskImage;
begin
  Ext := LowerCase(ExtractFileExt(FileName));
  FEmu.Lock;
  try
    try
      if Ext = '.tap' then
      begin
        FEmu.Spec.Tape.LoadTAP(FileName);
        if AutoStart then FEmu.Spec.AutoLoad;
      end
      else if Ext = '.sna' then
        LoadSNA(FEmu.Spec, FileName)
      else if Ext = '.z80' then
        LoadZ80(FEmu.Spec, FileName)
      else if Ext = '.dsk' then
      begin
        Disk := TDiskImage.Create;
        try
          Disk.LoadFromFile(FileName);
        except
          Disk.Free;
          raise;
        end;
        if not FEmu.Spec.Info.HasFDC then FEmu.Spec.SetModel(smPlus3);
        FEmu.Spec.FDC.InsertDisk(0, Disk);
        Settings.AddRecentDisk(FileName);
        if AutoStart then FEmu.Spec.AutoLoad;
      end
      else
        raise Exception.Create('Unsupported file type: ' + Ext);
    except
      on E: Exception do
      begin
        FEmu.Unlock;
        try
          MessageDlg('Could not open ' + ExtractFileName(FileName) + ':' + LineEnding + E.Message,
            mtError, [mbOK], 0);
        finally
          FEmu.Lock;
        end;
        Exit;
      end;
    end;
  finally
    FEmu.Unlock;
  end;
  Settings.AddRecent(FileName);
  FLastFile := FileName;
  NoteMediaFile(FileName);
  UpdateRecentMenu;
  UpdateRecentDisksMenu;
  UpdateChecks;
  Caption := 'pzx - ' + ExtractFileName(FileName);
  if TapeBrowserWindow <> nil then TapeBrowserWindow.Refresh(True);
end;

procedure TMainWindow.DoOpen(Sender: TObject);
var
  Dlg: TOpenDialog;
begin
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Filter := OPEN_FILTER;
    Dlg.InitialDir := Settings.LastDir;
    Dlg.Options := Dlg.Options + [ofFileMustExist];
    if Dlg.Execute then OpenFile(Dlg.FileName);
  finally
    Dlg.Free;
  end;
end;

procedure TMainWindow.DoOpenRecent(Sender: TObject);
var
  Index: Integer;
begin
  Index := (Sender as TComponent).Tag;
  if Index < Settings.RecentFiles.Count then OpenFile(Settings.RecentFiles[Index]);
end;

procedure TMainWindow.DoSaveSnapshot(Sender: TObject);
var
  Dlg: TSaveDialog;
begin
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := 'Z80 snapshot (*.z80)|*.z80|SNA snapshot (*.sna)|*.sna';
    Dlg.DefaultExt := 'z80';
    Dlg.InitialDir := Settings.LastDir;
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    if not Dlg.Execute then Exit;
    FEmu.Lock;
    try
      if LowerCase(ExtractFileExt(Dlg.FileName)) = '.sna' then
        SaveSNA(FEmu.Spec, Dlg.FileName)
      else
        SaveZ80(FEmu.Spec, Dlg.FileName);
    finally
      FEmu.Unlock;
    end;
    Settings.AddRecent(Dlg.FileName);
    UpdateRecentMenu;
  finally
    Dlg.Free;
  end;
end;

procedure TMainWindow.DoQuit(Sender: TObject);
begin
  Close;
end;

{ Machine }

procedure TMainWindow.ChangeModel(M: TSpectrumModel);
begin
  FEmu.Lock;
  try
    if FEmu.Spec.Model <> M then
    begin
      try
        FEmu.Spec.SetModel(M);
      except
        on E: Exception do
          MessageDlg(E.Message, mtError, [mbOK], 0);
      end;
    end;
  finally
    FEmu.Unlock;
  end;
  Settings.Model := FEmu.Spec.Model;
  // Leaving the ZX-Uno (its own DivMMC): as Settings say again
  ApplyDivMMC;
  UpdateChecks;
end;

procedure TMainWindow.DoModel(Sender: TObject);
begin
  ChangeModel(TSpectrumModel((Sender as TComponent).Tag));
end;

procedure TMainWindow.DoModelButton(Sender: TObject);
var
  P: TPoint;
begin
  P := FModelButton.ClientToScreen(Point(0, FModelButton.Height));
  FModelMenu.PopUp(P.X, P.Y);
end;

procedure TMainWindow.DoReset(Sender: TObject);
begin
  FEmu.Lock;
  try
    FEmu.Spec.Reset(False);
  finally
    FEmu.Unlock;
  end;
end;

procedure TMainWindow.DoHardReset(Sender: TObject);
begin
  FEmu.Lock;
  try
    FEmu.Spec.Reset(True);
  finally
    FEmu.Unlock;
  end;
end;

procedure TMainWindow.DoNMI(Sender: TObject);
begin
  FEmu.Lock;
  try
    FEmu.Spec.RequestNMI;
  finally
    FEmu.Unlock;
  end;
end;

procedure TMainWindow.DoPause(Sender: TObject);
begin
  FEmu.Paused := not FEmu.Paused;
  UpdateChecks;
end;

procedure TMainWindow.DoTurbo(Sender: TObject);
begin
  FEmu.Turbo := not FEmu.Turbo;
  UpdateChecks;
end;

{ Tape }

procedure TMainWindow.DoTapeBrowser(Sender: TObject);
begin
  ShowTapeBrowser(FEmu);
end;

procedure TMainWindow.DoTapePlay(Sender: TObject);
begin
  FEmu.Lock;
  try
    FEmu.Spec.Tape.Play(FEmu.Spec.Cpu.T);
  finally
    FEmu.Unlock;
  end;
end;

procedure TMainWindow.DoTapeStop(Sender: TObject);
begin
  FEmu.Lock;
  try
    FEmu.Spec.Tape.Stop;
  finally
    FEmu.Unlock;
  end;
end;

procedure TMainWindow.DoTapeRewind(Sender: TObject);
begin
  FEmu.Lock;
  try
    FEmu.Spec.Tape.Rewind;
  finally
    FEmu.Unlock;
  end;
end;

procedure TMainWindow.DoTapeEject(Sender: TObject);
begin
  FEmu.Lock;
  try
    FEmu.Spec.Tape.Clear;
  finally
    FEmu.Unlock;
  end;
end;

procedure TMainWindow.DoTapeRecord(Sender: TObject);
begin
  FEmu.Lock;
  try
    FEmu.Spec.Recording := not FEmu.Spec.Recording;
  finally
    FEmu.Unlock;
  end;
  UpdateChecks;
  if TapeBrowserWindow <> nil then TapeBrowserWindow.Refresh(True);
end;

procedure TMainWindow.DoTapeSave(Sender: TObject);
var
  Dlg: TSaveDialog;
begin
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := 'Tape images (*.tap)|*.tap';
    Dlg.DefaultExt := 'tap';
    Dlg.InitialDir := Settings.LastDir;
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
end;

procedure TMainWindow.DoFastLoad(Sender: TObject);
begin
  Settings.FastLoad := not Settings.FastLoad;
  ApplySettings;
  UpdateChecks;
end;

procedure TMainWindow.DoAutoPlay(Sender: TObject);
begin
  Settings.AutoPlayTape := not Settings.AutoPlayTape;
  ApplySettings;
  UpdateChecks;
end;

{ Disk }

function TMainWindow.ConfirmDiskChanges(Drive: Integer): Boolean;
var
  Disk: TDiskImage;
  Answer: Integer;
  Dlg: TSaveDialog;
begin
  Result := True;
  FEmu.Lock;
  try
    Disk := FEmu.Spec.FDC.Disk(Drive);
    if (Disk = nil) or not Disk.Modified then Exit;
  finally
    FEmu.Unlock;
  end;
  Answer := MessageDlg(Format('Disk %s: has been modified. Save changes?', [Chr(Ord('A') + Drive)]),
    mtConfirmation, [mbYes, mbNo, mbCancel], 0);
  if Answer = mrCancel then Exit(False);
  if Answer = mrNo then Exit;
  if Disk.FileName <> '' then
  begin
    FEmu.Lock;
    try
      Disk.SaveToFile(Disk.FileName);
    finally
      FEmu.Unlock;
    end;
    Exit;
  end;
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := '+3 disk images (*.dsk)|*.dsk';
    Dlg.DefaultExt := 'dsk';
    Dlg.InitialDir := Settings.LastDir;
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    if not Dlg.Execute then Exit(False);
    FEmu.Lock;
    try
      Disk.SaveToFile(Dlg.FileName);
    finally
      FEmu.Unlock;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TMainWindow.DoDiskInsert(Sender: TObject);
var
  Dlg: TOpenDialog;
  Drive: Integer;
begin
  Drive := (Sender as TComponent).Tag;
  if not ConfirmDiskChanges(Drive) then Exit;
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Filter := '+3 disk images (*.dsk)|*.dsk|All files|*.*';
    Dlg.InitialDir := Settings.LastDir;
    Dlg.Options := Dlg.Options + [ofFileMustExist];
    if Dlg.Execute then InsertDiskFile(Drive, Dlg.FileName);
  finally
    Dlg.Free;
  end;
end;

function TMainWindow.InsertDiskFile(Drive: Integer; const FileName: string): Boolean;
var
  Disk: TDiskImage;
begin
  Result := False;
  Disk := TDiskImage.Create;
  try
    Disk.LoadFromFile(FileName);
  except
    on E: Exception do
    begin
      Disk.Free;
      MessageDlg(E.Message, mtError, [mbOK], 0);
      Exit;
    end;
  end;
  FEmu.Lock;
  try
    FEmu.Spec.FDC.InsertDisk(Drive, Disk);
  finally
    FEmu.Unlock;
  end;
  Settings.AddRecent(FileName);
  Settings.AddRecentDisk(FileName);
  NoteMediaFile(FileName);
  UpdateRecentMenu;
  UpdateRecentDisksMenu;
  if not FEmu.Spec.Info.HasFDC then
    MessageDlg('The disk is inserted, but only the +3 has a disk drive. ' +
      'Switch to the +3 model to use it.', mtInformation, [mbOK], 0);
  if DiskBrowserWindow <> nil then DiskBrowserWindow.Refresh;
  Result := True;
end;

{ The Disk and SD menus' lists of recent images }
procedure TMainWindow.NoteMediaFile(const FileName: string);
begin
  FEmu.Lock;
  try
    FEmu.Spec.LastMediaFile := ExtractFileName(FileName);
  finally
    FEmu.Unlock;
  end;
end;

procedure TMainWindow.AddDriveBItem(Item: TMenuItem);
begin
  SetLength(FDriveBItems, Length(FDriveBItems) + 1);
  FDriveBItems[High(FDriveBItems)] := Item;
end;

procedure TMainWindow.UpdateRecentDisksMenu;
var
  I, D: Integer;
  Item, Sub: TMenuItem;
begin
  // Both drives share the list; the tag says the drive (1000 for B) and entry
  for D := 0 to 1 do
  begin
    if D = 0 then Sub := FRecentDisksMenu else Sub := FRecentDisksMenuB;
    Sub.Clear;
    for I := 0 to Settings.RecentDisks.Count - 1 do
    begin
      Item := AddItem(Sub, Format('&%d %s', [I + 1, Settings.RecentDisks[I]]), @DoInsertRecentDisk);
      Item.Tag := D * 1000 + I;
    end;
    Sub.Enabled := Settings.RecentDisks.Count > 0;
  end;
  FRecentCardsMenu.Clear;
  for I := 0 to Settings.RecentCards.Count - 1 do
  begin
    Item := AddItem(FRecentCardsMenu, Format('&%d %s', [I + 1, Settings.RecentCards[I]]),
      @DoInsertRecentCard);
    Item.Tag := I;
  end;
  FRecentCardsMenu.Enabled := Settings.RecentCards.Count > 0;
end;

procedure TMainWindow.DoInsertRecentDisk(Sender: TObject);
var
  Index, Drive: Integer;
begin
  Drive := (Sender as TComponent).Tag div 1000;
  Index := (Sender as TComponent).Tag mod 1000;
  if (Index < Settings.RecentDisks.Count) and ConfirmDiskChanges(Drive) then
    InsertDiskFile(Drive, Settings.RecentDisks[Index]);
end;

procedure TMainWindow.DoInsertRecentCard(Sender: TObject);
var
  Index: Integer;
begin
  Index := (Sender as TComponent).Tag;
  if Index < Settings.RecentCards.Count then InsertSDCard(Settings.RecentCards[Index]);
end;

procedure TMainWindow.DoDiskBrowser(Sender: TObject);
begin
  // A: if it has a disk, otherwise B:
  ShowDiskBrowser(FEmu);
end;

procedure TMainWindow.DoSDBrowser(Sender: TObject);
begin
  if FEmu.Spec.DivMMCOn and (FEmu.Spec.DivMMC.Card <> nil) then ShowSDBrowser(FEmu);
end;

procedure TMainWindow.DoSDInsert(Sender: TObject);
var
  Dlg: TOpenDialog;
begin
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Filter := 'SD card images (*.img;*.mmc;*.hdf;*.bin)|*.img;*.mmc;*.hdf;*.bin|All files|*.*';
    Dlg.InitialDir := Settings.LastDir;
    Dlg.Options := Dlg.Options + [ofFileMustExist];
    if Dlg.Execute then InsertSDCard(Dlg.FileName);
  finally
    Dlg.Free;
  end;
end;

{ Size of a new card, in MB }
function AskCardSize(WithEsxdos: Boolean; out SizeMB: Integer): Boolean;
const
  SIZES: array[0..7] of Integer = (16, 32, 64, 128, 256, 512, 1024, 2048);
var
  Dlg: TForm;
  Combo: TComboBox;
  Lbl: TLabel;
  Btn: TButton;
  I: Integer;
begin
  Result := False;
  Dlg := TForm.CreateNew(nil, 0);
  try
    if WithEsxdos then Dlg.Caption := 'New SD card with ESXDOS' else Dlg.Caption := 'New SD card';
    Dlg.BorderStyle := bsDialog;
    Dlg.Position := poMainFormCenter;
    Dlg.ClientWidth := 360;
    Dlg.ClientHeight := 130;
    Lbl := TLabel.Create(Dlg);
    Lbl.Parent := Dlg;
    Lbl.Caption := 'Size (FAT16):';
    Lbl.SetBounds(10, 16, 120, 18);
    Combo := TComboBox.Create(Dlg);
    Combo.Parent := Dlg;
    Combo.Style := csDropDownList;
    Combo.SetBounds(140, 12, 120, 24);
    for I := 0 to High(SIZES) do Combo.Items.Add(Format('%d MB', [SIZES[I]]));
    Combo.ItemIndex := 3;
    Lbl := TLabel.Create(Dlg);
    Lbl.Parent := Dlg;
    if WithEsxdos then
      Lbl.Caption := 'The card gets the ESXDOS SYS, BIN and TMP folders.'
    else
      Lbl.Caption := 'An empty card with one FAT16 partition.';
    Lbl.SetBounds(10, 50, 340, 18);
    Btn := TButton.Create(Dlg);
    Btn.Parent := Dlg;
    Btn.Caption := 'OK';
    Btn.Default := True;
    Btn.ModalResult := mrOK;
    Btn.SetBounds(190, 90, 75, 28);
    Btn := TButton.Create(Dlg);
    Btn.Parent := Dlg;
    Btn.Caption := 'Cancel';
    Btn.Cancel := True;
    Btn.ModalResult := mrCancel;
    Btn.SetBounds(275, 90, 75, 28);
    if Dlg.ShowModal <> mrOK then Exit;
    SizeMB := SIZES[Combo.ItemIndex];
    Result := True;
  finally
    Dlg.Free;
  end;
end;

procedure TMainWindow.DoSDNew(Sender: TObject);
var
  WithEsxdos: Boolean;
  SizeMB: Integer;
  Dlg: TSaveDialog;
  S: TFileStream;
  Vol: TFatVolume;
  Esx, Err: string;
  Entries: TFatEntries;
begin
  WithEsxdos := (Sender as TComponent).Tag = 1;
  Esx := PzxPath('esxdos');
  if WithEsxdos and (Esx = '') then
  begin
    MessageDlg('The esxdos folder (with SYS and BIN) was not found next to pzx.', mtError, [mbOK], 0);
    Exit;
  end;
  if not AskCardSize(WithEsxdos, SizeMB) then Exit;
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := 'SD card images (*.img)|*.img';
    Dlg.DefaultExt := 'img';
    Dlg.InitialDir := Settings.LastDir;
    Dlg.FileName := 'sdcard.img';
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    if not Dlg.Execute then Exit;
    // The card being replaced may be the one in the DivMMC
    FEmu.Lock;
    try
      if (FEmu.Spec.DivMMC.Card <> nil) and SameFileName(FEmu.Spec.DivMMC.Card.FileName, Dlg.FileName) then
        FEmu.Spec.DivMMC.EjectCard;
    finally
      FEmu.Unlock;
    end;
    Err := '';
    Screen.Cursor := crHourGlass;
    try
      try
        S := TFileStream.Create(Dlg.FileName, fmCreate);
        try
          FormatCard(S, SizeMB, 'PZX SD');
          if WithEsxdos then
          begin
            Vol := TFatVolume.Create(S);
            try
              Vol.MakeDir(0, 'SYS');
              Vol.MakeDir(0, 'BIN');
              Vol.MakeDir(0, 'TMP');
              Entries := Vol.ListDir(0);
              CopyTree(Vol, Entries[0].Cluster, IncludeTrailingPathDelimiter(Esx) + 'SYS');
              CopyTree(Vol, Entries[1].Cluster, IncludeTrailingPathDelimiter(Esx) + 'BIN');
            finally
              Vol.Free;
            end;
          end;
        finally
          S.Free;
        end;
      except
        on E: Exception do Err := E.Message;
      end;
    finally
      Screen.Cursor := crDefault;
    end;
    if Err <> '' then
    begin
      MessageDlg('Could not create the SD card: ' + Err, mtError, [mbOK], 0);
      Exit;
    end;
    InsertSDCard(Dlg.FileName);
  finally
    Dlg.Free;
  end;
end;

function TMainWindow.SaveCardAs: Boolean;
var
  Dlg: TSaveDialog;
  Err: string;
begin
  Result := False;
  if FEmu.Spec.DivMMC.Card = nil then Exit;
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := 'SD card images (*.img)|*.img|All files|*.*';
    Dlg.DefaultExt := 'img';
    // Where it was loaded from
    Dlg.InitialDir := ExtractFilePath(FEmu.Spec.DivMMC.Card.FileName);
    Dlg.FileName := ExtractFileName(FEmu.Spec.DivMMC.Card.FileName);
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    if not Dlg.Execute then Exit;
    Err := '';
    FEmu.Lock;
    try
      try
        FEmu.Spec.DivMMC.Card.Save(Dlg.FileName);
        Settings.SDCardFile := FEmu.Spec.DivMMC.Card.FileName;
      except
        on E: Exception do Err := E.Message;
      end;
    finally
      FEmu.Unlock;
    end;
    if Err <> '' then
      MessageDlg('Could not save the SD card: ' + Err, mtError, [mbOK], 0)
    else
    begin
      Settings.AddRecentCard(Dlg.FileName);
      UpdateRecentDisksMenu;
      DropTempCard;   // saved as a real image: the temporary one goes
      Result := True;
    end;
  finally
    Dlg.Free;
  end;
end;

{ Save to the image's own file }
function SaveCardInPlace(Emu: TEmulator; out Err: string): Boolean;
begin
  Err := '';
  Emu.Lock;
  try
    try
      Emu.Spec.DivMMC.Card.Save;
    except
      on E: Exception do Err := E.Message;
    end;
  finally
    Emu.Unlock;
  end;
  Result := Err = '';
end;

function TMainWindow.ConfirmCardChanges: Boolean;
var
  Answer: Integer;
  Err: string;
begin
  Result := True;
  if (FEmu.Spec.DivMMC.Card = nil) or not FEmu.Spec.DivMMC.Card.Modified then Exit;
  if SameFileName(FEmu.Spec.DivMMC.Card.FileName, FTempCard) then
  begin
    // Made from a folder: the changes can only be kept as an image
    Answer := MessageDlg(Format('The SD card made from the folder %s has been modified. ' +
      'Save it as an SD card image?', [FTempFolder]), mtConfirmation, [mbYes, mbNo, mbCancel], 0);
    if Answer = mrCancel then Exit(False);
    if Answer = mrYes then Result := SaveCardAs;
    Exit;
  end;
  Answer := MessageDlg(Format('The SD card %s has been modified. Save the changes?',
    [ExtractFileName(FEmu.Spec.DivMMC.Card.FileName)]), mtConfirmation, [mbYes, mbNo, mbCancel], 0);
  if Answer = mrCancel then Exit(False);
  if Answer = mrNo then Exit;
  if FEmu.Spec.DivMMC.Card.ReadOnly then Exit(SaveCardAs);
  if not SaveCardInPlace(FEmu, Err) then
  begin
    MessageDlg('Could not save the SD card: ' + Err, mtError, [mbOK], 0);
    Result := SaveCardAs;
  end;
end;

procedure TMainWindow.DoSDSave(Sender: TObject);
var
  Err: string;
begin
  if FEmu.Spec.DivMMC.Card = nil then
  begin
    MessageDlg('There is no SD card inserted.', mtInformation, [mbOK], 0);
    Exit;
  end;
  if ((Sender as TComponent).Tag = 1) or FEmu.Spec.DivMMC.Card.ReadOnly then
    SaveCardAs
  else if not SaveCardInPlace(FEmu, Err) then
    MessageDlg('Could not save the SD card: ' + Err, mtError, [mbOK], 0);
  if SDBrowserWindow <> nil then SDBrowserWindow.Refresh;
end;

procedure TMainWindow.DoDiskSaveSame(Sender: TObject);
var
  Drive: Integer;
  Disk: TDiskImage;
  Err: string;
begin
  Drive := (Sender as TComponent).Tag;
  Disk := FEmu.Spec.FDC.Disk(Drive);
  if Disk = nil then
  begin
    MessageDlg('There is no disk in that drive.', mtInformation, [mbOK], 0);
    Exit;
  end;
  // A new disk has no file yet
  if Disk.FileName = '' then
  begin
    DoDiskSave(Sender);
    Exit;
  end;
  Err := '';
  FEmu.Lock;
  try
    try
      Disk.SaveToFile(Disk.FileName);
    except
      on E: Exception do Err := E.Message;
    end;
  finally
    FEmu.Unlock;
  end;
  if Err <> '' then MessageDlg('Could not save the disk: ' + Err, mtError, [mbOK], 0);
  if DiskBrowserWindow <> nil then DiskBrowserWindow.Refresh;
end;

procedure TMainWindow.DropTempCard;
begin
  if FTempCard = '' then Exit;
  if (FEmu.Spec.DivMMC.Card <> nil) and SameFileName(FEmu.Spec.DivMMC.Card.FileName, FTempCard) then
    Exit;
  DeleteFile(FTempCard);
  FTempCard := '';
  FTempFolder := '';
end;

function TMainWindow.UseFolderAsCard(const Folder: string): Boolean;
const
  SIZES: array[0..7] of Integer = (16, 32, 64, 128, 256, 512, 1024, 2048);
var
  Bytes, Need: Int64;
  Entries, SizeMB, I: Integer;
  Esx, TempFile, Err: string;
  S: TFileStream;
  Vol: TFatVolume;
  Dirs: TFatEntries;
begin
  Result := False;
  Esx := PzxPath('esxdos');
  if Esx = '' then
  begin
    MessageDlg('The esxdos folder (with SYS and BIN) was not found next to pzx.', mtError, [mbOK], 0);
    Exit;
  end;
  if not ConfirmCardChanges then Exit;
  // Room for the files (with some slack per file), esxDOS and some spare
  Bytes := FolderSize(Folder, Entries);
  Need := (Bytes + Int64(Entries) * 32768 + 4 * 1024 * 1024) * 5 div 4 + 8 * 1024 * 1024;
  SizeMB := 0;
  for I := 0 to High(SIZES) do
    if (SizeMB = 0) and (Int64(SIZES[I]) * 1024 * 1024 >= Need) then SizeMB := SIZES[I];
  if SizeMB = 0 then
  begin
    MessageDlg('The folder is too big for an SD card of up to 2 GB.', mtError, [mbOK], 0);
    Exit;
  end;
  TempFile := IncludeTrailingPathDelimiter(GetTempDir) +
    Format('pzx-sd-%s.img', [FormatDateTime('yyyymmddhhnnsszzz', Now)]);
  Err := '';
  Screen.Cursor := crHourGlass;
  try
    try
      S := TFileStream.Create(TempFile, fmCreate);
      try
        FormatCard(S, SizeMB, 'PZX FOLDER');
        Vol := TFatVolume.Create(S);
        try
          Vol.MakeDir(0, 'SYS');
          Vol.MakeDir(0, 'BIN');
          Vol.MakeDir(0, 'TMP');
          Dirs := Vol.ListDir(0);
          CopyTree(Vol, Dirs[0].Cluster, IncludeTrailingPathDelimiter(Esx) + 'SYS');
          CopyTree(Vol, Dirs[1].Cluster, IncludeTrailingPathDelimiter(Esx) + 'BIN');
          // The folder's files and subfolders in the root, as 8.3 names
          CopyTree(Vol, 0, Folder, True);
        finally
          Vol.Free;
        end;
      finally
        S.Free;
      end;
    except
      on E: Exception do Err := E.Message;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
  if Err <> '' then
  begin
    DeleteFile(TempFile);
    MessageDlg('Could not make the SD card from the folder: ' + Err, mtError, [mbOK], 0);
    Exit;
  end;
  // The card in the DivMMC goes out (its changes were dealt with above)
  FEmu.Lock;
  try
    FEmu.Spec.DivMMC.EjectCard;
  finally
    FEmu.Unlock;
  end;
  DropTempCard;
  if not InsertSDCard(TempFile, False) then
  begin
    DeleteFile(TempFile);
    Exit;
  end;
  FTempCard := TempFile;
  FTempFolder := Folder;
  Settings.SDCardFile := '';    // nothing to insert again next time
  // Boot again so esxDOS sees the new card
  FEmu.Lock;
  try
    FEmu.Spec.Reset(True);
  finally
    FEmu.Unlock;
  end;
  if SDBrowserWindow <> nil then SDBrowserWindow.Refresh;
  Result := True;
end;

procedure TMainWindow.DoSDFolder(Sender: TObject);
var
  Dlg: TSelectDirectoryDialog;
begin
  Dlg := TSelectDirectoryDialog.Create(Self);
  try
    Dlg.Title := 'Folder to use as the SD card';
    Dlg.InitialDir := Settings.LastDir;
    if Dlg.Execute then UseFolderAsCard(Dlg.FileName);
  finally
    Dlg.Free;
  end;
end;

procedure TMainWindow.DoSDEject(Sender: TObject);
begin
  if not ConfirmCardChanges then Exit;
  FEmu.Lock;
  try
    FEmu.Spec.DivMMC.EjectCard;
  finally
    FEmu.Unlock;
  end;
  Settings.SDCardFile := '';
  DropTempCard;
  if SDBrowserWindow <> nil then SDBrowserWindow.Refresh;
end;


procedure TMainWindow.DoDiskNew(Sender: TObject);
var
  Drive: Integer;
  Disk: TDiskImage;
begin
  Drive := (Sender as TComponent).Tag;
  if not ConfirmDiskChanges(Drive) then Exit;
  // Already formatted (+3 standard format), ready for SAVE without FORMAT
  Disk := TDiskImage.Create;
  Disk.CreatePlus3Formatted;
  FEmu.Lock;
  try
    FEmu.Spec.FDC.InsertDisk(Drive, Disk);
  finally
    FEmu.Unlock;
  end;
  if not FEmu.Spec.Info.HasFDC then
    MessageDlg('The disk is inserted, but only the +3 has a disk drive.', mtInformation, [mbOK], 0);
end;

procedure TMainWindow.DoDiskEject(Sender: TObject);
var
  Drive: Integer;
begin
  Drive := (Sender as TComponent).Tag;
  if not ConfirmDiskChanges(Drive) then Exit;
  FEmu.Lock;
  try
    FEmu.Spec.FDC.EjectDisk(Drive).Free;
  finally
    FEmu.Unlock;
  end;
end;

procedure TMainWindow.DoDiskSave(Sender: TObject);
var
  Dlg: TSaveDialog;
  Drive: Integer;
begin
  Drive := (Sender as TComponent).Tag;
  if FEmu.Spec.FDC.Disk(Drive) = nil then
  begin
    MessageDlg('There is no disk in that drive.', mtInformation, [mbOK], 0);
    Exit;
  end;
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := '+3 disk images (*.dsk)|*.dsk';
    Dlg.DefaultExt := 'dsk';
    // Where it was loaded from, if it was
    if FEmu.Spec.FDC.Disk(Drive).FileName <> '' then
    begin
      Dlg.InitialDir := ExtractFilePath(FEmu.Spec.FDC.Disk(Drive).FileName);
      Dlg.FileName := ExtractFileName(FEmu.Spec.FDC.Disk(Drive).FileName);
    end
    else
      Dlg.InitialDir := Settings.LastDir;
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    if not Dlg.Execute then Exit;
    FEmu.Lock;
    try
      FEmu.Spec.FDC.Disk(Drive).SaveToFile(Dlg.FileName);
    finally
      FEmu.Unlock;
    end;
  finally
    Dlg.Free;
  end;
end;

{ Options }

procedure TMainWindow.DoMute(Sender: TObject);
begin
  Settings.Sound := not Settings.Sound;
  ApplySettings;
  UpdateChecks;
end;


procedure TMainWindow.DoMonochrome(Sender: TObject);
begin
  Settings.Monochrome := not Settings.Monochrome;
  UpdateChecks;
  RenderBitmap;
  FDisplay.Invalidate;
end;

procedure TMainWindow.DoDocumentation(Sender: TObject);
begin
  ShowDocumentation;
end;



{ Kempston mouse: PC mouse movement over the picture, one Spectrum pixel per
  zoomed pixel. X and Y are 8-bit counters that wrap; Y grows upwards. }
procedure TMainWindow.DisplayMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  Scale, DX, DY: Integer;
begin
  if not Settings.KempstonMouse then Exit;
  if FMouseHave then
  begin
    Scale := DisplayScale;
    DX := X - FMouseLast.X + FMouseRemX;
    DY := Y - FMouseLast.Y + FMouseRemY;
    FMouseRemX := DX mod Scale;
    FMouseRemY := DY mod Scale;
    FEmu.Spec.MouseX := Byte(FEmu.Spec.MouseX + DX div Scale);
    FEmu.Spec.MouseY := Byte(FEmu.Spec.MouseY - DY div Scale);
  end;
  FMouseLast := Point(X, Y);
  FMouseHave := True;
end;

function MouseBit(Button: TMouseButton): Byte;
begin
  case Button of
    mbRight: Result := 1;
    mbLeft: Result := 2;
    mbMiddle: Result := 4;
  else
    Result := 0;
  end;
end;

procedure TMainWindow.DisplayMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if Settings.KempstonMouse then
    FEmu.Spec.MouseButtons := FEmu.Spec.MouseButtons and not MouseBit(Button);
end;

procedure TMainWindow.DisplayMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if Settings.KempstonMouse then
    FEmu.Spec.MouseButtons := FEmu.Spec.MouseButtons or MouseBit(Button);
end;

procedure TMainWindow.DisplayMouseLeave(Sender: TObject);
begin
  FMouseHave := False;
  FEmu.Spec.MouseButtons := $FF;
end;




procedure TMainWindow.ApplyPokes(const Pokes: TPokeList);
var
  I, Rom: Integer;
begin
  Rom := 0;
  FEmu.Lock;
  try
    for I := 0 to High(Pokes) do
    begin
      case FEmu.Spec.MemoryAt(Pokes[I].Addr) of
        maNone: Inc(Rom);
        maRom: if not Settings.AllowRomEdit then Inc(Rom);
      end;
      FEmu.Spec.Poke(Pokes[I].Addr, Pokes[I].Value);
    end;
  finally
    FEmu.Unlock;
  end;
  if Rom > 0 then
    MessageDlg(Format('%d POKE(s) went to ROM (or to no memory) and had no effect.', [Rom]) +
      LineEnding + 'ROM changes can be allowed in Options > Settings.', mtWarning, [mbOK], 0);
end;

procedure TMainWindow.DoPoke(Sender: TObject);
begin
  ReleaseAllKeys;
  ShowPokeDialog(FLastFile, @ApplyPokes);
  Settings.Save;
end;

function TMainWindow.ConfirmTapeChanges: Boolean;
var
  Answer: Integer;
begin
  Result := True;
  if not FEmu.Spec.Tape.Modified or (FEmu.Spec.Tape.Count = 0) then Exit;
  Answer := MessageDlg('The tape has changed (blocks saved, moved or deleted). Save it?',
    mtConfirmation, [mbYes, mbNo, mbCancel], 0);
  if Answer = mrCancel then Exit(False);
  if Answer = mrYes then
  begin
    DoTapeSave(nil);
    Result := not FEmu.Spec.Tape.Modified;
  end;
end;

procedure TMainWindow.DoNewTape(Sender: TObject);
begin
  if not ConfirmTapeChanges then Exit;
  FEmu.Lock;
  try
    FEmu.Spec.Tape.Clear;
  finally
    FEmu.Unlock;
  end;
  if TapeBrowserWindow <> nil then TapeBrowserWindow.Refresh(True);
end;

procedure TMainWindow.DoSaveToTape(Sender: TObject);
begin
  Settings.SaveToTape := not Settings.SaveToTape;
  ApplySettings;
  UpdateChecks;
end;

procedure TMainWindow.DoFastDisk(Sender: TObject);
begin
  Settings.FastDisk := not Settings.FastDisk;
  ApplySettings;
  UpdateChecks;
end;

procedure TMainWindow.DoDriveB(Sender: TObject);
begin
  Settings.DriveB := not Settings.DriveB;
  ApplySettings;
  UpdateChecks;
end;

procedure TMainWindow.DoScreenshotBorder(Sender: TObject);
begin
  Settings.ScreenshotBorder := not Settings.ScreenshotBorder;
  UpdateChecks;
end;

procedure TMainWindow.DoScreenshotSCR(Sender: TObject);
var
  Dlg: TSaveDialog;
begin
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := 'Spectrum screen (*.scr)|*.scr';
    Dlg.DefaultExt := 'scr';
    Dlg.InitialDir := Settings.LastDir;
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    if not Dlg.Execute then Exit;
    FEmu.Lock;
    try
      SaveSCR(FEmu.Spec, Dlg.FileName);
    finally
      FEmu.Unlock;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TMainWindow.DoScreenshotPNG(Sender: TObject);
var
  Dlg: TSaveDialog;
  Pixels: array of LongWord;
begin
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := 'PNG image (*.png)|*.png';
    Dlg.DefaultExt := 'png';
    Dlg.InitialDir := Settings.LastDir;
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    if not Dlg.Execute then Exit;
    SetLength(Pixels, FB_WIDTH * SCREEN_HEIGHT);
    FEmu.CopyDisplay(@Pixels[0]);
    SavePNG(Pixels, Dlg.FileName, (Sender as TComponent).Tag, Settings.ScreenshotBorder);
  finally
    Dlg.Free;
  end;
end;

procedure TMainWindow.DoScale(Sender: TObject);
begin
  SetScale((Sender as TComponent).Tag);
  UpdateChecks;
end;

procedure TMainWindow.DoSettings(Sender: TObject);
var
  OldRomDir, OldUno: string;
begin
  OldRomDir := Settings.RomDir;
  OldUno := Settings.ZXUnoFirmware + '|' + Settings.ZXUnoRoms + '|' + Settings.ZXUnoCustomRom;
  FirmwareChanged := False;
  StoreZXUnoBios;
  if not ShowSettings then Exit;
  // Other ZX-Uno BIOS, ROMs or custom ROM: switch it off and on with them
  if Settings.ZXUnoFirmware + '|' + Settings.ZXUnoRoms + '|' + Settings.ZXUnoCustomRom <> OldUno then
    ApplyZXUnoFiles(FEmu.Spec.Model = smZXUno);
  // Another firmware: switch the DivMMC off and on to load it
  if FirmwareChanged and Settings.DivMMC and FEmu.Spec.DivMMCOn then
  begin
    Settings.DivMMC := False;
    ApplyDivMMC;
    Settings.DivMMC := True;
  end;
  if Settings.RomDir <> OldRomDir then
  begin
    FEmu.Lock;
    try
      FEmu.Spec.RomDir := Settings.RomDir;
      try
        FEmu.Spec.SetModel(FEmu.Spec.Model);
      except
        on E: Exception do
        begin
          MessageDlg(E.Message + LineEnding + 'Keeping the previous ROM folder.', mtError, [mbOK], 0);
          Settings.RomDir := OldRomDir;
          FEmu.Spec.RomDir := OldRomDir;
          FEmu.Spec.SetModel(FEmu.Spec.Model);
        end;
      end;
    finally
      FEmu.Unlock;
    end;
  end;
  if Settings.Model <> FEmu.Spec.Model then ChangeModel(Settings.Model);
  ApplySettings;
  SetScale(Settings.Scale);
  UpdateChecks;
  RenderBitmap;    // black and white may have changed
  FDisplay.Invalidate;
  Settings.Save;
end;

procedure TMainWindow.DoDaadDebugger(Sender: TObject);
begin
  ShowDaadDebugger(FEmu);
  UpdateChecks;
end;

procedure TMainWindow.DoDebugger(Sender: TObject);
begin
  ShowDebugger(FEmu);
  UpdateChecks;
end;

{ Command line: see README.TXT. Options may start with - or -- and
  take their value as the next argument or after "=". }
procedure TMainWindow.ProcessCommandLine;
type
  TBreakArg = record
    Text: string;
    Flags: Byte;
    Port: Boolean;
  end;
var
  I, N, Speed: Integer;
  Arg, Value, Errors, Err: string;
  Files, Tapes, KeyTexts: TStringList;
  Disks: array[0..1] of string;
  Breaks: array of TBreakArg;
  BreakFile, WatchFile, DaadBreakFile: string;   // JSON files to load
  Watches: TWordArray;
  SymFiles: TStringList;
  M: TSpectrumModel;
  J: TJoystickKeys;
  HaveModel, Help, BoolValue, TurboSet, TurboValue, FirmwareSet: Boolean;
  BoolTarget: PBoolean;
  Boot, RomIndex: Integer;
  RomDirArg, BoolName: string;
  Parts: TStringArray;
  SDFile: string;
  SDAdds: TStringList;
  SDFolder: string;
  NewModel: TSpectrumModel;
  ForcedBefore: array[0..3] of Boolean;
  UnoSet: Boolean;
  Addr: Word;
  Disk: TDiskImage;

  function NeedsValue(const Name: string): Boolean;
  begin
    Result := (Name = 'model') or (Name = 'speed') or (Name = 'scale') or (Name = 'tape') or
      (Name = 'disk') or (Name = 'diska') or (Name = 'diskb') or (Name = 'sym') or (Name = 's') or
      (Name = 'bp') or (Name = 'bpr') or (Name = 'bpw') or (Name = 'bprw') or (Name = 'bpa') or
      (Name = 'bpin') or (Name = 'bpout') or (Name = 'bpio') or (Name = 'keyin') or
      (Name = 'config') or (Name = 'config-add') or (Name = 'joystick') or (Name = 'sdcard') or
      (Name = 'sdadd') or (Name = 'sdfolder') or (Name = 'volume') or (Name = 'issue') or
      (Name = 'romdir') or (Name = 'rom') or (Name = 'divmmcrom') or
      (Name = 'zxunofirmware') or (Name = 'zxunoroms') or (Name = 'zxunocustomrom') or
      (Name = 'shiftkeys') or (Name = 'breakpoints') or (Name = 'watches') or
      (Name = 'daadbreakpoints');
  end;

  { On/off options, one per setting: --name turns it on, --no-name off }
  function BoolSetting(const Name: string): PBoolean;
  begin
    Result := Settings.BoolField(Name);
  end;

  procedure AddBreak(const Text: string; Flags: Byte; Port: Boolean = False);
  begin
    SetLength(Breaks, Length(Breaks) + 1);
    Breaks[High(Breaks)].Text := Text;
    Breaks[High(Breaks)].Flags := Flags;
    Breaks[High(Breaks)].Port := Port;
  end;

  procedure InsertDisk(Drive: Integer; const FileName: string);
  begin
    Disk := TDiskImage.Create;
    try
      Disk.LoadFromFile(FileName);
    except
      on E: Exception do
      begin
        Disk.Free;
        Errors := Errors + FileName + ': ' + E.Message + LineEnding;
        Exit;
      end;
    end;
    FEmu.Lock;
    try
      if not FEmu.Spec.Info.HasFDC and not HaveModel then FEmu.Spec.SetModel(smPlus3);
      FEmu.Spec.FDC.InsertDisk(Drive, Disk);
    finally
      FEmu.Unlock;
    end;
    Settings.AddRecentDisk(ExpandFileName(FileName));
    NoteMediaFile(FileName);
  end;

begin
  Errors := '';
  RomDirArg := '';
  TurboSet := False;
  TurboValue := False;
  FirmwareSet := False;
  SDFile := '';
  SDFolder := '';
  HaveModel := False;
  Help := False;
  Speed := 0;
  NewModel := FEmu.Spec.Model;
  UnoSet := False;
  ForcedBefore[0] := Settings.DivMMC;
  ForcedBefore[1] := Settings.Timex;
  ForcedBefore[2] := Settings.Radastan;
  ForcedBefore[3] := Settings.ULAPlus;
  Disks[0] := '';
  Disks[1] := '';
  Breaks := nil;
  BreakFile := '';
  WatchFile := '';
  DaadBreakFile := '';
  Files := TStringList.Create;
  Tapes := TStringList.Create;
  SDAdds := TStringList.Create;
  KeyTexts := TStringList.Create;
  SymFiles := TStringList.Create;
  try
    I := 1;
    while I <= ParamCount do
    begin
      Arg := ParamStr(I);
      Inc(I);
      if (Arg = '') or (Arg[1] <> '-') then
      begin
        Files.Add(Arg);
        Continue;
      end;
      Value := '';
      N := Pos('=', Arg);
      if N > 0 then
      begin
        Value := Copy(Arg, N + 1, MaxInt);
        Arg := Copy(Arg, 1, N - 1);
      end;
      while (Arg <> '') and (Arg[1] = '-') do Delete(Arg, 1, 1);
      Arg := LowerCase(Arg);
      if NeedsValue(Arg) and (N = 0) then
      begin
        if I > ParamCount then
        begin
          Errors := Errors + '-' + Arg + ' needs a value' + LineEnding;
          Break;
        end;
        Value := ParamStr(I);
        Inc(I);
      end;
      // On/off options: --name, --no-name
      BoolValue := Copy(Arg, 1, 3) <> 'no-';
      if BoolValue then BoolName := Arg else BoolName := Copy(Arg, 4, MaxInt);
      BoolTarget := BoolSetting(BoolName);
      if BoolTarget <> nil then
      begin
        BoolTarget^ := BoolValue;
        Continue;
      end;
      if BoolName = 'mute' then
      begin
        Settings.Sound := not BoolValue;
        Continue;
      end;
      if BoolName = 'turbo' then
      begin
        TurboSet := True;
        TurboValue := BoolValue;
        Continue;
      end;
      if Arg = 'model' then
      begin
        Value := LowerCase(StringReplace(Value, '+', 'plus', [rfReplaceAll]));
        HaveModel := False;
        for M := Low(TSpectrumModel) to High(TSpectrumModel) do
          if (Value = ModelKey(M)) or (Value = ModelKey(M) + 'k') then
          begin
            NewModel := M;
            HaveModel := True;
          end;
        if not HaveModel then Errors := Errors + 'Unknown model: ' + Value + LineEnding;
      end
      else if Arg = 'speed' then
      begin
        Speed := StrToIntDef(Value, 0);
        if not (Speed in [1, 2, 4, 8, 16, 32]) then
        begin
          Errors := Errors + 'Speed must be 1, 2, 4, 8, 16 or 32' + LineEnding;
          Speed := 0;
        end;
      end
      else if Arg = 'scale' then
      begin
        N := StrToIntDef(Value, 0);
        if (N >= 1) and (N <= 4) then Settings.Scale := N
        else Errors := Errors + 'Scale must be 1 to 4' + LineEnding;
      end
      else if Arg = 'tape' then Tapes.Add(Value)
      else if (Arg = 'disk') or (Arg = 'diska') then Disks[0] := Value
      else if Arg = 'diskb' then
      begin
        Disks[1] := Value;
        Settings.DriveB := True;   // a disk for B connects the drive
      end
      else if (Arg = 'sym') or (Arg = 's') then SymFiles.Add(Value)
      else if Arg = 'breakpoints' then BreakFile := Value
      else if Arg = 'watches' then WatchFile := Value
      else if Arg = 'daadbreakpoints' then DaadBreakFile := Value
      else if Arg = 'bp' then AddBreak(Value, BP_EXEC)
      else if Arg = 'bpr' then AddBreak(Value, BP_READ)
      else if Arg = 'bpw' then AddBreak(Value, BP_WRITE)
      else if (Arg = 'bprw') or (Arg = 'bpa') then AddBreak(Value, BP_READ or BP_WRITE)
      else if Arg = 'bpin' then AddBreak(Value, BP_READ, True)
      else if Arg = 'bpout' then AddBreak(Value, BP_WRITE, True)
      else if Arg = 'bpio' then AddBreak(Value, BP_READ or BP_WRITE, True)
      else if Arg = 'keyin' then KeyTexts.Add(Value)
      else if Arg = 'volume' then
      begin
        N := StrToIntDef(Value, -1);
        if (N >= 0) and (N <= 100) then Settings.Volume := N
        else Errors := Errors + 'Volume must be 0 to 100' + LineEnding;
      end
      else if Arg = 'issue' then
      begin
        if Value = '2' then Settings.Issue2 := True
        else if Value = '3' then Settings.Issue2 := False
        else Errors := Errors + 'Keyboard issue must be 2 or 3' + LineEnding;
      end
      else if Arg = 'romdir' then
      begin
        if DirectoryExists(Value) then RomDirArg := ExpandFileName(Value)
        else Errors := Errors + 'ROM folder not found: ' + Value + LineEnding;
      end
      else if Arg = 'rom' then
      begin
        // "MODEL,N,FILE": ROM N of a model; an empty FILE means the standard one
        Parts := Value.Split([','], 3);
        RomIndex := -1;
        if Length(Parts) = 3 then
        begin
          Parts[0] := LowerCase(StringReplace(Trim(Parts[0]), '+', 'plus', [rfReplaceAll]));
          for M := Low(TSpectrumModel) to High(TSpectrumModel) do
            if (Parts[0] = ModelKey(M)) or (Parts[0] = ModelKey(M) + 'k') then
            begin
              RomIndex := StrToIntDef(Trim(Parts[1]), -1);
              if (RomIndex >= 0) and (RomIndex < ModelInfo[M].RomCount) and
                 ((Trim(Parts[2]) = '') or FileExists(Trim(Parts[2]))) then
              begin
                if Trim(Parts[2]) = '' then Settings.RomFiles[M, RomIndex] := ''
                else Settings.RomFiles[M, RomIndex] := ExpandFileName(Trim(Parts[2]));
              end
              else
                RomIndex := -1;
            end;
        end;
        if RomIndex < 0 then
          Errors := Errors + '--rom "' + Value + '": expected MODEL,N,FILE (an existing file, ' +
            'N one of the model''s ROMs)' + LineEnding;
      end
      else if Arg = 'shiftkeys' then
      begin
        Value := LowerCase(Value);
        if Value = 'standard' then Settings.ShiftSides := False
        else if Value = 'sides' then Settings.ShiftSides := True
        else Errors := Errors + 'Unknown --shiftkeys (standard or sides): ' + Value + LineEnding;
      end
      else if (Arg = 'zxunofirmware') or (Arg = 'zxunoroms') or (Arg = 'zxunocustomrom') then
      begin
        if (Value = '') or FileExists(Value) then
        begin
          if Value <> '' then Value := ExpandFileName(Value);
          if Arg = 'zxunofirmware' then Settings.ZXUnoFirmware := Value
          else if Arg = 'zxunoroms' then Settings.ZXUnoRoms := Value
          else Settings.ZXUnoCustomRom := Value;
          UnoSet := True;
        end
        else
          Errors := Errors + 'File not found: ' + Value + LineEnding;
      end
      else if Arg = 'divmmcrom' then
      begin
        if (Value = '') or FileExists(Value) then
        begin
          if Value <> '' then Value := ExpandFileName(Value);
          FirmwareSet := Value <> Settings.DivMMCFirmware;
          Settings.DivMMCFirmware := Value;
        end
        else
          Errors := Errors + 'DivMMC firmware not found: ' + Value + LineEnding;
      end
      else if Arg = 'sdcard' then SDFile := Value
      else if Arg = 'sdadd' then SDAdds.Add(Value)
      else if Arg = 'sdfolder' then SDFolder := Value
      else if Arg = 'joystick' then
      begin
        Value := LowerCase(Value);
        if Value = 'sinclair' then Value := 'sinclair1'
        else if Value = 'protek' then Value := 'cursor';
        N := -1;
        for J := Low(TJoystickKeys) to High(TJoystickKeys) do
          if Value = JOYSTICK_KEYS[J] then
          begin
            Settings.Joystick := J;
            N := 0;
          end;
        if N < 0 then Errors := Errors + 'Unknown joystick: ' + Value + LineEnding;
      end
      else if (Arg = 'help') or (Arg = 'h') or (Arg = '?') then Help := True
      else if (Arg = 'config') or (Arg = 'config-add') then
        // already applied before the settings were loaded
      else
        Errors := Errors + 'Unknown option: ' + ParamStr(I - 1) + LineEnding;
    end;

    // Settings first, then the machine, media, debugging aids and typing
    if RomDirArg <> '' then
    begin
      Settings.RomDir := RomDirArg;
      FEmu.Lock;
      try
        FEmu.Spec.RomDir := RomDirArg;
        try
          FEmu.Spec.SetModel(FEmu.Spec.Model);
        except
          on E: Exception do Errors := Errors + 'ROM folder: ' + E.Message + LineEnding;
        end;
      finally
        FEmu.Unlock;
      end;
    end;
    if FirmwareSet and FEmu.Spec.DivMMCOn then
    begin
      // Load the other firmware: off and on again
      BoolValue := Settings.DivMMC;
      Settings.DivMMC := False;
      ApplyDivMMC;
      Settings.DivMMC := BoolValue;
    end;
    // The ZX-Uno always has its DivMMC, Timex modes, Radastan and ULAplus:
    // asking for it with any of them off ignores that
    if NewModel = smZXUno then
    begin
      if ForcedBefore[0] then Settings.DivMMC := True;
      if ForcedBefore[1] then Settings.Timex := True;
      if ForcedBefore[2] then Settings.Radastan := True;
      if ForcedBefore[3] then Settings.ULAPlus := True;
    end;
    ApplySettings;
    if TurboSet then FEmu.Turbo := TurboValue;
    // Other ZX-Uno files: before starting it (or again, if it already is)
    if UnoSet then ApplyZXUnoFiles(FEmu.Spec.Model = smZXUno);
    if HaveModel then ChangeModel(NewModel);
    ApplyDivMMC;
    if SDFile <> '' then
    begin
      if not FileExists(SDFile) then
        Errors := Errors + 'SD card image not found: ' + SDFile + LineEnding
      else if (FEmu.Spec.DivMMC.Card <> nil) and SameFileName(
        ExpandFileName(FEmu.Spec.DivMMC.Card.FileName), ExpandFileName(SDFile)) then
      begin
        // Already in (the card of the last session): just make sure the
        // interface is connected
        Settings.DivMMC := True;
        ApplyDivMMC;
      end
      else
        InsertSDCard(ExpandFileName(SDFile));
    end;
    if SDFolder <> '' then
    begin
      if DirectoryExists(SDFolder) then UseFolderAsCard(ExpandFileName(SDFolder))
      else Errors := Errors + 'Folder not found: ' + SDFolder + LineEnding;
    end;
    if SDAdds.Count > 0 then AddFilesToCard(SDAdds, Errors);
    if Speed > 0 then Settings.CpuSpeed := Speed;
    for I := 0 to Files.Count - 1 do
      if FileExists(Files[I]) then OpenFile(Files[I])
      else Errors := Errors + 'File not found: ' + Files[I] + LineEnding;
    for I := 0 to Tapes.Count - 1 do
      if FileExists(Tapes[I]) then OpenFile(Tapes[I], False)
      else Errors := Errors + 'File not found: ' + Tapes[I] + LineEnding;
    for N := 0 to 1 do
      if Disks[N] <> '' then
      begin
        if FileExists(Disks[N]) then InsertDisk(N, Disks[N])
        else Errors := Errors + 'File not found: ' + Disks[N] + LineEnding;
      end;
    for I := 0 to SymFiles.Count - 1 do LoadSymbols(SymFiles[I]);
    for I := 0 to High(Breaks) do
    begin
      // "ADDR", "ADDR if CONDITION" or "ADDR,CONDITION"; ADDR may be a label
      // (ports are hex)
      Arg := Trim(Breaks[I].Text);
      Value := '';
      N := Pos(' IF ', UpperCase(Arg) + ' ');
      if N > 0 then
      begin
        Value := Trim(Copy(Arg, N + 4, MaxInt));
        Arg := Trim(Copy(Arg, 1, N - 1));
      end
      else if Pos(',', Arg) > 0 then
      begin
        Value := Trim(Copy(Arg, Pos(',', Arg) + 1, MaxInt));
        Arg := Trim(Copy(Arg, 1, Pos(',', Arg) - 1));
      end;
      if not CommandLineAddress(Arg, Addr) then
      begin
        Errors := Errors + 'Not an address or label: ' + Arg + LineEnding;
        Continue;
      end;
      FEmu.Lock;
      try
        if Breaks[I].Port then
        begin
          if FEmu.Spec.SetPortBreakCondition(Addr, Value, Err) then
            FEmu.Spec.PortBreakpoint[Addr] := Breaks[I].Flags
          else
            Errors := Errors + 'Breakpoint ' + Breaks[I].Text + ': ' + Err + LineEnding;
        end
        else if FEmu.Spec.SetBreakCondition(Addr, Value, Err) then
          FEmu.Spec.Breakpoint[Addr] := Breaks[I].Flags
        else
          Errors := Errors + 'Breakpoint ' + Breaks[I].Text + ': ' + Err + LineEnding;
      finally
        FEmu.Unlock;
      end;
    end;
    // Breakpoints, watches and DAAD breakpoints saved by the debuggers
    if BreakFile <> '' then
    begin
      FEmu.Lock;
      try
        if not LoadBreakpoints(FEmu.Spec, BreakFile, Err) then
          Errors := Errors + '--breakpoints ' + BreakFile + ': ' + Err + LineEnding;
      finally
        FEmu.Unlock;
      end;
    end;
    if WatchFile <> '' then
    begin
      if not LoadWatches(WatchFile, Watches, Err) then
        Errors := Errors + '--watches ' + WatchFile + ': ' + Err + LineEnding
      else if DebuggerWindow <> nil then DebuggerWindow.SetWatches(Watches)
      else PendingWatches := Watches;
    end;
    if DaadBreakFile <> '' then
    begin
      // They act once the DAAD debugger is open
      if DaadWindow = nil then DaadWindow := TDaadWindow.CreateFor(Application, FEmu);
      if not DaadWindow.LoadBreaksFile(DaadBreakFile, Err) then
        Errors := Errors + '--daadbreakpoints ' + DaadBreakFile + ': ' + Err + LineEnding;
    end;
    if KeyTexts.Count > 0 then
    begin
      FEmu.Lock;
      try
        // Give the ROM (and the DivMMC firmware) time to start up before typing
        if FEmu.Spec.Info.Memory = mkZXUno then Boot := 450         // its BIOS, then ESXDOS
        else if FEmu.Spec.DivMMCOn then Boot := 330 else Boot := 150;   // ESXDOS boots for ~5 s
        if not FEmu.Spec.AutoTyping and (FEmu.Spec.FramesSinceReset < Boot) then
          FEmu.Spec.AutoType(Boot - FEmu.Spec.FramesSinceReset, []);
        for I := 0 to KeyTexts.Count - 1 do
          if not FEmu.Spec.TypeText(KeyTexts[I], Err) then
            Errors := Errors + '-keyin: ' + Err + LineEnding;
      finally
        FEmu.Unlock;
      end;
    end;
  finally
    SymFiles.Free;
    SDAdds.Free;
    KeyTexts.Free;
    Tapes.Free;
    Files.Free;
  end;
  ApplySettings;
  UpdateChecks;
  UpdateRecentDisksMenu;
  if Help then ShowDocumentation;
  if Errors <> '' then
    MessageDlg('Command line:' + LineEnding + Errors + LineEnding +
      'See Help > Documentation for the options.', mtWarning, [mbOK], 0);
end;

procedure TMainWindow.AddFilesToCard(Specs: TStrings; var Errors: string);
var
  I, P: Integer;
  Source, Folder: string;
  Vol: TFatVolume;
  S: TFileStream;
  Data: TBytes;
  Added: Boolean;
begin
  Added := False;
  FEmu.Lock;
  try
    if FEmu.Spec.DivMMC.Card = nil then
    begin
      Errors := Errors + '--sdadd needs an SD card (--sdcard FILE)' + LineEnding;
      Exit;
    end;
    try
      Vol := TFatVolume.Create(FEmu.Spec.DivMMC.Card.Stream);
    except
      on E: Exception do
      begin
        Errors := Errors + 'SD card: ' + E.Message + LineEnding;
        Exit;
      end;
    end;
    try
      for I := 0 to Specs.Count - 1 do
      begin
        // "SOURCE,FOLDER": the folder after the last comma, "/" if none
        P := LastDelimiter(',', Specs[I]);
        if P > 0 then
        begin
          Source := Trim(Copy(Specs[I], 1, P - 1));
          Folder := Trim(Copy(Specs[I], P + 1, MaxInt));
        end
        else
        begin
          Source := Trim(Specs[I]);
          Folder := '/';
        end;
        if not FileExists(Source) then
        begin
          Errors := Errors + '--sdadd: file not found: ' + Source + LineEnding;
          Continue;
        end;
        try
          S := TFileStream.Create(Source, fmOpenRead or fmShareDenyWrite);
          try
            SetLength(Data, S.Size);
            if S.Size > 0 then S.ReadBuffer(Data[0], S.Size);
          finally
            S.Free;
          end;
          Vol.PutFile(Vol.FindDir(Folder, True), ShortNameFor(Source), Data);
          Added := True;
        except
          on E: Exception do
            Errors := Errors + '--sdadd ' + Specs[I] + ': ' + E.Message + LineEnding;
        end;
      end;
    finally
      Vol.Free;
    end;
    // The firmware may have read the card already: boot again
    if Added and FEmu.Spec.DivMMCOn then FEmu.Spec.Reset(True);
  finally
    FEmu.Unlock;
  end;
  if SDBrowserWindow <> nil then SDBrowserWindow.Refresh;
end;

function TMainWindow.FindRomLabel(const AName: string; out Addr: Word): Boolean;
var
  Paths: array of string;
  I: Integer;
begin
  // Called with the emulator locked or stopped: read the machine directly
  SetLength(Paths, FEmu.Spec.Info.RomCount);
  for I := 0 to High(Paths) do Paths[I] := FEmu.Spec.RomPath(I);
  RomLabels.Load(FEmu.Spec.RomDir, FEmu.Spec.Info, Paths);
  Result := RomLabels.Find(UpperCase(AName), FEmu.Spec.PagedRom, Addr);
end;

{ A symbol, or a hex number ($, 0x prefix or h suffix allowed). "#NAME" is
  always the symbol; a leading digit makes it a number. }
function TMainWindow.CommandLineAddress(const AText: string; out Addr: Word): Boolean;
var
  S: string;
  V: Integer;
begin
  S := Trim(AText);
  if (S <> '') and (S[1] = '#') then
  begin
    Delete(S, 1, 1);
    Result := LookupConditionSymbol(S, Addr);
    if Result then Exit;
  end
  else if (S <> '') and not (S[1] in ['0'..'9', '$']) then
  begin
    Result := LookupConditionSymbol(S, Addr);
    if Result then Exit;
  end;
  S := UpperCase(S);
  if (S <> '') and (S[1] = '$') then Delete(S, 1, 1)
  else if Copy(S, 1, 2) = '0X' then Delete(S, 1, 2)
  else if (S <> '') and (S[Length(S)] = 'H') then Delete(S, Length(S), 1);
  V := StrToIntDef('$' + S, -1);
  Result := (S <> '') and (V >= 0) and (V <= $FFFF);
  if Result then Addr := V;
end;

function TMainWindow.LoadSymbols(const FileName: string): Boolean;
var
  N: Integer;
begin
  Result := False;
  UserSymbols.Clear;
  try
    N := UserSymbols.LoadFromFile(FileName);
  except
    on E: Exception do
    begin
      MessageDlg('Could not load symbols from ' + FileName + ':' + LineEnding + E.Message,
        mtError, [mbOK], 0);
      Exit;
    end;
  end;
  if N = 0 then
    MessageDlg('No symbols found in ' + ExtractFileName(FileName) + '.' + LineEnding +
      'Expected lines like "LABEL: EQU 0x8000" (as exported by SjASM / SjASMPlus).',
      mtWarning, [mbOK], 0);
  if N > 0 then
  begin
    Settings.AddRecentSymbols(ExpandFileName(FileName));
    UpdateRecentSymbolsMenu;
  end;
  if DebuggerWindow <> nil then DebuggerWindow.Refresh(False);
  Result := N > 0;
end;

procedure TMainWindow.DoLoadSymbols(Sender: TObject);
var
  Dlg: TOpenDialog;
begin
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Filter := 'Symbol files (*.sym;*.exp;*.lab;*.txt)|*.sym;*.exp;*.lab;*.txt|All files|*.*';
    Dlg.InitialDir := Settings.LastDir;
    Dlg.Options := Dlg.Options + [ofFileMustExist];
    if Dlg.Execute then LoadSymbols(Dlg.FileName);
  finally
    Dlg.Free;
  end;
end;

procedure TMainWindow.DoClearSymbols(Sender: TObject);
begin
  UserSymbols.Clear;
  if DebuggerWindow <> nil then DebuggerWindow.Refresh(False);
end;

procedure TMainWindow.DoClearBreakpoints(Sender: TObject);
begin
  FEmu.Lock;
  try
    FEmu.Spec.ClearBreakpoints;
  finally
    FEmu.Unlock;
  end;
  if DebuggerWindow <> nil then DebuggerWindow.BreakHit;
end;

procedure TMainWindow.EmulatorBreak(Sender: TObject);
var
  Kind: TBreakKind;
begin
  FEmu.Lock;
  try
    Kind := FEmu.Spec.BreakKind;
  finally
    FEmu.Unlock;
  end;
  if (Kind = bkDaad) and (DaadWindow <> nil) then
  begin
    // The DAAD/PAW debugger stopped at a condact: the Z80 one only follows,
    // and the DAAD/PAW one gets the focus (last)
    if (DebuggerWindow <> nil) and DebuggerWindow.Visible then DebuggerWindow.BreakHit;
    DaadWindow.BreakHit;
    UpdateChecks;
    Exit;
  end;
  // A breakpoint stopped the emulation: show where
  if DebuggerWindow = nil then
    ShowDebugger(FEmu)
  else
    DebuggerWindow.BreakHit;
  DebuggerWindow.ReportBreak;
  UpdateChecks;
end;

procedure TMainWindow.DoAbout(Sender: TObject);
{$I Release.inc}
begin
  MessageDlg('About pzx',
    'pzx - ZX Spectrum emulator' + LineEnding +
    'pzx stands for Pascal ZX.' + LineEnding +
    'Release ' + PZX_RELEASE + LineEnding +
    '(C) Vivecoded by Uto - 2028' + LineEnding + LineEnding +
    'Written in Free Pascal with Lazarus.' + LineEnding + LineEnding +
    'Spectrum ROMs are copyright Amstrad, who allow their distribution.' + LineEnding +
    'ROM labels (.sym files): 48K from "The Complete Spectrum ROM Disassembly" ' +
    '(Ian Logan and Frank O''Hara), via Richard Dymond''s SkoolKit disassembly; ' +
    '128K, +2 and +3 from the disassemblies by Paul Farrow, Garry Lancaster and ' +
    'others (ZXSpectrumVault rom-disassemblies).' + LineEnding +
    'ZX-Uno (its design, core, BIOS and ROMs pack): (C) ZX-Uno Team.' + LineEnding +
    'esxDOS: (C) Miguel Guerreiro (Papaya Dezign).',
    mtInformation, [mbOK], 0);
end;

procedure TMainWindow.DoLicense(Sender: TObject);
begin
  ShowLicense;
end;

end.

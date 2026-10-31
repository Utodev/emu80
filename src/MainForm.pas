{ MainForm: main window. Display, keyboard, menus, quick toolbar and
  status bar. Controls are created in code so no .lfm is needed. }
unit MainForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs, Menus, ComCtrls, StdCtrls,
  ExtCtrls, LCLType, LCLIntf, GraphType, NextNotice, FramePresenter, Models, Spectrum, Amstrad, Sam, Msx, MsxMachine, DSK, Emulator, Config, Icons, PokeForm,
  Pokes, ScreenCapture, DocForm, ModernUI, KeyboardGuide, VirtualKeyboard;

type
  { A text longer than its room that scrolls now and then: from where it starts, a character at a time
    after a pause, and back to the start after another }
  TMarquee = record
    Full: string;
    Offset, Pause: Integer;
  end;

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
    FPauseButton, FTapePlayButton: TToolButton;
    FRecButton: TToolButton;
    FDiskButton: TToolButton;
    FSDButton: TToolButton;
    FDiskBrowserItem, FSDBrowserItem, FCartBrowserItem: TMenuItem;
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
    FRecentMenu: TMenuItem;
    FModernHide: TList;                      // menu items the modern interface has as buttons instead (left out of its menus)
    FRecentOpen: TStringList;                // what Open recent shows now (the files, with Objects = their kind)
    FRecentSymbolsMenu: TMenuItem;
    FRecentDisksMenu, FRecentDisksMenuB, FRecentCardsMenu, FRecentTapesMenu, FRecentTapesMenuJ, FRecentCartsMenu: TMenuItem;
    FDriveBItems: array of TMenuItem;   // Floppy menu entries for drive B
    FKeyboardItem, FFastLoadItem, FAutoPlayItem, FMuteItem, FPauseItem, FTurboItem, FModernItem, FInstallNextItem, FMsxCompatItem: TMenuItem;
    FMonitorItems: array[0..3] of TMenuItem;
    FScanlinesItem: TMenuItem;
    FModelMenuTop: array[0..1] of TMenuItem;   // ZX Spectrum and Amstrad CPC in the machine menu
    FSaveToTapeItem, FFastDiskItem, FDriveBItem, FBorderShotItem: TMenuItem;
    FLastFile: string;          // last file opened, for the POKE history
    FStarted: Boolean;          // command line processed
    FStartNext: Boolean;        // the ZX Spectrum Next was the model last time
    FNextFromCommandLine: Boolean;
    FInCommandLine: Boolean;    // the command line is being processed: it says what to load
    FShowNotice: Boolean;            // first start: the modern interface's note
    FNotice: TModernNotice;
    FNoticeTimer: TTimer;   // --model zxnext: emu80 closes if it can't start
    FFullerBits: Byte;
    FScaleItems: array[1..4] of TMenuItem;
    FDeinterlaceItems: array[TDeinterlace] of TMenuItem;
    FPrevPixels: array of LongWord;   // the frame before (the other field)
    FPixelsOdd: Boolean;              // FPixels is the odd field
    FOldRomDir, FOldUno: string;             // what was set before the settings window's last Apply
    FDeinterlaceTop, FCrtcTop: TMenuItem;   // Options entries of the Spectrum and of the CPC
    FCrtcItems: array[0..5] of TMenuItem;    // automatic and chips 0-4
    FTapeTop, FFloppyTop, FSDTop: TMenuItem;           // menus (Tape, Floppy and SD: the modern header leaves them out; the first one belongs to every machine)
    FKeyCount: array[0..39] of Integer;
    FCPCKeyCount: array[0..79] of Integer;   // the CPC's keys (CPCK_*) held
    FSamKeyCount: array[0..SAMK_COUNT - 1] of Integer;   // the SAM Coupe's keys (SAMK_*) held
    FMsxKeyCount: array[0..MSXK_COUNT - 1] of Integer;   // the MSX's keys (MSXK_*) held
    FMsxJoy: array[0..5] of Integer;         // the MSX joystick's directions and buttons held (MSXJ_ bit order)
    FCartTop: TMenuItem;                     // the Cartridge menu (MSX)
    FCartMapperItems: array[0..5] of TMenuItem;   // auto, plain, konami, konamiscc, ascii8, ascii16
    FCartFile: string;                       // the file of the cartridge inserted
    FOldMapper: string;                      // the cartridge mapper when the settings window opened
    // The SAM's keys that make characters go by the character the PC keyboard gives (any layout), not
    // by the key: FSamRoute 1 = by character, 2 = Alt+F key; the chord of each PC key held
    FSamRoute: array[0..255] of Byte;
    FSamChordKey, FSamChordMod: array[0..255] of SmallInt;
    FSamChordKeys: array[0..SAMK_COUNT - 1] of Integer;   // the SAM keys held by those chords
    FSamChordActive: Integer;                // chords held: their Shift and Symbol replace the PC's
    FSamLastCharVK: Word;                    // the PC key whose character is about to come
    FDriveNmiItem: TMenuItem;
    FExtCount: array[0..15] of Integer;      // two-key keys (EXT_*) held
    // The modern interface (MainModern.inc)
    FModern: Boolean;
    FNextJustInstalled: Boolean;   // its card is made at the usual size, without asking
    FModernMinHeight, FModernMinWidth: Integer;
    FBigImages, FSmallImages: TImageList;
    FMirror: TPopupMenu;
    FMHeader, FMLeft, FMRight, FMBottom: TDarkPanel;
    FMMachine, FMTape, FMMedia: TPaletteBox;
    FMModelBtn, FMKeyboard, FMPause, FMTurbo, FMRec, FMFast, FMFastDisk, FMDiskBtn, FMSDBtn, FMTapePlay: TFlatButton;
    FMZoom: array[1..4] of TFlatButton;
    FMCassette: TCassette;
    FMTapeLabel: TLabel;
    FMMediaBox, FMStatusBox: TPaintBox;
    FMediaNames: array[0..2] of string;
    FMediaShown: array[0..2] of string;      // what is drawn of each name (a carousel when it is long)
    FMarquee: array[0..3] of TMarquee;       // the three media names and the tape's text
    FMMenuBtn: array[0..2] of TFlatButton;   // the Floppy menu (A: and B:) and the SD menu, from the Media palette
    FMediaOn: array[0..2] of Boolean;        // the drives and the card reader the machine has (drawn dim when not)
    FPCKeyDown: array[0..255] of Boolean;
    FPCKeyTime: array[0..255] of QWord;     // when each PC key went down
    FPendingUp: array[0..255] of QWord;     // delayed key-up due time, 0 = none
    FKeyTimer: TTimer;
    FKempstonBits: Byte;
    FMouseLast: TPoint;          // last position over the display (Kempston mouse)
    FMouseHave: Boolean;
    FMouseRemX, FMouseRemY: Integer;   // movement not yet worth a Spectrum pixel
    FAttachAsked: Boolean;       // the question about attaching the mouse was asked (once per run)
    FMouseClipped: Boolean;      // the PC mouse is held inside the window
    FClipTimer: TTimer;
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
    function RecentFits(const FileName: string; Kind: Integer): Boolean;
    procedure UpdateRecentSymbolsMenu;
    procedure DoLoadRecentSymbols(Sender: TObject);
    procedure UpdateChecks;
    procedure ApplySettings;
    procedure SetScale(Scale: Integer);
    procedure ScaleExtra(out ExtraW, ExtraH: Integer);
    function ScaleFits(Scale: Integer): Boolean;
    function DisplayScale: Integer;
    procedure RenderBitmap;
    procedure FrameReady(Sender: TObject);
    procedure PaintDisplay(Sender: TObject);
    procedure StatusTick(Sender: TObject);
    procedure UpdateKeyboard;
    procedure MapKey(Key: Word; Down: Boolean);
    procedure MapKeyCPC(Key: Word; Down: Boolean);
    procedure MapKeySAM(Key: Word; Down: Boolean);
    procedure MapKeyMSX(Key: Word; Down: Boolean);
    procedure InsertCartridgeFile(const FileName: string);
    procedure DoCartInsert(Sender: TObject);
    procedure DoCartEject(Sender: TObject);
    procedure DoCartMapper(Sender: TObject);
    function SamCharKey(Key: Word): Boolean;
    function SamKeyHeld(K: Integer): Boolean;
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormUTF8KeyPress(Sender: TObject; var UTF8Key: TUTF8Char);
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
    procedure DoDriveNMI(Sender: TObject);
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
    procedure InsertDiskDialog(Drive: Integer);
    function FloppyAvailable: Boolean;
    function SDAvailable: Boolean;
    procedure ModernMediaClick(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    function InsertDiskFile(Drive: Integer; const FileName: string): Boolean;
    function LoadDiskChecked(const FileName: string; out Disk: TDiskImage; out Msg: string): Boolean;
    procedure UpdateRecentDisksMenu;
    { The game file just loaded, for default names (Adventure Debugger's source export) }
    procedure NoteMediaFile(const FileName: string);
    procedure AddDriveBItem(Item: TMenuItem);
    procedure DoInsertRecentDisk(Sender: TObject);
    procedure DoInsertRecentCard(Sender: TObject);
    procedure DoInsertRecentTape(Sender: TObject);
    procedure DoInsertRecentTapeOnly(Sender: TObject);
    procedure InsertRecentTape(Sender: TObject; AutoStart: Boolean);
    procedure DoInsertRecentCart(Sender: TObject);
    procedure DoDiskBrowser(Sender: TObject);
    procedure DoSDBrowser(Sender: TObject);
    procedure CartSaved(const FileName: string);
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
    procedure ApplyCurrah;
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
    procedure DoMonitor(Sender: TObject);
    procedure DoScanlines(Sender: TObject);
    function MouseOn: Boolean;
    function MouseInUse: Boolean;
    procedure DoDocumentation(Sender: TObject);
    procedure ApplyRomFiles;
    procedure DisplayMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure DisplayMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer);
    procedure DisplayMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer);
    procedure DisplayMouseLeave(Sender: TObject);
    procedure MouseClipTick(Sender: TObject);
    procedure ReleaseMouseClip;
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
    procedure DoDeinterlace(Sender: TObject);
    procedure DoCrtc(Sender: TObject);
    procedure DoSettings(Sender: TObject);
    procedure DoKeyboardGuide(Sender: TObject);
    procedure DoVirtualKeyboard(Sender: TObject);
    procedure DoMsxCompat(Sender: TObject);
    procedure MsxNotice;
    function TypeVirtualSymbol(const Sym: string; DryRun: Boolean): Boolean;
    procedure SettingsApplied(Sender: TObject);
    procedure DoTapeInsert(Sender: TObject);
    procedure DoTapeInsertOnly(Sender: TObject);
    procedure InsertTapeDialog(AutoStart: Boolean);
    function TapeFilter: string;
    procedure BuildModern;
    procedure ApplyStyle;
    procedure DoToggleTheme(Sender: TObject);
    procedure ShowNotice;
    procedure NoticeEnd(Sender: TObject);
    procedure PaintStripes(Sender: TObject);
    procedure ModernMenuClick(Sender: TObject);
    procedure MirrorItems(Src, Dst: TMenuItem);
    procedure MirrorClick(Sender: TObject);
    function MenuShortcut(Key: Word; Shift: TShiftState): Boolean;
    procedure PaintModernMedia(Sender: TObject);
    function MarqueeText(Index: Integer; const Full: string; C: TCanvas; Room: Integer): string;
    procedure PaintModernStatus(Sender: TObject);
    procedure ModernTick;
    procedure DoAbout(Sender: TObject);
    procedure DoLicense(Sender: TObject);
    procedure DoDebugger(Sender: TObject);
    procedure DoDaadDebugger(Sender: TObject);
    procedure DoClearBreakpoints(Sender: TObject);
    procedure DoLoadSymbols(Sender: TObject);
    procedure DoClearSymbols(Sender: TObject);
    procedure ProcessCommandLine;
    function CommandLineAddress(const AText: string; out Addr: Word): Boolean;
    { --zx_sdadd: copy PC files ("SOURCE,FOLDER") onto the SD card, then switch
      the machine off and on so the firmware sees them }
    procedure AddFilesToCard(Specs: TStrings; var Errors: string);
  public
    { A ROM or system variable label of the ROM paged in now }
    function FindRomLabel(const AName: string; out Addr: Word): Boolean;
  private
    function LoadSymbols(const FileName: string): Boolean;
    procedure EmulatorBreak(Sender: TObject);
    function ConfirmDiskChanges(Drive: Integer): Boolean;
    function PrepareNext: Boolean;
    { The card each hardware remembers: the Next's (NextCard), the ZX-Uno's, the
      standard models' }
    procedure RememberCard(const FileName: string);
    { Put that card in the DivMMC (nothing, if it isn't there): the one that
      is in goes out first (its changes were dealt with) }
    procedure UseCard(const FileName: string; EjectIfNone: Boolean);
    { Switching hardware: the DivMMC and its card for the new one }
    procedure HardwareChanged(Old, New: TSpectrumModel);
    { The licence warning the first time the Next is to say it is a real one
      (hidden option realspecnext), and the ID the machine will send }
    procedure ConfirmRealSpecNext;
    procedure ApplyNextId;
    { The distribution isn't installed: where to get it and how to install it }
    procedure NoNextDistro;
    { Options > Install Spectrum Next Distribution: only without one }
    procedure UpdateInstallNextItem(Sender: TObject);
    procedure DoInstallNextDistro(Sender: TObject);
    procedure InstallProgress(Percent: Integer);
    procedure LeaveNext;
    function MakeNextCardFile(const FileName: string; SizeMB: Integer = 0): Boolean;
    procedure DoNewNextCard(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure OpenFile(const FileName: string; AutoStart: Boolean = True);
    procedure ChangeModel(M: TSpectrumModel);
    procedure SamDosBoot;
    function SamDosDisk: TDiskImage;
    function CliSamDos: Boolean;
    procedure ApplyContention;
    procedure ApplyZXUnoFiles(Reload: Boolean);
    function ReleasedSide(Key: Word): Word;
    procedure StoreZXUnoBios;
    property Emu: TEmulator read FEmu;
  end;

var
  MainWindow: TMainWindow;

implementation

uses
  Snapshot, Tape, TapeBrowser, SettingsForm, DebuggerForm, DaadForm, Symbols, BreakExpr, DiskBrowser,
  SDBrowser, CartBrowser, FatFS, DebugFiles, NextCard, DiskFormat;

{$IFDEF WINDOWS}
{ (The Windows unit would hide SysUtils' DeleteFile and others) }
function WinClipCursor(lpRect: Pointer): LongBool; stdcall; external 'user32' name 'ClipCursor';
{$ENDIF}

{ Names in breakpoint conditions: user symbols first, then ROM labels }
function LookupConditionSymbol(const Name: string; out Value: Word): Boolean;
begin
  Result := UserSymbols.Find(Name, Value);
  if not Result and (MainWindow <> nil) then Result := MainWindow.FindRomLabel(Name, Value);
end;

const
  SAMDOS_FILE = 'SAMDOS2.dsk';     // the SAM Coupe's DOS disk, in the roms folder
  DISK_FILTER = 'Disk images (*.dsk;*.mgt;*.sad)|*.dsk;*.mgt;*.sad';
  SAVE_DISK_FILTER = 'Disk images (*.dsk)|*.dsk|SAM Coupe MGT images (*.mgt)|*.mgt|SAM Coupe SAD images (*.sad)|*.sad';
  CART_MAPPER_KEYS: array[0..5] of string = ('auto', 'plain', 'konami', 'konamiscc', 'ascii8', 'ascii16');
  CART_MAPPER_NAMES: array[0..5] of string = ('Auto-detect', 'Plain ROM (no mapper)', 'Konami', 'Konami SCC', 'ASCII8', 'ASCII16');
  OPEN_FILTER = 'All supported files|*.tap;*.tzx;*.cdt;*.sna;*.z80;*.dsk;*.mgt;*.sad;*.nex;*.e80;*.rom;*.cas;*.tsx|' +
    'MSX cartridges (*.rom)|*.rom|' +
    'Tape images (*.tap;*.tzx;*.cdt;*.cas;*.tsx)|*.tap;*.tzx;*.cdt;*.cas;*.tsx|' +
    'Snapshots (*.sna;*.z80;*.e80)|*.sna;*.z80;*.e80|' + DISK_FILTER + '|' +
    'ZX Spectrum Next programs (*.nex)|*.nex|All files|*.*';

{ TMainWindow }

var
  { --ui on the command line ('' if not given): it is applied at once, and
    the first-run question isn't asked }
  CommandLineUI: string = '';

{ --config FILE / --config-add FILE (and --ui) must be known before the
  settings load }
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
    if Arg = 'ui' then
    begin
      if (Value = '') and (I < ParamCount) then Value := ParamStr(I + 1);
      CommandLineUI := LowerCase(Value);
    end
    else if (Arg = 'config') or (Arg = 'config-add') then
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
            MessageDlg('emu80', 'The settings file given with --config does not exist.' +
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

{ Cards made from folders that an emu80 closed abruptly left behind (one still
  in use by another emu80 can't be deleted, and stays) }
procedure RemoveStaleTempCards;
var
  Info: TSearchRec;
  Dir: string;
begin
  Dir := IncludeTrailingPathDelimiter(GetTempDir);
  if FindFirst(Dir + 'emu80-sd-*.img', faAnyFile, Info) = 0 then
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
  FirstRun: Boolean;
begin
  inherited CreateNew(AOwner, 0);
  Caption := 'emu80 - 8 bit machines emulator';
  Position := poScreenCenter;
  // Sizes here are real screen pixels (whole zoom factors); don't let LCL
  // multiply them by the desktop DPI scale
  Scaled := False;
  KeyPreview := True;
  AllowDropFiles := True;
  OnKeyDown := @FormKeyDown;
  OnKeyUp := @FormKeyUp;
  OnUTF8KeyPress := @FormUTF8KeyPress;
  OnDeactivate := @FormDeactivate;
  OnDropFiles := @FormDropFiles;
  OnClose := @FormClose;
  OnShow := @FormShow;

  ReadSettingsOptions;
  FirstRun := not FileExists(Settings.FileName);
  Settings.Load;
  // The interface: as the command line says, else the settings' (the
  // modern one the first time, with a note on how to change it)
  if (CommandLineUI = 'modern') or (CommandLineUI = 'classic') then
    Settings.ModernUI := CommandLineUI = 'modern';
  FShowNotice := FirstRun and Settings.ModernUI;
  RemoveStaleTempCards;
  Err := '';
  // The Next needs its distribution and its card: started as the 48K and
  // switched over once the window is up
  FStartNext := Settings.Model = smZXNext;
  if FStartNext then Settings.Model := sm48K;
  try
    FEmu := TEmulator.Create(Settings.Model, Settings.RomDir);
  except
    on E: Exception do
    begin
      // Fall back to the ROMs next to the executable (a ZX-Uno without its
      // BIOS: the 48K)
      Err := E.Message;
      // (an MSX2 without its ROMs: the 48K, and the ROM folder stays)
      if Settings.Model <> smMSX2 then Settings.RomDir := DefaultRomDir;
      if Settings.Model in [smZXUno, smMSX2] then Settings.Model := sm48K;
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
  SetLength(FPrevPixels, FB_WIDTH * SCREEN_HEIGHT);

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
  BuildModern;

  FKeyTimer := TTimer.Create(Self);
  FKeyTimer.Interval := 10;
  FKeyTimer.Enabled := False;
  FKeyTimer.OnTimer := @KeyTimerTick;

  // Keeps the PC mouse in the window when it is attached to it
  FClipTimer := TTimer.Create(Self);
  FClipTimer.Interval := 15;
  FClipTimer.OnTimer := @MouseClipTick;

  FStatusTimer := TTimer.Create(Self);
  FStatusTimer.Interval := 250;
  FStatusTimer.OnTimer := @StatusTick;

  // The card that was in the DivMMC last time (the ZX-Uno's, if it starts as
  // that; the Next's is put in when it is switched to)
  if Settings.Model = smZXUno then
  begin
    Settings.DivMMC := True;
    if (Settings.ZXUnoCard <> '') and FileExists(Settings.ZXUnoCard) then UseCard(Settings.ZXUnoCard, False);
  end;
  if (FEmu.Spec.DivMMC.Card = nil) and (Settings.SDCardFile <> '') and FileExists(Settings.SDCardFile) then
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
  ApplyStyle;
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
  ReleaseMouseClip;
  FEmu.Free;
  FRecentOpen.Free;
  FModernHide.Free;
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
  S, I: Integer;
  D: TDeinterlace;
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

  // The model is chosen with the toolbar's chip button or in Settings
  TopItem := AddItem(FMenu.Items, '&Machine', nil);
  AddItem(TopItem, '&NMI', @DoNMI, ShortCut(VK_F5, []));
  // The ZX Spectrum Next's second NMI button (F5 is its M1 button)
  FDriveNmiItem := AddItem(TopItem, '&DRIVE button (DivMMC NMI)', @DoDriveNMI, ShortCut(VK_F5, [ssShift]));
  AddItem(TopItem, '&Hard reset', @DoHardReset, ShortCut(VK_F6, []));
  AddItem(TopItem, '&Reset', @DoReset, ShortCut(VK_F6, [ssShift]));
  AddItem(TopItem, '-', nil);
  FPauseItem := AddItem(TopItem, '&Pause', @DoPause, ShortCut(VK_F4, []));
  AddItem(TopItem, '-', nil);
  AddItem(TopItem, '&POKE...', @DoPoke, ShortCut(VK_F9, []));

  // The storage menus (Tape, Floppy, SD) between separators
  AddItem(FMenu.Items, '|', nil).Enabled := False;
  TopItem := AddItem(FMenu.Items, '&Tape', nil);
  FTapeTop := TopItem;
  AddItem(TopItem, '&Insert tape && load...', @DoTapeInsert);
  AddItem(TopItem, '&Just insert tape...', @DoTapeInsertOnly);
  FRecentTapesMenu := AddItem(TopItem, 'Insert &recent tape && load', nil);
  FRecentTapesMenuJ := AddItem(TopItem, 'Just insert recent &tape', nil);
  AddItem(TopItem, '-', nil);
  FModernHide := TList.Create;
  FModernHide.Add(AddItem(TopItem, 'Tape &browser...', @DoTapeBrowser, ShortCut(VK_F7, [])));
  FModernHide.Add(AddItem(TopItem, '&Play/pause', @DoTapePlay, ShortCut(VK_F8, [])));
  FModernHide.Add(AddItem(TopItem, '&Stop', @DoTapeStop, ShortCut(VK_F8, [ssShift])));
  FRecItem := AddItem(TopItem, 'Re&cord (REC)', @DoTapeRecord);
  FModernHide.Add(FRecItem);
  FModernHide.Add(AddItem(TopItem, '&Rewind', @DoTapeRewind));
  AddItem(TopItem, '&Eject', @DoTapeEject);
  AddItem(TopItem, 'Save tape &as...', @DoTapeSave);
  AddItem(TopItem, '-', nil);
  AddItem(TopItem, '&New blank tape', @DoNewTape);
  AddItem(TopItem, '-', nil);
  FFastLoadItem := AddItem(TopItem, '&Fast loading', @DoFastLoad);
  FModernHide.Add(FFastLoadItem);
  FAutoPlayItem := AddItem(TopItem, '&Auto play/stop', @DoAutoPlay);
  FSaveToTapeItem := AddItem(TopItem, 'SA&VE writes to the tape', @DoSaveToTape);

  TopItem := AddItem(FMenu.Items, 'F&loppy', nil);
  FFloppyTop := TopItem;
  FDiskBrowserItem := AddItem(TopItem, 'Disk &browser...', @DoDiskBrowser);
  FModernHide.Add(FDiskBrowserItem);
  AddItem(TopItem, '-', nil);
  Item := AddItem(TopItem, 'Insert disk in drive &A:...', @DoDiskInsert, ShortCut(VK_F2, [ssShift]));
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
  FModernHide.Add(FFastDiskItem);
  FDriveBItem := AddItem(TopItem, 'Drive &B: connected', @DoDriveB);

  // MSX cartridge slot (the MSX has no SD card reader: the slot takes ROM cartridges)
  TopItem := AddItem(FMenu.Items, '&Cartridge', nil);
  FCartTop := TopItem;
  FCartBrowserItem := AddItem(TopItem, 'Cartridge &browser...', @DoSDBrowser);
  AddItem(TopItem, '-', nil);
  AddItem(TopItem, '&Insert cartridge...', @DoCartInsert);
  FRecentCartsMenu := AddItem(TopItem, 'Insert &recent cartridge', nil);
  AddItem(TopItem, '&Eject cartridge', @DoCartEject);
  AddItem(TopItem, '-', nil);
  Item := AddItem(TopItem, '&Mapper', nil);
  for I := 0 to 5 do
  begin
    if I = 0 then FCartMapperItems[I] := AddItem(Item, '&Auto-detect', @DoCartMapper)
    else FCartMapperItems[I] := AddItem(Item, CART_MAPPER_NAMES[I], @DoCartMapper);
    FCartMapperItems[I].Tag := I;
    FCartMapperItems[I].RadioItem := True;
    FCartMapperItems[I].GroupIndex := 7;
  end;

  // DivMMC SD card (the interface is switched on in Settings > Hardware)
  TopItem := AddItem(FMenu.Items, '&SD', nil);
  FSDTop := TopItem;
  FSDBrowserItem := AddItem(TopItem, 'SD card &browser...', @DoSDBrowser);
  FModernHide.Add(FSDBrowserItem);
  AddItem(TopItem, '-', nil);
  AddItem(TopItem, '&Insert SD card image...', @DoSDInsert);
  FRecentCardsMenu := AddItem(TopItem, 'Insert &recent SD card', nil);
  AddItem(TopItem, 'Use a PC &folder as SD card...', @DoSDFolder);
  AddItem(TopItem, '&New SD card...', @DoSDNew).Tag := 0;
  AddItem(TopItem, 'New SD card with &ESXDOS...', @DoSDNew).Tag := 1;
  AddItem(TopItem, 'New SD card with the &Next distribution...', @DoNewNextCard);
  AddItem(TopItem, '-', nil);
  AddItem(TopItem, '&Save SD card', @DoSDSave).Tag := 0;
  AddItem(TopItem, 'Save SD card &as...', @DoSDSave).Tag := 1;
  AddItem(TopItem, '-', nil);
  AddItem(TopItem, 'E&ject SD card', @DoSDEject);

  AddItem(FMenu.Items, '|', nil).Enabled := False;
  TopItem := AddItem(FMenu.Items, '&Debug', nil);
  AddItem(TopItem, '&Debugger...', @DoDebugger, ShortCut(VK_F12, []));
  AddItem(TopItem, '&Clear all breakpoints', @DoClearBreakpoints);
  AddItem(TopItem, '-', nil);
  AddItem(TopItem, '&Load symbols...', @DoLoadSymbols);
  FRecentSymbolsMenu := AddItem(TopItem, 'Load &recent symbols', nil);
  AddItem(TopItem, 'C&lear symbols', @DoClearSymbols);
  AddItem(TopItem, '-', nil);
  AddItem(TopItem, '&Adventure Debugger...', @DoDaadDebugger, ShortCut(VK_F11, []));

  TopItem := AddItem(FMenu.Items, '&Options', nil);
  TopItem.OnClick := @UpdateInstallNextItem;
  // The monitor, for both machines
  Item := AddItem(TopItem, '&Monitor', nil);
  for S := 0 to 3 do
  begin
    FMonitorItems[S] := AddItem(Item, MONITOR_NAMES[S], @DoMonitor);
    FMonitorItems[S].Tag := S;
    FMonitorItems[S].RadioItem := True;
    FMonitorItems[S].GroupIndex := 5;
  end;
  FScanlinesItem := AddItem(TopItem, '&Scanlines (zoom 2x or more)', @DoScanlines);
  Item := AddItem(TopItem, '&Zoom', nil);
  for S := 1 to 4 do
  begin
    FScaleItems[S] := AddItem(Item, Format('%dx', [S]), @DoScale);
    FScaleItems[S].Tag := S;
    FScaleItems[S].RadioItem := True;
    FScaleItems[S].GroupIndex := 2;
  end;
  Item := AddItem(TopItem, '&Deinterlace', nil);
  FDeinterlaceTop := Item;
  for D := Low(TDeinterlace) to High(TDeinterlace) do
  begin
    FDeinterlaceItems[D] := AddItem(Item, DEINTERLACE_NAMES[D], @DoDeinterlace);
    FDeinterlaceItems[D].Tag := Ord(D);
    FDeinterlaceItems[D].RadioItem := True;
    FDeinterlaceItems[D].GroupIndex := 3;
  end;
  // The CPC's CRTC chip, in the place of the Spectrum's deinterlacing
  Item := AddItem(TopItem, '&CRTC chip', nil);
  FCrtcTop := Item;
  for S := 0 to 5 do
  begin
    if S = 0 then FCrtcItems[S] := AddItem(Item, 'The model''s own', @DoCrtc)
    else FCrtcItems[S] := AddItem(Item, Format('Type %d: %s', [S - 1,
      CRTC_NAMES[S - 1]]), @DoCrtc);
    FCrtcItems[S].Tag := S;
    FCrtcItems[S].RadioItem := True;
    FCrtcItems[S].GroupIndex := 4;
  end;
  FMuteItem := AddItem(TopItem, '&Mute sound', @DoMute);
  FTurboItem := AddItem(TopItem, '&Turbo speed', @DoTurbo, ShortCut(VK_F11, [ssShift]));
  FModernItem := AddItem(TopItem, 'Mo&dern interface (dark)', @DoToggleTheme);
  // The MSX2 with an MSX1's slots (none expanded): resets the machine
  FMsxCompatItem := AddItem(TopItem, 'MSX 1 &compatibility mode', @DoMsxCompat);
  // Every machine; the modern interface has a button for it
  FModernHide.Add(AddItem(TopItem, '&Virtual Keyboard', @DoVirtualKeyboard));
  // Every Spectrum, not the CPC, the SAM Coupe or the MSX; the modern interface has a button for it
  FKeyboardItem := AddItem(TopItem, 'ZX &Keyboard Guide', @DoKeyboardGuide);
  FModernHide.Add(FKeyboardItem);
  FInstallNextItem := AddItem(TopItem, 'Install Spectrum Next Distribution', @DoInstallNextDistro);
  AddItem(TopItem, '-', nil);
  AddItem(TopItem, 'S&ettings...', @DoSettings);

  TopItem := AddItem(FMenu.Items, '&Help', nil);
  AddItem(TopItem, '&Documentation', @DoDocumentation, ShortCut(VK_F1, []));
  AddItem(TopItem, '-', nil);
  AddItem(TopItem, '&License (GPL v3)', @DoLicense);
  AddItem(TopItem, '&About emu80...', @DoAbout);
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
  SamItem: TMenuItem;
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
  // Two levels: the family (ZX Spectrum above, Amstrad CPC below), then its machines; the SAM Coupe is a lone entry at the end
  FModelMenu := TPopupMenu.Create(Self);
  FModelMenuTop[0] := TMenuItem.Create(FModelMenu);
  FModelMenuTop[0].Caption := 'ZX Spectrum';
  FModelMenu.Items.Add(FModelMenuTop[0]);
  FModelMenuTop[1] := TMenuItem.Create(FModelMenu);
  FModelMenuTop[1].Caption := 'Amstrad CPC';
  FModelMenu.Items.Add(FModelMenuTop[1]);
  SamItem := nil;
  for M := Low(TSpectrumModel) to High(TSpectrumModel) do
  begin
    FModelPopupItems[M] := TMenuItem.Create(FModelMenu);
    FModelPopupItems[M].Caption := ModelInfo[M].Name;
    FModelPopupItems[M].Tag := Ord(M);
    FModelPopupItems[M].RadioItem := True;
    FModelPopupItems[M].GroupIndex := 1;
    FModelPopupItems[M].OnClick := @DoModel;
    // The MSX2 and the SAM Coupe are single machines: they sit at the first level, after the families (the SAM last)
    if IsMSXModel(M) then
      FModelMenu.Items.Add(FModelPopupItems[M])
    else if IsSAMModel(M) then
      SamItem := FModelPopupItems[M]
    else
      FModelMenuTop[Ord(IsCPCModel(M))].Add(FModelPopupItems[M]);
  end;
  if SamItem <> nil then FModelMenu.Items.Add(SamItem);
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
  FTapePlayButton := AddButton(ikPlay, 'Play/pause tape (F8)', @DoTapePlay);
  AddButton(ikStop, 'Stop tape (Shift+F8)', @DoTapeStop);
  FRecButton := AddButton(ikRecord, 'Record onto the tape (REC)', @DoTapeRecord);
  FRecButton.Style := tbsCheck;
  AddSeparator;
  FDiskButton := AddButton(ikDisk, 'Disk browser', @DoDiskBrowser);
  FSDButton := AddButton(ikSDCard, 'SD card browser (DivMMC)', @DoSDBrowser);
  AddSeparator;
  AddButton(ikDebugger, 'Debugger (F12)', @DoDebugger);
  AddButton(ikSettings, 'Settings', @DoSettings);
  AddButton(ikTheme, 'Switch to the modern interface (dark)', @DoToggleTheme);
end;

{ Contention on the Spectrum models; the Gate Array's wait states and the CRTC
  chip on the Amstrad CPC (the emulator is locked by the caller) }
procedure TMainWindow.ApplyContention;
begin
  if FEmu.Spec.CPC <> nil then
  begin
    FEmu.Spec.ContentionOn := Settings.CPCWaitStates;
    if Settings.CPCCrtc < 0 then
      FEmu.Spec.CPC.CrtcType := TAmstrad.DefaultCrtcType(FEmu.Spec.Model)
    else
      FEmu.Spec.CPC.CrtcType := Settings.CPCCrtc;
  end
  else
    FEmu.Spec.ContentionOn := Settings.Contention;
end;

procedure TMainWindow.ApplySettings;
var
  Err: string;
begin
  Err := '';
  FEmu.Lock;
  try
    FEmu.Spec.FastLoad := Settings.FastLoad;
    FEmu.Spec.AutoPlayTape := Settings.AutoPlayTape;
    FEmu.Spec.Tape.Loop := Settings.TapeLoop;
    FEmu.Spec.KempstonEnabled := Settings.Joystick = jkKempston;
    FEmu.Spec.MouseEnabled := MouseOn;
    // The Spectrum's extras are off on a CPC
    FEmu.Spec.AYOn48K := Settings.AY48 and (FEmu.Spec.CPC = nil);
    FEmu.Spec.FullerEnabled := Settings.Joystick = jkFuller;
    FEmu.Spec.SamSaaOn := Settings.SamSaa;
    FEmu.Spec.SamJoystickOn := Settings.SamJoystick;
    FEmu.Spec.SamMouseOn := Settings.SamMouse;
    FEmu.Spec.SamClockOn := Settings.SamClock;
    FEmu.Spec.SamMemoryKB := Settings.SamMemory;
    if Settings.MsxMapper = 'on' then FEmu.Spec.MsxMapperMode := MSX_MAPPER_ON
    else if Settings.MsxMapper = 'off' then FEmu.Spec.MsxMapperMode := MSX_MAPPER_OFF
    else FEmu.Spec.MsxMapperMode := MSX_MAPPER_AUTO;
    FEmu.Spec.MsxCompat := Settings.MsxCompat;
    // The slot layout is built at a reset: the machine has the other one, so it starts again
    if IsMSXModel(FEmu.Spec.Model) and (FEmu.Spec.MSXHw <> nil) and (FEmu.Spec.MSXHw.Compat <> Settings.MsxCompat) then
      FEmu.Spec.Reset(True);
    FEmu.Spec.Issue2 := Settings.Issue2;
    FEmu.Spec.SetSpeed(Settings.CpuSpeed);
    FEmu.Spec.SaveToTape := Settings.SaveToTape;
    FEmu.Spec.SetFastDisk(Settings.FastDisk);
    FEmu.Spec.DriveBOn := Settings.DriveB;
    FEmu.Spec.FloppyNoise := Settings.FloppyNoise;
    FEmu.Spec.Volume := Settings.Volume / 100;
    FEmu.Spec.TurboSound := Settings.TurboSound and (FEmu.Spec.CPC = nil);
    ApplyContention;
    FEmu.Spec.SnowOn := Settings.UlaSnow;
    FEmu.Spec.RomWritable := Settings.AllowRomEdit;
    FEmu.Spec.ULAPlusEnabled := Settings.ULAPlus;
    FEmu.Spec.TimexEnabled := Settings.Timex;
    FEmu.Spec.RadastanEnabled := Settings.Radastan;
    FEmu.Spec.NextDir := NextDistroDir;
    if Settings.RealSpecNext and Settings.RealSpecNextOk then FEmu.Spec.NextMachineId := $0A
    else FEmu.Spec.NextMachineId := $08;
    FEmu.Spec.NextBootRom := IncludeTrailingPathDelimiter(DefaultRomDir) + 'tbblue_loader.rom';
    // Another way of starting the Next: switched off and on again
    if FEmu.Spec.NextFirmwareBoot <> Settings.NextFirmware then
    begin
      FEmu.Spec.NextFirmwareBoot := Settings.NextFirmware;
      if FEmu.Spec.Model = smZXNext then
        try
          FEmu.Spec.SetModel(smZXNext);
        except
          on E: Exception do Err := E.Message;
        end;
    end;
  finally
    FEmu.Unlock;
  end;
  if Err <> '' then MessageDlg('ZX Spectrum Next: ' + Err, mtError, [mbOK], 0);
  FEmu.Sound := Settings.Sound;
  ApplyRomFiles;
  ApplyDivMMC;
  ApplyCurrah;
end;

{ The Currah µSpeech: plugging it in or out switches the machine off and
  on. Its ROMs are currah.rom and sp0256-al2.rom in the ROM folder. }
procedure TMainWindow.ApplyCurrah;
var
  Dir, Err: string;
begin
  if (Settings.Currah = FEmu.Spec.CurrahOn) or (FEmu.Spec.CPC <> nil) or IsSAMModel(FEmu.Spec.Model) then Exit;
  Err := '';
  FEmu.Lock;
  try
    if Settings.Currah then
    begin
      Dir := IncludeTrailingPathDelimiter(FEmu.Spec.RomDir);
      try
        FEmu.Spec.Currah.LoadRoms(Dir + 'currah.rom', Dir + 'sp0256-al2.rom');
        FEmu.Spec.CurrahOn := True;
      except
        on E: Exception do Err := E.Message;
      end;
    end
    else
      FEmu.Spec.CurrahOn := False;
    if Err = '' then FEmu.Spec.Reset(True);
  finally
    FEmu.Unlock;
  end;
  if Err <> '' then
  begin
    Settings.Currah := False;
    MessageDlg('Currah ' + #$C2#$B5 + 'Speech: ' + Err + LineEnding +
      'It needs currah.rom and sp0256-al2.rom in the ROM folder.', mtError, [mbOK], 0);
  end;
end;

function TMainWindow.ApplyDivMMC: Boolean;
var
  Firmware, Err: string;
begin
  Result := True;
  // The ZX-Uno and the Next have their own DivMMC
  if FEmu.Spec.Info.Memory in [mkZXUno, mkZXNext, mkCPC, mkSAM, mkMSX] then Exit;
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
  // The same image again is inserted again (what was changed in it is asked about, as for any other)
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
    RememberCard(FileName);
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
  M, MM: TSpectrumModel;
  S, I: Integer;
begin
  M := FEmu.Spec.Model;
  for MM := Low(TSpectrumModel) to High(TSpectrumModel) do FModelPopupItems[MM].Checked := MM = M;
  FModelButton.Hint := 'Machine: ' + ModelInfo[M].Name + ' (click to change)';
  FFastLoadItem.Checked := Settings.FastLoad;
  FModernItem.Checked := Settings.ModernUI;
  FAutoPlayItem.Checked := Settings.AutoPlayTape;
  FMuteItem.Checked := not Settings.Sound;
  FMonitorItems[Settings.Monitor].Checked := True;
  FScanlinesItem.Checked := Settings.Scanlines;
  UpdateInstallNextItem(nil);
  FSaveToTapeItem.Checked := Settings.SaveToTape;
  UpdateRecentMenu;
  UpdateRecentDisksMenu;
  FFastDiskItem.Checked := Settings.FastDisk;
  FDriveBItem.Checked := Settings.DriveB;
  for I := 0 to High(FDriveBItems) do FDriveBItems[I].Visible := Settings.DriveB;
  FDriveNmiItem.Visible := M = smZXNext;
  // The menus of what the machine has: a drive built in, or the DivMMC (which brings an SD card and a disk
  // interface to any machine); the modern interface has them behind the Media palette's buttons instead
  if FFloppyTop <> nil then FFloppyTop.Visible := FloppyAvailable or FEmu.Spec.DivMMCOn;
  if FSDTop <> nil then FSDTop.Visible := SDAvailable;
  if FCartTop <> nil then FCartTop.Visible := IsMSXModel(M);
  for I := 0 to 5 do
    if (FCartMapperItems[I] <> nil) and (CART_MAPPER_KEYS[I] = Settings.MsxCartMapper) then FCartMapperItems[I].Checked := True;
  FBorderShotItem.Checked := Settings.ScreenshotBorder;
  FPauseItem.Checked := FEmu.Paused;
  FRecItem.Checked := FEmu.Spec.Recording;
  FRecButton.Down := FEmu.Spec.Recording;
  FPauseButton.Down := FEmu.Paused;
  FTurboItem.Checked := FEmu.Turbo;
  FTurboButton.Down := FEmu.Turbo;
  FMsxCompatItem.Visible := IsMSXModel(M);
  FMsxCompatItem.Checked := Settings.MsxCompat;
  for S := 1 to 4 do
  begin
    FScaleItems[S].Checked := S = Settings.Scale;
  FDeinterlaceItems[Settings.Deinterlace].Checked := True;
  FCrtcItems[Settings.CPCCrtc + 1].Checked := True;
  // Deinterlacing is the Spectrum's, the CRTC chip the CPC's
  FDeinterlaceTop.Visible := (FEmu.Spec.CPC = nil) and not IsSAMModel(M);
  FCrtcTop.Visible := FEmu.Spec.CPC <> nil;
  FKeyboardItem.Visible := M in [sm16K..smZXNext];
    // A zoom too big for the screen can't be chosen
    FScaleItems[S].Enabled := (S = 1) or ScaleFits(S);
  end;
  ModernTick;
end;

{ Space around the screen in the window: toolbar, status bar etc. (from
  the live layout), or the modern palettes, header and bar }
procedure TMainWindow.ScaleExtra(out ExtraW, ExtraH: Integer);
begin
  if FModern then
  begin
    // The palettes, header and bar around the screen are of fixed sizes
    ExtraW := FMLeft.Width + FMRight.Width + 2 * FDisplay.BorderSpacing.Around;
    ExtraH := FMHeader.Height + FMBottom.Height + 2 * FDisplay.BorderSpacing.Around;
  end
  else
  begin
    ExtraW := Max(0, ClientWidth - FDisplay.Width);
    ExtraH := Max(FToolBar.Height + FStatus.Height, ClientHeight - FDisplay.Height);
  end;
end;

{ The window at this zoom fits on its screen (with its frame and title,
  as they really are once it is shown) }
function TMainWindow.ScaleFits(Scale: Integer): Boolean;
var
  Work: TRect;
  ExtraW, ExtraH, W, H, FrameW, FrameH: Integer;
begin
  ScaleExtra(ExtraW, ExtraH);
  W := SCREEN_WIDTH * Scale + ExtraW;
  H := SCREEN_HEIGHT * Scale + ExtraH;
  if FModern then
  begin
    W := Max(W, FModernMinWidth);
    H := Max(H, FModernMinHeight);
  end;
  if HandleAllocated and (Width > ClientWidth) and (Height > ClientHeight) then
  begin
    FrameW := Width - ClientWidth;
    FrameH := Height - ClientHeight;
  end
  else
  begin
    FrameW := 16;
    FrameH := 60;
  end;
  if Monitor <> nil then Work := Monitor.WorkareaRect else Work := Screen.WorkAreaRect;
  Result := (W + FrameW <= Work.Right - Work.Left) and (H + FrameH <= Work.Bottom - Work.Top);
end;

procedure TMainWindow.SetScale(Scale: Integer);
var
  ExtraW, ExtraH: Integer;
begin
  ScaleExtra(ExtraW, ExtraH);
  // Keep the window on screen: drop to the largest whole zoom that fits
  while (Scale > 1) and not ScaleFits(Scale) do Dec(Scale);
  Settings.Scale := Scale;
  WindowState := wsNormal;
  ClientWidth := SCREEN_WIDTH * Scale + ExtraW;
  ClientHeight := SCREEN_HEIGHT * Scale + ExtraH;
  // The modern palettes need their height, whatever the zoom
  if FModern and (ClientHeight < FModernMinHeight) then ClientHeight := FModernMinHeight;
  if FModern and (ClientWidth < FModernMinWidth) then ClientWidth := FModernMinWidth;
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
  for I := 0 to Min(Settings.RecentSymbols.Count, RECENT_SHOWN) - 1 do
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
  Path: string;
begin
  Index := (Sender as TComponent).Tag;
  if Index < Settings.RecentSymbols.Count then
  begin
    Path := Settings.RecentSymbols[Index];      // a copy: the list changes as it loads
    LoadSymbols(Path);
  end;
end;

{ Whether a recent file makes sense for the machine now: Kind 0 a file opened (judged by its type), 1 a disk image,
  2 an SD card image. Tapes go to the tape, disks to a drive and cards to the reader, and only those the machine
  can use are listed: no .mgt on a +3, no card image on a SAM Coupe. }
function TMainWindow.RecentFits(const FileName: string; Kind: Integer): Boolean;
var
  Ext: string;
  M: TSpectrumModel;
  Memory: TMemoryKind;

  function DiskFits: Boolean;
  begin
    Result := FloppyAvailable and ((Ext = '.dsk') or (IsSAMModel(M) and ((Ext = '.mgt') or (Ext = '.sad'))));
  end;

begin
  Ext := LowerCase(ExtractFileExt(FileName));
  M := FEmu.Spec.Model;
  Memory := FEmu.Spec.Info.Memory;
  case Kind of
    1: Result := DiskFits;
    2: Result := SDAvailable;
    // Tapes and cartridges have lists of their own (the tape and cartridge menus); the files opened
    // include them as well, judged by their type below
    3, 4: Result := RecentFits(FileName, 0);
  else
    if Ext = '.tap' then Result := not (Memory in [mkCPC, mkMSX])      // the SAM Coupé's ROM loads the Spectrum's standard speed blocks
    else if Ext = '.tzx' then Result := True
    else if (Ext = '.cas') or (Ext = '.tsx') then Result := Memory = mkMSX
    else if Ext = '.rom' then Result := Memory = mkMSX
    else if Ext = '.cdt' then Result := Memory = mkCPC
    else if Ext = '.z80' then Result := not (Memory in [mkCPC, mkSAM, mkZXNext])
    else if Ext = '.sna' then Result := (Memory = mkCPC) or not (Memory in [mkSAM, mkZXNext])
    else if Ext = '.nex' then Result := M = smZXNext
    else if Ext = '.e80' then
    begin
      try
        Result := FileExists(FileName) and (TSpectrum.OwnSnapshotModel(FileName) = M);
      except
        Result := False;
      end;
    end
    else Result := DiskFits;
  end;
end;

{ Open recent: the recent files that fit the machine (the files opened, then the disk images and SD card images
  inserted that aren't among them), newest first; opening one puts it where it goes }
procedure TMainWindow.UpdateRecentMenu;
var
  Item: TMenuItem;

  procedure Collect(List: TStringList; Kind: Integer);
  var
    I, J: Integer;
    Dup: Boolean;
  begin
    for I := 0 to List.Count - 1 do
    begin
      if not RecentFits(List[I], Kind) then Continue;
      Dup := False;
      for J := 0 to FRecentOpen.Count - 1 do
        if SameFileName(FRecentOpen[J], List[I]) then Dup := True;
      if not Dup then FRecentOpen.AddObject(List[I], TObject(PtrInt(Kind)));
    end;
  end;

var
  I: Integer;
begin
  if FRecentOpen = nil then FRecentOpen := TStringList.Create;
  FRecentOpen.Clear;
  Collect(Settings.RecentFiles, 0);
  Collect(Settings.RecentDisks, 1);
  Collect(Settings.RecentCards, 2);
  Collect(Settings.RecentTapes, 3);
  Collect(Settings.RecentCarts, 4);
  FRecentMenu.Clear;
  for I := 0 to Min(FRecentOpen.Count, RECENT_SHOWN) - 1 do
  begin
    Item := AddItem(FRecentMenu, Format('&%d %s', [I + 1, FRecentOpen[I]]), @DoOpenRecent);
    Item.Tag := I;
  end;
  FRecentMenu.Enabled := FRecentMenu.Count > 0;
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
  Scale, X, Y, Stride, BytesPP, W, H: Integer;
  RShift, GShift, BShift, AShift: Byte;
  Data, Row: PByte;
  Tmp: array of LongWord;
  Options: TPresentOptions;
  Direct: Boolean;
  P, Native: LongWord;
begin
  Scale := DisplayScale;
  // A CPC or SAM Coupe picture is progressive: the frames aren't the fields of an interlaced one
  if (FEmu.Spec.CPC <> nil) or IsSAMModel(FEmu.Spec.Model) then Options.Deinterlace := dlProgressive
  else Options.Deinterlace := Settings.Deinterlace;
  Options.Monitor := Settings.Monitor;
  Options.Scanlines := Settings.Scanlines;
  Options.Fine := FEmu.Spec.CPC <> nil;
  W := SCREEN_WIDTH * Scale;
  H := SCREEN_HEIGHT * Scale;
  if (FBitmap.Width <> W) or (FBitmap.Height <> H) then FBitmap.SetSize(W, H);
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
    if Direct then
      PresentFrame(@FPixels[0], @FPrevPixels[0], FPixelsOdd, Scale, Options, Data, Stride)
    else
    begin
      // Another pixel format: drawn as BGRA and converted
      SetLength(Tmp, W * H);
      PresentFrame(@FPixels[0], @FPrevPixels[0], FPixelsOdd, Scale, Options, @Tmp[0], W * 4);
      for Y := 0 to H - 1 do
      begin
        Row := @Data[Y * Stride];
        for X := 0 to W - 1 do
        begin
          P := Tmp[Y * W + X];
          Native := (((P shr 16) and $FF) shl RShift) or (((P shr 8) and $FF) shl GShift) or
            ((P and $FF) shl BShift) or (LongWord($FF) shl AShift);
          Move(Native, Row[X * BytesPP], BytesPP);
        end;
      end;
    end;
  finally
    FBitmap.EndUpdate(False);
  end;
end;

procedure TMainWindow.FrameReady(Sender: TObject);
begin
  FEmu.CopyFields(@FPixels[0], @FPrevPixels[0], FPixelsOdd);
  RenderBitmap;
  FDisplay.Invalidate;
end;

procedure TMainWindow.DoCrtc(Sender: TObject);
begin
  Settings.CPCCrtc := (Sender as TMenuItem).Tag - 1;
  FEmu.Lock;
  try
    ApplyContention;
  finally
    FEmu.Unlock;
  end;
  UpdateChecks;
end;

procedure TMainWindow.DoDeinterlace(Sender: TObject);
begin
  Settings.Deinterlace := TDeinterlace((Sender as TMenuItem).Tag);
  UpdateChecks;
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
  // Around the picture: black, or (modern) the window's grey with a dark
  // frame round the screen
  if FModern then FDisplay.Canvas.Brush.Color := MUI_BACK else FDisplay.Canvas.Brush.Color := clBlack;
  FDisplay.Canvas.FillRect(0, 0, FDisplay.Width, Max(R.Top, 0));
  FDisplay.Canvas.FillRect(0, R.Bottom, FDisplay.Width, FDisplay.Height);
  FDisplay.Canvas.FillRect(0, R.Top, Max(R.Left, 0), R.Bottom);
  FDisplay.Canvas.FillRect(R.Right, R.Top, FDisplay.Width, R.Bottom);
  if FModern then
  begin
    FDisplay.Canvas.Brush.Color := MUI_SCREEN_FRAME;
    FDisplay.Canvas.Pen.Color := $00111111;
    FDisplay.Canvas.Rectangle(R.Left - MUIScale(8), R.Top - MUIScale(8), R.Right + MUIScale(8),
      R.Bottom + MUIScale(8));
  end;
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
      TapeText := TapeText + ' ' + Spec.TapeStateText;
      if Spec.Tape.Current < Spec.Tape.Count then
        TapeText := TapeText + ': ' + Spec.Tape[Spec.Tape.Current].Description;
    end;
    // The Play button shows a pause while the tape plays
    if Spec.Tape.Playing then
      FTapePlayButton.ImageIndex := Ord(ikPause)
    else
      FTapePlayButton.ImageIndex := Ord(ikPlay);
    // The disk browser needs a disk in A:, the SD browser a card
    // The browsers need something to browse: from the toolbar and the menus
    HaveDisk := DefaultDrive(Spec) >= 0;
    if IsMSXModel(Spec.Model) then HaveCard := Spec.MSXHw.CartridgeName(1) <> ''
    else HaveCard := Spec.DivMMCOn and (Spec.DivMMC.Card <> nil);
    if FDiskButton.Enabled <> HaveDisk then FDiskButton.Enabled := HaveDisk;
    if FDiskBrowserItem.Enabled <> HaveDisk then FDiskBrowserItem.Enabled := HaveDisk;
    if FSDButton.Enabled <> HaveCard then FSDButton.Enabled := HaveCard;
    // On the MSX the SD card's browser is the cartridge's (CR)
    if IsMSXModel(Spec.Model) then
    begin
      FSDButton.ImageIndex := Ord(ikCartridge);
      FSDButton.Hint := 'Cartridge browser (CR)';
      FSDBrowserItem.Caption := 'Cartridge &browser...';
    end
    else
    begin
      FSDButton.ImageIndex := Ord(ikSDCard);
      FSDButton.Hint := 'SD card browser (DivMMC)';
      FSDBrowserItem.Caption := 'SD card &browser...';
    end;
    if FSDBrowserItem.Enabled <> HaveCard then FSDBrowserItem.Enabled := HaveCard;
    if FCartBrowserItem.Enabled <> (IsMSXModel(Spec.Model) and HaveCard) then FCartBrowserItem.Enabled := IsMSXModel(Spec.Model) and HaveCard;
    FStatus.Panels[0].Text := Spec.Info.Name;
  finally
    FEmu.Unlock;
  end;
  if (FPauseButton.Down <> FEmu.Paused) or (FRecButton.Down <> FEmu.Spec.Recording) then
    UpdateChecks;
  if FEmu.Spec.ForeignCore >= 0 then
  begin
    FEmu.Spec.ForeignCore := -1;
    MessageDlg('ZX Spectrum Next', 'The Next''s firmware tried to start another machine''s core ' +
      '(an extra core, slots 8-31). emu80 emulates only the ZX Spectrum Next core, so the Next ' +
      'starts again instead.', mtInformation, [mbOK], 0);
  end;
  if FEmu.Paused then
    FStatus.Panels[1].Text := 'Paused'
  else
    FStatus.Panels[1].Text := Format('%d fps', [FEmu.Fps]);
  if FEmu.Spec.Speed > 1 then
    FStatus.Panels[1].Text := FStatus.Panels[1].Text + Format(' CPU x%d', [FEmu.Spec.Speed]);
  FStatus.Panels[2].Text := TapeText;
  ModernTick;
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
    if Spec.DiskAt(0) <> nil then
    begin
      State := State or 1;
      if Now - Spec.DiskLastAccess(0) < LIT_MS then State := State or $10;
    end;
    if (Spec.DiskAt(1) <> nil) and Spec.DriveBOn then
    begin
      State := State or 2;
      if Now - Spec.DiskLastAccess(1) < LIT_MS then State := State or $20;
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
    if FModern then FMMediaBox.Invalidate;
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
  Ext: Word;
begin
  if FEmu.Spec.Model in [smCPC464, smCPC664, smCPC6128] then
  begin
    // The CPC's matrix: 10 lines of 8 keys
    for Row := 0 to 9 do
    begin
      Value := $FF;
      for Bit := 0 to 7 do
        if FCPCKeyCount[Row * 8 + Bit] > 0 then Value := Value and not (1 shl Bit);
      FEmu.Spec.CPC.KeyMatrix[Row] := Value;
    end;
    Exit;
  end;
  if IsMSXModel(FEmu.Spec.Model) then
  begin
    // The MSX's matrix: 11 rows of 8 keys, a clear bit for a key down; the joystick as the PSG reads it
    for Row := 0 to MSX_KEY_ROWS - 1 do
    begin
      Value := $FF;
      for Bit := 0 to 7 do
        if FMsxKeyCount[Row * 8 + Bit] > 0 then Value := Value and not (1 shl Bit);
      FEmu.Spec.MSXHw.KeyMatrix[Row] := Value;
    end;
    Value := $3F;
    for Bit := 0 to 5 do
      if FMsxJoy[Bit] > 0 then Value := Value and not (1 shl Bit);
    FEmu.Spec.MSXHw.SetJoystick(0, Value);
    Exit;
  end;
  if IsSAMModel(FEmu.Spec.Model) then
  begin
    // The SAM Coupe's matrix: 9 rows of 8 keys, a set bit for a key down
    for Row := 0 to 8 do
    begin
      Value := 0;
      for Bit := 0 to 7 do
        if SamKeyHeld(Row * 8 + Bit) then Value := Value or (1 shl Bit);
      FEmu.Spec.SAM.Keys[Row] := Value;
    end;
    FEmu.Spec.KempstonState := FKempstonBits;
    Exit;
  end;
  for Row := 0 to 7 do
  begin
    Value := $FF;
    for Bit := 0 to 4 do
      if FKeyCount[Row * 5 + Bit] > 0 then Value := Value and not (1 shl Bit);
    FEmu.Spec.Keyboard[Row] := Value;
  end;
  Ext := 0;
  for Bit := 0 to 15 do
    if FExtCount[Bit] > 0 then Ext := Ext or (1 shl Bit);
  FEmu.Spec.ExtKeys := Ext;
  FEmu.Spec.KempstonState := FKempstonBits;
  FEmu.Spec.FullerState := not FFullerBits;
end;

procedure TMainWindow.MapKey(Key: Word; Down: Boolean);

  procedure Press(K: Integer);
  begin
    if Down then Inc(FKeyCount[K]) else if FKeyCount[K] > 0 then Dec(FKeyCount[K]);
  end;

  { A key that is two Spectrum keys (the Next's keyboard has it alone) }
  procedure Ext(Bit: Integer);
  begin
    if Down then Inc(FExtCount[Bit]) else if FExtCount[Bit] > 0 then Dec(FExtCount[Bit]);
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
  if FEmu.Spec.Model in [smCPC464, smCPC664, smCPC6128] then
  begin
    MapKeyCPC(Key, Down);
    Exit;
  end;
  if IsSAMModel(FEmu.Spec.Model) then
  begin
    MapKeySAM(Key, Down);
    Exit;
  end;
  if IsMSXModel(FEmu.Spec.Model) then
  begin
    MapKeyMSX(Key, Down);
    Exit;
  end;
  // Cursor keys and Ctrl as a joystick: the right one, and the left one too when it is not CAPS SHIFT
  if (Settings.Joystick <> jkNone) and
     ((Key in [VK_LEFT, VK_RIGHT, VK_UP, VK_DOWN, VK_RCONTROL]) or
      (Settings.LeftShiftCaps and (Key in [VK_CONTROL, VK_LCONTROL]))) then
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
    // Left Ctrl is CAPS SHIFT (or the left Shift, with zx_leftshift) and right Shift SYMBOL SHIFT
    // (FormKeyDown/Up tell left from right)
    VK_SHIFT, VK_LSHIFT: if Settings.LeftShiftCaps then Press(KEY_CAPS);
    VK_CONTROL, VK_LCONTROL: if not Settings.LeftShiftCaps then Press(KEY_CAPS);
    VK_RSHIFT: Press(KEY_SYM);
    VK_BACK, VK_DELETE: Ext(EXT_DELETE);
    VK_LEFT: Ext(EXT_LEFT);
    VK_DOWN: Ext(EXT_DOWN);
    VK_UP: Ext(EXT_UP);
    VK_RIGHT: Ext(EXT_RIGHT);
    VK_ESCAPE: Ext(EXT_BREAK);
    VK_TAB: Ext(EXT_EXTEND);                  // extended mode
    VK_INSERT: Ext(EXT_EDIT);
    VK_CAPITAL: Ext(EXT_CAPSLOCK);
    VK_NEXT: Ext(EXT_GRAPH);                  // Page Down
    VK_HOME: Ext(EXT_TRUEVIDEO);
    VK_END: Ext(EXT_INVVIDEO);
    VK_OEM_COMMA: Ext(EXT_COMMA);
    VK_OEM_PERIOD: Ext(EXT_PERIOD);
    VK_OEM_MINUS, VK_SUBTRACT: begin Press(KEY_SYM); Press(KEY_J); end;
    VK_OEM_PLUS: begin Press(KEY_SYM); Press(KEY_L); end;
    VK_ADD: begin Press(KEY_SYM); Press(KEY_K); end;
    VK_MULTIPLY: begin Press(KEY_SYM); Press(KEY_B); end;
    VK_DIVIDE, VK_OEM_2: begin Press(KEY_SYM); Press(KEY_V); end;
    VK_OEM_1: Ext(EXT_SEMICOLON);
    VK_OEM_7: Ext(EXT_QUOTE);
  end;
end;

{ The same for the Amstrad CPC: each PC key is the CPC key in its place (or its
  label); the numeric keypad is the CPC's F0-F9 and F.; the cursor keys are the
  cursor keys and also joystick 1, with the right Ctrl as its fire button }
procedure TMainWindow.MapKeyCPC(Key: Word; Down: Boolean);

  procedure Press(K: Integer);
  begin
    if Down then Inc(FCPCKeyCount[K]) else if FCPCKeyCount[K] > 0 then Dec(FCPCKeyCount[K]);
  end;

const
  Letters: array['A'..'Z'] of Integer = (
    CPCK_A, CPCK_B, CPCK_C, CPCK_D, CPCK_E, CPCK_F, CPCK_G, CPCK_H, CPCK_I, CPCK_J, CPCK_K, CPCK_L,
    CPCK_M, CPCK_N, CPCK_O, CPCK_P, CPCK_Q, CPCK_R, CPCK_S, CPCK_T, CPCK_U, CPCK_V, CPCK_W, CPCK_X,
    CPCK_Y, CPCK_Z);
  Digits: array['0'..'9'] of Integer = (
    CPCK_0, CPCK_1, CPCK_2, CPCK_3, CPCK_4, CPCK_5, CPCK_6, CPCK_7, CPCK_8, CPCK_9);
  FKeys: array[0..9] of Integer = (
    CPCK_F0, CPCK_F1, CPCK_F2, CPCK_F3, CPCK_F4, CPCK_F5, CPCK_F6, CPCK_F7, CPCK_F8, CPCK_F9);
begin
  case Key of
    VK_A..VK_Z: Press(Letters[Chr(Key)]);
    VK_0..VK_9: Press(Digits[Chr(Key)]);
    VK_NUMPAD0..VK_NUMPAD9: Press(FKeys[Key - VK_NUMPAD0]);
    VK_DECIMAL: Press(CPCK_FDOT);
    VK_RETURN: Press(CPCK_RETURN);
    VK_SPACE: Press(CPCK_SPACE);
    VK_SHIFT, VK_LSHIFT, VK_RSHIFT: Press(CPCK_SHIFT);
    VK_LCONTROL: Press(CPCK_CONTROL);
    VK_CONTROL: Press(CPCK_CONTROL);
    VK_RCONTROL: if Settings.CPCJoystick then Press(CPCK_JFIRE1) else Press(CPCK_CONTROL);
    VK_ESCAPE: Press(CPCK_ESC);
    VK_TAB: Press(CPCK_TAB);
    VK_CAPITAL: Press(CPCK_CAPSLOCK);
    VK_BACK: Press(CPCK_DEL);
    VK_DELETE: Press(CPCK_CLR);
    VK_INSERT: Press(CPCK_COPY);
    VK_LEFT: begin Press(CPCK_LEFT); if Settings.CPCJoystick then Press(CPCK_JLEFT); end;
    VK_RIGHT: begin Press(CPCK_RIGHT); if Settings.CPCJoystick then Press(CPCK_JRIGHT); end;
    VK_UP: begin Press(CPCK_UP); if Settings.CPCJoystick then Press(CPCK_JUP); end;
    VK_DOWN: begin Press(CPCK_DOWN); if Settings.CPCJoystick then Press(CPCK_JDOWN); end;
    VK_OEM_COMMA: Press(CPCK_COMMA);
    VK_OEM_PERIOD: Press(CPCK_DOT);
    VK_OEM_2: Press(CPCK_SLASH);
    VK_OEM_MINUS, VK_SUBTRACT: Press(CPCK_MINUS);
    VK_OEM_PLUS: Press(CPCK_CARET);
    VK_OEM_1: Press(CPCK_SEMICOLON);
    VK_OEM_7: Press(CPCK_COLON);
    VK_OEM_3: Press(CPCK_AT);
    VK_OEM_4: Press(CPCK_LBRACKET);
    VK_OEM_6: Press(CPCK_RBRACKET);
    VK_OEM_5: Press(CPCK_BACKSLASH);
    VK_ADD: begin Press(CPCK_SHIFT); Press(CPCK_SEMICOLON); end;
    VK_MULTIPLY: begin Press(CPCK_SHIFT); Press(CPCK_COLON); end;
    VK_DIVIDE: Press(CPCK_SLASH);
  end;
end;

{ The same for the MSX: each PC key is the MSX key in its place (the keyboard is the international
  one); Ctrl is CTRL, Page Up CODE, Page Down GRAPH, End SELECT, Pause STOP, Backspace BS; the numeric
  keypad 1-5 are F1-F5 (the PC's F keys are the emulator's) and its other digits the digits; the cursor
  keys are the cursor keys and also joystick 1, with the right Ctrl as its fire button }
procedure TMainWindow.MapKeyMSX(Key: Word; Down: Boolean);

  procedure Press(K: Integer);
  begin
    if Down then Inc(FMsxKeyCount[K]) else if FMsxKeyCount[K] > 0 then Dec(FMsxKeyCount[K]);
  end;

  procedure Joy(Bit: Integer);
  begin
    if not Settings.MsxJoystick then Exit;
    if Down then Inc(FMsxJoy[Bit]) else if FMsxJoy[Bit] > 0 then Dec(FMsxJoy[Bit]);
  end;

const
  Letters: array['A'..'Z'] of Integer = (
    MSXK_A, MSXK_B, MSXK_C, MSXK_D, MSXK_E, MSXK_F, MSXK_G, MSXK_H, MSXK_I, MSXK_J, MSXK_K, MSXK_L,
    MSXK_M, MSXK_N, MSXK_O, MSXK_P, MSXK_Q, MSXK_R, MSXK_S, MSXK_T, MSXK_U, MSXK_V, MSXK_W, MSXK_X,
    MSXK_Y, MSXK_Z);
  Digits: array['0'..'9'] of Integer = (
    MSXK_0, MSXK_1, MSXK_2, MSXK_3, MSXK_4, MSXK_5, MSXK_6, MSXK_7, MSXK_8, MSXK_9);
  PadF: array[1..5] of Integer = (MSXK_F1, MSXK_F2, MSXK_F3, MSXK_F4, MSXK_F5);
begin
  case Key of
    VK_A..VK_Z: Press(Letters[Chr(Key)]);
    VK_0..VK_9: Press(Digits[Chr(Key)]);
    VK_NUMPAD0: Press(MSXK_0);
    VK_NUMPAD1..VK_NUMPAD5: Press(PadF[Key - VK_NUMPAD0]);
    VK_NUMPAD6..VK_NUMPAD9: Press(Digits[Chr(Ord('0') + Key - VK_NUMPAD0)]);
    VK_RETURN: Press(MSXK_RETURN);
    VK_SPACE: Press(MSXK_SPACE);
    VK_SHIFT, VK_LSHIFT, VK_RSHIFT: Press(MSXK_SHIFT);
    VK_LCONTROL: Press(MSXK_CTRL);
    VK_CONTROL: Press(MSXK_CTRL);
    VK_RCONTROL: if Settings.MsxJoystick then Joy(4) else Press(MSXK_CTRL);
    VK_ESCAPE: Press(MSXK_ESC);
    VK_TAB: Press(MSXK_TAB);
    VK_CAPITAL: Press(MSXK_CAPS);
    VK_BACK: Press(MSXK_BS);
    VK_DELETE: Press(MSXK_DEL);
    VK_INSERT: Press(MSXK_INS);
    VK_HOME: Press(MSXK_HOME);
    VK_END: Press(MSXK_SELECT);
    VK_PRIOR: Press(MSXK_CODE);
    VK_NEXT: Press(MSXK_GRAPH);
    VK_PAUSE: Press(MSXK_STOP);
    VK_LEFT: begin Press(MSXK_LEFT); Joy(2); end;
    VK_RIGHT: begin Press(MSXK_RIGHT); Joy(3); end;
    VK_UP: begin Press(MSXK_UP); Joy(0); end;
    VK_DOWN: begin Press(MSXK_DOWN); Joy(1); end;
    VK_OEM_COMMA, VK_DECIMAL: if Key = VK_DECIMAL then Press(MSXK_PERIOD) else Press(MSXK_COMMA);
    VK_OEM_PERIOD: Press(MSXK_PERIOD);
    VK_OEM_2, VK_DIVIDE: Press(MSXK_SLASH);
    VK_OEM_MINUS, VK_SUBTRACT: Press(MSXK_MINUS);
    VK_OEM_PLUS: Press(MSXK_EQUALS);
    VK_OEM_1: Press(MSXK_SEMICOLON);
    VK_OEM_7: Press(MSXK_QUOTE);
    VK_OEM_3: Press(MSXK_GRAVE);
    VK_OEM_4: Press(MSXK_LBRACKET);
    VK_OEM_6: Press(MSXK_RBRACKET);
    VK_OEM_5: Press(MSXK_BACKSLASH);
    VK_ADD: begin Press(MSXK_SHIFT); Press(MSXK_EQUALS); end;
    VK_MULTIPLY: begin Press(MSXK_SHIFT); Press(MSXK_8); end;
  end;
end;

{ Cartridges (the MSX): a .rom file goes into the first cartridge slot, with the mapper the Cartridge menu
  says (auto-detected unless chosen); the computer restarts with it, as if it had been inserted and switched on }
procedure TMainWindow.InsertCartridgeFile(const FileName: string);
var
  F: TFileStream;
  Data: array of Byte;
  Kind: TMsxMapperKind;
  Auto: Boolean;
  Used: TMsxMapperKind;
begin
  if not IsMSXModel(FEmu.Spec.Model) then
  begin
    ChangeModel(smMSX2);
    if not IsMSXModel(FEmu.Spec.Model) then Exit;
  end;
  try
    F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
    try
      if (F.Size < 16) or (F.Size > 4 * 1024 * 1024) then
        raise Exception.Create('That does not look like an MSX cartridge: its size is ' + IntToStr(F.Size) + ' bytes.');
      SetLength(Data, F.Size);
      F.ReadBuffer(Data[0], F.Size);
    finally
      F.Free;
    end;
    Auto := not MapperFromName(Settings.MsxCartMapper, Kind);
    FEmu.Lock;
    try
      Used := FEmu.Spec.MSXHw.InsertCartridge(1, ChangeFileExt(ExtractFileName(FileName), ''), Data[0],
        Length(Data), Auto, Kind);
      FEmu.Spec.Reset(True);
    finally
      FEmu.Unlock;
    end;
    FCartFile := FileName;
    CartFileName := FileName;
    CartOnSaved := @CartSaved;
    RefreshCartBrowser;
    Settings.AddRecentCart(FileName);
    Settings.LastDir := ExtractFilePath(FileName);   // the dialogs open there next, as for tapes and disks
    UpdateRecentMenu;
    UpdateRecentDisksMenu;
    FStatus.Panels[0].Text := FEmu.Spec.Info.Name + ': ' + ExtractFileName(FileName) + ' (' + MapperName(Used) + ')';
  except
    on E: Exception do
      MessageDlg('Could not insert ' + ExtractFileName(FileName) + ':' + LineEnding + E.Message, mtError, [mbOK], 0);
  end;
end;

procedure TMainWindow.DoCartInsert(Sender: TObject);
var
  Dlg: TOpenDialog;
begin
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Filter := 'MSX cartridges (*.rom)|*.rom|All files|*.*';
    Dlg.InitialDir := Settings.LastDir;
    Dlg.Options := Dlg.Options + [ofFileMustExist];
    if Dlg.Execute then InsertCartridgeFile(Dlg.FileName);
  finally
    Dlg.Free;
  end;
end;

procedure TMainWindow.DoCartEject(Sender: TObject);
begin
  if not IsMSXModel(FEmu.Spec.Model) then Exit;
  FEmu.Lock;
  try
    FEmu.Spec.MSXHw.RemoveRom(1);
    FEmu.Spec.Reset(True);
  finally
    FEmu.Unlock;
  end;
  FCartFile := '';
  CartFileName := '';
  RefreshCartBrowser;
end;

{ The mapper for the cartridges: chosen in the menu; a cartridge already in is inserted again with it }
procedure TMainWindow.DoCartMapper(Sender: TObject);
begin
  Settings.MsxCartMapper := CART_MAPPER_KEYS[(Sender as TComponent).Tag];
  (Sender as TMenuItem).Checked := True;
  if (FCartFile <> '') and FileExists(FCartFile) and IsMSXModel(FEmu.Spec.Model) then InsertCartridgeFile(FCartFile);
end;

{ The same for the SAM Coupe: each PC key is the SAM key in its place (or its
  label); the right Shift is SYMBOL, Insert is EDIT, Backspace and Delete are DELETE; the
  numeric keypad is the SAM's F0-F9 (the PC's F keys are the emulator's) }
procedure TMainWindow.MapKeySAM(Key: Word; Down: Boolean);

  procedure Press(K: Integer);
  begin
    if Down then Inc(FSamKeyCount[K]) else if FSamKeyCount[K] > 0 then Dec(FSamKeyCount[K]);
  end;

  { The Kempston joystick: the cursor keys and the right Ctrl, if it is on }
  procedure Joy(Bit: Byte);
  begin
    if not Settings.SamJoystick then Exit;
    if Down then FKempstonBits := FKempstonBits or Bit else FKempstonBits := FKempstonBits and not Bit;
  end;

const
  Letters: array['A'..'Z'] of Integer = (
    SAMK_A, SAMK_B, SAMK_C, SAMK_D, SAMK_E, SAMK_F, SAMK_G, SAMK_H, SAMK_I, SAMK_J, SAMK_K, SAMK_L,
    SAMK_M, SAMK_N, SAMK_O, SAMK_P, SAMK_Q, SAMK_R, SAMK_S, SAMK_T, SAMK_U, SAMK_V, SAMK_W, SAMK_X,
    SAMK_Y, SAMK_Z);
  Digits: array['0'..'9'] of Integer = (
    SAMK_0, SAMK_1, SAMK_2, SAMK_3, SAMK_4, SAMK_5, SAMK_6, SAMK_7, SAMK_8, SAMK_9);
  FKeys: array[0..9] of Integer = (
    SAMK_F0, SAMK_F1, SAMK_F2, SAMK_F3, SAMK_F4, SAMK_F5, SAMK_F6, SAMK_F7, SAMK_F8, SAMK_F9);
begin
  // Alt+F1..F10 are the SAM's F1..F9 and F0
  if (Key <= High(FSamRoute)) and (FSamRoute[Key] = 2) then
  begin
    if Key = VK_F10 then Press(SAMK_F0) else Press(FKeys[Key - VK_F1 + 1]);
    if not Down then FSamRoute[Key] := 0;
    Exit;
  end;
  // By character: the chord was pressed when the character came (FormUTF8KeyPress)
  if (Key <= High(FSamRoute)) and (FSamRoute[Key] = 1) then
  begin
    if not Down then
    begin
      if FSamChordKey[Key] >= 0 then
      begin
        Dec(FSamChordKeys[FSamChordKey[Key]]);
        if FSamChordMod[Key] >= 0 then Dec(FSamChordKeys[FSamChordMod[Key]]);
        Dec(FSamChordActive);
        FSamChordKey[Key] := -1;
      end;
      FSamRoute[Key] := 0;
    end;
    Exit;
  end;
  case Key of
    VK_A..VK_Z: Press(Letters[Chr(Key)]);
    VK_0..VK_9: Press(Digits[Chr(Key)]);
    VK_NUMPAD0..VK_NUMPAD9: Press(FKeys[Key - VK_NUMPAD0]);
    VK_RETURN: Press(SAMK_RETURN);
    VK_SPACE: Press(SAMK_SPACE);
    // Left Shift is SHIFT and right Shift SYMBOL, as on the Spectrum (FormKeyDown/Up tell them apart)
    VK_SHIFT, VK_LSHIFT: Press(SAMK_SHIFT);
    VK_RSHIFT: Press(SAMK_SYMBOL);
    VK_CONTROL, VK_LCONTROL: Press(SAMK_CTRL);
    VK_RCONTROL:
      if Settings.SamJoystick then Joy($10) else Press(SAMK_CTRL);   // fire
    VK_ESCAPE: Press(SAMK_ESC);
    VK_TAB: Press(SAMK_TAB);
    VK_CAPITAL: Press(SAMK_CAPS);
    VK_BACK, VK_DELETE: Press(SAMK_DELETE);
    VK_INSERT: Press(SAMK_EDIT);
    VK_END: Press(SAMK_INV);
    VK_LEFT: begin Press(SAMK_LEFT); Joy($02); end;
    VK_RIGHT: begin Press(SAMK_RIGHT); Joy($01); end;
    VK_UP: begin Press(SAMK_UP); Joy($08); end;
    VK_DOWN: begin Press(SAMK_DOWN); Joy($04); end;
    VK_ADD: Press(SAMK_PLUS);
    VK_SUBTRACT: Press(SAMK_MINUS);
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
var
  IsSam, AltGr, SamF, ByChar: Boolean;
begin
  // The modern interface has no menu bar to take its shortcuts
  if FModern and MenuShortcut(Key, Shift) then
  begin
    Key := 0;
    Exit;
  end;
  IsSam := IsSAMModel(FEmu.Spec.Model);
  // AltGr is Ctrl+Alt: on a SAM it makes characters ([ ] { } @ # \ | on a Spanish keyboard)
  AltGr := (ssAltGr in Shift) or ((ssAlt in Shift) and (ssCtrl in Shift));
  // The SAM's F keys are Alt+F1..F10 (the others are the emulator's)
  SamF := IsSam and (ssAlt in Shift) and not AltGr and (Key >= VK_F1) and (Key <= VK_F10);
  if (Key >= VK_F1) and (Key <= VK_F24) and not SamF then Exit;    // leave function keys to the menu
  if not SamF and ((Key = VK_MENU) or ((ssAlt in Shift) and not (IsSam and AltGr))) then Exit;
  Key := SidedKey(Key);
  // The SAM takes the characters from the keyboard layout, so any layout can type them all
  ByChar := IsSam and (Key <= High(FSamRoute)) and SamCharKey(Key) and (not (ssCtrl in Shift) or AltGr);
  if Key <= High(FPCKeyDown) then
  begin
    if FPendingUp[Key] <> 0 then ReleasePCKey(Key);   // finish a pending tap first
    if not FPCKeyDown[Key] then
    begin
      FPCKeyDown[Key] := True;
      FPCKeyTime[Key] := GetTickCount64;
      if SamF then FSamRoute[Key] := 2
      else if ByChar then
      begin
        FSamRoute[Key] := 1;
        FSamChordKey[Key] := -1;
        FSamLastCharVK := Key;
      end;
      if not ByChar then
      begin
        MapKey(Key, True);
        UpdateKeyboard;
      end;
    end;
  end;
  // The character comes next, from the key's press
  if not ByChar then Key := 0;
end;

{ Keys that make a character the SAM may take: letters, digits and the layout's signs }
function TMainWindow.SamCharKey(Key: Word): Boolean;
begin
  Result := ((Key >= VK_A) and (Key <= VK_Z)) or ((Key >= VK_0) and (Key <= VK_9)) or
    ((Key >= VK_OEM_1) and (Key <= VK_OEM_3)) or ((Key >= VK_OEM_4) and (Key <= VK_OEM_8)) or
    (Key = VK_OEM_102);
end;

{ The character a key made: the SAM keys that make it on its keyboard }
procedure TMainWindow.FormUTF8KeyPress(Sender: TObject; var UTF8Key: TUTF8Char);
var
  VK: Word;
  K, M: Integer;
begin
  VK := FSamLastCharVK;
  if not IsSAMModel(FEmu.Spec.Model) or (VK > High(FSamRoute)) or (FSamRoute[VK] <> 1) or
     not FPCKeyDown[VK] then Exit;
  // An auto-repeat gives the same character again: the chord is down already
  if (FSamChordKey[VK] < 0) and (Length(UTF8Key) = 1) and SamKeysForChar(UTF8Key[1], K, M) then
  begin
    FSamChordKey[VK] := K;
    FSamChordMod[VK] := M;
    Inc(FSamChordKeys[K]);
    if M >= 0 then Inc(FSamChordKeys[M]);
    Inc(FSamChordActive);
    UpdateKeyboard;
  end;
  UTF8Key := '';    // the machine, not a control, takes it
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

  procedure Release(K: Word);
  var
    Held: QWord;
  begin
    if (K > High(FPCKeyDown)) or not FPCKeyDown[K] then Exit;
    Held := GetTickCount64 - FPCKeyTime[K];
    if Held >= MIN_HOLD_MS then
      ReleasePCKey(K)
    else
    begin
      // Too short for the Spectrum to notice: release it a little later
      FPendingUp[K] := FPCKeyTime[K] + MIN_HOLD_MS;
      FKeyTimer.Enabled := True;
    end;
  end;

  { With both Shifts (or both Ctrls) down Windows reports the release of only one of them, so the other
    would stay down for the emulated machine (the Spectrum's extended mode then gave the shifted keywords):
    one that is down for us and no longer for the keyboard is up }
  procedure ReleaseGone(L, R: Word);
  begin
    if FPCKeyDown[L] and (GetKeyState(L) >= 0) then Release(L);
    if FPCKeyDown[R] and (GetKeyState(R) >= 0) then Release(R);
  end;

var
  Generic: Word;
begin
  if (Key >= VK_F1) and (Key <= VK_F24) and ((Key > High(FSamRoute)) or (FSamRoute[Key] <> 2)) then Exit;
  Generic := Key;
  Key := ReleasedSide(Key);
  Release(Key);
  if Generic = VK_SHIFT then ReleaseGone(VK_LSHIFT, VK_RSHIFT)
  else if Generic = VK_CONTROL then ReleaseGone(VK_LCONTROL, VK_RCONTROL);
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

{ A SAM key is down: a PC key for it, or a chord; while a chord is held the Shift, Symbol and Ctrl
  of the PC are not the SAM's (the character wanted says which it needs) }
function TMainWindow.SamKeyHeld(K: Integer): Boolean;
begin
  Result := FSamChordKeys[K] > 0;
  if not Result and ((FSamChordActive = 0) or not (K in [SAMK_SHIFT, SAMK_SYMBOL, SAMK_CTRL])) then
    Result := FSamKeyCount[K] > 0;
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
  for I := 0 to High(FExtCount) do FExtCount[I] := 0;
  for I := 0 to High(FCPCKeyCount) do FCPCKeyCount[I] := 0;
  for I := 0 to High(FSamKeyCount) do FSamKeyCount[I] := 0;
  for I := 0 to High(FMsxKeyCount) do FMsxKeyCount[I] := 0;
  for I := 0 to High(FMsxJoy) do FMsxJoy[I] := 0;
  for I := 0 to High(FSamChordKeys) do FSamChordKeys[I] := 0;
  for I := 0 to High(FSamRoute) do
  begin
    FSamRoute[I] := 0;
    FSamChordKey[I] := -1;
  end;
  FSamChordActive := 0;
  FKempstonBits := 0;
  FFullerBits := 0;
  UpdateKeyboard;
end;

procedure TMainWindow.FormDeactivate(Sender: TObject);
begin
  // Key-up events are lost while another window has focus
  ReleaseAllKeys;
  ReleaseMouseClip;
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
  // The window exists now: its title bar can be made dark
  SetDarkTitle(Self, FModern);
  // The command line can open windows (debugger, documentation), so it runs
  // once the main window exists
  if not FStarted then
  begin
    FStarted := True;
    if FShowNotice then ShowNotice;
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
  FInCommandLine := True;
  try
    ProcessCommandLine;
  finally
    FInCommandLine := False;
  end;
  SamDosBoot;
  if FStartNext and (Settings.Model = sm48K) and (FEmu.Spec.Model = sm48K) then ChangeModel(smZXNext);
  FStartNext := False;
  if Settings.Scale <> OldScale then SetScale(Settings.Scale);
  MsxNotice;                            // (the machine may have started as an MSX)
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
  M: TSpectrumModel;
  Ext: string;
  Disk, Dos: TDiskImage;
  CPCNote: string;
begin
  CPCNote := '';
  Ext := LowerCase(ExtractFileExt(FileName));
  if Ext = '.rom' then
  begin
    InsertCartridgeFile(FileName);
    Exit;
  end;
  // Snapshots and disks switch the Next to a standard model: its card first
  if (FEmu.Spec.Model = smZXNext) and ((Ext = '.sna') or (Ext = '.z80') or (Ext = '.dsk') or
     (Ext = '.mgt') or (Ext = '.sad')) then
    LeaveNext;
  // A .nex program needs the Next; an .e80 snapshot its machine
  if (Ext = '.nex') and (FEmu.Spec.Model <> smZXNext) then
  begin
    ChangeModel(smZXNext);
    if FEmu.Spec.Model <> smZXNext then Exit;
  end;
  // A CPC tape (.cdt) needs a CPC; a Spectrum tape (.tap) can't be loaded on one
  if (Ext = '.cdt') and not (FEmu.Spec.Model in [smCPC464, smCPC664, smCPC6128]) then
  begin
    ChangeModel(smCPC464);
    if FEmu.Spec.CPC = nil then Exit;
  end;
  // An MSX tape (.cas) needs an MSX; a Spectrum tape (.tap) can't be loaded on one
  if ((Ext = '.cas') or (Ext = '.tsx')) and not IsMSXModel(FEmu.Spec.Model) then
  begin
    ChangeModel(smMSX2);
    if not IsMSXModel(FEmu.Spec.Model) then Exit;
  end;
  if (Ext = '.tap') and IsMSXModel(FEmu.Spec.Model) then
  begin
    MessageDlg('Could not open ' + ExtractFileName(FileName) + ':' + LineEnding +
      'A .tap file is a ZX Spectrum tape; the MSX uses .cas tapes.', mtError, [mbOK], 0);
    Exit;
  end;
  if (Ext = '.tap') and (FEmu.Spec.CPC <> nil) then
  begin
    MessageDlg('Could not open ' + ExtractFileName(FileName) + ':' + LineEnding +
      'A .tap file is a ZX Spectrum tape; the Amstrad CPC uses .cdt (or .tzx) tapes.',
      mtError, [mbOK], 0);
    Exit;
  end;
  if Ext = '.e80' then
  begin
    try
      M := TSpectrum.OwnSnapshotModel(FileName);
    except
      on E: Exception do
      begin
        MessageDlg('Could not open ' + ExtractFileName(FileName) + ':' + LineEnding + E.Message,
          mtError, [mbOK], 0);
        Exit;
      end;
    end;
    if FEmu.Spec.Model <> M then
    begin
      ChangeModel(M);
      if FEmu.Spec.Model <> M then Exit;
    end;
  end;
  FEmu.Lock;
  try
    try
      if (Ext = '.tap') or (Ext = '.tzx') or (Ext = '.cdt') or (Ext = '.cas') or (Ext = '.tsx') then
      begin
        FEmu.Spec.Tape.LoadFile(FileName);
        Settings.AddRecentTape(FileName);
        // A CPC reads its own signals: a Spectrum standard-speed block (what a
        // .tzx made for the Spectrum has) plays, but nothing will load from it
        if (FEmu.Spec.CPC <> nil) and (FEmu.Spec.Tape.CountKind(TZX_STANDARD) > 0) then
          CPCNote := Format('%s has %d block(s) of the ZX Spectrum''s standard tape speed, which an ' +
            'Amstrad CPC can''t load. The tape is inserted anyway; its other blocks play as they are.',
            [ExtractFileName(FileName), FEmu.Spec.Tape.CountKind(TZX_STANDARD)]);
        // On the Next the tape is loaded from NextZXOS (LOAD "" or the Browser)
        if AutoStart and (FEmu.Spec.Model <> smZXNext) then FEmu.Spec.AutoLoad;
      end
      else if Ext = '.sna' then
        LoadSNA(FEmu.Spec, FileName)
      else if Ext = '.z80' then
        LoadZ80(FEmu.Spec, FileName)
      else if Ext = '.nex' then
        FEmu.Spec.LoadNex(FileName)
      else if Ext = '.e80' then
        FEmu.Spec.LoadOwnSnapshot(FileName)
      else if (Ext = '.dsk') or (Ext = '.mgt') or (Ext = '.sad') then
      begin
        if not LoadDiskChecked(FileName, Disk, CPCNote) then
          raise Exception.Create(CPCNote);
        CPCNote := '';
        // A CPC without a disc drive (the 464) becomes a 6128; the other models a +3
        if not FEmu.Spec.Info.HasFDC then
        begin
          if FEmu.Spec.CPC <> nil then FEmu.Spec.SetModel(smCPC6128) else FEmu.Spec.SetModel(smPlus3);
        end;
        Dos := nil;
        if CliSamDos then Dos := SamDosDisk;
        if Dos <> nil then
          FEmu.Spec.SamDosThen(Dos, Disk)
        else
        begin
          FEmu.Spec.InsertDiskAt(0, Disk);
          if AutoStart then FEmu.Spec.AutoLoad(True);
        end;
        Settings.AddRecentDisk(FileName);
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
  Caption := 'emu80 - ' + ExtractFileName(FileName);
  if TapeBrowserWindow <> nil then TapeBrowserWindow.Refresh(True);
  if CPCNote <> '' then MessageDlg('Amstrad CPC tape', CPCNote, mtWarning, [mbOK], 0);
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

{ The tapes the machine reads: a CPC's are .cdt and .tzx, the others' .tap and .tzx }
function TMainWindow.TapeFilter: string;
begin
  if FEmu.Spec.Info.Memory = mkCPC then
    Result := 'Tape images (*.cdt;*.tzx)|*.cdt;*.tzx'
  else if FEmu.Spec.Info.Memory = mkMSX then
    Result := 'MSX tape images (*.cas;*.tsx;*.tzx)|*.cas;*.tsx;*.tzx'
  else
    Result := 'Tape images (*.tap;*.tzx)|*.tap;*.tzx';
end;

{ A tape into the recorder (a click on the cassette in the modern interface): as File > Open,
  for tapes only }
procedure TMainWindow.DoTapeInsert(Sender: TObject);
begin
  InsertTapeDialog(True);
end;

{ Just the tape into the recorder: no autoload }
procedure TMainWindow.DoTapeInsertOnly(Sender: TObject);
begin
  InsertTapeDialog(False);
end;

procedure TMainWindow.InsertTapeDialog(AutoStart: Boolean);
var
  Dlg: TOpenDialog;
begin
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Title := 'Insert a tape';
    Dlg.Filter := TapeFilter;
    Dlg.InitialDir := Settings.LastDir;
    Dlg.Options := Dlg.Options + [ofFileMustExist];
    if Dlg.Execute then OpenFile(Dlg.FileName, AutoStart);
  finally
    Dlg.Free;
  end;
end;

procedure TMainWindow.DoOpenRecent(Sender: TObject);
var
  Index: Integer;
  Path: string;
begin
  Index := (Sender as TComponent).Tag;
  if (FRecentOpen = nil) or (Index >= FRecentOpen.Count) then Exit;
  // A copy of the name: the lists (and this menu) are rebuilt while the file is opened
  Path := FRecentOpen[Index];
  Settings.LastDir := ExtractFilePath(Path);       // the dialogs open there next, as after an Insert
  case PtrInt(FRecentOpen.Objects[Index]) of
    1: if ConfirmDiskChanges(0) then InsertDiskFile(0, Path);
    2: InsertSDCard(Path);
    4: InsertCartridgeFile(Path);
  else
    OpenFile(Path);       // (a tape too)
  end;
end;

procedure TMainWindow.DoSaveSnapshot(Sender: TObject);
var
  Dlg: TSaveDialog;
  FileName, Ext: string;
begin
  Dlg := TSaveDialog.Create(Self);
  try
    // .z80 and .sna can't hold the Next or the ZX-Uno: emu80's own format;
    // the others have it as a choice, .z80 first
    if FEmu.Spec.CPC <> nil then
    begin
      // The CPC's own .SNA (CPCEmu, Winape), or emu80's
      Dlg.Filter := 'CPC snapshot (*.sna)|*.sna|emu80 snapshot (*.e80)|*.e80';
      Dlg.DefaultExt := 'sna';
    end
    else if FEmu.Spec.NeedsOwnSnapshot then
    begin
      Dlg.Filter := 'emu80 snapshot (*.e80)|*.e80';
      Dlg.DefaultExt := 'e80';
    end
    else
    begin
      Dlg.Filter := 'Z80 snapshot (*.z80)|*.z80|SNA snapshot (*.sna)|*.sna|emu80 snapshot (*.e80)|*.e80';
      Dlg.DefaultExt := 'z80';
      Dlg.FilterIndex := 1;
    end;
    Dlg.InitialDir := Settings.LastDir;
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    if not Dlg.Execute then Exit;
    // The format: by the name's extension, else by the type chosen
    FileName := Dlg.FileName;
    Ext := LowerCase(ExtractFileExt(FileName));
    if FEmu.Spec.CPC <> nil then
    begin
      if Ext <> '.e80' then
      begin
        if (Ext <> '.sna') and (Dlg.FilterIndex = 2) then Ext := '.e80' else Ext := '.sna';
      end;
    end
    else if FEmu.Spec.NeedsOwnSnapshot then
      Ext := '.e80'
    else if (Ext <> '.z80') and (Ext <> '.sna') and (Ext <> '.e80') then
      case Dlg.FilterIndex of
        2: Ext := '.sna';
        3: Ext := '.e80';
      else
        Ext := '.z80';
      end;
    FileName := ChangeFileExt(FileName, Ext);
    FEmu.Lock;
    try
      if Ext = '.e80' then
        FEmu.Spec.SaveOwnSnapshot(FileName)
      else if Ext = '.sna' then
        SaveSNA(FEmu.Spec, FileName)
      else
        SaveZ80(FEmu.Spec, FileName);
    finally
      FEmu.Unlock;
    end;
    Settings.AddRecent(FileName);
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

{ ZX Spectrum Next }

function SaveCardInPlace(Emu: TEmulator; out Err: string): Boolean; forward;
function AskSize(const Caption, Info: string; MinMB, DefaultMB: Integer; out SizeMB: Integer): Boolean; forward;

{ Make the Next's card from its distribution, showing that it is busy }
{ The size of a new Next card: the distribution must fit, with room left
  (FAT16: up to 2 GB) }
function AskNextCardSize(out SizeMB: Integer): Boolean;
var
  Entries, DistroMB: Integer;
begin
  DistroMB := Integer(FolderSize(NextDistroDir, Entries) div (1024 * 1024)) + 1;
  Result := AskSize('ZX Spectrum Next SD card', Format('A new card for the ZX Spectrum Next, ' +
    'with its distribution (%d MB) and room for your files.', [DistroMB]),
    DistroMB * 5 div 4 + 16, 512, SizeMB);
end;

function TMainWindow.MakeNextCardFile(const FileName: string; SizeMB: Integer): Boolean;
var
  OldStatus: string;
begin
  // No size given: ask it
  if (SizeMB = 0) and not AskNextCardSize(SizeMB) then Exit(False);
  Result := True;
  OldStatus := FStatus.Panels[2].Text;
  FStatus.Panels[2].Text := 'Making the ZX Spectrum Next SD card...';
  Screen.Cursor := crHourGlass;
  Application.ProcessMessages;
  try
    try
      MakeNextCard(NextDistroDir, FileName, SizeMB);
      Settings.NextDistroId := NextCard.NextDistroId(NextDistroDir);
    except
      on E: Exception do
      begin
        Result := False;
        MessageDlg('Could not make the ZX Spectrum Next SD card: ' + E.Message, mtError, [mbOK], 0);
      end;
    end;
  finally
    Screen.Cursor := crDefault;
    FStatus.Panels[2].Text := OldStatus;
  end;
end;

{ Before switching to the Next: its distribution must be there; its card is
  made the first time (and again, if asked, for a new distribution) and
  put in its DivMMC. False: it can't be used (said why). }
function TMainWindow.PrepareNext: Boolean;
var
  Dir, Card, Id, Old: string;
  Vol: TFatVolume;
  Repaired: TStringList;
begin
  Result := False;
  // First of all: what the Next says it is (and the warning, if it asks to be a real one)
  ConfirmRealSpecNext;
  Dir := NextDistroDir;
  // Not there (it can't come with emu80): where to get it and how to install
  // it; the machine stays as it was (or emu80 closes, started on it)
  if not NextDistroReady(Dir) then
  begin
    NoNextDistro;
    Exit;
  end;
  Card := NextCardFile;
  Id := NextCard.NextDistroId(Dir);
  if not FileExists(Card) then
  begin
    // Just installed: straight on, the card of the usual size
    if FNextJustInstalled then
    begin
      if not MakeNextCardFile(Card, NEXT_CARD_MB) then Exit;
    end
    else if not MakeNextCardFile(Card) then Exit;
  end
  else if (Settings.NextDistroId <> '') and (Settings.NextDistroId <> Id) then
  begin
    Old := ChangeFileExt(Card, '') + '-' + FormatDateTime('yyyymmdd-hhnn', Now) + ExtractFileExt(Card);
    if MessageDlg('ZX Spectrum Next', Format('There is a new ZX Spectrum Next distribution (%s). ' +
      'Make a new SD card from it?' + LineEnding + LineEnding + 'The current card is kept as %s.',
      [NextDistroVersion(Dir), ExtractFileName(Old)]), mtConfirmation, [mbYes, mbNo], 0) = mrYes then
    begin
      if not RenameFile(Card, Old) then
      begin
        MessageDlg('Could not rename ' + Card, mtError, [mbOK], 0);
        Exit;
      end;
      if not MakeNextCardFile(Card) then Exit;
    end
    else
      Settings.NextDistroId := Id;    // not asked again for this one
  end
  else if Settings.NextDistroId = '' then
    Settings.NextDistroId := Id;
  // The other models' card first (its changes saved, or not, as the user says)
  if not ConfirmCardChanges then Exit;
  Repaired := nil;
  FEmu.Lock;
  try
    try
      FEmu.Spec.DivMMC.InsertCard(Card);
      Result := True;
    except
      on E: Exception do
        MessageDlg('Could not use the SD card ' + Card + ': ' + E.Message, mtError, [mbOK], 0);
    end;
    // Files that older versions of emu80 left empty, mended from the distribution
    if Result then
      try
        Vol := TFatVolume.Create(FEmu.Spec.DivMMC.Card.Stream);
        try
          Repaired := RepairNextCard(Vol, Dir);
        finally
          Vol.Free;
        end;
      except
        FreeAndNil(Repaired);
      end;
  finally
    FEmu.Unlock;
  end;
  if Repaired <> nil then
  try
    if Repaired.Count > 0 then
      MessageDlg('ZX Spectrum Next', 'These files on the Next''s SD card were empty (an older ' +
        'version of emu80 didn''t save what NextZXOS and the firmware wrote) and have been mended ' +
        'from the distribution:' + LineEnding + LineEnding + Repaired.Text, mtInformation, [mbOK], 0);
  finally
    Repaired.Free;
  end;
end;

{ Leaving the Next: its card saved, and the other models' card back }
procedure TMainWindow.LeaveNext;
var
  Err: string;
begin
  if (FEmu.Spec.DivMMC.Card <> nil) and FEmu.Spec.DivMMC.Card.Modified then
    if not SaveCardInPlace(FEmu, Err) then
      MessageDlg('Could not save the Next''s SD card: ' + Err, mtError, [mbOK], 0);
  FEmu.Lock;
  try
    FEmu.Spec.DivMMC.EjectCard;
    if (Settings.SDCardFile <> '') and FileExists(Settings.SDCardFile) then
      try
        FEmu.Spec.DivMMC.InsertCard(Settings.SDCardFile);
      except
        Settings.SDCardFile := '';
      end;
  finally
    FEmu.Unlock;
  end;
end;

procedure TMainWindow.RememberCard(const FileName: string);
begin
  case FEmu.Spec.Model of
    smZXNext: Settings.NextCard := FileName;
    smZXUno: Settings.ZXUnoCard := FileName;
  else
    Settings.SDCardFile := FileName;
  end;
end;

procedure TMainWindow.UseCard(const FileName: string; EjectIfNone: Boolean);
var
  Have: Boolean;
begin
  Have := (FileName <> '') and FileExists(FileName);
  // Already in: nothing to do (reading it again would drop what isn't saved)
  if Have and (FEmu.Spec.DivMMC.Card <> nil) and
     SameFileName(ExpandFileName(FEmu.Spec.DivMMC.Card.FileName), ExpandFileName(FileName)) then Exit;
  if not Have and not EjectIfNone then Exit;
  FEmu.Lock;
  try
    FEmu.Spec.DivMMC.EjectCard;
    if Have then
      try
        FEmu.Spec.DivMMC.InsertCard(FileName);
      except
        // An unreadable image is as good as none
      end;
  finally
    FEmu.Unlock;
  end;
  DropTempCard;
  if SDBrowserWindow <> nil then SDBrowserWindow.Refresh;
end;

procedure TMainWindow.HardwareChanged(Old, New: TSpectrumModel);
const
  OWN = [smZXUno, smZXNext];
begin
  if Old = New then Exit;
  // Into the Next or the ZX-Uno: their DivMMC is on, with the last card
  // used in them if there is one (the Next's was put in by PrepareNext)
  // (and the Kempston mouse, on by default in both)
  if New in OWN then
  begin
    Settings.DivMMC := True;
    Settings.KempstonMouse := True;
  end;
  if New = smZXUno then UseCard(Settings.ZXUnoCard, False)
  // Out of the ZX-Uno: the standard models' card (out of the Next, LeaveNext)
  else if (Old = smZXUno) and not (New in OWN) then UseCard(Settings.SDCardFile, True);
  // The DivMMC is a Spectrum device: on a CPC it is simply switched off
  if IsCPCModel(New) or IsSAMModel(New) or IsMSXModel(New) then
  begin
    Settings.DivMMC := False;
    Settings.KempstonMouse := False;
    Exit;
  end;
  // Out of either to a standard Spectrum: keep the DivMMC?
  if (Old in OWN) and not (New in OWN) and Settings.DivMMC then
    if MessageDlg('DivMMC', 'This is a standard ZX Spectrum. Do you want to switch off the DivMMC ' +
       'interface?', mtConfirmation, [mbYes, mbNo], 0) = mrYes then Settings.DivMMC := False;
  // The standard models start without the mouse, as they do by default
  if (Old in OWN) and not (New in OWN) then Settings.KempstonMouse := False;
end;

procedure TMainWindow.ApplyNextId;
begin
  FEmu.Lock;
  try
    // $0A: a ZX Spectrum Next; $08: an emulator, as emu80 says it is
    if Settings.RealSpecNext and Settings.RealSpecNextOk then FEmu.Spec.NextMachineId := $0A
    else FEmu.Spec.NextMachineId := $08;
  finally
    FEmu.Unlock;
  end;
end;

procedure TMainWindow.ConfirmRealSpecNext;
begin
  if Settings.RealSpecNext and not Settings.RealSpecNextOk then
  begin
    if MessageDlg('ZX Spectrum Next', 'Al usar esta característica puede estar violando la licencia ' +
       'del software del Spectrum Next. ¿Quiere continuar?', mtWarning, [mbYes, mbNo], 0) = mrYes then
      Settings.AcceptRealSpecNext
    else
    begin
      // Refused: the emulator's ID. The file's entry goes only if that is
      // where the option came from; a command line one is ignored this once
      if not Settings.RealSpecNextCmd then Settings.ForgetRealSpecNext;
      Settings.RealSpecNext := False;
    end;
  end;
  ApplyNextId;
end;

procedure TMainWindow.NoNextDistro;
begin
  ShowNoNextDistro;
end;

procedure TMainWindow.InstallProgress(Percent: Integer);
begin
  FStatus.Panels[2].Text := Format('Installing the ZX Spectrum Next distribution... %d%%', [Percent]);
  Application.ProcessMessages;
end;

procedure TMainWindow.UpdateInstallNextItem(Sender: TObject);
begin
  if FInstallNextItem <> nil then FInstallNextItem.Visible := not NextDistroReady(NextDistroDir);
end;

{ Choose the distribution's zip, unpack it into the specnext folder and
  check it; then offer to start the Next. A zip that isn't a distribution
  leaves the folder empty (what was in it is deleted, as the user is told). }
procedure TMainWindow.DoInstallNextDistro(Sender: TObject);
var
  Dlg: TOpenDialog;
  ZipFile, Dir, Msg, OldStatus: string;
  R: TDistroInstall;
begin
  Dir := NextDistroDir;
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
  OldStatus := FStatus.Panels[2].Text;
  Screen.Cursor := crHourGlass;
  // Nothing else meanwhile: the window ignores the mouse and keyboard
  Enabled := False;
  try
    R := InstallNextDistroZip(ZipFile, Dir, Msg, @InstallProgress);
  finally
    Enabled := True;
    Screen.Cursor := crDefault;
    FStatus.Panels[2].Text := OldStatus;
  end;
  UpdateInstallNextItem(nil);
  case R of
    diOk:
      if MessageDlg('ZX Spectrum Next', 'Distribución instalada.' + LineEnding +
         '¿Quiere iniciar la emulación de Spectrum Next?', mtConfirmation, [mbYes, mbNo], 0) = mrYes then
      begin
        FNextJustInstalled := True;
        try
          ChangeModel(smZXNext);
        finally
          FNextJustInstalled := False;
        end;
      end;
    diInvalid:
      begin
        MessageDlg('ZX Spectrum Next', 'Distribución no valida', mtError, [mbOK], 0);
        // As the message says: the folder is emptied
        ClearNextDistroDir(Dir);
        UpdateInstallNextItem(nil);
      end;
  else
    MessageDlg('ZX Spectrum Next', 'The distribution could not be installed: ' + Msg + LineEnding +
      'Nothing was installed.', mtError, [mbOK], 0);
  end;
end;

procedure TMainWindow.DoNewNextCard(Sender: TObject);
var
  Dlg: TSaveDialog;
  FileName: string;
  InUse: Boolean;
  SizeMB: Integer;
begin
  if not NextDistroReady(NextDistroDir) then
  begin
    NoNextDistro;
    Exit;
  end;
  // The size first, then the file (as for the DivMMC's new cards)
  if not AskNextCardSize(SizeMB) then Exit;
  Dlg := TSaveDialog.Create(nil);
  try
    Dlg.Title := 'New SD card with the ZX Spectrum Next distribution';
    Dlg.FileName := ExtractFileName(NextCardFile);
    Dlg.InitialDir := ExtractFilePath(NextCardFile);
    Dlg.Filter := 'SD card images (*.img)|*.img|All files|*.*';
    Dlg.DefaultExt := 'img';
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    if not Dlg.Execute then Exit;
    FileName := Dlg.FileName;
  finally
    Dlg.Free;
  end;
  // The card in use can't be replaced under the machine's feet
  InUse := (FEmu.Spec.DivMMC.Card <> nil) and SameFileName(FEmu.Spec.DivMMC.Card.FileName, FileName);
  if InUse then
  begin
    FEmu.Lock;
    try
      FEmu.Spec.DivMMC.EjectCard;
    finally
      FEmu.Unlock;
    end;
  end;
  if not MakeNextCardFile(FileName, SizeMB) then Exit;
  // It is the Next's card from now on
  if SameFileName(FileName, ExtractFilePath(Settings.FileName) + 'zxnext.img') then Settings.NextCard := ''
  else Settings.NextCard := FileName;
  if FEmu.Spec.Model = smZXNext then
  begin
    FEmu.Lock;
    try
      FEmu.Spec.DivMMC.InsertCard(FileName);
      FEmu.Spec.Reset(True);
    finally
      FEmu.Unlock;
    end;
  end;
end;

procedure TMainWindow.ChangeModel(M: TSpectrumModel);
var
  WasNext: Boolean;
  Old: TSpectrumModel;
begin
  Old := FEmu.Spec.Model;
  WasNext := FEmu.Spec.Model = smZXNext;
  // The card in the DivMMC may change with the hardware (the Next's does by
  // itself): its changes first, or the change is cancelled
  if (M <> Old) and (Old <> smZXNext) and (M <> smZXNext) and ((Old = smZXUno) or (M = smZXUno)) and
     not ConfirmCardChanges then Exit;
  // The Next: its distribution must be there, and its card ready
  if (M = smZXNext) and not WasNext and not PrepareNext then
  begin
    Settings.Model := FEmu.Spec.Model;
    UpdateChecks;
    Exit;
  end;
  if WasNext and (M <> smZXNext) then LeaveNext;
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
  HardwareChanged(Old, FEmu.Spec.Model);
  // What the machine has: the Spectrum's extras are off on a CPC, back on again
  ApplySettings;
  // Leaving the ZX-Uno (its own DivMMC): as Settings say again
  ApplyDivMMC;
  UpdateChecks;
  if (Old <> FEmu.Spec.Model) and IsSAMModel(FEmu.Spec.Model) then SamDosBoot;
  if (Old <> FEmu.Spec.Model) and IsMSXModel(FEmu.Spec.Model) then MsxNotice;
end;

procedure TMainWindow.DoModel(Sender: TObject);
begin
  ChangeModel(TSpectrumModel((Sender as TComponent).Tag));
end;

procedure TMainWindow.DoModelButton(Sender: TObject);
var
  P: TPoint;
begin
  if Sender = FMModelBtn then
  begin
    // Modern: under the button, at the window's right edge, so it opens
    // towards the left
    // (a dark copy of the menu, as those of the header)
    P := FMModelBtn.ClientToScreen(Point(FMModelBtn.Width, FMModelBtn.Height));
    FMirror.Items.Clear;
    MirrorItems(FModelMenu.Items, FMirror.Items);
    FMirror.Alignment := paRight;
    FMirror.PopUp(P.X, P.Y);
  end
  else
  begin
    P := FModelButton.ClientToScreen(Point(0, FModelButton.Height));
    FModelMenu.PopUp(P.X, P.Y);
  end;
end;

{ The SAM Coupe's "Boot SAMDOS automatically": with nothing in drive 1 (or the SAMDOS disk of an earlier
  boot) the SAMDOS2.dsk of the roms folder goes in and the machine boots it, as a user pressing F9 }
procedure TMainWindow.SamDosBoot;
var
  Path: string;
  Disk: TDiskImage;
  Msg: string;
  Cur: TDiskImage;

begin
  if FInCommandLine or not Settings.SamAutoDos or not IsSAMModel(FEmu.Spec.Model) then Exit;
  Path := IncludeTrailingPathDelimiter(Settings.RomDir) + SAMDOS_FILE;
  if not FileExists(Path) then Path := IncludeTrailingPathDelimiter(DefaultRomDir) + SAMDOS_FILE;
  if not FileExists(Path) then Exit;
  FEmu.Lock;
  try
    // Something else is typing or loading: it is the user's
    if FEmu.Spec.AutoTyping then Exit;
    Cur := FEmu.Spec.DiskAt(0);
    if (Cur <> nil) and not SameFileName(ExpandFileName(Cur.FileName), ExpandFileName(Path)) then Exit;
  finally
    FEmu.Unlock;
  end;
  if not LoadDiskChecked(Path, Disk, Msg) then
  begin
    MessageDlg(Msg, mtError, [mbOK], 0);
    Exit;
  end;
  FEmu.Lock;
  try
    FEmu.Spec.InsertDiskAt(0, Disk);
    FEmu.Spec.AutoLoad(True);
  finally
    FEmu.Unlock;
  end;
  UpdateChecks;
end;

{ The SAMDOS disk of the roms folder, nil if there is none }
function TMainWindow.SamDosDisk: TDiskImage;
var
  Path, Msg: string;
begin
  Result := nil;
  Path := IncludeTrailingPathDelimiter(Settings.RomDir) + SAMDOS_FILE;
  if not FileExists(Path) then Path := IncludeTrailingPathDelimiter(DefaultRomDir) + SAMDOS_FILE;
  if FileExists(Path) and not LoadDiskChecked(Path, Result, Msg) then Result := nil;
end;

{ From the command line a disk for the SAM goes in after SAMDOS has booted, if that is on }
function TMainWindow.CliSamDos: Boolean;
begin
  Result := FInCommandLine and Settings.SamAutoDos and IsSAMModel(FEmu.Spec.Model);
end;

procedure TMainWindow.DoReset(Sender: TObject);
begin
  FEmu.Lock;
  try
    FEmu.Spec.Reset(False);
  finally
    FEmu.Unlock;
  end;
  SamDosBoot;
end;

procedure TMainWindow.DoHardReset(Sender: TObject);
begin
  FEmu.Lock;
  try
    FEmu.Spec.Reset(True);
  finally
    FEmu.Unlock;
  end;
  SamDosBoot;
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

procedure TMainWindow.DoDriveNMI(Sender: TObject);
begin
  FEmu.Lock;
  try
    FEmu.Spec.DriveNMI;
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

{ Play/pause: plays the tape from where it is; while it plays, stops it there }
procedure TMainWindow.DoTapePlay(Sender: TObject);
begin
  FEmu.Lock;
  try
    if FEmu.Spec.Tape.Playing or FEmu.Spec.CPCTapeArmed then FEmu.Spec.StopTape
    else FEmu.Spec.PlayTape;
  finally
    FEmu.Unlock;
  end;
end;

procedure TMainWindow.DoTapeStop(Sender: TObject);
begin
  FEmu.Lock;
  try
    FEmu.Spec.StopTape;
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
begin
  SaveTapeDialog(FEmu, '');
end;

{ The other interface (classic or modern), at once }
procedure TMainWindow.DoToggleTheme(Sender: TObject);
begin
  Settings.ModernUI := not Settings.ModernUI;
  // The first start's note is about the modern interface
  if FNotice <> nil then NoticeEnd(nil);
  ApplyStyle;
  SetScale(Settings.Scale);
  UpdateChecks;
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
  Msg: string;
begin
  Result := True;
  FEmu.Lock;
  try
    Disk := FEmu.Spec.DiskAt(Drive);
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
      Msg := SaveDiskImage(Disk, Disk.FileName);
    finally
      FEmu.Unlock;
    end;
    if Msg <> '' then
    begin
      MessageDlg(Msg, mtError, [mbOK], 0);
      Result := False;
    end;
    Exit;
  end;
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := SAVE_DISK_FILTER;
    Dlg.DefaultExt := 'dsk';
    Dlg.InitialDir := Settings.LastDir;
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    if not Dlg.Execute then Exit(False);
    FEmu.Lock;
    try
      Msg := SaveDiskImage(Disk, Dlg.FileName);
    finally
      FEmu.Unlock;
    end;
    if Msg <> '' then
    begin
      MessageDlg(Msg, mtError, [mbOK], 0);
      Result := False;
    end;
  finally
    Dlg.Free;
  end;
end;

{ A disk drive built into the machine (a CPC 464 and the Spectrums but the +3 have none) }
function TMainWindow.FloppyAvailable: Boolean;
begin
  Result := FEmu.Spec.Info.HasFDC;
end;

{ An SD card reader: the DivMMC (fitted, or the ZX-Uno's and the Next's own) }
function TMainWindow.SDAvailable: Boolean;
begin
  Result := (FEmu.Spec.DivMMCOn or (FEmu.Spec.Info.Memory in [mkZXUno, mkZXNext])) and not IsMSXModel(FEmu.Spec.Model);
end;

procedure TMainWindow.DoDiskInsert(Sender: TObject);
begin
  InsertDiskDialog((Sender as TComponent).Tag);
end;

procedure TMainWindow.InsertDiskDialog(Drive: Integer);
var
  Dlg: TOpenDialog;
begin
  if not ConfirmDiskChanges(Drive) then Exit;
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Filter := DISK_FILTER + '|All files|*.*';
    Dlg.InitialDir := Settings.LastDir;
    Dlg.Options := Dlg.Options + [ofFileMustExist];
    if Dlg.Execute then InsertDiskFile(Drive, Dlg.FileName);
  finally
    Dlg.Free;
  end;
end;

{ Loads a disk image and checks that the machine can use it. The format is the
  file's, whatever its name: a SAM Coupe disk (80 cylinders of 10 sectors of 512
  bytes) isn't one an Amstrad CPC or a +3 reads, so they say so. The SAM Coupe's
  controller reads whatever the disk holds: its software, CP/M for one, is what
  knows the CPC and +3 formats. }
function TMainWindow.LoadDiskChecked(const FileName: string; out Disk: TDiskImage; out Msg: string): Boolean;
var
  Problem: TDiskProblem;
  Machine: TDiskMachine;
begin
  Msg := '';
  Disk := LoadDiskImage(FileName, Problem, Msg);
  if Disk = nil then Exit(False);
  if IsMSXModel(FEmu.Spec.Model) then Machine := dmMSX
  else if IsSAMModel(FEmu.Spec.Model) then Machine := dmSAM
  else if FEmu.Spec.CPC <> nil then Machine := dmCPC
  else Machine := dmSpectrum;
  Result := CheckDiskForMachine(Disk, FileName, Machine, Msg);
  if not Result then FreeAndNil(Disk);
end;

function TMainWindow.InsertDiskFile(Drive: Integer; const FileName: string): Boolean;
var
  Disk: TDiskImage;
  Msg: string;
begin
  Result := False;
  if not LoadDiskChecked(FileName, Disk, Msg) then
  begin
    MessageDlg(Msg, mtError, [mbOK], 0);
    Exit;
  end;
  FEmu.Lock;
  try
    FEmu.Spec.InsertDiskAt(Drive, Disk);
  finally
    FEmu.Unlock;
  end;
  Settings.AddRecent(FileName);
  Settings.AddRecentDisk(FileName);
  NoteMediaFile(FileName);
  UpdateRecentMenu;
  UpdateRecentDisksMenu;
  if not FEmu.Spec.Info.HasFDC then
    MessageDlg('The disk is inserted, but this computer has no disk drive.', mtInformation, [mbOK], 0);
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
  I, D, Shown: Integer;
  Item, Sub: TMenuItem;
begin
  // Both drives share the list; the tag says the drive (1000 for B) and entry
  for D := 0 to 1 do
  begin
    if D = 0 then Sub := FRecentDisksMenu else Sub := FRecentDisksMenuB;
    Sub.Clear;
    Shown := 0;
    for I := 0 to Settings.RecentDisks.Count - 1 do
      if (Shown < RECENT_SHOWN) and RecentFits(Settings.RecentDisks[I], 1) then
      begin
        Inc(Shown);
        Item := AddItem(Sub, Format('&%d %s', [I + 1, Settings.RecentDisks[I]]), @DoInsertRecentDisk);
        Item.Tag := D * 1000 + I;
      end;
    Sub.Enabled := Sub.Count > 0;
  end;
  FRecentCardsMenu.Clear;
  Shown := 0;
  for I := 0 to Settings.RecentCards.Count - 1 do
    if (Shown < RECENT_SHOWN) and RecentFits(Settings.RecentCards[I], 2) then
    begin
      Inc(Shown);
      Item := AddItem(FRecentCardsMenu, Format('&%d %s', [I + 1, Settings.RecentCards[I]]),
        @DoInsertRecentCard);
      Item.Tag := I;
    end;
  FRecentCardsMenu.Enabled := FRecentCardsMenu.Count > 0;
  FRecentTapesMenu.Clear;
  FRecentTapesMenuJ.Clear;
  Shown := 0;
  for I := 0 to Settings.RecentTapes.Count - 1 do
    if (Shown < RECENT_SHOWN) and RecentFits(Settings.RecentTapes[I], 3) then
    begin
      Inc(Shown);
      Item := AddItem(FRecentTapesMenu, Format('&%d %s', [I + 1, Settings.RecentTapes[I]]), @DoInsertRecentTape);
      Item.Tag := I;
      Item := AddItem(FRecentTapesMenuJ, Format('&%d %s', [I + 1, Settings.RecentTapes[I]]), @DoInsertRecentTapeOnly);
      Item.Tag := I;
    end;
  FRecentTapesMenu.Enabled := FRecentTapesMenu.Count > 0;
  FRecentTapesMenuJ.Enabled := FRecentTapesMenuJ.Count > 0;
  FRecentCartsMenu.Clear;
  Shown := 0;
  for I := 0 to Settings.RecentCarts.Count - 1 do
    if (Shown < RECENT_SHOWN) and RecentFits(Settings.RecentCarts[I], 4) then
    begin
      Inc(Shown);
      Item := AddItem(FRecentCartsMenu, Format('&%d %s', [I + 1, Settings.RecentCarts[I]]), @DoInsertRecentCart);
      Item.Tag := I;
    end;
  FRecentCartsMenu.Enabled := FRecentCartsMenu.Count > 0;
end;

procedure TMainWindow.DoInsertRecentTape(Sender: TObject);
begin
  InsertRecentTape(Sender, True);
end;

procedure TMainWindow.DoInsertRecentTapeOnly(Sender: TObject);
begin
  InsertRecentTape(Sender, False);
end;

procedure TMainWindow.InsertRecentTape(Sender: TObject; AutoStart: Boolean);
var
  Index: Integer;
  Path: string;
begin
  Index := (Sender as TComponent).Tag;
  if Index < Settings.RecentTapes.Count then
  begin
    Path := Settings.RecentTapes[Index];      // a copy: the list changes as it is inserted
    Settings.LastDir := ExtractFilePath(Path);
    OpenFile(Path, AutoStart);
  end;
end;

procedure TMainWindow.DoInsertRecentCart(Sender: TObject);
var
  Index: Integer;
  Path: string;
begin
  Index := (Sender as TComponent).Tag;
  if Index < Settings.RecentCarts.Count then
  begin
    Path := Settings.RecentCarts[Index];
    Settings.LastDir := ExtractFilePath(Path);
    InsertCartridgeFile(Path);
  end;
end;

procedure TMainWindow.DoInsertRecentDisk(Sender: TObject);
var
  Index, Drive: Integer;
  Path: string;
begin
  Drive := (Sender as TComponent).Tag div 1000;
  Index := (Sender as TComponent).Tag mod 1000;
  if (Index < Settings.RecentDisks.Count) and ConfirmDiskChanges(Drive) then
  begin
    Path := Settings.RecentDisks[Index];      // a copy: the list changes as it is inserted
    Settings.LastDir := ExtractFilePath(Path);
    InsertDiskFile(Drive, Path);
  end;
end;

procedure TMainWindow.DoInsertRecentCard(Sender: TObject);
var
  Index: Integer;
  Path: string;
begin
  Index := (Sender as TComponent).Tag;
  if Index < Settings.RecentCards.Count then
  begin
    Path := Settings.RecentCards[Index];      // a copy: the list changes as it is inserted
    Settings.LastDir := ExtractFilePath(Path);
    InsertSDCard(Path);
  end;
end;

procedure TMainWindow.DoDiskBrowser(Sender: TObject);
begin
  // A: if it has a disk, otherwise B:
  ShowDiskBrowser(FEmu);
end;

procedure TMainWindow.DoSDBrowser(Sender: TObject);
begin
  if IsMSXModel(FEmu.Spec.Model) then
  begin
    // On the MSX this is the cartridge browser (CR)
    CartOnSaved := @CartSaved;
    if FEmu.Spec.MSXHw.CartridgeName(1) <> '' then ShowCartBrowser(FEmu);
    Exit;
  end;
  if FEmu.Spec.DivMMCOn and (FEmu.Spec.DivMMC.Card <> nil) then ShowSDBrowser(FEmu);
end;

{ The cartridge browser saved the cartridge under another name: that is the file now }
procedure TMainWindow.CartSaved(const FileName: string);
begin
  FCartFile := FileName;
  Settings.AddRecentCart(FileName);
  UpdateRecentMenu;
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

{ Size of a new card, in MB: from those of MinMB or more, DefaultMB at first }
function AskSize(const Caption, Info: string; MinMB, DefaultMB: Integer; out SizeMB: Integer): Boolean;
const
  SIZES: array[0..7] of Integer = (16, 32, 64, 128, 256, 512, 1024, 2048);
var
  Dlg: TForm;
  Combo: TComboBox;
  Lbl: TLabel;
  Btn: TButton;
  I: Integer;
  Choices: array of Integer;
begin
  Result := False;
  Choices := nil;
  for I := 0 to High(SIZES) do
    if SIZES[I] >= MinMB then
    begin
      SetLength(Choices, Length(Choices) + 1);
      Choices[High(Choices)] := SIZES[I];
    end;
  if Choices = nil then Exit;
  Dlg := TForm.CreateNew(nil, 0);
  try
    Dlg.Caption := Caption;
    Dlg.BorderStyle := bsDialog;
    Dlg.Position := poMainFormCenter;
    Dlg.ClientWidth := 360;
    Dlg.ClientHeight := 142;
    Lbl := TLabel.Create(Dlg);
    Lbl.Parent := Dlg;
    Lbl.Caption := 'Size (FAT16):';
    Lbl.SetBounds(10, 16, 120, 18);
    Combo := TComboBox.Create(Dlg);
    Combo.Parent := Dlg;
    Combo.Style := csDropDownList;
    Combo.SetBounds(140, 12, 120, 24);
    Combo.ItemIndex := 0;
    for I := 0 to High(Choices) do
    begin
      Combo.Items.Add(Format('%d MB', [Choices[I]]));
      if Choices[I] = DefaultMB then Combo.ItemIndex := I;
    end;
    Lbl := TLabel.Create(Dlg);
    Lbl.Parent := Dlg;
    Lbl.AutoSize := False;
    Lbl.WordWrap := True;
    Lbl.Caption := Info;
    Lbl.SetBounds(10, 48, 340, 42);
    Btn := TButton.Create(Dlg);
    Btn.Parent := Dlg;
    Btn.Caption := 'OK';
    Btn.Default := True;
    Btn.ModalResult := mrOK;
    Btn.SetBounds(190, 104, 75, 28);
    Btn := TButton.Create(Dlg);
    Btn.Parent := Dlg;
    Btn.Caption := 'Cancel';
    Btn.Cancel := True;
    Btn.ModalResult := mrCancel;
    Btn.SetBounds(275, 104, 75, 28);
    if Dlg.ShowModal <> mrOK then Exit;
    SizeMB := Choices[Combo.ItemIndex];
    Result := True;
  finally
    Dlg.Free;
  end;
end;

{ Size of a new DivMMC card, in MB }
function AskCardSize(WithEsxdos: Boolean; out SizeMB: Integer): Boolean;
begin
  if WithEsxdos then
    Result := AskSize('New SD card with ESXDOS', 'The card gets the ESXDOS SYS, BIN and TMP folders.',
      16, 128, SizeMB)
  else
    Result := AskSize('New SD card', 'An empty card with one FAT16 partition.', 16, 128, SizeMB);
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
  Esx := Emu80Path('esxdos');
  if WithEsxdos and (Esx = '') then
  begin
    MessageDlg('The esxdos folder (with SYS and BIN) was not found next to emu80.', mtError, [mbOK], 0);
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
          FormatCard(S, SizeMB, 'EMU80 SD');
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
        RememberCard(FEmu.Spec.DivMMC.Card.FileName);
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
  // The Next's card keeps what NextZXOS writes, as on the real machine
  if FEmu.Spec.Model = smZXNext then
  begin
    if not SaveCardInPlace(FEmu, Err) then
      MessageDlg('Could not save the Next''s SD card: ' + Err, mtError, [mbOK], 0);
    Exit;
  end;
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
  Disk := FEmu.Spec.DiskAt(Drive);
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
  Esx := Emu80Path('esxdos');
  if Esx = '' then
  begin
    MessageDlg('The esxdos folder (with SYS and BIN) was not found next to emu80.', mtError, [mbOK], 0);
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
    Format('emu80-sd-%s.img', [FormatDateTime('yyyymmddhhnnsszzz', Now)]);
  Err := '';
  Screen.Cursor := crHourGlass;
  try
    try
      S := TFileStream.Create(TempFile, fmCreate);
      try
        FormatCard(S, SizeMB, 'EMU80 FOLDER');
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
  RememberCard('');    // nothing to insert again next time
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
  RememberCard('');
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
  // Already formatted (+3 standard format, or AMSDOS's data format on a CPC), ready
  // for SAVE without FORMAT
  Disk := TDiskImage.Create;
  if FEmu.Spec.CPC <> nil then Disk.CreateCPCFormatted
  else if IsSAMModel(FEmu.Spec.Model) then
  begin
    Disk.Free;
    Disk := NewSamDisk;
  end
  else if IsMSXModel(FEmu.Spec.Model) then
  begin
    Disk.Free;
    Disk := NewMsxDisk(True);
  end
  else Disk.CreatePlus3Formatted;
  FEmu.Lock;
  try
    FEmu.Spec.InsertDiskAt(Drive, Disk);
  finally
    FEmu.Unlock;
  end;
  if not FEmu.Spec.Info.HasFDC then
    MessageDlg('The disk is inserted, but this computer has no disk drive.', mtInformation, [mbOK], 0);
end;

procedure TMainWindow.DoDiskEject(Sender: TObject);
var
  Drive: Integer;
begin
  Drive := (Sender as TComponent).Tag;
  if not ConfirmDiskChanges(Drive) then Exit;
  FEmu.Lock;
  try
    FEmu.Spec.EjectDiskAt(Drive).Free;
  finally
    FEmu.Unlock;
  end;
end;

procedure TMainWindow.DoDiskSave(Sender: TObject);
var
  Dlg: TSaveDialog;
  Drive: Integer;
  Msg: string;
begin
  Drive := (Sender as TComponent).Tag;
  if FEmu.Spec.DiskAt(Drive) = nil then
  begin
    MessageDlg('There is no disk in that drive.', mtInformation, [mbOK], 0);
    Exit;
  end;
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := SAVE_DISK_FILTER;
    Dlg.DefaultExt := 'dsk';
    // Where it was loaded from, if it was
    if FEmu.Spec.DiskAt(Drive).FileName <> '' then
    begin
      Dlg.InitialDir := ExtractFilePath(FEmu.Spec.DiskAt(Drive).FileName);
      Dlg.FileName := ExtractFileName(FEmu.Spec.DiskAt(Drive).FileName);
    end
    else
      Dlg.InitialDir := Settings.LastDir;
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    if not Dlg.Execute then Exit;
    FEmu.Lock;
    try
      Msg := SaveDiskImage(FEmu.Spec.DiskAt(Drive), Dlg.FileName);
    finally
      FEmu.Unlock;
    end;
    if Msg <> '' then MessageDlg(Msg, mtError, [mbOK], 0);
  finally
    Dlg.Free;
  end;
end;

{ Options }

{ The note the first time the MSX starts: what it emulates and the ROMs it uses (msx_notice turns it on again) }
procedure TMainWindow.MsxNotice;
const
  NOTE = 'This emulator emulates an MSX2 and also uses unofficial QUANTIKA ROMs. As a result, some games may ' +
    'not work. Replacing the ROMs with the official ones may help. Alternatively, enabling MSX1 compatibility ' +
    'mode (in the Options menu) may also help, especially with games from the early days of the MSX.' + LineEnding + LineEnding +
    'If you want to use the official ROMs, you will need the MSX2.ROM and MSX2EXT.ROM files. Place them in the ' +
    'roms/msx folder, then select them under Settings > Common > ROMs.' + LineEnding + LineEnding +
    'To use a floppy disk drive, add the PHILIPSDISK.rom file under FLOPPY DISK. This will only work with the ' +
    'original ROMs. Searching the web for this ROM will probably lead you to the other two files as well.';
begin
  if not Settings.MsxNotice or not IsMSXModel(FEmu.Spec.Model) then Exit;
  Settings.MsxNoticeShown;
  ReleaseAllKeys;
  MessageDlg('MSX 2', NOTE, mtInformation, [mbOK], 0);
end;

{ The MSX with the slots of an MSX1 (no expanded slot) or the MSX2's own: it starts again with them }
procedure TMainWindow.DoMsxCompat(Sender: TObject);
begin
  Settings.MsxCompat := not Settings.MsxCompat;
  ApplySettings;
  UpdateChecks;
end;

procedure TMainWindow.DoMute(Sender: TObject);
begin
  Settings.Sound := not Settings.Sound;
  ApplySettings;
  UpdateChecks;
end;


procedure TMainWindow.DoMonitor(Sender: TObject);
begin
  Settings.Monitor := (Sender as TMenuItem).Tag;
  UpdateChecks;
  RenderBitmap;
  FDisplay.Invalidate;
end;

procedure TMainWindow.DoScanlines(Sender: TObject);
begin
  Settings.Scanlines := not Settings.Scanlines;
  UpdateChecks;
  RenderBitmap;
  FDisplay.Invalidate;
end;

{ The Spectrum's Kempston mouse, or the SAM Coupe's }
function TMainWindow.MouseOn: Boolean;
begin
  if IsSAMModel(FEmu.Spec.Model) then Result := Settings.SamMouse
  else Result := Settings.KempstonMouse and (FEmu.Spec.CPC = nil);
end;

{ The mouse is on and a program has read it lately: only then is the PC pointer
  hidden and attached, as a program that doesn't use the mouse draws no pointer }
function TMainWindow.MouseInUse: Boolean;
const
  IN_USE_MS = 2000;
var
  Tick: QWord;
begin
  Result := MouseOn;
  if not Result then Exit;
  if IsSAMModel(FEmu.Spec.Model) then Tick := FEmu.Spec.SAM.MouseReadTick
  else Tick := FEmu.Spec.MouseReadTick;
  Result := (Tick <> 0) and (GetTickCount64 - Tick < IN_USE_MS);
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
  if not MouseOn then Exit;
  if FMouseHave then
  begin
    Scale := DisplayScale;
    DX := X - FMouseLast.X + FMouseRemX;
    DY := Y - FMouseLast.Y + FMouseRemY;
    FMouseRemX := DX mod Scale;
    FMouseRemY := DY mod Scale;
    if IsSAMModel(FEmu.Spec.Model) then
    begin
      FEmu.Lock;
      try
        FEmu.Spec.SAM.MouseMoved(DX div Scale, DY div Scale);
      finally
        FEmu.Unlock;
      end;
    end
    else
    begin
      FEmu.Spec.MouseX := Byte(FEmu.Spec.MouseX + DX div Scale);
      FEmu.Spec.MouseY := Byte(FEmu.Spec.MouseY - DY div Scale);
    end;
  end;
  FMouseLast := Point(X, Y);
  FMouseHave := True;
end;

{ The SAM's button numbers: 1 left, 2 right, 3 middle }
function SamMouseBit(Button: TMouseButton): Byte;
begin
  case Button of
    mbLeft: Result := 1;
    mbRight: Result := 2;
    mbMiddle: Result := 4;
  else
    Result := 0;
  end;
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
  if not MouseOn then Exit;
  // The first click: the mouse over the picture is lost when it leaves the
  // window, so offer to keep it in (the click itself isn't passed on)
  if not Settings.AttachMouse and not FAttachAsked and MouseInUse then
  begin
    FAttachAsked := True;
    ReleaseAllKeys;
    if MessageDlg('Mouse', 'Do you want to attach the mouse to the window?',
       mtConfirmation, [mbYes, mbNo], 0) = mrYes then
    begin
      Settings.AttachMouse := True;
      Settings.Save;
    end;
    FMouseHave := False;
    Exit;
  end;
  if IsSAMModel(FEmu.Spec.Model) then
    FEmu.Spec.SAM.MouseButtons := FEmu.Spec.SAM.MouseButtons or SamMouseBit(Button)
  else
    FEmu.Spec.MouseButtons := FEmu.Spec.MouseButtons and not MouseBit(Button);
end;

procedure TMainWindow.DisplayMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if not MouseOn then Exit;
  if IsSAMModel(FEmu.Spec.Model) then
    FEmu.Spec.SAM.MouseButtons := FEmu.Spec.SAM.MouseButtons and not SamMouseBit(Button)
  else
    FEmu.Spec.MouseButtons := FEmu.Spec.MouseButtons or MouseBit(Button);
end;

procedure TMainWindow.DisplayMouseLeave(Sender: TObject);
begin
  FMouseHave := False;
  FEmu.Spec.MouseButtons := $FF;
  if IsSAMModel(FEmu.Spec.Model) then FEmu.Spec.SAM.MouseButtons := 0;
end;

procedure TMainWindow.ReleaseMouseClip;
begin
  if not FMouseClipped then Exit;
  FMouseClipped := False;
{$IFDEF WINDOWS}
  WinClipCursor(nil);
{$ENDIF}
end;

{ The mouse attached to the window (Settings): once the PC pointer is over the
  picture, and the window is the active one with a program reading the mouse, it
  can't leave the picture (where the PC pointer is hidden), so only the
  emulated one is seen and the edges are easy to reach. Ctrl+Alt frees it
  while held (to reach the menus); so do Alt-Tab and any dialog. }
procedure TMainWindow.MouseClipTick(Sender: TObject);
var
  R: TRect;
  P: TPoint;
  C: TCursor;
begin
  // The program draws its own pointer while it uses the mouse: the PC one is hidden over the picture
  if MouseInUse then C := crNone else C := crDefault;
  if FDisplay.Cursor <> C then FDisplay.Cursor := C;
  if not (Settings.AttachMouse and MouseInUse and Application.Active and (Screen.ActiveForm = Self) and
          Visible and (WindowState <> wsMinimized)) or
     ((GetKeyState(VK_CONTROL) < 0) and (GetKeyState(VK_MENU) < 0)) then
  begin
    ReleaseMouseClip;
    Exit;
  end;
  R.TopLeft := FDisplay.ClientToScreen(Point(0, 0));
  R.BottomRight := FDisplay.ClientToScreen(Point(FDisplay.Width, FDisplay.Height));
  P := Mouse.CursorPos;
  if not FMouseClipped then
  begin
    if not PtInRect(R, P) then Exit;
    FMouseClipped := True;
  end;
{$IFDEF WINDOWS}
  WinClipCursor(@R);
{$ELSE}
  if P.X < R.Left then P.X := R.Left else if P.X >= R.Right then P.X := R.Right - 1;
  if P.Y < R.Top then P.Y := R.Top else if P.Y >= R.Bottom then P.Y := R.Bottom - 1;
  if (P.X <> Mouse.CursorPos.X) or (P.Y <> Mouse.CursorPos.Y) then Mouse.CursorPos := P;
{$ENDIF}
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
    if FEmu.Spec.CPC <> nil then Dlg.Filter := 'CPC screen (*.scr)|*.scr'
    else Dlg.Filter := 'Spectrum screen (*.scr)|*.scr';
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
    SavePNG(Pixels, Dlg.FileName, (Sender as TComponent).Tag, Settings.ScreenshotBorder,
      FEmu.Spec.CPC <> nil);
  finally
    Dlg.Free;
  end;
end;

procedure TMainWindow.DoScale(Sender: TObject);
begin
  SetScale((Sender as TComponent).Tag);
  UpdateChecks;
end;

procedure TMainWindow.DoKeyboardGuide(Sender: TObject);
begin
  ShowKeyboardGuide(Self);
end;

procedure TMainWindow.DoVirtualKeyboard(Sender: TObject);
begin
  ShowVirtualKeyboard(Self, @TypeVirtualSymbol);
end;

{ The virtual keyboard's symbols go to the machine as --keyin's text does }
function TMainWindow.TypeVirtualSymbol(const Sym: string; DryRun: Boolean): Boolean;
begin
  FEmu.Lock;
  try
    Result := FEmu.Spec.TypeSymbol(Sym, DryRun);
  finally
    FEmu.Unlock;
  end;
end;

procedure TMainWindow.DoSettings(Sender: TObject);
begin
  FOldRomDir := Settings.RomDir;
  FOldMapper := Settings.MsxCartMapper;
  FOldUno := Settings.ZXUnoFirmware + '|' + Settings.ZXUnoRoms + '|' + Settings.ZXUnoCustomRom;
  FirmwareChanged := False;
  StoreZXUnoBios;
  ShowSettings(@SettingsApplied);
end;

{ The settings window's Apply (and OK, and Cancel after an Apply): what changed
  takes effect }
procedure TMainWindow.SettingsApplied(Sender: TObject);
var
  OldRomDir, OldUno: string;
begin
  OldRomDir := FOldRomDir;
  OldUno := FOldUno;
  // Another cartridge mapper: the cartridge in goes in again with it
  if (Settings.MsxCartMapper <> FOldMapper) and (FCartFile <> '') and FileExists(FCartFile) and
     IsMSXModel(FEmu.Spec.Model) then
    InsertCartridgeFile(FCartFile);
  FOldMapper := Settings.MsxCartMapper;
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
  if Settings.ModernUI <> FModern then ApplyStyle;
  SetScale(Settings.Scale);
  UpdateChecks;
  RenderBitmap;    // black and white may have changed
  FDisplay.Invalidate;
  Settings.Save;
  FOldRomDir := Settings.RomDir;
  FOldUno := Settings.ZXUnoFirmware + '|' + Settings.ZXUnoRoms + '|' + Settings.ZXUnoCustomRom;
  FirmwareChanged := False;
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

{ Command line: see README.md. Options may start with - or -- and
  take their value as the next argument or after "=". }
procedure TMainWindow.ProcessCommandLine;
type
  TBreakArg = record
    Text: string;
    Flags: Byte;
    Port: Boolean;
  end;
var
  I, N, S, Speed: Integer;
  MapperTmp: TMsxMapperKind;
  Arg, Value, Errors, Err: string;
  Files, Tapes, KeyTexts: TStringList;
  Disks: array[0..1] of string;
  Breaks: array of TBreakArg;
  BreakFile, WatchFile, DaadBreakFile: string;   // JSON files to load
  Watches: TWordArray;
  SymFiles: TStringList;
  M: TSpectrumModel;
  J: TJoystickKeys;
  D: TDeinterlace;
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
      (Name = 'config') or (Name = 'config-add') or (Name = 'zx_joystick') or
      (Name = 'zx_deinterlace') or (Name = 'zx_sdcard') or (Name = 'zx_unocard') or
      (Name = 'zx_sdadd') or (Name = 'zx_sdfolder') or (Name = 'volume') or (Name = 'zx_issue') or
      (Name = 'romdir') or (Name = 'rom') or (Name = 'zx_divmmcrom') or
      (Name = 'zx_unofirmware') or (Name = 'zx_unoroms') or (Name = 'zx_unocustomrom') or
      (Name = 'zx_nextdir') or (Name = 'zx_nextcard') or (Name = 'cpc_crtc') or (Name = 'sam_memory') or (Name = 'msx_cartmapper') or (Name = 'msx_mapper') or (Name = 'monitor') or
      (Name = 'ui') or (Name = 'breakpoints') or (Name = 'watches') or
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
  var
    Msg: string;
    Dos: TDiskImage;
  begin
    if not LoadDiskChecked(FileName, Disk, Msg) then
    begin
      Errors := Errors + Msg + LineEnding;
      Exit;
    end;
    FEmu.Lock;
    try
      if not FEmu.Spec.Info.HasFDC and not HaveModel then
      begin
        if FEmu.Spec.CPC <> nil then FEmu.Spec.SetModel(smCPC6128) else FEmu.Spec.SetModel(smPlus3);
      end;
      Dos := nil;
      if (Drive = 0) and CliSamDos then Dos := SamDosDisk;
      if Dos <> nil then FEmu.Spec.SamDosThen(Dos, Disk)
      else FEmu.Spec.InsertDiskAt(Drive, Disk);
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
        // The CPC machines and the SAM Coupe by name: emu80 cpc464, cpc664, cpc6128 or sam (as --model)
        M := ModelFromName(LowerCase(Arg), smPlus3);
        if (IsCPCModel(M) or IsSAMModel(M) or IsMSXModel(M)) and (LowerCase(Arg) = ModelKey(M)) and not FileExists(Arg) then
        begin
          NewModel := M;
          HaveModel := True;
          Continue;
        end;
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
      // The options of the ZX Spectrum start zx_, those of the CPC cpc_; the
      // names they had before are still taken
      Arg := CurrentOptionName(LowerCase(Arg));
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
      // --bw (the black and white display) is the black and white monitor
      if BoolName = 'bw' then
      begin
        if BoolValue then Settings.Monitor := 1
        else if Settings.Monitor = 1 then Settings.Monitor := 0;
        Continue;
      end;
      if BoolName = 'mute' then
      begin
        Settings.Sound := not BoolValue;
        Continue;
      end;
      // Hidden option (not documented, see CLAUDE.md): over the settings file's
      if BoolName = 'zx_realspecnext' then
      begin
        if Value <> '' then BoolValue := (Value <> '0') and not SameText(Value, 'false');
        Settings.RealSpecNext := BoolValue;
        Settings.RealSpecNextCmd := True;
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
      else if Arg = 'zx_issue' then
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
      else if Arg = 'ui' then
      begin
        // Applied before the window was made (ReadSettingsOptions)
        Value := LowerCase(Value);
        if (Value <> 'classic') and (Value <> 'modern') then
          Errors := Errors + 'Unknown --ui (classic or modern): ' + Value + LineEnding;
      end
      else if (Arg = 'zx_unofirmware') or (Arg = 'zx_unoroms') or (Arg = 'zx_unocustomrom') then
      begin
        if (Value = '') or FileExists(Value) then
        begin
          if Value <> '' then Value := ExpandFileName(Value);
          if Arg = 'zx_unofirmware' then Settings.ZXUnoFirmware := Value
          else if Arg = 'zx_unoroms' then Settings.ZXUnoRoms := Value
          else Settings.ZXUnoCustomRom := Value;
          UnoSet := True;
        end
        else
          Errors := Errors + 'File not found: ' + Value + LineEnding;
      end
      else if Arg = 'zx_divmmcrom' then
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
      else if Arg = 'zx_nextdir' then
      begin
        if (Value = '') or DirectoryExists(Value) then
        begin
          if Value <> '' then Value := ExpandFileName(Value);
          Settings.NextDir := Value;
          FEmu.Spec.NextDir := NextDistroDir;
        end
        else
          Errors := Errors + 'Folder not found: ' + Value + LineEnding;
      end
      else if Arg = 'zx_nextcard' then
      begin
        // Made from the distribution if it doesn't exist yet
        if Value <> '' then Value := ExpandFileName(Value);
        Settings.NextCard := Value;
      end
      else if Arg = 'zx_sdcard' then SDFile := Value
      else if Arg = 'zx_unocard' then
      begin
        if Value <> '' then Value := ExpandFileName(Value);
        Settings.ZXUnoCard := Value;
      end
      else if Arg = 'zx_sdadd' then SDAdds.Add(Value)
      else if Arg = 'zx_sdfolder' then SDFolder := Value
      else if Arg = 'monitor' then
      begin
        Value := LowerCase(Value);
        N := -1;
        for S := 0 to 3 do
          if Value = MONITOR_KEYS[S] then
          begin
            Settings.Monitor := S;
            N := 0;
          end;
        if N < 0 then Errors := Errors + 'Unknown --monitor (color, bw, green or orange): ' + Value + LineEnding;
      end
      else if Arg = 'cpc_crtc' then
      begin
        Value := LowerCase(Value);
        if Value = 'auto' then Settings.CPCCrtc := -1
        else if (Length(Value) = 1) and (Value[1] in ['0'..'4']) then Settings.CPCCrtc := Ord(Value[1]) - 48
        else Errors := Errors + 'Unknown --cpc_crtc (auto, or the chip 0 to 4): ' + Value + LineEnding;
      end
      else if Arg = 'msx_cartmapper' then
      begin
        Value := LowerCase(Value);
        if (Value = 'auto') or MapperFromName(Value, MapperTmp) then Settings.MsxCartMapper := Value
        else Errors := Errors + 'Unknown --msx_cartmapper (auto, plain, konami, konamiscc, ascii8 or ascii16): ' + Value + LineEnding;
      end
      else if Arg = 'msx_mapper' then
      begin
        Value := LowerCase(Value);
        if (Value = 'auto') or (Value = 'on') or (Value = 'off') then Settings.MsxMapper := Value
        else Errors := Errors + 'Unknown --msx_mapper (auto, on or off): ' + Value + LineEnding;
      end
      else if Arg = 'sam_memory' then
      begin
        if (Value = '256') or (Value = '512') then Settings.SamMemory := StrToInt(Value)
        else Errors := Errors + 'Unknown --sam_memory (256 or 512): ' + Value + LineEnding;
      end
      else if Arg = 'zx_deinterlace' then
      begin
        Value := LowerCase(Value);
        N := -1;
        for D := Low(TDeinterlace) to High(TDeinterlace) do
          if Value = DEINTERLACE_KEYS[D] then
          begin
            Settings.Deinterlace := D;
            N := 0;
          end;
        if N < 0 then Errors := Errors + 'Unknown --zx_deinterlace (progressive, bob or weave): ' + Value + LineEnding;
      end
      else if Arg = 'zx_joystick' then
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
    if HaveModel then
    begin
      FStartNext := False;
      FNextFromCommandLine := NewModel = smZXNext;
      ChangeModel(NewModel);
      FNextFromCommandLine := False;
      // --model zxnext without its distribution: nothing else to do
      if (NewModel = smZXNext) and (FEmu.Spec.Model <> smZXNext) then
      begin
        Close;
        Exit;
      end;
      // --model msx2 without its ROMs: nothing else to do either
      if (NewModel = smMSX2) and (FEmu.Spec.Model <> smMSX2) then
      begin
        Close;
        Exit;
      end;
    end;
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
      // They act once the Adventure Debugger is open
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
      Errors := Errors + '--zx_sdadd needs an SD card (--zx_sdcard FILE)' + LineEnding;
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
          Errors := Errors + '--zx_sdadd: file not found: ' + Source + LineEnding;
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
            Errors := Errors + '--zx_sdadd ' + Specs[I] + ': ' + E.Message + LineEnding;
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
  if FEmu.Spec.SlotBank(3) < 0 then RomLabels.UpperRom := -1 - FEmu.Spec.SlotBank(3)
  else RomLabels.UpperRom := 0;
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
    // The Adventure Debugger stopped at a condact: the Z80 one only follows,
    // and the Adventure Debugger gets the focus (last)
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
  MessageDlg('About emu80',
    'emu80 - 8 bit machines emulator' + LineEnding +
    'ZX Spectrum, ZX-Uno, ZX Spectrum Next, Amstrad CPC, SAM Coup' + #$C3#$A9 + ' and MSX2.' + LineEnding +
    'Release ' + EMU80_RELEASE + LineEnding +
    '(C) Vivecoded by Uto - 2028' + LineEnding + LineEnding +
    'Written in Free Pascal with Lazarus.' + LineEnding + LineEnding +
    'Spectrum ROMs are copyright Amstrad, who allow their distribution.' + LineEnding +
    'ROM labels (.sym files): 48K from "The Complete Spectrum ROM Disassembly" ' +
    '(Ian Logan and Frank O''Hara), via Richard Dymond''s SkoolKit disassembly; ' +
    '128K, +2 and +3 from the disassemblies by Paul Farrow, Garry Lancaster and ' +
    'others (ZXSpectrumVault rom-disassemblies); CPCs: names from Bread80''s ' +
    '6128 firmware source, "Amstrad CPC464 Firmware Explained" and Don Thomasson''s memory maps.' + LineEnding +
    'ZX-Uno (its design, core, BIOS and ROMs pack): (C) ZX-Uno Team.' + LineEnding +
    'ZX Spectrum Next boot ROM (tbblue_loader.rom): (C) Victor Trucco and Fabio Belavenuto ' +
    '(TBBlue), GPL v3, via ZEsarUX. Its distribution (specnext.com) is not included.' + LineEnding +
    'esxDOS: (C) Miguel Guerreiro (Papaya Dezign).' + LineEnding +
    'Currah ' + #$C2#$B5 + 'Speech ROM: (C) Currah 1983. SP0256-AL2 mask ROM: Microchip ' +
    'Technology holds its copyright and the rights to its algorithms and data. SP0256 ' +
    'emulation ported from MAME (BSD-3-Clause, Joseph Zbiciak and Tim Lindner).',
    mtInformation, [mbOK], 0);
end;

procedure TMainWindow.DoLicense(Sender: TObject);
begin
  ShowLicense;
end;

{$I MainModern.inc}

end.

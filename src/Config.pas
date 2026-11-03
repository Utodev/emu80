{ Config: user settings, stored in ochenta.ini next to the executable (or in the
  file given with --config). A second file given with --config-add is
  applied on top for the session without being merged into the main file. }
unit Config;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, IniFiles, Models{$IFDEF UNIX}, BaseUnix{$ENDIF};

type
  { What the cursor keys + Ctrl (fire) emulate }
  TJoystickKeys = (jkNone, jkKempston, jkSinclair1, jkSinclair2, jkCursor, jkFuller);

  TSettings = class
  private
    FFileName: string;
    FOverlay: string;          // --config-add file, '' if none
    FCustomFile: Boolean;      // --config: no fallback to older settings
    FMainText: TStringList;    // the main file as loaded, before the overlay
    procedure ReadFrom(Ini: TCustomIniFile; Overlay: Boolean);
    procedure ReadOptions(Ini: TCustomIniFile);
    procedure WriteOptions(Ini: TCustomIniFile);
    function RomList: string;
    procedure SetRomList(const List: string);
    procedure WriteTo(Ini: TCustomIniFile);
  public
    Model: TSpectrumModel;
    RomDir: string;
    FastLoad: Boolean;
    AutoPlayTape: Boolean;
    TapeLoop: Boolean;            // the tape goes on from its start at the end
    Sound: Boolean;
    Volume: Integer;           // 0..100
    Scale: Integer;            // 1..4
    Joystick: TJoystickKeys;
    Deinterlace: TDeinterlace;
    Issue2: Boolean;
    { Shift and Ctrl: False = Shift is CAPS SHIFT and Ctrl SYMBOL SHIFT;
      True = the left ones are CAPS SHIFT and the right ones SYMBOL SHIFT }
    CpuSpeed: Integer;            // 1, 2, 4 ... 32 (interrupts stay at 50 Hz)
    FastDisk: Boolean;            // disk without real drive timing
    DriveB: Boolean;              // second drive connected to the +3
    FloppyNoise: Boolean;         // the drive's sound at real speed
    { Common > Emulation: for every machine, present and future ([Emulation] in the ini file) }
    RunAhead: Integer;            // frames run ahead to cut the input lag (0 = off, up to 3)
    SaveOnExit: Boolean;          // write the settings when ochenta closes
    ModernUI: Boolean;            // the modern interface (--ui modern), else the classic one
    Language: string;             // the interface's language: auto, en, es, fr, pt or de (--lang)
    SaveToTape: Boolean;          // SAVE adds blocks to the tape
    ScreenshotBorder: Boolean;
    TurboSound: Boolean;          // two AY chips (128K and later)
    AY48: Boolean;                // AY interface on the 16K/48K
    DivMMC: Boolean;              // DivMMC interface connected
    Currah: Boolean;              // Currah µSpeech connected
    LeftCtrlCaps: Boolean;        // ZX Spectrum: the left Ctrl is CAPS SHIFT (and only the right Ctrl the joystick's fire), else the left Shift is
    CPCJoystick: Boolean;         // Amstrad CPC: the cursor keys and right Ctrl are also joystick 1
    CPCWaitStates: Boolean;       // Amstrad CPC: the Gate Array's wait states (every access on the 1 MHz grid)
    CPCCrtc: Integer;             // Amstrad CPC: the CRTC chip, 0-4; -1 = the one the model came with
    SamSaa: Boolean;              // SAM Coupe: the SAA1099 sound generator is heard
    SamJoystick: Boolean;         // SAM Coupe: the cursor keys and right Ctrl are also a joystick (Kempston)
    SamMouse: Boolean;            // SAM Coupe: a mouse is connected (the PC's mouse over the picture)
    MsxJoystick: Boolean;         // MSX: the cursor keys and right Ctrl are also joystick 1
    MsxNotice: Boolean;           // MSX: the note about the QUANTIKA ROMs is shown the first time the machine starts
    MsxCompat: Boolean;           // MSX2: the slots of an MSX1 (none expanded, no disk interface): from the next reset
    MsxCartMapper: string;        // MSX: the mapper of the cartridges inserted: auto, plain, konami, konamiscc, ascii8 or ascii16
    MsxMapper: string;            // MSX2: the memory mapper's ports: auto (off when a tape starts the machine), on or off
    C64CursorJoy: Boolean;        // Commodore 64: the cursor keys and Ctrl are also a joystick
    C64Joystick: Boolean;         // Commodore 64: the numeric keypad and the right Ctrl (or Alt) are a joystick
    C64JoyPort: Integer;          // 1, 2 or 3 (both): the control port that joystick is in
    C64Drive9: Boolean;           // Commodore 64: a second 1541 (device 9) is connected
    C64TapeNoDrive: Boolean;      // Commodore 64: the disk drives are disconnected while a tape is in
    C64SaveDisk: Boolean;         // Commodore 64: what the drives write goes into the .d64 files
    SamClock: Boolean;            // SAM Coupe: the SAMBUS clock interface is connected
    SamAutoDos: Boolean;          // SAM Coupe: SAMDOS2.dsk is inserted and booted on start, reset and model change
    SamMemory: Integer;           // SAM Coupe: the RAM in K, 256 or 512
    DivMMCFirmware: string;       // its EEPROM image ('' = the bundled ESXDOS)
    ZXUnoFirmware: string;        // the ZX-Uno's BIOS ('' = zxuno/FIRMWARE.ZX1)
    NextDir: string;              // the ZX Spectrum Next's distribution ('' = the specnext folder)
    NextCard: string;             // its SD card image ('' = zxnext.img next to ochenta.ini)
    NextDistroId: string;         // the distribution the card was made from
    NextFirmware: Boolean;        // the Next starts through its firmware (else NextZXOS directly)
    { A hidden option, not documented (see CLAUDE.md): the Next says it is a
      real one. RealSpecNext is what applies in this run (the file's value, or
      the command line's over it); the rest tells where it came from and
      whether the licence warning has been accepted (kept in the file). }
    RealSpecNext: Boolean;
    RealSpecNextCmd: Boolean;     // the command line gave it
    RealSpecNextIni: Boolean;     // the settings file has it
    RealSpecNextOk: Boolean;      // the warning was accepted
    ZXUnoRoms: string;            // its ROMs ('' = zxuno/ROMS.ZX1)
    ZXUnoCustomRom: string;       // a 16K ROM run instead of the BIOS's choice ('' = none)
    ZXUnoBios: string;            // its BIOS settings, as the BIOS saved them (hex)
    SDCardFile: string;           // the SD card image inserted (the standard models')
    ZXUnoCard: string;            // the last one inserted in the ZX-Uno ('' = none); the Next's is NextCard
    KempstonMouse: Boolean;
    Monitor: Integer;             // 0 colour, 1 black and white, 2 green phosphor, 3 orange phosphor
    Contention: Boolean;          // memory and I/O contention
    UlaSnow: Boolean;             // ULA snow on the models that have it
    AllowRomEdit: Boolean;        // debugger and POKEs may change the ROM
    ULAPlus: Boolean;             // ULAplus 64-colour palette
    Timex: Boolean;               // Timex screen modes (port FF)
    Radastan: Boolean;            // ZX-Uno Radastan mode (128x96, 16 colours)
    Scanlines: Boolean;           // darker rows between lines (from 2x)
    AttachMouse: Boolean;         // the PC mouse can't leave the window while the emulated mouse is used
    RomFiles: array[TSpectrumModel, 0..3] of string;   // '' = default ROM file
    PokeHistory: TStringList;     // "file|pokes", newest first
    RecentFiles: TStringList;
    RecentSymbols: TStringList;   // symbol files loaded, newest first
    RecentDisks: TStringList;     // disk images inserted, newest first
    RecentCards: TStringList;     // SD card images inserted, newest first
    RecentTapes: TStringList;     // tapes inserted, newest first
    RecentCarts: TStringList;     // MSX cartridges inserted, newest first
    LastDir: string;
    DiskBrowserDir: string;       // last PC folder of the disk browser's import/export
    SDBrowserDir: string;         // and of the SD card browser's
    constructor Create;
    destructor Destroy; override;
    { The setting behind an on/off option (BOOL_OPTIONS), nil if none }
    function BoolField(const Name: string): PBoolean;
    { Load the main file, then the overlay file if one was given }
    procedure Load;
    procedure Save;
    { The hidden option's file entries, changed on the spot (they don't wait
      for the settings to be saved): the warning accepted, and the file's
      own value dropped when the warning isn't accepted }
    { All the settings as text, and back from it (the settings dialog's Cancel
      after an Apply) }
    function Snapshot: string;
    procedure Restore(const Text: string);
    procedure AcceptRealSpecNext;
    { The MSX note was shown: it won't be again (only that key of the file changes) }
    procedure MsxNoticeShown;
    procedure ForgetRealSpecNext;
    procedure AddRecent(const FileName: string);
    procedure AddRecentSymbols(const FileName: string);
    procedure AddRecentDisk(const FileName: string);
    procedure AddRecentCard(const FileName: string);
    procedure AddRecentTape(const FileName: string);
    procedure AddRecentCart(const FileName: string);
    procedure AddPoke(const FileName, Pokes: string);
    { Use another main settings file (--config); it must exist }
    procedure UseFile(const AFileName: string);
    { Settings applied on top of the main file for this session
      (--config-add); a missing file is ignored }
    procedure UseOverlay(const AFileName: string);
    property FileName: string read FFileName;
    property Overlay: string read FOverlay;
  end;

const
  MAX_RECENT = 30;      // kept, newest first
  RECENT_SHOWN = 10;    // listed in the Open recent menus: the machine's own are a few among those kept
  MAX_POKES = 20;
  { What the cursor keys emulate, as in --zx_joystick and the settings file }
  { As in --zx_deinterlace and the settings file }
  DEINTERLACE_KEYS: array[TDeinterlace] of string = ('progressive', 'bob', 'weave');
  { The monitors, as in --monitor and the settings file }
  MONITOR_KEYS: array[0..3] of string = ('color', 'bw', 'green', 'orange');
  // TR-BEGIN (translated where used)
  MONITOR_NAMES: array[0..3] of string = ('Colour', 'Black and white', 'Green phosphor',
    'Orange phosphor (amber)');
  // TR-END
  { The CRTC chips, types 0 to 4 }
  CRTC_NAMES: array[0..4] of string = ('HD6845S / UM6845', 'UM6845R', 'MC6845', 'AMS40489 (CPC+ ASIC)',
    'AMS40226 (pre-ASIC)');
  JOYSTICK_KEYS: array[TJoystickKeys] of string = (
    'none', 'kempston', 'sinclair1', 'sinclair2', 'cursor', 'fuller');

type
  { An on/off option: its name is both the command line option (--name,
    --no-name) and the key in the settings file, in Section }
  TBoolOption = record
    Name, Section: string;
  end;

const
  { Sections of the settings file: the options of the ZX Spectrum models (names
    starting zx_) and of the Amstrad CPC (cpc_) have their own; those of
    both, no prefix, the older ones }
  SEC_ZX = 'ZXSpectrum';
  SEC_CPC = 'AmstradCPC';
  SEC_SAM = 'SAMCoupe';
  SEC_MSX = 'MSX';
  SEC_C64 = 'Commodore64';

  BOOL_OPTIONS: array[0..38] of TBoolOption = (
    (Name: 'saveonexit'; Section: 'General'),
    (Name: 'zx_contention'; Section: SEC_ZX),
    (Name: 'zx_snow'; Section: SEC_ZX),
    (Name: 'romedit'; Section: 'Machine'),
    (Name: 'zx_ulaplus'; Section: SEC_ZX),
    (Name: 'zx_timex'; Section: SEC_ZX),
    (Name: 'zx_radastan'; Section: SEC_ZX),
    (Name: 'scanlines'; Section: 'Machine'),
    (Name: 'attachmouse'; Section: 'Machine'),
    (Name: 'zx_turbosound'; Section: SEC_ZX),
    (Name: 'zx_ay48'; Section: SEC_ZX),
    (Name: 'zx_kmouse'; Section: SEC_ZX),
    (Name: 'zx_divmmc'; Section: SEC_ZX),
    (Name: 'zx_currah'; Section: SEC_ZX),
    (Name: 'zx_leftctrl'; Section: SEC_ZX),
    (Name: 'zx_nextfirmware'; Section: SEC_ZX),
    (Name: 'zx_savetotape'; Section: SEC_ZX),
    (Name: 'cpc_joystick'; Section: SEC_CPC),
    (Name: 'cpc_waitstates'; Section: SEC_CPC),
    (Name: 'msx_joystick'; Section: SEC_MSX),
    (Name: 'msx_compat'; Section: SEC_MSX),
    (Name: 'msx_notice'; Section: SEC_MSX),
    (Name: 'c64_joystick'; Section: SEC_C64),
    (Name: 'c64_cursorjoy'; Section: SEC_C64),
    (Name: 'c64_drive9'; Section: SEC_C64),
    (Name: 'c64_savedisk'; Section: SEC_C64),
    (Name: 'c64_tapenodrive'; Section: SEC_C64),
    (Name: 'sam_saa'; Section: SEC_SAM),
    (Name: 'sam_joystick'; Section: SEC_SAM),
    (Name: 'sam_autodos'; Section: SEC_SAM),
    (Name: 'sam_mouse'; Section: SEC_SAM),
    (Name: 'sam_clock'; Section: SEC_SAM),
    (Name: 'fastload'; Section: 'TapeDisk'),
    (Name: 'autoplay'; Section: 'TapeDisk'),
    (Name: 'tapeloop'; Section: 'TapeDisk'),
    (Name: 'fastdisk'; Section: 'TapeDisk'),
    (Name: 'driveb'; Section: 'TapeDisk'),
    (Name: 'floppynoise'; Section: 'TapeDisk'),
    (Name: 'pngborder'; Section: 'Screenshot'));

  { Options that had another name (and another section in the file) before
    the ones of the ZX Spectrum took zx_ and those of the CPC cpc_: the file
    and the command line still understand the old names }
  OPTION_RENAMES: array[0..28] of record
    NewName, OldName, OldSection: string;
  end = (
    (NewName: 'zx_contention'; OldName: 'contention'; OldSection: 'Machine'),
    (NewName: 'zx_snow'; OldName: 'snow'; OldSection: 'Machine'),
    (NewName: 'zx_ulaplus'; OldName: 'ulaplus'; OldSection: 'Machine'),
    (NewName: 'zx_timex'; OldName: 'timex'; OldSection: 'Machine'),
    (NewName: 'zx_radastan'; OldName: 'radastan'; OldSection: 'Machine'),
    (NewName: 'zx_turbosound'; OldName: 'turbosound'; OldSection: 'Hardware'),
    (NewName: 'zx_ay48'; OldName: 'ay48'; OldSection: 'Hardware'),
    (NewName: 'zx_kmouse'; OldName: 'kmouse'; OldSection: 'Hardware'),
    (NewName: 'zx_divmmc'; OldName: 'divmmc'; OldSection: 'Hardware'),
    (NewName: 'zx_currah'; OldName: 'currah'; OldSection: 'Hardware'),
    (NewName: 'zx_nextfirmware'; OldName: 'nextfirmware'; OldSection: 'ZXNext'),
    (NewName: 'zx_savetotape'; OldName: 'savetotape'; OldSection: 'TapeDisk'),
    (NewName: 'cpc_joystick'; OldName: 'cpcjoystick'; OldSection: 'Hardware'),
    (NewName: 'zx_joystick'; OldName: 'joystick'; OldSection: 'Machine'),
    (NewName: 'zx_deinterlace'; OldName: 'deinterlace'; OldSection: 'Machine'),
    (NewName: 'zx_issue'; OldName: 'issue'; OldSection: 'Machine'),
    (NewName: 'zx_divmmcrom'; OldName: 'divmmcrom'; OldSection: 'ROMs'),
    (NewName: 'zx_unofirmware'; OldName: 'zxunofirmware'; OldSection: 'ROMs'),
    (NewName: 'zx_unoroms'; OldName: 'zxunoroms'; OldSection: 'ROMs'),
    (NewName: 'zx_unocustomrom'; OldName: 'zxunocustomrom'; OldSection: 'ROMs'),
    (NewName: 'zx_nextdir'; OldName: 'nextdir'; OldSection: 'ZXNext'),
    (NewName: 'zx_nextcard'; OldName: 'nextcard'; OldSection: 'ZXNext'),
    (NewName: 'zx_distroid'; OldName: 'distroid'; OldSection: 'ZXNext'),
    (NewName: 'zx_sdcard'; OldName: 'sdcard'; OldSection: 'Media'),
    (NewName: 'zx_unocard'; OldName: 'zxunocard'; OldSection: 'Media'),
    (NewName: 'zx_sdfolder'; OldName: 'sdfolder'; OldSection: ''),
    (NewName: 'zx_sdadd'; OldName: 'sdadd'; OldSection: ''),
    (NewName: 'zx_realspecnext'; OldName: 'realspecnext'; OldSection: 'ZXNext'),
    (NewName: 'zx_realspecnextok'; OldName: 'realspecnextok'; OldSection: 'ZXNext'));

  // TR-BEGIN (translated where used)
  DEINTERLACE_NAMES: array[TDeinterlace] of string = (
    'Progressive (each frame on its own)', 'Bob (two frames blended)', 'Weave (two frames'' lines interleaved)');
  // TR-END
  // TR-BEGIN (translated where used)
  JOYSTICK_NAMES: array[TJoystickKeys] of string = (
    'None (cursor keys and Ctrl as on the keyboard)', 'Kempston',
    'Sinclair Interface 2, joystick 1 (keys 6-0)', 'Sinclair Interface 2, joystick 2 (keys 1-5)',
    'Cursor / Protek / AGF (keys 5-8, 0)', 'Fuller');
  // TR-END

var
  Settings: TSettings;

{ The current name of a command line option given by an old one (without the
  dashes; "no-" is kept): 'turbosound' is 'zx_turbosound' }
function CurrentOptionName(const Name: string): string;
{ The section of the settings file an option of that name is in }
function OptionSection(const NewName: string; const Default: string): string;

{ The standard ROM folder: "roms" next to the executable, or in the folder
  above it (when the executable is built inside src) }
function DefaultRomDir: string;
{ A file or folder that comes with ochenta (such as 'esxdos'): next to the
  executable or in the folder above it; '' if neither }
function OchentaPath(const Name: string): string;
{ The DivMMC firmware to use: the setting, or the bundled ESXDOS }
function DivMMCFirmwareFile: string;
{ The ZX Spectrum Next's distribution folder and its SD card image, as set
  or the defaults }
function NextDistroDir: string;
function NextCardFile: string;
{ The ZX-Uno's BIOS and ROMs files: as set, or the ones in the zxuno folder }
function ZXUnoFirmwareFile: string;
function ZXUnoRomsFile: string;

implementation

uses
  NextCard, Msx;

function DefaultRomDir: string;
var
  Dir: string;
begin
  Dir := ExtractFilePath(ParamStr(0));
  Result := Dir + 'roms';
  if not DirectoryExists(Result) and DirectoryExists(Dir + '..' + PathDelim + 'roms') then
    Result := ExpandFileName(Dir + '..' + PathDelim + 'roms');
  if not DirectoryExists(Result) and DirectoryExists(Dir + '../Resources/roms') then
    Result := ExpandFileName(Dir + '../Resources/roms');     // macOS app bundle
end;

function OchentaPath(const Name: string): string;
var
  Dir: string;
begin
  Dir := ExtractFilePath(ParamStr(0));
  Result := Dir + Name;
  if FileExists(Result) or DirectoryExists(Result) then Exit;
  Result := Dir + '..' + PathDelim + Name;
  if FileExists(Result) or DirectoryExists(Result) then Exit(ExpandFileName(Result));
  Result := Dir + '../Resources/' + Name;      // macOS app bundle
  if FileExists(Result) or DirectoryExists(Result) then Exit(ExpandFileName(Result));
  Result := '';
end;

function ZXUnoFirmwareFile: string;
begin
  Result := Settings.ZXUnoFirmware;
  if Result = '' then Result := OchentaPath('zxuno' + PathDelim + 'FIRMWARE.ZX1');
end;

function ZXUnoRomsFile: string;
begin
  Result := Settings.ZXUnoRoms;
  if Result = '' then Result := OchentaPath('zxuno' + PathDelim + 'ROMS.ZX1');
end;

function DivMMCFirmwareFile: string;
begin
  Result := Settings.DivMMCFirmware;
  if Result = '' then Result := OchentaPath('esxdos' + PathDelim + 'ESXMMC.BIN');
end;

{ Whether a file can be made in Dir (which is created if missing) }
function CanWriteIn(const Dir: string): Boolean;
var
  F: string;
  H: THandle;
begin
  Result := False;
  if not DirectoryExists(Dir) and not ForceDirectories(Dir) then Exit;
  F := IncludeTrailingPathDelimiter(Dir) + '.ochentawrite';
  H := FileCreate(F);
  if H = THandle(-1) then Exit;
  FileClose(H);
  DeleteFile(F);
  Result := True;
end;

function NextDistroDir: string;
var
  Own: string;
begin
  Result := Settings.NextDir;
  if Result <> '' then Exit;
  // The specnext folder next to the program; when that can't be written
  // (installed from a package) the one next to the settings file
  Own := ExtractFilePath(Settings.FileName) + 'specnext';
  Result := OchentaPath('specnext');
  if (Result <> '') and NextDistroReady(Result) then Exit;
  if NextDistroReady(Own) then Exit(Own);
  if (Result = '') or not CanWriteIn(Result) then Result := Own;
end;

function NextCardFile: string;
begin
  Result := Settings.NextCard;
  if Result = '' then Result := ExtractFilePath(Settings.FileName) + 'zxnext.img';
end;

constructor TSettings.Create;
{$IFDEF DARWIN}
var
  Own: string;
{$ENDIF}
begin
  inherited Create;
  RecentFiles := TStringList.Create;
  RecentSymbols := TStringList.Create;
  RecentDisks := TStringList.Create;
  RecentCards := TStringList.Create;
  RecentTapes := TStringList.Create;
  RecentCarts := TStringList.Create;
  PokeHistory := TStringList.Create;
  FMainText := TStringList.Create;
  FFileName := ExtractFilePath(ParamStr(0)) + 'ochenta.ini';
  {$IFDEF DARWIN}
  // Inside an app bundle (which can't be written: it may run from a read-only copy, and changing it breaks its
  // signature): the settings go to ~/Library/Application Support/ochenta, unless there is an ochenta.ini next
  // to ochenta.app (a portable copy). The ZX Spectrum Next's distribution (specnext) and the user's own ROMs
  // (roms/c64, roms/msx: looked in when missing from the ROM folder) go there too; their folders are made
  if Pos('.app/Contents/MacOS/', FFileName) > 0 then
  begin
    FFileName := ExtractFilePath(Copy(FFileName, 1, Pos('.app/Contents/MacOS/', FFileName) + 3)) +
      'ochenta.ini';
    if not FileExists(FFileName) then
    begin
      Own := IncludeTrailingPathDelimiter(GetEnvironmentVariable('HOME')) + 'Library/Application Support/ochenta/';
      ForceDirectories(Own + 'specnext');
      ForceDirectories(Own + 'roms/c64');
      ForceDirectories(Own + 'roms/msx');
      FFileName := Own + 'ochenta.ini';
    end;
    UserRomDir := ExtractFilePath(FFileName) + 'roms';
  end;
  {$ENDIF}
  {$IFDEF UNIX}
  // Installed where users can't write (a .deb or .rpm: /usr/lib/ochenta): the
  // settings go to the user's own folder (~/.config/ochenta/ochenta.ini)
  if FpAccess(ExtractFilePath(FFileName), W_OK) <> 0 then
    FFileName := IncludeTrailingPathDelimiter(GetAppConfigDir(False)) + 'ochenta.ini';
  {$ENDIF}
  Model := sm48K;
  RomDir := DefaultRomDir;
  FastLoad := True;
  AutoPlayTape := True;
  TapeLoop := True;
  Sound := True;
  Volume := 70;
  Scale := 2;
  Joystick := jkKempston;
  Deinterlace := dlWeave;
  Issue2 := False;
  CpuSpeed := 1;
  FastDisk := False;
  DriveB := False;
  FloppyNoise := True;
  SaveOnExit := True;
  ModernUI := True;
  Language := 'auto';
  SaveToTape := True;
  ScreenshotBorder := True;
  TurboSound := False;
  Currah := False;
  LeftCtrlCaps := False;
  CPCJoystick := True;
  CPCWaitStates := True;
  CPCCrtc := -1;
  MsxJoystick := True;
  MsxCompat := False;
  MsxNotice := True;
  MsxCartMapper := 'auto';
  MsxMapper := 'auto';
  C64Joystick := True;
  C64CursorJoy := True;
  C64JoyPort := 3;
  C64Drive9 := False;
  C64SaveDisk := True;
  C64TapeNoDrive := True;
  RunAhead := 0;
  SamSaa := True;
  SamJoystick := True;
  SamAutoDos := True;
  SamMouse := False;
  SamClock := True;
  SamMemory := 512;
  NextFirmware := True;
  RealSpecNext := False;
  RealSpecNextCmd := False;
  RealSpecNextIni := False;
  RealSpecNextOk := False;
  Monitor := 0;
  Contention := True;
  UlaSnow := True;
  AllowRomEdit := False;
  ULAPlus := False;
  Timex := False;
  Radastan := False;
  Scanlines := False;
  AttachMouse := False;
end;

destructor TSettings.Destroy;
begin
  RecentFiles.Free;
  RecentSymbols.Free;
  RecentDisks.Free;
  RecentCards.Free;
  RecentTapes.Free;
  RecentCarts.Free;
  PokeHistory.Free;
  FMainText.Free;
  inherited Destroy;
end;

procedure TSettings.UseFile(const AFileName: string);
begin
  FFileName := ExpandFileName(AFileName);
  FCustomFile := True;
end;

procedure TSettings.UseOverlay(const AFileName: string);
begin
  FOverlay := ExpandFileName(AFileName);
end;

function RomKey(M: TSpectrumModel; I: Integer): string;
begin
  Result := ModelKey(M) + '-' + IntToStr(I);
end;

procedure ReadList(Ini: TCustomIniFile; const Section: string; List: TStringList; Overlay: Boolean);
var
  I: Integer;
  S: string;
begin
  if Overlay and not Ini.SectionExists(Section) then Exit;
  List.Clear;
  for I := 0 to MAX_RECENT - 1 do
  begin
    S := Ini.ReadString(Section, 'File' + IntToStr(I), '');
    if S <> '' then List.Add(S);
  end;
end;

procedure WriteList(Ini: TCustomIniFile; const Section: string; List: TStringList);
var
  I: Integer;
begin
  Ini.EraseSection(Section);
  for I := 0 to List.Count - 1 do
    Ini.WriteString(Section, 'File' + IntToStr(I), List[I]);
end;

const
  // Settings file keys of older versions (read once, then replaced)
  OLD_SECTIONS: array[0..6] of string = ('Display', 'Sound', 'Input', 'Tape', 'Disk', 'DivMMC',
    'Roms');
  OLD_KEYS: array[0..8] of TBoolOption = (
    (Name: 'Model'; Section: 'Machine'), (Name: 'RomDir'; Section: 'Machine'),
    (Name: 'Kempston'; Section: 'Machine'), (Name: 'Issue2'; Section: 'Machine'),
    (Name: 'CpuSpeed'; Section: 'Machine'), (Name: 'UlaSnow'; Section: 'Machine'),
    (Name: 'AllowRomEdit'; Section: 'Machine'), (Name: 'SaveOnExit'; Section: 'Files'),
    (Name: 'Border'; Section: 'Screenshot'));

function TSettings.BoolField(const Name: string): PBoolean;
begin
  case LowerCase(Name) of
    'saveonexit': Result := @SaveOnExit;
    'zx_contention': Result := @Contention;
    'zx_snow': Result := @UlaSnow;
    'romedit': Result := @AllowRomEdit;
    'zx_ulaplus': Result := @ULAPlus;
    'zx_timex': Result := @Timex;
    'zx_radastan': Result := @Radastan;
    'scanlines': Result := @Scanlines;
    'attachmouse': Result := @AttachMouse;
    'zx_turbosound': Result := @TurboSound;
    'zx_ay48': Result := @AY48;
    'zx_kmouse': Result := @KempstonMouse;
    'zx_divmmc': Result := @DivMMC;
    'zx_currah': Result := @Currah;
    'zx_leftctrl': Result := @LeftCtrlCaps;
    'cpc_joystick': Result := @CPCJoystick;
    'cpc_waitstates': Result := @CPCWaitStates;
    'msx_joystick': Result := @MsxJoystick;
    'msx_compat': Result := @MsxCompat;
    'msx_notice': Result := @MsxNotice;
    'c64_joystick': Result := @C64Joystick;
    'c64_cursorjoy': Result := @C64CursorJoy;
    'c64_drive9': Result := @C64Drive9;
    'c64_savedisk': Result := @C64SaveDisk;
    'c64_tapenodrive': Result := @C64TapeNoDrive;
    'sam_saa': Result := @SamSaa;
    'sam_joystick': Result := @SamJoystick;
    'sam_autodos': Result := @SamAutoDos;
    'sam_mouse': Result := @SamMouse;
    'sam_clock': Result := @SamClock;
    'zx_nextfirmware': Result := @NextFirmware;
    'fastload': Result := @FastLoad;
    'autoplay': Result := @AutoPlayTape;
    'tapeloop': Result := @TapeLoop;
    'zx_savetotape': Result := @SaveToTape;
    'fastdisk': Result := @FastDisk;
    'driveb': Result := @DriveB;
    'floppynoise': Result := @FloppyNoise;
    'pngborder': Result := @ScreenshotBorder;
  else
    Result := nil;
  end;
end;

{ "MODEL,N,FILE" entries, as --rom takes them, joined with "|" }
function TSettings.RomList: string;
var
  M: TSpectrumModel;
  I: Integer;
begin
  Result := '';
  for M := Low(TSpectrumModel) to High(TSpectrumModel) do
    for I := 0 to 3 do
      if RomFiles[M, I] <> '' then
      begin
        if Result <> '' then Result := Result + '|';
        Result := Result + Format('%s,%d,%s', [ModelKey(M), I, RomFiles[M, I]]);
      end;
end;

procedure TSettings.SetRomList(const List: string);
var
  Entries, Parts: TStringArray;
  M: TSpectrumModel;
  E, I: Integer;
begin
  for M := Low(TSpectrumModel) to High(TSpectrumModel) do
    for I := 0 to 3 do RomFiles[M, I] := '';
  if List = '' then Exit;
  Entries := List.Split(['|']);
  for E := 0 to High(Entries) do
  begin
    Parts := Entries[E].Split([','], 3);
    if Length(Parts) <> 3 then Continue;
    I := StrToIntDef(Trim(Parts[1]), -1);
    for M := Low(TSpectrumModel) to High(TSpectrumModel) do
      if SameText(Trim(Parts[0]), ModelKey(M)) and (I >= 0) and (I <= 3) then
        RomFiles[M, I] := Trim(Parts[2]);
  end;
end;

function CurrentOptionName(const Name: string): string;
var
  Prefix, Base: string;
  I: Integer;
begin
  Prefix := '';
  Base := LowerCase(Name);
  if Copy(Base, 1, 3) = 'no-' then
  begin
    Prefix := 'no-';
    Base := Copy(Base, 4, MaxInt);
  end;
  for I := 0 to High(OPTION_RENAMES) do
    if Base = OPTION_RENAMES[I].OldName then Exit(Prefix + OPTION_RENAMES[I].NewName);
  Result := Name;
end;

function OptionSection(const NewName: string; const Default: string): string;
begin
  if Copy(NewName, 1, 3) = 'zx_' then Result := SEC_ZX
  else if Copy(NewName, 1, 4) = 'cpc_' then Result := SEC_CPC
  else if Copy(NewName, 1, 4) = 'sam_' then Result := SEC_SAM
  else if Copy(NewName, 1, 4) = 'msx_' then Result := SEC_MSX
  else if Copy(NewName, 1, 4) = 'c64_' then Result := SEC_C64
  else Result := Default;
end;

{ Where an option is in a file: under its name, or under the one it had
  before (a file written by an older version) }
procedure LocateOption(Ini: TCustomIniFile; const Section, Name: string; out Sec, Key: string);
var
  I: Integer;
begin
  Sec := Section;
  Key := Name;
  if Ini.ValueExists(Section, Name) then Exit;
  for I := 0 to High(OPTION_RENAMES) do
    if (OPTION_RENAMES[I].NewName = Name) and (OPTION_RENAMES[I].OldSection <> '') and
       Ini.ValueExists(OPTION_RENAMES[I].OldSection, OPTION_RENAMES[I].OldName) then
    begin
      Sec := OPTION_RENAMES[I].OldSection;
      Key := OPTION_RENAMES[I].OldName;
      Exit;
    end;
end;

function ReadOptString(Ini: TCustomIniFile; const Section, Name, Default: string): string;
var
  Sec, Key: string;
begin
  LocateOption(Ini, Section, Name, Sec, Key);
  Result := Ini.ReadString(Sec, Key, Default);
end;

function ReadOptBool(Ini: TCustomIniFile; const Section, Name: string; Default: Boolean): Boolean;
var
  Sec, Key: string;
begin
  LocateOption(Ini, Section, Name, Sec, Key);
  Result := Ini.ReadBool(Sec, Key, Default);
end;

{ The options, named as on the command line }
procedure TSettings.ReadOptions(Ini: TCustomIniFile);
var
  I: Integer;
  P: PBoolean;
  S: string;
  J: TJoystickKeys;
  D: TDeinterlace;
  MapperTmp: TMsxMapperKind;
begin
  for I := 0 to High(BOOL_OPTIONS) do
  begin
    P := BoolField(BOOL_OPTIONS[I].Name);
    P^ := ReadOptBool(Ini, BOOL_OPTIONS[I].Section, BOOL_OPTIONS[I].Name, P^);
  end;
  Sound := not Ini.ReadBool('General', 'mute', not Sound);
  Model := ModelFromName(LowerCase(Ini.ReadString('General', 'model', ModelKey(Model))), Model);
  Scale := Ini.ReadInteger('General', 'scale', Scale);
  Volume := Ini.ReadInteger('General', 'volume', Volume);
  CpuSpeed := Ini.ReadInteger('General', 'speed', CpuSpeed);
  S := LowerCase(Ini.ReadString('General', 'ui', ''));
  if S = 'modern' then ModernUI := True else if S = 'classic' then ModernUI := False;
  S := LowerCase(Ini.ReadString('General', 'lang', Language));
  if (S = 'auto') or (S = 'en') or (S = 'es') or (S = 'fr') or (S = 'pt') or (S = 'de') then Language := S;
  S := LowerCase(ReadOptString(Ini, SEC_ZX, 'zx_joystick', JOYSTICK_KEYS[Joystick]));
  for J := Low(TJoystickKeys) to High(TJoystickKeys) do
    if S = JOYSTICK_KEYS[J] then Joystick := J;
  S := LowerCase(ReadOptString(Ini, SEC_ZX, 'zx_deinterlace', DEINTERLACE_KEYS[Deinterlace]));
  for D := Low(TDeinterlace) to High(TDeinterlace) do
    if S = DEINTERLACE_KEYS[D] then Deinterlace := D;
  S := ReadOptString(Ini, SEC_ZX, 'zx_issue', '');
  if S = '2' then Issue2 := True else if S = '3' then Issue2 := False;
  S := LowerCase(Ini.ReadString(SEC_CPC, 'cpc_crtc', ''));
  if S = 'auto' then CPCCrtc := -1
  else if (Length(S) = 1) and (S[1] in ['0'..'4']) then CPCCrtc := Ord(S[1]) - 48;
  S := LowerCase(Ini.ReadString(SEC_MSX, 'msx_cartmapper', MsxCartMapper));
  if (S = 'auto') or MapperFromName(S, MapperTmp) then MsxCartMapper := S;
  S := LowerCase(Ini.ReadString(SEC_MSX, 'msx_mapper', MsxMapper));
  if (S = 'auto') or (S = 'on') or (S = 'off') then MsxMapper := S;
  I := Ini.ReadInteger(SEC_C64, 'c64_joyport', C64JoyPort);
  if (I >= 1) and (I <= 3) then C64JoyPort := I;
  I := Ini.ReadInteger('Emulation', 'runahead', RunAhead);
  if (I >= 0) and (I <= 3) then RunAhead := I;
  I := Ini.ReadInteger(SEC_SAM, 'sam_memory', SamMemory);
  if (I = 256) or (I = 512) then SamMemory := I;
  // The monitor; older files had "bw", an on/off for the black and white display
  if Ini.ValueExists('General', 'bw') and Ini.ReadBool('General', 'bw', False) then Monitor := 1;
  S := LowerCase(Ini.ReadString('General', 'monitor', ''));
  for I := 0 to 3 do
    if S = MONITOR_KEYS[I] then Monitor := I;
  S := Ini.ReadString('ROMs', 'romdir', RomDir);
  // a saved folder that no longer exists (moved or renamed) keeps the default one
  if DirectoryExists(S) then RomDir := S;
  if Ini.ValueExists('ROMs', 'rom') then SetRomList(Ini.ReadString('ROMs', 'rom', ''));
  DivMMCFirmware := ReadOptString(Ini, SEC_ZX, 'zx_divmmcrom', DivMMCFirmware);
  ZXUnoFirmware := ReadOptString(Ini, SEC_ZX, 'zx_unofirmware', ZXUnoFirmware);
  ZXUnoRoms := ReadOptString(Ini, SEC_ZX, 'zx_unoroms', ZXUnoRoms);
  ZXUnoCustomRom := ReadOptString(Ini, SEC_ZX, 'zx_unocustomrom', ZXUnoCustomRom);
  NextDir := ReadOptString(Ini, SEC_ZX, 'zx_nextdir', NextDir);
  NextCard := ReadOptString(Ini, SEC_ZX, 'zx_nextcard', NextCard);
  NextDistroId := ReadOptString(Ini, SEC_ZX, 'zx_distroid', NextDistroId);
  // Older versions kept the README's version with its double spaces
  while Pos('  ', NextDistroId) > 0 do
    NextDistroId := StringReplace(NextDistroId, '  ', ' ', [rfReplaceAll]);
  SDCardFile := ReadOptString(Ini, SEC_ZX, 'zx_sdcard', SDCardFile);
  ZXUnoCard := ReadOptString(Ini, SEC_ZX, 'zx_unocard', ZXUnoCard);
end;

procedure TSettings.WriteOptions(Ini: TCustomIniFile);

  { Delete first, so the key takes the option's spelling; and the key the
    option had before it was renamed goes }
  procedure Put(const Section, Name, Value: string);
  var
    I: Integer;
  begin
    Ini.DeleteKey(Section, Name);
    Ini.WriteString(Section, Name, Value);
    for I := 0 to High(OPTION_RENAMES) do
      if (OPTION_RENAMES[I].NewName = Name) and (OPTION_RENAMES[I].OldSection <> '') then
        Ini.DeleteKey(OPTION_RENAMES[I].OldSection, OPTION_RENAMES[I].OldName);
  end;

var
  I: Integer;
const
  ONOFF: array[Boolean] of string = ('0', '1');
begin
  for I := 0 to High(BOOL_OPTIONS) do
    Put(BOOL_OPTIONS[I].Section, BOOL_OPTIONS[I].Name, ONOFF[BoolField(BOOL_OPTIONS[I].Name)^]);
  Put('General', 'mute', ONOFF[not Sound]);
  Put('General', 'model', ModelKey(Model));
  Put('General', 'scale', IntToStr(Scale));
  if ModernUI then Put('General', 'ui', 'modern') else Put('General', 'ui', 'classic');
  Put('General', 'lang', Language);
  Put('General', 'volume', IntToStr(Volume));
  Put('General', 'speed', IntToStr(CpuSpeed));
  Put(SEC_ZX, 'zx_joystick', JOYSTICK_KEYS[Joystick]);
  Put(SEC_ZX, 'zx_deinterlace', DEINTERLACE_KEYS[Deinterlace]);
  if Issue2 then Put(SEC_ZX, 'zx_issue', '2') else Put(SEC_ZX, 'zx_issue', '3');
  if CPCCrtc < 0 then Put(SEC_CPC, 'cpc_crtc', 'auto') else Put(SEC_CPC, 'cpc_crtc', IntToStr(CPCCrtc));
  Put(SEC_SAM, 'sam_memory', IntToStr(SamMemory));
  Put(SEC_C64, 'c64_joyport', IntToStr(C64JoyPort));
  Put('Emulation', 'runahead', IntToStr(RunAhead));
  Put(SEC_MSX, 'msx_cartmapper', MsxCartMapper);
  Put(SEC_MSX, 'msx_mapper', MsxMapper);
  Put('General', 'monitor', MONITOR_KEYS[Monitor]);
  Ini.DeleteKey('General', 'bw');
  Put('ROMs', 'romdir', RomDir);
  Put('ROMs', 'rom', RomList);
  Put(SEC_ZX, 'zx_divmmcrom', DivMMCFirmware);
  Put(SEC_ZX, 'zx_unofirmware', ZXUnoFirmware);
  Put(SEC_ZX, 'zx_unoroms', ZXUnoRoms);
  Put(SEC_ZX, 'zx_unocustomrom', ZXUnoCustomRom);
  Put(SEC_ZX, 'zx_nextdir', NextDir);
  Put(SEC_ZX, 'zx_nextcard', NextCard);
  Put(SEC_ZX, 'zx_distroid', NextDistroId);
  if RealSpecNextIni then Put(SEC_ZX, 'zx_realspecnext', '1') else Ini.DeleteKey(SEC_ZX, 'zx_realspecnext');
  if RealSpecNextOk then Put(SEC_ZX, 'zx_realspecnextok', '1') else Ini.DeleteKey(SEC_ZX, 'zx_realspecnextok');
  if not RealSpecNextIni then Ini.DeleteKey('ZXNext', 'realspecnext');
  if not RealSpecNextOk then Ini.DeleteKey('ZXNext', 'realspecnextok');
  Put(SEC_ZX, 'zx_sdcard', SDCardFile);
  Put(SEC_ZX, 'zx_unocard', ZXUnoCard);
end;

{ Values missing from the file keep their current value, so the overlay only
  changes what it mentions }
procedure TSettings.ReadFrom(Ini: TCustomIniFile; Overlay: Boolean);
var
  I: Integer;
  S: string;
  M: TSpectrumModel;
begin
  Model := ModelFromName(Ini.ReadString('Machine', 'Model', ModelKey(Model)), Model);
  RomDir := Ini.ReadString('Machine', 'RomDir', RomDir);
  FastLoad := Ini.ReadBool('Tape', 'FastLoad', FastLoad);
  AutoPlayTape := Ini.ReadBool('Tape', 'AutoPlay', AutoPlayTape);
  Sound := Ini.ReadBool('Sound', 'Enabled', Sound);
  Volume := Ini.ReadInteger('Sound', 'Volume', Volume);
  TurboSound := Ini.ReadBool('Sound', 'TurboSound', TurboSound);
  AY48 := Ini.ReadBool('Sound', 'AY48', AY48);
  DivMMC := Ini.ReadBool('DivMMC', 'Enabled', DivMMC);
  DivMMCFirmware := Ini.ReadString('DivMMC', 'Firmware', DivMMCFirmware);
  SDCardFile := Ini.ReadString('DivMMC', 'Card', SDCardFile);
  KempstonMouse := Ini.ReadBool('Input', 'KempstonMouse', KempstonMouse);
  Scale := Ini.ReadInteger('Display', 'Scale', Scale);
  if Ini.ReadBool('Display', 'Monochrome', False) then Monitor := 1;
  I := Ini.ReadInteger('Input', 'Joystick', Ord(Joystick));
  if (I >= Ord(Low(TJoystickKeys))) and (I <= Ord(High(TJoystickKeys))) then
    Joystick := TJoystickKeys(I);
  Issue2 := Ini.ReadBool('Machine', 'Issue2', Issue2);
  CpuSpeed := Ini.ReadInteger('Machine', 'CpuSpeed', CpuSpeed);
  Contention := Ini.ReadBool('Machine', 'Contention', Contention);
  UlaSnow := Ini.ReadBool('Machine', 'UlaSnow', UlaSnow);
  AllowRomEdit := Ini.ReadBool('Machine', 'AllowRomEdit', AllowRomEdit);
  for M := Low(TSpectrumModel) to High(TSpectrumModel) do
    for I := 0 to 3 do
      RomFiles[M, I] := Ini.ReadString('Roms', RomKey(M, I), RomFiles[M, I]);
  FastDisk := Ini.ReadBool('Disk', 'Fast', FastDisk);
  DriveB := Ini.ReadBool('Disk', 'DriveB', DriveB);
  FloppyNoise := Ini.ReadBool('Disk', 'Noise', FloppyNoise);
  SaveOnExit := Ini.ReadBool('Files', 'SaveOnExit', SaveOnExit);
  SaveToTape := Ini.ReadBool('Tape', 'SaveToTape', SaveToTape);
  ScreenshotBorder := Ini.ReadBool('Screenshot', 'Border', ScreenshotBorder);
  // The keys above are those of older versions; these are the current ones,
  // named as the command line options
  ReadOptions(Ini);
  if not Overlay then
  begin
    RealSpecNextIni := ReadOptBool(Ini, SEC_ZX, 'zx_realspecnext', False);
    RealSpecNext := RealSpecNextIni;
    RealSpecNextOk := ReadOptBool(Ini, SEC_ZX, 'zx_realspecnextok', False);
  end;
  if not Overlay or Ini.SectionExists('Pokes') then
  begin
    PokeHistory.Clear;
    for I := 0 to MAX_POKES - 1 do
    begin
      S := Ini.ReadString('Pokes', 'Poke' + IntToStr(I), '');
      if S <> '' then PokeHistory.Add(S);
    end;
  end;
  LastDir := Ini.ReadString('Files', 'LastDir', LastDir);
  DiskBrowserDir := Ini.ReadString('Files', 'DiskBrowserDir', DiskBrowserDir);
  SDBrowserDir := Ini.ReadString('Files', 'SDBrowserDir', SDBrowserDir);
  ZXUnoBios := Ini.ReadString('ZXUno', 'BiosSettings', ZXUnoBios);
  ZXUnoBios := Ini.ReadString(SEC_ZX, 'zx_unobios', ZXUnoBios);
  ReadList(Ini, 'RecentDisks', RecentDisks, Overlay);
  ReadList(Ini, 'RecentCards', RecentCards, Overlay);
  ReadList(Ini, 'RecentTapes', RecentTapes, Overlay);
  ReadList(Ini, 'RecentCarts', RecentCarts, Overlay);
  if not Overlay or Ini.SectionExists('RecentSymbols') then
  begin
    RecentSymbols.Clear;
    for I := 0 to MAX_RECENT - 1 do
    begin
      S := Ini.ReadString('RecentSymbols', 'File' + IntToStr(I), '');
      if S <> '' then RecentSymbols.Add(S);
    end;
  end;
  if not Overlay or Ini.SectionExists('Recent') then
  begin
    RecentFiles.Clear;
    for I := 0 to MAX_RECENT - 1 do
    begin
      S := Ini.ReadString('Recent', 'File' + IntToStr(I), '');
      if S <> '' then RecentFiles.Add(S);
    end;
  end;
end;

procedure TSettings.Load;
var
  Ini: TMemIniFile;
  Old: string;
begin
  FMainText.Clear;
  Old := IncludeTrailingPathDelimiter(GetAppConfigDir(False)) + 'ochenta.ini';
  if FileExists(FFileName) then
    FMainText.LoadFromFile(FFileName)
{$IFDEF WINDOWS};  // On Windows only the ini next to the executable is read
{$ELSE}
  else if not FCustomFile and FileExists(ExtractFilePath(FFileName) + '..' + PathDelim + 'ochenta.ini') then
    // Settings next to an executable that used to live one folder up
    FMainText.LoadFromFile(ExtractFilePath(FFileName) + '..' + PathDelim + 'ochenta.ini')
  else if not FCustomFile and FileExists(Old) then
    FMainText.LoadFromFile(Old);    // settings of older versions, kept per user
{$ENDIF}
  Ini := TMemIniFile.Create('');
  try
    Ini.SetStrings(FMainText);
    ReadFrom(Ini, False);
  finally
    Ini.Free;
  end;
  if (FOverlay <> '') and FileExists(FOverlay) then
  begin
    Ini := TMemIniFile.Create(FOverlay);
    try
      ReadFrom(Ini, True);
    finally
      Ini.Free;
    end;
  end;
  if (Scale < 1) or (Scale > 4) then Scale := 2;
  if (Volume < 0) or (Volume > 100) then Volume := 70;
  if not (CpuSpeed in [1, 2, 4, 8, 16, 32]) then CpuSpeed := 1;
end;

procedure TSettings.WriteTo(Ini: TCustomIniFile);
var
  I: Integer;
begin
  // Keys of older versions go: the options are written under their names
  for I := 0 to High(OLD_SECTIONS) do Ini.EraseSection(OLD_SECTIONS[I]);
  for I := 0 to High(OLD_KEYS) do Ini.DeleteKey(OLD_KEYS[I].Section, OLD_KEYS[I].Name);
  WriteOptions(Ini);
  Ini.EraseSection('Pokes');
  for I := 0 to PokeHistory.Count - 1 do
    Ini.WriteString('Pokes', 'Poke' + IntToStr(I), PokeHistory[I]);
  Ini.WriteString('Files', 'LastDir', LastDir);
  Ini.WriteString('Files', 'DiskBrowserDir', DiskBrowserDir);
  Ini.WriteString('Files', 'SDBrowserDir', SDBrowserDir);
  Ini.DeleteKey('ZXUno', 'BiosSettings');
  if ZXUnoBios <> '' then Ini.WriteString(SEC_ZX, 'zx_unobios', ZXUnoBios);
  WriteList(Ini, 'RecentDisks', RecentDisks);
  WriteList(Ini, 'RecentCards', RecentCards);
  WriteList(Ini, 'RecentTapes', RecentTapes);
  WriteList(Ini, 'RecentCarts', RecentCarts);
  Ini.EraseSection('RecentSymbols');
  for I := 0 to RecentSymbols.Count - 1 do
    Ini.WriteString('RecentSymbols', 'File' + IntToStr(I), RecentSymbols[I]);
  Ini.EraseSection('Recent');
  for I := 0 to RecentFiles.Count - 1 do
    Ini.WriteString('Recent', 'File' + IntToStr(I), RecentFiles[I]);
end;

procedure TSettings.Save;
var
  Ini, Over, Main: TMemIniFile;
  Sections, Keys, Text: TStringList;
  I, J: Integer;
  Sec, Key: string;
begin
  Ini := TMemIniFile.Create('');
  Text := TStringList.Create;
  try
    Ini.SetStrings(FMainText);   // keeps keys this version doesn't know
    WriteTo(Ini);
    if (FOverlay <> '') and FileExists(FOverlay) then
    begin
      // Values that still match the overlay came from it: keep the main
      // file's own value for them
      Over := TMemIniFile.Create(FOverlay);
      Main := TMemIniFile.Create('');
      Sections := TStringList.Create;
      Keys := TStringList.Create;
      try
        Main.SetStrings(FMainText);
        Over.ReadSections(Sections);
        for I := 0 to Sections.Count - 1 do
        begin
          Sec := Sections[I];
          Over.ReadSection(Sec, Keys);
          for J := 0 to Keys.Count - 1 do
          begin
            Key := Keys[J];
            if Ini.ReadString(Sec, Key, #1) <> Over.ReadString(Sec, Key, #2) then Continue;
            if Main.ValueExists(Sec, Key) then
              Ini.WriteString(Sec, Key, Main.ReadString(Sec, Key, ''))
            else
              Ini.DeleteKey(Sec, Key);
          end;
        end;
      finally
        Keys.Free;
        Sections.Free;
        Main.Free;
        Over.Free;
      end;
    end;
    Ini.GetStrings(Text);
    try
      ForceDirectories(ExtractFilePath(FFileName));
      Text.SaveToFile(FFileName);
      FMainText.Assign(Text);
    except
      // Read-only folder: settings are not saved
    end;
  finally
    Text.Free;
    Ini.Free;
  end;
end;

{ One key of the settings file, changed now: written, or deleted when Value
  is empty (the rest of the file as it is) }
procedure ChangeFileKey(const FileName: string; Text: TStringList;
  const Section, Key, Value: string);
var
  Ini: TMemIniFile;
begin
  Ini := TMemIniFile.Create('');
  try
    Ini.SetStrings(Text);
    Ini.DeleteKey(Section, Key);
    if Value <> '' then Ini.WriteString(Section, Key, Value);
    Text.Clear;
    Ini.GetStrings(Text);
    try
      ForceDirectories(ExtractFilePath(FileName));
      Text.SaveToFile(FileName);
    except
      // Read-only folder: it stays as it was
    end;
  finally
    Ini.Free;
  end;
end;

function TSettings.Snapshot: string;
var
  Ini: TMemIniFile;
  L: TStringList;
begin
  Ini := TMemIniFile.Create('');
  L := TStringList.Create;
  try
    WriteTo(Ini);
    Ini.GetStrings(L);
    Result := L.Text;
  finally
    L.Free;
    Ini.Free;
  end;
end;

procedure TSettings.Restore(const Text: string);
var
  Ini: TMemIniFile;
  L: TStringList;
  Real, Cmd: Boolean;
begin
  Real := RealSpecNext;
  Cmd := RealSpecNextCmd;
  Ini := TMemIniFile.Create('');
  L := TStringList.Create;
  try
    L.Text := Text;
    Ini.SetStrings(L);
    ReadFrom(Ini, False);
  finally
    L.Free;
    Ini.Free;
  end;
  RealSpecNext := Real;
  RealSpecNextCmd := Cmd;
end;

procedure TSettings.MsxNoticeShown;
begin
  MsxNotice := False;
  if FileExists(FFileName) then ChangeFileKey(FFileName, FMainText, SEC_MSX, 'msx_notice', '0')
  else Save;
end;

procedure TSettings.AcceptRealSpecNext;
begin
  RealSpecNextOk := True;
  ChangeFileKey(FFileName, FMainText, SEC_ZX, 'zx_realspecnextok', '1');
end;

procedure TSettings.ForgetRealSpecNext;
begin
  RealSpecNextIni := False;
  ChangeFileKey(FFileName, FMainText, SEC_ZX, 'zx_realspecnext', '');
  ChangeFileKey(FFileName, FMainText, 'ZXNext', 'realspecnext', '');
end;

procedure TSettings.AddPoke(const FileName, Pokes: string);
var
  Entry: string;
  I: Integer;
begin
  Entry := ExtractFileName(FileName) + '|' + Pokes;
  I := PokeHistory.IndexOf(Entry);
  if I >= 0 then PokeHistory.Delete(I);
  PokeHistory.Insert(0, Entry);
  while PokeHistory.Count > MAX_POKES do PokeHistory.Delete(PokeHistory.Count - 1);
end;

{ A recent-files list: newest first, no repeats, MAX_RECENT at most }
procedure AddToRecent(List: TStringList; const FileName: string);
var
  I: Integer;
begin
  I := List.IndexOf(FileName);
  if I >= 0 then List.Delete(I);
  List.Insert(0, FileName);
  while List.Count > MAX_RECENT do List.Delete(List.Count - 1);
end;

procedure TSettings.AddRecentDisk(const FileName: string);
begin
  AddToRecent(RecentDisks, FileName);
end;

procedure TSettings.AddRecentCard(const FileName: string);
begin
  AddToRecent(RecentCards, FileName);
end;

procedure TSettings.AddRecentTape(const FileName: string);
begin
  AddToRecent(RecentTapes, FileName);
end;

procedure TSettings.AddRecentCart(const FileName: string);
begin
  AddToRecent(RecentCarts, FileName);
end;

procedure TSettings.AddRecentSymbols(const FileName: string);
var
  I: Integer;
begin
  I := RecentSymbols.IndexOf(FileName);
  if I >= 0 then RecentSymbols.Delete(I);
  RecentSymbols.Insert(0, FileName);
  while RecentSymbols.Count > MAX_RECENT do RecentSymbols.Delete(RecentSymbols.Count - 1);
end;

procedure TSettings.AddRecent(const FileName: string);
var
  I: Integer;
begin
  I := RecentFiles.IndexOf(FileName);
  if I >= 0 then RecentFiles.Delete(I);
  RecentFiles.Insert(0, FileName);
  while RecentFiles.Count > MAX_RECENT do RecentFiles.Delete(RecentFiles.Count - 1);
  LastDir := ExtractFilePath(FileName);
end;

initialization
  Settings := TSettings.Create;

finalization
  Settings.Free;

end.

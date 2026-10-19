{ Config: user settings, stored in pzx.ini next to the executable (or in the
  file given with --config). A second file given with --config-add is
  applied on top for the session without being merged into the main file. }
unit Config;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, IniFiles, Models;

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
    Sound: Boolean;
    Volume: Integer;           // 0..100
    Scale: Integer;            // 1..4
    Joystick: TJoystickKeys;
    Issue2: Boolean;
    { Shift and Ctrl: False = Shift is CAPS SHIFT and Ctrl SYMBOL SHIFT;
      True = the left ones are CAPS SHIFT and the right ones SYMBOL SHIFT }
    ShiftSides: Boolean;              // 16K/48K keyboard issue 2 (else issue 3)
    CpuSpeed: Integer;            // 1, 2, 4 ... 32 (interrupts stay at 50 Hz)
    FastDisk: Boolean;            // disk without real drive timing
    DriveB: Boolean;              // second drive connected to the +3
    FloppyNoise: Boolean;         // the drive's sound at real speed
    SaveOnExit: Boolean;          // write the settings when pzx closes
    SaveToTape: Boolean;          // SAVE adds blocks to the tape
    ScreenshotBorder: Boolean;
    TurboSound: Boolean;          // two AY chips (128K and later)
    AY48: Boolean;                // AY interface on the 16K/48K
    DivMMC: Boolean;              // DivMMC interface connected
    DivMMCFirmware: string;       // its EEPROM image ('' = the bundled ESXDOS)
    ZXUnoFirmware: string;        // the ZX-Uno's BIOS ('' = zxuno/FIRMWARE.ZX1)
    ZXUnoRoms: string;            // its ROMs ('' = zxuno/ROMS.ZX1)
    ZXUnoCustomRom: string;       // a 16K ROM run instead of the BIOS's choice ('' = none)
    ZXUnoBios: string;            // its BIOS settings, as the BIOS saved them (hex)
    SDCardFile: string;           // the SD card image inserted
    KempstonMouse: Boolean;
    Monochrome: Boolean;          // black and white display
    Contention: Boolean;          // memory and I/O contention
    UlaSnow: Boolean;             // ULA snow on the models that have it
    AllowRomEdit: Boolean;        // debugger and POKEs may change the ROM
    ULAPlus: Boolean;             // ULAplus 64-colour palette
    Timex: Boolean;               // Timex screen modes (port FF)
    Radastan: Boolean;            // ZX-Uno Radastan mode (128x96, 16 colours)
    Scanlines: Boolean;           // darker rows between lines (from 2x)
    RomFiles: array[TSpectrumModel, 0..3] of string;   // '' = default ROM file
    PokeHistory: TStringList;     // "file|pokes", newest first
    RecentFiles: TStringList;
    RecentSymbols: TStringList;   // symbol files loaded, newest first
    RecentDisks: TStringList;     // disk images inserted, newest first
    RecentCards: TStringList;     // SD card images inserted, newest first
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
    procedure AddRecent(const FileName: string);
    procedure AddRecentSymbols(const FileName: string);
    procedure AddRecentDisk(const FileName: string);
    procedure AddRecentCard(const FileName: string);
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
  MAX_RECENT = 8;
  MAX_POKES = 20;
  { What the cursor keys emulate, as in --joystick and the settings file }
  JOYSTICK_KEYS: array[TJoystickKeys] of string = (
    'none', 'kempston', 'sinclair1', 'sinclair2', 'cursor', 'fuller');

type
  { An on/off option: its name is both the command line option (--name,
    --no-name) and the key in the settings file, in Section }
  TBoolOption = record
    Name, Section: string;
  end;

const
  BOOL_OPTIONS: array[0..19] of TBoolOption = (
    (Name: 'bw'; Section: 'General'),
    (Name: 'saveonexit'; Section: 'General'),
    (Name: 'contention'; Section: 'Machine'),
    (Name: 'snow'; Section: 'Machine'),
    (Name: 'romedit'; Section: 'Machine'),
    (Name: 'ulaplus'; Section: 'Machine'),
    (Name: 'timex'; Section: 'Machine'),
    (Name: 'radastan'; Section: 'Machine'),
    (Name: 'scanlines'; Section: 'Machine'),
    (Name: 'turbosound'; Section: 'Hardware'),
    (Name: 'ay48'; Section: 'Hardware'),
    (Name: 'kmouse'; Section: 'Hardware'),
    (Name: 'divmmc'; Section: 'Hardware'),
    (Name: 'fastload'; Section: 'TapeDisk'),
    (Name: 'autoplay'; Section: 'TapeDisk'),
    (Name: 'savetotape'; Section: 'TapeDisk'),
    (Name: 'fastdisk'; Section: 'TapeDisk'),
    (Name: 'driveb'; Section: 'TapeDisk'),
    (Name: 'floppynoise'; Section: 'TapeDisk'),
    (Name: 'pngborder'; Section: 'Screenshot'));

  JOYSTICK_NAMES: array[TJoystickKeys] of string = (
    'None (cursor keys and Ctrl as on the keyboard)', 'Kempston',
    'Sinclair Interface 2, joystick 1 (keys 6-0)', 'Sinclair Interface 2, joystick 2 (keys 1-5)',
    'Cursor / Protek / AGF (keys 5-8, 0)', 'Fuller');

var
  Settings: TSettings;

{ The standard ROM folder: "roms" next to the executable, or in the folder
  above it (when the executable is built inside src) }
function DefaultRomDir: string;
{ A file or folder that comes with pzx (such as 'esxdos'): next to the
  executable or in the folder above it; '' if neither }
function PzxPath(const Name: string): string;
{ The DivMMC firmware to use: the setting, or the bundled ESXDOS }
function DivMMCFirmwareFile: string;
{ The ZX-Uno's BIOS and ROMs files: as set, or the ones in the zxuno folder }
function ZXUnoFirmwareFile: string;
function ZXUnoRomsFile: string;

implementation

function DefaultRomDir: string;
var
  Dir: string;
begin
  Dir := ExtractFilePath(ParamStr(0));
  Result := Dir + 'roms';
  if not DirectoryExists(Result) and DirectoryExists(Dir + '..' + PathDelim + 'roms') then
    Result := ExpandFileName(Dir + '..' + PathDelim + 'roms');
end;

function PzxPath(const Name: string): string;
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
  if Result = '' then Result := PzxPath('zxuno' + PathDelim + 'FIRMWARE.ZX1');
end;

function ZXUnoRomsFile: string;
begin
  Result := Settings.ZXUnoRoms;
  if Result = '' then Result := PzxPath('zxuno' + PathDelim + 'ROMS.ZX1');
end;

function DivMMCFirmwareFile: string;
begin
  Result := Settings.DivMMCFirmware;
  if Result = '' then Result := PzxPath('esxdos' + PathDelim + 'ESXMMC.BIN');
end;

constructor TSettings.Create;
begin
  inherited Create;
  RecentFiles := TStringList.Create;
  RecentSymbols := TStringList.Create;
  RecentDisks := TStringList.Create;
  RecentCards := TStringList.Create;
  PokeHistory := TStringList.Create;
  FMainText := TStringList.Create;
  FFileName := ExtractFilePath(ParamStr(0)) + 'pzx.ini';
  {$IFDEF DARWIN}
  // Inside an app bundle: keep it next to pzx.app
  if Pos('.app/Contents/MacOS/', FFileName) > 0 then
    FFileName := ExtractFilePath(Copy(FFileName, 1, Pos('.app/Contents/MacOS/', FFileName) + 3)) +
      'pzx.ini';
  {$ENDIF}
  Model := sm48K;
  RomDir := DefaultRomDir;
  FastLoad := True;
  AutoPlayTape := True;
  Sound := True;
  Volume := 70;
  Scale := 2;
  Joystick := jkNone;
  Issue2 := False;
  ShiftSides := False;
  CpuSpeed := 1;
  FastDisk := False;
  DriveB := False;
  FloppyNoise := True;
  SaveOnExit := True;
  SaveToTape := True;
  ScreenshotBorder := True;
  TurboSound := False;
  Monochrome := False;
  Contention := True;
  UlaSnow := True;
  AllowRomEdit := False;
  ULAPlus := False;
  Timex := False;
  Radastan := False;
  Scanlines := False;
end;

destructor TSettings.Destroy;
begin
  RecentFiles.Free;
  RecentSymbols.Free;
  RecentDisks.Free;
  RecentCards.Free;
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
    'bw': Result := @Monochrome;
    'saveonexit': Result := @SaveOnExit;
    'contention': Result := @Contention;
    'snow': Result := @UlaSnow;
    'romedit': Result := @AllowRomEdit;
    'ulaplus': Result := @ULAPlus;
    'timex': Result := @Timex;
    'radastan': Result := @Radastan;
    'scanlines': Result := @Scanlines;
    'turbosound': Result := @TurboSound;
    'ay48': Result := @AY48;
    'kmouse': Result := @KempstonMouse;
    'divmmc': Result := @DivMMC;
    'fastload': Result := @FastLoad;
    'autoplay': Result := @AutoPlayTape;
    'savetotape': Result := @SaveToTape;
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

{ The options, named as on the command line }
procedure TSettings.ReadOptions(Ini: TCustomIniFile);
var
  I: Integer;
  P: PBoolean;
  S: string;
  J: TJoystickKeys;
begin
  for I := 0 to High(BOOL_OPTIONS) do
  begin
    P := BoolField(BOOL_OPTIONS[I].Name);
    P^ := Ini.ReadBool(BOOL_OPTIONS[I].Section, BOOL_OPTIONS[I].Name, P^);
  end;
  Sound := not Ini.ReadBool('General', 'mute', not Sound);
  Model := ModelFromName(LowerCase(Ini.ReadString('General', 'model', ModelKey(Model))), Model);
  Scale := Ini.ReadInteger('General', 'scale', Scale);
  Volume := Ini.ReadInteger('General', 'volume', Volume);
  CpuSpeed := Ini.ReadInteger('General', 'speed', CpuSpeed);
  S := LowerCase(Ini.ReadString('Machine', 'joystick', JOYSTICK_KEYS[Joystick]));
  for J := Low(TJoystickKeys) to High(TJoystickKeys) do
    if S = JOYSTICK_KEYS[J] then Joystick := J;
  S := LowerCase(Ini.ReadString('Machine', 'shiftkeys', ''));
  if S = 'sides' then ShiftSides := True else if S = 'standard' then ShiftSides := False;
  S := Ini.ReadString('Machine', 'issue', '');
  if S = '2' then Issue2 := True else if S = '3' then Issue2 := False;
  RomDir := Ini.ReadString('ROMs', 'romdir', RomDir);
  if Ini.ValueExists('ROMs', 'rom') then SetRomList(Ini.ReadString('ROMs', 'rom', ''));
  DivMMCFirmware := Ini.ReadString('ROMs', 'divmmcrom', DivMMCFirmware);
  ZXUnoFirmware := Ini.ReadString('ROMs', 'zxunofirmware', ZXUnoFirmware);
  ZXUnoRoms := Ini.ReadString('ROMs', 'zxunoroms', ZXUnoRoms);
  ZXUnoCustomRom := Ini.ReadString('ROMs', 'zxunocustomrom', ZXUnoCustomRom);
  SDCardFile := Ini.ReadString('Media', 'sdcard', SDCardFile);
end;

procedure TSettings.WriteOptions(Ini: TCustomIniFile);

  { Delete first, so the key takes the option's spelling }
  procedure Put(const Section, Name, Value: string);
  begin
    Ini.DeleteKey(Section, Name);
    Ini.WriteString(Section, Name, Value);
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
  Put('General', 'volume', IntToStr(Volume));
  Put('General', 'speed', IntToStr(CpuSpeed));
  Put('Machine', 'joystick', JOYSTICK_KEYS[Joystick]);
  if Issue2 then Put('Machine', 'issue', '2') else Put('Machine', 'issue', '3');
  if ShiftSides then Put('Machine', 'shiftkeys', 'sides') else Put('Machine', 'shiftkeys', 'standard');
  Put('ROMs', 'romdir', RomDir);
  Put('ROMs', 'rom', RomList);
  Put('ROMs', 'divmmcrom', DivMMCFirmware);
  Put('ROMs', 'zxunofirmware', ZXUnoFirmware);
  Put('ROMs', 'zxunoroms', ZXUnoRoms);
  Put('ROMs', 'zxunocustomrom', ZXUnoCustomRom);
  Put('Media', 'sdcard', SDCardFile);
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
  Monochrome := Ini.ReadBool('Display', 'Monochrome', Monochrome);
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
  ReadList(Ini, 'RecentDisks', RecentDisks, Overlay);
  ReadList(Ini, 'RecentCards', RecentCards, Overlay);
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
  Old := IncludeTrailingPathDelimiter(GetAppConfigDir(False)) + 'pzx.ini';
  if FileExists(FFileName) then
    FMainText.LoadFromFile(FFileName)
  else if not FCustomFile and FileExists(ExtractFilePath(FFileName) + '..' + PathDelim + 'pzx.ini') then
    // Settings next to an executable that used to live one folder up
    FMainText.LoadFromFile(ExtractFilePath(FFileName) + '..' + PathDelim + 'pzx.ini')
  else if not FCustomFile and FileExists(Old) then
    FMainText.LoadFromFile(Old);    // settings of older versions, kept per user
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
  if ZXUnoBios <> '' then Ini.WriteString('ZXUno', 'BiosSettings', ZXUnoBios);
  WriteList(Ini, 'RecentDisks', RecentDisks);
  WriteList(Ini, 'RecentCards', RecentCards);
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

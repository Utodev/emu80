{ SettingsForm: modal settings dialog editing the global Settings. }
unit SettingsForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Dialogs, ButtonPanel,
  Graphics, Models, Config;

{ Opens the settings window (not modal; brought forward if it is open). Apply
  and OK write the changes into Settings and call OnApplied; Cancel puts back
  what Settings was when it opened (calling OnApplied again if Apply had been
  used) and closes. }
procedure ShowSettings(OnApplied: TNotifyEvent);

var
  { Set when the dialog changed the DivMMC firmware file }
  FirmwareChanged: Boolean;

implementation

type
  TCheckBoxArray4 = array[0..3] of TCheckBox;

  TSettingsDialog = class(TForm)
  private
    FPages, FCommon, FZX: TPageControl;   // the three main tabs; what is inside the Common and ZX Spectrum ones
    FCrtc, FMonitor: TComboBox;
    FCPCWait: TCheckBox;
    FModel: TComboBox;
    FRomDir: TEdit;
    FBrowse: TButton;
    FFastLoad, FAutoPlay, FTapeLoop, FSound, FSaveToTape, FFastDisk, FDriveB: TCheckBox;
    FTurboSound, FMonochrome, FContention, FSnow, FRomEdit, FAY48, FMouse, FDivMMC, FCurrah, FCPCJoystick: TCheckBox;
    FULAPlus, FTimex, FRadastan, FScanlines: TCheckBox;
    FFirmware: TEdit;
    FFloppyNoise, FSaveOnExit: TCheckBox;
    FFirmwareBrowse: TButton;
    FUnoFirmware, FUnoRoms, FUnoCustom: TEdit;   // ZX-Uno BIOS, ROMs and custom ROM files
    FNextDir, FNextCard: TEdit;                  // ZX Spectrum Next distribution and SD card
    FNextFirmware: TCheckBox;
    FJoystick, FDeinterlace: TComboBox;
    FIssue2, FIssue3: TRadioButton;
    FVolume, FSpeed: TTrackBar;
    FScale: TComboBox;
    FUI: TComboBox;
    FRomModel: TComboBox;
    FRomLabels: array[0..3] of TLabel;
    FRomEdits: array[0..3] of TEdit;
    FRomBrowse: array[0..3] of TButton;
    FRomFiles: array[TSpectrumModel, 0..3] of string;   // being edited
    FShownRomModel: Integer;
    FOwn: array[0..3] of Boolean;   // DivMMC, Timex, Radastan, ULAplus as set (not forced)
    FBottom: TPanel;
    FOK, FApply, FCancel: TButton;
    FBackup: string;               // Settings when the window opened
    FApplied: Boolean;             // Apply was used
    FOnApplied: TNotifyEvent;
    procedure DoOK(Sender: TObject);
    procedure DoApply(Sender: TObject);
    procedure DoCancel(Sender: TObject);
    procedure DoClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure Apply;
    function AddPage(PC: TPageControl; const ACaption: string): TTabSheet;
    function AddTabs(Page: TTabSheet; Logo: Integer): TPageControl;
    { A band at the top of a main tab, with a machine's logo and name (1 ZX Spectrum, 2 Amstrad CPC;
      0: only the gap) }
    function AddBand(Page: TTabSheet; Logo: Integer): TPaintBox;
    procedure PaintLogo(Sender: TObject);
    function AddLabel(Page: TWinControl; const ACaption: string; ATop: Integer): TLabel;
    function AddCheck(Page: TWinControl; const ACaption: string; ATop: Integer): TCheckBox;
    { A short explanation in grey under an option }
    function AddNote(Page: TWinControl; const AText: string; ATop: Integer): TLabel;
    function AddCombo(Page: TWinControl; ATop, AWidth: Integer): TComboBox;
    { A box with a title around a section of a page }
    function AddGroup(Page: TWinControl; const ACaption: string; ATop, AHeight: Integer): TGroupBox;
    { Radio buttons that are one choice go on a panel of their own }
    function AddRadioPanel(Group: TWinControl; ATop, AHeight: Integer): TPanel;
    function AddRadio(Panel: TWinControl; const ACaption: string; ALeft, ATop: Integer): TRadioButton;
    procedure DoBrowse(Sender: TObject);
    procedure DoFirmwareBrowse(Sender: TObject);
    procedure DoUnoBrowse(Sender: TObject);
    function AddFileRow(Page: TWinControl; const ACaption, AHint: string; ATop, ATag: Integer): TEdit;
    procedure DoRomBrowse(Sender: TObject);
    procedure DoRomModel(Sender: TObject);
    procedure StoreRomEdits;
    function ForcedBoxes: TCheckBoxArray4;
    procedure DoModelChange(Sender: TObject);
    procedure ShowRomEdits;
  public
    constructor Create(AOwner: TComponent); override;
    procedure LoadFrom(S: TSettings);
    procedure SaveTo(S: TSettings);
  end;

var
  Window: TSettingsDialog = nil;

procedure ShowSettings(OnApplied: TNotifyEvent);
begin
  if Window <> nil then
  begin
    Window.BringToFront;
    Exit;
  end;
  Window := TSettingsDialog.Create(Application);
  Window.FOnApplied := OnApplied;
  Window.LoadFrom(Settings);
  Window.FBackup := Settings.Snapshot;
  Window.Show;
end;

procedure TSettingsDialog.Apply;
begin
  SaveTo(Settings);
  FApplied := True;
  if Assigned(FOnApplied) then FOnApplied(Self);
end;

procedure TSettingsDialog.DoApply(Sender: TObject);
begin
  Apply;
end;

procedure TSettingsDialog.DoOK(Sender: TObject);
begin
  Apply;
  FApplied := False;
  Close;
end;

{ Cancel: what was set when the window opened comes back }
procedure TSettingsDialog.DoCancel(Sender: TObject);
begin
  Close;
end;

procedure TSettingsDialog.DoClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  CloseAction := caFree;
  Window := nil;
  if FApplied then
  begin
    Settings.Restore(FBackup);
    if Assigned(FOnApplied) then FOnApplied(Self);
  end;
end;

constructor TSettingsDialog.Create(AOwner: TComponent);
var
  M: TSpectrumModel;
  S, Y, I: Integer;
  J: TJoystickKeys;
  D: TDeinterlace;
  Page: TTabSheet;
  Group: TGroupBox;
  Panel: TPanel;
begin
  inherited CreateNew(AOwner, 0);
  Caption := 'Settings';
  BorderStyle := bsDialog;
  Position := poMainFormCenter;
  ClientWidth := 500;
  ClientHeight := 710;

  // OK applies and closes, Apply applies, Cancel undoes what was applied and
  // closes (the window isn't modal)
  PopupMode := pmExplicit;
  PopupParent := Application.MainForm;
  OnClose := @DoClose;
  FBottom := TPanel.Create(Self);
  FBottom.Parent := Self;
  FBottom.Align := alBottom;
  FBottom.Height := 44;
  FBottom.BevelOuter := bvNone;
  FApply := TButton.Create(Self);
  FApply.Parent := FBottom;
  FApply.Caption := 'Apply';
  FApply.SetBounds(ClientWidth - 6 - 84, 8, 84, 28);
  FApply.OnClick := @DoApply;
  FCancel := TButton.Create(Self);
  FCancel.Parent := FBottom;
  FCancel.Caption := 'Cancel';
  FCancel.Cancel := True;
  FCancel.SetBounds(ClientWidth - 6 - 84 * 2 - 8, 8, 84, 28);
  FCancel.OnClick := @DoCancel;
  FOK := TButton.Create(Self);
  FOK.Parent := FBottom;
  FOK.Caption := 'OK';
  FOK.Default := True;
  FOK.SetBounds(ClientWidth - 6 - 84 * 3 - 16, 8, 84, 28);
  FOK.OnClick := @DoOK;

  FPages := TPageControl.Create(Self);
  FPages.Parent := Self;
  FPages.Align := alClient;
  FPages.BorderSpacing.Around := 6;

  // Three main tabs: what is common to every machine, what is the ZX
  // Spectrum's (and its relatives') and what is the Amstrad CPC's. The
  // Common and ZX Spectrum ones have tabs of their own inside.
  FCommon := AddTabs(AddPage(FPages, 'Common'), 0);
  FZX := AddTabs(AddPage(FPages, 'ZX Spectrum'), 1);

  // Common: General
  Page := AddPage(FCommon, 'General');
  Y := 14;
  AddLabel(Page, 'Machine:', Y + 4);
  FModel := AddCombo(Page, Y, 270);
  for M := Low(TSpectrumModel) to High(TSpectrumModel) do FModel.Items.Add(ModelInfo[M].Name);
  FModel.OnChange := @DoModelChange;
  Inc(Y, 36);
  AddLabel(Page, 'Window size:', Y + 4);
  FScale := AddCombo(Page, Y, 100);
  for S := 1 to 4 do FScale.Items.Add(Format('%dx', [S]));
  Inc(Y, 36);
  AddLabel(Page, 'Interface:', Y + 4);
  FUI := AddCombo(Page, Y, 270);
  FUI.Items.Add('Classic (menus and toolbar)');
  FUI.Items.Add('Modern (dark)');
  Inc(Y, 40);
  FMonochrome := AddCheck(Page, 'Black and white display', Y);
  Inc(Y, 28);
  FScanlines := AddCheck(Page, 'Scanlines (window size 2x or more)', Y);
  Inc(Y, 28);
  FSound := AddCheck(Page, 'Mute sound', Y);
  Inc(Y, 34);
  AddLabel(Page, 'Volume:', Y + 4);
  FVolume := TTrackBar.Create(Self);
  FVolume.Parent := Page;
  FVolume.SetBounds(180, Y, 270, 30);
  FVolume.Min := 0;
  FVolume.Max := 100;
  FVolume.Frequency := 10;

  // CPU speed: 1x to 32x in powers of two, with the value under each mark
  Inc(Y, 48);
  AddLabel(Page, 'CPU speed:', Y + 4);
  FSpeed := TTrackBar.Create(Self);
  FSpeed.Parent := Page;
  FSpeed.SetBounds(180, Y, 270, 30);
  FSpeed.Min := 0;
  FSpeed.Max := 5;
  FSpeed.Frequency := 1;
  for S := 0 to 5 do
    with AddLabel(Page, Format('%dx', [1 shl S]), Y + 32) do
    begin
      AutoSize := False;
      Alignment := taCenter;
      // The marks run between the thumb's half-widths at both ends
      SetBounds(180 + 11 + S * (270 - 22) div 5 - 20, Y + 32, 40, 18);
    end;
  AddNote(Page, 'The Z80 runs this many times faster; interrupts stay at 50 per second.',
    Y + 56);
  Inc(Y, 96);
  FRomEdit := AddCheck(Page, 'Allow writing to ROM', Y);
  FRomEdit.Hint := 'From the debugger and with POKE';
  Inc(Y, 32);
  FSaveOnExit := AddCheck(Page, 'Save the settings when pzx closes', Y);
  AddNote(Page, 'Off: changes made while running (window size, model, recent files...) ' +
    'are forgotten; OK in this dialog still saves.', Y + 22);

  // Common: tapes and disks
  Page := AddPage(FCommon, 'Storage');
  Group := AddGroup(Page, 'Tape', 8, 116);
  Y := 8;
  FFastLoad := AddCheck(Group, 'Fast tape loading', Y);
  Inc(Y, 28);
  FAutoPlay := AddCheck(Group, 'Start the tape automatically when the machine loads', Y);
  Inc(Y, 28);
  FTapeLoop := AddCheck(Group, 'Continuous tape playback (from the start again at the end)', Y);
  Group := AddGroup(Page, 'Floppy', 136, 116);
  Y := 8;
  FFastDisk := AddCheck(Group, 'Fast floppy disk access (no real drive timing)', Y);
  Inc(Y, 28);
  FDriveB := AddCheck(Group, 'Drive B: connected (+3, CPC 664 and 6128)', Y);
  Inc(Y, 28);
  FFloppyNoise := AddCheck(Group, 'Emulate floppy drive noise', Y);
  FFloppyNoise.Hint := 'Motor, head steps and reading, when the drive works at real speed';

  // Common: the machines' ROMs (an empty file is the standard one)
  Page := AddPage(FCommon, 'ROMs');
  Group := AddGroup(Page, 'ROMs', 8, 248);
  Y := 8;
  AddLabel(Group, 'Standard ROM folder:', Y + 4);
  FRomDir := TEdit.Create(Self);
  FRomDir.Parent := Group;
  FRomDir.SetBounds(170, Y, 190, 24);
  FBrowse := TButton.Create(Self);
  FBrowse.Parent := Group;
  FBrowse.Caption := 'Browse...';
  FBrowse.SetBounds(366, Y, 80, 25);
  FBrowse.OnClick := @DoBrowse;
  Inc(Y, 40);
  AddLabel(Group, 'ROM files for:', Y + 4);
  FRomModel := AddCombo(Group, Y, 276);
  FRomModel.Left := 170;
  for M := Low(TSpectrumModel) to High(TSpectrumModel) do FRomModel.Items.Add(ModelInfo[M].Name);
  FRomModel.OnChange := @DoRomModel;
  Inc(Y, 36);
  for I := 0 to 3 do
  begin
    FRomLabels[I] := AddLabel(Group, '', Y + 4);
    FRomEdits[I] := TEdit.Create(Self);
    FRomEdits[I].Parent := Group;
    FRomEdits[I].SetBounds(170, Y, 190, 24);
    FRomEdits[I].Hint := 'Labels for a ROM are read from a .sym file next to it';
    FRomEdits[I].ShowHint := True;
    FRomBrowse[I] := TButton.Create(Self);
    FRomBrowse[I].Parent := Group;
    FRomBrowse[I].Caption := 'Browse...';
    FRomBrowse[I].Tag := I;
    FRomBrowse[I].SetBounds(366, Y, 80, 25);
    FRomBrowse[I].OnClick := @DoRomBrowse;
    Inc(Y, 32);
  end;
  AddNote(Page, 'On the CPC models ROM 0 is the 32K firmware (operating system and BASIC) and ROM 1 the ' +
    'AMSDOS disc ROM.', 264);

  // ZX Spectrum: hardware connected to the machine
  Page := AddPage(FZX, 'Hardware');
  Y := 14;
  FTurboSound := AddCheck(Page, 'TurboSound', Y);
  FTurboSound.Hint := 'Two AY sound chips on the 128K and later models';
  Inc(Y, 28);
  FAY48 := AddCheck(Page, 'AY sound chip on the 16K and 48K', Y);
  FAY48.Hint := 'An AY interface at the 128K''s ports (FFFD and BFFD)';
  Inc(Y, 28);
  FMouse := AddCheck(Page, 'Kempston mouse', Y);
  FMouse.Hint := 'Moved with the PC mouse over the picture';
  Inc(Y, 28);
  FDivMMC := AddCheck(Page, 'DivMMC interface', Y);
  FDivMMC.Hint := 'SD card with the esxDOS firmware (see the SD menu); changing it switches ' +
    'the machine off and on';
  Inc(Y, 28);
  FCurrah := AddCheck(Page, 'Currah ' + #$C2#$B5 + 'Speech', Y);
  FCurrah.Hint := 'Speech synthesizer for the 48K BASIC (LET s$="..."); changing it switches ' +
    'the machine off and on';
  Inc(Y, 36);
  FSaveToTape := AddCheck(Page, 'SAVE writes the blocks to the tape', Y);
  FSaveToTape.Hint := 'The ROM''s SAVE adds its blocks to the inserted tape at once';

  // ZX Spectrum: the machine
  Page := AddPage(FZX, 'Machine');
  Group := AddGroup(Page, 'Graphics', 8, 142);
  Y := 8;
  FULAPlus := AddCheck(Group, 'ULAplus (64-colour palette)', Y);
  Inc(Y, 28);
  FTimex := AddCheck(Group, 'Timex screen modes (second screen, hi-colour, 512x192 hi-res)', Y);
  Inc(Y, 28);
  FRadastan := AddCheck(Group, 'Radastan mode', Y);
  Inc(Y, 30);
  AddLabel(Group, 'Deinterlace:', Y + 4);
  FDeinterlace := AddCombo(Group, Y, 270);
  FDeinterlace.Left := 170;
  for D := Low(TDeinterlace) to High(TDeinterlace) do FDeinterlace.Items.Add(DEINTERLACE_NAMES[D]);
  FDeinterlace.Hint := 'The frames taken as the fields of an interlaced picture: needed by ' +
    'demos that alternate two pictures (Mescaline, Paralactika, Ultraviolet)';
  FDeinterlace.ShowHint := True;
  Group := AddGroup(Page, 'Controls', 158, 82);
  Y := 8;
  AddLabel(Group, 'Keyboard (16K/48K):', Y);
  Panel := AddRadioPanel(Group, Y - 2, 26);
  FIssue2 := AddRadio(Panel, 'Issue 2', 0, 0);
  FIssue3 := AddRadio(Panel, 'Issue 3', 100, 0);
  Inc(Y, 30);
  AddLabel(Group, 'Joystick (cursors + Ctrl):', Y + 4);
  FJoystick := AddCombo(Group, Y, 270);
  FJoystick.Left := 170;
  for J := Low(TJoystickKeys) to High(TJoystickKeys) do FJoystick.Items.Add(JOYSTICK_NAMES[J]);
  Group := AddGroup(Page, 'Core features', 248, 88);
  Y := 8;
  FContention := AddCheck(Group, 'Contended memory and I/O (real timing)', Y);
  Inc(Y, 28);
  FSnow := AddCheck(Group, 'ULA snow (16K, 48K, 128K and +2)', Y);

  // ZX Spectrum: firmware of the DivMMC, the ZX-Uno and the Next
  Page := AddPage(FZX, 'Firmware');
  Group := AddGroup(Page, 'DivMMC', 6, 72);
  Y := 8;
  AddLabel(Group, 'Firmware:', Y + 4);
  FFirmware := TEdit.Create(Self);
  FFirmware.Parent := Group;
  FFirmware.SetBounds(170, Y, 190, 24);
  FFirmware.TextHint := 'esxdos/ESXMMC.BIN (bundled)';
  FFirmware.Hint := 'An 8K EEPROM image';
  FFirmware.ShowHint := True;
  FFirmwareBrowse := TButton.Create(Self);
  FFirmwareBrowse.Parent := Group;
  FFirmwareBrowse.Caption := 'Browse...';
  FFirmwareBrowse.SetBounds(366, Y, 80, 25);
  FFirmwareBrowse.OnClick := @DoFirmwareBrowse;
  Group := AddGroup(Page, 'ZX-Uno', 90, 142);
  Y := 8;
  FUnoFirmware := AddFileRow(Group, 'BIOS:', 'zxuno/FIRMWARE.ZX1', Y, 1);
  Inc(Y, 32);
  FUnoRoms := AddFileRow(Group, 'ROMs:', 'zxuno/ROMS.ZX1', Y, 2);
  Inc(Y, 32);
  FUnoCustom := AddFileRow(Group, 'Custom ROM:', 'none', Y, 3);
  FUnoCustom.Hint := 'A 16K ROM that runs as a 48K instead of the BIOS''s choice; changes ' +
    'switch the ZX-Uno off and on';
  FUnoCustom.ShowHint := True;
  Group := AddGroup(Page, 'ZX Spectrum Next', 240, 138);
  Y := 8;
  FNextDir := AddFileRow(Group, 'Distribution:', 'the specnext folder', Y, 4);
  FNextDir.Hint := 'The folder with the ZX Spectrum Next''s system distribution (from ' +
    'specnext.com), with machines/next in it';
  FNextDir.ShowHint := True;
  Inc(Y, 32);
  FNextCard := AddFileRow(Group, 'SD card:', 'zxnext.img next to pzx.ini', Y, 5);
  FNextCard.Hint := 'Its SD card image, made from the distribution if it doesn''t exist';
  FNextCard.ShowHint := True;
  Inc(Y, 32);
  FNextFirmware := AddCheck(Group, 'Start through its firmware (TBBLUE.FW: boot screen and menu)', Y);
  FNextFirmware.Hint := 'Off: NextZXOS starts directly, without the firmware''s screen';

  // Amstrad CPC
  Page := AddPage(FPages, 'Amstrad CPC');
  AddBand(Page, 2);
  Group := AddGroup(Page, 'Video', 60, 150);
  Y := 8;
  AddLabel(Group, 'CRTC chip:', Y + 4);
  FCrtc := AddCombo(Group, Y, 270);
  FCrtc.Left := 170;
  FCrtc.Items.Add('The one the model came with (464: type 0; 664, 6128: type 1)');
  FCrtc.Items.Add('Type 0: HD6845S / UM6845');
  FCrtc.Items.Add('Type 1: UM6845R');
  FCrtc.Items.Add('Type 2: MC6845');
  FCrtc.Items.Add('Type 3: AMS40489 (CPC+ ASIC)');
  FCrtc.Items.Add('Type 4: AMS40226 (pre-ASIC)');
  FCrtc.Hint := 'The chips differ in which registers they read back, the VSYNC width, the ' +
    'HSYNC of width 0, the display skew and when the sync and display compares happen';
  FCrtc.ShowHint := True;
  AddNote(Group, 'Programs detect the chip (and some demos need a particular one); the ' +
    'registers written are kept when it is changed.', Y + 34);
  Inc(Y, 82);
  AddLabel(Group, 'Monitor:', Y + 4);
  FMonitor := AddCombo(Group, Y, 270);
  FMonitor.Left := 170;
  FMonitor.Items.Add('Colour');
  FMonitor.Items.Add('Green phosphor (GT65)');
  FMonitor.Items.Add('Orange phosphor');
  FMonitor.Hint := 'A monochrome monitor shows the colours as shades of its phosphor; ' +
    '"Black and white display" only applies to the colour monitor';
  FMonitor.ShowHint := True;
  Group := AddGroup(Page, 'Timing', 218, 64);
  Y := 8;
  FCPCWait := AddCheck(Group, 'Gate Array wait states (every access on the 1 MHz grid)', Y);
  FCPCWait.Hint := 'Real timing: instructions take a whole number of microseconds; off makes ' +
    'every access take its nominal time';
  Group := AddGroup(Page, 'Controls', 298, 64);
  Y := 8;
  FCPCJoystick := AddCheck(Group, 'Cursor keys and right Ctrl as joystick 1', Y);
  FCPCJoystick.Hint := 'On the CPC the cursor keys are always the cursor keys; with this on they ' +
    'also move joystick 1, and the right Ctrl is its fire button';
  FShownRomModel := -1;
end;

function TSettingsDialog.AddPage(PC: TPageControl; const ACaption: string): TTabSheet;
begin
  Result := PC.AddTabSheet;
  Result.Caption := ACaption;
end;

{ A tab with tabs inside }
function TSettingsDialog.AddTabs(Page: TTabSheet; Logo: Integer): TPageControl;
begin
  AddBand(Page, Logo);
  Result := TPageControl.Create(Self);
  Result.Parent := Page;
  Result.Align := alClient;
  Result.BorderSpacing.Around := 2;
end;

function TSettingsDialog.AddBand(Page: TTabSheet; Logo: Integer): TPaintBox;
begin
  Result := TPaintBox.Create(Self);
  Result.Parent := Page;
  Result.Align := alTop;
  Result.Height := 50;
  Result.Tag := Logo;
  Result.OnPaint := @PaintLogo;
end;

{ The machine's logo, drawn in code: the Spectrum's rainbow over a black
  keyboard, the CPC's coloured keys on a grey one }
procedure TSettingsDialog.PaintLogo(Sender: TObject);
var
  Box: TPaintBox;
  C: TCanvas;
  X, Y, I: Integer;
  Dark: Boolean;
  Back, Edge, Ink, Body: TColor;
  Title: string;
const
  SPEC: array[0..3] of TColor = ($0000E0, $00E0E0, $00D000, $E0D000);   // red, yellow, green, cyan (BGR)
  CPCK: array[0..3] of TColor = ($2828F0, $F0A828, $28D0FF, $38C038);
begin
  Box := Sender as TPaintBox;
  C := Box.Canvas;
  Back := ColorToRGB(Box.Parent.Color);
  Dark := (Red(Back) * 30 + Green(Back) * 59 + Blue(Back) * 11) div 100 < 128;
  C.Brush.Color := Back;
  C.FillRect(0, 0, Box.Width, Box.Height);
  if Box.Tag = 0 then Exit;
  // On a dark ground: a light outline and light lettering, the keyboards lighter
  if Dark then
  begin
    Edge := $E0E0E0;
    Ink := clWhite;
  end
  else
  begin
    Edge := $000000;
    Ink := clWindowText;
  end;
  X := 22;
  Y := 8;
  if Box.Tag = 1 then
  begin
    if Dark then Body := $585858 else Body := $202020;
    C.Brush.Color := Body;
    C.Pen.Color := Edge;
    C.Pen.Width := 2;
    C.RoundRect(X, Y + 6, X + 56, Y + 32, 6, 6);
    C.Pen.Width := 1;
    C.Brush.Color := $A0A0A0;
    for I := 0 to 3 do C.FillRect(X + 6 + I * 11, Y + 24, X + 14 + I * 11, Y + 28);
    for I := 0 to 3 do
    begin
      C.Brush.Color := SPEC[I];
      C.Pen.Color := SPEC[I];
      C.Polygon([Point(X + 34 + I * 4, Y + 20), Point(X + 38 + I * 4, Y + 20),
        Point(X + 50 + I * 4, Y + 6), Point(X + 46 + I * 4, Y + 6)]);
    end;
    Title := 'ZX Spectrum';
  end
  else
  begin
    if Dark then Body := $A8A8A8 else Body := $8C8C8C;
    C.Brush.Color := Body;
    C.Pen.Color := Edge;
    C.Pen.Width := 2;
    C.RoundRect(X, Y + 6, X + 56, Y + 32, 4, 4);
    C.Pen.Width := 1;
    C.Brush.Color := $303030;
    for I := 0 to 5 do C.FillRect(X + 4 + I * 8, Y + 22, X + 10 + I * 8, Y + 28);
    for I := 0 to 3 do
    begin
      C.Brush.Color := CPCK[I];
      C.Pen.Color := $202020;
      C.Rectangle(X + 6 + I * 11, Y + 10, X + 14 + I * 11, Y + 18);
    end;
    Title := 'Amstrad CPC';
  end;
  C.Brush.Style := bsClear;
  C.Font.Style := [fsBold];
  C.Font.Size := 13;
  C.Font.Color := Ink;
  C.TextOut(X + 72, Y + 12, Title);
end;

function TSettingsDialog.AddLabel(Page: TWinControl; const ACaption: string; ATop: Integer): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := Page;
  Result.Caption := ACaption;
  Result.Left := 16;
  Result.Top := ATop;
end;

function TSettingsDialog.AddCheck(Page: TWinControl; const ACaption: string; ATop: Integer): TCheckBox;
begin
  Result := TCheckBox.Create(Self);
  Result.Parent := Page;
  Result.Caption := ACaption;
  Result.Left := 16;
  Result.Top := ATop;
  Result.ShowHint := True;
end;

function TSettingsDialog.AddNote(Page: TWinControl; const AText: string; ATop: Integer): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := Page;
  Result.Caption := AText;
  Result.Font.Color := clGrayText;
  Result.AutoSize := False;
  Result.WordWrap := True;
  Result.SetBounds(36, ATop, 430, 34);
end;

function TSettingsDialog.AddGroup(Page: TWinControl; const ACaption: string;
  ATop, AHeight: Integer): TGroupBox;
begin
  Result := TGroupBox.Create(Self);
  Result.Parent := Page;
  Result.Caption := ACaption;
  Result.SetBounds(8, ATop, 468, AHeight);
end;

function TSettingsDialog.AddRadioPanel(Group: TWinControl; ATop, AHeight: Integer): TPanel;
begin
  Result := TPanel.Create(Self);
  Result.Parent := Group;
  Result.BevelOuter := bvNone;
  Result.SetBounds(170, ATop, 290, AHeight);
end;

function TSettingsDialog.AddRadio(Panel: TWinControl; const ACaption: string;
  ALeft, ATop: Integer): TRadioButton;
begin
  Result := TRadioButton.Create(Self);
  Result.Parent := Panel;
  Result.Caption := ACaption;
  Result.Left := ALeft;
  Result.Top := ATop;
end;

function TSettingsDialog.AddCombo(Page: TWinControl; ATop, AWidth: Integer): TComboBox;
begin
  Result := TComboBox.Create(Self);
  Result.Parent := Page;
  Result.Style := csDropDownList;
  Result.SetBounds(180, ATop, AWidth, 24);
end;

procedure TSettingsDialog.DoBrowse(Sender: TObject);
var
  Dlg: TSelectDirectoryDialog;
begin
  Dlg := TSelectDirectoryDialog.Create(Self);
  try
    Dlg.InitialDir := FRomDir.Text;
    if Dlg.Execute then FRomDir.Text := Dlg.FileName;
  finally
    Dlg.Free;
  end;
end;

procedure TSettingsDialog.DoRomBrowse(Sender: TObject);
var
  Dlg: TOpenDialog;
  I: Integer;
begin
  I := (Sender as TComponent).Tag;
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Filter := 'ROM images (*.rom;*.bin)|*.rom;*.bin|All files|*.*';
    if FRomEdits[I].Text <> '' then
      Dlg.InitialDir := ExtractFilePath(FRomEdits[I].Text)
    else
      Dlg.InitialDir := FRomDir.Text;
    Dlg.Options := Dlg.Options + [ofFileMustExist];
    if Dlg.Execute then FRomEdits[I].Text := Dlg.FileName;
  finally
    Dlg.Free;
  end;
end;

{ A label, a file name box (empty: AHint, shown in grey) and its Browse button }
function TSettingsDialog.AddFileRow(Page: TWinControl; const ACaption, AHint: string;
  ATop, ATag: Integer): TEdit;
var
  B: TButton;
begin
  AddLabel(Page, ACaption, ATop + 4);
  Result := TEdit.Create(Self);
  Result.Parent := Page;
  Result.SetBounds(170, ATop, 190, 24);
  Result.TextHint := AHint;
  B := TButton.Create(Self);
  B.Parent := Page;
  B.Caption := 'Browse...';
  B.SetBounds(366, ATop, 80, 25);
  B.Tag := ATag;
  B.OnClick := @DoUnoBrowse;
end;

procedure TSettingsDialog.DoUnoBrowse(Sender: TObject);
var
  Dlg: TOpenDialog;
  DirDlg: TSelectDirectoryDialog;
begin
  // The Next's distribution folder and SD card
  if (Sender as TComponent).Tag = 4 then
  begin
    DirDlg := TSelectDirectoryDialog.Create(Self);
    try
      DirDlg.Title := 'ZX Spectrum Next distribution folder';
      if DirDlg.Execute then FNextDir.Text := DirDlg.FileName;
    finally
      DirDlg.Free;
    end;
    Exit;
  end;
  if (Sender as TComponent).Tag = 5 then
  begin
    Dlg := TOpenDialog.Create(Self);
    try
      Dlg.Title := 'ZX Spectrum Next SD card image (made if it doesn''t exist)';
      Dlg.Filter := 'SD card images (*.img)|*.img|All files|*.*';
      if Dlg.Execute then FNextCard.Text := Dlg.FileName;
    finally
      Dlg.Free;
    end;
    Exit;
  end;
  Dlg := TOpenDialog.Create(Self);
  try
    if (Sender as TComponent).Tag = 3 then
      Dlg.Filter := 'ROM images (*.rom;*.bin)|*.rom;*.bin|All files|*.*'
    else
      Dlg.Filter := 'ZX-Uno files (*.zx*)|*.zx*;*.ZX*|All files|*.*';
    Dlg.Options := Dlg.Options + [ofFileMustExist];
    if Dlg.Execute then
      case (Sender as TComponent).Tag of
        1: FUnoFirmware.Text := Dlg.FileName;
        2: FUnoRoms.Text := Dlg.FileName;
        3: FUnoCustom.Text := Dlg.FileName;
      end;
  finally
    Dlg.Free;
  end;
end;

procedure TSettingsDialog.DoFirmwareBrowse(Sender: TObject);
var
  Dlg: TOpenDialog;
begin
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Filter := 'Firmware images (*.bin;*.rom)|*.bin;*.rom|All files|*.*';
    Dlg.Options := Dlg.Options + [ofFileMustExist];
    if Dlg.Execute then FFirmware.Text := Dlg.FileName;
  finally
    Dlg.Free;
  end;
end;

procedure TSettingsDialog.StoreRomEdits;
var
  I: Integer;
begin
  if FShownRomModel < 0 then Exit;
  for I := 0 to 3 do
    FRomFiles[TSpectrumModel(FShownRomModel), I] := Trim(FRomEdits[I].Text);
end;

procedure TSettingsDialog.ShowRomEdits;
var
  M: TSpectrumModel;
  I: Integer;
begin
  M := TSpectrumModel(FRomModel.ItemIndex);
  FShownRomModel := Ord(M);
  for I := 0 to 3 do
  begin
    FRomLabels[I].Visible := I < ModelInfo[M].RomCount;
    FRomEdits[I].Visible := FRomLabels[I].Visible;
    FRomBrowse[I].Visible := FRomLabels[I].Visible;
    FRomLabels[I].Caption := Format('ROM %d (%s):', [I, ModelInfo[M].RomFiles[I]]);
    FRomEdits[I].Text := FRomFiles[M, I];
    FRomEdits[I].TextHint := ModelInfo[M].RomFiles[I];
  end;
end;

procedure TSettingsDialog.DoRomModel(Sender: TObject);
begin
  StoreRomEdits;
  ShowRomEdits;
end;

function TSettingsDialog.ForcedBoxes: TCheckBoxArray4;
begin
  Result[0] := FDivMMC;
  Result[1] := FTimex;
  Result[2] := FRadastan;
  Result[3] := FULAPlus;
end;

{ The ZX-Uno always has its DivMMC, Timex modes, Radastan and ULAplus: shown
  on and greyed out, keeping what is set for the other models }
procedure TSettingsDialog.DoModelChange(Sender: TObject);
var
  Boxes: TCheckBoxArray4;
  I: Integer;
  ZXUno: Boolean;
begin
  Boxes := ForcedBoxes;
  ZXUno := FModel.ItemIndex = Ord(smZXUno);
  for I := 0 to 3 do
  begin
    if ZXUno and Boxes[I].Enabled then
    begin
      FOwn[I] := Boxes[I].Checked;
      Boxes[I].Checked := True;
      Boxes[I].Enabled := False;
      Boxes[I].Hint := 'The ZX-Uno always has it (its own registers can switch it off)';
      Boxes[I].ShowHint := True;
    end
    else if not ZXUno and not Boxes[I].Enabled then
    begin
      Boxes[I].Enabled := True;
      Boxes[I].Checked := FOwn[I];
      Boxes[I].ShowHint := False;
    end;
  end;
end;

procedure TSettingsDialog.LoadFrom(S: TSettings);
var
  M: TSpectrumModel;
  I: Integer;
begin
  FModel.ItemIndex := Ord(S.Model);
  FRomDir.Text := S.RomDir;
  FFastLoad.Checked := S.FastLoad;
  FAutoPlay.Checked := S.AutoPlayTape;
  FTapeLoop.Checked := S.TapeLoop;
  FMouse.Checked := S.KempstonMouse;
  FDivMMC.Checked := S.DivMMC;
  FCurrah.Checked := S.Currah;
  FCPCJoystick.Checked := S.CPCJoystick;
  FCPCWait.Checked := S.CPCWaitStates;
  FCrtc.ItemIndex := S.CPCCrtc + 1;
  FMonitor.ItemIndex := S.CPCMonitor;
  FFirmware.Text := S.DivMMCFirmware;
  FUnoFirmware.Text := S.ZXUnoFirmware;
  FNextDir.Text := S.NextDir;
  FNextCard.Text := S.NextCard;
  FNextFirmware.Checked := S.NextFirmware;
  FUnoRoms.Text := S.ZXUnoRoms;
  FUnoCustom.Text := S.ZXUnoCustomRom;
  FAY48.Checked := S.AY48;
  FSaveToTape.Checked := S.SaveToTape;
  FFastDisk.Checked := S.FastDisk;
  FDriveB.Checked := S.DriveB;
  FFloppyNoise.Checked := S.FloppyNoise;
  FSaveOnExit.Checked := S.SaveOnExit;
  FJoystick.ItemIndex := Ord(S.Joystick);
  FDeinterlace.ItemIndex := Ord(S.Deinterlace);
  FIssue2.Checked := S.Issue2;
  FIssue3.Checked := not S.Issue2;
  FSound.Checked := not S.Sound;
  FTurboSound.Checked := S.TurboSound;
  FMonochrome.Checked := S.Monochrome;
  FContention.Checked := S.Contention;
  FSnow.Checked := S.UlaSnow;
  FRomEdit.Checked := S.AllowRomEdit;
  FULAPlus.Checked := S.ULAPlus;
  FTimex.Checked := S.Timex;
  FRadastan.Checked := S.Radastan;
  DoModelChange(nil);
  FScanlines.Checked := S.Scanlines;
  FVolume.Position := S.Volume;
  FSpeed.Position := 0;
  while (1 shl FSpeed.Position) < S.CpuSpeed do FSpeed.Position := FSpeed.Position + 1;
  FScale.ItemIndex := S.Scale - 1;
  FUI.ItemIndex := Ord(S.ModernUI);
  for M := Low(TSpectrumModel) to High(TSpectrumModel) do
    for I := 0 to 3 do FRomFiles[M, I] := S.RomFiles[M, I];
  FRomModel.ItemIndex := Ord(S.Model);
  ShowRomEdits;
end;

procedure TSettingsDialog.SaveTo(S: TSettings);
var
  M: TSpectrumModel;
  I: Integer;
begin
  StoreRomEdits;
  S.Model := TSpectrumModel(FModel.ItemIndex);
  S.RomDir := FRomDir.Text;
  S.FastLoad := FFastLoad.Checked;
  S.AutoPlayTape := FAutoPlay.Checked;
  S.TapeLoop := FTapeLoop.Checked;
  S.KempstonMouse := FMouse.Checked;
  if FDivMMC.Enabled then S.DivMMC := FDivMMC.Checked else S.DivMMC := FOwn[0];
  S.ZXUnoFirmware := Trim(FUnoFirmware.Text);
  S.NextDir := Trim(FNextDir.Text);
  S.NextCard := Trim(FNextCard.Text);
  S.NextFirmware := FNextFirmware.Checked;
  S.ZXUnoRoms := Trim(FUnoRoms.Text);
  S.ZXUnoCustomRom := Trim(FUnoCustom.Text);
  if Trim(FFirmware.Text) <> S.DivMMCFirmware then
  begin
    S.DivMMCFirmware := Trim(FFirmware.Text);
    FirmwareChanged := True;
  end;
  S.AY48 := FAY48.Checked;
  S.SaveToTape := FSaveToTape.Checked;
  S.FastDisk := FFastDisk.Checked;
  S.DriveB := FDriveB.Checked;
  S.FloppyNoise := FFloppyNoise.Checked;
  S.SaveOnExit := FSaveOnExit.Checked;
  S.Joystick := TJoystickKeys(FJoystick.ItemIndex);
  S.Deinterlace := TDeinterlace(FDeinterlace.ItemIndex);
  S.Issue2 := FIssue2.Checked;
  S.Sound := not FSound.Checked;
  S.TurboSound := FTurboSound.Checked;
  S.Currah := FCurrah.Checked;
  S.CPCJoystick := FCPCJoystick.Checked;
  S.CPCWaitStates := FCPCWait.Checked;
  S.CPCCrtc := FCrtc.ItemIndex - 1;
  S.CPCMonitor := FMonitor.ItemIndex;
  S.Monochrome := FMonochrome.Checked;
  S.Contention := FContention.Checked;
  S.UlaSnow := FSnow.Checked;
  S.AllowRomEdit := FRomEdit.Checked;
  if FULAPlus.Enabled then S.ULAPlus := FULAPlus.Checked else S.ULAPlus := FOwn[3];
  if FTimex.Enabled then S.Timex := FTimex.Checked else S.Timex := FOwn[1];
  if FRadastan.Enabled then S.Radastan := FRadastan.Checked else S.Radastan := FOwn[2];
  S.Scanlines := FScanlines.Checked;
  S.Volume := FVolume.Position;
  S.CpuSpeed := 1 shl FSpeed.Position;
  S.Scale := FScale.ItemIndex + 1;
  S.ModernUI := FUI.ItemIndex = 1;
  for M := Low(TSpectrumModel) to High(TSpectrumModel) do
    for I := 0 to 3 do S.RomFiles[M, I] := FRomFiles[M, I];
end;

end.

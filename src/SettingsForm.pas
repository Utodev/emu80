{ SettingsForm: modal settings dialog editing the global Settings. }
unit SettingsForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Dialogs, ButtonPanel,
  Graphics, Models, Config;

{ Returns True if the user accepted the changes. }
function ShowSettings: Boolean;

var
  { Set when the dialog changed the DivMMC firmware file }
  FirmwareChanged: Boolean;

implementation

type
  TCheckBoxArray4 = array[0..3] of TCheckBox;

  TSettingsDialog = class(TForm)
  private
    FPages: TPageControl;
    FModel: TComboBox;
    FRomDir: TEdit;
    FBrowse: TButton;
    FFastLoad, FAutoPlay, FSound, FSaveToTape, FFastDisk, FDriveB: TCheckBox;
    FTurboSound, FMonochrome, FContention, FSnow, FRomEdit, FAY48, FMouse, FDivMMC: TCheckBox;
    FULAPlus, FTimex, FRadastan, FScanlines: TCheckBox;
    FFirmware: TEdit;
    FFloppyNoise, FSaveOnExit: TCheckBox;
    FFirmwareBrowse: TButton;
    FUnoFirmware, FUnoRoms, FUnoCustom: TEdit;   // ZX-Uno BIOS, ROMs and custom ROM files
    FJoystick, FIssue, FShiftKeys: TComboBox;
    FVolume, FSpeed: TTrackBar;
    FScale: TComboBox;
    FRomModel: TComboBox;
    FRomLabels: array[0..3] of TLabel;
    FRomEdits: array[0..3] of TEdit;
    FRomBrowse: array[0..3] of TButton;
    FRomNote: TLabel;
    FRomFiles: array[TSpectrumModel, 0..3] of string;   // being edited
    FShownRomModel: Integer;
    FOwn: array[0..3] of Boolean;   // DivMMC, Timex, Radastan, ULAplus as set (not forced)
    FButtons: TButtonPanel;
    function AddPage(const ACaption: string): TTabSheet;
    function AddLabel(Page: TWinControl; const ACaption: string; ATop: Integer): TLabel;
    function AddCheck(Page: TWinControl; const ACaption: string; ATop: Integer): TCheckBox;
    { A short explanation in grey under an option }
    function AddNote(Page: TWinControl; const AText: string; ATop: Integer): TLabel;
    function AddCombo(Page: TWinControl; ATop, AWidth: Integer): TComboBox;
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

function ShowSettings: Boolean;
var
  Dlg: TSettingsDialog;
begin
  Dlg := TSettingsDialog.Create(nil);
  try
    Dlg.LoadFrom(Settings);
    Result := Dlg.ShowModal = mrOK;
    if Result then Dlg.SaveTo(Settings);
  finally
    Dlg.Free;
  end;
end;

constructor TSettingsDialog.Create(AOwner: TComponent);
var
  M: TSpectrumModel;
  S, Y, I: Integer;
  J: TJoystickKeys;
  Page: TTabSheet;
  Bevel: TBevel;
begin
  inherited CreateNew(AOwner, 0);
  Caption := 'Settings';
  BorderStyle := bsDialog;
  Position := poMainFormCenter;
  ClientWidth := 500;
  ClientHeight := 570;

  FButtons := TButtonPanel.Create(Self);
  FButtons.Parent := Self;
  FButtons.ShowButtons := [pbOK, pbCancel];

  FPages := TPageControl.Create(Self);
  FPages.Parent := Self;
  FPages.Align := alClient;
  FPages.BorderSpacing.Around := 6;

  // General
  Page := AddPage('General');
  Y := 14;
  AddLabel(Page, 'Machine:', Y + 4);
  FModel := AddCombo(Page, Y, 270);
  for M := Low(TSpectrumModel) to High(TSpectrumModel) do FModel.Items.Add(ModelInfo[M].Name);
  FModel.OnChange := @DoModelChange;
  Inc(Y, 36);
  AddLabel(Page, 'Window size:', Y + 4);
  FScale := AddCombo(Page, Y, 100);
  for S := 1 to 4 do FScale.Items.Add(Format('%dx', [S]));
  Inc(Y, 40);
  FMonochrome := AddCheck(Page, 'Black and white display', Y);
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
  FSaveOnExit := AddCheck(Page, 'Save the settings when pzx closes', Y);
  AddNote(Page, 'Off: changes made while running (window size, model, recent files...) ' +
    'are forgotten; OK in this dialog still saves.', Y + 22);

  // Machine and input
  Page := AddPage('Machine');
  Y := 14;
  FContention := AddCheck(Page, 'Contended memory and I/O (real timing)', Y);
  Inc(Y, 28);
  FSnow := AddCheck(Page, 'ULA snow (16K, 48K, 128K and +2)', Y);
  Inc(Y, 28);
  FRomEdit := AddCheck(Page, 'Allow changing the ROM from the debugger and with POKE', Y);
  Inc(Y, 28);
  FULAPlus := AddCheck(Page, 'ULAplus (64-colour palette)', Y);
  Inc(Y, 28);
  FTimex := AddCheck(Page, 'Timex screen modes (second screen, hi-colour, 512x192 hi-res)', Y);
  Inc(Y, 28);
  FRadastan := AddCheck(Page, 'Radastan mode (ZX-Uno: 128x96, 16 colours)', Y);
  Inc(Y, 28);
  FScanlines := AddCheck(Page, 'Scanlines (window size 2x or more)', Y);
  Inc(Y, 40);
  AddLabel(Page, 'Joystick (cursors + Ctrl):', Y + 4);
  FJoystick := AddCombo(Page, Y, 270);
  for J := Low(TJoystickKeys) to High(TJoystickKeys) do FJoystick.Items.Add(JOYSTICK_NAMES[J]);
  Inc(Y, 36);
  AddLabel(Page, 'Keyboard (16K/48K):', Y + 4);
  FIssue := AddCombo(Page, Y, 270);
  FIssue.Items.Add('Issue 2');
  FIssue.Items.Add('Issue 3');
  Inc(Y, 36);
  AddLabel(Page, 'Shift keys:', Y + 4);
  FShiftKeys := AddCombo(Page, Y, 270);
  FShiftKeys.Items.Add('Shift = CAPS SHIFT, Ctrl = SYMBOL');
  FShiftKeys.Items.Add('Left = CAPS SHIFT, right = SYMBOL');
  FShiftKeys.Hint := 'Second option: left Shift and left Ctrl are CAPS SHIFT, right Shift and ' +
    'right Ctrl SYMBOL SHIFT';
  FShiftKeys.ShowHint := True;

  // Hardware connected to the machine
  Page := AddPage('Hardware');
  Y := 14;
  FTurboSound := AddCheck(Page, 'TurboSound', Y);
  AddNote(Page, 'Two AY sound chips on the 128K and later models.', Y + 22);
  Inc(Y, 50);
  FAY48 := AddCheck(Page, 'AY sound chip on the 16K and 48K', Y);
  AddNote(Page, 'An AY interface at the 128K''s ports (FFFD and BFFD).', Y + 22);
  Inc(Y, 50);
  FMouse := AddCheck(Page, 'Kempston mouse', Y);
  AddNote(Page, 'Moved with the PC mouse over the picture.', Y + 22);
  Inc(Y, 50);
  FDivMMC := AddCheck(Page, 'DivMMC interface', Y);
  AddNote(Page, 'SD card with the esxDOS firmware (see the SD menu). Changing it ' +
    'switches the machine off and on.', Y + 22);

  // Tape and disk
  Page := AddPage('Tape && disk');
  Y := 14;
  FFastLoad := AddCheck(Page, 'Fast tape loading', Y);
  Inc(Y, 28);
  FAutoPlay := AddCheck(Page, 'Start the tape automatically when the ROM loads (real-time mode)', Y);
  Inc(Y, 28);
  FSaveToTape := AddCheck(Page, 'SAVE writes the blocks to the tape', Y);
  Inc(Y, 28);
  FFastDisk := AddCheck(Page, 'Fast floppy disk access (no real drive timing)', Y);
  Inc(Y, 28);
  FDriveB := AddCheck(Page, 'Drive B: connected (+3)', Y);
  Inc(Y, 28);
  FFloppyNoise := AddCheck(Page, 'Emulate floppy drive noise', Y);
  AddNote(Page, 'Motor, head steps and reading, when the drive works at real speed.', Y + 22);

  // ROMs
  Page := AddPage('ROMs');
  Y := 14;
  AddLabel(Page, 'Standard ROM folder:', Y + 4);
  FRomDir := TEdit.Create(Self);
  FRomDir.Parent := Page;
  FRomDir.SetBounds(180, Y, 190, 24);
  FBrowse := TButton.Create(Self);
  FBrowse.Parent := Page;
  FBrowse.Caption := 'Browse...';
  FBrowse.SetBounds(376, Y, 80, 25);
  FBrowse.OnClick := @DoBrowse;
  Inc(Y, 44);
  AddLabel(Page, 'ROM files for:', Y + 4);
  FRomModel := AddCombo(Page, Y, 276);
  for M := Low(TSpectrumModel) to High(TSpectrumModel) do FRomModel.Items.Add(ModelInfo[M].Name);
  FRomModel.OnChange := @DoRomModel;
  Inc(Y, 36);
  for I := 0 to 3 do
  begin
    FRomLabels[I] := AddLabel(Page, '', Y + 4);
    FRomEdits[I] := TEdit.Create(Self);
    FRomEdits[I].Parent := Page;
    FRomEdits[I].SetBounds(180, Y, 190, 24);
    FRomBrowse[I] := TButton.Create(Self);
    FRomBrowse[I].Parent := Page;
    FRomBrowse[I].Caption := 'Browse...';
    FRomBrowse[I].Tag := I;
    FRomBrowse[I].SetBounds(376, Y, 80, 25);
    FRomBrowse[I].OnClick := @DoRomBrowse;
    Inc(Y, 32);
  end;
  // Placed under the ROMs the model has (see ShowRomEdits)
  FRomNote := AddLabel(Page, 'Leave a file empty to use the standard ROM from the folder above. ' +
    'Labels for a ROM are read from a .sym file next to it.', Y + 6);
  FRomNote.AutoSize := False;
  FRomNote.WordWrap := True;
  FRomNote.SetBounds(16, Y + 6, 440, 40);
  FRomNote.Font.Color := clGrayText;
  // The DivMMC's firmware, apart from the machine's ROMs
  Inc(Y, 56);
  Bevel := TBevel.Create(Self);
  Bevel.Parent := Page;
  Bevel.Shape := bsTopLine;
  Bevel.SetBounds(16, Y, 440, 4);
  Inc(Y, 10);
  AddLabel(Page, 'DivMMC firmware:', Y + 4);
  FFirmware := TEdit.Create(Self);
  FFirmware.Parent := Page;
  FFirmware.SetBounds(180, Y, 190, 24);
  FFirmware.TextHint := 'esxdos/ESXMMC.BIN (bundled)';
  FFirmwareBrowse := TButton.Create(Self);
  FFirmwareBrowse.Parent := Page;
  FFirmwareBrowse.Caption := 'Browse...';
  FFirmwareBrowse.SetBounds(376, Y, 80, 25);
  FFirmwareBrowse.OnClick := @DoFirmwareBrowse;
  AddNote(Page, 'Empty: esxDOS 0.8.9, which comes with pzx. An 8K EEPROM image.', Y + 30);
  Inc(Y, 66);
  FUnoFirmware := AddFileRow(Page, 'ZX-Uno BIOS:', 'zxuno/FIRMWARE.ZX1', Y, 1);
  Inc(Y, 32);
  FUnoRoms := AddFileRow(Page, 'ZX-Uno ROMs:', 'zxuno/ROMS.ZX1', Y, 2);
  Inc(Y, 32);
  FUnoCustom := AddFileRow(Page, 'ZX-Uno custom ROM:', 'none', Y, 3);
  AddNote(Page, 'Empty: the ones in the zxuno folder. A custom ROM (16K) runs as a 48K ' +
    'instead of the BIOS''s choice. Changes switch the ZX-Uno off and on.', Y + 30);
  FShownRomModel := -1;
end;

function TSettingsDialog.AddPage(const ACaption: string): TTabSheet;
begin
  Result := FPages.AddTabSheet;
  Result.Caption := ACaption;
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
  Result.SetBounds(180, ATop, 190, 24);
  Result.TextHint := AHint;
  B := TButton.Create(Self);
  B.Parent := Page;
  B.Caption := 'Browse...';
  B.SetBounds(376, ATop, 80, 25);
  B.Tag := ATag;
  B.OnClick := @DoUnoBrowse;
end;

procedure TSettingsDialog.DoUnoBrowse(Sender: TObject);
var
  Dlg: TOpenDialog;
begin
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
  FRomNote.Top := FRomEdits[0].Top + ModelInfo[M].RomCount * 32 + 4;
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
  FMouse.Checked := S.KempstonMouse;
  FDivMMC.Checked := S.DivMMC;
  FFirmware.Text := S.DivMMCFirmware;
  FUnoFirmware.Text := S.ZXUnoFirmware;
  FUnoRoms.Text := S.ZXUnoRoms;
  FUnoCustom.Text := S.ZXUnoCustomRom;
  FAY48.Checked := S.AY48;
  FSaveToTape.Checked := S.SaveToTape;
  FFastDisk.Checked := S.FastDisk;
  FDriveB.Checked := S.DriveB;
  FFloppyNoise.Checked := S.FloppyNoise;
  FSaveOnExit.Checked := S.SaveOnExit;
  FJoystick.ItemIndex := Ord(S.Joystick);
  if S.Issue2 then FIssue.ItemIndex := 0 else FIssue.ItemIndex := 1;
  FShiftKeys.ItemIndex := Ord(S.ShiftSides);
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
  S.KempstonMouse := FMouse.Checked;
  if FDivMMC.Enabled then S.DivMMC := FDivMMC.Checked else S.DivMMC := FOwn[0];
  S.ZXUnoFirmware := Trim(FUnoFirmware.Text);
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
  S.Issue2 := FIssue.ItemIndex = 0;
  S.ShiftSides := FShiftKeys.ItemIndex = 1;
  S.Sound := not FSound.Checked;
  S.TurboSound := FTurboSound.Checked;
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
  for M := Low(TSpectrumModel) to High(TSpectrumModel) do
    for I := 0 to 3 do S.RomFiles[M, I] := FRomFiles[M, I];
end;

end.

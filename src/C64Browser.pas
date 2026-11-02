{ C64Browser: what is on the Commodore 64's disks and tape. The disk's directory (drive 8 or 9: name, type, blocks and
  size), with the program exported to a .prg file of the PC, or loaded in the machine; the tape's files (the KERNAL's
  standard format: name, type, addresses and size; a tape with a fast loader of its own has none the KERNAL can see),
  with the tape put at the start of the one chosen. }
unit C64Browser;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, ComCtrls, StdCtrls, ExtCtrls, Dialogs, Emulator;

type
  TC64BrowserKind = (cbDisk, cbTape);

  { A file of a disk's directory }
  TC64DirEntry = record
    Name: string;
    FileType: Byte;            // 0 DEL, 1 SEQ, 2 PRG, 3 USR, 4 REL
    Closed: Boolean;
    Blocks: Integer;
    Track, Sector: Integer;
  end;
  TC64DirEntries = array of TC64DirEntry;

  { A file of a tape, as the KERNAL saved it }
  TC64TapeEntry = record
    Name: string;
    Kind: Byte;                // 1 relocatable program, 3 program, 4 data (SEQ)
    Start, Finish: Word;
    Pulse: Integer;            // where its header starts on the tape
  end;
  TC64TapeEntries = array of TC64TapeEntry;

  TC64BrowserWindow = class(TForm)
  private
    FEmu: TEmulator;
    FKind: TC64BrowserKind;
    FDrive: Integer;
    FToolBar: TPanel;
    FDriveCombo: TComboBox;
    FList: TListView;
    FStatus: TStatusBar;
    FDirEntries: TC64DirEntries;
    FTapeEntries: TC64TapeEntries;
    procedure DriveChange(Sender: TObject);
    procedure DoRefresh(Sender: TObject);
    procedure DoExport(Sender: TObject);
    procedure DoLoad(Sender: TObject);
    procedure ListDblClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FillDisk;
    procedure FillTape;
  public
    constructor CreateFor(AOwner: TComponent; AEmu: TEmulator; AKind: TC64BrowserKind);
    procedure Refresh;
  end;

var
  C64BrowserWindow: TC64BrowserWindow;

{ Open the browser on the disks or on the tape }
procedure ShowC64Browser(Emu: TEmulator; Kind: TC64BrowserKind);

implementation

uses
  C64, C64Disk, Config, Lang;

const
  TYPE_NAMES: array[0..4] of string = ('DEL', 'SEQ', 'PRG', 'USR', 'REL');

{ A PETSCII name as text: the letters, digits and signs as they are, the rest as a dot }
function PetsciiName(const S: string): string;
var
  I: Integer;
  C: Byte;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    C := Ord(S[I]);
    if C = $A0 then Break;
    if (C >= $20) and (C <= $5F) then Result := Result + Chr(C)
    else if (C >= $C1) and (C <= $DA) then Result := Result + Chr(C - $80)
    else if (C >= $61) and (C <= $7A) then Result := Result + Chr(C - 32)
    else Result := Result + '.';
  end;
end;

{ The directory of a .d64: track 18, from sector 1 }
function ReadDirectory(Disk: TD64Image): TC64DirEntries;
var
  Buf: array[0..255] of Byte;
  T, S, I, J, N, Guard: Integer;
  Name: string;
begin
  Result := nil;
  N := 0;
  T := 18;
  S := 1;
  Guard := 0;
  while (T <> 0) and (Guard < 40) do
  begin
    Inc(Guard);
    if not Disk.ReadSector(T, S, Buf) then Break;
    for I := 0 to 7 do
    begin
      if Buf[I * 32 + 2] = 0 then Continue;
      SetLength(Result, N + 1);
      Name := '';
      for J := 0 to 15 do Name := Name + Chr(Buf[I * 32 + 5 + J]);
      Result[N].Name := PetsciiName(Name);
      Result[N].FileType := Buf[I * 32 + 2] and 7;
      Result[N].Closed := (Buf[I * 32 + 2] and $80) <> 0;
      Result[N].Track := Buf[I * 32 + 3];
      Result[N].Sector := Buf[I * 32 + 4];
      Result[N].Blocks := Buf[I * 32 + 30] or (Buf[I * 32 + 31] shl 8);
      Inc(N);
    end;
    T := Buf[0];
    S := Buf[1];
  end;
end;

{ The bytes of a file: its chain of sectors }
function ReadFileData(Disk: TD64Image; const E: TC64DirEntry): TBytes;
var
  Buf: array[0..255] of Byte;
  T, S, Guard, N, Used: Integer;
begin
  Result := nil;
  T := E.Track;
  S := E.Sector;
  N := 0;
  Guard := 0;
  while (T <> 0) and (Guard < 800) do
  begin
    Inc(Guard);
    if not Disk.ReadSector(T, S, Buf) then Break;
    if Buf[0] = 0 then Used := Buf[1] - 1 else Used := 254;
    if Used < 0 then Used := 0;
    if Used > 254 then Used := 254;
    SetLength(Result, N + Used);
    if Used > 0 then Move(Buf[2], Result[N], Used);
    Inc(N, Used);
    T := Buf[0];
    S := Buf[1];
  end;
end;

{ The KERNAL's tape format: pulses short (about 352 cycles), medium (512) and long (672). A byte is a marker (long,
  medium) and nine bits (data from the low one, then an odd parity bit), each two pulses: short-medium is a 0 and
  medium-short a 1. Blocks start with a leader of short pulses and a countdown ($89 down to $81 the first time, $09 to
  $01 the repeat). A header block holds the type, the start and end addresses and the name. }
function ScanTape(Tape: TC64Tape): TC64TapeEntries;
var
  Count, Pos, N, LeaderStart, Shorts, I, K: Integer;
  Block: TBytes;

  function Cls(P: Integer): Integer;
  var
    C: LongWord;
  begin
    if P >= Count then Exit(-1);
    C := Tape.PulseCycles(P);
    if C < 432 then Result := 0
    else if C < 592 then Result := 1
    else if C < 900 then Result := 2
    else Result := 3;
  end;

  { A byte at Pos (a marker and nine bits); -1 at the end of a block or if it is not a byte }
  function ReadByte(out Value: Integer): Integer;
  var
    B, V, Par, A, Bb: Integer;
  begin
    Result := -1;
    if (Cls(Pos) <> 2) then Exit;
    if Cls(Pos + 1) = 0 then begin Inc(Pos, 2); Result := -2; Exit; end;      // the end of data marker
    if Cls(Pos + 1) <> 1 then Exit;
    Inc(Pos, 2);
    V := 0;
    Par := 0;
    for B := 0 to 8 do
    begin
      A := Cls(Pos);
      Bb := Cls(Pos + 1);
      if (A = 0) and (Bb = 1) then K := 0
      else if (A = 1) and (Bb = 0) then K := 1
      else Exit(-1);
      Inc(Pos, 2);
      if B < 8 then V := V or (K shl B);
      Par := Par xor K;
    end;
    if Par <> 1 then Exit(-1);
    Value := V;
    Result := 0;
  end;

var
  V, R, Len: Integer;
  Got: Boolean;
begin
  Result := nil;
  Count := Tape.Count;
  Pos := 0;
  N := 0;
  while Pos < Count do
  begin
    // A leader: a run of short pulses
    LeaderStart := Pos;
    Shorts := 0;
    while (Pos < Count) and (Cls(Pos) = 0) do begin Inc(Pos); Inc(Shorts); end;
    if Shorts < 200 then
    begin
      if Pos = LeaderStart then Inc(Pos);
      Continue;
    end;
    // The block: its bytes up to the end marker
    Block := nil;
    Len := 0;
    while True do
    begin
      R := ReadByte(V);
      if R <> 0 then Break;
      SetLength(Block, Len + 1);
      Block[Len] := V;
      Inc(Len);
    end;
    // The first copy: the countdown ($89..$81), the payload and a checksum
    Got := (Len >= 9 + 1 + 5 + 16) and (Block[0] = $89) and (Block[8] = $81);
    if Got and (Block[9] in [1, 3, 4]) then
    begin
      SetLength(Result, N + 1);
      Result[N].Kind := Block[9];
      Result[N].Start := Block[10] or (Block[11] shl 8);
      Result[N].Finish := Block[12] or (Block[13] shl 8);
      Result[N].Name := '';
      for I := 14 to 14 + 15 do Result[N].Name := Result[N].Name + Chr(Block[I]);
      Result[N].Name := PetsciiName(Result[N].Name);
      Result[N].Pulse := LeaderStart;
      Inc(N);
    end;
  end;
end;

procedure ShowC64Browser(Emu: TEmulator; Kind: TC64BrowserKind);
begin
  if (C64BrowserWindow <> nil) and (C64BrowserWindow.FKind <> Kind) then
  begin
    C64BrowserWindow.Free;
    C64BrowserWindow := nil;
  end;
  if C64BrowserWindow = nil then C64BrowserWindow := TC64BrowserWindow.CreateFor(Application, Emu, Kind);
  C64BrowserWindow.Refresh;
  C64BrowserWindow.Show;
  C64BrowserWindow.BringToFront;
end;

constructor TC64BrowserWindow.CreateFor(AOwner: TComponent; AEmu: TEmulator; AKind: TC64BrowserKind);

  procedure AddButton(const ACaption: string; AHandler: TNotifyEvent; ALeft: Integer);
  var
    B: TButton;
  begin
    B := TButton.Create(Self);
    B.Parent := FToolBar;
    B.Caption := ACaption;
    B.Left := ALeft;
    B.Top := 6;
    B.Width := 110;
    B.OnClick := AHandler;
  end;

  procedure AddColumn(const ACaption: string; AWidth: Integer);
  begin
    with FList.Columns.Add do
    begin
      Caption := ACaption;
      Width := AWidth;
    end;
  end;

begin
  inherited CreateNew(AOwner, 0);
  FEmu := AEmu;
  FKind := AKind;
  Width := 640;
  Height := 440;
  Position := poMainFormCenter;
  OnClose := @FormClose;
  KeyPreview := True;
  OnKeyDown := @FormKeyDown;
  FToolBar := TPanel.Create(Self);
  FToolBar.Parent := Self;
  FToolBar.Align := alTop;
  FToolBar.Height := 38;
  FToolBar.BevelOuter := bvNone;
  FStatus := TStatusBar.Create(Self);
  FStatus.Parent := Self;
  FStatus.SimplePanel := True;
  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.ViewStyle := vsReport;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.MultiSelect := False;
  FList.OnDblClick := @ListDblClick;
  if FKind = cbDisk then
  begin
    Caption := _('Disk browser');
    FDriveCombo := TComboBox.Create(Self);
    FDriveCombo.Parent := FToolBar;
    FDriveCombo.Left := 8;
    FDriveCombo.Top := 8;
    FDriveCombo.Width := 80;
    FDriveCombo.Style := csDropDownList;
    FDriveCombo.Items.Add(_('Drive 8'));
    FDriveCombo.Items.Add(_('Drive 9'));
    FDriveCombo.ItemIndex := 0;
    FDriveCombo.OnChange := @DriveChange;
    AddColumn(_('Name'), 200);
    AddColumn(_('Type'), 60);
    AddColumn(_('Blocks'), 70);
    AddColumn(_('Size'), 80);
    AddButton(_('Load'), @DoLoad, 100);
    AddButton(_('Export...'), @DoExport, 216);
    AddButton(_('Refresh'), @DoRefresh, 332);
  end
  else
  begin
    Caption := _('Tape browser');
    AddColumn(_('Name'), 200);
    AddColumn(_('Type'), 90);
    AddColumn(_('Start'), 70);
    AddColumn(_('End'), 70);
    AddColumn(_('Size'), 70);
    AddButton(_('Go to'), @DoLoad, 8);
    AddButton(_('Refresh'), @DoRefresh, 124);
  end;
end;

procedure TC64BrowserWindow.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  CloseAction := caFree;
  C64BrowserWindow := nil;
end;

procedure TC64BrowserWindow.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = 27 then Close;
end;

procedure TC64BrowserWindow.DriveChange(Sender: TObject);
begin
  FDrive := FDriveCombo.ItemIndex;
  Refresh;
end;

procedure TC64BrowserWindow.DoRefresh(Sender: TObject);
begin
  Refresh;
end;

procedure TC64BrowserWindow.Refresh;
begin
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    if FKind = cbDisk then FillDisk else FillTape;
  finally
    FList.Items.EndUpdate;
  end;
end;

procedure TC64BrowserWindow.FillDisk;
var
  Disk: TD64Image;
  I, Total: Integer;
  Item: TListItem;
  Mark: string;
begin
  FDirEntries := nil;
  FEmu.Lock;
  try
    Disk := FEmu.Spec.C64Hw.DiskAt(FDrive);
    if Disk <> nil then FDirEntries := ReadDirectory(Disk);
    if Disk = nil then
    begin
      FStatus.SimpleText := _('No disk in this drive');
      Exit;
    end;
    FStatus.SimpleText := Format(_('%s - %d files'), ['"' + PetsciiName(Disk.DiskName) + '"', Length(FDirEntries)]);
  finally
    FEmu.Unlock;
  end;
  Total := 0;
  for I := 0 to High(FDirEntries) do
  begin
    Item := FList.Items.Add;
    Item.Caption := FDirEntries[I].Name;
    if FDirEntries[I].Closed then Mark := '' else Mark := '*';
    if FDirEntries[I].FileType <= 4 then Item.SubItems.Add(Mark + TYPE_NAMES[FDirEntries[I].FileType])
    else Item.SubItems.Add(Mark + '?');
    Item.SubItems.Add(IntToStr(FDirEntries[I].Blocks));
    Item.SubItems.Add(IntToStr(FDirEntries[I].Blocks * 254));
    Inc(Total, FDirEntries[I].Blocks);
  end;
end;

procedure TC64BrowserWindow.FillTape;
var
  I: Integer;
  Item: TListItem;
begin
  FTapeEntries := nil;
  FEmu.Lock;
  try
    if not FEmu.Spec.C64Hw.Tape.Present then
    begin
      FStatus.SimpleText := _('No tape');
      Exit;
    end;
    FTapeEntries := ScanTape(FEmu.Spec.C64Hw.Tape);
  finally
    FEmu.Unlock;
  end;
  if Length(FTapeEntries) = 0 then
    FStatus.SimpleText := _('No files in the KERNAL''s format (a tape with a loader of its own can''t be listed)')
  else
    FStatus.SimpleText := Format(_('%d files'), [Length(FTapeEntries)]);
  for I := 0 to High(FTapeEntries) do
  begin
    Item := FList.Items.Add;
    Item.Caption := FTapeEntries[I].Name;
    case FTapeEntries[I].Kind of
      1: Item.SubItems.Add(_('Program (relocatable)'));
      3: Item.SubItems.Add(_('Program'));
    else
      Item.SubItems.Add(_('Data'));
    end;
    Item.SubItems.Add('$' + IntToHex(FTapeEntries[I].Start, 4));
    Item.SubItems.Add('$' + IntToHex(FTapeEntries[I].Finish, 4));
    Item.SubItems.Add(IntToStr(Integer(FTapeEntries[I].Finish) - FTapeEntries[I].Start));
  end;
end;

{ The selected file's program: its load address and bytes }
procedure TC64BrowserWindow.DoExport(Sender: TObject);
var
  Dlg: TSaveDialog;
  Data: TBytes;
  Disk: TD64Image;
  F: TFileStream;
  I: Integer;
begin
  if (FKind <> cbDisk) or (FList.Selected = nil) then Exit;
  I := FList.Selected.Index;
  FEmu.Lock;
  try
    Disk := FEmu.Spec.C64Hw.DiskAt(FDrive);
    if Disk = nil then Exit;
    Data := ReadFileData(Disk, FDirEntries[I]);
  finally
    FEmu.Unlock;
  end;
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Title := _('Export a file');
    Dlg.FileName := FDirEntries[I].Name + '.prg';
    Dlg.Filter := _F('Commodore 64 programs (*.prg)|*.prg|All files|*.*');
    Dlg.InitialDir := Settings.LastDir;
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    if Dlg.Execute then
    begin
      F := TFileStream.Create(Dlg.FileName, fmCreate);
      try
        if Length(Data) > 0 then F.WriteBuffer(Data[0], Length(Data));
      finally
        F.Free;
      end;
      FStatus.SimpleText := Format(_('%d bytes saved'), [Length(Data)]);
    end;
  finally
    Dlg.Free;
  end;
end;

{ Disk: LOAD the program (it is typed at the BASIC prompt); tape: put the tape at the file }
procedure TC64BrowserWindow.DoLoad(Sender: TObject);
var
  I: Integer;
begin
  if FList.Selected = nil then Exit;
  I := FList.Selected.Index;
  FEmu.Lock;
  try
    if FKind = cbDisk then
    begin
      if FEmu.Spec.C64Hw.DiskAt(FDrive) = nil then Exit;
      FEmu.Spec.C64Hw.TypeText('LOAD"' + FDirEntries[I].Name + '",' + IntToStr(8 + FDrive) + #13);
    end
    else
    begin
      FEmu.Spec.C64Hw.Tape.SeekTo(FTapeEntries[I].Pulse);
      FStatus.SimpleText := _('The tape is at that file: LOAD it, or press Play');
    end;
  finally
    FEmu.Unlock;
  end;
end;

procedure TC64BrowserWindow.ListDblClick(Sender: TObject);
begin
  DoLoad(Sender);
end;

end.

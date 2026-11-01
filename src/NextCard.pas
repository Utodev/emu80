{ NextCard: the ZX Spectrum Next's distribution (the specnext folder) and
  the SD card made from it: an image with one FAT16 partition and every file
  of the distribution, with its long names (NextZXOS looks files up by
  them). }
unit NextCard;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, FatFS, Zipper;

const
  NEXT_CARD_MB = 512;
  NEXT_DOWNLOAD_URL = 'https://www.specnext.com/latestdistro/';

type
  { The result of installing a distribution from a zip }
  TDistroInstall = (
    diOk,         // installed and checked
    diInvalid,    // the zip is not a ZX Spectrum Next distribution
    diError);     // it couldn't be read or written (nothing of it is left)

  TInstallProgress = procedure(Percent: Integer) of object;

{ The distribution is there: the NextZXOS ROMs in machines/next }
function NextDistroReady(const Dir: string): Boolean;
{ Unpack a distribution's zip into Dir. It is unpacked into a work folder
  inside Dir, checked, and only then moved into place, so a bad or broken
  zip leaves no partial installation. A distribution inside one folder of
  the zip is taken from there, and an entry that would be written outside
  Dir (a path with .., an absolute one) makes the whole zip refused. Msg says
  why when the result isn't diOk. }
function InstallNextDistroZip(const ZipFile, Dir: string; out Msg: string;
  OnProgress: TInstallProgress = nil): TDistroInstall;
{ Delete everything inside Dir (not Dir itself) }
procedure ClearNextDistroDir(const Dir: string);
{ What identifies a distribution: its version line in README.md and the size
  and date of its ROMs and core update, so a new one is noticed }
function NextDistroId(const Dir: string): string;
{ The version shown in README.md ("System/Next 24.06"), '' if not found }
function NextDistroVersion(const Dir: string): string;
{ A new card image with the whole distribution; raises on errors }
procedure MakeNextCard(const Dir, ImageFile: string; SizeMB: Integer = NEXT_CARD_MB);
{ Mend a card that older versions of emu80 left damaged: NextZXOS and the
  firmware rewrote files that ended empty (emu80 didn't answer the card's
  CMD13). Each empty file that isn't empty in the distribution is copied
  from it again, and an empty machines/next/config.ini (with which the
  firmware shows its test card at every start) gets the default one. The
  files mended, as card paths. }
function RepairNextCard(V: TFatVolume; const Dir: string): TStringList;

implementation

uses
  Lang;


procedure WriteDefaultConfig(V: TFatVolume); forward;

type
  { Where what isn't unpacked goes: nowhere }
  TSinkStream = class(TStream)
  public
    function Write(const Buffer; Count: Longint): Longint; override;
    function Read(var Buffer; Count: Longint): Longint; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
  end;

  { Unpacks a zip entry by entry into a folder }
  TDistroUnpacker = class
  private
    FRoot: string;           // where it unpacks (with the trailing separator)
    FStrip: string;          // the zip's own folder to leave out ('' if none)
    FOnProgress: TInstallProgress;
    FLastPct: Integer;
    procedure CreateStream(Sender: TObject; var AStream: TStream; AItem: TFullZipFileEntry);
    procedure DoneStream(Sender: TObject; var AStream: TStream; AItem: TFullZipFileEntry);
    procedure Progress(Sender: TObject; const Pct: Double);
  end;

{ An entry's path as the zip gives it, made safe: '/' separated, relative and
  without '.' or '..' parts. False: it would leave the folder. }
function SafeEntryName(const Name: string; out Clean: string): Boolean;
var
  S: string;
  Parts: TStringList;
  I: Integer;
begin
  Result := False;
  Clean := '';
  S := StringReplace(Name, '\', '/', [rfReplaceAll]);
  if (S = '') or (Pos(#0, S) > 0) then Exit;
  // Absolute, or on another drive
  if (S[1] = '/') or ((Length(S) > 1) and (S[2] = ':')) then Exit;
  Parts := TStringList.Create;
  try
    Parts.Delimiter := '/';
    Parts.StrictDelimiter := True;
    Parts.DelimitedText := S;
    for I := 0 to Parts.Count - 1 do
    begin
      if Parts[I] = '..' then Exit;
      if (Parts[I] <> '') and (Parts[I] <> '.') then
      begin
        if Clean <> '' then Clean := Clean + '/';
        Clean := Clean + Parts[I];
      end;
    end;
  finally
    Parts.Free;
  end;
  Result := True;
end;

function TSinkStream.Write(const Buffer; Count: Longint): Longint;
begin
  Result := Count;
end;

function TSinkStream.Read(var Buffer; Count: Longint): Longint;
begin
  Result := 0;
end;

function TSinkStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
begin
  Result := 0;
end;

procedure TDistroUnpacker.CreateStream(Sender: TObject; var AStream: TStream; AItem: TFullZipFileEntry);
var
  Clean, Dest, Name: string;
begin
  // Always a stream of ours: without one the unzipper would write the entry
  // under its own name, wherever that leads
  AStream := TSinkStream.Create;
  if not SafeEntryName(AItem.ArchiveFileName, Clean) then
    raise Exception.Create(_('Unsafe path in the zip: ') + AItem.ArchiveFileName);
  if (FStrip <> '') and (Copy(Clean + '/', 1, Length(FStrip)) <> FStrip) then Exit;   // outside the distribution
  Clean := Copy(Clean, Length(FStrip) + 1, MaxInt);
  if Clean = '' then Exit;
  Dest := FRoot + StringReplace(Clean, '/', PathDelim, [rfReplaceAll]);
  Name := AItem.ArchiveFileName;
  if AItem.IsDirectory or ((Name <> '') and (Name[Length(Name)] in ['/', '\'])) then
  begin
    if not ForceDirectories(Dest) then raise Exception.Create(_('Could not create ') + Dest);
    Exit;
  end;
  // Links are not made: only files and folders, which stay inside FRoot
  if AItem.IsLink then Exit;
  if not ForceDirectories(ExtractFilePath(Dest)) then
    raise Exception.Create(_('Could not create ') + ExtractFilePath(Dest));
  FreeAndNil(AStream);
  AStream := TFileStream.Create(Dest, fmCreate);
end;

procedure TDistroUnpacker.DoneStream(Sender: TObject; var AStream: TStream; AItem: TFullZipFileEntry);
begin
  FreeAndNil(AStream);
end;

procedure TDistroUnpacker.Progress(Sender: TObject; const Pct: Double);
begin
  if Assigned(FOnProgress) and (Round(Pct) <> FLastPct) then
  begin
    FLastPct := Round(Pct);
    FOnProgress(FLastPct);
  end;
end;

procedure RemoveTree(const Path: string);
var
  Info: TSearchRec;
begin
  if DirectoryExists(Path) and not ((FileGetAttr(Path) and faSymLink) <> 0) then
  begin
    if FindFirst(IncludeTrailingPathDelimiter(Path) + '*', faAnyFile, Info) = 0 then
    begin
      repeat
        if (Info.Name <> '.') and (Info.Name <> '..') then
          RemoveTree(IncludeTrailingPathDelimiter(Path) + Info.Name);
      until FindNext(Info) <> 0;
      FindClose(Info);
    end;
    RemoveDir(Path);
  end
  else
    DeleteFile(Path);
end;

procedure ClearNextDistroDir(const Dir: string);
var
  Info: TSearchRec;
  Names: TStringList;
  I: Integer;
begin
  if not DirectoryExists(Dir) then Exit;
  Names := TStringList.Create;
  try
    if FindFirst(IncludeTrailingPathDelimiter(Dir) + '*', faAnyFile, Info) = 0 then
    begin
      repeat
        if (Info.Name <> '.') and (Info.Name <> '..') then Names.Add(Info.Name);
      until FindNext(Info) <> 0;
      FindClose(Info);
    end;
    for I := 0 to Names.Count - 1 do RemoveTree(IncludeTrailingPathDelimiter(Dir) + Names[I]);
  finally
    Names.Free;
  end;
end;

function InstallNextDistroZip(const ZipFile, Dir: string; out Msg: string;
  OnProgress: TInstallProgress): TDistroInstall;
const
  WORK_DIR = '.emu80-install';
  MARK = 'machines/next/ennextzx.rom';
var
  UnZip: TUnZipper;
  Un: TDistroUnpacker;
  Work, Clean, Strip, Low, Dst: string;
  I: Integer;
  Entries: TStringList;
  Info: TSearchRec;
  Moved: TStringList;
  Zipped: Boolean;
begin
  Result := diError;
  Msg := '';
  Work := IncludeTrailingPathDelimiter(Dir) + WORK_DIR + PathDelim;
  Un := TDistroUnpacker.Create;
  UnZip := TUnZipper.Create;
  Entries := TStringList.Create;
  Moved := TStringList.Create;
  try
    try
      if not FileExists(ZipFile) then
      begin
        Msg := Format(_('The file %s does not exist.'), [ZipFile]);
        Exit;
      end;
      UnZip.FileName := ZipFile;
      // What is in it, before anything is written
      Zipped := True;
      try
        UnZip.Examine;
      except
        on E: EZipError do Zipped := False;
      end;
      if not Zipped then
      begin
        Msg := _('It is not a zip file.');
        Exit(diInvalid);
      end;
      Strip := '';
      Zipped := False;
      for I := 0 to UnZip.Entries.Count - 1 do
      begin
        if not SafeEntryName(UnZip.Entries[I].ArchiveFileName, Clean) then
        begin
          Msg := _('The zip has a path that would write outside the folder: ') + UnZip.Entries[I].ArchiveFileName;
          Exit;
        end;
        // The distribution: where its machines/next/enNextZX.rom is (at the
        // top, or inside the zip's one folder)
        Low := LowerCase(Clean);
        if (Low = MARK) or ((Length(Low) > Length(MARK)) and
           (Copy(Low, Length(Low) - Length(MARK) + 1, MaxInt) = MARK) and
           (Low[Length(Low) - Length(MARK)] = '/')) then
          if (not Zipped) or (Length(Low) - Length(MARK) < Length(Strip)) then
          begin
            Strip := Copy(Clean, 1, Length(Low) - Length(MARK));
            Zipped := True;
          end;
      end;
      if not Zipped then
      begin
        Msg := _('machines/next/enNextZX.rom is not in it.');
        Exit(diInvalid);
      end;
      // Into the work folder: nothing of it counts until it is checked
      RemoveTree(Work);
      if not ForceDirectories(Work) then
      begin
        Msg := _('Could not create ') + Work;
        Exit;
      end;
      Un.FRoot := Work;
      Un.FStrip := Strip;
      Un.FOnProgress := OnProgress;
      Un.FLastPct := -1;
      UnZip.OnCreateStream := @Un.CreateStream;
      UnZip.OnDoneStream := @Un.DoneStream;
      UnZip.OnProgress := @Un.Progress;
      UnZip.UnZipAllFiles;
      if not NextDistroReady(Work) then
      begin
        Msg := _('The ZX Spectrum Next ROMs are not complete in it.');
        RemoveTree(Work);
        Exit(diInvalid);
      end;
      // In place: machines last, so the distribution only shows as there
      // when all of it is
      if FindFirst(Work + '*', faAnyFile, Info) = 0 then
      begin
        repeat
          if (Info.Name <> '.') and (Info.Name <> '..') then Entries.Add(Info.Name);
        until FindNext(Info) <> 0;
        FindClose(Info);
      end;
      I := Entries.IndexOf('machines');
      if I >= 0 then Entries.Move(I, Entries.Count - 1);
      for I := 0 to Entries.Count - 1 do
      begin
        Dst := IncludeTrailingPathDelimiter(Dir) + Entries[I];
        RemoveTree(Dst);
        if not RenameFile(Work + Entries[I], Dst) then
          raise Exception.CreateFmt(_('Could not move %s into %s'), [Entries[I], Dir]);
        Moved.Add(Dst);
      end;
      RemoveTree(Work);
      Result := diOk;
    except
      on E: Exception do
      begin
        Msg := E.Message;
        RemoveTree(Work);
        // Not left half done
        for I := 0 to Moved.Count - 1 do RemoveTree(Moved[I]);
        Result := diError;
      end;
    end;
  finally
    Moved.Free;
    Entries.Free;
    UnZip.Free;
    Un.Free;
  end;
end;

function RepairNextCard(V: TFatVolume; const Dir: string): TStringList;

  procedure Walk(Cluster: LongWord; const Path: string);
  var
    E: TFatEntries;
    I: Integer;
    Name, Src: string;
    Data: TBytes;
    S: TFileStream;
  begin
    E := V.ListDir(Cluster);
    for I := 0 to High(E) do
    begin
      if E[I].LongName <> '' then Name := E[I].LongName else Name := E[I].ShortName;
      if IsDirectory(E[I]) then
      begin
        Walk(E[I].Cluster, Path + Name + '/');
        Continue;
      end;
      if E[I].Size <> 0 then Continue;
      if SameText(Path + Name, '/machines/next/config.ini') then
      begin
        V.Delete(E[I]);
        WriteDefaultConfig(V);
        Result.Add(Path + Name);
        Continue;
      end;
      Src := IncludeTrailingPathDelimiter(Dir) + StringReplace(Copy(Path, 2, MaxInt), '/', PathDelim,
        [rfReplaceAll]) + Name;
      if not FileExists(Src) then Continue;
      S := TFileStream.Create(Src, fmOpenRead or fmShareDenyWrite);
      try
        if S.Size = 0 then Continue;
        SetLength(Data, S.Size);
        S.ReadBuffer(Data[0], S.Size);
      finally
        S.Free;
      end;
      V.Delete(E[I]);
      V.WriteFileLong(Cluster, Name, Data);
      Result.Add(Path + Name);
    end;
  end;

begin
  Result := TStringList.Create;
  try
    Walk(0, '/');
  except
    Result.Free;
    raise;
  end;
end;

const
  { machines/next/config.ini as the firmware writes it once a video mode has
    been chosen on its test card (docs/config/config.txt's defaults), so the
    card boots straight away; timing 0 is VGA 0 }
  DEFAULT_CONFIG: array[0..27] of string = (
    'scandoubler=1', '50_60hz=0', 'timex=1', 'psgmode=0', 'stereomode=1', 'intsnd=1',
    'turbosound=1', 'dac=1', 'divmmc=0', 'divports=1', 'mf=0', 'joystick1=2', 'joystick2=0',
    'ps2=0', 'scanlines=0', 'turbokey=1', 'timing=0', 'default=0', 'dma=0', 'keyb_issue=0',
    'ay48=0', 'uart_i2c=1', 'kmouse=1', 'ulaplus=1', 'hdmisound=1', 'beepmode=0',
    'buttonswap=0', 'mousedpi=1');

function MachinesDir(const Dir: string): string;
begin
  Result := IncludeTrailingPathDelimiter(Dir) + 'machines' + PathDelim + 'next' + PathDelim;
end;

function NextDistroReady(const Dir: string): Boolean;
begin
  Result := (Dir <> '') and FileExists(MachinesDir(Dir) + 'enNextZX.rom') and
    FileExists(MachinesDir(Dir) + 'enNxtmmc.rom');
end;

function NextDistroVersion(const Dir: string): string;
var
  L: TStringList;
  I, P: Integer;
  S: string;
begin
  Result := '';
  if not FileExists(IncludeTrailingPathDelimiter(Dir) + 'README.md') then Exit;
  L := TStringList.Create;
  try
    L.LoadFromFile(IncludeTrailingPathDelimiter(Dir) + 'README.md');
    // |*System/Next*| **24.06** |
    for I := 0 to L.Count - 1 do
      if Pos('System/Next', L[I]) > 0 then
      begin
        S := StringReplace(L[I], '*', '', [rfReplaceAll]);
        S := StringReplace(S, '|', ' ', [rfReplaceAll]);
        P := Pos('System/Next', S);
        Result := Trim(Copy(S, P, MaxInt));
        while Pos('  ', Result) > 0 do Result := StringReplace(Result, '  ', ' ', [rfReplaceAll]);
        Exit;
      end;
  finally
    L.Free;
  end;
end;

function NextDistroId(const Dir: string): string;
const
  FILES: array[0..3] of string = ('enNextZX.rom', 'enNxtmmc.rom', 'enAltZX.rom', 'enNextMf.rom');
var
  I: Integer;
  Info: TSearchRec;
begin
  Result := NextDistroVersion(Dir);
  for I := 0 to High(FILES) do
    if FindFirst(MachinesDir(Dir) + FILES[I], faAnyFile, Info) = 0 then
    begin
      Result := Result + Format('|%s:%d:%d', [FILES[I], Info.Size, Info.Time]);
      FindClose(Info);
    end;
  if FindFirst(IncludeTrailingPathDelimiter(Dir) + 'TBBLUE.TBU', faAnyFile, Info) = 0 then
  begin
    Result := Result + Format('|tbu:%d:%d', [Info.Size, Info.Time]);
    FindClose(Info);
  end;
end;

procedure WriteDefaultConfig(V: TFatVolume);
var
  Text: string;
  Data: TBytes;
  I: Integer;
begin
  Text := '';
  for I := 0 to High(DEFAULT_CONFIG) do Text := Text + DEFAULT_CONFIG[I] + #13#10;
  SetLength(Data, Length(Text));
  Move(Text[1], Data[0], Length(Text));
  V.WriteFileLong(V.FindDir('/machines/next', True), 'config.ini', Data);
end;

procedure MakeNextCard(const Dir, ImageFile: string; SizeMB: Integer);
var
  Temp: string;
  F: TFileStream;
  V: TFatVolume;
begin
  if not NextDistroReady(Dir) then
    raise Exception.CreateFmt(_('There is no ZX Spectrum Next distribution in %s'), [Dir]);
  // Made under another name first: an error leaves the old card as it was
  Temp := ImageFile + '.new';
  F := TFileStream.Create(Temp, fmCreate);
  try
    try
      FormatCard(F, SizeMB, 'ZXNEXT');
      V := TFatVolume.Create(F);
      try
        CopyTree(V, 0, Dir, False, True);
        if not FileExists(MachinesDir(Dir) + 'config.ini') then WriteDefaultConfig(V);
      finally
        V.Free;
      end;
    finally
      F.Free;
    end;
  except
    DeleteFile(Temp);
    raise;
  end;
  if FileExists(ImageFile) and not DeleteFile(ImageFile) then
  begin
    DeleteFile(Temp);
    raise Exception.CreateFmt(_('Could not replace %s'), [ImageFile]);
  end;
  if not RenameFile(Temp, ImageFile) then
    raise Exception.CreateFmt(_('Could not create %s'), [ImageFile]);
end;

end.

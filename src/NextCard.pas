{ NextCard: the ZX Spectrum Next's distribution (the specnext folder) and
  the SD card made from it: an image with one FAT16 partition and every file
  of the distribution, with its long names (NextZXOS looks files up by
  them). }
unit NextCard;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, FatFS;

const
  NEXT_CARD_MB = 512;
  NEXT_DOWNLOAD_URL = 'https://www.specnext.com/latestdistro/';

{ The distribution is there: the NextZXOS ROMs in machines/next }
function NextDistroReady(const Dir: string): Boolean;
{ What identifies a distribution: its version line in README.md and the size
  and date of its ROMs and core update, so a new one is noticed }
function NextDistroId(const Dir: string): string;
{ The version shown in README.md ("System/Next 24.06"), '' if not found }
function NextDistroVersion(const Dir: string): string;
{ A new card image with the whole distribution; raises on errors }
procedure MakeNextCard(const Dir, ImageFile: string; SizeMB: Integer = NEXT_CARD_MB);
{ Mend a card that older versions of pzx left damaged: NextZXOS and the
  firmware rewrote files that ended empty (pzx didn't answer the card's
  CMD13). Each empty file that isn't empty in the distribution is copied
  from it again, and an empty machines/next/config.ini (with which the
  firmware shows its test card at every start) gets the default one. The
  files mended, as card paths. }
function RepairNextCard(V: TFatVolume; const Dir: string): TStringList;

implementation

procedure WriteDefaultConfig(V: TFatVolume); forward;

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
    raise Exception.CreateFmt('There is no ZX Spectrum Next distribution in %s', [Dir]);
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
    raise Exception.CreateFmt('Could not replace %s', [ImageFile]);
  end;
  if not RenameFile(Temp, ImageFile) then
    raise Exception.CreateFmt('Could not create %s', [ImageFile]);
end;

end.

{ FatFS: the FAT file system of an SD card image, for the SD card browser
  and for making new cards. FAT12, FAT16 and FAT32, on a card with a
  partition table (the first FAT partition) or without one. Long file names
  are read (and shown) but new names are 8.3, as ESXDOS uses them.

  Entries are located by their byte offset in the image, so the browser can
  act on what it listed without keeping any state. }
unit FatFS;

{$mode objfpc}{$H+}
{$R-}{$Q-}

interface

uses
  SysUtils, Classes, Math;

type
  EFatError = class(Exception);
  TLongWordArray = array of LongWord;
  TInt64Array = array of Int64;

  TFatEntry = record
    ShortName: string;     // "NAME.EXT"
    LongName: string;      // '' if none
    Attr: Byte;
    Cluster: LongWord;     // first cluster (0 for an empty file)
    Size: LongWord;
    Stamp: TDateTime;      // 0 if not set
    EntryPos: Int64;       // byte offset of the 8.3 entry in the image
    LfnPos: array of Int64;
  end;
  TFatEntries = array of TFatEntry;

  TFatVolume = class
  private
    FStream: TStream;
    FBase: Int64;           // byte offset of the volume (partition start)
    FBytesPerSector, FSecPerCluster, FReserved, FNumFATs, FRootEntries: Integer;
    FFatSectors, FTotalSectors: Int64;
    FRootCluster: LongWord; // FAT32
    FFatType: Integer;      // 12, 16 or 32
    FFatStart, FRootStart, FDataStart: Int64;   // byte offsets
    FClusters: LongWord;    // data clusters (numbered from 2)
    FFat: TBytes;           // the first FAT, in memory
    FLabel: string;
    function ClusterBytes: Integer;
    function ClusterPos(Cluster: LongWord): Int64;
    function GetFat(Cluster: LongWord): LongWord;
    procedure SetFat(Cluster, Value: LongWord);
    function IsEnd(Value: LongWord): Boolean;
    function EndMark: LongWord;
    function Chain(First: LongWord): TLongWordArray;
    function DirSectors(DirCluster: LongWord): TInt64Array;
    function AllocCluster(Previous: LongWord): LongWord;
    procedure FreeChain(First: LongWord);
    procedure ZeroCluster(Cluster: LongWord);
    function FindFreeEntry(DirCluster: LongWord): Int64;
    function FindFreeEntries(DirCluster: LongWord; Count: Integer): TInt64Array;
    procedure WriteLongName(const Positions: TInt64Array; const LongName: string;
      const Raw83: array of Byte);
    function ShortNameIn(DirCluster: LongWord; const LongName: string; Used: TStrings;
      out Raw: array of Byte): Boolean;
    function WriteData(const Data: TBytes): LongWord;
    procedure WriteEntry(Pos: Int64; const Raw83: array of Byte; Attr: Byte; Cluster,
      Size: LongWord);
  public
    constructor Create(AStream: TStream);
    { A file or folder with this 8.3 name (11 bytes, as MakeName83) in the folder }
    function Exists(DirCluster: LongWord; const Raw83: array of Byte): Boolean;
    { Directory contents (DirCluster 0 = the root); not "." or ".." }
    function ListDir(DirCluster: LongWord): TFatEntries;
    function ReadFile(const E: TFatEntry): TBytes;
    { The first Count bytes (fewer if the file is shorter) }
    function ReadStart(const E: TFatEntry; Count: Integer): TBytes;
    procedure WriteFile(DirCluster: LongWord; const AName: string; const Data: TBytes);
    procedure MakeDir(DirCluster: LongWord; const AName: string);
    { Write a file or make a folder with a long name (any PC name): an 8.3
      name is made for it (NAME~1.EXT...), and the long name is kept in
      LFN entries unless it already is a valid upper case 8.3 name. Used,
      if given, holds the 8.3 names already in the folder (and gets the new
      one), saving reading the folder each time. MakeDirLong returns the
      new folder's cluster. }
    procedure WriteFileLong(DirCluster: LongWord; const LongName: string; const Data: TBytes;
      Used: TStrings = nil);
    function MakeDirLong(DirCluster: LongWord; const LongName: string; Used: TStrings = nil): LongWord;
    { Files, or empty directories }
    procedure Delete(const E: TFatEntry);
    procedure Rename(DirCluster: LongWord; const E: TFatEntry; const NewName: string);
    { The directory at Path ("/", "/GAMES/ARCADE"...) inside the one at Start
      (0: the root), creating the missing folders if asked; raises if it
      can't }
    function FindDir(const Path: string; CreateMissing: Boolean; Start: LongWord = 0): LongWord;
    { Write a file, replacing one with the same name }
    procedure PutFile(DirCluster: LongWord; const AName: string; const Data: TBytes);
    { The same with a long name (any PC name), replacing a file whose long
      or 8.3 name is that }
    procedure PutFileLong(DirCluster: LongWord; const LongName: string; const Data: TBytes);
    { A file or folder whose long or 8.3 name is Name: True and it in E }
    function FindName(DirCluster: LongWord; const Name: string; out E: TFatEntry): Boolean;
    { A folder with everything in it, or a file }
    procedure DeleteTree(const E: TFatEntry);
    function FreeBytes: Int64;
    function TotalBytes: Int64;
    { Where a file's data is on the card: pairs of first 512-byte sector
      (from the start of the image) and number of sectors, one per run of
      consecutive clusters (at most 65535 sectors each) }
    function FileMap(const E: TFatEntry): TInt64Array;
    property FatType: Integer read FFatType;
    property VolumeLabel: string read FLabel;
  end;

{ The 11 directory characters of an 8.3 name, or False with the reason }
function MakeName83(const AName: string; out Raw: array of Byte; out Error: string): Boolean;
function IsDirectory(const E: TFatEntry): Boolean;
function DisplayName(const E: TFatEntry): string;
{ An 8.3 name for a PC file name: invalid characters left out, the name cut
  to 8 characters and the extension to 3 }
function ShortNameFor(const FileName: string): string;
{ A new card image: a partition table with one FAT16 partition filling it
  (SizeMB from 16 to 2048) }
procedure FormatCard(Stream: TStream; SizeMB: Integer; const ALabel: string);
{ Copy a folder of the PC (its files and subfolders) into a directory of the
  card, merging with folders already there. Names that aren't valid 8.3
  names are skipped, or with ConvertNames turned into 8.3 names (NAME~1.EXT
  when two would clash). LongNames: the PC names are kept as long names
  (VFAT), with an 8.3 name made for each. }
procedure CopyTree(Volume: TFatVolume; DirCluster: LongWord; const SourceDir: string;
  ConvertNames: Boolean = False; LongNames: Boolean = False);
{ Bytes in a folder of the PC and its subfolders, and how many files and
  folders there are }
function FolderSize(const Dir: string; out Entries: Integer): Int64;

implementation

const
  ATTR_READONLY = $01;
  ATTR_HIDDEN = $02;
  ATTR_SYSTEM = $04;
  ATTR_VOLUME = $08;
  ATTR_DIR = $10;
  ATTR_ARCHIVE = $20;
  ATTR_LFN = $0F;

function IsDirectory(const E: TFatEntry): Boolean;
begin
  Result := (E.Attr and ATTR_DIR) <> 0;
end;

function DisplayName(const E: TFatEntry): string;
begin
  if E.LongName <> '' then Result := E.LongName else Result := E.ShortName;
end;

function ShortNameFor(const FileName: string): string;
const
  OK_CHARS = ['A'..'Z', '0'..'9', '!', '#', '$', '%', '&', '''', '(', ')', '-', '@', '^', '_',
    '`', '{', '}', '~'];
var
  Base, Ext: string;
  Ch: Char;
begin
  Base := '';
  for Ch in UpperCase(ChangeFileExt(ExtractFileName(FileName), '')) do
    if Ch in OK_CHARS then Base := Base + Ch;
  Ext := '';
  for Ch in UpperCase(ExtractFileExt(FileName)) do
    if Ch in OK_CHARS then Ext := Ext + Ch;
  if Base = '' then Base := 'FILE';
  Result := Copy(Base, 1, 8);
  if Ext <> '' then Result := Result + '.' + Copy(Ext, 1, 3);
end;

function MakeName83(const AName: string; out Raw: array of Byte; out Error: string): Boolean;
const
  OK_CHARS = ['A'..'Z', '0'..'9', '!', '#', '$', '%', '&', '''', '(', ')', '-', '@', '^', '_',
    '`', '{', '}', '~'];
var
  S, Base, Ext: string;
  P, I: Integer;
begin
  Result := False;
  Error := '';
  S := UpperCase(Trim(AName));
  P := LastDelimiter('.', S);
  if (P > 0) and (S <> '.') then
  begin
    Base := Copy(S, 1, P - 1);
    Ext := Copy(S, P + 1, MaxInt);
  end
  else
  begin
    Base := S;
    Ext := '';
  end;
  if (Base = '') or (Length(Base) > 8) or (Length(Ext) > 3) then
  begin
    Error := 'the name must be 1 to 8 characters, with an optional extension of up to 3';
    Exit;
  end;
  for I := 1 to Length(Base + Ext) do
    if not ((Base + Ext)[I] in OK_CHARS) then
    begin
      Error := Format('"%s" can''t be used in a name', [(Base + Ext)[I]]);
      Exit;
    end;
  for I := 0 to 7 do
    if I < Length(Base) then Raw[I] := Ord(Base[I + 1]) else Raw[I] := Ord(' ');
  for I := 0 to 2 do
    if I < Length(Ext) then Raw[8 + I] := Ord(Ext[I + 1]) else Raw[8 + I] := Ord(' ');
  Result := True;
end;

function GetW(const B: array of Byte; I: Integer): Word; inline;
begin
  Result := B[I] or (B[I + 1] shl 8);
end;

function GetL(const B: array of Byte; I: Integer): LongWord; inline;
begin
  Result := B[I] or (B[I + 1] shl 8) or (B[I + 2] shl 16) or (LongWord(B[I + 3]) shl 24);
end;

procedure PutW(var B: array of Byte; I: Integer; V: Word); inline;
begin
  B[I] := V and $FF;
  B[I + 1] := V shr 8;
end;

procedure PutL(var B: array of Byte; I: Integer; V: LongWord); inline;
begin
  B[I] := V and $FF;
  B[I + 1] := (V shr 8) and $FF;
  B[I + 2] := (V shr 16) and $FF;
  B[I + 3] := V shr 24;
end;

function DosStamp(T: TDateTime; out Date, Time: Word): Boolean;
var
  Y, Mo, D, H, Mi, S, Ms: Word;
begin
  DecodeDate(T, Y, Mo, D);
  DecodeTime(T, H, Mi, S, Ms);
  if Y < 1980 then Y := 1980;
  Date := ((Y - 1980) shl 9) or (Mo shl 5) or D;
  Time := (H shl 11) or (Mi shl 5) or (S div 2);
  Result := True;
end;

{ TFatVolume }

constructor TFatVolume.Create(AStream: TStream);
var
  Sec: array[0..511] of Byte;
  I, PType: Integer;
  Start: Int64;
  RootSectors: Int64;
  DataSectors: Int64;

  function LooksLikeBoot(const B: array of Byte): Boolean;
  begin
    Result := (B[0] in [$EB, $E9]) and (GetW(B, 11) = 512) and (B[13] > 0) and
      (GetW(B, 14) > 0) and (B[16] in [1, 2]);
  end;

begin
  inherited Create;
  FStream := AStream;
  if FStream.Size < 4096 then raise EFatError.Create('the image is too small');
  FStream.Position := 0;
  FStream.ReadBuffer(Sec, 512);
  // A partition table, or a FAT volume right from sector 0
  FBase := -1;
  if (Sec[510] = $55) and (Sec[511] = $AA) and not LooksLikeBoot(Sec) then
    for I := 0 to 3 do
    begin
      PType := Sec[446 + I * 16 + 4];
      Start := GetL(Sec, 446 + I * 16 + 8);
      if (PType in [$01, $04, $06, $0B, $0C, $0E]) and (Start > 0) then
      begin
        FBase := Start * 512;
        Break;
      end;
    end;
  if FBase < 0 then FBase := 0;
  FStream.Position := FBase;
  FStream.ReadBuffer(Sec, 512);
  if not LooksLikeBoot(Sec) then raise EFatError.Create('no FAT file system found on the card');
  FBytesPerSector := GetW(Sec, 11);
  FSecPerCluster := Sec[13];
  FReserved := GetW(Sec, 14);
  FNumFATs := Sec[16];
  FRootEntries := GetW(Sec, 17);
  FTotalSectors := GetW(Sec, 19);
  if FTotalSectors = 0 then FTotalSectors := GetL(Sec, 32);
  FFatSectors := GetW(Sec, 22);
  if FFatSectors = 0 then
  begin
    FFatSectors := GetL(Sec, 36);
    FRootCluster := GetL(Sec, 44);
  end;
  RootSectors := (FRootEntries * 32 + FBytesPerSector - 1) div FBytesPerSector;
  FFatStart := FBase + Int64(FReserved) * FBytesPerSector;
  FRootStart := FFatStart + Int64(FNumFATs) * FFatSectors * FBytesPerSector;
  FDataStart := FRootStart + RootSectors * FBytesPerSector;
  DataSectors := FTotalSectors - FReserved - FNumFATs * FFatSectors - RootSectors;
  FClusters := DataSectors div FSecPerCluster;
  if FClusters < 4085 then FFatType := 12
  else if FClusters < 65525 then FFatType := 16
  else FFatType := 32;
  if (FFatType = 32) and (FRootCluster < 2) then raise EFatError.Create('bad FAT32 root directory');
  if FFatType = 32 then
    FLabel := TrimRight(Copy(PChar(@Sec[71]), 1, 11))
  else
    FLabel := TrimRight(Copy(PChar(@Sec[43]), 1, 11));
  // Keep the first FAT in memory
  SetLength(FFat, FFatSectors * FBytesPerSector);
  FStream.Position := FFatStart;
  FStream.ReadBuffer(FFat[0], Length(FFat));
end;

function TFatVolume.ClusterBytes: Integer;
begin
  Result := FSecPerCluster * FBytesPerSector;
end;

function TFatVolume.ClusterPos(Cluster: LongWord): Int64;
begin
  Result := FDataStart + Int64(Cluster - 2) * ClusterBytes;
end;

function TFatVolume.GetFat(Cluster: LongWord): LongWord;
var
  I: Integer;
begin
  case FFatType of
    12:
      begin
        I := Cluster * 3 div 2;
        Result := GetW(FFat, I);
        if Odd(Cluster) then Result := Result shr 4 else Result := Result and $FFF;
      end;
    16: Result := GetW(FFat, Cluster * 2);
  else
    Result := GetL(FFat, Cluster * 4) and $0FFFFFFF;
  end;
end;

procedure TFatVolume.SetFat(Cluster, Value: LongWord);
var
  I, Len, F: Integer;
  W: Word;
begin
  case FFatType of
    12:
      begin
        I := Cluster * 3 div 2;
        W := GetW(FFat, I);
        if Odd(Cluster) then W := (W and $000F) or (Value shl 4)
        else W := (W and $F000) or (Value and $FFF);
        PutW(FFat, I, W);
        Len := 2;
      end;
    16:
      begin
        I := Cluster * 2;
        PutW(FFat, I, Value);
        Len := 2;
      end;
  else
    I := Cluster * 4;
    PutL(FFat, I, (GetL(FFat, I) and $F0000000) or (Value and $0FFFFFFF));
    Len := 4;
  end;
  // Write through to every copy of the FAT
  for F := 0 to FNumFATs - 1 do
  begin
    FStream.Position := FFatStart + Int64(F) * FFatSectors * FBytesPerSector + I;
    FStream.WriteBuffer(FFat[I], Len);
  end;
end;

function TFatVolume.EndMark: LongWord;
begin
  case FFatType of
    12: Result := $FFF;
    16: Result := $FFFF;
  else
    Result := $0FFFFFFF;
  end;
end;

function TFatVolume.IsEnd(Value: LongWord): Boolean;
begin
  case FFatType of
    12: Result := Value >= $FF8;
    16: Result := Value >= $FFF8;
  else
    Result := Value >= $0FFFFFF8;
  end;
  Result := Result or (Value < 2) or (Value >= FClusters + 2);
end;

function TFatVolume.Chain(First: LongWord): TLongWordArray;
var
  C: LongWord;
  N: Integer;
begin
  Result := nil;
  N := 0;
  C := First;
  while (C >= 2) and (C < FClusters + 2) and (N <= FClusters) do
  begin
    SetLength(Result, N + 1);
    Result[N] := C;
    Inc(N);
    C := GetFat(C);
    if IsEnd(C) then Break;
  end;
end;

function TFatVolume.DirSectors(DirCluster: LongWord): TInt64Array;
var
  Clusters: TLongWordArray;
  I, K, N: Integer;
begin
  Result := nil;
  if (DirCluster = 0) and (FFatType = 32) then DirCluster := FRootCluster;
  if DirCluster = 0 then
  begin
    // FAT12/16 root: a fixed area
    N := (FRootEntries * 32 + FBytesPerSector - 1) div FBytesPerSector;
    SetLength(Result, N);
    for I := 0 to N - 1 do Result[I] := FRootStart + Int64(I) * FBytesPerSector;
  end
  else
  begin
    Clusters := Chain(DirCluster);
    SetLength(Result, Length(Clusters) * FSecPerCluster);
    for I := 0 to High(Clusters) do
      for K := 0 to FSecPerCluster - 1 do
        Result[I * FSecPerCluster + K] := ClusterPos(Clusters[I]) + Int64(K) * FBytesPerSector;
  end;
end;

function TFatVolume.ListDir(DirCluster: LongWord): TFatEntries;
var
  Sectors: TInt64Array;
  Sec: array[0..511] of Byte;
  S, I, N, Seq, K: Integer;
  E: PByte;
  Parts: array[1..20] of UnicodeString;
  LfnPos: array of Int64;
  HaveLfn: Boolean;
  Name, Ext: string;
  Ent: TFatEntry;
  U: UnicodeString;
  Ch: Word;
  D, T: Word;

  procedure ResetLfn;
  var
    J: Integer;
  begin
    HaveLfn := False;
    for J := 1 to 20 do Parts[J] := '';
    LfnPos := nil;
  end;

begin
  Result := nil;
  ResetLfn;
  Sectors := DirSectors(DirCluster);
  for S := 0 to High(Sectors) do
  begin
    FStream.Position := Sectors[S];
    FStream.ReadBuffer(Sec, 512);
    for I := 0 to 15 do
    begin
      E := @Sec[I * 32];
      if E[0] = 0 then Exit;            // end of the directory
      if E[0] = $E5 then
      begin
        ResetLfn;
        Continue;
      end;
      if E[11] = ATTR_LFN then
      begin
        // A piece of a long name: 13 UTF-16 characters
        Seq := E[0] and $1F;
        if (Seq >= 1) and (Seq <= 20) then
        begin
          U := '';
          for K := 0 to 12 do
          begin
            if K < 5 then Ch := GetW(Sec, I * 32 + 1 + K * 2)
            else if K < 11 then Ch := GetW(Sec, I * 32 + 14 + (K - 5) * 2)
            else Ch := GetW(Sec, I * 32 + 28 + (K - 11) * 2);
            if (Ch = 0) or (Ch = $FFFF) then Break;
            U := U + WideChar(Ch);
          end;
          Parts[Seq] := U;
          HaveLfn := True;
          SetLength(LfnPos, Length(LfnPos) + 1);
          LfnPos[High(LfnPos)] := Sectors[S] + I * 32;
        end;
        Continue;
      end;
      if (E[11] and ATTR_VOLUME) <> 0 then
      begin
        ResetLfn;
        Continue;
      end;
      Name := TrimRight(Copy(PChar(E), 1, 8));
      if E[0] = $05 then Name[1] := Chr($E5);
      Ext := TrimRight(Copy(PChar(@E[8]), 1, 3));
      if (Name = '.') or (Name = '..') then
      begin
        ResetLfn;
        Continue;
      end;
      Ent := Default(TFatEntry);
      if Ext <> '' then Ent.ShortName := Name + '.' + Ext else Ent.ShortName := Name;
      if HaveLfn then
      begin
        U := '';
        for K := 1 to 20 do U := U + Parts[K];
        Ent.LongName := UTF8Encode(U);
        Ent.LfnPos := Copy(LfnPos);
      end;
      Ent.Attr := E[11];
      Ent.Cluster := GetW(Sec, I * 32 + 26);
      if FFatType = 32 then Ent.Cluster := Ent.Cluster or (LongWord(GetW(Sec, I * 32 + 20)) shl 16);
      Ent.Size := GetL(Sec, I * 32 + 28);
      D := GetW(Sec, I * 32 + 24);
      T := GetW(Sec, I * 32 + 22);
      if D <> 0 then
        try
          Ent.Stamp := EncodeDate(1980 + D shr 9, Max(1, (D shr 5) and 15), Max(1, D and 31)) +
            EncodeTime(Min(23, T shr 11), Min(59, (T shr 5) and 63), Min(59, (T and 31) * 2), 0);
        except
          Ent.Stamp := 0;
        end;
      Ent.EntryPos := Sectors[S] + I * 32;
      N := Length(Result);
      SetLength(Result, N + 1);
      Result[N] := Ent;
      ResetLfn;
    end;
  end;
end;

function TFatVolume.ReadFile(const E: TFatEntry): TBytes;
var
  Clusters: TLongWordArray;
  I, Len: Integer;
  Done: Int64;
begin
  SetLength(Result, E.Size);
  Clusters := Chain(E.Cluster);
  Done := 0;
  for I := 0 to High(Clusters) do
  begin
    if Done >= E.Size then Break;
    Len := Min(ClusterBytes, E.Size - Done);
    FStream.Position := ClusterPos(Clusters[I]);
    FStream.ReadBuffer(Result[Done], Len);
    Inc(Done, Len);
  end;
  if Done < E.Size then raise EFatError.Create('the file''s clusters are broken');
end;

function TFatVolume.ReadStart(const E: TFatEntry; Count: Integer): TBytes;
var
  Clusters: TLongWordArray;
  I, Len, Done: Integer;
begin
  Count := Min(Count, E.Size);
  SetLength(Result, Count);
  Clusters := Chain(E.Cluster);
  Done := 0;
  for I := 0 to High(Clusters) do
  begin
    if Done >= Count then Break;
    Len := Min(ClusterBytes, Count - Done);
    FStream.Position := ClusterPos(Clusters[I]);
    FStream.ReadBuffer(Result[Done], Len);
    Inc(Done, Len);
  end;
  SetLength(Result, Done);
end;

function TFatVolume.AllocCluster(Previous: LongWord): LongWord;
var
  C: LongWord;
begin
  for C := 2 to FClusters + 1 do
    if GetFat(C) = 0 then
    begin
      SetFat(C, EndMark);
      if Previous >= 2 then SetFat(Previous, C);
      Exit(C);
    end;
  raise EFatError.Create('the card is full');
end;

procedure TFatVolume.FreeChain(First: LongWord);
var
  Clusters: TLongWordArray;
  I: Integer;
begin
  Clusters := Chain(First);
  for I := 0 to High(Clusters) do SetFat(Clusters[I], 0);
end;

procedure TFatVolume.ZeroCluster(Cluster: LongWord);
var
  Zero: TBytes;
begin
  SetLength(Zero, ClusterBytes);
  FStream.Position := ClusterPos(Cluster);
  FStream.WriteBuffer(Zero[0], Length(Zero));
end;

function TFatVolume.FindFreeEntry(DirCluster: LongWord): Int64;
var
  Sectors: TInt64Array;
  Sec: array[0..511] of Byte;
  S, I: Integer;
  Clusters: TLongWordArray;
  NewCluster: LongWord;
begin
  Sectors := DirSectors(DirCluster);
  for S := 0 to High(Sectors) do
  begin
    FStream.Position := Sectors[S];
    FStream.ReadBuffer(Sec, 512);
    for I := 0 to 15 do
      if Sec[I * 32] in [0, $E5] then Exit(Sectors[S] + I * 32);
  end;
  if (DirCluster = 0) and (FFatType <> 32) then
    raise EFatError.Create('the root directory is full');
  // Grow the directory by a cluster
  if (DirCluster = 0) then DirCluster := FRootCluster;
  Clusters := Chain(DirCluster);
  NewCluster := AllocCluster(Clusters[High(Clusters)]);
  ZeroCluster(NewCluster);
  Result := ClusterPos(NewCluster);
end;

procedure TFatVolume.WriteEntry(Pos: Int64; const Raw83: array of Byte; Attr: Byte; Cluster,
  Size: LongWord);
var
  E: array[0..31] of Byte;
  D, T: Word;
  I: Integer;
begin
  FillChar(E, SizeOf(E), 0);
  for I := 0 to 10 do E[I] := Raw83[I];
  E[11] := Attr;
  DosStamp(Now, D, T);
  PutW(E, 14, T);           // created
  PutW(E, 16, D);
  PutW(E, 18, D);           // accessed
  PutW(E, 20, Cluster shr 16);
  PutW(E, 22, T);           // written
  PutW(E, 24, D);
  PutW(E, 26, Cluster and $FFFF);
  PutL(E, 28, Size);
  FStream.Position := Pos;
  FStream.WriteBuffer(E, 32);
end;

function TFatVolume.Exists(DirCluster: LongWord; const Raw83: array of Byte): Boolean;
var
  Entries: TFatEntries;
  I: Integer;
  Raw: array[0..10] of Byte;
  Error: string;
begin
  Entries := ListDir(DirCluster);
  for I := 0 to High(Entries) do
    if MakeName83(Entries[I].ShortName, Raw, Error) and CompareMem(@Raw[0], @Raw83[0], 11) then
      Exit(True);
  Result := False;
end;

procedure TFatVolume.WriteFile(DirCluster: LongWord; const AName: string; const Data: TBytes);
var
  Raw: array[0..10] of Byte;
  Error: string;
  First, Prev, C: LongWord;
  Done, Len: Int64;
  Pos: Int64;
begin
  if not MakeName83(AName, Raw, Error) then raise EFatError.Create(Error);
  if Exists(DirCluster, Raw) then raise EFatError.CreateFmt('there is already a file called %s', [UpperCase(AName)]);
  if Length(Data) > FreeBytes then
    raise EFatError.CreateFmt('not enough space: %d bytes needed, %d free', [Length(Data), FreeBytes]);
  Pos := FindFreeEntry(DirCluster);
  First := 0;
  Prev := 0;
  Done := 0;
  while Done < Length(Data) do
  begin
    C := AllocCluster(Prev);
    if First = 0 then First := C;
    Len := Min(ClusterBytes, Length(Data) - Done);
    FStream.Position := ClusterPos(C);
    FStream.WriteBuffer(Data[Done], Len);
    Inc(Done, Len);
    Prev := C;
  end;
  WriteEntry(Pos, Raw, ATTR_ARCHIVE, First, Length(Data));
end;

procedure TFatVolume.MakeDir(DirCluster: LongWord; const AName: string);
var
  Raw, Dot: array[0..10] of Byte;
  Error: string;
  C, Parent: LongWord;
  Pos: Int64;
begin
  if not MakeName83(AName, Raw, Error) then raise EFatError.Create(Error);
  if Exists(DirCluster, Raw) then raise EFatError.CreateFmt('there is already a file called %s', [UpperCase(AName)]);
  Pos := FindFreeEntry(DirCluster);
  C := AllocCluster(0);
  ZeroCluster(C);
  // "." and ".." (the root is cluster 0 in "..")
  FillChar(Dot, SizeOf(Dot), Ord(' '));
  Dot[0] := Ord('.');
  WriteEntry(ClusterPos(C), Dot, ATTR_DIR, C, 0);
  Dot[1] := Ord('.');
  Parent := DirCluster;
  if (FFatType = 32) and (Parent = FRootCluster) then Parent := 0;
  WriteEntry(ClusterPos(C) + 32, Dot, ATTR_DIR, Parent, 0);
  WriteEntry(Pos, Raw, ATTR_DIR, C, 0);
end;

procedure TFatVolume.Delete(const E: TFatEntry);
var
  B: Byte;
  I: Integer;
begin
  if IsDirectory(E) and (Length(ListDir(E.Cluster)) > 0) then
    raise EFatError.Create('the folder isn''t empty');
  B := $E5;
  FStream.Position := E.EntryPos;
  FStream.WriteBuffer(B, 1);
  for I := 0 to High(E.LfnPos) do
  begin
    FStream.Position := E.LfnPos[I];
    FStream.WriteBuffer(B, 1);
  end;
  if E.Cluster >= 2 then FreeChain(E.Cluster);
end;

procedure TFatVolume.Rename(DirCluster: LongWord; const E: TFatEntry; const NewName: string);
var
  Raw, Old: array[0..10] of Byte;
  Error: string;
  B: Byte;
  I: Integer;
begin
  if not MakeName83(NewName, Raw, Error) then raise EFatError.Create(Error);
  if MakeName83(E.ShortName, Old, Error) and CompareMem(@Raw[0], @Old[0], 11) and (E.LongName = '') then
    Exit;
  if Exists(DirCluster, Raw) and not (MakeName83(E.ShortName, Old, Error) and
     CompareMem(@Raw[0], @Old[0], 11)) then
    raise EFatError.CreateFmt('there is already a file called %s', [UpperCase(NewName)]);
  FStream.Position := E.EntryPos;
  FStream.WriteBuffer(Raw, 11);
  // The old long name would no longer match: drop it
  B := $E5;
  for I := 0 to High(E.LfnPos) do
  begin
    FStream.Position := E.LfnPos[I];
    FStream.WriteBuffer(B, 1);
  end;
end;

function TFatVolume.FindDir(const Path: string; CreateMissing: Boolean; Start: LongWord): LongWord;
var
  Parts: TStringArray;
  I, K: Integer;
  Entries: TFatEntries;
  Found: Boolean;
  Raw: array[0..10] of Byte;
  Error: string;
begin
  Result := Start;
  Parts := StringReplace(Path, '\', '/', [rfReplaceAll]).Split(['/']);
  for I := 0 to High(Parts) do
  begin
    if Trim(Parts[I]) = '' then Continue;
    Found := False;
    Entries := ListDir(Result);
    for K := 0 to High(Entries) do
      if IsDirectory(Entries[K]) and (SameText(Entries[K].ShortName, Parts[I]) or
         SameText(Entries[K].LongName, Parts[I])) then
      begin
        Result := Entries[K].Cluster;
        Found := True;
        Break;
      end;
    if Found then Continue;
    if not CreateMissing then raise EFatError.CreateFmt('there is no folder %s', [Parts[I]]);
    // An 8.3 name as it is; any other with its long name
    if MakeName83(Parts[I], Raw, Error) then
    begin
      MakeDir(Result, Parts[I]);
      Entries := ListDir(Result);
      for K := 0 to High(Entries) do
        if IsDirectory(Entries[K]) and SameText(Entries[K].ShortName, Trim(Parts[I])) then
          Result := Entries[K].Cluster;
    end
    else
      Result := MakeDirLong(Result, Parts[I]);
  end;
end;

procedure TFatVolume.PutFileLong(DirCluster: LongWord; const LongName: string; const Data: TBytes);
var
  E: TFatEntry;
begin
  if FindName(DirCluster, LongName, E) and not IsDirectory(E) then Delete(E);
  WriteFileLong(DirCluster, LongName, Data);
end;

function TFatVolume.FindName(DirCluster: LongWord; const Name: string; out E: TFatEntry): Boolean;
var
  Entries: TFatEntries;
  I: Integer;
begin
  Result := False;
  Entries := ListDir(DirCluster);
  for I := 0 to High(Entries) do
    if SameText(Entries[I].ShortName, Trim(Name)) or
       ((Entries[I].LongName <> '') and SameText(Entries[I].LongName, Name)) then
    begin
      E := Entries[I];
      Exit(True);
    end;
end;

procedure TFatVolume.DeleteTree(const E: TFatEntry);
var
  Entries: TFatEntries;
  I: Integer;
begin
  if IsDirectory(E) then
  begin
    Entries := ListDir(E.Cluster);
    for I := 0 to High(Entries) do DeleteTree(Entries[I]);
  end;
  Delete(E);
end;

procedure TFatVolume.PutFile(DirCluster: LongWord; const AName: string; const Data: TBytes);
var
  Entries: TFatEntries;
  I: Integer;
begin
  Entries := ListDir(DirCluster);
  for I := 0 to High(Entries) do
    if not IsDirectory(Entries[I]) and SameText(Entries[I].ShortName, Trim(AName)) then
      Delete(Entries[I]);
  WriteFile(DirCluster, AName, Data);
end;

function TFatVolume.FreeBytes: Int64;
var
  C: LongWord;
  N: Int64;
begin
  N := 0;
  for C := 2 to FClusters + 1 do
    if GetFat(C) = 0 then Inc(N);
  Result := N * ClusterBytes;
end;

function TFatVolume.FileMap(const E: TFatEntry): TInt64Array;
var
  C: TLongWordArray;
  I, N, PerCluster: Integer;
  Sector: Int64;
begin
  Result := nil;
  if E.Cluster < 2 then Exit;
  C := Chain(E.Cluster);
  PerCluster := ClusterBytes div 512;
  N := 0;
  for I := 0 to High(C) do
  begin
    Sector := ClusterPos(C[I]) div 512;
    if (N > 0) and (Result[N - 2] + Result[N - 1] = Sector) and
       (Result[N - 1] + PerCluster <= 65535) then
      Inc(Result[N - 1], PerCluster)
    else
    begin
      SetLength(Result, N + 2);
      Result[N] := Sector;
      Result[N + 1] := PerCluster;
      Inc(N, 2);
    end;
  end;
end;

function TFatVolume.TotalBytes: Int64;
begin
  Result := Int64(FClusters) * ClusterBytes;
end;

function FolderSize(const Dir: string; out Entries: Integer): Int64;
var
  Info: TSearchRec;
  Sub: Integer;
begin
  Result := 0;
  Entries := 0;
  if FindFirst(IncludeTrailingPathDelimiter(Dir) + '*', faAnyFile, Info) <> 0 then Exit;
  try
    repeat
      if (Info.Name = '.') or (Info.Name = '..') then Continue;
      Inc(Entries);
      if (Info.Attr and faDirectory) <> 0 then
      begin
        Inc(Result, FolderSize(IncludeTrailingPathDelimiter(Dir) + Info.Name, Sub));
        Inc(Entries, Sub);
      end
      else
        Inc(Result, Info.Size);
    until FindNext(Info) <> 0;
  finally
    FindClose(Info);
  end;
end;

procedure CopyTreeLong(Volume: TFatVolume; DirCluster: LongWord; const SourceDir: string);
var
  Info: TSearchRec;
  Dir: string;
  Entries: TFatEntries;
  Used: TStringList;
  I: Integer;
  Data: TBytes;
  S: TFileStream;
  Sub: LongWord;
begin
  Dir := IncludeTrailingPathDelimiter(SourceDir);
  if FindFirst(Dir + '*', faAnyFile, Info) <> 0 then Exit;
  Used := TStringList.Create;
  try
    Entries := Volume.ListDir(DirCluster);
    for I := 0 to High(Entries) do Used.Add(UpperCase(Entries[I].ShortName));
    repeat
      if (Info.Name = '.') or (Info.Name = '..') then Continue;
      if (Info.Attr and faDirectory) <> 0 then
      begin
        // A folder that is already there is merged with
        Sub := 0;
        for I := 0 to High(Entries) do
          if IsDirectory(Entries[I]) and SameText(DisplayName(Entries[I]), Info.Name) then
            Sub := Entries[I].Cluster;
        if Sub = 0 then Sub := Volume.MakeDirLong(DirCluster, Info.Name, Used);
        CopyTreeLong(Volume, Sub, Dir + Info.Name);
      end
      else
      begin
        S := TFileStream.Create(Dir + Info.Name, fmOpenRead or fmShareDenyWrite);
        try
          SetLength(Data, S.Size);
          if S.Size > 0 then S.ReadBuffer(Data[0], S.Size);
        finally
          S.Free;
        end;
        Volume.WriteFileLong(DirCluster, Info.Name, Data, Used);
      end;
    until FindNext(Info) <> 0;
  finally
    Used.Free;
    FindClose(Info);
  end;
end;

procedure CopyTree(Volume: TFatVolume; DirCluster: LongWord; const SourceDir: string;
  ConvertNames: Boolean; LongNames: Boolean);
var
  Info: TSearchRec;
  Dir, Name, Base, Ext: string;
  Raw: array[0..10] of Byte;
  Error: string;
  Entries: TFatEntries;
  Used: TStringList;
  I, N: Integer;
  Data: TBytes;
  S: TFileStream;
  Sub: LongWord;
begin
  if LongNames then
  begin
    CopyTreeLong(Volume, DirCluster, SourceDir);
    Exit;
  end;
  Dir := IncludeTrailingPathDelimiter(SourceDir);
  if FindFirst(Dir + '*', faAnyFile, Info) <> 0 then Exit;
  Used := TStringList.Create;
  try
    // Names already in the card's folder
    Entries := Volume.ListDir(DirCluster);
    for I := 0 to High(Entries) do Used.Add(UpperCase(Entries[I].ShortName));
    repeat
      if (Info.Name = '.') or (Info.Name = '..') then Continue;
      Name := Info.Name;
      if not MakeName83(Name, Raw, Error) then
      begin
        if not ConvertNames then Continue;
        Name := ShortNameFor(Info.Name);
      end;
      Name := UpperCase(Name);
      if (Info.Attr and faDirectory) <> 0 then
      begin
        // A folder that is already there is merged with
        Sub := 0;
        for I := 0 to High(Entries) do
          if IsDirectory(Entries[I]) and SameText(Entries[I].ShortName, Name) then
            Sub := Entries[I].Cluster;
        if Sub = 0 then
        begin
          if Used.IndexOf(Name) >= 0 then Continue;   // a file with that name
          Volume.MakeDir(DirCluster, Name);
          Used.Add(Name);
          Entries := Volume.ListDir(DirCluster);
          for I := 0 to High(Entries) do
            if SameText(Entries[I].ShortName, Name) then Sub := Entries[I].Cluster;
        end;
        CopyTree(Volume, Sub, Dir + Info.Name, ConvertNames);
      end
      else
      begin
        if Used.IndexOf(Name) >= 0 then
        begin
          if not ConvertNames then Continue;
          // NAME~1.EXT, NAME~2.EXT...
          Ext := ExtractFileExt(Name);
          Base := ChangeFileExt(Name, '');
          N := 1;
          repeat
            Name := Copy(Base, 1, 8 - Length(IntToStr(N)) - 1) + '~' + IntToStr(N) + Ext;
            Inc(N);
          until Used.IndexOf(Name) < 0;
        end;
        S := TFileStream.Create(Dir + Info.Name, fmOpenRead or fmShareDenyWrite);
        try
          SetLength(Data, S.Size);
          if S.Size > 0 then S.ReadBuffer(Data[0], S.Size);
        finally
          S.Free;
        end;
        Volume.WriteFile(DirCluster, Name, Data);
        Used.Add(Name);
      end;
    until FindNext(Info) <> 0;
  finally
    Used.Free;
    FindClose(Info);
  end;
end;

{ Long names (VFAT) }

function LfnChecksum(const Raw83: array of Byte): Byte;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to 10 do Result := Byte(((Result and 1) shl 7) + (Result shr 1) + Raw83[I]);
end;

function LfnEntriesFor(const LongName: string): Integer;
begin
  Result := (Length(UTF8Decode(LongName)) + 12) div 13;
end;

function TFatVolume.FindFreeEntries(DirCluster: LongWord; Count: Integer): TInt64Array;
var
  Sectors: TInt64Array;
  Sec: array[0..511] of Byte;
  S, I, Run: Integer;
  Clusters: TLongWordArray;
  NewCluster, Dir: LongWord;
  K: Integer;
begin
  Result := nil;
  SetLength(Result, Count);
  Dir := DirCluster;
  repeat
    Sectors := DirSectors(Dir);
    Run := 0;
    for S := 0 to High(Sectors) do
    begin
      FStream.Position := Sectors[S];
      FStream.ReadBuffer(Sec, 512);
      for I := 0 to 15 do
        if Sec[I * 32] in [0, $E5] then
        begin
          Result[Run] := Sectors[S] + I * 32;
          Inc(Run);
          if Run = Count then Exit;
        end
        else
          Run := 0;
    end;
    if (Dir = 0) and (FFatType <> 32) then
      raise EFatError.Create('the root directory is full');
    // Grow the directory by a cluster; a run of free entries at its end
    // carries on into it
    if Dir = 0 then Dir := FRootCluster;
    Clusters := Chain(Dir);
    NewCluster := AllocCluster(Clusters[High(Clusters)]);
    ZeroCluster(NewCluster);
    for K := 0 to Count - 1 - Run do
    begin
      Result[Run + K] := ClusterPos(NewCluster) + K * 32;
      if K * 32 >= ClusterBytes then raise EFatError.Create('the name is too long');
    end;
    Exit;
  until False;
end;

procedure TFatVolume.WriteLongName(const Positions: TInt64Array; const LongName: string;
  const Raw83: array of Byte);
const
  OFFSETS: array[0..12] of Integer = (1, 3, 5, 7, 9, 14, 16, 18, 20, 22, 24, 28, 30);
var
  U: UnicodeString;
  E: array[0..31] of Byte;
  N, Seq, I, C: Integer;
  Sum: Byte;
  Ch: Word;
begin
  U := UTF8Decode(LongName);
  N := Length(Positions) - 1;    // LFN entries; the last position is the 8.3 entry
  Sum := LfnChecksum(Raw83);
  for Seq := 1 to N do
  begin
    FillChar(E, SizeOf(E), 0);
    E[0] := Seq;
    if Seq = N then E[0] := E[0] or $40;
    E[11] := ATTR_LFN;
    E[13] := Sum;
    for I := 0 to 12 do
    begin
      C := (Seq - 1) * 13 + I + 1;
      if C <= Length(U) then Ch := Ord(U[C])
      else if C = Length(U) + 1 then Ch := 0
      else Ch := $FFFF;
      E[OFFSETS[I]] := Ch and $FF;
      E[OFFSETS[I] + 1] := Ch shr 8;
    end;
    // Stored last part first
    FStream.Position := Positions[N - Seq];
    FStream.WriteBuffer(E, 32);
  end;
end;

{ The 8.3 name for LongName in a folder; True if it needs LFN entries }
function TFatVolume.ShortNameIn(DirCluster: LongWord; const LongName: string; Used: TStrings;
  out Raw: array of Byte): Boolean;
var
  Names: TStringList;
  Entries: TFatEntries;
  Short, Base, Ext, Error: string;
  I, N: Integer;
begin
  Names := nil;
  if Used = nil then
  begin
    Names := TStringList.Create;
    Entries := ListDir(DirCluster);
    for I := 0 to High(Entries) do Names.Add(UpperCase(Entries[I].ShortName));
    Used := Names;
  end;
  try
    Short := ShortNameFor(LongName);
    Result := Short <> LongName;
    // Only the case differs: the same 8.3 name, if it is free
    if (Short <> UpperCase(LongName)) or (Used.IndexOf(Short) >= 0) then
    begin
      Result := True;
      Ext := ExtractFileExt(Short);
      Base := ChangeFileExt(Short, '');
      N := 1;
      repeat
        Short := Copy(Base, 1, 8 - Length(IntToStr(N)) - 1) + '~' + IntToStr(N) + Ext;
        Inc(N);
      until Used.IndexOf(Short) < 0;
    end;
    if not MakeName83(Short, Raw, Error) then raise EFatError.Create(Error);
    Used.Add(Short);
  finally
    Names.Free;
  end;
end;

{ The data in new clusters; the first one (0 for no data) }
function TFatVolume.WriteData(const Data: TBytes): LongWord;
var
  Prev, C: LongWord;
  Done, Len: Int64;
begin
  if Length(Data) > FreeBytes then
    raise EFatError.CreateFmt('not enough space: %d bytes needed, %d free', [Length(Data), FreeBytes]);
  Result := 0;
  Prev := 0;
  Done := 0;
  while Done < Length(Data) do
  begin
    C := AllocCluster(Prev);
    if Result = 0 then Result := C;
    Len := Min(ClusterBytes, Length(Data) - Done);
    FStream.Position := ClusterPos(C);
    FStream.WriteBuffer(Data[Done], Len);
    Inc(Done, Len);
    Prev := C;
  end;
end;

procedure TFatVolume.WriteFileLong(DirCluster: LongWord; const LongName: string;
  const Data: TBytes; Used: TStrings);
var
  Raw: array[0..10] of Byte;
  Lfn: Integer;
  Pos: TInt64Array;
  First: LongWord;
begin
  if ShortNameIn(DirCluster, LongName, Used, Raw) then Lfn := LfnEntriesFor(LongName) else Lfn := 0;
  Pos := FindFreeEntries(DirCluster, Lfn + 1);
  First := WriteData(Data);
  if Lfn > 0 then WriteLongName(Pos, LongName, Raw);
  WriteEntry(Pos[Lfn], Raw, ATTR_ARCHIVE, First, Length(Data));
end;

function TFatVolume.MakeDirLong(DirCluster: LongWord; const LongName: string; Used: TStrings): LongWord;
var
  Raw, Dot: array[0..10] of Byte;
  Lfn: Integer;
  Pos: TInt64Array;
  Parent: LongWord;
begin
  if ShortNameIn(DirCluster, LongName, Used, Raw) then Lfn := LfnEntriesFor(LongName) else Lfn := 0;
  Pos := FindFreeEntries(DirCluster, Lfn + 1);
  Result := AllocCluster(0);
  ZeroCluster(Result);
  FillChar(Dot, SizeOf(Dot), Ord(' '));
  Dot[0] := Ord('.');
  WriteEntry(ClusterPos(Result), Dot, ATTR_DIR, Result, 0);
  Dot[1] := Ord('.');
  Parent := DirCluster;
  if (FFatType = 32) and (Parent = FRootCluster) then Parent := 0;
  WriteEntry(ClusterPos(Result) + 32, Dot, ATTR_DIR, Parent, 0);
  if Lfn > 0 then WriteLongName(Pos, LongName, Raw);
  WriteEntry(Pos[Lfn], Raw, ATTR_DIR, Result, 0);
end;

{ New cards }

procedure FormatCard(Stream: TStream; SizeMB: Integer; const ALabel: string);
const
  START = 2048;          // first sector of the partition (1 MB aligned)
  RESERVED = 1;
  ROOT_ENTRIES = 512;
var
  Total, PartSectors, FatSize, RootSectors, Tmp1, Tmp2: Int64;
  SPC, I: Integer;
  Sec: array[0..511] of Byte;
  LabelText: string;
begin
  if (SizeMB < 16) or (SizeMB > 2048) then raise EFatError.Create('the card size must be 16 to 2048 MB');
  Total := Int64(SizeMB) * 2048;
  PartSectors := Total - START;
  // Cluster size: FAT16 needs between 4085 and 65524 clusters
  SPC := 1;
  while PartSectors div SPC > 65000 do SPC := SPC * 2;
  RootSectors := ROOT_ENTRIES * 32 div 512;
  Tmp1 := PartSectors - (RESERVED + RootSectors);
  Tmp2 := 256 * SPC + 2;
  FatSize := (Tmp1 + Tmp2 - 1) div Tmp2;
  Stream.Size := Total * 512;
  // Partition table: one FAT16 (LBA) partition
  FillChar(Sec, SizeOf(Sec), 0);
  Sec[446] := $00;                    // not bootable
  Sec[446 + 1] := $FE; Sec[446 + 2] := $FF; Sec[446 + 3] := $FF;   // CHS: use LBA
  Sec[446 + 4] := $06;
  Sec[446 + 5] := $FE; Sec[446 + 6] := $FF; Sec[446 + 7] := $FF;
  PutL(Sec, 446 + 8, START);
  PutL(Sec, 446 + 12, PartSectors);
  Sec[510] := $55;
  Sec[511] := $AA;
  Stream.Position := 0;
  Stream.WriteBuffer(Sec, 512);
  // Boot sector
  FillChar(Sec, SizeOf(Sec), 0);
  Sec[0] := $EB; Sec[1] := $3C; Sec[2] := $90;
  Move(PChar('PZX     ')^, Sec[3], 8);
  PutW(Sec, 11, 512);
  Sec[13] := SPC;
  PutW(Sec, 14, RESERVED);
  Sec[16] := 2;
  PutW(Sec, 17, ROOT_ENTRIES);
  if PartSectors < 65536 then PutW(Sec, 19, PartSectors) else PutL(Sec, 32, PartSectors);
  Sec[21] := $F8;
  PutW(Sec, 22, FatSize);
  PutW(Sec, 24, 63);
  PutW(Sec, 26, 255);
  PutL(Sec, 28, START);
  Sec[36] := $80;
  Sec[38] := $29;
  PutL(Sec, 39, LongWord(Random($7FFFFFFF)));
  LabelText := Copy(UpperCase(ALabel) + '           ', 1, 11);
  Move(PChar(LabelText)^, Sec[43], 11);
  Move(PChar('FAT16   ')^, Sec[54], 8);
  Sec[510] := $55;
  Sec[511] := $AA;
  Stream.Position := Int64(START) * 512;
  Stream.WriteBuffer(Sec, 512);
  // Both FATs: media byte and end of chain in the first two entries, the
  // rest free; then an empty root directory
  FillChar(Sec, SizeOf(Sec), 0);
  for I := 0 to 1 do
  begin
    Stream.Position := Int64(START + RESERVED + I * FatSize) * 512;
    Sec[0] := $F8; Sec[1] := $FF; Sec[2] := $FF; Sec[3] := $FF;
    Stream.WriteBuffer(Sec, 512);
    Sec[0] := 0; Sec[1] := 0; Sec[2] := 0; Sec[3] := 0;
    Tmp1 := 1;
    while Tmp1 < FatSize + RootSectors * Ord(I = 1) do
    begin
      Stream.WriteBuffer(Sec, 512);
      Inc(Tmp1);
    end;
  end;
end;

end.

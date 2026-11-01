{ Plus3FS: the +3DOS (CP/M) file system on a DSK image, for the disk
  browser: list the files with their +3DOS headers, read, write, rename and
  delete them.

  The format comes from the disk specification in the first sector of
  track 0 when there is one, and otherwise from the sector numbers: the
  standard +3 format (IDs 1-9, one reserved track), or the CPC system ($41)
  and data ($C1) formats. Blocks of 1K or more, 64 or more directory
  entries; block numbers are 8-bit up to 255 blocks and 16-bit beyond. }
unit Plus3FS;

{$mode objfpc}{$H+}
{$R-}{$Q-}

interface

uses
  SysUtils, Classes, Math, DSK;

const
  PLUS3_HEADER_SIZE = 128;

  { +3DOS header file types (as on tape) }
  FT_PROGRAM = 0;
  FT_NUMBERS = 1;
  FT_CHARS = 2;
  FT_BYTES = 3;

type
  EPlus3Error = class(Exception);

  TPlus3File = record
    User: Byte;
    Name: string;             // "NAME.EXT", trailing spaces removed
    RawName: array[0..10] of Byte;   // as in the directory, attribute bits clear
    ReadOnly, System: Boolean;
    Size: Integer;            // bytes used on disk (whole 128-byte records)
    HasHeader: Boolean;       // starts with a valid PLUS3DOS header
    FileType: Byte;           // FT_* (if HasHeader)
    DataLength: Word;         // length from the header's BASIC part
    Param1, Param2: Word;     // start address / autostart line, and so on
    HeaderLength: Integer;    // whole file length from the header, header included
  end;

  TPlus3Disk = class
  private
    FDisk: TDiskImage;
    FSides, FTracks, FSPT, FSecSize, FReserved, FBlockSize, FDirBlocks: Integer;
    FFirstID: Byte;
    FBlocks: Integer;         // blocks in the data area
    FWide: Boolean;           // 16-bit block numbers
    FExtentMask: Integer;     // logical extents per directory entry - 1
    FDir: TBytes;             // the directory, read once
    FFiles: array of TPlus3File;
    procedure ReadGeometry;
    function SectorData(LogicalSector: Integer): PByte;
    procedure ReadBlock(Block: Integer; var Buf: array of Byte);
    procedure WriteBlock(Block: Integer; const Buf: array of Byte);
    procedure LoadDirectory;
    procedure SaveDirectory;
    function EntryCount: Integer;
    function Entry(I: Integer): PByte;
    function PointersPerEntry: Integer;
    function EntryBlock(E: PByte; K: Integer): Integer;
    function SameName(E: PByte; const F: TPlus3File): Boolean;
    procedure BuildFileList;
    function UsedBlocks: TBits;
    function GetFile(Index: Integer): TPlus3File;
    function GetCount: Integer;
  public
    { Raises EPlus3Error if the disk isn't in a format it understands }
    constructor Create(ADisk: TDiskImage);
    { Re-read the directory (after the emulated +3 has written to the disk) }
    procedure Refresh;
    function ReadFile(Index: Integer): TBytes;
    { Write a new file (the whole contents, header included if any) }
    procedure WriteFile(const AName: string; const Data: TBytes);
    procedure RenameFile(Index: Integer; const NewName: string);
    procedure DeleteFile(Index: Integer);
    function FreeBytes: Integer;
    function FindFile(const AName: string): Integer;
    property Count: Integer read GetCount;
    property Files[Index: Integer]: TPlus3File read GetFile; default;
    property BlockSize: Integer read FBlockSize;
  end;

{ "name.ext" as the 11 directory characters, upper case. False (with the
  reason) if it isn't a valid +3DOS name. }
function MakeRawName(const AName: string; out Raw: array of Byte; out Error: string): Boolean;
{ A file with a PLUS3DOS header in front of Data }
function AddPlus3Header(const Data: TBytes; FileType: Byte; Param1, Param2: Word): TBytes;
function HasPlus3Header(const Data: TBytes): Boolean;
{ An Amstrad CPC's AMSDOS header: 128 bytes, the sum of the first 67 in the word
  at 67 (and a user number below 16) }
function HasAmsdosHeader(const Data: TBytes): Boolean;
{ A binary (file type 2) with an AMSDOS header, for the 8.3 name AName, loading
  at Load and starting at Exec }
function AddAmsdosHeader(const Data: TBytes; const AName: string; Load, Exec: Word): TBytes;
function FileTypeName(const F: TPlus3File): string;

implementation

uses
  Lang;


const
  SIGNATURE = 'PLUS3DOS';
  FILLER = $E5;

function HasPlus3Header(const Data: TBytes): Boolean;
var
  I: Integer;
  Sum: Byte;
begin
  Result := False;
  if Length(Data) < PLUS3_HEADER_SIZE then Exit;
  for I := 1 to 8 do
    if Chr(Data[I - 1]) <> SIGNATURE[I] then Exit;
  Sum := 0;
  for I := 0 to 126 do Sum := Byte(Sum + Data[I]);
  Result := (Data[8] = $1A) and (Sum = Data[127]);
end;

function HasAmsdosHeader(const Data: TBytes): Boolean;
var
  I, Sum: Integer;
begin
  Result := False;
  if Length(Data) < PLUS3_HEADER_SIZE then Exit;
  if Data[0] > 15 then Exit;
  Sum := 0;
  for I := 0 to 66 do Inc(Sum, Data[I]);
  Result := ((Sum and $FFFF) = (Data[67] or (Data[68] shl 8))) and (Data[18] <= 3) and (Sum > 0);
end;

function AddAmsdosHeader(const Data: TBytes; const AName: string; Load, Exec: Word): TBytes;
var
  I, K, Sum, N: Integer;
  Base, Ext: string;
begin
  SetLength(Result, Length(Data) + PLUS3_HEADER_SIZE);
  FillChar(Result[0], PLUS3_HEADER_SIZE, 0);
  N := Pos('.', AName);
  if N > 0 then
  begin
    Base := Copy(AName, 1, N - 1);
    Ext := Copy(AName, N + 1, 3);
  end
  else
  begin
    Base := AName;
    Ext := '';
  end;
  FillChar(Result[1], 11, Ord(' '));
  for K := 1 to Min(Length(Base), 8) do Result[K] := Ord(UpCase(Base[K]));
  for K := 1 to Min(Length(Ext), 3) do Result[8 + K] := Ord(UpCase(Ext[K]));
  // As SAVE makes it on a disc: 0 user, 1-11 name, 18 type (2: binary; 0: BASIC),
  // 21-22 load address, 24-25 logical length, 26-27 entry, 64-66 length
  Result[18] := 2;
  Result[21] := Load and $FF; Result[22] := Load shr 8;
  Result[24] := Length(Data) and $FF; Result[25] := (Length(Data) shr 8) and $FF;
  Result[26] := Exec and $FF; Result[27] := Exec shr 8;
  Result[64] := Length(Data) and $FF; Result[65] := (Length(Data) shr 8) and $FF;
  Result[66] := (Length(Data) shr 16) and $FF;
  Sum := 0;
  for I := 0 to 66 do Inc(Sum, Result[I]);
  Result[67] := Sum and $FF;
  Result[68] := (Sum shr 8) and $FF;
  if Length(Data) > 0 then Move(Data[0], Result[PLUS3_HEADER_SIZE], Length(Data));
end;

function AddPlus3Header(const Data: TBytes; FileType: Byte; Param1, Param2: Word): TBytes;
var
  I, Total: Integer;
  Sum: Byte;
begin
  Total := Length(Data) + PLUS3_HEADER_SIZE;
  SetLength(Result, Total);
  FillChar(Result[0], PLUS3_HEADER_SIZE, 0);
  for I := 1 to 8 do Result[I - 1] := Ord(SIGNATURE[I]);
  Result[8] := $1A;
  Result[9] := 1;      // issue
  Result[10] := 0;     // version
  Result[11] := Total and $FF;
  Result[12] := (Total shr 8) and $FF;
  Result[13] := (Total shr 16) and $FF;
  Result[14] := (Total shr 24) and $FF;
  Result[15] := FileType;
  Result[16] := Length(Data) and $FF;
  Result[17] := (Length(Data) shr 8) and $FF;
  Result[18] := Param1 and $FF;
  Result[19] := Param1 shr 8;
  Result[20] := Param2 and $FF;
  Result[21] := Param2 shr 8;
  Sum := 0;
  for I := 0 to 126 do Sum := Byte(Sum + Result[I]);
  Result[127] := Sum;
  if Length(Data) > 0 then Move(Data[0], Result[PLUS3_HEADER_SIZE], Length(Data));
end;

function FileTypeName(const F: TPlus3File): string;
begin
  if not F.HasHeader then Exit(_('(no header)'));
  case F.FileType of
    FT_PROGRAM: Result := _('Program');
    FT_NUMBERS: Result := _('Number array');
    FT_CHARS: Result := _('Character array');
    FT_BYTES: Result := _('Bytes');
  else
    Result := Format(_('Type %d'), [F.FileType]);
  end;
end;

function MakeRawName(const AName: string; out Raw: array of Byte; out Error: string): Boolean;
const
  BAD = ['<', '>', '.', ',', ';', ':', '=', '?', '*', '[', ']', ' ', '"', '/', '\', '|'];
var
  S, Base, Ext: string;
  P, I: Integer;
begin
  Result := False;
  Error := '';
  S := UpperCase(Trim(AName));
  P := Pos('.', S);
  if P > 0 then
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
    Error := _('the name must be 1 to 8 characters, with an optional extension of up to 3');
    Exit;
  end;
  for I := 1 to Length(Base + Ext) do
    if ((Base + Ext)[I] in BAD) or ((Base + Ext)[I] < '!') or ((Base + Ext)[I] > '~') then
    begin
      Error := Format(_('"%s" can''t be used in a name'), [(Base + Ext)[I]]);
      Exit;
    end;
  for I := 0 to 7 do
    if I < Length(Base) then Raw[I] := Ord(Base[I + 1]) else Raw[I] := Ord(' ');
  for I := 0 to 2 do
    if I < Length(Ext) then Raw[8 + I] := Ord(Ext[I + 1]) else Raw[8 + I] := Ord(' ');
  Result := True;
end;

{ TPlus3Disk }

constructor TPlus3Disk.Create(ADisk: TDiskImage);
begin
  inherited Create;
  FDisk := ADisk;
  ReadGeometry;
  LoadDirectory;
end;

procedure TPlus3Disk.ReadGeometry;
var
  Trk: PTrack;
  I: Integer;
  Spec: PByte;
  Valid: Boolean;
begin
  Trk := FDisk.Track(0, 0);
  if (Trk = nil) or not Trk^.Formatted or (Length(Trk^.Sectors) = 0) then
    raise EPlus3Error.Create(_('the disk is not formatted'));
  FFirstID := 255;
  for I := 0 to High(Trk^.Sectors) do FFirstID := Min(FFirstID, Trk^.Sectors[I].R);
  // Defaults: the standard +3 format, or the CPC formats by their sector IDs
  FSides := 1;
  FTracks := FDisk.Cylinders;
  FSPT := Length(Trk^.Sectors);
  FSecSize := 128 shl (Trk^.Sectors[0].N and 7);
  FReserved := 1;
  FBlockSize := 1024;
  FDirBlocks := 2;
  if FFirstID = $C1 then FReserved := 0          // CPC data format
  else if FFirstID = $41 then FReserved := 2;    // CPC system format
  // A disk specification in the boot sector (its first byte 0 or 3)
  Spec := nil;
  for I := 0 to High(Trk^.Sectors) do
    if (Trk^.Sectors[I].R = FFirstID) and (Length(Trk^.Sectors[I].Data) >= 16) then
      Spec := @Trk^.Sectors[I].Data[0];
  if (FFirstID = 1) and (Spec <> nil) and (Spec[0] in [0, 3]) then
  begin
    Valid := (Spec[3] > 0) and (Spec[4] <= 3) and (Spec[6] >= 3) and (Spec[6] <= 7) and
      (Spec[7] > 0) and (Spec[2] > 0);
    if Valid then
    begin
      if (Spec[1] and 3) <> 0 then FSides := 2 else FSides := 1;
      FTracks := Spec[2];
      FSPT := Spec[3];
      FSecSize := 128 shl Spec[4];
      FReserved := Spec[5];
      FBlockSize := 128 shl Spec[6];
      FDirBlocks := Spec[7];
    end;
  end;
  if FSides > FDisk.Sides then FSides := FDisk.Sides;
  FTracks := Min(FTracks, FDisk.Cylinders);
  FBlocks := ((FTracks * FSides - FReserved) * FSPT * FSecSize) div FBlockSize;
  if FBlocks <= FDirBlocks then raise EPlus3Error.Create(_('the disk is too small'));
  FWide := FBlocks > 255;
  FExtentMask := (PointersPerEntry * FBlockSize) div 16384 - 1;
  if FExtentMask < 0 then FExtentMask := 0;
end;

function TPlus3Disk.PointersPerEntry: Integer;
begin
  if FWide then Result := 8 else Result := 16;
end;

{ Sector data for a logical sector of the data area }
function TPlus3Disk.SectorData(LogicalSector: Integer): PByte;
var
  T, Cyl, Head, ID, I: Integer;
  Trk: PTrack;
begin
  T := FReserved + LogicalSector div FSPT;
  ID := FFirstID + LogicalSector mod FSPT;
  if FSides = 2 then
  begin
    Cyl := T div 2;
    Head := T mod 2;
  end
  else
  begin
    Cyl := T;
    Head := 0;
  end;
  Trk := FDisk.Track(Cyl, Head);
  if Trk <> nil then
    for I := 0 to High(Trk^.Sectors) do
      if (Trk^.Sectors[I].R = ID) and (Length(Trk^.Sectors[I].Data) >= FSecSize) then
        Exit(@Trk^.Sectors[I].Data[0]);
  raise EPlus3Error.CreateFmt(_('sector %d of track %d is missing'), [ID, Cyl]);
end;

procedure TPlus3Disk.ReadBlock(Block: Integer; var Buf: array of Byte);
var
  K, PerBlock: Integer;
begin
  PerBlock := FBlockSize div FSecSize;
  for K := 0 to PerBlock - 1 do
    Move(SectorData(Block * PerBlock + K)^, Buf[K * FSecSize], FSecSize);
end;

procedure TPlus3Disk.WriteBlock(Block: Integer; const Buf: array of Byte);
var
  K, PerBlock: Integer;
begin
  PerBlock := FBlockSize div FSecSize;
  for K := 0 to PerBlock - 1 do
    Move(Buf[K * FSecSize], SectorData(Block * PerBlock + K)^, FSecSize);
  FDisk.MarkModified;
end;

procedure TPlus3Disk.LoadDirectory;
var
  B: Integer;
begin
  SetLength(FDir, FDirBlocks * FBlockSize);
  for B := 0 to FDirBlocks - 1 do ReadBlock(B, FDir[B * FBlockSize]);
  BuildFileList;
end;

procedure TPlus3Disk.SaveDirectory;
var
  B: Integer;
begin
  for B := 0 to FDirBlocks - 1 do WriteBlock(B, FDir[B * FBlockSize]);
end;

procedure TPlus3Disk.Refresh;
begin
  LoadDirectory;
end;

function TPlus3Disk.EntryCount: Integer;
begin
  Result := Length(FDir) div 32;
end;

function TPlus3Disk.Entry(I: Integer): PByte;
begin
  Result := @FDir[I * 32];
end;

function TPlus3Disk.EntryBlock(E: PByte; K: Integer): Integer;
begin
  if FWide then Result := E[16 + K * 2] or (E[17 + K * 2] shl 8)
  else Result := E[16 + K];
end;

function TPlus3Disk.SameName(E: PByte; const F: TPlus3File): Boolean;
var
  I: Integer;
begin
  Result := E[0] = F.User;
  if Result then
    for I := 0 to 10 do
      if (E[1 + I] and $7F) <> F.RawName[I] then Exit(False);
end;

function ExtentNumber(E: PByte): Integer;
begin
  Result := (E[12] and $1F) or (E[14] shl 5);
end;

procedure TPlus3Disk.BuildFileList;
var
  I, J, N, Records: Integer;
  E: PByte;
  F: TPlus3File;
  Found: Boolean;
  Data: TBytes;
begin
  SetLength(FFiles, 0);
  for I := 0 to EntryCount - 1 do
  begin
    E := Entry(I);
    if E[0] > 15 then Continue;    // deleted ($E5), or not a file
    F := Default(TPlus3File);
    F.User := E[0];
    for J := 0 to 10 do F.RawName[J] := E[1 + J] and $7F;
    Found := False;
    for J := 0 to High(FFiles) do
      if SameName(E, FFiles[J]) then
      begin
        Found := True;
        Break;
      end;
    if Found then Continue;
    F.Name := TrimRight(Chr(F.RawName[0]) + Chr(F.RawName[1]) + Chr(F.RawName[2]) +
      Chr(F.RawName[3]) + Chr(F.RawName[4]) + Chr(F.RawName[5]) + Chr(F.RawName[6]) +
      Chr(F.RawName[7]));
    if TrimRight(Chr(F.RawName[8]) + Chr(F.RawName[9]) + Chr(F.RawName[10])) <> '' then
      F.Name := F.Name + '.' + TrimRight(Chr(F.RawName[8]) + Chr(F.RawName[9]) + Chr(F.RawName[10]));
    F.ReadOnly := (E[9] and $80) <> 0;
    F.System := (E[10] and $80) <> 0;
    // Size: records up to the highest extent
    Records := 0;
    for J := 0 to EntryCount - 1 do
      if SameName(Entry(J), F) then
        Records := Max(Records, ExtentNumber(Entry(J)) * 128 + Entry(J)[15]);
    F.Size := Records * 128;
    N := Length(FFiles);
    SetLength(FFiles, N + 1);
    FFiles[N] := F;
    // The header, if any, from the first record
    try
      Data := ReadFile(N);
    except
      Data := nil;
    end;
    if HasPlus3Header(Data) then
    begin
      F.HasHeader := True;
      F.HeaderLength := Data[11] or (Data[12] shl 8) or (Data[13] shl 16) or (Data[14] shl 24);
      F.FileType := Data[15];
      F.DataLength := Data[16] or (Data[17] shl 8);
      F.Param1 := Data[18] or (Data[19] shl 8);
      F.Param2 := Data[20] or (Data[21] shl 8);
      FFiles[N] := F;
    end;
  end;
end;

function TPlus3Disk.ReadFile(Index: Integer): TBytes;
var
  F: TPlus3File;
  I, K, Ext, Blk, Total, Len: Integer;
  E: PByte;
  Buf: TBytes;
begin
  F := FFiles[Index];
  SetLength(Result, F.Size);
  SetLength(Buf, FBlockSize);
  for I := 0 to EntryCount - 1 do
  begin
    E := Entry(I);
    if not SameName(E, F) then Continue;
    // This entry holds logical extents from (extent and not mask) on
    Ext := ExtentNumber(E) and not FExtentMask;
    for K := 0 to PointersPerEntry - 1 do
    begin
      Blk := EntryBlock(E, K);
      if Blk = 0 then Continue;
      if (Blk < FDirBlocks) or (Blk >= FBlocks) then Continue;
      Total := Ext * 16384 + K * FBlockSize;
      if Total >= F.Size then Continue;
      ReadBlock(Blk, Buf[0]);
      Len := Min(FBlockSize, F.Size - Total);
      Move(Buf[0], Result[Total], Len);
    end;
  end;
  // A header gives the exact length
  if HasPlus3Header(Result) then
  begin
    Len := Result[11] or (Result[12] shl 8) or (Result[13] shl 16) or (Result[14] shl 24);
    if (Len >= PLUS3_HEADER_SIZE) and (Len <= Length(Result)) then SetLength(Result, Len);
  end;
end;

function TPlus3Disk.UsedBlocks: TBits;
var
  I, K, Blk: Integer;
  E: PByte;
begin
  Result := TBits.Create(FBlocks);
  for I := 0 to FDirBlocks - 1 do Result[I] := True;
  for I := 0 to EntryCount - 1 do
  begin
    E := Entry(I);
    if E[0] > 15 then Continue;
    for K := 0 to PointersPerEntry - 1 do
    begin
      Blk := EntryBlock(E, K);
      if (Blk > 0) and (Blk < FBlocks) then Result[Blk] := True;
    end;
  end;
end;

function TPlus3Disk.FreeBytes: Integer;
var
  Used: TBits;
  I: Integer;
begin
  Used := UsedBlocks;
  try
    Result := 0;
    for I := 0 to FBlocks - 1 do
      if not Used[I] then Inc(Result, FBlockSize);
  finally
    Used.Free;
  end;
end;

function TPlus3Disk.FindFile(const AName: string): Integer;
var
  Raw: array[0..10] of Byte;
  Error: string;
  I, J: Integer;
  Same: Boolean;
begin
  Result := -1;
  if not MakeRawName(AName, Raw, Error) then Exit;
  for I := 0 to High(FFiles) do
  begin
    Same := FFiles[I].User = 0;
    for J := 0 to 10 do
      if FFiles[I].RawName[J] <> Raw[J] then Same := False;
    if Same then Exit(I);
  end;
end;

procedure TPlus3Disk.WriteFile(const AName: string; const Data: TBytes);
var
  Raw: array[0..10] of Byte;
  Error: string;
  Used: TBits;
  Blocks, Entries, Records, I, K, B, FreeEntry, Ext, InEntry, LastExt, Pos_: Integer;
  BlockList: array of Integer;
  EntryList: array of Integer;
  Buf: TBytes;
  E: PByte;
begin
  if not MakeRawName(AName, Raw, Error) then raise EPlus3Error.Create(Error);
  if FindFile(AName) >= 0 then raise EPlus3Error.CreateFmt(_('there is already a file called %s'), [AName]);
  Records := (Length(Data) + 127) div 128;
  Blocks := (Length(Data) + FBlockSize - 1) div FBlockSize;
  Entries := Max(1, (Blocks + PointersPerEntry - 1) div PointersPerEntry);
  // Free blocks and directory entries
  Used := UsedBlocks;
  try
    SetLength(BlockList, Blocks);
    K := 0;
    for B := FDirBlocks to FBlocks - 1 do
      if (K < Blocks) and not Used[B] then
      begin
        BlockList[K] := B;
        Inc(K);
      end;
  finally
    Used.Free;
  end;
  if K < Blocks then
    raise EPlus3Error.CreateFmt(_('not enough space: %d bytes needed, %d free'),
      [Blocks * FBlockSize, FreeBytes]);
  SetLength(EntryList, Entries);
  K := 0;
  for I := 0 to EntryCount - 1 do
    if (K < Entries) and (Entry(I)[0] > 15) then
    begin
      EntryList[K] := I;
      Inc(K);
    end;
  if K < Entries then raise EPlus3Error.Create(_('the directory is full'));
  // Data, padded with ^Z as CP/M does
  SetLength(Buf, FBlockSize);
  for K := 0 to Blocks - 1 do
  begin
    FillChar(Buf[0], FBlockSize, $1A);
    Move(Data[K * FBlockSize], Buf[0], Min(FBlockSize, Length(Data) - K * FBlockSize));
    WriteBlock(BlockList[K], Buf[0]);
  end;
  // Directory entries
  for I := 0 to Entries - 1 do
  begin
    E := Entry(EntryList[I]);
    FillChar(E^, 32, 0);
    E[0] := 0;
    for K := 0 to 10 do E[1 + K] := Raw[K];
    // Records in this entry and the last logical extent it reaches
    InEntry := Min(Records - I * PointersPerEntry * (FBlockSize div 128),
      PointersPerEntry * (FBlockSize div 128));
    if InEntry < 0 then InEntry := 0;
    LastExt := Max(0, (InEntry - 1) div 128);
    Ext := I * (FExtentMask + 1) + LastExt;
    E[12] := Ext and $1F;
    E[14] := Ext shr 5;
    E[15] := InEntry - LastExt * 128;
    for K := 0 to PointersPerEntry - 1 do
    begin
      Pos_ := I * PointersPerEntry + K;
      if Pos_ >= Blocks then Break;
      if FWide then
      begin
        E[16 + K * 2] := BlockList[Pos_] and $FF;
        E[17 + K * 2] := BlockList[Pos_] shr 8;
      end
      else
        E[16 + K] := BlockList[Pos_];
    end;
  end;
  SaveDirectory;
  BuildFileList;
end;

procedure TPlus3Disk.RenameFile(Index: Integer; const NewName: string);
var
  Raw: array[0..10] of Byte;
  Error: string;
  F: TPlus3File;
  I, K, Other: Integer;
  E: PByte;
begin
  if not MakeRawName(NewName, Raw, Error) then raise EPlus3Error.Create(Error);
  Other := FindFile(NewName);
  if (Other >= 0) and (Other <> Index) then
    raise EPlus3Error.CreateFmt(_('there is already a file called %s'), [NewName]);
  F := FFiles[Index];
  for I := 0 to EntryCount - 1 do
  begin
    E := Entry(I);
    if not SameName(E, F) then Continue;
    // Keep the attribute bits (read-only, system, archive)
    for K := 0 to 10 do E[1 + K] := Raw[K] or (E[1 + K] and $80);
  end;
  SaveDirectory;
  BuildFileList;
end;

procedure TPlus3Disk.DeleteFile(Index: Integer);
var
  F: TPlus3File;
  I: Integer;
begin
  F := FFiles[Index];
  for I := 0 to EntryCount - 1 do
    if SameName(Entry(I), F) then Entry(I)[0] := FILLER;
  SaveDirectory;
  BuildFileList;
end;

function TPlus3Disk.GetFile(Index: Integer): TPlus3File;
begin
  Result := FFiles[Index];
end;

function TPlus3Disk.GetCount: Integer;
begin
  Result := Length(FFiles);
end;

end.

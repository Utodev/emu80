{ SamdosFS: the SAMDOS file system on a SAM Coupe disk (80 tracks, 2 sides, 10 sectors of 512 bytes),
  for the disk browser: list the files, read, write, rename and delete them.

  The directory is the first 4 tracks of side 0: 80 entries of 256 bytes, two to a sector. An entry
  has the file type (0 = free; 16 BASIC program, 17 number array, 18 string array, 19 CODE,
  20 SCREEN$; bit 6 hides it, bit 7 protects it), a 10 character name, the number of sectors, the
  track (bit 7 is the side) and sector of its first sector, and a map of the sectors it uses
  (195 bytes, a bit for each sector after the directory, the side-0 tracks first). A file is a
  chain of sectors, each with 510 bytes of data and the track and sector of the next at the end;
  its first 9 bytes are its header: type, length mod 16384 (2), offset (2), 2 unused, pages and
  start page. }
unit SamdosFS;

{$mode objfpc}{$H+}
{$R-}{$Q-}

interface

uses
  SysUtils, Classes, DSK;

const
  SAMDOS_TYPE_BASIC = 16;
  SAMDOS_TYPE_NUMS = 17;
  SAMDOS_TYPE_STRS = 18;
  SAMDOS_TYPE_CODE = 19;
  SAMDOS_TYPE_SCREEN = 20;

  SAMDOS_ENTRIES = 80;
  SAMDOS_DATA = 510;          // bytes of data in a sector

type
  ESamdosError = class(Exception);

  TSamFile = record
    FileType: Byte;           // 16..20 (as in the directory, the bits 6 and 7 apart)
    Hidden, Protected: Boolean;
    Name: string;
    Sectors: Integer;
    Length: Integer;          // of the data, without the header
    Offset: Word;             // where it starts in its page (8000-BFFF), as in the header
    StartPage: Byte;
  end;

  TSamdosDisk = class
  private
    FDisk: TDiskImage;
    FDir: array[0..SAMDOS_ENTRIES - 1, 0..255] of Byte;
    FFiles: array of TSamFile;
    FEntry: array of Integer;     // the directory entry of each file
    function Sector(Track, Side, ID: Integer): PByte;
    procedure LoadDirectory;
    procedure SaveDirectory;
    function GetFile(Index: Integer): TSamFile;
    function GetCount: Integer;
    function Used(Bit: Integer): Boolean;
    function NameOf(Entry: Integer): string;
    function CleanName(const AName: string): string;
  public
    constructor Create(ADisk: TDiskImage);
    function FindFile(const AName: string): Integer;
    { The data of the file, without its 9 byte header }
    function ReadFile(Index: Integer): TBytes;
    { The cylinder of the last sector of the file (where the head is when it has been read) }
    function LastCylinder(Index: Integer): Integer;
    { A file of that type: CODE with its start address (32768 and up in the SAM's address space,
      or an offset in the page) or any other type }
    procedure WriteFile(const AName: string; const Data: TBytes; AType: Byte = SAMDOS_TYPE_CODE;
      Start: Integer = 32768);
    procedure RenameFile(Index: Integer; const NewName: string);
    procedure DeleteFile(Index: Integer);
    function FreeBytes: Integer;
    function TypeName(Index: Integer): string;
    property Count: Integer read GetCount;
    property Files[Index: Integer]: TSamFile read GetFile; default;
  end;

{ Is it a SAMDOS directory (a SAM disk of the usual geometry whose entries make sense) }
function LooksLikeSamdos(Disk: TDiskImage): Boolean;

implementation

uses
  Lang;


const
  BITMAP_OFFSET = 15;
  BITMAP_BYTES = 195;
  TOTAL_SECTORS = 80 * 2 * 10 - 40;

{ Where the sector number Bit (from the first after the directory) is: the side-0 tracks first }
procedure Where(Bit: Integer; out Track, Side, ID: Integer);
begin
  Track := Bit div 10 + 4;
  Side := 0;
  if Track >= 80 then
  begin
    Dec(Track, 80);
    Side := 1;
  end;
  ID := Bit mod 10 + 1;
end;

function TSamdosDisk.Sector(Track, Side, ID: Integer): PByte;
var
  T: PTrack;
  I: Integer;
begin
  Result := nil;
  if (Track < 0) or (Track >= FDisk.Cylinders) or (Side < 0) or (Side >= FDisk.Sides) then Exit;
  T := FDisk.Track(Track, Side);
  if (T = nil) or not T^.Formatted then Exit;
  for I := 0 to High(T^.Sectors) do
    if (T^.Sectors[I].R = ID) and (Length(T^.Sectors[I].Data) >= 512) then Exit(@T^.Sectors[I].Data[0]);
end;

function LooksLikeSamdos(Disk: TDiskImage): Boolean;
var
  T: PTrack;
  I: Integer;
begin
  Result := False;
  if (Disk.Cylinders < 80) or (Disk.Sides < 2) then Exit;
  T := Disk.Track(0, 0);
  if (T = nil) or not T^.Formatted or (Length(T^.Sectors) <> 10) then Exit;
  for I := 0 to 9 do
    if (Length(T^.Sectors[I].Data) <> 512) then Exit;
  Result := True;
end;

constructor TSamdosDisk.Create(ADisk: TDiskImage);
begin
  inherited Create;
  FDisk := ADisk;
  if not LooksLikeSamdos(FDisk) then raise ESamdosError.Create(_('not a SAM Coupe disk'));
  LoadDirectory;
end;

function TSamdosDisk.NameOf(Entry: Integer): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to 10 do
    if FDir[Entry, I] >= 32 then Result := Result + Chr(FDir[Entry, I] and $7F) else Result := Result + ' ';
  Result := TrimRight(Result);
end;

procedure TSamdosDisk.LoadDirectory;
var
  S, E, H: Integer;
  P: PByte;
  F: TSamFile;
begin
  FillChar(FDir, SizeOf(FDir), 0);
  for S := 1 to 10 do
  begin
    P := Sector(0, 0, S);
    if P = nil then raise ESamdosError.Create(_('the directory can''t be read'));
    for H := 0 to 1 do
      Move((P + H * 256)^, FDir[(S - 1) * 2 + H, 0], 256);
  end;
  SetLength(FFiles, 0);
  SetLength(FEntry, 0);
  for E := 0 to SAMDOS_ENTRIES - 1 do
    if (FDir[E, 0] and $3F) <> 0 then
    begin
      F.FileType := FDir[E, 0] and $3F;
      F.Hidden := (FDir[E, 0] and $40) <> 0;
      F.Protected := (FDir[E, 0] and $80) <> 0;
      F.Name := NameOf(E);
      F.Sectors := FDir[E, 11] * 256 + FDir[E, 12];
      // The header is at the start of its first sector: length mod 16384, offset, pages, start page
      F.Length := 0;
      F.Offset := 0;
      F.StartPage := 0;
      P := Sector(FDir[E, 13] and $7F, (FDir[E, 13] shr 7) and 1, FDir[E, 14]);
      if (FDir[E, 13] <> 0) and (P <> nil) then
      begin
        F.Length := P[1] + (P[2] and $3F) * 256 + P[7] * 16384;
        F.Offset := P[3] + P[4] * 256;
        F.StartPage := P[8];
      end;
      SetLength(FFiles, Length(FFiles) + 1);
      FFiles[High(FFiles)] := F;
      SetLength(FEntry, Length(FEntry) + 1);
      FEntry[High(FEntry)] := E;
    end;
end;

procedure TSamdosDisk.SaveDirectory;
var
  S, H: Integer;
  P: PByte;
begin
  for S := 1 to 10 do
  begin
    P := Sector(0, 0, S);
    for H := 0 to 1 do
      Move(FDir[(S - 1) * 2 + H, 0], (P + H * 256)^, 256);
  end;
  FDisk.MarkModified;
  LoadDirectory;
end;

function TSamdosDisk.GetCount: Integer;
begin
  Result := Length(FFiles);
end;

function TSamdosDisk.GetFile(Index: Integer): TSamFile;
begin
  Result := FFiles[Index];
end;

function TSamdosDisk.TypeName(Index: Integer): string;
begin
  case FFiles[Index].FileType of
    SAMDOS_TYPE_BASIC: Result := 'BASIC';
    SAMDOS_TYPE_NUMS: Result := _('Number array');
    SAMDOS_TYPE_STRS: Result := _('String array');
    SAMDOS_TYPE_CODE: Result := 'CODE';
    SAMDOS_TYPE_SCREEN: Result := 'SCREEN$';
  else
    Result := _('Type ') + IntToStr(FFiles[Index].FileType);
  end;
end;

{ Is the sector number Bit (from the first after the directory) in any file }
function TSamdosDisk.Used(Bit: Integer): Boolean;
var
  E: Integer;
begin
  Result := False;
  for E := 0 to SAMDOS_ENTRIES - 1 do
    if ((FDir[E, 0] and $3F) <> 0) and ((FDir[E, BITMAP_OFFSET + Bit div 8] shr (Bit mod 8)) and 1 <> 0) then
      Exit(True);
end;

function TSamdosDisk.FreeBytes: Integer;
var
  I, N: Integer;
begin
  N := 0;
  for I := 0 to TOTAL_SECTORS - 1 do
    if not Used(I) then Inc(N);
  Result := N * SAMDOS_DATA;
end;

function TSamdosDisk.CleanName(const AName: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(AName) do
    if Ord(AName[I]) in [32..126] then Result := Result + AName[I];
  Result := TrimRight(Copy(Result, 1, 10));
  if Result = '' then raise ESamdosError.Create(_('a SAMDOS file needs a name'));
end;

function TSamdosDisk.FindFile(const AName: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(FFiles) do
    if SameText(FFiles[I].Name, TrimRight(AName)) then Exit(I);
end;

function TSamdosDisk.ReadFile(Index: Integer): TBytes;
var
  E, Track, Side, ID, NextT, NextS, Got, N, Total, Guard: Integer;
  P: PByte;
  All: TBytes;
begin
  E := FEntry[Index];
  Track := FDir[E, 13];
  ID := FDir[E, 14];
  SetLength(All, 0);
  Got := 0;
  Guard := 0;
  while (Track <> 0) and (Guard < 1600) do
  begin
    Inc(Guard);
    Side := (Track shr 7) and 1;
    P := Sector(Track and $7F, Side, ID);
    if P = nil then raise ESamdosError.CreateFmt(_('sector %d of track %d can''t be read'), [ID, Track and $7F]);
    SetLength(All, Got + SAMDOS_DATA);
    Move(P^, All[Got], SAMDOS_DATA);
    Inc(Got, SAMDOS_DATA);
    NextT := P[510];
    NextS := P[511];
    Track := NextT;
    ID := NextS;
  end;
  Total := FFiles[Index].Length;
  if Total > Got - 9 then Total := Got - 9;
  if Total < 0 then Total := 0;
  SetLength(Result, Total);
  N := Total;
  if N > 0 then Move(All[9], Result[0], N);
end;

function TSamdosDisk.LastCylinder(Index: Integer): Integer;
var
  E, Track, ID, Guard: Integer;
  P: PByte;
begin
  E := FEntry[Index];
  Track := FDir[E, 13];
  ID := FDir[E, 14];
  Result := Track and $7F;
  Guard := 0;
  while (Track <> 0) and (Guard < 1600) do
  begin
    Inc(Guard);
    Result := Track and $7F;
    P := Sector(Track and $7F, (Track shr 7) and 1, ID);
    if P = nil then Exit;
    Track := P[510];
    ID := P[511];
  end;
end;

procedure TSamdosDisk.WriteFile(const AName: string; const Data: TBytes; AType: Byte; Start: Integer);
var
  Name: string;
  E, I, Need, Len, Pos, Bit, Page: Integer;
  Bits: array of Integer;
  Body: TBytes;
  P: PByte;
  Track, Side, ID: Integer;
  Hdr: array[0..8] of Byte;
  Offset: Integer;
begin
  Name := CleanName(AName);
  if FindFile(Name) >= 0 then raise ESamdosError.Create('there is a file called ' + Name + ' already');
  E := -1;
  for I := 0 to SAMDOS_ENTRIES - 1 do
    if (FDir[I, 0] and $3F) = 0 then
    begin
      E := I;
      Break;
    end;
  if E < 0 then raise ESamdosError.Create(_('the directory is full (80 files)'));
  Len := Length(Data);
  if Len > 16 * 16384 + 16383 then raise ESamdosError.Create(_('the file is too long for SAMDOS'));
  // The file is the 9 byte header and the data
  Offset := $8000 or (Start and $3FFF);
  Hdr[0] := AType;
  Hdr[1] := Len and 255;
  Hdr[2] := (Len shr 8) and $3F;
  Hdr[3] := Offset and 255;
  Hdr[4] := Offset shr 8;
  Hdr[5] := $FF;
  Hdr[6] := $FF;
  Hdr[7] := Len shr 14;
  Page := 1;
  Hdr[8] := Page;
  SetLength(Body, Len + 9);
  Move(Hdr[0], Body[0], 9);
  if Len > 0 then Move(Data[0], Body[9], Len);
  Need := (Len + 9 + SAMDOS_DATA - 1) div SAMDOS_DATA;
  // The sectors: the first free ones
  SetLength(Bits, 0);
  Bit := 0;
  while (Length(Bits) < Need) and (Bit < TOTAL_SECTORS) do
  begin
    if not Used(Bit) then
    begin
      SetLength(Bits, Length(Bits) + 1);
      Bits[High(Bits)] := Bit;
    end;
    Inc(Bit);
  end;
  if Length(Bits) < Need then raise ESamdosError.Create(_('the disk is full'));
  // Write the chain
  for I := 0 to Need - 1 do
  begin
    Where(Bits[I], Track, Side, ID);
    P := Sector(Track, Side, ID);
    if P = nil then raise ESamdosError.Create(_('the disk can''t be written'));
    FillChar(P^, 512, 0);
    Pos := I * SAMDOS_DATA;
    Len := Length(Body) - Pos;
    if Len > SAMDOS_DATA then Len := SAMDOS_DATA;
    Move(Body[Pos], P^, Len);
    if I < Need - 1 then
    begin
      Where(Bits[I + 1], Track, Side, ID);
      P[510] := Track or (Side shl 7);
      P[511] := ID;
    end;
  end;
  // The directory entry
  FillChar(FDir[E, 0], 256, 0);
  FDir[E, 0] := AType;
  for I := 1 to 10 do
    if I <= Length(Name) then FDir[E, I] := Ord(Name[I]) else FDir[E, I] := 32;
  FDir[E, 11] := Need shr 8;
  FDir[E, 12] := Need and 255;
  Where(Bits[0], Track, Side, ID);
  FDir[E, 13] := Track or (Side shl 7);
  FDir[E, 14] := ID;
  for I := 0 to High(Bits) do
    FDir[E, BITMAP_OFFSET + Bits[I] div 8] := FDir[E, BITMAP_OFFSET + Bits[I] div 8] or (1 shl (Bits[I] mod 8));
  Move(Hdr[0], FDir[E, 211], 9);
  for I := 220 to 230 do FDir[E, I] := 32;
  for I := 231 to 235 do FDir[E, I] := $FF;
  SaveDirectory;
end;

procedure TSamdosDisk.RenameFile(Index: Integer; const NewName: string);
var
  E, I, Other: Integer;
  Name: string;
begin
  Name := CleanName(NewName);
  Other := FindFile(Name);
  if (Other >= 0) and (Other <> Index) then raise ESamdosError.Create('there is a file called ' + Name + ' already');
  E := FEntry[Index];
  for I := 1 to 10 do
    if I <= Length(Name) then FDir[E, I] := Ord(Name[I]) else FDir[E, I] := 32;
  SaveDirectory;
end;

procedure TSamdosDisk.DeleteFile(Index: Integer);
begin
  // A free entry has type 0; its sectors are free with it
  FDir[FEntry[Index], 0] := 0;
  SaveDirectory;
end;

end.

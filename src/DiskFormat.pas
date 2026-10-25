{ DiskFormat: what is in a disk image file, by its contents and not by its
  name (a .dsk can be a CPC's, a +3's or a SAM Coupe's, in two or three
  layouts), and the loading of those the SAM Coupe uses: MGT (raw, 80
  cylinders x 2 sides x 10 sectors of 512 bytes, the sides alternating),
  SAD (SAm Disk, its own header and the sides one after the other), raw CP/M
  (80 x 2 x 9 x 512) and the extended DSK a tool like SAMdisk writes.

  The kinds are told apart by the geometry: a SAM disk has 10 sectors of 512
  bytes in a track (numbered from 1) and 80 or so cylinders; a CPC's AMSDOS
  formats have the sector numbers C1-C9 (data) or 41-49 (system), a +3's
  and the CPC's IBM format 1-9 of 512 bytes in 40 cylinders. }
unit DiskFormat;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, DSK;

type
  TDiskKind = (dkSAM, dkCPC, dkPlus3, dkOther);

  { Why a file was not loaded }
  TDiskProblem = (dpNone, dpUnreadable, dpCompressed, dpUnknown, dpCorrupt);

  { The machines whose disk controllers differ in what they read }
  TDiskMachine = (dmSpectrum, dmCPC, dmSAM);

const
  RAW_SAM_SIZE = 80 * 2 * 10 * 512;       // an MGT disk: 819200 bytes
  RAW_CPM_SIZE = 80 * 2 * 9 * 512;        // 737280 bytes

{ The disk's kind from its geometry }
function ClassifyDisk(Disk: TDiskImage): TDiskKind;
function DiskKindName(Kind: TDiskKind): string;
{ Whether a machine can use a disk (Msg says why not): the SAM Coupe's controller
  reads whatever is on the disk, its software (CP/M, for one) knows the CPC and +3
  formats; a SAM Coupe disk (80 cylinders of 10 sectors of 512 bytes) is not one
  an Amstrad CPC or a +3 reads. }
function CheckDiskForMachine(Disk: TDiskImage; const FileName: string; Machine: TDiskMachine;
  out Msg: string): Boolean;
{ Loads an image of any of the formats above. Returns nil if it can't, saying
  why: Problem and a message for the user in Error. The file is only read. }
function LoadDiskImage(const FileName: string; out Problem: TDiskProblem; out Error: string): TDiskImage;
{ A new, empty SAM disk: 80 cylinders of 2 sides with 10 sectors of 512 bytes, all zero
  (an empty directory; FORMAT or SAMDOS' own tools put a name on it) }
function NewSamDisk: TDiskImage;
{ Saves a SAM disk (80 cylinders, 2 sides, 10 sectors of 512 bytes) as an MGT
  image, raw. False if the disk doesn't have that geometry. }
function SaveMGT(Disk: TDiskImage; const FileName: string): Boolean;
{ Saves a disk with the format its file name says: .mgt (raw, as SaveMGT), .sad
  (SAm Disk) or anything else as an extended DSK. Returns '' or what went wrong:
  a disk that doesn't have the geometry of an MGT or SAD image can't be one. }
function SaveDiskImage(Disk: TDiskImage; const FileName: string): string;

implementation

function CheckDiskForMachine(Disk: TDiskImage; const FileName: string; Machine: TDiskMachine;
  out Msg: string): Boolean;
const
  NAMES: array[TDiskMachine] of string = ('ZX Spectrum +3', 'Amstrad CPC', 'SAM Coupe');
begin
  Msg := '';
  Result := True;
  if (Machine <> dmSAM) and (ClassifyDisk(Disk) = dkSAM) then
  begin
    Msg := Format('%s is a SAM Coupe disk (%d cylinders, 10 sectors of 512 bytes a track): ' +
      'its format isn''t one the %s reads. Choose the SAM Coupe in the machine menu to use it.',
      [ExtractFileName(FileName), Disk.Cylinders, NAMES[Machine]]);
    Result := False;
  end;
end;

const
  SAD_SIGNATURE = 'Aley''s disk backup';
  SAD_HEADER = 22;

function ClassifyDisk(Disk: TDiskImage): TDiskKind;
var
  Trk: PTrack;
  I, N512: Integer;
  AllSam, HighIds: Boolean;
begin
  Result := dkOther;
  if (Disk = nil) or (Disk.Cylinders = 0) then Exit;
  Trk := Disk.Track(0, 0);
  if (Trk = nil) or not Trk^.Formatted or (Length(Trk^.Sectors) = 0) then Exit;
  N512 := 0;
  AllSam := True;
  HighIds := False;
  for I := 0 to High(Trk^.Sectors) do
  begin
    if Trk^.Sectors[I].N = 2 then Inc(N512);
    if (Trk^.Sectors[I].R < 1) or (Trk^.Sectors[I].R > 10) then AllSam := False;
    if Trk^.Sectors[I].R >= $41 then HighIds := True;
  end;
  if HighIds and (N512 = Length(Trk^.Sectors)) then Exit(dkCPC);
  if (Length(Trk^.Sectors) = 10) and (N512 = 10) and AllSam and (Disk.Cylinders >= 77) then Exit(dkSAM);
  if (N512 = Length(Trk^.Sectors)) and (Length(Trk^.Sectors) = 9) and (Disk.Cylinders <= 42) then Exit(dkPlus3);
end;

function DiskKindName(Kind: TDiskKind): string;
begin
  case Kind of
    dkSAM: Result := 'SAM Coupe';
    dkCPC: Result := 'Amstrad CPC';
    dkPlus3: Result := 'Spectrum +3 / CPC (IBM format)';
  else
    Result := 'unknown';
  end;
end;

{ A disk of Cyls x Sides x Count sectors of 512 bytes, from raw sector data;
  the sides alternate (SideMajor false: MGT) or one side after the other (SAD) }
function RawDisk(const Data: TBytes; Start, Cyls, Sides, Count, SecSize: Integer;
  Alternate: Boolean): TDiskImage;
var
  C, S, I, Pos, Sz: Integer;
  IDs: array of Byte;
  Trk: PTrack;
  N: Byte;
begin
  N := 0;
  Sz := 128;
  while Sz < SecSize do
  begin
    Sz := Sz * 2;
    Inc(N);
  end;
  Result := TDiskImage.Create;
  Result.CreateBlank(Cyls, Sides);
  SetLength(IDs, Count * 4);
  for C := 0 to Cyls - 1 do
    for S := 0 to Sides - 1 do
    begin
      for I := 0 to Count - 1 do
      begin
        IDs[I * 4] := C;
        IDs[I * 4 + 1] := S;
        IDs[I * 4 + 2] := I + 1;
        IDs[I * 4 + 3] := N;
      end;
      Result.FormatTrack(C, S, IDs, Count, N, $24, 0);
      Trk := Result.Track(C, S);
      if Alternate then Pos := Start + ((C * Sides + S) * Count) * SecSize
      else Pos := Start + ((S * Cyls + C) * Count) * SecSize;
      for I := 0 to Count - 1 do
      begin
        Move(Data[Pos + I * SecSize], Trk^.Sectors[I].Data[0], SecSize);
      end;
    end;
  // As made: nothing in it has been changed by anyone (a file loaded from it is as it is on disk)
  Result.MarkSaved('');
end;

function NewSamDisk: TDiskImage;
var
  Blank: TBytes;
begin
  SetLength(Blank, RAW_SAM_SIZE);
  FillChar(Blank[0], RAW_SAM_SIZE, 0);
  Result := RawDisk(Blank, 0, 80, 2, 10, 512, True);
  Result.MarkSaved('');
  Result.MarkModified;
end;

function ReadAll(const FileName: string): TBytes;
var
  F: TFileStream;
begin
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, F.Size);
    if F.Size > 0 then F.ReadBuffer(Result[0], F.Size);
  finally
    F.Free;
  end;
end;

function LoadDiskImage(const FileName: string; out Problem: TDiskProblem; out Error: string): TDiskImage;
var
  Data: TBytes;
  Sig: string;
  Cyls, Sides, Count, SecSize, Expected: Integer;
  Disk: TDiskImage;
  S: TMemoryStream;
begin
  Result := nil;
  Problem := dpNone;
  Error := '';
  try
    Data := ReadAll(FileName);
  except
    on E: Exception do
    begin
      Problem := dpUnreadable;
      Error := 'Could not read ' + ExtractFileName(FileName) + ': ' + E.Message;
      Exit;
    end;
  end;
  Sig := '';
  if Length(Data) = 0 then
  begin
    Problem := dpCorrupt;
    Error := ExtractFileName(FileName) + ' is empty.';
    Exit;
  end;
  SetString(Sig, PChar(@Data[0]), Min(Length(Data), 24));
  Disk := nil;
  try
    if (Length(Data) >= 4) and (Data[0] = $50) and (Data[1] = $4B) and (Data[2] = 3) and (Data[3] = 4) then
    begin
      Problem := dpCompressed;
      Error := ExtractFileName(FileName) + ' is a zip file, not a disk image: unzip it first.';
    end
    else if (Length(Data) >= 2) and (Data[0] = $1F) and (Data[1] = $8B) then
    begin
      Problem := dpCompressed;
      Error := ExtractFileName(FileName) + ' is a gzip file, not a disk image: unzip it first.';
    end
    else if (Copy(Sig, 1, 8) = 'MV - CPC') or (Copy(Sig, 1, 8) = 'EXTENDED') then
    begin
      // CPC DSK or extended DSK: whose is told by its tracks
      S := TMemoryStream.Create;
      try
        S.WriteBuffer(Data[0], Length(Data));
        S.Position := 0;
        Disk := TDiskImage.Create;
        Disk.LoadFromStream(S);
        Disk.FileName := FileName;
        Disk.WriteProtected := (FileGetAttr(FileName) and faReadOnly) <> 0;
      finally
        S.Free;
      end;
    end
    else if Copy(Sig, 1, Length(SAD_SIGNATURE)) = SAD_SIGNATURE then
    begin
      if Length(Data) < SAD_HEADER then
      begin
        Problem := dpCorrupt;
        Error := ExtractFileName(FileName) + ' is a SAD image cut short.';
      end
      else
      begin
        Sides := Data[18];
        Cyls := Data[19];
        Count := Data[20];
        SecSize := Data[21] * 64;
        Expected := SAD_HEADER + Sides * Cyls * Count * SecSize;
        if (Sides < 1) or (Sides > 2) or (Cyls < 1) or (Cyls > 83) or (Count < 1) or (SecSize < 128) or
           (SecSize > 1024) or (Length(Data) < Expected) then
        begin
          Problem := dpCorrupt;
          Error := Format('%s is a corrupt SAD image (%d sides, %d cylinders, %d sectors of %d bytes, %d bytes long).',
            [ExtractFileName(FileName), Sides, Cyls, Count, SecSize, Length(Data)]);
        end
        else
        begin
          Disk := RawDisk(Data, SAD_HEADER, Cyls, Sides, Count, SecSize, False);
          Disk.FileName := FileName;
        end;
      end;
    end
    else if Length(Data) = RAW_SAM_SIZE then
    begin
      Disk := RawDisk(Data, 0, 80, 2, 10, 512, True);
      Disk.FileName := FileName;
    end
    else if Length(Data) = RAW_CPM_SIZE then
    begin
      Disk := RawDisk(Data, 0, 80, 2, 9, 512, True);
      Disk.FileName := FileName;
    end
    else
    begin
      Problem := dpUnknown;
      Error := Format('%s (%d bytes) is not a disk image emu80 knows: DSK, MGT, SAD or raw 800K/720K.',
        [ExtractFileName(FileName), Length(Data)]);
    end;
  except
    on E: Exception do
    begin
      FreeAndNil(Disk);
      Problem := dpCorrupt;
      Error := ExtractFileName(FileName) + ' is a corrupt disk image: ' + E.Message;
    end;
  end;
  if Disk <> nil then
  begin
    Disk.WriteProtected := (FileGetAttr(FileName) and faReadOnly) <> 0;
    Result := Disk;
  end;
end;

function SaveMGT(Disk: TDiskImage; const FileName: string): Boolean;
var
  F: TFileStream;
  C, S, I: Integer;
  Trk: PTrack;
begin
  Result := False;
  if (Disk = nil) or (Disk.Cylinders < 80) or (Disk.Sides < 2) then Exit;
  // Every sector must be there to be written in its place
  for C := 0 to 79 do
    for S := 0 to 1 do
    begin
      Trk := Disk.Track(C, S);
      if (Trk = nil) or (Length(Trk^.Sectors) <> 10) then Exit;
      for I := 0 to 9 do
        if (Trk^.Sectors[I].R <> I + 1) or (Length(Trk^.Sectors[I].Data) <> 512) then Exit;
    end;
  F := TFileStream.Create(FileName, fmCreate);
  try
    for C := 0 to 79 do
      for S := 0 to 1 do
      begin
        Trk := Disk.Track(C, S);
        for I := 0 to 9 do F.WriteBuffer(Trk^.Sectors[I].Data[0], 512);
      end;
  finally
    F.Free;
  end;
  Result := True;
end;


{ A SAD image: 80 cylinders x 2 sides x 10 sectors of 512 bytes, or whatever the
  disk's uniform geometry is; the sides one after the other }
function SaveSAD(Disk: TDiskImage; const FileName: string): Boolean;
var
  F: TFileStream;
  C, S, I, Cyls, Sides, Count, Size: Integer;
  Trk: PTrack;
  H: array[0..21] of Byte;
begin
  Result := False;
  if (Disk = nil) or (Disk.Cylinders = 0) then Exit;
  Cyls := Disk.Cylinders;
  Sides := Disk.Sides;
  Trk := Disk.Track(0, 0);
  if (Trk = nil) or (Length(Trk^.Sectors) = 0) then Exit;
  Count := Length(Trk^.Sectors);
  Size := Length(Trk^.Sectors[0].Data);
  // Every track must have the same sectors, numbered from 1
  for S := 0 to Sides - 1 do
    for C := 0 to Cyls - 1 do
    begin
      Trk := Disk.Track(C, S);
      if (Trk = nil) or (Length(Trk^.Sectors) <> Count) then Exit;
      for I := 0 to Count - 1 do
        if (Trk^.Sectors[I].R <> I + 1) or (Length(Trk^.Sectors[I].Data) <> Size) then Exit;
    end;
  FillChar(H, SizeOf(H), 0);
  Move(SAD_SIGNATURE[1], H[0], Length(SAD_SIGNATURE));
  H[18] := Sides;
  H[19] := Cyls;
  H[20] := Count;
  H[21] := Size div 64;
  F := TFileStream.Create(FileName, fmCreate);
  try
    F.WriteBuffer(H, SizeOf(H));
    for S := 0 to Sides - 1 do
      for C := 0 to Cyls - 1 do
      begin
        Trk := Disk.Track(C, S);
        for I := 0 to Count - 1 do F.WriteBuffer(Trk^.Sectors[I].Data[0], Size);
      end;
  finally
    F.Free;
  end;
  Result := True;
end;

function SaveDiskImage(Disk: TDiskImage; const FileName: string): string;
var
  Ext: string;
begin
  Result := '';
  Ext := LowerCase(ExtractFileExt(FileName));
  try
    if Ext = '.mgt' then
    begin
      if not SaveMGT(Disk, FileName) then
        Result := 'This disk can''t be saved as an MGT image: it doesn''t have 80 cylinders of 2 sides ' +
          'with 10 sectors of 512 bytes. Save it as a .dsk.';
    end
    else if Ext = '.sad' then
    begin
      if not SaveSAD(Disk, FileName) then
        Result := 'This disk can''t be saved as a SAD image: its tracks don''t all have the same sectors. ' +
          'Save it as a .dsk.';
    end
    else
      Disk.SaveToFile(FileName);
    if (Result = '') and ((Ext = '.mgt') or (Ext = '.sad')) then Disk.MarkSaved(FileName);
  except
    on E: Exception do Result := 'Could not save ' + ExtractFileName(FileName) + ': ' + E.Message;
  end;
end;

end.

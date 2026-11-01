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
  TDiskMachine = (dmSpectrum, dmCPC, dmSAM, dmMSX);

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
{ A new MSX disk, formatted (FAT12, empty): 720K (80 cylinders, 2 sides) or 360K (40 cylinders, 2 sides) }
function NewMsxDisk(Double720: Boolean): TDiskImage;
{ Saves a disk as raw sectors (what an MSX .dsk is): cylinder by cylinder, side 0 then side 1 }
function SaveRawDisk(Disk: TDiskImage; const FileName: string): Boolean;
{ Whether a disk is made of 9 sectors of 512 bytes in all its tracks (what an MSX reads) }
function MsxGeometryOK(Disk: TDiskImage): Boolean;
{ Saves a SAM disk (80 cylinders, 2 sides, 10 sectors of 512 bytes) as an MGT
  image, raw. False if the disk doesn't have that geometry. }
function SaveMGT(Disk: TDiskImage; const FileName: string): Boolean;
{ Saves a disk with the format its file name says: .mgt (raw, as SaveMGT), .sad
  (SAm Disk) or anything else as an extended DSK. Returns '' or what went wrong:
  a disk that doesn't have the geometry of an MGT or SAD image can't be one. }
function SaveDiskImage(Disk: TDiskImage; const FileName: string): string;

implementation

uses
  Lang;


{ A disk whose tracks are all 9 sectors of 512 bytes, numbered from 1, in at most 83 cylinders }
function MsxGeometry(Disk: TDiskImage): Boolean;
var
  C, S, I: Integer;
  Trk: PTrack;
begin
  Result := False;
  if (Disk = nil) or (Disk.Cylinders < 35) or (Disk.Cylinders > 83) then Exit;
  for C := 0 to Disk.Cylinders - 1 do
    for S := 0 to Disk.Sides - 1 do
    begin
      Trk := Disk.Track(C, S);
      if (Trk = nil) or not Trk^.Formatted or (Length(Trk^.Sectors) <> 9) then Exit;
      for I := 0 to 8 do
        if (Trk^.Sectors[I].N <> 2) or (Trk^.Sectors[I].R < 1) or (Trk^.Sectors[I].R > 9) then Exit;
    end;
  Result := True;
end;

function CheckDiskForMachine(Disk: TDiskImage; const FileName: string; Machine: TDiskMachine;
  out Msg: string): Boolean;
const
  NAMES: array[TDiskMachine] of string = ('ZX Spectrum +3', 'Amstrad CPC', 'SAM Coupe', 'MSX');
begin
  Msg := '';
  Result := True;
  // The MSX reads 9 sectors of 512 bytes a track, in 40 or 80 cylinders (what the PC's and CP/M's raw
  // images are); what is on it (a FAT12 file system) is for MSX-DOS to make sense of
  if Machine = dmMSX then
  begin
    if (ClassifyDisk(Disk) in [dkSAM, dkCPC]) or not MsxGeometry(Disk) then
    begin
      Msg := Format(_('%s is not a disk the MSX reads: it needs 9 sectors of 512 bytes a track (a 720K or 360K ' +
        'raw image or a +3 disk), and this one has %d cylinders and is %s.'),
        [ExtractFileName(FileName), Disk.Cylinders, Format(_('%s format'), [DiskKindName(ClassifyDisk(Disk))])]);
      Result := False;
    end;
    Exit;
  end;
  if (Machine <> dmSAM) and (ClassifyDisk(Disk) = dkSAM) then
  begin
    Msg := Format(_('%s is a SAM Coupe disk (%d cylinders, 10 sectors of 512 bytes a track): ' +
      'its format isn''t one the %s reads. Choose the SAM Coupe in the machine menu to use it.'),
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

{ The geometry of a raw image of a PC-style floppy, from its size and, where a size can be two disks (360K:
  40 cylinders of 2 sides or 80 of 1), the boot sector's media byte and sector counts }
function RawGeometry(const Data: TBytes; out Cyls, Sides, Count: Integer): Boolean;
var
  Media: Byte;
begin
  Result := True;
  Count := 9;
  Media := 0;
  if Length(Data) >= 512 then Media := Data[21];
  case Length(Data) of
    737280: begin Cyls := 80; Sides := 2; end;
    368640:
      if (Media = $F8) then begin Cyls := 80; Sides := 1; end
      else begin Cyls := 40; Sides := 2; end;
    184320: begin Cyls := 40; Sides := 1; end;
    327680: begin Cyls := 40; Sides := 2; Count := 8; end;
    163840: begin Cyls := 40; Sides := 1; Count := 8; end;
  else
    Result := False;
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
      Error := Format(_('Could not read %s: %s'), [ExtractFileName(FileName), E.Message]);
      Exit;
    end;
  end;
  Sig := '';
  if Length(Data) = 0 then
  begin
    Problem := dpCorrupt;
    Error := Format(_('%s is empty.'), [ExtractFileName(FileName)]);
    Exit;
  end;
  SetString(Sig, PChar(@Data[0]), Min(Length(Data), 24));
  Disk := nil;
  try
    if (Length(Data) >= 4) and (Data[0] = $50) and (Data[1] = $4B) and (Data[2] = 3) and (Data[3] = 4) then
    begin
      Problem := dpCompressed;
      Error := Format(_('%s is a zip file, not a disk image: unzip it first.'), [ExtractFileName(FileName)]);
    end
    else if (Length(Data) >= 2) and (Data[0] = $1F) and (Data[1] = $8B) then
    begin
      Problem := dpCompressed;
      Error := Format(_('%s is a gzip file, not a disk image: unzip it first.'), [ExtractFileName(FileName)]);
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
        Error := Format(_('%s is a SAD image cut short.'), [ExtractFileName(FileName)]);
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
          Error := Format(_('%s is a corrupt SAD image (%d sides, %d cylinders, %d sectors of %d bytes, %d bytes long).'),
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
    else if RawGeometry(Data, Cyls, Sides, Count) then
    begin
      // The raw image of a 720K, 360K or other PC-style floppy: an MSX or CP/M disk
      Disk := RawDisk(Data, 0, Cyls, Sides, Count, 512, True);
      Disk.RawImage := True;
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
      Error := Format(_('%s is a corrupt disk image: %s'), [ExtractFileName(FileName), E.Message]);
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

function MsxGeometryOK(Disk: TDiskImage): Boolean;
begin
  Result := MsxGeometry(Disk);
end;

function SaveRawDisk(Disk: TDiskImage; const FileName: string): Boolean;
var
  F: TFileStream;
  C, S, I: Integer;
  Trk: PTrack;
begin
  Result := False;
  if (Disk = nil) or (Disk.Cylinders = 0) then Exit;
  for C := 0 to Disk.Cylinders - 1 do
    for S := 0 to Disk.Sides - 1 do
    begin
      Trk := Disk.Track(C, S);
      if (Trk = nil) or not Trk^.Formatted or (Length(Trk^.Sectors) = 0) then Exit;
      for I := 0 to High(Trk^.Sectors) do
        if (Trk^.Sectors[I].R <> I + 1) or (Length(Trk^.Sectors[I].Data) <> Length(Trk^.Sectors[0].Data)) then Exit;
    end;
  F := TFileStream.Create(FileName, fmCreate);
  try
    for C := 0 to Disk.Cylinders - 1 do
      for S := 0 to Disk.Sides - 1 do
      begin
        Trk := Disk.Track(C, S);
        for I := 0 to High(Trk^.Sectors) do F.WriteBuffer(Trk^.Sectors[I].Data[0], Length(Trk^.Sectors[I].Data));
      end;
  finally
    F.Free;
  end;
  Result := True;
end;

{ The boot sector of a blank MSX floppy: the BPB of a 720K or 360K double-sided disk, FAT12, and a boot program
  that returns at once (so the disk is not a system disk) }
function NewMsxDisk(Double720: Boolean): TDiskImage;
var
  Raw: TBytes;
  Cyls, Total, FatSecs, RootEntries, Media: Integer;
  I: Integer;
begin
  if Double720 then
  begin
    Cyls := 80; Total := 1440; FatSecs := 3; RootEntries := 112; Media := $F9;
  end
  else
  begin
    Cyls := 40; Total := 720; FatSecs := 2; RootEntries := 112; Media := $FD;
  end;
  SetLength(Raw, Total * 512);
  FillChar(Raw[0], Length(Raw), 0);
  // The sector 0: JMP, OEM name, BPB
  Raw[0] := $EB; Raw[1] := $FE; Raw[2] := $90;
  Move(PChar('emu80   ')^, Raw[3], 8);
  Raw[11] := 0; Raw[12] := 2;                 // 512 bytes a sector
  Raw[13] := 2;                               // 2 sectors a cluster
  Raw[14] := 1; Raw[15] := 0;                 // 1 reserved sector
  Raw[16] := 2;                               // 2 FATs
  Raw[17] := RootEntries and $FF; Raw[18] := RootEntries shr 8;
  Raw[19] := Total and $FF; Raw[20] := Total shr 8;
  Raw[21] := Media;
  Raw[22] := FatSecs; Raw[23] := 0;
  Raw[24] := 9; Raw[25] := 0;                 // 9 sectors a track
  Raw[26] := 2; Raw[27] := 0;                 // 2 heads
  Raw[28] := 0; Raw[29] := 0;                 // no hidden sectors
  Raw[$1E] := $D0;                            // RET NC ... the boot code at 001Eh does nothing
  Raw[$1F] := $C9;                            // RET
  // The FATs: the media byte and the two end-of-chain entries
  for I := 0 to 1 do
  begin
    Raw[512 * (1 + I * FatSecs)] := Media;
    Raw[512 * (1 + I * FatSecs) + 1] := $FF;
    Raw[512 * (1 + I * FatSecs) + 2] := $FF;
  end;
  Result := RawDisk(Raw, 0, Cyls, 2, 9, 512, True);
  Result.RawImage := True;
  Result.MarkSaved('');
  Result.MarkModified;
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
    else if Disk.RawImage and (Ext <> '.dsk') and (Ext <> '.img') then
      Disk.SaveToFile(FileName)
    else if Disk.RawImage then
    begin
      // A raw disk (MSX, CP/M) goes back as it came: sectors and nothing else
      if not SaveRawDisk(Disk, FileName) then
        Result := 'This disk can''t be saved as a raw image: its sectors are not numbered from 1 in every track.';
    end
    else
      Disk.SaveToFile(FileName);
    if (Result = '') and ((Ext = '.mgt') or (Ext = '.sad') or (Disk.RawImage and ((Ext = '.dsk') or (Ext = '.img')))) then
      Disk.MarkSaved(FileName);
  except
    on E: Exception do Result := Format(_('Could not save %s: %s'), [ExtractFileName(FileName), E.Message]);
  end;
end;

end.

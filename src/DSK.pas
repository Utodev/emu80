{ DSK: CPCEMU standard and extended disk images, as used by the +3. }
unit DSK;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math;

type
  TSector = record
    C, H, R, N: Byte;
    ST1, ST2: Byte;
    Data: TBytes;
  end;

  TTrack = record
    Formatted: Boolean;
    Gap3, Filler: Byte;
    Sectors: array of TSector;
  end;
  PTrack = ^TTrack;

  TDiskImage = class
  private
    FTracks: array of array[0..1] of TTrack;
    FSides: Integer;
    FFileName: string;
    FModified: Boolean;
    FWriteProtected: Boolean;
    FRawImage: Boolean;
    function GetCylinders: Integer;
  public
    constructor Create;
    procedure LoadFromFile(const FileName: string);
    procedure LoadFromStream(S: TStream);
    { Saves in extended DSK format }
    procedure SaveToFile(const FileName: string);
    { Creates an unformatted disk }
    procedure CreateBlank(Cylinders, Sides: Integer);
    { Creates an empty disk in the standard +3 format (ready to use, no FORMAT
      needed): 40 tracks, 1 side, 9 sectors of 512 bytes, empty directory }
    procedure CreatePlus3Formatted;
    { The same for an Amstrad CPC: AMSDOS's data format (sector numbers C1-C9,
      in its usual interleave) }
    procedure CreateCPCFormatted;
    function Track(Cylinder, Side: Integer): PTrack;
    procedure FormatTrack(Cylinder, Side: Integer; const IDs: array of Byte; SectorCount: Integer;
      N, Gap3, Filler: Byte);
    procedure MarkModified;
    { The disk was saved to FileName in another format: it is that file now, unchanged }
    procedure MarkSaved(const AFileName: string);
    property Cylinders: Integer read GetCylinders;
    property Sides: Integer read FSides;
    property FileName: string read FFileName write FFileName;
    property Modified: Boolean read FModified;
    property WriteProtected: Boolean read FWriteProtected write FWriteProtected;
    { Loaded from a file of raw sectors (an MSX or CP/M disk image): saved back the same way }
    property RawImage: Boolean read FRawImage write FRawImage;
  end;

implementation

const
  STD_SIGNATURE = 'MV - CPC';
  EXT_SIGNATURE = 'EXTENDED';
  MAX_CYLINDERS = 84;

constructor TDiskImage.Create;
begin
  inherited Create;
  CreateBlank(40, 1);
end;

function TDiskImage.GetCylinders: Integer;
begin
  Result := Length(FTracks);
end;

procedure TDiskImage.CreateBlank(Cylinders, Sides: Integer);
var
  C, S: Integer;
begin
  SetLength(FTracks, Cylinders);
  for C := 0 to Cylinders - 1 do
    for S := 0 to 1 do
    begin
      FTracks[C][S].Formatted := False;
      SetLength(FTracks[C][S].Sectors, 0);
    end;
  FSides := Sides;
  FModified := False;
end;

procedure TDiskImage.CreatePlus3Formatted;
var
  C, I: Integer;
  IDs: array[0..35] of Byte;
begin
  CreateBlank(40, 1);
  for C := 0 to 39 do
  begin
    for I := 0 to 8 do
    begin
      IDs[I * 4] := C;
      IDs[I * 4 + 1] := 0;
      IDs[I * 4 + 2] := I + 1;
      IDs[I * 4 + 3] := 2;
    end;
    // $E5 everywhere: an empty CP/M directory, and no disk specification in
    // the boot sector, so +3DOS uses its standard format
    FormatTrack(C, 0, IDs, 9, 2, $2A, $E5);
  end;
  FModified := False;
end;

procedure TDiskImage.CreateCPCFormatted;
const
  // The order the sectors are in around the track
  ORDER: array[0..8] of Byte = ($C1, $C6, $C2, $C7, $C3, $C8, $C4, $C9, $C5);
var
  C, I: Integer;
  IDs: array[0..35] of Byte;
begin
  CreateBlank(40, 1);
  for C := 0 to 39 do
  begin
    for I := 0 to 8 do
    begin
      IDs[I * 4] := C;
      IDs[I * 4 + 1] := 0;
      IDs[I * 4 + 2] := ORDER[I];
      IDs[I * 4 + 3] := 2;
    end;
    FormatTrack(C, 0, IDs, 9, 2, $4E, $E5);
  end;
  FModified := False;
end;

function TDiskImage.Track(Cylinder, Side: Integer): PTrack;
begin
  if (Cylinder < 0) or (Cylinder >= Length(FTracks)) or (Side < 0) or (Side >= FSides) then
    Result := nil
  else
    Result := @FTracks[Cylinder][Side];
end;

procedure TDiskImage.MarkModified;
begin
  FModified := True;
end;

procedure TDiskImage.MarkSaved(const AFileName: string);
begin
  FFileName := AFileName;
  FModified := False;
end;

procedure TDiskImage.FormatTrack(Cylinder, Side: Integer; const IDs: array of Byte; SectorCount: Integer;
  N, Gap3, Filler: Byte);
var
  I, Size, OldCount: Integer;
  Trk: PTrack;
begin
  if (Cylinder < 0) or (Cylinder >= MAX_CYLINDERS) or (Side < 0) or (Side > 1) then Exit;
  if Cylinder >= Length(FTracks) then
  begin
    OldCount := Length(FTracks);
    SetLength(FTracks, Cylinder + 1);
    for I := OldCount to Cylinder do
    begin
      FTracks[I][0].Formatted := False;
      FTracks[I][1].Formatted := False;
    end;
  end;
  if Side >= FSides then FSides := Side + 1;
  Trk := @FTracks[Cylinder][Side];
  Trk^.Formatted := True;
  Trk^.Gap3 := Gap3;
  Trk^.Filler := Filler;
  SetLength(Trk^.Sectors, SectorCount);
  for I := 0 to SectorCount - 1 do
  begin
    Trk^.Sectors[I].C := IDs[I * 4];
    Trk^.Sectors[I].H := IDs[I * 4 + 1];
    Trk^.Sectors[I].R := IDs[I * 4 + 2];
    Trk^.Sectors[I].N := IDs[I * 4 + 3];
    Trk^.Sectors[I].ST1 := 0;
    Trk^.Sectors[I].ST2 := 0;
    Size := 128 shl (N and 7);
    SetLength(Trk^.Sectors[I].Data, Size);
    FillChar(Trk^.Sectors[I].Data[0], Size, Filler);
  end;
  FModified := True;
end;

procedure TDiskImage.LoadFromStream(S: TStream);
var
  Header, TrackHeader: array[0..255] of Byte;
  Extended: Boolean;
  Cyls, C, Side, I, Count, Size, StdTrackSize, TrackSize: Integer;
  TrackStart, DataPos: Int64;
  Trk: PTrack;
  Sig: string;
begin
  S.ReadBuffer(Header, 256);
  SetString(Sig, PChar(@Header[0]), 8);
  if Sig = EXT_SIGNATURE then
    Extended := True
  else if Sig = STD_SIGNATURE then
    Extended := False
  else
    raise Exception.Create('Not a DSK disk image');
  Cyls := Header[$30];
  FSides := Header[$31];
  if (FSides < 1) or (FSides > 2) then raise Exception.Create('Unsupported number of sides');
  StdTrackSize := Header[$32] or (Header[$33] shl 8);
  CreateBlank(Cyls, FSides);
  FSides := Header[$31];

  TrackStart := 256;
  for C := 0 to Cyls - 1 do
    for Side := 0 to FSides - 1 do
    begin
      if Extended then
        TrackSize := Header[$34 + C * FSides + Side] * 256
      else
        TrackSize := StdTrackSize;
      if TrackSize = 0 then Continue;   // unformatted track
      if TrackStart + 256 > S.Size then Break;
      S.Position := TrackStart;
      S.ReadBuffer(TrackHeader, 256);
      Trk := @FTracks[C][Side];
      Trk^.Formatted := True;
      Trk^.Gap3 := TrackHeader[$16];
      Trk^.Filler := TrackHeader[$17];
      Count := TrackHeader[$15];
      if Count > 29 then Count := 29;
      SetLength(Trk^.Sectors, Count);
      DataPos := TrackStart + 256;
      for I := 0 to Count - 1 do
      begin
        Trk^.Sectors[I].C := TrackHeader[$18 + I * 8];
        Trk^.Sectors[I].H := TrackHeader[$19 + I * 8];
        Trk^.Sectors[I].R := TrackHeader[$1A + I * 8];
        Trk^.Sectors[I].N := TrackHeader[$1B + I * 8];
        Trk^.Sectors[I].ST1 := TrackHeader[$1C + I * 8];
        Trk^.Sectors[I].ST2 := TrackHeader[$1D + I * 8];
        if Extended then
          Size := TrackHeader[$1E + I * 8] or (TrackHeader[$1F + I * 8] shl 8)
        else
          Size := 128 shl (TrackHeader[$14] and 7);
        if DataPos + Size > S.Size then Size := Max(0, S.Size - DataPos);
        SetLength(Trk^.Sectors[I].Data, Size);
        if Size > 0 then
        begin
          S.Position := DataPos;
          S.ReadBuffer(Trk^.Sectors[I].Data[0], Size);
        end;
        Inc(DataPos, Size);
      end;
      Inc(TrackStart, TrackSize);
    end;
  FModified := False;
end;

procedure TDiskImage.LoadFromFile(const FileName: string);
var
  S: TFileStream;
begin
  S := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    LoadFromStream(S);
    FFileName := FileName;
    FWriteProtected := (FileGetAttr(FileName) and faReadOnly) <> 0;
  finally
    S.Free;
  end;
end;

procedure TDiskImage.SaveToFile(const FileName: string);
const
  DiskInfo: string = 'EXTENDED CPC DSK File'#13#10'Disk-Info'#13#10;
  TrackInfo: string = 'Track-Info'#13#10;
  Creator: string = 'emu80';
var
  Header, TrackHeader: array[0..255] of Byte;
  S: TFileStream;
  C, Side, I, Size, Padded: Integer;
  Trk: PTrack;
  Zero: array[0..255] of Byte;
begin
  FillChar(Header, SizeOf(Header), 0);
  FillChar(Zero, SizeOf(Zero), 0);
  Move(DiskInfo[1], Header[0], Length(DiskInfo));
  Move(Creator[1], Header[$22], Length(Creator));
  Header[$30] := Length(FTracks);
  Header[$31] := FSides;
  for C := 0 to High(FTracks) do
    for Side := 0 to FSides - 1 do
    begin
      Trk := @FTracks[C][Side];
      if not Trk^.Formatted then Continue;
      Size := 256;
      for I := 0 to High(Trk^.Sectors) do Inc(Size, Length(Trk^.Sectors[I].Data));
      Header[$34 + C * FSides + Side] := (Size + 255) div 256;
    end;

  S := TFileStream.Create(FileName, fmCreate);
  try
    S.WriteBuffer(Header, 256);
    for C := 0 to High(FTracks) do
      for Side := 0 to FSides - 1 do
      begin
        Trk := @FTracks[C][Side];
        if not Trk^.Formatted then Continue;
        FillChar(TrackHeader, SizeOf(TrackHeader), 0);
        Move(TrackInfo[1], TrackHeader[0], Length(TrackInfo));
        TrackHeader[$10] := C;
        TrackHeader[$11] := Side;
        if Length(Trk^.Sectors) > 0 then TrackHeader[$14] := Trk^.Sectors[0].N;
        TrackHeader[$15] := Length(Trk^.Sectors);
        TrackHeader[$16] := Trk^.Gap3;
        TrackHeader[$17] := Trk^.Filler;
        Size := 0;
        for I := 0 to High(Trk^.Sectors) do
        begin
          TrackHeader[$18 + I * 8] := Trk^.Sectors[I].C;
          TrackHeader[$19 + I * 8] := Trk^.Sectors[I].H;
          TrackHeader[$1A + I * 8] := Trk^.Sectors[I].R;
          TrackHeader[$1B + I * 8] := Trk^.Sectors[I].N;
          TrackHeader[$1C + I * 8] := Trk^.Sectors[I].ST1;
          TrackHeader[$1D + I * 8] := Trk^.Sectors[I].ST2;
          TrackHeader[$1E + I * 8] := Length(Trk^.Sectors[I].Data) and $FF;
          TrackHeader[$1F + I * 8] := Length(Trk^.Sectors[I].Data) shr 8;
          Inc(Size, Length(Trk^.Sectors[I].Data));
        end;
        S.WriteBuffer(TrackHeader, 256);
        for I := 0 to High(Trk^.Sectors) do
          if Length(Trk^.Sectors[I].Data) > 0 then
            S.WriteBuffer(Trk^.Sectors[I].Data[0], Length(Trk^.Sectors[I].Data));
        Padded := ((Size + 255) div 256) * 256;
        if Padded > Size then S.WriteBuffer(Zero, Padded - Size);
      end;
  finally
    S.Free;
  end;
  FFileName := FileName;
  FModified := False;
end;

end.

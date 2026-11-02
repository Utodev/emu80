{ C64Disk: a Commodore 1541 disk as a .d64 image (35 to 42 tracks of 17 to 21 sectors of 256 bytes, with or
  without the error byte per sector) and as the drive reads it: every track as its GCR bytes (sync marks, headers,
  data blocks and gaps), made from the image, and written back into the image when the drive writes a track. }
unit C64Disk;

{$mode objfpc}{$H+}
{$R-}{$Q-}

interface

uses
  SysUtils, Classes;

const
  D64_MAX_TRACKS = 42;
  D64_SIZE_35 = 174848;
  D64_SIZE_40 = 196608;
  D64_SIZE_42 = 205312;

type
  TGcrTrack = array of Byte;

  TD64Image = class
  private
    FData: TBytes;
    FErrors: TBytes;            // one error code per sector (empty: none)
    FTracks: Integer;
    FFileName: string;
    FDirty: Boolean;
    FReadOnly: Boolean;
    FGcr: array[1..D64_MAX_TRACKS] of TGcrTrack;
    FGcrValid: array[1..D64_MAX_TRACKS] of Boolean;
    function GetTrackGcr(Track: Integer): TGcrTrack;
    procedure BuildTrack(Track: Integer);
  public
    constructor Create;
    { Raises on a file that is not a .d64 }
    procedure LoadFromFile(const FileName: string);
    procedure LoadFromBytes(const Bytes: TBytes);
    procedure SaveToFile(const FileName: string);
    { A new, formatted and empty disk (the BAM and an empty directory) }
    procedure Format(const Name, Id: string);
    function SectorOffset(Track, Sector: Integer): Integer;
    function ReadSector(Track, Sector: Integer; var Buf: array of Byte): Boolean;
    procedure WriteSector(Track, Sector: Integer; const Buf: array of Byte);
    { The track as the head sees it (built when first asked for) }
    property Gcr[Track: Integer]: TGcrTrack read GetTrackGcr;
    { The drive has written this track's bytes: read the sectors back into the image }
    procedure TrackWritten(Track: Integer);
    procedure SetGcrByte(Track, Pos: Integer; Value: Byte);
    function DiskName: string;
    function DiskIdBytes: string;
    property Tracks: Integer read FTracks;
    property FileName: string read FFileName write FFileName;
    property Dirty: Boolean read FDirty write FDirty;
    property ReadOnly: Boolean read FReadOnly write FReadOnly;
    property Data: TBytes read FData;
  end;

function SectorsInTrack(Track: Integer): Integer;
{ 0 to 3: the speed zone (the drive's density bits) of a track; 3 is the fastest (tracks 1-17) }
function SpeedZone(Track: Integer): Integer;
{ Bytes of the GCR track (the drive's, at its zone's speed) }
function GcrTrackLength(Track: Integer): Integer;

implementation

uses
  Lang;

const
  GCR_ENC: array[0..15] of Byte = ($0A, $0B, $12, $13, $0E, $0F, $16, $17, $09, $19, $1A, $1B, $0D, $1D, $1E, $15);

var
  GcrDec: array[0..31] of ShortInt;

function SectorsInTrack(Track: Integer): Integer;
begin
  if Track <= 17 then Result := 21
  else if Track <= 24 then Result := 19
  else if Track <= 30 then Result := 18
  else Result := 17;
end;

function SpeedZone(Track: Integer): Integer;
begin
  if Track <= 17 then Result := 3
  else if Track <= 24 then Result := 2
  else if Track <= 30 then Result := 1
  else Result := 0;
end;

function GcrTrackLength(Track: Integer): Integer;
begin
  case SpeedZone(Track) of
    3: Result := 7692;
    2: Result := 7142;
    1: Result := 6666;
  else
    Result := 6250;
  end;
end;

{ Four bytes into five GCR bytes }
procedure GcrEncode4(const Src: array of Byte; Pos: Integer; var Dest: array of Byte; DPos: Integer);
var
  Bits: QWord;
  I: Integer;
begin
  Bits := 0;
  for I := 0 to 3 do
  begin
    Bits := (Bits shl 5) or GCR_ENC[Src[Pos + I] shr 4];
    Bits := (Bits shl 5) or GCR_ENC[Src[Pos + I] and $F];
  end;
  for I := 4 downto 0 do
  begin
    Dest[DPos + I] := Bits and $FF;
    Bits := Bits shr 8;
  end;
end;

{ Five GCR bytes into four; False if one is not valid }
function GcrDecode5(const Src: array of Byte; Pos: Integer; var Dest: array of Byte; DPos: Integer): Boolean;
var
  Bits: QWord;
  I, Hi, Lo: Integer;
begin
  Bits := 0;
  for I := 0 to 4 do Bits := (Bits shl 8) or Src[Pos + I];
  Result := True;
  for I := 3 downto 0 do
  begin
    Lo := GcrDec[Bits and $1F];
    Bits := Bits shr 5;
    Hi := GcrDec[Bits and $1F];
    Bits := Bits shr 5;
    if (Lo < 0) or (Hi < 0) then
    begin
      Result := False;
      Lo := 0;
      Hi := 0;
    end;
    Dest[DPos + I] := (Hi shl 4) or Lo;
  end;
end;

constructor TD64Image.Create;
begin
  inherited Create;
  FTracks := 35;
end;

procedure TD64Image.LoadFromBytes(const Bytes: TBytes);
var
  Sectors, I: Integer;
begin
  Sectors := 0;
  case Length(Bytes) of
    D64_SIZE_35, D64_SIZE_35 + 683: FTracks := 35;
    D64_SIZE_40, D64_SIZE_40 + 768: FTracks := 40;
    D64_SIZE_42, D64_SIZE_42 + 802: FTracks := 42;
  else
    raise Exception.Create(_('Not a .d64 disk image (its size is not one of a 35, 40 or 42 track disk)'));
  end;
  for I := 1 to FTracks do Inc(Sectors, SectorsInTrack(I));
  SetLength(FData, Sectors * 256);
  Move(Bytes[0], FData[0], Length(FData));
  SetLength(FErrors, 0);
  if Length(Bytes) > Length(FData) then
  begin
    SetLength(FErrors, Sectors);
    Move(Bytes[Length(FData)], FErrors[0], Sectors);
  end;
  for I := 1 to D64_MAX_TRACKS do FGcrValid[I] := False;
  FDirty := False;
end;

procedure TD64Image.LoadFromFile(const FileName: string);
var
  F: TFileStream;
  B: TBytes;
begin
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(B, F.Size);
    if F.Size > 0 then F.ReadBuffer(B[0], F.Size);
  finally
    F.Free;
  end;
  LoadFromBytes(B);
  FFileName := FileName;
  FReadOnly := (FileGetAttr(FileName) and faReadOnly) <> 0;
end;

procedure TD64Image.SaveToFile(const FileName: string);
var
  F: TFileStream;
begin
  F := TFileStream.Create(FileName, fmCreate);
  try
    F.WriteBuffer(FData[0], Length(FData));
    if Length(FErrors) > 0 then F.WriteBuffer(FErrors[0], Length(FErrors));
  finally
    F.Free;
  end;
  FDirty := False;
end;

function TD64Image.SectorOffset(Track, Sector: Integer): Integer;
var
  T: Integer;
begin
  Result := -1;
  if (Track < 1) or (Track > FTracks) or (Sector < 0) or (Sector >= SectorsInTrack(Track)) then Exit;
  Result := 0;
  for T := 1 to Track - 1 do Inc(Result, SectorsInTrack(T) * 256);
  Inc(Result, Sector * 256);
end;

function TD64Image.ReadSector(Track, Sector: Integer; var Buf: array of Byte): Boolean;
var
  O: Integer;
begin
  O := SectorOffset(Track, Sector);
  Result := O >= 0;
  if Result then Move(FData[O], Buf[0], 256);
end;

procedure TD64Image.WriteSector(Track, Sector: Integer; const Buf: array of Byte);
var
  O: Integer;
begin
  O := SectorOffset(Track, Sector);
  if O < 0 then Exit;
  Move(Buf[0], FData[O], 256);
  FGcrValid[Track] := False;
  FDirty := True;
end;

procedure TD64Image.Format(const Name, Id: string);
var
  Blank: TBytes;
  I, T, S, Sectors: Integer;
  Bam: array[0..255] of Byte;
  Dir: array[0..255] of Byte;
  N: string;
begin
  Sectors := 0;
  FTracks := 35;
  for I := 1 to FTracks do Inc(Sectors, SectorsInTrack(I));
  SetLength(Blank, Sectors * 256);
  FillChar(Blank[0], Length(Blank), 0);
  LoadFromBytes(Blank);
  FillChar(Bam, SizeOf(Bam), 0);
  Bam[0] := 18; Bam[1] := 1; Bam[2] := $41;
  for T := 1 to 35 do
  begin
    Bam[T * 4] := SectorsInTrack(T);
    for S := 0 to SectorsInTrack(T) - 1 do
      Bam[T * 4 + 1 + S div 8] := Bam[T * 4 + 1 + S div 8] or (1 shl (S mod 8));
  end;
  // Track 18 sectors 0 and 1 are in use
  Bam[18 * 4] := SectorsInTrack(18) - 2;
  Bam[18 * 4 + 1] := Bam[18 * 4 + 1] and not 3;
  N := Copy(UpperCase(Name) + StringOfChar(#$A0, 16), 1, 16);     // (the name is padded with shifted spaces)
  for I := 0 to 15 do Bam[$90 + I] := Ord(N[I + 1]);
  Bam[$A0] := $A0; Bam[$A1] := $A0;
  N := Copy(UpperCase(Id) + '  ', 1, 2);
  Bam[$A2] := Ord(N[1]); Bam[$A3] := Ord(N[2]);
  Bam[$A4] := $A0; Bam[$A5] := Ord('2'); Bam[$A6] := Ord('A');
  for I := $A7 to $AA do Bam[I] := $A0;
  WriteSector(18, 0, Bam);
  FillChar(Dir, SizeOf(Dir), 0);
  Dir[1] := $FF;
  WriteSector(18, 1, Dir);
  FDirty := True;
end;

function TD64Image.DiskName: string;
var
  O, I: Integer;
begin
  Result := '';
  O := SectorOffset(18, 0);
  if O < 0 then Exit;
  for I := 0 to 15 do
    if FData[O + $90 + I] <> $A0 then Result := Result + Chr(FData[O + $90 + I]);
end;

function TD64Image.DiskIdBytes: string;
var
  O: Integer;
begin
  O := SectorOffset(18, 0);
  Result := '  ';
  if O >= 0 then
  begin
    Result[1] := Chr(FData[O + $A2]);
    Result[2] := Chr(FData[O + $A3]);
  end;
end;

procedure TD64Image.BuildTrack(Track: Integer);
var
  Len, Sectors, S, Pos, I, Gap, Extra, Total: Integer;
  Id1, Id2, Chk, Err: Byte;
  Raw: array[0..259] of Byte;
  Hdr: array[0..7] of Byte;
  G: TGcrTrack;
  Off: Integer;

  procedure Put(B: Byte; Count: Integer);
  var
    K: Integer;
  begin
    for K := 1 to Count do
    begin
      if Pos < Len then G[Pos] := B;
      Inc(Pos);
    end;
  end;

begin
  Len := GcrTrackLength(Track);
  SetLength(G, Len);
  FillChar(G[0], Len, $55);
  Sectors := SectorsInTrack(Track);
  Off := SectorOffset(18, 0);
  Id1 := FData[Off + $A2];
  Id2 := FData[Off + $A3];
  // Space left after the sectors, shared as the tail gaps
  Total := Sectors * (5 + 10 + 9 + 5 + 325);
  Gap := (Len - Total) div Sectors;
  Extra := (Len - Total) - Gap * Sectors;
  Pos := 0;
  for S := 0 to Sectors - 1 do
  begin
    Err := 0;
    if Length(FErrors) > 0 then
    begin
      Off := 0;
      for I := 1 to Track - 1 do Inc(Off, SectorsInTrack(I));
      Err := FErrors[Off + S];
      if Err = 1 then Err := 0;
    end;
    // Error 3 (DOS 21, no SYNC): the sector has no sync marks at all, as on an
    // unformatted track, so the drive never finds its header
    if Err = 3 then
    begin
      Put($55, 5 + 10 + 9 + 5 + 325 + Gap + Ord(S < Extra));
      Continue;
    end;
    Chk := S xor Track xor Id1 xor Id2;
    if Err = 9 then Chk := Chk xor $FF;
    if Err = 11 then Id1 := Id1 xor $FF;
    Hdr[0] := 8; Hdr[1] := Chk; Hdr[2] := S; Hdr[3] := Track; Hdr[4] := Id2; Hdr[5] := Id1; Hdr[6] := $0F; Hdr[7] := $0F;
    if Err = 11 then Id1 := Id1 xor $FF;
    Put($FF, 5);
    if Err <> 2 then
    begin
      GcrEncode4(Hdr, 0, G, Pos);
      GcrEncode4(Hdr, 4, G, Pos + 5);
      Inc(Pos, 10);
    end
    else Put($55, 10);
    Put($55, 9);
    Put($FF, 5);
    if Err <> 4 then
    begin
      Off := SectorOffset(Track, S);
      Raw[0] := 7;
      Move(FData[Off], Raw[1], 256);
      Chk := 0;
      for I := 0 to 255 do Chk := Chk xor FData[Off + I];
      if Err = 5 then Chk := Chk xor $FF;
      Raw[257] := Chk;
      Raw[258] := 0;
      Raw[259] := 0;
      for I := 0 to 64 do GcrEncode4(Raw, I * 4, G, Pos + I * 5);
      Inc(Pos, 325);
    end
    else Put($55, 325);
    Put($55, Gap + Ord(S < Extra));
  end;
  FGcr[Track] := G;
  FGcrValid[Track] := True;
end;

function TD64Image.GetTrackGcr(Track: Integer): TGcrTrack;
begin
  if (Track < 1) or (Track > FTracks) then
  begin
    SetLength(Result, 0);
    Exit;
  end;
  if not FGcrValid[Track] then BuildTrack(Track);
  Result := FGcr[Track];
end;

procedure TD64Image.SetGcrByte(Track, Pos: Integer; Value: Byte);
begin
  if (Track < 1) or (Track > FTracks) then Exit;
  if not FGcrValid[Track] then BuildTrack(Track);
  if (Pos >= 0) and (Pos < Length(FGcr[Track])) then FGcr[Track][Pos] := Value;
end;

{ Read the sectors of a track the drive has written back into the image }
procedure TD64Image.TrackWritten(Track: Integer);
var
  G: TGcrTrack;
  Len, P, N, Start, Sec, Trk, I: Integer;
  Hdr: array[0..7] of Byte;
  Blk: array[0..259] of Byte;
  Buf: array[0..4] of Byte;
  Tmp: array[0..400] of Byte;
  Chk: Byte;
  Ok: Boolean;
  Off: Integer;

  function At(Q: Integer): Byte; inline;
  begin
    Result := G[((Q mod Len) + Len) mod Len];
  end;

begin
  if (Track < 1) or (Track > FTracks) or not FGcrValid[Track] then Exit;
  G := FGcr[Track];
  Len := Length(G);
  Sec := -1;
  Trk := -1;
  P := 0;
  N := 0;
  while N < Len do
  begin
    // A sync mark, then the block after it
    if (At(P) = $FF) and (At(P + 1) <> $FF) then
    begin
      Start := P + 1;
      for I := 0 to 9 do Tmp[I] := At(Start + I);
      if (GcrDecode5(Tmp, 0, Hdr, 0)) and (GcrDecode5(Tmp, 5, Hdr, 4)) and (Hdr[0] = 8) then
      begin
        Sec := Hdr[2];
        Trk := Hdr[3];
      end
      else
      begin
        for I := 0 to 324 do Tmp[I] := At(Start + I);
        Ok := True;
        for I := 0 to 64 do
          if not GcrDecode5(Tmp, I * 5, Blk, I * 4) then Ok := False;
        if Ok and (Blk[0] = 7) and (Trk = Track) and (Sec >= 0) then
        begin
          Chk := 0;
          for I := 1 to 256 do Chk := Chk xor Blk[I];
          if Chk = Blk[257] then
          begin
            Off := SectorOffset(Track, Sec);
            if Off >= 0 then
            begin
              Move(Blk[1], FData[Off], 256);
              FDirty := True;
            end;
          end;
          Sec := -1;
        end;
      end;
    end;
    Inc(P);
    Inc(N);
  end;
end;

procedure InitGcr;
var
  I: Integer;
begin
  for I := 0 to 31 do GcrDec[I] := -1;
  for I := 0 to 15 do GcrDec[GCR_ENC[I]] := I;
end;

initialization
  InitGcr;

end.

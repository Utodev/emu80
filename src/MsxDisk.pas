{ MsxDisk: the MSX's disk: the interface in a cartridge slot, and the disk
  image seen as the bytes of a FAT12 file system.

  The interface is the one of the Philips machines (NMS 8245, 8250 ...) as
  the PHILIPSDISK.rom of an MSX with a disk drive drives it (and emu80's own
  QUANTIKA_DISK.ROM, written for the same hardware): a 16K ROM that
  starts at 4000h (the page 1 only), with the controller's registers
  in its last bytes, 3FF8h-3FFFh of the ROM, so at 7FF8h (and again at BFF8h):

    7FF8  WD2793 status (read) / command (write)
    7FF9  track register
    7FFA  sector register
    7FFB  data register
    7FFC  the side: bit 0
    7FFD  the drive: bits 0-1 (0 drive A, 1 drive B; 3 none) and, in what the
          ROM writes (C4h and C5h for a transfer), bits 7-6 and 2 set
    7FFF  (read) bit 7: no DRQ, bit 6: no INTRQ (both active low)

  The controller is TWD1772 (the SAM's): a WD2793 differs from it in the
  stepping rates and the head load time, which the software here does not
  tell apart; the disks are TDiskImage with 9 sectors of 512 bytes a track.

  Written from the behaviour of the ROM (what it reads and writes where) and
  checked against how openMSX describes the interface; no code of openMSX is
  used. }
unit MsxDisk;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Msx, WD1772, DSK;

type
  TMsxTimeFn = function: Int64 of object;

  TMsxDiskInterface = class(TMsxDevice)
  private
    FRom: array of Byte;
    FWD: TWD1772;
    FSide: Byte;
    FDriveReg: Byte;
    FOnTime: TMsxTimeFn;
    function Reg(Offset: Integer): Word;
    procedure Sync;
  public
    constructor Create(const AName: string; const ARom; ASize: Integer; AWD: TWD1772);
    function Read(Addr: Word): Byte; override;
    function Peek(Addr: Word): Byte; override;
    procedure Write(Addr: Word; Value: Byte); override;
    procedure Reset; override;
    function PhysicalOffset(Addr: Word): Integer; override;
    { The current time in the controller's T-states, asked before each access (for timed disks) }
    property OnTime: TMsxTimeFn read FOnTime write FOnTime;
  end;

  { A disk image as one stream of bytes, the sectors in order: cylinder 0 side 0, cylinder 0 side 1, cylinder 1 ...
    (what a raw MSX or PC image file has). Writes go to the sectors and mark the disk changed. }
  TDiskImageStream = class(TStream)
  private
    FDisk: TDiskImage;
    FPos: Int64;
    FSize: Int64;
    FSectors: Integer;      // a track's, as the first has them
    FSecSize: Integer;
    function Locate(Pos: Int64; out Trk: PTrack; out Index, Offset: Integer): Boolean;
  public
    constructor Create(ADisk: TDiskImage);
    function Read(var Buffer; Count: LongInt): LongInt; override;
    function Write(const Buffer; Count: LongInt): LongInt; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
  end;

implementation

uses
  Lang;


{ TMsxDiskInterface }

constructor TMsxDiskInterface.Create(const AName: string; const ARom; ASize: Integer; AWD: TWD1772);
begin
  inherited Create(AName, mkOther);
  SetLength(FRom, ASize);
  if ASize > 0 then Move(ARom, FRom[0], ASize);
  FWD := AWD;
  Reset;
end;

procedure TMsxDiskInterface.Reset;
begin
  FSide := 0;
  FDriveReg := 0;
end;

procedure TMsxDiskInterface.Sync;
begin
  if Assigned(FOnTime) then FWD.SetTime(FOnTime());
end;

{ The port the controller class wants for a register: the drive selected and the side }
function TMsxDiskInterface.Reg(Offset: Integer): Word;
begin
  Result := Offset;
  if (FDriveReg and 3) = 1 then Result := Result or $10;
  if FSide <> 0 then Result := Result or 4;
end;

function TMsxDiskInterface.PhysicalOffset(Addr: Word): Integer;
begin
  if (Addr < $4000) or (Addr >= $8000) then Exit(-1);
  Result := Addr and $3FFF;
  if Result >= Length(FRom) then Result := -1;
end;

function TMsxDiskInterface.Peek(Addr: Word): Byte;
var
  O: Integer;
begin
  O := PhysicalOffset(Addr);
  if (O < 0) or (O >= $3FF8) then Result := $FF else Result := FRom[O];
end;

function TMsxDiskInterface.Read(Addr: Word): Byte;
var
  O: Integer;
begin
  if (Addr < $4000) or (Addr >= $C000) then Exit($FF);
  O := Addr and $3FFF;
  if O < $3FF8 then
  begin
    // the ROM is in page 1 only: the BIOS would find it a second time in page 2
    if (Addr < $8000) and (O < Length(FRom)) then Result := FRom[O] else Result := $FF;
    Exit;
  end;
  Sync;
  case O of
    $3FF8:
      begin
        Result := FWD.ReadReg(Reg(0));
      end;
    $3FF9: Result := FWD.ReadReg(Reg(1));
    $3FFA: Result := FWD.ReadReg(Reg(2));
    $3FFB:
      begin
        Result := FWD.ReadReg(Reg(3));
      end;
    $3FFC: Result := $FE or FSide;
    $3FFD: Result := FDriveReg;
    $3FFF:
      begin
        Result := $3F;
        if not FWD.DataRequest then Result := Result or $80;
        if not FWD.InterruptRequest then Result := Result or $40;
      end;
  else
    Result := $FF;
  end;
end;

procedure TMsxDiskInterface.Write(Addr: Word; Value: Byte);
var
  O: Integer;
begin
  if (Addr < $4000) or (Addr >= $C000) then Exit;
  O := Addr and $3FFF;
  if O < $3FF8 then Exit;
  Sync;
  case O of
    $3FF8:
      begin
        FWD.WriteReg(Reg(0), Value);
      end;
    $3FF9:
      begin
        FWD.WriteReg(Reg(1), Value);
      end;
    $3FFA:
      begin
        FWD.WriteReg(Reg(2), Value);
      end;
    $3FFB: FWD.WriteReg(Reg(3), Value);
    $3FFC: FSide := Value and 1;
    $3FFD: FDriveReg := Value;
  end;
end;

{ TDiskImageStream }

constructor TDiskImageStream.Create(ADisk: TDiskImage);
var
  Trk: PTrack;
begin
  inherited Create;
  FDisk := ADisk;
  Trk := FDisk.Track(0, 0);
  if (Trk = nil) or (Length(Trk^.Sectors) = 0) then raise Exception.Create(_('the disk is not formatted'));
  FSectors := Length(Trk^.Sectors);
  FSecSize := Length(Trk^.Sectors[0].Data);
  FSize := Int64(FDisk.Cylinders) * FDisk.Sides * FSectors * FSecSize;
end;

function TDiskImageStream.Locate(Pos: Int64; out Trk: PTrack; out Index, Offset: Integer): Boolean;
var
  SecNo, TrackNo: Int64;
begin
  Result := False;
  if (Pos < 0) or (Pos >= FSize) then Exit;
  SecNo := Pos div FSecSize;
  Offset := Pos mod FSecSize;
  TrackNo := SecNo div FSectors;
  Index := SecNo mod FSectors;
  Trk := FDisk.Track(TrackNo div FDisk.Sides, TrackNo mod FDisk.Sides);
  Result := (Trk <> nil) and (Index < Length(Trk^.Sectors)) and (Length(Trk^.Sectors[Index].Data) = FSecSize);
end;

function TDiskImageStream.Read(var Buffer; Count: LongInt): LongInt;
var
  P: PByte;
  Trk: PTrack;
  Index, Offset, N: Integer;
begin
  Result := 0;
  P := @Buffer;
  while Count > 0 do
  begin
    if not Locate(FPos, Trk, Index, Offset) then Break;
    N := FSecSize - Offset;
    if N > Count then N := Count;
    Move(Trk^.Sectors[Index].Data[Offset], P^, N);
    Inc(P, N);
    Inc(FPos, N);
    Inc(Result, N);
    Dec(Count, N);
  end;
end;

function TDiskImageStream.Write(const Buffer; Count: LongInt): LongInt;
var
  P: PByte;
  Trk: PTrack;
  Index, Offset, N: Integer;
begin
  Result := 0;
  P := @Buffer;
  while Count > 0 do
  begin
    if not Locate(FPos, Trk, Index, Offset) then Break;
    N := FSecSize - Offset;
    if N > Count then N := Count;
    Move(P^, Trk^.Sectors[Index].Data[Offset], N);
    Inc(P, N);
    Inc(FPos, N);
    Inc(Result, N);
    Dec(Count, N);
    FDisk.MarkModified;
  end;
end;

function TDiskImageStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
begin
  case Origin of
    soBeginning: FPos := Offset;
    soCurrent: FPos := FPos + Offset;
    soEnd: FPos := FSize + Offset;
  end;
  if FPos < 0 then FPos := 0;
  Result := FPos;
end;

end.

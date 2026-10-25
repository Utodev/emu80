{ WD1772: the Western Digital WD1772 (VL-1772-02) floppy disk controller of the
  SAM Coupe, written from its data sheet and the SAM Coupe Technical Manual.

  The Coupe has one chip for its two drives: the drive is chosen by the port
  (E0-E7: drive 1, F0-F7: drive 2) and the side by bit 2 of it (offsets 0-3:
  side 1, 4-7: side 2); the motor runs whenever there is a disk. The registers
  are the status/command, track, sector and data. DRQ and INTRQ are not wired
  to the CPU: programs poll the status.

  The disks are TDiskImage, any geometry: it is the software that makes sense
  of a SAM, +3 or CPC disk. Commands: restore, seek, step, step in/out (type
  I); read and write sector, single or multiple (II); read address, read
  track, write track (III); force interrupt (IV).

  With Timed set, things take the time they do on the real thing: steps of 6,
  12, 2 or 3 ms, a turn of the disk in 200 ms (300 rpm), a byte every 32 us.
  Otherwise everything is instantaneous ("fast disk"). }
unit WD1772;

{$mode objfpc}{$H+}
{$R-}{$Q-}

interface

uses
  SysUtils, Math, Types, DSK;

type
  TWDPhase = (wpIdle, wpTypeI, wpFinding, wpRead, wpWrite, wpAddress, wpTrackRead, wpTrackWrite);

  TWD1772 = class
  private
    FDisks: array[0..1] of TDiskImage;
    FCyl: array[0..1] of Integer;       // the head's cylinder, in each drive
    FDrive, FSide: Integer;             // selected by the port
    FTrackReg, FSectorReg, FData: Byte;
    FStatus: Byte;                      // the bits the commands set: see ST_*
    FTypeI: Boolean;                    // the status shows the type I view
    FStepDir: Integer;                  // +1 in, -1 out: the last step's direction
    FPhase: TWDPhase;
    FCommand: Byte;
    FHeadLoaded: Boolean;
    FBuffer: TBytes;
    FBufferLen, FBufferPos: Integer;
    FWriteTrk: PTrack;                  // the track a write sector writes to
    FWriteSector: Integer;
    FIdIndex: array[0..1] of Integer;   // the next ID a read address finds
    // Timing
    FTimed: Boolean;
    FClockHz: Integer;
    FNow: Int64;
    FBusyUntil: Int64;                  // when a seek or a search ends
    FReadyAt: Int64;                    // when the next byte is ready
    FActivity: Integer;
    FHeadActive: Integer;
    FLastAccess: array[0..1] of QWord;
    FStepStart: array[0..1] of Int64;
    FStepCount: array[0..1] of Integer;
    FStepT: Int64;
    FDriveB: Boolean;
    function ByteT: Int64;
    function RotationT: Int64;
    function RateT(Command: Byte): Int64;
    function DriveReady: Boolean;
    function CurrentTrack: PTrack;
    function SectorTime(Trk: PTrack; Index: Integer; Base: Int64): Int64;
    function FindSector(out Trk: PTrack): Integer;
    procedure Settle;
    procedure Finish(ExtraStatus: Byte);
    procedure Step(Dir: Integer; UpdateTrack: Boolean);
    procedure DoTypeI(Command: Byte);
    procedure BeginSectorOp;
    procedure BeginReadAddress;
    procedure BeginReadTrack;
    procedure FinishWriteTrack;
    procedure DoCommand(Command: Byte);
    procedure NoteAccess;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Reset;
    { Port access: Reg 0 status/command, 1 track, 2 sector, 3 data; the drive and
      side the port address chooses: Port and $10 (drive 2), Port and 4 (side 2) }
    function ReadReg(Port: Word): Byte;
    procedure WriteReg(Port: Word; Value: Byte);
    procedure Tick;
    procedure InsertDisk(Drive: Integer; Disk: TDiskImage);
    function EjectDisk(Drive: Integer): TDiskImage;
    function Disk(Drive: Integer): TDiskImage;
    { Current time (T-states since power on); set before each access }
    procedure SetTime(Now: Int64);
    { For the drive noise: the times of the head steps in [FromT, ToT) }
    function StepTimes(FromT, ToT: Int64): TInt64DynArray;
    function HeadActive: Boolean;
    function LastAccess(Drive: Integer): QWord;
    property Timed: Boolean read FTimed write FTimed;
    property ClockHz: Integer read FClockHz write FClockHz;
    property Activity: Integer read FActivity;
    { Whether a second drive is connected }
    property DriveB: Boolean read FDriveB write FDriveB;
    { The head is on this cylinder of this drive, and the track register says it: where a read of a
      whole file by something other than the controller's commands leaves it }
    procedure HeadMovedTo(Drive, Cyl: Integer);
    property TrackReg: Byte read FTrackReg;
    property SectorReg: Byte read FSectorReg;
  end;

implementation

const
  ST_BUSY = $01;
  ST_DRQ = $02;
  ST_LOST = $04;        // type II/III: lost data
  ST_TRACK0 = $04;      // type I: head at track 0
  ST_INDEX = $02;       // type I: the index hole
  ST_CRC = $08;
  ST_RNF = $10;         // type II/III: record not found
  ST_SEEK = $10;        // type I: seek error
  ST_RECORD = $20;      // type II: deleted data mark
  ST_HEADLOAD = $20;    // type I
  ST_WRITEPROT = $40;
  ST_NOTREADY = $80;
  MAX_CYL = 83;
  RAW_TRACK = 6250;     // bytes in a double-density track

constructor TWD1772.Create;
begin
  inherited Create;
  FDriveB := True;
  Reset;
end;

destructor TWD1772.Destroy;
begin
  FDisks[0].Free;
  FDisks[1].Free;
  inherited Destroy;
end;

procedure TWD1772.Reset;
begin
  FPhase := wpIdle;
  FStatus := 0;
  FTypeI := True;
  FTrackReg := 0;
  FSectorReg := 1;
  FData := 0;
  FStepDir := 1;
  FHeadLoaded := False;
  FBusyUntil := 0;
  FReadyAt := 0;
  FIdIndex[0] := 0;
  FIdIndex[1] := 0;
  if FClockHz = 0 then FClockHz := 6000000;
  FStepT := Int64(FClockHz) * 6 div 1000;
end;

procedure TWD1772.SetTime(Now: Int64);
begin
  FNow := Now;
end;

procedure TWD1772.Tick;
begin
  if FActivity > 0 then Dec(FActivity);
  if FHeadActive > 0 then Dec(FHeadActive);
end;

function TWD1772.ByteT: Int64;
begin
  if FTimed then Result := Int64(FClockHz) * 32 div 1000000 else Result := 0;
end;

function TWD1772.RotationT: Int64;
begin
  Result := FClockHz div 5;   // 300 rpm
end;

{ Time per step from the rate bits r1 r0 of a type I command: 6, 12, 2, 3 ms }
function TWD1772.RateT(Command: Byte): Int64;
const
  MS: array[0..3] of Integer = (6, 12, 2, 3);
begin
  if FTimed then Result := Int64(FClockHz) * MS[Command and 3] div 1000 else Result := 0;
end;

function TWD1772.DriveReady: Boolean;
begin
  Result := (FDisks[FDrive] <> nil) and ((FDrive = 0) or FDriveB);
end;

procedure TWD1772.InsertDisk(Drive: Integer; Disk: TDiskImage);
begin
  FDisks[Drive and 1].Free;
  FDisks[Drive and 1] := Disk;
end;

function TWD1772.EjectDisk(Drive: Integer): TDiskImage;
begin
  Result := FDisks[Drive and 1];
  FDisks[Drive and 1] := nil;
end;

function TWD1772.Disk(Drive: Integer): TDiskImage;
begin
  Result := FDisks[Drive and 1];
end;

procedure TWD1772.HeadMovedTo(Drive, Cyl: Integer);
begin
  FCyl[Drive and 1] := Cyl;
  if (Drive and 1) = FDrive then FTrackReg := Cyl;
end;

function TWD1772.LastAccess(Drive: Integer): QWord;
begin
  Result := FLastAccess[Drive and 1];
end;

function TWD1772.HeadActive: Boolean;
begin
  Result := FHeadActive > 0;
end;

procedure TWD1772.NoteAccess;
begin
  FLastAccess[FDrive] := GetTickCount64;
  FHeadActive := 3;
  FActivity := 3;
end;

function TWD1772.StepTimes(FromT, ToT: Int64): TInt64DynArray;
var
  D, K, N: Integer;
  T: Int64;
begin
  Result := nil;
  N := 0;
  if not FTimed then Exit;
  for D := 0 to 1 do
    for K := 1 to FStepCount[D] do
    begin
      T := FStepStart[D] + K * FStepT;
      if T >= ToT then Break;
      if T >= FromT then
      begin
        SetLength(Result, N + 1);
        Result[N] := T;
        Inc(N);
      end;
    end;
end;

function TWD1772.CurrentTrack: PTrack;
begin
  Result := nil;
  if (FDisks[FDrive] = nil) or (FCyl[FDrive] >= FDisks[FDrive].Cylinders) then Exit;
  if (FSide > 0) and (FDisks[FDrive].Sides < 2) then Exit;
  Result := FDisks[FDrive].Track(FCyl[FDrive], FSide);
  if (Result <> nil) and not Result^.Formatted then Result := nil;
end;

{ When the data field of sector Index on Trk next passes the head, from Base }
function TWD1772.SectorTime(Trk: PTrack; Index: Integer; Base: Int64): Int64;
var
  Offset, Wait: Int64;
begin
  if not FTimed or (Trk = nil) or (Length(Trk^.Sectors) = 0) then Exit(Base);
  // Sectors are spread evenly round the track; the data field follows its ID
  Offset := RotationT * Index div Length(Trk^.Sectors) + RotationT div 50;
  Wait := (Offset - Base mod RotationT + RotationT) mod RotationT;
  Result := Base + Wait;
end;

{ The sector the track register and sector register ask for on the head's
  track: the index in the track, or -1 }
function TWD1772.FindSector(out Trk: PTrack): Integer;
var
  I: Integer;
begin
  Result := -1;
  Trk := CurrentTrack;
  if Trk = nil then Exit;
  for I := 0 to High(Trk^.Sectors) do
    if (Trk^.Sectors[I].C = FTrackReg) and (Trk^.Sectors[I].R = FSectorReg) then Exit(I);
end;

{ A command ends: the busy bit goes, with the error bits it leaves }
procedure TWD1772.Finish(ExtraStatus: Byte);
begin
  FStatus := ExtraStatus and not (ST_BUSY or ST_DRQ);
  FPhase := wpIdle;
end;

{ Brings what is going on up to the current time }
procedure TWD1772.Settle;
begin
  case FPhase of
    wpTypeI:
      if FNow >= FBusyUntil then Finish(FStatus);
    wpFinding:
      if FNow >= FBusyUntil then Finish(FStatus or ST_RNF);
  end;
end;

procedure TWD1772.Step(Dir: Integer; UpdateTrack: Boolean);
begin
  FStepDir := Dir;
  Inc(FCyl[FDrive], Dir);
  if FCyl[FDrive] < 0 then FCyl[FDrive] := 0;
  if FCyl[FDrive] > MAX_CYL then FCyl[FDrive] := MAX_CYL;
  if UpdateTrack then FTrackReg := Byte(FTrackReg + Dir);
end;

procedure TWD1772.DoTypeI(Command: Byte);
var
  Steps, Dest: Integer;
  Dir: Integer;
  Verify, Update: Boolean;
  Trk: PTrack;
  I: Integer;
  Found: Boolean;
begin
  FTypeI := True;
  FHeadLoaded := (Command and 8) <> 0;
  Verify := (Command and 4) <> 0;
  Steps := 0;
  case Command shr 4 of
    0:
      begin
        // Restore: back to track 0
        Steps := FCyl[FDrive];
        FCyl[FDrive] := 0;
        FTrackReg := 0;
        FStepDir := -1;
      end;
    1:
      begin
        // Seek: from the track register to the data register
        Dest := FData;
        Steps := Abs(Dest - FTrackReg);
        if Dest > FTrackReg then Dir := 1 else Dir := -1;
        if Dest <> FTrackReg then
        begin
          FStepDir := Dir;
          Inc(FCyl[FDrive], Dest - FTrackReg);
          if FCyl[FDrive] < 0 then FCyl[FDrive] := 0;
          if FCyl[FDrive] > MAX_CYL then FCyl[FDrive] := MAX_CYL;
        end;
        FTrackReg := FData;
      end;
  else
    // Step (2, 3), step in (4, 5), step out (6, 7)
    Update := (Command and $10) <> 0;
    case Command shr 5 of
      1: Dir := FStepDir;
      2: Dir := 1;
    else
      Dir := -1;
    end;
    Steps := 1;
    Step(Dir, Update);
  end;
  FStatus := ST_BUSY;
  FPhase := wpTypeI;
  FStepStart[FDrive] := FNow;
  FStepCount[FDrive] := Steps;
  FBusyUntil := FNow + Steps * RateT(Command);
  if Verify and FTimed then Inc(FBusyUntil, Int64(FClockHz) * 15 div 1000);   // the settling time
  if not DriveReady then Exit;
  // Verify: the first ID that passes must be of the track register's track
  if Verify then
  begin
    Trk := CurrentTrack;
    Found := False;
    if Trk <> nil then
      for I := 0 to High(Trk^.Sectors) do
        if Trk^.Sectors[I].C = FTrackReg then Found := True;
    if not Found then
    begin
      FStatus := FStatus or ST_SEEK;
      if FTimed then Inc(FBusyUntil, RotationT * 5);
    end;
  end;
end;

{ A read or write sector: finds it, and the data starts to move (or the
  search ends in an error, after the five turns the chip tries) }
procedure TWD1772.BeginSectorOp;
var
  Trk: PTrack;
  Index, Len: Integer;
  Writing: Boolean;
begin
  Writing := (FCommand and $20) <> 0;
  FStatus := ST_BUSY;
  if not DriveReady then
  begin
    Finish(ST_NOTREADY);
    Exit;
  end;
  if Writing and FDisks[FDrive].WriteProtected then
  begin
    Finish(ST_WRITEPROT);
    Exit;
  end;
  Index := FindSector(Trk);
  if Index < 0 then
  begin
    FPhase := wpFinding;
    if FTimed then FBusyUntil := FNow + RotationT * 5 else FBusyUntil := FNow;
    Exit;
  end;
  Len := Length(Trk^.Sectors[Index].Data);
  FBufferLen := Len;
  FBufferPos := 0;
  FReadyAt := SectorTime(Trk, Index, FNow);
  if Writing then
  begin
    FWriteTrk := Trk;
    FWriteSector := Index;
    SetLength(FBuffer, Len);
    FPhase := wpWrite;
  end
  else
  begin
    FBuffer := Copy(Trk^.Sectors[Index].Data, 0, Len);
    FPhase := wpRead;
    if (Trk^.Sectors[Index].ST1 and $20) <> 0 then FStatus := FStatus or ST_CRC;
    if (Trk^.Sectors[Index].ST2 and $40) <> 0 then FStatus := FStatus or ST_RECORD;
  end;
  NoteAccess;
end;

procedure TWD1772.BeginReadAddress;
var
  Trk: PTrack;
  I: Integer;
begin
  FStatus := ST_BUSY;
  Trk := CurrentTrack;
  if not DriveReady then
  begin
    Finish(ST_NOTREADY);
    Exit;
  end;
  if (Trk = nil) or (Length(Trk^.Sectors) = 0) then
  begin
    FPhase := wpFinding;
    if FTimed then FBusyUntil := FNow + RotationT * 5 else FBusyUntil := FNow;
    Exit;
  end;
  I := FIdIndex[FDrive] mod Length(Trk^.Sectors);
  FIdIndex[FDrive] := I + 1;
  SetLength(FBuffer, 6);
  FBuffer[0] := Trk^.Sectors[I].C;
  FBuffer[1] := Trk^.Sectors[I].H;
  FBuffer[2] := Trk^.Sectors[I].R;
  FBuffer[3] := Trk^.Sectors[I].N;
  FBuffer[4] := 0;
  FBuffer[5] := 0;
  FBufferLen := 6;
  FBufferPos := 0;
  FReadyAt := SectorTime(Trk, I, FNow) - RotationT div 50 + RotationT div 100;
  if FReadyAt < FNow then FReadyAt := FNow;
  // The track number of the ID goes to the sector register
  FSectorReg := FBuffer[0];
  FPhase := wpAddress;
  NoteAccess;
end;

{ Read track: the raw track as the chip reads it, built from the sectors:
  gaps, ID and data fields, with their marks and (zero) CRCs }
procedure TWD1772.BeginReadTrack;
var
  Trk: PTrack;
  I, K, Len: Integer;
  Raw: TBytes;

  procedure Put(B: Byte; Count: Integer = 1);
  var
    J: Integer;
  begin
    for J := 1 to Count do
    begin
      if Len >= Length(Raw) then SetLength(Raw, Length(Raw) + 4096);
      Raw[Len] := B;
      Inc(Len);
    end;
  end;

begin
  FStatus := ST_BUSY;
  Trk := CurrentTrack;
  if not DriveReady then
  begin
    Finish(ST_NOTREADY);
    Exit;
  end;
  if Trk = nil then
  begin
    FPhase := wpFinding;
    if FTimed then FBusyUntil := FNow + RotationT * 5 else FBusyUntil := FNow;
    Exit;
  end;
  Len := 0;
  SetLength(Raw, RAW_TRACK);
  Put($4E, 80);
  Put(0, 12);
  Put($C2, 3);
  Put($FC);
  Put($4E, 50);
  for I := 0 to High(Trk^.Sectors) do
  begin
    Put(0, 12);
    Put($A1, 3);
    Put($FE);
    Put(Trk^.Sectors[I].C);
    Put(Trk^.Sectors[I].H);
    Put(Trk^.Sectors[I].R);
    Put(Trk^.Sectors[I].N);
    Put(0, 2);
    Put($4E, 22);
    Put(0, 12);
    Put($A1, 3);
    if (Trk^.Sectors[I].ST2 and $40) <> 0 then Put($F8) else Put($FB);
    for K := 0 to High(Trk^.Sectors[I].Data) do Put(Trk^.Sectors[I].Data[K]);
    Put(0, 2);
    Put($4E, Trk^.Gap3);
  end;
  while Len < RAW_TRACK do Put($4E);
  FBuffer := Raw;
  FBufferLen := Len;
  FBufferPos := 0;
  FReadyAt := FNow;
  FPhase := wpTrackRead;
  NoteAccess;
end;

{ Write track: the bytes the CPU sent are read as a format: each ID field
  (FE, C H R N) followed by a data field (FB or F8, the filler) makes a sector }
procedure TWD1772.FinishWriteTrack;
var
  IDs: array of Byte;
  I, Count, N: Integer;
  Filler, Gap3: Byte;
  B: Byte;
begin
  Count := 0;
  N := 2;
  Filler := $E5;
  Gap3 := $2A;
  I := 0;
  while I < FBufferLen do
  begin
    if (FBuffer[I] = $FE) and (I + 4 < FBufferLen) then
    begin
      SetLength(IDs, (Count + 1) * 4);
      IDs[Count * 4] := FBuffer[I + 1];
      IDs[Count * 4 + 1] := FBuffer[I + 2];
      IDs[Count * 4 + 2] := FBuffer[I + 3];
      IDs[Count * 4 + 3] := FBuffer[I + 4];
      if Count = 0 then N := FBuffer[I + 4] and 7;
      Inc(Count);
      Inc(I, 5);
    end
    else if ((FBuffer[I] = $FB) or (FBuffer[I] = $F8)) and (Count > 0) and (I + 1 < FBufferLen) then
    begin
      B := FBuffer[I + 1];
      if B <> $F7 then Filler := B;
      Inc(I);
    end
    else
      Inc(I);
  end;
  if (Count > 0) and (FCyl[FDrive] < FDisks[FDrive].Cylinders) then
  begin
    FDisks[FDrive].FormatTrack(FCyl[FDrive], FSide, IDs, Count, N, Gap3, Filler);
    FDisks[FDrive].MarkModified;
  end;
  Finish(0);
end;

procedure TWD1772.DoCommand(Command: Byte);
begin
  FCommand := Command;
  FPhase := wpIdle;
  case Command shr 4 of
    $0..$7: DoTypeI(Command);
    $8, $9:
      begin
        FTypeI := False;
        BeginSectorOp;
      end;
    $A, $B:
      begin
        FTypeI := False;
        BeginSectorOp;
      end;
    $C:
      begin
        FTypeI := False;
        BeginReadAddress;
      end;
    $E:
      begin
        FTypeI := False;
        BeginReadTrack;
      end;
    $F:
      begin
        FTypeI := False;
        FStatus := ST_BUSY;
        if not DriveReady then Finish(ST_NOTREADY)
        else if FDisks[FDrive].WriteProtected then Finish(ST_WRITEPROT)
        else
        begin
          SetLength(FBuffer, RAW_TRACK);
          FBufferLen := 0;
          FBufferPos := 0;
          FReadyAt := FNow;
          FPhase := wpTrackWrite;
          NoteAccess;
        end;
      end;
  else
    begin
      // Force interrupt: whatever was going on stops; the status shows the type I view
      FTypeI := True;
      FPhase := wpIdle;
      FStatus := FStatus and not (ST_BUSY or ST_DRQ or ST_LOST);
    end;
  end;
end;

function TWD1772.ReadReg(Port: Word): Byte;
var
  Rot: Int64;
begin
  FDrive := (Port shr 4) and 1;
  FSide := (Port shr 2) and 1;
  Settle;
  case Port and 3 of
    0:
      begin
        Result := FStatus and not (ST_BUSY or ST_DRQ);
        if FPhase <> wpIdle then Result := Result or ST_BUSY;
        // DRQ: a byte is ready to be read, or wanted
        if (FPhase in [wpRead, wpAddress, wpTrackRead, wpWrite, wpTrackWrite]) and (FNow >= FReadyAt) and
           ((FPhase = wpTrackWrite) or (FBufferPos < FBufferLen)) then
          Result := Result or ST_DRQ;
        if FTypeI then
        begin
          // Type I view: head loaded, track 0 and the index hole
          Result := Result and not (ST_DRQ or ST_HEADLOAD or ST_TRACK0 or ST_INDEX);
          if FHeadLoaded and DriveReady then Result := Result or ST_HEADLOAD;
          if FCyl[FDrive] = 0 then Result := Result or ST_TRACK0;
          // The index hole passes once a turn, whether or not the transfers are timed:
          // the ROM tells that there is a disk by it
          if DriveReady then
          begin
            Rot := RotationT;
            if (FNow mod Rot) < Rot div 50 then Result := Result or ST_INDEX;
          end;
          if DriveReady and (FDisks[FDrive].WriteProtected) then Result := Result or ST_WRITEPROT;
        end;
        if not DriveReady then Result := Result or ST_NOTREADY
        else Result := Result and not ST_NOTREADY;
      end;
    1: Result := FTrackReg;
    2: Result := FSectorReg;
  else
    begin
      Result := FData;
      if (FPhase in [wpRead, wpAddress, wpTrackRead]) and (FBufferPos < FBufferLen) then
      begin
        NoteAccess;
        Result := FBuffer[FBufferPos];
        FData := Result;
        Inc(FBufferPos);
        if FReadyAt < FNow then FReadyAt := FNow;
        Inc(FReadyAt, ByteT);
        if FBufferPos >= FBufferLen then
          case FPhase of
            wpRead:
              // Multiple: the next sector, until there is no more
              if (FCommand and $10) <> 0 then
              begin
                FSectorReg := Byte(FSectorReg + 1);
                BeginSectorOp;
              end
              else Finish(FStatus);
          else
            Finish(FStatus);
          end;
      end;
    end;
  end;
end;

procedure TWD1772.WriteReg(Port: Word; Value: Byte);
var
  Len: Integer;
begin
  FDrive := (Port shr 4) and 1;
  FSide := (Port shr 2) and 1;
  Settle;
  case Port and 3 of
    0: DoCommand(Value);
    1: FTrackReg := Value;
    2: FSectorReg := Value;
  else
    begin
      FData := Value;
      case FPhase of
        wpWrite:
          if FBufferPos < FBufferLen then
          begin
            NoteAccess;
            FBuffer[FBufferPos] := Value;
            Inc(FBufferPos);
            if FReadyAt < FNow then FReadyAt := FNow;
            Inc(FReadyAt, ByteT);
            if FBufferPos >= FBufferLen then
            begin
              Move(FBuffer[0], FWriteTrk^.Sectors[FWriteSector].Data[0], FBufferLen);
              // The data mark: A0 bit 0 = a deleted one
              if (FCommand and 1) <> 0 then
                FWriteTrk^.Sectors[FWriteSector].ST2 := FWriteTrk^.Sectors[FWriteSector].ST2 or $40
              else
                FWriteTrk^.Sectors[FWriteSector].ST2 := FWriteTrk^.Sectors[FWriteSector].ST2 and not $40;
              FDisks[FDrive].MarkModified;
              if (FCommand and $10) <> 0 then
              begin
                FSectorReg := Byte(FSectorReg + 1);
                BeginSectorOp;
              end
              else Finish(0);
            end;
          end;
        wpTrackWrite:
          begin
            NoteAccess;
            Len := FBufferLen;
            if Len < RAW_TRACK then
            begin
              FBuffer[Len] := Value;
              Inc(FBufferLen);
            end;
            if FBufferLen >= RAW_TRACK then FinishWriteTrack;
          end;
      end;
    end;
  end;
end;

end.

{ FDC765: NEC uPD765A floating disk controller as wired in the Spectrum +3:
  non-DMA mode, no interrupt line and no terminal count, so multi-sector
  commands always end with "end of cylinder".

  With Timed set, data moves at the drive's real speed: one byte every 32 us,
  sectors arrive as the disk turns (300 rpm) and seeks take time per track.
  Otherwise everything is instantaneous ("fast disk"). }
unit FDC765;

{$mode objfpc}{$H+}
{$R-}{$Q-}

interface

uses
  SysUtils, Math, Types, DSK;

type
  TFDCPhase = (fpCommand, fpExecRead, fpExecWrite, fpResult);

  TUPD765 = class
  private
    FDisks: array[0..1] of TDiskImage;
    FPCN: array[0..1] of Byte;          // present cylinder of each drive
    FReadIDIndex: array[0..1] of Integer;
    FPhase: TFDCPhase;
    FCommand: array[0..8] of Byte;
    FCommandLen, FCommandPos: Integer;
    FResult: array[0..6] of Byte;
    FResultLen, FResultPos: Integer;
    FBuffer: TBytes;
    FBufferLen, FBufferPos: Integer;
    FST0, FST1, FST2: Byte;
    FIntPending: Boolean;
    FIntST0: Byte;
    FMotor: Boolean;
    FActivity: Integer;
    FLastAccess: array[0..1] of QWord;    // GetTickCount64 of each drive's last access
    FDriveB: Boolean;
    // Timing
    FTimed: Boolean;
    FClockHz: Integer;
    FNow: Int64;                        // current time in T-states
    FReadyAt: Int64;                    // when the next byte / result is ready
    FSeekEnd: array[0..1] of Int64;     // when a seek finishes
    FSeekPending: array[0..1] of Boolean;
    FSeekST0: array[0..1] of Byte;
    FStepT: Int64;                      // time per track step
    FSeekStart: array[0..1] of Int64;   // when the last seek started, and its steps
    FSeekSteps: array[0..1] of Integer;
    FHeadActive: Integer;               // frames left with the head reading/writing
    // State of a running read/write command
    FDrive, FHead: Integer;
    FCurC, FCurH, FCurR, FCurN, FEOT: Byte;
    FWriteSector: Integer;
    FFormatSectors, FFormatN, FFormatGap, FFormatFiller: Byte;
    function CommandLength(Op: Byte): Integer;
    function ByteT: Int64;
    function RotationT: Int64;
    { When the data field of sector Index on Trk next passes the head, from Base }
    function SectorTime(Trk: PTrack; Index: Integer; Base: Int64): Int64;
    procedure StartSeek(Drive: Integer; NewCyl: Integer; ST0: Byte);
    function DriveReady(Drive: Integer): Boolean;
    procedure ExecuteCommand;
    procedure StartResult(Len: Integer);
    procedure SetRWResult;
    function FindSector(Drive, Head: Integer; R: Byte; out Trk: PTrack): Integer;
    procedure ReadNextSector;
    procedure WriteNextSector;
    procedure FinishExecWrite;
    procedure CmdReadData;
    procedure CmdWriteData;
    procedure CmdReadID;
    procedure CmdFormat;
    procedure CmdReadTrack;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Reset;
    function ReadStatus: Byte;
    function ReadData: Byte;
    procedure WriteData(Value: Byte);
    procedure Tick;
    procedure InsertDisk(Drive: Integer; Disk: TDiskImage);
    function EjectDisk(Drive: Integer): TDiskImage;
    function Disk(Drive: Integer): TDiskImage;
    { Current time (T-states since power on); set before each access }
    procedure SetTime(Now: Int64);
    property Motor: Boolean read FMotor write FMotor;
    { For the drive noise: the times of the head steps in [FromT, ToT)
      (absolute T-states, as SetTime), and whether data is moving }
    function StepTimes(FromT, ToT: Int64): TInt64DynArray;
    function HeadActive: Boolean;
    { Whether a second drive (B:) is connected }
    property DriveB: Boolean read FDriveB write FDriveB;
    property Timed: Boolean read FTimed write FTimed;
    property ClockHz: Integer read FClockHz write FClockHz;
    { Non-zero while the drive was recently accessed (for an activity LED). }
    property Activity: Integer read FActivity;
    { When the drive was last read or written (GetTickCount64), for a LED }
    function LastAccess(Drive: Integer): QWord;
    { The cylinder each drive's head is on (for snapshots: a program's own disk routines may count on it) }
    function GetPCN(Drive: Integer): Byte;
    procedure SetPCN(Drive: Integer; Value: Byte);
  end;

implementation

const
  ST0_ABNORMAL = $40;
  ST0_INVALID = $80;
  ST0_SEEK_END = $20;
  ST0_NOT_READY = $08;
  ST1_END_OF_CYL = $80;
  ST1_NO_DATA = $04;
  ST1_NOT_WRITABLE = $02;
  ST1_MISSING_AM = $01;
  ST2_CONTROL_MARK = $40;
  ST3_WRITE_PROT = $40;
  ST3_READY = $20;
  ST3_TRACK0 = $10;
  ST3_TWO_SIDE = $08;

constructor TUPD765.Create;
begin
  inherited Create;
  FDriveB := True;
  Reset;
end;

destructor TUPD765.Destroy;
begin
  FDisks[0].Free;
  FDisks[1].Free;
  inherited Destroy;
end;

procedure TUPD765.SetTime(Now: Int64);
begin
  FNow := Now;
end;

function TUPD765.ByteT: Int64;
begin
  if FTimed then Result := Int64(FClockHz) * 32 div 1000000 else Result := 0;
end;

function TUPD765.RotationT: Int64;
begin
  Result := FClockHz div 5;   // 300 rpm
end;

function TUPD765.SectorTime(Trk: PTrack; Index: Integer; Base: Int64): Int64;
var
  Offset, Wait: Int64;
begin
  if not FTimed or (Trk = nil) or (Length(Trk^.Sectors) = 0) then Exit(Base);
  // Sectors are spread evenly round the track; the data field follows its ID
  Offset := RotationT * Index div Length(Trk^.Sectors) + RotationT div 50;
  Wait := (Offset - Base mod RotationT + RotationT) mod RotationT;
  Result := Base + Wait;
end;

procedure TUPD765.StartSeek(Drive: Integer; NewCyl: Integer; ST0: Byte);
var
  Steps: Integer;
begin
  Steps := Abs(NewCyl - FPCN[Drive]);
  FPCN[Drive] := NewCyl;
  FSeekST0[Drive] := ST0;
  FSeekPending[Drive] := True;
  if FTimed then FSeekEnd[Drive] := FNow + Steps * FStepT else FSeekEnd[Drive] := 0;
  FSeekStart[Drive] := FNow;
  FSeekSteps[Drive] := Steps;
end;

procedure TUPD765.Reset;
begin
  FPhase := fpCommand;
  FCommandPos := 0;
  FIntPending := False;
  FMotor := False;
  FPCN[0] := 0;
  FPCN[1] := 0;
  FReadyAt := 0;
  FSeekPending[0] := False;
  FSeekPending[1] := False;
  FSeekEnd[0] := 0;
  FSeekEnd[1] := 0;
  if FClockHz = 0 then FClockHz := 3546900;
  FStepT := Int64(FClockHz) * 6 div 1000;   // 6 ms per track until SPECIFY
end;

procedure TUPD765.InsertDisk(Drive: Integer; Disk: TDiskImage);
begin
  FDisks[Drive and 1].Free;
  FDisks[Drive and 1] := Disk;
end;

function TUPD765.EjectDisk(Drive: Integer): TDiskImage;
begin
  Result := FDisks[Drive and 1];
  FDisks[Drive and 1] := nil;
end;

function TUPD765.Disk(Drive: Integer): TDiskImage;
begin
  Result := FDisks[Drive and 1];
end;

function TUPD765.GetPCN(Drive: Integer): Byte;
begin
  Result := FPCN[Drive and 1];
end;

procedure TUPD765.SetPCN(Drive: Integer; Value: Byte);
begin
  FPCN[Drive and 1] := Value;
end;

function TUPD765.LastAccess(Drive: Integer): QWord;
begin
  Result := FLastAccess[Drive and 1];
end;

function TUPD765.DriveReady(Drive: Integer): Boolean;
begin
  Result := (FDisks[Drive and 1] <> nil) and ((Drive and 1 = 0) or FDriveB);
end;

procedure TUPD765.Tick;
begin
  if FActivity > 0 then Dec(FActivity);
  if FHeadActive > 0 then Dec(FHeadActive);
end;

function TUPD765.StepTimes(FromT, ToT: Int64): TInt64DynArray;
var
  D, K, N: Integer;
  T: Int64;
begin
  Result := nil;
  N := 0;
  if not FTimed then Exit;
  for D := 0 to 1 do
    for K := 1 to FSeekSteps[D] do
    begin
      T := FSeekStart[D] + K * FStepT;
      if T >= ToT then Break;
      if T >= FromT then
      begin
        SetLength(Result, N + 1);
        Result[N] := T;
        Inc(N);
      end;
    end;
end;

function TUPD765.HeadActive: Boolean;
begin
  Result := FHeadActive > 0;
end;

function TUPD765.CommandLength(Op: Byte): Integer;
begin
  case Op and $1F of
    $02, $05, $06, $09, $0C, $11, $19, $1D: Result := 9;
    $03, $0F: Result := 3;
    $04, $07, $0A: Result := 2;
    $0D: Result := 6;
  else
    Result := 1;
  end;
end;

function TUPD765.ReadStatus: Byte;
var
  D: Integer;
begin
  case FPhase of
    fpCommand:
      if FCommandPos > 0 then Result := $90 else Result := $80;
    fpExecRead: Result := $F0;
    fpExecWrite: Result := $B0;
  else
    Result := $D0;
  end;
  // RQM (bit 7) only when the next byte or the result is ready
  if (FPhase <> fpCommand) and (FNow < FReadyAt) then Result := Result and $7F;
  // Drive busy bits while seeking
  for D := 0 to 1 do
    if FSeekPending[D] and (FNow < FSeekEnd[D]) then Result := Result or (1 shl D);
end;

function TUPD765.ReadData: Byte;
begin
  Result := $FF;
  case FPhase of
    fpExecRead:
      begin
        FLastAccess[FDrive] := GetTickCount64;
        FHeadActive := 3;
        Result := FBuffer[FBufferPos];
        Inc(FBufferPos);
        if FReadyAt < FNow then FReadyAt := FNow;
        Inc(FReadyAt, ByteT);
        if FBufferPos >= FBufferLen then ReadNextSector;
      end;
    fpResult:
      begin
        Result := FResult[FResultPos];
        Inc(FResultPos);
        if FResultPos >= FResultLen then
        begin
          FPhase := fpCommand;
          FCommandPos := 0;
        end;
      end;
  end;
end;

procedure TUPD765.WriteData(Value: Byte);
begin
  case FPhase of
    fpCommand:
      begin
        if FCommandPos = 0 then FCommandLen := CommandLength(Value);
        FCommand[FCommandPos] := Value;
        Inc(FCommandPos);
        if FCommandPos >= FCommandLen then ExecuteCommand;
      end;
    fpExecWrite:
      begin
        FLastAccess[FDrive] := GetTickCount64;
        FHeadActive := 3;
        FBuffer[FBufferPos] := Value;
        Inc(FBufferPos);
        if FReadyAt < FNow then FReadyAt := FNow;
        Inc(FReadyAt, ByteT);
        if FBufferPos >= FBufferLen then FinishExecWrite;
      end;
  end;
end;

procedure TUPD765.StartResult(Len: Integer);
begin
  FResultLen := Len;
  FResultPos := 0;
  FPhase := fpResult;
end;

procedure TUPD765.SetRWResult;
begin
  FResult[0] := FST0;
  FResult[1] := FST1;
  FResult[2] := FST2;
  FResult[3] := FCurC;
  FResult[4] := FCurH;
  FResult[5] := FCurR;
  FResult[6] := FCurN;
  StartResult(7);
end;

function TUPD765.FindSector(Drive, Head: Integer; R: Byte; out Trk: PTrack): Integer;
var
  I: Integer;
begin
  Result := -1;
  Trk := nil;
  if FDisks[Drive] = nil then Exit;
  Trk := FDisks[Drive].Track(FPCN[Drive], Head);
  if (Trk = nil) or not Trk^.Formatted then Exit;
  for I := 0 to High(Trk^.Sectors) do
    if (Trk^.Sectors[I].R = R) and (Trk^.Sectors[I].C = FCurC) and (Trk^.Sectors[I].H = FCurH) then
      Exit(I);
end;

procedure TUPD765.ExecuteCommand;
var
  Op: Byte;
  Drive, D: Integer;
begin
  Op := FCommand[0] and $1F;
  Drive := FCommand[1] and 1;
  FActivity := 25;
  // Every command but Specify and Sense interrupt names a drive
  if not (Op in [$03, $08]) then FLastAccess[Drive] := GetTickCount64;
  FReadyAt := FNow;
  case Op of
    $02: CmdReadTrack;
    $03:
      begin
        // Specify: step rate SRT is (16 - SRT) ms at the +3's 4 MHz FDC clock... x2
        FStepT := Int64(FClockHz) * (16 - (FCommand[1] shr 4)) * 2 div 1000;
        FPhase := fpCommand;
      end;
    $04:
      begin
        FResult[0] := (FCommand[1] and 7);
        if DriveReady(Drive) then
        begin
          FResult[0] := FResult[0] or ST3_READY;
          if FDisks[Drive].WriteProtected then FResult[0] := FResult[0] or ST3_WRITE_PROT;
          if FDisks[Drive].Sides > 1 then FResult[0] := FResult[0] or ST3_TWO_SIDE;
        end;
        if FPCN[Drive] = 0 then FResult[0] := FResult[0] or ST3_TRACK0;
        StartResult(1);
      end;
    $05, $09: CmdWriteData;
    $06, $0C, $11, $19, $1D: CmdReadData;
    $07:
      begin
        FIntST0 := ST0_SEEK_END or (FCommand[1] and 3);
        if not DriveReady(Drive) then FIntST0 := FIntST0 or ST0_ABNORMAL or ST0_NOT_READY;
        StartSeek(Drive, 0, FIntST0);
        FPhase := fpCommand;
      end;
    $08:
      begin
        // Report a finished seek; nothing to report is an invalid command
        D := -1;
        if FSeekPending[0] and (FNow >= FSeekEnd[0]) then D := 0
        else if FSeekPending[1] and (FNow >= FSeekEnd[1]) then D := 1;
        if D >= 0 then
        begin
          FSeekPending[D] := False;
          FResult[0] := FSeekST0[D];
          FResult[1] := FPCN[D];
          StartResult(2);
        end
        else
        begin
          FResult[0] := ST0_INVALID;
          StartResult(1);
        end;
      end;
    $0A: CmdReadID;
    $0D: CmdFormat;
    $0F:
      begin
        FIntST0 := ST0_SEEK_END or (FCommand[1] and 3);
        if not DriveReady(Drive) then FIntST0 := FIntST0 or ST0_ABNORMAL or ST0_NOT_READY;
        StartSeek(Drive, FCommand[2], FIntST0);
        FPhase := fpCommand;
      end;
  else
    begin
      FResult[0] := ST0_INVALID;
      StartResult(1);
    end;
  end;
  FCommandPos := 0;
end;

procedure TUPD765.CmdReadData;
begin
  FDrive := FCommand[1] and 1;
  FHead := (FCommand[1] shr 2) and 1;
  FCurC := FCommand[2];
  FCurH := FCommand[3];
  FCurR := FCommand[4];
  FCurN := FCommand[5];
  FEOT := FCommand[6];
  FST0 := (FCommand[1] and 7);
  FST1 := 0;
  FST2 := 0;
  if not DriveReady(FDrive) then
  begin
    FST0 := FST0 or ST0_ABNORMAL or ST0_NOT_READY;
    SetRWResult;
    Exit;
  end;
  ReadNextSector;
end;

{ Load the next sector of a read command into the buffer, or end the command. }
procedure TUPD765.ReadNextSector;
var
  Index, Len: Integer;
  Trk: PTrack;
  Deleted, WantDeleted: Boolean;
begin
  if FPhase = fpExecRead then
  begin
    // Previous sector finished: stop on errors, otherwise move on
    if ((FST1 and $7F) <> 0) or ((FST2 and $7F) <> 0) then
    begin
      FST0 := FST0 or ST0_ABNORMAL;
      SetRWResult;
      Exit;
    end;
    if FCurR = FEOT then
    begin
      // No terminal count on the +3: always ends with end of cylinder
      FST0 := FST0 or ST0_ABNORMAL;
      FST1 := FST1 or ST1_END_OF_CYL;
      SetRWResult;
      Exit;
    end;
    Inc(FCurR);
  end;

  Index := FindSector(FDrive, FHead, FCurR, Trk);
  if Index < 0 then
  begin
    FST0 := FST0 or ST0_ABNORMAL;
    if (Trk = nil) or not Trk^.Formatted then
      FST1 := FST1 or ST1_MISSING_AM
    else
      FST1 := FST1 or ST1_NO_DATA;
    SetRWResult;
    Exit;
  end;

  with Trk^.Sectors[Index] do
  begin
    FST1 := FST1 or (ST1 and $37);
    FST2 := FST2 or (ST2 and $7F);
    Deleted := (ST2 and ST2_CONTROL_MARK) <> 0;
    WantDeleted := (FCommand[0] and $1F) = $0C;
    if Deleted <> WantDeleted then FST2 := FST2 or ST2_CONTROL_MARK
    else FST2 := FST2 and not ST2_CONTROL_MARK;
    if FCurN = 0 then Len := FCommand[8] else Len := 128 shl (FCurN and 7);
    if Len > Length(Data) then
    begin
      // Weak/short sectors: pad with what we have
      SetLength(FBuffer, Len);
      FillChar(FBuffer[0], Len, 0);
      if Length(Data) > 0 then Move(Data[0], FBuffer[0], Length(Data));
    end
    else
    begin
      SetLength(FBuffer, Len);
      if Len > 0 then Move(Data[0], FBuffer[0], Len);
    end;
  end;
  FBufferLen := Len;
  FBufferPos := 0;
  // Wait for the sector to come round under the head
  FReadyAt := SectorTime(Trk, Index, Max(FNow, FReadyAt));
  if FBufferLen = 0 then
  begin
    SetRWResult;
    Exit;
  end;
  FPhase := fpExecRead;
end;

procedure TUPD765.CmdReadTrack;
begin
  // Read the track sequentially from the first sector regardless of IDs
  FDrive := FCommand[1] and 1;
  FHead := (FCommand[1] shr 2) and 1;
  FCurC := FCommand[2];
  FCurH := FCommand[3];
  FCurN := FCommand[5];
  FEOT := FCommand[6];
  FST0 := (FCommand[1] and 7);
  FST1 := 0;
  FST2 := 0;
  if not DriveReady(FDrive) then
  begin
    FST0 := FST0 or ST0_ABNORMAL or ST0_NOT_READY;
    SetRWResult;
    Exit;
  end;
  FCurR := FCommand[4];
  ReadNextSector;
end;

procedure TUPD765.CmdWriteData;
begin
  FDrive := FCommand[1] and 1;
  FHead := (FCommand[1] shr 2) and 1;
  FCurC := FCommand[2];
  FCurH := FCommand[3];
  FCurR := FCommand[4];
  FCurN := FCommand[5];
  FEOT := FCommand[6];
  FST0 := (FCommand[1] and 7);
  FST1 := 0;
  FST2 := 0;
  if not DriveReady(FDrive) then
  begin
    FST0 := FST0 or ST0_ABNORMAL or ST0_NOT_READY;
    SetRWResult;
    Exit;
  end;
  if FDisks[FDrive].WriteProtected then
  begin
    FST0 := FST0 or ST0_ABNORMAL;
    FST1 := ST1_NOT_WRITABLE;
    SetRWResult;
    Exit;
  end;
  FWriteSector := -1;
  WriteNextSector;
end;

procedure TUPD765.WriteNextSector;
var
  Index, Len: Integer;
  Trk: PTrack;
begin
  Index := FindSector(FDrive, FHead, FCurR, Trk);
  if Index < 0 then
  begin
    FST0 := FST0 or ST0_ABNORMAL;
    if (Trk = nil) or not Trk^.Formatted then
      FST1 := FST1 or ST1_MISSING_AM
    else
      FST1 := FST1 or ST1_NO_DATA;
    SetRWResult;
    Exit;
  end;
  FWriteSector := Index;
  if FCurN = 0 then Len := FCommand[8] else Len := 128 shl (FCurN and 7);
  SetLength(FBuffer, Len);
  FBufferLen := Len;
  FBufferPos := 0;
  FReadyAt := SectorTime(Trk, Index, Max(FNow, FReadyAt));
  FPhase := fpExecWrite;
end;

procedure TUPD765.FinishExecWrite;
var
  Trk: PTrack;
  I, Len: Integer;
  IDs: array of Byte;
begin
  if (FCommand[0] and $1F) = $0D then
  begin
    // Format: buffer holds C,H,R,N for each sector
    SetLength(IDs, FBufferLen);
    for I := 0 to FBufferLen - 1 do IDs[I] := FBuffer[I];
    FDisks[FDrive].FormatTrack(FPCN[FDrive], FHead, IDs, FFormatSectors, FFormatN, FFormatGap,
      FFormatFiller);
    FST0 := FDrive or (FHead shl 2);
    FST1 := 0;
    FST2 := 0;
    SetRWResult;
    Exit;
  end;

  Trk := FDisks[FDrive].Track(FPCN[FDrive], FHead);
  with Trk^.Sectors[FWriteSector] do
  begin
    Len := Length(Data);
    if Len > FBufferLen then Len := FBufferLen;
    if Len > 0 then Move(FBuffer[0], Data[0], Len);
    if (FCommand[0] and $1F) = $09 then ST2 := ST2 or ST2_CONTROL_MARK
    else ST2 := ST2 and not ST2_CONTROL_MARK;
  end;
  FDisks[FDrive].MarkModified;
  if FCurR = FEOT then
  begin
    FST0 := FST0 or ST0_ABNORMAL;
    FST1 := FST1 or ST1_END_OF_CYL;
    SetRWResult;
    Exit;
  end;
  Inc(FCurR);
  WriteNextSector;
end;

procedure TUPD765.CmdReadID;
var
  Drive, Head, Count: Integer;
  Trk: PTrack;
begin
  Drive := FCommand[1] and 1;
  Head := (FCommand[1] shr 2) and 1;
  FST0 := FCommand[1] and 7;
  FST1 := 0;
  FST2 := 0;
  FCurC := 0; FCurH := 0; FCurR := 0; FCurN := 0;
  if not DriveReady(Drive) then
  begin
    FST0 := FST0 or ST0_ABNORMAL or ST0_NOT_READY;
    SetRWResult;
    Exit;
  end;
  Trk := FDisks[Drive].Track(FPCN[Drive], Head);
  if (Trk = nil) or not Trk^.Formatted or (Length(Trk^.Sectors) = 0) then
  begin
    FST0 := FST0 or ST0_ABNORMAL;
    FST1 := ST1_MISSING_AM;
    SetRWResult;
    Exit;
  end;
  Count := Length(Trk^.Sectors);
  FReadIDIndex[Drive] := (FReadIDIndex[Drive] + 1) mod Count;
  FReadyAt := SectorTime(Trk, FReadIDIndex[Drive], FNow);
  with Trk^.Sectors[FReadIDIndex[Drive]] do
  begin
    FCurC := C; FCurH := H; FCurR := R; FCurN := N;
  end;
  SetRWResult;
end;

procedure TUPD765.CmdFormat;
begin
  FDrive := FCommand[1] and 1;
  FHead := (FCommand[1] shr 2) and 1;
  FFormatN := FCommand[2];
  FFormatSectors := FCommand[3];
  FFormatGap := FCommand[4];
  FFormatFiller := FCommand[5];
  FST0 := FCommand[1] and 7;
  FST1 := 0;
  FST2 := 0;
  FCurC := FPCN[FDrive]; FCurH := FHead; FCurR := 1; FCurN := FFormatN;
  if not DriveReady(FDrive) then
  begin
    FST0 := FST0 or ST0_ABNORMAL or ST0_NOT_READY;
    SetRWResult;
    Exit;
  end;
  if FDisks[FDrive].WriteProtected then
  begin
    FST0 := FST0 or ST0_ABNORMAL;
    FST1 := ST1_NOT_WRITABLE;
    SetRWResult;
    Exit;
  end;
  FBufferLen := FFormatSectors * 4;
  SetLength(FBuffer, FBufferLen);
  FBufferPos := 0;
  // Formatting starts at the index hole and takes a whole turn
  if FTimed then FReadyAt := FNow + (RotationT - FNow mod RotationT);
  if FBufferLen = 0 then
    FinishExecWrite
  else
    FPhase := fpExecWrite;
end;

end.

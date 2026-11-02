{ C64Drive: the Commodore 1541 disk drive, as the real thing: its own 6502 running the drive's DOS ROM (VC1541.rom,
  16K), 2K of RAM, the two 6522s (VIA 1 on the serial bus, VIA 2 on the disk controller) and the mechanics: the
  motor, the head stepper, the disk turning at 300 rpm and handing the head its GCR bytes at the speed the
  density bits say, and the write head. The serial (IEC) bus is TIecBus: the computer and every drive hold its lines
  low, and each one sees the sum. }
unit C64Drive;

{$mode objfpc}{$H+}
{$R-}{$Q-}

interface

uses
  SysUtils, Classes, Cpu6510, C64Via, C64Disk;

const
  DRIVE_CLOCK = 1000000;

type
  TC64Drive = class;

  { The serial bus: ATN, CLK and DATA are open collector lines (low if anyone holds them low) }
  TIecBus = class
  private
    FDrives: array of TC64Drive;
  public
    ComputerAtn, ComputerClk, ComputerData: Boolean;    // held low by the computer
    procedure AddDrive(D: TC64Drive);
    procedure Clear;
    function AtnLow: Boolean;
    function ClkLow: Boolean;
    function DataLow: Boolean;
    { The computer changed the lines: the drives see ATN }
    procedure Changed;
  end;

  TC64Drive = class(T6502Bus)
  private
    FCpu: T6510;
    FRam: array[0..2047] of Byte;
    FRom: array[0..16383] of Byte;
    FRomLoaded: Boolean;
    FVia1, FVia2: TVia;
    FIec: TIecBus;
    FDevice: Integer;
    FDisk: TD64Image;
    FCredit: Integer;           // drive cycles to run
    FAcc: Int64;
    FHalfTrack: Integer;        // 0 = track 1
    FPhase: Integer;
    FMotor, FLed: Boolean;
    FZone: Integer;
    FGcr: TGcrTrack;
    FGcrTrack: Integer;
    FBytePos: Integer;
    FByteTimer: Integer;
    FSync: Boolean;
    FDataLatch: Byte;
    FWriting: Boolean;
    FWriteDirty: Boolean;
    FWpTransient: Integer;      // cycles the write protect sensor still says "changing"
    FLastAccess: QWord;
    FTotalCycles: Int64;
    FAtnLast: Boolean;
    FHeadNoise: Integer;        // step events for the sound
    FConnected: Boolean;
    function V1ReadB: Byte;
    procedure V1WriteB(Value: Byte);
    function V2ReadA: Byte;
    procedure V2WriteA(Value: Byte);
    function V2ReadB: Byte;
    procedure V2WriteB(Value: Byte);
    procedure V2Control;
    procedure LoadTrack;
    procedure FlushWrite;
    procedure RotateOne; inline;
    procedure UpdateIrq; inline;
  public
    constructor Create(AIec: TIecBus; ADevice: Integer);
    destructor Destroy; override;
    function LoadRom(const FileName: string): Boolean;
    procedure Reset;
    { The whole state, for the debugger's step back: written to S (Save) or read back from it. The fields it copies as
      blocks (see StateIO) are plain values: no strings or dynamic arrays may go in between them }
    procedure StateIO(S: TStream; Save: Boolean);
    { Run for that many cycles of the computer's clock (985248 Hz): the drive's own clock is 1 MHz }
    procedure Run(ComputerCycles: Integer; ClockHz: Integer);
    procedure InsertDisk(Disk: TD64Image);
    function EjectDisk: TD64Image;
    { The levels this drive holds on the bus }
    function ClkLow: Boolean;
    function DataLow: Boolean;
    procedure AtnChanged;
    function Read(Addr: Word): Byte; override;
    procedure Write(Addr: Word; Value: Byte); override;
    function Peek(Addr: Word): Byte;
    property Cpu: T6510 read FCpu;
    property Disk: TD64Image read FDisk;
    property Motor: Boolean read FMotor;
    property Led: Boolean read FLed;
    property Track: Integer read FHalfTrack;
    property Device: Integer read FDevice write FDevice;
    property LastAccess: QWord read FLastAccess;
    property RomLoaded: Boolean read FRomLoaded;
    property Via1: TVia read FVia1;
    property Via2: TVia read FVia2;
    property Writing: Boolean read FWriting;
    { On the bus (a drive that is not there holds no line) }
    property Connected: Boolean read FConnected write FConnected;
  end;

implementation

{ TIecBus }

procedure TIecBus.AddDrive(D: TC64Drive);
begin
  SetLength(FDrives, Length(FDrives) + 1);
  FDrives[High(FDrives)] := D;
end;

procedure TIecBus.Clear;
begin
  SetLength(FDrives, 0);
end;

function TIecBus.AtnLow: Boolean;
begin
  Result := ComputerAtn;
end;

function TIecBus.ClkLow: Boolean;
var
  I: Integer;
begin
  Result := ComputerClk;
  for I := 0 to High(FDrives) do
    if FDrives[I].ClkLow then Exit(True);
end;

function TIecBus.DataLow: Boolean;
var
  I: Integer;
begin
  Result := ComputerData;
  for I := 0 to High(FDrives) do
    if FDrives[I].DataLow then Exit(True);
end;

procedure TIecBus.Changed;
var
  I: Integer;
begin
  for I := 0 to High(FDrives) do FDrives[I].AtnChanged;
end;

{ TC64Drive }

constructor TC64Drive.Create(AIec: TIecBus; ADevice: Integer);
begin
  inherited Create;
  FIec := AIec;
  FDevice := ADevice;
  FCpu := T6510.Create(Self);
  FVia1 := TVia.Create;
  FVia2 := TVia.Create;
  FVia1.OnReadB := @V1ReadB;
  FVia1.OnWriteB := @V1WriteB;
  FVia2.OnReadA := @V2ReadA;
  FVia2.OnWriteA := @V2WriteA;
  FVia2.OnReadB := @V2ReadB;
  FVia2.OnWriteB := @V2WriteB;
  FVia2.OnControl := @V2Control;
  FIec.AddDrive(Self);
end;

destructor TC64Drive.Destroy;
begin
  FCpu.Free;
  FVia1.Free;
  FVia2.Free;
  inherited Destroy;
end;

function TC64Drive.LoadRom(const FileName: string): Boolean;
var
  F: TFileStream;
begin
  Result := False;
  FRomLoaded := False;
  if not FileExists(FileName) then Exit;
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  try
    // 16K; an 8K ROM (the second half of the 1541's) fills the top
    if F.Size = 16384 then F.ReadBuffer(FRom[0], 16384)
    else if F.Size = 8192 then
    begin
      F.ReadBuffer(FRom[8192], 8192);
      Move(FRom[8192], FRom[0], 8192);
    end
    else Exit;
  finally
    F.Free;
  end;
  FRomLoaded := True;
  Result := True;
end;

procedure TC64Drive.Reset;
begin
  FillChar(FRam, SizeOf(FRam), 0);
  FVia1.Reset;
  FVia2.Reset;
  FMotor := False;
  FLed := False;
  FWriting := False;
  FZone := 0;
  FBytePos := 0;
  FByteTimer := 26;
  FCredit := 1000000;
  FAcc := 0;
  FWpTransient := 0;
  FPhase := 0;
  FGcrTrack := 0;
  if FRomLoaded then
  begin
    FCpu.PC := 0;
    FCpu.Reset;
  end;
  FCredit := 0;
  FAtnLast := False;
end;

function TC64Drive.ClkLow: Boolean;
begin
  Result := FConnected and ((FVia1.PortBPins and 8) <> 0);
end;

function TC64Drive.DataLow: Boolean;
var
  PB: Byte;
begin
  Result := False;
  if not FConnected then Exit;
  PB := FVia1.PortBPins;
  // DATA is held by PB1, and by the gate that answers ATN by itself: ATN low and ATNA (PB4) clear, or ATN high and
  // ATNA set
  Result := ((PB and 2) <> 0) or (FIec.AtnLow <> ((PB and $10) <> 0));
end;

procedure TC64Drive.AtnChanged;
var
  Atn: Boolean;
begin
  Atn := FIec.AtnLow;
  if Atn <> FAtnLast then
  begin
    FAtnLast := Atn;
    FVia1.SetCA1(Atn);
  end;
end;

function TC64Drive.V1ReadB: Byte;
begin
  Result := $1A;     // the inputs: bits 0, 2, 7 are the lines (set when low); 5 and 6 the device
  if FIec.DataLow then Result := Result or 1;
  if FIec.ClkLow then Result := Result or 4;
  if FIec.AtnLow then Result := Result or $80;
  Result := Result or ((FDevice - 8) and 3) shl 5;
end;

procedure TC64Drive.V1WriteB(Value: Byte);
begin
end;

function TC64Drive.V2ReadA: Byte;
begin
  Result := FDataLatch;
end;

procedure TC64Drive.V2WriteA(Value: Byte);
begin
end;

function TC64Drive.V2ReadB: Byte;
begin
  Result := $FF;
  // PB4: write protect (light = writable); PB7: sync (low while the head is over a sync mark)
  if (FDisk = nil) or FDisk.ReadOnly or (FWpTransient > 0) then Result := Result and not $10;
  if FSync and not FWriting then Result := Result and not $80;
end;

procedure TC64Drive.V2WriteB(Value: Byte);
var
  Pins, NewPhase, Delta: Integer;
begin
  Pins := FVia2.PortBPins;
  FMotor := (Pins and 4) <> 0;
  FLed := (Pins and 8) <> 0;
  FZone := (Pins shr 5) and 3;
  NewPhase := Pins and 3;
  if NewPhase <> FPhase then
  begin
    Delta := (NewPhase - FPhase) and 3;
    if Delta = 1 then
    begin
      if FHalfTrack < 2 * 41 then Inc(FHalfTrack);
      Inc(FHeadNoise);
    end
    else if Delta = 3 then
    begin
      if FHalfTrack > 0 then Dec(FHalfTrack);
      Inc(FHeadNoise);
    end;
    FPhase := NewPhase;
    FLastAccess := GetTickCount64;
    FlushWrite;
    LoadTrack;
  end;
end;

procedure TC64Drive.V2Control;
var
  W: Boolean;
begin
  // CB2 low: the write head is on
  W := not FVia2.CB2;
  if FWriting and not W then FlushWrite;
  FWriting := W;
end;

procedure TC64Drive.LoadTrack;
var
  T: Integer;
begin
  FGcrTrack := 0;
  SetLength(FGcr, 0);
  if FDisk = nil then Exit;
  T := FHalfTrack div 2 + 1;
  if T > FDisk.Tracks then Exit;
  FGcr := FDisk.Gcr[T];
  FGcrTrack := T;
  if FBytePos >= Length(FGcr) then FBytePos := 0;
end;

procedure TC64Drive.FlushWrite;
begin
  if FWriteDirty and (FDisk <> nil) and (FGcrTrack > 0) then
    FDisk.TrackWritten(FGcrTrack);
  FWriteDirty := False;
end;

procedure TC64Drive.UpdateIrq;
begin
  FCpu.IRQ := FVia1.Irq or FVia2.Irq;
end;

{ One cycle of the disk turning: the next byte comes under the head every so often }
procedure TC64Drive.RotateOne;
var
  B: Byte;
  Next: Boolean;
begin
  if FWpTransient > 0 then Dec(FWpTransient);
  if not FMotor or (FGcrTrack = 0) then
  begin
    FSync := False;
    Exit;
  end;
  Dec(FByteTimer);
  if FByteTimer > 0 then Exit;
  FByteTimer := 32 - 2 * FZone;
  if FWriting then
  begin
    // The byte the CPU left in port A goes onto the disk
    B := FVia2.PortAPins;
    FGcr[FBytePos] := B;
    FDisk.SetGcrByte(FGcrTrack, FBytePos, B);
    FWriteDirty := True;
    FLastAccess := GetTickCount64;
    FDataLatch := B;
    Next := True;
  end
  else
  begin
    B := FGcr[FBytePos];
    FDataLatch := B;
    // A sync mark is ten or more 1 bits: a run of $FF bytes (GCR data can have a single one, that is not sync)
    FSync := (B = $FF) and ((FGcr[(FBytePos + 1) mod Length(FGcr)] = $FF) or
      (FGcr[(FBytePos + Length(FGcr) - 1) mod Length(FGcr)] = $FF));
    Next := not FSync;
  end;
  FBytePos := (FBytePos + 1) mod Length(FGcr);
  if Next then
  begin
    // BYTE READY: CA1 of VIA 2 falls, and with the SOE line high the CPU's overflow flag is set
    FVia2.SetCA1(True);
    FVia2.SetCA1(False);
    if FVia2.CA2 then FCpu.P := FCpu.P or P_V;
    FLastAccess := GetTickCount64;
  end;
end;

function TC64Drive.Peek(Addr: Word): Byte;
begin
  if (Addr and $8000) <> 0 then Exit(FRom[Addr and $3FFF]);
  if (Addr and $1800) = 0 then Exit(FRam[Addr and $7FF]);
  if (Addr and $1C00) = $1800 then Exit(FVia1.Peek(Addr and $F));
  if (Addr and $1C00) = $1C00 then Exit(FVia2.Peek(Addr and $F));
  Result := $FF;
end;

function TC64Drive.Read(Addr: Word): Byte;
begin
  FVia1.Tick;
  FVia2.Tick;
  RotateOne;
  Inc(FTotalCycles);
  Dec(FCredit);
  if (Addr and $8000) <> 0 then Result := FRom[Addr and $3FFF]
  else if (Addr and $1800) = 0 then Result := FRam[Addr and $7FF]
  else if (Addr and $1C00) = $1800 then Result := FVia1.Read(Addr and $F)
  else if (Addr and $1C00) = $1C00 then Result := FVia2.Read(Addr and $F)
  else Result := $FF;
  UpdateIrq;
end;

procedure TC64Drive.Write(Addr: Word; Value: Byte);
begin
  FVia1.Tick;
  FVia2.Tick;
  RotateOne;
  Inc(FTotalCycles);
  Dec(FCredit);
  if (Addr and $8000) <> 0 then
  else if (Addr and $1800) = 0 then FRam[Addr and $7FF] := Value
  else if (Addr and $1C00) = $1800 then FVia1.Write(Addr and $F, Value)
  else if (Addr and $1C00) = $1C00 then FVia2.Write(Addr and $F, Value);
  UpdateIrq;
end;

procedure TC64Drive.Run(ComputerCycles: Integer; ClockHz: Integer);
begin
  if not FRomLoaded then Exit;
  FAcc := FAcc + Int64(ComputerCycles) * DRIVE_CLOCK;
  Inc(FCredit, FAcc div ClockHz);
  FAcc := FAcc mod ClockHz;
  while FCredit > 0 do FCpu.Step;
end;

procedure TC64Drive.InsertDisk(Disk: TD64Image);
begin
  FlushWrite;
  FDisk := Disk;
  FBytePos := 0;
  FWpTransient := 600000;
  LoadTrack;
end;

function TC64Drive.EjectDisk: TD64Image;
begin
  FlushWrite;
  Result := FDisk;
  FDisk := nil;
  FWpTransient := 600000;
  LoadTrack;
end;

procedure TC64Drive.StateIO(S: TStream; Save: Boolean);
begin
  // What was written to the disk is not undone: it is kept, and the head reads the track it was on
  if not Save then FlushWrite;
  FCpu.StateIO(S, Save);
  FVia1.StateIO(S, Save);
  FVia2.StateIO(S, Save);
  StateBlock(S, Save, FRam, SizeOf(FRam));
  // FCredit to FZone, then FGcrTrack to FHeadNoise
  StateBlock(S, Save, FCredit, PtrUInt(@FZone) + SizeOf(FZone) - PtrUInt(@FCredit));
  StateBlock(S, Save, FGcrTrack, PtrUInt(@FHeadNoise) + SizeOf(FHeadNoise) - PtrUInt(@FGcrTrack));
  if Save then Exit;
  if (FDisk <> nil) and (FGcrTrack > 0) and (FGcrTrack <= FDisk.Tracks) then
  begin
    FGcr := FDisk.Gcr[FGcrTrack];
    if FBytePos >= Length(FGcr) then FBytePos := 0;
  end
  else
  begin
    FGcrTrack := 0;
    SetLength(FGcr, 0);
  end;
  UpdateIrq;
end;

end.

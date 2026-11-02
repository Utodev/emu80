{ C64Cia: the MOS 6526 Complex Interface Adapter (two on the C64: keyboard, joysticks and the timers
  on CIA 1, the IEC serial bus and the video bank on CIA 2): two 16-bit timers, the time of day clock,
  the serial register and two 8-bit ports. The machine gives the levels of the ports' pins from outside
  (OnPortA, OnPortB) and is told when the chip's interrupt line changes. }
unit C64Cia;

{$mode objfpc}{$H+}
{$R-}{$Q-}

interface

uses
  Classes, Cpu6510;

type
  TPortRead = function: Byte of object;

  TCia = class
  private
    FPRA, FPRB, FDDRA, FDDRB: Byte;
    FTA, FTB, FLatchA, FLatchB: Word;
    FCRA, FCRB: Byte;
    FICR, FMask: Byte;            // flags, and which ask for the interrupt
    FIrq: Boolean;
    FSDR: Byte;
    FShiftCount: Integer;
    FPendingA: Integer;           // the timer A underflow of the last cycle (for timer B and the serial register)
    FToggleA, FToggleB: Boolean;
    FTodDiv, FTodTicks: Integer;
    FTod, FAlarm: array[0..3] of Byte;   // 10ths, seconds, minutes, hours (BCD)
    FTodLatch: array[0..3] of Byte;
    FTodLatched, FTodRunning: Boolean;
    FFlagPin: Boolean;
    FStartDelay: Integer;
    FOneShotA, FOneShotB: Boolean;
    FCyclesPerTick: Integer;
    procedure SetFlag(Bit: Byte);
    procedure TodTick;
    procedure TimerAUnderflow;
    procedure TimerBUnderflow;
  public
    OnPortA, OnPortB: TPortRead;
    constructor Create(ACyclesPerTodTick: Integer);
    procedure Reset;
    { The whole state, for the debugger's step back: written to S (Save) or read back from it. The fields it copies as
      blocks (see StateIO) are plain values: no strings or dynamic arrays may go in between them }
    procedure StateIO(S: TStream; Save: Boolean);
    { One cycle of the clock }
    procedure Tick; inline;
    function Read(Reg: Byte): Byte;
    function Peek(Reg: Byte): Byte;
    procedure Write(Reg, Value: Byte);
    { The levels of the port pins as the machine's outside world sees them: the outputs
      (bits whose DDR bit is 1 follow the port register) }
    function PortAPins: Byte;
    function PortBPins: Byte;
    { The FLAG input: a falling edge sets the flag (and the interrupt, if asked) }
    procedure SetFlagPin(Level: Boolean);
    property Irq: Boolean read FIrq;
    property DDRA: Byte read FDDRA;
    property DDRB: Byte read FDDRB;
    property PRA: Byte read FPRA;
    property PRB: Byte read FPRB;
    property CRA: Byte read FCRA;
    property CRB: Byte read FCRB;
    property TimerA: Word read FTA;
    property TimerB: Word read FTB;
    property Flags: Byte read FICR;
    property Mask: Byte read FMask;
  end;

implementation

constructor TCia.Create(ACyclesPerTodTick: Integer);
begin
  inherited Create;
  FCyclesPerTick := ACyclesPerTodTick;
  Reset;
end;

procedure TCia.Reset;
begin
  FPRA := 0; FPRB := 0; FDDRA := 0; FDDRB := 0;
  FTA := $FFFF; FTB := $FFFF; FLatchA := $FFFF; FLatchB := $FFFF;
  FCRA := 0; FCRB := 0;
  FICR := 0; FMask := 0; FIrq := False;
  FSDR := 0;
  FShiftCount := 0;
  FPendingA := 0;
  FToggleA := False; FToggleB := False;
  FTodDiv := 0; FTodTicks := 0;
  FillChar(FTod, SizeOf(FTod), 0);
  FillChar(FAlarm, SizeOf(FAlarm), 0);
  FTod[3] := $01;      // 1:00:00.0 AM
  FTodLatched := False;
  FTodRunning := True;
  FFlagPin := True;
  FStartDelay := 0;
end;

procedure TCia.SetFlag(Bit: Byte);
begin
  FICR := FICR or Bit;
  if (FMask and Bit) <> 0 then
  begin
    FIrq := True;
    FICR := FICR or $80;
  end;
end;

procedure TCia.TimerAUnderflow;
begin
  FTA := FLatchA;
  SetFlag(1);
  FToggleA := not FToggleA;
  if (FCRA and 8) <> 0 then FCRA := FCRA and not 1;      // one-shot: stops
  FPendingA := 1;
  // The serial register in output mode shifts one bit every second underflow
  if (FCRA and $40) <> 0 then
    if FShiftCount > 0 then
    begin
      Dec(FShiftCount);
      if FShiftCount = 0 then SetFlag(8);
    end;
end;

procedure TCia.TimerBUnderflow;
begin
  FTB := FLatchB;
  SetFlag(2);
  FToggleB := not FToggleB;
  if (FCRB and 8) <> 0 then FCRB := FCRB and not 1;
end;

procedure TCia.TodTick;
var
  Carry: Boolean;

  function Inc10(V: Byte; Limit: Byte): Byte;
  begin
    if (V and $0F) = 9 then V := (V and $F0) + $10 else Inc(V);
    if V >= Limit then V := 0;
    Result := V;
  end;

begin
  if not FTodRunning then Exit;
  // 10ths: 0-9
  FTod[0] := (FTod[0] + 1) and $0F;
  Carry := FTod[0] >= 10;
  if Carry then
  begin
    FTod[0] := 0;
    FTod[1] := Inc10(FTod[1], $60);
    if FTod[1] = 0 then
    begin
      FTod[2] := Inc10(FTod[2], $60);
      if FTod[2] = 0 then
      begin
        // Hours: 1-12 with the PM bit
        if (FTod[3] and $1F) = $11 then FTod[3] := FTod[3] xor $80 or $12
        else if (FTod[3] and $1F) = $12 then FTod[3] := (FTod[3] and $80) or 1
        else if (FTod[3] and $0F) = 9 then FTod[3] := (FTod[3] and $80) or ((FTod[3] and $1F) + 7)
        else FTod[3] := FTod[3] + 1;
      end;
    end;
  end;
  if (FTod[0] = FAlarm[0]) and (FTod[1] = FAlarm[1]) and (FTod[2] = FAlarm[2]) and (FTod[3] = FAlarm[3]) then SetFlag(4);
end;

procedure TCia.Tick;
var
  UnderA: Boolean;
begin
  // Time of day: the 50/60 Hz input, 5 or 6 pulses to the tenth of a second (CRA bit 7)
  Inc(FTodDiv);
  if FTodDiv >= FCyclesPerTick then
  begin
    FTodDiv := 0;
    Inc(FTodTicks);
    if FTodTicks >= 5 + Ord((FCRA and $80) = 0) then
    begin
      FTodTicks := 0;
      TodTick;
    end;
  end;
  UnderA := False;
  if (FCRA and 1) <> 0 then
  begin
    if (FCRA and $20) = 0 then
    begin
      if FTA = 0 then
      begin
        TimerAUnderflow;
        UnderA := True;
      end
      else Dec(FTA);
    end;
  end;
  // Timer B: the clock, or timer A's underflows
  if (FCRB and 1) <> 0 then
  begin
    case (FCRB shr 5) and 3 of
      0:
        if FTB = 0 then TimerBUnderflow else Dec(FTB);
      2, 3:
        if UnderA then
          if FTB = 0 then TimerBUnderflow else Dec(FTB);
    end;
  end;
end;

procedure TCia.SetFlagPin(Level: Boolean);
begin
  if FFlagPin and not Level then SetFlag($10);
  FFlagPin := Level;
end;

function TCia.PortAPins: Byte;
begin
  Result := FPRA or not FDDRA;
end;

function TCia.PortBPins: Byte;
begin
  Result := FPRB or not FDDRB;
  // Timer outputs on PB6 and PB7
  if (FCRA and 2) <> 0 then
  begin
    if FToggleA then Result := Result or $40 else Result := Result and not $40;
  end;
  if (FCRB and 2) <> 0 then
  begin
    if FToggleB then Result := Result or $80 else Result := Result and not $80;
  end;
end;

function TCia.Peek(Reg: Byte): Byte;
var
  Ext: Byte;
begin
  case Reg and $F of
    0:
      begin
        Ext := $FF;
        if Assigned(OnPortA) then Ext := OnPortA();
        // The pins: an output that is high still gives way to something pulling the line low (a joystick in port 2
        // read with the KERNAL's DDRA = $FF)
        Result := PortAPins and Ext;
      end;
    1:
      begin
        Ext := $FF;
        if Assigned(OnPortB) then Ext := OnPortB();
        Result := PortBPins and Ext;
        if (FCRA and 2) <> 0 then Result := (Result and not $40) or (PortBPins and $40);
        if (FCRB and 2) <> 0 then Result := (Result and not $80) or (PortBPins and $80);
      end;
    2: Result := FDDRA;
    3: Result := FDDRB;
    4: Result := FTA and $FF;
    5: Result := FTA shr 8;
    6: Result := FTB and $FF;
    7: Result := FTB shr 8;
    8: if FTodLatched then Result := FTodLatch[0] else Result := FTod[0];
    9: if FTodLatched then Result := FTodLatch[1] else Result := FTod[1];
    $A: if FTodLatched then Result := FTodLatch[2] else Result := FTod[2];
    $B: if FTodLatched then Result := FTodLatch[3] else Result := FTod[3];
    $C: Result := FSDR;
    $D: Result := FICR;
    $E: Result := FCRA;
  else
    Result := FCRB;
  end;
end;

function TCia.Read(Reg: Byte): Byte;
begin
  Result := Peek(Reg);
  case Reg and $F of
    8:
      FTodLatched := False;
    $B:
      begin
        // Reading the hours latches the clock until the tenths are read
        if not FTodLatched then
        begin
          FTodLatch := FTod;
          FTodLatched := True;
        end;
        Result := FTodLatch[3];
      end;
    $D:
      begin
        FICR := 0;
        FIrq := False;
      end;
  end;
end;

procedure TCia.Write(Reg, Value: Byte);
begin
  case Reg and $F of
    0: FPRA := Value;
    1: FPRB := Value;
    2: FDDRA := Value;
    3: FDDRB := Value;
    4: FLatchA := (FLatchA and $FF00) or Value;
    5:
      begin
        FLatchA := (FLatchA and $FF) or (Value shl 8);
        if (FCRA and 1) = 0 then FTA := FLatchA;
      end;
    6: FLatchB := (FLatchB and $FF00) or Value;
    7:
      begin
        FLatchB := (FLatchB and $FF) or (Value shl 8);
        if (FCRB and 1) = 0 then FTB := FLatchB;
      end;
    8..$B:
      begin
        if (FCRB and $80) <> 0 then
          FAlarm[(Reg and $F) - 8] := Value
        else
        begin
          if (Reg and $F) = $B then FTodRunning := False;
          FTod[(Reg and $F) - 8] := Value;
          if (Reg and $F) = 8 then FTodRunning := True;
        end;
      end;
    $C:
      begin
        FSDR := Value;
        if (FCRA and $40) <> 0 then FShiftCount := 16;
      end;
    $D:
      begin
        if (Value and $80) <> 0 then FMask := FMask or (Value and $1F)
        else FMask := FMask and not (Value and $1F);
        if (FICR and FMask and $1F) <> 0 then
        begin
          FIrq := True;
          FICR := FICR or $80;
        end;
      end;
    $E:
      begin
        if (Value and $10) <> 0 then FTA := FLatchA;       // force load
        if ((Value and 1) <> 0) and ((FCRA and 1) = 0) then FToggleA := True;
        FCRA := Value and not $10;
      end;
    $F:
      begin
        if (Value and $10) <> 0 then FTB := FLatchB;
        if ((Value and 1) <> 0) and ((FCRB and 1) = 0) then FToggleB := True;
        FCRB := Value and not $10;
      end;
  end;
end;

procedure TCia.StateIO(S: TStream; Save: Boolean);
begin
  // FPRA to FCyclesPerTick
  StateBlock(S, Save, FPRA, PtrUInt(@FCyclesPerTick) + SizeOf(FCyclesPerTick) - PtrUInt(@FPRA));
end;

end.

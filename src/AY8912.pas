{ AY8912: General Instrument AY-3-8912 sound chip (128K, +2, +2B, +3). }
unit AY8912;

{$mode objfpc}{$H+}
{$R-}{$Q-}

interface

type
  TAY8912 = class
  private
    FRegs: array[0..15] of Byte;
    FSelected: Byte;
    FToneCount: array[0..2] of Integer;
    FToneOut: array[0..2] of Boolean;
    FNoiseCount: Integer;
    FNoiseSeed: LongWord;
    FNoiseOut: Boolean;
    FNoiseHalf: Boolean;
    FEnvCount: Integer;
    FEnvStep: Integer;     // 0..15 within the current cycle
    FEnvHolding: Boolean;
    FEnvAttack: Boolean;   // current direction (True = rising)
    FEnvLevel: Integer;
    procedure ResetEnvelope;
    procedure EnvelopeTick;
  public
    constructor Create;
    procedure Reset;
    procedure SelectRegister(Value: Byte);
    procedure WriteData(Value: Byte);
    function ReadData: Byte;
    procedure WriteRegister(Reg, Value: Byte);
    function GetRegister(Reg: Integer): Byte;
    { Advance one tick (AY clock / 8) and return channel levels 0..1. }
    procedure Tick(out ChA, ChB, ChC: Single);
    property Selected: Byte read FSelected;
  end;

const
  { Measured AY volume levels, normalised }
  AYVolumes: array[0..15] of Single = (
    0.0, 0.0137, 0.0205, 0.0291, 0.0423, 0.0618, 0.0847, 0.1369,
    0.1691, 0.2647, 0.3527, 0.4499, 0.5704, 0.6873, 0.8482, 1.0);

implementation

const
  RegMasks: array[0..15] of Byte = (
    $FF, $0F, $FF, $0F, $FF, $0F, $1F, $FF, $1F, $1F, $1F, $FF, $FF, $0F, $FF, $FF);

constructor TAY8912.Create;
begin
  inherited Create;
  Reset;
end;

procedure TAY8912.Reset;
var
  I: Integer;
begin
  for I := 0 to 15 do FRegs[I] := 0;
  FSelected := 0;
  for I := 0 to 2 do
  begin
    FToneCount[I] := 0;
    FToneOut[I] := False;
  end;
  FNoiseCount := 0;
  FNoiseSeed := 1;
  FNoiseOut := False;
  FNoiseHalf := False;
  ResetEnvelope;
end;

procedure TAY8912.ResetEnvelope;
begin
  FEnvCount := 0;
  FEnvStep := 0;
  FEnvHolding := False;
  FEnvAttack := (FRegs[13] and $04) <> 0;
  if FEnvAttack then FEnvLevel := 0 else FEnvLevel := 15;
end;

procedure TAY8912.SelectRegister(Value: Byte);
begin
  FSelected := Value;
end;

procedure TAY8912.WriteData(Value: Byte);
begin
  if FSelected < 16 then WriteRegister(FSelected, Value);
end;

function TAY8912.ReadData: Byte;
begin
  if FSelected < 16 then
    Result := FRegs[FSelected]
  else
    Result := $FF;
end;

procedure TAY8912.WriteRegister(Reg, Value: Byte);
begin
  FRegs[Reg and 15] := Value and RegMasks[Reg and 15];
  if (Reg and 15) = 13 then ResetEnvelope;
end;

function TAY8912.GetRegister(Reg: Integer): Byte;
begin
  Result := FRegs[Reg and 15];
end;

procedure TAY8912.EnvelopeTick;
var
  Shape: Byte;
begin
  if FEnvHolding then Exit;
  Inc(FEnvStep);
  if FEnvStep < 16 then
  begin
    if FEnvAttack then FEnvLevel := FEnvStep else FEnvLevel := 15 - FEnvStep;
    Exit;
  end;
  // End of a 16-step cycle
  Shape := FRegs[13];
  FEnvStep := 0;
  if (Shape and $08) = 0 then
  begin
    // Shapes 0-7: drop to 0 and hold
    FEnvHolding := True;
    FEnvLevel := 0;
    Exit;
  end;
  if (Shape and $01) <> 0 then
  begin
    // Hold: final level depends on alternate
    FEnvHolding := True;
    if (Shape and $02) <> 0 then FEnvAttack := not FEnvAttack;
    if FEnvAttack then FEnvLevel := 15 else FEnvLevel := 0;
    Exit;
  end;
  if (Shape and $02) <> 0 then FEnvAttack := not FEnvAttack;
  if FEnvAttack then FEnvLevel := 0 else FEnvLevel := 15;
end;

procedure TAY8912.Tick(out ChA, ChB, ChC: Single);
var
  Ch, Period: Integer;
  Mixer, Vol: Byte;
  Output: Boolean;
  Levels: array[0..2] of Single;
begin
  for Ch := 0 to 2 do
  begin
    Period := FRegs[Ch * 2] or ((FRegs[Ch * 2 + 1] and $0F) shl 8);
    if Period = 0 then Period := 1;
    Inc(FToneCount[Ch]);
    if FToneCount[Ch] >= Period then
    begin
      FToneCount[Ch] := 0;
      FToneOut[Ch] := not FToneOut[Ch];
    end;
  end;

  // Noise runs at half the tone rate
  FNoiseHalf := not FNoiseHalf;
  if FNoiseHalf then
  begin
    Period := FRegs[6] and $1F;
    if Period = 0 then Period := 1;
    Inc(FNoiseCount);
    if FNoiseCount >= Period then
    begin
      FNoiseCount := 0;
      // 17-bit LFSR, taps at bits 0 and 3
      FNoiseSeed := (FNoiseSeed shr 1) or ((((FNoiseSeed and 1) xor ((FNoiseSeed shr 3) and 1))) shl 16);
      FNoiseOut := (FNoiseSeed and 1) <> 0;
    end;
  end;

  // Envelope step every 2 * period ticks
  Period := FRegs[11] or (FRegs[12] shl 8);
  if Period = 0 then Period := 1;
  Inc(FEnvCount);
  if FEnvCount >= Period * 2 then
  begin
    FEnvCount := 0;
    EnvelopeTick;
  end;

  Mixer := FRegs[7];
  for Ch := 0 to 2 do
  begin
    Output := (FToneOut[Ch] or ((Mixer and (1 shl Ch)) <> 0)) and
      (FNoiseOut or ((Mixer and (8 shl Ch)) <> 0));
    if not Output then
      Levels[Ch] := 0
    else
    begin
      Vol := FRegs[8 + Ch];
      if (Vol and $10) <> 0 then
        Levels[Ch] := AYVolumes[FEnvLevel]
      else
        Levels[Ch] := AYVolumes[Vol and $0F];
    end;
  end;
  ChA := Levels[0];
  ChB := Levels[1];
  ChC := Levels[2];
end;

end.

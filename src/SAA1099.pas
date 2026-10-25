{ SAA1099: the Philips SAA1099 sound generator of the SAM Coupe, from its data
  sheet and the SAM Coupe Technical Manual: six square wave generators, each
  with an octave and a frequency, two noise generators, two envelope
  generators and an amplitude for the left and the right of each channel.

  Registers: 0-5 amplitude (low nibble left, high right), 8-13 frequency,
  16-18 octaves (two channels each: 0-2 the even one, 4-6 the odd one), 20 tone
  enable, 21 noise enable, 22 noise generators' clocks, 24-25 envelope
  generators, 28 sound enable (bit 0) and reset (bit 1).

  The chip runs from the SAM's 8 MHz: a generator's frequency is
  8 MHz / 512 * 2^octave / (511 - frequency), 31 Hz to 7.8 kHz. Rendered one
  output sample at a time (SampleRate), the registers written as they come. }
unit SAA1099;

{$mode objfpc}{$H+}

interface

const
  SAA_CLOCK = 8000000;

type
  TSAA1099 = class
  private
    FReg: array[0..31] of Byte;
    FPhase: array[0..5] of Double;      // 0..1 of a cycle
    FNoisePhase: array[0..1] of Double;
    FNoiseLfsr: array[0..1] of LongWord;
    FNoiseBit: array[0..1] of Boolean;
    FEnvPhase: array[0..1] of Double;   // steps of the envelope
    FEnvStep: array[0..1] of Integer;
    FEnvDone: array[0..1] of Boolean;
    FEnabled: Boolean;
    function ToneFreq(Ch: Integer): Double;
    function EnvLevel(Gen: Integer): Integer;
    procedure ResetGenerators;
  public
    constructor Create;
    procedure Reset;
    procedure WriteRegister(Reg, Value: Byte);
    { What was written to a register (for a snapshot) }
    function GetRegister(Reg: Byte): Byte;
    { The next output sample, -1..1 for each side }
    procedure Sample(SampleRate: Integer; out L, R: Single);
    property Enabled: Boolean read FEnabled;
  end;

implementation

constructor TSAA1099.Create;
begin
  inherited Create;
  Reset;
end;

procedure TSAA1099.ResetGenerators;
var
  I: Integer;
begin
  for I := 0 to 5 do FPhase[I] := 0;
  for I := 0 to 1 do
  begin
    FNoisePhase[I] := 0;
    FNoiseLfsr[I] := $1FFFF;
    FNoiseBit[I] := False;
    FEnvPhase[I] := 0;
    FEnvStep[I] := 0;
    FEnvDone[I] := False;
  end;
end;

procedure TSAA1099.Reset;
begin
  FillChar(FReg, SizeOf(FReg), 0);
  FEnabled := False;
  ResetGenerators;
end;

procedure TSAA1099.WriteRegister(Reg, Value: Byte);
begin
  Reg := Reg and 31;
  FReg[Reg] := Value;
  case Reg of
    24, 25:
      begin
        // A write to an envelope register starts it again
        FEnvPhase[Reg - 24] := 0;
        FEnvStep[Reg - 24] := 0;
        FEnvDone[Reg - 24] := False;
      end;
    28:
      begin
        FEnabled := (Value and 1) <> 0;
        if (Value and 2) <> 0 then ResetGenerators;
      end;
  end;
end;

function TSAA1099.GetRegister(Reg: Byte): Byte;
begin
  Result := FReg[Reg and 31];
end;

{ The tone frequency of a channel in Hz }
function TSAA1099.ToneFreq(Ch: Integer): Double;
var
  Oct: Integer;
begin
  Oct := (FReg[16 + Ch div 2] shr (4 * (Ch and 1))) and 7;
  Result := SAA_CLOCK / 512.0 * (1 shl Oct) / (511 - FReg[8 + Ch]);
end;

{ The envelope generator's level (0-15), from its shape }
function TSAA1099.EnvLevel(Gen: Integer): Integer;
var
  Shape, S, Res: Integer;
begin
  Shape := (FReg[24 + Gen] shr 1) and 7;
  S := FEnvStep[Gen];
  // 16 steps a cycle in 4-bit resolution, 8 in 3-bit (every other level)
  case Shape of
    0: Result := 0;
    1: Result := 15;
    2, 3:
      if FEnvDone[Gen] and (Shape = 2) then Result := 0 else Result := 15 - (S and 15);
    4, 5:
      begin
        if (FEnvDone[Gen] and (Shape = 4)) then Result := 0
        else if (S and 31) < 16 then Result := S and 15 else Result := 15 - (S and 15);
        if Shape = 4 then
          if S >= 32 then Result := 0;
      end;
  else
    if FEnvDone[Gen] and (Shape = 6) then Result := 15 else Result := S and 15;
  end;
  Res := (FReg[24 + Gen] shr 4) and 1;
  if Res <> 0 then Result := Result and $0E;   // 3-bit: the low bit is dropped
end;

procedure TSAA1099.Sample(SampleRate: Integer; out L, R: Single);
var
  Ch, G, Div_, Env, Ampl, LeftA, RightA: Integer;
  F, NoiseF: Double;
  Tone, Noise, Out_: Boolean;
  Bit: LongWord;
  EnvF: Double;
  Sel: Integer;
begin
  L := 0;
  R := 0;
  // The generators run even when the output is off
  for Ch := 0 to 5 do
  begin
    FPhase[Ch] := FPhase[Ch] + ToneFreq(Ch) / SampleRate;
    if FPhase[Ch] >= 1 then FPhase[Ch] := FPhase[Ch] - Trunc(FPhase[Ch]);
  end;
  for G := 0 to 1 do
  begin
    Sel := (FReg[22] shr (G * 4)) and 3;
    case Sel of
      0: NoiseF := SAA_CLOCK / 256.0;
      1: NoiseF := SAA_CLOCK / 512.0;
      2: NoiseF := SAA_CLOCK / 1024.0;
    else
      NoiseF := ToneFreq(G * 3);
    end;
    FNoisePhase[G] := FNoisePhase[G] + NoiseF / SampleRate;
    while FNoisePhase[G] >= 1 do
    begin
      FNoisePhase[G] := FNoisePhase[G] - 1;
      // 17-bit linear feedback shift register
      Bit := ((FNoiseLfsr[G] shr 0) xor (FNoiseLfsr[G] shr 3)) and 1;
      FNoiseLfsr[G] := (FNoiseLfsr[G] shr 1) or (Bit shl 16);
      FNoiseBit[G] := (FNoiseLfsr[G] and 1) <> 0;
    end;
    // The envelope: its own clock (the SAM's 8 MHz / 256), or the generator's tone
    if (FReg[24 + G] and $80) <> 0 then
    begin
      if (FReg[24 + G] and $20) <> 0 then EnvF := ToneFreq(G * 3 + 1) * 2
      else EnvF := SAA_CLOCK / 256.0;
      FEnvPhase[G] := FEnvPhase[G] + EnvF / SampleRate;
      while FEnvPhase[G] >= 1 do
      begin
        FEnvPhase[G] := FEnvPhase[G] - 1;
        if not FEnvDone[G] then
        begin
          Inc(FEnvStep[G]);
          Env := (FReg[24 + G] shr 1) and 7;
          // The single shapes stop after one run
          if (Env in [2, 6]) and (FEnvStep[G] >= 16) then FEnvDone[G] := True
          else if (Env = 4) and (FEnvStep[G] >= 32) then FEnvDone[G] := True;
        end;
      end;
    end;
  end;
  if not FEnabled then Exit;
  for Ch := 0 to 5 do
  begin
    Tone := (FReg[20] and (1 shl Ch)) <> 0;
    Noise := (FReg[21] and (1 shl Ch)) <> 0;
    if not (Tone or Noise) then Continue;
    G := Ch div 3;
    if Tone and Noise then Out_ := (FPhase[Ch] < 0.5) and FNoiseBit[G]
    else if Tone then Out_ := FPhase[Ch] < 0.5
    else Out_ := FNoiseBit[G];
    if not Out_ then Continue;
    LeftA := FReg[Ch] and 15;
    RightA := (FReg[Ch] shr 4) and 15;
    // The envelope generators shape channels 2 and 5
    if ((Ch = 2) or (Ch = 5)) and ((FReg[24 + (Ch div 3)] and $80) <> 0) then
    begin
      Env := EnvLevel(Ch div 3);
      LeftA := LeftA * Env div 15;
      if (FReg[24 + (Ch div 3)] and 1) <> 0 then RightA := RightA * (15 - Env) div 15
      else RightA := RightA * Env div 15;
    end;
    L := L + LeftA / 15;
    R := R + RightA / 15;
  end;
end;

end.

{ C64Sid: the C64's sound chip, a MOS 6581 (three voices with waveforms, ADSR envelopes, ring
  modulation and synchronisation, and the multimode filter). The chip is clocked cycle by cycle
  (the envelope and noise generators depend on it), as its registers were written: the writes of a
  frame are kept with their cycle and replayed when the frame's audio is made. }
unit C64Sid;

{$mode objfpc}{$H+}
{$R-}{$Q-}

interface

uses
  Math;

type
  TSidWrite = record
    Cycle: Integer;
    Reg, Value: Byte;
  end;

  TSidVoice = record
    Freq, Pulse: Word;
    Ctrl, AD, SR: Byte;
    Acc: LongWord;                // 24 bits
    Shift: LongWord;              // the noise generator's 23-bit shift register
    NoiseOut: Word;
    // Envelope
    State: Byte;                  // 0 attack, 1 decay/sustain, 2 release
    Env: Byte;
    RateCnt: Integer;
    ExpCnt, ExpPeriod: Integer;
    Hold: Boolean;
    GateOld: Boolean;
    Out: Integer;
  end;

  TSid = class
  private
    FV: array[0..2] of TSidVoice;
    FCutoff: Word;                // 11 bits
    FResRoute: Byte;              // resonance and routing
    FModeVol: Byte;               // mode and volume
    FLow, FBand: Single;
    FWrites: array of TSidWrite;
    FWriteCount: Integer;
    FSamplePos: Double;
    FBus: Byte;                   // last value written (the chip's data bus keeps it for a while)
    FBusAge: Integer;
    FExtOut: Single;
    FClockHz: Integer;
    procedure ClockOne;
    procedure DoWrite(Reg, Value: Byte);
    function WaveOut(I: Integer): Integer;
  public
    constructor Create(AClockHz: Integer);
    procedure Reset;
    { A write by the CPU, at that cycle of the frame (the chip itself is brought up to date when the audio is made) }
    procedure Write(Cycle: Integer; Reg, Value: Byte);
    function Read(Reg: Byte): Byte;
    { The audio of a frame of FrameCycles cycles: Count stereo samples of SampleRate Hz into Dest (L, R SmallInt pairs) }
    procedure Generate(FrameCycles, SampleRate: Integer; Dest: PSmallInt; Count: Integer);
    procedure EndFrame;
    function Register(Reg: Byte): Byte;    // for the debugger
  end;

implementation

const
  RATE_PERIOD: array[0..15] of Integer = (9, 32, 63, 95, 149, 220, 267, 313, 392, 977, 1954, 3126, 3907, 11720, 19532, 31251);
  CLOCK_DEFAULT = 985248;

constructor TSid.Create(AClockHz: Integer);
begin
  inherited Create;
  FClockHz := AClockHz;
  SetLength(FWrites, 256);
  Reset;
end;

procedure TSid.Reset;
var
  I: Integer;
begin
  FillChar(FV, SizeOf(FV), 0);
  for I := 0 to 2 do
  begin
    FV[I].Shift := $7FFFF8;
    FV[I].ExpPeriod := 1;
    FV[I].State := 2;
  end;
  FCutoff := 0;
  FResRoute := 0;
  FModeVol := 0;
  FLow := 0;
  FBand := 0;
  FWriteCount := 0;
  FBus := 0;
end;

procedure TSid.Write(Cycle: Integer; Reg, Value: Byte);
begin
  if FWriteCount >= Length(FWrites) then SetLength(FWrites, Length(FWrites) * 2);
  FWrites[FWriteCount].Cycle := Cycle;
  FWrites[FWriteCount].Reg := Reg and $1F;
  FWrites[FWriteCount].Value := Value;
  Inc(FWriteCount);
  FBus := Value;
end;

function TSid.Register(Reg: Byte): Byte;
var
  I: Integer;
begin
  Result := 0;
  I := Reg div 7;
  case Reg of
    0..20:
      case Reg mod 7 of
        0: Result := FV[I].Freq and $FF;
        1: Result := FV[I].Freq shr 8;
        2: Result := FV[I].Pulse and $FF;
        3: Result := FV[I].Pulse shr 8;
        4: Result := FV[I].Ctrl;
        5: Result := FV[I].AD;
        6: Result := FV[I].SR;
      end;
    21: Result := FCutoff and 7;
    22: Result := FCutoff shr 3;
    23: Result := FResRoute;
    24: Result := FModeVol;
  end;
end;

function TSid.Read(Reg: Byte): Byte;
begin
  case Reg and $1F of
    $19, $1A: Result := $FF;                       // paddles
    $1B: Result := WaveOut(2) shr 4;               // voice 3's oscillator
    $1C: Result := FV[2].Env;                      // and its envelope
  else
    Result := FBus;                                // write-only registers read the bus
  end;
end;

procedure TSid.DoWrite(Reg, Value: Byte);
var
  I: Integer;
begin
  case Reg of
    0..20:
      begin
        I := Reg div 7;
        case Reg mod 7 of
          0: FV[I].Freq := (FV[I].Freq and $FF00) or Value;
          1: FV[I].Freq := (FV[I].Freq and $00FF) or (Value shl 8);
          2: FV[I].Pulse := (FV[I].Pulse and $0F00) or Value;
          3: FV[I].Pulse := (FV[I].Pulse and $00FF) or ((Value and $0F) shl 8);
          4:
            begin
              // The test bit holds the oscillator at zero (and resets the noise)
              if ((Value and 8) <> 0) and ((FV[I].Ctrl and 8) = 0) then
              begin
                FV[I].Acc := 0;
                FV[I].Shift := 0;
              end;
              if ((Value and 8) = 0) and ((FV[I].Ctrl and 8) <> 0) then FV[I].Shift := $7FFFF8;
              FV[I].Ctrl := Value;
              if (Value and 1) <> 0 then
              begin
                if not FV[I].GateOld then
                begin
                  FV[I].State := 0;
                  FV[I].Hold := False;
                end;
              end
              else if FV[I].GateOld then FV[I].State := 2;
              FV[I].GateOld := (Value and 1) <> 0;
            end;
          5: FV[I].AD := Value;
          6: FV[I].SR := Value;
        end;
      end;
    21: FCutoff := (FCutoff and $7F8) or (Value and 7);
    22: FCutoff := (FCutoff and 7) or (Value shl 3);
    23: FResRoute := Value;
    24: FModeVol := Value;
  end;
end;

{ The 12-bit output of voice I's oscillator }
function TSid.WaveOut(I: Integer): Integer;
var
  W: Integer;
  Acc: LongWord;
  Tri, Saw, Pul, Nz: Integer;
  Prev: Integer;
begin
  W := FV[I].Ctrl shr 4;
  if W = 0 then Exit(0);
  Acc := FV[I].Acc;
  Saw := Acc shr 12;
  Tri := Acc shr 11;
  if (Acc and $800000) <> 0 then Tri := not Tri;
  if (FV[I].Ctrl and 4) <> 0 then
  begin
    // Ring modulation: the triangle follows the other oscillator's MSB
    Prev := (I + 2) mod 3;
    if (FV[Prev].Acc and $800000) <> 0 then Tri := not Tri;
  end;
  Tri := Tri and $FFF;
  if (FV[I].Ctrl and 8) <> 0 then Pul := $FFF
  else if Saw >= FV[I].Pulse then Pul := $FFF else Pul := 0;
  Nz := FV[I].NoiseOut;
  Result := $FFF;
  if (W and 1) <> 0 then Result := Result and Tri;
  if (W and 2) <> 0 then Result := Result and Saw;
  if (W and 4) <> 0 then Result := Result and Pul;
  if (W and 8) <> 0 then Result := Result and Nz;
  // Combined waveforms are quieter than the AND of the parts on the real chip: dampen them a little
  if W in [3, 5, 6, 7] then Result := Result * 3 div 4;
end;

procedure TSid.ClockOne;
var
  I, Prev, Rate, Period: Integer;
  Old: LongWord;
  Bit: LongWord;
  V: ^TSidVoice;
begin
  for I := 0 to 2 do
  begin
    V := @FV[I];
    // Oscillator
    if (V^.Ctrl and 8) = 0 then
    begin
      Old := V^.Acc;
      V^.Acc := (V^.Acc + V^.Freq) and $FFFFFF;
      // Noise: the shift register moves when bit 19 of the accumulator rises
      if ((V^.Acc and $080000) <> 0) and ((Old and $080000) = 0) then
      begin
        Bit := ((V^.Shift shr 22) xor (V^.Shift shr 17)) and 1;
        V^.Shift := ((V^.Shift shl 1) or Bit) and $7FFFFF;
        V^.NoiseOut := ((V^.Shift and $400000) shr 11) or ((V^.Shift and $100000) shr 10) or ((V^.Shift and $010000) shr 7) or
          ((V^.Shift and $002000) shr 5) or ((V^.Shift and $000800) shr 4) or ((V^.Shift and $000080) shr 1) or
          ((V^.Shift and $000010) shl 1) or ((V^.Shift and $000004) shl 2);
      end;
    end;
    // Envelope
    case V^.State of
      0: Rate := V^.AD shr 4;
      1: Rate := V^.AD and $F;
    else
      Rate := V^.SR and $F;
    end;
    Period := RATE_PERIOD[Rate];
    Inc(V^.RateCnt);
    if V^.RateCnt >= Period then
    begin
      V^.RateCnt := 0;
      if V^.State = 0 then
      begin
        if not V^.Hold then
        begin
          Inc(V^.Env);
          if V^.Env = $FF then
          begin
            V^.State := 1;
            V^.RateCnt := 0;
          end;
        end;
      end
      else
      begin
        Inc(V^.ExpCnt);
        if V^.ExpCnt >= V^.ExpPeriod then
        begin
          V^.ExpCnt := 0;
          if (V^.State = 2) or (V^.Env <> (V^.SR shr 4) * 17) then
            if V^.Env > 0 then Dec(V^.Env);
        end;
      end;
      case V^.Env of
        $FF: V^.ExpPeriod := 1;
        $5D: V^.ExpPeriod := 2;
        $36: V^.ExpPeriod := 4;
        $1A: V^.ExpPeriod := 8;
        $0E: V^.ExpPeriod := 16;
        $06: V^.ExpPeriod := 30;
        $00: V^.ExpPeriod := 1;
      end;
    end;
  end;
  // Hard sync, after all the oscillators have moved
  for I := 0 to 2 do
  begin
    Prev := (I + 2) mod 3;
    if ((FV[I].Ctrl and 2) <> 0) and ((FV[Prev].Ctrl and 8) = 0) and (FV[Prev].Freq > 0) and
       (FV[Prev].Acc < FV[Prev].Freq) then
      FV[I].Acc := 0;
  end;
end;

procedure TSid.Generate(FrameCycles, SampleRate: Integer; Dest: PSmallInt; Count: Integer);
var
  S, C, Target, Wp, I, Routed: Integer;
  CyclesPerSample, Pos: Double;
  Cyc: Integer;
  Mix, Direct, Inp, F, Q, Hp, Outp, Vol: Single;
  Res: Integer;
  Wave: Integer;
begin
  CyclesPerSample := FrameCycles / Count;
  Cyc := 0;
  Wp := 0;
  Pos := 0;
  for S := 0 to Count - 1 do
  begin
    Pos := Pos + CyclesPerSample;
    Target := Trunc(Pos);
    while Cyc < Target do
    begin
      while (Wp < FWriteCount) and (FWrites[Wp].Cycle <= Cyc) do
      begin
        DoWrite(FWrites[Wp].Reg, FWrites[Wp].Value);
        Inc(Wp);
      end;
      ClockOne;
      Inc(Cyc);
    end;
    // Mix: each voice is its waveform (centred) times the envelope; some go through the filter
    Mix := 0;
    Direct := 0;
    Routed := FResRoute and 7;
    for I := 0 to 2 do
    begin
      Wave := WaveOut(I);
      FV[I].Out := ((Wave - $800) * FV[I].Env);
      Inp := FV[I].Out / (2048.0 * 255.0);
      // (the 6581 has a DC level in every voice, which makes the volume register audible by itself)
      Inp := Inp + 0.12;
      if I = 2 then
        if ((FModeVol and $80) <> 0) and ((Routed and 4) = 0) then Inp := 0;     // voice 3 off
      if (Routed and (1 shl I)) <> 0 then Mix := Mix + Inp else Direct := Direct + Inp;
    end;
    // State variable filter
    F := 2 * Sin(3.14159265 * (30 + FCutoff * 5.5) / SampleRate);
    if F > 1.0 then F := 1.0;
    Res := FResRoute shr 4;
    Q := 1.0 / (0.7 + Res * 0.13);
    Hp := Mix - FLow - Q * FBand;
    FBand := FBand + F * Hp;
    FLow := FLow + F * FBand;
    Outp := Direct;
    if (FModeVol and $10) <> 0 then Outp := Outp + FLow;
    if (FModeVol and $20) <> 0 then Outp := Outp + FBand;
    if (FModeVol and $40) <> 0 then Outp := Outp + Hp;
    Vol := (FModeVol and $F) / 15.0;
    Outp := Outp * Vol * 0.32;
    if Outp > 1 then Outp := 1;
    if Outp < -1 then Outp := -1;
    Dest[S * 2] := Round(Outp * 30000);
    Dest[S * 2 + 1] := Dest[S * 2];
  end;
  // The writes of the last cycles
  while Wp < FWriteCount do
  begin
    DoWrite(FWrites[Wp].Reg, FWrites[Wp].Value);
    Inc(Wp);
  end;
  while Cyc < FrameCycles do
  begin
    ClockOne;
    Inc(Cyc);
  end;
end;

procedure TSid.EndFrame;
begin
  FWriteCount := 0;
end;

end.

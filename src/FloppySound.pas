unit FloppySound;

{ The noise of a floppy drive, one sample at a time (44100 Hz): the motor's whir, the head scratching the disk
  while it turns under it (with the grains of the oxide) and the stepper's knocks.
  A step is not a tone: it is a burst of noise that rings the drive's mechanics (a few resonances of the
  frame, the rails and the head carriage), and a knock against the stop at track 0 is a deeper, louder thump
  with a rattle. The excitations of the steps go into the same resonators, so a seek sounds as the buzz of
  steps one after another, as on the real drives.
  While the disk turns and no step has been heard for 3 seconds, the head moves by itself now and then (a
  short random seek of a few steps), as a real drive seems to do while the program works. }

{$mode objfpc}{$H+}

interface

type
  { A two-pole band-pass (RBJ, constant 0 dB peak) }
  TResonator = record
    B0, A1, A2: Single;
    X1, X2, Y1, Y2: Single;
  end;

  TFloppyKind = (fkSpectrum, fkC64);

  TFloppySound = class
  private
    FRate: Integer;
    FKind: TFloppyKind;
    FExciteSecs: Double;
    FSeed: LongWord;
    FMotorPhase, FTurnPhase, FMotorHz, FTurnHz: Single;
    FHiss, FHissLP, FGrainEnv, FRumble: Single;
    FStep: array[0..3] of TResonator;      // the mechanics rung by a step
    FStepGain: array[0..3] of Single;
    FBump: array[0..1] of TResonator;      // the thump against the stop
    FScratch: array[0..1] of TResonator;   // the head on the disk
    FGrain: TResonator;                    // the grains of the oxide
    FStepGap: Integer;                     // samples between the steps of a seek of its own
    FQuiet: Integer;                       // samples since the last step was heard
    FIdleWait: Integer;                    // samples of quiet before the next seek of its own
    FIdleT, FIdleN: Integer;               // that seek: samples since it started and its steps (0: none)
    procedure NextIdleWait;
    function IdleSteps(Spinning: Boolean; Steps, Bumps: Single): Single;
    function Rnd: Single; inline;
  public
    constructor Create(Kind: TFloppyKind; Rate: Integer = 44100);
    { The excitation of one step Age seconds after it (0 once it has ended): add those of all the steps
      still sounding and give the sum to Sample. Bump: the head knocked against the stop }
    function StepExcite(Age: Double; Bump: Boolean): Single;
    { The next sample: the motor (Spinning), the head on the disk (Reading) and the steps' excitation }
    function Sample(Spinning, Reading: Boolean; Steps, Bumps: Single): Single;
    { How long a step's excitation lasts for this drive (STEP_EXCITE_SECS or C64_STEP_EXCITE_SECS) }
    property ExciteSecs: Double read FExciteSecs;
  end;

const
  { A step's excitation lasts this long (the ringing goes on in the resonators) }
  STEP_EXCITE_SECS = 0.004;
  { The 1541's step is longer: its stepper's rotor bounces around the new position, a short deep "prrrt" }
  C64_STEP_EXCITE_SECS = 0.032;
  { The quiet (seconds) after which the head moves by itself now and then, and the most extra random wait }
  IDLE_SEEK_QUIET = 3.0;
  IDLE_SEEK_EXTRA = 4.0;

implementation

uses
  Math;

procedure SetBandPass(var R: TResonator; Freq, Q: Double; Rate: Integer);
var
  W, Alpha, A0: Double;
begin
  W := 2 * Pi * Freq / Rate;
  Alpha := Sin(W) / (2 * Q);
  A0 := 1 + Alpha;
  R.B0 := Alpha / A0;
  R.A1 := -2 * Cos(W) / A0;
  R.A2 := (1 - Alpha) / A0;
  R.X1 := 0; R.X2 := 0; R.Y1 := 0; R.Y2 := 0;
end;

function Run(var R: TResonator; X: Single): Single; inline;
begin
  // b1 = 0, b2 = -b0 for the band-pass
  Result := R.B0 * (X - R.X2) - R.A1 * R.Y1 - R.A2 * R.Y2;
  if Abs(Result) < 1E-20 then Result := 0;
  R.X2 := R.X1; R.X1 := X;
  R.Y2 := R.Y1; R.Y1 := Result;
end;

constructor TFloppySound.Create(Kind: TFloppyKind; Rate: Integer);
begin
  FRate := Rate;
  FKind := Kind;
  FSeed := 22695477;
  if Kind = fkC64 then FExciteSecs := C64_STEP_EXCITE_SECS else FExciteSecs := STEP_EXCITE_SECS;
  if Kind = fkC64 then
  begin
    // The 1541: a big metal frame and a loud stepper on a worm gear: low and mid resonances, a rattly top
    FMotorHz := 60; FTurnHz := 300 / 60;
    SetBandPass(FStep[0], 230, 4, Rate);   FStepGain[0] := 1.3;
    SetBandPass(FStep[1], 700, 4, Rate);   FStepGain[1] := 0.9;
    SetBandPass(FStep[2], 1900, 3, Rate);  FStepGain[2] := 0.5;
    SetBandPass(FStep[3], 4200, 3, Rate);  FStepGain[3] := 0.25;
    SetBandPass(FBump[0], 140, 5, Rate);
    SetBandPass(FBump[1], 820, 3, Rate);
    SetBandPass(FScratch[0], 1900, 1.2, Rate);
    SetBandPass(FScratch[1], 4300, 1.5, Rate);
    SetBandPass(FGrain, 3200, 6, Rate);
  end
  else
  begin
    // The 3" and 3.5" drives: lighter, a higher and drier click
    FMotorHz := 95; FTurnHz := 300 / 60;
    SetBandPass(FStep[0], 650, 5, Rate);   FStepGain[0] := 0.7;
    SetBandPass(FStep[1], 1600, 5, Rate);  FStepGain[1] := 1.0;
    SetBandPass(FStep[2], 3300, 4, Rate);  FStepGain[2] := 0.7;
    SetBandPass(FStep[3], 6500, 3, Rate);  FStepGain[3] := 0.4;
    SetBandPass(FBump[0], 220, 5, Rate);
    SetBandPass(FBump[1], 1100, 3, Rate);
    SetBandPass(FScratch[0], 2200, 1.2, Rate);
    SetBandPass(FScratch[1], 5000, 1.5, Rate);
    SetBandPass(FGrain, 3800, 6, Rate);
  end;
  // The step rate of a seek: the 1541's stepper is slow, the 3" and 3.5" drives step every 6 ms
  if Kind = fkC64 then FStepGap := Round(0.014 * Rate) else FStepGap := Round(0.006 * Rate);
  NextIdleWait;
end;

procedure TFloppySound.NextIdleWait;
begin
  FIdleWait := Round((IDLE_SEEK_QUIET + IDLE_SEEK_EXTRA * (Rnd + 1) / 2) * FRate);
end;

{ The excitation of the head's seeks of its own: one starts after a random quiet while the disk turns }
function TFloppySound.IdleSteps(Spinning: Boolean; Steps, Bumps: Single): Single;
var
  K: Integer;
  U: Single;
begin
  Result := 0;
  if FIdleN > 0 then
  begin
    for K := 0 to FIdleN - 1 do
      Result := Result + StepExcite((FIdleT - K * FStepGap) / FRate, False);
    Inc(FIdleT);
    if FIdleT >= (FIdleN - 1) * FStepGap + Round(FExciteSecs * FRate) then
    begin
      FIdleN := 0;
      FQuiet := 0;
      NextIdleWait;
    end;
    Exit;
  end;
  if (Steps <> 0) or (Bumps <> 0) or not Spinning then
  begin
    // A real step (or the motor stopped): the quiet starts again
    FQuiet := 0;
    Exit;
  end;
  Inc(FQuiet);
  if FQuiet >= FIdleWait then
  begin
    // Mostly a step or two, sometimes a longer seek
    U := (Rnd + 1) / 2;
    if U < 0.45 then FIdleN := 1
    else if U < 0.75 then FIdleN := 2
    else FIdleN := 3 + Trunc(((Rnd + 1) / 2) * 6);
    FIdleT := 0;
  end;
end;

function TFloppySound.Rnd: Single;
begin
  FSeed := FSeed * 1103515245 + 12345;
  Result := ((FSeed shr 9) and $7FFF) / 16384 - 1;
end;

function TFloppySound.StepExcite(Age: Double; Bump: Boolean): Single;
const
  // The 1541's rotor bounce: a hit every half period of its swing, each one weaker and of the other side
  BOUNCE = 0.0042;
var
  K: Integer;
  T: Double;
begin
  if (Age < 0) or (Age >= FExciteSecs) then Exit(0);
  if FKind = fkC64 then
  begin
    K := Trunc(Age / BOUNCE);
    T := Age - K * BOUNCE;
    Result := 0;
    if T < 0.0005 then
    begin
      Result := (1.3 + 0.4 * Rnd) * Power(0.78, K);
      if Odd(K) then Result := -Result;
    end;
    // The gear's grit all along
    Result := Result + 0.35 * Rnd * Exp(-Age / 0.012);
    if Bump then Result := Result * 1.6;
    Exit;
  end;
  // A hard hit (the first fraction of a millisecond) and the noise of the gear right after it
  Result := Rnd * Exp(-Age / 0.0007);
  if Age < 0.00012 then Result := Result + 1.5;
  if Bump then Result := Result * 1.6;
end;

function TFloppySound.Sample(Spinning, Reading: Boolean; Steps, Bumps: Single): Single;
var
  I: Integer;
  N, Turn, S: Single;
begin
  Result := 0;
  Steps := Steps + IdleSteps(Spinning, Steps, Bumps);
  if Spinning then
  begin
    // The motor: a hum with its harmonics and a little rumble of the bearings
    FMotorPhase := FMotorPhase + 2 * Pi * FMotorHz / FRate;
    if FMotorPhase > 2 * Pi then FMotorPhase := FMotorPhase - 2 * Pi;
    FTurnPhase := FTurnPhase + 2 * Pi * FTurnHz / FRate;
    if FTurnPhase > 2 * Pi then FTurnPhase := FTurnPhase - 2 * Pi;
    FRumble := FRumble * 0.995 + Rnd * 0.005;
    Result := Result + 0.012 * Sin(FMotorPhase) + 0.007 * Sin(2 * FMotorPhase) + 0.004 * Sin(5 * FMotorPhase)
      + 0.25 * FRumble;
    N := Rnd;
    if Reading then
    begin
      // The head on the disk: a steady soft hiss and the grains (it barely changes along a turn: a strong
      // beat once a turn sounds like a steam train)
      Turn := 1 + 0.04 * Sin(FTurnPhase);
      S := Run(FScratch[0], N) * 0.9 + Run(FScratch[1], N) * 0.6;
      FHissLP := FHissLP * 0.9 + Abs(S) * 0.1;
      // A grain now and then, more where the disk rubs harder
      if (Rnd > 0.985 - 0.01 * Turn) then FGrainEnv := 0.6 + 0.4 * Abs(Rnd);
      FGrainEnv := FGrainEnv * 0.93;
      Result := Result + Turn * (0.045 * S + 0.015 * Sign(S) * FHissLP)
        + 0.35 * Run(FGrain, FGrainEnv * Rnd);
    end
    else
    begin
      // Turning with the head lifted (or no disk): only a faint air
      FHiss := FHiss * 0.8 + N * 0.2;
      Result := Result + 0.006 * FHiss;
    end;
  end;
  for I := 0 to High(FStep) do
    Result := Result + 0.55 * FStepGain[I] * Run(FStep[I], Steps);
  Result := Result + 0.9 * Run(FBump[0], Bumps) + 0.5 * Run(FBump[1], Bumps);
  // A soft clip: the knocks are loud, but never a harsh digital clip
  if Result > 1 then Result := 1 else if Result < -1 then Result := -1;
  Result := Result * (1.5 - 0.5 * Result * Result);
end;

end.

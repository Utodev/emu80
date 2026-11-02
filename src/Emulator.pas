{ Emulator: runs the Spectrum on a background thread at real speed.

  All access to the TSpectrum from the UI must happen between Lock and
  Unlock. Each finished frame is copied to a display buffer and the UI is
  notified through OnFrame (called on the main thread). }
unit Emulator;

{$mode objfpc}{$H+}

interface

uses
  {$IFDEF WINDOWS}Windows,{$ENDIF}   // before SyncObjs: Windows has its own TCriticalSection
  {$IFDEF UNIX}BaseUnix, Unix,{$ENDIF}
  Classes, SysUtils, SyncObjs, Models, Spectrum, Audio, Disasm;

type
  TEmulator = class;

  TEmuThread = class(TThread)
  private
    FOwner: TEmulator;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TEmulator);
  end;

  TEmulator = class
  private
    FSpec: TSpectrum;
    FLock: TCriticalSection;
    FDisplayLock: TCriticalSection;   // guards FDisplay only
    FThread: TEmuThread;
    FAudio: TAudioOutput;
    FDisplay: array of LongWord;
    FPrevDisplay: array of LongWord;   // the frame before: the other field, to deinterlace
    FDisplayOdd: Boolean;              // FDisplay is an odd field (frames alternate)
    FFramePending: Boolean;
    FPaused: Boolean;
    FTurbo: Boolean;
    FSound: Boolean;
    FOnFrame: TNotifyEvent;
    FOnBreak: TNotifyEvent;
    FHosted: Boolean;
    FOnHostFrame: TNotifyEvent;
    FOnHostBreak: TNotifyEvent;
    FIdle: Boolean;           // thread is parked in the paused state
    FFps: Integer;
    FFrameCounter: Integer;
    FFpsStart: Int64;
    FBack: array of TMachineState;   // before the last steps, oldest first
    procedure NotifyBreak;
    procedure FrameDone;
    procedure NotifyFrame;
    function GetRunning: Boolean;
    procedure StepOne;
  public
    constructor Create(AModel: TSpectrumModel; const RomDir: string);
    destructor Destroy; override;
    procedure Start;
    procedure Lock;
    procedure Unlock;
    { Copy the latest frame (FB_WIDTH x SCREEN_HEIGHT $00RRGGBB pixels). }
    procedure CopyDisplay(Dest: PLongWord);
    { The latest frame and the one before it (the two fields of an interlaced
      picture), and whether the latest is the odd field }
    procedure CopyFields(Cur, Prev: PLongWord; out CurOdd: Boolean);
    property Spec: TSpectrum read FSpec;
    property Paused: Boolean read FPaused write FPaused;
    property Turbo: Boolean read FTurbo write FTurbo;
    property Sound: Boolean read FSound write FSound;
    property Fps: Integer read FFps;
    property OnFrame: TNotifyEvent read FOnFrame write FOnFrame;
    { The library's way (a host with no main thread of ours to queue to):
      with Hosted the frames and the breakpoint stops are not queued, but
      told from the emulation thread through these (the break one is also
      readable as Paused and Spec.BreakKind) }
    property Hosted: Boolean read FHosted write FHosted;
    property OnHostFrame: TNotifyEvent read FOnHostFrame write FOnHostFrame;
    property OnHostBreak: TNotifyEvent read FOnHostBreak write FOnHostBreak;
    { Stop the thread for good (Start runs it again) }
    procedure StopThread;
    property Running: Boolean read GetRunning;
    { Called on the main thread when a breakpoint pauses the emulation. }
    property OnBreak: TNotifyEvent read FOnBreak write FOnBreak;
    { Debugger commands; call them while paused, without holding the lock. }
    { Pause and wait until the emulation thread has really stopped. }
    procedure PauseAndWait;
    procedure Resume;
    procedure StepInto;
    procedure StepOver;
    procedure RunTo(Addr: Word);
    { Step back: StepInto, StepOver and RunTo (and the debugger's Run, with
      SaveBackPoint) keep the machine as it was, up to MAX_BACK times;
      StepBack puts the last one back. False if there is none. }
    procedure SaveBackPoint;
    function StepBack: Boolean;
    function BackCount: Integer;
    { Forget them (another machine is not put back where an earlier one was) }
    procedure ClearBackPoints;
    { Refresh the display buffer from the machine (after stepping). }
    procedure UpdateDisplay;
  end;

const
  MAX_BACK = 10;

function MicroTime: Int64;

implementation

function MicroTime: Int64;
{$IFDEF WINDOWS}
var
  Count, Freq: Int64;
begin
  QueryPerformanceFrequency(Freq);
  QueryPerformanceCounter(Count);
  Result := Round(Count / Freq * 1000000);
end;
{$ELSE}
var
  TV: TTimeVal;
begin
  fpGetTimeOfDay(@TV, nil);
  Result := Int64(TV.tv_sec) * 1000000 + TV.tv_usec;
end;
{$ENDIF}

{ TEmuThread }

constructor TEmuThread.Create(AOwner: TEmulator);
begin
  FOwner := AOwner;
  FreeOnTerminate := False;
  inherited Create(True);
end;

procedure TEmuThread.Execute;
var
  NextTime, Now, FrameUs, TurboYield: Int64;
  Queued, Broke, Fast: Boolean;
begin
  Fast := False;
  NextTime := MicroTime;
  TurboYield := NextTime;
  while not Terminated do
  begin
    if FOwner.FPaused then
    begin
      FOwner.FIdle := True;
      Sleep(5);
      NextTime := MicroTime;
      Continue;
    end;

    FOwner.FIdle := False;
    FOwner.FLock.Enter;
    try
      FOwner.FSpec.Muted := not FOwner.FSound or Fast;
      Broke := not FOwner.FSpec.RunFrame;
      // Turbo, or a tape playing in real time with fast loading on (turbo
      // loaders, recordings: what the ROM trap can't take): as fast as
      // possible, the tape and the CPU keeping their own T-state clock
      Fast := FOwner.FTurbo or FOwner.FSpec.TapeAccelerating or FOwner.FSpec.DiskAccelerating;
      if Broke then
      begin
        // Breakpoint: stop here and show the picture up to the beam position
        FOwner.FPaused := True;
        FOwner.FSpec.RenderToCurrent;
      end;
      FrameUs := Int64(FOwner.FSpec.Info.FrameT) * 1000000 div FOwner.FSpec.Info.ClockHz;
      FOwner.FDisplayLock.Enter;
      try
        Move(FOwner.FDisplay[0], FOwner.FPrevDisplay[0], Length(FOwner.FDisplay) * SizeOf(LongWord));
        FOwner.FSpec.CopyFrameBuffer(@FOwner.FDisplay[0]);
        FOwner.FDisplayOdd := not FOwner.FDisplayOdd;
      finally
        FOwner.FDisplayLock.Leave;
      end;
    finally
      FOwner.FLock.Leave;
    end;
    FOwner.FrameDone;
    if Broke then
    begin
      if FOwner.FHosted then
      begin
        if Assigned(FOwner.FOnHostBreak) then FOwner.FOnHostBreak(FOwner);
      end
      else
        TThread.Queue(Self, @FOwner.NotifyBreak);
      Continue;
    end;

    if Fast then
    begin
      // Critical sections are not fair: without an occasional pause the UI
      // thread would never get the lock while running flat out.
      Now := MicroTime;
      if Now - TurboYield >= 20000 then
      begin
        Sleep(1);
        TurboYield := MicroTime;
      end;
      NextTime := Now;
      Continue;
    end;
    TurboYield := MicroTime;

    // Audio pacing: blocks while the device buffers are full
    Queued := False;
    if FOwner.FAudio <> nil then
      Queued := FOwner.FAudio.Write(FOwner.FSpec.Samples, FOwner.FSpec.SampleCount);
    if Queued then
    begin
      NextTime := MicroTime;
      Continue;
    end;

    // Timer pacing
    Inc(NextTime, FrameUs);
    Now := MicroTime;
    if NextTime - Now > 1000 then
      Sleep((NextTime - Now) div 1000)
    else if Now - NextTime > 100000 then
      NextTime := Now;   // fell too far behind: resynchronise
  end;
end;

{ TEmulator }

constructor TEmulator.Create(AModel: TSpectrumModel; const RomDir: string);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FDisplayLock := TCriticalSection.Create;
  FSpec := TSpectrum.Create(AModel, RomDir);
  SetLength(FDisplay, FB_WIDTH * SCREEN_HEIGHT);
  SetLength(FPrevDisplay, FB_WIDTH * SCREEN_HEIGHT);
  FSound := True;
  FAudio := TAudioOutput.Create(SAMPLE_RATE, 4, 1024);
  if not FAudio.IsOpen then FreeAndNil(FAudio);
  FFpsStart := MicroTime;
end;

destructor TEmulator.Destroy;
var
  I: Integer;
begin
  if FThread <> nil then
  begin
    FThread.Terminate;
    FThread.WaitFor;
    TThread.RemoveQueuedEvents(FThread);
    FThread.Free;
  end;
  FAudio.Free;
  for I := 0 to High(FBack) do FBack[I].Free;
  FSpec.Free;
  FDisplayLock.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TEmulator.Start;
begin
  if FThread <> nil then Exit;
  FThread := TEmuThread.Create(Self);
  FThread.Start;
end;

procedure TEmulator.StopThread;
begin
  if FThread = nil then Exit;
  FThread.Terminate;
  FThread.WaitFor;
  TThread.RemoveQueuedEvents(FThread);
  FreeAndNil(FThread);
  FIdle := True;
end;

function TEmulator.GetRunning: Boolean;
begin
  Result := FThread <> nil;
end;

procedure TEmulator.Lock;
begin
  FLock.Enter;
end;

procedure TEmulator.Unlock;
begin
  FLock.Leave;
end;

procedure TEmulator.CopyDisplay(Dest: PLongWord);
begin
  FDisplayLock.Enter;
  try
    Move(FDisplay[0], Dest^, Length(FDisplay) * SizeOf(LongWord));
  finally
    FDisplayLock.Leave;
  end;
end;

procedure TEmulator.FrameDone;
var
  Now: Int64;
begin
  Inc(FFrameCounter);
  Now := MicroTime;
  if Now - FFpsStart >= 1000000 then
  begin
    FFps := Round(FFrameCounter * 1000000 / (Now - FFpsStart));
    FFrameCounter := 0;
    FFpsStart := Now;
  end;
  if FHosted then
  begin
    if Assigned(FOnHostFrame) then FOnHostFrame(Self);
    Exit;
  end;
  // Only one notification in flight, so a slow UI never queues a backlog
  if not FFramePending then
  begin
    FFramePending := True;
    TThread.Queue(FThread, @NotifyFrame);
  end;
end;

procedure TEmulator.NotifyBreak;
begin
  if Assigned(FOnBreak) then FOnBreak(Self);
end;

procedure TEmulator.PauseAndWait;
var
  Waited: Integer;
begin
  FPaused := True;
  Waited := 0;
  while not FIdle and (Waited < 500) do
  begin
    Sleep(1);
    Inc(Waited);
  end;
end;

procedure TEmulator.Resume;
begin
  FLock.Enter;
  try
    FSpec.SkipBreakpointOnce;   // don't stop again at the breakpoint we are on
  finally
    FLock.Leave;
  end;
  FIdle := False;   // so a following PauseAndWait waits for the thread
  FPaused := False;
end;

procedure TEmulator.SaveBackPoint;
var
  I: Integer;
begin
  FLock.Enter;
  try
    if Length(FBack) >= MAX_BACK then
    begin
      FBack[0].Free;
      for I := 0 to High(FBack) - 1 do FBack[I] := FBack[I + 1];
      SetLength(FBack, Length(FBack) - 1);
    end;
    SetLength(FBack, Length(FBack) + 1);
    FBack[High(FBack)] := FSpec.SaveState;
  finally
    FLock.Leave;
  end;
end;

function TEmulator.StepBack: Boolean;
var
  S: TMachineState;
begin
  Result := False;
  FLock.Enter;
  try
    while (Length(FBack) > 0) and not Result do
    begin
      S := FBack[High(FBack)];
      SetLength(FBack, Length(FBack) - 1);
      // A state of another model (changed since) is dropped
      Result := FSpec.LoadState(S);
      S.Free;
    end;
  finally
    FLock.Leave;
  end;
  if Result then UpdateDisplay;
end;

function TEmulator.BackCount: Integer;
begin
  Result := Length(FBack);
end;

procedure TEmulator.ClearBackPoints;
var
  I: Integer;
begin
  FLock.Enter;
  try
    for I := 0 to High(FBack) do FBack[I].Free;
    FBack := nil;
  finally
    FLock.Leave;
  end;
end;

procedure TEmulator.StepOne;
begin
  FLock.Enter;
  try
    FSpec.StepInstruction;
  finally
    FLock.Leave;
  end;
  UpdateDisplay;
end;

procedure TEmulator.StepInto;
begin
  SaveBackPoint;
  StepOne;
end;

procedure TEmulator.StepOver;
var
  Len: Integer;
  Over: Boolean;
begin
  SaveBackPoint;
  FLock.Enter;
  try
    Over := IsStepOver(FSpec.Cpu.PC.W, @FSpec.Peek);
    if Over then
    begin
      Disassemble(FSpec.Cpu.PC.W, @FSpec.Peek, Len);
      // esxDOS calls are RST $08 followed by a function byte, and return
      // after that byte
      if FSpec.DivMMCOn and (FSpec.Peek(FSpec.Cpu.PC.W) = $CF) then Len := 2;
      FSpec.TempBreak := Word(FSpec.Cpu.PC.W + Len);
    end;
  finally
    FLock.Leave;
  end;
  if Over then Resume else StepOne;
end;

procedure TEmulator.RunTo(Addr: Word);
begin
  SaveBackPoint;
  FLock.Enter;
  try
    FSpec.TempBreak := Addr;
  finally
    FLock.Leave;
  end;
  Resume;
end;

procedure TEmulator.CopyFields(Cur, Prev: PLongWord; out CurOdd: Boolean);
begin
  FDisplayLock.Enter;
  try
    Move(FDisplay[0], Cur^, Length(FDisplay) * SizeOf(LongWord));
    Move(FPrevDisplay[0], Prev^, Length(FPrevDisplay) * SizeOf(LongWord));
    CurOdd := FDisplayOdd;
  finally
    FDisplayLock.Leave;
  end;
end;

procedure TEmulator.UpdateDisplay;
begin
  FLock.Enter;
  try
    FDisplayLock.Enter;
    try
      FSpec.CopyFrameBuffer(@FDisplay[0]);
    finally
      FDisplayLock.Leave;
    end;
  finally
    FLock.Leave;
  end;
  if Assigned(FOnFrame) then FOnFrame(Self);
end;

procedure TEmulator.NotifyFrame;
begin
  FFramePending := False;
  if Assigned(FOnFrame) then FOnFrame(Self);
end;

end.

{ Tape: tape image (block list), TAP and TZX files, and real-time EAR signal
  generation: the standard ROM loader timings for TAP blocks, and every
  kind of signal of TZX 1.20 (turbo data, tones, pulse sequences, direct
  and CSW recordings, generalized data), with its flow control (loops,
  jumps, calls, stops). }
unit Tape;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, Generics.Collections;

const
  // TZX block kinds (their IDs); a TAP block is a standard one
  TZX_STANDARD = $10;
  TZX_TURBO = $11;
  TZX_TONE = $12;
  TZX_PULSES = $13;
  TZX_PURE_DATA = $14;
  TZX_DIRECT = $15;
  TZX_CSW = $18;
  TZX_GENERALIZED = $19;
  TZX_PAUSE = $20;
  TZX_GROUP_START = $21;
  TZX_GROUP_END = $22;
  TZX_JUMP = $23;
  TZX_LOOP_START = $24;
  TZX_LOOP_END = $25;
  TZX_CALL = $26;
  TZX_RETURN = $27;
  TZX_SELECT = $28;
  TZX_STOP_48K = $2A;
  TZX_LEVEL = $2B;
  TZX_TEXT = $30;
  TZX_MESSAGE = $31;
  TZX_ARCHIVE = $32;
  TZX_HARDWARE = $33;
  TZX_CUSTOM = $35;
  TZX_GLUE = $5A;

type
  { How a pulse starts: the level turned over (an edge), kept, or set }
  TPulseStart = (psToggle, psKeep, psLow, psHigh);

  { A symbol of a generalized data block: how it starts and its pulses }
  TGenSymbol = record
    Start: TPulseStart;
    Pulses: array of Integer;
  end;

  TGenSymbols = array of TGenSymbol;

  { A symbol of the pilot and sync part, repeated }
  TGenRun = record
    Symbol: Integer;
    Count: Integer;
  end;

  TTapeBlock = class
  private
    FDuration: Double;     // T-states (with the pause), worked out once
  public
    Kind: Byte;     // the TZX ID; TZX_STANDARD for TAP blocks
    Data: TBytes;   // data blocks: flag byte + payload + checksum, as in a TAP file;
                    // direct recordings: the samples; generalized data: the symbols
    PauseMs: Integer;
    // Pulse lengths in T-states (standard, turbo, tone and pure data blocks)
    PilotLen, PilotCount, Sync1Len, Sync2Len, ZeroLen, OneLen: Integer;
    UsedBits: Integer;            // bits of the last byte of Data that are used (1..8)
    Pulses: array of Integer;     // pulse sequences; CSW recordings (as T-states)
    SampleT: Integer;             // direct recordings: T-states a sample
    Text: string;                 // groups, texts, messages, archive info, selections...
    Value: Integer;               // jumps, loop repetitions, signal level, message seconds
    Calls: array of Integer;      // call sequences (relative)
    GenPilot, GenData: TGenSymbols;
    GenRuns: array of TGenRun;
    GenCount: Integer;            // symbols in the data stream
    GenBits: Integer;             // bits a symbol of the data stream
    { A standard block (TAP), with the ROM's timings }
    constructor Create(const AData: TBytes);
    { An empty block of a TZX kind }
    constructor CreateKind(AKind: Byte);
    function Flag: Integer;
    function IsHeader: Boolean;
    function Description: string;
    function ChecksumOK: Boolean;
    { Carries bytes in the ROM's layout (standard, turbo, pure data) }
    function IsData: Boolean;
    { Data the ROM's loader can read: fast loading takes it at once }
    function FitsRom: Boolean;
    { Takes no time on the tape: information, groups, flow control }
    function IsInfo: Boolean;
    { How long it plays, in T-states, its pause included }
    function DurationT(ClockHz: Integer): Double;
    { Bit Index (from 0, most significant first) of Data }
    function BitAt(Index: Integer): Boolean;
    function DataBits: Integer;
  end;

  TTapeEdgeEvent = procedure(T: Integer; Level: Boolean) of object;

  TTapeState = (tsStopped, tsPilot, tsSync1, tsSync2, tsData, tsPause, tsPulses, tsDirect,
    tsGenPilot, tsGenData);

  TTape = class
  private
    FBlocks: specialize TObjectList<TTapeBlock>;
    FCurrent: Integer;
    FState: TTapeState;
    FNextEdgeT: Integer;
    FLevel: Boolean;
    FPulsesLeft: Integer;
    FBytePos: Integer;
    FBitMask: Byte;
    FBitsLeft: Integer;
    FSecondHalf: Boolean;
    FPauseDrop: Boolean;    // pause started with the line high
    FOwed: Boolean;         // a pulse is going on: its end is an edge
    FIndex: Integer;        // pulse, run or symbol being played
    FRunLeft: Integer;      // generalized data: repetitions left of the run
    FSymbol: Integer;       // generalized data: the symbol being played
    FSymPulse: Integer;     // ... and its pulse
    FLoopStart, FLoopLeft: Integer;
    FLoop: Boolean;
    FStoppedByBlock: Boolean;
    FEpoch: Integer;
    FCallBlock, FCallPos: Integer;
    FStopIf48K: Boolean;
    FFileName: string;
    FModified: Boolean;
    FOnEdge: TTapeEdgeEvent;
    FOnChange: TNotifyEvent;
    FClockHz: Integer;
    FFinalEdge: Boolean;
    FHeld: TTapeState;               // where the tape was stopped in place (Hold), tsStopped if it wasn't
    FHeldEpoch: Integer;
    FStretchNum, FStretchDen: Integer;     // pulse lengths are scaled by Num / Den
    FChangeCount: Integer;
    function GetCount: Integer;
    function GetBlock(Index: Integer): TTapeBlock;
    function GetPlaying: Boolean;
    procedure StartBlock(T: Integer);
    procedure SetupBlock;
    procedure NextEvent;
    procedure SetLevel(Value: Boolean);
    procedure StartPulse(Len: Integer; How: TPulseStart);
    procedure BeginData(B: TTapeBlock);
    function BeginPause(B: TTapeBlock): Boolean;
    function MsT(Ms: Integer): Int64;
    function NextSignal(From: Integer): Integer;
    procedure Changed;
    function CurrentBit: Boolean;
    procedure Loaded;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure LoadTAP(const FileName: string);
    procedure LoadTAPFromStream(S: TStream);
    procedure LoadTZX(const FileName: string);
    procedure LoadTZXFromStream(S: TStream);
    { A tape file: .tzx as TZX, anything else as TAP }
    procedure LoadFile(const FileName: string);
    { Only the data blocks (standard, turbo and pure data) go into a TAP }
    procedure SaveTAP(const FileName: string);
    { The whole tape as a TZX (.tzx, or .cdt for the Amstrad CPC: the same
      format). Raises if it has blocks that can't be written (CSW recordings,
      generalized data and flow control). }
    procedure SaveTZX(const FileName: string);
    { A recorded signal: the pulses (in T-states of a 3.5 MHz machine), as
      pulse sequence blocks, after a pause of PauseMs }
    procedure AddPulses(const Pulses: array of Integer; PauseMs: Integer);
    { Has blocks a TAP file can't keep (turbo, recordings, information...) }
    function HasNonStandard: Boolean;
    { Blocks of a TZX kind (such as TZX_STANDARD: the Spectrum ROM's timing, which
      an Amstrad CPC can't read) }
    function CountKind(Kind: Byte): Integer;
    procedure Play(T: Integer);
    procedure Stop;
    procedure Rewind;
    procedure SelectBlock(Index: Integer);
    procedure DeleteBlock(Index: Integer);
    procedure MoveBlock(FromIndex, ToIndex: Integer);
    procedure AddBlock(const Data: TBytes);
    { Advance the signal up to frame T-state T, firing OnEdge for each edge. }
    procedure AdvanceTo(T: Integer);
    { Called at end of frame so pending times stay frame-relative. }
    procedure EndFrame(FrameT: Integer);
    { Fast-load support: take the next block the ROM can read and move past
      it; nil if the next one isn't (turbo data...: it plays in real time) }
    function TakeBlockForTrap: TTapeBlock;
    { What comes next on the tape is a signal the ROM can't read (turbo
      data...): after fast loading, the tape goes on playing for it }
    function NextNeedsRealTime: Boolean;
    { Fast loading switched on while a block's data is playing: that block
      (nil if none is, or the ROM can't read it), the byte playing now in
      BytePos, and the tape stopped at the next one }
    function TakeBlockBeingRead(out BytePos: Integer): TTapeBlock;
    property Count: Integer read GetCount;
    property Blocks[Index: Integer]: TTapeBlock read GetBlock; default;
    property Current: Integer read FCurrent;
    property Playing: Boolean read GetPlaying;
    { At the end of the tape play goes on from its start }
    property Loop: Boolean read FLoop write FLoop;
    { A TZX block stopped the tape ("stop the tape", or "stop if 48K"): until
      it is played again }
    property StoppedByBlock: Boolean read FStoppedByBlock;
    { Counts what the user does to the position or the tape in it: Rewind, a
      block chosen, a tape put in or ejected }
    property Epoch: Integer read FEpoch;
    { Something is left to play: blocks after the current one, or the start
      again when the tape loops }
    function HasMore: Boolean;
    property State: TTapeState read FState;
    { How far the tape has played, 0..1, by time (for a cassette's reels) }
    function Progress: Double;
    property Level: Boolean read FLevel;
    property FileName: string read FFileName;
    property Modified: Boolean read FModified;
    property OnEdge: TTapeEdgeEvent read FOnEdge write FOnEdge;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    { Incremented on every change, so a UI on another thread can poll it. }
    property ChangeCount: Integer read FChangeCount;
    property ClockHz: Integer read FClockHz write FClockHz;
    { A TZX gives its pulses in T-states of a 3.5 MHz machine: a faster CPU
      (the SAM Coupe's 6 MHz) stretches them (Num / Den = 12 / 7) so they
      keep their length in time. Pauses (in ms) are not affected. }
    procedure SetPulseScale(Num, Den: Integer);
    { The last block of a tape with no pause ends with the edge its last pulse has (a loader of the SAM needs it) }
    property FinalEdge: Boolean read FFinalEdge write FFinalEdge;
    { Stop the tape where it is, in the middle of a block too, as a tape deck's motor does, and go on from
      there with Resume (False if it wasn't stopped that way: Play then) }
    procedure Hold;
    function Resume(T: Integer): Boolean;
    { Where the signal is in the data of the block playing: the byte (for tests and tools) }
    property BytePosition: Integer read FBytePos;
    { A 48K (or 16K) is playing it: TZX's "stop the tape if in 48K mode" }
    property StopIf48K: Boolean read FStopIf48K write FStopIf48K;
  end;

const
  PILOT_PULSE = 2168;
  SYNC1_PULSE = 667;
  SYNC2_PULSE = 735;
  ZERO_PULSE = 855;
  ONE_PULSE = 1710;
  HEADER_PILOTS = 8063;
  DATA_PILOTS = 3223;

type
  { REC: turns the edges of the MIC output into tape blocks. Standard ROM
    timing (in CPU T-states): pilot pulses of 2168, sync 667 + 735, bits as
    two pulses of 855 (0) or 1710 (1). A block ends when the signal stops or
    leaves those timings. }
  TRecState = (rsIdle, rsPilot, rsSync, rsData);

  TTapeRecorder = class
  private
    FTape: TTape;
    FActive: Boolean;
    FLastEdge: Int64;
    FHaveEdge: Boolean;
    FState: TRecState;
    FPilot: Integer;          // pilot pulses seen
    FHalf: Integer;           // first pulse of a bit, -1 if none
    FBitCount: Integer;
    FByte: Byte;
    FData: TBytes;
    FLen: Integer;
    FRaw: Boolean;            // keep the pulses as they are (no decoding)
    FPulses: array of Integer;
    FPulseCount: Integer;
    FSilence: Int64;          // T-states of silence before the pulses kept
    procedure Pulse(Len: Integer);
    procedure FlushPulses;
    procedure AddBit(One: Boolean);
    procedure FinishBlock;
  public
    constructor Create(ATape: TTape);
    procedure Start;
    procedure Stop;
    { The MIC level changed at CPU T-state T (counted from any fixed point) }
    procedure Edge(T: Int64);
    { No edge until T: ends a block that has stopped }
    procedure Idle(T: Int64);
    property Active: Boolean read FActive;
    { The Amstrad CPC's recorder: every pulse is kept (a CDT can hold any
      signal), and a pause of more than 40 ms starts the next group }
    property Raw: Boolean read FRaw write FRaw;
    { End what is being recorded }
    procedure Flush;
  end;


implementation

uses
  TZX;

{ TTapeBlock }

constructor TTapeBlock.Create(const AData: TBytes);
begin
  CreateKind(TZX_STANDARD);
  Data := AData;
  if Flag < 128 then PilotCount := HEADER_PILOTS else PilotCount := DATA_PILOTS;
end;

constructor TTapeBlock.CreateKind(AKind: Byte);
begin
  inherited Create;
  Kind := AKind;
  PauseMs := 1000;
  PilotLen := PILOT_PULSE;
  PilotCount := DATA_PILOTS;
  Sync1Len := SYNC1_PULSE;
  Sync2Len := SYNC2_PULSE;
  ZeroLen := ZERO_PULSE;
  OneLen := ONE_PULSE;
  UsedBits := 8;
  FDuration := -1;
end;

function TTapeBlock.Flag: Integer;
begin
  if IsData and (Length(Data) > 0) then Result := Data[0] else Result := -1;
end;

function TTapeBlock.IsHeader: Boolean;
begin
  Result := (Flag = 0) and (Length(Data) = 19);
end;

function TTapeBlock.IsData: Boolean;
begin
  Result := Kind in [TZX_STANDARD, TZX_TURBO, TZX_PURE_DATA];
end;

function TTapeBlock.FitsRom: Boolean;
begin
  // The ROM tells 0 from 1 by the length of a bit: about 855 and 1710
  Result := (Kind = TZX_STANDARD) or
    ((Kind in [TZX_TURBO, TZX_PURE_DATA]) and (UsedBits = 8) and (Length(Data) >= 2) and
     (Abs(ZeroLen - ZERO_PULSE) <= 150) and (Abs(OneLen - ONE_PULSE) <= 300));
end;

function TTapeBlock.IsInfo: Boolean;
begin
  Result := not (Kind in [TZX_STANDARD, TZX_TURBO, TZX_TONE, TZX_PULSES, TZX_PURE_DATA, TZX_DIRECT,
    TZX_CSW, TZX_GENERALIZED, TZX_PAUSE]);
end;

function TTapeBlock.ChecksumOK: Boolean;
var
  I: Integer;
  X: Byte;
begin
  X := 0;
  for I := 0 to High(Data) do X := X xor Data[I];
  Result := IsData and (Length(Data) > 0) and (X = 0);
end;

function TTapeBlock.DataBits: Integer;
begin
  if Length(Data) = 0 then Result := 0
  else Result := (Length(Data) - 1) * 8 + EnsureRange(UsedBits, 1, 8);
end;

function TTapeBlock.BitAt(Index: Integer): Boolean;
begin
  Result := (Data[Index shr 3] and ($80 shr (Index and 7))) <> 0;
end;

function TTapeBlock.Description: string;
var
  Name: string;
  I: Integer;
begin
  case Kind of
    TZX_STANDARD, TZX_TURBO, TZX_PURE_DATA:
      begin
        if IsHeader then
        begin
          Name := '';
          for I := 2 to 11 do
            if (Data[I] >= 32) and (Data[I] < 127) then Name := Name + Chr(Data[I]) else Name := Name + '?';
          case Data[1] of
            0: Result := 'Program: ' + Name;
            1: Result := 'Number array: ' + Name;
            2: Result := 'Character array: ' + Name;
            3: Result := 'Bytes: ' + Name;
          else
            Result := 'Header: ' + Name;
          end;
        end
        else if Flag = $FF then
          Result := Format('Data (%d bytes)', [Length(Data) - 2])
        else
          Result := Format('Block, flag %d (%d bytes)', [Flag, Length(Data)]);
        if Kind = TZX_TURBO then Result := 'Turbo: ' + Result
        else if Kind = TZX_PURE_DATA then Result := 'Pure data: ' + Result;
      end;
    TZX_TONE: Result := Format('Tone: %d pulses of %d T', [PilotCount, PilotLen]);
    TZX_PULSES: Result := Format('Pulses: %d', [Length(Pulses)]);
    TZX_DIRECT: Result := Format('Direct recording (%d samples)', [DataBits]);
    TZX_CSW: Result := Format('CSW recording (%d pulses)', [Length(Pulses)]);
    TZX_GENERALIZED: Result := Format('Generalized data (%d symbols)', [GenCount]);
    TZX_PAUSE:
      if PauseMs = 0 then Result := 'Stop the tape' else Result := Format('Pause: %d ms', [PauseMs]);
    TZX_GROUP_START: Result := 'Group: ' + Text;
    TZX_GROUP_END: Result := 'Group end';
    TZX_JUMP: Result := Format('Jump to block %+d', [Value]);
    TZX_LOOP_START: Result := Format('Loop: %d times', [Value]);
    TZX_LOOP_END: Result := 'Loop end';
    TZX_CALL: Result := Format('Call sequence (%d)', [Length(Calls)]);
    TZX_RETURN: Result := 'Return from the sequence';
    TZX_SELECT: Result := 'Select: ' + Text;
    TZX_STOP_48K: Result := 'Stop the tape on a 48K';
    TZX_LEVEL: if Value <> 0 then Result := 'Signal level: high' else Result := 'Signal level: low';
    TZX_TEXT: Result := 'Text: ' + Text;
    TZX_MESSAGE: Result := 'Message: ' + Text;
    TZX_ARCHIVE: Result := 'Archive info: ' + Text;
    TZX_HARDWARE: Result := 'Hardware type';
    TZX_CUSTOM: Result := 'Custom info: ' + Text;
    TZX_GLUE: Result := 'Glue';
  else
    Result := Format('Block %.2Xh', [Kind]);
  end;
end;

function TTapeBlock.DurationT(ClockHz: Integer): Double;
var
  I, J, K, Bits, Ones: Integer;
  Sym: Integer;

  function SymbolT(const S: TGenSymbol): Double;
  var
    P: Integer;
  begin
    Result := 0;
    for P in S.Pulses do Result := Result + P;
  end;

begin
  if FDuration >= 0 then Exit(FDuration);
  Result := 0;
  case Kind of
    TZX_STANDARD, TZX_TURBO, TZX_TONE, TZX_PURE_DATA:
      begin
        if Kind <> TZX_PURE_DATA then Result := Double(PilotLen) * PilotCount;
        if Kind in [TZX_STANDARD, TZX_TURBO] then Result := Result + Sync1Len + Sync2Len;
        if Kind <> TZX_TONE then
        begin
          Bits := DataBits;
          Ones := 0;
          for I := 0 to Bits - 1 do
            if BitAt(I) then Inc(Ones);
          Result := Result + 2.0 * (Ones * OneLen + (Bits - Ones) * ZeroLen);
        end;
      end;
    TZX_PULSES, TZX_CSW:
      for I := 0 to High(Pulses) do Result := Result + Pulses[I];
    TZX_DIRECT: Result := Double(DataBits) * SampleT;
    TZX_GENERALIZED:
      begin
        for I := 0 to High(GenRuns) do
          if GenRuns[I].Symbol <= High(GenPilot) then
            Result := Result + SymbolT(GenPilot[GenRuns[I].Symbol]) * GenRuns[I].Count;
        for I := 0 to GenCount - 1 do
        begin
          Sym := 0;
          for J := 0 to GenBits - 1 do
          begin
            K := I * GenBits + J;
            if K shr 3 > High(Data) then Break;
            Sym := (Sym shl 1) or Ord(BitAt(K));
          end;
          if Sym <= High(GenData) then Result := Result + SymbolT(GenData[Sym]);
        end;
      end;
  end;
  if not IsInfo and not (Kind in [TZX_TONE, TZX_PULSES]) then
    Result := Result + Double(PauseMs) * ClockHz / 1000;
  FDuration := Result;
end;

{ TTape }

constructor TTape.Create;
begin
  inherited Create;
  FBlocks := specialize TObjectList<TTapeBlock>.Create(True);
  FClockHz := 3500000;
  FStretchNum := 1;
  FStretchDen := 1;
  FState := tsStopped;
  FCallBlock := -1;
end;

destructor TTape.Destroy;
begin
  FBlocks.Free;
  inherited Destroy;
end;

procedure TTape.Changed;
begin
  Inc(FChangeCount);
  if Assigned(FOnChange) then FOnChange(Self);
end;

function TTape.GetCount: Integer;
begin
  Result := FBlocks.Count;
end;

function TTape.GetBlock(Index: Integer): TTapeBlock;
begin
  Result := FBlocks[Index];
end;

function TTape.GetPlaying: Boolean;
begin
  Result := FState <> tsStopped;
end;

procedure TTape.Clear;
begin
  FBlocks.Clear;
  FCurrent := 0;
  FState := tsStopped;
  FLevel := False;
  FFileName := '';
  FModified := False;
  FStoppedByBlock := False;
  Inc(FEpoch);
  Changed;
end;

{ A new tape is in: at its start, stopped }
procedure TTape.Loaded;
begin
  FCurrent := 0;
  FState := tsStopped;
  FLevel := False;
  FOwed := False;
  FCallBlock := -1;
  FLoopLeft := 0;
  FModified := False;
  FStoppedByBlock := False;
  Inc(FEpoch);
  Changed;
end;

procedure TTape.LoadTAPFromStream(S: TStream);
var
  Len: Word;
  Data: TBytes;
  Buf: array[0..1] of Byte;
begin
  FBlocks.Clear;
  while S.Position + 2 <= S.Size do
  begin
    S.ReadBuffer(Buf, 2);
    Len := Buf[0] or (Buf[1] shl 8);
    if S.Position + Len > S.Size then Len := S.Size - S.Position;
    SetLength(Data, Len);
    if Len > 0 then S.ReadBuffer(Data[0], Len);
    FBlocks.Add(TTapeBlock.Create(Data));
  end;
  Loaded;
end;

procedure TTape.LoadTAP(const FileName: string);
var
  S: TFileStream;
begin
  S := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    LoadTAPFromStream(S);
    FFileName := FileName;
  finally
    S.Free;
  end;
end;

procedure TTape.LoadTZXFromStream(S: TStream);
var
  List: TTapeBlockArray;
  B: TTapeBlock;
begin
  // Read whole first: a broken file leaves the tape as it was
  List := ReadTZX(S);
  FBlocks.Clear;
  for B in List do FBlocks.Add(B);
  Loaded;
end;

procedure TTape.LoadTZX(const FileName: string);
var
  S: TFileStream;
begin
  S := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    LoadTZXFromStream(S);
    FFileName := FileName;
  finally
    S.Free;
  end;
end;

procedure TTape.LoadFile(const FileName: string);
begin
  // A .cdt (the Amstrad CPC's tape) is a TZX file
  if (LowerCase(ExtractFileExt(FileName)) = '.tzx') or (LowerCase(ExtractFileExt(FileName)) = '.cdt') then
    LoadTZX(FileName)
  else LoadTAP(FileName);
end;

function TTape.CountKind(Kind: Byte): Integer;
var
  B: TTapeBlock;
begin
  Result := 0;
  for B in FBlocks do
    if B.Kind = Kind then Inc(Result);
end;

function TTape.HasNonStandard: Boolean;
var
  B: TTapeBlock;
begin
  for B in FBlocks do
    if B.Kind <> TZX_STANDARD then Exit(True);
  Result := False;
end;

procedure TTape.SaveTAP(const FileName: string);
var
  S: TFileStream;
  Block: TTapeBlock;
  Buf: array[0..1] of Byte;
begin
  S := TFileStream.Create(FileName, fmCreate);
  try
    for Block in FBlocks do
      if Block.IsData then
      begin
        Buf[0] := Length(Block.Data) and $FF;
        Buf[1] := (Length(Block.Data) shr 8) and $FF;
        S.WriteBuffer(Buf, 2);
        if Length(Block.Data) > 0 then S.WriteBuffer(Block.Data[0], Length(Block.Data));
      end;
  finally
    S.Free;
  end;
  FFileName := FileName;
  FModified := False;
  Changed;
end;

function TTape.MsT(Ms: Integer): Int64;
begin
  Result := Int64(Ms) * FClockHz div 1000;
end;

procedure TTape.SetPulseScale(Num, Den: Integer);
begin
  if (Num < 1) or (Den < 1) then
  begin
    Num := 1;
    Den := 1;
  end;
  FStretchNum := Num;
  FStretchDen := Den;
end;

procedure TTape.SetLevel(Value: Boolean);
begin
  if Value = FLevel then Exit;
  FLevel := Value;
  if Assigned(FOnEdge) then FOnEdge(FNextEdgeT, FLevel);
end;

{ A pulse starts now (at FNextEdgeT) and lasts Len T-states }
procedure TTape.StartPulse(Len: Integer; How: TPulseStart);
begin
  case How of
    psToggle: SetLevel(not FLevel);
    psLow: SetLevel(False);
    psHigh: SetLevel(True);
  end;
  FOwed := True;
  Inc(FNextEdgeT, Max(Int64(Len) * FStretchNum div FStretchDen, 1));
end;

procedure TTape.BeginData(B: TTapeBlock);
begin
  FState := tsData;
  FBytePos := 0;
  FBitMask := $80;
  FSecondHalf := False;
  FBitsLeft := B.DataBits;
end;

{ After a block's signal: its pause, if it has one (True: something is
  scheduled). The end of the last pulse is an edge; if that leaves the line
  high, it drops 1 ms into the pause, as TZX says. }
function TTape.BeginPause(B: TTapeBlock): Boolean;
var
  Ms: Integer;
begin
  Ms := B.PauseMs;
  // The last block of a tape with no pause (a turbo tape): the end of its last pulse is still an
  // edge, which a loader needs to finish its last bit
  if FFinalEdge and (Ms = 0) and FOwed and (FCurrent = FBlocks.Count - 1) then Ms := 1;
  Result := Ms > 0;
  if not Result then Exit;
  if FOwed then SetLevel(not FLevel);
  FOwed := False;
  FState := tsPause;
  FPauseDrop := FLevel;
  if FPauseDrop then Inc(FNextEdgeT, MsT(1)) else Inc(FNextEdgeT, MsT(Ms));
end;

{ The block at FCurrent, from now: blocks that take no time (information,
  flow control) are done at once, and FCurrent moves on to one that plays }
procedure TTape.SetupBlock;
var
  B: TTapeBlock;
  Guard: Integer;
  WrappedNow: Boolean;
begin
  Guard := 0;
  WrappedNow := False;
  while True do
  begin
    Inc(Guard);
    // The end of a looping tape: from the start, once (a tape with nothing
    // to play would go round for ever)
    if FLoop and not WrappedNow and (FCurrent = FBlocks.Count) and (FBlocks.Count > 0) then
    begin
      WrappedNow := True;
      FCurrent := 0;
      FLoopLeft := 0;
      FCallBlock := -1;
    end;
    if (FCurrent < 0) or (FCurrent >= FBlocks.Count) or (Guard > 100000) then
    begin
      // The end (or a jump nowhere, or round in circles)
      if FCurrent < 0 then FCurrent := 0;
      if FCurrent > FBlocks.Count then FCurrent := FBlocks.Count;
      FState := tsStopped;
      Exit;
    end;
    B := FBlocks[FCurrent];
    case B.Kind of
      TZX_STANDARD, TZX_TURBO, TZX_TONE:
        begin
          FState := tsPilot;
          FPulsesLeft := B.PilotCount;
          Exit;
        end;
      TZX_PULSES, TZX_CSW:
        begin
          FState := tsPulses;
          FIndex := 0;
          Exit;
        end;
      TZX_PURE_DATA:
        begin
          BeginData(B);
          Exit;
        end;
      TZX_DIRECT:
        begin
          FState := tsDirect;
          FIndex := 0;
          FBitsLeft := B.DataBits;
          Exit;
        end;
      TZX_GENERALIZED:
        begin
          FState := tsGenPilot;
          FIndex := 0;
          FSymPulse := 0;
          if Length(B.GenRuns) > 0 then FRunLeft := B.GenRuns[0].Count else FRunLeft := 0;
          Exit;
        end;
      TZX_PAUSE:
        if B.PauseMs = 0 then
        begin
          // "Stop the tape": the next Play goes on after it
          Inc(FCurrent);
          FState := tsStopped;
          FStoppedByBlock := True;
          Exit;
        end
        else if BeginPause(B) then
          Exit
        else
          Inc(FCurrent);
      TZX_JUMP:
        if B.Value = 0 then Inc(FCurrent) else FCurrent := FCurrent + B.Value;
      TZX_LOOP_START:
        begin
          FLoopStart := FCurrent + 1;
          FLoopLeft := B.Value;
          Inc(FCurrent);
        end;
      TZX_LOOP_END:
        begin
          Dec(FLoopLeft);
          if FLoopLeft > 0 then FCurrent := FLoopStart else Inc(FCurrent);
        end;
      TZX_CALL:
        if Length(B.Calls) = 0 then
          Inc(FCurrent)
        else
        begin
          FCallBlock := FCurrent;
          FCallPos := 0;
          FCurrent := FCurrent + B.Calls[0];
        end;
      TZX_RETURN:
        if (FCallBlock < 0) or (FCallBlock >= FBlocks.Count) then
          Inc(FCurrent)
        else
        begin
          Inc(FCallPos);
          if FCallPos <= High(FBlocks[FCallBlock].Calls) then
            FCurrent := FCallBlock + FBlocks[FCallBlock].Calls[FCallPos]
          else
          begin
            FCurrent := FCallBlock + 1;
            FCallBlock := -1;
          end;
        end;
      TZX_STOP_48K:
        begin
          Inc(FCurrent);
          if FStopIf48K then
          begin
            FState := tsStopped;
            FStoppedByBlock := True;
            Exit;
          end;
        end;
      TZX_LEVEL:
        begin
          SetLevel(B.Value <> 0);
          FOwed := False;
          Inc(FCurrent);
        end;
    else
      Inc(FCurrent);    // information: texts, groups, archive info...
    end;
  end;
end;

procedure TTape.StartBlock(T: Integer);
begin
  FNextEdgeT := T;
  SetupBlock;
  Changed;
end;

procedure TTape.Play(T: Integer);
begin
  FHeld := tsStopped;
  if Playing or (FBlocks.Count = 0) then Exit;
  // At the end of the tape: from the start again
  if FCurrent >= FBlocks.Count then
  begin
    FCurrent := 0;
    FLevel := False;
  end;
  FOwed := False;
  FStoppedByBlock := False;
  StartBlock(T);
end;

procedure TTape.Stop;
begin
  FHeld := tsStopped;
  if FState = tsStopped then Exit;
  // In the pause after a block, that block is done: the tape goes on after
  // it (stopped in its data or tone, it goes on from the start of the block)
  if (FState = tsPause) and (FCurrent < FBlocks.Count) then Inc(FCurrent);
  FState := tsStopped;
  Changed;
end;

procedure TTape.Hold;
begin
  if FState = tsStopped then Exit;
  // Only in the data of a block it goes on from where it was (a program reads what it wants of a block, and
  // stops the motor); in the tone, the sync or a pause it is a Stop
  if FState <> tsData then
  begin
    Stop;
    Exit;
  end;
  FHeld := FState;
  FHeldEpoch := FEpoch;
  FState := tsStopped;
  Changed;
end;

function TTape.Resume(T: Integer): Boolean;
begin
  Result := (FHeld <> tsStopped) and (FHeldEpoch = FEpoch) and (FCurrent < FBlocks.Count);
  if not Result then
  begin
    FHeld := tsStopped;
    Exit;
  end;
  FState := FHeld;
  FHeld := tsStopped;
  FStoppedByBlock := False;
  FNextEdgeT := T;
  Changed;
end;

procedure TTape.Rewind;
begin
  FState := tsStopped;
  FCurrent := 0;
  FLevel := False;
  FCallBlock := -1;
  FStoppedByBlock := False;
  Inc(FEpoch);
  Changed;
end;

procedure TTape.SelectBlock(Index: Integer);
begin
  if (Index < 0) or (Index > FBlocks.Count) then Exit;
  FState := tsStopped;
  FCurrent := Index;
  FStoppedByBlock := False;
  Inc(FEpoch);
  Changed;
end;

procedure TTape.DeleteBlock(Index: Integer);
begin
  if (Index < 0) or (Index >= FBlocks.Count) then Exit;
  FBlocks.Delete(Index);
  if FCurrent > Index then Dec(FCurrent);
  if FCurrent > FBlocks.Count then FCurrent := FBlocks.Count;
  if FCurrent = Index then FState := tsStopped;
  FModified := True;
  Changed;
end;

procedure TTape.MoveBlock(FromIndex, ToIndex: Integer);
begin
  if (FromIndex < 0) or (FromIndex >= FBlocks.Count) or
     (ToIndex < 0) or (ToIndex >= FBlocks.Count) or (FromIndex = ToIndex) then Exit;
  FState := tsStopped;
  FBlocks.Move(FromIndex, ToIndex);
  if FCurrent = FromIndex then
    FCurrent := ToIndex
  else if (FromIndex < FCurrent) and (ToIndex >= FCurrent) then
    Dec(FCurrent)
  else if (FromIndex > FCurrent) and (ToIndex <= FCurrent) then
    Inc(FCurrent);
  FModified := True;
  Changed;
end;

procedure TTape.AddPulses(const Pulses: array of Integer; PauseMs: Integer);
var
  B: TTapeBlock;
  I, N, K: Integer;
begin
  I := 0;
  while I < Length(Pulses) do
  begin
    N := Min(255, Length(Pulses) - I);
    B := TTapeBlock.CreateKind(TZX_PULSES);
    SetLength(B.Pulses, N);
    for K := 0 to N - 1 do B.Pulses[K] := Pulses[I + K];
    FBlocks.Add(B);
    Inc(I, N);
  end;
  if PauseMs > 0 then
  begin
    B := TTapeBlock.CreateKind(TZX_PAUSE);
    B.PauseMs := PauseMs;
    FBlocks.Add(B);
  end;
  FModified := True;
  Changed;
end;

procedure TTape.SaveTZX(const FileName: string);
var
  S: TMemoryStream;
  B: TTapeBlock;
  I: Integer;

  procedure W8(V: Integer);
  var X: Byte;
  begin
    X := V and $FF;
    S.WriteBuffer(X, 1);
  end;

  procedure W16(V: Integer);
  begin
    W8(V);
    W8(V shr 8);
  end;

  procedure W24(V: Integer);
  begin
    W16(V);
    W8(V shr 16);
  end;

  procedure WData;
  begin
    if Length(B.Data) > 0 then S.WriteBuffer(B.Data[0], Length(B.Data));
  end;

  procedure WStr(const T: string);
  begin
    W8(Length(T));
    if T <> '' then S.WriteBuffer(T[1], Length(T));
  end;

var
  F: TFileStream;
begin
  S := TMemoryStream.Create;
  try
    S.WriteBuffer('ZXTape!'#$1A, 8);
    W8(1);
    W8(20);
    for B in FBlocks do
    begin
      W8(B.Kind);
      case B.Kind of
        TZX_STANDARD: begin W16(B.PauseMs); W16(Length(B.Data)); WData; end;
        TZX_TURBO:
          begin
            W16(B.PilotLen); W16(B.Sync1Len); W16(B.Sync2Len); W16(B.ZeroLen); W16(B.OneLen);
            W16(B.PilotCount); W8(B.UsedBits); W16(B.PauseMs); W24(Length(B.Data)); WData;
          end;
        TZX_TONE: begin W16(B.PilotLen); W16(B.PilotCount); end;
        TZX_PULSES:
          begin
            W8(Length(B.Pulses));
            for I := 0 to High(B.Pulses) do W16(B.Pulses[I]);
          end;
        TZX_PURE_DATA:
          begin
            W16(B.ZeroLen); W16(B.OneLen); W8(B.UsedBits); W16(B.PauseMs); W24(Length(B.Data)); WData;
          end;
        TZX_DIRECT: begin W16(B.SampleT); W16(B.PauseMs); W8(B.UsedBits); W24(Length(B.Data)); WData; end;
        TZX_PAUSE: W16(B.PauseMs);
        TZX_GROUP_START, TZX_TEXT: WStr(Copy(B.Text, 1, 255));
        TZX_GROUP_END: ;
      else
        raise Exception.CreateFmt('The tape has a block (type %.2X) that can''t be saved as a TZX or CDT', [B.Kind]);
      end;
    end;
    F := TFileStream.Create(FileName, fmCreate);
    try
      F.CopyFrom(S, 0);
    finally
      F.Free;
    end;
  finally
    S.Free;
  end;
end;

procedure TTape.AddBlock(const Data: TBytes);
begin
  FBlocks.Add(TTapeBlock.Create(Data));
  FModified := True;
  Changed;
end;

function TTape.CurrentBit: Boolean;
begin
  Result := (FBlocks[FCurrent].Data[FBytePos] and FBitMask) <> 0;
end;

{ What happens at FNextEdgeT: the next pulse of the block starts, or its
  pause, or the next block }
procedure TTape.NextEvent;
var
  B: TTapeBlock;
  Len, Run, Sym, I, K: Integer;
  Bit: Boolean;
begin
  while FState <> tsStopped do
  begin
    B := FBlocks[FCurrent];
    case FState of
      tsPilot:
        if FPulsesLeft > 0 then
        begin
          Dec(FPulsesLeft);
          StartPulse(B.PilotLen, psToggle);
          Exit;
        end
        else if B.Kind = TZX_TONE then
        begin
          // A tone is followed by the next block straight away
          Inc(FCurrent);
          SetupBlock;
          Changed;
        end
        else
          FState := tsSync1;
      tsSync1:
        begin
          FState := tsSync2;
          if B.Sync1Len > 0 then
          begin
            StartPulse(B.Sync1Len, psToggle);
            Exit;
          end;
        end;
      tsSync2:
        begin
          BeginData(B);
          if B.Sync2Len > 0 then
          begin
            StartPulse(B.Sync2Len, psToggle);
            Exit;
          end;
        end;
      tsData:
        if FBitsLeft > 0 then
        begin
          // Each bit is two equal pulses
          if CurrentBit then Len := B.OneLen else Len := B.ZeroLen;
          StartPulse(Len, psToggle);
          if FSecondHalf then
          begin
            FSecondHalf := False;
            Dec(FBitsLeft);
            FBitMask := FBitMask shr 1;
            if FBitMask = 0 then
            begin
              FBitMask := $80;
              Inc(FBytePos);
            end;
          end
          else
            FSecondHalf := True;
          Exit;
        end
        else
        begin
          // The end of its data: the byte past the last one
          FBytePos := Length(B.Data);
          if BeginPause(B) then Exit;
          Inc(FCurrent);
          SetupBlock;
          Changed;
        end;
      tsPulses:
        if FIndex <= High(B.Pulses) then
        begin
          StartPulse(B.Pulses[FIndex], psToggle);
          Inc(FIndex);
          Exit;
        end
        else
        begin
          // A pulse sequence has no pause; a CSW recording may
          if (B.Kind = TZX_CSW) and BeginPause(B) then Exit;
          Inc(FCurrent);
          SetupBlock;
          Changed;
        end;
      tsDirect:
        if FBitsLeft > 0 then
        begin
          // The level of each sample; the same ones together
          Bit := B.BitAt(FIndex);
          Run := 0;
          while (FBitsLeft > 0) and (B.BitAt(FIndex) = Bit) do
          begin
            Inc(Run);
            Inc(FIndex);
            Dec(FBitsLeft);
          end;
          SetLevel(Bit);
          FOwed := False;
          Inc(FNextEdgeT, Max(Int64(1), Int64(Run) * B.SampleT * FStretchNum div FStretchDen));
          FBytePos := FIndex shr 3;
          Exit;
        end
        else
        begin
          if BeginPause(B) then Exit;
          Inc(FCurrent);
          SetupBlock;
          Changed;
        end;
      tsGenPilot:
        if FIndex <= High(B.GenRuns) then
        begin
          Sym := B.GenRuns[FIndex].Symbol;
          if (FRunLeft > 0) and (Sym <= High(B.GenPilot)) and (FSymPulse <= High(B.GenPilot[Sym].Pulses)) then
          begin
            if FSymPulse = 0 then StartPulse(B.GenPilot[Sym].Pulses[0], B.GenPilot[Sym].Start)
            else StartPulse(B.GenPilot[Sym].Pulses[FSymPulse], psToggle);
            Inc(FSymPulse);
            Exit;
          end;
          // That symbol done: again, or the next run
          FSymPulse := 0;
          Dec(FRunLeft);
          if FRunLeft <= 0 then
          begin
            Inc(FIndex);
            if FIndex <= High(B.GenRuns) then FRunLeft := B.GenRuns[FIndex].Count;
          end;
        end
        else
        begin
          FState := tsGenData;
          FIndex := 0;
          FSymPulse := 0;
          FSymbol := -1;
        end;
      tsGenData:
        if FIndex < B.GenCount then
        begin
          if FSymbol < 0 then
          begin
            // The next symbol of the stream
            FSymbol := 0;
            for I := 0 to B.GenBits - 1 do
            begin
              K := FIndex * B.GenBits + I;
              if K shr 3 > High(B.Data) then Break;
              FSymbol := (FSymbol shl 1) or Ord(B.BitAt(K));
            end;
            FBytePos := (FIndex * B.GenBits) shr 3;
          end;
          if (FSymbol <= High(B.GenData)) and (FSymPulse <= High(B.GenData[FSymbol].Pulses)) then
          begin
            if FSymPulse = 0 then StartPulse(B.GenData[FSymbol].Pulses[0], B.GenData[FSymbol].Start)
            else StartPulse(B.GenData[FSymbol].Pulses[FSymPulse], psToggle);
            Inc(FSymPulse);
            Exit;
          end;
          Inc(FIndex);
          FSymPulse := 0;
          FSymbol := -1;
        end
        else
        begin
          if BeginPause(B) then Exit;
          Inc(FCurrent);
          SetupBlock;
          Changed;
        end;
      tsPause:
        if FPauseDrop then
        begin
          FPauseDrop := False;
          SetLevel(False);
          Inc(FNextEdgeT, Max(Int64(1), MsT(B.PauseMs - 1)));
          Exit;
        end
        else
        begin
          Inc(FCurrent);
          SetupBlock;
          Changed;
        end;
    end;
  end;
  // Stopped (the end, or a stop block)
  Changed;
end;

procedure TTape.AdvanceTo(T: Integer);
begin
  while (FState <> tsStopped) and (FNextEdgeT <= T) do NextEvent;
end;

procedure TTape.EndFrame(FrameT: Integer);
begin
  if FState <> tsStopped then Dec(FNextEdgeT, FrameT);
end;

{ The first block from From that plays a signal, past information, pauses,
  and the tone and pulses before pure data (Count if none) }
function TTape.NextSignal(From: Integer): Integer;
begin
  Result := From;
  while (Result < FBlocks.Count) and not FBlocks[Result].FitsRom and
        (FBlocks[Result].IsInfo and not (FBlocks[Result].Kind in [TZX_JUMP, TZX_LOOP_START, TZX_LOOP_END,
          TZX_CALL, TZX_RETURN, TZX_STOP_48K]) or
         (FBlocks[Result].Kind in [TZX_TONE, TZX_PULSES]) or
         ((FBlocks[Result].Kind = TZX_PAUSE) and (FBlocks[Result].PauseMs > 0))) do
    Inc(Result);
end;

function TTape.TakeBlockForTrap: TTapeBlock;
var
  I: Integer;
begin
  Result := nil;
  // Something the ROM can't read is playing (turbo data...): let it play
  if Playing and (FCurrent < FBlocks.Count) and not FBlocks[FCurrent].FitsRom then Exit;
  I := FCurrent;
  // Playing past a block's pilot tone (its data, or the pause after it):
  // the loader has had it already, the next one is wanted
  if FState in [tsSync1, tsSync2, tsData, tsPause] then Inc(I);
  I := NextSignal(I);
  // The end of a looping tape: the first block again
  if FLoop and (I >= FBlocks.Count) and (FBlocks.Count > 0) then I := NextSignal(0);
  if I >= FBlocks.Count then
  begin
    FCurrent := FBlocks.Count;
    FState := tsStopped;
    Changed;
    Exit;
  end;
  if not FBlocks[I].FitsRom then Exit;
  Result := FBlocks[I];
  FCurrent := I + 1;
  FState := tsStopped;
  Changed;
end;

function TTape.HasMore: Boolean;
begin
  Result := (FCurrent < FBlocks.Count) or (FLoop and (FBlocks.Count > 0));
end;

function TTape.NextNeedsRealTime: Boolean;
var
  I: Integer;
begin
  I := NextSignal(FCurrent);
  Result := (I < FBlocks.Count) and not FBlocks[I].FitsRom and
    not (FBlocks[I].Kind in [TZX_JUMP, TZX_LOOP_START, TZX_LOOP_END, TZX_CALL, TZX_RETURN, TZX_STOP_48K]) and
    not ((FBlocks[I].Kind = TZX_PAUSE) and (FBlocks[I].PauseMs = 0));
end;

function TTape.Progress: Double;
var
  I: Integer;
  Total, Done, Dur: Double;
  B: TTapeBlock;
begin
  // By time, as a real tape moves: pilot tones, data and pauses
  Total := 0;
  Done := 0;
  for I := 0 to FBlocks.Count - 1 do
  begin
    B := FBlocks[I];
    Dur := B.DurationT(FClockHz);
    if I < FCurrent then
      Done := Done + Dur
    else if (I = FCurrent) and (FState <> tsStopped) then
      case FState of
        tsPilot: Done := Done + Double(B.PilotCount - FPulsesLeft) * B.PilotLen;
        tsSync1, tsSync2: Done := Done + Double(B.PilotCount) * B.PilotLen;
        tsData:
          if B.DataBits > 0 then
            Done := Done + (Dur - B.PauseMs * FClockHz / 1000) * (B.DataBits - FBitsLeft) / B.DataBits;
        tsPulses: if Length(B.Pulses) > 0 then Done := Done + Dur * FIndex / Length(B.Pulses);
        tsDirect: Done := Done + Double(FIndex) * B.SampleT;
        tsGenData: if B.GenCount > 0 then Done := Done + Dur * FIndex / B.GenCount;
        tsPause: Done := Done + Dur - B.PauseMs * FClockHz / 1000;
      end;
    Total := Total + Dur;
  end;
  if Total = 0 then Result := 0 else Result := Min(1, Done / Total);
end;

function TTape.TakeBlockBeingRead(out BytePos: Integer): TTapeBlock;
begin
  Result := nil;
  BytePos := 0;
  if (FState <> tsData) or (FCurrent >= FBlocks.Count) or not FBlocks[FCurrent].FitsRom then Exit;
  Result := FBlocks[FCurrent];
  BytePos := FBytePos;
  Inc(FCurrent);
  FState := tsStopped;
  Changed;
end;

{ TTapeRecorder }

constructor TTapeRecorder.Create(ATape: TTape);
begin
  inherited Create;
  FTape := ATape;
end;

procedure TTapeRecorder.Start;
begin
  FActive := True;
  FHaveEdge := False;
  FState := rsIdle;
  FPilot := 0;
end;

procedure TTapeRecorder.Flush;
begin
  if FRaw then FlushPulses
  else if FState = rsData then FinishBlock;
  FHaveEdge := False;
end;

procedure TTapeRecorder.FlushPulses;
var
  Ms: Integer;
begin
  if FPulseCount > 0 then
  begin
    Ms := Integer(Min(FSilence * 1000 div 3500000, 5000));
    FTape.AddPulses(Copy(FPulses, 0, FPulseCount), Max(Ms, 1));
  end;
  FPulseCount := 0;
  FSilence := 0;
end;

procedure TTapeRecorder.Stop;
begin
  if FRaw then FlushPulses;
  if FState = rsData then FinishBlock;
  FActive := False;
  FState := rsIdle;
end;

procedure TTapeRecorder.Edge(T: Int64);
begin
  if not FActive then Exit;
  if FRaw then
  begin
    if FHaveEdge then
    begin
      if (T - FLastEdge > 140000) or (T - FLastEdge > 65535) then
      begin
        // A silence: what came before is a group, this edge starts another
        FlushPulses;
        FSilence := T - FLastEdge;
      end
      else
      begin
        if FPulseCount >= Length(FPulses) then SetLength(FPulses, Length(FPulses) * 2 + 1024);
        FPulses[FPulseCount] := Integer(T - FLastEdge);
        Inc(FPulseCount);
      end;
    end;
    FLastEdge := T;
    FHaveEdge := True;
    Exit;
  end;
  if FHaveEdge then Pulse(Integer(Min(T - FLastEdge, 1000000)));
  FLastEdge := T;
  FHaveEdge := True;
end;

procedure TTapeRecorder.Idle(T: Int64);
begin
  // A block ends when nothing comes for a while (more than a long pulse)
  if FRaw then
  begin
    if FActive and FHaveEdge and (T - FLastEdge > 140000) and (FPulseCount > 0) then
    begin
      FlushPulses;
      FHaveEdge := False;
    end;
    Exit;
  end;
  if FActive and FHaveEdge and (T - FLastEdge > 20000) then
  begin
    if FState = rsData then FinishBlock;
    FState := rsIdle;
    FPilot := 0;
  end;
end;

procedure TTapeRecorder.AddBit(One: Boolean);
begin
  FByte := (FByte shl 1) or Ord(One);
  Inc(FBitCount);
  if FBitCount = 8 then
  begin
    if FLen >= Length(FData) then SetLength(FData, Length(FData) * 2 + 1024);
    FData[FLen] := FByte;
    Inc(FLen);
    FBitCount := 0;
    FByte := 0;
  end;
end;

procedure TTapeRecorder.FinishBlock;
begin
  // A bit whose second pulse never ended: take it as long as the first
  if FHalf >= 0 then AddBit(FHalf > 1282);
  if FLen >= 2 then FTape.AddBlock(Copy(FData, 0, FLen));
  FState := rsIdle;
  FPilot := 0;
end;

procedure TTapeRecorder.Pulse(Len: Integer);
begin
  case FState of
    rsIdle, rsPilot:
      if (Len >= 1800) and (Len <= 2600) then
      begin
        Inc(FPilot);
        FState := rsPilot;
      end
      else if (FPilot >= 200) and (Len >= 400) and (Len <= 1000) then
        FState := rsSync          // first sync pulse
      else
      begin
        FPilot := 0;
        FState := rsIdle;
      end;
    rsSync:
      if (Len >= 400) and (Len <= 1100) then
      begin
        FState := rsData;
        FHalf := -1;
        FBitCount := 0;
        FByte := 0;
        FLen := 0;
      end
      else
      begin
        FPilot := 0;
        FState := rsIdle;
      end;
    rsData:
      if (Len >= 500) and (Len <= 2400) then
      begin
        if FHalf < 0 then
          FHalf := Len
        else
        begin
          AddBit(FHalf + Len > 2565);   // halfway between 2 x 855 and 2 x 1710
          FHalf := -1;
        end;
      end
      else
      begin
        FinishBlock;
        Pulse(Len);    // it may be the start of the next pilot
      end;
  end;
end;

end.

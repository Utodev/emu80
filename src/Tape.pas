{ Tape: tape image (block list), TAP file I/O and real-time EAR signal
  generation using the standard ROM loader timings. }
unit Tape;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, Generics.Collections;

type
  TTapeBlock = class
  public
    Data: TBytes;   // flag byte + payload + checksum, as stored in a TAP file
    PauseMs: Integer;
    constructor Create(const AData: TBytes);
    function Flag: Integer;
    function IsHeader: Boolean;
    function Description: string;
    function ChecksumOK: Boolean;
  end;

  TTapeEdgeEvent = procedure(T: Integer; Level: Boolean) of object;

  TTapeState = (tsStopped, tsPilot, tsSync1, tsSync2, tsData, tsPause);

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
    FSecondHalf: Boolean;
    FPauseDrop: Boolean;    // pause started with the line high
    FFileName: string;
    FModified: Boolean;
    FOnEdge: TTapeEdgeEvent;
    FOnChange: TNotifyEvent;
    FClockHz: Integer;
    FChangeCount: Integer;
    function GetCount: Integer;
    function GetBlock(Index: Integer): TTapeBlock;
    function GetPlaying: Boolean;
    procedure StartBlock(T: Integer);
    procedure Changed;
    function CurrentBit: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure LoadTAP(const FileName: string);
    procedure LoadTAPFromStream(S: TStream);
    procedure SaveTAP(const FileName: string);
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
    { Fast-load support: take the current block and move to the next. }
    function TakeBlockForTrap: TTapeBlock;
    property Count: Integer read GetCount;
    property Blocks[Index: Integer]: TTapeBlock read GetBlock; default;
    property Current: Integer read FCurrent;
    property Playing: Boolean read GetPlaying;
    property Level: Boolean read FLevel;
    property FileName: string read FFileName;
    property Modified: Boolean read FModified;
    property OnEdge: TTapeEdgeEvent read FOnEdge write FOnEdge;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    { Incremented on every change, so a UI on another thread can poll it. }
    property ChangeCount: Integer read FChangeCount;
    property ClockHz: Integer read FClockHz write FClockHz;
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
    procedure Pulse(Len: Integer);
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
  end;

implementation

{ TTapeBlock }

constructor TTapeBlock.Create(const AData: TBytes);
begin
  inherited Create;
  Data := AData;
  PauseMs := 1000;
end;

function TTapeBlock.Flag: Integer;
begin
  if Length(Data) > 0 then Result := Data[0] else Result := -1;
end;

function TTapeBlock.IsHeader: Boolean;
begin
  Result := (Flag = 0) and (Length(Data) = 19);
end;

function TTapeBlock.ChecksumOK: Boolean;
var
  I: Integer;
  X: Byte;
begin
  X := 0;
  for I := 0 to High(Data) do X := X xor Data[I];
  Result := (Length(Data) > 0) and (X = 0);
end;

function TTapeBlock.Description: string;
var
  Name: string;
  I: Integer;
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
end;

{ TTape }

constructor TTape.Create;
begin
  inherited Create;
  FBlocks := specialize TObjectList<TTapeBlock>.Create(True);
  FClockHz := 3500000;
  FState := tsStopped;
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
  FCurrent := 0;
  FState := tsStopped;
  FLevel := False;
  FModified := False;
  Changed;
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

procedure TTape.SaveTAP(const FileName: string);
var
  S: TFileStream;
  Block: TTapeBlock;
  Buf: array[0..1] of Byte;
begin
  S := TFileStream.Create(FileName, fmCreate);
  try
    for Block in FBlocks do
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

procedure TTape.StartBlock(T: Integer);
begin
  if FCurrent >= FBlocks.Count then
  begin
    FState := tsStopped;
    Changed;
    Exit;
  end;
  FState := tsPilot;
  if FBlocks[FCurrent].Flag < 128 then
    FPulsesLeft := HEADER_PILOTS
  else
    FPulsesLeft := DATA_PILOTS;
  FNextEdgeT := T + PILOT_PULSE;
end;

procedure TTape.Play(T: Integer);
begin
  if Playing or (FBlocks.Count = 0) then Exit;
  // At the end of the tape: from the start again
  if FCurrent >= FBlocks.Count then
  begin
    FCurrent := 0;
    FLevel := False;
  end;
  StartBlock(T);
  Changed;
end;

procedure TTape.Stop;
begin
  if FState = tsStopped then Exit;
  FState := tsStopped;
  Changed;
end;

procedure TTape.Rewind;
begin
  FState := tsStopped;
  FCurrent := 0;
  FLevel := False;
  Changed;
end;

procedure TTape.SelectBlock(Index: Integer);
begin
  if (Index < 0) or (Index > FBlocks.Count) then Exit;
  FState := tsStopped;
  FCurrent := Index;
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

procedure TTape.AdvanceTo(T: Integer);
var
  Block: TTapeBlock;
begin
  while (FState <> tsStopped) and (FNextEdgeT <= T) do
  begin
    Block := FBlocks[FCurrent];
    if FState <> tsPause then
    begin
      FLevel := not FLevel;
      if Assigned(FOnEdge) then FOnEdge(FNextEdgeT, FLevel);
    end;
    case FState of
      tsPilot:
        begin
          Dec(FPulsesLeft);
          if FPulsesLeft > 0 then
            Inc(FNextEdgeT, PILOT_PULSE)
          else
          begin
            FState := tsSync1;
            Inc(FNextEdgeT, SYNC1_PULSE);
          end;
        end;
      tsSync1:
        begin
          FState := tsSync2;
          Inc(FNextEdgeT, SYNC2_PULSE);
        end;
      tsSync2, tsData:
        begin
          if FState = tsSync2 then
          begin
            FState := tsData;
            FBytePos := 0;
            FBitMask := $80;
            FSecondHalf := False;
          end
          else if FSecondHalf then
          begin
            FSecondHalf := False;
            FBitMask := FBitMask shr 1;
            if FBitMask = 0 then
            begin
              FBitMask := $80;
              Inc(FBytePos);
            end;
          end
          else
            FSecondHalf := True;
          if FBytePos >= Length(Block.Data) then
          begin
            // End of data. The final edge must stay visible, so (as in TZX)
            // the line only drops low 1 ms into the pause.
            FState := tsPause;
            FPauseDrop := FLevel and (Block.PauseMs > 0);
            if FPauseDrop then
              Inc(FNextEdgeT, FClockHz div 1000)
            else
              Inc(FNextEdgeT, Int64(Block.PauseMs) * FClockHz div 1000);
          end
          else if CurrentBit then
            Inc(FNextEdgeT, ONE_PULSE)
          else
            Inc(FNextEdgeT, ZERO_PULSE);
        end;
      tsPause:
        if FPauseDrop then
        begin
          FPauseDrop := False;
          FLevel := False;
          if Assigned(FOnEdge) then FOnEdge(FNextEdgeT, FLevel);
          Inc(FNextEdgeT, Int64(Block.PauseMs - 1) * FClockHz div 1000);
        end
        else
        begin
          Inc(FCurrent);
          Changed;
          StartBlock(FNextEdgeT);
        end;
    end;
  end;
end;

procedure TTape.EndFrame(FrameT: Integer);
begin
  if FState <> tsStopped then Dec(FNextEdgeT, FrameT);
end;

function TTape.TakeBlockForTrap: TTapeBlock;
begin
  Result := nil;
  if FCurrent >= FBlocks.Count then Exit;
  Result := FBlocks[FCurrent];
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

procedure TTapeRecorder.Stop;
begin
  if FState = rsData then FinishBlock;
  FActive := False;
  FState := rsIdle;
end;

procedure TTapeRecorder.Edge(T: Int64);
begin
  if not FActive then Exit;
  if FHaveEdge then Pulse(Integer(Min(T - FLastEdge, 1000000)));
  FLastEdge := T;
  FHaveEdge := True;
end;

procedure TTapeRecorder.Idle(T: Int64);
begin
  // A block ends when nothing comes for a while (more than a long pulse)
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

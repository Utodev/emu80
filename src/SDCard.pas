{ SDCard: an SD card in SPI mode, as the DivMMC talks to it, on an image
  file (a raw dump of a card). It answers as an SDHC card (block addresses):
  CMD0, CMD8, CMD55/ACMD41, CMD1, CMD58, CMD9, CMD10, CMD12, CMD13, CMD16,
  CMD17, CMD18, CMD24, CMD25 and CMD59.

  The image file isn't changed until the card is saved: the blocks written
  (by the Spectrum or by the SD card browser) are kept in memory on top of
  it, so only what changed takes memory, whatever the size of the card. }
unit SDCard;

{$mode objfpc}{$H+}
{$R-}{$Q-}

interface

uses
  SysUtils, Classes, Math, Generics.Collections;

type
  { A file with changes kept in memory, block by block, until Save }
  TOverlayStream = class(TStream)
  private
    FFileName: string;
    FBase: TFileStream;
    FPos, FSize: Int64;
    FBlocks: specialize TDictionary<Int64, TBytes>;
    function BlockFor(Block: Int64; ForWrite: Boolean): TBytes;
  protected
    function GetSize: Int64; override;
  public
    constructor Create(const AFileName: string);
    destructor Destroy; override;
    function Read(var Buffer; Count: Longint): Longint; override;
    function Write(const Buffer; Count: Longint): Longint; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
    { Write the changes into the file (or a copy of it at another path,
      which then becomes the file) }
    procedure Save(const AFileName: string);
    function Modified: Boolean;
    property FileName: string read FFileName;
  end;

  TSDWriteState = (wsNone, wsToken, wsData);

  TSDCard = class
  private
    FStream: TOverlayStream;
    FFileName: string;
    FReadOnly: Boolean;
    FBlocks: Int64;
    FSelected: Boolean;
    FCmd: array[0..5] of Byte;
    FCmdLen: Integer;
    FOut: TBytes;                 // bytes waiting to be read by the host
    FOutPos, FOutLen: Integer;
    FAppCmd: Boolean;
    FIdle: Boolean;
    FMultiRead: Boolean;
    FReadBlock: Int64;
    FWriteState: TSDWriteState;
    FMultiWrite: Boolean;
    FWriteBlock: Int64;
    FWriteBuf: array[0..513] of Byte;    // 512 data bytes and the CRC
    FWritePos: Integer;
    FActivity: Integer;
    FLastAccess: QWord;
    procedure Queue(const Bytes: array of Byte);
    procedure QueueBlock(Block: Int64);
    procedure Command;
    procedure DataByte(Value: Byte);
  public
    { Opens the image (read-only if the file can't be written) }
    constructor Create(const AFileName: string);
    destructor Destroy; override;
    procedure Select(Value: Boolean);
    { A byte from the host (OUT to the data port) }
    procedure WriteByte(Value: Byte);
    { The next byte for the host (IN from the data port) }
    function ReadByte: Byte;
    property Stream: TOverlayStream read FStream;
    property FileName: string read FFileName;
    { Changed since it was inserted or saved }
    function Modified: Boolean;
    { Save the changes into the image (AFileName '' = its own file) }
    procedure Save(const AFileName: string = '');
    property ReadOnly: Boolean read FReadOnly;
    property Blocks: Int64 read FBlocks;
    { Counts down after each access, for an activity light }
    property Activity: Integer read FActivity write FActivity;
    { When a block was last read or written (GetTickCount64), for a LED }
    property LastAccess: QWord read FLastAccess;
  end;

implementation

const
  SD_BLOCK = 512;

function FileIsReadOnly(const FileName: string): Boolean;
begin
  Result := (FileGetAttr(FileName) and faReadOnly) <> 0;
end;

{ TOverlayStream }

constructor TOverlayStream.Create(const AFileName: string);
begin
  inherited Create;
  FFileName := AFileName;
  FBase := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  FSize := FBase.Size;
  FBlocks := specialize TDictionary<Int64, TBytes>.Create;
end;

destructor TOverlayStream.Destroy;
begin
  FBlocks.Free;
  FBase.Free;
  inherited Destroy;
end;

function TOverlayStream.GetSize: Int64;
begin
  Result := FSize;
end;

function TOverlayStream.Modified: Boolean;
begin
  Result := FBlocks.Count > 0;
end;

function TOverlayStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
begin
  case Origin of
    soBeginning: FPos := Offset;
    soCurrent: Inc(FPos, Offset);
    soEnd: FPos := FSize + Offset;
  end;
  Result := FPos;
end;

{ A block as it is now: the changed copy, or read from the file (and kept
  if it is going to be changed) }
function TOverlayStream.BlockFor(Block: Int64; ForWrite: Boolean): TBytes;
begin
  if FBlocks.TryGetValue(Block, Result) then Exit;
  SetLength(Result, SD_BLOCK);
  FillChar(Result[0], SD_BLOCK, 0);
  FBase.Position := Block * SD_BLOCK;
  FBase.Read(Result[0], SD_BLOCK);
  if ForWrite then FBlocks.Add(Block, Result);
end;

function TOverlayStream.Read(var Buffer; Count: Longint): Longint;
var
  P: PByte;
  Block, Off, N: Int64;
  Data: TBytes;
begin
  Result := 0;
  P := @Buffer;
  if FPos + Count > FSize then Count := Max(0, FSize - FPos);
  while Count > 0 do
  begin
    Block := FPos div SD_BLOCK;
    Off := FPos mod SD_BLOCK;
    N := Min(SD_BLOCK - Off, Count);
    if FBlocks.TryGetValue(Block, Data) then
      Move(Data[Off], P^, N)
    else
    begin
      FBase.Position := FPos;
      FBase.ReadBuffer(P^, N);
    end;
    Inc(P, N);
    Inc(FPos, N);
    Inc(Result, N);
    Dec(Count, N);
  end;
end;

function TOverlayStream.Write(const Buffer; Count: Longint): Longint;
var
  P: PByte;
  Block, Off, N: Int64;
  Data: TBytes;
begin
  Result := 0;
  P := @Buffer;
  if FPos + Count > FSize then Count := Max(0, FSize - FPos);   // a card doesn't grow
  while Count > 0 do
  begin
    Block := FPos div SD_BLOCK;
    Off := FPos mod SD_BLOCK;
    N := Min(SD_BLOCK - Off, Count);
    Data := BlockFor(Block, True);
    Move(P^, Data[Off], N);
    Inc(P, N);
    Inc(FPos, N);
    Inc(Result, N);
    Dec(Count, N);
  end;
end;

procedure TOverlayStream.Save(const AFileName: string);
var
  Target: string;
  Pair: specialize TPair<Int64, TBytes>;
  Src, Dst: TFileStream;
begin
  Target := AFileName;
  if Target = '' then Target := FFileName;
  if not SameFileName(ExpandFileName(Target), ExpandFileName(FFileName)) then
  begin
    // A copy of the file first, then the changes on it
    Dst := TFileStream.Create(Target, fmCreate);
    try
      FBase.Position := 0;
      Dst.CopyFrom(FBase, FBase.Size);
    finally
      Dst.Free;
    end;
  end;
  // The file is open read-only: reopen it for writing meanwhile
  FreeAndNil(FBase);
  try
    Dst := TFileStream.Create(Target, fmOpenReadWrite or fmShareDenyWrite);
    try
      for Pair in FBlocks do
      begin
        Dst.Position := Pair.Key * SD_BLOCK;
        Dst.WriteBuffer(Pair.Value[0], SD_BLOCK);
      end;
    finally
      Dst.Free;
    end;
    FFileName := Target;
    FBlocks.Clear;
  finally
    if FBase = nil then
    begin
      Src := TFileStream.Create(FFileName, fmOpenRead or fmShareDenyWrite);
      FBase := Src;
    end;
  end;
end;

{ TSDCard }

constructor TSDCard.Create(const AFileName: string);
begin
  inherited Create;
  FFileName := AFileName;
  FStream := TOverlayStream.Create(AFileName);
  FReadOnly := FileIsReadOnly(AFileName);
  FBlocks := FStream.Size div SD_BLOCK;
  SetLength(FOut, SD_BLOCK + 16);
  FIdle := True;
end;

destructor TSDCard.Destroy;
begin
  FStream.Free;
  inherited Destroy;
end;

procedure TSDCard.Select(Value: Boolean);
begin
  if Value = FSelected then Exit;
  FSelected := Value;
  // Deselecting abandons a half-sent command
  FCmdLen := 0;
end;

procedure TSDCard.Queue(const Bytes: array of Byte);
var
  I: Integer;
begin
  if FOutPos >= FOutLen then
  begin
    FOutPos := 0;
    FOutLen := 0;
  end;
  if FOutLen + Length(Bytes) > Length(FOut) then SetLength(FOut, FOutLen + Length(Bytes) + SD_BLOCK);
  for I := 0 to High(Bytes) do FOut[FOutLen + I] := Bytes[I];
  Inc(FOutLen, Length(Bytes));
end;

{ Data token, a 512-byte block and a (dummy) CRC }
procedure TSDCard.QueueBlock(Block: Int64);
var
  Data: array[0..SD_BLOCK - 1] of Byte;
begin
  FillChar(Data, SizeOf(Data), 0);
  if (Block >= 0) and (Block < FBlocks) then
  begin
    FStream.Position := Block * SD_BLOCK;
    FStream.ReadBuffer(Data, SD_BLOCK);
    Queue([$FE]);
    Queue(Data);
    Queue([$FF, $FF]);
  end
  else
    Queue([$09]);   // data error token: out of range
  FActivity := 25;
  FLastAccess := GetTickCount64;
end;

function TSDCard.Modified: Boolean;
begin
  Result := FStream.Modified;
end;

procedure TSDCard.Save(const AFileName: string);
begin
  FStream.Save(AFileName);
  FFileName := FStream.FileName;
  FReadOnly := FileIsReadOnly(FFileName);
end;

function TSDCard.ReadByte: Byte;
begin
  if not FSelected then Exit($FF);
  if (FOutPos >= FOutLen) and FMultiRead then
  begin
    // CMD18 keeps sending blocks until CMD12
    Inc(FReadBlock);
    QueueBlock(FReadBlock);
  end;
  if FOutPos < FOutLen then
  begin
    Result := FOut[FOutPos];
    Inc(FOutPos);
  end
  else
    Result := $FF;
end;

procedure TSDCard.WriteByte(Value: Byte);
begin
  if not FSelected then Exit;
  if FWriteState <> wsNone then
  begin
    DataByte(Value);
    Exit;
  end;
  // A command starts with 01xxxxxx; anything else between commands is filler
  if (FCmdLen = 0) and ((Value and $C0) <> $40) then Exit;
  FCmd[FCmdLen] := Value;
  Inc(FCmdLen);
  if FCmdLen = 6 then
  begin
    FCmdLen := 0;
    Command;
  end;
end;

procedure TSDCard.Command;
var
  Index: Integer;
  Arg: LongWord;
  R1: Byte;
  CSize: LongWord;
begin
  Index := FCmd[0] and $3F;
  Arg := (LongWord(FCmd[1]) shl 24) or (LongWord(FCmd[2]) shl 16) or (LongWord(FCmd[3]) shl 8) or FCmd[4];
  if FIdle then R1 := $01 else R1 := $00;
  // A new command drops what was waiting to be read (except for CMD12,
  // which stops a multiple read)
  FOutPos := 0;
  FOutLen := 0;
  if FAppCmd then
  begin
    FAppCmd := False;
    case Index of
      41:
        begin
          FIdle := False;
          Queue([$00]);
        end;
    else
      Queue([R1]);
    end;
    Exit;
  end;
  case Index of
    0:
      begin
        FIdle := True;
        FMultiRead := False;
        FWriteState := wsNone;
        Queue([$01]);
      end;
    1:
      begin
        FIdle := False;
        Queue([$00]);
      end;
    8: Queue([R1, $00, $00, FCmd[3] and $0F, FCmd[4]]);
    9:
      begin
        // CSD version 2 (SDHC): capacity = (C_SIZE + 1) * 512K
        CSize := LongWord(FBlocks div 1024);
        if CSize > 0 then Dec(CSize);
        Queue([R1, $FE, $40, $0E, $00, $32, $5B, $59, $00, (CSize shr 16) and $3F,
          (CSize shr 8) and $FF, CSize and $FF, $7F, $80, $0A, $40, $00, $01, $FF, $FF]);
      end;
    10: Queue([R1, $FE, $03, $50, $5A, $50, $5A, $58, $53, $44, $10, $00, $00, $00, $01,
      $01, $50, $01, $FF, $FF]);   // CID: "PZPZXSD"
    12:
      begin
        FMultiRead := False;
        Queue([$FF, R1]);
      end;
    // SEND_STATUS (R2: no error), which NextZXOS and the Next's firmware ask
    // for after every block they write
    13: Queue([R1, $00]);
    16, 59: Queue([R1]);
    17:
      begin
        Queue([R1]);
        QueueBlock(Arg);
      end;
    18:
      begin
        Queue([R1]);
        FReadBlock := Arg;
        QueueBlock(Arg);
        FMultiRead := True;
      end;
    24, 25:
      begin
        Queue([R1]);
        FWriteBlock := Arg;
        FMultiWrite := Index = 25;
        FWriteState := wsToken;
      end;
    55:
      begin
        FAppCmd := True;
        Queue([R1]);
      end;
    58:
      // OCR: powered up, card capacity status (SDHC), 3.2-3.4 V
      Queue([R1, $C0, $FF, $80, $00]);
  else
    Queue([R1 or $04]);   // illegal command
  end;
end;

procedure TSDCard.DataByte(Value: Byte);
begin
  case FWriteState of
    wsToken:
      if (Value = $FE) or (FMultiWrite and (Value = $FC)) then
      begin
        FWriteState := wsData;
        FWritePos := 0;
      end
      else if FMultiWrite and (Value = $FD) then
      begin
        // Stop transmission: not busy
        FWriteState := wsNone;
        Queue([$FF]);
      end
      else if (Value and $C0) = $40 then
      begin
        // A command instead of data: give up writing
        FWriteState := wsNone;
        FCmd[0] := Value;
        FCmdLen := 1;
      end;
    wsData:
      begin
        FWriteBuf[FWritePos] := Value;
        Inc(FWritePos);
        if FWritePos = SD_BLOCK + 2 then
        begin
          if FWriteBlock < FBlocks then
          begin
            FStream.Position := FWriteBlock * SD_BLOCK;
            FStream.WriteBuffer(FWriteBuf, SD_BLOCK);
            Queue([$05, $FF]);           // data accepted, not busy
          end
          else
            Queue([$0D, $FF]);           // write error
          FActivity := 25;
  FLastAccess := GetTickCount64;
          Inc(FWriteBlock);
          if FMultiWrite then FWriteState := wsToken else FWriteState := wsNone;
        end;
      end;
  end;
end;

end.

{ TZX: reads TZX tape files (version 1.20 and earlier) into tape blocks; TSX files (the MSX's: the same format
  with another extension) are read by it too, with their block 4Bh (data in the Kansas City Standard, which becomes
  the tone and the pulses of the data) and the TSX.LOAD custom info (the command that loads the tape).
  Every block of the specification is understood: the signal ones (standard,
  turbo, tone, pulses, pure data, direct and CSW recordings, generalized
  data), pauses and stops, flow control (groups, jumps, loops, calls,
  selections, stop on a 48K, signal level) and information (texts,
  messages, archive info, hardware, custom info, glue). Old and unknown
  blocks are skipped by their length. A file cut short keeps the blocks
  read until then. }
unit TZX;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils, Classes, Math, Tape;

type
  TTapeBlockArray = array of TTapeBlock;

{ The blocks of a TZX file from the stream's position; raises if it isn't
  one }
function ReadTZX(S: TStream): TTapeBlockArray;

implementation

uses
  ZStream, Lang;

type
  { The file's bytes, read with bounds checking: past the end raises }
  TReader = record
    Buf: TBytes;
    Pos: Integer;
    function Left: Integer;
    procedure Need(N: Integer);
    function B: Byte;
    function W: Word;
    function W3: Integer;
    function D: LongWord;
    function Bytes(N: Integer): TBytes;
    function Str(N: Integer): string;
  end;

  ETruncated = class(Exception);

function TReader.Left: Integer;
begin
  Result := Length(Buf) - Pos;
end;

procedure TReader.Need(N: Integer);
begin
  if (N < 0) or (N > Left) then raise ETruncated.Create(_('The file is cut short'));
end;

function TReader.B: Byte;
begin
  Need(1);
  Result := Buf[Pos];
  Inc(Pos);
end;

function TReader.W: Word;
begin
  Need(2);
  Result := Buf[Pos] or (Buf[Pos + 1] shl 8);
  Inc(Pos, 2);
end;

function TReader.W3: Integer;
begin
  Need(3);
  Result := Buf[Pos] or (Buf[Pos + 1] shl 8) or (Buf[Pos + 2] shl 16);
  Inc(Pos, 3);
end;

function TReader.D: LongWord;
begin
  Need(4);
  Result := LongWord(Buf[Pos]) or (LongWord(Buf[Pos + 1]) shl 8) or (LongWord(Buf[Pos + 2]) shl 16) or
    (LongWord(Buf[Pos + 3]) shl 24);
  Inc(Pos, 4);
end;

function TReader.Bytes(N: Integer): TBytes;
begin
  Need(N);
  SetLength(Result, N);
  if N > 0 then Move(Buf[Pos], Result[0], N);
  Inc(Pos, N);
end;

{ Text of the file (ASCII): anything else shown as '?' }
function TReader.Str(N: Integer): string;
var
  I: Integer;
  C: Byte;
begin
  Need(N);
  Result := '';
  for I := 0 to N - 1 do
  begin
    C := Buf[Pos + I];
    if C = 13 then Result := Result + ' '
    else if (C >= 32) and (C < 127) then Result := Result + Chr(C)
    else Result := Result + '?';
  end;
  Inc(Pos, N);
  Result := Trim(Result);
end;

function SignedW(V: Word): Integer;
begin
  if V >= $8000 then Result := Integer(V) - $10000 else Result := V;
end;

{ Data bytes of a block; what the file has of them if it is cut short }
function DataPart(var R: TReader; N: Integer; out Short: Boolean): TBytes;
begin
  Short := N > R.Left;
  if Short then N := R.Left;
  Result := R.Bytes(N);
end;

{ A generalized data block's symbol table: Count symbols of up to Max pulses }
function ReadSymbols(var R: TReader; Count, MaxPulses: Integer): TGenSymbols;
var
  I, J, N: Integer;
  Flags: Byte;
  P: array of Integer;
begin
  SetLength(Result, Count);
  for I := 0 to Count - 1 do
  begin
    Flags := R.B;
    Result[I].Start := TPulseStart(Flags and 3);
    SetLength(P, MaxPulses);
    N := 0;
    for J := 0 to MaxPulses - 1 do
    begin
      P[J] := R.W;
      // A pulse of 0 ends the symbol early
      if (P[J] > 0) and (N = J) then N := J + 1;
    end;
    Result[I].Pulses := Copy(P, 0, N);
  end;
end;

procedure ReadGeneralized(var R: TReader; Blk: TTapeBlock);
var
  Len, EndPos, TotP, NPP, ASP, TotD, NPD, ASD, I, Bytes: Integer;
begin
  Len := R.D;
  R.Need(Len);
  EndPos := R.Pos + Len;
  Blk.PauseMs := R.W;
  TotP := R.D;
  NPP := R.B;
  ASP := R.B;
  if ASP = 0 then ASP := 256;
  TotD := R.D;
  NPD := R.B;
  ASD := R.B;
  if ASD = 0 then ASD := 256;
  if TotP > 0 then
  begin
    Blk.GenPilot := ReadSymbols(R, ASP, NPP);
    SetLength(Blk.GenRuns, TotP);
    for I := 0 to TotP - 1 do
    begin
      Blk.GenRuns[I].Symbol := R.B;
      Blk.GenRuns[I].Count := R.W;
    end;
  end;
  if TotD > 0 then
  begin
    Blk.GenData := ReadSymbols(R, ASD, NPD);
    // Bits a symbol: enough for ASD of them
    Blk.GenBits := 0;
    while (1 shl Blk.GenBits) < ASD do Inc(Blk.GenBits);
    Blk.GenCount := TotD;
    Bytes := (Int64(TotD) * Blk.GenBits + 7) div 8;
    Blk.Data := R.Bytes(Min(Bytes, EndPos - R.Pos));
  end;
  R.Pos := EndPos;
end;

procedure ReadCSW(var R: TReader; Blk: TTapeBlock);
var
  Len, EndPos, Rate, Compression, Stored, I, N, Count: Integer;
  Packed_, Raw: TBytes;
  Input: TBytesStream;
  Z: TDecompressionStream;
  Output: TMemoryStream;
  Buf: array[0..65535] of Byte;
begin
  Len := R.D;
  R.Need(Len);
  EndPos := R.Pos + Len;
  Blk.PauseMs := R.W;
  Rate := R.W3;
  Compression := R.B;
  Stored := R.D;
  Packed_ := R.Bytes(EndPos - R.Pos);
  if Compression = 2 then
  begin
    // Z-RLE: the RLE data, compressed with zlib
    Input := TBytesStream.Create(Packed_);
    Output := TMemoryStream.Create;
    try
      Z := TDecompressionStream.Create(Input);
      try
        repeat
          N := Z.Read(Buf, SizeOf(Buf));
          if N > 0 then Output.WriteBuffer(Buf, N);
        until N <= 0;
      finally
        Z.Free;
      end;
      SetLength(Raw, Output.Size);
      if Output.Size > 0 then Move(Output.Memory^, Raw[0], Output.Size);
    finally
      Output.Free;
      Input.Free;
    end;
  end
  else
    Raw := Packed_;
  // RLE: a byte with the samples of a pulse; 0, then 4 bytes for long ones
  SetLength(Blk.Pulses, Max(Stored, 0));
  N := 0;
  I := 0;
  if Rate <= 0 then Rate := 44100;
  while I <= High(Raw) do
  begin
    Count := Raw[I];
    Inc(I);
    if Count = 0 then
    begin
      if I + 3 > High(Raw) then Break;
      Count := Raw[I] or (Raw[I + 1] shl 8) or (Raw[I + 2] shl 16) or (Raw[I + 3] shl 24);
      Inc(I, 4);
    end;
    if N >= Length(Blk.Pulses) then SetLength(Blk.Pulses, N * 2 + 16);
    Blk.Pulses[N] := Max(1, Round(Int64(Count) * 3500000 / Rate));
    Inc(N);
  end;
  SetLength(Blk.Pulses, N);
  R.Pos := EndPos;
end;

const
  // TR-BEGIN (translated where used)
  ARCHIVE_TYPES: array[0..8] of string = ('Title', 'Publisher', 'Author', 'Year', 'Language', 'Type',
    'Price', 'Loader', 'Origin');
  // TR-END

{ Block 4Bh, the MSX's data: a pilot tone, then each byte as the start bits, its eight bits and the stop bits, each bit
  a number of pulses of its length: a tone block, the pulses and the pause that follows them }
function ReadKcs(var R: TReader): TTapeBlockArray;
var
  Total, Pause, PilotLen, PilotCount, Len0, Len1, N0, N1, BitCfg, ByteCfg, StartN, StopN, StartV, StopV: Integer;
  Data: TBytes;
  I, J, P, K: Integer;
  Msb, IsHeader: Boolean;
  Name: string;
  Blk: TTapeBlock;

  procedure Bit(V: Integer);
  var
    N, L, T: Integer;
  begin
    if V = 0 then
    begin
      N := N0;
      L := Len0;
    end
    else
    begin
      N := N1;
      L := Len1;
    end;
    for T := 1 to N do
    begin
      Blk.Pulses[P] := L;
      Inc(P);
    end;
  end;

  procedure Put(ABlock: TTapeBlock);
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := ABlock;
  end;

begin
  Result := nil;
  Total := R.D;
  if Total < 12 then raise Exception.Create(_('A KCS block of a TSX file is too short'));
  Pause := R.W;
  PilotLen := R.W;
  PilotCount := R.W;
  Len0 := R.W;
  Len1 := R.W;
  BitCfg := R.B;
  ByteCfg := R.B;
  Data := R.Bytes(Total - 12);
  N0 := BitCfg shr 4;
  N1 := BitCfg and 15;
  if N0 = 0 then N0 := 16;
  if N1 = 0 then N1 := 16;
  StartN := (ByteCfg shr 6) and 3;
  StartV := (ByteCfg shr 5) and 1;
  StopN := (ByteCfg shr 3) and 3;
  StopV := (ByteCfg shr 2) and 1;
  Msb := (ByteCfg and 2) <> 0;
  if PilotCount > 0 then
  begin
    Blk := TTapeBlock.CreateKind(TZX_TONE);
    Blk.PilotLen := PilotLen;
    Blk.PilotCount := PilotCount;
    Put(Blk);
  end;
  Blk := TTapeBlock.CreateKind(TZX_PULSES);
  SetLength(Blk.Pulses, Length(Data) * (StartN + 8 + StopN) * Max(N0, N1));
  P := 0;
  for I := 0 to High(Data) do
  begin
    for K := 1 to StartN do Bit(StartV);
    for J := 0 to 7 do
      if Msb then Bit((Data[I] shr (7 - J)) and 1) else Bit((Data[I] shr J) and 1);
    for K := 1 to StopN do Bit(StopV);
  end;
  SetLength(Blk.Pulses, P);
  // What it is, as the .cas tapes say (a file header is ten identical bytes and the name)
  IsHeader := Length(Data) >= 16;
  if IsHeader then
  begin
    for I := 1 to 9 do
      if Data[I] <> Data[0] then IsHeader := False;
    if not (Data[0] in [$D0, $D3, $EA]) then IsHeader := False;
  end;
  if IsHeader then
  begin
    Name := '';
    for I := 10 to 15 do
      if (Data[I] >= 32) and (Data[I] < 127) then Name := Name + Chr(Data[I]) else Name := Name + ' ';
    case Data[0] of
      $D0: Blk.Text := _('Binary (BLOAD): ') + Trim(Name);
      $D3: Blk.Text := _('BASIC program: ') + Trim(Name);
    else
      Blk.Text := _('ASCII file: ') + Trim(Name);
    end;
  end
  else Blk.Text := Format(_('Data (%d bytes)'), [Length(Data)]);
  Put(Blk);
  if Pause > 0 then
  begin
    Blk := TTapeBlock.CreateKind(TZX_PAUSE);
    Blk.PauseMs := Pause;
    Put(Blk);
  end;
end;

function ReadTZX(S: TStream): TTapeBlockArray;
var
  R: TReader;
  N: Integer;
  Id: Byte;
  Blk: TTapeBlock;
  Short: Boolean;
  I, Cnt, Len, Kind: Integer;
  Info: string;
  Parts: TTapeBlockArray;

  procedure Add(ABlock: TTapeBlock);
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := ABlock;
  end;

begin
  Result := nil;
  SetLength(R.Buf, S.Size - S.Position);
  if Length(R.Buf) > 0 then S.ReadBuffer(R.Buf[0], Length(R.Buf));
  R.Pos := 0;
  if (Length(R.Buf) < 10) or (R.Str(7) <> 'ZXTape!') or (R.B <> $1A) then
    raise Exception.Create(_('This is not a TZX file'));
  if R.B <> 1 then raise Exception.Create(_('This TZX version is not supported'));
  R.B;   // minor version: any 1.x
  Blk := nil;
  try
    while R.Left > 0 do
    begin
      Id := R.B;
      Blk := TTapeBlock.CreateKind(Id);
      Short := False;
      case Id of
        TZX_STANDARD:
          begin
            Blk.PauseMs := R.W;
            Len := R.W;
            Blk.Data := DataPart(R, Len, Short);
            if (Length(Blk.Data) > 0) and (Blk.Data[0] < 128) then Blk.PilotCount := HEADER_PILOTS;
          end;
        TZX_TURBO:
          begin
            Blk.PilotLen := R.W;
            Blk.Sync1Len := R.W;
            Blk.Sync2Len := R.W;
            Blk.ZeroLen := R.W;
            Blk.OneLen := R.W;
            Blk.PilotCount := R.W;
            Blk.UsedBits := R.B;
            Blk.PauseMs := R.W;
            Len := R.W3;
            Blk.Data := DataPart(R, Len, Short);
          end;
        TZX_TONE:
          begin
            Blk.PilotLen := R.W;
            Blk.PilotCount := R.W;
          end;
        TZX_PULSES:
          begin
            Cnt := R.B;
            SetLength(Blk.Pulses, Cnt);
            for I := 0 to Cnt - 1 do Blk.Pulses[I] := R.W;
          end;
        TZX_PURE_DATA:
          begin
            Blk.ZeroLen := R.W;
            Blk.OneLen := R.W;
            Blk.UsedBits := R.B;
            Blk.PauseMs := R.W;
            Len := R.W3;
            Blk.Data := DataPart(R, Len, Short);
          end;
        TZX_DIRECT:
          begin
            Blk.SampleT := R.W;
            Blk.PauseMs := R.W;
            Blk.UsedBits := R.B;
            Len := R.W3;
            Blk.Data := DataPart(R, Len, Short);
          end;
        TZX_CSW: ReadCSW(R, Blk);
        TZX_GENERALIZED: ReadGeneralized(R, Blk);
        TZX_PAUSE: Blk.PauseMs := R.W;
        TZX_GROUP_START: Blk.Text := R.Str(R.B);
        TZX_GROUP_END, TZX_LOOP_END, TZX_RETURN: ;
        TZX_JUMP: Blk.Value := SignedW(R.W);
        TZX_LOOP_START: Blk.Value := R.W;
        TZX_CALL:
          begin
            Cnt := R.W;
            SetLength(Blk.Calls, Cnt);
            for I := 0 to Cnt - 1 do Blk.Calls[I] := SignedW(R.W);
          end;
        TZX_SELECT:
          begin
            Len := R.W;
            R.Need(Len);
            N := R.Pos + Len;
            Cnt := R.B;
            Info := '';
            for I := 1 to Cnt do
            begin
              R.W;
              if Info <> '' then Info := Info + ' / ';
              Info := Info + R.Str(R.B);
            end;
            Blk.Text := Info;
            R.Pos := N;
          end;
        TZX_STOP_48K: R.Bytes(R.D);
        TZX_LEVEL:
          begin
            Len := R.D;
            R.Need(Len);
            N := R.Pos + Len;
            if Len > 0 then Blk.Value := R.B;
            R.Pos := N;
          end;
        TZX_TEXT: Blk.Text := R.Str(R.B);
        TZX_MESSAGE:
          begin
            Blk.Value := R.B;
            Blk.Text := R.Str(R.B);
          end;
        TZX_ARCHIVE:
          begin
            Len := R.W;
            R.Need(Len);
            N := R.Pos + Len;
            Cnt := R.B;
            Info := '';
            for I := 1 to Cnt do
            begin
              Kind := R.B;
              if Info <> '' then Info := Info + '; ';
              if Kind <= High(ARCHIVE_TYPES) then Info := Info + _(ARCHIVE_TYPES[Kind]) + ': '
              else if Kind <> $FF then Info := Info + _('Info: ');
              Info := Info + R.Str(R.B);
            end;
            Blk.Text := Info;
            R.Pos := N;
          end;
        TZX_HARDWARE: R.Bytes(R.B * 3);
        TZX_CUSTOM:
          begin
            Blk.Text := R.Str(16);
            Len := R.D;
            if (Blk.Text = 'TSX.LOAD') or (Blk.Text = 'TOSEC.NAME') then
            begin
              // The command that loads the tape, for the MSX's Auto load (or the tape's name, which says it in [ ])
              Info := R.Str(Min(Len, R.Left));
              Blk.Text := Blk.Text + ': ' + Info;
            end
            else R.Bytes(Len);
          end;
        $4B:
          begin
            // Data of the MSX's tapes: becomes the tone, the pulses and the pause
            Blk.Free;
            Blk := nil;
            Parts := ReadKcs(R);
            for I := 0 to High(Parts) do Add(Parts[I]);
          end;
        TZX_GLUE: R.Bytes(9);
        // Old blocks no longer in the specification: skipped
        $16, $17:
          begin
            Blk.Kind := Id;
            R.Bytes(R.D);
          end;
        $34: R.Bytes(8);
        $40:
          begin
            R.B;
            R.Bytes(R.W3);
          end;
      else
        // Blocks of later versions start with their length
        R.Bytes(R.D);
      end;
      if Blk <> nil then Add(Blk);
      Blk := nil;
      if Short then Break;
    end;
  except
    on ETruncated do
      // Cut short in the middle of a block: what was read stays
      Blk.Free;
    on E: Exception do
    begin
      Blk.Free;
      for Blk in Result do Blk.Free;
      raise;
    end;
  end;
end;

end.

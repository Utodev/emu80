{ Snapshot: SNA (48K/128K) and Z80 (v1, v2, v3) snapshot load and save. }
unit Snapshot;

{$mode objfpc}{$H+}
{$R-}{$Q-}

interface

uses
  SysUtils, Classes, Z80Core, Models, Spectrum;

procedure LoadSNA(Spec: TSpectrum; const FileName: string);
procedure SaveSNA(Spec: TSpectrum; const FileName: string);
procedure LoadZ80(Spec: TSpectrum; const FileName: string);
procedure SaveZ80(Spec: TSpectrum; const FileName: string);

implementation

function ReadFileBytes(const FileName: string): TBytes;
var
  S: TFileStream;
begin
  S := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, S.Size);
    if S.Size > 0 then S.ReadBuffer(Result[0], S.Size);
  finally
    S.Free;
  end;
end;

procedure WriteFileBytes(const FileName: string; const Data: TBytes);
var
  S: TFileStream;
begin
  S := TFileStream.Create(FileName, fmCreate);
  try
    if Length(Data) > 0 then S.WriteBuffer(Data[0], Length(Data));
  finally
    S.Free;
  end;
end;

function Word16(const D: TBytes; Pos: Integer): Word; inline;
begin
  Result := D[Pos] or (D[Pos + 1] shl 8);
end;

procedure PutWord(var D: TBytes; Pos: Integer; Value: Word); inline;
begin
  D[Pos] := Value and $FF;
  D[Pos + 1] := Value shr 8;
end;

function Is128(Spec: TSpectrum): Boolean;
begin
  Result := Spec.Info.Memory <> mk48K;
end;

{ Switch to a model the snapshot can run on: 128K-capable, 48K or 16K }
procedure EnsureModel(Spec: TSpectrum; Need128: Boolean; Preferred: TSpectrumModel);
begin
  // The ZX-Uno's ROM is whatever its BIOS chose, and the Next's snapshots
  // need its own formats: use a standard model
  if Spec.Model in [smZXUno, smZXNext] then
  begin
    if Need128 then Spec.SetModel(Preferred)
    else if Preferred = sm16K then Spec.SetModel(sm16K)
    else Spec.SetModel(sm48K);
    Exit;
  end;
  if Need128 then
  begin
    if not Is128(Spec) then Spec.SetModel(Preferred) else Spec.Reset(True);
  end
  else if Preferred = sm16K then
  begin
    if Spec.Model <> sm16K then Spec.SetModel(sm16K) else Spec.Reset(True);
  end
  else if Is128(Spec) or (Spec.Model = sm16K) then
    Spec.SetModel(sm48K)   // a 48K snapshot needs the upper 32K
  else
    Spec.Reset(True);
end;

{ Write 48K of RAM from 0x4000 using the current paging }
procedure Fill48K(Spec: TSpectrum; const D: TBytes; Pos: Integer);
var
  I: Integer;
begin
  for I := 0 to $BFFF do
    if Pos + I < Length(D) then
      Spec.WriteMem($4000 + I, D[Pos + I], 0);
end;

{ SNA }

procedure LoadSNA(Spec: TSpectrum; const FileName: string);
var
  D: TBytes;
  Cpu: TZ80;
  Is128K: Boolean;
  Paging: Byte;
  Bank, Pos: Integer;
begin
  D := ReadFileBytes(FileName);
  // A CPC snapshot starts with "MV - SNA"; a Spectrum one has no signature
  if (Length(D) >= 8) and (D[0] = Ord('M')) and (D[1] = Ord('V')) and (D[2] = Ord(' ')) and
     (D[3] = Ord('-')) and (D[4] = Ord(' ')) and (D[5] = Ord('S')) and (D[6] = Ord('N')) and
     (D[7] = Ord('A')) then
  begin
    Spec.LoadCPCSna(FileName);
    Exit;
  end;
  if Length(D) < 49179 then raise Exception.Create('Invalid SNA file');
  Paging := 0;
  Is128K := Length(D) > 49179;
  EnsureModel(Spec, Is128K, sm128K);
  Cpu := Spec.Cpu;

  if Is128K then
  begin
    Paging := D[49181];
    Spec.WritePaging7FFD(Paging);
  end;
  Fill48K(Spec, D, 27);

  Cpu.I := D[0];
  Cpu.HL_.W := Word16(D, 1);
  Cpu.DE_.W := Word16(D, 3);
  Cpu.BC_.W := Word16(D, 5);
  Cpu.F_ := D[7]; Cpu.A_ := D[8];
  Cpu.HL.W := Word16(D, 9);
  Cpu.DE.W := Word16(D, 11);
  Cpu.BC.W := Word16(D, 13);
  Cpu.IY.W := Word16(D, 15);
  Cpu.IX.W := Word16(D, 17);
  Cpu.IFF2 := (D[19] and 4) <> 0;
  Cpu.IFF1 := Cpu.IFF2;
  Cpu.R := D[20]; Cpu.R7 := D[20];
  Cpu.F := D[21]; Cpu.A := D[22];
  Cpu.SP.W := Word16(D, 23);
  Cpu.IM := D[25] and 3;
  Spec.Border := D[26] and 7;

  if Is128K then
  begin
    Cpu.PC.W := Word16(D, 49179);
    Pos := 49183;
    for Bank := 0 to 7 do
    begin
      if (Bank = 5) or (Bank = 2) or (Bank = (Paging and 7)) then Continue;
      if Pos + $4000 > Length(D) then Break;
      Move(D[Pos], Spec.RamBank(Bank)^[0], $4000);
      Inc(Pos, $4000);
    end;
  end
  else
  begin
    // 48K: PC is on the stack
    Cpu.PC.L := Spec.ReadMem(Cpu.SP.W, 0);
    Cpu.PC.H := Spec.ReadMem(Word(Cpu.SP.W + 1), 0);
    Cpu.SP.W := Word(Cpu.SP.W + 2);
  end;
  Cpu.T := Spec.Info.InterruptLength;
end;

procedure SaveSNA(Spec: TSpectrum; const FileName: string);
var
  D: TBytes;
  Cpu: TZ80;
  I, Bank, Pos: Integer;
  SP: Word;
begin
  if Spec.CPC <> nil then
  begin
    Spec.SaveCPCSna(FileName);
    Exit;
  end;
  Cpu := Spec.Cpu;
  if Is128(Spec) then SetLength(D, 49179 + 4 + 5 * $4000) else SetLength(D, 49179);
  D[0] := Cpu.I;
  PutWord(D, 1, Cpu.HL_.W);
  PutWord(D, 3, Cpu.DE_.W);
  PutWord(D, 5, Cpu.BC_.W);
  D[7] := Cpu.F_; D[8] := Cpu.A_;
  PutWord(D, 9, Cpu.HL.W);
  PutWord(D, 11, Cpu.DE.W);
  PutWord(D, 13, Cpu.BC.W);
  PutWord(D, 15, Cpu.IY.W);
  PutWord(D, 17, Cpu.IX.W);
  if Cpu.IFF2 then D[19] := 4 else D[19] := 0;
  D[20] := Cpu.GetR;
  D[21] := Cpu.F; D[22] := Cpu.A;
  D[25] := Cpu.IM;
  D[26] := Spec.Border;
  for I := 0 to $BFFF do
    D[27 + I] := Spec.ReadMem($4000 + I, 0);

  SP := Cpu.SP.W;
  if Is128(Spec) then
  begin
    PutWord(D, 49179, Cpu.PC.W);
    D[49181] := Spec.Port7FFD;
    D[49182] := 0;
    Pos := 49183;
    for Bank := 0 to 7 do
    begin
      if (Bank = 5) or (Bank = 2) or (Bank = (Spec.Port7FFD and 7)) then Continue;
      Move(Spec.RamBank(Bank)^[0], D[Pos], $4000);
      Inc(Pos, $4000);
    end;
    SetLength(D, Pos);
  end
  else
  begin
    // Push PC onto the saved stack image
    SP := Word(SP - 2);
    if SP >= $4000 then
    begin
      D[27 + SP - $4000] := Cpu.PC.L;
      if SP < $FFFF then D[27 + SP + 1 - $4000] := Cpu.PC.H;
    end;
  end;
  PutWord(D, 23, SP);
  WriteFileBytes(FileName, D);
end;

{ Z80 }

{ Decompress a Z80 memory block (ED ED nn bb = nn copies of bb). }
procedure Decompress(const D: TBytes; Pos, Len: Integer; Dest: PByte; DestLen: Integer);
var
  EndPos, Out, N: Integer;
  B: Byte;
begin
  EndPos := Pos + Len;
  if EndPos > Length(D) then EndPos := Length(D);
  Out := 0;
  while (Pos < EndPos) and (Out < DestLen) do
  begin
    if (Pos + 3 < EndPos) and (D[Pos] = $ED) and (D[Pos + 1] = $ED) then
    begin
      N := D[Pos + 2];
      B := D[Pos + 3];
      Inc(Pos, 4);
      while (N > 0) and (Out < DestLen) do
      begin
        Dest[Out] := B;
        Inc(Out);
        Dec(N);
      end;
    end
    else
    begin
      Dest[Out] := D[Pos];
      Inc(Out);
      Inc(Pos);
    end;
  end;
end;

function Compress(const Src: PByte; Len: Integer): TBytes;
var
  I, Run, Out: Integer;
  B: Byte;
begin
  SetLength(Result, Len * 2 + 16);
  Out := 0;
  I := 0;
  while I < Len do
  begin
    B := Src[I];
    Run := 1;
    while (I + Run < Len) and (Src[I + Run] = B) and (Run < 255) do Inc(Run);
    if (Run >= 5) or ((B = $ED) and (Run >= 2)) then
    begin
      Result[Out] := $ED; Result[Out + 1] := $ED;
      Result[Out + 2] := Run; Result[Out + 3] := B;
      Inc(Out, 4);
      Inc(I, Run);
    end
    else
    begin
      Result[Out] := B;
      Inc(Out);
      Inc(I);
      // A single ED is never followed by the start of a block
      if (B = $ED) and (I < Len) then
      begin
        Result[Out] := Src[I];
        Inc(Out);
        Inc(I);
      end;
    end;
  end;
  SetLength(Result, Out);
end;

procedure LoadZ80(Spec: TSpectrum; const FileName: string);
var
  D: TBytes;
  Cpu: TZ80;
  Version, HeaderLen, HwMode, Pos, BlockLen, Page, Bank, I: Integer;
  Flags, Paging, Paging2: Byte;
  Need128: Boolean;
  Preferred: TSpectrumModel;
  Ram48: array[0..$BFFF] of Byte;
  Modify: Boolean;
begin
  D := ReadFileBytes(FileName);
  if Length(D) < 30 then raise Exception.Create('Invalid Z80 file');

  if Word16(D, 6) <> 0 then
  begin
    Version := 1;
    HeaderLen := 30;
    HwMode := 0;
  end
  else
  begin
    HeaderLen := 32 + Word16(D, 30);
    if Word16(D, 30) = 23 then Version := 2 else Version := 3;
    HwMode := D[34];
  end;

  Need128 := False;
  Preferred := sm128K;
  Modify := (Version > 1) and ((D[37] and $80) <> 0);
  if Version = 2 then
    Need128 := HwMode in [3, 4]
  else if Version = 3 then
    case HwMode of
      4, 5, 6: Need128 := True;
      7, 8:
        begin
          Need128 := True;
          if Modify then Preferred := smPlus2B else Preferred := smPlus3;
        end;
      12: begin Need128 := True; Preferred := smPlus2; end;
      13: begin Need128 := True; Preferred := smPlus2B; end;
    end;
  if Need128 and (Preferred = sm128K) and Modify then Preferred := smPlus2;

  if Need128 then
  begin
    // Pick a model of the right family
    if (Preferred in [smPlus3, smPlus2B]) and (Spec.Info.Memory <> mkPlus3) then
      Spec.SetModel(Preferred)
    else if (Preferred in [sm128K, smPlus2]) and (Spec.Info.Memory <> mk128K) then
      Spec.SetModel(Preferred)
    else
      Spec.Reset(True);
  end
  else if Modify and (HwMode in [0, 1, 3]) then
    EnsureModel(Spec, False, sm16K)   // 48K hardware with the "modified" bit: 16K
  else
    EnsureModel(Spec, False, sm48K);

  Cpu := Spec.Cpu;
  Cpu.A := D[0]; Cpu.F := D[1];
  Cpu.BC.W := Word16(D, 2);
  Cpu.HL.W := Word16(D, 4);
  Cpu.SP.W := Word16(D, 8);
  Cpu.I := D[10];
  Flags := D[12];
  if Flags = $FF then Flags := 1;
  Cpu.R := (D[11] and $7F) or ((Flags and 1) shl 7);
  Cpu.R7 := Cpu.R;
  Spec.Border := (Flags shr 1) and 7;
  Cpu.DE.W := Word16(D, 13);
  Cpu.BC_.W := Word16(D, 15);
  Cpu.DE_.W := Word16(D, 17);
  Cpu.HL_.W := Word16(D, 19);
  Cpu.A_ := D[21]; Cpu.F_ := D[22];
  Cpu.IY.W := Word16(D, 23);
  Cpu.IX.W := Word16(D, 25);
  Cpu.IFF1 := D[27] <> 0;
  Cpu.IFF2 := D[28] <> 0;
  Cpu.IM := D[29] and 3;

  if Version = 1 then
  begin
    Cpu.PC.W := Word16(D, 6);
    if (Flags and $20) <> 0 then
      Decompress(D, 30, Length(D) - 30, @Ram48[0], SizeOf(Ram48))
    else
      for I := 0 to $BFFF do
        if 30 + I < Length(D) then Ram48[I] := D[30 + I] else Ram48[I] := 0;
    for I := 0 to $BFFF do Spec.WriteMem($4000 + I, Ram48[I], 0);
  end
  else
  begin
    Cpu.PC.W := Word16(D, 32);
    if Need128 then
    begin
      Paging := D[35];
      if (Spec.Info.Memory = mkPlus3) and (HeaderLen >= 87) then
        Paging2 := D[86]
      else
        Paging2 := 0;
      Spec.WritePaging1FFD(Paging2);
      Spec.WritePaging7FFD(Paging);
      if Spec.HasAY then
      begin
        for I := 0 to 15 do Spec.AY.WriteRegister(I, D[39 + I]);
        Spec.AY.SelectRegister(D[38]);
      end;
    end;
    Pos := HeaderLen;
    while Pos + 3 <= Length(D) do
    begin
      BlockLen := Word16(D, Pos);
      Page := D[Pos + 2];
      Inc(Pos, 3);
      if Need128 then
        Bank := Page - 3
      else
        case Page of
          4: Bank := 2;
          5: Bank := 0;
          8: Bank := 5;
        else
          Bank := -1;
        end;
      if BlockLen = $FFFF then
      begin
        if (Bank >= 0) and (Bank <= 7) and (Pos + $4000 <= Length(D)) then
          Move(D[Pos], Spec.RamBank(Bank)^[0], $4000);
        Inc(Pos, $4000);
      end
      else
      begin
        if (Bank >= 0) and (Bank <= 7) then
          Decompress(D, Pos, BlockLen, @Spec.RamBank(Bank)^[0], $4000);
        Inc(Pos, BlockLen);
      end;
    end;
  end;
  Cpu.T := Spec.Info.InterruptLength;
end;

procedure SaveZ80(Spec: TSpectrum; const FileName: string);
const
  HEADER_LEN = 32 + 55;
var
  D, Block: TBytes;
  Cpu: TZ80;
  I, Pos, Page: Integer;
  Banks: array of Integer;
  Pages: array of Integer;
begin
  Cpu := Spec.Cpu;
  SetLength(D, HEADER_LEN);
  FillChar(D[0], HEADER_LEN, 0);
  D[0] := Cpu.A; D[1] := Cpu.F;
  PutWord(D, 2, Cpu.BC.W);
  PutWord(D, 4, Cpu.HL.W);
  PutWord(D, 6, 0);
  PutWord(D, 8, Cpu.SP.W);
  D[10] := Cpu.I;
  D[11] := Cpu.GetR and $7F;
  D[12] := (Cpu.GetR shr 7) or (Spec.Border shl 1);
  PutWord(D, 13, Cpu.DE.W);
  PutWord(D, 15, Cpu.BC_.W);
  PutWord(D, 17, Cpu.DE_.W);
  PutWord(D, 19, Cpu.HL_.W);
  D[21] := Cpu.A_; D[22] := Cpu.F_;
  PutWord(D, 23, Cpu.IY.W);
  PutWord(D, 25, Cpu.IX.W);
  D[27] := Ord(Cpu.IFF1);
  D[28] := Ord(Cpu.IFF2);
  D[29] := Cpu.IM;
  PutWord(D, 30, 55);
  PutWord(D, 32, Cpu.PC.W);
  case Spec.Model of
    sm16K: begin D[34] := 0; D[37] := $80; end;
    sm48K: D[34] := 0;
    sm128K: D[34] := 4;
    smPlus2: D[34] := 12;
    smPlus2B: D[34] := 13;
    smPlus3: D[34] := 7;
  end;
  if Is128(Spec) then
  begin
    D[35] := Spec.Port7FFD;
    D[38] := Spec.AY.Selected;
    for I := 0 to 15 do D[39 + I] := Spec.AY.GetRegister(I);
    D[86] := Spec.Port1FFD;
    SetLength(Banks, 8);
    SetLength(Pages, 8);
    for I := 0 to 7 do
    begin
      Banks[I] := I;
      Pages[I] := I + 3;
    end;
  end
  else
  begin
    SetLength(Banks, 3);
    SetLength(Pages, 3);
    Banks[0] := 5; Pages[0] := 8;
    Banks[1] := 2; Pages[1] := 4;
    Banks[2] := 0; Pages[2] := 5;
  end;

  Pos := HEADER_LEN;
  for Page := 0 to High(Banks) do
  begin
    Block := Compress(@Spec.RamBank(Banks[Page])^[0], $4000);
    SetLength(D, Pos + 3 + Length(Block));
    PutWord(D, Pos, Length(Block));
    D[Pos + 2] := Pages[Page];
    Move(Block[0], D[Pos + 3], Length(Block));
    Inc(Pos, 3 + Length(Block));
  end;
  WriteFileBytes(FileName, D);
end;

end.

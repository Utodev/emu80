{ tzxtest: TZX files (1.20), made here block by block: every block is
  read; the signal of each kind has the pulses (lengths, levels) the
  specification says; flow control (loops, jumps, calls, stops, signal
  level) plays in the right order; a file cut short keeps what it has; a
  tape saved as .tap keeps only the data blocks; and the DAAD Ready test
  game as TZX loads, with fast loading and in real time.

    tzxtest <roms folder> <tests/daad folder> }
program tzxtest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, ZStream, Models, Spectrum, Tape;

type
  TEdge = record
    T: Integer;
    Level: Boolean;
  end;

  TListener = class
    Edges: array of TEdge;
    procedure Edge(T: Integer; Level: Boolean);
  end;

var
  Failures: Integer = 0;
  F: TMemoryStream;
  Tp: TTape;
  L: TListener;

procedure TListener.Edge(T: Integer; Level: Boolean);
begin
  SetLength(Edges, Length(Edges) + 1);
  Edges[High(Edges)].T := T;
  Edges[High(Edges)].Level := Level;
end;

procedure Check(Cond: Boolean; const What: string);
begin
  if not Cond then
  begin
    WriteLn('FAIL  ', What);
    Inc(Failures);
  end;
end;

{ Building a TZX file }

procedure Start;
begin
  F.Clear;
  F.WriteBuffer(PChar('ZXTape!')^, 7);
  F.WriteByte($1A);
  F.WriteByte(1);
  F.WriteByte(20);
end;

procedure B(V: Integer);
begin
  F.WriteByte(Byte(V));
end;

procedure W(V: Integer);
begin
  B(V and $FF);
  B((V shr 8) and $FF);
end;

procedure W3(V: Integer);
begin
  W(V and $FFFF);
  B((V shr 16) and $FF);
end;

procedure D(V: Integer);
begin
  W(V and $FFFF);
  W((V shr 16) and $FFFF);
end;

procedure Str(const S: string);
begin
  if S <> '' then F.WriteBuffer(S[1], Length(S));
end;

procedure Bytes(const A: array of Byte);
var
  X: Byte;
begin
  for X in A do B(X);
end;

procedure Load;
begin
  F.Position := 0;
  Tp.LoadTZXFromStream(F);
end;

{ The pulses played (the times between edges) from the start of the tape,
  with the level each edge leaves }
procedure PlayAll(MaxT: Integer = 400000000);
var
  T: Integer;
begin
  SetLength(L.Edges, 0);
  Tp.Play(0);
  T := 0;
  while Tp.Playing and (T < MaxT) do
  begin
    Inc(T, 1000000);
    Tp.AdvanceTo(T);
  end;
end;

function Gaps: string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to High(L.Edges) do
  begin
    if Result <> '' then Result := Result + ',';
    Result := Result + IntToStr(L.Edges[I].T - L.Edges[I - 1].T);
  end;
end;

function Levels: string;
var
  E: TEdge;
begin
  Result := '';
  for E in L.Edges do Result := Result + Chr(Ord('0') + Ord(E.Level));
end;

{ The DAAD Ready game's blocks, as a TAP file has them }
function TapBlocks(const FileName: string): specialize TArray<TBytes>;
var
  S: TFileStream;
  Len: Integer;
begin
  Result := nil;
  S := TFileStream.Create(FileName, fmOpenRead);
  try
    while S.Position + 2 <= S.Size do
    begin
      Len := S.ReadByte or (S.ReadByte shl 8);
      SetLength(Result, Length(Result) + 1);
      SetLength(Result[High(Result)], Len);
      S.ReadBuffer(Result[High(Result)][0], Len);
    end;
  finally
    S.Free;
  end;
end;

var
  Sp: TSpectrum;
  Blocks: specialize TArray<TBytes>;
  I, J: Integer;
  Z: TCompressionStream;
  Packed_: TMemoryStream;
  RLE: array[0..6] of Byte = (10, 20, 0, $2C, $01, 0, 0);
  TapName: string;
  Expected: string;
begin
  F := TMemoryStream.Create;
  Tp := TTape.Create;
  L := TListener.Create;
  Tp.OnEdge := @L.Edge;
  try
    // Every block of 1.20 is read, unknown ones skipped by their length
    Start;
    B($10); W(1000); W(3); Bytes([$FF, $AA, $55]);
    B($11); W(2000); W(600); W(700); W(400); W(800); W(3); B(1); W(0); W3(1); Bytes([$80]);
    B($12); W(1000); W(5);
    B($13); B(2); W(300); W(400);
    B($14); W(500); W(1000); B(3); W(0); W3(1); Bytes([$A0]);
    B($15); W(100); W(0); B(4); W3(1); Bytes([$C0]);
    B($18); D(10 + 7); W(0); W3(3500000); B(1); D(3); Bytes(RLE);
    B($20); W(0);
    B($21); B(5); Str('Group');
    B($22);
    B($23); W($FFFE);
    B($24); W(3);
    B($25);
    B($26); W(2); W(1); W($FFFF);
    B($27);
    B($28); W(1 + 2 + 1 + 3); B(1); W(1); B(3); Str('One');
    B($2A); D(0);
    B($2B); D(1); B(1);
    B($30); B(4); Str('Text');
    B($31); B(5); B(3); Str('Msg');
    B($32); W(1 + 2 + 5); B(1); B(0); B(5); Str('Title');
    B($33); B(1); Bytes([0, 1, 2]);
    B($35); Str('CustomInfo      '); D(2); Bytes([1, 2]);
    B($5A); Bytes([$58, $54, $61, $70, $65, $21, $1A, 1, 20]);
    B($4B); D(3); Bytes([1, 2, 3]);
    Load;
    Check(Tp.Count = 25, Format('25 blocks read (%d)', [Tp.Count]));
    if Tp.Count = 25 then
    begin
      Check((Tp[0].Kind = $10) and (Tp[0].PauseMs = 1000) and (Length(Tp[0].Data) = 3) and Tp[0].FitsRom,
        'standard block');
      Check((Tp[1].Kind = $11) and (Tp[1].PilotLen = 2000) and (Tp[1].PilotCount = 3) and
        (Tp[1].UsedBits = 1) and not Tp[1].FitsRom, 'turbo block');
      Check((Tp[2].PilotLen = 1000) and (Tp[2].PilotCount = 5), 'tone');
      Check((Length(Tp[3].Pulses) = 2) and (Tp[3].Pulses[1] = 400), 'pulse sequence');
      Check((Tp[4].Kind = $14) and (Tp[4].UsedBits = 3), 'pure data');
      Check((Tp[5].Kind = $15) and (Tp[5].SampleT = 100), 'direct recording');
      Check((Tp[6].Kind = $18) and (Length(Tp[6].Pulses) = 3) and (Tp[6].Pulses[2] = 300), 'CSW (RLE)');
      Check((Tp[7].Kind = $20) and (Tp[7].PauseMs = 0), 'stop the tape');
      Check(Tp[8].Text = 'Group', 'group name');
      Check(Tp[10].Value = -2, 'jump back');
      Check(Tp[11].Value = 3, 'loop count');
      Check((Length(Tp[13].Calls) = 2) and (Tp[13].Calls[1] = -1), 'call sequence');
      Check(Tp[15].Text = 'One', 'select');
      Check(Tp[17].Value = 1, 'signal level');
      Check(Tp[18].Text = 'Text', 'text');
      Check((Tp[19].Text = 'Msg') and (Tp[19].Value = 5), 'message');
      Check(Tp[20].Text = 'Title: Title', 'archive info');
      Check(Tp[22].Text = 'CustomInfo', 'custom info');
      Check(Tp[24].Kind = $4B, 'an unknown block skipped by its length');
    end;

    // The signals: tone, pulses, pure data (3 bits: 1 0 1), then a pause of
    // 1 ms (the end of the last pulse is an edge; high, it drops 1 ms later)
    Start;
    B($12); W(1000); W(5);
    B($13); B(2); W(300); W(400);
    B($14); W(500); W(1000); B(3); W(1); W3(1); Bytes([$A0]);
    Load;
    PlayAll;
    Check(Gaps = '1000,1000,1000,1000,1000,300,400,1000,1000,500,500,1000,1000',
      'tone, pulses and pure data: ' + Gaps);
    Check(Levels = '10101010101010', 'levels of tone, pulses and data: ' + Levels);
    Check(not Tp.Playing and (Tp.Current = Tp.Count), 'the tape stops at its end');

    // Turbo: 3 pilot pulses, two syncs, one bit; the pause leaves it low
    Start;
    B($11); W(2000); W(600); W(700); W(400); W(800); W(3); B(1); W(2); W3(1); Bytes([$80]);
    Load;
    PlayAll;
    Check(Gaps = '2000,2000,2000,600,700,800,800', 'turbo block: ' + Gaps);
    Check(Levels = '10101010', 'turbo levels: ' + Levels);

    // Direct recording: 4 samples (1 1 0 0) of 100 T
    Start;
    B($15); W(100); W(0); B(4); W3(1); Bytes([$C0]);
    Load;
    PlayAll;
    Check((Levels = '10') and (Gaps = '200'), 'direct recording: ' + Levels + ' ' + Gaps);

    // CSW, RLE and Z-RLE: pulses of 10, 20 and 300 T (at 3.5 MHz)
    Start;
    B($18); D(10 + 7); W(0); W3(3500000); B(1); D(3); Bytes(RLE);
    Packed_ := TMemoryStream.Create;
    try
      Z := TCompressionStream.Create(clDefault, Packed_);
      Z.WriteBuffer(RLE, SizeOf(RLE));
      Z.Free;
      B($18); D(10 + Packed_.Size); W(0); W3(3500000); B(2); D(3);
      F.WriteBuffer(Packed_.Memory^, Packed_.Size);
    finally
      Packed_.Free;
    end;
    Load;
    Check((Tp.Count = 2) and (Length(Tp[1].Pulses) = 3) and (Tp[1].Pulses[2] = 300), 'CSW (Z-RLE)');
    PlayAll;
    Check(Gaps = '10,20,300,10,20', 'CSW pulses: ' + Gaps);

    // Generalized data: a pilot symbol (100, 200) twice; data symbols 0
    // (toggle: 50, 50) and 1 (forced high: 70); the stream 1 0 1
    Start;
    B($19);
    D(2 + 4 + 1 + 1 + 4 + 1 + 1 + (1 + 4) + 3 + 2 * (1 + 4) + 1);
    W(0); D(1); B(2); B(1); D(3); B(2); B(2);
    B(0); W(100); W(200);          // pilot symbol 0
    B(0); W(2);                    // symbol 0, twice
    B(0); W(50); W(50);            // data symbol 0: toggles
    B(3); W(70); W(0);             // data symbol 1: high, one pulse
    B($A0);                        // 1 0 1
    Load;
    Check((Tp.Count = 1) and (Tp[0].GenCount = 3) and (Tp[0].GenBits = 1) and
      (Length(Tp[0].GenData[1].Pulses) = 1), 'generalized data read');
    PlayAll;
    // (the last symbol, high already, starts with no edge)
    Check(Gaps = '100,200,100,200,70,50', 'generalized pulses: ' + Gaps);
    Check(Levels = '1010101', 'generalized levels: ' + Levels);

    // Loops and jumps: 111, 222 three times, then 444 (333 jumped over)
    Start;
    B($12); W(111); W(1);
    B($24); W(3);
    B($12); W(222); W(1);
    B($25);
    B($23); W(2);
    B($12); W(333); W(1);
    B($12); W(444); W(1);
    B($12); W(1); W(1);
    Load;
    PlayAll;
    Check(Gaps = '111,222,222,222,444', 'loops and jumps: ' + Gaps);

    // Calls: blocks 2 then 4, back to block 1 afterwards
    Start;
    B($26); W(2); W(2); W(4);
    B($12); W(999); W(1);
    B($12); W(555); W(1);
    B($27);
    B($12); W(666); W(1);
    B($27);
    B($12); W(1); W(1);
    Load;
    PlayAll;
    Check(Gaps = '555,666,999,555,666', 'call sequence: ' + Gaps);

    // Stops: "stop the tape", and "stop if 48K" (only on a 48K)
    Start;
    B($12); W(100); W(2);
    B($20); W(0);
    B($12); W(100); W(2);
    B($2A); D(0);
    B($12); W(100); W(2);
    Load;
    Tp.StopIf48K := False;
    PlayAll;
    Check(not Tp.Playing and (Tp.Current = 2), 'stop the tape: stopped after it');
    Tp.AdvanceTo(0);
    PlayAll;
    Check(Tp.Current = 5, 'stop if 48K: goes on on a 128K');
    Tp.SelectBlock(2);
    Tp.StopIf48K := True;
    PlayAll;
    Check(not Tp.Playing and (Tp.Current = 4), 'stop if 48K: stops on a 48K');

    // The signal level
    Start;
    B($2B); D(1); B(1);
    B($12); W(100); W(2);
    Load;
    Tp.StopIf48K := False;
    Tp.SelectBlock(0);
    PlayAll;
    Check(Levels = '101', 'signal level set high: ' + Levels);

    // Continuous playback: at the end it goes on from the start
    Start;
    B($10); W(1000); W(3); Bytes([$FF, 1, $FE]);
    B($10); W(1000); W(3); Bytes([$FF, 2, $FD]);
    Load;
    Tp.Loop := True;
    Check(Tp.HasMore, 'a looping tape always has more');
    Tp.Play(0);
    Tp.AdvanceTo(2000000);
    Check(Tp.Playing, 'a looping tape is still playing after its length');
    Tp.AdvanceTo(8000000);
    Check(Tp.Playing and (Tp.Current < 2), 'a looping tape keeps wrapping to the start');
    Tp.Stop;
    Tp.Loop := False;
    PlayAll;
    Check(not Tp.Playing and (Tp.Current = 2) and not Tp.HasMore, 'without the loop it stops at the end');
    Tp.Loop := True;
    Tp.Rewind;
    Check(Tp.TakeBlockForTrap = Tp[0], 'the trap takes the first block');
    Check(Tp.TakeBlockForTrap = Tp[1], 'the trap takes the second block');
    Check(Tp.TakeBlockForTrap = Tp[0], 'the trap wraps to the first block on a looping tape');
    Tp.Loop := False;

    // Fast loading: only what the ROM can read; turbo timings play
    Start;
    B($30); B(2); Str('Hi');
    B($11); W(2168); W(667); W(735); W(855); W(1710); W(3223); B(8); W(1000); W3(3);
    Bytes([$FF, 1, $FE]);
    B($11); W(1500); W(400); W(400); W(400); W(800); W(1000); B(8); W(1000); W3(3);
    Bytes([$FF, 1, $FE]);
    Load;
    Check(Tp.TakeBlockForTrap = Tp[1], 'the trap takes a turbo block with the ROM''s timings');
    Check(Tp.NextNeedsRealTime, 'turbo timings next: the tape goes on playing after the trap');
    Check(Tp.TakeBlockForTrap = nil, 'the trap leaves turbo timings to play');

    // A file cut short: the blocks read until then, the last one partly
    Start;
    B($10); W(1000); W(3); Bytes([$FF, 1, $FE]);
    B($10); W(1000); W(100); Bytes([$FF, 1, 2]);
    Load;
    Check((Tp.Count = 2) and (Length(Tp[1].Data) = 3), 'a file cut short keeps what it has');
    F.Clear;
    Str('Not a TZX file at all');
    try
      Load;
      Check(False, 'a file that isn''t TZX is refused');
    except
      on Exception do ;
    end;

    // Saved as .tap: the data blocks only
    Start;
    B($10); W(1000); W(3); Bytes([$FF, 1, $FE]);
    B($30); B(2); Str('Hi');
    B($11); W(2168); W(667); W(735); W(855); W(1710); W(3223); B(8); W(1000); W3(3);
    Bytes([$FF, 2, $FD]);
    B($12); W(100); W(2);
    Load;
    Check(Tp.HasNonStandard, 'a TZX tape has blocks a .tap can''t keep');
    TapName := GetTempFileName;
    Tp.SaveTAP(TapName);
    Tp.LoadTAP(TapName);
    DeleteFile(TapName);
    Check((Tp.Count = 2) and (Tp[1].Data[1] = 2), 'saved as .tap: the two data blocks');

    // The DAAD Ready game as TZX (standard blocks): fast and real time
    Blocks := TapBlocks(IncludeTrailingPathDelimiter(ParamStr(2)) + 'test48.tap');
    Start;
    B($32); W(1 + 2 + 4); B(1); B(0); B(4); Str('Test');
    for I := 0 to High(Blocks) do
    begin
      B($10); W(1000); W(Length(Blocks[I]));
      F.WriteBuffer(Blocks[I][0], Length(Blocks[I]));
    end;
    Sp := TSpectrum.Create(sm48K, ParamStr(1));
    try
      for J := 0 to 1 do
      begin
        Sp.SetModel(sm48K);
        Sp.FastLoad := J = 0;
        Sp.AutoPlayTape := True;
        if J = 1 then Sp.SetSpeed(4) else Sp.SetSpeed(1);
        F.Position := 0;
        Sp.Tape.LoadTZXFromStream(F);
        Sp.AutoLoad;
        I := 0;
        while ((Sp.Peek($8401) <> $11) or (Sp.Peek($8402) <> $5F)) and (I < 6000) do
        begin
          Sp.RunFrame;
          Inc(I);
          // The reels move while it plays
          if (J = 1) and (I = 400) then
            Check(Sp.Tape.Progress > 0, 'the tape''s progress grows in real time');
        end;
        if J = 0 then Expected := 'with fast loading' else Expected := 'in real time';
        Check((Sp.Peek($8401) = $11) and (Sp.Peek($8402) = $5F), 'the game as TZX loads ' + Expected);
      end;
      // The emulator runs flat out while a tape plays in real time with fast
      // loading on; never with it off, nor with the tape stopped
      Sp.Tape.Stop;
      Sp.FastLoad := True;
      Check(not Sp.TapeAccelerating, 'a stopped tape is not accelerated');
      Sp.Tape.Rewind;
      Sp.Tape.Play(Sp.Cpu.T);
      Check(Sp.TapeAccelerating, 'a playing tape is accelerated with fast loading');
      Sp.FastLoad := False;
      Check(not Sp.TapeAccelerating, 'a playing tape is not accelerated without fast loading');
    finally
      Sp.Free;
    end;
  finally
    L.Free;
    Tp.Free;
    F.Free;
  end;
  if Failures = 0 then
    WriteLn('TZX tapes (1.20 blocks, pulses, flow, fast and real-time loading): all passed')
  else
    Halt(1);
end.

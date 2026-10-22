{ Auto play/stop: the tape starts when the Spectrum asks for it and stops
  when it doesn't, with a loader of our own (it reads the EAR bit in a tight
  loop, no ROM routine). Needs the ROMs:

    autoplaytest <roms folder> }
program autoplaytest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Models, Spectrum, Tape;

var
  Failures: Integer = 0;
  Sp: TSpectrum;
  F: TMemoryStream;

procedure Check(Cond: Boolean; const What: string);
begin
  if not Cond then
  begin
    WriteLn('FAIL  ', What);
    Inc(Failures);
  end;
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

{ Tone of N pulses of 2168 T: N/1600 seconds of tape }
procedure Tone(N: Integer);
begin
  B($12); W(2168); W(N);
end;

procedure Pause(Ms: Integer);
begin
  B($20); W(Ms);
end;

procedure StartTape;
begin
  F.Clear;
  F.WriteBuffer(PChar('ZXTape!')^, 7);
  B($1A); B(1); B(20);
end;

procedure InsertTape;
begin
  F.Position := 0;
  Sp.Tape.LoadTZXFromStream(F);
end;

{ What the program does: a loader reading the EAR bit as fast as it can (0),
  a game that reads the keyboard once a frame (1), or nothing but waiting (2) }
procedure Run_(Kind: Integer);
const
  LOADER: array[0..4] of Byte = ($F3, $DB, $FE, $18, $FC);        // DI: IN A,(FE): JR -4
  KEYS: array[0..5] of Byte = ($FB, $DB, $FE, $76, $18, $FC);     // EI: IN A,(FE): HALT: JR -4
  IDLE: array[0..3] of Byte = ($FB, $76, $18, $FD);               // EI: HALT: JR -3
var
  I: Integer;
begin
  case Kind of
    0: for I := 0 to High(LOADER) do Sp.Poke($8000 + I, LOADER[I]);
    1: for I := 0 to High(KEYS) do Sp.Poke($8000 + I, KEYS[I]);
  else
    for I := 0 to High(IDLE) do Sp.Poke($8000 + I, IDLE[I]);
  end;
  Sp.Cpu.Halted := False;
  Sp.Cpu.PC.W := $8000;
end;

procedure Frames(N: Integer);
var
  I: Integer;
begin
  for I := 1 to N do Sp.RunFrame;
end;

{ A standard block: flag, data, parity }
procedure StdBlock(Flag: Byte; const Data: array of Byte);
var
  I: Integer;
  X: Byte;
begin
  B($10); W(1000); W(Length(Data) + 2);
  B(Flag);
  X := Flag;
  for I := 0 to High(Data) do
  begin
    B(Data[I]);
    X := X xor Data[I];
  end;
  B(X);
end;

{ The ROM's own LD-BYTES, called as a program would: the flag, the length and
  where, with a return to an idle loop at 8000. Runs it up to 60 seconds. }
function RomLoad(Flag: Byte; Len, Addr: Word): Boolean;
var
  I: Integer;
begin
  Sp.Poke($8000, $FB); Sp.Poke($8001, $76); Sp.Poke($8002, $18); Sp.Poke($8003, $FD);
  Sp.Cpu.SP.W := $7F00;
  Sp.Poke($7EFE, $00); Sp.Poke($7EFF, $80);
  Sp.Cpu.SP.W := $7EFE;
  Sp.Cpu.A := Flag;
  Sp.Cpu.F := Sp.Cpu.F or 1;          // carry: load
  Sp.Cpu.DE.W := Len;
  Sp.Cpu.IX.W := Addr;
  Sp.Cpu.Halted := False;
  Sp.Cpu.PC.W := $0556;
  for I := 1 to 3000 do
  begin
    Sp.RunFrame;
    if (Sp.Cpu.PC.W >= $8000) and (Sp.Cpu.PC.W < $8004) then Exit(True);
  end;
  Result := False;
end;

var
  Pos0: Integer;
begin
  F := TMemoryStream.Create;
  Sp := TSpectrum.Create(sm48K, ParamStr(1));
  try
    Sp.FastLoad := False;
    Sp.AutoPlayTape := True;
    Sp.Tape.Loop := False;
    Sp.Tape.StopIf48K := False;
    Frames(5);

    // Blocks of tone, with pauses between them: a short one first, so that
    // the tape is past it when the loader stops asking
    StartTape;
    Tone(600); Pause(100);
    Tone(3000); Pause(200);
    Tone(3000);
    InsertTape;

    // Something that only reads the keyboard now and then doesn't start it
    Run_(1);
    Frames(200);
    Check(not Sp.Tape.Playing, 'occasional port reads do not start the tape');
    Run_(2);
    Frames(20);

    // A loader of its own starts it, after a moment of reading
    Run_(0);
    Frames(5);
    Check(not Sp.Tape.Playing, 'a moment of reading is not yet a load');
    Frames(20);
    Check(Sp.Tape.Playing, 'a custom loader reading the EAR bit starts the tape');

    // When it stops asking, the tape stops where it is
    Run_(2);
    Frames(40);
    Check(Sp.Tape.Playing, 'a short silence does not stop it (no false Play/Stop cycles)');
    Frames(60);
    Check(not Sp.Tape.Playing, 'the tape stops when nothing asks for it any more');
    Pos0 := Sp.Tape.Current;
    Check(Pos0 > 0, 'it stopped where it was (at its block), not at the start');

    // The next load goes on from there
    Run_(0);
    Frames(25);
    Check(Sp.Tape.Playing and (Sp.Tape.Current >= Pos0), 'the next load resumes from the position it was left at');

    // Stopped by the user while the load goes on: not started again for it
    Sp.StopTape;
    Pos0 := Sp.Tape.Current;
    Frames(60);
    Check(not Sp.Tape.Playing and (Sp.Tape.Current = Pos0), 'after a manual Stop it does not restart for the same load');
    Check(Sp.TapeAutoHeld, 'and says it waits for the next load');
    Run_(2);
    Frames(80);
    Run_(0);
    Frames(25);
    Check(Sp.Tape.Playing, 'a new load, after that one ended, is free to start it');

    // Manual Play over a held Auto play, and Stop with nothing asking
    Run_(2);
    Frames(100);
    Check(not Sp.Tape.Playing, 'stopped again with nothing asking');
    Sp.PlayTape;
    Check(Sp.Tape.Playing and not Sp.TapeAutoHeld, 'the user''s Play plays');
    Sp.StopTape;
    Check(not Sp.Tape.Playing, 'the user''s Stop stops');

    // Choosing a block and playing (the tape browser's double click)
    Sp.Tape.SelectBlock(2);
    Sp.PlayTape;
    Check(Sp.Tape.Playing and (Sp.Tape.Current = 2), 'play from a chosen block');
    Sp.StopTape;

    // The end of the tape: no restart by itself, with a loader asking
    Sp.Tape.SelectBlock(Sp.Tape.Count);
    Run_(0);
    Frames(40);
    Check(not Sp.Tape.Playing and (Sp.Tape.Current = Sp.Tape.Count), 'at the end of the tape the tape is not started again');
    Sp.Tape.Rewind;
    Frames(2);
    Check(Sp.Tape.Playing and (Sp.Tape.Current = 0), 'rewound, with the load still asking, it plays from the start again');
    Run_(2);
    Frames(120);

    // "Stop the tape" in a TZX: it stays stopped for the load that is asking
    StartTape;
    Tone(1500);
    B($20); W(0);
    Tone(1500);
    InsertTape;
    Run_(0);
    Frames(150);
    Check(not Sp.Tape.Playing and Sp.Tape.StoppedByBlock and (Sp.Tape.Current = 2),
      'a zero pause stops the tape, and Auto play does not start it at once');
    Check(Sp.TapeAutoHeld, 'it waits for the next load');
    Run_(2);
    Frames(80);
    Run_(0);
    Frames(25);
    Check(Sp.Tape.Playing, 'the next load goes on after the stop block');
    Run_(2);
    Frames(150);

    // Auto play/stop off: the tape is the user's
    Sp.AutoPlayTape := False;
    Sp.Tape.Rewind;
    Run_(0);
    Frames(60);
    Check(not Sp.Tape.Playing, 'with Auto play off a loader does not start the tape');
    Sp.PlayTape;
    Run_(2);
    Frames(20);
    Check(Sp.Tape.Playing, 'with Auto play off the user''s Play plays');
    Frames(150);
    Check(Sp.Tape.StoppedByBlock and (Sp.Tape.Current = 2),
      'with Auto play off nothing stops a tape that plays, but the TZX''s own stop block');

    // The ROM's loader (TAP-like blocks): the tape starts with LD-BYTES, goes
    // on from the right block for a second load made later, and stops in
    // between and at the end of each one
    StartTape;
    StdBlock($00, [1, 2, 3]);
    StdBlock($FF, [10, 20, 30, 40]);
    StdBlock($00, [4, 5, 6]);
    StdBlock($FF, [50, 60, 70]);
    InsertTape;
    Sp.AutoPlayTape := True;
    Sp.FastLoad := False;
    Run_(2);
    Frames(120);
    Check(not Sp.Tape.Playing and (Sp.Tape.Current = 0), 'before any load the tape is where it was put');
    Check(RomLoad($00, 3, $9000), 'the ROM loads a header');
    Check(Sp.Peek($9000) = 1, 'the header was read from the tape');
    Check(Sp.Tape.Playing or (Sp.Tape.Current > 0), 'the ROM''s load started the tape');
    Check(RomLoad($FF, 4, $9100), 'the ROM loads the data');
    Check(Sp.Peek($9100) = 10, 'the data was read from the tape');
    Frames(40);
    Check(not Sp.Tape.Playing, 'a few frames after the load the tape stops');
    Pos0 := Sp.Tape.Current;
    Check(Pos0 >= 2, 'it stopped after the first two blocks, not at the start');
    // The game runs for a while with the tape stopped, then asks again
    Frames(300);
    Check(not Sp.Tape.Playing and (Sp.Tape.Current = Pos0), 'the stopped tape stays where it is while the game runs');
    Check(RomLoad($00, 3, $9200) and (Sp.Peek($9200) = 4), 'the next load goes on from the next block');
    Check(RomLoad($FF, 3, $9300) and (Sp.Peek($9300) = 50), 'and its data');
    Frames(40);
    Check(not Sp.Tape.Playing, 'stopped again at the end of that load');
  finally
    Sp.Free;
    F.Free;
  end;
  if Failures = 0 then
    WriteLn('Tape auto play/stop (custom loaders, manual Stop, end of tape, TZX stop): all passed')
  else
    Halt(1);
end.

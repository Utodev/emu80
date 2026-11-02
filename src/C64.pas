{ C64: the Commodore 64 (PAL): the 6510, 64K of RAM with the BASIC, KERNAL and character ROMs behind the
  PLA's banking, the VIC-II, two CIAs, the SID, the keyboard and the joysticks, the cassette (a .tap file played
  into the CIA's FLAG line) and up to two 1541 disk drives on the serial bus.

  Everything advances one cycle at a time in Clock, which every access of the 6510 calls (a read first waits while the
  VIC-II holds the bus). TSpectrum holds a TC64 as it holds the Amstrad's or the MSX's hardware. }
unit C64;

{$mode objfpc}{$H+}
{$R-}{$Q-}

interface

uses
  SysUtils, Classes, Cpu6510, C64Vic, C64Cia, C64Sid, C64Disk, C64Drive, C64Expr;

const
  C64_CLOCK = 985248;
  C64_FRAME_CYCLES = VIC_LINES * VIC_CYCLES;      // 19656: 50.12 frames a second
  C64_BP_EXEC = 1;
  C64_BP_READ = 2;
  C64_BP_WRITE = 4;
  C64_BP_DISABLED = $80;
  { The DAAD interpreter for the C64 loads the database (DDB) at $3880 and keeps the 256 flags (then the objects'
    locations) 514 bytes before it }
  C64_DAAD_FLAGS = $3880 - 514;

const
  { The keys, as column * 8 + row (the CIA 1's port A bit and port B bit) }
  C64K_DEL = 0; C64K_RETURN = 1; C64K_CRSR_RIGHT = 2; C64K_F7 = 3; C64K_F1 = 4; C64K_F3 = 5; C64K_F5 = 6; C64K_CRSR_DOWN = 7;
  C64K_3 = 8; C64K_W = 9; C64K_A = 10; C64K_4 = 11; C64K_Z = 12; C64K_S = 13; C64K_E = 14; C64K_LSHIFT = 15;
  C64K_5 = 16; C64K_R = 17; C64K_D = 18; C64K_6 = 19; C64K_C = 20; C64K_F = 21; C64K_T = 22; C64K_X = 23;
  C64K_7 = 24; C64K_Y = 25; C64K_G = 26; C64K_8 = 27; C64K_B = 28; C64K_H = 29; C64K_U = 30; C64K_V = 31;
  C64K_9 = 32; C64K_I = 33; C64K_J = 34; C64K_0 = 35; C64K_M = 36; C64K_K = 37; C64K_O = 38; C64K_N = 39;
  C64K_PLUS = 40; C64K_P = 41; C64K_L = 42; C64K_MINUS = 43; C64K_PERIOD = 44; C64K_COLON = 45; C64K_AT = 46; C64K_COMMA = 47;
  C64K_POUND = 48; C64K_STAR = 49; C64K_SEMICOLON = 50; C64K_HOME = 51; C64K_RSHIFT = 52; C64K_EQUALS = 53; C64K_UP_ARROW = 54; C64K_SLASH = 55;
  C64K_1 = 56; C64K_LEFT_ARROW = 57; C64K_CTRL = 58; C64K_2 = 59; C64K_SPACE = 60; C64K_CBM = 61; C64K_Q = 62; C64K_RUNSTOP = 63;
  C64K_COUNT = 64;

type
  TC64Ram = array[0..65535] of Byte;

  { The cassette: a .tap file (C64-TAPE-RAW) as a list of pulses, each the cycles between two falling edges }
  TC64Tape = class
  private
    FPulses: array of LongWord;
    FPos: Integer;
    FRemaining: LongWord;
    FName: string;
    FPulseCount: Integer;
    procedure Next;
  public
    procedure LoadFromFile(const FileName: string);
    procedure LoadFromBytes(const Bytes: TBytes);
    procedure Rewind;
    procedure Eject;
    { Where the tape is, for the debugger's step back (the same tape: else nothing changes) }
    procedure StateIO(S: TStream; Save: Boolean);
    { One cycle: True when the signal falls (a pulse starts) }
    function Tick: Boolean; inline;
    property Pos: Integer read FPos write FPos;
    property Count: Integer read FPulseCount;
    property Name: string read FName;
    function AtEnd: Boolean;
    function Present: Boolean;
    { The length of a pulse in cycles }
    function PulseCycles(I: Integer): LongWord;
    { Put the tape at pulse I }
    procedure SeekTo(I: Integer);
  end;

  TC64Read = procedure(Addr: Word) of object;

  TC64BreakKind = (cbkNone, cbkExec, cbkRead, cbkWrite, cbkRunTo, cbkDaad);

  { An access of the processor to a chip's register (the VIC-II, the SID, the CIAs, the I/O areas at DE00-DFFF) or
    to the 6510's port (0 and 1), for the debugger's ports zone }
  TC64IoAccess = record
    PC: Word;          // the instruction that did it
    Addr: Word;
    Value: Byte;
    Write: Boolean;
    Step: LongWord;    // InstrCount then
  end;

const
  C64_IO_LOG = 50;     // accesses remembered

type

  TC64 = class(T6502Bus)
  private
    FRam: TC64Ram;
    FBasic: array[0..8191] of Byte;
    FKernal: array[0..8191] of Byte;
    FChar: array[0..4095] of Byte;
    FPort, FDdr: Byte;               // the 6510's I/O port (addresses 1 and 0)
    FPortPins: Byte;                 // what the port's bits 4 and 5 read
    FBank: Integer;                  // LORAM, HIRAM and CHAREN as the PLA sees them
    FCpu: T6510;
    FVic: TVic;
    FCia1, FCia2: TCia;
    FSid: TSid;
    FIec: TIecBus;
    FDrive: array[0..1] of TC64Drive;
    FDriveOn: array[0..1] of Boolean;
    FDriveRom: string;
    FTape: TC64Tape;
    FTapePressed: Boolean;           // PLAY is down
    FAutoPlay: Boolean;              // PLAY goes down by itself when the KERNAL asks for it
    FAutoSaveDisks: Boolean;         // what a drive writes goes to the .d64 file once the drive is quiet
    FTapeMotor: Boolean;
    FKeys: array[0..7] of Byte;      // the matrix: a set bit is a key down (column, row bit)
    FJoy: array[1..2] of Byte;       // bits 0-4: up, down, left, right, fire, set when held
    FRestart: Boolean;
    FNmiPrev: Boolean;
    FIrqPrev, FNmiSeen: Boolean;
    FFrameCycle: Integer;
    FTotalCycles: Int64;
    FFrames: Int64;
    FInstrCount: LongWord;           // instructions run (an interrupt taken counts as one)
    FIoLog: array[0..C64_IO_LOG - 1] of TC64IoAccess;
    FIoLogPos, FIoLogCount: Integer;
    FSamples: array of SmallInt;
    FSampleCount: Integer;
    FSampleAcc: Double;
    FMuted: Boolean;
    FLastBus: Byte;
    // Debugger
    FBreakFlags: array[0..65535] of Byte;
    FBreakHit: Boolean;
    FBreakKind: TC64BreakKind;
    FBreakAddr: Word;
    FBreakInstr: Word;
    FSkipBreakOnce: Boolean;
    FTempBreak: Integer;
    FMemBreaks: Integer;
    FSuppress: Boolean;
    FCondition: array of TC64Condition;
    // Typing and auto load
    FTypeQueue: string;
    FTypeCount: Integer;
    FAutoStage: Integer;
    FAutoWait: Integer;
    FAutoPrg: TBytes;
    FAutoCmd: string;
    FIdleHits, FIdleFrames: Integer;
    FResetFrame: Int64;
    FLastMedia: string;
    FDaadOn: Boolean;
    FDaadMap: array[0..65535] of Byte;
    FOnDaadRead: TC64Read;
    procedure Clock; inline;
    procedure UpdateBank;
    function IoRead(Addr: Word): Byte;
    procedure IoWrite(Addr: Word; Value: Byte);
    function ReadMem(Addr: Word): Byte;
    procedure WriteMem(Addr: Word; Value: Byte);
    function VicRead(Addr: Word): Byte;
    function Cia1PortA: Byte;
    function Cia1PortB: Byte;
    function Cia2PortA: Byte;
    procedure UpdateIec;
    procedure LogIo(Addr: Word; Value: Byte; IsWrite: Boolean); inline;
    procedure FinishFrame;
    procedure AutoStep;
    procedure PushKeys;
    function LoadRomFile(const Path: string; var Buf; Size: Integer): Boolean;
    procedure ApplyPrg(const Bytes: TBytes);
    procedure ReleaseDisk(Disk: TD64Image);
    procedure SaveIfDirty(Disk: TD64Image);
    function GetDrive(N: Integer): TC64Drive;
    function GetDriveOn(N: Integer): Boolean;
    function GetTapePressed: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    { Raises if a ROM is missing }
    procedure LoadRoms(const KernalPath, BasicPath, CharPath, DrivePath: string);
    procedure Reset(Hard: Boolean);
    { The whole state, for the debugger's step back: written to S (Save) or read back from it. The fields it copies as
      blocks (see StateIO) are plain values: no strings or dynamic arrays may go in between them }
    procedure StateIO(S: TStream; Save: Boolean);
    { Run until the end of the frame; False if a breakpoint stopped it }
    function RunFrame: Boolean;
    { One instruction (or the interrupt sequence) }
    procedure StepInstruction;
    function Read(Addr: Word): Byte; override;
    procedure Write(Addr: Word; Value: Byte); override;
    { What the CPU would read, without side effects or breakpoints; also the RAM under a ROM }
    function Peek(Addr: Word): Byte;
    function PeekRam(Addr: Word): Byte;
    procedure Poke(Addr: Word; Value: Byte);
    procedure PokeRam(Addr: Word; Value: Byte);
    { A register of the VIC-II, the SID, the CIAs or the colour RAM ($D000-$DFFF), whatever the processor maps there }
    procedure PokeIo(Addr: Word; Value: Byte);
    { What the 6510 sees at that address: 0 RAM, 1 BASIC ROM, 2 KERNAL ROM, 3 character ROM, 4 I/O }
    function MemoryAt(Addr: Word): Integer;
    { Keys: the matrix position and the joysticks (ports 1 and 2) }
    procedure SetKey(Col, Row: Integer; Down: Boolean);
    procedure SetJoystick(Port: Integer; Bits: Byte);
    procedure SetRestore(Down: Boolean);
    procedure SetKeyColumn(Col: Integer; Bits: Byte);
    procedure ReleaseKeys;
    { Typing: ASCII text through the keyboard buffer (as the KERNAL's own keys) }
    procedure TypeText(const Text: string);
    function Typing: Boolean;
    { Programs: a .prg file put in memory (and run), disks and tapes }
    procedure LoadPrg(const FileName: string; Run: Boolean);
    procedure LoadPrgBytes(const Bytes: TBytes; Run: Boolean);
    { FromDisk: LOAD"*",8,1 (Drive 0) or LOAD"*",9,1 (Drive 1); otherwise from the tape }
    procedure AutoLoad(FromDisk: Boolean; Drive: Integer = 0);
    procedure InsertDisk(Drive: Integer; Disk: TD64Image);
    { The disk goes out (and is freed: the machine owns the images put in it) }
    procedure EjectDisk(Drive: Integer);
    procedure SaveDisk(Drive: Integer; const FileName: string);
    property AutoSaveDisks: Boolean read FAutoSaveDisks write FAutoSaveDisks;
    function DiskAt(Drive: Integer): TD64Image;
    procedure InsertTape(const FileName: string);
    procedure EjectTape;
    procedure PlayTape;
    procedure StopTape;
    { The audio of the frame just run, 44100 Hz stereo }
    function Samples: Pointer;
    property SampleCount: Integer read FSampleCount;
    { Sound/video helpers }
    procedure CopyFrame(Dest: PLongWord);
    { Breakpoints }
    function GetBreakpoint(Addr: Word): Byte;
    procedure SetBreakpoint(Addr: Word; Flags: Byte);
    procedure ClearBreakpoints;
    function SetCondition(Addr: Word; const Text: string; out Error: string): Boolean;
    function ConditionOf(Addr: Word): string;
    procedure SkipBreakpointOnce;
    function EvalCondition(const Text: string; out Value: Integer; out Error: string): Boolean;
    function ConditionHolds(Addr: Word): Boolean;
    function BreakHits(Addr: Word): Integer;
    function ExprState: TExprState;
    { The DAAD interpreter's reads, for the Adventure Debugger (Map has DAAD_* flags per address) }
    procedure SetDaadMap(Map: PByte);
    property Cpu: T6510 read FCpu;
    property Vic: TVic read FVic;
    property Cia1: TCia read FCia1;
    property Cia2: TCia read FCia2;
    property Sid: TSid read FSid;
    property Tape: TC64Tape read FTape;
    property TapePressed: Boolean read GetTapePressed;
    property AutoPlay: Boolean read FAutoPlay write FAutoPlay;
    { PLAY has been pressed by the user (not by auto play) }
    property PlayDown: Boolean read FTapePressed;
    property TapeMotor: Boolean read FTapeMotor;
    property Drive[N: Integer]: TC64Drive read GetDrive;
    property DriveOn[N: Integer]: Boolean read GetDriveOn;
    property Frames: Int64 read FFrames;
    property FramesSinceReset: Int64 read FFrames;
    property Muted: Boolean read FMuted write FMuted;
    property BreakHit: Boolean read FBreakHit write FBreakHit;
    property BreakKind: TC64BreakKind read FBreakKind write FBreakKind;
    property BreakAddr: Word read FBreakAddr;
    property BreakInstr: Word read FBreakInstr;
    property TempBreak: Integer read FTempBreak write FTempBreak;
    property Port: Byte read FPort;
    property Ddr: Byte read FDdr;
    property Bank: Integer read FBank;
    property Iec: TIecBus read FIec;
    property LastMedia: string read FLastMedia write FLastMedia;
    property DaadOn: Boolean read FDaadOn;
    { Told of every read of an address the map flags }
    property OnDaadRead: TC64Read read FOnDaadRead write FOnDaadRead;
    property FrameCycle: Integer read FFrameCycle;
    { The accesses to the chips and the 6510's port, newest first (Index 0) }
    function IoLogCount: Integer;
    function IoLog(Index: Integer): TC64IoAccess;
    property InstrCount: LongWord read FInstrCount;
    property TotalCycles: Int64 read FTotalCycles;
    procedure SetDriveEnabled(N: Integer; Value: Boolean);
    { A drive is working (motor on): the emulation may run flat out while a program loads }
    function DriveBusy: Boolean;
    function DiskActivity: QWord;
  end;

{ ASCII to the PETSCII the keyboard gives }
function AsciiToPetscii(C: Char): Byte;
{ The key (and the one to hold with it: SHIFT, or -1) that makes a printable character on the C64's keyboard }
function C64KeysForChar(Ch: Char; out Key, Modifier: Integer): Boolean;

implementation

uses
  Lang;

function AsciiToPetscii(C: Char): Byte;
begin
  case C of
    'a'..'z': Result := Ord(C) - 32;          // the letter keys give the capitals of the default set
    #10, #13: Result := 13;
  else
    Result := Ord(C);
  end;
end;

function C64KeysForChar(Ch: Char; out Key, Modifier: Integer): Boolean;
const
  PLAIN = ' +-.:@,*;=/0123456789';
  PLAIN_KEYS: array[1..21] of Integer = (C64K_SPACE, C64K_PLUS, C64K_MINUS, C64K_PERIOD, C64K_COLON, C64K_AT, C64K_COMMA,
    C64K_STAR, C64K_SEMICOLON, C64K_EQUALS, C64K_SLASH, C64K_0, C64K_1, C64K_2, C64K_3, C64K_4, C64K_5, C64K_6, C64K_7,
    C64K_8, C64K_9);
  // Typed with SHIFT
  SHIFTED = '!"#$%&''()<>?[]';
  SHIFTED_KEYS: array[1..15] of Integer = (C64K_1, C64K_2, C64K_3, C64K_4, C64K_5, C64K_6, C64K_7, C64K_8, C64K_9,
    C64K_COMMA, C64K_PERIOD, C64K_SLASH, C64K_COLON, C64K_SEMICOLON, C64K_SLASH);
  LETTERS: array['A'..'Z'] of Integer = (C64K_A, C64K_B, C64K_C, C64K_D, C64K_E, C64K_F, C64K_G, C64K_H, C64K_I, C64K_J,
    C64K_K, C64K_L, C64K_M, C64K_N, C64K_O, C64K_P, C64K_Q, C64K_R, C64K_S, C64K_T, C64K_U, C64K_V, C64K_W, C64K_X, C64K_Y,
    C64K_Z);
var
  P: Integer;
begin
  Result := True;
  Modifier := -1;
  if Ch in ['a'..'z'] then
  begin
    Key := LETTERS[UpCase(Ch)];
    Exit;
  end;
  if Ch in ['A'..'Z'] then
  begin
    Key := LETTERS[Ch];
    Modifier := C64K_LSHIFT;
    Exit;
  end;
  P := Pos(Ch, PLAIN);
  if P > 0 then
  begin
    Key := PLAIN_KEYS[P];
    Exit;
  end;
  P := Pos(Ch, SHIFTED);
  if P > 0 then
  begin
    Key := SHIFTED_KEYS[P];
    Modifier := C64K_LSHIFT;
    // [ and ] are SHIFT + : and SHIFT + ; ; the last one in the list is a second way to ?
    if Ch = '?' then Key := C64K_SLASH;
    Exit;
  end;
  case Ch of
    '_': Key := C64K_LEFT_ARROW;
    '^': Key := C64K_UP_ARROW;
    #$A3: Key := C64K_POUND;
  else
    Result := False;
  end;
end;

{ TC64Tape }

procedure TC64Tape.LoadFromBytes(const Bytes: TBytes);
var
  I, Ver, N: Integer;
  Len: LongWord;
begin
  if (Length(Bytes) < 20) or (Copy(StringOf(Bytes), 1, 12) <> 'C64-TAPE-RAW') then
    raise Exception.Create(_('Not a C64 tape image (.tap)'));
  Ver := Bytes[12];
  SetLength(FPulses, Length(Bytes));
  N := 0;
  I := 20;
  while I < Length(Bytes) do
  begin
    if Bytes[I] <> 0 then
    begin
      FPulses[N] := Bytes[I] * 8;
      Inc(I);
    end
    else if (Ver >= 1) and (I + 3 < Length(Bytes)) then
    begin
      Len := Bytes[I + 1] or (Bytes[I + 2] shl 8) or (Bytes[I + 3] shl 16);
      FPulses[N] := Len;
      Inc(I, 4);
    end
    else
    begin
      FPulses[N] := 256 * 8;
      Inc(I);
    end;
    Inc(N);
  end;
  FPulseCount := N;
  Rewind;
end;

procedure TC64Tape.LoadFromFile(const FileName: string);
var
  F: TFileStream;
  B: TBytes;
begin
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(B, F.Size);
    if F.Size > 0 then F.ReadBuffer(B[0], F.Size);
  finally
    F.Free;
  end;
  LoadFromBytes(B);
  FName := ExtractFileName(FileName);
end;

procedure TC64Tape.Rewind;
begin
  FPos := 0;
  FRemaining := 0;
  if FPulseCount > 0 then FRemaining := FPulses[0];
end;

procedure TC64Tape.Eject;
begin
  SetLength(FPulses, 0);
  FPulseCount := 0;
  FPos := 0;
  FRemaining := 0;
  FName := '';
end;

function TC64Tape.PulseCycles(I: Integer): LongWord;
begin
  if (I >= 0) and (I < FPulseCount) then Result := FPulses[I] else Result := 0;
end;

procedure TC64Tape.SeekTo(I: Integer);
begin
  if I < 0 then I := 0;
  if I > FPulseCount then I := FPulseCount;
  FPos := I;
  if I < FPulseCount then FRemaining := FPulses[I] else FRemaining := 0;
end;

function TC64Tape.AtEnd: Boolean;
begin
  Result := FPos >= FPulseCount;
end;

function TC64Tape.Present: Boolean;
begin
  Result := FPulseCount > 0;
end;

procedure TC64Tape.Next;
begin
  Inc(FPos);
  if FPos < FPulseCount then FRemaining := FPulses[FPos] else FRemaining := 0;
end;

function TC64Tape.Tick: Boolean;
begin
  Result := False;
  if FPos >= FPulseCount then Exit;
  if FRemaining > 0 then Dec(FRemaining);
  if FRemaining = 0 then
  begin
    Result := True;
    Next;
  end;
end;

{ TC64 }

constructor TC64.Create;
begin
  inherited Create;
  FCpu := T6510.Create(Self);
  FVic := TVic.Create;
  FVic.OnRead := @VicRead;
  FCia1 := TCia.Create(C64_CLOCK div 50);
  FCia2 := TCia.Create(C64_CLOCK div 50);
  FCia1.OnPortA := @Cia1PortA;
  FCia1.OnPortB := @Cia1PortB;
  FCia2.OnPortA := @Cia2PortA;
  FSid := TSid.Create(C64_CLOCK);
  FIec := TIecBus.Create;
  FDrive[0] := TC64Drive.Create(FIec, 8);
  FDrive[1] := TC64Drive.Create(FIec, 9);
  FDriveOn[0] := True;
  FDrive[0].Connected := True;
  FTape := TC64Tape.Create;
  FTempBreak := -1;
  SetLength(FSamples, 2 * 2048);
end;

destructor TC64.Destroy;
var
  I: Integer;
begin
  ClearBreakpoints;
  for I := 0 to 1 do ReleaseDisk(FDrive[I].EjectDisk);
  FTape.Free;
  for I := 0 to 1 do FDrive[I].Free;
  FIec.Free;
  FSid.Free;
  FCia1.Free;
  FCia2.Free;
  FVic.Free;
  FCpu.Free;
  inherited Destroy;
end;

function TC64.GetTapePressed: Boolean;
begin
  Result := FTape.Present and not FTape.AtEnd and (FTapePressed or FAutoPlay);
end;

function TC64.GetDriveOn(N: Integer): Boolean;
begin
  Result := FDriveOn[N and 1];
end;

function TC64.GetDrive(N: Integer): TC64Drive;
begin
  Result := FDrive[N and 1];
end;

{ A file by its path; if the name's case is not the one on disk (on Linux), the one that matches in that folder }
function FindFileNoCase(const Path: string): string;
var
  SR: TSearchRec;
  Dir, Name: string;
begin
  Result := Path;
  if FileExists(Path) then Exit;
  Dir := ExtractFilePath(Path);
  Name := ExtractFileName(Path);
  if Dir = '' then Dir := './';
  if FindFirst(Dir + '*', faAnyFile, SR) = 0 then
  begin
    repeat
      if SameText(SR.Name, Name) then
      begin
        Result := Dir + SR.Name;
        Break;
      end;
    until FindNext(SR) <> 0;
    FindClose(SR);
  end;
end;

function TC64.LoadRomFile(const Path: string; var Buf; Size: Integer): Boolean;
var
  F: TFileStream;
  P: string;
begin
  Result := False;
  P := FindFileNoCase(Path);
  if not FileExists(P) then Exit;
  F := TFileStream.Create(P, fmOpenRead or fmShareDenyNone);
  try
    if F.Size <> Size then Exit;
    F.ReadBuffer(Buf, Size);
  finally
    F.Free;
  end;
  Result := True;
end;

procedure TC64.LoadRoms(const KernalPath, BasicPath, CharPath, DrivePath: string);
var
  Missing: string;
  I: Integer;
begin
  Missing := '';
  if not LoadRomFile(BasicPath, FBasic, 8192) then Missing := Missing + ' ' + ExtractFileName(BasicPath);
  if not LoadRomFile(KernalPath, FKernal, 8192) then Missing := Missing + ' ' + ExtractFileName(KernalPath);
  if not LoadRomFile(CharPath, FChar, 4096) then Missing := Missing + ' ' + ExtractFileName(CharPath);
  if Missing <> '' then
    raise Exception.Create(Format(_('The C64 ROMs are missing from %s:%s'), [ExtractFilePath(KernalPath), Missing]));
  // The drive's DOS is optional: without it there are no drives
  for I := 0 to 1 do FDrive[I].LoadRom(FindFileNoCase(DrivePath));
end;

procedure TC64.Reset(Hard: Boolean);
var
  I: Integer;
begin
  if Hard then
  begin
    // The RAM comes up with the pattern of 64 bytes of 0 and 64 of $FF
    for I := 0 to 65535 do
      if (I and $40) = 0 then FRam[I] := 0 else FRam[I] := $FF;
  end;
  FDdr := $2F;
  FPort := $37;
  UpdateBank;
  FVic.Reset;
  FCia1.Reset;
  FCia2.Reset;
  FSid.Reset;
  FIec.ComputerAtn := True;
  FIec.ComputerClk := True;
  FIec.ComputerData := True;
  UpdateIec;
  // The drives are not reset by the computer's reset button, only when the power goes off and on
  for I := 0 to 1 do
  begin
    if Hard then FDrive[I].Reset;
    FDrive[I].AtnChanged;
  end;
  FFrameCycle := 0;
  FNmiPrev := False;
  FIrqPrev := False;
  FNmiSeen := False;
  FTapeMotor := False;
  FTypeQueue := '';
  FAutoStage := 0;
  FIdleHits := 0;
  FIdleFrames := 0;
  FSampleAcc := 0;
  FResetFrame := FFrames;
  FCpu.Reset;
end;

procedure TC64.UpdateBank;
var
  P: Byte;
begin
  P := (FPort or not FDdr) and 7;
  FBank := P;
  // Bit 5 of the port is the cassette motor (low = on), bit 4 the PLAY sense (read)
  FTapeMotor := ((FDdr and $20) <> 0) and ((FPort and $20) = 0);
end;

procedure TC64.Clock;
var
  Nmi: Boolean;
begin
  FVic.Tick;
  FCia1.Tick;
  FCia2.Tick;
  // The 6502 looks at its interrupt lines at the end of the second to last cycle of an instruction: what changes in the
  // last one waits for the next instruction. So the CPU gets the lines as they were a cycle ago.
  FCpu.IRQ := FIrqPrev;
  FIrqPrev := FVic.Irq or FCia1.Irq;
  if FNmiSeen then
  begin
    FCpu.NMIEdge := True;
    FNmiSeen := False;
  end;
  Nmi := FCia2.Irq or FRestart;
  if Nmi and not FNmiPrev then FNmiSeen := True;
  FNmiPrev := Nmi;
  if FTapeMotor and GetTapePressed then
    if FTape.Tick then
    begin
      FCia1.SetFlagPin(False);
      FCia1.SetFlagPin(True);
    end;
  if FDriveOn[0] then FDrive[0].Run(1, C64_CLOCK);
  if FDriveOn[1] then FDrive[1].Run(1, C64_CLOCK);
  Inc(FFrameCycle);
  Inc(FTotalCycles);
end;

function TC64.VicRead(Addr: Word): Byte;
var
  VBank: Integer;
  A: Word;
begin
  VBank := (not (FCia2.PortAPins)) and 3;
  A := (VBank shl 14) or (Addr and $3FFF);
  // The character ROM shows in banks 0 and 2 at $1000-$1FFF
  if ((VBank and 1) = 0) and ((Addr and $3000) = $1000) then Exit(FChar[Addr and $FFF]);
  Result := FRam[A];
end;

{ Keyboard and joysticks, as the CIA 1 ports see them: a key joins a column line (port A) to a row line (port B) }
function TC64.Cia1PortA: Byte;
var
  PB: Byte;
  R, C: Integer;
begin
  Result := $FF;
  PB := FCia1.PortBPins;
  for R := 0 to 7 do
    if (PB and (1 shl R)) = 0 then
      for C := 0 to 7 do
        if (FKeys[C] and (1 shl R)) <> 0 then Result := Result and not (1 shl C);
  Result := Result and not (FJoy[2] and $1F);
end;

function TC64.Cia1PortB: Byte;
var
  PA: Byte;
  C: Integer;
begin
  Result := $FF;
  PA := FCia1.PortAPins;
  for C := 0 to 7 do
    if (PA and (1 shl C)) = 0 then Result := Result and not FKeys[C];
  Result := Result and not (FJoy[1] and $1F);
end;

function TC64.Cia2PortA: Byte;
begin
  Result := $3F;
  if not FIec.ClkLow then Result := Result or $40;
  if not FIec.DataLow then Result := Result or $80;
end;

procedure TC64.UpdateIec;
var
  Pins: Byte;
begin
  Pins := FCia2.PortAPins;
  // The outputs go through inverters: a set bit holds the line low
  FIec.ComputerAtn := (Pins and 8) <> 0;
  FIec.ComputerClk := (Pins and $10) <> 0;
  FIec.ComputerData := (Pins and $20) <> 0;
  FIec.Changed;
end;

function TC64.MemoryAt(Addr: Word): Integer;
begin
  Result := 0;
  case Addr shr 12 of
    $A, $B: if (FBank and 3) = 3 then Result := 1;
    $D:
      if (FBank and 3) <> 0 then
        if (FBank and 4) <> 0 then Result := 4 else Result := 3;
    $E, $F: if (FBank and 2) <> 0 then Result := 2;
  end;
end;

function TC64.IoRead(Addr: Word): Byte;
begin
  case (Addr shr 8) and $F of
    0..3: Result := FVic.Read(Addr and $3F);
    4..7: Result := FSid.Read(Addr and $1F);
    8..$B: Result := (FVic.ColorRam[Addr and $3FF] and $0F) or (FLastBus and $F0);
    $C: Result := FCia1.Read(Addr and $F);
    $D: Result := FCia2.Read(Addr and $F);
  else
    Result := FVic.LastFetch;
  end;
end;

procedure TC64.IoWrite(Addr: Word; Value: Byte);
begin
  case (Addr shr 8) and $F of
    0..3: FVic.Write(Addr and $3F, Value);
    4..7: FSid.Write(FFrameCycle, Addr and $1F, Value);
    8..$B: FVic.ColorRam[Addr and $3FF] := Value and $0F;
    $C: FCia1.Write(Addr and $F, Value);
    $D:
      begin
        FCia2.Write(Addr and $F, Value);
        if (Addr and $F) in [0, 2] then UpdateIec;
      end;
  end;
end;

function TC64.ReadMem(Addr: Word): Byte;
begin
  case Addr shr 12 of
    0:
      if Addr = 0 then Result := FDdr
      else if Addr = 1 then
      begin
        Result := (FPort and FDdr) or (not FDdr and (FPort or $17));
        // PLAY sense: low while the button is down
        if (FDdr and $10) = 0 then
        begin
          if GetTapePressed then Result := Result and not $10 else Result := Result or $10;
        end;
        if (FDdr and $20) = 0 then Result := Result or $20;
      end
      else Result := FRam[Addr];
    $A, $B:
      if (FBank and 3) = 3 then Result := FBasic[Addr and $1FFF] else Result := FRam[Addr];
    $D:
      if (FBank and 3) = 0 then Result := FRam[Addr]
      else if (FBank and 4) <> 0 then Result := IoRead(Addr)
      else Result := FChar[Addr and $FFF];
    $E, $F:
      if (FBank and 2) <> 0 then Result := FKernal[Addr and $1FFF] else Result := FRam[Addr];
  else
    Result := FRam[Addr];
  end;
end;

procedure TC64.WriteMem(Addr: Word; Value: Byte);
begin
  if Addr < 2 then
  begin
    if Addr = 0 then FDdr := Value else FPort := Value;
    UpdateBank;
    Exit;
  end;
  if (Addr shr 12 = $D) and ((FBank and 3) <> 0) and ((FBank and 4) <> 0) then IoWrite(Addr, Value)
  else FRam[Addr] := Value;
end;

function TC64.Peek(Addr: Word): Byte;
begin
  case Addr shr 12 of
    0:
      if Addr = 0 then Result := FDdr
      else if Addr = 1 then Result := (FPort and FDdr) or (not FDdr and $FF)
      else Result := FRam[Addr];
    $A, $B:
      if (FBank and 3) = 3 then Result := FBasic[Addr and $1FFF] else Result := FRam[Addr];
    $D:
      if (FBank and 3) = 0 then Result := FRam[Addr]
      else if (FBank and 4) <> 0 then
      begin
        case (Addr shr 8) and $F of
          0..3: Result := FVic.Peek(Addr and $3F);
          4..7: Result := FSid.Register(Addr and $1F);
          8..$B: Result := FVic.ColorRam[Addr and $3FF] and $0F;
          $C: Result := FCia1.Peek(Addr and $F);
          $D: Result := FCia2.Peek(Addr and $F);
        else
          Result := $FF;
        end;
      end
      else Result := FChar[Addr and $FFF];
    $E, $F:
      if (FBank and 2) <> 0 then Result := FKernal[Addr and $1FFF] else Result := FRam[Addr];
  else
    Result := FRam[Addr];
  end;
end;

function TC64.PeekRam(Addr: Word): Byte;
begin
  Result := FRam[Addr];
end;

procedure TC64.PokeRam(Addr: Word; Value: Byte);
begin
  FRam[Addr] := Value;
end;

procedure TC64.Poke(Addr: Word; Value: Byte);
begin
  if Addr < 2 then WriteMem(Addr, Value)
  else if MemoryAt(Addr) = 4 then IoWrite(Addr, Value)
  else FRam[Addr] := Value;
end;

procedure TC64.PokeIo(Addr: Word; Value: Byte);
begin
  IoWrite($D000 or (Addr and $0FFF), Value);
end;

{ The chips' registers as the processor sees them (the I/O paged in, not the colour RAM) and the 6510's port }
procedure TC64.LogIo(Addr: Word; Value: Byte; IsWrite: Boolean);
begin
  if Addr >= 2 then
  begin
    if (Addr shr 12 <> $D) or ((Addr and $0C00) = $0800) then Exit;
    if ((FBank and 3) = 0) or ((FBank and 4) = 0) then Exit;
  end;
  FIoLog[FIoLogPos].PC := FCpu.InstrPC;
  FIoLog[FIoLogPos].Addr := Addr;
  FIoLog[FIoLogPos].Value := Value;
  FIoLog[FIoLogPos].Write := IsWrite;
  FIoLog[FIoLogPos].Step := FInstrCount;
  FIoLogPos := (FIoLogPos + 1) mod C64_IO_LOG;
  if FIoLogCount < C64_IO_LOG then Inc(FIoLogCount);
end;

function TC64.IoLogCount: Integer;
begin
  Result := FIoLogCount;
end;

function TC64.IoLog(Index: Integer): TC64IoAccess;
begin
  Result := FIoLog[(FIoLogPos - 1 - Index + C64_IO_LOG * 2) mod C64_IO_LOG];
end;

function TC64.Read(Addr: Word): Byte;
begin
  Clock;
  // Held while the VIC-II has the bus
  while FVic.BaLow do Clock;
  Result := ReadMem(Addr);
  FLastBus := Result;
  LogIo(Addr, Result, False);
  if FDaadOn and (FDaadMap[Addr] <> 0) and Assigned(FOnDaadRead) then FOnDaadRead(Addr);
  if (FMemBreaks > 0) and not FSuppress and ((FBreakFlags[Addr] and (C64_BP_READ or C64_BP_DISABLED)) = C64_BP_READ) and
     ConditionHolds(Addr) then
  begin
    FBreakHit := True;
    FBreakKind := cbkRead;
    FBreakAddr := Addr;
    FBreakInstr := FCpu.InstrPC;
  end;
end;

procedure TC64.Write(Addr: Word; Value: Byte);
begin
  Clock;
  // The CPU can write for three cycles after BA falls, then it is held too
  if FVic.BaLow and (FVic.BaRun > 3) then
    while FVic.BaLow do Clock;
  FLastBus := Value;
  WriteMem(Addr, Value);
  LogIo(Addr, Value, True);
  if (FMemBreaks > 0) and not FSuppress and ((FBreakFlags[Addr] and (C64_BP_WRITE or C64_BP_DISABLED)) = C64_BP_WRITE) and
     ConditionHolds(Addr) then
  begin
    FBreakHit := True;
    FBreakKind := cbkWrite;
    FBreakAddr := Addr;
    FBreakInstr := FCpu.InstrPC;
  end;
end;

procedure TC64.SetKey(Col, Row: Integer; Down: Boolean);
begin
  if (Col < 0) or (Col > 7) or (Row < 0) or (Row > 7) then Exit;
  if Down then FKeys[Col] := FKeys[Col] or (1 shl Row) else FKeys[Col] := FKeys[Col] and not (1 shl Row);
end;

procedure TC64.ReleaseKeys;
begin
  FillChar(FKeys, SizeOf(FKeys), 0);
  FJoy[1] := 0;
  FJoy[2] := 0;
  FRestart := False;
end;

procedure TC64.SetJoystick(Port: Integer; Bits: Byte);
begin
  if (Port >= 1) and (Port <= 2) then FJoy[Port] := Bits and $1F;
end;

procedure TC64.SetKeyColumn(Col: Integer; Bits: Byte);
begin
  if (Col >= 0) and (Col <= 7) then FKeys[Col] := Bits;
end;

procedure TC64.SetRestore(Down: Boolean);
begin
  FRestart := Down;
end;

procedure TC64.CopyFrame(Dest: PLongWord);
var
  X, Y: Integer;
  Src: PLongWord;
  P: PLongWord;
begin
  // (twice as wide: every pixel twice)
  Src := @FVic.Frame[0];
  P := Dest;
  for Y := 0 to VIC_HEIGHT - 1 do
    for X := 0 to VIC_WIDTH - 1 do
    begin
      P^ := Src^;
      Inc(P);
      P^ := Src^;
      Inc(P);
      Inc(Src);
    end;
end;

function TC64.Samples: Pointer;
begin
  Result := @FSamples[0];
end;

{ The end of a frame: audio and the housekeeping of the auto load }
procedure TC64.FinishFrame;
var
  Count, I: Integer;
begin
  FSampleAcc := FSampleAcc + 44100.0 * C64_FRAME_CYCLES / C64_CLOCK;
  Count := Trunc(FSampleAcc);
  FSampleAcc := FSampleAcc - Count;
  if Count * 2 > Length(FSamples) then SetLength(FSamples, Count * 2 + 64);
  FSampleCount := Count;
  if Count > 0 then FSid.Generate(C64_FRAME_CYCLES, 44100, @FSamples[0], Count);
  FSid.EndFrame;
  Dec(FFrameCycle, C64_FRAME_CYCLES);
  if FFrameCycle < 0 then FFrameCycle := 0;
  Inc(FFrames);
  if FIdleHits > 40 then Inc(FIdleFrames) else FIdleFrames := 0;
  FIdleHits := 0;
  PushKeys;
  AutoStep;
  // A disk written to: once the drive has been quiet for a moment, into its file
  if FAutoSaveDisks and (FFrames and 15 = 0) then
    for I := 0 to 1 do
      if (FDrive[I].Disk <> nil) and FDrive[I].Disk.Dirty and not FDrive[I].Writing and
         (GetTickCount64 - FDrive[I].LastAccess > 1500) then SaveIfDirty(FDrive[I].Disk);
end;

function TC64.RunFrame: Boolean;
var
  PC: Word;
begin
  FBreakHit := False;
  FBreakKind := cbkNone;
  while not FVic.FrameReady do
  begin
    PC := FCpu.PC;
    if PC = $E5CD then Inc(FIdleHits);
    if FSkipBreakOnce then
      FSkipBreakOnce := False
    else if ((FBreakFlags[PC] and (C64_BP_EXEC or C64_BP_DISABLED)) = C64_BP_EXEC) and ConditionHolds(PC) then
    begin
      FBreakKind := cbkExec;
      FBreakAddr := PC;
      FBreakInstr := PC;
      Exit(False);
    end
    else if PC = FTempBreak then
    begin
      FTempBreak := -1;
      FBreakKind := cbkRunTo;
      FBreakAddr := PC;
      FBreakInstr := PC;
      Exit(False);
    end;
    Inc(FInstrCount);
    FCpu.Step;
    if FBreakHit then Exit(False);
  end;
  FVic.FrameReady := False;
  FinishFrame;
  Result := True;
end;

procedure TC64.StepInstruction;
begin
  FBreakHit := False;
  FBreakKind := cbkNone;
  FSkipBreakOnce := False;
  Inc(FInstrCount);
  FCpu.Step;
  if FVic.FrameReady then
  begin
    FVic.FrameReady := False;
    FinishFrame;
  end;
end;

procedure TC64.SkipBreakpointOnce;
begin
  FSkipBreakOnce := True;
end;

{ Typing, programs, auto load }

procedure TC64.TypeText(const Text: string);
var
  I: Integer;
begin
  for I := 1 to Length(Text) do FTypeQueue := FTypeQueue + Chr(AsciiToPetscii(Text[I]));
end;

function TC64.Typing: Boolean;
begin
  Result := (FTypeQueue <> '') or (FAutoStage <> 0);
end;

{ The KERNAL's keyboard buffer takes ten characters (count at $C6, buffer at $0277) }
procedure TC64.PushKeys;
var
  N, I: Integer;
begin
  if FTypeQueue = '' then Exit;
  // (the KERNAL clears its keyboard buffer while it starts: not before the prompt is there)
  if FFrames - FResetFrame < 90 then Exit;
  if FRam[$C6] <> 0 then Exit;
  N := Length(FTypeQueue);
  if N > 10 then N := 10;
  for I := 1 to N do FRam[$0276 + I] := Ord(FTypeQueue[I]);
  FRam[$C6] := N;
  Delete(FTypeQueue, 1, N);
end;

procedure TC64.ApplyPrg(const Bytes: TBytes);
var
  Addr, I, EndAddr: Integer;
begin
  if Length(Bytes) < 3 then Exit;
  Addr := Bytes[0] or (Bytes[1] shl 8);
  for I := 2 to Length(Bytes) - 1 do
    if Addr + I - 2 <= $FFFF then FRam[Addr + I - 2] := Bytes[I];
  EndAddr := Addr + Length(Bytes) - 2;
  // As the KERNAL's LOAD leaves BASIC: the end of the program in $2D/$2E (and the variables after it)
  if Addr = $0801 then
  begin
    FRam[$2D] := EndAddr and $FF; FRam[$2E] := EndAddr shr 8;
    FRam[$2F] := EndAddr and $FF; FRam[$30] := EndAddr shr 8;
    FRam[$31] := EndAddr and $FF; FRam[$32] := EndAddr shr 8;
    FRam[$AE] := EndAddr and $FF; FRam[$AF] := EndAddr shr 8;
  end;
end;

procedure TC64.LoadPrgBytes(const Bytes: TBytes; Run: Boolean);
begin
  FAutoPrg := Copy(Bytes, 0, Length(Bytes));
  if Run then
  begin
    if (Length(FAutoPrg) > 2) and ((FAutoPrg[0] or (FAutoPrg[1] shl 8)) = $0801) then FAutoCmd := 'RUN'#13
    else if Length(FAutoPrg) > 2 then FAutoCmd := 'SYS' + IntToStr(FAutoPrg[0] or (FAutoPrg[1] shl 8)) + #13
    else FAutoCmd := '';
  end
  else FAutoCmd := '';
  FAutoStage := 1;
  FAutoWait := 0;
end;

{ The first program of a .t64 container as a .prg (start address and data) }
function T64FirstProgram(const B: TBytes): TBytes;
var
  Used, Max, I, Base, Start, EndA, Offs, Len: Integer;
begin
  if (Length(B) < $60) or (Copy(StringOf(B), 1, 3) <> 'C64') then
    raise Exception.Create(_('Not a C64 tape container (.t64)'));
  Max := B[$22] or (B[$23] shl 8);
  Used := B[$24] or (B[$25] shl 8);
  if Max = 0 then Max := Used;
  for I := 0 to Max - 1 do
  begin
    Base := $40 + I * 32;
    if Base + 32 > Length(B) then Break;
    if B[Base] <> 1 then Continue;
    Start := B[Base + 2] or (B[Base + 3] shl 8);
    EndA := B[Base + 4] or (B[Base + 5] shl 8);
    Offs := B[Base + 8] or (B[Base + 9] shl 8) or (B[Base + 10] shl 16) or (B[Base + 11] shl 24);
    if (Offs <= 0) or (Offs >= Length(B)) then Continue;
    Len := EndA - Start;
    // (many .t64 files have a wrong end address: use what is left of the file)
    if (Len <= 0) or (Offs + Len > Length(B)) then Len := Length(B) - Offs;
    SetLength(Result, Len + 2);
    Result[0] := Start and $FF;
    Result[1] := Start shr 8;
    Move(B[Offs], Result[2], Len);
    Exit;
  end;
  raise Exception.Create(_('The .t64 file has no programs'));
end;

procedure TC64.LoadPrg(const FileName: string; Run: Boolean);
var
  F: TFileStream;
  B: TBytes;
begin
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(B, F.Size);
    if F.Size > 0 then F.ReadBuffer(B[0], F.Size);
  finally
    F.Free;
  end;
  // A .p00 file has a 26 byte header
  if (Length(B) > 26) and (Copy(StringOf(B), 1, 7) = 'C64File') then B := Copy(B, 26, Length(B) - 26);
  // A .t64 file is a tape image that holds programs: the first one is loaded
  if LowerCase(ExtractFileExt(FileName)) = '.t64' then B := T64FirstProgram(B);
  LoadPrgBytes(B, Run);
  FLastMedia := ExtractFileName(FileName);
end;

procedure TC64.AutoLoad(FromDisk: Boolean; Drive: Integer);
begin
  Reset(True);
  FAutoPrg := nil;
  // (the tape's program goes where it was saved from: ,1,1)
  if FromDisk then FAutoCmd := 'LOAD"*",' + IntToStr(8 + Drive) + ',1'#13 else FAutoCmd := 'LOAD"",1,1'#13;
  FAutoStage := 1;
  FAutoWait := 0;
  if not FromDisk and FTape.Present then
  begin
    FTape.Rewind;
    FTapePressed := True;
  end;
end;

{ The auto load, a frame at a time: wait for the BASIC prompt, put the program in or type the command, then (for
  a LOAD) wait for the prompt again and type RUN }
procedure TC64.AutoStep;
var
  Ready: Boolean;
begin
  if FAutoStage = 0 then Exit;
  Ready := (FIdleFrames >= 2) and (FTypeQueue = '') and (FRam[$C6] = 0) and (FFrames - FResetFrame > 60);
  case FAutoStage of
    1:
      if Ready then
      begin
        if Length(FAutoPrg) > 0 then
        begin
          ApplyPrg(FAutoPrg);
          if FAutoCmd <> '' then FTypeQueue := FTypeQueue + FAutoCmd;
          FAutoStage := 0;
        end
        else
        begin
          FTypeQueue := FAutoCmd;
          FAutoStage := 2;
          FAutoWait := 0;
        end;
      end;
    2:
      begin
        // The command is typed and entered; give the LOAD time to start, then wait until it is over
        Inc(FAutoWait);
        if (FAutoWait > 20) and Ready and not DriveBusy and not (FTapeMotor and GetTapePressed) then
        begin
          FTypeQueue := 'RUN'#13;
          FAutoStage := 0;
        end;
      end;
  end;
end;

{ A disk that is leaving: what was written to it goes to its file first, if that is asked for }
procedure TC64.ReleaseDisk(Disk: TD64Image);
begin
  if Disk = nil then Exit;
  SaveIfDirty(Disk);
  Disk.Free;
end;

procedure TC64.SaveIfDirty(Disk: TD64Image);
begin
  if FAutoSaveDisks and Disk.Dirty and (Disk.FileName <> '') and not Disk.ReadOnly then
    try
      Disk.SaveToFile(Disk.FileName);
    except
      // (the file can't be written: the image keeps the changes, the disk menu can save it elsewhere)
    end;
end;

procedure TC64.InsertDisk(Drive: Integer; Disk: TD64Image);
begin
  Drive := Drive and 1;
  ReleaseDisk(FDrive[Drive].EjectDisk);
  FDrive[Drive].InsertDisk(Disk);
  FDriveOn[Drive] := FDrive[Drive].RomLoaded;
  FDrive[Drive].Connected := FDriveOn[Drive];
end;

procedure TC64.EjectDisk(Drive: Integer);
begin
  ReleaseDisk(FDrive[Drive and 1].EjectDisk);
end;

procedure TC64.SaveDisk(Drive: Integer; const FileName: string);
var
  D: TD64Image;
begin
  D := FDrive[Drive and 1].Disk;
  if D = nil then Exit;
  D.SaveToFile(FileName);
  D.FileName := FileName;
end;

function TC64.DiskAt(Drive: Integer): TD64Image;
begin
  Result := FDrive[Drive and 1].Disk;
end;

procedure TC64.SetDriveEnabled(N: Integer; Value: Boolean);
begin
  N := N and 1;
  FDriveOn[N] := Value and FDrive[N].RomLoaded;
  FDrive[N].Connected := FDriveOn[N];
  if not FDriveOn[N] then FDrive[N].Via1.Reset;
  // (a drive that is not there does not hold the bus)
  FIec.Changed;
end;

function TC64.DriveBusy: Boolean;
begin
  Result := (FDriveOn[0] and FDrive[0].Motor) or (FDriveOn[1] and FDrive[1].Motor);
end;

function TC64.DiskActivity: QWord;
begin
  Result := FDrive[0].LastAccess;
  if FDrive[1].LastAccess > Result then Result := FDrive[1].LastAccess;
end;

procedure TC64.InsertTape(const FileName: string);
begin
  FTape.LoadFromFile(FileName);
  FTapePressed := False;
  FLastMedia := ExtractFileName(FileName);
end;

procedure TC64.EjectTape;
begin
  FTape.Eject;
  FTapePressed := False;
end;

procedure TC64.PlayTape;
begin
  if FTape.Present then FTapePressed := True;
end;

procedure TC64.StopTape;
begin
  FTapePressed := False;
end;

{ Breakpoints }

function TC64.GetBreakpoint(Addr: Word): Byte;
begin
  Result := FBreakFlags[Addr];
end;

procedure TC64.SetBreakpoint(Addr: Word; Flags: Byte);
begin
  // How many addresses have a read or write breakpoint (none: the bus doesn't look)
  if (FBreakFlags[Addr] and (C64_BP_READ or C64_BP_WRITE)) <> 0 then Dec(FMemBreaks);
  FBreakFlags[Addr] := Flags;
  if (Flags and (C64_BP_READ or C64_BP_WRITE)) <> 0 then Inc(FMemBreaks);
  if Flags = 0 then
  begin
    if Length(FCondition) > 0 then
    begin
      if FCondition[Addr] <> nil then FCondition[Addr].Free;
      FCondition[Addr] := nil;
    end;
  end;
end;

procedure TC64.ClearBreakpoints;
var
  I: Integer;
begin
  FillChar(FBreakFlags, SizeOf(FBreakFlags), 0);
  for I := 0 to High(FCondition) do FCondition[I].Free;
  SetLength(FCondition, 0);
  FMemBreaks := 0;
end;

function TC64.ExprState: TExprState;
begin
  Result.A := FCpu.A;
  Result.X := FCpu.X;
  Result.Y := FCpu.Y;
  Result.SP := FCpu.SP;
  Result.P := FCpu.P;
  Result.PC := FCpu.PC;
  Result.Hits := 0;
  Result.Peek := @Peek;
end;

{ A breakpoint's condition ('' = always) }
function TC64.SetCondition(Addr: Word; const Text: string; out Error: string): Boolean;
var
  C: TC64Condition;
begin
  Error := '';
  if Length(FCondition) = 0 then SetLength(FCondition, 65536);
  if Trim(Text) = '' then
  begin
    FCondition[Addr].Free;
    FCondition[Addr] := nil;
    Exit(True);
  end;
  C := CompileC64Condition(Text, Error);
  Result := C <> nil;
  if Result then
  begin
    FCondition[Addr].Free;
    FCondition[Addr] := C;
  end;
end;

function TC64.ConditionOf(Addr: Word): string;
begin
  Result := '';
  if (Length(FCondition) > 0) and (FCondition[Addr] <> nil) then Result := FCondition[Addr].Text;
end;

function TC64.BreakHits(Addr: Word): Integer;
begin
  Result := -1;
  if (Length(FCondition) > 0) and (FCondition[Addr] <> nil) and FCondition[Addr].UsesHits then
    Result := FCondition[Addr].Hits;
end;

function TC64.ConditionHolds(Addr: Word): Boolean;
var
  S: TExprState;
begin
  if (Length(FCondition) = 0) or (FCondition[Addr] = nil) then Exit(True);
  S := ExprState;
  Result := FCondition[Addr].Holds(S);
end;

{ The value of an expression in the debugger's boxes (registers and memory as they are now) }
function TC64.EvalCondition(const Text: string; out Value: Integer; out Error: string): Boolean;
begin
  Result := EvalC64Expression(Text, ExprState, Value, Error);
end;

procedure TC64.SetDaadMap(Map: PByte);
begin
  FDaadOn := Map <> nil;
  if FDaadOn then Move(Map^, FDaadMap, SizeOf(FDaadMap));
end;

procedure TC64Tape.StateIO(S: TStream; Save: Boolean);
var
  N, P: Integer;
  R: LongWord;
begin
  N := FPulseCount;
  P := FPos;
  R := FRemaining;
  StateBlock(S, Save, N, SizeOf(N));
  StateBlock(S, Save, P, SizeOf(P));
  StateBlock(S, Save, R, SizeOf(R));
  if Save or (N <> FPulseCount) then Exit;
  FPos := P;
  FRemaining := R;
end;

procedure TC64.StateIO(S: TStream; Save: Boolean);
var
  I: Integer;
begin
  StateBlock(S, Save, FRam, SizeOf(FRam));
  // FPort to FBank, FRestart to FIoLogCount (the accesses logged among them)
  StateBlock(S, Save, FPort, PtrUInt(@FBank) + SizeOf(FBank) - PtrUInt(@FPort));
  StateBlock(S, Save, FRestart, PtrUInt(@FIoLogCount) + SizeOf(FIoLogCount) - PtrUInt(@FRestart));
  StateBlock(S, Save, FTapeMotor, SizeOf(FTapeMotor));
  StateBlock(S, Save, FLastBus, SizeOf(FLastBus));
  StateBlock(S, Save, FIec.ComputerAtn, SizeOf(Boolean));
  StateBlock(S, Save, FIec.ComputerClk, SizeOf(Boolean));
  StateBlock(S, Save, FIec.ComputerData, SizeOf(Boolean));
  FCpu.StateIO(S, Save);
  FVic.StateIO(S, Save);
  FCia1.StateIO(S, Save);
  FCia2.StateIO(S, Save);
  FSid.StateIO(S, Save);
  FTape.StateIO(S, Save);
  // Both drives (they are always there, switched on or not)
  for I := 0 to 1 do FDrive[I].StateIO(S, Save);
  if not Save then UpdateBank;
end;

end.

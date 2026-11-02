{ Amstrad: the hardware of the Amstrad CPC 464, 664 and 6128 that is not a
  Spectrum's: the Gate Array (memory banking, ROM selection, palette, screen
  mode and the interrupt counter), the 6845 CRTC (its raster, timing and
  video addresses), the 8255 PPI (keyboard, PSG bus, tape and the vsync
  line), the memory map and the ports. The CPU, the PSG, the tape and the
  disc controller are shared with the Spectrum and belong to TSpectrum,
  which owns a TAmstrad when a CPC model is chosen.

  Time is in CPU T-states within the frame (4 MHz): the chips run in
  microseconds (4 T-states), caught up lazily by Sync to the CPU's time,
  before each port access and after each instruction. The picture is drawn
  as the beam goes, one CRTC character (16 pixels of the 640-pixel mode) at
  a time, so what a program changes during the frame shows where it does. }
unit Amstrad;

{$mode objfpc}{$H+}
{$R-}{$Q-}

interface

uses
  SysUtils, Classes, Math, Models;

const
  { The picture: 44 characters of 16 pixels wide (a 40-character screen with
    two characters of border each side) by 288 lines. The same size as the
    Spectrum's, so the frame buffers are interchangeable. }
  CPC_WIDTH = 704;
  CPC_HEIGHT = 288;
  CPC_FRAME_T = 79872;       // 312 lines of 64 us: the CRTC's power-on timing
  { Where the picture starts, in characters after the end of the HSYNC and in
    lines after the start of the VSYNC (with the CRTC's power-on values the
    screen is 4 characters and 72 lines after those) }
  CPC_LEFT_CHARS = 2;
  CPC_TOP_LINES = 24;
  CPC_CHARS = 44;

type
  TCPCBank = array[0..$3FFF] of Byte;
  PCPCBank = ^TCPCBank;

  { A PSG register write at T-state T }
  TCPCPsgEvent = procedure(T: Integer; Reg, Value: Byte) of object;

  { The Amstrad's tape and disc are the Spectrum's; TAmstrad asks for them
    through these }
  TCPCTapeLevel = function(T: Integer): Boolean of object;
  TCPCMotor = procedure(T: Integer; On_: Boolean) of object;
  TCPCTapeOut = procedure(T: Integer; Level: Boolean) of object;
  TCPCFdcAccess = function(Write: Boolean; Reg: Integer; Value: Byte; T: Integer): Byte of object;

  { The registers of the Gate Array, CRTC, PPI and PSG, as a CPC .SNA snapshot
    holds them }
  TCPCRegisters = record
    PenSel: Byte;
    Pens: array[0..16] of Byte;      // hardware colour of each pen, and the border
    RomReg, RamConfig, UpperRom: Byte;
    CrtcSel: Byte;
    Crtc: array[0..17] of Byte;
    Ppi: array[0..3] of Byte;        // ports A, B, C and the control register
    PsgSel: Byte;
    Psg: array[0..15] of Byte;
  end;

  TAmstrad = class
  private
    FModel: TSpectrumModel;
    FRam: array[0..7] of TCPCBank;   // 464/664: 0-3; 6128: 0-7
    FRomLow: TCPCBank;               // the operating system (0000-3FFF)
    FRomBasic: TCPCBank;             // BASIC (upper ROM 0, and the unused numbers)
    FRomDisc: TCPCBank;              // AMSDOS (upper ROM 7)
    FHasDisc: Boolean;
    FRamBanks: Integer;
    FReadSlot: array[0..3] of PCPCBank;
    FWriteSlot: array[0..3] of PCPCBank;
    FSlotRom: array[0..3] of Integer;   // -1 RAM; 0 system, 1 BASIC, 2 AMSDOS
    FSlotBank: array[0..3] of Integer;  // RAM bank in the slot (when RAM)
    { Gate Array }
    FPenSel: Byte;                   // 0-15 pen, 16 border
    FPen: array[0..16] of Byte;      // hardware colour (0-31) of each pen
    FPenRGB: array[0..16] of LongWord;
    FRomReg: Byte;                   // last function 2 write
    FRamConfig: Byte;                // last function 3 write
    FUpperRom: Byte;                 // port DFxx
    FIntCounter: Byte;               // 6-bit HSYNC counter
    FIntPending: Boolean;
    FVsyncDelay: Integer;            // HSYNC ends to wait after a VSYNC began
    FMode: Byte;
    { CRTC }
    FCrtcSel: Byte;
    FCrtc: array[0..17] of Byte;     // as the chip keeps them (written values through the type's mask)
    FCrtcRaw: array[0..17] of Byte;  // as written, to mask them again if the type changes
    FCrtcType: Integer;              // 0 HD6845S, 1 UM6845R, 2 MC6845, 3 AMS40489, 4 AMS40226
    FHdisp, FVdisp: Boolean;         // the display enable flags (set at the start, cleared by compare with R1, R6)
    FVsyncTriggered: Boolean;        // the VSYNC has started in this character row
    FDispPipe: Byte;                 // display enable of this and the last characters (R8 skew)
    FStatus1: Byte;                  // the UM6845R's status register bit 0
    FHcc, FVcc, FVlc, FVadj: Integer;
    FInAdjust: Boolean;
    FRowStart: Integer;              // MA of the row's first character
    FHsyncLeft, FVsyncLeft: Integer;
    FHsyncSeen: Boolean;             // (kept in snapshots only)
    FXChars: Integer;                // (kept in snapshots only: FMonX rounded)
    { The monitor's horizontal oscillator: it runs by itself and the HSYNCs pull it a little at a time, in
      absolute time, so the picture's lines are its sweeps, not the CRTC's lines }
    FMonX: Double;                   // characters since the beam went back to the left
    FMonPeriod: Double;              // the length of its sweep, in characters (64 at 15625 Hz)
    FMonInit: Boolean;               // locked to the HSYNC (not after a reset)
    FYLines: Integer;                // the monitor's lines since the VSYNC began
    FVsyncRose: Boolean;
    { Video output }
    FLine: array[0..CPC_WIDTH - 1] of LongWord;
    FBuild: array of LongWord;       // the picture being drawn
    FShown: array of LongWord;       // the last picture completed
    FShownDone: Boolean;             // this frame's picture has gone to FShown
    FLineX: Integer;
    { PPI }
    FPpiA, FPpiB, FPpiC, FPpiCtl: Byte;
    FPsgSel: Byte;
    FPsgRegs: array[0..15] of Byte;
    FKeyLine: Byte;
    FMotor: Boolean;
    FTapeOutLevel: Boolean;
    FPsgFn: Byte;
    { Time }
    FChipT: Integer;                 // the chips have run up to here (T-states in the frame)
    FDiscMotor: Boolean;
    FOnPsg: TCPCPsgEvent;
    FOnTapeIn: TCPCTapeLevel;
    FOnMotor: TCPCMotor;
    FOnTapeOut: TCPCTapeOut;
    FOnFdc: TCPCFdcAccess;
    procedure BuildPalette;
    procedure UpdateMemory;
    procedure CharStep;
    procedure MonitorLine;
    procedure StartFrame;
    procedure HsyncEnded;
    procedure VsyncBegan;
    procedure DrawChar(Blank: Boolean; Dispen: Boolean);
    procedure LineChecks;
    procedure CrtcWrite(Reg, Value: Byte);
    function CrtcRead(Reg: Integer): Byte;
    function CrtcStatus: Byte;
    procedure PpiWriteC(Value: Byte);
    procedure PsgFunction(Fn: Byte; T: Integer);
    function PpiReadA: Byte;
    function GetKey(Row: Integer): Byte;
    function CrtcLinesPerRow: Integer;
  public
    { Keyboard matrix: 10 lines of 8 keys, bit = 0 when pressed. Line 9 holds
      the joystick (and DEL) }
    KeyMatrix: array[0..9] of Byte;
    { Keys typed for the user (automatic typing), ANDed with KeyMatrix }
    AutoMatrix: array[0..9] of Byte;
    constructor Create(AModel: TSpectrumModel);
    procedure LoadRoms(const FirmwareFile, DiscFile: string);
    procedure Reset(Hard: Boolean);
    { Memory as the CPU sees it }
    function Read(Addr: Word): Byte; inline;
    { The RAM at Addr, also where a ROM covers it }
    function ReadRam(Addr: Word): Byte;
    procedure Write(Addr: Word; Value: Byte); inline;
    { Memory of a 16K slot as the CPU sees it: RAM bank number (0-7), or
      -1 - ROM (0 system, 1 BASIC, 2 AMSDOS) }
    function SlotBank(Slot: Integer): Integer;
    { Debugger: what a 16K slot can hold on this hardware, as SlotBank says it
      (RAM bank, or -1 - ROM number: ROM0 the lower ROM at 0000, ROM1 BASIC and
      ROM2 AMSDOS at C000) }
    function SlotCanHold(Slot, What: Integer): Boolean;
    { Debugger: put it there the way the CPC does: the ROM enable bits, the upper
      ROM number and the RAM configuration of the Gate Array. False if it can't. }
    function SetSlot(Slot, What: Integer): Boolean;
    function RamBank(Index: Integer): PCPCBank;
    { The memory the CPU reads in a 16K slot }
    function ReadPtr(Slot: Integer): PByte;
    { Whether the address is ROM (writes go to the RAM under it) }
    function IsRom(Addr: Word): Boolean;
    function InPort(Port: Word; T: Integer): Byte;
    procedure OutPort(Port: Word; Value: Byte; T: Integer);
    { Run the chips up to T-state T of the frame }
    procedure Sync(T: Integer);
    { The Z80's /INT line, and the CPU acknowledging it }
    function IntLine: Boolean; inline;
    procedure IntAck;
    { The frame is over: T-states of the next one start at 0 }
    procedure EndFrame(FrameT: Integer);
    { The picture: the last one completed (CPC_WIDTH x CPC_HEIGHT, $FFRRGGBB);
      Preview adds the one being drawn, for the debugger }
    procedure CopyFrame(Dest: PLongWord);
    procedure PreviewFrame;
    { The chips' registers: read for a .SNA snapshot, and set from one (the
      memory map follows, the CRTC starts a frame, nothing else is touched) }
    procedure GetRegisters(out R: TCPCRegisters);
    procedure SetRegisters(const R: TCPCRegisters);
    { The debugger's chips window: the PSG's register selected (Reg < 0) or register Reg, written as the PPI would
      (the sound follows) }
    procedure SetPsg(Reg: Integer; Value: Byte);
    { Whole machine state, for snapshots (everything but the ROMs) }
    procedure SaveState(S: TStream);
    procedure LoadState(S: TStream);
    property Model: TSpectrumModel read FModel;
    property HasDisc: Boolean read FHasDisc;
    property RamBanks: Integer read FRamBanks;
    property Vsync: Boolean read FVsyncRose;
    property Mode: Byte read FMode;
    property RomReg: Byte read FRomReg;
    property RamConfig: Byte read FRamConfig;
    property UpperRom: Byte read FUpperRom;
    property Motor: Boolean read FMotor;
    property DiscMotor: Boolean read FDiscMotor;
    property ChipT: Integer read FChipT;
    property OnPsg: TCPCPsgEvent read FOnPsg write FOnPsg;
    property OnTapeIn: TCPCTapeLevel read FOnTapeIn write FOnTapeIn;
    property OnMotor: TCPCMotor read FOnMotor write FOnMotor;
    property OnTapeOut: TCPCTapeOut read FOnTapeOut write FOnTapeOut;
    property OnFdc: TCPCFdcAccess read FOnFdc write FOnFdc;
    { Debugger: the CRTC registers, the pens, the PSG's registers }
    function CrtcReg(Index: Integer): Byte;
    function PenColour(Index: Integer): Byte;
    function PsgReg(Index: Integer): Byte;
    function PpiPort(Index: Integer): Byte;
    function CrtcPosition(out Hcc, Vcc, Vlc: Integer): Boolean;
    function IntCounter: Integer;
    { The CRTC chip: 0 HD6845S/UM6845, 1 UM6845R, 2 MC6845, 3 AMS40489 (CPC+),
      4 AMS40226 (pre-ASIC). The registers written keep their value. }
    procedure SetCrtcType(AType: Integer);
    property CrtcType: Integer read FCrtcType write SetCrtcType;
    { The type the model came with (464: 0, 664 and 6128: 1) }
    class function DefaultCrtcType(AModel: TSpectrumModel): Integer;
  end;

const
  { Hardware colour number (the 5 bits written to the Gate Array) to RGB }
  CPC_COLOURS: array[0..31] of LongWord = (
    $FF808080, $FF808080, $FF00FF80, $FFFFFF80, $FF000080, $FFFF0080, $FF008080, $FFFF8080,
    $FFFF0080, $FFFFFF80, $FFFFFF00, $FFFFFFFF, $FFFF0000, $FFFF00FF, $FFFF8000, $FFFF80FF,
    $FF000080, $FF00FF80, $FF00FF00, $FF00FFFF, $FF000000, $FF0000FF, $FF008000, $FF0080FF,
    $FF800080, $FF80FF80, $FF80FF00, $FF80FFFF, $FF800000, $FF8000FF, $FF808000, $FF8080FF);

  { CPC keys as line * 8 + bit, matching KeyMatrix }
  CPCK_UP = 0; CPCK_RIGHT = 1; CPCK_DOWN = 2; CPCK_F9 = 3; CPCK_F6 = 4; CPCK_F3 = 5;
  CPCK_ENTER = 6; CPCK_FDOT = 7;
  CPCK_LEFT = 8; CPCK_COPY = 9; CPCK_F7 = 10; CPCK_F8 = 11; CPCK_F5 = 12; CPCK_F1 = 13;
  CPCK_F2 = 14; CPCK_F0 = 15;
  CPCK_CLR = 16; CPCK_LBRACKET = 17; CPCK_RETURN = 18; CPCK_RBRACKET = 19; CPCK_F4 = 20;
  CPCK_SHIFT = 21; CPCK_BACKSLASH = 22; CPCK_CONTROL = 23;
  CPCK_CARET = 24; CPCK_MINUS = 25; CPCK_AT = 26; CPCK_P = 27; CPCK_SEMICOLON = 28;
  CPCK_COLON = 29; CPCK_SLASH = 30; CPCK_DOT = 31;
  CPCK_0 = 32; CPCK_9 = 33; CPCK_O = 34; CPCK_I = 35; CPCK_L = 36; CPCK_K = 37;
  CPCK_M = 38; CPCK_COMMA = 39;
  CPCK_8 = 40; CPCK_7 = 41; CPCK_U = 42; CPCK_Y = 43; CPCK_H = 44; CPCK_J = 45;
  CPCK_N = 46; CPCK_SPACE = 47;
  CPCK_6 = 48; CPCK_5 = 49; CPCK_R = 50; CPCK_T = 51; CPCK_G = 52; CPCK_F = 53;
  CPCK_B = 54; CPCK_V = 55;
  CPCK_4 = 56; CPCK_3 = 57; CPCK_E = 58; CPCK_W = 59; CPCK_S = 60; CPCK_D = 61;
  CPCK_C = 62; CPCK_X = 63;
  CPCK_1 = 64; CPCK_2 = 65; CPCK_ESC = 66; CPCK_Q = 67; CPCK_TAB = 68; CPCK_A = 69;
  CPCK_CAPSLOCK = 70; CPCK_Z = 71;
  CPCK_JUP = 72; CPCK_JDOWN = 73; CPCK_JLEFT = 74; CPCK_JRIGHT = 75; CPCK_JFIRE1 = 76;
  CPCK_JFIRE2 = 77; CPCK_JFIRE3 = 78; CPCK_DEL = 79;

implementation

uses
  Lang;


{ TAmstrad }

constructor TAmstrad.Create(AModel: TSpectrumModel);
begin
  inherited Create;
  FModel := AModel;
  FHasDisc := ModelInfo[AModel].HasFDC;
  if AModel = smCPC6128 then FRamBanks := 8 else FRamBanks := 4;
  SetLength(FBuild, CPC_WIDTH * CPC_HEIGHT);
  SetLength(FShown, CPC_WIDTH * CPC_HEIGHT);
  FillChar(FRomLow, SizeOf(FRomLow), $FF);
  FillChar(FRomBasic, SizeOf(FRomBasic), $FF);
  FillChar(FRomDisc, SizeOf(FRomDisc), $FF);
  FCrtcType := DefaultCrtcType(AModel);
  Reset(True);
end;

{ The firmware file is 32K: the system ROM, then BASIC. A 16K file is taken as
  the system ROM alone (BASIC stays empty). }
procedure TAmstrad.LoadRoms(const FirmwareFile, DiscFile: string);
var
  S: TFileStream;
  Size: Int64;
begin
  if not FileExists(FirmwareFile) then
    raise Exception.CreateFmt(_('ROM file not found: %s'), [FirmwareFile]);
  S := TFileStream.Create(FirmwareFile, fmOpenRead or fmShareDenyWrite);
  try
    Size := S.Size;
    if (Size <> $8000) and (Size <> $4000) then
      raise Exception.CreateFmt(_('%s: the CPC firmware is a 32K file (system ROM and BASIC)'), [FirmwareFile]);
    S.ReadBuffer(FRomLow, SizeOf(FRomLow));
    if Size = $8000 then S.ReadBuffer(FRomBasic, SizeOf(FRomBasic));
  finally
    S.Free;
  end;
  if FHasDisc then
  begin
    if not FileExists(DiscFile) then
      raise Exception.CreateFmt(_('ROM file not found: %s'), [DiscFile]);
    S := TFileStream.Create(DiscFile, fmOpenRead or fmShareDenyWrite);
    try
      FillChar(FRomDisc, SizeOf(FRomDisc), $FF);
      S.Read(FRomDisc, SizeOf(FRomDisc));
    finally
      S.Free;
    end;
  end;
  UpdateMemory;
end;

procedure TAmstrad.BuildPalette;
var
  I: Integer;
begin
  for I := 0 to 16 do FPenRGB[I] := CPC_COLOURS[FPen[I] and 31];
end;

procedure TAmstrad.Reset(Hard: Boolean);
var
  I: Integer;
begin
  if Hard then
    for I := 0 to 7 do FillChar(FRam[I], SizeOf(TCPCBank), 0);
  for I := 0 to 16 do FPen[I] := $14;     // black, until the firmware sets them
  BuildPalette;
  FPenSel := 0;
  FRomReg := 0;                           // both ROMs on, mode 0
  FRamConfig := 0;
  FUpperRom := 0;
  FMode := 0;
  FIntCounter := 0;
  FIntPending := False;
  FVsyncDelay := 0;
  // The CRTC at its power-on values: the firmware writes its own at once
  FillChar(FCrtcRaw, SizeOf(FCrtcRaw), 0);
  FCrtcRaw[0] := 63; FCrtcRaw[1] := 40; FCrtcRaw[2] := 46; FCrtcRaw[3] := $8E;
  FCrtcRaw[4] := 38; FCrtcRaw[5] := 0; FCrtcRaw[6] := 25; FCrtcRaw[7] := 30;
  FCrtcRaw[9] := 7; FCrtcRaw[12] := $30;
  SetCrtcType(FCrtcType);
  FHdisp := False; FVdisp := True; FVsyncTriggered := False; FDispPipe := 0;
  FStatus1 := 0;
  FCrtcSel := 0;
  FHcc := 0; FVcc := 0; FVlc := 0; FVadj := 0;
  FInAdjust := False;
  FRowStart := (FCrtc[12] and $3F) shl 8 or FCrtc[13];
  FHsyncLeft := 0; FVsyncLeft := 0;
  FHsyncSeen := False;
  FMonX := 4;
  FMonPeriod := 64;
  FMonInit := False;
  FYLines := 0;
  FVsyncRose := False;
  FLineX := 0;
  FillChar(FLine, SizeOf(FLine), 0);
  FPpiA := 0; FPpiB := 0; FPpiC := 0; FPpiCtl := $82;
  FPsgSel := 0;
  FillChar(FPsgRegs, SizeOf(FPsgRegs), 0);
  FKeyLine := 0;
  FMotor := False;
  FTapeOutLevel := False;
  FPsgFn := 0;
  FChipT := 0;
  FDiscMotor := False;
  if Hard then
  begin
    FillChar(KeyMatrix, SizeOf(KeyMatrix), $FF);
    FillChar(AutoMatrix, SizeOf(AutoMatrix), $FF);
    FillChar(FBuild[0], Length(FBuild) * SizeOf(LongWord), 0);
    FillChar(FShown[0], Length(FShown) * SizeOf(LongWord), 0);
  end;
  UpdateMemory;
end;

const
  { The RAM banks the Gate Array's configurations (port 7Fxx, 11000cccb) put in each slot }
  RAM_CONFIG: array[0..7, 0..3] of Integer = (
    (0, 1, 2, 3), (0, 1, 2, 7), (4, 5, 6, 7), (0, 3, 2, 7),
    (0, 4, 2, 3), (0, 5, 2, 3), (0, 6, 2, 3), (0, 7, 2, 3));

function TAmstrad.SlotCanHold(Slot, What: Integer): Boolean;
var
  Cfg: Integer;
begin
  Result := False;
  Slot := Slot and 3;
  if What < 0 then
    case -1 - What of
      0: Result := Slot = 0;
      1: Result := Slot = 3;
      2: Result := (Slot = 3) and FHasDisc;
    end
  else
    for Cfg := 0 to 7 do
      if ((Cfg = 0) or (FRamBanks >= 8)) and (RAM_CONFIG[Cfg, Slot] = What) then Result := True;
end;

function TAmstrad.SetSlot(Slot, What: Integer): Boolean;
var
  Cfg, Best, BestScore, Score, S: Integer;
begin
  Slot := Slot and 3;
  Result := SlotCanHold(Slot, What);
  if not Result then Exit;
  if What < 0 then
  begin
    if Slot = 0 then FRomReg := FRomReg and not 4        // lower ROM on
    else
    begin
      FRomReg := FRomReg and not 8;                       // upper ROM on
      if What = -3 then FUpperRom := 7
      else if FUpperRom = 7 then FUpperRom := 0;
    end;
  end
  else
  begin
    // The configuration that holds it and keeps the most of the other slots
    Best := -1;
    BestScore := -1;
    for Cfg := 0 to 7 do
      if ((Cfg = 0) or (FRamBanks >= 8)) and (RAM_CONFIG[Cfg, Slot] = What) then
      begin
        Score := 0;
        for S := 0 to 3 do
          if RAM_CONFIG[Cfg, S] = FSlotBank[S] then Inc(Score);
        if Score > BestScore then begin Best := Cfg; BestScore := Score; end;
      end;
    FRamConfig := (FRamConfig and not 7) or Best;
    if Slot = 0 then FRomReg := FRomReg or 4              // lower ROM off
    else if Slot = 3 then FRomReg := FRomReg or 8;        // upper ROM off
  end;
  UpdateMemory;
end;

{ The memory map from the Gate Array's registers }
procedure TAmstrad.UpdateMemory;
const
  Config: array[0..7, 0..3] of Integer = (
    (0, 1, 2, 3), (0, 1, 2, 7), (4, 5, 6, 7), (0, 3, 2, 7),
    (0, 4, 2, 3), (0, 5, 2, 3), (0, 6, 2, 3), (0, 7, 2, 3));
var
  Slot, Bank, Cfg: Integer;
begin
  Cfg := FRamConfig and 7;
  if FRamBanks < 8 then Cfg := 0;           // no banking hardware
  for Slot := 0 to 3 do
  begin
    Bank := Config[Cfg, Slot];
    FSlotBank[Slot] := Bank;
    FSlotRom[Slot] := -1;
    FWriteSlot[Slot] := @FRam[Bank];
    FReadSlot[Slot] := @FRam[Bank];
  end;
  if (FRomReg and 4) = 0 then          // lower ROM on
  begin
    FReadSlot[0] := @FRomLow;
    FSlotRom[0] := 0;
  end;
  if (FRomReg and 8) = 0 then          // upper ROM on
  begin
    if FHasDisc and (FUpperRom = 7) then
    begin
      FReadSlot[3] := @FRomDisc;
      FSlotRom[3] := 2;
    end
    else
    begin
      FReadSlot[3] := @FRomBasic;
      FSlotRom[3] := 1;
    end;
  end;
end;

function TAmstrad.Read(Addr: Word): Byte;
begin
  Result := FReadSlot[Addr shr 14]^[Addr and $3FFF];
end;

procedure TAmstrad.Write(Addr: Word; Value: Byte);
begin
  FWriteSlot[Addr shr 14]^[Addr and $3FFF] := Value;
end;

function TAmstrad.ReadRam(Addr: Word): Byte;
begin
  Result := FWriteSlot[Addr shr 14]^[Addr and $3FFF];
end;

function TAmstrad.SlotBank(Slot: Integer): Integer;
begin
  if FSlotRom[Slot and 3] >= 0 then Result := -1 - FSlotRom[Slot and 3]
  else Result := FSlotBank[Slot and 3];
end;

function TAmstrad.RamBank(Index: Integer): PCPCBank;
begin
  Result := @FRam[Index and 7];
end;

function TAmstrad.ReadPtr(Slot: Integer): PByte;
begin
  Result := PByte(FReadSlot[Slot and 3]);
end;

function TAmstrad.IsRom(Addr: Word): Boolean;
begin
  Result := FSlotRom[Addr shr 14] >= 0;
end;

{ The Z80's /INT: the Gate Array holds it until the CPU acknowledges it }
function TAmstrad.IntLine: Boolean;
begin
  Result := FIntPending;
end;

procedure TAmstrad.IntAck;
begin
  FIntPending := False;
  FIntCounter := FIntCounter and $1F;     // bit 5 cleared: no interrupt within 32 lines
end;

{ Ports }

function TAmstrad.GetKey(Row: Integer): Byte;
begin
  if Row > 9 then Result := $FF else Result := KeyMatrix[Row] and AutoMatrix[Row];
end;

{ What port A reads: the PSG's register when it is on the bus, with the
  keyboard on register 14; the byte written otherwise }
function TAmstrad.PpiReadA: Byte;
begin
  if (FPpiCtl and $10) = 0 then Exit(FPpiA);        // output mode
  if FPsgFn = 1 then                                // PSG read
  begin
    if FPsgSel = 14 then Result := GetKey(FKeyLine)
    else Result := FPsgRegs[FPsgSel and 15];
  end
  else
    Result := $FF;
end;

function TAmstrad.InPort(Port: Word; T: Integer): Byte;
var
  Fn: Integer;
begin
  Sync(T);
  Result := $FF;
  // PPI: A11 low
  if (Port and $0800) = 0 then
  begin
    case (Port shr 8) and 3 of
      0: Result := PpiReadA;
      1:
        begin
          // vsync, the jumpers (Amstrad, 50 Hz), no expansion, no printer, tape
          Result := $7E;
          if FVsyncRose then Result := Result or 1;
          if Assigned(FOnTapeIn) and FOnTapeIn(T) then Result := Result or $80;
        end;
      2: Result := FPpiC;
      3: Result := FPpiCtl;
    end;
    Exit;
  end;
  // CRTC: A14 low
  if (Port and $4000) = 0 then
  begin
    Fn := (Port shr 8) and 3;
    case Fn of
      2: Result := CrtcStatus;
      3: Result := CrtcRead(FCrtcSel);
    end;
    Exit;
  end;
  // The disc controller (664, 6128): A10 and A7 low
  if FHasDisc and ((Port and $0480) = 0) and ((Port and $0100) <> 0) and Assigned(FOnFdc) then
    Result := FOnFdc(False, Port and 1, 0, T);
end;

procedure TAmstrad.PsgFunction(Fn: Byte; T: Integer);
begin
  // The address is latched when the latch cycle ends, from what is on the bus then: a player may put
  // the register number on port A after it has started the cycle (OUT C,latch; OUT A,reg; OUT C,inactive)
  if (FPsgFn = 3) and (Fn <> 3) then FPsgSel := FPpiA and 15;
  case Fn of
    3: FPsgSel := FPpiA and 15;                       // latch the register number (again at its end)
    2:                                                // write
      begin
        FPsgRegs[FPsgSel and 15] := FPpiA;
        if Assigned(FOnPsg) and (FPsgSel < 14) then FOnPsg(T, FPsgSel, FPpiA);
      end;
  end;
  FPsgFn := Fn;
end;

procedure TAmstrad.PpiWriteC(Value: Byte);
var
  Fn: Byte;
  MotorOn, Level: Boolean;
begin
  FPpiC := Value;
  FKeyLine := Value and 15;
  MotorOn := (Value and $10) <> 0;
  if MotorOn <> FMotor then
  begin
    FMotor := MotorOn;
    if Assigned(FOnMotor) then FOnMotor(FChipT, MotorOn);
  end;
  Level := (Value and $20) <> 0;
  if Level <> FTapeOutLevel then
  begin
    FTapeOutLevel := Level;
    if Assigned(FOnTapeOut) then FOnTapeOut(FChipT, Level);
  end;
  Fn := Value shr 6;      // BDIR, BC1
  // Function 3 is latch address, 2 write; the others leave the bus
  if (Fn <> FPsgFn) then PsgFunction(Fn, FChipT);
end;

procedure TAmstrad.OutPort(Port: Word; Value: Byte; T: Integer);
var
  Bit: Integer;
begin
  Sync(T);
  // Gate Array: A15 low, A14 high
  if (Port and $C000) = $4000 then
  begin
    case Value shr 6 of
      0:
        FPenSel := Value and $1F;
      1:
        begin
          if (FPenSel and $10) <> 0 then Bit := 16 else Bit := FPenSel and 15;
          FPen[Bit] := Value and $1F;
          FPenRGB[Bit] := CPC_COLOURS[Value and $1F];
        end;
      2:
        begin
          FRomReg := Value;
          FMode := Value and 3;
          if (Value and $10) <> 0 then
          begin
            FIntCounter := 0;
            FIntPending := False;
          end;
          UpdateMemory;
        end;
      3:
        begin
          FRamConfig := Value;
          UpdateMemory;
        end;
    end;
  end;
  // CRTC: A14 low
  if (Port and $4000) = 0 then
  begin
    case (Port shr 8) and 3 of
      0: FCrtcSel := Value and $1F;
      1: CrtcWrite(FCrtcSel, Value);
    end;
  end;
  // Upper ROM select: A13 low
  if (Port and $2000) = 0 then
  begin
    FUpperRom := Value;
    UpdateMemory;
  end;
  // PPI: A11 low
  if (Port and $0800) = 0 then
  begin
    case (Port shr 8) and 3 of
      0:
        begin
          FPpiA := Value;
          // A write with the PSG on the bus in write mode goes on at once
        end;
      1: FPpiB := Value;
      2: PpiWriteC(Value);
      3:
        begin
          if (Value and $80) <> 0 then
          begin
            FPpiCtl := Value;
            // A mode set clears the ports (and the PSG is let go of); the
            // CPC+'s ASIC, which has the PPI built in, doesn't clear port C
            // (that is how programs tell the AMS40489 from the AMS40226).
            // The PSG's latch cycle ends with port C going to 0, and takes the register number from what
            // was on the bus then, before port A is cleared (a keyboard scan does: C=C0, A=0E, mode set 92)
            if FCrtcType <> 3 then PpiWriteC(0);
            FPpiA := 0; FPpiB := 0;
          end
          else
          begin
            Bit := (Value shr 1) and 7;
            if (Value and 1) <> 0 then PpiWriteC(FPpiC or (1 shl Bit))
            else PpiWriteC(FPpiC and not (1 shl Bit));
          end;
        end;
    end;
  end;
  // The disc controller: A10 and A7 low
  if FHasDisc and ((Port and $0480) = 0) and Assigned(FOnFdc) then
  begin
    if (Port and $0100) = 0 then
    begin
      // FA7E (bit 0: the motor)
      FDiscMotor := (Value and 1) <> 0;
      FOnFdc(True, 2, Value, T);
    end
    else
      FOnFdc(True, Port and 1, Value, T);
  end;
end;

{ Video: the CRTC and the Gate Array, a character (1 us) at a time }

function TAmstrad.CrtcLinesPerRow: Integer;
begin
  Result := FCrtc[9] and $1F;
end;

procedure TAmstrad.Sync(T: Integer);
begin
  while FChipT + 4 <= T do
  begin
    CharStep;
    Inc(FChipT, 4);
  end;
end;

procedure TAmstrad.EndFrame(FrameT: Integer);
begin
  Sync(FrameT);
  Dec(FChipT, FrameT);
end;

procedure TAmstrad.StartFrame;
begin
  FVcc := 0;
  FVlc := 0;
  FVadj := 0;
  FInAdjust := False;
  FRowStart := (FCrtc[12] and $3F) shl 8 or FCrtc[13];
  FVdisp := True;
  FVsyncTriggered := False;
end;

procedure TAmstrad.HsyncEnded;
var
  Err: Double;
begin
  // The monitor doesn't follow every HSYNC: its oscillator is pulled towards them in a few lines, by
  // when they come and not where the CRTC's line starts. A program that moves the HSYNC from line to
  // line (R2 alternating, say) doesn't shift the picture line by line, and one that makes short lines
  // whose HSYNCs still come every 64 microseconds (Pinball Dreams' tables scroll that way) doesn't
  // shift it at all, just as on the real thing. With a steady HSYNC the HSYNC's end is the left edge.
  if not FMonInit then
  begin
    FMonX := 0;
    FMonPeriod := 64;
    FMonInit := True;
  end
  else
  begin
    // How late the HSYNC came after the beam went back (negative: early)
    Err := FMonX;
    if Err > FMonPeriod / 2 then Err := Err - FMonPeriod;
    FMonX := FMonX - Err / 8;
    FMonPeriod := Min(72, Max(56, FMonPeriod + Err / 32));
  end;
  // The Gate Array counts the HSYNCs: 52 raise the interrupt
  Inc(FIntCounter);
  if FIntCounter >= 52 then
  begin
    FIntCounter := 0;
    FIntPending := True;
  end;
  // After a VSYNC began it waits two of them, and then the interrupt comes
  // at once if the counter was 32 or more; the counter restarts
  if FVsyncDelay > 0 then
  begin
    Dec(FVsyncDelay);
    if FVsyncDelay = 0 then
    begin
      if FIntCounter >= 32 then FIntPending := True;
      FIntCounter := 0;
    end;
  end;
end;

procedure TAmstrad.VsyncBegan;
var
  W, Row: Integer;
begin
  W := FCrtc[3] shr 4;
  if W = 0 then W := 16;
  FVsyncLeft := W;
  FVsyncRose := True;
  FVsyncDelay := 2;
  // A frame shorter than the 312 lines a picture takes (a program with its own CRTC values, a
  // screen of 23 rows of 32 characters, say) never reached the last line: its picture is what it
  // drew, black below
  Row := FYLines - CPC_TOP_LINES;
  if not FShownDone and (Row > 0) and (Row < CPC_HEIGHT) then
  begin
    FillChar(FBuild[Row * CPC_WIDTH], (CPC_HEIGHT - Row) * CPC_WIDTH * SizeOf(LongWord), 0);
    Move(FBuild[0], FShown[0], Length(FBuild) * SizeOf(LongWord));
  end;
  FShownDone := False;
  FYLines := 0;
end;

{ One character's 16 pixels (of the 640-pixel mode) into the line, if it is
  inside the picture }
procedure TAmstrad.DrawChar(Blank: Boolean; Dispen: Boolean);
var
  X, Ma, Addr, I, P: Integer;
  B0, B1: Byte;
  Pen: Integer;
  Col: LongWord;
  Dst: PLongWord;
begin
  X := Round(FMonX);
  if (X < CPC_LEFT_CHARS) or (X >= CPC_LEFT_CHARS + CPC_CHARS) then Exit;
  X := (X - CPC_LEFT_CHARS) * 16;
  Dst := @FLine[X];
  if Blank then
  begin
    for I := 0 to 15 do Dst[I] := $FF000000;
    Exit;
  end;
  if not Dispen then
  begin
    Col := FPenRGB[16];
    for I := 0 to 15 do Dst[I] := Col;
    Exit;
  end;
  Ma := (FRowStart + FHcc) and $3FFF;
  Addr := ((Ma and $3000) shl 2) or ((FVlc and 7) shl 11) or ((Ma and $3FF) shl 1);
  B0 := FRam[Addr shr 14][Addr and $3FFF];
  Addr := Addr + 1;
  B1 := FRam[(Addr shr 14) and 3][Addr and $3FFF];
  case FMode of
    0:
      for I := 0 to 3 do
      begin
        // Two pixels a byte: bits 7,3,5,1 (even pixel) and 6,2,4,0 (odd)
        if I < 2 then P := B0 else P := B1;
        if (I and 1) = 0 then
          Pen := ((P shr 7) and 1) or (((P shr 3) and 1) shl 1) or (((P shr 5) and 1) shl 2) or (((P shr 1) and 1) shl 3)
        else
          Pen := ((P shr 6) and 1) or (((P shr 2) and 1) shl 1) or (((P shr 4) and 1) shl 2) or ((P and 1) shl 3);
        Col := FPenRGB[Pen];
        for P := 0 to 3 do Dst[I * 4 + P] := Col;
      end;
    1, 3:
      for I := 0 to 7 do
      begin
        if I < 4 then P := B0 else P := B1;
        if FMode = 1 then
          Pen := ((P shr (7 - (I and 3))) and 1) or (((P shr (3 - (I and 3))) and 1) shl 1)
        else
          Pen := 0;   // mode 3 below
        if FMode = 3 then
        begin
          // 160x200, 4 colours: the even/odd pixel of a byte like mode 0, two bits
          if (I and 1) = 0 then
            Pen := ((P shr 7) and 1) or (((P shr 3) and 1) shl 1)
          else
            Pen := ((P shr 6) and 1) or (((P shr 2) and 1) shl 1);
        end;
        Col := FPenRGB[Pen];
        Dst[I * 2] := Col;
        Dst[I * 2 + 1] := Col;
      end;
  else
    for I := 0 to 15 do
    begin
      if I < 8 then P := B0 else P := B1;
      Dst[I] := FPenRGB[(P shr (7 - (I and 7))) and 1];
    end;
  end;
end;

{ The monitor's beam went back to the left: its line into the picture, if it is inside it }
procedure TAmstrad.MonitorLine;
var
  Row: Integer;
begin
  Row := FYLines - CPC_TOP_LINES;
  if (Row >= 0) and (Row < CPC_HEIGHT) then
  begin
    Move(FLine[0], FBuild[Row * CPC_WIDTH], CPC_WIDTH * SizeOf(LongWord));
    if Row = CPC_HEIGHT - 1 then
    begin
      Move(FBuild[0], FShown[0], Length(FBuild) * SizeOf(LongWord));
      FShownDone := True;
    end;
  end;
  Inc(FYLines);
  if FYLines > 100000 then FYLines := 100000;
end;

{ The compares the CRTC makes at the start of every line (and when R6 or R7 is
  written): R6 ends the displayed rows and R7 starts the VSYNC, both by
  equality with the row counter, so a value the counter has passed is not met
  again until it wraps. The AMS40489 only does it on the first raster of a row. }
procedure TAmstrad.LineChecks;
var
  FirstRaster: Boolean;
begin
  FirstRaster := FVlc = 0;
  if (FVcc = FCrtc[6]) and ((FCrtcType <> 3) or FirstRaster) then FVdisp := False;
  if (FVcc = FCrtc[7]) and not FVsyncTriggered and (FVsyncLeft = 0) and
     ((FCrtcType <> 3) or FirstRaster) then
  begin
    FVsyncTriggered := True;
    VsyncBegan;
  end;
end;

procedure TAmstrad.CharStep;
var
  Blank, Dispen: Boolean;
  W, Skew: Integer;
begin
  // The horizontal display flag: set at the start of the line, cleared when
  // the character counter meets R1 (R1 beyond the total: all the line)
  if FHcc = 0 then FHdisp := True;
  if FHcc = FCrtc[1] then FHdisp := False;
  FDispPipe := ((FDispPipe shl 1) or Ord(FHdisp and FVdisp and not FInAdjust)) and 7;
  // R8's display skew delays the display enable by 0 to 2 characters (3: none)
  Skew := (FCrtc[8] shr 4) and 3;
  if Skew = 3 then Dispen := False else Dispen := ((FDispPipe shr Skew) and 1) <> 0;
  // This character's output
  Blank := (FHsyncLeft > 0) or (FVsyncLeft > 0);
  DrawChar(Blank, Dispen);
  FMonX := FMonX + 1;
  if FMonX >= FMonPeriod then
  begin
    FMonX := FMonX - FMonPeriod;
    MonitorLine;
  end;
  // Then the counters
  if FHsyncLeft > 0 then
  begin
    Dec(FHsyncLeft);
    if FHsyncLeft = 0 then HsyncEnded;
  end;
  if FHcc <> FCrtc[0] then
  begin
    FHcc := (FHcc + 1) and $FF;
    if FHcc = FCrtc[2] then
    begin
      W := FCrtc[3] and 15;
      // A width of 0 is no HSYNC on the HD6845S and UM6845R, 16 on the others
      if (W = 0) and (FCrtcType in [2, 3]) then W := 16;
      FHsyncLeft := W;
    end;
    Exit;
  end;
  // End of line: the counter met R0
  FHcc := 0;
  if FVsyncLeft > 0 then
  begin
    Dec(FVsyncLeft);
    if FVsyncLeft = 0 then FVsyncRose := False;
  end;
  if FInAdjust then
  begin
    Inc(FVadj);
    if FVadj >= FCrtc[5] then StartFrame;
  end
  // The raster counter ends a row when it meets R9 (lowered below it, it goes on to 31 and round to R9)
  else if FVlc = (FCrtc[9] and $1F) then
  begin
    FVlc := 0;
    FVsyncTriggered := False;
    if FVcc = (FCrtc[4] and $7F) then
    begin
      if FCrtc[5] > 0 then
      begin
        FInAdjust := True;
        FVadj := 0;
      end
      else
        StartFrame;
    end
    else
    begin
      FVcc := (FVcc + 1) and $7F;
      FRowStart := (FRowStart + FCrtc[1]) and $3FFF;
    end;
  end
  else
    FVlc := (FVlc + 1) and $1F;
  // The UM6845R takes a new start address in the first row too
  if (FCrtcType = 1) and (FVcc = 0) and not FInAdjust then
    FRowStart := (FCrtc[12] and $3F) shl 8 or FCrtc[13];
  LineChecks;
  if FHcc = FCrtc[2] then
  begin
    W := FCrtc[3] and 15;
    if (W = 0) and (FCrtcType in [2, 3]) then W := 16;
    FHsyncLeft := W;
  end;
end;

{ The registers the chips let through, as written (Arnold's tables of
  masks): the HD6845S, AMS40489 and AMS40226 keep all of R3 (the VSYNC width
  in its high nibble) and R8's skew; the UM6845R and MC6845 don't, and have
  a VSYNC of 16 lines }
procedure TAmstrad.CrtcWrite(Reg, Value: Byte);
const
  MASK: array[0..17] of Byte = (
    $FF, $FF, $FF, $FF, $7F, $1F, $7F, $7F, $F3, $1F, $7F, $1F, $3F, $FF, $3F, $FF, $FF, $FF);
begin
  if Reg > 15 then Exit;      // R16 and R17 (the light pen) can't be written
  FCrtcRaw[Reg] := Value;
  FCrtc[Reg] := Value and MASK[Reg];
  if FCrtcType in [1, 2] then
  begin
    if Reg = 3 then FCrtc[3] := Value and $0F;
    if Reg = 8 then FCrtc[8] := Value and $03;
  end;
  if (Reg = 6) or (Reg = 7) then LineChecks;
end;

procedure TAmstrad.SetCrtcType(AType: Integer);
var
  I: Integer;
begin
  if (AType < 0) or (AType > 4) then AType := 1;
  FCrtcType := AType;
  // What was written, through the new chip's masks
  for I := 0 to 15 do
  begin
    FCrtc[I] := 0;
    CrtcWrite(I, FCrtcRaw[I]);
  end;
end;

class function TAmstrad.DefaultCrtcType(AModel: TSpectrumModel): Integer;
begin
  if AModel = smCPC464 then Result := 0 else Result := 1;
end;

{ Port BExx: the UM6845R has a status register (bit 5: in VSYNC, bit 6: the
  light pen register is full); the AMS40489 and AMS40226 show the
  register data there; the HD6845S and MC6845 nothing (the bus floats high) }
function TAmstrad.CrtcStatus: Byte;
begin
  case FCrtcType of
    1:
      begin
        Result := FStatus1;
        if FVsyncRose then Result := Result or $20;
      end;
    3, 4: Result := CrtcRead(FCrtcSel);
  else
    Result := $FF;
  end;
end;

{ Port BFxx: the register selected, if the chip lets it be read (what it
  can't returns 0). The HD6845S and the later chips read R12-R17; the UM6845R
  and MC6845 only R14-R17. The AMS40489 shows 8 registers repeated: the light
  pen, two status registers and the screen address. }
function TAmstrad.CrtcRead(Reg: Integer): Byte;
var
  Status: Byte;
begin
  Result := 0;
  Reg := Reg and $1F;
  if FCrtcType = 3 then
  begin
    case Reg and 7 of
      0: Result := 0;                      // light pen high
      1: Result := 0;                      // light pen low
      2:
        begin
          // status 1: bit 5 not on the last VSYNC line, 0 HC=R0, 1 HC<>R0/2,
          // 2 HC<>R1, 3 HC<>R2
          Status := $3F;
          if FVsyncLeft = 1 then Status := Status and not $20;
          if FHcc <> FCrtc[0] then Status := Status and not $01;
          if FHcc = (FCrtc[0] shr 1) then Status := Status and not $02;
          if FHcc = FCrtc[1] then Status := Status and not $04;
          if FHcc = FCrtc[2] then Status := Status and not $08;
          Result := Status or $C0;
        end;
      3:
        begin
          // status 2: bit 7 RC=0, bit 5 RC<>R9
          Status := $FF;
          if FVlc = 0 then Status := Status or $80 else Status := Status and not $80;
          if FVlc >= (FCrtc[9] and $1F) then Status := Status and not $20;
          Result := Status;
        end;
      4: Result := FCrtc[12];
      5: Result := FCrtc[13];
    end;
    Exit;
  end;
  case Reg of
    12, 13:
      if FCrtcType in [0, 4] then Result := FCrtc[Reg];
    14, 15: Result := FCrtc[Reg];
    16: if FCrtcType = 0 then Result := $14;       // the light pen's address
    17: if FCrtcType = 0 then Result := $7C;
  end;
  if (FCrtcType = 1) and (Reg in [16, 17]) then FStatus1 := FStatus1 and not 1;   // the light pen's "full" bit
end;

procedure TAmstrad.CopyFrame(Dest: PLongWord);
begin
  Move(FShown[0], Dest^, Length(FShown) * SizeOf(LongWord));
end;

procedure TAmstrad.PreviewFrame;
begin
  Move(FBuild[0], FShown[0], Length(FBuild) * SizeOf(LongWord));
end;

procedure TAmstrad.GetRegisters(out R: TCPCRegisters);
var
  I: Integer;
begin
  FillChar(R, SizeOf(R), 0);
  R.PenSel := FPenSel;
  for I := 0 to 16 do R.Pens[I] := FPen[I];
  R.RomReg := FRomReg;
  R.RamConfig := FRamConfig;
  R.UpperRom := FUpperRom;
  R.CrtcSel := FCrtcSel;
  for I := 0 to 17 do R.Crtc[I] := FCrtcRaw[I];
  R.Ppi[0] := FPpiA; R.Ppi[1] := FPpiB; R.Ppi[2] := FPpiC; R.Ppi[3] := FPpiCtl;
  R.PsgSel := FPsgSel;
  for I := 0 to 15 do R.Psg[I] := FPsgRegs[I];
end;

procedure TAmstrad.SetPsg(Reg: Integer; Value: Byte);
begin
  if Reg < 0 then
  begin
    FPsgSel := Value and 15;
    Exit;
  end;
  FPsgRegs[Reg and 15] := Value;
  if Assigned(FOnPsg) and ((Reg and 15) < 14) then FOnPsg(FChipT, Reg and 15, Value);
end;

procedure TAmstrad.SetRegisters(const R: TCPCRegisters);
var
  I: Integer;
begin
  FPenSel := R.PenSel;
  for I := 0 to 16 do FPen[I] := R.Pens[I] and $1F;
  BuildPalette;
  FRomReg := R.RomReg;
  FMode := FRomReg and 3;
  FRamConfig := R.RamConfig;
  FUpperRom := R.UpperRom;
  UpdateMemory;
  FCrtcSel := R.CrtcSel;
  for I := 0 to 17 do FCrtcRaw[I] := R.Crtc[I];
  SetCrtcType(FCrtcType);
  FPpiA := R.Ppi[0]; FPpiB := R.Ppi[1]; FPpiC := R.Ppi[2]; FPpiCtl := R.Ppi[3];
  FKeyLine := FPpiC and 15;
  FMotor := (FPpiC and $10) <> 0;
  FTapeOutLevel := (FPpiC and $20) <> 0;
  FPsgFn := FPpiC shr 6;
  FPsgSel := R.PsgSel and 15;
  for I := 0 to 15 do FPsgRegs[I] := R.Psg[I];
  // The beam at the start of a frame, the interrupt counter at zero
  FHcc := 0; FVcc := 0; FVlc := 0; FVadj := 0;
  FInAdjust := False;
  FRowStart := (FCrtc[12] and $3F) shl 8 or FCrtc[13];
  FHsyncLeft := 0; FVsyncLeft := 0;
  FHdisp := False; FVdisp := True; FVsyncTriggered := False; FDispPipe := 0;
  FVsyncRose := False;
  FIntCounter := 0;
  FIntPending := False;
  FVsyncDelay := 0;
  FMonX := 4;
  FMonPeriod := 64;
  FMonInit := False;
  FYLines := 0;
  FChipT := 0;
end;

function TAmstrad.CrtcReg(Index: Integer): Byte;
begin
  Result := FCrtc[Index mod 18];
end;

function TAmstrad.PenColour(Index: Integer): Byte;
begin
  Result := FPen[Index mod 17];
end;

function TAmstrad.PsgReg(Index: Integer): Byte;
begin
  Result := FPsgRegs[Index and 15];
end;

function TAmstrad.PpiPort(Index: Integer): Byte;
begin
  case Index of
    0: Result := FPpiA;
    1: Result := FPpiB;
    2: Result := FPpiC;
  else
    Result := FPpiCtl;
  end;
end;

function TAmstrad.CrtcPosition(out Hcc, Vcc, Vlc: Integer): Boolean;
begin
  Hcc := FHcc; Vcc := FVcc; Vlc := FVlc;
  Result := True;
end;

function TAmstrad.IntCounter: Integer;
begin
  Result := FIntCounter;
end;

{ The state: every field that is not a ROM or a callback, in a fixed order.
  A version byte first so it can grow. }
procedure TAmstrad.SaveState(S: TStream);
var
  Ver: Byte;
  B: Integer;
begin
  Ver := 2;
  S.WriteBuffer(Ver, 1);
  B := FRamBanks;
  S.WriteBuffer(B, SizeOf(B));
  S.WriteBuffer(FRam, B * SizeOf(TCPCBank));
  S.WriteBuffer(FPenSel, 1);
  S.WriteBuffer(FPen, SizeOf(FPen));
  S.WriteBuffer(FRomReg, 1); S.WriteBuffer(FRamConfig, 1); S.WriteBuffer(FUpperRom, 1);
  S.WriteBuffer(FIntCounter, 1); S.WriteBuffer(FIntPending, 1);
  S.WriteBuffer(FVsyncDelay, SizeOf(FVsyncDelay));
  S.WriteBuffer(FCrtcSel, 1); S.WriteBuffer(FCrtc, SizeOf(FCrtc));
  S.WriteBuffer(FCrtcRaw, SizeOf(FCrtcRaw)); S.WriteBuffer(FCrtcType, SizeOf(FCrtcType));
  S.WriteBuffer(FHdisp, 1); S.WriteBuffer(FVdisp, 1); S.WriteBuffer(FVsyncTriggered, 1);
  S.WriteBuffer(FDispPipe, 1); S.WriteBuffer(FStatus1, 1);
  S.WriteBuffer(FHcc, SizeOf(FHcc)); S.WriteBuffer(FVcc, SizeOf(FVcc));
  S.WriteBuffer(FVlc, SizeOf(FVlc)); S.WriteBuffer(FVadj, SizeOf(FVadj));
  S.WriteBuffer(FInAdjust, 1);
  S.WriteBuffer(FRowStart, SizeOf(FRowStart));
  S.WriteBuffer(FHsyncLeft, SizeOf(FHsyncLeft)); S.WriteBuffer(FVsyncLeft, SizeOf(FVsyncLeft));
  FXChars := Round(FMonX);
  S.WriteBuffer(FHsyncSeen, 1);
  S.WriteBuffer(FXChars, SizeOf(FXChars)); S.WriteBuffer(FYLines, SizeOf(FYLines));
  S.WriteBuffer(FVsyncRose, 1);
  S.WriteBuffer(FPpiA, 1); S.WriteBuffer(FPpiB, 1); S.WriteBuffer(FPpiC, 1);
  S.WriteBuffer(FPpiCtl, 1);
  S.WriteBuffer(FPsgSel, 1); S.WriteBuffer(FPsgRegs, SizeOf(FPsgRegs));
  S.WriteBuffer(FPsgFn, 1);
  S.WriteBuffer(FMotor, 1); S.WriteBuffer(FTapeOutLevel, 1); S.WriteBuffer(FDiscMotor, 1);
  S.WriteBuffer(FChipT, SizeOf(FChipT));
  S.WriteBuffer(KeyMatrix, SizeOf(KeyMatrix));
end;

procedure TAmstrad.LoadState(S: TStream);
var
  Ver: Byte;
  B: Integer;
begin
  S.ReadBuffer(Ver, 1);
  if (Ver < 1) or (Ver > 2) then raise Exception.Create(_('Unknown CPC snapshot version'));
  S.ReadBuffer(B, SizeOf(B));
  if B <> FRamBanks then raise Exception.Create(_('Not a snapshot of this CPC model'));
  S.ReadBuffer(FRam, B * SizeOf(TCPCBank));
  S.ReadBuffer(FPenSel, 1);
  S.ReadBuffer(FPen, SizeOf(FPen));
  S.ReadBuffer(FRomReg, 1); S.ReadBuffer(FRamConfig, 1); S.ReadBuffer(FUpperRom, 1);
  S.ReadBuffer(FIntCounter, 1); S.ReadBuffer(FIntPending, 1);
  S.ReadBuffer(FVsyncDelay, SizeOf(FVsyncDelay));
  S.ReadBuffer(FCrtcSel, 1); S.ReadBuffer(FCrtc, SizeOf(FCrtc));
  if Ver >= 2 then
  begin
    S.ReadBuffer(FCrtcRaw, SizeOf(FCrtcRaw)); S.ReadBuffer(FCrtcType, SizeOf(FCrtcType));
    S.ReadBuffer(FHdisp, 1); S.ReadBuffer(FVdisp, 1); S.ReadBuffer(FVsyncTriggered, 1);
    S.ReadBuffer(FDispPipe, 1); S.ReadBuffer(FStatus1, 1);
  end
  else
  begin
    FCrtcRaw := FCrtc;
    FHdisp := False; FVdisp := True; FVsyncTriggered := False; FDispPipe := 0; FStatus1 := 0;
  end;
  S.ReadBuffer(FHcc, SizeOf(FHcc)); S.ReadBuffer(FVcc, SizeOf(FVcc));
  S.ReadBuffer(FVlc, SizeOf(FVlc)); S.ReadBuffer(FVadj, SizeOf(FVadj));
  S.ReadBuffer(FInAdjust, 1);
  S.ReadBuffer(FRowStart, SizeOf(FRowStart));
  S.ReadBuffer(FHsyncLeft, SizeOf(FHsyncLeft)); S.ReadBuffer(FVsyncLeft, SizeOf(FVsyncLeft));
  S.ReadBuffer(FHsyncSeen, 1);
  S.ReadBuffer(FXChars, SizeOf(FXChars)); S.ReadBuffer(FYLines, SizeOf(FYLines));
  FMonX := FXChars;
  FMonPeriod := 64;
  FMonInit := False;
  S.ReadBuffer(FVsyncRose, 1);
  S.ReadBuffer(FPpiA, 1); S.ReadBuffer(FPpiB, 1); S.ReadBuffer(FPpiC, 1);
  S.ReadBuffer(FPpiCtl, 1);
  S.ReadBuffer(FPsgSel, 1); S.ReadBuffer(FPsgRegs, SizeOf(FPsgRegs));
  S.ReadBuffer(FPsgFn, 1);
  S.ReadBuffer(FMotor, 1); S.ReadBuffer(FTapeOutLevel, 1); S.ReadBuffer(FDiscMotor, 1);
  S.ReadBuffer(FChipT, SizeOf(FChipT));
  S.ReadBuffer(KeyMatrix, SizeOf(KeyMatrix));
  FMode := FRomReg and 3;
  BuildPalette;
  UpdateMemory;
end;

end.

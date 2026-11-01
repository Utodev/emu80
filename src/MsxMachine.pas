{ MsxMachine: an MSX computer's hardware apart from the Z80: the slots with
  their ROM and RAM (Msx.pas), the video chip (MsxVdp.pas), the 8255 PPI
  (the slot register, the keyboard matrix, the caps lamp and the click), the
  PSG's ports and the joysticks. TSpectrum (SpectrumMSX.inc) joins it to the
  CPU, the sound and the picture shown.

  The machine of this project is a PAL one: 313 lines of 228 T-states (a
  Z80 at 3.579545 MHz) = 71364 T-states a frame (50 Hz); the 192 lines of the
  picture start at line 51 and the frame interrupt is at line 243, where the
  bottom border starts. }
unit MsxMachine;

{$mode objfpc}{$H+}
{$POINTERMATH ON}

interface

uses
  SysUtils, Classes, Msx, MsxVdp, MsxDisk, WD1772;

const
  MSX_LINE_T = 228;
  MSX_LINES = 313;
  MSX_FRAME_T = MSX_LINE_T * MSX_LINES;
  MSX_FIRST_LINE = 51;                // the first line of the picture
  MSX_INT_LINE = MSX_FIRST_LINE + VDP_SCREEN_LINES;
  MSX_FB_WIDTH = 704;                 // the frame buffer of TSpectrum: 352 x 2 columns
  MSX_FB_HEIGHT = 288;
  MSX_SHOW_TOP = 48;                  // the picture's first row in it (a border above)
  MSX_SHOW_LEFT = 96;                 // and its first column (every pixel twice)
  MSX_KEY_ROWS = 11;

  { The keyboard matrix: 11 rows of 8 keys, key = row * 8 + bit (a row is read at port A9h
    with its number in the low 4 bits of port AAh); a key held reads 0 }
  MSXK_0 = 0;  MSXK_1 = 1;  MSXK_2 = 2;  MSXK_3 = 3;  MSXK_4 = 4;  MSXK_5 = 5;  MSXK_6 = 6;  MSXK_7 = 7;
  MSXK_8 = 8;  MSXK_9 = 9;  MSXK_MINUS = 10; MSXK_EQUALS = 11; MSXK_BACKSLASH = 12;
  MSXK_LBRACKET = 13; MSXK_RBRACKET = 14; MSXK_SEMICOLON = 15;
  MSXK_QUOTE = 16; MSXK_GRAVE = 17; MSXK_COMMA = 18; MSXK_PERIOD = 19; MSXK_SLASH = 20; MSXK_DEAD = 21;
  MSXK_A = 22; MSXK_B = 23;
  MSXK_C = 24; MSXK_D = 25; MSXK_E = 26; MSXK_F = 27; MSXK_G = 28; MSXK_H = 29; MSXK_I = 30; MSXK_J = 31;
  MSXK_K = 32; MSXK_L = 33; MSXK_M = 34; MSXK_N = 35; MSXK_O = 36; MSXK_P = 37; MSXK_Q = 38; MSXK_R = 39;
  MSXK_S = 40; MSXK_T = 41; MSXK_U = 42; MSXK_V = 43; MSXK_W = 44; MSXK_X = 45; MSXK_Y = 46; MSXK_Z = 47;
  MSXK_SHIFT = 48; MSXK_CTRL = 49; MSXK_GRAPH = 50; MSXK_CAPS = 51; MSXK_CODE = 52;
  MSXK_F1 = 53; MSXK_F2 = 54; MSXK_F3 = 55;
  MSXK_F4 = 56; MSXK_F5 = 57; MSXK_ESC = 58; MSXK_TAB = 59; MSXK_STOP = 60; MSXK_BS = 61;
  MSXK_SELECT = 62; MSXK_RETURN = 63;
  MSXK_SPACE = 64; MSXK_HOME = 65; MSXK_INS = 66; MSXK_DEL = 67;
  MSXK_LEFT = 68; MSXK_UP = 69; MSXK_DOWN = 70; MSXK_RIGHT = 71;
  MSXK_COUNT = MSX_KEY_ROWS * 8;

  { The joystick's bits (a pressed one reads 0 at the PSG) }
  MSXJ_UP = 1; MSXJ_DOWN = 2; MSXJ_LEFT = 4; MSXJ_RIGHT = 8; MSXJ_FIRE1 = $10; MSXJ_FIRE2 = $20;

type
  TMsxPsgEvent = procedure(T: Integer; Reg, Value: Byte) of object;
  TMsxClickEvent = procedure(T: Integer; Level: Boolean) of object;
  TMsxTapeInEvent = function(T: Integer): Boolean of object;
  TMsxMotorEvent = procedure(T: Integer; On_: Boolean) of object;

  TMsxMachine = class
  private
    FSlots: TMsxSlots;
    FIO: TMsxIO;
    FVdp: TMsxVdp;
    FPpiC: Byte;
    FPsgSel: Byte;
    FPsgRegs: array[0..15] of Byte;
    FJoy: array[0..1] of Byte;        // bit 0 up, 1 down, 2 left, 3 right, 4 and 5 the buttons; 1 = not pressed
    FHasDisk: Boolean;
    FCompat: Boolean;                 // the MSX1 layout: no expanded slot (see SetCompat)
    FMapper: TMsxMapper;              // the memory mapper
    FMapperOn: Boolean;               // False: no mapper ports, the 64K of RAM stay as the BIOS leaves them (3, 2, 1, 0)
    FRtcSel: Byte;                    // the MSX2's clock chip (RP-5C01): the register selected
    FRtc: array[0..3, 0..15] of Byte; // its four blocks of 13 4-bit registers; 2 and 3 are the battery-backed RAM
    FLine: Integer;                   // the next line to draw
    FBuild, FShown: array of LongWord;
    FT: Integer;
    FOnPsg: TMsxPsgEvent;
    FOnClick: TMsxClickEvent;
    FOnTapeIn: TMsxTapeInEvent;
    FOnMotor: TMsxMotorEvent;
    function PpiRead(Port: Byte): Byte;
    procedure PpiWrite(Port: Byte; Value: Byte);
    function MapperRead(Port: Byte): Byte;
    procedure MapperWrite(Port: Byte; Value: Byte);
    function RtcRead(Port: Byte): Byte;
    procedure RtcWrite(Port: Byte; Value: Byte);
    function VdpRead(Port: Byte): Byte;
    procedure VdpWrite(Port: Byte; Value: Byte);
    function PsgRead(Port: Byte): Byte;
    procedure PsgWrite(Port: Byte; Value: Byte);
    procedure DrawLine(L: Integer);
    procedure SetPpiC(Value: Byte);
    procedure BuildSlots(Compat: Boolean);
  public
    KeyMatrix: array[0..MSX_KEY_ROWS - 1] of Byte;   // 1 = released
    AutoMatrix: array[0..MSX_KEY_ROWS - 1] of Byte;
    constructor Create;
    destructor Destroy; override;
    { Loads the BIOS (and BASIC) into slot 0 from its file; raises if it is missing }
    procedure LoadBios(const FileName: string);
    { A cartridge ROM in a slot (1 or 2), placed where its header says it starts }
    { The MSX2's sub-ROM (16K) goes in the expanded slot 3, subslot 1, at 0000h (in the MSX1 layout, in slot 2) }
    procedure LoadSubRom(const FileName: string);
    { The MSX1 layout: no slot is expanded (FFFFh is plain RAM, as in an MSX1) - the RAM alone in slot 3, the sub-ROM in slot 2
      and no disk interface; the other, the MSX2's own (slot 3 expanded). Frees what is in slots 2 and 3: the sub-ROM and
      the disk interface must be put in again (LoadSubRom, InstallDisk); the RAM starts empty }
    procedure SetCompat(Value: Boolean);
    property Compat: Boolean read FCompat;
    procedure InsertRom(Slot: Integer; const AName: string; const Data; Size: Integer);
    { The same with a mapper: Auto guesses it (GuessMapper), else Kind is used.
      Returns the mapper in use }
    function InsertCartridge(Slot: Integer; const AName: string; const Data; Size: Integer;
      Auto: Boolean; Kind: TMsxMapperKind): TMsxMapperKind;
    { The disk interface (the ROM of its cartridge and the controller) in a subslot of slot 3 }
    procedure InstallDisk(const FileName: string; AWD: TWD1772; ATime: TMsxTimeFn);
    { Takes the disk interface out (slot 3-3 empty): no drive }
    procedure RemoveDisk;
    function HasDisk: Boolean;
    procedure RemoveRom(Slot: Integer);
    function CartridgeName(Slot: Integer): string;
    { The cartridge in a slot, for the cartridge browser: its bytes (what is changed there is what the Z80 sees),
      their number, its mapper and where a plain ROM is shown (-1 when there is none) }
    function CartridgeData(Slot: Integer): PByte;
    function CartridgeSize(Slot: Integer): Integer;
    function CartridgeMapper(Slot: Integer): TMsxMapperKind;
    function CartridgeBase(Slot: Integer): Integer;
    { The debugger's view of the ports: code $0000 the slot register (A8h), $0001 the secondary one of slot 3 (FFFFh), $0002
      the PPI's port C (AAh), $0010+N the mapper's segment of page N, $0100+N the PSG's register N, $0110 the PSG's selected
      register, $0200+N the VDP's register N, $0240+N its status register N, $0260+N colour N of its palette (as the digits R, G and B, 0 to 7) }
    function PortValue(Code: Integer): Integer;
    procedure SetPortValue(Code, Value: Integer);
    procedure Reset(Hard: Boolean);
    function Read(Addr: Word): Byte;
    function Peek(Addr: Word): Byte;
    procedure Write(Addr: Word; Value: Byte);
    function InPort(Port: Word; T: Integer): Byte;
    procedure OutPort(Port: Word; Value: Byte; T: Integer);
    { The beam: draws the lines up to T-state T of the frame and raises the frame flag }
    procedure Sync(T: Integer);
    procedure EndFrame;
    procedure CopyFrame(Dest: PLongWord);
    procedure PreviewFrame;
    function IntLine: Boolean;
    procedure SetJoystick(Port: Integer; Bits: Byte);
    property Slots: TMsxSlots read FSlots;
    property Vdp: TMsxVdp read FVdp;
    property OnPsg: TMsxPsgEvent read FOnPsg write FOnPsg;
    property OnClick: TMsxClickEvent read FOnClick write FOnClick;
    property OnTapeIn: TMsxTapeInEvent read FOnTapeIn write FOnTapeIn;
    property OnMotor: TMsxMotorEvent read FOnMotor write FOnMotor;
    { The cassette motor (bit 4 of PPI port C, a 0 is on) }
    function Motor: Boolean;
    { The mapper's ports FCh-FFh answer; off, they are not there, as on an MSX1: the programs that use those ports for
      something of their own (the ZX Spectrum conversions: FEh is the Spectrum's border and beeper) do not move the RAM.
      Takes effect with the next reset }
    property MapperOn: Boolean read FMapperOn write FMapperOn;
  end;

implementation

uses
  Lang;


{ The RAM and the disk interface share the primary slot 3 (expanded), as in the Philips machines: the software that
  pages memory through the slot register itself, the DAAD engines for one, keeps its own copy of it, which only
  holds if the disk ROM, in a subslot, never needs the register changed. The machine has 128K of
  mapper RAM in 3-0 and, as the same memory, in 3-2, the sub-ROM in 3-1 and the disk in 3-3. Where the BIOS leaves the
  subslot register, programs that look for RAM in a primary slot alone find it in 3-0, and the ones that set the whole
  register to the subslot of the RAM they know (2 is the usual one) find it there: a game loader does both.
  The MSX1 layout (Compat) has no expanded slot, which some MSX1 programs need: they use FFFFh as RAM or look for it
  in a primary slot only; there the RAM is slot 3 alone, the sub-ROM is in slot 2 and the disk interface is not there }
procedure TMsxMachine.BuildSlots(Compat: Boolean);
var
  Ram: TMsxMapperRam;
begin
  FSlots.ClearPrimary(3);
  FSlots.ClearPrimary(2);
  FSlots.SetExpanded(3, not Compat);
  Ram := TMsxMapperRam.Create(FMapper);
  FSlots.Install(3, 0, Ram);
  if not Compat then FSlots.Install(3, 2, TMsxMapperRam.CreateMirror(Ram));
  FCompat := Compat;
  FHasDisk := False;
end;

procedure TMsxMachine.SetCompat(Value: Boolean);
begin
  if Value <> FCompat then BuildSlots(Value);
end;

constructor TMsxMachine.Create;
begin
  inherited Create;
  FSlots := TMsxSlots.Create;
  FIO := TMsxIO.Create;
  FVdp := TMsxVdp.Create;
  SetLength(FBuild, MSX_FB_WIDTH * MSX_FB_HEIGHT);
  SetLength(FShown, MSX_FB_WIDTH * MSX_FB_HEIGHT);
  FIO.Clear;
  FIO.Map($98, 4, @VdpRead, @VdpWrite);
  FIO.Map($A0, 3, @PsgRead, @PsgWrite);
  FIO.Map($A8, 4, @PpiRead, @PpiWrite);
  FMapper := TMsxMapper.Create(8);
  FMapperOn := True;
  BuildSlots(False);
  FIO.Map($FC, 4, @MapperRead, @MapperWrite);
  FIO.Map($B4, 2, @RtcRead, @RtcWrite);
  FillChar(KeyMatrix, SizeOf(KeyMatrix), $FF);
  FillChar(AutoMatrix, SizeOf(AutoMatrix), $FF);
  FillChar(FRtc, SizeOf(FRtc), 0);
  FJoy[0] := $3F;
  FJoy[1] := $3F;
end;

destructor TMsxMachine.Destroy;
begin
  FVdp.Free;
  FIO.Free;
  FSlots.Free;
  FMapper.Free;
  inherited Destroy;
end;

procedure TMsxMachine.LoadBios(const FileName: string);
var
  F: TFileStream;
  Data: array of Byte;
begin
  if not FileExists(FileName) then
    raise Exception.CreateFmt(_('ROM file not found: %s'), [FileName]);
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Data, F.Size);
    if F.Size > 0 then F.ReadBuffer(Data[0], F.Size);
  finally
    F.Free;
  end;
  FSlots.Install(0, 0, TMsxRom.Create('BIOS', Data[0], Length(Data), 0));
end;

procedure TMsxMachine.LoadSubRom(const FileName: string);
var
  F: TFileStream;
  Data: array of Byte;
begin
  if not FileExists(FileName) then
    raise Exception.CreateFmt(_('ROM file not found: %s'), [FileName]);
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Data, F.Size);
    if F.Size > 0 then F.ReadBuffer(Data[0], F.Size);
  finally
    F.Free;
  end;
  if FCompat then FSlots.Install(2, 0, TMsxRom.Create('Sub-ROM', Data[0], Length(Data), 0))
  else FSlots.Install(3, 1, TMsxRom.Create('Sub-ROM', Data[0], Length(Data), 0));
end;

procedure TMsxMachine.InsertRom(Slot: Integer; const AName: string; const Data; Size: Integer);
var
  B: PByte;
  Base: Word;
  Init: Integer;
begin
  B := @Data;
  { A ROM of 16K or 32K with the 'AB' header starts at 4000h, or at 8000h if
    its INIT routine is there; a 48K or 64K one at 0000h and 4000h (the
    mappers of phase 4 take the bigger ones) }
  Base := $4000;
  if (Size >= 16) and (B[0] = Ord('A')) and (B[1] = Ord('B')) then
  begin
    Init := B[2] or (B[3] shl 8);
    if (Size <= 16384) and (Init >= $8000) and (Init < $C000) then Base := $8000
    else if (Size > 32768) and (Init < $4000) and (Init <> 0) then Base := $0000;
  end;
  if Size = 49152 then Base := $4000;
  // A 32K ROM whose header is in its second half (at 4000h) has the first half in page 0: it is mapped from 0000h
  // (Athletic Land is one: its first 16K is code of its own, with an "AB" header and an INIT in page 0)
  if (Size = 32768) and (B[$4000] = Ord('A')) and (B[$4001] = Ord('B')) and
     ((B[$4002] or (B[$4003] shl 8)) >= $4000) and ((B[$4002] or (B[$4003] shl 8)) < $8000) and
     not ((B[0] = Ord('A')) and (B[1] = Ord('B')) and ((B[2] or (B[3] shl 8)) >= $4000)) then
    Base := $0000;
  FSlots.Install(Slot, 0, TMsxRom.Create(AName, Data, Size, Base));
end;

function TMsxMachine.InsertCartridge(Slot: Integer; const AName: string; const Data; Size: Integer;
  Auto: Boolean; Kind: TMsxMapperKind): TMsxMapperKind;
begin
  if Auto then Kind := GuessMapper(Data, Size);
  if Kind = mpPlain then InsertRom(Slot, AName, Data, Size)
  else FSlots.Install(Slot, 0, TMsxMegaRom.Create(AName, Kind, Data, Size));
  Result := Kind;
end;

function TMsxMachine.CartridgeName(Slot: Integer): string;
var
  D: TMsxDevice;
begin
  D := FSlots.DeviceAtSlot(Slot, 0);
  if (D <> nil) and (D.Kind in [mkRom, mkCartridge]) then Result := D.Name else Result := '';
end;

function TMsxMachine.CartridgeData(Slot: Integer): PByte;
var
  D: TMsxDevice;
begin
  D := FSlots.DeviceAtSlot(Slot, 0);
  if (D <> nil) and (D.Kind in [mkRom, mkCartridge]) then Result := D.RawData else Result := nil;
end;

function TMsxMachine.CartridgeSize(Slot: Integer): Integer;
var
  D: TMsxDevice;
begin
  D := FSlots.DeviceAtSlot(Slot, 0);
  if (D <> nil) and (D.Kind in [mkRom, mkCartridge]) then Result := D.RawSize else Result := 0;
end;

function TMsxMachine.CartridgeMapper(Slot: Integer): TMsxMapperKind;
var
  D: TMsxDevice;
begin
  D := FSlots.DeviceAtSlot(Slot, 0);
  if D is TMsxMegaRom then Result := TMsxMegaRom(D).Mapper else Result := mpPlain;
end;

function TMsxMachine.CartridgeBase(Slot: Integer): Integer;
var
  D: TMsxDevice;
begin
  D := FSlots.DeviceAtSlot(Slot, 0);
  if D is TMsxRom then Result := TMsxRom(D).Base else Result := -1;
end;

function TMsxMachine.PortValue(Code: Integer): Integer;
begin
  case Code of
    $0000: Result := FSlots.PrimaryReg;
    $0001: Result := FSlots.SecondaryReg(3);
    $0002: Result := FPpiC;
    $0010..$0013: Result := FMapper.Segment(Code - $0010);
    $0100..$010F: Result := FPsgRegs[Code - $0100];
    $0110: Result := FPsgSel;
    $0200..$022F: Result := FVdp.Reg(Code - $0200);
    $0240..$0249: Result := FVdp.StatusReg(Code - $0240);
    $0260..$026F:
      begin
        Result := FVdp.PaletteRGB(Code - $0260);
        Result := (((Result shr 21) and 7) shl 8) or (((Result shr 13) and 7) shl 4) or ((Result shr 5) and 7);
      end;
  else
    Result := 0;
  end;
end;

procedure TMsxMachine.SetPortValue(Code, Value: Integer);
var
  Sel: Byte;
begin
  case Code of
    $0000: FSlots.SetPrimaryReg(Value);
    $0001: FSlots.SetSecondaryReg(3, Value);
    $0002: SetPpiC(Value);
    $0010..$0013: FMapper.WritePort($FC + Code - $0010, Value);
    $0100..$010F:
      begin
        Sel := FPsgSel;
        FPsgSel := Code - $0100;
        PsgWrite(1, Value);
        FPsgSel := Sel;
      end;
    $0110: FPsgSel := Value and 15;
    $0200..$022F: FVdp.SetReg(Code - $0200, Value);
    $0260..$026F: FVdp.SetPalEntry(Code - $0260, (Value shr 8) and 7, (Value shr 4) and 7, Value and 7);
  end;
end;

procedure TMsxMachine.InstallDisk(const FileName: string; AWD: TWD1772; ATime: TMsxTimeFn);
var
  F: TFileStream;
  Data: array of Byte;
  Dev: TMsxDiskInterface;
begin
  if FCompat then Exit;               // no room for it in a machine with no expanded slot
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Data, F.Size);
    if F.Size > 0 then F.ReadBuffer(Data[0], F.Size);
  finally
    F.Free;
  end;
  Dev := TMsxDiskInterface.Create('Disk interface', Data[0], Length(Data), AWD);
  Dev.OnTime := ATime;
  FSlots.Install(3, 3, Dev);
  FHasDisk := True;
end;

procedure TMsxMachine.RemoveDisk;
begin
  if FCompat then Exit;
  FSlots.Install(3, 3, TMsxEmpty.Create);
  FHasDisk := False;
end;

function TMsxMachine.HasDisk: Boolean;
begin
  Result := FHasDisk;
end;

procedure TMsxMachine.RemoveRom(Slot: Integer);
begin
  FSlots.Install(Slot, 0, TMsxEmpty.Create);
end;

procedure TMsxMachine.Reset(Hard: Boolean);
begin
  if Hard then FSlots.Wipe;
  FSlots.Reset;
  FVdp.Reset;
  FPpiC := 0;
  FPsgSel := 0;
  FillChar(FPsgRegs, SizeOf(FPsgRegs), 0);
  FLine := 0;
  FT := 0;
  FillChar(FBuild[0], Length(FBuild) * SizeOf(LongWord), 0);
  FillChar(FShown[0], Length(FShown) * SizeOf(LongWord), 0);
end;

function TMsxMachine.Read(Addr: Word): Byte;
begin
  Result := FSlots.Read(Addr);
end;

function TMsxMachine.Peek(Addr: Word): Byte;
begin
  Result := FSlots.Peek(Addr);
end;

procedure TMsxMachine.Write(Addr: Word; Value: Byte);
begin
  FSlots.Write(Addr, Value);
end;

function TMsxMachine.InPort(Port: Word; T: Integer): Byte;
begin
  Sync(T);
  FT := T;
  Result := FIO.Read(Port and $FF);
end;

procedure TMsxMachine.OutPort(Port: Word; Value: Byte; T: Integer);
begin
  Sync(T);
  FT := T;
  FIO.Write(Port and $FF, Value);
end;

{ The 8255 PPI: A (A8h) is the slot register, B (A9h) the keyboard row selected by the low 4 bits of
  C (AAh), whose bit 4 is the cassette motor, 5 the cassette output, 6 the caps lamp, 7 the click }
function TMsxMachine.PpiRead(Port: Byte): Byte;
var
  Row: Integer;
begin
  case Port and 3 of
    0: Result := FSlots.PrimaryReg;
    1:
      begin
        Row := FPpiC and 15;
        if Row < MSX_KEY_ROWS then Result := KeyMatrix[Row] and AutoMatrix[Row] else Result := $FF;
      end;
    2: Result := FPpiC;
  else
    Result := $FF;
  end;
end;

function TMsxMachine.Motor: Boolean;
begin
  Result := (FPpiC and $10) = 0;
end;

procedure TMsxMachine.SetPpiC(Value: Byte);
var
  Old: Byte;
begin
  Old := FPpiC;
  FPpiC := Value;
  if ((Old xor Value) and $80) <> 0 then
    if Assigned(FOnClick) then FOnClick(FT, (Value and $80) <> 0);
  if ((Old xor Value) and $10) <> 0 then
    if Assigned(FOnMotor) then FOnMotor(FT, (Value and $10) = 0);
end;

procedure TMsxMachine.PpiWrite(Port: Byte; Value: Byte);
var
  Bit: Integer;
begin
  case Port and 3 of
    0: FSlots.SetPrimaryReg(Value);
    2: SetPpiC(Value);
    3:
      if (Value and $80) = 0 then
      begin
        Bit := (Value shr 1) and 7;
        if (Value and 1) <> 0 then SetPpiC(FPpiC or (1 shl Bit))
        else SetPpiC(FPpiC and not (1 shl Bit));
      end;
  end;
end;

{ The beam's place for the status register 2 of the V9938: in the vertical blanking, and the last part of a line }
function TMsxMachine.VdpRead(Port: Byte): Byte;
var
  Top, Y: Integer;
begin
  if (Port and 1) = 0 then Result := FVdp.ReadData
  else
  begin
    Top := MSX_FIRST_LINE - (FVdp.Lines - VDP_SCREEN_LINES) div 2;
    Y := FT div MSX_LINE_T - Top;
    FVdp.VBlank := (Y < 0) or (Y >= FVdp.Lines);
    FVdp.HBlank := (FT mod MSX_LINE_T) >= 190;
    Result := FVdp.ReadStatus;
  end;
end;

procedure TMsxMachine.VdpWrite(Port: Byte; Value: Byte);
begin
  case Port and 3 of
    0: FVdp.WriteData(Value);
    1: FVdp.WriteControl(Value);
    2: FVdp.WritePalette(Value);
    3: FVdp.WriteIndirect(Value);
  end;
end;

function TMsxMachine.MapperRead(Port: Byte): Byte;
begin
  if FMapperOn then Result := FMapper.ReadPort(Port) else Result := $FF;
end;

procedure TMsxMachine.MapperWrite(Port: Byte; Value: Byte);
begin
  if FMapperOn then FMapper.WritePort(Port, Value);
end;

{ The clock chip: B4h selects a register, B5h reads or writes it. Register 13 has the block (bits 0-1), 14 and
  15 the test and reset; block 0 is the time (as the PC has it), block 1 the alarm and 24-hour mode, blocks 2 and
  3 a RAM the BIOS keeps its settings (screen, colours, the title) in }
function TMsxMachine.RtcRead(Port: Byte): Byte;
var
  Blk: Integer;
  Now_: TDateTime;
  Y, Mo, D, H, Mi, S, Ms: Word;
begin
  Result := $F0;
  if (Port and 1) = 0 then Exit;
  Blk := FRtc[0, 13] and 3;
  case FRtcSel of
    13: Exit($F0 or (FRtc[0, 13] and $F));
    14, 15: Exit($F0);
  end;
  if Blk = 0 then
  begin
    Now_ := Now;
    DecodeDate(Now_, Y, Mo, D);
    DecodeTime(Now_, H, Mi, S, Ms);
    case FRtcSel of
      0: Result := S mod 10;
      1: Result := S div 10;
      2: Result := Mi mod 10;
      3: Result := Mi div 10;
      4: Result := H mod 10;
      5: Result := H div 10;
      6: Result := DayOfWeek(Now_) - 1;
      7: Result := D mod 10;
      8: Result := D div 10;
      9: Result := Mo mod 10;
      10: Result := Mo div 10;
      11: Result := (Y - 1980) mod 10;
      12: Result := ((Y - 1980) div 10) mod 10;
    else
      Result := 0;
    end;
    Result := Result or $F0;
  end
  else
    Result := $F0 or (FRtc[Blk, FRtcSel and 15] and $F);
end;

procedure TMsxMachine.RtcWrite(Port: Byte; Value: Byte);
var
  Blk: Integer;
begin
  if (Port and 1) = 0 then
  begin
    FRtcSel := Value and 15;
    Exit;
  end;
  Blk := FRtc[0, 13] and 3;
  case FRtcSel of
    13: FRtc[0, 13] := Value and $F;
    14: ;
    15: ;
  else
    if Blk <> 0 then FRtc[Blk, FRtcSel] := Value and $F;     // (the time itself follows the PC's)
  end;
end;

{ The PSG: A0h selects a register, A1h writes it, A2h reads it. Registers 14 and 15 are its I/O
  ports: 14 reads the joystick selected by bit 6 of 15 (and the cassette input in bit 7) }
function TMsxMachine.PsgRead(Port: Byte): Byte;
begin
  if (Port and 3) <> 2 then Exit($FF);
  case FPsgSel and 15 of
    14:
      begin
        Result := (FJoy[(FPsgRegs[15] shr 6) and 1] and $3F) or $40;
        if Assigned(FOnTapeIn) and FOnTapeIn(FT) then Result := Result or $80;
      end;
    15: Result := FPsgRegs[15];
  else
    Result := FPsgRegs[FPsgSel and 15];
  end;
end;

procedure TMsxMachine.PsgWrite(Port: Byte; Value: Byte);
begin
  case Port and 3 of
    0: FPsgSel := Value and 15;
    1:
      begin
        FPsgRegs[FPsgSel and 15] := Value;
        if (FPsgSel and 15) < 14 then
          if Assigned(FOnPsg) then FOnPsg(FT, FPsgSel and 15, Value);
      end;
  end;
end;

procedure TMsxMachine.SetJoystick(Port: Integer; Bits: Byte);
begin
  FJoy[Port and 1] := Bits and $3F;
end;

procedure TMsxMachine.DrawLine(L: Integer);
var
  Row, X, Y, Top: Integer;
  Pixels: TVdpOut;
  Wide: Boolean;
  Bd: LongWord;
  P: PLongWord;
begin
  { The picture of 192 lines starts at frame line 51, the V9938's 212 ten lines earlier; frame line L shows at row
    L - 3 of the frame buffer, the picture from row 48 }
  Top := MSX_FIRST_LINE - (FVdp.Lines - VDP_SCREEN_LINES) div 2;
  Row := L - (MSX_FIRST_LINE - MSX_SHOW_TOP);
  if (Row < 0) or (Row >= MSX_FB_HEIGHT) then Exit;
  Bd := FVdp.BackdropRGB;
  P := @FBuild[Row * MSX_FB_WIDTH];
  Y := L - Top;
  if (Y < 0) or (Y >= FVdp.Lines) then
  begin
    for X := 0 to MSX_FB_WIDTH - 1 do P[X] := Bd;
    Exit;
  end;
  FVdp.RenderLine(Y, Pixels, Wide);
  for X := 0 to MSX_SHOW_LEFT - 1 do P[X] := Bd;
  Move(Pixels[0], P[MSX_SHOW_LEFT], 512 * SizeOf(LongWord));
  for X := MSX_SHOW_LEFT + 512 to MSX_FB_WIDTH - 1 do P[X] := Bd;
end;

procedure TMsxMachine.Sync(T: Integer);
var
  Top, Y: Integer;
begin
  while (FLine < MSX_LINES) and (FLine * MSX_LINE_T <= T) do
  begin
    Top := MSX_FIRST_LINE - (FVdp.Lines - VDP_SCREEN_LINES) div 2;
    Y := FLine - Top;
    if FLine = Top + FVdp.Lines then FVdp.SetFrameFlag;
    if (Y >= 0) and (Y < FVdp.Lines) then FVdp.LineReached(Y);
    DrawLine(FLine);
    Inc(FLine);
  end;
end;

procedure TMsxMachine.EndFrame;
begin
  Sync(MSX_FRAME_T);
  FLine := 0;
  Move(FBuild[0], FShown[0], Length(FBuild) * SizeOf(LongWord));
end;

procedure TMsxMachine.CopyFrame(Dest: PLongWord);
begin
  Move(FShown[0], Dest^, Length(FShown) * SizeOf(LongWord));
end;

procedure TMsxMachine.PreviewFrame;
begin
  Move(FBuild[0], FShown[0], Length(FBuild) * SizeOf(LongWord));
end;

function TMsxMachine.IntLine: Boolean;
begin
  Result := FVdp.IntLine;
end;

end.

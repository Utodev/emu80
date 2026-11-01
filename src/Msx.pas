{ Msx: the memory and I/O architecture of the MSX computers, apart from any
  chip: the four primary slots, the secondary slots of an expanded primary
  slot (selected by the register at FFFFh, which reads back inverted), the
  four 16K pages of the Z80's address space each pointing to one slot (the
  register at port A8h), the memory mapper of the MSX2 (segments of 16K,
  ports FCh-FFh) and an I/O space of 256 ports with handlers.

  Devices (ROM, RAM, mapper RAM, a cartridge, later disk interfaces and sound
  cartridges) are installed in a slot and see the logical address of the
  access, so one can be put in any slot, and new ones need no change here.

  Written from the MSX System specification and checked against how openMSX
  behaves (the slot register, the mapper's unused bits reading as 1); no code
  of openMSX is used. }
unit Msx;

{$mode objfpc}{$H+}

interface

const
  MSX_PAGE_SIZE = $4000;
  MSX_SEGMENT_MAX = 256;          // segments of 16K a mapper can have (4 MB)

type
  { What an installed device is, for the debugger and the missing-ROM report }
  TMsxDeviceKind = (mkEmpty, mkRom, mkRam, mkMapperRam, mkCartridge, mkOther);

  { A device in a slot. Addr is the logical address (0000h-FFFFh) }
  TMsxDevice = class
  private
    FName: string;
    FKind: TMsxDeviceKind;
  public
    constructor Create(const AName: string; AKind: TMsxDeviceKind);
    function Read(Addr: Word): Byte; virtual;
    function Peek(Addr: Word): Byte; virtual;           // Read without side effects
    procedure Write(Addr: Word; Value: Byte); virtual;
    procedure Reset; virtual;
    { A power-on: memory goes back to zeros }
    procedure Wipe; virtual;
    { The offset in the device's own memory that Addr maps to, -1 if none }
    function PhysicalOffset(Addr: Word): Integer; virtual;
    { The contents of a ROM (nil for a device without one), for the cartridge browser: what is changed there is what runs }
    function RawData: PByte; virtual;
    function RawSize: Integer; virtual;
    property Name: string read FName;
    property Kind: TMsxDeviceKind read FKind;
  end;

  { Nothing: reads FFh (the bus floats high), ignores writes }
  TMsxEmpty = class(TMsxDevice)
  public
    constructor Create;
  end;

  { A ROM of any size, shown from logical address Base. Outside the ROM's
    own size reads FFh; writes are ignored }
  TMsxRom = class(TMsxDevice)
  private
    FData: array of Byte;
    FBase: Word;
  public
    constructor Create(const AName: string; const AData; ASize: Integer; ABase: Word);
    function Read(Addr: Word): Byte; override;
    function PhysicalOffset(Addr: Word): Integer; override;
    function RawData: PByte; override;
    function RawSize: Integer; override;
    function Size: Integer;
    property Base: Word read FBase;
  end;

  { Plain RAM from logical address Base up, ASize bytes }
  TMsxRam = class(TMsxDevice)
  private
    FData: array of Byte;
    FBase: Word;
  public
    constructor Create(const AName: string; ASize: Integer; ABase: Word);
    function Read(Addr: Word): Byte; override;
    procedure Write(Addr: Word; Value: Byte); override;
    procedure Reset; override;
    procedure Wipe; override;
    function PhysicalOffset(Addr: Word): Integer; override;
    function Size: Integer;
  end;

  { The memory mapper's segment registers (ports FCh-FFh, one per 16K page of
    the CPU). Unused high bits read back as 1 }
  TMsxMapper = class
  private
    FSegments: Integer;               // a power of 2
    FReg: array[0..3] of Byte;
  public
    constructor Create(ASegments: Integer);
    procedure Reset;
    procedure WritePort(Port: Byte; Value: Byte);   // port FCh-FFh (the low 2 bits pick the page)
    function ReadPort(Port: Byte): Byte;
    function Segment(Page: Integer): Integer;
    property Segments: Integer read FSegments;
  end;

  { RAM in 16K segments, selected per page by a mapper (the MSX2's 128K) }
  TMsxMapperRam = class(TMsxDevice)
  private
    FData: array of Byte;
    FMapper: TMsxMapper;
  public
    constructor Create(AMapper: TMsxMapper);
    { The same memory seen from another subslot (the two share their bytes) }
    constructor CreateMirror(AOther: TMsxMapperRam);
    function Read(Addr: Word): Byte; override;
    procedure Write(Addr: Word; Value: Byte); override;
    procedure Reset; override;
    procedure Wipe; override;
    function PhysicalOffset(Addr: Word): Integer; override;
  end;

  { The mappers of the cartridges (a plain ROM has none) }
  TMsxMapperKind = (mpPlain, mpKonami, mpKonamiScc, mpAscii8, mpAscii16);

  { A cartridge ROM bigger than the 32K the Z80 sees at 4000h-BFFFh: 8K (16K for
    the ASCII16 type) banks selected by writes to the ROM area. The names
    mean the way the banks are selected:
      Konami     banks 1-3 (at 6000h, 8000h, A000h) by a write anywhere in their 8K;
                 bank 0 (4000h) is fixed
      Konami SCC the same, written at 5000h, 7000h, 9000h, B000h (the SCC's sound
                 is not emulated yet)
      ASCII8     four 8K banks, written at 6000h, 6800h, 7000h, 7800h
      ASCII16    two 16K banks, written at 6000h and 7000h }
  TMsxMegaRom = class(TMsxDevice)
  private
    FData: array of Byte;
    FMapperKind: TMsxMapperKind;
    FBank: array[0..3] of Integer;      // the 8K bank shown at 4000h, 6000h, 8000h, A000h
    FBanks: Integer;                    // 8K banks the ROM has
    procedure SetBank(Region, Value: Integer);
  public
    constructor Create(const AName: string; AKind: TMsxMapperKind; const AData; ASize: Integer);
    function Read(Addr: Word): Byte; override;
    procedure Write(Addr: Word; Value: Byte); override;
    procedure Reset; override;
    function PhysicalOffset(Addr: Word): Integer; override;
    function RawData: PByte; override;
    function RawSize: Integer; override;
    property Mapper: TMsxMapperKind read FMapperKind;
  end;

  TMsxPortRead = function(Port: Byte): Byte of object;
  TMsxPortWrite = procedure(Port: Byte; Value: Byte) of object;

  { The 256 ports, each with an optional reader and writer. An unhandled
    read gives FFh }
  TMsxIO = class
  private
    FReaders: array[0..255] of TMsxPortRead;
    FWriters: array[0..255] of TMsxPortWrite;
  public
    procedure Clear;
    procedure Map(First, Count: Integer; AReader: TMsxPortRead; AWriter: TMsxPortWrite);
    function Read(Port: Byte): Byte;
    procedure Write(Port: Byte; Value: Byte);
  end;

  { The slots: 4 primary, each either a single slot or expanded into 4 }
  TMsxSlots = class
  private
    FDevices: array[0..3, 0..3] of TMsxDevice;   // [primary, secondary]
    FExpanded: array[0..3] of Boolean;
    FPrimaryReg: Byte;                           // port A8h
    FSecondaryReg: array[0..3] of Byte;          // register FFFFh of each expanded slot
    FEmpty: TMsxEmpty;
    function Resolve(Addr: Word): TMsxDevice;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Reset;
    procedure Wipe;
    { Installs a device (the slots own it and free it). Sub is ignored in a
      slot that is not expanded }
    procedure Install(Primary, Sub: Integer; Device: TMsxDevice);
    procedure SetExpanded(Primary: Integer; Value: Boolean);
    function IsExpanded(Primary: Integer): Boolean;
    { Frees what is in the four subslots of a primary slot (a device that is in several is freed once) }
    procedure ClearPrimary(Primary: Integer);
    function Read(Addr: Word): Byte;
    function Peek(Addr: Word): Byte;
    procedure Write(Addr: Word; Value: Byte);
    { The slot register (port A8h) }
    procedure SetPrimaryReg(Value: Byte);
    property PrimaryReg: Byte read FPrimaryReg;
    function SecondaryReg(Primary: Integer): Byte;
    procedure SetSecondaryReg(Primary: Integer; Value: Byte);
    { Which primary slot (0-3) and secondary (0-3, or -1 if not expanded) page N shows now }
    function PageSlot(Page: Integer): Integer;
    function PageSub(Page: Integer): Integer;
    function DeviceAt(Addr: Word): TMsxDevice;
    { The device installed in a slot, whatever the pages show (nil if none) }
    function DeviceAtSlot(Primary, Sub: Integer): TMsxDevice;
    { For the debugger: "3-2 Mapper RAM +0C000" }
    function Describe(Addr: Word): string;
  end;

{ Which mapper a ROM of Size bytes seems to use: up to 32K none; above, by the
  writes to the mapper's registers that its code does (LD (nnnn),A) }
function GuessMapper(const Data; Size: Integer): TMsxMapperKind;
function MapperName(K: TMsxMapperKind): string;
{ 'auto' is not a mapper: returns False for it (and for names it does not know) }
function MapperFromName(const S: string; out K: TMsxMapperKind): Boolean;

implementation

uses
  SysUtils, Lang;

{ TMsxDevice }

constructor TMsxDevice.Create(const AName: string; AKind: TMsxDeviceKind);
begin
  inherited Create;
  FName := AName;
  FKind := AKind;
end;

function TMsxDevice.Read(Addr: Word): Byte;
begin
  Result := $FF;
end;

function TMsxDevice.Peek(Addr: Word): Byte;
begin
  Result := Read(Addr);
end;

procedure TMsxDevice.Write(Addr: Word; Value: Byte);
begin
end;

procedure TMsxDevice.Reset;
begin
end;

procedure TMsxDevice.Wipe;
begin
end;

function TMsxDevice.PhysicalOffset(Addr: Word): Integer;
begin
  Result := -1;
end;

function TMsxDevice.RawData: PByte;
begin
  Result := nil;
end;

function TMsxDevice.RawSize: Integer;
begin
  Result := 0;
end;

{ TMsxEmpty }

constructor TMsxEmpty.Create;
begin
  inherited Create('empty', mkEmpty);
end;

{ TMsxRom }

constructor TMsxRom.Create(const AName: string; const AData; ASize: Integer; ABase: Word);
begin
  inherited Create(AName, mkRom);
  SetLength(FData, ASize);
  if ASize > 0 then Move(AData, FData[0], ASize);
  FBase := ABase;
end;

function TMsxRom.Read(Addr: Word): Byte;
var
  O: Integer;
begin
  O := Integer(Addr) - FBase;
  if (O >= 0) and (O < Length(FData)) then Result := FData[O] else Result := $FF;
end;

function TMsxRom.PhysicalOffset(Addr: Word): Integer;
begin
  Result := Integer(Addr) - FBase;
  if (Result < 0) or (Result >= Length(FData)) then Result := -1;
end;

function TMsxRom.RawData: PByte;
begin
  if Length(FData) > 0 then Result := @FData[0] else Result := nil;
end;

function TMsxRom.RawSize: Integer;
begin
  Result := Length(FData);
end;

function TMsxRom.Size: Integer;
begin
  Result := Length(FData);
end;

{ TMsxRam }

constructor TMsxRam.Create(const AName: string; ASize: Integer; ABase: Word);
begin
  inherited Create(AName, mkRam);
  SetLength(FData, ASize);
  FBase := ABase;
  Reset;
end;

function TMsxRam.Read(Addr: Word): Byte;
var
  O: Integer;
begin
  O := Integer(Addr) - FBase;
  if (O >= 0) and (O < Length(FData)) then Result := FData[O] else Result := $FF;
end;

procedure TMsxRam.Write(Addr: Word; Value: Byte);
var
  O: Integer;
begin
  O := Integer(Addr) - FBase;
  if (O >= 0) and (O < Length(FData)) then FData[O] := Value;
end;

procedure TMsxRam.Reset;
begin
  { RAM keeps its contents over a reset on a real MSX, the BIOS clears what it uses;
    only a fresh machine starts with zeros }
end;

procedure TMsxRam.Wipe;
begin
  if Length(FData) > 0 then FillChar(FData[0], Length(FData), 0);
end;

function TMsxRam.PhysicalOffset(Addr: Word): Integer;
begin
  Result := Integer(Addr) - FBase;
  if (Result < 0) or (Result >= Length(FData)) then Result := -1;
end;

function TMsxRam.Size: Integer;
begin
  Result := Length(FData);
end;

{ TMsxMapper }

constructor TMsxMapper.Create(ASegments: Integer);
begin
  inherited Create;
  if (ASegments < 1) or (ASegments > MSX_SEGMENT_MAX) or ((ASegments and (ASegments - 1)) <> 0) then
    raise Exception.CreateFmt(_('Memory mapper size must be a power of 2 up to %d segments'), [MSX_SEGMENT_MAX]);
  FSegments := ASegments;
  Reset;
end;

procedure TMsxMapper.Reset;
const
  { The segments the MSX-DOS 2 and BIOS expect after a reset: 3, 2, 1, 0 for pages 0..3 }
  Initial: array[0..3] of Byte = (3, 2, 1, 0);
var
  I: Integer;
begin
  for I := 0 to 3 do FReg[I] := Initial[I] and (FSegments - 1);
end;

procedure TMsxMapper.WritePort(Port: Byte; Value: Byte);
begin
  FReg[Port and 3] := Value and (FSegments - 1);
end;

function TMsxMapper.ReadPort(Port: Byte): Byte;
begin
  Result := FReg[Port and 3] or Byte(not (FSegments - 1));
end;

function TMsxMapper.Segment(Page: Integer): Integer;
begin
  Result := FReg[Page and 3];
end;

{ TMsxMapperRam }

constructor TMsxMapperRam.Create(AMapper: TMsxMapper);
begin
  inherited Create('Mapper RAM', mkMapperRam);
  FMapper := AMapper;
  SetLength(FData, AMapper.Segments * MSX_PAGE_SIZE);
end;

constructor TMsxMapperRam.CreateMirror(AOther: TMsxMapperRam);
begin
  inherited Create('Mapper RAM', mkMapperRam);
  FMapper := AOther.FMapper;
  FData := AOther.FData;
end;

function TMsxMapperRam.PhysicalOffset(Addr: Word): Integer;
begin
  Result := FMapper.Segment(Addr shr 14) * MSX_PAGE_SIZE + (Addr and (MSX_PAGE_SIZE - 1));
end;

function TMsxMapperRam.Read(Addr: Word): Byte;
begin
  Result := FData[PhysicalOffset(Addr)];
end;

procedure TMsxMapperRam.Write(Addr: Word; Value: Byte);
begin
  FData[PhysicalOffset(Addr)] := Value;
end;

procedure TMsxMapperRam.Reset;
begin
  FMapper.Reset;
end;

procedure TMsxMapperRam.Wipe;
begin
  FillChar(FData[0], Length(FData), 0);
end;

{ TMsxMegaRom }


constructor TMsxMegaRom.Create(const AName: string; AKind: TMsxMapperKind; const AData; ASize: Integer);
begin
  inherited Create(AName, mkCartridge);
  FMapperKind := AKind;
  SetLength(FData, ASize);
  if ASize > 0 then Move(AData, FData[0], ASize);
  FBanks := (ASize + $1FFF) div $2000;
  if FBanks < 1 then FBanks := 1;
  Reset;
end;

procedure TMsxMegaRom.Reset;
var
  I: Integer;
begin
  for I := 0 to 3 do FBank[I] := I mod FBanks;
end;

procedure TMsxMegaRom.SetBank(Region, Value: Integer);
begin
  FBank[Region] := Value mod FBanks;
end;

function TMsxMegaRom.RawData: PByte;
begin
  if Length(FData) > 0 then Result := @FData[0] else Result := nil;
end;

function TMsxMegaRom.RawSize: Integer;
begin
  Result := Length(FData);
end;

function TMsxMegaRom.PhysicalOffset(Addr: Word): Integer;
begin
  if (Addr < $4000) or (Addr >= $C000) then Exit(-1);
  Result := FBank[(Addr - $4000) shr 13] * $2000 + (Addr and $1FFF);
  if Result >= Length(FData) then Result := -1;
end;

function TMsxMegaRom.Read(Addr: Word): Byte;
var
  O: Integer;
begin
  O := PhysicalOffset(Addr);
  if O >= 0 then Result := FData[O] else Result := $FF;
end;

procedure TMsxMegaRom.Write(Addr: Word; Value: Byte);
var
  B: Integer;
begin
  if (Addr < $4000) or (Addr >= $C000) then Exit;
  case FMapperKind of
    mpKonami:
      if Addr >= $6000 then SetBank((Addr - $4000) shr 13, Value);
    mpKonamiScc:
      case Addr and $F800 of
        $5000: SetBank(0, Value);
        $7000: SetBank(1, Value);
        $9000: SetBank(2, Value);
        $B000: SetBank(3, Value);
      end;
    mpAscii8:
      case Addr and $F800 of
        $6000: SetBank(0, Value);
        $6800: SetBank(1, Value);
        $7000: SetBank(2, Value);
        $7800: SetBank(3, Value);
      end;
    mpAscii16:
      case Addr and $F800 of
        $6000:
          begin
            B := (Value * 2) mod FBanks;
            FBank[0] := B;
            FBank[1] := (B + 1) mod FBanks;
          end;
        $7000:
          begin
            B := (Value * 2) mod FBanks;
            FBank[2] := B;
            FBank[3] := (B + 1) mod FBanks;
          end;
      end;
  end;
end;

function MapperName(K: TMsxMapperKind): string;
const
  Names: array[TMsxMapperKind] of string = ('plain', 'konami', 'konamiscc', 'ascii8', 'ascii16');
begin
  Result := Names[K];
end;

function MapperFromName(const S: string; out K: TMsxMapperKind): Boolean;
var
  M: TMsxMapperKind;
begin
  for M := Low(TMsxMapperKind) to High(TMsxMapperKind) do
    if LowerCase(S) = MapperName(M) then
    begin
      K := M;
      Exit(True);
    end;
  Result := False;
end;

function GuessMapper(const Data; Size: Integer): TMsxMapperKind;
var
  B: PByte;
  I: Integer;
  Addr: Word;
  KonamiOnly, SccOnly, A8Only, W5000, W6000, W7000: Integer;
begin
  Result := mpPlain;
  if Size <= 32768 then Exit;
  B := @Data;
  KonamiOnly := 0;       // writes only the Konami type does (8000h, A000h)
  SccOnly := 0;          // only the SCC type (5000h, 9000h, B000h)
  A8Only := 0;           // only ASCII8 (6800h, 7800h)
  W5000 := 0;            // the SCC type writes 5000h, 7000h, 9000h and B000h
  W6000 := 0;
  W7000 := 0;            // the ones ASCII16 uses (and ASCII8 too)
  for I := 0 to Size - 4 do
    if B[I] = $32 then      // LD (nnnn),A
    begin
      Addr := B[I + 1] or (B[I + 2] shl 8);
      case Addr of
        $6000: Inc(W6000);
        $7000, $77FF: Inc(W7000);
        $8000, $A000: Inc(KonamiOnly);
        $6800, $7800: Inc(A8Only);
        $5000: begin Inc(W5000); Inc(SccOnly); end;
        $9000, $B000: Inc(SccOnly);
      end;
    end;
  if (W5000 > 0) and (SccOnly > KonamiOnly) and (SccOnly > A8Only) then Result := mpKonamiScc
  else if A8Only > 0 then Result := mpAscii8
  else if KonamiOnly > 0 then Result := mpKonami
  else if (Size and (Size - 1)) <> 0 then Result := mpKonami      // 48K, 96K...: not made of 16K banks
  else if (W6000 > 0) or (W7000 > 0) then Result := mpAscii16
  else Result := mpKonami;
end;

{ TMsxIO }

procedure TMsxIO.Clear;
var
  I: Integer;
begin
  for I := 0 to 255 do
  begin
    FReaders[I] := nil;
    FWriters[I] := nil;
  end;
end;

procedure TMsxIO.Map(First, Count: Integer; AReader: TMsxPortRead; AWriter: TMsxPortWrite);
var
  I: Integer;
begin
  for I := First to First + Count - 1 do
  begin
    FReaders[I and 255] := AReader;
    FWriters[I and 255] := AWriter;
  end;
end;

function TMsxIO.Read(Port: Byte): Byte;
begin
  if Assigned(FReaders[Port]) then Result := FReaders[Port](Port) else Result := $FF;
end;

procedure TMsxIO.Write(Port: Byte; Value: Byte);
begin
  if Assigned(FWriters[Port]) then FWriters[Port](Port, Value);
end;

{ TMsxSlots }

constructor TMsxSlots.Create;
var
  P, S: Integer;
begin
  inherited Create;
  FEmpty := TMsxEmpty.Create;
  for P := 0 to 3 do
    for S := 0 to 3 do FDevices[P, S] := FEmpty;
end;

destructor TMsxSlots.Destroy;
var
  P, S, K: Integer;
  D: TMsxDevice;
begin
  { A device can sit in several slots or pages; free each object once }
  for P := 0 to 3 do
    for S := 0 to 3 do
    begin
      D := FDevices[P, S];
      if (D <> nil) and (D <> FEmpty) then
      begin
        for K := P * 4 + S + 1 to 15 do
          if FDevices[K div 4, K mod 4] = D then FDevices[K div 4, K mod 4] := nil;
        D.Free;
      end;
    end;
  FEmpty.Free;
  inherited Destroy;
end;

procedure TMsxSlots.Reset;
var
  P, S: Integer;
begin
  FPrimaryReg := 0;
  for P := 0 to 3 do FSecondaryReg[P] := 0;
  for P := 0 to 3 do
    for S := 0 to 3 do
      if (FDevices[P, S] <> nil) then FDevices[P, S].Reset;
end;

procedure TMsxSlots.Wipe;
var
  P, S: Integer;
begin
  for P := 0 to 3 do
    for S := 0 to 3 do
      if FDevices[P, S] <> nil then FDevices[P, S].Wipe;
end;

procedure TMsxSlots.ClearPrimary(Primary: Integer);
var
  S, K: Integer;
  D: TMsxDevice;
begin
  Primary := Primary and 3;
  for S := 0 to 3 do
  begin
    D := FDevices[Primary, S];
    if (D <> nil) and (D <> FEmpty) then
    begin
      for K := S + 1 to 3 do
        if FDevices[Primary, K] = D then FDevices[Primary, K] := nil;
      D.Free;
    end;
    FDevices[Primary, S] := nil;
  end;
end;

procedure TMsxSlots.SetExpanded(Primary: Integer; Value: Boolean);
begin
  FExpanded[Primary and 3] := Value;
end;

function TMsxSlots.IsExpanded(Primary: Integer): Boolean;
begin
  Result := FExpanded[Primary and 3];
end;

procedure TMsxSlots.Install(Primary, Sub: Integer; Device: TMsxDevice);
begin
  Primary := Primary and 3;
  if not FExpanded[Primary] then Sub := 0;
  Sub := Sub and 3;
  if (FDevices[Primary, Sub] <> nil) and (FDevices[Primary, Sub] <> FEmpty) and
     (FDevices[Primary, Sub] <> Device) then
    FDevices[Primary, Sub].Free;
  FDevices[Primary, Sub] := Device;
end;

function TMsxSlots.PageSlot(Page: Integer): Integer;
begin
  Result := (FPrimaryReg shr ((Page and 3) * 2)) and 3;
end;

function TMsxSlots.PageSub(Page: Integer): Integer;
var
  P: Integer;
begin
  P := PageSlot(Page);
  if FExpanded[P] then Result := (FSecondaryReg[P] shr ((Page and 3) * 2)) and 3
  else Result := -1;
end;

function TMsxSlots.Resolve(Addr: Word): TMsxDevice;
var
  Page, P, S: Integer;
begin
  Page := Addr shr 14;
  P := PageSlot(Page);
  S := PageSub(Page);
  if S < 0 then S := 0;
  Result := FDevices[P, S];
  if Result = nil then Result := FEmpty;
end;

function TMsxSlots.DeviceAtSlot(Primary, Sub: Integer): TMsxDevice;
begin
  Result := FDevices[Primary and 3, Sub and 3];
  if Result = FEmpty then Result := nil;
end;

function TMsxSlots.DeviceAt(Addr: Word): TMsxDevice;
begin
  Result := Resolve(Addr);
end;

function TMsxSlots.Read(Addr: Word): Byte;
begin
  if (Addr = $FFFF) and FExpanded[PageSlot(3)] then
    Result := not FSecondaryReg[PageSlot(3)]
  else
    Result := Resolve(Addr).Read(Addr);
end;

function TMsxSlots.Peek(Addr: Word): Byte;
begin
  if (Addr = $FFFF) and FExpanded[PageSlot(3)] then
    Result := not FSecondaryReg[PageSlot(3)]
  else
    Result := Resolve(Addr).Peek(Addr);
end;

procedure TMsxSlots.Write(Addr: Word; Value: Byte);
begin
  if (Addr = $FFFF) and FExpanded[PageSlot(3)] then
    FSecondaryReg[PageSlot(3)] := Value
  else
    Resolve(Addr).Write(Addr, Value);
end;

procedure TMsxSlots.SetPrimaryReg(Value: Byte);
begin
  FPrimaryReg := Value;
end;

function TMsxSlots.SecondaryReg(Primary: Integer): Byte;
begin
  Result := FSecondaryReg[Primary and 3];
end;

procedure TMsxSlots.SetSecondaryReg(Primary: Integer; Value: Byte);
begin
  if FExpanded[Primary and 3] then FSecondaryReg[Primary and 3] := Value;
end;

function TMsxSlots.Describe(Addr: Word): string;
var
  Page, P, S, Off: Integer;
  D: TMsxDevice;
begin
  Page := Addr shr 14;
  P := PageSlot(Page);
  S := PageSub(Page);
  D := Resolve(Addr);
  if S >= 0 then Result := Format('%d-%d %s', [P, S, D.Name])
  else Result := Format('%d %s', [P, D.Name]);
  Off := D.PhysicalOffset(Addr);
  if Off >= 0 then Result := Result + Format(' +%.5X', [Off]);
end;

end.

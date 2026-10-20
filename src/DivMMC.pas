{ DivMMC: the DivMMC interface. 8K of EEPROM (the firmware, e.g. ESXDOS),
  128K of RAM in 16 banks of 8K, an SD card on SPI and automatic paging.

  Ports (low byte decoded):
    E3  control (write): bit 7 CONMEM (map now, EEPROM at 0000), bit 6
        MAPRAM (bank 3 replaces the EEPROM, read-only; can't be cleared
        until power off), bits 0-3 the RAM bank at 2000-3FFF
    E7  card select (write): bit 0 low selects the card
    EB  SPI data (read and write)

  When mapped, 0000-1FFF holds the EEPROM (or RAM bank 3 with MAPRAM) and
  2000-3FFF the selected RAM bank. Mapping happens automatically on opcode
  fetches: at once at 3D00-3DFF, and after the fetch at 0000, 0008, 0038,
  0066, 04C6 and 0562; unmapping after a fetch at 1FF8-1FFF. }
unit DivMMC;

{$mode objfpc}{$H+}
{$R-}{$Q-}

interface

uses
  SysUtils, Classes, SDCard;

const
  DIVMMC_BANKS = 16;

type
  { Its memory and paging, for the debugger's step back }
  TDivState = record
    Ram: array[0..DIVMMC_BANKS - 1, 0..$1FFF] of Byte;
    Control: Byte;
    Mapped: Boolean;
  end;

  TDivMMC = class
  private
    FRom: array[0..$1FFF] of Byte;
    FRam: array[0..DIVMMC_BANKS - 1, 0..$1FFF] of Byte;
    FControl: Byte;
    FMapped: Boolean;
    FCard: TSDCard;
    FRomLoaded: Boolean;
    FExtRom: PByte;      // memory of the machine used instead (ZX-Uno), or nil
    FExtRam: PByte;
    function GetActive: Boolean; inline;
    function RomPtr: PByte; inline;
    function BankPtr(Bank: Integer): PByte; inline;
  public
    constructor Create;
    destructor Destroy; override;
    { The firmware (an 8K EEPROM image) }
    procedure LoadRom(const FileName: string);
    { The firmware from memory (8K): the ZX-Uno keeps it in its SRAM }
    procedure LoadRomData(Data: PByte);
    { The ZX-Uno keeps the DivMMC's memory in its SRAM: the firmware (8K)
      at Rom and the 16 RAM banks (128K) at Ram; nil = its own }
    procedure UseMemory(Rom, Ram: PByte);
    { Power on (Hard) or reset: unmapped; MAPRAM survives a reset }
    procedure Reset(Hard: Boolean);
    { Memory at Addr (0000-3FFF) while Active }
    function Read(Addr: Word): Byte; inline;
    procedure Write(Addr: Word; Value: Byte);
    { While Active: Addr (0000-3FFF) can't be written (the EEPROM, or bank 3
      with MAPRAM); ForceWrite writes it anyway (debugger, ROM edits on) }
    function ReadOnlyAt(Addr: Word): Boolean;
    procedure ForceWrite(Addr: Word; Value: Byte);
    { Automatic paging around an opcode fetch at Addr }
    procedure BeforeFetch(Addr: Word); inline;
    procedure AfterFetch(Addr: Word); inline;
    { Ports E3, E7, EB }
    function IsPort(Port: Word): Boolean; inline;
    function ReadPort(Port: Word): Byte;
    procedure WritePort(Port: Word; Value: Byte);
    { SD card: an image file, or none }
    procedure InsertCard(const FileName: string);
    procedure EjectCard;
    property Card: TSDCard read FCard;
    { Mapped in now (automatically or with CONMEM) }
    property Active: Boolean read GetActive;
    property Control: Byte read FControl;
    { Debugger: change the control register (MAPRAM still can't be cleared)
      and the automatic paging state }
    procedure SetControl(Value: Byte);
    property Mapped: Boolean read FMapped write FMapped;
    property RomLoaded: Boolean read FRomLoaded;
    { Debugger: its state, saved and put back (its RAM only when it has its
      own: the ZX-Uno's is in the machine's SRAM) }
    procedure SaveState(var S: TDivState);
    procedure LoadState(const S: TDivState);
  public
    { Port E3 can be read back (the ZX Spectrum Next's DivMMC) }
    ControlReadable: Boolean;
    { The Next's programmable entry points (NR B8-BB) instead of the fixed
      ones: which addresses map it in, whether only with ROM 3 (48K BASIC)
      paged in (Rom3: it is), and instantly or after the opcode fetch }
    NextEntries: Boolean;
    Entry0, Valid0, Timing0, Entry1: Byte;
    Rom3: Boolean;
    { The Next's Multiface is paged in over it: it isn't seen meanwhile }
    Hidden: Boolean;
    { The Next's DRIVE button was pressed: 0066 maps it in (NR BB bits 1-0) }
    NmiButton: Boolean;
  end;

implementation

constructor TDivMMC.Create;
begin
  inherited Create;
  FillChar(FRom, SizeOf(FRom), $FF);
  Reset(True);
end;

destructor TDivMMC.Destroy;
begin
  FCard.Free;
  inherited Destroy;
end;

procedure TDivMMC.LoadRom(const FileName: string);
var
  S: TFileStream;
begin
  S := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    FillChar(FRom, SizeOf(FRom), $FF);
    S.Read(FRom, SizeOf(FRom));
  finally
    S.Free;
  end;
  FRomLoaded := True;
end;

procedure TDivMMC.LoadRomData(Data: PByte);
begin
  Move(Data^, FRom, SizeOf(FRom));
  FRomLoaded := True;
end;

procedure TDivMMC.UseMemory(Rom, Ram: PByte);
begin
  FExtRom := Rom;
  FExtRam := Ram;
  if Rom <> nil then FRomLoaded := True;
end;

function TDivMMC.RomPtr: PByte;
begin
  if FExtRom <> nil then Result := FExtRom else Result := @FRom[0];
end;

function TDivMMC.BankPtr(Bank: Integer): PByte;
begin
  if FExtRam <> nil then Result := FExtRam + Bank * $2000 else Result := @FRam[Bank, 0];
end;

procedure TDivMMC.Reset(Hard: Boolean);
begin
  if Hard then
  begin
    FControl := 0;
    if FExtRam = nil then FillChar(FRam, SizeOf(FRam), 0);
  end
  else
    FControl := FControl and $40;
  FMapped := False;
  Hidden := False;
  NmiButton := False;
end;

function TDivMMC.GetActive: Boolean;
begin
  Result := (FMapped or ((FControl and $80) <> 0)) and not Hidden;
end;

function TDivMMC.Read(Addr: Word): Byte;
begin
  if Addr < $2000 then
  begin
    if ((FControl and $80) = 0) and ((FControl and $40) <> 0) then
      Result := BankPtr(3)[Addr]
    else
      Result := RomPtr[Addr];
  end
  else
    Result := BankPtr(FControl and $0F)[Addr and $1FFF];
end;

procedure TDivMMC.Write(Addr: Word; Value: Byte);
var
  Bank: Integer;
begin
  // 0000-1FFF is the EEPROM (write-protected) or the read-only bank 3
  if Addr < $2000 then Exit;
  Bank := FControl and $0F;
  if ((FControl and $C0) = $40) and (Bank = 3) then Exit;   // MAPRAM: bank 3 is read-only
  BankPtr(Bank)[Addr and $1FFF] := Value;
end;

function TDivMMC.ReadOnlyAt(Addr: Word): Boolean;
begin
  if Addr < $2000 then Result := True
  else Result := ((FControl and $C0) = $40) and ((FControl and $0F) = 3);
end;

procedure TDivMMC.ForceWrite(Addr: Word; Value: Byte);
begin
  if Addr < $2000 then
  begin
    if ((FControl and $80) = 0) and ((FControl and $40) <> 0) then BankPtr(3)[Addr] := Value
    else RomPtr[Addr] := Value;
  end
  else
    BankPtr(FControl and $0F)[Addr and $1FFF] := Value;
end;

procedure TDivMMC.BeforeFetch(Addr: Word);
var
  Bit: Byte;
begin
  if NextEntries then
  begin
    // RST addresses 0000-0038 set to map instantly; 3Dxx (TR-DOS)
    if (Addr and $FFC7) = 0 then
    begin
      Bit := 1 shl (Addr shr 3);
      if ((Entry0 and Bit) <> 0) and (((Valid0 and Bit) <> 0) or Rom3) and ((Timing0 and Bit) <> 0) then
        FMapped := True;
    end
    else if ((Addr and $FF00) = $3D00) and ((Entry1 and $80) <> 0) and Rom3 then
      FMapped := True
    else if (Addr = $0066) and NmiButton and ((Entry1 and 2) <> 0) then
      FMapped := True;
    Exit;
  end;
  // ROM 3Dxx (the TR-DOS entry points): mapped before the opcode is read
  if (Addr and $FF00) = $3D00 then FMapped := True;
end;

procedure TDivMMC.AfterFetch(Addr: Word);
var
  Bit: Byte;
begin
  if NextEntries then
  begin
    case Addr of
      $0000, $0008, $0010, $0018, $0020, $0028, $0030, $0038:
        begin
          Bit := 1 shl (Addr shr 3);
          if ((Entry0 and Bit) <> 0) and (((Valid0 and Bit) <> 0) or Rom3) and ((Timing0 and Bit) = 0) then
            FMapped := True;
        end;
      $04C6: if ((Entry1 and $04) <> 0) and Rom3 then FMapped := True;
      $0562: if ((Entry1 and $08) <> 0) and Rom3 then FMapped := True;
      $04D7: if ((Entry1 and $10) <> 0) and Rom3 then FMapped := True;
      $056A: if ((Entry1 and $20) <> 0) and Rom3 then FMapped := True;
      // 0066 maps only with the NMI (DRIVE) button
      $0066: if NmiButton and ((Entry1 and 1) <> 0) then FMapped := True;
      $1FF8..$1FFF: if (Entry1 and $40) <> 0 then FMapped := False;
    end;
    Exit;
  end;
  case Addr of
    $0000, $0008, $0038, $0066, $04C6, $0562: FMapped := True;
    $1FF8..$1FFF: FMapped := False;
  end;
end;

procedure TDivMMC.SaveState(var S: TDivState);
begin
  if FExtRam = nil then Move(FRam, S.Ram, SizeOf(FRam));
  S.Control := FControl;
  S.Mapped := FMapped;
end;

procedure TDivMMC.LoadState(const S: TDivState);
begin
  if FExtRam = nil then Move(S.Ram, FRam, SizeOf(FRam));
  FControl := S.Control;
  FMapped := S.Mapped;
end;

procedure TDivMMC.SetControl(Value: Byte);
begin
  FControl := Value or (FControl and $40);
end;

function TDivMMC.IsPort(Port: Word): Boolean;
begin
  Result := ((Port and $FF) = $E3) or ((Port and $FF) = $E7) or ((Port and $FF) = $EB);
end;

function TDivMMC.ReadPort(Port: Word): Byte;
begin
  if ((Port and $FF) = $EB) and (FCard <> nil) then
    Result := FCard.ReadByte
  else if ((Port and $FF) = $E3) and ControlReadable then
    Result := FControl
  else
    Result := $FF;
end;

procedure TDivMMC.WritePort(Port: Word; Value: Byte);
begin
  case Port and $FF of
    $E3: FControl := Value or (FControl and $40);   // MAPRAM can't be cleared
    $E7: if FCard <> nil then FCard.Select((Value and 1) = 0);
    $EB: if FCard <> nil then FCard.WriteByte(Value);
  end;
end;

procedure TDivMMC.InsertCard(const FileName: string);
var
  NewCard: TSDCard;
begin
  NewCard := TSDCard.Create(FileName);   // raises if it can't be opened
  FCard.Free;
  FCard := NewCard;
end;

procedure TDivMMC.EjectCard;
begin
  FreeAndNil(FCard);
end;

end.

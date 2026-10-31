{ Symbols: address labels for the debugger. Reads the symbol files exported
  by SjASM / SjASMPlus ("NAME: EQU 0x00008000"), and also accepts "NAME equ
  8000h", "NAME = $8000", "#8000" and decimal values. }
unit Symbols;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, Models;

type
  TSymbolTable = class
  private
    FNames: array of string;   // indexed by address
    FMore: array of string;    // other names at the same address, ', ' separated
    FCount: Integer;
    FFileName: string;
  public
    constructor Create;
    procedure Clear;
    { Adds the symbols of a file within an address range; returns how many
      were read. }
    function LoadFromFile(const FileName: string; MinAddr: Integer = 0;
      MaxAddr: Integer = $FFFF): Integer;
    { Address of a symbol (case-insensitive); False if not found. }
    function Find(const Name: string; out Addr: Word): Boolean;
    procedure Add(Addr: Word; const Name: string);
    { The name at Addr, replacing any; '' removes it }
    procedure SetName(Addr: Word; const Name: string);
    function Lookup(Addr: Word): string;
    { Every name at Addr, ', ' separated ('' if none) }
    function LookupAll(Addr: Word): string;
    property Count: Integer read FCount;
    property FileName: string read FFileName;
  end;

  { Labels for the ROMs of a model: roms/<rom file>.sym, plus roms/48.sym for
    the 48K BASIC ROM. ROM labels apply only while that ROM is paged in; RAM
    labels (system variables) apply always. On the Amstrad CPC the ROM at
    0000-3FFF is the lower ROM and the one at C000-FFFF the upper ROM (BASIC):
    labels in either apply only while that ROM is switched in (BASIC or, on the
    models with a disc drive, AMSDOS, which has its own file), whereas the ones
    in 4000-BFFF (firmware jumpblock and variables) apply always. }
  TRomSymbolSet = class
  private
    FRoms: array[0..3] of TSymbolTable;
    FRam: TSymbolTable;
    FUpper: array[1..2] of TSymbolTable;   // CPC: labels at C000-FFFF of the upper ROMs (1 BASIC, 2 AMSDOS)
    FCpc: Boolean;
    FLoadedKey: string;
  public
    { CPC: the upper ROM switched in at C000-FFFF, 1 BASIC and 2 AMSDOS, 0 none (set by who looks labels up) }
    UpperRom: Integer;
    constructor Create;
    destructor Destroy; override;
    { Load the labels for a model; does nothing if they are already loaded. }
    procedure Load(const RomDir: string; const Info: TModelInfo); overload;
    { RomPaths: the ROM files in use. A ROM's labels come from the .sym file
      next to it; the 48K BASIC labels only apply to the standard ROMs. }
    procedure Load(const RomDir: string; const Info: TModelInfo;
      const RomPaths: array of string); overload;
    { RomIndex: ROM paged at 0000-3FFF, or -1 if RAM is there. }
    function Lookup(Addr: Word; RomIndex: Integer): string;
    { Every name at Addr, ', ' separated }
    function LookupAll(Addr: Word; RomIndex: Integer): string;
    function Find(const Name: string; RomIndex: Integer; out Addr: Word): Boolean;
  end;

var
  RomLabels: TRomSymbolSet;
  { Symbols loaded by the user (command line or Debug menu) }
  UserSymbols: TSymbolTable;

{ Parse one symbol file line. Returns False for comments and other lines. }
function ParseSymbolLine(const Line: string; out Name: string; out Value: Integer): Boolean;

implementation

function ParseNumber(S: string; out Value: Integer): Boolean;
var
  Base: Integer;
  V: Int64;
  Ch: Char;
  Digit: Integer;
begin
  Result := False;
  S := UpperCase(Trim(S));
  if S = '' then Exit;
  Base := 10;
  if Copy(S, 1, 2) = '0X' then begin Delete(S, 1, 2); Base := 16; end
  else if (S[1] = '$') or (S[1] = '#') then begin Delete(S, 1, 1); Base := 16; end
  else if S[Length(S)] = 'H' then begin Delete(S, Length(S), 1); Base := 16; end;
  if S = '' then Exit;
  V := 0;
  for Digit := 1 to Length(S) do
  begin
    Ch := S[Digit];
    case Ch of
      '0'..'9': V := V * Base + Ord(Ch) - Ord('0');
      'A'..'F': if Base = 16 then V := V * Base + Ord(Ch) - Ord('A') + 10 else Exit;
    else
      Exit;
    end;
    if V > $FFFFFFFF then Exit;
  end;
  Value := V and $FFFF;
  Result := True;
end;

function ParseSymbolLine(const Line: string; out Name: string; out Value: Integer): Boolean;
var
  S, Rest: string;
  P: Integer;
begin
  Result := False;
  S := Line;
  P := Pos(';', S);
  if P > 0 then S := Copy(S, 1, P - 1);
  S := Trim(S);
  if S = '' then Exit;
  // Name: letters, digits, _ . @ ? ! (SjASMPlus local labels contain dots)
  P := 1;
  while (P <= Length(S)) and (S[P] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '.', '@', '?', '!']) do
    Inc(P);
  if (P = 1) or (S[1] in ['0'..'9']) then Exit;
  Name := Copy(S, 1, P - 1);
  Rest := Trim(Copy(S, P, MaxInt));
  if (Rest <> '') and (Rest[1] = ':') then Rest := Trim(Copy(Rest, 2, MaxInt));
  if UpperCase(Copy(Rest, 1, 3)) = 'EQU' then
    Rest := Copy(Rest, 4, MaxInt)
  else if (Rest <> '') and (Rest[1] = '=') then
    Rest := Copy(Rest, 2, MaxInt);
  Result := ParseNumber(Rest, Value);
end;

{ TSymbolTable }

constructor TSymbolTable.Create;
begin
  inherited Create;
  SetLength(FNames, $10000);
  SetLength(FMore, $10000);
end;

procedure TSymbolTable.Clear;
var
  I: Integer;
begin
  for I := 0 to $FFFF do
  begin
    FNames[I] := '';
    FMore[I] := '';
  end;
  FCount := 0;
  FFileName := '';
end;

procedure TSymbolTable.Add(Addr: Word; const Name: string);
begin
  // First name is the one shown; the others are only listed by LookupAll
  if FNames[Addr] = '' then
  begin
    FNames[Addr] := Name;
    Inc(FCount);
  end
  else if (UpperCase(FNames[Addr]) <> UpperCase(Name)) and
          (Pos(', ' + UpperCase(Name) + ', ', ', ' + UpperCase(FMore[Addr]) + ', ') = 0) then
  begin
    if FMore[Addr] <> '' then FMore[Addr] := FMore[Addr] + ', ';
    FMore[Addr] := FMore[Addr] + Name;
  end;
end;

procedure TSymbolTable.SetName(Addr: Word; const Name: string);
begin
  if (FNames[Addr] = '') and (Name <> '') then Inc(FCount)
  else if (FNames[Addr] <> '') and (Name = '') then Dec(FCount);
  FNames[Addr] := Name;
  FMore[Addr] := '';
end;

function TSymbolTable.Lookup(Addr: Word): string;
begin
  Result := FNames[Addr];
end;

function TSymbolTable.LookupAll(Addr: Word): string;
begin
  Result := FNames[Addr];
  if (Result <> '') and (FMore[Addr] <> '') then Result := Result + ', ' + FMore[Addr];
end;

function TSymbolTable.Find(const Name: string; out Addr: Word): Boolean;
var
  A: Integer;
  U: string;
begin
  U := UpperCase(Name);
  for A := 0 to $FFFF do
    if (FNames[A] <> '') and (UpperCase(FNames[A]) = U) then
    begin
      Addr := A;
      Exit(True);
    end;
  Result := False;
end;

function TSymbolTable.LoadFromFile(const FileName: string; MinAddr: Integer;
  MaxAddr: Integer): Integer;
var
  Lines: TStringList;
  I, Value: Integer;
  Name: string;
begin
  Result := 0;
  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(FileName);
    for I := 0 to Lines.Count - 1 do
      if ParseSymbolLine(Lines[I], Name, Value) and (Value >= MinAddr) and (Value <= MaxAddr) then
      begin
        Add(Value, Name);
        Inc(Result);
      end;
  finally
    Lines.Free;
  end;
  FFileName := FileName;
end;

{ TRomSymbolSet }

constructor TRomSymbolSet.Create;
var
  I: Integer;
begin
  inherited Create;
  for I := 0 to 3 do FRoms[I] := TSymbolTable.Create;
  FRam := TSymbolTable.Create;
  FUpper[1] := TSymbolTable.Create;
  FUpper[2] := TSymbolTable.Create;
end;

destructor TRomSymbolSet.Destroy;
var
  I: Integer;
begin
  for I := 0 to 3 do FRoms[I].Free;
  FRam.Free;
  FUpper[1].Free;
  FUpper[2].Free;
  inherited Destroy;
end;

procedure TRomSymbolSet.Load(const RomDir: string; const Info: TModelInfo);
var
  Paths: array of string;
  I: Integer;
begin
  SetLength(Paths, Info.RomCount);
  for I := 0 to Info.RomCount - 1 do
    Paths[I] := IncludeTrailingPathDelimiter(RomDir) + Info.RomFiles[I];
  Load(RomDir, Info, Paths);
end;

procedure TRomSymbolSet.Load(const RomDir: string; const Info: TModelInfo;
  const RomPaths: array of string);
var
  I: Integer;
  Dir, FileName, Basic, Key: string;

  procedure LoadFile(const Name: string; Rom: Integer);
  begin
    if not FileExists(Name) then Exit;
    try
      if FCpc then
      begin
        // ROM 0 is the firmware: lower ROM and BASIC; ROM 1 is AMSDOS (upper ROM 2)
        if Rom = 0 then
        begin
          FRoms[0].LoadFromFile(Name, 0, $3FFF);
          FRam.LoadFromFile(Name, 0, $3F);     // the low kernel is in RAM too
        end;
        FRam.LoadFromFile(Name, $4000, $BFFF);
        if Rom <= 1 then FUpper[Rom + 1].LoadFromFile(Name, $C000, $FFFF);
      end
      else if Rom >= 0 then
      begin
        FRoms[Rom].LoadFromFile(Name, 0, $3FFF);
        FRam.LoadFromFile(Name, $4000, $FFFF);
      end
      else
        FRam.LoadFromFile(Name, $4000, $FFFF);
    except
      // labels are optional: ignore unreadable files
    end;
  end;

begin
  Key := RomDir + '|' + Info.Name;
  for I := 0 to High(RomPaths) do Key := Key + '|' + RomPaths[I];
  if FLoadedKey = Key then Exit;
  FLoadedKey := Key;
  for I := 0 to 3 do FRoms[I].Clear;
  FRam.Clear;
  FUpper[1].Clear;
  FUpper[2].Clear;
  FCpc := Info.Memory = mkCPC;
  Dir := IncludeTrailingPathDelimiter(RomDir);
  Basic := Dir + '48.sym';
  // The model's own files first: the first name for an address wins
  for I := 0 to Min(High(RomPaths), 3) do
  begin
    FileName := ChangeFileExt(RomPaths[I], '.sym');
    if FileName <> Basic then LoadFile(FileName, I);
  end;
  // A replaced BASIC ROM has its own labels, if any
  if (Info.Memory <> mkCPC) and (Info.BasicRom <= High(RomPaths)) and
     (RomPaths[Info.BasicRom] = Dir + Info.RomFiles[Info.BasicRom]) then
    LoadFile(Basic, Info.BasicRom);
end;

function TRomSymbolSet.Lookup(Addr: Word; RomIndex: Integer): string;
begin
  if FCpc and (Addr >= $C000) then
  begin
    if (UpperRom >= 1) and (UpperRom <= 2) then Result := FUpper[UpperRom].Lookup(Addr) else Result := '';
  end
  else if (Addr >= $4000) or (FCpc and (Addr < $40)) then
    Result := FRam.Lookup(Addr)
  else if (RomIndex >= 0) and (RomIndex <= 3) then
    Result := FRoms[RomIndex].Lookup(Addr)
  else
    Result := '';
end;

function TRomSymbolSet.LookupAll(Addr: Word; RomIndex: Integer): string;
begin
  if FCpc and (Addr >= $C000) then
  begin
    if (UpperRom >= 1) and (UpperRom <= 2) then Result := FUpper[UpperRom].LookupAll(Addr) else Result := '';
  end
  else if (Addr >= $4000) or (FCpc and (Addr < $40)) then
    Result := FRam.LookupAll(Addr)
  else if (RomIndex >= 0) and (RomIndex <= 3) then
    Result := FRoms[RomIndex].LookupAll(Addr)
  else
    Result := '';
end;

function TRomSymbolSet.Find(const Name: string; RomIndex: Integer; out Addr: Word): Boolean;
begin
  Result := FRam.Find(Name, Addr) or
    (FCpc and (UpperRom >= 1) and (UpperRom <= 2) and FUpper[UpperRom].Find(Name, Addr)) or
    ((RomIndex >= 0) and (RomIndex <= 3) and FRoms[RomIndex].Find(Name, Addr));
end;

initialization
  RomLabels := TRomSymbolSet.Create;
  UserSymbols := TSymbolTable.Create;

finalization
  RomLabels.Free;
  UserSymbols.Free;

end.

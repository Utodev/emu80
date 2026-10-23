{ DebugFiles: breakpoints and watches saved as JSON files, for the
  debuggers (their context menus) and the command line. Addresses and ports
  are hex strings.

  Breakpoints (the Z80 debugger):
    {"emu80": "breakpoints", "version": 1,
     "memory": [{"address": "8000", "type": "exec", "enabled": true,
                 "condition": "A = 3"}, ...],
     "ports":  [{"port": "00FE", "type": "out", "enabled": true,
                 "condition": ""}, ...]}
    memory types: exec, read, write, access; port types: in, out, any.
    A range has an "end" (address or port): one breakpoint over all of it.
  Watches:
    {"emu80": "watches", "version": 1, "watches": ["5C3A", "8000"]}
  DAAD breakpoints (on condacts; "condact" just tells which one it was):
    {"emu80": "daad-breakpoints", "version": 1,
     "breakpoints": [{"address": "8A69", "enabled": true,
                      "condition": "f0 = 3", "condact": "P1 E5 NOUN2 251"}]}
  Loading replaces what there was. }
unit DebugFiles;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, jsonparser, Spectrum;

type
  TWordArray = array of Word;

  TDaadBreakData = record
    Addr: Word;
    Enabled: Boolean;
    Condition: string;
    Condact: string;
  end;
  TDaadBreakDataArray = array of TDaadBreakData;

{ The Z80 breakpoints (memory and ports) of Spec; call with it locked }
procedure SaveBreakpoints(Spec: TSpectrum; const FileName: string);
function LoadBreakpoints(Spec: TSpectrum; const FileName: string; out Error: string): Boolean;
procedure SaveWatches(const Watches: array of Word; const FileName: string);
function LoadWatches(const FileName: string; out Watches: TWordArray; out Error: string): Boolean;
procedure SaveDaadBreaks(const Breaks: TDaadBreakDataArray; const FileName: string);
function LoadDaadBreaks(const FileName: string; out Breaks: TDaadBreakDataArray;
  out Error: string): Boolean;

implementation

const
  MEM_TYPES: array[0..3] of string = ('exec', 'read', 'write', 'access');
  MEM_FLAGS: array[0..3] of Byte = (BP_EXEC, BP_READ, BP_WRITE, BP_READ or BP_WRITE);
  PORT_TYPES: array[0..2] of string = ('in', 'out', 'any');
  PORT_FLAGS: array[0..2] of Byte = (BP_READ, BP_WRITE, BP_READ or BP_WRITE);

procedure SaveJSON(Root: TJSONObject; const FileName: string);
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.Text := Root.FormatJSON;
    L.SaveToFile(FileName);
  finally
    L.Free;
    Root.Free;
  end;
end;

{ The file's JSON, if it is an emu80 file of that kind; nil (and Error) if not }
function LoadJSON(const FileName, Kind: string; out Error: string): TJSONObject;
var
  L: TStringList;
  Data: TJSONData;
begin
  Result := nil;
  Error := '';
  L := TStringList.Create;
  try
    try
      L.LoadFromFile(FileName);
      Data := GetJSON(L.Text);
    except
      on E: Exception do
      begin
        Error := E.Message;
        Exit;
      end;
    end;
  finally
    L.Free;
  end;
  // The files made when it was called pzx say "pzx" instead
  if not (Data is TJSONObject) or ((TJSONObject(Data).Get('emu80', '') <> Kind) and
     (TJSONObject(Data).Get('pzx', '') <> Kind)) then
  begin
    Data.Free;
    Error := Format('not an emu80 %s file', [Kind]);
    Exit;
  end;
  Result := TJSONObject(Data);
end;

function HexValue(const S: string; out V: Word): Boolean;
var
  N: Integer;
begin
  Result := TryStrToInt('$' + Trim(S), N) and (N >= 0) and (N <= $FFFF);
  if Result then V := N;
end;

function TypeIndex(const S: string; const Names: array of string): Integer;
begin
  for Result := 0 to High(Names) do
    if SameText(S, Names[Result]) then Exit;
  Result := -1;
end;

function NewDoc(const Kind: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('emu80', Kind);
  Result.Add('version', 1);
end;

procedure SaveBreakpoints(Spec: TSpectrum; const FileName: string);
var
  Root, Item: TJSONObject;
  Mem, Ports: TJSONArray;
  A, T, Last, PortLast: Integer;
  F: Byte;
begin
  Root := NewDoc('breakpoints');
  Mem := TJSONArray.Create;
  Ports := TJSONArray.Create;
  Root.Add('memory', Mem);
  Root.Add('ports', Ports);
  // A range is one entry, from its first address (the rest are skipped)
  Last := -1;
  PortLast := -1;
  for A := 0 to $FFFF do
  begin
    F := Spec.Breakpoint[A];
    if (A > Last) and ((F and (BP_EXEC or BP_READ or BP_WRITE)) <> 0) then
    begin
      Item := TJSONObject.Create;
      Item.Add('address', IntToHex(A, 4));
      Last := Spec.BreakRangeLast(A, False);
      if Last <> A then Item.Add('end', IntToHex(Last, 4));
      if (F and BP_EXEC) <> 0 then T := 0
      else if (F and (BP_READ or BP_WRITE)) = (BP_READ or BP_WRITE) then T := 3
      else if (F and BP_READ) <> 0 then T := 1
      else T := 2;
      Item.Add('type', MEM_TYPES[T]);
      Item.Add('enabled', (F and BP_DISABLED) = 0);
      Item.Add('condition', Spec.BreakCondition(A));
      Mem.Add(Item);
    end;
    F := Spec.PortBreakpoint[A];
    if (A > PortLast) and ((F and (BP_READ or BP_WRITE)) <> 0) then
    begin
      Item := TJSONObject.Create;
      Item.Add('port', IntToHex(A, 4));
      PortLast := Spec.BreakRangeLast(A, True);
      if PortLast <> A then Item.Add('end', IntToHex(PortLast, 4));
      if (F and (BP_READ or BP_WRITE)) = (BP_READ or BP_WRITE) then T := 2
      else if (F and BP_READ) <> 0 then T := 0
      else T := 1;
      Item.Add('type', PORT_TYPES[T]);
      Item.Add('enabled', (F and BP_DISABLED) = 0);
      Item.Add('condition', Spec.PortBreakCondition(A));
      Ports.Add(Item);
    end;
  end;
  SaveJSON(Root, FileName);
end;

function LoadBreakpoints(Spec: TSpectrum; const FileName: string; out Error: string): Boolean;
type
  TEntry = record
    Addr, Last: Word;
    Flags: Byte;
    Cond: string;
    Port: Boolean;
  end;
var
  Root: TJSONObject;
  Arr: TJSONArray;
  Item: TJSONObject;
  Entries: array of TEntry;
  I, K, T: Integer;
  A, E: Word;
  Err: string;
begin
  Result := False;
  Root := LoadJSON(FileName, 'breakpoints', Error);
  if Root = nil then Exit;
  try
    // Check them all first: a bad file changes nothing
    Entries := nil;
    for K := 0 to 1 do
    begin
      if K = 0 then Arr := Root.Get('memory', TJSONArray(nil))
      else Arr := Root.Get('ports', TJSONArray(nil));
      if Arr = nil then Continue;
      for I := 0 to Arr.Count - 1 do
      begin
        if not (Arr[I] is TJSONObject) then
        begin
          Error := 'an entry is not an object';
          Exit;
        end;
        Item := TJSONObject(Arr[I]);
        if K = 0 then
        begin
          if not HexValue(Item.Get('address', ''), A) then
          begin
            Error := 'bad address: ' + Item.Get('address', '');
            Exit;
          end;
          T := TypeIndex(Item.Get('type', 'exec'), MEM_TYPES);
        end
        else
        begin
          if not HexValue(Item.Get('port', ''), A) then
          begin
            Error := 'bad port: ' + Item.Get('port', '');
            Exit;
          end;
          T := TypeIndex(Item.Get('type', 'any'), PORT_TYPES);
        end;
        if T < 0 then
        begin
          Error := 'bad type: ' + Item.Get('type', '');
          Exit;
        end;
        E := A;
        if (Item.Get('end', '') <> '') and (not HexValue(Item.Get('end', ''), E) or (E < A)) then
        begin
          Error := 'bad end: ' + Item.Get('end', '');
          Exit;
        end;
        SetLength(Entries, Length(Entries) + 1);
        with Entries[High(Entries)] do
        begin
          Addr := A;
          Last := E;
          Port := K = 1;
          if Port then Flags := PORT_FLAGS[T] else Flags := MEM_FLAGS[T];
          if not Item.Get('enabled', True) then Flags := Flags or BP_DISABLED;
          Cond := Item.Get('condition', '');
        end;
      end;
    end;
    Spec.ClearBreakpoints;
    for I := 0 to High(Entries) do
      with Entries[I] do
      begin
        Spec.SetBreakRange(Addr, Last, Port);
        if Port then
        begin
          if Spec.SetPortBreakCondition(Addr, Cond, Err) then Spec.PortBreakpoint[Addr] := Flags
          else Error := Error + Format('port %.4X: %s; ', [Addr, Err]);
        end
        else
        begin
          if Spec.SetBreakCondition(Addr, Cond, Err) then Spec.Breakpoint[Addr] := Flags
          else Error := Error + Format('%.4X: %s; ', [Addr, Err]);
        end;
      end;
    Result := Error = '';
  finally
    Root.Free;
  end;
end;

procedure SaveWatches(const Watches: array of Word; const FileName: string);
var
  Root: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
begin
  Root := NewDoc('watches');
  Arr := TJSONArray.Create;
  Root.Add('watches', Arr);
  for I := 0 to High(Watches) do Arr.Add(IntToHex(Watches[I], 4));
  SaveJSON(Root, FileName);
end;

function LoadWatches(const FileName: string; out Watches: TWordArray; out Error: string): Boolean;
var
  Root: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
  A: Word;
begin
  Result := False;
  Watches := nil;
  Root := LoadJSON(FileName, 'watches', Error);
  if Root = nil then Exit;
  try
    Arr := Root.Get('watches', TJSONArray(nil));
    if Arr <> nil then
      for I := 0 to Arr.Count - 1 do
      begin
        if not HexValue(Arr[I].AsString, A) then
        begin
          Error := 'bad address: ' + Arr[I].AsString;
          Watches := nil;
          Exit;
        end;
        SetLength(Watches, Length(Watches) + 1);
        Watches[High(Watches)] := A;
      end;
    Result := True;
  finally
    Root.Free;
  end;
end;

procedure SaveDaadBreaks(const Breaks: TDaadBreakDataArray; const FileName: string);
var
  Root, Item: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
begin
  Root := NewDoc('daad-breakpoints');
  Arr := TJSONArray.Create;
  Root.Add('breakpoints', Arr);
  for I := 0 to High(Breaks) do
  begin
    Item := TJSONObject.Create;
    Item.Add('address', IntToHex(Breaks[I].Addr, 4));
    Item.Add('enabled', Breaks[I].Enabled);
    Item.Add('condition', Breaks[I].Condition);
    Item.Add('condact', Breaks[I].Condact);
    Arr.Add(Item);
  end;
  SaveJSON(Root, FileName);
end;

function LoadDaadBreaks(const FileName: string; out Breaks: TDaadBreakDataArray;
  out Error: string): Boolean;
var
  Root, Item: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
  A: Word;
begin
  Result := False;
  Breaks := nil;
  Root := LoadJSON(FileName, 'daad-breakpoints', Error);
  if Root = nil then Exit;
  try
    Arr := Root.Get('breakpoints', TJSONArray(nil));
    if Arr <> nil then
      for I := 0 to Arr.Count - 1 do
      begin
        if not (Arr[I] is TJSONObject) then
        begin
          Error := 'an entry is not an object';
          Breaks := nil;
          Exit;
        end;
        Item := TJSONObject(Arr[I]);
        if not HexValue(Item.Get('address', ''), A) then
        begin
          Error := 'bad address: ' + Item.Get('address', '');
          Breaks := nil;
          Exit;
        end;
        SetLength(Breaks, Length(Breaks) + 1);
        Breaks[High(Breaks)].Addr := A;
        Breaks[High(Breaks)].Enabled := Item.Get('enabled', True);
        Breaks[High(Breaks)].Condition := Item.Get('condition', '');
        Breaks[High(Breaks)].Condact := Item.Get('condact', '');
      end;
    Result := True;
  finally
    Root.Free;
  end;
end;

end.

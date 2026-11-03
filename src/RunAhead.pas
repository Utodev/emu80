{ RunAhead: the input lag cut down, for every emulated machine. After each frame the machine runs a few more with the
  same input, without being heard, the picture of the last one is shown, and the machine is put back exactly as it
  was: the game answers that many frames sooner, while running just as it would.

  Putting it back needs the whole machine. TRunAhead keeps it as a copy of each of its objects (the machine itself and
  every chip, ObjectStateIO): the object's memory as it is, field by field, so that a field added later is kept too
  with nothing to remember. Its managed fields are found through the RTTI: strings, interfaces and dynamic arrays of
  managed things are left as they are (they are names, lists, settings: nothing a frame changes), and the dynamic
  arrays of plain values (memory, pictures, buffers) are kept by their contents. An object referenced from a field is
  not copied with it (only the reference): every object with state of its own must be in the list given to Save. }
unit RunAhead;

{$mode objfpc}{$H+}
{$modeswitch nestedprocvars}
{$R-}{$Q-}

interface

uses
  Classes, TypInfo;

type
  TRunAhead = class
  private
    FState: TMemoryStream;
    FObjects: TFPList;
  public
    { The picture of the last frame run ahead (what the machine shows while Valid) }
    Picture: array of LongWord;
    Valid: Boolean;
    constructor Create;
    destructor Destroy; override;
    { The objects the machine is made of (each once; nil ones are left out): Save keeps them }
    property Objects: TFPList read FObjects;
    { The machine as it is now }
    procedure Save;
    { And back as it was }
    procedure Restore;
  end;

{ An object's state into S (Save) or back from it (see the unit's note) }
procedure ObjectStateIO(Obj: TObject; S: TStream; Save: Boolean);

implementation

{ The bytes a managed field takes in the instance }
function ManagedSize(TI: PTypeInfo): SizeInt;
begin
  case TI^.Kind of
    tkArray: Result := GetTypeData(TI)^.ArrayData.Size;
    tkRecord, tkObject: Result := GetTypeData(TI)^.RecSize;
    tkVariant: Result := SizeOf(Variant);
  else
    Result := SizeOf(Pointer);       // strings, dynamic arrays, interfaces
  end;
end;

{ A dynamic array whose contents are kept (its elements are plain values), and their size }
function PlainDynArray(TI: PTypeInfo; out ElSize: SizeInt): Boolean;
var
  TD: PTypeData;
begin
  Result := False;
  if TI^.Kind <> tkDynArray then Exit;
  TD := GetTypeData(TI);
  if TD^.elType <> nil then Exit;   // managed elements
  ElSize := TD^.elSize;
  Result := True;
end;

type
  TFieldVisit = procedure(Obj: TObject; Offset: SizeInt; TI: PTypeInfo) is nested;

{ Every managed field of the object, of its class and of its parents }
procedure ForManagedFields(Obj: TObject; Visit: TFieldVisit);
var
  C: TClass;
  TI: PTypeInfo;
  RI: PRecInitData;
  F: PInitManagedField;
  I: Integer;
begin
  C := Obj.ClassType;
  while C <> nil do
  begin
    TI := PTypeInfo(PVmt(C)^.vInitTable);
    if TI <> nil then
    begin
      RI := PRecInitData(GetTypeData(TI));
      F := AlignTypeData(PInitManagedField(PByte(@RI^.ManagedFieldCount) + SizeOf(RI^.ManagedFieldCount)));
      for I := 1 to RI^.ManagedFieldCount do
      begin
        Visit(Obj, F^.FldOffset, F^.TypeRef);
        Inc(F);
      end;
    end;
    C := C.ClassParent;
  end;
end;

procedure ObjectStateIO(Obj: TObject; S: TStream; Save: Boolean);
var
  Size: SizeInt;
  Tmp: PByte;

  // Loading: a managed field keeps the value it has now
  procedure KeepField(O: TObject; Offset: SizeInt; TI: PTypeInfo);
  begin
    Move((PByte(O) + Offset)^, (Tmp + Offset - SizeOf(Pointer))^, ManagedSize(TI));
  end;

  // The contents of a dynamic array of plain values: its length, then its bytes
  procedure ArrayIO(O: TObject; Offset: SizeInt; TI: PTypeInfo);
  var
    P: PPointer;
    ElSize, N, Len: SizeInt;
  begin
    if not PlainDynArray(TI, ElSize) then Exit;
    P := PPointer(PByte(O) + Offset);
    if Save then
    begin
      if P^ = nil then N := 0 else N := DynArraySize(P^);
      S.WriteBuffer(N, SizeOf(N));
      if N > 0 then S.WriteBuffer(P^^, N * ElSize);
    end
    else
    begin
      S.ReadBuffer(N, SizeOf(N));
      if P^ = nil then Len := 0 else Len := DynArraySize(P^);
      // (kept in place when it has the same length: arrays shared by two objects stay shared)
      if Len <> N then DynArraySetLength(P^, TI, 1, @N);
      if N > 0 then S.ReadBuffer(P^^, N * ElSize);
    end;
  end;

begin
  // The instance after its VMT pointer
  Size := Obj.InstanceSize - SizeOf(Pointer);
  if Save then
    S.WriteBuffer((PByte(Obj) + SizeOf(Pointer))^, Size)
  else
  begin
    GetMem(Tmp, Size);
    try
      S.ReadBuffer(Tmp^, Size);
      ForManagedFields(Obj, @KeepField);
      Move(Tmp^, (PByte(Obj) + SizeOf(Pointer))^, Size);
    finally
      FreeMem(Tmp);
    end;
  end;
  ForManagedFields(Obj, @ArrayIO);
end;

{ TRunAhead }

constructor TRunAhead.Create;
begin
  inherited Create;
  FState := TMemoryStream.Create;
  FObjects := TFPList.Create;
end;

destructor TRunAhead.Destroy;
begin
  FState.Free;
  FObjects.Free;
  inherited Destroy;
end;

procedure TRunAhead.Save;
var
  I: Integer;
begin
  FObjects.Pack;
  FState.Position := 0;
  for I := 0 to FObjects.Count - 1 do ObjectStateIO(TObject(FObjects[I]), FState, True);
end;

procedure TRunAhead.Restore;
var
  I: Integer;
begin
  FState.Position := 0;
  for I := 0 to FObjects.Count - 1 do ObjectStateIO(TObject(FObjects[I]), FState, False);
end;

end.

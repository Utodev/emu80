{ C64Via: the MOS 6522 Versatile Interface Adapter, as the 1541 drive uses it (two of them: the serial bus
  and the disk controller): two 8-bit ports with their handshake lines, timer 1 (one-shot or free running)
  and timer 2 (one-shot), and the interrupt flags. The shift register is not emulated (the 1541 does not use it). }
unit C64Via;

{$mode objfpc}{$H+}
{$R-}{$Q-}

interface

type
  TViaRead = function: Byte of object;
  TViaWrite = procedure(Value: Byte) of object;
  TViaNotify = procedure of object;

  TVia = class
  private
    FORA, FORB, FDDRA, FDDRB: Byte;
    FT1C, FT1L, FT2C, FT2L: Word;
    FT1Run, FT2Run: Boolean;
    FT1Out: Boolean;
    FACR, FPCR, FIFR, FIER: Byte;
    FCA1, FCB1, FCA2Out, FCB2Out: Boolean;
    FIrq: Boolean;
    FT2Low: Byte;
    procedure UpdateIrq;
    procedure Fire(Bit: Byte);
    procedure UpdateControl;
  public
    OnReadA, OnReadB: TViaRead;
    OnWriteA, OnWriteB: TViaWrite;
    OnControl: TViaNotify;        // CA2 or CB2 changed
    constructor Create;
    procedure Reset;
    procedure Tick; inline;
    function Read(Reg: Byte): Byte;
    function Peek(Reg: Byte): Byte;
    procedure Write(Reg, Value: Byte);
    { CA1 / CB1 input lines (the interrupt flag is set on the edge the PCR chooses) }
    procedure SetCA1(Level: Boolean);
    procedure SetCB1(Level: Boolean);
    function PortAPins: Byte;
    function PortBPins: Byte;
    property Irq: Boolean read FIrq;
    property CA2: Boolean read FCA2Out;
    property CB2: Boolean read FCB2Out;
    property IFR: Byte read FIFR;
    property IER: Byte read FIER;
    property ACR: Byte read FACR;
    property PCR: Byte read FPCR;
  end;

implementation

const
  IRQ_CA2 = $01; IRQ_CA1 = $02; IRQ_SR = $04; IRQ_CB2 = $08; IRQ_CB1 = $10; IRQ_T2 = $20; IRQ_T1 = $40;

constructor TVia.Create;
begin
  inherited Create;
  Reset;
end;

procedure TVia.Reset;
begin
  FORA := 0; FORB := 0; FDDRA := 0; FDDRB := 0;
  FT1C := $FFFF; FT1L := $FFFF; FT2C := $FFFF; FT2L := $FFFF;
  FT1Run := False; FT2Run := False; FT1Out := True;
  FACR := 0; FPCR := 0; FIFR := 0; FIER := 0;
  FCA1 := False; FCB1 := False;
  FCA2Out := True; FCB2Out := True;
  FIrq := False;
end;

procedure TVia.UpdateIrq;
begin
  FIrq := (FIFR and FIER and $7F) <> 0;
  if FIrq then FIFR := FIFR or $80 else FIFR := FIFR and $7F;
end;

procedure TVia.Fire(Bit: Byte);
begin
  FIFR := FIFR or Bit;
  UpdateIrq;
end;

procedure TVia.UpdateControl;
var
  NewA, NewB: Boolean;
begin
  // CA2 / CB2 as manual outputs: PCR 110 = low, 111 = high (the other modes are handshakes, left high)
  case (FPCR shr 1) and 7 of
    6: NewA := False;
  else
    NewA := True;
  end;
  case (FPCR shr 5) and 7 of
    6: NewB := False;
  else
    NewB := True;
  end;
  if (NewA <> FCA2Out) or (NewB <> FCB2Out) then
  begin
    FCA2Out := NewA;
    FCB2Out := NewB;
    if Assigned(OnControl) then OnControl();
  end;
end;

procedure TVia.Tick;
begin
  if FT1Run then
  begin
    if FT1C = 0 then
    begin
      Fire(IRQ_T1);
      FT1Out := not FT1Out;
      if (FACR and $40) <> 0 then FT1C := FT1L else FT1Run := False;
      if (FACR and $40) = 0 then FT1C := $FFFF;
    end
    else Dec(FT1C);
  end
  else Dec(FT1C);
  if (FACR and $20) = 0 then
  begin
    if FT2C = 0 then
    begin
      if FT2Run then
      begin
        FT2Run := False;
        Fire(IRQ_T2);
      end;
    end;
    Dec(FT2C);
  end;
end;

function TVia.PortAPins: Byte;
begin
  Result := FORA or not FDDRA;
end;

function TVia.PortBPins: Byte;
begin
  Result := FORB or not FDDRB;
end;

function TVia.Peek(Reg: Byte): Byte;
var
  Ext: Byte;
begin
  case Reg and $F of
    0:
      begin
        Ext := $FF;
        if Assigned(OnReadB) then Ext := OnReadB();
        Result := (FORB and FDDRB) or (Ext and not FDDRB);
        if (FACR and $80) <> 0 then
          Result := (Result and $7F) or (Ord(FT1Out) shl 7);
      end;
    1, $F:
      begin
        Ext := $FF;
        if Assigned(OnReadA) then Ext := OnReadA();
        Result := (FORA and FDDRA) or (Ext and not FDDRA);
      end;
    2: Result := FDDRB;
    3: Result := FDDRA;
    4: Result := FT1C and $FF;
    5: Result := FT1C shr 8;
    6: Result := FT1L and $FF;
    7: Result := FT1L shr 8;
    8: Result := FT2C and $FF;
    9: Result := FT2C shr 8;
    $A: Result := 0;
    $B: Result := FACR;
    $C: Result := FPCR;
    $D: Result := FIFR;
    $E: Result := FIER or $80;
  else
    Result := 0;
  end;
end;

function TVia.Read(Reg: Byte): Byte;
begin
  Result := Peek(Reg);
  case Reg and $F of
    0:
      begin
        FIFR := FIFR and not (IRQ_CB1 or IRQ_CB2);
        UpdateIrq;
      end;
    1:
      begin
        FIFR := FIFR and not (IRQ_CA1 or IRQ_CA2);
        UpdateIrq;
      end;
    4:
      begin
        FIFR := FIFR and not IRQ_T1;
        UpdateIrq;
      end;
    8:
      begin
        FIFR := FIFR and not IRQ_T2;
        UpdateIrq;
      end;
  end;
end;

procedure TVia.Write(Reg, Value: Byte);
begin
  case Reg and $F of
    0:
      begin
        FORB := Value;
        FIFR := FIFR and not (IRQ_CB1 or IRQ_CB2);
        UpdateIrq;
        if Assigned(OnWriteB) then OnWriteB(FORB);
      end;
    1:
      begin
        FORA := Value;
        FIFR := FIFR and not (IRQ_CA1 or IRQ_CA2);
        UpdateIrq;
        if Assigned(OnWriteA) then OnWriteA(FORA);
      end;
    $F:
      begin
        FORA := Value;
        if Assigned(OnWriteA) then OnWriteA(FORA);
      end;
    2:
      begin
        FDDRB := Value;
        if Assigned(OnWriteB) then OnWriteB(FORB);
      end;
    3:
      begin
        FDDRA := Value;
        if Assigned(OnWriteA) then OnWriteA(FORA);
      end;
    4, 6: FT1L := (FT1L and $FF00) or Value;
    5:
      begin
        FT1L := (FT1L and $FF) or (Value shl 8);
        FT1C := FT1L;
        FT1Run := True;
        FT1Out := False;
        FIFR := FIFR and not IRQ_T1;
        UpdateIrq;
      end;
    7:
      begin
        FT1L := (FT1L and $FF) or (Value shl 8);
        FIFR := FIFR and not IRQ_T1;
        UpdateIrq;
      end;
    8: FT2L := (FT2L and $FF00) or Value;
    9:
      begin
        FT2L := (FT2L and $FF) or (Value shl 8);
        FT2C := FT2L;
        FT2Run := True;
        FIFR := FIFR and not IRQ_T2;
        UpdateIrq;
      end;
    $B: FACR := Value;
    $C:
      begin
        FPCR := Value;
        UpdateControl;
      end;
    $D:
      begin
        FIFR := FIFR and not (Value and $7F);
        UpdateIrq;
      end;
    $E:
      begin
        if (Value and $80) <> 0 then FIER := FIER or (Value and $7F)
        else FIER := FIER and not (Value and $7F);
        UpdateIrq;
      end;
  end;
end;

procedure TVia.SetCA1(Level: Boolean);
begin
  if Level <> FCA1 then
  begin
    // PCR bit 0: 0 = negative edge, 1 = positive edge
    if (Level and ((FPCR and 1) <> 0)) or (not Level and ((FPCR and 1) = 0)) then Fire(IRQ_CA1);
    FCA1 := Level;
  end;
end;

procedure TVia.SetCB1(Level: Boolean);
begin
  if Level <> FCB1 then
  begin
    if (Level and ((FPCR and $10) <> 0)) or (not Level and ((FPCR and $10) = 0)) then Fire(IRQ_CB1);
    FCB1 := Level;
  end;
end;

end.

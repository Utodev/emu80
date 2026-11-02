{ C64Debugger: the debugger of the Commodore 64's 6510, laid out like the Z80 debugger: the disassembly (with the names of the
  KERNAL entry points and the chip registers, and the user's symbols), the registers and flags with the stack and the zero page
  on its right, and under them the memory, the breakpoints (on execution and on reads and writes, with conditions such as
  "A=3 AND @C000=FF") and the watches. A button opens the state of the VIC-II, the CIAs, the SID and the disk drives. Over a
  mnemonic the help says what the instruction does (C64Help).

  The window works on copies of the memory and registers taken under the emulator's lock (after every stop or step, and a few
  times a second while the machine runs), so drawing never races the emulation. F5 runs or pauses, F7 steps into, F10 steps over,
  F11 steps out, F9 runs to the selected line, F8 puts or takes away a breakpoint on it, Ctrl+G goes to an address. }
unit C64Debugger;

{$mode objfpc}{$H+}
{$R-}{$Q-}

interface

uses
  Classes, SysUtils, Types, Math, StrUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, ComCtrls, Dialogs, Menus,
  LCLType, Emulator, Spectrum, C64, Cpu6510, C64Disasm, C64Help, C64Vic, C64Cia, C64Drive, C64Disk, Symbols, ModernUI, Icons,
  DelayHint;

type
  TC64DebuggerWindow = class;

  TSpotKind = (
    skInfo,       // a hex value: its decimal value as a hint
    skLabel,      // a label: the hint is its full name
    skHint,       // text shown as a hint
    skDoc,        // longer help, shown after the mouse rests on it a second
    skReg,        // click to change; Target = register (0 A, 1 X, 2 Y, 3 SP, 4 PC, 5 P)
    skFlag,       // click to toggle; Target = the flag's mask
    skByte        // a byte of memory; Target = its address
  );

  TSpot = record
    R: TRect;
    Kind: TSpotKind;
    Value: Integer;
    Digits: Integer;
    Target: Integer;
    Text: string;
  end;

  { Base of the custom-drawn zones }
  TC64View = class(TCustomControl)
  protected
    FWin: TC64DebuggerWindow;
    FLineH, FCharW: Integer;
    FSpots: array of TSpot;
    FSpotCount: Integer;
    FHintSpot: Integer;
    FBoldFont: TFont;
    procedure MeasureFont;
    function VisibleLines: Integer;
    procedure ClearSpots;
    procedure AddSpot(X, Y, Chars: Integer; Kind: TSpotKind; Value: Integer; Digits: Integer = 0; Target: Integer = 0;
      const AText: string = '');
    function DrawText(X, Y: Integer; const S: string; AColor: TColor; Bold: Boolean): Integer;
    function SpotAt(X, Y: Integer): Integer;
    function ClickSpot(Index: Integer): Boolean; virtual;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure DoEnter; override;
    procedure DoExit; override;
    procedure DrawFocus;
  public
    constructor CreateView(AWin: TC64DebuggerWindow);
    destructor Destroy; override;
    procedure MeasureNow;
    property CharWidth: Integer read FCharW;
    property LineHeight: Integer read FLineH;
  end;

  TDisLine = record
    Addr: Word;
    Len: Integer;
  end;

  { The disassembly }
  TC64DisView = class(TC64View)
  private
    FTop: Word;
    FSel: Integer;                  // address of the selected line (-1 none)
    FLines: array of TDisLine;
    FPopup: TPopupMenu;
    FTargetItem: TMenuItem;
    FMenuAddr: Word;
    FMenuTarget: Integer;
    procedure Layout;
    function LineAt(Y: Integer): Integer;
    function DrawInstruction(X, Y: Integer; Addr: Word; OnBreak, OnPC: Boolean): Integer;
    procedure DrawCheck(X, Y: Integer; Ok: Boolean);
    procedure DrawArrow(X, Y: Integer);
    procedure MenuToggle(Sender: TObject);
    procedure MenuRunTo(Sender: TObject);
    procedure MenuSetPC(Sender: TObject);
    procedure MenuAddBp(Sender: TObject);
    procedure MenuGotoTarget(Sender: TObject);
    procedure MenuGoto(Sender: TObject);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DblClick; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure Resize; override;
  public
    constructor CreateView(AWin: TC64DebuggerWindow);
    function SelAddr: Word;
    procedure ShowAt(Addr: Word);
    procedure EnsureVisible(Addr: Word);
    procedure GoToAddr(Addr: Word);
    procedure Scroll(Count: Integer);
    property Sel: Integer read FSel write FSel;
  end;

  { The registers, the flags, the interrupt and memory state, and the stack }
  TC64RegView = class(TC64View)
  private
    FStackOfs: Integer;
    FStackBox: TRect;
    FStep: Integer;
  protected
    procedure Paint; override;
    function ClickSpot(Index: Integer): Boolean; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  end;

  { A hex dump: the memory (16 bytes and their characters per row) or the zero page (the bytes only) }
  TC64HexView = class(TC64View)
  private
    FTop: Word;
    FZero: Boolean;
    FSelByte: Integer;
    FPopup: TPopupMenu;
    FReadItem, FWriteItem: TMenuItem;
    function AddrDigits: Integer;
    procedure ClampTop;
    procedure MenuGoto(Sender: TObject);
    procedure MenuRead(Sender: TObject);
    procedure MenuWrite(Sender: TObject);
    procedure EditByte(Addr: Word);
  protected
    procedure Paint; override;
    function ClickSpot(Index: Integer): Boolean; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DblClick; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure Resize; override;
  public
    constructor CreateHex(AWin: TC64DebuggerWindow; AZeroPage: Boolean);
    procedure GoToAddr(Addr: Word);
    property FirstAddr: Word read FTop;
  end;

  { The breakpoints }
  TC64BreakView = class(TC64View)
  private
    FSel: Integer;
    FPopup: TPopupMenu;
    function RowAt(Y: Integer): Integer;
    procedure MenuEdit(Sender: TObject);
    procedure MenuRemove(Sender: TObject);
    procedure MenuOnOff(Sender: TObject);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DblClick; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor CreateView(AWin: TC64DebuggerWindow);
    property Sel: Integer read FSel write FSel;
  end;

  { The watches }
  TC64WatchView = class(TC64View)
  private
    FSel: Integer;
    FPopup: TPopupMenu;
    procedure MenuRemove(Sender: TObject);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor CreateView(AWin: TC64DebuggerWindow);
    property Sel: Integer read FSel write FSel;
  end;

  TBpEntry = record
    First, Last: Word;
    Flags: Byte;
    Cond: string;
  end;

  TC64DebuggerWindow = class(TForm)
  private
    FEmu: TEmulator;
    FTimer: TTimer;
    FImages: TImageList;
    FToolbar: TToolBar;
    FRunButton, FBreakButton, FStepButton, FOverButton, FOutButton, FToButton: TToolButton;
    FStatusBar: TStatusBar;
    FDataPanel, FRightPanel, FMemZone, FBreakZone, FWatchZone, FRegZone, FZeroZone: TPanel;
    FWatchSplit: TSplitter;
    FWatchShare: Double;
    FDis: TC64DisView;
    FRegView: TC64RegView;
    FMem, FZero: TC64HexView;
    FBreakView: TC64BreakView;
    FWatchView: TC64WatchView;
    FRamCheck: TCheckBox;
    FSysForm: TForm;
    FSysMemo: TMemo;
    FLaidOut: Boolean;
    // The copies, taken under the emulator's lock
    FPeek: array[0..65535] of Byte;
    FRam: array[0..65535] of Byte;
    FSnapRegs, FPrevRegs: T6502Regs;
    FRunning, FHavePrev: Boolean;
    FWatchText: TStringList;
    FWatchValues: TStringList;
    FSysText: string;
    FReason: string;
    FMapText, FIrqText, FPortText: string;
    FBpList: array of TBpEntry;
    FFollow: Boolean;
    FStepCount: Integer;
    function MakeColumn(AParent: TWinControl; const ACaption: string; AWidth: Integer; AAlign: TAlign): TPanel;
    function AddButton(AIcon: TIconKind; const AHint: string; AHandler: TNotifyEvent): TToolButton;
    procedure AddSeparator;
    procedure BuildUI;
    procedure FormResize(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FitLayout;
    function DataRest: Integer;
    procedure WatchSplitMoved(Sender: TObject);
    procedure TimerTick(Sender: TObject);
    procedure DoRun(Sender: TObject);
    procedure DoBreak(Sender: TObject);
    procedure DoStep(Sender: TObject);
    procedure DoOver(Sender: TObject);
    procedure DoOut(Sender: TObject);
    procedure DoToCursor(Sender: TObject);
    procedure DoToggleBp(Sender: TObject);
    procedure DoGoto(Sender: TObject);
    procedure DoSymbols(Sender: TObject);
    procedure DoSystem(Sender: TObject);
    procedure RamChange(Sender: TObject);
    procedure FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure WindowClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure Take;
    function SystemText: string;
    procedure UpdateAll;
    procedure Resume;
    procedure TakeBreakpoints;
    function BpFlagsText(Flags: Byte): string;
  public
    constructor CreateFor(AOwner: TComponent; AEmu: TEmulator);
    destructor Destroy; override;
    { Stop the machine where it is and show it (a breakpoint was hit) }
    procedure BreakHit;
    procedure Refresh(Force: Boolean);
    procedure ShowAt(Addr: Word);
    // What the views ask for
    function Peek(Addr: Word): Byte;
    function PeekRamAt(Addr: Word): Byte;
    procedure SetFollow(Value: Boolean);
    procedure DoAddBp(Sender: TObject);
    procedure DoClearBps(Sender: TObject);
    procedure DoAddWatch(Sender: TObject);
    function NextInstr(Addr: Word): Word;
    function BackInstr(Addr: Word; Count: Integer): Word;
    function SymbolName(Addr: Word): string;
    function ParseAddr(const AText: string; out Addr: Word): Boolean;
    function EvalValue(const AText: string; out Value: Integer): Boolean;
    function BpFlagsAt(Addr: Word): Byte;
    function CondAt(Addr: Word): string;
    function BpCount: Integer;
    function BpEntryAt(Index: Integer): TBpEntry;
    function WatchCount: Integer;
    function WatchLine(Index: Integer): string;
    procedure ToggleBpAt(Addr: Word);
    procedure SetBpFlags(Addr: Word; Flags: Byte);
    procedure RunToAddr(Addr: Word);
    procedure SetPCAt(Addr: Word);
    procedure SetRegister(Index, Value: Integer);
    procedure ToggleFlag(Mask: Byte);
    procedure PokeAt(Addr: Word; Value: Byte; Ram: Boolean);
    procedure BpDialog(Edit: Boolean; Sel: Integer; DefaultAddr: Word);
    procedure EditBpAt(Index: Integer);
    procedure ToggleBpEnabled(Index: Integer);
    procedure DeleteBp(Index: Integer);
    procedure DeleteWatch(Index: Integer);
    function RamOnly: Boolean;
    function AskAddress(const ATitle: string; out Addr: Word): Boolean;
    property Regs: T6502Regs read FSnapRegs;
    property Prev: T6502Regs read FPrevRegs;
    property HavePrev: Boolean read FHavePrev;
    property Running: Boolean read FRunning;
    property MapText: string read FMapText;
    property IrqText: string read FIrqText;
    property PortText: string read FPortText;
    property StepCount: Integer read FStepCount;
    property SnapPC: Word read FSnapRegs.PC;
  end;

var
  C64DebuggerWindow: TC64DebuggerWindow;

{ Open (or bring to front) the debugger, stopping the machine where it is }
procedure ShowC64Debugger(Emu: TEmulator);

implementation

const
  {$IFDEF WINDOWS}
  MONO_FONT = 'Consolas';
  {$ELSE}
  {$IFDEF DARWIN}
  MONO_FONT = 'Menlo';
  {$ELSE}
  MONO_FONT = 'Monospace';
  {$ENDIF}
  {$ENDIF}
  FLAG_NAMES = 'NV-BDIZC';
  MEM_NAMES: array[0..4] of string = ('RAM', 'BASIC', 'KERNAL', 'char ROM', 'I/O');
  REG_NAMES: array[0..5] of string = ('A', 'X', 'Y', 'SP', 'PC', 'P');
  GUTTER_W = 40;      // breakpoint type, "?" if conditional, execution arrow
  MAX_LABEL = 20;     // longer labels are cut, with the full name as a hint
  HEX_BYTES = 16;     // bytes per row in the memory view

function Hex2(V: Integer): string;
begin
  Result := IntToHex(V and $FF, 2);
end;

function Hex4(V: Integer): string;
begin
  Result := IntToHex(V and $FFFF, 4);
end;

// The colours of the Z80 debugger
function BreakColor: TColor;
begin
  Result := TC(RGBToColor(205, 40, 40));
end;

function DisabledColor: TColor;
begin
  Result := TC(RGBToColor(245, 205, 205));
end;

function PCColor: TColor;
begin
  Result := TC(RGBToColor(200, 240, 200));
end;

function ChangedColor: TColor;
begin
  Result := TC(RGBToColor(160, 0, 0));
end;

function MnemonicColor(OnBreak: Boolean): TColor;
begin
  if OnBreak then Result := TC(RGBToColor(255, 235, 140)) else Result := TC(RGBToColor(0, 0, 200));
end;

function LabelColor: TColor;
begin
  Result := TC(RGBToColor(0, 110, 110));
end;

procedure ShowC64Debugger(Emu: TEmulator);
begin
  if C64DebuggerWindow = nil then C64DebuggerWindow := TC64DebuggerWindow.CreateFor(Application, Emu);
  Emu.PauseAndWait;
  C64DebuggerWindow.Show;
  C64DebuggerWindow.BringToFront;
  C64DebuggerWindow.Refresh(True);
  C64DebuggerWindow.ShowAt(C64DebuggerWindow.SnapPC);
end;

{ ---- TC64View ---- }

constructor TC64View.CreateView(AWin: TC64DebuggerWindow);
begin
  inherited Create(AWin);
  FWin := AWin;
  TabStop := True;
  Color := clWhite;
  Font.Name := MONO_FONT;
  Font.Size := 10;
  FBoldFont := TFont.Create;
  DoubleBuffered := True;
  ShowHint := True;
  BorderStyle := bsSingle;
  FHintSpot := -1;
end;

destructor TC64View.Destroy;
begin
  FBoldFont.Free;
  inherited Destroy;
end;

procedure TC64View.MeasureFont;
begin
  FBoldFont.Assign(Font);
  FBoldFont.Style := [fsBold];
  Canvas.Font := FBoldFont;
  FCharW := Canvas.TextWidth('0');
  FLineH := Canvas.TextHeight('Xg') + 2;
  Canvas.Font := Font;
end;

function TC64View.VisibleLines: Integer;
begin
  if FLineH = 0 then MeasureFont;
  Result := Max(1, ClientHeight div FLineH);
end;

procedure TC64View.ClearSpots;
begin
  FSpotCount := 0;
end;

procedure TC64View.AddSpot(X, Y, Chars: Integer; Kind: TSpotKind; Value: Integer; Digits: Integer; Target: Integer;
  const AText: string);
begin
  if FSpotCount >= Length(FSpots) then SetLength(FSpots, FSpotCount * 2 + 64);
  FSpots[FSpotCount].R := Rect(X, Y, X + Chars * FCharW, Y + FLineH);
  FSpots[FSpotCount].Kind := Kind;
  FSpots[FSpotCount].Value := Value;
  FSpots[FSpotCount].Digits := Digits;
  FSpots[FSpotCount].Target := Target;
  FSpots[FSpotCount].Text := AText;
  Inc(FSpotCount);
end;

function TC64View.DrawText(X, Y: Integer; const S: string; AColor: TColor; Bold: Boolean): Integer;
begin
  if Bold then Canvas.Font := FBoldFont else Canvas.Font := Font;
  Canvas.Font.Color := AColor;
  Canvas.Brush.Style := bsClear;
  Canvas.TextOut(X, Y, S);
  Result := X + Length(S) * FCharW;
  Canvas.Font := Font;
end;

function TC64View.SpotAt(X, Y: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to FSpotCount - 1 do
    if PtInRect(FSpots[I].R, Point(X, Y)) then Exit(I);
  Result := -1;
end;

function TC64View.ClickSpot(Index: Integer): Boolean;
begin
  Result := False;
end;

procedure TC64View.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Spot: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  DelayedHint.Cancel;
  if TabStop and CanFocus then SetFocus;
  if Button <> mbLeft then Exit;
  Spot := SpotAt(X, Y);
  if (Spot >= 0) and ClickSpot(Spot) then Invalidate;
end;

procedure TC64View.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Spot: Integer;
  Labels: string;
begin
  inherited MouseMove(Shift, X, Y);
  Spot := SpotAt(X, Y);
  if (Spot >= 0) and (FSpots[Spot].Kind in [skReg, skFlag]) then Cursor := crHandPoint else Cursor := crDefault;
  if Spot = FHintSpot then Exit;
  FHintSpot := Spot;
  Application.CancelHint;
  if Spot < 0 then
  begin
    Hint := '';
    DelayedHint.Cancel;
    Exit;
  end;
  if FSpots[Spot].Kind = skDoc then
  begin
    Hint := '';
    DelayedHint.Request(Self, FSpots[Spot].R, FSpots[Spot].Text);
    Exit;
  end;
  DelayedHint.Cancel;
  if FSpots[Spot].Kind in [skLabel, skHint] then Hint := FSpots[Spot].Text
  else
  begin
    // The decimal value of the hex number under the mouse; a 16-bit one: the names it has
    Hint := IntToStr(FSpots[Spot].Value);
    if (FSpots[Spot].Digits >= 4) and (FSpots[Spot].Value >= 0) and (FSpots[Spot].Value <= $FFFF) then
    begin
      Labels := FWin.SymbolName(Word(FSpots[Spot].Value));
      if Labels <> '' then Hint := Hint + ' - ' + Labels;
    end;
  end;
  if Hint <> '' then Application.ActivateHint(Mouse.CursorPos);
end;

procedure TC64View.MouseLeave;
begin
  inherited MouseLeave;
  DelayedHint.Cancel;
  FHintSpot := -1;
  Hint := '';
  Application.CancelHint;
end;

procedure TC64View.DoEnter;
begin
  inherited DoEnter;
  Invalidate;
end;

procedure TC64View.DoExit;
begin
  inherited DoExit;
  Invalidate;
end;

procedure TC64View.DrawFocus;
begin
  if not Focused then Exit;
  Canvas.Pen.Color := TC(clHighlight);
  Canvas.Brush.Style := bsClear;
  Canvas.Rectangle(ClientRect);
  Canvas.Brush.Style := bsSolid;
end;


procedure TC64View.MeasureNow;
begin
  MeasureFont;
end;

{ ---- TC64DisView ---- }

constructor TC64DisView.CreateView(AWin: TC64DebuggerWindow);

  procedure AddMenu(const ACaption: string; AHandler: TNotifyEvent);
  var
    Item: TMenuItem;
  begin
    Item := TMenuItem.Create(FPopup);
    Item.Caption := ACaption;
    Item.OnClick := AHandler;
    FPopup.Items.Add(Item);
  end;

begin
  inherited CreateView(AWin);
  FSel := -1;
  FPopup := TPopupMenu.Create(Self);
  AddMenu('Toggle breakpoint (F8)', @MenuToggle);
  AddMenu('Add breakpoint...', @MenuAddBp);
  AddMenu('Run to here (F9)', @MenuRunTo);
  AddMenu('Set PC here', @MenuSetPC);
  AddMenu('Go to address... (Ctrl+G)', @MenuGoto);
  AddMenu('Go to', @MenuGotoTarget);
  FTargetItem := FPopup.Items[FPopup.Items.Count - 1];
end;

function TC64DisView.SelAddr: Word;
begin
  if FSel >= 0 then Result := Word(FSel) else Result := FWin.Regs.PC;
end;

procedure TC64DisView.Layout;
var
  N, I: Integer;
  A: Word;
begin
  if FLineH = 0 then MeasureFont;
  N := VisibleLines;
  SetLength(FLines, N);
  A := FTop;
  for I := 0 to N - 1 do
  begin
    FLines[I].Addr := A;
    FLines[I].Len := OpLength(FWin.Peek(A));
    A := Word(A + FLines[I].Len);
  end;
end;

function TC64DisView.LineAt(Y: Integer): Integer;
begin
  if FLineH = 0 then MeasureFont;
  Result := Y div FLineH;
  if (Result < 0) or (Result > High(FLines)) then Result := -1;
end;

procedure TC64DisView.ShowAt(Addr: Word);
begin
  // A few lines of context above
  FTop := FWin.BackInstr(Addr, 4);
  Layout;
  Invalidate;
end;

procedure TC64DisView.EnsureVisible(Addr: Word);
var
  I: Integer;
begin
  Layout;
  // Visible and not on the last line: leave the view alone
  for I := 0 to High(FLines) - 1 do
    if FLines[I].Addr = Addr then
    begin
      Invalidate;
      Exit;
    end;
  ShowAt(Addr);
end;

procedure TC64DisView.GoToAddr(Addr: Word);
begin
  FSel := Addr;
  FWin.SetFollow(False);
  ShowAt(Addr);
end;

procedure TC64DisView.Scroll(Count: Integer);
var
  I: Integer;
begin
  for I := 1 to Abs(Count) do
    if Count > 0 then FTop := FWin.NextInstr(FTop) else FTop := FWin.BackInstr(FTop, 1);
  FWin.SetFollow(False);
  Layout;
  Invalidate;
end;

procedure TC64DisView.Resize;
begin
  inherited Resize;
  if FLineH > 0 then Layout;
end;

procedure TC64DisView.DrawCheck(X, Y: Integer; Ok: Boolean);
var
  S: Integer;
begin
  S := FLineH - 6;
  Canvas.Pen.Width := 2;
  if Ok then
  begin
    Canvas.Pen.Color := TC(RGBToColor(0, 150, 0));
    Canvas.Line(X, Y + S div 2, X + S div 3, Y + S);
    Canvas.Line(X + S div 3, Y + S, X + S, Y);
  end
  else
  begin
    Canvas.Pen.Color := TC(RGBToColor(220, 0, 0));
    Canvas.Line(X, Y, X + S, Y + S);
    Canvas.Line(X + S, Y, X, Y + S);
  end;
  Canvas.Pen.Width := 1;
end;

procedure TC64DisView.DrawArrow(X, Y: Integer);
var
  H: Integer;
begin
  H := FLineH - 4;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := TC(RGBToColor(0, 120, 0));
  Canvas.Pen.Color := TC(clBlack);
  Canvas.Polygon([Point(X, Y), Point(X + H div 2 + 2, Y + H div 2), Point(X, Y + H)]);
  Canvas.Brush.Style := bsClear;
end;

{ Draw one instruction: the mnemonic in blue (dark red if it is an illegal opcode), A X Y in bold, numbers and names normal.
  An operand with a name is shown by it, followed by its value in brackets in grey. Returns the X after the text. }
function TC64DisView.DrawInstruction(X, Y: Integer; Addr: Word; OnBreak, OnPC: Boolean): Integer;
var
  Instr, Mnem, Operand, Tok, Lbl, Help: string;
  Len, Target, P, Start, V, Digits: Integer;
  Op: Byte;
  Illegal, ZeroPageMode: Boolean;
  TextColor: TColor;
begin
  if OnBreak then TextColor := TC(clWhite) else TextColor := TC(clBlack);
  Op := FWin.Peek(Addr);
  Illegal := OpIllegal[Op];
  Instr := Disassemble6502(Addr, @FWin.Peek, Len, Target);
  Mnem := OpName[Op];
  Operand := Copy(Instr, 6, MaxInt);
  ZeroPageMode := OpMode[Op] in [amZp, amZpx, amZpy, amIzx, amIzy];
  if ZeroPageMode then Digits := 2 else Digits := 4;
  Lbl := '';
  if (Target >= 0) and (OpMode[Op] <> amImm) then
  begin
    Lbl := FWin.SymbolName(Word(Target));
    if Lbl <> '' then Operand := StringReplace(Operand, '$' + IntToHex(Target, Digits), Lbl, []);
  end;
  Help := InstructionHelp6502(Op, Operand);
  if Help <> '' then AddSpot(X, Y - 1, Length(Mnem), skDoc, 0, 0, 0, Help);
  if DarkTheme then
  begin
    if OnBreak or OnPC or not Illegal then X := DrawText(X, Y, Mnem, clWhite, True)
    else X := DrawText(X, Y, Mnem, RGBToColor(255, 125, 125), True);
  end
  else if not Illegal then X := DrawText(X, Y, Mnem, MnemonicColor(OnBreak), False)
  else if OnBreak then X := DrawText(X, Y, Mnem, RGBToColor(255, 225, 120), True)
  else X := DrawText(X, Y, Mnem, RGBToColor(150, 0, 0), True);
  if Operand <> '' then
  begin
    X := DrawText(X, Y, ' ', TextColor, False);
    P := 1;
    while P <= Length(Operand) do
    begin
      if Operand[P] in [',', '(', ')', '#'] then
      begin
        X := DrawText(X, Y, Operand[P], TextColor, False);
        Inc(P);
        Continue;
      end;
      Start := P;
      while (P <= Length(Operand)) and not (Operand[P] in [',', '(', ')', '#']) do Inc(P);
      Tok := Copy(Operand, Start, P - Start);
      if (Tok <> '') and (Tok[1] = '$') then
      begin
        V := StrToIntDef(Tok, 0);
        AddSpot(X, Y - 1, Length(Tok), skInfo, V, IfThen(Length(Tok) <= 3, 2, 4));
        X := DrawText(X, Y, Tok, TextColor, False);
      end
      else if (Lbl <> '') and (Tok = Lbl) then
      begin
        AddSpot(X, Y - 1, Length(Tok), skLabel, Target, 0, 0, Lbl);
        X := DrawText(X, Y, Tok, TextColor, False);
      end
      else if (Tok = 'X') or (Tok = 'Y') or (Tok = 'A') then X := DrawText(X, Y, Tok, TextColor, True)
      else X := DrawText(X, Y, Tok, TextColor, False);
    end;
  end;
  if Lbl <> '' then
  begin
    // The value the name stands for, in grey
    Inc(X, FCharW * 2);
    if OnBreak then TextColor := TC(RGBToColor(255, 205, 205)) else TextColor := TC(RGBToColor(150, 150, 150));
    X := DrawText(X, Y, '[', TextColor, False);
    AddSpot(X, Y - 1, Digits, skInfo, Target, Digits);
    X := DrawText(X, Y, IntToHex(Target, Digits), TextColor, False);
    X := DrawText(X, Y, ']', TextColor, False);
  end;
  Result := X;
end;

procedure TC64DisView.Paint;
var
  I, J, Y, X, Len, Target, Bit: Integer;
  L: TDisLine;
  Lbl, Cond: string;
  BP, Op: Byte;
  IsPC, Active: Boolean;
  Back, TextColor: TColor;
begin
  MeasureFont;
  Layout;
  ClearSpots;
  Canvas.Brush.Color := TC(clWhite);
  Canvas.FillRect(ClientRect);
  for I := 0 to High(FLines) do
  begin
    L := FLines[I];
    Y := I * FLineH;
    BP := FWin.BpFlagsAt(L.Addr);
    IsPC := L.Addr = FWin.Regs.PC;
    // A breakpoint that is switched off keeps a pale background
    Active := (BP <> 0) and ((BP and C64_BP_DISABLED) = 0);
    if Active then Back := BreakColor
    else if IsPC then Back := PCColor
    else if BP <> 0 then Back := DisabledColor
    else Back := TC(clWhite);
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := Back;
    Canvas.FillRect(0, Y, ClientWidth, Y + FLineH);
    if Active then TextColor := TC(clWhite) else TextColor := TC(clBlack);

    // Gutter: the breakpoint's type and the execution arrow
    if (BP and C64_BP_EXEC) <> 0 then DrawText(2, Y + 1, 'E', TextColor, True)
    else if (BP and (C64_BP_READ or C64_BP_WRITE)) = (C64_BP_READ or C64_BP_WRITE) then DrawText(2, Y + 1, 'A', TextColor, True)
    else if (BP and C64_BP_READ) <> 0 then DrawText(2, Y + 1, 'R', TextColor, True)
    else if (BP and C64_BP_WRITE) <> 0 then DrawText(2, Y + 1, 'W', TextColor, True);
    // "?" after the type marks a conditional breakpoint
    Cond := '';
    if BP <> 0 then Cond := FWin.CondAt(L.Addr);
    if Cond <> '' then DrawText(2 + FCharW, Y + 1, '?', TextColor, True);
    if IsPC then DrawArrow(FCharW * 2 + 4, Y + 2);

    // The name of the address
    Lbl := FWin.SymbolName(L.Addr);
    if Lbl <> '' then
    begin
      AddSpot(GUTTER_W, Y, Min(Length(Lbl), MAX_LABEL), skLabel, L.Addr, 0, 0, Lbl);
      if Length(Lbl) > MAX_LABEL then Lbl := Copy(Lbl, 1, MAX_LABEL - 1) + '~';
      if Active then DrawText(GUTTER_W, Y + 1, Lbl, TC(clWhite), False)
      else DrawText(GUTTER_W, Y + 1, Lbl, LabelColor, False);
    end;

    // The address, then the instruction's bytes
    X := GUTTER_W + (MAX_LABEL + 1) * FCharW;
    AddSpot(X, Y, 4, skInfo, L.Addr, 4);
    DrawText(X, Y + 1, Hex4(L.Addr), TextColor, False);
    Inc(X, FCharW * 6);
    for J := 0 to L.Len - 1 do
    begin
      AddSpot(X + J * 3 * FCharW, Y, 2, skInfo, FWin.Peek(Word(L.Addr + J)), 2);
      DrawText(X + J * 3 * FCharW, Y + 1, Hex2(FWin.Peek(Word(L.Addr + J))), TextColor, False);
    end;
    Inc(X, FCharW * 10);
    X := DrawInstruction(X, Y + 1, L.Addr, Active, IsPC);

    // Where a conditional branch at the execution point will go
    Op := FWin.Peek(L.Addr);
    if IsPC and (OpMode[Op] = amRel) then
    begin
      // Bits 7-6 of the opcode choose the flag (N V C Z), bit 5 the value it must have
      case (Op shr 6) and 3 of
        0: Bit := $80;
        1: Bit := $40;
        2: Bit := $01;
      else
        Bit := $02;
      end;
      DrawCheck(X + FCharW * 2, Y + 3, ((FWin.Regs.P and Bit) <> 0) = (((Op shr 5) and 1) = 1));
      Inc(X, FCharW * 3);
    end;

    // The breakpoint's condition
    if Cond <> '' then
    begin
      if Active then TextColor := TC(RGBToColor(255, 240, 150)) else TextColor := TC(RGBToColor(140, 90, 0));
      DrawText(X + FCharW * 3, Y + 1, 'if ' + Cond, TextColor, False);
      AddSpot(0, Y, 3, skHint, 0, 0, 0, 'Condition: ' + Cond);
    end;

    if (FSel >= 0) and (L.Addr = Word(FSel)) then
    begin
      Canvas.Pen.Color := TC(clNavy);
      if Focused then Canvas.Pen.Style := psSolid else Canvas.Pen.Style := psDot;
      Canvas.Brush.Style := bsClear;
      Canvas.Rectangle(GUTTER_W - 2, Y, ClientWidth - 1, Y + FLineH);
      Canvas.Pen.Style := psSolid;
    end;
  end;
  Target := 0;
  DrawFocus;
end;

procedure TC64DisView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  I, Len, Target: Integer;
  P: TPoint;
begin
  I := LineAt(Y);
  if I >= 0 then FSel := FLines[I].Addr;
  inherited MouseDown(Button, Shift, X, Y);
  if I < 0 then Exit;
  Invalidate;
  // A click in the gutter puts or takes away a breakpoint
  if (Button = mbLeft) and (X < GUTTER_W) then FWin.ToggleBpAt(FSel);
  if Button = mbRight then
  begin
    FMenuAddr := FSel;
    Disassemble6502(FMenuAddr, @FWin.Peek, Len, Target);
    FMenuTarget := Target;
    FTargetItem.Visible := Target >= 0;
    if Target >= 0 then FTargetItem.Caption := Format('Go to $%s', [Hex4(Target)]);
    P := ClientToScreen(Point(X, Y));
    FPopup.PopUp(P.X, P.Y);
  end;
end;

procedure TC64DisView.DblClick;
begin
  inherited DblClick;
  if FSel >= 0 then FWin.ToggleBpAt(Word(FSel));
end;

procedure TC64DisView.MenuToggle(Sender: TObject);
begin
  FWin.ToggleBpAt(FMenuAddr);
end;

procedure TC64DisView.MenuRunTo(Sender: TObject);
begin
  FWin.RunToAddr(FMenuAddr);
end;

procedure TC64DisView.MenuSetPC(Sender: TObject);
begin
  FWin.SetPCAt(FMenuAddr);
end;

procedure TC64DisView.MenuAddBp(Sender: TObject);
begin
  FWin.BpDialog(False, -1, FMenuAddr);
end;

procedure TC64DisView.MenuGotoTarget(Sender: TObject);
begin
  if FMenuTarget >= 0 then GoToAddr(Word(FMenuTarget));
end;

procedure TC64DisView.MenuGoto(Sender: TObject);
var
  A: Word;
begin
  if FWin.AskAddress('Go to address in the disassembly', A) then GoToAddr(A);
end;

procedure TC64DisView.KeyDown(var Key: Word; Shift: TShiftState);
var
  Row: Integer;
begin
  inherited KeyDown(Key, Shift);
  case Key of
    VK_DOWN, VK_UP:
      begin
        Row := 0;
        while (Row < High(FLines)) and (FLines[Row].Addr <> SelAddr) do Inc(Row);
        if Key = VK_DOWN then
        begin
          if Row >= High(FLines) - 1 then Scroll(1);
          FSel := FWin.NextInstr(SelAddr);
        end
        else
        begin
          if Row <= 0 then Scroll(-1);
          FSel := FWin.BackInstr(SelAddr, 1);
        end;
        Invalidate;
        Key := 0;
      end;
    VK_NEXT: begin Scroll(Max(1, VisibleLines - 2)); Key := 0; end;
    VK_PRIOR: begin Scroll(-Max(1, VisibleLines - 2)); Key := 0; end;
    VK_SPACE, VK_RETURN: begin FWin.ToggleBpAt(SelAddr); Key := 0; end;
  end;
end;

function TC64DisView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  if WheelDelta > 0 then Scroll(-3) else Scroll(3);
  Result := True;
end;

{ ---- TC64RegView ---- }

procedure TC64RegView.Paint;
const
  FLAG_MASKS: array[0..7] of Byte = ($80, $40, $20, $10, $08, $04, $02, $01);
var
  R, P: T6502Regs;
  Y, I, Rows, Idx, SPv, Bit: Integer;
  W, Callee: Word;
  Have: Boolean;
  Lbl: string;
  ValueColor: TColor;

  function Col(N: Integer): Integer;
  begin
    Result := 8 + N * FCharW;
  end;

  procedure Name(C: Integer; const S: string);
  begin
    DrawText(Col(C), Y, S, TC(clBlack), True);
  end;

  function ChangedOrBlack(Changed: Boolean): TColor;
  begin
    if Changed and Have then Result := ChangedColor else Result := TC(clBlack);
  end;

  { Register value: dark red if the last instruction changed it; click to edit }
  procedure RegValue(C: Integer; Reg: Integer; V, Digits: Integer; Changed: Boolean);
  begin
    AddSpot(Col(C), Y, Digits, skReg, V, Digits, Reg);
    DrawText(Col(C), Y, IntToHex(V, Digits), ChangedOrBlack(Changed), False);
  end;

  procedure Grey(C: Integer; const S: string);
  begin
    DrawText(Col(C), Y, S, TC(clGray), False);
  end;

begin
  MeasureFont;
  ClearSpots;
  Canvas.Brush.Color := TC(clBtnFace);
  Canvas.FillRect(ClientRect);
  R := FWin.Regs;
  P := FWin.Prev;
  Have := FWin.HavePrev;
  // After a step the stack shows its top again
  if FWin.StepCount <> FStep then
  begin
    FStep := FWin.StepCount;
    FStackOfs := 0;
  end;
  Y := 6;

  Name(0, 'A'); RegValue(4, 0, R.A, 2, R.A <> P.A); Grey(7, Format('(%3d)', [R.A]));
  Name(17, 'X'); RegValue(21, 1, R.X, 2, R.X <> P.X); Grey(24, Format('(%3d)', [R.X]));
  Inc(Y, FLineH);
  Name(0, 'Y'); RegValue(4, 2, R.Y, 2, R.Y <> P.Y); Grey(7, Format('(%3d)', [R.Y]));
  Name(17, 'SP'); RegValue(21, 3, R.SP, 2, R.SP <> P.SP); Grey(24, '($01' + Hex2(R.SP) + ')');
  Inc(Y, FLineH);
  Name(0, 'PC'); RegValue(4, 4, R.PC, 4, R.PC <> P.PC); Grey(9, '(' + Hex2(FWin.Peek(R.PC)) + ')');
  Name(17, 'P'); RegValue(21, 5, R.P, 2, R.P <> P.P);
  Grey(24, '(%' + RightStr('00000000' + IntToBin(R.P, 8), 8) + ')');
  Inc(Y, FLineH + FLineH div 2);

  // Flags: names above, X (set) or . (clear) below; click to toggle
  Name(0, 'Flags');
  for I := 0 to 7 do
  begin
    AddSpot(Col(7 + I * 2), Y, 1, skDoc, 0, 0, 0, FlagHelp6502(7 - I));
    DrawText(Col(7 + I * 2), Y, FLAG_NAMES[I + 1], TC(clBlack), True);
  end;
  Inc(Y, FLineH);
  for I := 0 to 7 do
  begin
    Bit := FLAG_MASKS[I];
    ValueColor := ChangedOrBlack(((R.P xor P.P) and Bit) <> 0);
    if Bit <> $20 then AddSpot(Col(7 + I * 2), Y, 1, skFlag, Ord((R.P and Bit) <> 0), 1, Bit);
    if (R.P and Bit) <> 0 then DrawText(Col(7 + I * 2), Y, 'X', ValueColor, False)
    else DrawText(Col(7 + I * 2), Y, '.', ValueColor, False);
  end;
  Inc(Y, FLineH + FLineH div 2);

  // The interrupt lines, the processor port and what it maps
  Name(0, 'IRQ'); DrawText(Col(4), Y, FWin.IrqText, TC(clBlack), False);
  Inc(Y, FLineH);
  Name(0, 'Port'); DrawText(Col(5), Y, FWin.PortText, TC(clBlack), False);
  Inc(Y, FLineH);
  DrawText(Col(0), Y, FWin.MapText, TC(clGray), False);
  Inc(Y, FLineH + FLineH div 2);

  // The stack: from SP upwards, as 16-bit words (a return address of a JSR has the call in grey)
  Name(0, 'Stack');
  Inc(Y, FLineH);
  FStackBox := Rect(4, Y, ClientWidth - 4, ClientHeight - 4);
  Rows := Max(1, (ClientHeight - 4 - Y) div FLineH);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := TC(clWhite);
  Canvas.Pen.Color := TC(clGray);
  Canvas.Rectangle(FStackBox);
  Canvas.Brush.Style := bsClear;
  SPv := R.SP;
  Inc(Y, 2);
  for I := 0 to Rows - 1 do
  begin
    Idx := I + FStackOfs;
    if SPv + 1 + Idx * 2 > $FF then
    begin
      if I = 0 then DrawText(Col(0), Y, 'empty', TC(clGray), False);
      Break;
    end;
    W := Word($0100 or (SPv + 1 + Idx * 2));
    AddSpot(Col(0), Y, 4, skInfo, W, 4);
    DrawText(Col(0), Y, Hex4(W), TC(clGray), False);
    W := Word(FWin.Peek(W) or (FWin.Peek(Word(W + 1)) shl 8));
    AddSpot(Col(6), Y, 4, skInfo, W, 4);
    DrawText(Col(6), Y, Hex4(W), TC(clBlack), False);
    Lbl := FWin.SymbolName(W);
    if Lbl <> '' then DrawText(Col(11), Y, Lbl, LabelColor, False)
    else if FWin.Peek(Word(W - 2)) = $20 then
    begin
      Callee := Word(FWin.Peek(Word(W - 1)) or (FWin.Peek(W) shl 8));
      Lbl := FWin.SymbolName(Callee);
      if Lbl = '' then Lbl := '$' + Hex4(Callee);
      DrawText(Col(11), Y, 'JSR ' + Lbl, TC(clGray), False);
    end;
    Inc(Y, FLineH);
  end;
  DrawFocus;
end;

function TC64RegView.ClickSpot(Index: Integer): Boolean;
var
  S: string;
  V: Integer;
begin
  Result := False;
  case FSpots[Index].Kind of
    skFlag:
      begin
        FWin.ToggleFlag(FSpots[Index].Target);
        Result := True;
      end;
    skReg:
      begin
        S := IntToHex(FSpots[Index].Value, FSpots[Index].Digits);
        if InputQuery('Set ' + REG_NAMES[FSpots[Index].Target], 'New value (hex, or an expression):', S) then
        begin
          if FWin.EvalValue(S, V) then FWin.SetRegister(FSpots[Index].Target, V)
          else MessageDlg('Set', 'Not a value: ' + S, mtError, [mbOK], 0);
        end;
        Result := True;
      end;
  end;
end;

function TC64RegView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
var
  D: Integer;
begin
  Result := True;
  if WheelDelta < 0 then D := 1 else D := -1;
  if PtInRect(FStackBox, MousePos) then
  begin
    FStackOfs := Max(0, FStackOfs + D);
    Invalidate;
  end
  else Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
end;

{ ---- TC64HexView ---- }

constructor TC64HexView.CreateHex(AWin: TC64DebuggerWindow; AZeroPage: Boolean);

  function AddMenu(const ACaption: string; AHandler: TNotifyEvent): TMenuItem;
  begin
    Result := TMenuItem.Create(FPopup);
    Result.Caption := ACaption;
    Result.OnClick := AHandler;
    FPopup.Items.Add(Result);
  end;

begin
  inherited CreateView(AWin);
  FZero := AZeroPage;
  FSelByte := -1;
  FPopup := TPopupMenu.Create(Self);
  if not FZero then AddMenu('Go to address... (Ctrl+G)', @MenuGoto);
  FReadItem := AddMenu('Stop when this byte is read', @MenuRead);
  FWriteItem := AddMenu('Stop when this byte is written', @MenuWrite);
end;

function TC64HexView.AddrDigits: Integer;
begin
  if FZero then Result := 2 else Result := 4;
end;

procedure TC64HexView.ClampTop;
var
  MaxTop: Integer;
begin
  if FZero then
  begin
    MaxTop := Max(0, 256 - VisibleLines * HEX_BYTES);
    FTop := Word(Min(FTop and $F0, MaxTop));
  end
  else FTop := FTop and $FFF0;
end;

procedure TC64HexView.Resize;
begin
  inherited Resize;
  if FLineH > 0 then ClampTop;
end;

procedure TC64HexView.GoToAddr(Addr: Word);
begin
  FSelByte := Addr;
  FTop := Addr and $FFF0;
  ClampTop;
  Invalidate;
end;

procedure TC64HexView.Paint;
var
  Row, Col, Y, X, AsciiX, Digits: Integer;
  A: Word;
  V, BP: Byte;
  Back: TColor;
begin
  MeasureFont;
  ClearSpots;
  ClampTop;
  Canvas.Brush.Color := TC(clWhite);
  Canvas.FillRect(ClientRect);
  Digits := AddrDigits;
  AsciiX := 4 + FCharW * (Digits + 2 + HEX_BYTES * 3 + 1);
  for Row := 0 to VisibleLines - 1 do
  begin
    Y := Row * FLineH;
    A := Word(FTop + Row * HEX_BYTES);
    if FZero and (A > $FF) then Break;
    AddSpot(4, Y, Digits, skInfo, A, Digits);
    DrawText(4, Y + 1, IntToHex(A, Digits), TC(clGray), False);
    for Col := 0 to HEX_BYTES - 1 do
    begin
      if (FWin.RamOnly and not FZero) then V := FWin.PeekRamAt(Word(A + Col)) else V := FWin.Peek(Word(A + Col));
      // A read or write breakpoint on the byte: pink, pale when switched off
      BP := FWin.BpFlagsAt(Word(A + Col));
      if (BP and (C64_BP_READ or C64_BP_WRITE)) <> 0 then
      begin
        if (BP and C64_BP_DISABLED) <> 0 then Back := TC(RGBToColor(250, 230, 230))
        else Back := TC(RGBToColor(255, 185, 185));
      end
      else Back := TC(clWhite);
      X := 4 + FCharW * (Digits + 2 + Col * 3);
      if Back <> TC(clWhite) then
      begin
        Canvas.Brush.Style := bsSolid;
        Canvas.Brush.Color := Back;
        Canvas.FillRect(X - FCharW div 2, Y, X + FCharW * 2 + FCharW div 2, Y + FLineH);
      end;
      if FSelByte = Word(A + Col) then
      begin
        Canvas.Brush.Style := bsSolid;
        Canvas.Brush.Color := TC(RGBToColor(190, 215, 255));
        Canvas.FillRect(X - FCharW div 2, Y, X + FCharW * 2 + FCharW div 2, Y + FLineH);
      end;
      AddSpot(X, Y, 2, skByte, V, 2, Word(A + Col));
      DrawText(X, Y + 1, Hex2(V), TC(clBlack), False);
      if not FZero then
      begin
        X := AsciiX + Col * FCharW;
        AddSpot(X, Y, 1, skByte, V, 2, Word(A + Col));
        if FSelByte = Word(A + Col) then
        begin
          Canvas.Brush.Style := bsSolid;
          Canvas.Brush.Color := TC(RGBToColor(190, 215, 255));
          Canvas.FillRect(X, Y, X + FCharW, Y + FLineH);
        end;
        // Not printable: a grey dot
        if (V >= 32) and (V < 127) then DrawText(X, Y + 1, Chr(V), TC(clBlack), False)
        else DrawText(X, Y + 1, '.', TC(clGray), False);
      end;
    end;
  end;
  DrawFocus;
end;

function TC64HexView.ClickSpot(Index: Integer): Boolean;
begin
  Result := False;
  if FSpots[Index].Kind = skByte then
  begin
    FSelByte := FSpots[Index].Target;
    Result := True;
  end;
end;

procedure TC64HexView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Spot: Integer;
  P: TPoint;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbRight then
  begin
    Spot := SpotAt(X, Y);
    if (Spot >= 0) and (FSpots[Spot].Kind = skByte) then FSelByte := FSpots[Spot].Target;
    Invalidate;
    FReadItem.Enabled := FSelByte >= 0;
    FWriteItem.Enabled := FSelByte >= 0;
    if FSelByte >= 0 then
    begin
      FReadItem.Checked := (FWin.BpFlagsAt(Word(FSelByte)) and C64_BP_READ) <> 0;
      FWriteItem.Checked := (FWin.BpFlagsAt(Word(FSelByte)) and C64_BP_WRITE) <> 0;
    end;
    P := ClientToScreen(Point(X, Y));
    FPopup.PopUp(P.X, P.Y);
  end;
end;

procedure TC64HexView.EditByte(Addr: Word);
var
  S: string;
  V: Integer;
begin
  S := Hex2(FWin.Peek(Addr));
  if InputQuery('Change $' + Hex4(Addr), 'New value (hex, or an expression):', S) then
  begin
    if FWin.EvalValue(S, V) then FWin.PokeAt(Addr, V, (FWin.RamOnly and not FZero))
    else MessageDlg('Change', 'Not a value: ' + S, mtError, [mbOK], 0);
  end;
end;

procedure TC64HexView.DblClick;
begin
  inherited DblClick;
  if FSelByte >= 0 then EditByte(Word(FSelByte));
end;

procedure TC64HexView.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  case Key of
    VK_RETURN: begin if FSelByte >= 0 then EditByte(Word(FSelByte)); Key := 0; end;
    VK_DOWN: begin FTop := Word(FTop + HEX_BYTES); ClampTop; Invalidate; Key := 0; end;
    VK_UP: begin FTop := Word(FTop - HEX_BYTES); ClampTop; Invalidate; Key := 0; end;
    VK_NEXT: begin FTop := Word(FTop + HEX_BYTES * VisibleLines); ClampTop; Invalidate; Key := 0; end;
    VK_PRIOR: begin FTop := Word(FTop - HEX_BYTES * VisibleLines); ClampTop; Invalidate; Key := 0; end;
  end;
end;

function TC64HexView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  if WheelDelta > 0 then FTop := Word(FTop - HEX_BYTES * 3) else FTop := Word(FTop + HEX_BYTES * 3);
  ClampTop;
  Invalidate;
  Result := True;
end;

procedure TC64HexView.MenuGoto(Sender: TObject);
var
  A: Word;
begin
  if FWin.AskAddress('Go to address in the memory', A) then GoToAddr(A);
end;

procedure TC64HexView.MenuRead(Sender: TObject);
begin
  if FSelByte >= 0 then
    FWin.SetBpFlags(Word(FSelByte), FWin.BpFlagsAt(Word(FSelByte)) xor C64_BP_READ);
end;

procedure TC64HexView.MenuWrite(Sender: TObject);
begin
  if FSelByte >= 0 then
    FWin.SetBpFlags(Word(FSelByte), FWin.BpFlagsAt(Word(FSelByte)) xor C64_BP_WRITE);
end;

{ ---- TC64BreakView ---- }

constructor TC64BreakView.CreateView(AWin: TC64DebuggerWindow);

  procedure AddMenu(const ACaption: string; AHandler: TNotifyEvent);
  var
    Item: TMenuItem;
  begin
    Item := TMenuItem.Create(FPopup);
    Item.Caption := ACaption;
    Item.OnClick := AHandler;
    FPopup.Items.Add(Item);
  end;

begin
  inherited CreateView(AWin);
  FSel := -1;
  FPopup := TPopupMenu.Create(Self);
  AddMenu('Add... (Insert)', @FWin.DoAddBp);
  AddMenu('Edit... (Enter)', @MenuEdit);
  AddMenu('Remove (Delete)', @MenuRemove);
  AddMenu('On / off (Space)', @MenuOnOff);
  AddMenu('Remove all', @FWin.DoClearBps);
end;

function TC64BreakView.RowAt(Y: Integer): Integer;
begin
  if FLineH = 0 then MeasureFont;
  Result := Y div FLineH;
  if (Result < 0) or (Result >= FWin.BpCount) then Result := -1;
end;

procedure TC64BreakView.MenuEdit(Sender: TObject);
begin
  if FSel >= 0 then FWin.EditBpAt(FSel);
end;

procedure TC64BreakView.MenuRemove(Sender: TObject);
begin
  if FSel >= 0 then FWin.DeleteBp(FSel);
end;

procedure TC64BreakView.MenuOnOff(Sender: TObject);
begin
  if FSel >= 0 then FWin.ToggleBpEnabled(FSel);
end;

function BreakTypeName(Flags: Byte): string;
begin
  if (Flags and C64_BP_EXEC) <> 0 then Result := 'Exec'
  else if (Flags and (C64_BP_READ or C64_BP_WRITE)) = (C64_BP_READ or C64_BP_WRITE) then Result := 'Access'
  else if (Flags and C64_BP_READ) <> 0 then Result := 'Read'
  else Result := 'Write';
end;

procedure TC64BreakView.Paint;
var
  I, Y, X, Box: Integer;
  E: TBpEntry;
  Lbl, Cond, Full, T: string;
  IsOn: Boolean;
  TextColor: TColor;
begin
  MeasureFont;
  ClearSpots;
  Canvas.Brush.Color := TC(clWhite);
  Canvas.FillRect(ClientRect);
  if FWin.BpCount = 0 then DrawText(4, 2, 'Insert: add', TC(clGray), False);
  Box := FLineH - 6;
  for I := 0 to FWin.BpCount - 1 do
  begin
    Y := I * FLineH;
    E := FWin.BpEntryAt(I);
    IsOn := (E.Flags and C64_BP_DISABLED) = 0;
    if I = FSel then
    begin
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := TC(RGBToColor(210, 225, 250));
      Canvas.FillRect(0, Y, ClientWidth, Y + FLineH);
    end;
    // On/off box: click to switch
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := TC(clWhite);
    Canvas.Pen.Color := TC(clGray);
    Canvas.Rectangle(4, Y + 3, 4 + Box, Y + 3 + Box);
    if IsOn then
    begin
      Canvas.Pen.Color := BreakColor;
      Canvas.Pen.Width := 2;
      Canvas.Line(6, Y + 3 + Box div 2, 4 + Box div 2, Y + 1 + Box);
      Canvas.Line(4 + Box div 2, Y + 1 + Box, 2 + Box, Y + 5);
      Canvas.Pen.Width := 1;
    end;
    if IsOn then TextColor := TC(clBlack) else TextColor := TC(clGray);
    T := BreakTypeName(E.Flags);
    DrawText(8 + Box, Y + 1, T, TextColor, True);
    Full := T + '  ';
    X := 8 + Box + FCharW * 8;
    AddSpot(X, Y, 4, skInfo, E.First, 4);
    Lbl := Hex4(E.First);
    if E.Last <> E.First then Lbl := Lbl + '-' + Hex4(E.Last);
    X := DrawText(X, Y + 1, Lbl, TextColor, False);
    Full := Full + Lbl;
    Lbl := FWin.SymbolName(E.First);
    if Lbl <> '' then
    begin
      Full := Full + ' ' + Lbl;
      AddSpot(X + FCharW, Y, Min(Length(Lbl), 14), skLabel, E.First, 0, 0, Lbl);
      if Length(Lbl) > 14 then Lbl := Copy(Lbl, 1, 13) + '~';
      X := DrawText(X + FCharW, Y + 1, Lbl, LabelColor, False);
    end;
    Cond := E.Cond;
    if Cond <> '' then
    begin
      X := DrawText(X + FCharW, Y + 1, 'if ' + Cond, TC(RGBToColor(140, 90, 0)), False);
      Full := Full + ' if ' + Cond;
    end;
    // Cut at the right: the box and the type show it whole as a hint
    if X > ClientWidth - 4 then AddSpot(0, Y, ClientWidth div FCharW + 1, skHint, 0, 0, 0, Full);
  end;
  DrawFocus;
end;

procedure TC64BreakView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  P: TPoint;
begin
  inherited MouseDown(Button, Shift, X, Y);
  FSel := RowAt(Y);
  if (Button = mbLeft) and (FSel >= 0) and (X < FLineH + 4) then FWin.ToggleBpEnabled(FSel);
  Invalidate;
  if Button = mbRight then
  begin
    P := ClientToScreen(Point(X, Y));
    FPopup.PopUp(P.X, P.Y);
  end;
end;

procedure TC64BreakView.DblClick;
begin
  inherited DblClick;
  if FSel >= 0 then FWin.EditBpAt(FSel);
end;

procedure TC64BreakView.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  case Key of
    VK_INSERT: begin FWin.BpDialog(False, -1, FWin.Regs.PC); Key := 0; end;
    VK_DELETE: begin if FSel >= 0 then FWin.DeleteBp(FSel); Key := 0; end;
    VK_SPACE: begin if FSel >= 0 then FWin.ToggleBpEnabled(FSel); Key := 0; end;
    VK_RETURN: begin if FSel >= 0 then FWin.EditBpAt(FSel); Key := 0; end;
    VK_DOWN: begin if FSel < FWin.BpCount - 1 then Inc(FSel); Invalidate; Key := 0; end;
    VK_UP: begin if FSel > 0 then Dec(FSel); Invalidate; Key := 0; end;
  end;
end;

{ ---- TC64WatchView ---- }

constructor TC64WatchView.CreateView(AWin: TC64DebuggerWindow);

  procedure AddMenu(const ACaption: string; AHandler: TNotifyEvent);
  var
    Item: TMenuItem;
  begin
    Item := TMenuItem.Create(FPopup);
    Item.Caption := ACaption;
    Item.OnClick := AHandler;
    FPopup.Items.Add(Item);
  end;

begin
  inherited CreateView(AWin);
  FSel := -1;
  FPopup := TPopupMenu.Create(Self);
  AddMenu('Add a watch... (Insert)', @FWin.DoAddWatch);
  AddMenu('Remove (Delete)', @MenuRemove);
end;

procedure TC64WatchView.MenuRemove(Sender: TObject);
begin
  if FSel >= 0 then FWin.DeleteWatch(FSel);
end;

procedure TC64WatchView.Paint;
var
  I, Y: Integer;
  S: string;
begin
  MeasureFont;
  ClearSpots;
  Canvas.Brush.Color := TC(clWhite);
  Canvas.FillRect(ClientRect);
  if FWin.WatchCount = 0 then DrawText(4, 2, 'Insert: add a watch', TC(clGray), False);
  for I := 0 to FWin.WatchCount - 1 do
  begin
    Y := I * FLineH;
    if I = FSel then
    begin
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := TC(RGBToColor(210, 225, 250));
      Canvas.FillRect(0, Y, ClientWidth, Y + FLineH);
    end;
    S := FWin.WatchLine(I);
    if Pos('?', S) > 0 then DrawText(6, Y + 1, S, TC(clGray), False)
    else DrawText(6, Y + 1, S, TC(clBlack), False);
  end;
  DrawFocus;
end;

procedure TC64WatchView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  P: TPoint;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if FLineH = 0 then MeasureFont;
  FSel := Y div FLineH;
  if FSel >= FWin.WatchCount then FSel := -1;
  Invalidate;
  if Button = mbRight then
  begin
    P := ClientToScreen(Point(X, Y));
    FPopup.PopUp(P.X, P.Y);
  end;
end;

procedure TC64WatchView.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  case Key of
    VK_INSERT: begin FWin.DoAddWatch(Self); Key := 0; end;
    VK_DELETE: begin if FSel >= 0 then FWin.DeleteWatch(FSel); Key := 0; end;
    VK_DOWN: begin if FSel < FWin.WatchCount - 1 then Inc(FSel); Invalidate; Key := 0; end;
    VK_UP: begin if FSel > 0 then Dec(FSel); Invalidate; Key := 0; end;
  end;
end;

{ ---- TC64DebuggerWindow ---- }

{ Hint over a zone's title }
procedure SetZoneHint(Zone: TPanel; const AHint: string);
var
  Header: TPanel;
begin
  Header := TPanel(Zone.Controls[0]);
  Header.Hint := AHint;
  Header.ShowHint := True;
  TLabel(Header.Controls[0]).Hint := AHint;
  TLabel(Header.Controls[0]).ShowHint := True;
end;

constructor TC64DebuggerWindow.CreateFor(AOwner: TComponent; AEmu: TEmulator);
begin
  inherited CreateNew(AOwner);
  FEmu := AEmu;
  FWatchText := TStringList.Create;
  FWatchValues := TStringList.Create;
  FFollow := True;
  Caption := 'Commodore 64 debugger';
  Width := 1100;
  Height := 860;
  Position := poMainFormCenter;
  KeyPreview := True;
  OnKeyDown := @FormKey;
  OnClose := @WindowClose;
  OnResize := @FormResize;
  OnShow := @FormShow;
  BuildUI;
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 250;
  FTimer.OnTimer := @TimerTick;
  FTimer.Enabled := True;
  ThemeForm(Self);
end;

destructor TC64DebuggerWindow.Destroy;
begin
  FWatchText.Free;
  FWatchValues.Free;
  C64DebuggerWindow := nil;
  inherited Destroy;
end;

procedure TC64DebuggerWindow.WindowClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  CloseAction := caHide;
end;

function TC64DebuggerWindow.Peek(Addr: Word): Byte;
begin
  Result := FPeek[Addr];
end;

function TC64DebuggerWindow.PeekRamAt(Addr: Word): Byte;
begin
  Result := FRam[Addr];
end;

function TC64DebuggerWindow.RamOnly: Boolean;
begin
  Result := (FRamCheck <> nil) and FRamCheck.Checked;
end;

procedure TC64DebuggerWindow.SetFollow(Value: Boolean);
begin
  FFollow := Value;
end;

function TC64DebuggerWindow.AddButton(AIcon: TIconKind; const AHint: string; AHandler: TNotifyEvent): TToolButton;
begin
  Result := TToolButton.Create(FToolbar);
  Result.Parent := FToolbar;
  Result.ImageIndex := Ord(AIcon);
  Result.Hint := AHint;
  Result.OnClick := AHandler;
  Result.Left := FToolbar.Width + 1000;   // append at the right
end;

procedure TC64DebuggerWindow.AddSeparator;
var
  Sep: TToolButton;
begin
  Sep := TToolButton.Create(FToolbar);
  Sep.Parent := FToolbar;
  Sep.Style := tbsDivider;
  Sep.Left := FToolbar.Width + 1000;
end;

{ A zone of the window: a tinted header with a bold title, then the view }
function TC64DebuggerWindow.MakeColumn(AParent: TWinControl; const ACaption: string; AWidth: Integer;
  AAlign: TAlign): TPanel;
var
  Header: TPanel;
  Lbl: TLabel;
begin
  Result := TPanel.Create(Self);
  Result.Parent := AParent;
  Result.Align := AAlign;
  if AWidth > 0 then Result.Width := AWidth;
  Result.BevelOuter := bvNone;
  Result.BorderSpacing.Around := 3;
  Header := TPanel.Create(Self);
  Header.Parent := Result;
  Header.Align := alTop;
  Header.Height := 24;
  Header.BevelOuter := bvNone;
  Header.Color := RGBToColor(214, 224, 242);
  Header.ParentBackground := False;
  Lbl := TLabel.Create(Self);
  Lbl.Parent := Header;
  Lbl.Caption := ACaption;
  Lbl.Font.Style := [fsBold];
  Lbl.Left := 6;
  Lbl.Top := 4;
end;

procedure TC64DebuggerWindow.BuildUI;
var
  Split: TSplitter;
  Header: TPanel;
  Zone: TPanel;
begin
  FImages := TImageList.Create(Self);
  LoadIcons(FImages);
  FToolbar := TToolBar.Create(Self);
  FToolbar.Parent := Self;
  FToolbar.Images := FImages;
  FToolbar.ShowCaptions := False;
  FToolbar.ShowHint := True;
  FToolbar.ButtonWidth := IconSize + 10;
  FToolbar.ButtonHeight := IconSize + 10;
  FToolbar.AutoSize := True;
  FRunButton := AddButton(ikRun, 'Run (F5)', @DoRun);
  FBreakButton := AddButton(ikBreak, 'Break (F5)', @DoBreak);
  AddSeparator;
  FStepButton := AddButton(ikStepInto, 'Step into (F7)', @DoStep);
  FOverButton := AddButton(ikStepOver, 'Step over (F10)', @DoOver);
  FOutButton := AddButton(ikFolderUp, 'Step out: run until the subroutine returns (F11)', @DoOut);
  FToButton := AddButton(ikRunToCursor, 'Run to cursor (F9)', @DoToCursor);
  AddSeparator;
  AddButton(ikGoTo, 'Go to address (Ctrl+G)', @DoGoto);
  AddButton(ikBreakpoint, 'Put or take away a breakpoint on the selected line (F8)', @DoToggleBp);
  AddButton(ikClearBreakpoints, 'Remove all the breakpoints', @DoClearBps);
  AddButton(ikWatch, 'Add a watch', @DoAddWatch);
  AddSeparator;
  AddButton(ikOpen, 'Load symbols: NAME = $ADDRESS lines, as the assemblers write them', @DoSymbols);
  AddButton(ikChip, 'System: the state of the VIC-II, the CIAs, the SID and the disk drives', @DoSystem);

  // Data zone (bottom third): memory | breakpoints | watches, the last two sharing the rest
  FDataPanel := TPanel.Create(Self);
  FDataPanel.Parent := Self;
  FDataPanel.Align := alBottom;
  FDataPanel.Height := 220;
  FDataPanel.BevelOuter := bvNone;
  FMemZone := MakeColumn(FDataPanel, 'Memory (Ctrl+G: go to; double-click: change a byte)', 600, alLeft);
  Header := TPanel(FMemZone.Controls[0]);
  FRamCheck := TCheckBox.Create(Self);
  FRamCheck.Parent := Header;
  FRamCheck.Caption := 'RAM only';
  FRamCheck.AnchorSideRight.Control := Header;
  FRamCheck.AnchorSideRight.Side := asrRight;
  FRamCheck.BorderSpacing.Right := 4;
  FRamCheck.Anchors := [akTop, akRight];
  FRamCheck.Top := 2;
  FRamCheck.Hint := 'Show (and change) the RAM under the ROMs and the I/O, not what the processor sees';
  FRamCheck.ShowHint := True;
  FRamCheck.OnChange := @RamChange;
  FMem := TC64HexView.CreateHex(Self, False);
  FMem.Parent := FMemZone;
  FMem.Align := alClient;
  Split := TSplitter.Create(Self);
  Split.Parent := FDataPanel;
  Split.Align := alLeft;
  Split.Left := 2000;
  FBreakZone := MakeColumn(FDataPanel, 'Breakpoints', 200, alLeft);
  FBreakZone.Left := 3000;
  SetZoneHint(FBreakZone, 'Insert: add, Delete: remove, Space or the box: on/off, Enter or double-click: edit, ' +
    'right-click: menu');
  FBreakView := TC64BreakView.CreateView(Self);
  FBreakView.Parent := FBreakZone;
  FBreakView.Align := alClient;
  FWatchSplit := TSplitter.Create(Self);
  FWatchSplit.Parent := FDataPanel;
  FWatchSplit.Align := alLeft;
  FWatchSplit.Left := 4000;
  FWatchSplit.Width := 6;
  FWatchSplit.Beveled := True;
  FWatchSplit.MinSize := 80;
  FWatchSplit.ResizeStyle := rsUpdate;
  FWatchSplit.OnMoved := @WatchSplitMoved;
  FWatchShare := 0.5;
  FWatchZone := MakeColumn(FDataPanel, 'Watches', 0, alClient);
  SetZoneHint(FWatchZone, 'Insert: add a watch (A, X, @D012, @(FB)...), Delete: remove it, right-click: menu');
  FWatchView := TC64WatchView.CreateView(Self);
  FWatchView.Parent := FWatchZone;
  FWatchView.Align := alClient;

  Split := TSplitter.Create(Self);
  Split.Parent := Self;
  Split.Align := alBottom;

  // The right side: the registers, and the zero page under them
  FRightPanel := TPanel.Create(Self);
  FRightPanel.Parent := Self;
  FRightPanel.Align := alRight;
  FRightPanel.Width := 440;
  FRightPanel.BevelOuter := bvNone;
  FZeroZone := MakeColumn(FRightPanel, 'Zero page (double-click: change a byte)', 0, alBottom);
  FZeroZone.Height := 240;
  FZero := TC64HexView.CreateHex(Self, True);
  FZero.Parent := FZeroZone;
  FZero.Align := alClient;
  Split := TSplitter.Create(Self);
  Split.Parent := FRightPanel;
  Split.Align := alBottom;
  FRegZone := MakeColumn(FRightPanel, 'Registers (click to change)', 0, alClient);
  FRegView := TC64RegView.CreateView(Self);
  FRegView.Parent := FRegZone;
  FRegView.Align := alClient;
  FRegView.TabStop := False;
  FRegView.Color := clBtnFace;

  Split := TSplitter.Create(Self);
  Split.Parent := Self;
  Split.Align := alRight;

  // The disassembly (the rest)
  Zone := MakeColumn(Self, 'Disassembly (double-click: breakpoint; right-click: menu)', 0, alClient);
  FDis := TC64DisView.CreateView(Self);
  FDis.Parent := Zone;
  FDis.Align := alClient;

  // Bottom-aligned controls are ordered by Top: put the status bar lowest
  FStatusBar := TStatusBar.Create(Self);
  FStatusBar.Parent := Self;
  FStatusBar.SimplePanel := True;
  FStatusBar.Top := 100000;
end;

function TC64DebuggerWindow.DataRest: Integer;
begin
  Result := Max(1, FDataPanel.ClientWidth - FMemZone.Width - 26);
end;

procedure TC64DebuggerWindow.FormResize(Sender: TObject);
const
  MIN_DATA = 110;
var
  Avail, Data: Integer;
begin
  if FDataPanel = nil then Exit;
  // The data zone keeps a third of the height
  Avail := ClientHeight - FToolbar.Height - FStatusBar.Height - 8;
  Data := Avail div 3;
  FDataPanel.Height := Max(MIN_DATA, Data);
  FBreakZone.Width := Max(80, DataRest - Round(DataRest * FWatchShare));
end;

procedure TC64DebuggerWindow.WatchSplitMoved(Sender: TObject);
begin
  FWatchShare := Max(0.1, 1 - FBreakZone.Width / DataRest);
end;

procedure TC64DebuggerWindow.FormShow(Sender: TObject);
begin
  if not FLaidOut then FitLayout;
end;

{ Size the zones to what they show, now that the font can be measured }
procedure TC64DebuggerWindow.FitLayout;
var
  CW, Border, DisasmW, RegW, MemW: Integer;
  Work: TRect;
begin
  FLaidOut := True;
  FDis.MeasureNow;
  CW := FDis.CharWidth;
  Border := FRegView.Width - FRegView.ClientWidth;
  // Registers: 36 columns, or the zero page's 16 bytes if that is wider
  RegW := Max(16 + 36 * CW, 8 + (4 + HEX_BYTES * 3) * CW) + Border;
  DisasmW := GUTTER_W + (MAX_LABEL + 1 + 6 + 10 + 26) * CW + Border;
  MemW := 6 + (6 + HEX_BYTES * 3 + 1 + HEX_BYTES) * CW + Border;
  FRightPanel.Width := RegW + 12;
  FMemZone.Width := MemW + 6;
  FZeroZone.Height := 24 + 8 * FDis.LineHeight + Border + 12;
  ClientWidth := DisasmW + RegW + 12 + 10;
  // Not bigger than the screen
  Work := Monitor.WorkareaRect;
  if Height > Work.Bottom - Work.Top then
  begin
    Height := Work.Bottom - Work.Top;
    Top := Work.Top;
  end
  else if Top + Height > Work.Bottom then Top := Max(Work.Top, Work.Bottom - Height);
  if Width > Work.Right - Work.Left then
  begin
    Width := Work.Right - Work.Left;
    Left := Work.Left;
  end
  else if Left + Width > Work.Right then Left := Max(Work.Left, Work.Right - Width);
  FormResize(Self);
end;

procedure TC64DebuggerWindow.RamChange(Sender: TObject);
begin
  FMem.Invalidate;
end;

{ ---- the copies ---- }

procedure TC64DebuggerWindow.Take;
var
  I, V: Integer;
  Hw: TC64;
  Err: string;
begin
  FEmu.Lock;
  try
    Hw := FEmu.Spec.C64Hw;
    if Hw = nil then Exit;
    FRunning := not FEmu.Paused;
    if FHavePrev and (FSnapRegs.PC <> Hw.Cpu.PC) then
    begin
      FPrevRegs := FSnapRegs;
      Inc(FStepCount);
    end;
    FSnapRegs := Hw.Cpu.GetRegs;
    for I := 0 to 65535 do
    begin
      FPeek[I] := Hw.Peek(I);
      FRam[I] := Hw.PeekRam(I);
    end;
    FSysText := SystemText;
    FPortText := Format('DDR %s  PORT %s  (bank %d)', [Hex2(Hw.Ddr), Hex2(Hw.Port), Hw.Bank and 7]);
    FMapText := Format('A000 %s  D000 %s  E000 %s', [MEM_NAMES[Hw.MemoryAt($A000)], MEM_NAMES[Hw.MemoryAt($D000)],
      MEM_NAMES[Hw.MemoryAt($E000)]]);
    FIrqText := '';
    if Hw.Vic.Irq then FIrqText := FIrqText + 'VIC ';
    if Hw.Cia1.Irq then FIrqText := FIrqText + 'CIA1 ';
    if FIrqText = '' then FIrqText := 'idle' else FIrqText := 'asserted: ' + Trim(FIrqText);
    if Hw.Cia2.Irq then FIrqText := FIrqText + '   NMI: CIA2';
    FWatchValues.Clear;
    for I := 0 to FWatchText.Count - 1 do
      if Hw.EvalCondition(FWatchText[I], V, Err) then
        FWatchValues.Add(Format('%s = $%s (%d)', [FWatchText[I], IntToHex(V and $FFFFFF, IfThen(V > $FF, 4, 2)), V]))
      else
        FWatchValues.Add(FWatchText[I] + ' = ?   ' + Err);
    TakeBreakpoints;
    if Hw.BreakKind <> cbkNone then
    begin
      case Hw.BreakKind of
        cbkExec: FReason := Format('Breakpoint at $%s', [Hex4(Hw.BreakAddr)]);
        cbkRead: FReason := Format('Read of $%s (instruction at $%s)', [Hex4(Hw.BreakAddr), Hex4(Hw.BreakInstr)]);
        cbkWrite: FReason := Format('Write to $%s (instruction at $%s)', [Hex4(Hw.BreakAddr), Hex4(Hw.BreakInstr)]);
        cbkRunTo: FReason := 'Reached the address';
      else
        FReason := '';
      end;
    end;
  finally
    FEmu.Unlock;
  end;
  FHavePrev := True;
end;

procedure TC64DebuggerWindow.TakeBreakpoints;
var
  A, Start: Integer;
  F: Byte;
  Hw: TC64;
  C: string;
begin
  Hw := FEmu.Spec.C64Hw;
  SetLength(FBpList, 0);
  A := 0;
  while A <= $FFFF do
  begin
    F := Hw.GetBreakpoint(A);
    if F = 0 then
    begin
      Inc(A);
      Continue;
    end;
    Start := A;
    C := Hw.ConditionOf(A);
    // A run of addresses with the same flags (and no condition) is one range
    while (A < $FFFF) and (Hw.GetBreakpoint(A + 1) = F) and (C = '') and (Hw.ConditionOf(A + 1) = '') do Inc(A);
    SetLength(FBpList, Length(FBpList) + 1);
    FBpList[High(FBpList)].First := Start;
    FBpList[High(FBpList)].Last := A;
    FBpList[High(FBpList)].Flags := F;
    FBpList[High(FBpList)].Cond := C;
    Inc(A);
  end;
end;

function TC64DebuggerWindow.BpFlagsAt(Addr: Word): Byte;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FBpList) do
    if (Addr >= FBpList[I].First) and (Addr <= FBpList[I].Last) then Result := FBpList[I].Flags;
end;

function TC64DebuggerWindow.BpFlagsText(Flags: Byte): string;
begin
  Result := '';
  if (Flags and C64_BP_EXEC) <> 0 then Result := Result + 'exec ';
  if (Flags and C64_BP_READ) <> 0 then Result := Result + 'read ';
  if (Flags and C64_BP_WRITE) <> 0 then Result := Result + 'write ';
  Result := Trim(Result);
end;

{ The text of the System tab (the emulator is locked) }
function TC64DebuggerWindow.SystemText: string;
var
  Hw: TC64;
  V: TVic;
  I: Integer;
  S: string;
  D: TC64Drive;

  procedure Line(const T: string);
  begin
    Result := Result + T + LineEnding;
  end;

  procedure Cia(const Name: string; C: TCia);
  begin
    Line(Format('%s: PRA=%s PRB=%s DDRA=%s DDRB=%s  TA=%s TB=%s  CRA=%s CRB=%s  flags=%s mask=%s IRQ=%s',
      [Name, Hex2(C.PRA), Hex2(C.PRB), Hex2(C.DDRA), Hex2(C.DDRB), Hex4(C.TimerA), Hex4(C.TimerB), Hex2(C.CRA), Hex2(C.CRB),
       Hex2(C.Flags), Hex2(C.Mask), IfThen(C.Irq, 'yes', 'no')]));
  end;

begin
  Result := '';
  Hw := FEmu.Spec.C64Hw;
  V := Hw.Vic;
  Line(Format('6510 port: DDR=%s PORT=%s  (LORAM/HIRAM/CHAREN = %d)', [Hex2(Hw.Ddr), Hex2(Hw.Port), Hw.Bank and 7]));
  Line(Format('At A000: %s   D000: %s   E000: %s', [MEM_NAMES[Hw.MemoryAt($A000)], MEM_NAMES[Hw.MemoryAt($D000)],
    MEM_NAMES[Hw.MemoryAt($E000)]]));
  Line('');
  Line(Format('VIC-II: raster %d, cycle %d, IRQ %s, VC=%d RC=%d', [V.Raster, V.Cycle, IfThen(V.Irq, 'on', 'off'),
    V.VideoCounter, V.RowCounter]));
  S := '';
  for I := 0 to 46 do
  begin
    S := S + Hex2(V.Peek(I)) + ' ';
    if (I mod 16 = 15) or (I = 46) then
    begin
      Line(Format('  $D0%s: %s', [Hex2(I - (I mod 16)), S]));
      S := '';
    end;
  end;
  Line(Format('  %s%s %s, screen $%s, %s $%s, border %d, background %d, scroll X=%d Y=%d, %d columns, %d rows',
    [IfThen((V.Peek($11) and $40) <> 0, 'ECM ', ''), IfThen((V.Peek($11) and $20) <> 0, 'bitmap', 'text'),
     IfThen((V.Peek($16) and $10) <> 0, 'multicolour', 'hires'), Hex4(((V.Peek($18) shr 4) and 15) * $400 +
       (((not Hw.Cia2.PortAPins) and 3) shl 14)),
     IfThen((V.Peek($11) and $20) <> 0, 'bitmap', 'characters'),
     Hex4(IfThen((V.Peek($11) and $20) <> 0, (V.Peek($18) and 8) * $400, (V.Peek($18) and 14) * $400) +
       (((not Hw.Cia2.PortAPins) and 3) shl 14)),
     V.Peek($20) and 15, V.Peek($21) and 15, V.Peek($16) and 7, V.Peek($11) and 7,
     IfThen((V.Peek($16) and 8) <> 0, 40, 38), IfThen((V.Peek($11) and 8) <> 0, 25, 24)]));
  Line(Format('  VIC bank %d (starts at $%s), display %s', [(not Hw.Cia2.PortAPins) and 3,
    Hex4(((not Hw.Cia2.PortAPins) and 3) shl 14), IfThen((V.Peek($11) and $10) <> 0, 'on', 'off (DEN clear)')]));
  for I := 0 to 7 do
    if (V.Peek($15) and (1 shl I)) <> 0 then
      Line(Format('  sprite %d: x=%d y=%d colour %d%s%s%s', [I, V.Peek(I * 2) + ((V.Peek($10) shr I) and 1) * 256,
        V.Peek(I * 2 + 1), V.Peek($27 + I) and 15, IfThen((V.Peek($1C) and (1 shl I)) <> 0, ', multicolour', ''),
        IfThen((V.Peek($1D) and (1 shl I)) <> 0, ', double width', ''),
        IfThen((V.Peek($17) and (1 shl I)) <> 0, ', double height', '')]));
  Line('');
  Cia('CIA 1', Hw.Cia1);
  Cia('CIA 2', Hw.Cia2);
  Line('');
  Line('SID:');
  S := '';
  for I := 0 to 24 do
  begin
    S := S + Hex2(Hw.Sid.Register(I)) + ' ';
    if (I mod 8 = 7) or (I = 24) then
    begin
      Line('  ' + S);
      S := '';
    end;
  end;
  Line('');
  for I := 0 to 1 do
    if Hw.DriveOn[I] then
    begin
      D := Hw.Drive[I];
      // (IfThen evaluates both branches: no disk would be dereferenced)
      if D.Disk <> nil then S := D.Disk.DiskName + ' (' + ExtractFileName(D.Disk.FileName) + ')' else S := 'none';
      Line(Format('Drive %d: PC=%s  track %d%s  motor %s  LED %s  disk: %s', [8 + I, Hex4(D.Cpu.PC), D.Track div 2 + 1,
        IfThen(Odd(D.Track), '.5', ''), IfThen(D.Motor, 'on', 'off'), IfThen(D.Led, 'on', 'off'), S]));
    end;
  Line(Format('IEC bus: ATN %s  CLK %s  DATA %s', [IfThen(Hw.Iec.AtnLow, 'low', 'high'), IfThen(Hw.Iec.ClkLow, 'low', 'high'),
    IfThen(Hw.Iec.DataLow, 'low', 'high')]));
  Line('');
  if Hw.Tape.Present then
    Line(Format('Tape: %s, pulse %d of %d, %s', [Hw.Tape.Name, Hw.Tape.Pos, Hw.Tape.Count, FEmu.Spec.TapeStateText]))
  else
    Line('Tape: none');
  Line(Format('Frame %d, cycle %d of the frame', [Hw.Frames, Hw.FrameCycle]));
end;



{ ---- instructions ---- }

function TC64DebuggerWindow.SymbolName(Addr: Word): string;
begin
  Result := UserSymbols.Lookup(Addr);
  if Result = '' then Result := C64AddressName(Addr);
end;

function TC64DebuggerWindow.NextInstr(Addr: Word): Word;
begin
  Result := Word(Addr + OpLength(FPeek[Addr]));
end;

{ The address of the instruction Count instructions before Addr (a guess: 6502 code can't be read backwards for sure) }
function TC64DebuggerWindow.BackInstr(Addr: Word; Count: Integer): Word;
var
  I, L: Integer;
  Found: Boolean;
begin
  Result := Addr;
  for I := 1 to Count do
  begin
    Found := False;
    for L := 3 downto 1 do
      if NextInstr(Word(Result - L)) = Result then
      begin
        Result := Word(Result - L);
        Found := True;
        Break;
      end;
    if not Found then Result := Word(Result - 1);
  end;
end;

procedure TC64DebuggerWindow.ShowAt(Addr: Word);
begin
  FDis.ShowAt(Addr);
end;

function TC64DebuggerWindow.ParseAddr(const AText: string; out Addr: Word): Boolean;
var
  V: Integer;
  Err: string;
  S: Word;
begin
  Result := False;
  if Trim(AText) = '' then Exit;
  // A name first (a symbol or a KERNAL/chip name), then an expression
  if UserSymbols.Find(Trim(AText), S) or C64FindName(Trim(AText), S) then
  begin
    Addr := S;
    Exit(True);
  end;
  FEmu.Lock;
  try
    Result := FEmu.Spec.C64Hw.EvalCondition(AText, V, Err);
  finally
    FEmu.Unlock;
  end;
  if Result then Addr := Word(V);
end;

function TC64DebuggerWindow.EvalValue(const AText: string; out Value: Integer): Boolean;
var
  Err: string;
begin
  FEmu.Lock;
  try
    Result := FEmu.Spec.C64Hw.EvalCondition(AText, Value, Err);
  finally
    FEmu.Unlock;
  end;
end;

function TC64DebuggerWindow.AskAddress(const ATitle: string; out Addr: Word): Boolean;
var
  S: string;
begin
  Result := False;
  S := '';
  if not InputQuery(ATitle, 'Address, name or expression (hex):', S) then Exit;
  Result := ParseAddr(S, Addr);
  if not Result then MessageDlg('Go to', 'Not an address or a name: ' + S, mtError, [mbOK], 0);
end;

function TC64DebuggerWindow.CondAt(Addr: Word): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(FBpList) do
    if (Addr >= FBpList[I].First) and (Addr <= FBpList[I].Last) then Result := FBpList[I].Cond;
end;

function TC64DebuggerWindow.BpCount: Integer;
begin
  Result := Length(FBpList);
end;

function TC64DebuggerWindow.BpEntryAt(Index: Integer): TBpEntry;
begin
  Result := FBpList[Index];
end;

function TC64DebuggerWindow.WatchCount: Integer;
begin
  Result := FWatchValues.Count;
end;

function TC64DebuggerWindow.WatchLine(Index: Integer): string;
begin
  Result := FWatchValues[Index];
end;

{ ---- showing everything ---- }

procedure TC64DebuggerWindow.UpdateAll;
var
  Idle: Boolean;
begin
  Idle := not FRunning;
  FRunButton.Enabled := Idle;
  FBreakButton.Enabled := not Idle;
  FStepButton.Enabled := Idle;
  FOverButton.Enabled := Idle;
  FOutButton.Enabled := Idle;
  FToButton.Enabled := Idle;
  if FRunning then FStatusBar.SimpleText := 'running'
  else if FReason <> '' then FStatusBar.SimpleText := 'stopped: ' + FReason
  else FStatusBar.SimpleText := 'stopped';
  // The disassembly follows the PC while it is stopped, unless the user scrolled away
  if Idle and FFollow then FDis.EnsureVisible(FSnapRegs.PC) else FDis.Invalidate;
  FRegView.Invalidate;
  FMem.Invalidate;
  FZero.Invalidate;
  FBreakView.Invalidate;
  FWatchView.Invalidate;
  if (FSysForm <> nil) and FSysForm.Visible and (Idle or (FSysMemo.Lines.Count = 0)) then
    if FSysMemo.Text <> FSysText then FSysMemo.Text := FSysText;
end;

procedure TC64DebuggerWindow.Refresh(Force: Boolean);
begin
  if not Visible and not Force then Exit;
  Take;
  UpdateAll;
end;

procedure TC64DebuggerWindow.TimerTick(Sender: TObject);
begin
  if Visible then Refresh(False);
end;

procedure TC64DebuggerWindow.BreakHit;
begin
  FFollow := True;
  if not Visible then Show;
  BringToFront;
  Refresh(True);
  ShowAt(FSnapRegs.PC);
end;

{ ---- actions ---- }

procedure TC64DebuggerWindow.Resume;
begin
  FReason := '';
  FFollow := True;
  FEmu.Lock;
  try
    FEmu.Spec.C64Hw.BreakKind := cbkNone;
  finally
    FEmu.Unlock;
  end;
  FEmu.Resume;
  Refresh(True);
end;

procedure TC64DebuggerWindow.DoRun(Sender: TObject);
begin
  if FEmu.Paused then Resume
  else DoBreak(Sender);
end;

procedure TC64DebuggerWindow.DoBreak(Sender: TObject);
begin
  FEmu.PauseAndWait;
  FFollow := True;
  Refresh(True);
  ShowAt(FSnapRegs.PC);
end;

procedure TC64DebuggerWindow.DoStep(Sender: TObject);
begin
  FEmu.PauseAndWait;
  FReason := '';
  FFollow := True;
  FEmu.StepInto;
  Refresh(True);
end;

procedure TC64DebuggerWindow.DoOver(Sender: TObject);
var
  PC: Word;
begin
  FEmu.PauseAndWait;
  Take;
  PC := FSnapRegs.PC;
  if IsSubroutineCall(PC, @Peek) then
  begin
    FEmu.Lock;
    try
      FEmu.Spec.C64Hw.TempBreak := Word(PC + 3);
    finally
      FEmu.Unlock;
    end;
    Resume;
  end
  else
  begin
    FReason := '';
    FFollow := True;
    FEmu.StepInto;
    Refresh(True);
  end;
end;

{ Run until the subroutine returns: to the address the stack holds (+1) }
procedure TC64DebuggerWindow.DoOut(Sender: TObject);
var
  Ret: Word;
begin
  FEmu.PauseAndWait;
  Take;
  Ret := Word((FPeek[Word($0100 or Byte(FSnapRegs.SP + 2))] shl 8) or FPeek[Word($0100 or Byte(FSnapRegs.SP + 1))]) + 1;
  FEmu.Lock;
  try
    FEmu.Spec.C64Hw.TempBreak := Ret;
  finally
    FEmu.Unlock;
  end;
  Resume;
end;

procedure TC64DebuggerWindow.RunToAddr(Addr: Word);
begin
  FEmu.PauseAndWait;
  FEmu.Lock;
  try
    FEmu.Spec.C64Hw.TempBreak := Addr;
  finally
    FEmu.Unlock;
  end;
  Resume;
end;

procedure TC64DebuggerWindow.DoToCursor(Sender: TObject);
begin
  RunToAddr(FDis.SelAddr);
end;

procedure TC64DebuggerWindow.SetBpFlags(Addr: Word; Flags: Byte);
begin
  FEmu.Lock;
  try
    if (Flags and (C64_BP_EXEC or C64_BP_READ or C64_BP_WRITE)) = 0 then Flags := 0;
    FEmu.Spec.C64Hw.SetBreakpoint(Addr, Flags);
  finally
    FEmu.Unlock;
  end;
  Refresh(True);
end;

procedure TC64DebuggerWindow.ToggleBpAt(Addr: Word);
var
  F: Byte;
begin
  F := BpFlagsAt(Addr);
  if (F and C64_BP_EXEC) <> 0 then F := F and not (C64_BP_EXEC or C64_BP_DISABLED) else F := F or C64_BP_EXEC;
  SetBpFlags(Addr, F);
end;

procedure TC64DebuggerWindow.DoToggleBp(Sender: TObject);
begin
  ToggleBpAt(FDis.SelAddr);
end;

procedure TC64DebuggerWindow.DoGoto(Sender: TObject);
var
  A: Word;
begin
  if (ActiveControl = FMem) or (ActiveControl = FZero) then
  begin
    if AskAddress('Go to address in the memory', A) then FMem.GoToAddr(A);
  end
  else if AskAddress('Go to address in the disassembly', A) then FDis.GoToAddr(A);
end;

procedure TC64DebuggerWindow.SetPCAt(Addr: Word);
var
  R: T6502Regs;
begin
  FEmu.Lock;
  try
    R := FEmu.Spec.C64Hw.Cpu.GetRegs;
    R.PC := Addr;
    FEmu.Spec.C64Hw.Cpu.SetRegs(R);
  finally
    FEmu.Unlock;
  end;
  FFollow := True;
  Refresh(True);
end;

procedure TC64DebuggerWindow.SetRegister(Index, Value: Integer);
var
  R: T6502Regs;
begin
  FEmu.Lock;
  try
    R := FEmu.Spec.C64Hw.Cpu.GetRegs;
    case Index of
      0: R.A := Value;
      1: R.X := Value;
      2: R.Y := Value;
      3: R.SP := Value;
      4: R.PC := Value;
      5: R.P := Value;
    end;
    FEmu.Spec.C64Hw.Cpu.SetRegs(R);
  finally
    FEmu.Unlock;
  end;
  Refresh(True);
end;

procedure TC64DebuggerWindow.ToggleFlag(Mask: Byte);
var
  R: T6502Regs;
begin
  FEmu.Lock;
  try
    R := FEmu.Spec.C64Hw.Cpu.GetRegs;
    R.P := R.P xor Mask;
    FEmu.Spec.C64Hw.Cpu.SetRegs(R);
  finally
    FEmu.Unlock;
  end;
  Refresh(True);
end;

procedure TC64DebuggerWindow.PokeAt(Addr: Word; Value: Byte; Ram: Boolean);
begin
  FEmu.Lock;
  try
    if Ram then FEmu.Spec.C64Hw.PokeRam(Addr, Value) else FEmu.Spec.C64Hw.Poke(Addr, Value);
  finally
    FEmu.Unlock;
  end;
  Refresh(True);
end;

procedure TC64DebuggerWindow.DoSymbols(Sender: TObject);
var
  Dlg: TOpenDialog;
  N: Integer;
begin
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Title := 'Load symbols (NAME = $ADDRESS lines, as the assemblers write them)';
    Dlg.Filter := 'Symbol files|*.sym;*.lbl;*.txt;*.lst|All files|*.*';
    if Dlg.Execute then
    begin
      N := UserSymbols.LoadFromFile(Dlg.FileName);
      MessageDlg('Symbols', Format('%d symbols read.', [N]), mtInformation, [mbOK], 0);
      Refresh(True);
    end;
  finally
    Dlg.Free;
  end;
end;

{ The state of the chips and the drives, in a window of its own }
procedure TC64DebuggerWindow.DoSystem(Sender: TObject);
begin
  if FSysForm = nil then
  begin
    FSysForm := TForm.CreateNew(Self);
    FSysForm.Caption := 'Commodore 64 system';
    FSysForm.Position := poOwnerFormCenter;
    FSysForm.Width := 980;
    FSysForm.Height := 520;
    FSysMemo := TMemo.Create(FSysForm);
    FSysMemo.Parent := FSysForm;
    FSysMemo.Align := alClient;
    FSysMemo.ReadOnly := True;
    FSysMemo.ScrollBars := ssBoth;
    FSysMemo.WordWrap := False;
    FSysMemo.Font.Name := MONO_FONT;
    FSysMemo.Font.Size := 10;
    ThemeForm(FSysForm);
  end;
  FSysForm.Show;
  FSysForm.BringToFront;
  Refresh(True);
  FSysMemo.Text := FSysText;
end;

{ Add or change a breakpoint: an address or a range, what stops it, and a condition }
procedure TC64DebuggerWindow.BpDialog(Edit: Boolean; Sel: Integer; DefaultAddr: Word);
var
  F: TForm;
  EFrom, ETo, ECond: TEdit;
  CExec, CRead, CWrite: TCheckBox;
  Lb: TLabel;
  Ok, Cancel: TButton;
  A: Integer;
  First, Last: Word;
  Flags: Byte;
  Err: string;
  OldFlags: Byte;
begin
  if Edit and ((Sel < 0) or (Sel > High(FBpList))) then Exit;
  F := TForm.CreateNew(Self);
  try
    F.Caption := IfThen(Edit, 'Edit breakpoint', 'Add a breakpoint');
    F.Position := poOwnerFormCenter;
    F.BorderStyle := bsDialog;
    F.ClientWidth := 360;
    F.ClientHeight := 190;
    Lb := TLabel.Create(F); Lb.Parent := F; Lb.SetBounds(12, 16, 60, 20); Lb.Caption := 'From:';
    EFrom := TEdit.Create(F); EFrom.Parent := F; EFrom.SetBounds(80, 12, 110, 24);
    Lb := TLabel.Create(F); Lb.Parent := F; Lb.SetBounds(200, 16, 30, 20); Lb.Caption := 'To:';
    ETo := TEdit.Create(F); ETo.Parent := F; ETo.SetBounds(232, 12, 110, 24);
    CExec := TCheckBox.Create(F); CExec.Parent := F; CExec.SetBounds(12, 48, 100, 20); CExec.Caption := 'Execute';
    CRead := TCheckBox.Create(F); CRead.Parent := F; CRead.SetBounds(120, 48, 100, 20); CRead.Caption := 'Read';
    CWrite := TCheckBox.Create(F); CWrite.Parent := F; CWrite.SetBounds(220, 48, 100, 20); CWrite.Caption := 'Write';
    Lb := TLabel.Create(F); Lb.Parent := F; Lb.SetBounds(12, 86, 80, 20); Lb.Caption := 'Condition:';
    ECond := TEdit.Create(F); ECond.Parent := F; ECond.SetBounds(80, 82, 262, 24);
    Lb := TLabel.Create(F); Lb.Parent := F; Lb.SetBounds(12, 114, 340, 20);
    Lb.Caption := 'e.g. A=3 AND X>.10, @C000=FF, #Z=1, T=3 (ranges have no condition)';
    Ok := TButton.Create(F); Ok.Parent := F; Ok.SetBounds(180, 148, 80, 28); Ok.Caption := 'OK'; Ok.ModalResult := mrOk; Ok.Default := True;
    Cancel := TButton.Create(F); Cancel.Parent := F; Cancel.SetBounds(266, 148, 80, 28); Cancel.Caption := 'Cancel'; Cancel.ModalResult := mrCancel;
    CExec.Checked := True;
    OldFlags := 0;
    if Edit then
    begin
      EFrom.Text := Hex4(FBpList[Sel].First);
      ETo.Text := Hex4(FBpList[Sel].Last);
      ECond.Text := FBpList[Sel].Cond;
      OldFlags := FBpList[Sel].Flags;
      CExec.Checked := (OldFlags and C64_BP_EXEC) <> 0;
      CRead.Checked := (OldFlags and C64_BP_READ) <> 0;
      CWrite.Checked := (OldFlags and C64_BP_WRITE) <> 0;
    end
    else EFrom.Text := Hex4(DefaultAddr);
    ThemeForm(F);
    if F.ShowModal <> mrOk then Exit;
    if not ParseAddr(EFrom.Text, First) then
    begin
      MessageDlg('Breakpoint', 'Not an address: ' + EFrom.Text, mtError, [mbOK], 0);
      Exit;
    end;
    if Trim(ETo.Text) = '' then Last := First
    else if not ParseAddr(ETo.Text, Last) then
    begin
      MessageDlg('Breakpoint', 'Not an address: ' + ETo.Text, mtError, [mbOK], 0);
      Exit;
    end;
    if Last < First then Last := First;
    Flags := 0;
    if CExec.Checked then Flags := Flags or C64_BP_EXEC;
    if CRead.Checked then Flags := Flags or C64_BP_READ;
    if CWrite.Checked then Flags := Flags or C64_BP_WRITE;
    if Flags = 0 then Exit;
    if (Last > First) and (Trim(ECond.Text) <> '') then
    begin
      MessageDlg('Breakpoint', 'A range has no condition.', mtError, [mbOK], 0);
      Exit;
    end;
    FEmu.Lock;
    try
      if Edit then
        for A := FBpList[Sel].First to FBpList[Sel].Last do FEmu.Spec.C64Hw.SetBreakpoint(A, 0);
      for A := First to Last do FEmu.Spec.C64Hw.SetBreakpoint(A, Flags or (OldFlags and C64_BP_DISABLED));
      if not FEmu.Spec.C64Hw.SetCondition(First, ECond.Text, Err) then
      begin
        FEmu.Unlock;
        try
          MessageDlg('Breakpoint', 'The condition is not valid: ' + Err, mtError, [mbOK], 0);
        finally
          FEmu.Lock;
        end;
      end;
    finally
      FEmu.Unlock;
    end;
  finally
    F.Free;
  end;
  Refresh(True);
end;

procedure TC64DebuggerWindow.DoAddBp(Sender: TObject);
begin
  BpDialog(False, -1, FDis.SelAddr);
end;

procedure TC64DebuggerWindow.EditBpAt(Index: Integer);
begin
  BpDialog(True, Index, 0);
end;

procedure TC64DebuggerWindow.DeleteBp(Index: Integer);
var
  A: Integer;
begin
  if (Index < 0) or (Index > High(FBpList)) then Exit;
  FEmu.Lock;
  try
    for A := FBpList[Index].First to FBpList[Index].Last do FEmu.Spec.C64Hw.SetBreakpoint(A, 0);
  finally
    FEmu.Unlock;
  end;
  FBreakView.Sel := -1;
  Refresh(True);
end;

procedure TC64DebuggerWindow.ToggleBpEnabled(Index: Integer);
var
  A: Integer;
begin
  if (Index < 0) or (Index > High(FBpList)) then Exit;
  FEmu.Lock;
  try
    for A := FBpList[Index].First to FBpList[Index].Last do
      FEmu.Spec.C64Hw.SetBreakpoint(A, FEmu.Spec.C64Hw.GetBreakpoint(A) xor C64_BP_DISABLED);
  finally
    FEmu.Unlock;
  end;
  Refresh(True);
end;

procedure TC64DebuggerWindow.DoClearBps(Sender: TObject);
begin
  FEmu.Lock;
  try
    FEmu.Spec.C64Hw.ClearBreakpoints;
  finally
    FEmu.Unlock;
  end;
  FBreakView.Sel := -1;
  Refresh(True);
end;

procedure TC64DebuggerWindow.DoAddWatch(Sender: TObject);
var
  S: string;
begin
  S := '';
  if InputQuery('Watch', 'Expression (e.g. @D012, A, @(FB)):', S) and (Trim(S) <> '') then
  begin
    FWatchText.Add(S);
    Refresh(True);
  end;
end;

procedure TC64DebuggerWindow.DeleteWatch(Index: Integer);
begin
  if (Index >= 0) and (Index < FWatchText.Count) then
  begin
    FWatchText.Delete(Index);
    FWatchView.Sel := -1;
    Refresh(True);
  end;
end;

procedure TC64DebuggerWindow.FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_F5: begin DoRun(Self); Key := 0; end;
    VK_F7: begin DoStep(Self); Key := 0; end;
    VK_F8: begin DoToggleBp(Self); Key := 0; end;
    VK_F9: begin DoToCursor(Self); Key := 0; end;
    VK_F10: begin DoOver(Self); Key := 0; end;
    VK_F11: begin DoOut(Self); Key := 0; end;
    VK_G: if ssCtrl in Shift then begin DoGoto(Self); Key := 0; end;
  end;
end;

end.

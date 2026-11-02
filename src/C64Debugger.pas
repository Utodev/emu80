{ C64Debugger: the debugger of the Commodore 64's 6510, laid out and used like the Z80 debugger: the disassembly (with the
  labels of the ROMs from roms/c64.sym while that ROM is paged in, the names of the chip registers and the user's symbols),
  the registers, the flags and the memory configuration on its right with the stack beside them and the ports (the last
  accesses to the chips) and the zero page under them, and at
  the bottom the memory (with its XOR key), the breakpoints (on execution and on reads and writes, with conditions such as
  "A=3 AND @C000=FF") and the watches. Every value is changed where it is shown: a click opens a box over it. A
  right-click on any number or label offers to go to it in the disassembly or to see it in the memory. A button opens the
  registers of the VIC-II, the SID and the CIAs (also changed in place) and the state of the chips and the drives. Over a
  mnemonic the help says what the instruction does (C64Help).

  The window works on copies of the memory and registers taken under the emulator's lock (after every stop or step, and a few
  times a second while the machine runs), so drawing never races the emulation. F5 runs or pauses, F7 steps into (Shift+F7 steps back), F10 steps over,
  F11 steps out, F9 runs to the selected line, F8 puts or takes away a breakpoint on it, Ctrl+G goes to an address, Ctrl+F
  searches and F3 searches again. }
unit C64Debugger;

{$mode objfpc}{$H+}
{$R-}{$Q-}

interface

uses
  Classes, SysUtils, Types, Math, StrUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, ComCtrls, Dialogs, Menus,
  LCLType, Clipbrd, fpjson, jsonparser, Emulator, Spectrum, C64, Cpu6510, C64Disasm, C64Help, C64Expr, C64Vic, C64Cia,
  C64Drive, C64Disk, C64Opcodes, Symbols, ModernUI, Icons, DelayHint, MemText, DebugFiles;

type
  TC64DebuggerWindow = class;

  TSpotKind = (
    skInfo,       // a hex value: its decimal value as a hint
    skLabel,      // a label: Value is its address, the hint its name and description
    skHint,       // text shown as a hint
    skDoc,        // longer help, shown after the mouse rests on it a second
    skReg,        // click to change; Target = register (0 A, 1 X, 2 Y, 3 SP, 4 PC, 5 P)
    skFlag,       // click to toggle; Target = the flag's mask
    skByte,       // click to change the byte of memory at Target
    skXorByte,    // as skByte, in the memory zone: shown and typed XORed with its key (and in the RAM only, if chosen)
    skAscii,      // the memory zone's text column: click to type text at Target
    skWord,       // click to change the 16-bit word at Target (low byte first)
    skIo,         // click to change a register of the VIC-II, the SID or a CIA; Target = its address
    skBank        // click to choose the memory configuration
  );

  TSpot = record
    R: TRect;
    Kind: TSpotKind;
    Value: Integer;
    Digits: Integer;
    Target: Integer;
    Text: string;
  end;

  { Base of the custom-drawn zones: spots (values with a hint, a click or a box to change them) and the menu items
    "Go to X" and "View data at X" for a number or a label under the mouse }
  TC64View = class(TCustomControl)
  protected
    FWin: TC64DebuggerWindow;
    FLineH, FCharW: Integer;
    FSpots: array of TSpot;
    FSpotCount: Integer;
    FHintSpot: Integer;
    FBoldFont: TFont;
    FEditor: TEdit;
    FEditSpot: TSpot;
    FGotoMenu: TPopupMenu;
    FGotoAddr: Word;
    procedure MeasureFont;
    function VisibleLines: Integer;
    procedure ClearSpots;
    procedure AddSpot(X, Y, Chars: Integer; Kind: TSpotKind; Value: Integer; Digits: Integer = 0; Target: Integer = 0;
      const AText: string = '');
    function DrawText(X, Y: Integer; const S: string; AColor: TColor; Bold: Boolean): Integer;
    { Underlined: a value chosen from a menu }
    procedure DrawLink(X, Y: Integer; const S: string; AColor: TColor);
    function SpotAt(X, Y: Integer): Integer;
    function ClickSpot(Index: Integer): Boolean; virtual;
    procedure BeginEdit(const Spot: TSpot);
    procedure EditorKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure EditorExit(Sender: TObject);
    procedure EndEdit(Commit: Boolean);
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure DoEnter; override;
    procedure DoExit; override;
    procedure DrawFocus;
    { "Go to X" and "View data at X" (and a separator) at the top of Menu, for the number or label at X, Y; False (and the
      items hidden) if there is none }
    function PrepareGoto(Menu: TPopupMenu; X, Y: Integer): Boolean;
    procedure GotoClick(Sender: TObject);
    procedure ViewDataClick(Sender: TObject);
    { The view has a context menu of its own (and calls PrepareGoto) }
    function HasOwnMenu: Boolean; virtual;
    function AddItem(Menu: TPopupMenu; const ACaption: string; AHandler: TNotifyEvent; const AHint: string = ''): TMenuItem;
  public
    constructor CreateView(AWin: TC64DebuggerWindow);
    destructor Destroy; override;
    function Editing: Boolean;
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
    FSel: Integer;                  // address of the selected line (-1 none: the PC)
    FLines: array of TDisLine;
    FPopup: TPopupMenu;
    FMenuAddr: Word;
    FTypeItems: array[0..3] of TMenuItem;   // execution, read, write, read or write
    FEnabledItem, FRemoveItem, FLabelItem: TMenuItem;
    FBack: array of LongWord;       // where the view was before each jump: top shl 16 or selection
    FSearch: string;
    procedure Layout;
    function LineAt(Y: Integer): Integer;
    function DrawInstruction(X, Y: Integer; Addr: Word; OnBreak, OnPC: Boolean): Integer;
    procedure DrawCheck(X, Y: Integer; Ok: Boolean);
    procedure DrawArrow(X, Y: Integer);
    procedure PushBack;
    procedure MenuGoto(Sender: TObject);
    procedure MenuSearch(Sender: TObject);
    procedure MenuExport(Sender: TObject);
    procedure MenuLabel(Sender: TObject);
    procedure MenuToggle(Sender: TObject);
    procedure MenuType(Sender: TObject);
    procedure MenuCondition(Sender: TObject);
    procedure MenuEnabled(Sender: TObject);
    procedure MenuRemove(Sender: TObject);
    procedure MenuRunTo(Sender: TObject);
    procedure MenuSetPC(Sender: TObject);
  protected
    function HasOwnMenu: Boolean; override;
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
    { A line as the view shows it: address, bytes, label and instruction }
    function LineText(Addr: Word): string;
    procedure Search;
    procedure SearchNext;
    property Sel: Integer read FSel write FSel;
  end;

  { The registers, the flags, the interrupt lines and the memory configuration }
  TC64RegView = class(TC64View)
  protected
    procedure Paint; override;
    function ClickSpot(Index: Integer): Boolean; override;
  end;

  { The stack: from SP upwards, as 16-bit words (each one changed in place) }
  TC64StackView = class(TC64View)
  private
    FOfs: Integer;
    FStep: Integer;
  protected
    procedure Paint; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  end;

  { The ports: the last accesses of the processor to the chips' registers and the 6510's port, newest first }
  TC64PortView = class(TC64View)
  private
    FOfs: Integer;
    FStep: Integer;
  protected
    procedure Paint; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  end;

  { The zero page: 8 bytes a row (each one changed in place) }
  TC64ZeroView = class(TC64View)
  private
    FTop: Integer;
    FMenu: TPopupMenu;
    FMenuAddr: Integer;
    FWatchItem, FReadItem, FWriteItem: TMenuItem;
    procedure MenuWatch(Sender: TObject);
    procedure MenuRead(Sender: TObject);
    procedure MenuWrite(Sender: TObject);
  protected
    function HasOwnMenu: Boolean; override;
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor CreateView(AWin: TC64DebuggerWindow);
    procedure GoToAddr(Addr: Byte);
  end;

  { The memory: 16 bytes and their characters a row, XORed with a key; text typed in the text column }
  TC64HexView = class(TC64View)
  private
    FTop: Word;
    FXor: Byte;
    FTextCursor: Integer;   // address being typed in the text column, -1 if none
    FMenu: TPopupMenu;
    FWatchItem, FSpriteItem, FReadItem, FWriteItem, FCopyTextItem, FCopyItem, FPasteItem: TMenuItem;
    FMenuAddr: Integer;     // byte under the mouse on right-click, -1 if none
    FSprites: Boolean;      // the bytes as 8x8 cells
    FSpriteRowBytes, FSpriteRows: Integer;
    FSelA, FSelB: Integer;  // text column selection: anchor and end (-1 = none)
    FDragging: Boolean;
    FSearchText: string;
    FSearchHex, FSearchCase: Boolean;
    procedure SetXor(Value: Byte);
    function HasSel: Boolean;
    function SelFirst: Word;
    function SelLast: Word;
    procedure BreakRange(out First, Last: Word);
    function CopyRange(out First, Last: Integer): Boolean;
    function ByteAt(Addr: Word): Byte;
    procedure PasteAt(Addr: Word);
    procedure PaintSprites;
    function RowBytes: Integer;
    function Rows: Integer;
    procedure MenuGoTo(Sender: TObject);
    procedure MenuWatch(Sender: TObject);
    procedure MenuRead(Sender: TObject);
    procedure MenuWrite(Sender: TObject);
    procedure MenuSprites(Sender: TObject);
    procedure MenuCopyText(Sender: TObject);
    procedure MenuCopy(Sender: TObject);
    procedure MenuPaste(Sender: TObject);
    procedure MenuSearch(Sender: TObject);
    procedure MenuExport(Sender: TObject);
    procedure MenuImport(Sender: TObject);
    procedure MenuExportBinary(Sender: TObject);
    procedure MenuImportBinary(Sender: TObject);
  protected
    function HasOwnMenu: Boolean; override;
    procedure Paint; override;
    function ClickSpot(Index: Integer): Boolean; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure KeyPress(var Key: Char); override;
    procedure DoExit; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor CreateView(AWin: TC64DebuggerWindow);
    procedure GoToAddr(Addr: Word);
    procedure Search;
    procedure SearchNext;
    function VisibleBytes: Integer;
    { Escape: the typing in the text column, or the selection, ends (True), if there was one }
    function CancelTyping: Boolean;
    property TopAddr: Word read FTop;
    property XorValue: Byte read FXor write SetXor;
  end;

  { The breakpoints }
  TC64BreakView = class(TC64View)
  private
    FSel: Integer;
    FMenu: TPopupMenu;
    FEditItem, FEnabledItem, FRemoveItem, FShowItem, FRemoveAllItem: TMenuItem;
    function RowAt(Y: Integer): Integer;
    function HaveSel: Boolean;
    procedure MenuAdd(Sender: TObject);
    procedure MenuEdit(Sender: TObject);
    procedure MenuEnabled(Sender: TObject);
    procedure MenuRemove(Sender: TObject);
    procedure MenuShow(Sender: TObject);
    procedure MenuRemoveAll(Sender: TObject);
    procedure MenuSave(Sender: TObject);
    procedure MenuLoad(Sender: TObject);
  protected
    function HasOwnMenu: Boolean; override;
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DblClick; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor CreateView(AWin: TC64DebuggerWindow);
    property Sel: Integer read FSel write FSel;
  end;

  { The watches: expressions, with their values }
  TC64WatchView = class(TC64View)
  private
    FSel: Integer;
    FMenu: TPopupMenu;
    FRemoveItem: TMenuItem;
    procedure MenuAdd(Sender: TObject);
    procedure MenuRemove(Sender: TObject);
    procedure MenuSave(Sender: TObject);
    procedure MenuLoad(Sender: TObject);
  protected
    function HasOwnMenu: Boolean; override;
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor CreateView(AWin: TC64DebuggerWindow);
    property Sel: Integer read FSel write FSel;
  end;

  { The registers of the VIC-II, the SID and the CIAs (System window), changed in place }
  TC64ChipView = class(TC64View)
  protected
    procedure Paint; override;
  end;

  TBpEntry = record
    First, Last: Word;
    Flags: Byte;
    Cond: string;
    Hits: Integer;      // times reached, if the condition uses T (else -1)
  end;

  TC64DebuggerWindow = class(TForm)
  private
    FEmu: TEmulator;
    FTimer: TTimer;
    FImages: TImageList;
    FToolbar: TToolBar;
    FRunButton, FBreakButton, FStepButton, FOverButton, FOutButton, FToButton: TToolButton;
    FStatusBar: TStatusBar;
    FDataPanel, FRightPanel, FTopPanel, FLowPanel, FMemZone, FBreakZone, FWatchZone, FRegZone, FStackZone, FPortZone,
      FZeroZone: TPanel;
    FWatchSplit: TSplitter;
    FWatchShare: Double;
    FRightMinH: Integer;
    FShrink: Integer;   // UPPER_CUT lines, in pixels: the window is that much shorter, the data zone as tall
    FDis: TC64DisView;
    FRegView: TC64RegView;
    FStack: TC64StackView;
    FPorts: TC64PortView;
    FZero: TC64ZeroView;
    FMem: TC64HexView;
    FBreakView: TC64BreakView;
    FWatchView: TC64WatchView;
    FRamCheck: TCheckBox;
    FXorEdit: TEdit;
    FBankMenu: TPopupMenu;
    FSysForm: TForm;
    FSysMemo: TMemo;
    FChipView: TC64ChipView;
    FLaidOut: Boolean;
    FNotice: string;
    FNoticeTime: QWord;
    // The copies, taken under the emulator's lock
    FPeek: array[0..65535] of Byte;
    FRam: array[0..65535] of Byte;
    FVicRegs: array[0..$3F] of Byte;
    FSidRegs: array[0..$1F] of Byte;
    FCiaRegs: array[0..1, 0..$F] of Byte;
    FSnapRegs, FPrevRegs: T6502Regs;
    FBank, FPortValue, FDdrValue: Byte;
    FMemA, FMemD, FMemE: Integer;   // what the processor sees at A000, D000 and E000 (TC64.MemoryAt)
    FRunning, FHavePrev: Boolean;
    FWatchText: TStringList;
    FWatchValues: TStringList;
    FWatchNumbers: array of Integer;   // each watch's value (-1 if it can't be worked out)
    FSysText: string;
    FReason: string;
    FIrqText, FNmiText: string;
    FIoLog: array of TC64IoAccess;   // newest first
    FInstrNow: LongWord;             // the machine's InstrCount: an access with it was made by the last instruction
    FHistory: TStringList;           // Ctrl+G: the last addresses gone to, newest first
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
    procedure DoStepBack(Sender: TObject);
    procedure DoOpcodes(Sender: TObject);
    procedure DoToggleBp(Sender: TObject);
    procedure DoGoto(Sender: TObject);
    procedure DoSymbols(Sender: TObject);
    procedure DoSystem(Sender: TObject);
    procedure RamChange(Sender: TObject);
    procedure XorChange(Sender: TObject);
    procedure BankClick(Sender: TObject);
    procedure FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure WindowClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FocusMainWindow(Data: PtrInt);
    procedure AppHint(Sender: TObject);
    procedure Take;
    function SystemText: string;
    procedure UpdateAll;
    procedure Resume;
    procedure TakeBreakpoints;
    procedure LoadRomSymbols;
  public
    constructor CreateFor(AOwner: TComponent; AEmu: TEmulator);
    destructor Destroy; override;
    { Stop the machine where it is and show it (a breakpoint was hit) }
    procedure BreakHit;
    procedure Refresh(Force: Boolean);
    procedure ShowAt(Addr: Word);
    procedure ShowNotice(const AText: string);
    // What the views ask for
    function Peek(Addr: Word): Byte;
    function PeekRamAt(Addr: Word): Byte;
    function VicReg(I: Integer): Byte;
    function SidReg(I: Integer): Byte;
    function CiaReg(N, I: Integer): Byte;
    procedure SetFollow(Value: Boolean);
    procedure DoAddBp(Sender: TObject);
    procedure DoClearBps(Sender: TObject);
    procedure DoAddWatch(Sender: TObject);
    procedure AddWatchText(const S: string);
    function NextInstr(Addr: Word): Word;
    function BackInstr(Addr: Word; Count: Integer): Word;
    { The name of an address: the user's symbol, then the ROM's label (while that ROM is paged in), then the KERNAL's entry
      point or the chip register ('' if none) }
    function SymbolName(Addr: Word): string;
    { The name of the address, or its hex value }
    function NameOrHex(Addr: Word): string;
    { What the hint over a name says: every name the address has and the label's description }
    function LabelHint(Addr: Word): string;
    { The address of a name: the user's symbols, the ROMs' labels, the chips' registers }
    function FindSymbol(const AName: string; out Addr: Word): Boolean;
    function ParseAddr(const AText: string; out Addr: Word): Boolean;
    function EvalValue(const AText: string; out Value: Integer): Boolean;
    function BpFlagsAt(Addr: Word): Byte;
    function BpIndexAt(Addr: Word): Integer;
    function CondAt(Addr: Word): string;
    function BpCount: Integer;
    function BpEntryAt(Index: Integer): TBpEntry;
    function WatchCount: Integer;
    function WatchLine(Index: Integer): string;
    function WatchNumber(Index: Integer): Integer;
    procedure ToggleBpAt(Addr: Word);
    procedure SetBpFlags(Addr: Word; Flags: Byte);
    { A read or write breakpoint from the memory zones: Bit on or off for the breakpoint at Addr, or a new one over
      First-Last }
    procedure ToggleDataBreak(Addr, First, Last: Word; Bit: Byte);
    procedure RunToAddr(Addr: Word);
    procedure SetPCAt(Addr: Word);
    procedure SetRegister(Index, Value: Integer);
    procedure ToggleFlag(Mask: Byte);
    procedure PokeAt(Addr: Word; Value: Byte; Ram: Boolean);
    { The memory zone's byte: in the RAM under the ROMs and the I/O if "RAM only" is on }
    procedure PokeMem(Addr: Word; Value: Byte);
    procedure PokeIoAt(Addr: Word; Value: Byte);
    procedure WriteBytes(Addr: Word; const Values: TBytes);
    { The memory configuration: LORAM, HIRAM and CHAREN (bits 0-2 of the processor port) }
    procedure SetBank(Bank: Integer);
    procedure ChooseBank;
    { Add (Index < 0) or change a breakpoint; a new one starts at DefaultAddr }
    procedure BpDialog(Index: Integer; DefaultAddr: Word);
    procedure EditBpAt(Index: Integer);
    procedure ToggleBpEnabled(Index: Integer);
    procedure DeleteBp(Index: Integer);
    procedure DeleteWatch(Index: Integer);
    procedure SaveBreaksAs;
    procedure LoadBreaksAsk;
    procedure SaveWatchesAs;
    procedure LoadWatchesAsk;
    procedure EditLabel(Addr: Word);
    procedure GoToCode(Addr: Word);
    procedure ViewData(Addr: Word);
    function RamOnly: Boolean;
    { Go to: the address typed, one of the last ones (the list) or the PC (its button); not AGoTo: just an address }
    function AskAddress(const ATitle: string; var Addr: Word; AGoTo: Boolean = True): Boolean;
    function AskRange(const ACaption: string; var Addr: Word; var Len: Integer): Boolean;
    procedure ExportMemory;
    procedure ImportMemory;
    procedure ExportBinary;
    procedure ImportBinary;
    procedure ExportAssembler(Start: Word);
    property Regs: T6502Regs read FSnapRegs;
    property Prev: T6502Regs read FPrevRegs;
    property HavePrev: Boolean read FHavePrev;
    property Running: Boolean read FRunning;
    property IrqText: string read FIrqText;
    property NmiText: string read FNmiText;
    function IoLogCount: Integer;
    function IoLogEntry(Index: Integer): TC64IoAccess;
    property InstrNow: LongWord read FInstrNow;
    { Load a watches file: the C64 debugger's (expressions) or the Z80 debugger's (addresses: the byte there) }
    function LoadWatchesFile(const FileName: string; out Error: string): Boolean;
    property Bank: Byte read FBank;
    property PortValue: Byte read FPortValue;
    property DdrValue: Byte read FDdrValue;
    property MemA: Integer read FMemA;
    property MemD: Integer read FMemD;
    property MemE: Integer read FMemE;
    property StepCount: Integer read FStepCount;
    property SnapPC: Word read FSnapRegs.PC;
    property Mem: TC64HexView read FMem;
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
  MEM_NAMES: array[0..4] of string = ('RAM', 'BASIC', 'KERNAL', 'CHAR', 'I/O');
  GUTTER_W = 40;      // breakpoint type, "?" if conditional, execution arrow
  MAX_LABEL = 20;     // longer labels are cut, with the full name as a hint
  HEX_BYTES = 16;     // bytes per row in the memory view
  ZP_BYTES = 8;       // bytes per row in the zero page
  LOW_ROWS = 3;       // lines of the stack and the zero page, at least
  UPPER_CUT = 6;      // lines the disassembly, the stack and the zero page give up from the first layout
  REG_LINES = 10;     // lines of text of the registers zone (see TC64RegView.Paint)
  REG_COLS = 28;      // its columns
  CLICKABLE = [skReg, skFlag, skByte, skXorByte, skWord, skIo, skBank];

function Hex2(V: Integer): string;
begin
  Result := IntToHex(V and $FF, 2);
end;

function Hex4(V: Integer): string;
begin
  Result := IntToHex(V and $FFFF, 4);
end;

{ Hex number with optional $, 0x prefix or h suffix }
function ParseHex(const Text: string; out Value: Integer): Boolean;
var
  S: string;
begin
  S := UpperCase(Trim(Text));
  if (S <> '') and (S[1] = '$') then Delete(S, 1, 1)
  else if Copy(S, 1, 2) = '0X' then Delete(S, 1, 2)
  else if (S <> '') and (S[Length(S)] = 'H') then Delete(S, Length(S), 1);
  Value := StrToIntDef('$' + S, -1);
  Result := (S <> '') and (Value >= 0);
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

function SelColor: TColor;
begin
  Result := TC(RGBToColor(210, 225, 250));
end;

{ What the processor sees at A000, D000 and E000 with a memory configuration (bits 0-2: LORAM, HIRAM, CHAREN) }
function BankText(B: Integer): string;
var
  A, D, E: string;
begin
  if (B and 3) = 3 then A := 'BASIC' else A := 'RAM';
  if (B and 3) = 0 then D := 'RAM' else if (B and 4) <> 0 then D := 'I/O' else D := 'CHAR';
  if (B and 2) <> 0 then E := 'KERNAL' else E := 'RAM';
  Result := Format('%d: A000 %s, D000 %s, E000 %s', [B, A, D, E]);
end;

procedure ShowC64Debugger(Emu: TEmulator);
begin
  if C64DebuggerWindow = nil then C64DebuggerWindow := TC64DebuggerWindow.CreateFor(Application, Emu);
  Emu.PauseAndWait;
  C64DebuggerWindow.Show;
  C64DebuggerWindow.BringToFront;
  C64DebuggerWindow.Refresh(True);
  C64DebuggerWindow.ShowAt(C64DebuggerWindow.SnapPC);
  if C64DebuggerWindow.FDis.CanFocus then C64DebuggerWindow.FDis.SetFocus;
end;

type
  { Breakpoint window: the end address follows the start until it is changed by hand }
  TEndFollower = class
    StartEdit, EndEdit: TEdit;
    Own: Boolean;
    Updating: Boolean;
    procedure StartChange(Sender: TObject);
    procedure EndChange(Sender: TObject);
  end;

procedure TEndFollower.StartChange(Sender: TObject);
begin
  if Own then Exit;
  Updating := True;
  EndEdit.Text := StartEdit.Text;
  Updating := False;
end;

procedure TEndFollower.EndChange(Sender: TObject);
begin
  if not Updating then Own := not SameText(Trim(EndEdit.Text), Trim(StartEdit.Text));
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

procedure TC64View.MeasureNow;
begin
  MeasureFont;
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

procedure TC64View.DrawLink(X, Y: Integer; const S: string; AColor: TColor);
begin
  Canvas.Font := Font;
  Canvas.Font.Style := [fsUnderline];
  Canvas.Font.Color := AColor;
  Canvas.Brush.Style := bsClear;
  Canvas.TextOut(X, Y, S);
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

function TC64View.Editing: Boolean;
begin
  Result := (FEditor <> nil) and FEditor.Visible;
end;

function TC64View.ClickSpot(Index: Integer): Boolean;
begin
  Result := True;
  case FSpots[Index].Kind of
    skReg, skByte, skXorByte, skWord, skIo: BeginEdit(FSpots[Index]);
    skFlag: FWin.ToggleFlag(FSpots[Index].Target);
    skBank: FWin.ChooseBank;
  else
    Result := False;
  end;
end;

{ A box over the value: Enter applies (a hex number, or an expression), Escape or leaving cancels }
procedure TC64View.BeginEdit(const Spot: TSpot);
begin
  if FEditor = nil then
  begin
    FEditor := TEdit.Create(Self);
    FEditor.Parent := Self;
    FEditor.Font := Font;
    FEditor.OnKeyDown := @EditorKeyDown;
    FEditor.OnExit := @EditorExit;
    FEditor.Tag := THEME_OWN_COLOURS;
  end;
  // Black ink on white, in both themes
  FEditor.Color := clWhite;
  FEditor.Font.Color := clBlack;
  FEditSpot := Spot;
  FEditor.SetBounds(Spot.R.Left - 3, Spot.R.Top - 2, (Spot.Digits + 2) * FCharW + 6, Spot.R.Bottom - Spot.R.Top + 6);
  FEditor.MaxLength := 0;
  FEditor.Text := IntToHex(Spot.Value, Spot.Digits);
  FEditor.Visible := True;
  FEditor.SetFocus;
  FEditor.SelectAll;
end;

procedure TC64View.EditorKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_RETURN: begin EndEdit(True); Key := 0; end;
    VK_ESCAPE: begin EndEdit(False); Key := 0; end;
  end;
end;

procedure TC64View.EditorExit(Sender: TObject);
begin
  EndEdit(False);
end;

procedure TC64View.EndEdit(Commit: Boolean);
var
  V, Limit: Integer;
begin
  if not Editing then Exit;
  FEditor.Visible := False;
  if Commit then
  begin
    if FEditSpot.Digits <= 2 then Limit := $FF else Limit := $FFFF;
    if not ParseHex(FEditor.Text, V) and not FWin.EvalValue(FEditor.Text, V) then
    begin
      Beep;
      Exit;
    end;
    if (V < 0) or (V > Limit) then
    begin
      Beep;
      Exit;
    end;
    case FEditSpot.Kind of
      skReg: FWin.SetRegister(FEditSpot.Target, V);
      skByte: FWin.PokeAt(FEditSpot.Target, V, False);
      // Typed as the zone shows it: stored XORed back with the key
      skXorByte: FWin.PokeMem(FEditSpot.Target, V xor FWin.Mem.XorValue);
      skWord:
        begin
          FWin.PokeAt(FEditSpot.Target, V and $FF, False);
          FWin.PokeAt(Word(FEditSpot.Target + 1), V shr 8, False);
        end;
      skIo: FWin.PokeIoAt(FEditSpot.Target, V);
    end;
  end;
  if CanFocus then SetFocus;
end;

const
  GOTO_TAG = 900;
  GOTO_ITEMS = 3;     // Go to, View data at and a separator, first in a menu

function TC64View.HasOwnMenu: Boolean;
begin
  Result := False;
end;

function TC64View.AddItem(Menu: TPopupMenu; const ACaption: string; AHandler: TNotifyEvent; const AHint: string): TMenuItem;
begin
  Result := TMenuItem.Create(Menu);
  Result.Caption := ACaption;
  Result.OnClick := AHandler;
  Result.Hint := AHint;
  Menu.Items.Add(Result);
end;

function TC64View.PrepareGoto(Menu: TPopupMenu; X, Y: Integer): Boolean;
var
  Spot, I: Integer;
  What: string;
  Item: TMenuItem;
begin
  // The two items and a separator, made once at the top of the menu
  if (Menu.Items.Count = 0) or (Menu.Items[0].Tag <> GOTO_TAG) then
  begin
    Item := TMenuItem.Create(Menu);
    Item.Tag := GOTO_TAG;
    Item.OnClick := @GotoClick;
    Menu.Items.Insert(0, Item);
    Item := TMenuItem.Create(Menu);
    Item.Tag := GOTO_TAG;
    Item.OnClick := @ViewDataClick;
    Menu.Items.Insert(1, Item);
    Item := TMenuItem.Create(Menu);
    Item.Tag := GOTO_TAG;
    Item.Caption := '-';
    Menu.Items.Insert(2, Item);
  end;
  Spot := SpotAt(X, Y);
  Result := (Spot >= 0) and (FSpots[Spot].Kind in [skInfo, skLabel, skReg, skByte, skXorByte, skWord, skIo]) and
    (FSpots[Spot].Value >= 0) and (FSpots[Spot].Value <= $FFFF);
  if Result then
  begin
    FGotoAddr := Word(FSpots[Spot].Value);
    // As it is shown: the label, or the number
    if FSpots[Spot].Kind = skLabel then What := FWin.NameOrHex(FGotoAddr)
    else if FSpots[Spot].Digits = 2 then What := Hex2(FSpots[Spot].Value)
    else What := Hex4(FGotoAddr);
    Menu.Items[0].Caption := 'Go to ' + What;
    Menu.Items[1].Caption := 'View data at ' + What;
  end;
  for I := 0 to 2 do Menu.Items[I].Visible := Result;
  // Nothing else in the menu: the separator isn't needed either
  if Menu.Items.Count = 3 then Menu.Items[2].Visible := False;
end;

procedure TC64View.GotoClick(Sender: TObject);
begin
  FWin.GoToCode(FGotoAddr);
end;

procedure TC64View.ViewDataClick(Sender: TObject);
begin
  FWin.ViewData(FGotoAddr);
end;

procedure TC64View.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Spot: Integer;
  P: TPoint;
begin
  inherited MouseDown(Button, Shift, X, Y);
  DelayedHint.Cancel;
  if TabStop and CanFocus then SetFocus;
  if (Button = mbRight) and not HasOwnMenu then
  begin
    if FGotoMenu = nil then FGotoMenu := TPopupMenu.Create(Self);
    if PrepareGoto(FGotoMenu, X, Y) then
    begin
      P := ClientToScreen(Point(X, Y));
      FGotoMenu.PopUp(P.X, P.Y);
    end;
    Exit;
  end;
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
  if (Spot >= 0) and (FSpots[Spot].Kind in CLICKABLE) then Cursor := crHandPoint else Cursor := crDefault;
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
  if FSpots[Spot].Kind in [skLabel, skHint, skBank] then Hint := FSpots[Spot].Text
  else
  begin
    // The decimal value of the hex number under the mouse; a 16-bit one: the names it has
    Hint := IntToStr(FSpots[Spot].Value);
    if FSpots[Spot].Text <> '' then Hint := FSpots[Spot].Text + ': ' + Hint
    else if (FSpots[Spot].Digits >= 4) and (FSpots[Spot].Value >= 0) and (FSpots[Spot].Value <= $FFFF) then
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

{ ---- TC64DisView ---- }

function TC64DisView.HasOwnMenu: Boolean;
begin
  Result := True;
end;

constructor TC64DisView.CreateView(AWin: TC64DebuggerWindow);
begin
  inherited CreateView(AWin);
  FSel := -1;
  FPopup := TPopupMenu.Create(Self);
  AddItem(FPopup, 'Go to address...  (Ctrl+G)', @MenuGoto);
  AddItem(FPopup, 'Search...  (Ctrl+F, F3: next)', @MenuSearch);
  AddItem(FPopup, 'Export as assembler (.asm)...', @MenuExport);
  FLabelItem := AddItem(FPopup, 'Add label...', @MenuLabel);
  AddItem(FPopup, '-', nil);
  AddItem(FPopup, 'Run to here  (F9)', @MenuRunTo);
  AddItem(FPopup, 'Set PC here', @MenuSetPC);
  AddItem(FPopup, '-', nil);
  AddItem(FPopup, 'Toggle breakpoint  (F8, Space)', @MenuToggle);
  FTypeItems[0] := AddItem(FPopup, 'Execution breakpoint', @MenuType);
  FTypeItems[0].Tag := C64_BP_EXEC;
  FTypeItems[1] := AddItem(FPopup, 'Read breakpoint', @MenuType);
  FTypeItems[1].Tag := C64_BP_READ;
  FTypeItems[2] := AddItem(FPopup, 'Write breakpoint', @MenuType);
  FTypeItems[2].Tag := C64_BP_WRITE;
  FTypeItems[3] := AddItem(FPopup, 'Read/write breakpoint (any access)', @MenuType);
  FTypeItems[3].Tag := C64_BP_READ or C64_BP_WRITE;
  AddItem(FPopup, 'Breakpoint with condition...', @MenuCondition);
  FEnabledItem := AddItem(FPopup, 'Enabled', @MenuEnabled);
  AddItem(FPopup, '-', nil);
  FRemoveItem := AddItem(FPopup, 'Remove breakpoint', @MenuRemove);
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

procedure TC64DisView.PushBack;
begin
  if Length(FBack) >= 64 then
  begin
    Move(FBack[1], FBack[0], (Length(FBack) - 1) * SizeOf(LongWord));
    SetLength(FBack, Length(FBack) - 1);
  end;
  SetLength(FBack, Length(FBack) + 1);
  FBack[High(FBack)] := (LongWord(FTop) shl 16) or SelAddr;
end;

procedure TC64DisView.GoToAddr(Addr: Word);
begin
  PushBack;
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
        AddSpot(X, Y - 1, Length(Tok), skLabel, Target, 0, 0, FWin.LabelHint(Word(Target)));
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
  I, J, Y, X, Bit: Integer;
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
      AddSpot(GUTTER_W, Y, Min(Length(Lbl), MAX_LABEL), skLabel, L.Addr, 0, 0, FWin.LabelHint(L.Addr));
      if Length(Lbl) > MAX_LABEL then Lbl := Copy(Lbl, 1, MAX_LABEL - 1) + '~';
      if Active then DrawText(GUTTER_W, Y + 1, Lbl, TC(clWhite), False)
      else DrawText(GUTTER_W, Y + 1, Lbl, LabelColor, False);
    end;

    // The address, then the instruction's bytes (click one to change it)
    X := GUTTER_W + (MAX_LABEL + 1) * FCharW;
    AddSpot(X, Y, 4, skInfo, L.Addr, 4);
    DrawText(X, Y + 1, Hex4(L.Addr), TextColor, False);
    Inc(X, FCharW * 6);
    for J := 0 to L.Len - 1 do
    begin
      AddSpot(X + J * 3 * FCharW, Y, 2, skByte, FWin.Peek(Word(L.Addr + J)), 2, Word(L.Addr + J));
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
  DrawFocus;
end;

procedure TC64DisView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  I: Integer;
  Flags: Byte;
  P: TPoint;
begin
  I := LineAt(Y);
  if I >= 0 then FSel := FLines[I].Addr;
  inherited MouseDown(Button, Shift, X, Y);   // may start changing a byte
  if I < 0 then Exit;
  Invalidate;
  // A click in the gutter puts or takes away a breakpoint
  if (Button = mbLeft) and (X < GUTTER_W) then FWin.ToggleBpAt(FSel);
  if Button = mbRight then
  begin
    FMenuAddr := FSel;
    Flags := FWin.BpFlagsAt(FMenuAddr);
    FTypeItems[0].Checked := (Flags and C64_BP_EXEC) <> 0;
    FTypeItems[1].Checked := (Flags and (C64_BP_EXEC or C64_BP_READ or C64_BP_WRITE)) = C64_BP_READ;
    FTypeItems[2].Checked := (Flags and (C64_BP_EXEC or C64_BP_READ or C64_BP_WRITE)) = C64_BP_WRITE;
    FTypeItems[3].Checked := (Flags and (C64_BP_EXEC or C64_BP_READ or C64_BP_WRITE)) = (C64_BP_READ or C64_BP_WRITE);
    FEnabledItem.Enabled := Flags <> 0;
    FEnabledItem.Checked := (Flags <> 0) and ((Flags and C64_BP_DISABLED) = 0);
    FRemoveItem.Enabled := Flags <> 0;
    if UserSymbols.Lookup(FMenuAddr) <> '' then FLabelItem.Caption := Format('Edit label at %s...', [Hex4(FMenuAddr)])
    else FLabelItem.Caption := Format('Add label at %s...', [Hex4(FMenuAddr)]);
    PrepareGoto(FPopup, X, Y);
    P := ClientToScreen(Point(X, Y));
    FPopup.PopUp(P.X, P.Y);
  end;
end;

procedure TC64DisView.DblClick;
begin
  inherited DblClick;
  if Editing then Exit;   // a double-click on a byte changes it
  if FSel >= 0 then FWin.ToggleBpAt(Word(FSel));
end;

procedure TC64DisView.MenuGoto(Sender: TObject);
var
  A: Word;
begin
  A := SelAddr;
  if FWin.AskAddress('Go to address in the disassembly', A) then GoToAddr(A);
end;

procedure TC64DisView.MenuSearch(Sender: TObject);
begin
  Search;
end;

procedure TC64DisView.MenuExport(Sender: TObject);
begin
  FWin.ExportAssembler(FTop);
end;

procedure TC64DisView.MenuLabel(Sender: TObject);
begin
  FWin.EditLabel(FMenuAddr);
end;

procedure TC64DisView.MenuToggle(Sender: TObject);
begin
  FWin.ToggleBpAt(FMenuAddr);
end;

{ Changing the type keeps the condition and the on/off state }
procedure TC64DisView.MenuType(Sender: TObject);
begin
  FWin.SetBpFlags(FMenuAddr, (Sender as TMenuItem).Tag or (FWin.BpFlagsAt(FMenuAddr) and C64_BP_DISABLED));
end;

procedure TC64DisView.MenuCondition(Sender: TObject);
var
  I: Integer;
begin
  I := FWin.BpIndexAt(FMenuAddr);
  if I >= 0 then FWin.BpDialog(I, FMenuAddr) else FWin.BpDialog(-1, FMenuAddr);
end;

procedure TC64DisView.MenuEnabled(Sender: TObject);
begin
  FWin.ToggleBpEnabled(FWin.BpIndexAt(FMenuAddr));
end;

procedure TC64DisView.MenuRemove(Sender: TObject);
begin
  FWin.DeleteBp(FWin.BpIndexAt(FMenuAddr));
end;

procedure TC64DisView.MenuRunTo(Sender: TObject);
begin
  FWin.RunToAddr(FMenuAddr);
end;

procedure TC64DisView.MenuSetPC(Sender: TObject);
begin
  FWin.SetPCAt(FMenuAddr);
end;

function TC64DisView.LineText(Addr: Word): string;
var
  Len, Target, I: Integer;
  Instr, Lbl: string;
begin
  Instr := Disassemble6502(Addr, @FWin.Peek, Len, Target);
  Result := Hex4(Addr) + ' ';
  for I := 0 to Len - 1 do Result := Result + ' ' + Hex2(FWin.Peek(Word(Addr + I)));
  Lbl := FWin.SymbolName(Addr);
  if Lbl <> '' then Result := Result + ' ' + Lbl + ':';
  Result := Result + ' ' + Trim(Instr);
  if (Target >= 0) and (OpMode[FWin.Peek(Addr)] <> amImm) then
  begin
    Lbl := FWin.SymbolName(Word(Target));
    if Lbl <> '' then Result := Result + ' ' + Lbl;
  end;
end;

procedure TC64DisView.Search;
var
  S: string;
begin
  S := FSearch;
  if not InputQuery('Search the disassembly', 'Text (an address, bytes, a mnemonic, a label...):', S) or (Trim(S) = '') then
    Exit;
  FSearch := Trim(S);
  SearchNext;
end;

{ From the line after the selection, round the whole memory, instruction by instruction }
procedure TC64DisView.SearchNext;
var
  A: Word;
  Done: Integer;
  Want: string;
begin
  if FSearch = '' then
  begin
    Search;
    Exit;
  end;
  Want := UpperCase(FSearch);
  A := FWin.NextInstr(SelAddr);
  Done := 0;
  while Done < $10000 do
  begin
    if Pos(Want, UpperCase(LineText(A))) > 0 then
    begin
      GoToAddr(A);
      FWin.ShowNotice(Format('Found at %s (F3: next)', [Hex4(A)]));
      Exit;
    end;
    Inc(Done, OpLength(FWin.Peek(A)));
    A := FWin.NextInstr(A);
  end;
  Beep;
  FWin.ShowNotice('Not found in the disassembly');
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
    VK_NEXT:
      begin
        // Ctrl: 1024 bytes on, Shift: $1000 (4096); else a page
        if ssCtrl in Shift then GoToAddr(Word(FTop + 1024))
        else if ssShift in Shift then GoToAddr(Word(FTop + $1000))
        else Scroll(Max(1, VisibleLines - 2));
        Key := 0;
      end;
    VK_PRIOR:
      begin
        if ssCtrl in Shift then GoToAddr(Word(FTop - 1024))
        else if ssShift in Shift then GoToAddr(Word(FTop - $1000))
        else Scroll(-Max(1, VisibleLines - 2));
        Key := 0;
      end;
    VK_HOME: begin GoToAddr(0); Key := 0; end;
    VK_END: begin GoToAddr($FFF0); Key := 0; end;
    VK_BACK:
      begin
        // Back to where the view was before the last jump
        if Length(FBack) > 0 then
        begin
          FTop := FBack[High(FBack)] shr 16;
          FSel := FBack[High(FBack)] and $FFFF;
          SetLength(FBack, Length(FBack) - 1);
          FWin.SetFollow(False);
          Layout;
          Invalidate;
        end;
        Key := 0;
      end;
    VK_F:
      if ssCtrl in Shift then
      begin
        Search;
        Key := 0;
      end;
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
  Y, I, Bit, X: Integer;
  Have: Boolean;
  S: string;
  ValueColor: TColor;

  function Col(N: Integer): Integer;
  begin
    Result := 8 + N * FCharW;
  end;

  procedure Name(C: Integer; const T: string);
  begin
    DrawText(Col(C), Y, T, TC(clBlack), True);
  end;

  function ChangedOrBlack(Changed: Boolean): TColor;
  begin
    if Changed and Have then Result := ChangedColor else Result := TC(clBlack);
  end;

  { Register value in hex: dark red if the last instruction changed it; click to change it }
  procedure RegValue(C: Integer; Reg: Integer; V, Digits: Integer; Changed: Boolean);
  begin
    AddSpot(Col(C), Y, Digits, skReg, V, Digits, Reg);
    DrawText(Col(C), Y, IntToHex(V, Digits), ChangedOrBlack(Changed), False);
  end;

  { A byte of memory (the processor port), changed in place }
  procedure ByteValue(C: Integer; Addr: Word; V: Byte; const AName: string);
  begin
    AddSpot(Col(C), Y, 2, skByte, V, 2, Addr, AName);
    DrawText(Col(C), Y, Hex2(V), TC(clBlack), False);
  end;

begin
  MeasureFont;
  ClearSpots;
  Canvas.Brush.Color := TC(clBtnFace);
  Canvas.FillRect(ClientRect);
  R := FWin.Regs;
  P := FWin.Prev;
  Have := FWin.HavePrev;
  Y := 6;

  Name(0, 'A'); RegValue(3, 0, R.A, 2, R.A <> P.A);
  Name(9, 'X'); RegValue(12, 1, R.X, 2, R.X <> P.X);
  Name(18, 'Y'); RegValue(21, 2, R.Y, 2, R.Y <> P.Y);
  Inc(Y, FLineH);
  Name(0, 'SP'); RegValue(3, 3, R.SP, 2, R.SP <> P.SP);
  Name(9, 'PC'); RegValue(12, 4, R.PC, 4, R.PC <> P.PC);
  Name(18, 'P'); RegValue(21, 5, R.P, 2, R.P <> P.P);
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

  // The interrupt lines: who holds the IRQ, and the NMI
  Name(0, 'IRQ');
  DrawText(Col(4), Y, FWin.IrqText, TC(clBlack), False);
  Name(14, 'NMI');
  DrawText(Col(18), Y, FWin.NmiText, TC(clBlack), False);
  Inc(Y, FLineH);
  // The processor port (bits 0-2 choose what is paged in), changed in place
  Name(0, 'DDR'); ByteValue(4, 0, FWin.DdrValue, 'DDR_6510');
  Name(9, 'Port'); ByteValue(14, 1, FWin.PortValue, 'PORT_6510');
  AddSpot(Col(18), Y, 6, skBank, FWin.Bank, 0, 0,
    'The memory configuration: LORAM, HIRAM and CHAREN (bits 0-2 of the port); click to choose it');
  DrawText(Col(18), Y, 'bank', TC(clGray), False);
  DrawLink(Col(23), Y, IntToStr(FWin.Bank), TC(clBlack));
  Inc(Y, FLineH);
  // What the processor sees, on two lines (A000 and D000, then E000): click to choose the configuration
  Name(0, 'Map');
  X := 4;
  S := 'A000 ' + MEM_NAMES[FWin.MemA];
  AddSpot(Col(X), Y, Length(S), skBank, FWin.Bank, 0, 0, BankText(FWin.Bank) + ' (click to choose)');
  DrawLink(Col(X), Y, S, TC(clBlack));
  X := 16;
  S := 'D000 ' + MEM_NAMES[FWin.MemD];
  AddSpot(Col(X), Y, Length(S), skBank, FWin.Bank, 0, 0, BankText(FWin.Bank) + ' (click to choose)');
  DrawLink(Col(X), Y, S, TC(clBlack));
  Inc(Y, FLineH);
  X := 4;
  S := 'E000 ' + MEM_NAMES[FWin.MemE];
  AddSpot(Col(X), Y, Length(S), skBank, FWin.Bank, 0, 0, BankText(FWin.Bank) + ' (click to choose)');
  DrawLink(Col(X), Y, S, TC(clBlack));
  DrawFocus;
end;

function TC64RegView.ClickSpot(Index: Integer): Boolean;
begin
  Result := inherited ClickSpot(Index);
end;

{ ---- TC64StackView ---- }

procedure TC64StackView.Paint;
var
  I, Y, K, A, Rows: Integer;
  W: Word;
  SP: Byte;

  function Col(N: Integer): Integer;
  begin
    Result := 4 + N * FCharW;
  end;

begin
  MeasureFont;
  ClearSpots;
  Canvas.Brush.Color := TC(clWhite);
  Canvas.FillRect(ClientRect);
  // After a step the stack shows its top again
  if FWin.StepCount <> FStep then
  begin
    FStep := FWin.StepCount;
    FOfs := 0;
  end;
  SP := FWin.Regs.SP;
  Rows := VisibleLines;
  FOfs := Max(0, Min(FOfs, ($FF - SP) div 2));
  for I := 0 to Rows - 1 do
  begin
    K := FOfs + I;
    A := $0100 + SP + 1 + K * 2;
    Y := I * FLineH + 1;
    if A > $01FF then
    begin
      if K = 0 then DrawText(Col(1), Y, 'empty', TC(clGray), False);
      Break;
    end;
    // > marks the top
    if K = 0 then DrawText(Col(0), Y, '>', TC(clBlack), True);
    AddSpot(Col(1), Y - 1, 4, skInfo, A, 4);
    DrawText(Col(1), Y, Hex4(A), TC(clGray), False);
    if A = $01FF then
    begin
      // The last byte of the stack: just the byte
      AddSpot(Col(8), Y - 1, 2, skByte, FWin.Peek(A), 2, A);
      DrawText(Col(8), Y, Hex2(FWin.Peek(A)), TC(clBlack), False);
    end
    else
    begin
      W := FWin.Peek(A) or (FWin.Peek(A + 1) shl 8);
      AddSpot(Col(6), Y - 1, 4, skWord, W, 4, A);
      DrawText(Col(6), Y, Hex4(W), TC(clBlack), False);
    end;
  end;
  DrawFocus;
end;

function TC64StackView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  if WheelDelta < 0 then Inc(FOfs) else FOfs := Max(0, FOfs - 1);
  Invalidate;
  Result := True;
end;

{ ---- TC64PortView ---- }

{ As the Z80 debugger's ports: the instruction's address, the register, R or W and the value (dark red if the last
  instruction made the access); > marks the latest. The wheel scrolls; after a step the latest shows again. }
procedure TC64PortView.Paint;
var
  I, K, Y, Rows: Integer;
  Access: TC64IoAccess;
  ValueColor: TColor;

  function Col(N: Integer): Integer;
  begin
    Result := 4 + N * FCharW;
  end;

begin
  MeasureFont;
  ClearSpots;
  Canvas.Brush.Color := TC(clWhite);
  Canvas.FillRect(ClientRect);
  if FWin.StepCount <> FStep then
  begin
    FStep := FWin.StepCount;
    FOfs := 0;
  end;
  Rows := VisibleLines;
  FOfs := Max(0, Min(FOfs, FWin.IoLogCount - Rows));
  if FWin.IoLogCount = 0 then DrawText(Col(1), 1, 'none yet', TC(clGray), False);
  for I := 0 to Min(FWin.IoLogCount - FOfs, Rows) - 1 do
  begin
    K := FOfs + I;
    Access := FWin.IoLogEntry(K);
    Y := I * FLineH + 1;
    if K = 0 then DrawText(Col(0), Y, '>', TC(clBlack), True);
    AddSpot(Col(1), Y - 1, 4, skInfo, Access.PC, 4);
    DrawText(Col(1), Y, Hex4(Access.PC), TC(clGray), False);
    AddSpot(Col(6), Y - 1, 4, skInfo, Access.Addr, 4);
    DrawText(Col(6), Y, Hex4(Access.Addr), TC(clBlack), False);
    if Access.Write then DrawText(Col(11), Y, 'W', TC(RGBToColor(0, 0, 200)), True)
    else DrawText(Col(11), Y, 'R', TC(RGBToColor(0, 130, 0)), True);
    if Access.Step = FWin.InstrNow then ValueColor := ChangedColor else ValueColor := TC(clBlack);
    AddSpot(Col(13), Y - 1, 2, skInfo, Access.Value, 2);
    DrawText(Col(13), Y, Hex2(Access.Value), ValueColor, False);
  end;
  DrawFocus;
end;

function TC64PortView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  if WheelDelta < 0 then Inc(FOfs) else FOfs := Max(0, FOfs - 1);
  Invalidate;
  Result := True;
end;

{ ---- TC64ZeroView ---- }

function TC64ZeroView.HasOwnMenu: Boolean;
begin
  Result := True;
end;

constructor TC64ZeroView.CreateView(AWin: TC64DebuggerWindow);
begin
  inherited CreateView(AWin);
  FMenuAddr := -1;
  FMenu := TPopupMenu.Create(Self);
  FWatchItem := AddItem(FMenu, 'Add a watch here', @MenuWatch);
  FReadItem := AddItem(FMenu, 'Read breakpoint', @MenuRead, 'Stop before an instruction reads this byte');
  FWriteItem := AddItem(FMenu, 'Write breakpoint', @MenuWrite, 'Stop before an instruction writes this byte');
end;

procedure TC64ZeroView.GoToAddr(Addr: Byte);
begin
  FTop := Addr div ZP_BYTES;
  Invalidate;
end;

procedure TC64ZeroView.Paint;
var
  Row, C, Y, X, MaxTop: Integer;
  A: Word;
  V, BP: Byte;
begin
  MeasureFont;
  ClearSpots;
  Canvas.Brush.Color := TC(clWhite);
  Canvas.FillRect(ClientRect);
  MaxTop := Max(0, 256 div ZP_BYTES - VisibleLines);
  FTop := Max(0, Min(FTop, MaxTop));
  for Row := 0 to VisibleLines - 1 do
  begin
    A := (FTop + Row) * ZP_BYTES;
    if A > $FF then Break;
    Y := Row * FLineH;
    AddSpot(4, Y, 2, skInfo, A, 2);
    DrawText(4, Y + 1, Hex2(A), TC(clGray), False);
    for C := 0 to ZP_BYTES - 1 do
    begin
      V := FWin.Peek(A + C);
      X := 4 + FCharW * (3 + C * 3);
      // A read or write breakpoint on the byte: pink, pale when switched off
      BP := FWin.BpFlagsAt(A + C);
      if (BP and (C64_BP_READ or C64_BP_WRITE)) <> 0 then
      begin
        Canvas.Brush.Style := bsSolid;
        if (BP and C64_BP_DISABLED) <> 0 then Canvas.Brush.Color := TC(RGBToColor(250, 230, 230))
        else Canvas.Brush.Color := TC(RGBToColor(255, 185, 185));
        Canvas.FillRect(X - FCharW div 2, Y, X + FCharW * 2 + FCharW div 2, Y + FLineH);
      end;
      AddSpot(X, Y, 2, skByte, V, 2, A + C, FWin.SymbolName(A + C));
      DrawText(X, Y + 1, Hex2(V), TC(clBlack), False);
    end;
  end;
  DrawFocus;
end;

procedure TC64ZeroView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Spot: Integer;
  P: TPoint;
  Flags: Byte;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbRight then Exit;
  Spot := SpotAt(X, Y);
  FMenuAddr := -1;
  if (Spot >= 0) and (FSpots[Spot].Kind = skByte) then FMenuAddr := FSpots[Spot].Target;
  FWatchItem.Enabled := FMenuAddr >= 0;
  FReadItem.Enabled := FMenuAddr >= 0;
  FWriteItem.Enabled := FMenuAddr >= 0;
  Flags := 0;
  if FMenuAddr >= 0 then
  begin
    FWatchItem.Caption := 'Add a watch at ' + Hex4(FMenuAddr);
    FReadItem.Caption := 'Read breakpoint at ' + Hex4(FMenuAddr);
    FWriteItem.Caption := 'Write breakpoint at ' + Hex4(FMenuAddr);
    Flags := FWin.BpFlagsAt(FMenuAddr);
    if (Flags and C64_BP_EXEC) <> 0 then Flags := 0;
  end;
  FReadItem.Checked := (Flags and C64_BP_READ) <> 0;
  FWriteItem.Checked := (Flags and C64_BP_WRITE) <> 0;
  PrepareGoto(FMenu, X, Y);
  P := ClientToScreen(Point(X, Y));
  FMenu.PopUp(P.X, P.Y);
end;

procedure TC64ZeroView.MenuWatch(Sender: TObject);
begin
  if FMenuAddr >= 0 then FWin.AddWatchText('@$' + Hex4(FMenuAddr));
end;

procedure TC64ZeroView.MenuRead(Sender: TObject);
begin
  if FMenuAddr >= 0 then FWin.ToggleDataBreak(FMenuAddr, FMenuAddr, FMenuAddr, C64_BP_READ);
end;

procedure TC64ZeroView.MenuWrite(Sender: TObject);
begin
  if FMenuAddr >= 0 then FWin.ToggleDataBreak(FMenuAddr, FMenuAddr, FMenuAddr, C64_BP_WRITE);
end;

procedure TC64ZeroView.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  case Key of
    VK_DOWN: begin Inc(FTop); Invalidate; Key := 0; end;
    VK_UP: begin Dec(FTop); Invalidate; Key := 0; end;
    VK_NEXT: begin Inc(FTop, VisibleLines); Invalidate; Key := 0; end;
    VK_PRIOR: begin Dec(FTop, VisibleLines); Invalidate; Key := 0; end;
    VK_HOME: begin FTop := 0; Invalidate; Key := 0; end;
    VK_END: begin FTop := 255; Invalidate; Key := 0; end;
  end;
end;

function TC64ZeroView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  if WheelDelta > 0 then Dec(FTop, 3) else Inc(FTop, 3);
  Invalidate;
  Result := True;
end;

{ ---- TC64HexView ---- }

function TC64HexView.HasOwnMenu: Boolean;
begin
  Result := True;
end;

constructor TC64HexView.CreateView(AWin: TC64DebuggerWindow);
begin
  inherited CreateView(AWin);
  FTextCursor := -1;
  FMenuAddr := -1;
  FSelA := -1;
  FSelB := -1;
  FSpriteRowBytes := 8;
  FSpriteRows := 1;
  FMenu := TPopupMenu.Create(Self);
  AddItem(FMenu, 'Go to address...  (Ctrl+G)', @MenuGoTo);
  FWatchItem := AddItem(FMenu, 'Add a watch here', @MenuWatch);
  FReadItem := AddItem(FMenu, 'Read breakpoint', @MenuRead,
    'Stop before an instruction reads this byte (the selection, if the byte is in it)');
  FWriteItem := AddItem(FMenu, 'Write breakpoint', @MenuWrite,
    'Stop before an instruction writes this byte (the selection, if the byte is in it)');
  FSpriteItem := AddItem(FMenu, 'Sprite mode  (Space)', @MenuSprites);
  AddItem(FMenu, '-', nil);
  FCopyTextItem := AddItem(FMenu, 'Copy', @MenuCopyText, 'Copy the selected bytes as the text column shows them');
  FCopyItem := AddItem(FMenu, 'Copy values  (Ctrl+C)', @MenuCopy,
    'Copy the selected bytes as hex values with a $ in front, separated by commas');
  FPasteItem := AddItem(FMenu, 'Paste  (Ctrl+V)', @MenuPaste,
    'Write the clipboard from this byte: values separated by commas (decimal, or $ for hex), or else its text');
  AddItem(FMenu, 'Search...  (Ctrl+F, F3: next)', @MenuSearch,
    'Find text, or bytes in hex, as the zone shows them (with the XOR)');
  AddItem(FMenu, '-', nil);
  AddItem(FMenu, 'Export text...', @MenuExport, 'Export to a comma separated text file, values in hex with a $ in front');
  AddItem(FMenu, 'Import text...', @MenuImport,
    'Import from a comma separated text file, decimal values, or prepend $ for hex');
  AddItem(FMenu, 'Export binary...', @MenuExportBinary, 'Save a range of memory to a file, byte by byte');
  AddItem(FMenu, 'Import binary...', @MenuImportBinary, 'Load a file into memory, byte by byte, at an address');
end;

{ The byte as the zone shows it: what the processor sees, or the RAM under it; XORed with the key }
function TC64HexView.ByteAt(Addr: Word): Byte;
begin
  if FWin.RamOnly then Result := FWin.PeekRamAt(Addr) else Result := FWin.Peek(Addr);
  Result := Result xor FXor;
end;

procedure TC64HexView.SetXor(Value: Byte);
begin
  FXor := Value;
  Invalidate;
end;

function TC64HexView.CancelTyping: Boolean;
begin
  Result := (FTextCursor >= 0) or HasSel;
  FTextCursor := -1;
  FSelA := -1;
  FSelB := -1;
  if Result then Invalidate;
end;

procedure TC64HexView.GoToAddr(Addr: Word);
begin
  FTop := Addr and $FFF0;
  FSelA := Addr;
  FSelB := Addr;
  Invalidate;
end;

function TC64HexView.HasSel: Boolean;
begin
  Result := (FSelA >= 0) and (FSelB >= 0);
end;

function TC64HexView.SelFirst: Word;
begin
  Result := Min(FSelA, FSelB);
end;

function TC64HexView.SelLast: Word;
begin
  Result := Max(FSelA, FSelB);
end;

function TC64HexView.RowBytes: Integer;
begin
  if FSprites then Result := FSpriteRowBytes else Result := HEX_BYTES;
end;

function TC64HexView.Rows: Integer;
begin
  if FSprites then Result := FSpriteRows else Result := VisibleLines;
end;

function TC64HexView.VisibleBytes: Integer;
begin
  Result := RowBytes * Rows;
end;

{ The range a data breakpoint from the menu covers: the breakpoint already there, else the selection if the byte is in it,
  else the byte }
procedure TC64HexView.BreakRange(out First, Last: Word);
var
  I: Integer;
  E: TBpEntry;
begin
  First := FMenuAddr;
  Last := FMenuAddr;
  I := FWin.BpIndexAt(FMenuAddr);
  if I >= 0 then
  begin
    E := FWin.BpEntryAt(I);
    First := E.First;
    Last := E.Last;
    Exit;
  end;
  if HasSel and (FMenuAddr >= SelFirst) and (FMenuAddr <= SelLast) then
  begin
    First := SelFirst;
    Last := SelLast;
  end;
end;

function TC64HexView.CopyRange(out First, Last: Integer): Boolean;
begin
  Result := True;
  if HasSel then
  begin
    First := SelFirst;
    Last := SelLast;
  end
  else if FMenuAddr >= 0 then
  begin
    First := FMenuAddr;
    Last := FMenuAddr;
  end
  else Result := False;
end;

procedure TC64HexView.MenuGoTo(Sender: TObject);
var
  A: Word;
begin
  A := FTop;
  if FWin.AskAddress('Go to address in the memory', A) then GoToAddr(A);
end;

procedure TC64HexView.MenuWatch(Sender: TObject);
begin
  if FMenuAddr >= 0 then FWin.AddWatchText('@$' + Hex4(FMenuAddr));
end;

procedure TC64HexView.MenuRead(Sender: TObject);
var
  First, Last: Word;
begin
  if FMenuAddr < 0 then Exit;
  BreakRange(First, Last);
  FWin.ToggleDataBreak(FMenuAddr, First, Last, C64_BP_READ);
end;

procedure TC64HexView.MenuWrite(Sender: TObject);
var
  First, Last: Word;
begin
  if FMenuAddr < 0 then Exit;
  BreakRange(First, Last);
  FWin.ToggleDataBreak(FMenuAddr, First, Last, C64_BP_WRITE);
end;

procedure TC64HexView.MenuSprites(Sender: TObject);
begin
  FSprites := not FSprites;
  FTextCursor := -1;
  Invalidate;
end;

{ The selection as the text column shows it (XOR applied, "." for the bytes that aren't printable) }
procedure TC64HexView.MenuCopyText(Sender: TObject);
var
  First, Last, A: Integer;
  V: Byte;
  S: string;
begin
  if not CopyRange(First, Last) then Exit;
  S := '';
  for A := First to Last do
  begin
    V := ByteAt(A);
    if (V >= 32) and (V < 127) then S := S + Chr(V) else S := S + '.';
  end;
  Clipboard.AsText := S;
  FWin.ShowNotice(Format('Copied %d characters', [Last - First + 1]));
end;

{ The selection (or the byte right-clicked) as "$3E,$01,..." }
procedure TC64HexView.MenuCopy(Sender: TObject);
var
  First, Last, A: Integer;
  S: string;
begin
  if not CopyRange(First, Last) then Exit;
  S := '';
  for A := First to Last do
  begin
    if A > First then S := S + ',';
    S := S + '$' + Hex2(ByteAt(A) xor FXor);
  end;
  Clipboard.AsText := S;
  FWin.ShowNotice(Format('Copied %d values', [Last - First + 1]));
end;

procedure TC64HexView.MenuPaste(Sender: TObject);
begin
  if FMenuAddr >= 0 then PasteAt(FMenuAddr);
end;

{ Values separated by commas (or one $ value) are written as they are; any other text as typed in the text column (XORed
  with the key) }
procedure TC64HexView.PasteAt(Addr: Word);
var
  Clip, Error: string;
  Values: TBytes;
  I, N: Integer;
begin
  Clip := Clipboard.AsText;
  if Trim(Clip) = '' then
  begin
    Beep;
    Exit;
  end;
  if (Pos(',', Clip) > 0) or (Trim(Clip)[1] = '$') then
  begin
    if not ParseValues(Clip, Values, Error) then
    begin
      MessageDlg('Paste failed: ' + Error + '.', mtError, [mbOK], 0);
      Exit;
    end;
  end
  else
  begin
    SetLength(Values, Length(Clip));
    N := 0;
    for I := 1 to Length(Clip) do
      if Clip[I] in [#32..#126] then
      begin
        Values[N] := Ord(Clip[I]) xor FXor;
        Inc(N);
      end;
    SetLength(Values, N);
  end;
  FWin.WriteBytes(Addr, Values);
end;

procedure TC64HexView.MenuSearch(Sender: TObject);
begin
  Search;
end;

procedure TC64HexView.MenuExport(Sender: TObject);
begin
  FWin.ExportMemory;
end;

procedure TC64HexView.MenuImport(Sender: TObject);
begin
  FWin.ImportMemory;
end;

procedure TC64HexView.MenuExportBinary(Sender: TObject);
begin
  FWin.ExportBinary;
end;

procedure TC64HexView.MenuImportBinary(Sender: TObject);
begin
  FWin.ImportBinary;
end;

{ A small window: what to find, as text or as hex bytes ("A9 01" or "A901") }
procedure TC64HexView.Search;
var
  Dlg: TForm;
  Edit: TEdit;
  TextRadio, HexRadio: TRadioButton;
  CaseCheck: TCheckBox;
  Lbl: TLabel;
  Btn: TButton;
begin
  Dlg := TForm.CreateNew(Self, 0);
  try
    Dlg.Caption := 'Search the memory';
    Dlg.BorderStyle := bsDialog;
    Dlg.Position := poOwnerFormCenter;
    Dlg.ClientWidth := 380;
    Dlg.ClientHeight := 150;
    Lbl := TLabel.Create(Dlg);
    Lbl.Parent := Dlg;
    Lbl.Caption := 'Find:';
    Lbl.SetBounds(10, 14, 60, 18);
    Edit := TEdit.Create(Dlg);
    Edit.Parent := Dlg;
    Edit.SetBounds(70, 10, 300, 24);
    Edit.Text := FSearchText;
    TextRadio := TRadioButton.Create(Dlg);
    TextRadio.Parent := Dlg;
    TextRadio.Caption := 'Text';
    TextRadio.SetBounds(70, 44, 80, 22);
    HexRadio := TRadioButton.Create(Dlg);
    HexRadio.Parent := Dlg;
    HexRadio.Caption := 'Bytes in hex (A9 01 or A901)';
    HexRadio.SetBounds(160, 44, 210, 22);
    TextRadio.Checked := not FSearchHex;
    HexRadio.Checked := FSearchHex;
    CaseCheck := TCheckBox.Create(Dlg);
    CaseCheck.Parent := Dlg;
    CaseCheck.Caption := 'Match case (text)';
    CaseCheck.SetBounds(70, 72, 200, 22);
    CaseCheck.Checked := FSearchCase;
    Btn := TButton.Create(Dlg);
    Btn.Parent := Dlg;
    Btn.Caption := 'Find';
    Btn.Default := True;
    Btn.ModalResult := mrOk;
    Btn.SetBounds(200, 112, 80, 28);
    Btn := TButton.Create(Dlg);
    Btn.Parent := Dlg;
    Btn.Caption := 'Cancel';
    Btn.Cancel := True;
    Btn.ModalResult := mrCancel;
    Btn.SetBounds(290, 112, 80, 28);
    Dlg.ActiveControl := Edit;
    ThemeForm(Dlg);
    if (Dlg.ShowModal <> mrOk) or (Edit.Text = '') then Exit;
    FSearchText := Edit.Text;
    FSearchHex := HexRadio.Checked;
    FSearchCase := CaseCheck.Checked;
  finally
    Dlg.Free;
  end;
  SearchNext;
end;

{ From the byte after the selection (or the first one shown), round the whole memory; the bytes found are selected }
procedure TC64HexView.SearchNext;
var
  Want: array of Byte;
  S: string;
  I, N, Start, A: Integer;
  V: Byte;
  Ok: Boolean;
begin
  if FSearchText = '' then
  begin
    Search;
    Exit;
  end;
  if FSearchHex then
  begin
    S := StringReplace(StringReplace(FSearchText, ' ', '', [rfReplaceAll]), '$', '', [rfReplaceAll]);
    if Odd(Length(S)) or (S = '') then
    begin
      MessageDlg('The bytes must be pairs of hex digits: A9 01 or A901.', mtError, [mbOK], 0);
      Exit;
    end;
    SetLength(Want, Length(S) div 2);
    for I := 0 to High(Want) do
    begin
      N := StrToIntDef('$' + Copy(S, I * 2 + 1, 2), -1);
      if N < 0 then
      begin
        MessageDlg('"' + Copy(S, I * 2 + 1, 2) + '" is not a hex byte.', mtError, [mbOK], 0);
        Exit;
      end;
      Want[I] := N;
    end;
  end
  else
  begin
    S := FSearchText;
    if not FSearchCase then S := UpperCase(S);
    SetLength(Want, Length(S));
    for I := 1 to Length(S) do Want[I - 1] := Ord(S[I]);
  end;
  if HasSel then Start := SelFirst + 1
  else if FTextCursor >= 0 then Start := FTextCursor
  else Start := FTop;
  for N := 0 to $FFFF do
  begin
    A := (Start + N) and $FFFF;
    Ok := True;
    for I := 0 to High(Want) do
    begin
      // What the zone shows: the byte with the XOR
      V := ByteAt(Word(A + I));
      if not FSearchHex and not FSearchCase and (V in [Ord('a')..Ord('z')]) then Dec(V, 32);
      if V <> Want[I] then
      begin
        Ok := False;
        Break;
      end;
    end;
    if Ok then
    begin
      FSelA := A;
      FSelB := Min($FFFF, A + High(Want));
      FTextCursor := -1;
      if Word(A - FTop) >= VisibleBytes then FTop := Word(A and not (HEX_BYTES - 1));
      Invalidate;
      FWin.ShowNotice(Format('Found at %s (F3: next)', [Hex4(A)]));
      Exit;
    end;
  end;
  Beep;
  FWin.ShowNotice('Not found in memory');
end;

{ Sprite mode: each 8 bytes as an 8x8 cell (one byte per pixel row), cells left to right, the address of each row on the
  left }
procedure TC64HexView.PaintSprites;
var
  PS, Cell, Gap, X0, Cols, RowCount, R, C, B, Bit, X, Y: Integer;
  A: Word;
  V: Byte;
begin
  PS := Max(2, FLineH div 6);
  Cell := 8 * PS;
  Gap := PS * 2;
  X0 := 4 + FCharW * 5;
  Cols := Max(1, (ClientWidth - X0 - 4) div (Cell + Gap));
  RowCount := Max(1, (ClientHeight - 4) div (Cell + Gap));
  FSpriteRowBytes := Cols * 8;
  FSpriteRows := RowCount;
  for R := 0 to RowCount - 1 do
  begin
    Y := 3 + R * (Cell + Gap);
    A := Word(FTop + R * FSpriteRowBytes);
    AddSpot(4, Y, 4, skInfo, A, 4);
    DrawText(4, Y, Hex4(A), TC(clGray), False);
    for C := 0 to Cols - 1 do
    begin
      X := X0 + C * (Cell + Gap);
      Canvas.Pen.Color := TC(RGBToColor(150, 170, 210));
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := TC(clWhite);
      Canvas.Rectangle(X - 1, Y - 1, X + Cell + 1, Y + Cell + 1);
      Canvas.Brush.Color := TC(clBlack);
      for B := 0 to 7 do
      begin
        V := ByteAt(Word(A + C * 8 + B));
        for Bit := 0 to 7 do
          if (V and ($80 shr Bit)) <> 0 then
            Canvas.FillRect(X + Bit * PS, Y + B * PS, X + (Bit + 1) * PS, Y + (B + 1) * PS);
      end;
      AddSpot(X, Y, 1, skHint, 0, 0, 0, Format('%s-%s', [Hex4(A + C * 8), Hex4(A + C * 8 + 7)]));
      FSpots[FSpotCount - 1].R := Rect(X, Y, X + Cell, Y + Cell);
    end;
  end;
end;

procedure TC64HexView.Paint;
var
  Row, Col, Y, X, AsciiX: Integer;
  A: Word;
  V, BP: Byte;
  Back: TColor;
begin
  MeasureFont;
  ClearSpots;
  Canvas.Brush.Color := TC(clWhite);
  Canvas.FillRect(ClientRect);
  if FSprites then
  begin
    PaintSprites;
    DrawFocus;
    Exit;
  end;
  AsciiX := 4 + FCharW * (6 + HEX_BYTES * 3 + 1);
  for Row := 0 to VisibleLines - 1 do
  begin
    Y := Row * FLineH;
    A := Word(FTop + Row * HEX_BYTES);
    AddSpot(4, Y, 4, skInfo, A, 4);
    DrawText(4, Y + 1, Hex4(A), TC(clGray), False);
    for Col := 0 to HEX_BYTES - 1 do
    begin
      V := ByteAt(Word(A + Col));
      // A read or write breakpoint on the byte: pink, pale when switched off
      BP := FWin.BpFlagsAt(Word(A + Col));
      if (BP and (C64_BP_READ or C64_BP_WRITE)) <> 0 then
      begin
        if (BP and C64_BP_DISABLED) <> 0 then Back := TC(RGBToColor(250, 230, 230))
        else Back := TC(RGBToColor(255, 185, 185));
      end
      else Back := TC(clWhite);
      X := 4 + FCharW * (6 + Col * 3);
      if Back <> TC(clWhite) then
      begin
        Canvas.Brush.Style := bsSolid;
        Canvas.Brush.Color := Back;
        Canvas.FillRect(X - FCharW div 2, Y, X + FCharW * 2 + FCharW div 2, Y + FLineH);
      end;
      AddSpot(X, Y, 2, skXorByte, V, 2, Word(A + Col));
      DrawText(X, Y + 1, Hex2(V), TC(clBlack), False);
      X := AsciiX + Col * FCharW;
      AddSpot(X, Y, 1, skAscii, V, 2, Word(A + Col));
      if HasSel and (Word(A + Col) >= SelFirst) and (Word(A + Col) <= SelLast) then
        Back := TC(RGBToColor(190, 215, 255));    // selected
      if Word(A + Col) = FTextCursor then
        Back := TC(RGBToColor(120, 170, 255));    // typing position in the text column
      if Back <> TC(clWhite) then
      begin
        Canvas.Brush.Style := bsSolid;
        Canvas.Brush.Color := Back;
        Canvas.FillRect(X, Y, X + FCharW, Y + FLineH);
      end;
      // Not printable: a grey dot
      if (V >= 32) and (V < 127) then DrawText(X, Y + 1, Chr(V), TC(clBlack), False)
      else DrawText(X, Y + 1, '.', TC(clGray), False);
    end;
  end;
  DrawFocus;
end;

function TC64HexView.ClickSpot(Index: Integer): Boolean;
begin
  if FSpots[Index].Kind = skAscii then
  begin
    // Start typing text at that byte
    FTextCursor := FSpots[Index].Target;
    Invalidate;
    Exit(True);
  end;
  FTextCursor := -1;
  Result := inherited ClickSpot(Index);
end;

procedure TC64HexView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Spot: Integer;
  P: TPoint;
  First, Last: Word;
  Flags: Byte;
  Where: string;
begin
  Spot := SpotAt(X, Y);
  if (Spot < 0) and (FTextCursor >= 0) then
  begin
    FTextCursor := -1;
    Invalidate;
  end;
  // Text column: click or drag to select (Shift+click extends)
  if Button = mbLeft then
  begin
    if (Spot >= 0) and (FSpots[Spot].Kind = skAscii) then
    begin
      if not ((ssShift in Shift) and HasSel) then FSelA := FSpots[Spot].Target;
      FSelB := FSpots[Spot].Target;
      FDragging := True;
    end
    else
    begin
      FSelA := -1;
      FSelB := -1;
    end;
    Invalidate;
  end;
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbRight then
  begin
    FMenuAddr := -1;
    if (Spot >= 0) and (FSpots[Spot].Kind in [skXorByte, skAscii]) then FMenuAddr := FSpots[Spot].Target;
    FWatchItem.Enabled := FMenuAddr >= 0;
    FSpriteItem.Checked := FSprites;
    if FMenuAddr >= 0 then FWatchItem.Caption := 'Add a watch at ' + Hex4(FMenuAddr)
    else FWatchItem.Caption := 'Add a watch here';
    // Read and write breakpoints: on/off for the byte (or the selection)
    FReadItem.Enabled := FMenuAddr >= 0;
    FWriteItem.Enabled := FMenuAddr >= 0;
    Where := 'here';
    Flags := 0;
    if FMenuAddr >= 0 then
    begin
      BreakRange(First, Last);
      if Last <> First then Where := Format('at %s-%s', [Hex4(First), Hex4(Last)]) else Where := 'at ' + Hex4(First);
      Flags := FWin.BpFlagsAt(FMenuAddr);
      if (Flags and C64_BP_EXEC) <> 0 then Flags := 0;
    end;
    FReadItem.Caption := 'Read breakpoint ' + Where;
    FReadItem.Checked := (Flags and C64_BP_READ) <> 0;
    FWriteItem.Caption := 'Write breakpoint ' + Where;
    FWriteItem.Checked := (Flags and C64_BP_WRITE) <> 0;
    FCopyItem.Enabled := HasSel or (FMenuAddr >= 0);
    FCopyTextItem.Enabled := FCopyItem.Enabled;
    FPasteItem.Enabled := FMenuAddr >= 0;
    PrepareGoto(FMenu, X, Y);
    P := ClientToScreen(Point(X, Y));
    FMenu.PopUp(P.X, P.Y);
  end;
end;

procedure TC64HexView.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Spot: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  if not FDragging or not (ssLeft in Shift) then Exit;
  // Past the top or bottom: scroll a row
  if Y < 0 then
  begin
    FTop := Word(FTop - HEX_BYTES);
    FSelB := Max(0, FSelB - HEX_BYTES);
  end
  else if Y >= ClientHeight then
  begin
    FTop := Word(FTop + HEX_BYTES);
    FSelB := Min($FFFF, FSelB + HEX_BYTES);
  end
  else
  begin
    Spot := SpotAt(X, Y);
    if (Spot < 0) or (FSpots[Spot].Kind <> skAscii) then Exit;
    if FSpots[Spot].Target = FSelB then Exit;
    FSelB := FSpots[Spot].Target;
  end;
  Invalidate;
end;

procedure TC64HexView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  FDragging := False;
end;

procedure TC64HexView.KeyDown(var Key: Word; Shift: TShiftState);
var
  A: Word;
begin
  inherited KeyDown(Key, Shift);
  if ssCtrl in Shift then
    case Key of
      VK_F: begin Search; Key := 0; end;
      VK_C:
        begin
          FMenuAddr := FTextCursor;
          MenuCopy(nil);
          Key := 0;
        end;
      VK_V:
        begin
          // At the typing position, else the selection, else the first byte shown
          if FTextCursor >= 0 then PasteAt(FTextCursor)
          else if HasSel then PasteAt(SelFirst)
          else PasteAt(FTop);
          Key := 0;
        end;
      VK_G:
        begin
          A := FTop;
          if FWin.AskAddress('Go to address in the memory', A) then GoToAddr(A);
          Key := 0;
        end;
    end;
  if Key = VK_ESCAPE then
  begin
    FSelA := -1;
    FSelB := -1;
  end;
  if FTextCursor >= 0 then
    case Key of
      VK_ESCAPE, VK_RETURN: begin FTextCursor := -1; Key := 0; end;
      VK_LEFT, VK_BACK: begin FTextCursor := Word(FTextCursor - 1); Key := 0; end;
      VK_RIGHT: begin FTextCursor := Word(FTextCursor + 1); Key := 0; end;
    end;
  case Key of
    VK_SPACE:
      if FTextCursor < 0 then
      begin
        MenuSprites(nil);
        Key := 0;
      end;
    VK_DOWN: begin FTop := Word(FTop + RowBytes); Key := 0; end;
    VK_UP: begin FTop := Word(FTop - RowBytes); Key := 0; end;
    // Ctrl: 1024 bytes, Shift: $1000 (4096), else a page
    VK_NEXT:
      begin
        if ssCtrl in Shift then FTop := Word(FTop + 1024)
        else if ssShift in Shift then FTop := Word(FTop + $1000)
        else FTop := Word(FTop + VisibleBytes);
        Key := 0;
      end;
    VK_PRIOR:
      begin
        if ssCtrl in Shift then FTop := Word(FTop - 1024)
        else if ssShift in Shift then FTop := Word(FTop - $1000)
        else FTop := Word(FTop - VisibleBytes);
        Key := 0;
      end;
  end;
  Invalidate;
end;

procedure TC64HexView.KeyPress(var Key: Char);
begin
  inherited KeyPress(Key);
  if (FTextCursor < 0) or not (Key in [#32..#126]) then Exit;
  // Typed in the decoded view: stored XORed back with the key
  FWin.PokeMem(FTextCursor, Ord(Key) xor FXor);
  FTextCursor := Word(FTextCursor + 1);
  // Keep the cursor on screen
  if Word(FTextCursor - FTop) >= HEX_BYTES * VisibleLines then FTop := Word(FTop + HEX_BYTES);
  Key := #0;
end;

procedure TC64HexView.DoExit;
begin
  FTextCursor := -1;
  inherited DoExit;
end;

function TC64HexView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  if WheelDelta < 0 then FTop := Word(FTop + RowBytes * 3) else FTop := Word(FTop - RowBytes * 3);
  Invalidate;
  Result := True;
end;

{ ---- TC64BreakView ---- }

function TC64BreakView.HasOwnMenu: Boolean;
begin
  Result := True;
end;

constructor TC64BreakView.CreateView(AWin: TC64DebuggerWindow);
begin
  inherited CreateView(AWin);
  FSel := -1;
  FMenu := TPopupMenu.Create(Self);
  AddItem(FMenu, 'Add breakpoint...  (Insert)', @MenuAdd);
  FEditItem := AddItem(FMenu, 'Edit...  (Enter)', @MenuEdit);
  FEnabledItem := AddItem(FMenu, 'Enabled  (Space)', @MenuEnabled);
  FRemoveItem := AddItem(FMenu, 'Remove  (Delete)', @MenuRemove);
  AddItem(FMenu, '-', nil);
  FShowItem := AddItem(FMenu, 'Show in the disassembly', @MenuShow);
  FRemoveAllItem := AddItem(FMenu, 'Remove all', @MenuRemoveAll);
  AddItem(FMenu, '-', nil);
  AddItem(FMenu, 'Save breakpoints (JSON)...', @MenuSave);
  AddItem(FMenu, 'Load breakpoints (JSON)...', @MenuLoad);
end;

function TC64BreakView.RowAt(Y: Integer): Integer;
begin
  if FLineH = 0 then MeasureFont;
  Result := Y div FLineH;
  if (Result < 0) or (Result >= FWin.BpCount) then Result := -1;
end;

function TC64BreakView.HaveSel: Boolean;
begin
  Result := (FSel >= 0) and (FSel < FWin.BpCount);
end;

procedure TC64BreakView.MenuAdd(Sender: TObject);
begin
  FWin.DoAddBp(Self);
end;

procedure TC64BreakView.MenuEdit(Sender: TObject);
begin
  if HaveSel then FWin.EditBpAt(FSel);
end;

procedure TC64BreakView.MenuEnabled(Sender: TObject);
begin
  if HaveSel then FWin.ToggleBpEnabled(FSel);
end;

procedure TC64BreakView.MenuRemove(Sender: TObject);
begin
  if not HaveSel then Exit;
  FWin.DeleteBp(FSel);
  if FSel >= FWin.BpCount then FSel := FWin.BpCount - 1;
end;

procedure TC64BreakView.MenuShow(Sender: TObject);
begin
  if HaveSel then FWin.GoToCode(FWin.BpEntryAt(FSel).First);
end;

procedure TC64BreakView.MenuRemoveAll(Sender: TObject);
begin
  FWin.DoClearBps(Self);
  FSel := -1;
end;

procedure TC64BreakView.MenuSave(Sender: TObject);
begin
  FWin.SaveBreaksAs;
end;

procedure TC64BreakView.MenuLoad(Sender: TObject);
begin
  FWin.LoadBreaksAsk;
  FSel := -1;
end;

function BreakTypeName(Flags: Byte): string;
begin
  if (Flags and C64_BP_EXEC) <> 0 then Result := 'Exec'
  else if (Flags and (C64_BP_READ or C64_BP_WRITE)) = (C64_BP_READ or C64_BP_WRITE) then Result := 'R/W'
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
      Canvas.Brush.Color := SelColor;
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
    X := 8 + Box + FCharW * 7;
    AddSpot(X, Y, 4, skInfo, E.First, 4);
    Lbl := Hex4(E.First);
    if E.Last <> E.First then Lbl := Lbl + '-' + Hex4(E.Last);
    X := DrawText(X, Y + 1, Lbl, TextColor, False);
    Full := Full + Lbl;
    Lbl := FWin.SymbolName(E.First);
    if Lbl <> '' then
    begin
      Full := Full + ' ' + Lbl;
      AddSpot(X + FCharW, Y, Min(Length(Lbl), 14), skLabel, E.First, 0, 0, FWin.LabelHint(E.First));
      if Length(Lbl) > 14 then Lbl := Copy(Lbl, 1, 13) + '~';
      X := DrawText(X + FCharW, Y + 1, Lbl, LabelColor, False);
    end;
    Cond := E.Cond;
    if E.Hits >= 0 then Cond := Cond + Format('  (T=%d)', [E.Hits]);   // times reached so far
    if Cond <> '' then
    begin
      X := DrawText(X + FCharW, Y + 1, 'if ' + Cond, TC(RGBToColor(140, 90, 0)), False);
      Full := Full + ' if ' + Cond;
    end;
    // Cut at the right: the box and the type (and any free part of the line) show it whole as a hint
    if X > ClientWidth - 4 then
    begin
      AddSpot(0, Y, (8 + Box) div FCharW + 7, skHint, 0, 0, 0, Full);
      AddSpot(0, Y, ClientWidth div FCharW + 1, skHint, 0, 0, 0, Full);
    end;
  end;
  DrawFocus;
end;

procedure TC64BreakView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  P: TPoint;
begin
  FSel := RowAt(Y);
  inherited MouseDown(Button, Shift, X, Y);
  if (Button = mbLeft) and HaveSel and (X < FLineH + 4) then FWin.ToggleBpEnabled(FSel);
  Invalidate;
  if Button = mbRight then
  begin
    FEditItem.Enabled := HaveSel;
    FEnabledItem.Enabled := HaveSel;
    FEnabledItem.Checked := HaveSel and ((FWin.BpEntryAt(FSel).Flags and C64_BP_DISABLED) = 0);
    FRemoveItem.Enabled := HaveSel;
    FShowItem.Enabled := HaveSel;
    FRemoveAllItem.Enabled := FWin.BpCount > 0;
    PrepareGoto(FMenu, X, Y);
    P := ClientToScreen(Point(X, Y));
    FMenu.PopUp(P.X, P.Y);
  end;
end;

procedure TC64BreakView.DblClick;
begin
  inherited DblClick;
  MenuEdit(nil);
end;

procedure TC64BreakView.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  case Key of
    VK_INSERT: begin MenuAdd(nil); Key := 0; end;
    VK_DELETE: begin MenuRemove(nil); Key := 0; end;
    VK_SPACE: begin MenuEnabled(nil); Key := 0; end;
    VK_RETURN: begin MenuEdit(nil); Key := 0; end;
    VK_DOWN: begin if FSel < FWin.BpCount - 1 then Inc(FSel); Key := 0; end;
    VK_UP: begin if FSel > 0 then Dec(FSel); Key := 0; end;
  end;
  Invalidate;
end;

{ ---- TC64WatchView ---- }

function TC64WatchView.HasOwnMenu: Boolean;
begin
  Result := True;
end;

constructor TC64WatchView.CreateView(AWin: TC64DebuggerWindow);
begin
  inherited CreateView(AWin);
  FSel := -1;
  FMenu := TPopupMenu.Create(Self);
  AddItem(FMenu, 'Add watch...  (Insert)', @MenuAdd);
  FRemoveItem := AddItem(FMenu, 'Remove watch  (Delete)', @MenuRemove);
  AddItem(FMenu, '-', nil);
  AddItem(FMenu, 'Save watches (JSON)...', @MenuSave);
  AddItem(FMenu, 'Load watches (JSON)...', @MenuLoad);
end;

procedure TC64WatchView.MenuAdd(Sender: TObject);
begin
  FWin.DoAddWatch(Self);
end;

procedure TC64WatchView.MenuRemove(Sender: TObject);
begin
  if FSel >= 0 then FWin.DeleteWatch(FSel);
end;

procedure TC64WatchView.MenuSave(Sender: TObject);
begin
  FWin.SaveWatchesAs;
end;

procedure TC64WatchView.MenuLoad(Sender: TObject);
begin
  FWin.LoadWatchesAsk;
  FSel := -1;
end;

procedure TC64WatchView.Paint;
var
  I, Y, V, P: Integer;
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
      Canvas.Brush.Color := SelColor;
      Canvas.FillRect(0, Y, ClientWidth, Y + FLineH);
    end;
    S := FWin.WatchLine(I);
    V := FWin.WatchNumber(I);
    if V < 0 then DrawText(6, Y + 1, S, TC(clGray), False)
    else
    begin
      DrawText(6, Y + 1, S, TC(clBlack), False);
      // The value: right-click it to go there
      P := Pos('= $', S);
      if (P > 0) and (V <= $FFFF) then AddSpot(6 + (P + 2) * FCharW, Y, IfThen(V > $FF, 4, 2), skInfo, V, IfThen(V > $FF, 4, 2));
    end;
  end;
  DrawFocus;
end;

procedure TC64WatchView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  P: TPoint;
begin
  if FLineH = 0 then MeasureFont;
  FSel := Y div FLineH;
  if FSel >= FWin.WatchCount then FSel := -1;
  inherited MouseDown(Button, Shift, X, Y);
  Invalidate;
  if Button = mbRight then
  begin
    FRemoveItem.Enabled := FSel >= 0;
    PrepareGoto(FMenu, X, Y);
    P := ClientToScreen(Point(X, Y));
    FMenu.PopUp(P.X, P.Y);
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

{ ---- TC64ChipView ---- }

{ Each chip: its title, then rows of 8 registers (the address, then the values; the hint names the register) }
procedure TC64ChipView.Paint;
var
  Y: Integer;

  procedure Block(const Title: string; Base: Word; Count, Chip: Integer);
  var
    I, X, V: Integer;
  begin
    DrawText(6, Y, Title, TC(clBlack), True);
    Inc(Y, FLineH);
    for I := 0 to Count - 1 do
    begin
      if I mod 8 = 0 then
      begin
        if I > 0 then Inc(Y, FLineH);
        AddSpot(6, Y, 4, skInfo, Base + I, 4);
        DrawText(6, Y, Hex4(Base + I), TC(clGray), False);
      end;
      case Chip of
        0: V := FWin.VicReg(I);
        1: V := FWin.SidReg(I);
        2: V := FWin.CiaReg(0, I);
      else
        V := FWin.CiaReg(1, I);
      end;
      X := 6 + FCharW * (6 + (I mod 8) * 3);
      AddSpot(X, Y, 2, skIo, V, 2, Base + I, C64AddressName(Base + I));
      DrawText(X, Y, Hex2(V), TC(clBlack), False);
    end;
    Inc(Y, FLineH + FLineH div 2);
  end;

begin
  MeasureFont;
  ClearSpots;
  Canvas.Brush.Color := TC(clWhite);
  Canvas.FillRect(ClientRect);
  Y := 6;
  Block('VIC-II', $D000, 47, 0);
  Block('SID (the values last written: its registers are write-only)', $D400, 25, 1);
  Block('CIA 1', $DC00, 16, 2);
  Block('CIA 2', $DD00, 16, 3);
  DrawText(6, Y, 'Click a value to change it; the hint names the register.', TC(clGray), False);
  DrawFocus;
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
var
  I: Integer;
  Item: TMenuItem;
begin
  inherited CreateNew(AOwner);
  FEmu := AEmu;
  FWatchText := TStringList.Create;
  FWatchValues := TStringList.Create;
  FHistory := TStringList.Create;
  FFollow := True;
  // Menu item hints show in the status bar
  Application.AddOnHintHandler(@AppHint);
  Caption := 'Debugger';   // as the Z80's
  Width := 1100;
  Height := 720;
  Position := poMainFormCenter;
  KeyPreview := True;
  OnKeyDown := @FormKey;
  OnClose := @WindowClose;
  OnResize := @FormResize;
  OnShow := @FormShow;
  FBankMenu := TPopupMenu.Create(Self);
  for I := 0 to 7 do
  begin
    Item := TMenuItem.Create(FBankMenu);
    Item.Caption := BankText(I);
    Item.Tag := I;
    Item.RadioItem := True;
    Item.OnClick := @BankClick;
    FBankMenu.Items.Add(Item);
  end;
  BuildUI;
  LoadRomSymbols;
  C64ExprSymbols := @FindSymbol;
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 250;
  FTimer.OnTimer := @TimerTick;
  FTimer.Enabled := True;
  ThemeForm(Self);
  FMem.GoToAddr($0400);
end;

destructor TC64DebuggerWindow.Destroy;
begin
  if C64ExprSymbols = @FindSymbol then C64ExprSymbols := nil;
  Application.RemoveOnHintHandler(@AppHint);
  Application.RemoveAsyncCalls(Self);
  FHistory.Free;
  FWatchText.Free;
  FWatchValues.Free;
  C64DebuggerWindow := nil;
  inherited Destroy;
end;

procedure TC64DebuggerWindow.LoadRomSymbols;
begin
  LoadC64RomSymbols(IncludeTrailingPathDelimiter(FEmu.Spec.RomDir) + 'c64.sym');
end;

procedure TC64DebuggerWindow.WindowClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  CloseAction := caHide;
  // Its chips window goes with it
  if FSysForm <> nil then FSysForm.Hide;
  // Closing it carries on running, like Run (F5), as the Z80 debugger does (another machine just runs)
  if FEmu.Paused then
    if FEmu.Spec.C64Hw <> nil then Resume else FEmu.Resume;
  // The keys go to the main window again
  Application.QueueAsyncCall(@FocusMainWindow, 0);
end;

procedure TC64DebuggerWindow.FocusMainWindow(Data: PtrInt);
begin
  if (Application.MainForm <> nil) and Application.MainForm.CanFocus then
  begin
    Application.MainForm.BringToFront;
    Application.MainForm.SetFocus;
  end;
end;

{ The hints of the menus' items (and the toolbar's) show in the status bar, as in the Z80 debugger }
procedure TC64DebuggerWindow.AppHint(Sender: TObject);
begin
  if Active and (Application.Hint <> '') then ShowNotice(GetLongHint(Application.Hint));
end;

function TC64DebuggerWindow.IoLogCount: Integer;
begin
  Result := Length(FIoLog);
end;

function TC64DebuggerWindow.IoLogEntry(Index: Integer): TC64IoAccess;
begin
  Result := FIoLog[Index];
end;

function TC64DebuggerWindow.Peek(Addr: Word): Byte;
begin
  Result := FPeek[Addr];
end;

function TC64DebuggerWindow.PeekRamAt(Addr: Word): Byte;
begin
  Result := FRam[Addr];
end;

function TC64DebuggerWindow.VicReg(I: Integer): Byte;
begin
  Result := FVicRegs[I and $3F];
end;

function TC64DebuggerWindow.SidReg(I: Integer): Byte;
begin
  Result := FSidRegs[I and $1F];
end;

function TC64DebuggerWindow.CiaReg(N, I: Integer): Byte;
begin
  Result := FCiaRegs[N and 1, I and $F];
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
  Lbl: TLabel;
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
  AddButton(ikRewind, 'Step back (Shift+F7): to where it was before the last step, step over, step out, run to cursor ' +
    'or run (up to 10 times)', @DoStepBack);
  AddSeparator;
  AddButton(ikGoTo, 'Go to address (Ctrl+G)', @DoGoto);
  AddButton(ikBreakpoint, 'Put or take away a breakpoint on the selected line (F8)', @DoToggleBp);
  AddButton(ikClearBreakpoints, 'Remove all the breakpoints', @DoClearBps);
  AddButton(ikWatch, 'Add a watch', @DoAddWatch);
  AddSeparator;
  AddButton(ikOpen, 'Load symbols: NAME = $ADDRESS lines, as the assemblers write them', @DoSymbols);
  AddButton(ikChip, 'Chip registers: the VIC-II, the SID and the CIAs (click a value to change it), and the state of ' +
    'the chips and the disk drives', @DoSystem);
  AddSeparator;
  AddButton(ik6502, '6502: the instruction set, as a table of opcodes (the undocumented ones too)', @DoOpcodes);

  // Data zone (bottom third): memory | breakpoints | watches, the last two sharing the rest
  FDataPanel := TPanel.Create(Self);
  FDataPanel.Parent := Self;
  FDataPanel.Align := alBottom;
  FDataPanel.Height := 220;
  FDataPanel.BevelOuter := bvNone;
  FMemZone := MakeColumn(FDataPanel, 'Memory (Ctrl+G: go to; Space: sprites)', 600, alLeft);
  Header := TPanel(FMemZone.Controls[0]);
  // XOR: its box at the right end of the header, the label before it, and "RAM only" before them
  FXorEdit := TEdit.Create(Self);
  FXorEdit.Parent := Header;
  FXorEdit.AnchorSideRight.Control := Header;
  FXorEdit.AnchorSideRight.Side := asrRight;
  FXorEdit.BorderSpacing.Right := 4;
  FXorEdit.Anchors := [akTop, akRight];
  FXorEdit.Top := 1;
  FXorEdit.Width := Scale96ToForm(30);
  FXorEdit.Text := '00';
  FXorEdit.MaxLength := 2;
  FXorEdit.Hint := 'Each byte is XORed with this hex value for display and when edited';
  FXorEdit.ShowHint := True;
  FXorEdit.OnChange := @XorChange;
  Lbl := TLabel.Create(Self);
  Lbl.Parent := Header;
  Lbl.Caption := 'XOR:';
  Lbl.Font.Style := [fsBold];
  Lbl.AnchorSideRight.Control := FXorEdit;
  Lbl.AnchorSideRight.Side := asrLeft;
  Lbl.BorderSpacing.Right := 6;
  Lbl.Anchors := [akTop, akRight];
  Lbl.Top := 4;
  FRamCheck := TCheckBox.Create(Self);
  FRamCheck.Parent := Header;
  FRamCheck.Caption := 'RAM only';
  FRamCheck.AnchorSideRight.Control := Lbl;
  FRamCheck.AnchorSideRight.Side := asrLeft;
  FRamCheck.BorderSpacing.Right := 12;
  FRamCheck.Anchors := [akTop, akRight];
  FRamCheck.Top := 2;
  FRamCheck.Hint := 'Show (and change) the RAM under the ROMs and the I/O, not what the processor sees';
  FRamCheck.ShowHint := True;
  FRamCheck.OnChange := @RamChange;
  FMem := TC64HexView.CreateView(Self);
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

  // The right side: the registers with the stack on their right, and under them the ports and the zero page side by
  // side
  FRightPanel := TPanel.Create(Self);
  FRightPanel.Parent := Self;
  FRightPanel.Align := alRight;
  FRightPanel.Width := 440;
  FRightPanel.BevelOuter := bvNone;
  FTopPanel := TPanel.Create(Self);
  FTopPanel.Parent := FRightPanel;
  FTopPanel.Align := alTop;
  FTopPanel.Height := 200;
  FTopPanel.BevelOuter := bvNone;
  FStackZone := MakeColumn(FTopPanel, 'Stack', 120, alRight);
  SetZoneHint(FStackZone, 'From SP upwards as 16-bit words (> is the top); click one to change it, the wheel scrolls');
  FStack := TC64StackView.CreateView(Self);
  FStack.Parent := FStackZone;
  FStack.Align := alClient;
  FRegZone := MakeColumn(FTopPanel, 'Registers (click to change)', 0, alClient);
  FRegView := TC64RegView.CreateView(Self);
  FRegView.Parent := FRegZone;
  FRegView.Align := alClient;
  FRegView.TabStop := False;
  FRegView.Color := clBtnFace;
  FLowPanel := TPanel.Create(Self);
  FLowPanel.Parent := FRightPanel;
  FLowPanel.Align := alClient;
  FLowPanel.BevelOuter := bvNone;
  FPortZone := MakeColumn(FLowPanel, 'Ports', 120, alLeft);
  SetZoneHint(FPortZone, 'The last accesses to the chips (VIC-II, SID, CIAs, DE00-DFFF) and the 6510''s port (0, 1): ' +
    'the instruction''s address, the register, R or W and the value (dark red if the last instruction made it); > is ' +
    'the latest; the wheel scrolls');
  FPorts := TC64PortView.CreateView(Self);
  FPorts.Parent := FPortZone;
  FPorts.Align := alClient;
  FZeroZone := MakeColumn(FLowPanel, 'Zero page', 0, alClient);
  SetZoneHint(FZeroZone, 'Click a byte to change it; right-click: watches and breakpoints; the wheel scrolls');
  FZero := TC64ZeroView.CreateView(Self);
  FZero.Parent := FZeroZone;
  FZero.Align := alClient;

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
  // The data zone keeps a third of the height, but the registers, the stack and the zero page above keep their lines
  Avail := ClientHeight - FToolbar.Height - FStatusBar.Height - 8;
  Data := (Avail + FShrink) div 3;
  if Avail - Data < FRightMinH then Data := Avail - FRightMinH;
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
  CW, LH, Border, DisasmW, RegW, StackW, ZeroW, MemW, HeaderH, PortW, RightW: Integer;
  Work: TRect;
begin
  FLaidOut := True;
  FDis.MeasureNow;
  CW := FDis.CharWidth;
  LH := FDis.LineHeight;
  Border := FRegView.Width - FRegView.ClientWidth;
  HeaderH := TPanel(FRegZone.Controls[0]).Height;
  // The stack: "> 01F8  1234"; the ports: "> E5A0 D020 W 0E"; the zero page: its address and 8 bytes
  StackW := 8 + 11 * CW + Border;
  PortW := 8 + 16 * CW + Border;
  ZeroW := 8 + (3 + ZP_BYTES * 3) * CW + Border;
  // Registers (REG_COLS columns) and the stack on top, the ports and the zero page under them: the wider
  RegW := 16 + REG_COLS * CW + Border;
  RightW := Max(RegW + StackW + 12, PortW + ZeroW + 12);
  DisasmW := GUTTER_W + (MAX_LABEL + 1 + 6 + 10 + 30) * CW + Border;
  MemW := 6 + (6 + HEX_BYTES * 3 + 1 + HEX_BYTES) * CW + Border;
  FRightPanel.Width := RightW + 6;
  FStackZone.Width := StackW + 6;
  FPortZone.Width := PortW + 6;
  FMemZone.Width := MemW + 6;
  FTopPanel.Height := HeaderH + 12 + REG_LINES * LH + Border + 6;
  // The right column: the registers and LOW_ROWS lines of the ports and the zero page
  FRightMinH := FTopPanel.Height + HeaderH + LOW_ROWS * LH + Border + 18;
  ClientWidth := DisasmW + RightW + 12 + 10;
  // Shorter by UPPER_CUT lines, all of them taken from the upper part
  FShrink := UPPER_CUT * LH;
  Height := Height - FShrink;
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

procedure TC64DebuggerWindow.XorChange(Sender: TObject);
var
  V: Integer;
begin
  V := StrToIntDef('$' + Trim(FXorEdit.Text), -1);
  if (V < 0) or (V > 255) or (Trim(FXorEdit.Text) = '') then
  begin
    FXorEdit.Font.Color := clRed;
    Exit;
  end;
  if DarkTheme then FXorEdit.Font.Color := clWhite else FXorEdit.Font.Color := clDefault;
  FMem.XorValue := V;
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
    // After a change by hand nothing is shown as changed by the last instruction
    if not FHavePrev then FPrevRegs := FSnapRegs;
    for I := 0 to 65535 do
    begin
      FPeek[I] := Hw.Peek(I);
      FRam[I] := Hw.PeekRam(I);
    end;
    for I := 0 to $3F do FVicRegs[I] := Hw.Vic.Peek(I);
    for I := 0 to $1F do FSidRegs[I] := Hw.Sid.Register(I);
    for I := 0 to $F do
    begin
      FCiaRegs[0, I] := Hw.Cia1.Peek(I);
      FCiaRegs[1, I] := Hw.Cia2.Peek(I);
    end;
    FSysText := SystemText;
    FBank := Hw.Bank and 7;
    FPortValue := Hw.Port;
    FDdrValue := Hw.Ddr;
    FMemA := Hw.MemoryAt($A000);
    FMemD := Hw.MemoryAt($D000);
    FMemE := Hw.MemoryAt($E000);
    FIrqText := '';
    if Hw.Vic.Irq then FIrqText := FIrqText + 'VIC ';
    if Hw.Cia1.Irq then FIrqText := FIrqText + 'CIA1 ';
    if FIrqText = '' then FIrqText := 'idle' else FIrqText := Trim(FIrqText);
    if Hw.Cia2.Irq then FNmiText := 'CIA2' else FNmiText := 'idle';
    SetLength(FIoLog, Hw.IoLogCount);
    for I := 0 to High(FIoLog) do FIoLog[I] := Hw.IoLog(I);
    FInstrNow := Hw.InstrCount;
    FWatchValues.Clear;
    SetLength(FWatchNumbers, FWatchText.Count);
    for I := 0 to FWatchText.Count - 1 do
      if Hw.EvalCondition(FWatchText[I], V, Err) then
      begin
        FWatchValues.Add(Format('%s = $%s (%d)', [FWatchText[I], IntToHex(V and $FFFFFF, IfThen(V > $FF, 4, 2)), V]));
        FWatchNumbers[I] := V;
      end
      else
      begin
        FWatchValues.Add(FWatchText[I] + ' = ?   ' + Err);
        FWatchNumbers[I] := -1;
      end;
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

{ The breakpoints as the list shows them: a range is one (the emulator is locked) }
procedure TC64DebuggerWindow.TakeBreakpoints;
var
  A: Integer;
  F: Byte;
  Last: Word;
  Spec: TSpectrum;
begin
  Spec := FEmu.Spec;
  SetLength(FBpList, 0);
  A := 0;
  while A <= $FFFF do
  begin
    F := Spec.Breakpoint[A];
    if F = 0 then
    begin
      Inc(A);
      Continue;
    end;
    Last := Spec.BreakRangeLast(A, False);
    if Last < A then Last := A;
    SetLength(FBpList, Length(FBpList) + 1);
    FBpList[High(FBpList)].First := A;
    FBpList[High(FBpList)].Last := Last;
    FBpList[High(FBpList)].Flags := F;
    FBpList[High(FBpList)].Cond := Spec.BreakCondition(A);
    FBpList[High(FBpList)].Hits := Spec.BreakHits(A);
    A := Last + 1;
  end;
end;

function TC64DebuggerWindow.BpIndexAt(Addr: Word): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FBpList) do
    if (Addr >= FBpList[I].First) and (Addr <= FBpList[I].Last) then Exit(I);
  Result := -1;
end;

function TC64DebuggerWindow.BpFlagsAt(Addr: Word): Byte;
var
  I: Integer;
begin
  I := BpIndexAt(Addr);
  if I >= 0 then Result := FBpList[I].Flags else Result := 0;
end;

function TC64DebuggerWindow.CondAt(Addr: Word): string;
var
  I: Integer;
begin
  I := BpIndexAt(Addr);
  if I >= 0 then Result := FBpList[I].Cond else Result := '';
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

function TC64DebuggerWindow.WatchNumber(Index: Integer): Integer;
begin
  if Index <= High(FWatchNumbers) then Result := FWatchNumbers[Index] else Result := -1;
end;

{ The text of the System window's state tab (the emulator is locked) }
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

{ ---- names ---- }

function TC64DebuggerWindow.SymbolName(Addr: Word): string;
begin
  Result := UserSymbols.Lookup(Addr);
  if Result <> '' then Exit;
  // The ROMs' labels only while that ROM is paged in (the RAM's ones anywhere else)
  Result := C64RomLabel(Addr, FMemA = 1, FMemE = 2);
  if Result <> '' then Exit;
  // The chips' registers while the I/O is paged in, the KERNAL's entry points while the KERNAL is
  case Addr shr 12 of
    $D: if FMemD <> 4 then Exit;
    $E, $F: if FMemE <> 2 then Exit;
  end;
  Result := C64AddressName(Addr);
end;

function TC64DebuggerWindow.NameOrHex(Addr: Word): string;
begin
  Result := SymbolName(Addr);
  if Result = '' then Result := Hex4(Addr);
end;

function TC64DebuggerWindow.LabelHint(Addr: Word): string;
var
  Names, S, D: string;

  procedure AddName(const N: string);
  begin
    if (N <> '') and (Pos(' ' + N + ' ', ' ' + Names + ' ') = 0) then
      if Names = '' then Names := N else Names := Names + ', ' + N;
  end;

begin
  Names := '';
  AddName(UserSymbols.Lookup(Addr));
  S := C64RomLabel(Addr, FMemA = 1, FMemE = 2);
  AddName(S);
  AddName(C64AddressName(Addr));
  Result := Hex4(Addr);
  if Names <> '' then Result := Names + ' = ' + Result;
  if S <> '' then
  begin
    D := C64RomDescription(Addr);
    if D <> '' then Result := Result + LineEnding + D;
  end;
end;

function TC64DebuggerWindow.FindSymbol(const AName: string; out Addr: Word): Boolean;
begin
  Result := UserSymbols.Find(AName, Addr) or C64FindRomLabel(AName, Addr) or C64FindName(AName, Addr);
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

procedure TC64DebuggerWindow.ShowNotice(const AText: string);
begin
  FNotice := AText;
  FNoticeTime := GetTickCount64;
  FStatusBar.SimpleText := AText;
end;

function TC64DebuggerWindow.ParseAddr(const AText: string; out Addr: Word): Boolean;
var
  V: Integer;
begin
  Result := False;
  Addr := 0;
  if Trim(AText) = '' then Exit;
  // A name first (a symbol, a ROM label, a KERNAL or chip name), then an expression
  if FindSymbol(Trim(AText), Addr) then Exit(True);
  Result := EvalValue(AText, V) and (V >= 0) and (V <= $FFFF);
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

type
  TC64AddressDialog = class(TForm)
  public
    Edit: TEdit;
    List: TListBox;
    procedure ListClick(Sender: TObject);
    procedure ListDblClick(Sender: TObject);
  end;

procedure TC64AddressDialog.ListClick(Sender: TObject);
begin
  if List.ItemIndex >= 0 then Edit.Text := List.Items[List.ItemIndex];
end;

procedure TC64AddressDialog.ListDblClick(Sender: TObject);
begin
  ListClick(Sender);
  ModalResult := mrOK;
end;

{ As the Z80 debugger's: the last MAX_HISTORY addresses (shared by the disassembly and the memory) and a "Go to PC"
  button, which doesn't add the PC to them }
function TC64DebuggerWindow.AskAddress(const ATitle: string; var Addr: Word; AGoTo: Boolean): Boolean;
const
  MAX_HISTORY = 10;
var
  S: string;
  Dlg: TC64AddressDialog;
  Lbl: TLabel;
  Btn: TButton;
  A: Word;
  I: Integer;
begin
  Result := False;
  if not AGoTo then
  begin
    S := Hex4(Addr);
    repeat
      if not InputQuery(ATitle, 'Address, label or expression (hex):', S) then Exit;
      Result := ParseAddr(S, Addr);
      if not Result then MessageDlg('Not an address or a label: ' + S, mtError, [mbOK], 0);
    until Result;
    Exit;
  end;
  A := Addr;
  Dlg := TC64AddressDialog.CreateNew(Self, 0);
  try
    Dlg.Caption := ATitle;
    Dlg.BorderStyle := bsDialog;
    Dlg.Position := poOwnerFormCenter;
    Dlg.ClientWidth := 420;
    Dlg.ClientHeight := 330;
    Lbl := TLabel.Create(Dlg);
    Lbl.Parent := Dlg;
    Lbl.Caption := 'Address, label or expression (hex):';
    Lbl.SetBounds(10, 10, 400, 18);
    Dlg.Edit := TEdit.Create(Dlg);
    Dlg.Edit.Parent := Dlg;
    Dlg.Edit.SetBounds(10, 32, 400, 24);
    Dlg.Edit.Text := Hex4(Addr);
    Lbl := TLabel.Create(Dlg);
    Lbl.Parent := Dlg;
    Lbl.Caption := 'Last addresses (click to use, double-click to go):';
    Lbl.SetBounds(10, 66, 400, 18);
    Dlg.List := TListBox.Create(Dlg);
    Dlg.List.Parent := Dlg;
    Dlg.List.SetBounds(10, 88, 400, 190);
    Dlg.List.Items.Assign(FHistory);
    Dlg.List.OnClick := @Dlg.ListClick;
    Dlg.List.OnDblClick := @Dlg.ListDblClick;
    Btn := TButton.Create(Dlg);
    Btn.Parent := Dlg;
    Btn.Caption := 'OK';
    Btn.Default := True;
    Btn.ModalResult := mrOK;
    Btn.SetBounds(250, 290, 75, 28);
    Btn := TButton.Create(Dlg);
    Btn.Parent := Dlg;
    Btn.Caption := 'Cancel';
    Btn.Cancel := True;
    Btn.ModalResult := mrCancel;
    Btn.SetBounds(335, 290, 75, 28);
    // Straight to the execution point, without adding it to the list
    Btn := TButton.Create(Dlg);
    Btn.Parent := Dlg;
    Btn.Caption := 'Go to PC';
    Btn.Hint := Format('Go to the execution point (%s)', [Hex4(FSnapRegs.PC)]);
    Btn.ShowHint := True;
    Btn.ModalResult := mrYes;
    Btn.SetBounds(10, 290, 100, 28);
    ThemeForm(Dlg);
    Dlg.ActiveControl := Dlg.Edit;
    repeat
      case Dlg.ShowModal of
        mrOK: ;
        mrYes:
          begin
            Addr := FSnapRegs.PC;
            Exit(True);
          end;
      else
        Exit;
      end;
      S := Trim(Dlg.Edit.Text);
      if ParseAddr(S, A) then Break;
      MessageDlg('Not an address or a label: ' + S, mtError, [mbOK], 0);
    until False;
  finally
    Dlg.Free;
  end;
  Addr := A;
  Result := True;
  // Remembered as an address, the most recent first
  S := Hex4(A);
  I := FHistory.IndexOf(S);
  if I >= 0 then FHistory.Delete(I);
  FHistory.Insert(0, S);
  while FHistory.Count > MAX_HISTORY do FHistory.Delete(FHistory.Count - 1);
end;

function TC64DebuggerWindow.AskRange(const ACaption: string; var Addr: Word; var Len: Integer): Boolean;
var
  Dlg: TForm;
  AddrEdit, LenEdit: TEdit;
  Btn: TButton;
  A: Word;
  V: Integer;

  function AddEdit(const ALabel, AText: string; ATop: Integer): TEdit;
  var
    Lbl: TLabel;
  begin
    Lbl := TLabel.Create(Dlg);
    Lbl.Parent := Dlg;
    Lbl.Caption := ALabel;
    Lbl.SetBounds(10, ATop + 4, 170, 18);
    Result := TEdit.Create(Dlg);
    Result.Parent := Dlg;
    Result.SetBounds(180, ATop, 110, 24);
    Result.Text := AText;
  end;

begin
  Result := False;
  V := 0;
  A := 0;
  Dlg := TForm.CreateNew(Self, 0);
  try
    Dlg.Caption := ACaption;
    Dlg.BorderStyle := bsDialog;
    Dlg.Position := poOwnerFormCenter;
    Dlg.ClientWidth := 300;
    Dlg.ClientHeight := 130;
    AddrEdit := AddEdit('Address (hex or label):', Hex4(Addr), 12);
    LenEdit := AddEdit('Length in bytes (hex):', IntToHex(Len, 4), 46);
    Btn := TButton.Create(Dlg);
    Btn.Parent := Dlg;
    Btn.Caption := 'OK';
    Btn.Default := True;
    Btn.ModalResult := mrOK;
    Btn.SetBounds(130, 92, 75, 28);
    Btn := TButton.Create(Dlg);
    Btn.Parent := Dlg;
    Btn.Caption := 'Cancel';
    Btn.Cancel := True;
    Btn.ModalResult := mrCancel;
    Btn.SetBounds(215, 92, 75, 28);
    Dlg.ActiveControl := AddrEdit;
    ThemeForm(Dlg);
    repeat
      if Dlg.ShowModal <> mrOK then Exit;
      if not ParseAddr(AddrEdit.Text, A) then
        MessageDlg('Not a valid address: ' + AddrEdit.Text, mtError, [mbOK], 0)
      else if not ParseHex(LenEdit.Text, V) or (V < 1) or (V > $10000) then
        MessageDlg('The length must be a hex number from 1 to 10000.', mtError, [mbOK], 0)
      else
        Break;
    until False;
    Addr := A;
    Len := V;
    Result := True;
  finally
    Dlg.Free;
  end;
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
  // A notice stays a few seconds
  if (FNotice <> '') and (GetTickCount64 - FNoticeTime < 4000) then FStatusBar.SimpleText := FNotice
  else
  begin
    FNotice := '';
    if FRunning then FStatusBar.SimpleText := 'running'
    else if FReason <> '' then FStatusBar.SimpleText := 'stopped: ' + FReason
    else FStatusBar.SimpleText := 'stopped';
  end;
  // The disassembly follows the PC while it is stopped, unless the user scrolled away
  if Idle and FFollow then FDis.EnsureVisible(FSnapRegs.PC) else FDis.Invalidate;
  FRegView.Invalidate;
  FStack.Invalidate;
  FPorts.Invalidate;
  FZero.Invalidate;
  FMem.Invalidate;
  FBreakView.Invalidate;
  FWatchView.Invalidate;
  if (FSysForm <> nil) and FSysForm.Visible then
  begin
    if FSysMemo.Text <> FSysText then FSysMemo.Text := FSysText;
    FChipView.Invalidate;
  end;
end;

procedure TC64DebuggerWindow.Refresh(Force: Boolean);
begin
  if not Visible and not Force then Exit;
  if FEmu.Spec.C64Hw = nil then Exit;
  // Not while a value is being typed: the box would lose what it shows
  if not Force and (FDis.Editing or FRegView.Editing or FStack.Editing or FZero.Editing or FMem.Editing or
    ((FChipView <> nil) and FChipView.Editing)) then Exit;
  Take;
  UpdateAll;
end;

procedure TC64DebuggerWindow.TimerTick(Sender: TObject);
begin
  // While the machine runs, a few times a second; stopped, only to clear the notices
  if Visible and (FRunning or (FNotice <> '')) then Refresh(False);
end;

procedure TC64DebuggerWindow.BreakHit;
begin
  FFollow := True;
  if not Visible then Show;
  BringToFront;
  Refresh(True);
  ShowAt(FSnapRegs.PC);
end;

{ ---- running ---- }

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
  if FEmu.Paused then
  begin
    FEmu.SaveBackPoint;   // Shift+F7 comes back here
    Resume;
  end
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
  FDis.Sel := -1;
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
  FDis.Sel := -1;
  if IsSubroutineCall(PC, @Peek) then RunToAddr(Word(PC + 3))
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
  FDis.Sel := -1;
  Ret := Word((FPeek[Word($0100 or Byte(FSnapRegs.SP + 2))] shl 8) or FPeek[Word($0100 or Byte(FSnapRegs.SP + 1))]) + 1;
  RunToAddr(Ret);
end;

procedure TC64DebuggerWindow.RunToAddr(Addr: Word);
begin
  FEmu.PauseAndWait;
  FEmu.SaveBackPoint;   // Shift+F7 comes back here
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

{ As the Z80 debugger's: the machine as it was before the last step, step over, step out, run to cursor or run }
procedure TC64DebuggerWindow.DoStepBack(Sender: TObject);
begin
  if not FEmu.Paused then FEmu.PauseAndWait;
  FReason := '';
  FFollow := True;
  FDis.Sel := -1;
  if not FEmu.StepBack then
  begin
    Beep;
    Refresh(True);
    ShowNotice(Format('No earlier position to go back to (the last %d are kept)', [MAX_BACK]));
    Exit;
  end;
  Refresh(True);
  ShowNotice(Format('Back one step (%d more kept)', [FEmu.BackCount]));
end;

procedure TC64DebuggerWindow.DoOpcodes(Sender: TObject);
begin
  ShowC64Opcodes;
end;

{ ---- breakpoints ---- }

procedure TC64DebuggerWindow.SetBpFlags(Addr: Word; Flags: Byte);
begin
  if (Flags and (C64_BP_EXEC or C64_BP_READ or C64_BP_WRITE)) = 0 then Flags := 0;
  FEmu.Lock;
  try
    // A range keeps being one: all of its addresses change
    FEmu.Spec.Breakpoint[Addr] := Flags;
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
  if F <> 0 then F := 0 else F := C64_BP_EXEC;
  SetBpFlags(Addr, F);
end;

procedure TC64DebuggerWindow.DoToggleBp(Sender: TObject);
begin
  ToggleBpAt(FDis.SelAddr);
end;

procedure TC64DebuggerWindow.ToggleDataBreak(Addr, First, Last: Word; Bit: Byte);
var
  Flags, NewFlags: Byte;
begin
  FEmu.Lock;
  try
    Flags := FEmu.Spec.Breakpoint[Addr];
    if Flags <> 0 then
    begin
      // One already there (for the whole of its range): an execution one becomes this type, a data one gets the type
      // switched on or off
      if (Flags and C64_BP_EXEC) <> 0 then NewFlags := Bit or (Flags and C64_BP_DISABLED)
      else
      begin
        NewFlags := Flags xor Bit;
        if (NewFlags and (C64_BP_READ or C64_BP_WRITE)) = 0 then NewFlags := 0;
      end;
      FEmu.Spec.Breakpoint[Addr] := NewFlags;
    end
    else
    begin
      if Last > First then FEmu.Spec.SetBreakRange(First, Last, False);
      FEmu.Spec.Breakpoint[First] := Bit;
    end;
  finally
    FEmu.Unlock;
  end;
  Refresh(True);
end;

{ Add or change a breakpoint: an address or a range, its type, a condition and whether it is on }
procedure TC64DebuggerWindow.BpDialog(Index: Integer; DefaultAddr: Word);
const
  TYPE_FLAGS: array[0..3] of Byte = (C64_BP_EXEC, C64_BP_READ, C64_BP_WRITE, C64_BP_READ or C64_BP_WRITE);
var
  Dlg: TForm;
  AddrEdit, EndEdit, CondEdit: TEdit;
  TypeCombo: TComboBox;
  EnabledCheck: TCheckBox;
  Help: TMemo;
  Btn: TButton;
  Flags: Byte;
  A, Last: Word;
  I: Integer;
  Error: string;
  Ok: Boolean;
  Follower: TEndFollower;
  Test: TC64Condition;
  Old: TBpEntry;

  procedure AddLabel(const ACaption: string; ATop: Integer; ALeft: Integer = 10);
  var
    Lbl: TLabel;
  begin
    Lbl := TLabel.Create(Dlg);
    Lbl.Parent := Dlg;
    Lbl.Caption := ACaption;
    Lbl.SetBounds(ALeft, ATop, 560 - ALeft, 18);
  end;

begin
  if Index > High(FBpList) then Exit;
  Flags := C64_BP_EXEC;
  if Index >= 0 then
  begin
    Old := FBpList[Index];
    Flags := Old.Flags;
  end;
  Follower := TEndFollower.Create;
  Dlg := TForm.CreateNew(Self, 0);
  try
    if Index >= 0 then Dlg.Caption := 'Edit breakpoint' else Dlg.Caption := 'Add breakpoint';
    Dlg.BorderStyle := bsDialog;
    Dlg.Position := poOwnerFormCenter;
    Dlg.ClientWidth := 580;
    Dlg.ClientHeight := 560;
    AddLabel('Address:', 10);
    AddLabel('End address:', 10, 150);
    AddLabel('Type:', 10, 320);
    AddrEdit := TEdit.Create(Dlg);
    AddrEdit.Parent := Dlg;
    AddrEdit.SetBounds(10, 30, 130, 24);
    if Index >= 0 then AddrEdit.Text := Hex4(Old.First) else AddrEdit.Text := Hex4(DefaultAddr);
    // The end: the same as the start (one address) until it is changed
    EndEdit := TEdit.Create(Dlg);
    EndEdit.Parent := Dlg;
    EndEdit.SetBounds(150, 30, 130, 24);
    EndEdit.Text := AddrEdit.Text;
    if (Index >= 0) and (Old.Last <> Old.First) then EndEdit.Text := Hex4(Old.Last);
    Follower.StartEdit := AddrEdit;
    Follower.EndEdit := EndEdit;
    Follower.Own := EndEdit.Text <> AddrEdit.Text;
    AddrEdit.OnChange := @Follower.StartChange;
    EndEdit.OnChange := @Follower.EndChange;
    TypeCombo := TComboBox.Create(Dlg);
    TypeCombo.Parent := Dlg;
    TypeCombo.Style := csDropDownList;
    TypeCombo.SetBounds(320, 30, 250, 24);
    TypeCombo.Items.Add('Execution');
    TypeCombo.Items.Add('Memory read');
    TypeCombo.Items.Add('Memory write');
    TypeCombo.Items.Add('Memory read or write (any)');
    TypeCombo.ItemIndex := 0;
    for I := 0 to 3 do
      if TYPE_FLAGS[I] = Flags and (C64_BP_EXEC or C64_BP_READ or C64_BP_WRITE) then TypeCombo.ItemIndex := I;
    AddLabel('Hex; addresses may also be a register or a label. A different end makes', 60);
    AddLabel('one breakpoint over the whole range (a range has no condition).', 76);
    AddLabel('Condition (empty = always stop; see below):', 102);
    CondEdit := TEdit.Create(Dlg);
    CondEdit.Parent := Dlg;
    CondEdit.SetBounds(10, 122, 560, 24);
    if Index >= 0 then CondEdit.Text := Old.Cond;
    EnabledCheck := TCheckBox.Create(Dlg);
    EnabledCheck.Parent := Dlg;
    EnabledCheck.Caption := 'Enabled';
    EnabledCheck.SetBounds(10, 152, 200, 24);
    EnabledCheck.Checked := (Flags and C64_BP_DISABLED) = 0;
    // A short manual of the condition language
    Help := TMemo.Create(Dlg);
    Help.Parent := Dlg;
    Help.SetBounds(10, 184, 560, 324);
    Help.ReadOnly := True;
    Help.ScrollBars := ssAutoVertical;
    Help.Font.Name := MONO_FONT;
    Help.Font.Size := 9;
    Help.Color := RGBToColor(250, 250, 238);
    Help.Lines.Text :=
      'EXAMPLES' + LineEnding +
      '  A=3' + LineEnding +
      '  X=10 AND #Z=1' + LineEnding +
      '  PC>=C000 AND PC<C100' + LineEnding +
      '  A = X * 2' + LineEnding +
      '  A = Y & 7' + LineEnding +
      '  A=@0400' + LineEnding +
      '  @D012 = .100' + LineEnding +
      '  @(FB) = 20' + LineEnding +
      '  PC = CHROUT' + LineEnding +
      '  A=0D OR A=20' + LineEnding +
      '  T=5' + LineEnding +
      '  T>=2 AND A=0' + LineEnding +
      '  NOT (#C=1)' + LineEnding + LineEnding +
      'CONDITIONS SYNTAX' + LineEnding +
      'The breakpoint stops only when its condition is true.' + LineEnding +
      'Empty condition = always stop.' + LineEnding + LineEnding +
      'Numbers are hex: 10 is sixteen, FF, $FF and FFh are 255.' + LineEnding +
      'With a dot they are decimal: .30 is thirty.' + LineEnding + LineEnding +
      'Registers (upper or lower case):' + LineEnding +
      '  8 bits:  A X Y SP P' + LineEnding +
      '  16 bits: PC' + LineEnding + LineEnding +
      'A name is first a register, then a symbol (yours, then' + LineEnding +
      'the labels of roms/c64.sym, then the KERNAL entry points' + LineEnding +
      'and the chip registers), then a hex number:' + LineEnding +
      '  A X Y alone are registers; A=0A means A is 10. A' + LineEnding +
      '  leading 0 always makes a number: 0ADD, 0CAFE.' + LineEnding +
      '  Symbols are looked up when the condition is set.' + LineEnding + LineEnding +
      'Flags (0 or 1): #N #V #B #D #I #Z #C' + LineEnding + LineEnding +
      '@x is the byte in memory at address x, as the processor' + LineEnding +
      '  sees it: @D012, @(FB), @VIC_RASTER.' + LineEnding + LineEnding +
      'T = times this breakpoint has been reached, this one' + LineEnding +
      '  included. T=3 stops the 3rd time, T>=3 from then on.' + LineEnding +
      '  The count restarts when the condition is changed.' + LineEnding + LineEnding +
      'Operators, lowest priority first:' + LineEnding +
      '  OR  XOR       logical: either / only one is true' + LineEnding +
      '  AND           logical: both are true' + LineEnding +
      '  NOT           logical: is not true' + LineEnding +
      '  = <> < > <= >=' + LineEnding +
      '  + -           add, subtract' + LineEnding +
      '  |             bitwise or: A | 80 sets bit 7' + LineEnding +
      '  * / MOD       multiply, divide, remainder' + LineEnding +
      '  &             bitwise and: Y & 7 keeps bits 0-2' + LineEnding +
      '  - @           negative, memory byte (prefixes)' + LineEnding +
      '  ( )           group' + LineEnding +
      'AND/OR/XOR/NOT combine true/false; & and | work on the' + LineEnding +
      'bits of a value: "A = Y & 7" is not "A = Y AND 7".' + LineEnding + LineEnding +
      'Read and write conditions are checked when the' + LineEnding +
      'instruction touches the address, with the registers as' + LineEnding +
      'they are then.';
    Btn := TButton.Create(Dlg);
    Btn.Parent := Dlg;
    Btn.Caption := 'OK';
    Btn.Default := True;
    Btn.ModalResult := mrOK;
    Btn.SetBounds(410, 520, 75, 28);
    Btn := TButton.Create(Dlg);
    Btn.Parent := Dlg;
    Btn.Caption := 'Cancel';
    Btn.Cancel := True;
    Btn.ModalResult := mrCancel;
    Btn.SetBounds(495, 520, 75, 28);
    Dlg.ActiveControl := AddrEdit;
    ThemeForm(Dlg);
    Help.Color := TC(RGBToColor(250, 250, 238));
    repeat
      if Dlg.ShowModal <> mrOK then Exit;
      Ok := ParseAddr(AddrEdit.Text, A) and ParseAddr(EndEdit.Text, Last);
      if not Ok then
      begin
        MessageDlg('Not a valid address: ' + AddrEdit.Text + ' / ' + EndEdit.Text, mtError, [mbOK], 0);
        Continue;
      end;
      if Last < A then
      begin
        MessageDlg('The end address can''t be before the start.', mtError, [mbOK], 0);
        Ok := False;
        Continue;
      end;
      if (Last > A) and (Trim(CondEdit.Text) <> '') then
      begin
        MessageDlg('A range has no condition: leave it empty, or make the end the same as the start.', mtError,
          [mbOK], 0);
        Ok := False;
        Continue;
      end;
      // Check the condition before changing anything
      if Trim(CondEdit.Text) <> '' then
      begin
        Test := CompileC64Condition(CondEdit.Text, Error);
        if Test = nil then
        begin
          MessageDlg('Invalid condition: ' + Error, mtError, [mbOK], 0);
          Ok := False;
          Continue;
        end;
        Test.Free;
      end;
      Flags := TYPE_FLAGS[TypeCombo.ItemIndex];
      if not EnabledCheck.Checked then Flags := Flags or C64_BP_DISABLED;
      FEmu.Lock;
      try
        // The old one (all of its range) goes, then the new one is set
        if Index >= 0 then FEmu.Spec.Breakpoint[Old.First] := 0;
        FEmu.Spec.SetBreakRange(A, Last, False);
        FEmu.Spec.Breakpoint[A] := Flags;
        Ok := FEmu.Spec.SetBreakCondition(A, CondEdit.Text, Error);
        if not Ok then FEmu.Spec.Breakpoint[A] := 0;
      finally
        FEmu.Unlock;
      end;
      if not Ok then MessageDlg('Invalid condition: ' + Error, mtError, [mbOK], 0);
    until Ok;
  finally
    Dlg.Free;
    Follower.Free;
  end;
  Refresh(True);
end;

procedure TC64DebuggerWindow.DoAddBp(Sender: TObject);
begin
  BpDialog(-1, FDis.SelAddr);
end;

procedure TC64DebuggerWindow.EditBpAt(Index: Integer);
begin
  BpDialog(Index, 0);
end;

procedure TC64DebuggerWindow.DeleteBp(Index: Integer);
begin
  if (Index < 0) or (Index > High(FBpList)) then Exit;
  FEmu.Lock;
  try
    FEmu.Spec.Breakpoint[FBpList[Index].First] := 0;
  finally
    FEmu.Unlock;
  end;
  Refresh(True);
end;

procedure TC64DebuggerWindow.ToggleBpEnabled(Index: Integer);
begin
  if (Index < 0) or (Index > High(FBpList)) then Exit;
  SetBpFlags(FBpList[Index].First, FBpList[Index].Flags xor C64_BP_DISABLED);
end;

procedure TC64DebuggerWindow.DoClearBps(Sender: TObject);
begin
  FEmu.Lock;
  try
    FEmu.Spec.ClearBreakpoints;
  finally
    FEmu.Unlock;
  end;
  FBreakView.Sel := -1;
  Refresh(True);
end;

procedure TC64DebuggerWindow.SaveBreaksAs;
var
  Dlg: TSaveDialog;
begin
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := 'Breakpoints (*.json)|*.json|All files|*.*';
    Dlg.DefaultExt := 'json';
    Dlg.FileName := 'breakpoints.json';
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    if not Dlg.Execute then Exit;
    FEmu.Lock;
    try
      try
        SaveBreakpoints(FEmu.Spec, Dlg.FileName);
        ShowNotice('Breakpoints saved to ' + ExtractFileName(Dlg.FileName));
      except
        on E: Exception do MessageDlg('Could not save: ' + E.Message, mtError, [mbOK], 0);
      end;
    finally
      FEmu.Unlock;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TC64DebuggerWindow.LoadBreaksAsk;
var
  Dlg: TOpenDialog;
  Ok: Boolean;
  Error: string;
begin
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Filter := 'Breakpoints (*.json)|*.json|All files|*.*';
    Dlg.Options := Dlg.Options + [ofFileMustExist];
    if not Dlg.Execute then Exit;
    FEmu.Lock;
    try
      Ok := LoadBreakpoints(FEmu.Spec, Dlg.FileName, Error);
    finally
      FEmu.Unlock;
    end;
    if Ok then ShowNotice('Breakpoints loaded from ' + ExtractFileName(Dlg.FileName))
    else MessageDlg('Could not load the breakpoints: ' + Error, mtError, [mbOK], 0);
  finally
    Dlg.Free;
  end;
  FBreakView.Sel := -1;
  Refresh(True);
end;

{ ---- watches ---- }

procedure TC64DebuggerWindow.AddWatchText(const S: string);
begin
  if Trim(S) = '' then Exit;
  FWatchText.Add(Trim(S));
  Refresh(True);
end;

procedure TC64DebuggerWindow.DoAddWatch(Sender: TObject);
var
  S: string;
begin
  S := '';
  if InputQuery('Watch', 'Expression (e.g. @D012, A, @(FB), @VIC_RASTER):', S) then AddWatchText(S);
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

// The watches file: {"ochenta": "c64-watches", "version": 1, "watches": ["@D012", "A", ...]}
procedure TC64DebuggerWindow.SaveWatchesAs;
var
  Dlg: TSaveDialog;
  Root: TJSONObject;
  List: TJSONArray;
  L: TStringList;
  I: Integer;
begin
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := 'Watches (*.json)|*.json|All files|*.*';
    Dlg.DefaultExt := 'json';
    Dlg.FileName := 'watches.json';
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    if not Dlg.Execute then Exit;
    Root := TJSONObject.Create;
    L := TStringList.Create;
    try
      Root.Add('ochenta', 'c64-watches');
      Root.Add('version', 1);
      List := TJSONArray.Create;
      for I := 0 to FWatchText.Count - 1 do List.Add(FWatchText[I]);
      Root.Add('watches', List);
      L.Text := Root.FormatJSON;
      try
        L.SaveToFile(Dlg.FileName);
        ShowNotice('Watches saved to ' + ExtractFileName(Dlg.FileName));
      except
        on E: Exception do MessageDlg('Could not save: ' + E.Message, mtError, [mbOK], 0);
      end;
    finally
      L.Free;
      Root.Free;
    end;
  finally
    Dlg.Free;
  end;
end;

{ The C64 debugger's watches ("c64-watches": expressions) or the Z80 debugger's ("watches": addresses, each watched
  here as the byte at it, @$xxxx) }
function TC64DebuggerWindow.LoadWatchesFile(const FileName: string; out Error: string): Boolean;
var
  L: TStringList;
  Data: TJSONData;
  List: TJSONArray;
  I: Integer;
  Kind, S: string;
begin
  Error := '';
  Data := nil;
  L := TStringList.Create;
  try
    try
      L.LoadFromFile(FileName);
      Data := GetJSON(L.Text);
    except
      on E: Exception do Error := E.Message;
    end;
  finally
    L.Free;
  end;
  try
    Kind := '';
    if (Error = '') and (Data is TJSONObject) then Kind := TJSONObject(Data).Get('ochenta', '');
    if (Error = '') and (Kind <> 'c64-watches') and (Kind <> 'watches') then
      Error := 'not an ochenta watches file';
    if Error = '' then
    begin
      List := TJSONObject(Data).Get('watches', TJSONArray(nil));
      if List = nil then Error := 'no "watches" list'
      else
      begin
        FWatchText.Clear;
        for I := 0 to List.Count - 1 do
        begin
          S := Trim(List.Strings[I]);
          if S = '' then Continue;
          if Kind = 'watches' then S := '@$' + S;
          FWatchText.Add(S);
        end;
      end;
    end;
  finally
    Data.Free;
  end;
  Result := Error = '';
  FWatchView.Sel := -1;
  Refresh(True);
end;

procedure TC64DebuggerWindow.LoadWatchesAsk;
var
  Dlg: TOpenDialog;
  Error: string;
begin
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Filter := 'Watches (*.json)|*.json|All files|*.*';
    Dlg.Options := Dlg.Options + [ofFileMustExist];
    if not Dlg.Execute then Exit;
    if not LoadWatchesFile(Dlg.FileName, Error) then
      MessageDlg('Could not load the watches: ' + Error, mtError, [mbOK], 0)
    else ShowNotice('Watches loaded from ' + ExtractFileName(Dlg.FileName));
  finally
    Dlg.Free;
  end;
end;

{ ---- changing things ---- }

procedure TC64DebuggerWindow.DoGoto(Sender: TObject);
var
  A: Word;
begin
  if (ActiveControl = FMem) or (ActiveControl = FZero) then
  begin
    A := FMem.TopAddr;
    if AskAddress('Go to address in the memory', A) then FMem.GoToAddr(A);
  end
  else
  begin
    A := FDis.SelAddr;
    if AskAddress('Go to address in the disassembly', A) then FDis.GoToAddr(A);
  end;
end;

procedure TC64DebuggerWindow.GoToCode(Addr: Word);
begin
  FDis.GoToAddr(Addr);
  if FDis.CanFocus then FDis.SetFocus;
end;

procedure TC64DebuggerWindow.ViewData(Addr: Word);
begin
  if Addr < $100 then FZero.GoToAddr(Addr);
  FMem.GoToAddr(Addr);
  if FMem.CanFocus then FMem.SetFocus;
end;

procedure TC64DebuggerWindow.SetPCAt(Addr: Word);
begin
  FDis.Sel := -1;
  SetRegister(4, Addr);
end;

procedure TC64DebuggerWindow.SetRegister(Index, Value: Integer);
var
  R: T6502Regs;
begin
  FEmu.PauseAndWait;
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
  // A change by hand is not a step: no dark red for it
  FHavePrev := False;
  if Index = 4 then FFollow := True;
  Refresh(True);
end;

procedure TC64DebuggerWindow.ToggleFlag(Mask: Byte);
begin
  SetRegister(5, FSnapRegs.P xor Mask);
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

procedure TC64DebuggerWindow.PokeMem(Addr: Word; Value: Byte);
begin
  PokeAt(Addr, Value, RamOnly);
end;

procedure TC64DebuggerWindow.PokeIoAt(Addr: Word; Value: Byte);
begin
  FEmu.Lock;
  try
    FEmu.Spec.C64Hw.PokeIo(Addr, Value);
  finally
    FEmu.Unlock;
  end;
  Refresh(True);
end;

{ Up to FFFF (no wrapping to 0000); what the processor sees (a ROM's area: the RAM under it), or the RAM if "RAM only" }
procedure TC64DebuggerWindow.WriteBytes(Addr: Word; const Values: TBytes);
var
  I, Count: Integer;
  Ram: Boolean;
begin
  Count := Min(Length(Values), $10000 - Addr);
  Ram := RamOnly;
  FEmu.Lock;
  try
    for I := 0 to Count - 1 do
      if Ram then FEmu.Spec.C64Hw.PokeRam(Addr + I, Values[I]) else FEmu.Spec.C64Hw.Poke(Addr + I, Values[I]);
  finally
    FEmu.Unlock;
  end;
  Refresh(True);
  if Count < Length(Values) then
  begin
    Beep;
    ShowNotice(Format('Pasted %d bytes at %s; %d more would go past FFFF and were not written',
      [Count, Hex4(Addr), Length(Values) - Count]));
  end
  else ShowNotice(Format('Pasted %d bytes at %s', [Count, Hex4(Addr)]));
end;

procedure TC64DebuggerWindow.SetBank(Bank: Integer);
begin
  FEmu.Lock;
  try
    // Bits 0-2 of the port as outputs, then their values
    FEmu.Spec.C64Hw.Poke(0, FEmu.Spec.C64Hw.Ddr or 7);
    FEmu.Spec.C64Hw.Poke(1, (FEmu.Spec.C64Hw.Port and $F8) or (Bank and 7));
  finally
    FEmu.Unlock;
  end;
  Refresh(True);
  ShowNotice('Memory configuration ' + BankText(Bank));
end;

procedure TC64DebuggerWindow.ChooseBank;
var
  I: Integer;
  P: TPoint;
begin
  for I := 0 to FBankMenu.Items.Count - 1 do FBankMenu.Items[I].Checked := FBankMenu.Items[I].Tag = FBank;
  P := Mouse.CursorPos;
  FBankMenu.PopUp(P.X, P.Y);
end;

procedure TC64DebuggerWindow.BankClick(Sender: TObject);
begin
  SetBank((Sender as TMenuItem).Tag);
end;

procedure TC64DebuggerWindow.EditLabel(Addr: Word);
var
  LName: string;
  I: Integer;
  Ok: Boolean;
begin
  LName := UserSymbols.Lookup(Addr);
  repeat
    if not InputQuery('Label', Format('Name for %s (letters, digits and _; empty: no label). ' +
      'It is kept when exporting as assembler:', [Hex4(Addr)]), LName) then Exit;
    LName := Trim(LName);
    Ok := True;
    for I := 1 to Length(LName) do
      if not (LName[I] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '.', '?', '!', '@']) then Ok := False;
    if (LName <> '') and (LName[1] in ['0'..'9']) then Ok := False;
    if not Ok then
      MessageDlg('A label has letters, digits, _ . ? ! and @, and doesn''t start with a digit.', mtError, [mbOK], 0);
  until Ok;
  UserSymbols.SetName(Addr, LName);
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
      ShowNotice(Format('%d symbols read from %s', [N, ExtractFileName(Dlg.FileName)]));
      Refresh(True);
    end;
  finally
    Dlg.Free;
  end;
end;

{ The chips' registers (changed in place) and the state of the chips and the drives, in a window of its own }
procedure TC64DebuggerWindow.DoSystem(Sender: TObject);
var
  Pages: TPageControl;
  Tab: TTabSheet;
begin
  if FSysForm = nil then
  begin
    FSysForm := TForm.CreateNew(Self);
    FSysForm.Caption := 'Commodore 64 chips';
    FSysForm.Position := poOwnerFormCenter;
    FSysForm.Width := 980;
    FSysForm.Height := 560;
    Pages := TPageControl.Create(FSysForm);
    Pages.Parent := FSysForm;
    Pages.Align := alClient;
    Tab := Pages.AddTabSheet;
    Tab.Caption := 'Registers';
    FChipView := TC64ChipView.CreateView(Self);
    FChipView.Parent := Tab;
    FChipView.Align := alClient;
    Tab := Pages.AddTabSheet;
    Tab.Caption := 'State';
    FSysMemo := TMemo.Create(FSysForm);
    FSysMemo.Parent := Tab;
    FSysMemo.Align := alClient;
    FSysMemo.ReadOnly := True;
    FSysMemo.ScrollBars := ssBoth;
    FSysMemo.WordWrap := False;
    FSysMemo.Font.Name := MONO_FONT;
    FSysMemo.Font.Size := 10;
    Pages.ActivePageIndex := 0;
    ThemeForm(FSysForm);
  end;
  FSysForm.Show;
  FSysForm.BringToFront;
  Refresh(True);
  FSysMemo.Text := FSysText;
end;

{ ---- export and import ---- }

procedure TC64DebuggerWindow.ExportMemory;
var
  Addr: Word;
  Len, I: Integer;
  Dlg: TSaveDialog;
  Lines: TStringList;
  Data: TBytes;
begin
  Addr := FMem.TopAddr;
  Len := FMem.VisibleBytes;
  if not AskRange('Export memory', Addr, Len) then Exit;
  Dlg := TSaveDialog.Create(Self);
  Lines := TStringList.Create;
  try
    Dlg.Filter := 'Text files (*.txt)|*.txt|All files|*.*';
    Dlg.DefaultExt := 'txt';
    Dlg.FileName := Format('mem_%.4X_%.4X.txt', [Addr, Len]);
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    if not Dlg.Execute then Exit;
    // As the memory zone shows it (what the processor sees, or the RAM), without the XOR
    SetLength(Data, Len);
    for I := 0 to Len - 1 do
      if RamOnly then Data[I] := FRam[Word(Addr + I)] else Data[I] := FPeek[Word(Addr + I)];
    Lines.Text := FormatValues(Data);
    try
      Lines.SaveToFile(Dlg.FileName);
      ShowNotice(Format('Exported %d bytes from %s to %s', [Len, Hex4(Addr), ExtractFileName(Dlg.FileName)]));
    except
      on E: Exception do MessageDlg('Could not save: ' + E.Message, mtError, [mbOK], 0);
    end;
  finally
    Lines.Free;
    Dlg.Free;
  end;
end;

procedure TC64DebuggerWindow.ImportMemory;
var
  Addr: Word;
  Len: Integer;
  Dlg: TOpenDialog;
  Values: TBytes;
  Error: string;
  Lines: TStringList;
  Ok: Boolean;
begin
  Addr := FMem.TopAddr;
  Len := FMem.VisibleBytes;
  if not AskRange('Import memory', Addr, Len) then Exit;
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Filter := 'Text files (*.txt)|*.txt|All files|*.*';
    Dlg.Options := Dlg.Options + [ofFileMustExist];
    if not Dlg.Execute then Exit;
    try
      Lines := TStringList.Create;
      try
        Lines.LoadFromFile(Dlg.FileName);
        Ok := ParseValues(Lines.Text, Values, Error);
      finally
        Lines.Free;
      end;
    except
      on E: Exception do
      begin
        MessageDlg('Import failed: ' + E.Message, mtError, [mbOK], 0);
        Exit;
      end;
    end;
    if not Ok then
    begin
      MessageDlg('Import failed: ' + Error + '.', mtError, [mbOK], 0);
      Exit;
    end;
    if Length(Values) < Len then
    begin
      MessageDlg(Format('Import failed: the file has %d values and %d are needed.', [Length(Values), Len]), mtError,
        [mbOK], 0);
      Exit;
    end;
    SetLength(Values, Len);
    WriteBytes(Addr, Values);
    ShowNotice(Format('Imported %d bytes at %s', [Len, Hex4(Addr)]));
  finally
    Dlg.Free;
  end;
end;

procedure TC64DebuggerWindow.ExportBinary;
var
  Addr: Word;
  Len, I: Integer;
  Dlg: TSaveDialog;
  Data: TBytes;
  F: TFileStream;
begin
  Addr := FMem.TopAddr;
  Len := FMem.VisibleBytes;
  if not AskRange('Export binary', Addr, Len) then Exit;
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := 'Binary files (*.bin)|*.bin|All files|*.*';
    Dlg.DefaultExt := 'bin';
    Dlg.FileName := Format('mem_%.4X_%.4X.bin', [Addr, Len]);
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    if not Dlg.Execute then Exit;
    SetLength(Data, Len);
    for I := 0 to Len - 1 do
      if RamOnly then Data[I] := FRam[Word(Addr + I)] else Data[I] := FPeek[Word(Addr + I)];
    try
      F := TFileStream.Create(Dlg.FileName, fmCreate);
      try
        F.WriteBuffer(Data[0], Len);
      finally
        F.Free;
      end;
      ShowNotice(Format('Exported %d bytes from %s to %s', [Len, Hex4(Addr), ExtractFileName(Dlg.FileName)]));
    except
      on E: Exception do MessageDlg('Could not save: ' + E.Message, mtError, [mbOK], 0);
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TC64DebuggerWindow.ImportBinary;
var
  Addr: Word;
  Dlg: TOpenDialog;
  F: TFileStream;
  Data: TBytes;
  N, Past: Integer;
begin
  Addr := FMem.TopAddr;
  if not AskAddress('Import binary: load at address', Addr, False) then Exit;
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Filter := 'All files|*.*';
    Dlg.Options := Dlg.Options + [ofFileMustExist];
    if not Dlg.Execute then Exit;
    try
      F := TFileStream.Create(Dlg.FileName, fmOpenRead or fmShareDenyWrite);
      try
        SetLength(Data, F.Size);
        if F.Size > 0 then F.ReadBuffer(Data[0], F.Size);
      finally
        F.Free;
      end;
    except
      on E: Exception do
      begin
        MessageDlg('Could not read the file: ' + E.Message, mtError, [mbOK], 0);
        Exit;
      end;
    end;
  finally
    Dlg.Free;
  end;
  N := Min(Length(Data), $10000 - Addr);
  Past := Length(Data) - N;
  WriteBytes(Addr, Data);
  if Past > 0 then
    MessageDlg('Import binary', Format('The file has %d bytes: the last %d went past FFFF and were not loaded.',
      [Length(Data), Past]), mtWarning, [mbOK], 0)
  else ShowNotice(Format('Loaded %d bytes at %s-%s', [N, Hex4(Addr), Hex4(Addr + N - 1)]));
end;

{ 6502 source for 64tass and the like: "* = $XXXX", labels for the jumps and branches into the range (the names known,
  else L_XXXX), "NAME = $XXXX" for the names outside it, and .byte for the illegal opcodes and for absolute operands under
  $100 (an assembler would make them zero page ones) }
procedure TC64DebuggerWindow.ExportAssembler(Start: Word);
var
  Addr: Word;
  Len, I, Pass, ILen, Target: Integer;
  Dlg: TSaveDialog;
  Lines, Outside: TStringList;
  Targets: array of Boolean;
  A, Stop: LongInt;
  Op: Byte;
  Instr, LName, S, Bytes: string;

  function InRange(T: Integer): Boolean;
  begin
    Result := (T >= Addr) and (T < Stop);
  end;

  function NameFor(T: Integer): string;
  begin
    Result := SymbolName(Word(T));
    if (Result = '') and InRange(T) and Targets[T - Addr] then Result := 'L_' + Hex4(T);
  end;

begin
  Addr := Start;
  Len := $100;
  if not AskRange('Export as assembler', Addr, Len) then Exit;
  Stop := LongInt(Addr) + Len;
  if Stop > $10000 then Stop := $10000;
  Dlg := TSaveDialog.Create(Self);
  Lines := TStringList.Create;
  Outside := TStringList.Create;
  try
    Dlg.Filter := 'Assembler source (*.asm)|*.asm|All files|*.*';
    Dlg.DefaultExt := 'asm';
    Dlg.FileName := Format('code_%.4X.asm', [Addr]);
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    if not Dlg.Execute then Exit;
    Outside.Sorted := True;
    Outside.Duplicates := dupIgnore;
    SetLength(Targets, Stop - Addr);
    // Pass 0 finds the jumps' and branches' targets; pass 1 writes
    for Pass := 0 to 1 do
    begin
      A := Addr;
      while A < Stop do
      begin
        Op := FPeek[A];
        Instr := Disassemble6502(A, @Peek, ILen, Target);
        if A + ILen > Stop then ILen := 1;
        if Pass = 0 then
        begin
          if (Target >= 0) and InRange(Target) and (OpMode[Op] in [amAbs, amRel, amInd]) and
            (OpName[Op][1] in ['J', 'B']) then Targets[Target - Addr] := True;
        end
        else
        begin
          LName := SymbolName(Word(A));
          if (LName = '') and Targets[A - Addr] then LName := 'L_' + Hex4(A);
          if LName <> '' then Lines.Add(LName + ':');
          Bytes := '';
          for I := 0 to ILen - 1 do
          begin
            if I > 0 then Bytes := Bytes + ', ';
            Bytes := Bytes + '$' + Hex2(FPeek[Word(A + I)]);
          end;
          if OpIllegal[Op] or (A + OpLength(Op) > Stop) or
            ((OpMode[Op] in [amAbs, amAbx, amAby]) and (Target >= 0) and (Target < $100)) then
            S := Format('        .byte %-24s ; %s  %s', [Bytes, Hex4(A), Trim(Instr)])
          else
          begin
            S := Trim(Instr);
            if (Target >= 0) and (OpMode[Op] <> amImm) then
            begin
              LName := NameFor(Target);
              if LName <> '' then
              begin
                if OpMode[Op] in [amZp, amZpx, amZpy, amIzx, amIzy] then
                  S := StringReplace(S, '$' + Hex2(Target), LName, [])
                else S := StringReplace(S, '$' + Hex4(Target), LName, []);
                if (SymbolName(Word(Target)) <> '') and not InRange(Target) then
                  Outside.Add(Format('%s = $%s', [SymbolName(Word(Target)), IntToHex(Target,
                    IfThen(OpMode[Op] in [amZp, amZpx, amZpy, amIzx, amIzy], 2, 4))]));
              end;
            end;
            S := Format('        %-30s ; %s  %s', [S, Hex4(A), Bytes]);
          end;
          Lines.Add(S);
        end;
        Inc(A, ILen);
      end;
    end;
    Lines.Insert(0, '');
    Lines.Insert(0, Format('        * = $%s', [Hex4(Addr)]));
    Lines.Insert(0, '');
    for I := Outside.Count - 1 downto 0 do Lines.Insert(0, Outside[I]);
    Lines.Insert(0, '');
    Lines.Insert(0, Format('; %s-%s exported by the ochenta Commodore 64 debugger', [Hex4(Addr), Hex4(Stop - 1)]));
    Lines.Insert(0, '; 64tass format (assemble with 64tass)');
    try
      Lines.SaveToFile(Dlg.FileName);
      ShowNotice(Format('Exported %s-%s as assembler to %s', [Hex4(Addr), Hex4(Stop - 1), ExtractFileName(Dlg.FileName)]));
    except
      on E: Exception do MessageDlg('Could not save: ' + E.Message, mtError, [mbOK], 0);
    end;
  finally
    Outside.Free;
    Lines.Free;
    Dlg.Free;
  end;
end;

procedure TC64DebuggerWindow.FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  // Keys typed in a box (a value, the XOR) are the box's
  if ActiveControl is TEdit then Exit;
  // Escape closes the window, unless it ends the typing or the selection in the memory zone first
  if Key = VK_ESCAPE then
  begin
    if not ((ActiveControl = FMem) and FMem.CancelTyping) then Close;
    Key := 0;
    Exit;
  end;
  case Key of
    VK_F3:
      begin
        if ActiveControl = FMem then FMem.SearchNext else FDis.SearchNext;
        Key := 0;
      end;
    VK_F5: begin DoRun(Self); Key := 0; end;
    VK_F7: begin if ssShift in Shift then DoStepBack(Self) else DoStep(Self); Key := 0; end;
    VK_F8: begin DoToggleBp(Self); Key := 0; end;
    VK_F9: begin DoToCursor(Self); Key := 0; end;
    VK_F10: begin DoOver(Self); Key := 0; end;
    VK_F11: begin DoOut(Self); Key := 0; end;
    VK_G: if ssCtrl in Shift then begin DoGoto(Self); Key := 0; end;
  end;
end;

end.

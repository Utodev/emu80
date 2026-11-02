{ DebuggerForm: non-modal debugger window with three zones: disassembly with
  labels and breakpoints, registers/flags/stack, and a hex+ASCII memory view.

  The window works on a snapshot of memory and registers taken under the
  emulator lock (after every stop or step, and a few times per second while
  running), so painting never races the emulation thread.

  Everything drawn is recorded as a "spot" that knows what it shows: hex
  values show their decimal value on mouse over, and registers, memory,
  flags and interrupt state can be changed by clicking them. }
unit DebuggerForm;

{$mode objfpc}{$H+}
{$R-}{$Q-}

interface

uses
  Classes, SysUtils, Types, Math, Forms, Controls, Graphics, StdCtrls, ExtCtrls, Menus,
  LCLType, Dialogs, ComCtrls, Clipbrd, Emulator, Spectrum, Disasm, Z80Core, Symbols, Icons, Models,
  MemText, DivMMC, ZXUnoRegsForm, CartBrowser, AsmExport, DebugFiles, BreakExpr, DelayHint, Z80Help, Z80Opcodes;

type
  TDebuggerWindow = class;

  TSpotKind = (
    skInfo,       // read-only hex value
    skLabel,      // a label: Value is its address, the hint its full name
    skHint,       // text shown as a hint (not an address)
    skDoc,        // longer help, shown after the mouse rests on it a second
    skRegister,   // click to edit; Target = TRegId
    skMemWord,    // click to edit the 16-bit word at Target
    skMemByte,    // click to edit the byte at Target
    skMemXorByte, // as skMemByte, typed value is XORed with the data view key
    skAscii,      // click to type text at Target (data view)
    skFlag,       // click to toggle; Target = flag mask
    skIFF,        // click to toggle; Target = 1 or 2
    skIM,         // click to cycle 0, 1, 2
    skSlot3,      // click to choose the RAM bank at C000
    skCpcSlot,    // CPC: click to choose what a slot holds (Target = slot)
    skDivBank,    // click to choose the DivMMC RAM bank at 2000
    skDivConmem,  // click to toggle CONMEM
    skDivMapped,  // click to page the DivMMC in or out
    skUnoBoot,    // click to toggle the ZX-Uno's boot mode (MASTERCONF bit 0)
    skUnoMapper,  // click to choose MASTERMAPPER's SRAM page
    skNextMMU     // click to choose the page of an MMU register of the Next (Target = slot 0-7)
  );

  TRegId = (rAF, rHL, rDE, rBC, rAF_, rHL_, rDE_, rBC_, rIX, rIY, rI, rR, rSP, rPC,
    rBus,     // the data bus value an interrupt reads (IM 2 vector's low byte)
    rIm2);    // the IM 2 vector: I (MSB) and the data bus (LSB)

  TSpot = record
    R: TRect;
    Kind: TSpotKind;
    Value: Integer;
    Digits: Integer;
    Target: Integer;
    Text: string;
  end;

  { Base for the debugger's custom-drawn zones }
  TDebugView = class(TCustomControl)
  protected
    FOwnerWin: TDebuggerWindow;
    FLineH, FCharW: Integer;
    FSpots: array of TSpot;
    FSpotCount: Integer;
    FHintSpot: Integer;
    FBoldFont: TFont;
    FEditor: TEdit;
    FEditSpot: TSpot;
    FGotoMenu: TPopupMenu;        // for views without a menu of their own
    FGotoAddr: Word;
    procedure MeasureFont;
    function VisibleLines: Integer;
    procedure ClearSpots;
    procedure AddSpot(X, Y, Chars: Integer; Kind: TSpotKind; Value: Integer; Digits: Integer = 0;
      Target: Integer = 0; const AText: string = '');
    { Draw text and return the X after it }
    function DrawText(X, Y: Integer; const S: string; AColor: TColor; Bold: Boolean): Integer;
    function SpotAt(X, Y: Integer): Integer;
    { Handle a click on a spot (edit or toggle). True if it was handled. }
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
    { Right-click on a number or a label: "Go to X" and "View data at X" at
      the top of Menu. False (and the items hidden) if there is none. }
    function PrepareGoto(Menu: TPopupMenu; X, Y: Integer): Boolean;
    procedure GotoClick(Sender: TObject);
    procedure ViewDataClick(Sender: TObject);
    { The view has a context menu of its own (it calls PrepareGoto) }
    function HasOwnMenu: Boolean; virtual;
  public
    constructor CreateView(AOwner: TDebuggerWindow);
    destructor Destroy; override;
    function Editing: Boolean;
  end;

  { A breakpoint in the list: on a memory address or on a port }
  TBreakEntry = record
    Addr: Word;
    Last: Word;       // end of its range (Addr if it is a single address)
    Port: Boolean;
    Hits: Integer;    // times reached, if the condition uses T (else -1)
  end;

  TDisasmLine = record
    Addr: Word;
    Len: Integer;
  end;

  TDisasmView = class(TDebugView)
  private
    FTop: Word;
    FSel: Word;
    FLines: array of TDisasmLine;
    FMenuAddr: Word;
    FPopup: TPopupMenu;
    FTypeItems: array[0..3] of TMenuItem;   // execution, read, write, read/write
    FEnabledItem, FRemoveItem, FConditionItem, FLabelItem: TMenuItem;
    FBack: array of LongWord;   // where the view was before each jump: top shl 16 or selection
    FSearch: string;            // the text searched last
    FPlaced: Boolean;           // a first address has been shown
    procedure Layout;
    function LineAt(Y: Integer): Integer;
    function PrevAddr(Addr: Word): Word;
    { The top that shows FFFF on the last line }
    function EndTop: Word;
    { The view doesn't go past FFFF: no top beyond EndTop }
    procedure ClampTop;
    { Remember the view before a jump, for Backspace }
    procedure PushBack;
    procedure JumpTo(ATop, ASel: Word);
    { A line as the view shows it: address, bytes, label and instruction }
    function LineText(Addr: Word; out Len: Integer): string;
    procedure MenuClick(Sender: TObject);
    procedure DrawCheck(X, Y: Integer; Ok: Boolean);
    procedure DrawArrow(X, Y: Integer);
    function DrawInstruction(X, Y: Integer; Addr: Word; OnBreak: Boolean; OnPC: Boolean = False): Integer;
  protected
    function HasOwnMenu: Boolean; override;
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DblClick; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor CreateView(AOwner: TDebuggerWindow);
    procedure GoToAddr(Addr: Word);
    { Scroll so Addr is visible, keeping the view if it already is. }
    procedure EnsureVisible(Addr: Word);
    property SelAddr: Word read FSel write FSel;
    { Ask for a text and find it; F3 finds the next one }
    procedure Search;
    procedure SearchNext;
  end;

  THexView = class(TDebugView)
  private
    FTop: Word;
    FXor: Byte;
    FTextCursor: Integer;   // address being typed in the ASCII column, -1 if none
    FMenu: TPopupMenu;
    FWatchItem, FSpriteItem: TMenuItem;
    FMenuAddr: Integer;     // byte under the mouse on right-click, -1 if none
    FSprites: Boolean;      // show the bytes as 8x8 sprites
    FSpriteRowBytes, FSpriteRows: Integer;   // sprite layout of the last paint
    FSelA, FSelB: Integer;  // text column selection: anchor and end (-1 = none)
    FDragging: Boolean;
    FSearchText: string;    // the search: text, or hex bytes
    FSearchHex, FSearchCase: Boolean;
    FReadItem, FWriteItem, FCopyTextItem, FCopyItem, FPasteItem: TMenuItem;
    procedure SetXor(Value: Byte);
    function HasSel: Boolean;
    function SelFirst: Word;
    function SelLast: Word;
    { The range a data breakpoint from the menu covers: the selection if the
      byte is in it, else the byte }
    procedure BreakRange(out First, Last: Word);
    procedure MenuReadBreak(Sender: TObject);
    procedure MenuWriteBreak(Sender: TObject);
    procedure MenuCopy(Sender: TObject);
    procedure MenuCopyText(Sender: TObject);
    { The selection, else the byte right-clicked; False if neither }
    function CopyRange(out First, Last: Integer): Boolean;
    procedure MenuPaste(Sender: TObject);
    procedure PasteAt(Addr: Word);
    procedure MenuSearch(Sender: TObject);
    procedure MenuGoTo(Sender: TObject);
    procedure MenuWatch(Sender: TObject);
    procedure MenuSprites(Sender: TObject);
    procedure MenuExport(Sender: TObject);
    procedure MenuImport(Sender: TObject);
    procedure MenuImportBinary(Sender: TObject);
    procedure MenuExportBinary(Sender: TObject);
    procedure PaintSprites;
    function RowBytes: Integer;
    function Rows: Integer;
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
    constructor CreateView(AOwner: TDebuggerWindow);
    procedure GoToAddr(Addr: Word);
    { Escape: drop the typing position or the selection; False if there
      was neither (Escape then closes the window) }
    function CancelTyping: Boolean;
    { Ask for text or hex bytes and find them (selected); F3: the next }
    procedure Search;
    procedure SearchNext;
    { Bytes on screen, from TopAddr }
    function VisibleBytes: Integer;
    property TopAddr: Word read FTop;
    property XorValue: Byte read FXor write SetXor;
  end;

  { Watches: address, the two bytes there (editable) and its label }
  TWatchView = class(TDebugView)
  private
    FSel: Integer;
    FMenu: TPopupMenu;
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
    constructor CreateView(AOwner: TDebuggerWindow);
  end;

  { Breakpoints: on/off box, type, address, label and condition }
  TBreakView = class(TDebugView)
  private
    FSel: Integer;
    FMenu: TPopupMenu;
    FEnabledItem: TMenuItem;
    function HaveSel: Boolean;
    function SelEntry: TBreakEntry;
    procedure MenuAdd(Sender: TObject);
    procedure MenuEdit(Sender: TObject);
    procedure MenuEnable(Sender: TObject);
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
    constructor CreateView(AOwner: TDebuggerWindow);
  end;

  { Registers, flags, interrupt state and stack }
  TRegView = class(TDebugView)
  private
    FStackOfs, FPortOfs: Integer;   // entries scrolled with the wheel
    FStackBox, FPortBox: TRect;
    FStep: LongWord;                // step shown: a new one scrolls back to the top
  protected
    procedure Paint; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  end;

  TRegSnapshot = record
    A, F, A_, F_, I, R, IM, DataBus: Byte;
    BC, DE, HL, BC_, DE_, HL_, IX, IY, SP, PC: Word;
    IFF1, IFF2, Halted: Boolean;
  end;

  TDebuggerWindow = class(TForm)
  private
    FEmu: TEmulator;
    FMem: array[0..$FFFF] of Byte;
    FBreak: array[0..$FFFF] of Byte;
    FRegs: TRegSnapshot;
    FPrev: TRegSnapshot;      // registers before the last instruction
    FHavePrev: Boolean;
    FPrevPaging: TPagingState;  // paging before the last instruction
    FStep: LongWord;            // the emulator's step count
    FWatchSplit: TSplitter;
    FWatchShare: Double;        // the watches' part of what memory leaves (splitter)
    FRomIndex: Integer;       // ROM paged at 0000-3FFF (-1 = RAM)
    FWasPaused: Boolean;
    FHistory: TStringList;
    FWatchHistory: TStringList;   // the addresses watched, apart from those gone to
    FCondText: array of string;     // breakpoint conditions, by address
    FPortLog: array of TPortAccess; // newest first
    FSlots: array[0..3] of Integer; // what is paged in each 16K slot
    FSlot3OK: Boolean;              // slot 3 can be changed (128K paging)
    FIsCpc: Boolean;                // Amstrad CPC: every slot can be changed, as the CPC allows
    FCpcSlot: Integer;              // the slot whose menu is open
    FDivActive: Boolean;            // the DivMMC is paged in at 0000-3FFF
    FCurrahPaged: Boolean;          // the Currah µSpeech's ROM is paged in
    FDivOn: Boolean;                // the DivMMC is connected
    FDivControl: Byte;              // its control register (port E3)
    FDivMapped: Boolean;            // paged in by the automatic paging
    FUnoOn: Boolean;                // the machine is a ZX-Uno
    FNextOn: Boolean;               // the machine is a ZX Spectrum Next
    FNextMMU: array[0..7] of Byte;  // its MMU registers (8K page of each slot, 255 = ROM)
    FUnoConf, FUnoMapper: Byte;     // its MASTERCONF and MASTERMAPPER
    FUnoButton: TToolButton;        // ZX-Uno registers (shown on a ZX-Uno)
    FCartButton: TToolButton;       // the cartridge browser (shown on an MSX)
    FUnoRegs: TZXUnoRegsWindow;
    FMapperMenu: TPopupMenu;
    FDivMenu: TPopupMenu;
    FSlotMenu: TPopupMenu;
    FCpcMenu: TPopupMenu;           // CPC: what a slot can hold
    FNextMenu: TPopupMenu;          // Next: the pages an MMU register can take
    FNextSlot: Integer;             // the MMU register whose menu is open
    FWatches: array of Word;
    FWatchView: TDebugView;
    FBreakView: TDebugView;
    FBreakList: array of TBreakEntry;   // memory breakpoints, then port ones
    FPortBreak: array[0..$FFFF] of Byte;
    FPortCondText: array of string;
    FNotice: string;                // message shown in the status bar for a while
    FNoticeTime: QWord;
    FImages: TImageList;
    FToolbar: TToolBar;
    FRunButton, FBreakButton: TToolButton;
    FStatusBar: TStatusBar;
    FDisasm: TDisasmView;
    FRegView: TRegView;
    FDataPanel: TPanel;
    FMemZone, FBreakZone, FWatchZone, FRegZone: TPanel;
    FLaidOut: Boolean;
    FRegMinH: Integer;      // height the registers zone needs (it can't shrink)
    FXorEdit: TEdit;
    FHex: THexView;
    FTimer: TTimer;
    procedure WatchSplitMoved(Sender: TObject);
    function DataRest: Integer;
    function AddButton(AIcon: TIconKind; const AHint: string; AHandler: TNotifyEvent): TToolButton;
    procedure AddSeparator;
    procedure SetStatus(const AText: string);
    procedure DoToggleBreakpoint(Sender: TObject);
    procedure DoClearBreakpoints(Sender: TObject);
    procedure DoGoTo(Sender: TObject);
    procedure DoAddWatch(Sender: TObject);
    procedure RegsChanged(Sender: TObject);
    procedure DoUnoRegs(Sender: TObject);
    procedure DoCartBrowser(Sender: TObject);
    procedure DoZ80Opcodes(Sender: TObject);
    function MakeColumn(AParent: TWinControl; const ACaption: string; AWidth: Integer;
      AAlign: TAlign): TPanel;
    procedure FormResize(Sender: TObject);
    procedure UpdateRunButtons;
    procedure FitLayout;
    procedure FitToScreen;
    procedure FormShow(Sender: TObject);
    procedure TakeSnapshot;
    procedure Tick(Sender: TObject);
    procedure XorChange(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FocusMainWindow(Data: PtrInt);
    procedure DoRun(Sender: TObject);
    procedure DoBreak(Sender: TObject);
    procedure DoStepInto(Sender: TObject);
    procedure DoStepOver(Sender: TObject);
    procedure DoRunToCursor(Sender: TObject);
    procedure DoStepBack(Sender: TObject);
    procedure DoStepOut(Sender: TObject);
    procedure DoLoadSymbols(Sender: TObject);
    procedure DoCondition(Sender: TObject);
    procedure EnsurePaused;
  public
    constructor CreateFor(AOwner: TComponent; AEmu: TEmulator);
    destructor Destroy; override;
    procedure Refresh(FollowPC: Boolean);
    function Peek(Addr: Word): Byte;
    function BreakFlags(Addr: Word): Byte;
    procedure SetBreak(Addr: Word; Flags: Byte);
    function ConditionText(Addr: Word): string;
    { Breakpoint list for the breakpoints view }
    function BreakCount: Integer;
    function BreakAt(Index: Integer): TBreakEntry;
    function EntryFlags(const E: TBreakEntry): Byte;
    function EntryCondition(const E: TBreakEntry): string;
    procedure RemoveEntry(const E: TBreakEntry);
    { Add (OldAddr < 0) or change a breakpoint with a dialog }
    procedure EditBreakpoint(OldAddr: Integer; OldPort: Boolean = False);
    procedure ToggleBreakEnabled(Addr: Word; Port: Boolean = False);
    procedure ClearBreakpoints;
    { Breakpoints and watches to and from JSON files (DebugFiles); loading
      replaces them }
    procedure SaveBreaksAs;
    procedure LoadBreaksAsk;
    procedure SaveWatchesAs;
    procedure LoadWatchesAsk;
    procedure SetWatches(const Watches: TWordArray);
    procedure ShowNotice(const AText: string);
    { Memory to and from a text file of "$XX" values (16 per line) }
    procedure ExportMemory;
    { The disassembly of a range as a .asm file for sjasmplus }
    procedure ExportAssembler(Start: Word);
    function AsmLabel(Addr: Word; Kind: TOperandKind): string;
    procedure ImportMemory;
    { A file loaded as it is at an address (asked; the memory zone's by
      default) }
    procedure ImportBinary;
    { A range (asked; what the memory zone shows by default) saved as it is }
    procedure ExportBinary;
    { A menu item's hint in the status bar while the mouse is over it }
    procedure AppHint(Sender: TObject);
    function AskRange(const ACaption: string; var Addr: Word; var Len: Integer): Boolean;
    procedure GoToCode(Addr: Word);
    { Name the address (a user symbol, kept when exporting as assembler);
      an empty name removes it }
    procedure EditLabel(Addr: Word);
    { Ask for the condition of the breakpoint at Addr (adding one if needed) }
    procedure EditCondition(Addr: Word);
    function PortLogCount: Integer;
    function PortLogEntry(Index: Integer): TPortAccess;
    function SlotBank(Slot: Integer): Integer;
    function Slot3Changeable: Boolean;
    function CpcSlotChangeable: Boolean;
    function DivActive: Boolean;
    function CurrahPaged: Boolean;
    function DivOn: Boolean;
    function DivControl: Byte;
    function DivMappedNow: Boolean;
    function UnoOn: Boolean;
    function NextOn: Boolean;
    function NextMMU(Slot: Integer): Byte;
    procedure SetNextMMU(Slot, Value: Integer);
    procedure ChooseNextMMU(Slot: Integer);
    procedure NextMMUClick(Sender: TObject);
    function UnoConf: Byte;
    function UnoMapper: Byte;
    procedure ToggleUnoBoot;
    procedure ChooseUnoMapper;
    procedure UnoMapperClick(Sender: TObject);
    procedure ChooseDivBank;
    procedure DivBankClick(Sender: TObject);
    procedure ChangeDivControl(Mask: Byte);
    procedure ToggleDivMapped;
    procedure ChooseSlot3;
    procedure Slot3Click(Sender: TObject);
    procedure ChooseCpcSlot(Slot: Integer);
    procedure CpcSlotClick(Sender: TObject);
    { Watches: addresses whose two bytes are shown in the watch zone }
    procedure AddWatch;
    procedure AddWatchAt(Addr: Word);
    procedure RemoveWatch(Index: Integer);
    function WatchCount: Integer;
    function Watch(Index: Integer): Word;
    { Label for an address: user symbols first, then those of the ROM that is
      paged in (or RAM labels such as system variables). }
    function SymbolFor(Addr: Word): string;
    { Every label at Addr (user ones, then the ROM's), ', ' separated }
    function SymbolsFor(Addr: Word): string;
    { Changes made by hand from the register or memory views }
    procedure SetRegister(Reg: TRegId; Value: Word);
    { The disassembly's menu: run to that line (as F9), or put the PC there }
    procedure RunToAddr(Addr: Word);
    procedure SetPCAt(Addr: Word);
    procedure PokeByte(Addr: Word; Value: Byte);
    procedure ToggleFlag(Mask: Byte);
    procedure ToggleIFF(Which: Integer);
    procedure CycleIM;
    { Ask for an address (typed or from the last ones used). False if cancelled. }
    function AskAddress(var Addr: Word; ForWatch: Boolean = False): Boolean;
    { Called when a breakpoint stops the emulation. }
    procedure BreakHit;
    { After a stop: show the instruction that caused a memory or port
      breakpoint, and say why a port breakpoint stopped }
    procedure ReportBreak;
    property Regs: TRegSnapshot read FRegs;
    property Prev: TRegSnapshot read FPrev;
    property HavePrev: Boolean read FHavePrev;
    property PrevPaging: TPagingState read FPrevPaging;
    property Step: LongWord read FStep;
    { A paging change made by hand is not shown as changed by an instruction }
    procedure PagingChangedByHand;
    { Toggle Bit (BP_READ or BP_WRITE) of the memory breakpoint at Addr, or
      add one over First-Last }
    procedure ToggleDataBreak(Addr, First, Last: Word; Bit: Byte);
    { Write bytes from Addr (up to FFFF), skipping ROM unless writable }
    procedure WriteBytes(Addr: Word; const Values: TBytes);
    property Hex: THexView read FHex;
  end;

var
  DebuggerWindow: TDebuggerWindow;
  { Debug > Load symbols of the main window, for the toolbar's button }
  DebugLoadSymbols: TNotifyEvent;
  { Watches from the command line, for when the debugger is opened }
  PendingWatches: TWordArray;

{ Open (or bring to front) the debugger, stopping at the current address. }
procedure ShowDebugger(Emu: TEmulator);

implementation

uses
  ModernUI;

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
  MAX_HISTORY = 10;
  GUTTER_W = 40;      // breakpoint type, "?" if conditional, execution arrow
  MAX_LABEL = 20;     // longer labels are cut, with the full name as a hint
  HEX_BYTES = 16;     // bytes per row in the data view
  STACK_ENTRIES = 8;   // also the port accesses shown
  STACK_HISTORY = 50;  // stack entries the wheel reaches (the port log keeps as many)

  REGISTER_NAMES: array[0..21] of string = (
    'A', 'B', 'C', 'D', 'E', 'H', 'L', 'I', 'R', 'F', 'AF', 'AF''', 'BC', 'DE', 'HL', 'SP',
    'IX', 'IY', 'IXH', 'IXL', 'IYH', 'IYL');

  MENU_CONDITION = 100;
  MENU_GOTO = 101;
  MENU_TOGGLE = 102;
  MENU_ENABLE = 103;
  MENU_PORT = 104;
  MENU_EXPORTASM = 105;
  MENU_SEARCH = 106;
  MENU_LABEL = 107;
  MENU_RUNTO = 108;
  MENU_SETPC = 109;

  CLICKABLE = [skRegister, skMemWord, skMemByte, skMemXorByte, skAscii, skFlag, skIFF, skIM,
    skSlot3, skCpcSlot, skDivBank, skDivConmem, skDivMapped, skUnoBoot, skUnoMapper,
    skNextMMU];

type
  { Breakpoint window: the end address follows the start until it is
    changed by hand }
  TEndFollower = class
    StartEdit, EndEdit: TEdit;
    Own: Boolean;        // the end was typed: it no longer follows
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

function BreakColor: TColor;
begin
  Result := TC(RGBToColor(205, 40, 40));
end;

{ Breakpoint that is switched off }
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

function IsRegister(const S: string): Boolean;
var
  R: string;
begin
  for R in REGISTER_NAMES do
    if S = R then Exit(True);
  Result := False;
end;

{ Hex number with optional $, #, 0x prefix or h suffix }
function ParseHex(const Text: string; out Value: Integer): Boolean;
var
  S: string;
begin
  S := UpperCase(Trim(Text));
  if (S <> '') and ((S[1] = '$') or (S[1] = '#')) then Delete(S, 1, 1)
  else if Copy(S, 1, 2) = '0X' then Delete(S, 1, 2)
  else if (S <> '') and (S[Length(S)] = 'H') then Delete(S, Length(S), 1);
  Value := StrToIntDef('$' + S, -1);
  Result := (S <> '') and (Value >= 0);
end;

procedure ShowDebugger(Emu: TEmulator);
begin
  if DebuggerWindow = nil then
    DebuggerWindow := TDebuggerWindow.CreateFor(Application, Emu);
  // Remember registers before each instruction while the debugger is open
  Emu.Lock;
  try
    Emu.Spec.TrackPrevRegs := True;
  finally
    Emu.Unlock;
  end;
  // Stop where the emulation is and show that address
  Emu.PauseAndWait;
  DebuggerWindow.FWasPaused := True;
  DebuggerWindow.Show;
  DebuggerWindow.BringToFront;
  DebuggerWindow.Refresh(True);
  // Focus on the window and the execution line: F7 / F10 step at once
  DebuggerWindow.SetFocus;
  DebuggerWindow.FDisasm.SetFocus;
end;

{ TDebugView }

constructor TDebugView.CreateView(AOwner: TDebuggerWindow);
begin
  inherited Create(AOwner);
  FOwnerWin := AOwner;
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

destructor TDebugView.Destroy;
begin
  FBoldFont.Free;
  inherited Destroy;
end;

procedure TDebugView.MeasureFont;
begin
  FBoldFont.Assign(Font);
  FBoldFont.Style := [fsBold];
  Canvas.Font := FBoldFont;
  // Bold is never narrower, so columns stay aligned in either style
  FCharW := Canvas.TextWidth('0');
  FLineH := Canvas.TextHeight('Xg') + 2;
  Canvas.Font := Font;
end;

function TDebugView.VisibleLines: Integer;
begin
  if FLineH = 0 then MeasureFont;
  Result := Max(1, ClientHeight div FLineH);
end;

procedure TDebugView.ClearSpots;
begin
  FSpotCount := 0;
end;

procedure TDebugView.AddSpot(X, Y, Chars: Integer; Kind: TSpotKind; Value: Integer;
  Digits: Integer; Target: Integer; const AText: string);
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

function TDebugView.DrawText(X, Y: Integer; const S: string; AColor: TColor; Bold: Boolean): Integer;
begin
  if Bold then Canvas.Font := FBoldFont else Canvas.Font := Font;
  Canvas.Font.Color := AColor;
  Canvas.Brush.Style := bsClear;
  Canvas.TextOut(X, Y, S);
  Result := X + Length(S) * FCharW;
  Canvas.Font := Font;
end;

function TDebugView.SpotAt(X, Y: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to FSpotCount - 1 do
    if PtInRect(FSpots[I].R, Point(X, Y)) then Exit(I);
  Result := -1;
end;

function TDebugView.Editing: Boolean;
begin
  Result := (FEditor <> nil) and FEditor.Visible;
end;

function TDebugView.ClickSpot(Index: Integer): Boolean;
var
  Spot: TSpot;
begin
  Result := True;
  Spot := FSpots[Index];
  case Spot.Kind of
    skRegister, skMemWord, skMemByte, skMemXorByte: BeginEdit(Spot);
    skNextMMU: FOwnerWin.ChooseNextMMU(Spot.Target);
    skFlag: FOwnerWin.ToggleFlag(Spot.Target);
    skIFF: FOwnerWin.ToggleIFF(Spot.Target);
    skIM: FOwnerWin.CycleIM;
    skSlot3: FOwnerWin.ChooseSlot3;
    skCpcSlot: FOwnerWin.ChooseCpcSlot(Spot.Target);
    skDivBank: FOwnerWin.ChooseDivBank;
    skDivConmem: FOwnerWin.ChangeDivControl($80);
    skDivMapped: FOwnerWin.ToggleDivMapped;
    skUnoBoot: FOwnerWin.ToggleUnoBoot;
    skUnoMapper: FOwnerWin.ChooseUnoMapper;
  else
    Result := False;
  end;
end;

{ Inline editor over a value: Enter applies, Escape or leaving cancels }
procedure TDebugView.BeginEdit(const Spot: TSpot);
begin
  if FEditor = nil then
  begin
    FEditor := TEdit.Create(Self);
    FEditor.Parent := Self;
    FEditor.Font := Font;
    FEditor.OnKeyDown := @EditorKeyDown;
    FEditor.OnExit := @EditorExit;
    // Its colours are set here, for the theme in use
    FEditor.Tag := THEME_OWN_COLOURS;
  end;
  // Black ink on white, in both themes
  FEditor.Color := clWhite;
  FEditor.Font.Color := clBlack;
  FEditSpot := Spot;
  FEditor.SetBounds(Spot.R.Left - 3, Spot.R.Top - 2, (Spot.Digits + 2) * FCharW + 6,
    Spot.R.Bottom - Spot.R.Top + 6);
  FEditor.MaxLength := Spot.Digits + 1;
  FEditor.Text := IntToHex(Spot.Value, Spot.Digits);
  FEditor.Visible := True;
  FEditor.SetFocus;
  FEditor.SelectAll;
end;

procedure TDebugView.EditorKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_RETURN: begin EndEdit(True); Key := 0; end;
    VK_ESCAPE: begin EndEdit(False); Key := 0; end;
  end;
end;

procedure TDebugView.EditorExit(Sender: TObject);
begin
  EndEdit(False);
end;

procedure TDebugView.EndEdit(Commit: Boolean);
var
  V, Limit: Integer;
begin
  if not Editing then Exit;
  FEditor.Visible := False;
  if Commit then
  begin
    if FEditSpot.Digits <= 2 then Limit := $FF else Limit := $FFFF;
    if not ParseHex(FEditor.Text, V) or (V > Limit) then
    begin
      Beep;
      Exit;
    end;
    case FEditSpot.Kind of
      skRegister: FOwnerWin.SetRegister(TRegId(FEditSpot.Target), V);
      skMemWord:
        begin
          FOwnerWin.PokeByte(FEditSpot.Target, V and $FF);
          FOwnerWin.PokeByte(Word(FEditSpot.Target + 1), V shr 8);
        end;
      skMemByte: FOwnerWin.PokeByte(FEditSpot.Target, V);
      // Typed in the decoded view: store it encoded with the XOR key
      skMemXorByte: FOwnerWin.PokeByte(FEditSpot.Target, V xor FOwnerWin.Hex.XorValue);
    end;
    FOwnerWin.Refresh(False);
  end;
  if CanFocus then SetFocus;
end;

const
  GOTO_TAG = 900;
  GOTO_ITEMS = 3;     // Go to, View data at and a separator, first in a menu

function TDebugView.HasOwnMenu: Boolean;
begin
  Result := False;
end;

function TDebugView.PrepareGoto(Menu: TPopupMenu; X, Y: Integer): Boolean;
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
  Result := (Spot >= 0) and (FSpots[Spot].Kind in [skInfo, skLabel, skRegister, skMemWord,
    skMemByte, skMemXorByte]);
  if Result then
  begin
    FGotoAddr := Word(FSpots[Spot].Value);
    // As it is shown: the label, or the number
    if FSpots[Spot].Kind = skLabel then What := FSpots[Spot].Text
    else if FSpots[Spot].Digits = 2 then What := IntToHex(FSpots[Spot].Value, 2)
    else What := IntToHex(FGotoAddr, 4);
    Menu.Items[0].Caption := 'Go to ' + What;
    Menu.Items[1].Caption := 'View data at ' + What;
  end;
  for I := 0 to 2 do Menu.Items[I].Visible := Result;
  // Nothing else in the menu: the separator isn't needed either
  if Menu.Items.Count = 3 then Menu.Items[2].Visible := False;
end;

procedure TDebugView.GotoClick(Sender: TObject);
begin
  FOwnerWin.GoToCode(FGotoAddr);
end;

procedure TDebugView.ViewDataClick(Sender: TObject);
begin
  FOwnerWin.Hex.GoToAddr(FGotoAddr);
end;

procedure TDebugView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
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

procedure TDebugView.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Spot: Integer;
  Labels: string;
begin
  inherited MouseMove(Shift, X, Y);
  Spot := SpotAt(X, Y);
  if (Spot >= 0) and (FSpots[Spot].Kind in CLICKABLE) then
    Cursor := crHandPoint
  else
    Cursor := crDefault;
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
  // Full label name, or the decimal value of the hex number under the mouse
  if FSpots[Spot].Kind in [skLabel, skHint] then
    Hint := FSpots[Spot].Text
  else
  begin
    Hint := IntToStr(FSpots[Spot].Value);
    // A 16-bit number: the labels with that value, if any
    if (FSpots[Spot].Kind in [skInfo, skRegister, skMemWord]) and
       ((FSpots[Spot].Digits >= 4) or ((FSpots[Spot].Kind = skInfo) and (FSpots[Spot].Digits = 0))) and
       (FSpots[Spot].Value >= 0) and (FSpots[Spot].Value <= $FFFF) then
    begin
      Labels := FOwnerWin.SymbolsFor(Word(FSpots[Spot].Value));
      if Labels <> '' then Hint := Hint + ' - ' + Labels;
    end;
  end;
  if Hint <> '' then Application.ActivateHint(Mouse.CursorPos);
end;

procedure TDebugView.MouseLeave;
begin
  inherited MouseLeave;
  DelayedHint.Cancel;
  FHintSpot := -1;
  Hint := '';
  Application.CancelHint;
end;

procedure TDebugView.DoEnter;
begin
  inherited DoEnter;
  Invalidate;
end;

procedure TDebugView.DoExit;
begin
  inherited DoExit;
  Invalidate;
end;

procedure TDebugView.DrawFocus;
begin
  if not Focused then Exit;
  Canvas.Pen.Color := TC(clHighlight);
  Canvas.Brush.Style := bsClear;
  Canvas.Rectangle(ClientRect);
  Canvas.Brush.Style := bsSolid;
end;

{ TDisasmView }

function TDisasmView.HasOwnMenu: Boolean;
begin
  Result := True;
end;

constructor TDisasmView.CreateView(AOwner: TDebuggerWindow);

  function AddItem(const ACaption: string; ATag: Integer): TMenuItem;
  begin
    Result := TMenuItem.Create(FPopup);
    Result.Caption := ACaption;
    Result.Tag := ATag;
    Result.OnClick := @MenuClick;
    FPopup.Items.Add(Result);
  end;

begin
  inherited CreateView(AOwner);
  FPopup := TPopupMenu.Create(Self);
  AddItem('Go to address...  (Ctrl+G)', MENU_GOTO);
  AddItem('Search...  (Ctrl+F, F3: next)', MENU_SEARCH);
  AddItem('Export as assembler (.asm)...', MENU_EXPORTASM);
  FLabelItem := AddItem('Add label...', MENU_LABEL);
  AddItem('-', -1);
  AddItem('Run to here  (F9)', MENU_RUNTO);
  AddItem('Set PC here', MENU_SETPC);
  AddItem('-', -1);
  AddItem('Toggle breakpoint  (Space, F8)', MENU_TOGGLE);
  FTypeItems[0] := AddItem('Execution breakpoint', BP_EXEC);
  FTypeItems[1] := AddItem('Read breakpoint', BP_READ);
  FTypeItems[2] := AddItem('Write breakpoint', BP_WRITE);
  FTypeItems[3] := AddItem('Read/write breakpoint (any access)', BP_READ or BP_WRITE);
  AddItem('Port breakpoint...', MENU_PORT);
  FConditionItem := AddItem('Breakpoint with condition...', MENU_CONDITION);
  FEnabledItem := AddItem('Enabled', MENU_ENABLE);
  AddItem('-', -1);
  FRemoveItem := AddItem('Remove breakpoint', 0);
end;

procedure TDisasmView.Layout;
var
  I, N, Len, A: Integer;
begin
  N := VisibleLines;
  SetLength(FLines, N);
  A := FTop;
  I := 0;
  // Up to the instruction that holds FFFF (it may take its operands from
  // 0000), never round to 0000
  while (I < N) and (A <= $FFFF) do
  begin
    Disassemble(A, @FOwnerWin.Peek, Len);
    FLines[I].Addr := A;
    FLines[I].Len := Len;
    Inc(A, Len);
    Inc(I);
  end;
  SetLength(FLines, I);
end;

function TDisasmView.LineAt(Y: Integer): Integer;
begin
  if FLineH = 0 then MeasureFont;
  Result := Y div FLineH;
  if (Result < 0) or (Result > High(FLines)) then Result := -1;
end;

{ Find the start of the instruction before Addr (variable-length code makes
  this a guess: prefer the longest instruction that ends exactly at Addr). }
function TDisasmView.PrevAddr(Addr: Word): Word;
var
  Back, Len: Integer;
begin
  if Addr = 0 then Exit(0);   // nothing before 0000
  for Back := Min(4, Addr) downto 1 do
  begin
    Disassemble(Word(Addr - Back), @FOwnerWin.Peek, Len);
    if Len = Back then Exit(Word(Addr - Back));
  end;
  Result := Word(Addr - 1);
end;

function TDisasmView.EndTop: Word;
var
  Back, Len, I: Integer;
begin
  // The instruction that ends at FFFF (or, failing that, FFFF itself)
  Result := $FFFF;
  for Back := 4 downto 1 do
  begin
    Disassemble(Word($10000 - Back), @FOwnerWin.Peek, Len);
    if Len = Back then
    begin
      Result := Word($10000 - Back);
      Break;
    end;
  end;
  for I := 2 to VisibleLines do Result := PrevAddr(Result);
end;

procedure TDisasmView.ClampTop;
var
  Last: Word;
begin
  Last := EndTop;
  if FTop > Last then FTop := Last;
  Layout;
end;

procedure TDisasmView.PushBack;
const
  MAX_BACK = 50;
var
  V: LongWord;
begin
  V := (LongWord(FTop) shl 16) or FSel;
  if (Length(FBack) > 0) and (FBack[High(FBack)] = V) then Exit;
  if Length(FBack) >= MAX_BACK then Delete(FBack, 0, 1);
  SetLength(FBack, Length(FBack) + 1);
  FBack[High(FBack)] := V;
end;

procedure TDisasmView.JumpTo(ATop, ASel: Word);
begin
  if FPlaced then PushBack;
  FPlaced := True;
  FTop := ATop;
  FSel := ASel;
  ClampTop;
  Invalidate;
end;

function TDisasmView.LineText(Addr: Word; out Len: Integer): string;
var
  Instr, Lbl: string;
  Operand, J: Integer;
  Kind: TOperandKind;
begin
  Instr := DisassembleEx(Addr, @FOwnerWin.Peek, Len, Operand, Kind);
  // Labels as DrawInstruction shows them
  if Operand >= 0 then
  begin
    if Kind = okImmediate then Lbl := UserSymbols.Lookup(Operand)
    else Lbl := FOwnerWin.SymbolFor(Operand);
    if Lbl <> '' then Instr := StringReplace(Instr, '$' + IntToHex(Operand, 4), Lbl, []);
  end;
  Result := FOwnerWin.SymbolFor(Addr) + ' ' + IntToHex(Addr, 4) + ' ';
  for J := 0 to Min(Len, 4) - 1 do Result := Result + IntToHex(FOwnerWin.Peek(Word(Addr + J)), 2) + ' ';
  Result := Result + Instr;
end;

procedure TDisasmView.Search;
var
  S: string;
begin
  S := FSearch;
  if not InputQuery('Search the disassembly', 'Text to find (addresses, bytes, labels, ' +
    'instructions; F3 finds the next one):', S) or (Trim(S) = '') then Exit;
  FSearch := Trim(S);
  SearchNext;
end;

{ From the instruction after the selected one, round the whole memory }
procedure TDisasmView.SearchNext;
var
  A, Len, Done: Integer;
  Want: string;
begin
  if FSearch = '' then
  begin
    Search;
    Exit;
  end;
  Want := UpperCase(FSearch);
  LineText(FSel, Len);
  A := FSel + Len;
  Done := Len;
  while Done <= $10000 do
  begin
    if A > $FFFF then A := 0;
    if Pos(Want, UpperCase(LineText(A, Len))) > 0 then
    begin
      GoToAddr(A);
      FOwnerWin.ShowNotice(Format('Found "%s" at %.4X (F3: next)', [FSearch, A]));
      Exit;
    end;
    Inc(A, Len);
    Inc(Done, Len);
  end;
  Beep;
  FOwnerWin.ShowNotice(Format('"%s" is not in the disassembly', [FSearch]));
end;

procedure TDisasmView.GoToAddr(Addr: Word);
begin
  JumpTo(Addr, Addr);
end;

procedure TDisasmView.EnsureVisible(Addr: Word);
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
  // Show a couple of lines of context above
  FTop := PrevAddr(PrevAddr(Addr));
  ClampTop;
  Invalidate;
end;

procedure TDisasmView.DrawCheck(X, Y: Integer; Ok: Boolean);
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

procedure TDisasmView.DrawArrow(X, Y: Integer);
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

{ Draw one instruction: mnemonic in blue, registers in bold, numbers and
  labels normal. A 16-bit operand with a label is shown by name, followed by
  its value in brackets in grey. Returns the X after the text. }
function TDisasmView.DrawInstruction(X, Y: Integer; Addr: Word; OnBreak: Boolean; OnPC: Boolean): Integer;
var
  Instr, Mnem, Tok, Lbl, Help, Undoc: string;
  Len, Operand, P, Start, V: Integer;
  Kind: TOperandKind;
  TextColor: TColor;
  FirstOperand, IsFlow: Boolean;
begin
  if OnBreak then TextColor := TC(clWhite) else TextColor := TC(clBlack);
  Instr := DisassembleEx(Addr, @FOwnerWin.Peek, Len, Operand, Kind);
  Help := InstructionHelp(Instr);
  if Help <> '' then Help := Help + LineEnding + 'T-States: ' + InstructionTStates(Addr, @FOwnerWin.Peek);
  // Undocumented: said in the hint, and the mnemonic in bold dark red
  Undoc := UndocumentedNote(Addr, @FOwnerWin.Peek);
  if Undoc <> '' then
  begin
    if Help = '' then Help := Instr;
    Help := Help + LineEnding + 'Undocumented: ' + Undoc;
  end;
  Lbl := '';
  if Operand >= 0 then
  begin
    // Plain immediate values only get user symbols: a ROM label for "LD BC,0"
    // would usually be a coincidence
    if Kind = okImmediate then
      Lbl := UserSymbols.Lookup(Operand)
    else
      Lbl := FOwnerWin.SymbolFor(Operand);
    if Lbl <> '' then
      Instr := StringReplace(Instr, '$' + IntToHex(Operand, 4), Lbl, []);
  end;

  P := Pos(' ', Instr);
  if P = 0 then P := Length(Instr) + 1;
  Mnem := Copy(Instr, 1, P - 1);
  // Over the mnemonic: what the instruction does
  if Help <> '' then AddSpot(X, Y - 1, Length(Mnem), skDoc, 0, 0, 0, Help);
  if IsZ80N(Addr, @FOwnerWin.Peek) then
  begin
    // The Next's Z80N instructions: bold teal (light cyan on a breakpoint's
    // red, and on the dark theme), apart from the blue, white and dark red
    // of the rest and readable on the green line and the pale red
    if OnBreak then X := DrawText(X, Y, Mnem, RGBToColor(150, 255, 255), True)
    else if DarkTheme then X := DrawText(X, Y, Mnem, RGBToColor(110, 235, 255), True)
    else X := DrawText(X, Y, Mnem, RGBToColor(0, 110, 130), True);
  end
  else if DarkTheme then
  begin
    // Dark: bold white (light red if undocumented), also on the green line
    // of the execution point and on a breakpoint's
    if OnBreak or OnPC then X := DrawText(X, Y, Mnem, clWhite, True)
    else if Undoc <> '' then X := DrawText(X, Y, Mnem, RGBToColor(255, 125, 125), True)
    else X := DrawText(X, Y, Mnem, clWhite, True);
  end
  else if Undoc = '' then X := DrawText(X, Y, Mnem, MnemonicColor(OnBreak), False)
  else if OnBreak then X := DrawText(X, Y, Mnem, RGBToColor(255, 225, 120), True)
  else X := DrawText(X, Y, Mnem, RGBToColor(150, 0, 0), True);
  IsFlow := (Mnem = 'JP') or (Mnem = 'JR') or (Mnem = 'CALL') or (Mnem = 'RET');
  FirstOperand := True;
  if P <= Length(Instr) then X := DrawText(X, Y, ' ', TextColor, False);
  Inc(P);
  while P <= Length(Instr) do
  begin
    if Instr[P] in [',', '(', ')', '+', '-'] then
    begin
      if Instr[P] = ',' then FirstOperand := False;
      X := DrawText(X, Y, Instr[P], TextColor, False);
      Inc(P);
      Continue;
    end;
    Start := P;
    while (P <= Length(Instr)) and not (Instr[P] in [',', '(', ')', '+', '-']) do Inc(P);
    Tok := Copy(Instr, Start, P - Start);
    if (Tok <> '') and (Tok[1] = '$') then
    begin
      V := StrToIntDef(Tok, 0);
      // 2 digits: a byte (no labels); more: an address
      if Length(Tok) <= 3 then AddSpot(X, Y - 1, Length(Tok), skInfo, V, 2)
      else AddSpot(X, Y - 1, Length(Tok), skInfo, V, 4);
      X := DrawText(X, Y, Tok, TextColor, False);
    end
    else if (Lbl <> '') and (Tok = Lbl) then
    begin
      AddSpot(X, Y - 1, Length(Tok), skLabel, Operand, 0, 0, Lbl);
      X := DrawText(X, Y, Tok, TextColor, False);
    end
    else if IsRegister(Tok) and not (IsFlow and FirstOperand and (Tok = 'C')) then
      X := DrawText(X, Y, Tok, TextColor, True)          // JP C: condition, not register
    else
      X := DrawText(X, Y, Tok, TextColor, False);
  end;

  if Lbl <> '' then
  begin
    // The value the label stands for, in grey
    Inc(X, FCharW * 2);
    if OnBreak then TextColor := TC(RGBToColor(255, 205, 205)) else TextColor := TC(RGBToColor(150, 150, 150));
    X := DrawText(X, Y, '[', TextColor, False);
    AddSpot(X, Y - 1, 4, skInfo, Operand);
    X := DrawText(X, Y, IntToHex(Operand, 4), TextColor, False);
    X := DrawText(X, Y, ']', TextColor, False);
  end;
  Result := X;
end;

procedure TDisasmView.Paint;
var
  I, J, Y, X, Len, LabelChars: Integer;
  L: TDisasmLine;
  Lbl: string;
  BP: Byte;
  IsPC, Active: Boolean;
  Cond: TCondition;
  Back, TextColor: TColor;
begin
  MeasureFont;
  Layout;
  ClearSpots;
  Canvas.Brush.Color := TC(clWhite);
  Canvas.FillRect(ClientRect);

  // Room for labels of up to MAX_LABEL characters
  LabelChars := MAX_LABEL + 1;

  for I := 0 to High(FLines) do
  begin
    L := FLines[I];
    Y := I * FLineH;
    BP := FOwnerWin.BreakFlags(L.Addr);
    IsPC := L.Addr = FOwnerWin.Regs.PC;
    // A breakpoint that is switched off keeps a pale background
    Active := (BP <> 0) and ((BP and BP_DISABLED) = 0);
    if Active then Back := BreakColor
    else if IsPC then Back := PCColor
    else if BP <> 0 then Back := DisabledColor
    else Back := TC(clWhite);
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := Back;
    Canvas.FillRect(0, Y, ClientWidth, Y + FLineH);
    if Active then TextColor := TC(clWhite) else TextColor := TC(clBlack);

    // Gutter: breakpoint type and execution arrow
    if (BP and BP_EXEC) <> 0 then DrawText(2, Y + 1, 'E', TextColor, True)
    else if (BP and (BP_READ or BP_WRITE)) = (BP_READ or BP_WRITE) then
      DrawText(2, Y + 1, 'A', TextColor, True)                  // any access
    else if (BP and BP_READ) <> 0 then DrawText(2, Y + 1, 'R', TextColor, True)
    else if (BP and BP_WRITE) <> 0 then DrawText(2, Y + 1, 'W', TextColor, True);
    // "?" after the type marks a conditional breakpoint
    if (BP <> 0) and (FOwnerWin.ConditionText(L.Addr) <> '') then
      DrawText(2 + FCharW, Y + 1, '?', TextColor, True);
    if IsPC then DrawArrow(FCharW * 2 + 4, Y + 2);

    // Label column
    Lbl := FOwnerWin.SymbolFor(L.Addr);
    if Lbl <> '' then
    begin
      AddSpot(GUTTER_W, Y, Min(Length(Lbl), MAX_LABEL), skLabel, L.Addr, 0, 0, Lbl);
      if Length(Lbl) > MAX_LABEL then Lbl := Copy(Lbl, 1, MAX_LABEL - 1) + '~';
      if Active then DrawText(GUTTER_W, Y + 1, Lbl, TC(clWhite), False)
      else DrawText(GUTTER_W, Y + 1, Lbl, TC(RGBToColor(0, 110, 110)), False);
    end;

    // Address, then the instruction bytes (click to edit)
    X := GUTTER_W + LabelChars * FCharW;
    AddSpot(X, Y, 4, skInfo, L.Addr);
    DrawText(X, Y + 1, IntToHex(L.Addr, 4), TextColor, False);
    Inc(X, FCharW * 6);
    Disassemble(L.Addr, @FOwnerWin.Peek, Len);
    for J := 0 to Min(Len, 4) - 1 do
    begin
      AddSpot(X + J * 3 * FCharW, Y, 2, skMemByte, FOwnerWin.Peek(Word(L.Addr + J)), 2,
        Word(L.Addr + J));
      DrawText(X + J * 3 * FCharW, Y + 1, IntToHex(FOwnerWin.Peek(Word(L.Addr + J)), 2),
        TextColor, False);
    end;
    Inc(X, FCharW * 13);
    X := DrawInstruction(X, Y + 1, L.Addr, Active, IsPC);

    // Where a conditional jump at the execution point will go
    if IsPC then
    begin
      Cond := ConditionAt(L.Addr, @FOwnerWin.Peek, FOwnerWin.Regs.F, Hi(FOwnerWin.Regs.BC));
      if Cond <> cdNone then
      begin
        DrawCheck(X + FCharW * 2, Y + 3, Cond = cdTaken);
        Inc(X, FCharW * 3);
      end;
    end;

    // Breakpoint condition
    if (BP <> 0) and (FOwnerWin.ConditionText(L.Addr) <> '') then
    begin
      if Active then TextColor := TC(RGBToColor(255, 240, 150)) else TextColor := TC(RGBToColor(140, 90, 0));
      DrawText(X + FCharW * 3, Y + 1, 'if ' + FOwnerWin.ConditionText(L.Addr), TextColor, False);
      AddSpot(0, Y, 3, skHint, 0, 0, 0, 'Condition: ' + FOwnerWin.ConditionText(L.Addr));
    end;

    if L.Addr = FSel then
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

procedure TDisasmView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  I: Integer;
  Flags: Byte;
  P: TPoint;
begin
  I := LineAt(Y);
  if I >= 0 then FSel := FLines[I].Addr;
  inherited MouseDown(Button, Shift, X, Y);   // may start editing a byte
  if I < 0 then Exit;
  Invalidate;
  if Button = mbRight then
  begin
    Flags := FOwnerWin.BreakFlags(FSel);
    FMenuAddr := FSel;
    FTypeItems[0].Checked := (Flags and BP_EXEC) <> 0;
    FTypeItems[1].Checked := (Flags and (BP_READ or BP_WRITE)) = BP_READ;
    FTypeItems[2].Checked := (Flags and (BP_READ or BP_WRITE)) = BP_WRITE;
    FTypeItems[3].Checked := (Flags and (BP_READ or BP_WRITE)) = (BP_READ or BP_WRITE);
    FEnabledItem.Enabled := Flags <> 0;
    FEnabledItem.Checked := (Flags <> 0) and ((Flags and BP_DISABLED) = 0);
    FRemoveItem.Enabled := Flags <> 0;
    if UserSymbols.Lookup(FMenuAddr) <> '' then
      FLabelItem.Caption := Format('Edit label at %.4X...', [FMenuAddr])
    else
      FLabelItem.Caption := Format('Add label at %.4X...', [FMenuAddr]);
    PrepareGoto(FPopup, X, Y);
    P := ClientToScreen(Point(X, Y));
    FPopup.PopUp(P.X, P.Y);
  end;
end;

procedure TDisasmView.MenuClick(Sender: TObject);
var
  ItemTag: Integer;
  A: Word;
begin
  ItemTag := (Sender as TMenuItem).Tag;
  case ItemTag of
    MENU_GOTO:
      begin
        A := FTop;
        if FOwnerWin.AskAddress(A) then GoToAddr(A);
      end;
    MENU_EXPORTASM: FOwnerWin.ExportAssembler(FTop);
    MENU_SEARCH: Search;
    MENU_LABEL: FOwnerWin.EditLabel(FMenuAddr);
    MENU_RUNTO: FOwnerWin.RunToAddr(FMenuAddr);
    MENU_SETPC: FOwnerWin.SetPCAt(FMenuAddr);
    MENU_TOGGLE:
      begin
        FSel := FMenuAddr;
        DblClick;
      end;
    MENU_CONDITION:
      // The same window as adding or editing in the breakpoints zone
      if FOwnerWin.BreakFlags(FMenuAddr) <> 0 then
        FOwnerWin.EditBreakpoint(FMenuAddr)
      else
      begin
        FSel := FMenuAddr;
        FOwnerWin.EditBreakpoint(-1);
      end;
    MENU_ENABLE: FOwnerWin.ToggleBreakEnabled(FMenuAddr);
    MENU_PORT: FOwnerWin.EditBreakpoint(-2);
  else
    // Changing the type keeps the condition and the on/off state; removing
    // drops it
    if ItemTag = 0 then
      FOwnerWin.SetBreak(FMenuAddr, 0)
    else
      FOwnerWin.SetBreak(FMenuAddr, ItemTag or (FOwnerWin.BreakFlags(FMenuAddr) and BP_DISABLED));
    FOwnerWin.Refresh(False);
  end;
  Invalidate;
end;

procedure TDisasmView.DblClick;
begin
  inherited DblClick;
  if Editing then Exit;   // double-click on a byte edits it
  if FOwnerWin.BreakFlags(FSel) <> 0 then
    FOwnerWin.SetBreak(FSel, 0)
  else
    FOwnerWin.SetBreak(FSel, BP_EXEC);
  FOwnerWin.Refresh(False);
end;

procedure TDisasmView.KeyDown(var Key: Word; Shift: TShiftState);
var
  I, Len: Integer;
  A: Word;
begin
  inherited KeyDown(Key, Shift);
  Layout;
  case Key of
    VK_G:
      if ssCtrl in Shift then
      begin
        A := FTop;
        if FOwnerWin.AskAddress(A) then GoToAddr(A);
        Key := 0;
      end;
    VK_F:
      if ssCtrl in Shift then
      begin
        Search;
        Key := 0;
      end;
    VK_DOWN:
      begin
        Disassemble(FSel, @FOwnerWin.Peek, Len);
        if FSel + Len <= $FFFF then
        begin
          FSel := FSel + Len;
          if (Length(FLines) > 1) and (FSel = FLines[High(FLines)].Addr) then FTop := FLines[1].Addr;
          ClampTop;
        end;
        Key := 0;
      end;
    VK_UP:
      begin
        if FSel = FTop then FTop := PrevAddr(FTop);
        FSel := PrevAddr(FSel);
        Key := 0;
      end;
    VK_NEXT:
      begin
        // Ctrl: 1024 bytes on, Shift: $1000 (4096); else a page
        if ssCtrl in Shift then FTop := Min($FFFF, FTop + 1024)
        else if ssShift in Shift then FTop := Min($FFFF, FTop + $1000)
        else if Length(FLines) > 0 then FTop := FLines[High(FLines)].Addr;
        FSel := FTop;
        ClampTop;
        Key := 0;
      end;
    VK_PRIOR:
      begin
        if ssCtrl in Shift then FTop := Max(0, FTop - 1024)
        else if ssShift in Shift then FTop := Max(0, FTop - $1000)
        else
          for I := 1 to VisibleLines - 1 do FTop := PrevAddr(FTop);
        FSel := FTop;
        Key := 0;
      end;
    VK_HOME:
      begin
        JumpTo(0, 0);
        Key := 0;
      end;
    VK_END:
      begin
        A := EndTop;
        JumpTo(A, A);
        if Length(FLines) > 0 then FSel := FLines[High(FLines)].Addr;   // the line with FFFF
        Key := 0;
      end;
    VK_BACK:
      begin
        // Back to where the view was before the last jump
        if Length(FBack) > 0 then
        begin
          FTop := FBack[High(FBack)] shr 16;
          FSel := FBack[High(FBack)] and $FFFF;
          SetLength(FBack, Length(FBack) - 1);
          ClampTop;
        end;
        Key := 0;
      end;
    VK_SPACE, VK_RETURN:
      begin
        DblClick;   // toggle breakpoint from the keyboard
        Key := 0;
      end;
  end;
  Invalidate;
end;

function TDisasmView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
var
  I, Len: Integer;
begin
  for I := 1 to 3 do
    if WheelDelta < 0 then
    begin
      Disassemble(FTop, @FOwnerWin.Peek, Len);
      if FTop + Len <= $FFFF then FTop := FTop + Len;
    end
    else
      FTop := PrevAddr(FTop);
  ClampTop;
  Invalidate;
  Result := True;
end;

{ THexView }

function THexView.HasOwnMenu: Boolean;
begin
  Result := True;
end;

constructor THexView.CreateView(AOwner: TDebuggerWindow);
var
  Item: TMenuItem;
begin
  inherited CreateView(AOwner);
  FTextCursor := -1;
  FMenuAddr := -1;
  FSelA := -1;
  FSelB := -1;
  FMenu := TPopupMenu.Create(Self);
  Item := TMenuItem.Create(FMenu);
  Item.Caption := 'Go to address...  (Ctrl+G)';
  Item.OnClick := @MenuGoTo;
  FMenu.Items.Add(Item);
  FWatchItem := TMenuItem.Create(FMenu);
  FWatchItem.Caption := 'Add a watch here';
  FWatchItem.OnClick := @MenuWatch;
  FMenu.Items.Add(FWatchItem);
  FReadItem := TMenuItem.Create(FMenu);
  FReadItem.OnClick := @MenuReadBreak;
  FReadItem.Hint := 'Stop before an instruction reads this byte (the selection, if the byte is in it)';
  FMenu.Items.Add(FReadItem);
  FWriteItem := TMenuItem.Create(FMenu);
  FWriteItem.OnClick := @MenuWriteBreak;
  FWriteItem.Hint := 'Stop before an instruction writes this byte (the selection, if the byte is in it)';
  FMenu.Items.Add(FWriteItem);
  FSpriteItem := TMenuItem.Create(FMenu);
  FSpriteItem.Caption := 'Sprite mode  (Space)';
  FSpriteItem.OnClick := @MenuSprites;
  FMenu.Items.Add(FSpriteItem);
  Item := TMenuItem.Create(FMenu);
  Item.Caption := '-';
  FMenu.Items.Add(Item);
  FCopyTextItem := TMenuItem.Create(FMenu);
  FCopyTextItem.Caption := 'Copy';
  FCopyTextItem.Hint := 'Copy the selected bytes as the text column shows them';
  FCopyTextItem.OnClick := @MenuCopyText;
  FMenu.Items.Add(FCopyTextItem);
  FCopyItem := TMenuItem.Create(FMenu);
  FCopyItem.Caption := 'Copy values  (Ctrl+C)';
  FCopyItem.Hint := 'Copy the selected bytes as hex values with a $ in front, separated by commas';
  FCopyItem.OnClick := @MenuCopy;
  FMenu.Items.Add(FCopyItem);
  FPasteItem := TMenuItem.Create(FMenu);
  FPasteItem.Caption := 'Paste  (Ctrl+V)';
  FPasteItem.Hint := 'Write the clipboard from this byte: values separated by commas (decimal, ' +
    'or $ for hex), or else its text';
  FPasteItem.OnClick := @MenuPaste;
  FMenu.Items.Add(FPasteItem);
  Item := TMenuItem.Create(FMenu);
  Item.Caption := 'Search...  (Ctrl+F, F3: next)';
  Item.Hint := 'Find text, or bytes in hex, as the zone shows them (with the XOR)';
  Item.OnClick := @MenuSearch;
  FMenu.Items.Add(Item);
  Item := TMenuItem.Create(FMenu);
  Item.Caption := '-';
  FMenu.Items.Add(Item);
  Item := TMenuItem.Create(FMenu);
  Item.Caption := 'Export text...';
  Item.Hint := 'Export to a comma separated text file, values in hex with a $ in front';
  Item.OnClick := @MenuExport;
  FMenu.Items.Add(Item);
  Item := TMenuItem.Create(FMenu);
  Item.Caption := 'Import text...';
  Item.Hint := 'Import from a comma separated text file, decimal values, or prepend $ for hex';
  Item.OnClick := @MenuImport;
  FMenu.Items.Add(Item);
  Item := TMenuItem.Create(FMenu);
  Item.Caption := 'Export binary...';
  Item.Hint := 'Save a range of memory to a file, byte by byte';
  Item.OnClick := @MenuExportBinary;
  FMenu.Items.Add(Item);
  Item := TMenuItem.Create(FMenu);
  Item.Caption := 'Import binary...';
  Item.Hint := 'Load a file into memory, byte by byte, at an address';
  Item.OnClick := @MenuImportBinary;
  FMenu.Items.Add(Item);
  FSpriteRowBytes := 8;
  FSpriteRows := 1;
end;

procedure THexView.MenuSearch(Sender: TObject);
begin
  Search;
end;

{ A small window: what to find, as text or as hex bytes ("3E 01" or "3E01") }
procedure THexView.Search;
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
    HexRadio.Caption := 'Bytes in hex (3E 01 or 3E01)';
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
    if (Dlg.ShowModal <> mrOk) or (Edit.Text = '') then Exit;
    FSearchText := Edit.Text;
    FSearchHex := HexRadio.Checked;
    FSearchCase := CaseCheck.Checked;
  finally
    Dlg.Free;
  end;
  SearchNext;
end;

{ From the byte after the selection (or the first one shown), round the
  whole memory; the bytes found are selected }
procedure THexView.SearchNext;
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
      MessageDlg('The bytes must be pairs of hex digits: 3E 01 or 3E01.', mtError, [mbOK], 0);
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
      V := FOwnerWin.Peek(Word(A + I)) xor FXor;
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
      // On screen, if it isn't
      if Word(A - FTop) >= VisibleBytes then FTop := Word(A and not (HEX_BYTES - 1));
      Invalidate;
      FOwnerWin.ShowNotice(Format('Found at %.4X (F3: next)', [A]));
      Exit;
    end;
  end;
  Beep;
  FOwnerWin.ShowNotice('Not found in memory');
end;

function THexView.CancelTyping: Boolean;
begin
  Result := (FTextCursor >= 0) or HasSel;
  FTextCursor := -1;
  FSelA := -1;
  FSelB := -1;
  if Result then Invalidate;
end;

function THexView.HasSel: Boolean;
begin
  Result := (FSelA >= 0) and (FSelB >= 0);
end;

function THexView.SelFirst: Word;
begin
  Result := Min(FSelA, FSelB);
end;

function THexView.SelLast: Word;
begin
  Result := Max(FSelA, FSelB);
end;

procedure THexView.BreakRange(out First, Last: Word);
var
  I: Integer;
  E: TBreakEntry;
begin
  First := FMenuAddr;
  Last := FMenuAddr;
  // A breakpoint already there: its range
  for I := 0 to FOwnerWin.BreakCount - 1 do
  begin
    E := FOwnerWin.BreakAt(I);
    if not E.Port and (FMenuAddr >= E.Addr) and (FMenuAddr <= E.Last) then
    begin
      First := E.Addr;
      Last := E.Last;
      Exit;
    end;
  end;
  if HasSel and (FMenuAddr >= SelFirst) and (FMenuAddr <= SelLast) then
  begin
    First := SelFirst;
    Last := SelLast;
  end;
end;

procedure THexView.MenuReadBreak(Sender: TObject);
var
  First, Last: Word;
begin
  if FMenuAddr < 0 then Exit;
  BreakRange(First, Last);
  FOwnerWin.ToggleDataBreak(FMenuAddr, First, Last, BP_READ);
end;

procedure THexView.MenuWriteBreak(Sender: TObject);
var
  First, Last: Word;
begin
  if FMenuAddr < 0 then Exit;
  BreakRange(First, Last);
  FOwnerWin.ToggleDataBreak(FMenuAddr, First, Last, BP_WRITE);
end;

function THexView.CopyRange(out First, Last: Integer): Boolean;
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

{ The selection as the text column shows it (XOR applied, "." for the
  bytes that aren't printable) }
procedure THexView.MenuCopyText(Sender: TObject);
var
  First, Last, A: Integer;
  V: Byte;
  S: string;
begin
  if not CopyRange(First, Last) then Exit;
  S := '';
  for A := First to Last do
  begin
    V := FOwnerWin.Peek(A) xor FXor;
    if (V >= 32) and (V < 127) then S := S + Chr(V) else S := S + '.';
  end;
  Clipboard.AsText := S;
  FOwnerWin.ShowNotice(Format('Copied %d characters', [Last - First + 1]));
end;

{ The selection (or the byte right-clicked) as "$3E,$01,..." }
procedure THexView.MenuCopy(Sender: TObject);
var
  First, Last: Integer;
  A: Integer;
  S: string;
begin
  if not CopyRange(First, Last) then Exit;
  S := '';
  for A := First to Last do
  begin
    if A > First then S := S + ',';
    S := S + '$' + IntToHex(FOwnerWin.Peek(A), 2);
  end;
  Clipboard.AsText := S;
  FOwnerWin.ShowNotice(Format('Copied %d values', [Last - First + 1]));
end;

procedure THexView.MenuPaste(Sender: TObject);
begin
  if FMenuAddr >= 0 then PasteAt(FMenuAddr);
end;

{ Values separated by commas (or one $ value) are written as they are; any
  other text as typed in the text column (XORed with the key) }
procedure THexView.PasteAt(Addr: Word);
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
  FOwnerWin.WriteBytes(Addr, Values);
end;

procedure THexView.MenuSprites(Sender: TObject);
begin
  FSprites := not FSprites;
  FTextCursor := -1;
  Invalidate;
end;

procedure THexView.MenuExport(Sender: TObject);
begin
  FOwnerWin.ExportMemory;
end;

procedure THexView.MenuImport(Sender: TObject);
begin
  FOwnerWin.ImportMemory;
end;

procedure THexView.MenuImportBinary(Sender: TObject);
begin
  FOwnerWin.ImportBinary;
end;

procedure THexView.MenuExportBinary(Sender: TObject);
begin
  FOwnerWin.ExportBinary;
end;

function THexView.RowBytes: Integer;
begin
  if FSprites then Result := FSpriteRowBytes else Result := HEX_BYTES;
end;

function THexView.Rows: Integer;
begin
  if FSprites then Result := FSpriteRows else Result := VisibleLines;
end;

function THexView.VisibleBytes: Integer;
begin
  Result := RowBytes * Rows;
end;

{ Sprite mode: each 8 bytes as an 8x8 cell (one byte per pixel row), cells
  left to right, the address of each row on the left }
procedure THexView.PaintSprites;
var
  PS, Cell, Gap, X0, Cols, RowCount, R, C, B, Bit, X, Y: Integer;
  A: Word;
  V: Byte;
begin
  PS := Max(2, FLineH div 6);         // screen pixels per sprite pixel
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
    AddSpot(4, Y, 4, skInfo, A);
    DrawText(4, Y, IntToHex(A, 4), TC(clGray), False);
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
        V := FOwnerWin.Peek(Word(A + C * 8 + B)) xor FXor;
        for Bit := 0 to 7 do
          if (V and ($80 shr Bit)) <> 0 then
            Canvas.FillRect(X + Bit * PS, Y + B * PS, X + (Bit + 1) * PS, Y + (B + 1) * PS);
      end;
      // Hover: the addresses of the cell
      AddSpot(X, Y, 1, skLabel, 0, 0, 0,
        Format('%.4X-%.4X', [Word(A + C * 8), Word(A + C * 8 + 7)]));
      FSpots[FSpotCount - 1].R := Rect(X, Y, X + Cell, Y + Cell);
    end;
  end;
end;

procedure THexView.MenuGoTo(Sender: TObject);
var
  A: Word;
begin
  A := FTop;
  if FOwnerWin.AskAddress(A) then GoToAddr(A);
end;

procedure THexView.MenuWatch(Sender: TObject);
begin
  if FMenuAddr >= 0 then FOwnerWin.AddWatchAt(FMenuAddr);
end;

procedure THexView.SetXor(Value: Byte);
begin
  FXor := Value;
  Invalidate;
end;

procedure THexView.GoToAddr(Addr: Word);
begin
  FTop := Addr;
  Invalidate;
end;

procedure THexView.Paint;
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
    AddSpot(4, Y, 4, skInfo, A);
    DrawText(4, Y + 1, IntToHex(A, 4), TC(clGray), False);
    for Col := 0 to HEX_BYTES - 1 do
    begin
      V := FOwnerWin.Peek(Word(A + Col)) xor FXor;
      // A read or write breakpoint on the byte: pink, pale when switched off
      BP := FOwnerWin.BreakFlags(Word(A + Col));
      if (BP and (BP_READ or BP_WRITE)) <> 0 then
      begin
        if (BP and BP_DISABLED) <> 0 then Back := TC(RGBToColor(250, 230, 230))
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
      AddSpot(X, Y, 2, skMemXorByte, V, 2, Word(A + Col));
      DrawText(X, Y + 1, IntToHex(V, 2), TC(clBlack), False);
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
      if (V >= 32) and (V < 127) then
        DrawText(X, Y + 1, Chr(V), TC(clBlack), False)
      else
        DrawText(X, Y + 1, '.', TC(clGray), False);
    end;
  end;
  DrawFocus;
end;

function THexView.ClickSpot(Index: Integer): Boolean;
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

procedure THexView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
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
    if (Spot >= 0) and (FSpots[Spot].Kind in [skMemXorByte, skAscii]) then
      FMenuAddr := FSpots[Spot].Target;
    FWatchItem.Enabled := FMenuAddr >= 0;
    FSpriteItem.Checked := FSprites;
    if FMenuAddr >= 0 then
      FWatchItem.Caption := 'Add a watch at ' + IntToHex(FMenuAddr, 4)
    else
      FWatchItem.Caption := 'Add a watch here';
    // Read and write breakpoints: on/off for the byte (or the selection)
    FReadItem.Enabled := FMenuAddr >= 0;
    FWriteItem.Enabled := FMenuAddr >= 0;
    Where := 'here';
    Flags := 0;
    if FMenuAddr >= 0 then
    begin
      BreakRange(First, Last);
      if Last <> First then Where := Format('at %.4X-%.4X', [First, Last])
      else Where := 'at ' + IntToHex(First, 4);
      Flags := FOwnerWin.BreakFlags(FMenuAddr);
      if (Flags and BP_EXEC) <> 0 then Flags := 0;
    end;
    FReadItem.Caption := 'Read breakpoint ' + Where;
    FReadItem.Checked := (Flags and BP_READ) <> 0;
    FWriteItem.Caption := 'Write breakpoint ' + Where;
    FWriteItem.Checked := (Flags and BP_WRITE) <> 0;
    FCopyItem.Enabled := HasSel or (FMenuAddr >= 0);
    FCopyTextItem.Enabled := FCopyItem.Enabled;
    FPasteItem.Enabled := FMenuAddr >= 0;
    PrepareGoto(FMenu, X, Y);
    P := ClientToScreen(Point(X, Y));
    FMenu.PopUp(P.X, P.Y);
  end;
end;

procedure THexView.MouseMove(Shift: TShiftState; X, Y: Integer);
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

procedure THexView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  FDragging := False;
end;

procedure THexView.KeyDown(var Key: Word; Shift: TShiftState);
var
  A: Word;
begin
  inherited KeyDown(Key, Shift);
  if ssCtrl in Shift then
    case Key of
      VK_F:
        begin
          Search;
          Key := 0;
        end;
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
    VK_G:
      if ssCtrl in Shift then
      begin
        A := FTop;
        if FOwnerWin.AskAddress(A) then GoToAddr(A);
        Key := 0;
      end;
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

procedure THexView.KeyPress(var Key: Char);
begin
  inherited KeyPress(Key);
  if (FTextCursor < 0) or not (Key in [#32..#126]) then Exit;
  // Typed in the decoded view: store it encoded with the XOR key
  FOwnerWin.PokeByte(FTextCursor, Ord(Key) xor FXor);
  FTextCursor := Word(FTextCursor + 1);
  // Keep the cursor on screen
  if Word(FTextCursor - FTop) >= HEX_BYTES * VisibleLines then FTop := Word(FTop + HEX_BYTES);
  FOwnerWin.Refresh(False);
  Key := #0;
end;

procedure THexView.DoExit;
begin
  FTextCursor := -1;
  inherited DoExit;
end;

function THexView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  if WheelDelta < 0 then FTop := Word(FTop + RowBytes * 3) else FTop := Word(FTop - RowBytes * 3);
  Invalidate;
  Result := True;
end;

{ TWatchView }

function TWatchView.HasOwnMenu: Boolean;
begin
  Result := True;
end;

constructor TWatchView.CreateView(AOwner: TDebuggerWindow);
var
  Item: TMenuItem;
begin
  inherited CreateView(AOwner);
  FSel := -1;
  FMenu := TPopupMenu.Create(Self);
  Item := TMenuItem.Create(FMenu);
  Item.Caption := 'Add watch...';
  Item.OnClick := @MenuAdd;
  FMenu.Items.Add(Item);
  Item := TMenuItem.Create(FMenu);
  Item.Caption := 'Remove watch';
  Item.OnClick := @MenuRemove;
  FMenu.Items.Add(Item);
  Item := TMenuItem.Create(FMenu);
  Item.Caption := '-';
  FMenu.Items.Add(Item);
  Item := TMenuItem.Create(FMenu);
  Item.Caption := 'Save watches (JSON)...';
  Item.OnClick := @MenuSave;
  FMenu.Items.Add(Item);
  Item := TMenuItem.Create(FMenu);
  Item.Caption := 'Load watches (JSON)...';
  Item.OnClick := @MenuLoad;
  FMenu.Items.Add(Item);
end;

procedure TWatchView.MenuSave(Sender: TObject);
begin
  FOwnerWin.SaveWatchesAs;
end;

procedure TWatchView.MenuLoad(Sender: TObject);
begin
  FOwnerWin.LoadWatchesAsk;
  FSel := -1;
end;

procedure TWatchView.MenuAdd(Sender: TObject);
begin
  FOwnerWin.AddWatch;
end;

procedure TWatchView.MenuRemove(Sender: TObject);
begin
  FOwnerWin.RemoveWatch(FSel);
  FSel := -1;
end;

procedure TWatchView.Paint;
var
  I, Y: Integer;
  A: Word;
  Lbl: string;
begin
  MeasureFont;
  ClearSpots;
  Canvas.Brush.Color := TC(clWhite);
  Canvas.FillRect(ClientRect);
  if FOwnerWin.WatchCount = 0 then
    DrawText(4, 2, 'Insert: add', TC(clGray), False);
  for I := 0 to FOwnerWin.WatchCount - 1 do
  begin
    Y := I * FLineH;
    A := FOwnerWin.Watch(I);
    if I = FSel then
    begin
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := TC(RGBToColor(210, 225, 250));
      Canvas.FillRect(0, Y, ClientWidth, Y + FLineH);
    end;
    AddSpot(4, Y, 4, skInfo, A);
    DrawText(4, Y + 1, IntToHex(A, 4), TC(clGray), False);
    AddSpot(4 + FCharW * 6, Y, 2, skMemByte, FOwnerWin.Peek(A), 2, A);
    DrawText(4 + FCharW * 6, Y + 1, IntToHex(FOwnerWin.Peek(A), 2), TC(clBlack), False);
    AddSpot(4 + FCharW * 9, Y, 2, skMemByte, FOwnerWin.Peek(Word(A + 1)), 2, Word(A + 1));
    DrawText(4 + FCharW * 9, Y + 1, IntToHex(FOwnerWin.Peek(Word(A + 1)), 2), TC(clBlack), False);
    Lbl := FOwnerWin.SymbolFor(A);
    if Lbl <> '' then
    begin
      AddSpot(4 + FCharW * 13, Y, Length(Lbl), skLabel, A, 0, 0, Lbl);
      DrawText(4 + FCharW * 13, Y + 1, Lbl, TC(RGBToColor(0, 110, 110)), False);
      // Cut at the right: the free parts of the line show it whole as a hint
      if 4 + FCharW * (13 + Length(Lbl)) > ClientWidth - 4 then
        AddSpot(0, Y, ClientWidth div FCharW + 1, skHint, 0, 0, 0,
          Format('%.4X  %.2X %.2X  %s', [A, FOwnerWin.Peek(A), FOwnerWin.Peek(Word(A + 1)), Lbl]));
    end;
  end;
  DrawFocus;
end;

procedure TWatchView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  P: TPoint;
begin
  if FLineH = 0 then MeasureFont;
  FSel := Y div FLineH;
  if FSel >= FOwnerWin.WatchCount then FSel := -1;
  inherited MouseDown(Button, Shift, X, Y);   // may start editing a byte
  Invalidate;
  if Button = mbRight then
  begin
    PrepareGoto(FMenu, X, Y);   // its three items come first
    FMenu.Items[GOTO_ITEMS + 1].Enabled := FSel >= 0;
    PrepareGoto(FMenu, X, Y);
    P := ClientToScreen(Point(X, Y));
    FMenu.PopUp(P.X, P.Y);
  end;
end;

procedure TWatchView.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  case Key of
    VK_INSERT: begin FOwnerWin.AddWatch; Key := 0; end;
    VK_DELETE:
      begin
        FOwnerWin.RemoveWatch(FSel);
        if FSel >= FOwnerWin.WatchCount then FSel := FOwnerWin.WatchCount - 1;
        Key := 0;
      end;
    VK_UP: if FSel > 0 then begin Dec(FSel); Key := 0; end;
    VK_DOWN: if FSel < FOwnerWin.WatchCount - 1 then begin Inc(FSel); Key := 0; end;
  end;
  Invalidate;
end;

{ TBreakView }

function TBreakView.HasOwnMenu: Boolean;
begin
  Result := True;
end;

constructor TBreakView.CreateView(AOwner: TDebuggerWindow);

  function AddItem(const ACaption: string; AHandler: TNotifyEvent): TMenuItem;
  begin
    Result := TMenuItem.Create(FMenu);
    Result.Caption := ACaption;
    Result.OnClick := AHandler;
    FMenu.Items.Add(Result);
  end;

begin
  inherited CreateView(AOwner);
  FSel := -1;
  FMenu := TPopupMenu.Create(Self);
  AddItem('Add breakpoint...  (Insert)', @MenuAdd);
  AddItem('Edit...  (Enter)', @MenuEdit);
  FEnabledItem := AddItem('Enabled  (Space)', @MenuEnable);
  AddItem('Remove  (Delete)', @MenuRemove);
  AddItem('-', nil);
  AddItem('Show in the disassembly', @MenuShow);
  AddItem('Remove all', @MenuRemoveAll);
  AddItem('-', nil);
  AddItem('Save breakpoints (JSON)...', @MenuSave);
  AddItem('Load breakpoints (JSON)...', @MenuLoad);
end;

procedure TBreakView.MenuSave(Sender: TObject);
begin
  FOwnerWin.SaveBreaksAs;
end;

procedure TBreakView.MenuLoad(Sender: TObject);
begin
  FOwnerWin.LoadBreaksAsk;
  FSel := -1;
end;

function TBreakView.HaveSel: Boolean;
begin
  Result := (FSel >= 0) and (FSel < FOwnerWin.BreakCount);
end;

function TBreakView.SelEntry: TBreakEntry;
begin
  Result := FOwnerWin.BreakAt(FSel);
end;

procedure TBreakView.MenuAdd(Sender: TObject);
begin
  FOwnerWin.EditBreakpoint(-1);
end;

procedure TBreakView.MenuEdit(Sender: TObject);
begin
  if HaveSel then FOwnerWin.EditBreakpoint(SelEntry.Addr, SelEntry.Port);
end;

procedure TBreakView.MenuEnable(Sender: TObject);
begin
  if HaveSel then FOwnerWin.ToggleBreakEnabled(SelEntry.Addr, SelEntry.Port);
end;

procedure TBreakView.MenuRemove(Sender: TObject);
begin
  if not HaveSel then Exit;
  FOwnerWin.RemoveEntry(SelEntry);
  if FSel >= FOwnerWin.BreakCount then FSel := FOwnerWin.BreakCount - 1;
end;

procedure TBreakView.MenuShow(Sender: TObject);
begin
  if HaveSel and not SelEntry.Port then FOwnerWin.GoToCode(SelEntry.Addr);
end;

procedure TBreakView.MenuRemoveAll(Sender: TObject);
begin
  FOwnerWin.ClearBreakpoints;
  FSel := -1;
end;

{ Short name of a breakpoint's type, as in the list }
function BreakTypeName(Flags: Byte; Port: Boolean): string;
begin
  if Port then
  begin
    case Flags and (BP_READ or BP_WRITE) of
      BP_READ: Result := 'Port R';
      BP_WRITE: Result := 'Port W';
    else
      Result := 'Port RW';
    end;
  end
  else if (Flags and BP_EXEC) <> 0 then Result := 'Exec'
  else
    case Flags and (BP_READ or BP_WRITE) of
      BP_READ: Result := 'Read';
      BP_WRITE: Result := 'Write';
    else
      Result := 'R/W';
    end;
end;

procedure TBreakView.Paint;
var
  I, Y, X, Box: Integer;
  E: TBreakEntry;
  Flags: Byte;
  Lbl, Cond, Full: string;
  IsOn: Boolean;
  TextColor: TColor;
begin
  MeasureFont;
  ClearSpots;
  Canvas.Brush.Color := TC(clWhite);
  Canvas.FillRect(ClientRect);
  if FOwnerWin.BreakCount = 0 then
    DrawText(4, 2, 'Insert: add', TC(clGray), False);
  Box := FLineH - 6;
  for I := 0 to FOwnerWin.BreakCount - 1 do
  begin
    Y := I * FLineH;
    E := FOwnerWin.BreakAt(I);
    Flags := FOwnerWin.EntryFlags(E);
    IsOn := (Flags and BP_DISABLED) = 0;
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
    DrawText(8 + Box, Y + 1, BreakTypeName(Flags, E.Port), TextColor, True);
    Full := BreakTypeName(Flags, E.Port) + '  ';
    X := 8 + Box + FCharW * 8;
    AddSpot(X, Y, 4, skInfo, E.Addr);
    if E.Port and (E.Addr <= $FF) then
      Lbl := 'xx' + IntToHex(E.Addr, 2)   // low byte only
    else
      Lbl := IntToHex(E.Addr, 4);
    // A range: up to its last address or port
    if E.Last <> E.Addr then
    begin
      if E.Port and (E.Last <= $FF) then
        Lbl := Lbl + '-xx' + IntToHex(E.Last, 2)
      else
        Lbl := Lbl + '-' + IntToHex(E.Last, 4);
    end;
    X := DrawText(X, Y + 1, Lbl, TextColor, False);
    Full := Full + Lbl;
    if not E.Port then
    begin
      Lbl := FOwnerWin.SymbolFor(E.Addr);
      if Lbl <> '' then
      begin
        Full := Full + ' ' + Lbl;
        AddSpot(X + FCharW, Y, Min(Length(Lbl), 14), skLabel, E.Addr, 0, 0, Lbl);
        if Length(Lbl) > 14 then Lbl := Copy(Lbl, 1, 13) + '~';
        X := DrawText(X + FCharW, Y + 1, Lbl, TC(RGBToColor(0, 110, 110)), False);
      end;
    end;
    Cond := FOwnerWin.EntryCondition(E);
    if E.Hits >= 0 then Cond := Cond + Format('  (T=%d)', [E.Hits]);   // times reached so far
    if Cond <> '' then
    begin
      X := DrawText(X + FCharW, Y + 1, 'if ' + Cond, TC(RGBToColor(140, 90, 0)), False);
      Full := Full + ' if ' + Cond;
    end;
    // Cut at the right: the box and the type (and any free part of the
    // line) show it whole as a hint
    if X > ClientWidth - 4 then
    begin
      AddSpot(0, Y, (8 + Box) div FCharW + 8, skHint, 0, 0, 0, Full);
      AddSpot(0, Y, ClientWidth div FCharW + 1, skHint, 0, 0, 0, Full);
    end;
  end;
  DrawFocus;
end;

procedure TBreakView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  P: TPoint;
begin
  if FLineH = 0 then MeasureFont;
  FSel := Y div FLineH;
  if FSel >= FOwnerWin.BreakCount then FSel := -1;
  inherited MouseDown(Button, Shift, X, Y);
  // The on/off box
  if (Button = mbLeft) and HaveSel and (X < 8 + FLineH) then
    FOwnerWin.ToggleBreakEnabled(SelEntry.Addr, SelEntry.Port);
  Invalidate;
  if Button = mbRight then
  begin
    PrepareGoto(FMenu, X, Y);   // its three items come first
    FMenu.Items[GOTO_ITEMS + 1].Enabled := HaveSel;
    FEnabledItem.Enabled := HaveSel;
    FEnabledItem.Checked := HaveSel and ((FOwnerWin.EntryFlags(SelEntry) and BP_DISABLED) = 0);
    FMenu.Items[GOTO_ITEMS + 3].Enabled := HaveSel;
    FMenu.Items[GOTO_ITEMS + 5].Enabled := HaveSel and not SelEntry.Port;
    FMenu.Items[GOTO_ITEMS + 6].Enabled := FOwnerWin.BreakCount > 0;
    PrepareGoto(FMenu, X, Y);
    P := ClientToScreen(Point(X, Y));
    FMenu.PopUp(P.X, P.Y);
  end;
end;

procedure TBreakView.DblClick;
begin
  inherited DblClick;
  MenuEdit(nil);
end;

procedure TBreakView.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  case Key of
    VK_INSERT: begin MenuAdd(nil); Key := 0; end;
    VK_DELETE: begin MenuRemove(nil); Key := 0; end;
    VK_SPACE: begin MenuEnable(nil); Key := 0; end;
    VK_RETURN: begin MenuEdit(nil); Key := 0; end;
    VK_UP: if FSel > 0 then begin Dec(FSel); Key := 0; end;
    VK_DOWN: if FSel < FOwnerWin.BreakCount - 1 then begin Inc(FSel); Key := 0; end;
  end;
  Invalidate;
end;

{ TRegView }

procedure TRegView.Paint;
const
  FLAG_NAMES = 'SZ5H3PNC';
var
  R, P: TRegSnapshot;
  Y, I, BoxTop: Integer;
  Mask: Byte;
  ValueColor: TColor;
  Have: Boolean;
  Access: TPortAccess;
  Bank: Integer;
  Text_: string;
  Rows, K, Im2: Integer;
  Ctl, OldCtl: Byte;
  PP: TPagingState;

  function Word16(Addr: Word): Word;
  begin
    Result := FOwnerWin.Peek(Addr) or (FOwnerWin.Peek(Word(Addr + 1)) shl 8);
  end;

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
  procedure RegValue(C: Integer; Reg: TRegId; V, Digits: Integer; Changed: Boolean);
  begin
    AddSpot(Col(C), Y, Digits, skRegister, V, Digits, Ord(Reg));
    DrawText(Col(C), Y, IntToHex(V, Digits), ChangedOrBlack(Changed), False);
  end;

  { A register pair: each half dark red only if the last instruction changed
    it (LD D,0 marks D, not E); click to edit }
  procedure PairValue(C: Integer; Reg: TRegId; V, Old: Word);
  begin
    AddSpot(Col(C), Y, 4, skRegister, V, 4, Ord(Reg));
    DrawText(Col(C), Y, IntToHex(V shr 8, 2), ChangedOrBlack((V shr 8) <> (Old shr 8)), False);
    DrawText(Col(C + 2), Y, IntToHex(V and $FF, 2), ChangedOrBlack((V and $FF) <> (Old and $FF)), False);
  end;

  { "AF  005C (C5C3)": register and the 16-bit word it points to (editable) }
  procedure Pair(C: Integer; const RegName: string; Reg: TRegId; V, Old: Word);
  begin
    Name(C, RegName);
    PairValue(C + 4, Reg, V, Old);
    DrawText(Col(C + 9), Y, '(', TC(clGray), False);
    AddSpot(Col(C + 10), Y, 4, skMemWord, Word16(V), 4, V);
    DrawText(Col(C + 10), Y, IntToHex(Word16(V), 4), TC(clGray), False);
    DrawText(Col(C + 14), Y, ')', TC(clGray), False);
  end;

  { Underlined: click to change }
  procedure ClickValue(C: Integer; const S: string; AColor: TColor);
  begin
    Canvas.Font := Font;
    Canvas.Font.Style := [fsUnderline];
    Canvas.Font.Color := AColor;
    Canvas.Brush.Style := bsClear;
    Canvas.TextOut(Col(C), Y, S);
    Canvas.Font := Font;
  end;

begin
  MeasureFont;
  ClearSpots;
  Canvas.Brush.Color := TC(clBtnFace);
  Canvas.FillRect(ClientRect);
  R := FOwnerWin.Regs;
  P := FOwnerWin.Prev;
  PP := FOwnerWin.PrevPaging;
  Have := FOwnerWin.HavePrev;
  // After a step the stack and the ports show their top again
  if FOwnerWin.Step <> FStep then
  begin
    FStep := FOwnerWin.Step;
    FStackOfs := 0;
    FPortOfs := 0;
  end;
  Y := 6;

  Pair(0, 'AF', rAF, (R.A shl 8) or R.F, (P.A shl 8) or P.F);
  Pair(17, 'AF''', rAF_, (R.A_ shl 8) or R.F_, (P.A_ shl 8) or P.F_);
  Inc(Y, FLineH);
  Pair(0, 'HL', rHL, R.HL, P.HL);
  Pair(17, 'HL''', rHL_, R.HL_, P.HL_);
  Inc(Y, FLineH);
  Pair(0, 'DE', rDE, R.DE, P.DE);
  Pair(17, 'DE''', rDE_, R.DE_, P.DE_);
  Inc(Y, FLineH);
  Pair(0, 'BC', rBC, R.BC, P.BC);
  Pair(17, 'BC''', rBC_, R.BC_, P.BC_);
  Inc(Y, FLineH);
  Pair(0, 'IX', rIX, R.IX, P.IX);
  Pair(17, 'IY', rIY, R.IY, P.IY);
  Inc(Y, FLineH + FLineH div 2);

  Name(0, 'I'); RegValue(4, rI, R.I, 2, R.I <> P.I);
  Name(11, 'R'); RegValue(14, rR, R.R, 2, R.R <> P.R);
  // IM 2 vector: I and the data bus, and the word there (below)
  AddSpot(Col(21), Y, 8, skHint, 0, 0, 0,
    'Where an IM 2 interrupt jumps to: the address (I as MSB, the data bus as LSB) ' +
    'and, in brackets, the word read there');
  Name(21, 'IM2 ADDR');
  Inc(Y, FLineH);
  Name(0, 'SP'); RegValue(4, rSP, R.SP, 4, R.SP <> P.SP);
  Name(11, 'PC'); RegValue(14, rPC, R.PC, 4, R.PC <> P.PC);
  // Editing the address edits I and the data bus; the word in brackets edits the memory
  Im2 := (R.I shl 8) or R.DataBus;
  // The address under its title; the word ends where the right pairs above end
  RegValue(21, rIm2, Im2, 4, R.I <> P.I);
  DrawText(Col(26), Y, '(', TC(clGray), False);
  AddSpot(Col(27), Y, 4, skMemWord, Word16(Im2), 4, Im2);
  DrawText(Col(27), Y, IntToHex(Word16(Im2), 4), TC(clGray), False);
  DrawText(Col(31), Y, ')', TC(clGray), False);
  Inc(Y, FLineH + FLineH div 2);

  // Flags: names above, X (set) or . (clear) below; click to toggle
  Name(0, 'Flags');
  for I := 0 to 7 do
  begin
    // Over a flag's name: what it means
    AddSpot(Col(7 + I * 2), Y, 1, skDoc, 0, 0, 0, FlagHelp(I));
    DrawText(Col(7 + I * 2), Y, FLAG_NAMES[I + 1], TC(clBlack), True);
  end;
  // Data bus: the value an interrupt reads (editable)
  AddSpot(Col(29), Y, 3, skHint, 0, 0, 0, 'Data bus value');
  Name(29, 'Bus');
  Inc(Y, FLineH);
  RegValue(29, rBus, R.DataBus, 2, False);
  for I := 0 to 7 do
  begin
    Mask := $80 shr I;
    ValueColor := ChangedOrBlack(((R.F xor P.F) and Mask) <> 0);
    AddSpot(Col(7 + I * 2), Y, 1, skFlag, Ord((R.F and Mask) <> 0), 1, Mask);
    if (R.F and Mask) <> 0 then
      DrawText(Col(7 + I * 2), Y, 'X', ValueColor, False)
    else
      DrawText(Col(7 + I * 2), Y, '.', ValueColor, False);
  end;
  Inc(Y, FLineH + FLineH div 2);

  // Interrupt state: click IM to cycle 0-1-2, IFF1/IFF2 to toggle
  Name(0, 'IM');
  AddSpot(Col(3), Y, 1, skIM, R.IM);
  ClickValue(3, IntToStr(R.IM), ChangedOrBlack(R.IM <> P.IM));
  Name(7, 'IFF1');
  AddSpot(Col(12), Y, 1, skIFF, Ord(R.IFF1), 1, 1);
  ClickValue(12, IntToStr(Ord(R.IFF1)), ChangedOrBlack(R.IFF1 <> P.IFF1));
  Name(15, 'IFF2');
  AddSpot(Col(20), Y, 1, skIFF, Ord(R.IFF2), 1, 2);
  ClickValue(20, IntToStr(Ord(R.IFF2)), ChangedOrBlack(R.IFF2 <> P.IFF2));
  // DI / EI as the program would see it (IFF1)
  if R.IFF1 then Name(23, 'EI') else Name(23, 'DI');
  if R.Halted then Name(26, 'HALT');
  Inc(Y, FLineH + FLineH div 2);

  // Stack (left) and port accesses (right): boxes like the memory view;
  // two lines fewer when the DivMMC lines are shown below (one more for the
  // ZX-Uno's), so the zone keeps its height
  if FOwnerWin.DivOn then Rows := STACK_ENTRIES - 2 else Rows := STACK_ENTRIES;
  if FOwnerWin.UnoOn then Dec(Rows);
  if FOwnerWin.NextOn then Dec(Rows);
  Name(0, 'Stack');
  Name(17, 'Ports');
  Inc(Y, FLineH);
  BoxTop := Y;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := TC(clWhite);
  Canvas.Pen.Color := TC(clGray);
  FStackBox := Rect(8, BoxTop, Col(15), BoxTop + FLineH * Rows + 6);
  FPortBox := Rect(Col(17), BoxTop, Col(36), BoxTop + FLineH * Rows + 6);
  Canvas.Rectangle(FStackBox);
  Canvas.Rectangle(FPortBox);
  // The wheel scrolls both lists (STACK_HISTORY entries at most)
  FStackOfs := Max(0, Min(FStackOfs, STACK_HISTORY - Rows));
  FPortOfs := Max(0, Min(FPortOfs, FOwnerWin.PortLogCount - Rows));
  Y := BoxTop + 3;
  for I := 0 to Rows - 1 do
  begin
    K := FStackOfs + I;
    if K = 0 then DrawText(Col(1), Y, '>', TC(clBlack), True);
    AddSpot(Col(3), Y, 4, skInfo, Word(R.SP + K * 2));
    DrawText(Col(3), Y, IntToHex(Word(R.SP + K * 2), 4), TC(clGray), False);
    AddSpot(Col(9), Y, 4, skMemWord, Word16(Word(R.SP + K * 2)), 4, Word(R.SP + K * 2));
    DrawText(Col(9), Y, IntToHex(Word16(Word(R.SP + K * 2)), 4), TC(clBlack), False);
    Inc(Y, FLineH);
  end;
  // Ports: address of the instruction, port, W (write) or R (read), value
  // (dark red if the last instruction made the access)
  Y := BoxTop + 3;
  for I := 0 to Min(FOwnerWin.PortLogCount - FPortOfs, Rows) - 1 do
  begin
    K := FPortOfs + I;
    Access := FOwnerWin.PortLogEntry(K);
    // > marks the latest access (the list is newest first)
    if K = 0 then DrawText(Col(17) + 3, Y, '>', TC(clBlack), True);
    AddSpot(Col(18) + FCharW div 2, Y, 4, skInfo, Access.PC);
    DrawText(Col(18) + FCharW div 2, Y, IntToHex(Access.PC, 4), TC(clGray), False);
    AddSpot(Col(24), Y, 4, skInfo, Access.Port);
    DrawText(Col(24), Y, IntToHex(Access.Port, 4), TC(clBlack), False);
    if Access.Write then
      DrawText(Col(29), Y, 'W', TC(RGBToColor(0, 0, 200)), True)
    else
      DrawText(Col(29), Y, 'R', TC(RGBToColor(0, 130, 0)), True);
    AddSpot(Col(32), Y, 2, skInfo, Access.Value);
    DrawText(Col(32), Y, IntToHex(Access.Value, 2), ChangedOrBlack(Access.Step = FOwnerWin.Step), False);
    Inc(Y, FLineH);
  end;

  // Memory map: what each 16K slot holds
  Y := BoxTop + FLineH * Rows + 6 + FLineH div 2;
  Name(0, 'Slots');
  for I := 0 to 3 do
  begin
    Bank := FOwnerWin.SlotBank(I);
    if (I = 0) and FOwnerWin.DivActive then Text_ := 'DIV'
    else if (I = 0) and FOwnerWin.CurrahPaged then Text_ := 'SPCH'
    else if FOwnerWin.UnoOn and (Bank = -5) then Text_ := 'BOOT'
    else if Bank = NO_MEMORY then Text_ := '----'
    else if Bank < 0 then Text_ := 'ROM' + IntToStr(-1 - Bank)
    else Text_ := 'RAM' + IntToStr(Bank);
    DrawText(Col(7 + I * 7), Y, IntToStr(I) + ':', TC(clGray), False);
    // Dark red if the last instruction paged something else in
    ValueColor := ChangedOrBlack((Bank <> PP.Slots[I]) or
      ((I = 0) and ((FOwnerWin.DivActive <> PP.DivActive) or
      (FOwnerWin.CurrahPaged <> PP.CurrahPaged))));
    if ((I = 3) and FOwnerWin.Slot3Changeable) or FOwnerWin.CpcSlotChangeable then
    begin
      // A drop-down: underlined, click to choose the bank (or the ROM, on the CPC)
      if FOwnerWin.CpcSlotChangeable then
        AddSpot(Col(9 + I * 7), Y, 6, skCpcSlot, Bank, 0, I)
      else
        AddSpot(Col(9 + I * 7), Y, 6, skSlot3, Bank);
      Canvas.Font := Font;
      Canvas.Font.Style := [fsUnderline];
      Canvas.Font.Color := ValueColor;
      Canvas.Brush.Style := bsClear;
      Canvas.TextOut(Col(9 + I * 7), Y, Text_);
      Canvas.Font := Font;
    end
    else
      DrawText(Col(9 + I * 7), Y, Text_, ValueColor, False);
  end;

  // Next: the MMU registers, the 8K page of each of the 8 slots (255 = ROM); click to choose
  if FOwnerWin.NextOn then
  begin
    Inc(Y, FLineH);
    Name(0, 'MMU');
    for I := 0 to 7 do
    begin
      AddSpot(Col(7 + I * 4), Y, 3, skNextMMU, FOwnerWin.NextMMU(I), 0, I);
      if FOwnerWin.NextMMU(I) = 255 then Text_ := 'ROM' else Text_ := IntToStr(FOwnerWin.NextMMU(I));
      ClickValue(7 + I * 4, Text_, TC(clBlack));
    end;
  end;

  // DivMMC paging: what it maps at 0000 and 2000 (bank: a drop-down), and
  // CONMEM and the automatic paging state (click to change)
  if FOwnerWin.DivOn then
  begin
    Ctl := FOwnerWin.DivControl;
    OldCtl := PP.DivControl;
    Inc(Y, FLineH);
    Name(0, 'DivMMC');
    if ((Ctl and $80) = 0) and ((Ctl and $40) <> 0) then Text_ := 'RAM3' else Text_ := 'EEPROM';
    DrawText(Col(7), Y, '0000:', TC(clGray), False);
    DrawText(Col(12), Y, Text_, ChangedOrBlack((((Ctl and $C0) = $40) <> ((OldCtl and $C0) = $40))), False);
    DrawText(Col(19), Y, '2000:', TC(clGray), False);
    AddSpot(Col(24), Y, 7, skDivBank, Ctl and $0F);
    Canvas.Font := Font;
    Canvas.Font.Style := [fsUnderline];
    Canvas.Font.Color := ChangedOrBlack(((Ctl xor OldCtl) and $0F) <> 0);
    Canvas.Brush.Style := bsClear;
    Canvas.TextOut(Col(24), Y, 'RAM' + IntToStr(Ctl and $0F));
    Canvas.Font := Font;
    // Paged in now (by automap or CONMEM) or not
    if FOwnerWin.DivActive <> PP.DivActive then ValueColor := ChangedOrBlack(True)
    else ValueColor := clNone;
    if FOwnerWin.DivActive then
    begin
      if ValueColor = clNone then ValueColor := TC(RGBToColor(0, 130, 0));
      DrawText(Col(32), Y, 'in', ValueColor, True);
    end
    else
    begin
      if ValueColor = clNone then ValueColor := TC(clGray);
      DrawText(Col(32), Y, 'out', ValueColor, True);
    end;
    Inc(Y, FLineH);
    DrawText(Col(7), Y, 'CONMEM', TC(clGray), False);
    AddSpot(Col(14), Y, 1, skDivConmem, Ord((Ctl and $80) <> 0));
    ClickValue(14, IntToStr(Ord((Ctl and $80) <> 0)), ChangedOrBlack(((Ctl xor OldCtl) and $80) <> 0));
    DrawText(Col(16), Y, 'MAPRAM', TC(clGray), False);
    DrawText(Col(23), Y, IntToStr(Ord((Ctl and $40) <> 0)), ChangedOrBlack(((Ctl xor OldCtl) and $40) <> 0), False);
    DrawText(Col(25), Y, 'automap', TC(clGray), False);
    AddSpot(Col(33), Y, 3, skDivMapped, 0);
    ValueColor := ChangedOrBlack(FOwnerWin.DivMappedNow <> PP.DivMapped);
    if FOwnerWin.DivMappedNow then ClickValue(33, 'on', ValueColor) else ClickValue(33, 'off', ValueColor);
  end;

  // ZX-Uno: boot mode (the boot ROM at 0000) and MASTERMAPPER, the SRAM
  // page at C000 in boot mode (grey when not in boot mode: it is unused)
  if FOwnerWin.UnoOn then
  begin
    Inc(Y, FLineH);
    Name(0, 'ZX-Uno');
    DrawText(Col(7), Y, 'BOOTM', TC(clGray), False);
    AddSpot(Col(13), Y, 1, skUnoBoot, FOwnerWin.UnoConf and 1);
    ClickValue(13, IntToStr(FOwnerWin.UnoConf and 1), ChangedOrBlack(((FOwnerWin.UnoConf xor PP.UnoConf) and 1) <> 0));
    DrawText(Col(15), Y, 'MAPPER', TC(clGray), False);
    // A drop-down; grey when not in boot mode (dark red if just changed)
    AddSpot(Col(22), Y, 7, skUnoMapper, FOwnerWin.UnoMapper);
    Canvas.Font := Font;
    Canvas.Font.Style := [fsUnderline];
    if Have and (FOwnerWin.UnoMapper <> PP.UnoMapper) then Canvas.Font.Color := ChangedColor
    else if (FOwnerWin.UnoConf and 1) = 0 then Canvas.Font.Color := TC(clGray);
    Canvas.Brush.Style := bsClear;
    Canvas.TextOut(Col(22), Y, 'RAM' + IntToStr(FOwnerWin.UnoMapper));
    Canvas.Font := Font;
    DrawText(Col(30), Y, 'LOCK', TC(clGray), False);
    DrawText(Col(35), Y, IntToStr(FOwnerWin.UnoConf shr 7), ChangedOrBlack(((FOwnerWin.UnoConf xor PP.UnoConf) and $80) <> 0), False);
  end;
end;

function TRegView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
var
  D: Integer;
begin
  Result := True;
  if WheelDelta < 0 then D := 1 else D := -1;
  if PtInRect(FStackBox, MousePos) then Inc(FStackOfs, D)
  else if PtInRect(FPortBox, MousePos) then Inc(FPortOfs, D)
  else Exit(inherited DoMouseWheel(Shift, WheelDelta, MousePos));
  Invalidate;   // Paint keeps the offsets in range
end;

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

{ TDebuggerWindow }

constructor TDebuggerWindow.CreateFor(AOwner: TComponent; AEmu: TEmulator);
var
  Lbl: TLabel;
  Split: TSplitter;
  Header, Column: TPanel;
begin
  inherited CreateNew(AOwner, 0);
  FEmu := AEmu;
  FHistory := TStringList.Create;
  FWatchHistory := TStringList.Create;
  // Menu item hints show in the status bar
  Application.AddOnHintHandler(@AppHint);
  // Watches given on the command line
  FWatches := Copy(PendingWatches);
  PendingWatches := nil;
  Caption := 'Debugger';
  Width := 1200;
  Height := 720;
  Position := poMainFormCenter;
  KeyPreview := True;
  OnKeyDown := @FormKeyDown;
  OnClose := @FormClose;
  OnResize := @FormResize;
  OnShow := @FormShow;

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
  FBreakButton := AddButton(ikBreak, 'Break', @DoBreak);
  AddSeparator;
  AddButton(ikStepInto, 'Step into (F7)', @DoStepInto);
  AddButton(ikStepOver, 'Step over (F10)', @DoStepOver);
  AddButton(ikFolderUp, 'Step out: run until the subroutine returns, to the address on the top of the stack (F11)',
    @DoStepOut);
  AddButton(ikRunToCursor, 'Run to cursor (F9)', @DoRunToCursor);
  AddButton(ikRewind, 'Step back (Shift+F7): to where it was before the last step, step ' +
    'over, step out, run to cursor or run (up to 10 times)', @DoStepBack);
  AddSeparator;
  AddButton(ikGoTo, 'Go to address (Ctrl+G)', @DoGoTo);
  AddButton(ikBreakpoint, 'Put or take away a breakpoint on the selected line (F8)', @DoToggleBreakpoint);
  AddButton(ikClearBreakpoints, 'Remove all the breakpoints', @DoClearBreakpoints);
  AddButton(ikWatch, 'Add a watch', @DoAddWatch);
  AddSeparator;
  AddButton(ikOpen, 'Load symbols (as Debug > Load symbols): LABEL: EQU 0x8000 lines, as SjASMPlus exports them',
    @DoLoadSymbols);
  FUnoButton := AddButton(ikChip, 'ZXUno Regs: the ZX-Uno''s registers', @DoUnoRegs);
  FCartButton := AddButton(ikCartridge, 'Cartridge browser: the cartridge in slot 1, its header and its bytes', @DoCartBrowser);
  AddSeparator;
  AddButton(ikZ80, 'Z80: the instruction set, as tables of opcodes', @DoZ80Opcodes);

  // Data zone (bottom third): memory (just as wide as its contents) |
  // breakpoints | watches, the last two sharing the rest
  FDataPanel := TPanel.Create(Self);
  FDataPanel.Parent := Self;
  FDataPanel.Align := alBottom;
  FDataPanel.Height := 220;
  FDataPanel.BevelOuter := bvNone;
  FMemZone := MakeColumn(FDataPanel, 'Memory (Ctrl+G: go to; Space: sprites)', 600, alLeft);
  Header := TPanel(FMemZone.Controls[0]);
  // XOR: its box at the right end of the header, the label before it
  FXorEdit := TEdit.Create(Self);
  FXorEdit.Parent := Header;
  FXorEdit.AnchorSideRight.Control := Header;
  FXorEdit.AnchorSideRight.Side := asrRight;
  FXorEdit.BorderSpacing.Right := 4;
  FXorEdit.Anchors := [akTop, akRight];
  FXorEdit.Top := 1;
  FXorEdit.Width := Scale96ToForm(30);   // two hex digits
  Lbl := TLabel.Create(Self);
  Lbl.Parent := Header;
  Lbl.Caption := 'XOR:';
  Lbl.Font.Style := [fsBold];
  Lbl.AnchorSideRight.Control := FXorEdit;
  Lbl.AnchorSideRight.Side := asrLeft;
  Lbl.BorderSpacing.Right := 6;
  Lbl.Anchors := [akTop, akRight];
  Lbl.Top := 4;
  FXorEdit.Text := '00';
  FXorEdit.MaxLength := 2;
  FXorEdit.Hint := 'Each byte is XORed with this hex value for display and when edited';
  FXorEdit.ShowHint := True;
  FXorEdit.OnChange := @XorChange;
  FHex := THexView.CreateView(Self);
  FHex.Parent := FMemZone;
  FHex.Align := alClient;
  Split := TSplitter.Create(Self);
  Split.Parent := FDataPanel;
  Split.Align := alLeft;
  Split.Left := 2000;
  // Left-aligned controls are ordered by Left: breakpoints after memory
  FBreakZone := MakeColumn(FDataPanel, 'Breakpoints', 200, alLeft);
  FBreakZone.Left := 3000;
  SetZoneHint(FBreakZone, 'Insert: add, Delete: remove, Space or the box: on/off, ' +
    'Enter or double-click: edit, right-click: menu');
  FBreakView := TBreakView.CreateView(Self);
  FBreakView.Parent := FBreakZone;
  FBreakView.Align := alClient;
  // Breakpoints | watches: drag the bevel between them to share the width
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
  SetZoneHint(FWatchZone, 'Insert: add a watch, Delete: remove it, right-click: menu');
  FWatchView := TWatchView.CreateView(Self);
  FWatchView.Parent := FWatchZone;
  FWatchView.Align := alClient;

  Split := TSplitter.Create(Self);
  Split.Parent := Self;
  Split.Align := alBottom;

  // Registers zone (right)
  FRegZone := MakeColumn(Self, 'Registers (click to change)', 400, alRight);
  FRegView := TRegView.CreateView(Self);
  FRegView.Parent := FRegZone;
  FRegView.Align := alClient;
  FRegView.TabStop := False;
  FRegView.Color := clBtnFace;

  Split := TSplitter.Create(Self);
  Split.Parent := Self;
  Split.Align := alRight;

  // Disassembly zone (rest)
  Column := MakeColumn(Self, 'Disassembly (double-click: breakpoint; right-click: menu)', 0, alClient);
  FDisasm := TDisasmView.CreateView(Self);
  FDisasm.Parent := Column;
  FDisasm.Align := alClient;

  // Bottom-aligned controls are ordered by Top: put the status bar lowest
  FStatusBar := TStatusBar.Create(Self);
  FStatusBar.Parent := Self;
  FStatusBar.SimplePanel := True;
  FStatusBar.Top := 100000;

  FTimer := TTimer.Create(Self);
  FTimer.Interval := 250;
  FTimer.OnTimer := @Tick;

  FWasPaused := True;
  TakeSnapshot;
  FDisasm.GoToAddr(FRegs.PC);
  FHex.GoToAddr($4000);
end;

destructor TDebuggerWindow.Destroy;
begin
  Application.RemoveOnHintHandler(@AppHint);
  FHistory.Free;
  FWatchHistory.Free;
  inherited Destroy;
end;

function TDebuggerWindow.AddButton(AIcon: TIconKind; const AHint: string;
  AHandler: TNotifyEvent): TToolButton;
begin
  Result := TToolButton.Create(FToolbar);
  Result.Parent := FToolbar;
  Result.ImageIndex := Ord(AIcon);
  Result.Hint := AHint;
  Result.OnClick := AHandler;
  Result.Left := FToolbar.Width + 1000;   // append at the right
end;

procedure TDebuggerWindow.AddSeparator;
var
  Sep: TToolButton;
begin
  Sep := TToolButton.Create(FToolbar);
  Sep.Parent := FToolbar;
  Sep.Style := tbsDivider;
  Sep.Left := FToolbar.Width + 1000;
end;

{ A zone of the window: a tinted header with a bold title, then the view.
  The gap around it and the view's border keep the zones apart. }
function TDebuggerWindow.MakeColumn(AParent: TWinControl; const ACaption: string;
  AWidth: Integer; AAlign: TAlign): TPanel;
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

procedure TDebuggerWindow.FormResize(Sender: TObject);
const
  MIN_DATA = 110;     // header and a few lines of memory, breakpoints and watches
var
  Avail, Data: Integer;
begin
  if FDataPanel = nil then Exit;
  // The data zone keeps a third of the height, but the registers zone above
  // keeps all its lines: on a short window the disassembly and the data
  // zone show fewer lines instead
  Avail := ClientHeight - FToolbar.Height - FStatusBar.Height - 8;
  Data := Avail div 3;
  if Avail - Data < FRegMinH then Data := Avail - FRegMinH;
  FDataPanel.Height := Max(MIN_DATA, Data);
  // Breakpoints and watches share what the memory view leaves (half each
  // until the splitter between them is moved)
  FBreakZone.Width := Max(80, DataRest - Round(DataRest * FWatchShare));
end;

{ Width for breakpoints and watches }
function TDebuggerWindow.DataRest: Integer;
begin
  Result := Max(1, FDataPanel.ClientWidth - FMemZone.Width - 26);
end;

procedure TDebuggerWindow.WatchSplitMoved(Sender: TObject);
begin
  FWatchShare := Max(0.1, 1 - FBreakZone.Width / DataRest);
end;

procedure TDebuggerWindow.FormShow(Sender: TObject);
begin
  if not FLaidOut then FitLayout;
end;

{ Size the zones to what they show, now that the font can be measured: the
  window is as wide as the disassembly plus the registers, and the memory
  view ends right after its text column. }
procedure TDebuggerWindow.FitLayout;
var
  CW, Border, DisasmW, RegW, MemW: Integer;
begin
  FLaidOut := True;
  FDisasm.MeasureFont;
  CW := FDisasm.FCharW;
  Border := FRegView.Width - FRegView.ClientWidth;
  // Registers: 36 columns (the ports box ends there) and the margins
  RegW := 16 + 36 * CW + Border;
  // Disassembly: gutter, label, address, bytes, and room for the instruction
  DisasmW := GUTTER_W + (MAX_LABEL + 1 + 6 + 13 + 28) * CW + Border;
  // Memory: address, 16 hex bytes and 16 characters
  MemW := 6 + (6 + HEX_BYTES * 3 + 1 + HEX_BYTES) * CW + Border;
  FRegZone.Width := RegW + 6;
  FMemZone.Width := MemW + 6;
  // The registers zone's lines (see TRegView.Paint): 22.5 lines of text
  // plus margins, the stack box, its title and the zone's border spacing
  FRegMinH := 12 + (45 * FDisasm.FLineH) div 2 + FDisasm.FLineH + Border +
    TPanel(FRegZone.Controls[0]).Height + 12;
  ClientWidth := DisasmW + RegW + 12 + 10;
  FitToScreen;
  FormResize(Self);
end;

{ Not bigger than the screen: a short screen gives fewer lines to the
  disassembly and the data zone (FormResize), a narrow one a narrower
  disassembly }
procedure TDebuggerWindow.FitToScreen;
var
  Work: TRect;
begin
  Work := Monitor.WorkareaRect;
  if Height > Work.Bottom - Work.Top then
  begin
    Height := Work.Bottom - Work.Top;
    Top := Work.Top;
  end
  else if Top + Height > Work.Bottom then
    Top := Max(Work.Top, Work.Bottom - Height);
  if Width > Work.Right - Work.Left then
  begin
    Width := Work.Right - Work.Left;
    Left := Work.Left;
  end
  else if Left + Width > Work.Right then
    Left := Max(Work.Left, Work.Right - Width);
end;

procedure TDebuggerWindow.SetStatus(const AText: string);
begin
  FStatusBar.SimpleText := AText;
end;

function TDebuggerWindow.Peek(Addr: Word): Byte;
begin
  Result := FMem[Addr];
end;

function TDebuggerWindow.BreakFlags(Addr: Word): Byte;
begin
  Result := FBreak[Addr];
end;

procedure TDebuggerWindow.SetBreak(Addr: Word; Flags: Byte);
begin
  FEmu.Lock;
  try
    FEmu.Spec.Breakpoint[Addr] := Flags;
  finally
    FEmu.Unlock;
  end;
  FBreak[Addr] := Flags;
end;

function TDebuggerWindow.ConditionText(Addr: Word): string;
begin
  if Length(FCondText) > 0 then Result := FCondText[Addr] else Result := '';
end;

procedure TDebuggerWindow.EditCondition(Addr: Word);
var
  CondStr, Error: string;
  Ok: Boolean;
begin
  CondStr := ConditionText(Addr);
  repeat
    if not InputQuery('Breakpoint condition',
      Format('Stop at %.4X only when this holds (empty = always).' + LineEnding +
        'Hex values, registers, #flags, = <> < > <= >=, AND OR XOR NOT, ( ).' + LineEnding +
        'Examples:  BC=289A    A=3 AND E=3    #Z=0 OR HL>=C000', [Addr]), CondStr) then Exit;
    FEmu.Lock;
    try
      Ok := FEmu.Spec.SetBreakCondition(Addr, CondStr, Error);
      // A condition needs a breakpoint to apply to
      if Ok and (Trim(CondStr) <> '') and (FEmu.Spec.Breakpoint[Addr] = 0) then
        FEmu.Spec.Breakpoint[Addr] := BP_EXEC;
    finally
      FEmu.Unlock;
    end;
    if not Ok then MessageDlg('Invalid condition: ' + Error, mtError, [mbOK], 0);
  until Ok;
  Refresh(False);
end;

function TDebuggerWindow.PortLogCount: Integer;
begin
  Result := Length(FPortLog);
end;

function TDebuggerWindow.PortLogEntry(Index: Integer): TPortAccess;
begin
  Result := FPortLog[Index];
end;

function TDebuggerWindow.SlotBank(Slot: Integer): Integer;
begin
  Result := FSlots[Slot];
end;

function TDebuggerWindow.DivActive: Boolean;
begin
  Result := FDivActive;
end;

function TDebuggerWindow.CurrahPaged: Boolean;
begin
  Result := FCurrahPaged;
end;

function TDebuggerWindow.DivOn: Boolean;
begin
  Result := FDivOn;
end;

function TDebuggerWindow.DivMappedNow: Boolean;
begin
  Result := FDivMapped;
end;

function TDebuggerWindow.DivControl: Byte;
begin
  Result := FDivControl;
end;

function TDebuggerWindow.NextOn: Boolean;
begin
  Result := FNextOn;
end;

function TDebuggerWindow.NextMMU(Slot: Integer): Byte;
begin
  Result := FNextMMU[Slot and 7];
end;

procedure TDebuggerWindow.ChooseNextMMU(Slot: Integer);
var
  Page: Integer;
  Group: TMenuItem;
  PickMenu: TPopupMenu;
  P: TPoint;

  function NewItem(Parent: TMenuItem; const ACaption: string; Value: Integer): TMenuItem;
  begin
    Result := TMenuItem.Create(PickMenu);
    Result.Caption := ACaption;
    Result.Tag := Value;
    if Value >= 0 then
    begin
      Result.RadioItem := True;
      Result.Checked := Value = FNextMMU[Slot and 7];
      Result.OnClick := @NextMMUClick;
    end;
    Parent.Add(Result);
  end;

begin
  FNextSlot := Slot and 7;
  PickMenu := TPopupMenu.Create(Self);
  // ROM only in the first two slots; the pages in two groups: the first 1Mb (0-95) and the next (96-223)
  if FNextSlot < 2 then NewItem(PickMenu.Items, 'ROM', 255);
  Group := NewItem(PickMenu.Items, '1Mb', -1);
  for Page := 0 to 95 do NewItem(Group, IntToStr(Page), Page);
  Group := NewItem(PickMenu.Items, '2Mb', -1);
  for Page := 96 to 223 do NewItem(Group, IntToStr(Page), Page);
  FNextMenu.Free;
  FNextMenu := PickMenu;
  P := Mouse.CursorPos;
  FNextMenu.PopUp(P.X, P.Y);
end;

procedure TDebuggerWindow.NextMMUClick(Sender: TObject);
begin
  SetNextMMU(FNextSlot, (Sender as TMenuItem).Tag);
  Refresh(False);
end;

procedure TDebuggerWindow.SetNextMMU(Slot, Value: Integer);
begin
  // As a program would: through the MMU register ($50-$57), so the paging follows
  FEmu.Lock;
  try
    FEmu.Spec.SetNextRegister($50 + (Slot and 7), Value);
  finally
    FEmu.Unlock;
  end;
  PagingChangedByHand;
end;

function TDebuggerWindow.UnoOn: Boolean;
begin
  Result := FUnoOn;
end;

function TDebuggerWindow.UnoConf: Byte;
begin
  Result := FUnoConf;
end;

function TDebuggerWindow.UnoMapper: Byte;
begin
  Result := FUnoMapper;
end;

procedure TDebuggerWindow.ChooseDivBank;
var
  Bank: Integer;
  Item: TMenuItem;
  P: TPoint;
begin
  if FDivMenu = nil then
  begin
    FDivMenu := TPopupMenu.Create(Self);
    for Bank := 0 to DIVMMC_BANKS - 1 do
    begin
      Item := TMenuItem.Create(FDivMenu);
      Item.Caption := 'RAM' + IntToStr(Bank);
      Item.Tag := Bank;
      Item.RadioItem := True;
      Item.OnClick := @DivBankClick;
      FDivMenu.Items.Add(Item);
    end;
  end;
  for Bank := 0 to DIVMMC_BANKS - 1 do FDivMenu.Items[Bank].Checked := Bank = FDivControl and $0F;
  P := Mouse.CursorPos;
  FDivMenu.PopUp(P.X, P.Y);
end;

procedure TDebuggerWindow.DivBankClick(Sender: TObject);
begin
  FEmu.Lock;
  try
    FEmu.Spec.DivMMC.SetControl((FEmu.Spec.DivMMC.Control and $F0) or (Sender as TMenuItem).Tag);
  finally
    FEmu.Unlock;
  end;
  PagingChangedByHand;
  Refresh(False);
end;

procedure TDebuggerWindow.ChangeDivControl(Mask: Byte);
begin
  FEmu.Lock;
  try
    FEmu.Spec.DivMMC.SetControl(FEmu.Spec.DivMMC.Control xor Mask);
  finally
    FEmu.Unlock;
  end;
  PagingChangedByHand;
  Refresh(False);
end;

procedure TDebuggerWindow.ToggleDivMapped;
begin
  FEmu.Lock;
  try
    FEmu.Spec.DivMMC.Mapped := not FEmu.Spec.DivMMC.Mapped;
  finally
    FEmu.Unlock;
  end;
  PagingChangedByHand;
  Refresh(False);
end;

function TDebuggerWindow.Slot3Changeable: Boolean;
begin
  Result := FSlot3OK;
end;

function TDebuggerWindow.CpcSlotChangeable: Boolean;
begin
  Result := FIsCpc;
end;

procedure TDebuggerWindow.ToggleUnoBoot;
begin
  FEmu.Lock;
  try
    FEmu.Spec.DebugSetZXUnoReg(0, FEmu.Spec.ZXUnoRegister(0) xor 1);
  finally
    FEmu.Unlock;
  end;
  PagingChangedByHand;
  Refresh(False);
end;

procedure TDebuggerWindow.ChooseUnoMapper;
var
  Page: Integer;
  Item: TMenuItem;
  P: TPoint;
begin
  if FMapperMenu = nil then
  begin
    FMapperMenu := TPopupMenu.Create(Self);
    for Page := 0 to ZXUNO_PAGES - 1 do
    begin
      Item := TMenuItem.Create(FMapperMenu);
      Item.Caption := 'RAM' + IntToStr(Page);
      case Page of
        8..11: Item.Caption := Item.Caption + ' (ROM' + IntToStr(Page - 8) + ')';
        12: Item.Caption := Item.Caption + ' (DivMMC firmware)';
        16..23: Item.Caption := Item.Caption + ' (DivMMC RAM' + IntToStr((Page - 16) * 2) +
          '-' + IntToStr((Page - 16) * 2 + 1) + ')';
      end;
      Item.Tag := Page;
      Item.RadioItem := True;
      Item.OnClick := @UnoMapperClick;
      FMapperMenu.Items.Add(Item);
    end;
  end;
  for Page := 0 to ZXUNO_PAGES - 1 do FMapperMenu.Items[Page].Checked := Page = FUnoMapper;
  P := Mouse.CursorPos;
  FMapperMenu.PopUp(P.X, P.Y);
end;

procedure TDebuggerWindow.UnoMapperClick(Sender: TObject);
begin
  FEmu.Lock;
  try
    FEmu.Spec.DebugSetZXUnoReg(1, (Sender as TMenuItem).Tag);
  finally
    FEmu.Unlock;
  end;
  PagingChangedByHand;
  Refresh(False);
end;

procedure TDebuggerWindow.ChooseSlot3;
var
  Bank: Integer;
  Item: TMenuItem;
  P: TPoint;
begin
  if FSlotMenu = nil then
  begin
    FSlotMenu := TPopupMenu.Create(Self);
    for Bank := 0 to 7 do
    begin
      Item := TMenuItem.Create(FSlotMenu);
      Item.Caption := 'RAM' + IntToStr(Bank);
      Item.Tag := Bank;
      Item.RadioItem := True;
      Item.OnClick := @Slot3Click;
      FSlotMenu.Items.Add(Item);
    end;
  end;
  for Bank := 0 to 7 do FSlotMenu.Items[Bank].Checked := Bank = FSlots[3];
  P := Mouse.CursorPos;
  FSlotMenu.PopUp(P.X, P.Y);
end;

procedure TDebuggerWindow.Slot3Click(Sender: TObject);
begin
  FEmu.Lock;
  try
    FEmu.Spec.SetSlot3Bank((Sender as TMenuItem).Tag);
  finally
    FEmu.Unlock;
  end;
  PagingChangedByHand;
  Refresh(False);
end;

procedure TDebuggerWindow.ChooseCpcSlot(Slot: Integer);
var
  What: Integer;
  Item: TMenuItem;
  PickMenu: TPopupMenu;
  P: TPoint;
begin
  FCpcSlot := Slot;
  // Only what the CPC can put in this slot: ROMs by their enable bits, RAM banks by
  // the Gate Array's configurations (the 464 and 664 have the first four)
  PickMenu := TPopupMenu.Create(Self);
  FEmu.Lock;
  try
    for What := -3 to 31 do
      if FEmu.Spec.CPCSlotCanHold(Slot, What) then
      begin
        Item := TMenuItem.Create(PickMenu);
        if What < 0 then Item.Caption := 'ROM' + IntToStr(-1 - What)
        else Item.Caption := 'RAM' + IntToStr(What);
        Item.Tag := What;
        Item.RadioItem := True;
        Item.Checked := What = FSlots[Slot];
        Item.OnClick := @CpcSlotClick;
        PickMenu.Items.Add(Item);
      end;
  finally
    FEmu.Unlock;
  end;
  FCpcMenu.Free;
  FCpcMenu := PickMenu;
  P := Mouse.CursorPos;
  FCpcMenu.PopUp(P.X, P.Y);
end;

procedure TDebuggerWindow.CpcSlotClick(Sender: TObject);
begin
  FEmu.Lock;
  try
    FEmu.Spec.SetCPCSlot(FCpcSlot, (Sender as TMenuItem).Tag);
  finally
    FEmu.Unlock;
  end;
  PagingChangedByHand;
  Refresh(False);
end;

procedure TDebuggerWindow.PagingChangedByHand;
begin
  FEmu.Lock;
  try
    FEmu.Spec.PrevPaging := FEmu.Spec.PagingState;
  finally
    FEmu.Unlock;
  end;
end;

procedure TDebuggerWindow.ToggleDataBreak(Addr, First, Last: Word; Bit: Byte);
var
  Flags, NewFlags: Byte;
begin
  FEmu.Lock;
  try
    Flags := FEmu.Spec.Breakpoint[Addr];
    if Flags <> 0 then
    begin
      // One already there (for the whole of its range): an execution one
      // becomes this type, a data one gets the type switched on or off
      if (Flags and BP_EXEC) <> 0 then
        NewFlags := Bit or (Flags and BP_DISABLED)
      else
      begin
        NewFlags := Flags xor Bit;
        if (NewFlags and (BP_READ or BP_WRITE)) = 0 then NewFlags := 0;
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
  Refresh(False);
end;

procedure TDebuggerWindow.WriteBytes(Addr: Word; const Values: TBytes);
var
  I, Count, Skipped: Integer;
begin
  // Up to FFFF: it doesn't go round to 0000
  Count := Min(Length(Values), $10000 - Addr);
  Skipped := 0;
  FEmu.Lock;
  try
    for I := 0 to Count - 1 do
      case FEmu.Spec.MemoryAt(Addr + I) of
        maRam: FEmu.Spec.Poke(Addr + I, Values[I]);
        maRom:
          if FEmu.Spec.RomWritable then FEmu.Spec.Poke(Addr + I, Values[I])
          else Inc(Skipped);
      else
        Inc(Skipped);
      end;
  finally
    FEmu.Unlock;
  end;
  Refresh(False);
  if Count < Length(Values) then Beep;
  if Skipped > 0 then
    ShowNotice(Format('Pasted %d bytes at %.4X; %d fell on ROM (or no memory) and were not written',
      [Count, Addr, Skipped]))
  else if Count < Length(Values) then
    ShowNotice(Format('Pasted %d bytes at %.4X; %d more would go past FFFF and were not written',
      [Count, Addr, Length(Values) - Count]))
  else
    ShowNotice(Format('Pasted %d bytes at %.4X', [Count, Addr]));
end;

procedure TDebuggerWindow.AddWatch;
var
  A: Word;
begin
  A := 0;
  if WatchCount > 0 then A := FWatches[High(FWatches)];
  if not AskAddress(A, True) then Exit;
  SetLength(FWatches, Length(FWatches) + 1);
  FWatches[High(FWatches)] := A;
  FWatchView.Invalidate;
end;

procedure TDebuggerWindow.AddWatchAt(Addr: Word);
begin
  SetLength(FWatches, Length(FWatches) + 1);
  FWatches[High(FWatches)] := Addr;
  FWatchView.Invalidate;
end;

procedure TDebuggerWindow.RemoveWatch(Index: Integer);
var
  I: Integer;
begin
  if (Index < 0) or (Index > High(FWatches)) then Exit;
  for I := Index to High(FWatches) - 1 do FWatches[I] := FWatches[I + 1];
  SetLength(FWatches, Length(FWatches) - 1);
  FWatchView.Invalidate;
end;

function TDebuggerWindow.WatchCount: Integer;
begin
  Result := Length(FWatches);
end;

function TDebuggerWindow.Watch(Index: Integer): Word;
begin
  Result := FWatches[Index];
end;

function TDebuggerWindow.SymbolFor(Addr: Word): string;
begin
  Result := UserSymbols.Lookup(Addr);
  if Result = '' then Result := RomLabels.Lookup(Addr, FRomIndex);
end;

function TDebuggerWindow.SymbolsFor(Addr: Word): string;
var
  Rom, One: string;
  P: Integer;
begin
  Result := UserSymbols.LookupAll(Addr);
  Rom := RomLabels.LookupAll(Addr, FRomIndex);
  while Rom <> '' do
  begin
    P := Pos(', ', Rom);
    if P = 0 then P := Length(Rom) + 1;
    One := Copy(Rom, 1, P - 1);
    Delete(Rom, 1, P + 1);
    // A ROM label with the same name as a user one is not repeated
    if Pos(', ' + UpperCase(One) + ', ', ', ' + UpperCase(Result) + ', ') = 0 then
    begin
      if Result <> '' then Result := Result + ', ';
      Result := Result + One;
    end;
  end;
end;

procedure TDebuggerWindow.SetRegister(Reg: TRegId; Value: Word);
var
  Cpu: TZ80;
  P: TZ80Regs;
begin
  FEmu.Lock;
  try
    Cpu := FEmu.Spec.Cpu;
    P := FEmu.Spec.PrevRegs;
    // Changed by hand, not by an instruction: keep it out of the red highlight
    case Reg of
      rAF: begin Cpu.SetAF(Value); P.A := Cpu.A; P.F := Cpu.F; end;
      rHL: begin Cpu.HL.W := Value; P.HL := Value; end;
      rDE: begin Cpu.DE.W := Value; P.DE := Value; end;
      rBC: begin Cpu.BC.W := Value; P.BC := Value; end;
      rAF_: begin Cpu.A_ := Value shr 8; Cpu.F_ := Value and $FF; P.A_ := Cpu.A_; P.F_ := Cpu.F_; end;
      rHL_: begin Cpu.HL_.W := Value; P.HL_ := Value; end;
      rDE_: begin Cpu.DE_.W := Value; P.DE_ := Value; end;
      rBC_: begin Cpu.BC_.W := Value; P.BC_ := Value; end;
      rIX: begin Cpu.IX.W := Value; P.IX := Value; end;
      rIY: begin Cpu.IY.W := Value; P.IY := Value; end;
      rI: begin Cpu.I := Value; P.I := Value; end;
      rBus: Cpu.DataBus := Value;
      rIm2: begin Cpu.I := Value shr 8; P.I := Cpu.I; Cpu.DataBus := Value and $FF; end;
      rR: begin Cpu.R := Value; Cpu.R7 := Value; P.R := Value; end;
      rSP: begin Cpu.SP.W := Value; P.SP := Value; end;
      rPC: begin Cpu.PC.W := Value; P.PC := Value; Cpu.Halted := False; end;
    end;
    FEmu.Spec.PrevRegs := P;
  finally
    FEmu.Unlock;
  end;
  Refresh(Reg = rPC);
end;

procedure TDebuggerWindow.PokeByte(Addr: Word; Value: Byte);
var
  Kind: TMemoryAt;
  Ok: Boolean;
begin
  FEmu.Lock;
  try
    Kind := FEmu.Spec.MemoryAt(Addr);
    Ok := (Kind = maRam) or ((Kind = maRom) and FEmu.Spec.RomWritable);
    if Ok then FEmu.Spec.Poke(Addr, Value);
  finally
    FEmu.Unlock;
  end;
  if Ok then Exit;
  Beep;
  if Kind = maNone then
    ShowNotice(Format('There is no memory at %.4X', [Addr]))
  else
    ShowNotice(Format('%.4X is ROM, which can''t be changed (Options > Settings > Machine ' +
      'can allow it)', [Addr]));
end;

procedure TDebuggerWindow.ShowNotice(const AText: string);
begin
  FNotice := AText;
  FNoticeTime := GetTickCount64;
  SetStatus(AText);
end;

procedure TDebuggerWindow.ToggleFlag(Mask: Byte);
var
  P: TZ80Regs;
begin
  FEmu.Lock;
  try
    FEmu.Spec.Cpu.F := FEmu.Spec.Cpu.F xor Mask;
    P := FEmu.Spec.PrevRegs;
    P.F := P.F xor Mask;
    FEmu.Spec.PrevRegs := P;
  finally
    FEmu.Unlock;
  end;
  Refresh(False);
end;

procedure TDebuggerWindow.ToggleIFF(Which: Integer);
var
  P: TZ80Regs;
begin
  FEmu.Lock;
  try
    P := FEmu.Spec.PrevRegs;
    if Which = 1 then
    begin
      FEmu.Spec.Cpu.IFF1 := not FEmu.Spec.Cpu.IFF1;
      P.IFF1 := FEmu.Spec.Cpu.IFF1;
    end
    else
    begin
      FEmu.Spec.Cpu.IFF2 := not FEmu.Spec.Cpu.IFF2;
      P.IFF2 := FEmu.Spec.Cpu.IFF2;
    end;
    FEmu.Spec.PrevRegs := P;
  finally
    FEmu.Unlock;
  end;
  Refresh(False);
end;

procedure TDebuggerWindow.CycleIM;
var
  P: TZ80Regs;
begin
  FEmu.Lock;
  try
    FEmu.Spec.Cpu.IM := (FEmu.Spec.Cpu.IM + 1) mod 3;
    P := FEmu.Spec.PrevRegs;
    P.IM := FEmu.Spec.Cpu.IM;
    FEmu.Spec.PrevRegs := P;
  finally
    FEmu.Unlock;
  end;
  Refresh(False);
end;

procedure TDebuggerWindow.TakeSnapshot;
var
  A, N: Integer;
  Cpu: TZ80;
  Status: string;
  Paths: array of string;
begin
  FEmu.Lock;
  try
    for A := 0 to $FFFF do
    begin
      FMem[A] := FEmu.Spec.Peek(A);
      FBreak[A] := FEmu.Spec.Breakpoint[A];
    end;
    // Labels for this model's ROMs (only reloaded when the ROMs change)
    SetLength(Paths, FEmu.Spec.Info.RomCount);
    for A := 0 to High(Paths) do Paths[A] := FEmu.Spec.RomPath(A);
    RomLabels.Load(FEmu.Spec.RomDir, FEmu.Spec.Info, Paths);
    FRomIndex := FEmu.Spec.PagedRom;
    // CPC: the upper ROM switched in (1 BASIC, 2 AMSDOS)
    if FEmu.Spec.SlotBank(3) < 0 then RomLabels.UpperRom := -1 - FEmu.Spec.SlotBank(3)
    else RomLabels.UpperRom := 0;
    // The DivMMC's memory hides the ROM: its labels don't apply
    FDivActive := FEmu.Spec.DivMMCOn and FEmu.Spec.DivMMC.Active;
    FDivOn := FEmu.Spec.DivMMCOn or (FEmu.Spec.Model = smZXUno);
    FDivControl := FEmu.Spec.DivMMC.Control;
    FDivMapped := FEmu.Spec.DivMMC.Mapped;
    FUnoOn := FEmu.Spec.Model = smZXUno;
    FNextOn := FEmu.Spec.Model = smZXNext;
    for A := 0 to 7 do FNextMMU[A] := FEmu.Spec.NextMMU(A);
    FUnoConf := FEmu.Spec.ZXUnoRegister(0);
    FUnoMapper := FEmu.Spec.ZXUnoRegister(1);
    FCartButton.Visible := IsMSXModel(FEmu.Spec.Model);
    // Every machine has its chips window (the ZX-Uno's, the Next's, the SAM's and the MSX's ports, the
    // Spectrum's ULA and AY, the CPC's Gate Array, CRTC, PPI and PSG)
    FUnoButton.Visible := True;
    if FEmu.Spec.Info.Memory = mkCPC then
      FUnoButton.Hint := 'CPC chips: the Gate Array (pens, mode, ROMs, RAM), the CRTC, the PPI and the PSG'
    else if not ((FUnoOn) or (FEmu.Spec.Model in [smZXNext, smSAM]) or IsMSXModel(FEmu.Spec.Model)) then
      FUnoButton.Hint := 'Spectrum ports: the ULA (FE), the paging (7FFD, 1FFD), Timex, ULAplus and the AY''s registers'
    else if FEmu.Spec.Model = smZXNext then
      FUnoButton.Hint := 'Next Regs: the ZX Spectrum Next''s registers (MMU, speed, interrupts...)'
    else if IsMSXModel(FEmu.Spec.Model) then
      FUnoButton.Hint := 'MSX Ports: slots, mapper, PPI, PSG and VDP registers and palette'
    else if FEmu.Spec.Model = smSAM then
      FUnoButton.Hint := 'SAM Regs: the SAM Coupe''s ports (paging LMPR and HMPR, video, border, CLUT, sound)'
    else
      FUnoButton.Hint := 'ZXUno Regs: the ZX-Uno''s registers';
    FCurrahPaged := FEmu.Spec.CurrahOn and FEmu.Spec.Currah.Paged;
    if FDivActive or FCurrahPaged then FRomIndex := -1;
    Cpu := FEmu.Spec.Cpu;
    FRegs.A := Cpu.A; FRegs.F := Cpu.F; FRegs.A_ := Cpu.A_; FRegs.F_ := Cpu.F_;
    FRegs.BC := Cpu.BC.W; FRegs.DE := Cpu.DE.W; FRegs.HL := Cpu.HL.W;
    FRegs.BC_ := Cpu.BC_.W; FRegs.DE_ := Cpu.DE_.W; FRegs.HL_ := Cpu.HL_.W;
    FRegs.IX := Cpu.IX.W; FRegs.IY := Cpu.IY.W; FRegs.SP := Cpu.SP.W; FRegs.PC := Cpu.PC.W;
    FRegs.I := Cpu.I; FRegs.R := Cpu.GetR; FRegs.IM := Cpu.IM;
    FRegs.DataBus := Cpu.DataBus;
    FRegs.IFF1 := Cpu.IFF1; FRegs.IFF2 := Cpu.IFF2; FRegs.Halted := Cpu.Halted;
    // Changes are only meaningful while stopped
    FHavePrev := FEmu.Paused and FEmu.Spec.TrackPrevRegs;
    if FHavePrev then
      with FEmu.Spec.PrevRegs do
      begin
        FPrev.A := A; FPrev.F := F; FPrev.A_ := A_; FPrev.F_ := F_;
        FPrev.BC := BC; FPrev.DE := DE; FPrev.HL := HL;
        FPrev.BC_ := BC_; FPrev.DE_ := DE_; FPrev.HL_ := HL_;
        FPrev.IX := IX; FPrev.IY := IY; FPrev.SP := SP; FPrev.PC := PC;
        FPrev.I := I; FPrev.R := R; FPrev.IM := IM;
        FPrev.IFF1 := IFF1; FPrev.IFF2 := IFF2;
      end
    else
      FPrev := FRegs;
    FStep := FEmu.Spec.StepCount;
    if FHavePrev then FPrevPaging := FEmu.Spec.PrevPaging
    else FPrevPaging := FEmu.Spec.PagingState;
    if FEmu.Paused then
    begin
      if FEmu.Spec.BreakReason <> '' then
        Status := 'Stopped: ' + FEmu.Spec.BreakReason
      else
        Status := 'Paused';
    end
    else
      Status := 'Running';
    if UserSymbols.Count > 0 then
      Status := Status + Format('     Symbols: %s (%d)',
        [ExtractFileName(UserSymbols.FileName), UserSymbols.Count]);
    // A recent message (such as "can't change the ROM") stays for a while
    if (FNotice <> '') and (GetTickCount64 - FNoticeTime < 4000) then
      Status := FNotice
    else
      FNotice := '';
    SetStatus(Status);
    // Breakpoint conditions, port log and memory map
    if Length(FCondText) = 0 then SetLength(FCondText, $10000);
    N := 0;
    for A := 0 to $FFFF do
      if FBreak[A] <> 0 then
      begin
        FCondText[A] := FEmu.Spec.BreakCondition(A);
        Inc(N);
      end
      else if FCondText[A] <> '' then FCondText[A] := '';
    if Length(FPortCondText) = 0 then SetLength(FPortCondText, $10000);
    for A := 0 to $FFFF do
    begin
      FPortBreak[A] := FEmu.Spec.PortBreakpoint[A];
      if FPortBreak[A] <> 0 then
      begin
        FPortCondText[A] := FEmu.Spec.PortBreakCondition(A);
        Inc(N);
      end
      else if FPortCondText[A] <> '' then FPortCondText[A] := '';
    end;
    // One entry per breakpoint: a range is one, from its first address
    SetLength(FBreakList, N);
    N := 0;
    A := 0;
    while A <= $FFFF do
    begin
      if FBreak[A] <> 0 then
      begin
        FBreakList[N].Addr := A;
        FBreakList[N].Last := FEmu.Spec.BreakRangeLast(A, False);
        FBreakList[N].Port := False;
        FBreakList[N].Hits := FEmu.Spec.BreakHits(A);
        A := FBreakList[N].Last;
        Inc(N);
      end;
      Inc(A);
    end;
    A := 0;
    while A <= $FFFF do
    begin
      if FPortBreak[A] <> 0 then
      begin
        FBreakList[N].Addr := A;
        FBreakList[N].Last := FEmu.Spec.BreakRangeLast(A, True);
        FBreakList[N].Port := True;
        FBreakList[N].Hits := FEmu.Spec.PortBreakHits(A);
        A := FBreakList[N].Last;
        Inc(N);
      end;
      Inc(A);
    end;
    SetLength(FBreakList, N);
    SetLength(FPortLog, FEmu.Spec.PortLogCount);
    for A := 0 to High(FPortLog) do FPortLog[A] := FEmu.Spec.PortLog(A);
    for A := 0 to 3 do FSlots[A] := FEmu.Spec.SlotBank(A);
    FSlot3OK := not (FEmu.Spec.Info.Memory in [mk48K, mkCPC, mkSAM]) and ((FEmu.Spec.Port1FFD and 1) = 0);
    // Every slot can be changed, as the CPC and the SAM Coupe allow (the SAM's by its paging registers)
    FIsCpc := FEmu.Spec.Info.Memory in [mkCPC, mkSAM];
  finally
    FEmu.Unlock;
  end;
end;

procedure TDebuggerWindow.Refresh(FollowPC: Boolean);
begin
  TakeSnapshot;
  if FollowPC then
  begin
    FDisasm.EnsureVisible(FRegs.PC);
    FDisasm.SelAddr := FRegs.PC;
  end;
  FDisasm.Invalidate;
  FHex.Invalidate;
  FRegView.Invalidate;
  FWatchView.Invalidate;
  FBreakView.Invalidate;
  UpdateRunButtons;
end;

{ Run only makes sense while stopped, Break while running }
procedure TDebuggerWindow.UpdateRunButtons;
begin
  FRunButton.Enabled := FEmu.Paused;
  FBreakButton.Enabled := not FEmu.Paused;
end;

procedure TDebuggerWindow.Tick(Sender: TObject);
var
  Paused: Boolean;
begin
  if not Visible then Exit;
  UpdateRunButtons;
  // Don't repaint under an open inline editor
  if FDisasm.Editing or FHex.Editing or FRegView.Editing or FWatchView.Editing then Exit;
  Paused := FEmu.Paused;
  if Paused and FWasPaused then Exit;   // nothing changes while stopped
  // Follow the execution point when the emulation has just stopped
  Refresh(Paused and not FWasPaused);
  FWasPaused := Paused;
end;

procedure TDebuggerWindow.BreakHit;
begin
  if not Visible then
  begin
    ShowDebugger(FEmu);
    Exit;
  end;
  BringToFront;
  FWasPaused := True;
  Refresh(True);
end;

procedure TDebuggerWindow.ReportBreak;
var
  Kind: TBreakKind;
  Instr: Word;
  Reason: string;
begin
  FEmu.Lock;
  try
    Kind := FEmu.Spec.BreakKind;
    Instr := FEmu.Spec.BreakInstr;
    Reason := FEmu.Spec.BreakReason;
  finally
    FEmu.Unlock;
  end;
  if not (Kind in [bkMemory, bkPort]) then Exit;
  // The access was made by the previous instruction: show and select it
  FDisasm.EnsureVisible(Instr);
  FDisasm.SelAddr := Instr;
  FDisasm.Invalidate;
  if Kind = bkPort then
    MessageDlg('Port breakpoint', 'Stopped by a port breakpoint.' + LineEnding + LineEnding +
      Reason + LineEnding + LineEnding +
      'Execution stopped at the instruction that accesses the port (in green), before it runs.',
      mtInformation, [mbOK], 0);
end;

procedure TDebuggerWindow.XorChange(Sender: TObject);
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
  FHex.XorValue := V;
end;

type
  { Ctrl+G dialog: an edit box plus the list of the last addresses used }
  TAddressDialog = class(TForm)
  public
    Edit: TEdit;
    List: TListBox;
    procedure ListClick(Sender: TObject);
    procedure ListDblClick(Sender: TObject);
  end;

procedure TAddressDialog.ListClick(Sender: TObject);
begin
  if List.ItemIndex >= 0 then Edit.Text := List.Items[List.ItemIndex];
end;

procedure TAddressDialog.ListDblClick(Sender: TObject);
begin
  ListClick(Sender);
  ModalResult := mrOK;
end;

{ Address from text: a register name, a label or a hex number }
function ParseAddress(const Text: string; const R: TRegSnapshot; RomIndex: Integer;
  out Addr: Word): Boolean;
var
  S: string;
  V: Integer;
begin
  S := UpperCase(Trim(Text));
  Result := True;
  // "#NAME" is always a symbol (BC is the register, #BC a symbol called BC)
  if (Length(S) > 1) and (S[1] = '#') and
     (UserSymbols.Find(Copy(S, 2, MaxInt), Addr) or RomLabels.Find(Copy(S, 2, MaxInt), RomIndex, Addr)) then
    Exit;
  if S = 'PC' then Addr := R.PC
  else if S = 'SP' then Addr := R.SP
  else if S = 'HL' then Addr := R.HL
  else if S = 'DE' then Addr := R.DE
  else if S = 'BC' then Addr := R.BC
  else if S = 'IX' then Addr := R.IX
  else if S = 'IY' then Addr := R.IY
  else if UserSymbols.Find(S, Addr) or RomLabels.Find(S, RomIndex, Addr) then
  else if ParseHex(S, V) and (V <= $FFFF) then Addr := V
  else Result := False;
end;

function TDebuggerWindow.AskAddress(var Addr: Word; ForWatch: Boolean): Boolean;
var
  Dlg: TAddressDialog;
  Lbl: TLabel;
  BtnOK, BtnCancel, BtnPC: TButton;
  A: Word;
  Typed: string;
  I: Integer;
  History: TStringList;
begin
  Result := False;
  // Going to an address and watching one: each its own list
  if ForWatch then History := FWatchHistory else History := FHistory;
  Dlg := TAddressDialog.CreateNew(Self, 0);
  try
    if ForWatch then Dlg.Caption := 'Add a watch' else Dlg.Caption := 'Go to address';
    Dlg.BorderStyle := bsDialog;
    Dlg.Position := poOwnerFormCenter;
    Dlg.ClientWidth := 420;
    Dlg.ClientHeight := 330;
    Lbl := TLabel.Create(Dlg);
    Lbl.Parent := Dlg;
    if ForWatch then
      Lbl.Caption := 'Address to watch (hex, a register such as HL, or a label):'
    else
      Lbl.Caption := 'Address (hex, a register such as PC or HL, or a label):';
    Lbl.SetBounds(10, 10, 400, 18);
    Dlg.Edit := TEdit.Create(Dlg);
    Dlg.Edit.Parent := Dlg;
    Dlg.Edit.SetBounds(10, 32, 400, 24);
    Dlg.Edit.Text := IntToHex(Addr, 4);
    Lbl := TLabel.Create(Dlg);
    Lbl.Parent := Dlg;
    if ForWatch then
      Lbl.Caption := 'Last addresses watched (click to use, double-click to add):'
    else
      Lbl.Caption := 'Last addresses (click to use, double-click to go):';
    Lbl.SetBounds(10, 66, 400, 18);
    Dlg.List := TListBox.Create(Dlg);
    Dlg.List.Parent := Dlg;
    Dlg.List.SetBounds(10, 88, 400, 190);
    Dlg.List.Items.Assign(History);   // shared by the disassembly and memory views
    Dlg.List.OnClick := @Dlg.ListClick;
    Dlg.List.OnDblClick := @Dlg.ListDblClick;
    BtnOK := TButton.Create(Dlg);
    BtnOK.Parent := Dlg;
    BtnOK.Caption := 'OK';
    BtnOK.Default := True;
    BtnOK.ModalResult := mrOK;
    BtnOK.SetBounds(250, 290, 75, 28);
    BtnCancel := TButton.Create(Dlg);
    BtnCancel.Parent := Dlg;
    BtnCancel.Caption := 'Cancel';
    BtnCancel.Cancel := True;
    BtnCancel.ModalResult := mrCancel;
    BtnCancel.SetBounds(335, 290, 75, 28);
    // Straight to the execution point, without adding it to the list
    BtnPC := TButton.Create(Dlg);
    BtnPC.Parent := Dlg;
    BtnPC.Caption := 'Go to PC';
    BtnPC.Hint := Format('Go to the execution point (%.4X)', [FRegs.PC]);
    BtnPC.ShowHint := True;
    BtnPC.ModalResult := mrYes;
    BtnPC.SetBounds(10, 290, 100, 28);
    BtnPC.Visible := not ForWatch;
    if ForWatch then BtnOK.Caption := 'Add';
    Dlg.ActiveControl := Dlg.Edit;
    repeat
      case Dlg.ShowModal of
        mrOK: ;
        mrYes:
          begin
            Addr := FRegs.PC;
            Exit(True);
          end;
      else
        Exit;
      end;
      Typed := Trim(Dlg.Edit.Text);
      if ParseAddress(Typed, FRegs, FRomIndex, A) then Break;
      MessageDlg('Not a valid address: ' + Typed, mtError, [mbOK], 0);
    until False;
  finally
    Dlg.Free;
  end;
  // Remember it as an address, most recent first
  Typed := IntToHex(A, 4);
  I := History.IndexOf(Typed);
  if I >= 0 then History.Delete(I);
  History.Insert(0, Typed);
  while History.Count > MAX_HISTORY do History.Delete(History.Count - 1);
  Addr := A;
  Result := True;
end;

{ Commands }

procedure TDebuggerWindow.EnsurePaused;
begin
  if not FEmu.Paused then
  begin
    FEmu.PauseAndWait;
    FWasPaused := True;
    Refresh(True);
  end;
end;

procedure TDebuggerWindow.DoRun(Sender: TObject);
begin
  if FEmu.Paused then FEmu.SaveBackPoint;   // Shift+F7 comes back here
  FEmu.Resume;
  FWasPaused := False;
  Refresh(False);
end;

procedure TDebuggerWindow.DoStepBack(Sender: TObject);
begin
  EnsurePaused;
  if not FEmu.StepBack then
  begin
    Beep;
    ShowNotice('No earlier position to go back to (the last 10 are kept)');
    Exit;
  end;
  FWasPaused := True;
  Refresh(True);
  ShowNotice(Format('Back one step (%d more kept)', [FEmu.BackCount]));
end;

procedure TDebuggerWindow.EditLabel(Addr: Word);
var
  LName: string;
  I: Integer;
  Ok: Boolean;
begin
  LName := UserSymbols.Lookup(Addr);
  repeat
    if not InputQuery('Label', Format('LName for %.4X (letters, digits and _; empty: no label). ' +
      'It is kept when exporting as assembler:', [Addr]), LName) then Exit;
    LName := Trim(LName);
    Ok := True;
    for I := 1 to Length(LName) do
      if not (LName[I] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '.', '?', '!', '@']) then Ok := False;
    if (LName <> '') and (LName[1] in ['0'..'9']) then Ok := False;
    if not Ok then
      MessageDlg('A label has letters, digits, _ . ? ! and @, and doesn''t start with a digit.',
        mtError, [mbOK], 0);
  until Ok;
  UserSymbols.SetName(Addr, LName);
  Refresh(False);
end;

procedure TDebuggerWindow.DoBreak(Sender: TObject);
begin
  EnsurePaused;
end;

procedure TDebuggerWindow.DoStepInto(Sender: TObject);
begin
  if not FEmu.Paused then
  begin
    EnsurePaused;   // first press stops; further presses step
    Exit;
  end;
  FEmu.StepInto;
  Refresh(True);
end;

procedure TDebuggerWindow.DoStepOver(Sender: TObject);
begin
  if not FEmu.Paused then
  begin
    EnsurePaused;
    Exit;
  end;
  FEmu.StepOver;
  if FEmu.Paused then Refresh(True) else FWasPaused := False;
end;

procedure TDebuggerWindow.DoRunToCursor(Sender: TObject);
begin
  RunToAddr(FDisasm.SelAddr);
end;

procedure TDebuggerWindow.RunToAddr(Addr: Word);
begin
  EnsurePaused;
  FEmu.RunTo(Addr);
  FWasPaused := False;
end;

{ Run until the subroutine returns: to the address on the top of the stack (as the C64 debugger's) }
procedure TDebuggerWindow.DoStepOut(Sender: TObject);
var
  Ret: Word;
begin
  EnsurePaused;
  Ret := Peek(FRegs.SP) or (Peek(Word(FRegs.SP + 1)) shl 8);
  RunToAddr(Ret);
end;

procedure TDebuggerWindow.SetPCAt(Addr: Word);
begin
  EnsurePaused;
  SetRegister(rPC, Addr);
  Refresh(True);
end;

procedure TDebuggerWindow.DoLoadSymbols(Sender: TObject);
begin
  if Assigned(DebugLoadSymbols) then DebugLoadSymbols(Self);
  Refresh(False);
end;

procedure TDebuggerWindow.DoCondition(Sender: TObject);
begin
  EditCondition(FDisasm.SelAddr);
end;

function TDebuggerWindow.BreakCount: Integer;
begin
  Result := Length(FBreakList);
end;

function TDebuggerWindow.BreakAt(Index: Integer): TBreakEntry;
begin
  Result := FBreakList[Index];
end;

function TDebuggerWindow.EntryFlags(const E: TBreakEntry): Byte;
begin
  if E.Port then Result := FPortBreak[E.Addr] else Result := FBreak[E.Addr];
end;

function TDebuggerWindow.EntryCondition(const E: TBreakEntry): string;
begin
  if not E.Port then Result := ConditionText(E.Addr)
  else if Length(FPortCondText) > 0 then Result := FPortCondText[E.Addr]
  else Result := '';
end;

procedure TDebuggerWindow.RemoveEntry(const E: TBreakEntry);
begin
  FEmu.Lock;
  try
    if E.Port then FEmu.Spec.PortBreakpoint[E.Addr] := 0
    else FEmu.Spec.Breakpoint[E.Addr] := 0;
  finally
    FEmu.Unlock;
  end;
  Refresh(False);
end;

procedure TDebuggerWindow.ToggleBreakEnabled(Addr: Word; Port: Boolean);
begin
  FEmu.Lock;
  try
    if Port then
    begin
      if FEmu.Spec.PortBreakpoint[Addr] <> 0 then
        FEmu.Spec.PortBreakpoint[Addr] := FEmu.Spec.PortBreakpoint[Addr] xor BP_DISABLED;
    end
    else if FEmu.Spec.Breakpoint[Addr] <> 0 then
      FEmu.Spec.Breakpoint[Addr] := FEmu.Spec.Breakpoint[Addr] xor BP_DISABLED;
  finally
    FEmu.Unlock;
  end;
  Refresh(False);
end;

procedure TDebuggerWindow.GoToCode(Addr: Word);
begin
  FDisasm.GoToAddr(Addr);
  FDisasm.SetFocus;
end;

procedure TDebuggerWindow.DoToggleBreakpoint(Sender: TObject);
begin
  if BreakFlags(FDisasm.SelAddr) <> 0 then SetBreak(FDisasm.SelAddr, 0)
  else SetBreak(FDisasm.SelAddr, BP_EXEC);
  Refresh(False);
end;

procedure TDebuggerWindow.DoClearBreakpoints(Sender: TObject);
begin
  ClearBreakpoints;
end;

procedure TDebuggerWindow.SaveBreaksAs;
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

procedure TDebuggerWindow.LoadBreaksAsk;
var
  Dlg: TOpenDialog;
  Error: string;
  Ok: Boolean;
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
    Refresh(False);
    if Ok then ShowNotice('Breakpoints loaded from ' + ExtractFileName(Dlg.FileName))
    else MessageDlg('Could not load the breakpoints: ' + Error, mtError, [mbOK], 0);
  finally
    Dlg.Free;
  end;
end;

procedure TDebuggerWindow.SaveWatchesAs;
var
  Dlg: TSaveDialog;
begin
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := 'Watches (*.json)|*.json|All files|*.*';
    Dlg.DefaultExt := 'json';
    Dlg.FileName := 'watches.json';
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    if not Dlg.Execute then Exit;
    try
      SaveWatches(FWatches, Dlg.FileName);
      ShowNotice('Watches saved to ' + ExtractFileName(Dlg.FileName));
    except
      on E: Exception do MessageDlg('Could not save: ' + E.Message, mtError, [mbOK], 0);
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TDebuggerWindow.LoadWatchesAsk;
var
  Dlg: TOpenDialog;
  Error: string;
  W: TWordArray;
begin
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Filter := 'Watches (*.json)|*.json|All files|*.*';
    Dlg.Options := Dlg.Options + [ofFileMustExist];
    if not Dlg.Execute then Exit;
    if LoadWatches(Dlg.FileName, W, Error) then
    begin
      SetWatches(W);
      ShowNotice('Watches loaded from ' + ExtractFileName(Dlg.FileName));
    end
    else
      MessageDlg('Could not load the watches: ' + Error, mtError, [mbOK], 0);
  finally
    Dlg.Free;
  end;
end;

procedure TDebuggerWindow.SetWatches(const Watches: TWordArray);
begin
  FWatches := Copy(Watches);
  Refresh(False);
end;

procedure TDebuggerWindow.ClearBreakpoints;
begin
  FEmu.Lock;
  try
    FEmu.Spec.ClearBreakpoints;
  finally
    FEmu.Unlock;
  end;
  Refresh(False);
end;

{ A register edited in the ports window (the SAM's LMPR or HMPR, the ZX-Uno's MMU...) changes what
  the CPU sees: read it all again }
procedure TDebuggerWindow.RegsChanged(Sender: TObject);
begin
  Refresh(False);
end;

procedure TDebuggerWindow.DoCartBrowser(Sender: TObject);
begin
  if IsMSXModel(FEmu.Spec.Model) then ShowCartBrowser(FEmu);
end;

procedure TDebuggerWindow.DoUnoRegs(Sender: TObject);
begin
  if FUnoRegs = nil then
  begin
    FUnoRegs := TZXUnoRegsWindow.CreateFor(Self, FEmu);
    FUnoRegs.OnChanged := @RegsChanged;
  end;
  FUnoRegs.UpdateValues;
  FUnoRegs.Show;
  FUnoRegs.BringToFront;
end;

procedure TDebuggerWindow.DoZ80Opcodes(Sender: TObject);
begin
  ShowZ80Opcodes;
end;

procedure TDebuggerWindow.DoAddWatch(Sender: TObject);
begin
  AddWatch;
end;

procedure TDebuggerWindow.DoGoTo(Sender: TObject);
var
  A: Word;
begin
  A := FDisasm.SelAddr;
  if AskAddress(A) then FDisasm.GoToAddr(A);
end;

procedure TDebuggerWindow.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  // Escape closes the window, unless it ends an edit or the typing in the
  // memory zone first
  if Key = VK_ESCAPE then
  begin
    if FDisasm.Editing or FHex.Editing or FRegView.Editing or FWatchView.Editing or
       FBreakView.Editing then Exit;
    if not FHex.CancelTyping then Close;
    Key := 0;
    Exit;
  end;
  // F3: the next match in the zone with the focus
  if Key = VK_F3 then
  begin
    if FHex.Focused then FHex.SearchNext
    else if FDisasm.Focused then FDisasm.SearchNext;
    Key := 0;
    Exit;
  end;
  case Key of
    VK_F5: DoRun(Self);
    VK_F7: if ssShift in Shift then DoStepBack(Self) else DoStepInto(Self);
    VK_F8: DoToggleBreakpoint(Self);
    VK_F9: DoRunToCursor(Self);
    VK_F10: DoStepOver(Self);
    VK_F11: DoStepOut(Self);
  else
    Exit;
  end;
  Key := 0;
end;

procedure TDebuggerWindow.EditBreakpoint(OldAddr: Integer; OldPort: Boolean);
const
  // Type list: flags and whether it is a port breakpoint
  TYPE_FLAGS: array[0..6] of Byte = (BP_EXEC, BP_READ, BP_WRITE, BP_READ or BP_WRITE,
    BP_READ, BP_WRITE, BP_READ or BP_WRITE);
  TYPE_PORT: array[0..6] of Boolean = (False, False, False, False, True, True, True);
var
  Dlg: TForm;
  AddrEdit, EndEdit, CondEdit: TEdit;
  TypeCombo: TComboBox;
  EnabledCheck: TCheckBox;
  Help: TMemo;
  Btn: TButton;
  Flags: Byte;
  A, Last: Word;
  V, I: Integer;
  Error: string;
  Ok, Port: Boolean;
  Follower: TEndFollower;
  Test: TBreakCondition;

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
  Flags := BP_EXEC;
  if OldAddr >= 0 then
  begin
    if OldPort then Flags := FPortBreak[OldAddr] else Flags := FBreak[OldAddr];
  end;
  Follower := TEndFollower.Create;
  Dlg := TForm.CreateNew(Self, 0);
  try
    if OldAddr >= 0 then Dlg.Caption := 'Edit breakpoint' else Dlg.Caption := 'Add breakpoint';
    Dlg.BorderStyle := bsDialog;
    Dlg.Position := poOwnerFormCenter;
    Dlg.ClientWidth := 580;
    Dlg.ClientHeight := 560;
    AddLabel('Address or port:', 10);
    // Columns wide enough for their titles: the end's doesn't reach Type
    AddLabel('End address or port:', 10, 150);
    AddLabel('Type:', 10, 320);
    AddrEdit := TEdit.Create(Dlg);
    AddrEdit.Parent := Dlg;
    AddrEdit.SetBounds(10, 30, 130, 24);
    if OldAddr >= 0 then AddrEdit.Text := IntToHex(OldAddr, 4)
    else if OldAddr = -2 then AddrEdit.Text := 'FE'       // new port breakpoint
    else AddrEdit.Text := IntToHex(FDisasm.SelAddr, 4);
    // The end: the same as the start (one address) until it is changed
    EndEdit := TEdit.Create(Dlg);
    EndEdit.Parent := Dlg;
    EndEdit.SetBounds(150, 30, 130, 24);
    EndEdit.Text := AddrEdit.Text;
    if OldAddr >= 0 then
    begin
      Last := FEmu.Spec.BreakRangeLast(OldAddr, OldPort);
      if Last <> OldAddr then EndEdit.Text := IntToHex(Last, 4);
    end;
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
    TypeCombo.Items.Add('Port read (IN)');
    TypeCombo.Items.Add('Port write (OUT)');
    TypeCombo.Items.Add('Port read or write (any)');
    TypeCombo.ItemIndex := 0;
    if OldAddr = -2 then TypeCombo.ItemIndex := 4;
    for I := 0 to 6 do
      if (OldAddr >= 0) and (TYPE_PORT[I] = OldPort) and
         (TYPE_FLAGS[I] = Flags and (BP_EXEC or BP_READ or BP_WRITE)) then
        TypeCombo.ItemIndex := I;
    AddLabel('Hex; addresses may also be a register or a label. A different end makes', 60);
    AddLabel('one breakpoint over the whole range. A port up to FF matches any high byte.', 76);
    AddLabel('Condition (empty = always stop; see below):', 102);
    CondEdit := TEdit.Create(Dlg);
    CondEdit.Parent := Dlg;
    CondEdit.SetBounds(10, 122, 560, 24);
    if OldAddr >= 0 then
    begin
      if OldPort then CondEdit.Text := FPortCondText[OldAddr]
      else CondEdit.Text := ConditionText(OldAddr);
    end;
    EnabledCheck := TCheckBox.Create(Dlg);
    EnabledCheck.Parent := Dlg;
    EnabledCheck.Caption := 'Enabled';
    EnabledCheck.SetBounds(10, 152, 200, 24);
    EnabledCheck.Checked := (Flags and BP_DISABLED) = 0;
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
      '  BC=289A AND #Z=1' + LineEnding +
      '  HL>=C000 AND HL<C100' + LineEnding +
      '  A = B * 2' + LineEnding +
      '  BC = DE + HL' + LineEnding +
      '  A = C & 7' + LineEnding +
      '  A=@8400' + LineEnding +
      '  @(IX+2) = .30' + LineEnding +
      '  HL = SCREEN_START' + LineEnding +
      '  A=0A OR A=0F' + LineEnding +
      '  T=5' + LineEnding +
      '  T>=2 AND A=0' + LineEnding +
      '  NOT (#C=1)' + LineEnding + LineEnding +
      'CONDITIONS SYNTAX' + LineEnding +
      'The breakpoint stops only when its condition is true.' + LineEnding +
      'Empty condition = always stop.' + LineEnding + LineEnding +
      'Numbers are hex: 10 is sixteen, FF, $FF and FFh are 255.' + LineEnding +
      'With a dot they are decimal: .30 is thirty.' + LineEnding + LineEnding +
      'Registers (upper or lower case):' + LineEnding +
      '  8 bits:  A B C D E F H L I R IXH IXL IYH IYL' + LineEnding +
      '  16 bits: AF BC DE HL IX IY SP PC' + LineEnding +
      '  alternate set: A'' F'' AF'' BC'' DE'' HL''' + LineEnding +
      '  interrupts: IFF1 IFF2 (0 or 1), IM (0, 1, 2)' + LineEnding + LineEnding +
      'A name is first a register, then a symbol (yours, then' + LineEnding +
      'the ROM labels), then a hex number:' + LineEnding +
      '  A B C D E F alone are registers: write 0A 0B 0C 0D 0E' + LineEnding +
      '  0F for the numbers (A=0A means A is 10). A leading 0' + LineEnding +
      '  always makes a number: 0ADD, 0CAFE.' + LineEnding +
      '  #name is always the symbol: BC is the register, #BC' + LineEnding +
      '  the symbol BC; #main.loop for names with dots.' + LineEnding +
      '  Symbols are looked up when the condition is set.' + LineEnding + LineEnding +
      'Flags (0 or 1): #S #Z #5 #H #3 #P (#V) #N #C' + LineEnding + LineEnding +
      '@x is the byte in memory at address x: @8400, @HL,' + LineEnding +
      '  @(IX+2), @#VAR.' + LineEnding + LineEnding +
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
      '  &             bitwise and: C & 7 keeps bits 0-2' + LineEnding +
      '  - @           negative, memory byte (prefixes)' + LineEnding +
      '  ( )           group' + LineEnding +
      'AND/OR/XOR/NOT combine true/false; & and | work on the' + LineEnding +
      'bits of a value: "A = C & 7" is not "A = C AND 7".' + LineEnding + LineEnding +
      'Arithmetic wraps like the Z80: at 8 bits when both sides' + LineEnding +
      'are 8-bit values (8-bit registers, flags, @x, numbers up' + LineEnding +
      'to FF), at 16 bits otherwise. A-1 with A=0 is FF; DE+1' + LineEnding +
      'with DE=FFFF is 0.' + LineEnding + LineEnding +
      'Memory and port conditions are checked just before the' + LineEnding +
      'instruction runs, with the registers as they are then.';
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
    repeat
      if Dlg.ShowModal <> mrOK then Exit;
      Port := TYPE_PORT[TypeCombo.ItemIndex];
      if Port then
      begin
        Ok := ParseHex(AddrEdit.Text, V) and (V <= $FFFF);
        A := V;
        if Ok then
        begin
          Ok := ParseHex(EndEdit.Text, V) and (V <= $FFFF);
          Last := V;
        end;
      end
      else
        Ok := ParseAddress(AddrEdit.Text, FRegs, FRomIndex, A) and
          ParseAddress(EndEdit.Text, FRegs, FRomIndex, Last);
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
      // Check the condition before changing anything
      if Trim(CondEdit.Text) <> '' then
      begin
        Test := CompileCondition(CondEdit.Text, Error);
        if Test = nil then
        begin
          MessageDlg('Invalid condition: ' + Error, mtError, [mbOK], 0);
          Ok := False;
          Continue;
        end;
        Test.Free;
      end;
      Flags := TYPE_FLAGS[TypeCombo.ItemIndex];
      if not EnabledCheck.Checked then Flags := Flags or BP_DISABLED;
      FEmu.Lock;
      try
        // The old one (all of its range) goes, then the new one is set
        if OldAddr >= 0 then
        begin
          if OldPort then FEmu.Spec.PortBreakpoint[OldAddr] := 0
          else FEmu.Spec.Breakpoint[OldAddr] := 0;
        end;
        FEmu.Spec.SetBreakRange(A, Last, Port);
        if Port then
        begin
          Ok := FEmu.Spec.SetPortBreakCondition(A, CondEdit.Text, Error);
          if Ok then FEmu.Spec.PortBreakpoint[A] := Flags;
        end
        else
        begin
          Ok := FEmu.Spec.SetBreakCondition(A, CondEdit.Text, Error);
          if Ok then FEmu.Spec.Breakpoint[A] := Flags;
        end;
      finally
        FEmu.Unlock;
      end;
      if not Ok then MessageDlg('Invalid condition: ' + Error, mtError, [mbOK], 0);
    until Ok;
  finally
    Dlg.Free;
    Follower.Free;
  end;
  Refresh(False);
end;

function TDebuggerWindow.AskRange(const ACaption: string; var Addr: Word;
  var Len: Integer): Boolean;
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
  Dlg := TForm.CreateNew(Self, 0);
  try
    Dlg.Caption := ACaption;
    Dlg.BorderStyle := bsDialog;
    Dlg.Position := poOwnerFormCenter;
    Dlg.ClientWidth := 300;
    Dlg.ClientHeight := 130;
    AddrEdit := AddEdit('Address (hex or label):', IntToHex(Addr, 4), 12);
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
    repeat
      if Dlg.ShowModal <> mrOK then Exit;
      if not ParseAddress(AddrEdit.Text, FRegs, FRomIndex, A) then
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

procedure TDebuggerWindow.ExportMemory;
var
  Addr: Word;
  Len, I: Integer;
  Dlg: TSaveDialog;
  Lines: TStringList;
  Data: TBytes;
begin
  Addr := FHex.TopAddr;
  Len := FHex.VisibleBytes;
  if not AskRange('Export memory', Addr, Len) then Exit;
  Dlg := TSaveDialog.Create(Self);
  Lines := TStringList.Create;
  try
    Dlg.Filter := 'Text files (*.txt)|*.txt|All files|*.*';
    Dlg.DefaultExt := 'txt';
    Dlg.FileName := Format('mem_%.4X_%.4X.txt', [Addr, Len]);
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    if not Dlg.Execute then Exit;
    // "$3E,$01,...": 16 values per line
    SetLength(Data, Len);
    FEmu.Lock;
    try
      for I := 0 to Len - 1 do Data[I] := FEmu.Spec.Peek(Word(Addr + I));
    finally
      FEmu.Unlock;
    end;
    Lines.Text := FormatValues(Data);
    try
      Lines.SaveToFile(Dlg.FileName);
      ShowNotice(Format('Exported %d bytes from %.4X to %s',
        [Len, Addr, ExtractFileName(Dlg.FileName)]));
    except
      on E: Exception do MessageDlg('Could not save: ' + E.Message, mtError, [mbOK], 0);
    end;
  finally
    Lines.Free;
    Dlg.Free;
  end;
end;

function TDebuggerWindow.AsmLabel(Addr: Word; Kind: TOperandKind): string;
begin
  // Plain values only get user symbols, as in the disassembly
  if Kind = okImmediate then Result := UserSymbols.Lookup(Addr)
  else Result := SymbolFor(Addr);
end;

procedure TDebuggerWindow.ExportAssembler(Start: Word);
var
  Addr: Word;
  Len: Integer;
  Dlg: TSaveDialog;
  Lines: TStringList;
begin
  Addr := Start;
  Len := $100;
  if not AskRange('Export as assembler', Addr, Len) then Exit;
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := 'Assembler source (*.asm)|*.asm|All files|*.*';
    Dlg.DefaultExt := 'asm';
    Dlg.FileName := Format('code_%.4X.asm', [Addr]);
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    if not Dlg.Execute then Exit;
    // From the memory as the debugger shows it (taken when it stopped)
    Lines := AsmExport.ExportAsm(Addr, Len, @Peek, @AsmLabel);
    try
      try
        Lines.SaveToFile(Dlg.FileName);
        ShowNotice(Format('Exported %.4X-%.4X as assembler to %s',
          [Addr, Word(Addr + Len - 1), ExtractFileName(Dlg.FileName)]));
      except
        on E: Exception do MessageDlg('Could not save: ' + E.Message, mtError, [mbOK], 0);
      end;
    finally
      Lines.Free;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TDebuggerWindow.ExportBinary;
var
  Addr: Word;
  Len, I: Integer;
  Dlg: TSaveDialog;
  Data: TBytes;
  F: TFileStream;
begin
  Addr := FHex.TopAddr;
  Len := FHex.VisibleBytes;
  if not AskRange('Export binary', Addr, Len) then Exit;
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := 'Binary files (*.bin)|*.bin|All files|*.*';
    Dlg.DefaultExt := 'bin';
    Dlg.FileName := Format('mem_%.4X_%.4X.bin', [Addr, Len]);
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    if not Dlg.Execute then Exit;
    // As the CPU sees memory, wrapping at FFFF like it (as Export text)
    SetLength(Data, Len);
    FEmu.Lock;
    try
      for I := 0 to Len - 1 do Data[I] := FEmu.Spec.Peek(Word(Addr + I));
    finally
      FEmu.Unlock;
    end;
    try
      F := TFileStream.Create(Dlg.FileName, fmCreate);
      try
        F.WriteBuffer(Data[0], Len);
      finally
        F.Free;
      end;
      ShowNotice(Format('Exported %d bytes from %.4X to %s', [Len, Addr, ExtractFileName(Dlg.FileName)]));
    except
      on E: Exception do MessageDlg('Could not save: ' + E.Message, mtError, [mbOK], 0);
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TDebuggerWindow.AppHint(Sender: TObject);
begin
  if Active and (Application.Hint <> '') then SetStatus(Application.Hint);
end;

procedure TDebuggerWindow.ImportBinary;
var
  Addr: Word;
  AddrText, Msg: string;
  Dlg: TOpenDialog;
  F: TFileStream;
  Data: TBytes;
  I, N, Rom, NoMem, Past: Integer;
begin
  AddrText := IntToHex(FHex.TopAddr, 4);
  repeat
    if not InputQuery('Import binary', 'Load at address (hex or label):', AddrText) then Exit;
    if ParseAddress(AddrText, FRegs, FRomIndex, Addr) then Break;
    MessageDlg('Not a valid address: ' + AddrText, mtError, [mbOK], 0);
  until False;
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
  // Up to FFFF: what goes past it is not loaded (no wrapping to 0000)
  N := Min(Length(Data), $10000 - Addr);
  Past := Length(Data) - N;
  Rom := 0;
  NoMem := 0;
  FEmu.Lock;
  try
    for I := 0 to N - 1 do
      case FEmu.Spec.MemoryAt(Word(Addr + I)) of
        maRam: FEmu.Spec.Poke(Word(Addr + I), Data[I]);
        maRom:
          // ROM only with Options > Settings > Machine allowing it
          if FEmu.Spec.RomWritable then FEmu.Spec.Poke(Word(Addr + I), Data[I])
          else Inc(Rom);
      else
        Inc(NoMem);
      end;
  finally
    FEmu.Unlock;
  end;
  Refresh(False);
  Msg := '';
  if Past > 0 then
    Msg := Msg + Format('The file has %d bytes: the last %d went past FFFF and were not ' +
      'loaded.', [Length(Data), Past]) + LineEnding;
  if Rom > 0 then
    Msg := Msg + Format('%d bytes fell on ROM and were not written (Options > Settings > ' +
      'Machine can allow changing the ROM).', [Rom]) + LineEnding;
  if NoMem > 0 then
    Msg := Msg + Format('%d bytes fell where there is no memory.', [NoMem]) + LineEnding;
  if Msg <> '' then MessageDlg('Import binary', Msg, mtWarning, [mbOK], 0)
  else ShowNotice(Format('Loaded %d bytes at %.4X-%.4X', [N, Addr, Word(Addr + N - 1)]));
end;

procedure TDebuggerWindow.ImportMemory;
var
  Addr: Word;
  Len, I, Skipped: Integer;
  Dlg: TOpenDialog;
  Values: TBytes;
  Error: string;
  Lines: TStringList;
  Ok: Boolean;
begin
  Addr := FHex.TopAddr;
  Len := FHex.VisibleBytes;
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
      if not Ok then
      begin
        MessageDlg('Import failed: ' + Error + '.', mtError, [mbOK], 0);
        Exit;
      end;
    except
      on E: Exception do
      begin
        MessageDlg('Import failed: ' + E.Message, mtError, [mbOK], 0);
        Exit;
      end;
    end;
    if Length(Values) < Len then
    begin
      MessageDlg(Format('Import failed: the file has %d values and %d are needed.',
        [Length(Values), Len]), mtError, [mbOK], 0);
      Exit;
    end;
    Skipped := 0;
    FEmu.Lock;
    try
      for I := 0 to Len - 1 do
      begin
        case FEmu.Spec.MemoryAt(Word(Addr + I)) of
          maRam: FEmu.Spec.Poke(Word(Addr + I), Values[I]);
          maRom:
            if FEmu.Spec.RomWritable then FEmu.Spec.Poke(Word(Addr + I), Values[I])
            else Inc(Skipped);
        else
          Inc(Skipped);
        end;
      end;
    finally
      FEmu.Unlock;
    end;
    Refresh(False);
    if Skipped > 0 then
      MessageDlg(Format('%d of the %d bytes fell on ROM (or no memory) and were not written.',
        [Skipped, Len]), mtWarning, [mbOK], 0)
    else
      ShowNotice(Format('Imported %d bytes at %.4X from %s',
        [Len, Addr, ExtractFileName(Dlg.FileName)]));
  finally
    Dlg.Free;
  end;
end;

procedure TDebuggerWindow.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  CloseAction := caHide;
  FEmu.Lock;
  try
    FEmu.Spec.TrackPrevRegs := False;
  finally
    FEmu.Unlock;
  end;
  // Closing the debugger carries on running, like Run (F5)
  if FEmu.Paused then FEmu.Resume;
  // The keys go to the main window again
  Application.QueueAsyncCall(@FocusMainWindow, 0);
end;

procedure TDebuggerWindow.FocusMainWindow(Data: PtrInt);
begin
  if (Application.MainForm <> nil) and Application.MainForm.CanFocus then
  begin
    Application.MainForm.BringToFront;
    Application.MainForm.SetFocus;
  end;
end;

end.

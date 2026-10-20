{ DaadForm: the Adventure Debugger, a non-modal window that follows a DAAD,
  PAW or Quill game condact by condact (PAW is DAAD's predecessor and The
  Quill PAW's: much the same structures, their own condacts; The Quill's
  flags are fewer, with the object locations right after them).

  The game's database (DDB, usually at 8400) says where every condact of every
  process is; the machine stops when the interpreter reads the opcode of
  one (TSpectrum.SetDaadMap), whatever the interpreter (48K or 128K,
  English or Spanish). At that point IX points at the 256 flags, and the
  objects' locations follow them (IX+256).

  Zones: the current process (entries and condacts, the green arrow on the
  condact about to run, breakpoints in red), the breakpoints (with
  conditions on flags: "f0 = 3 AND f10>11"), the flags (value and, after
  "@", the value of the flag it points at) and the objects' locations.
  Values are decimal and can be changed by clicking them; flags holding
  vocabulary words (fVerb, fNoun...) show the word and offer a list. }
unit DaadForm;

{$mode objfpc}{$H+}
{$R-}{$Q-}

interface

uses
  Classes, SysUtils, Types, Math, Forms, Controls, Graphics, StdCtrls, ExtCtrls, ComCtrls,
  LCLType, Dialogs, Menus, StrUtils, Emulator, Spectrum, Daad, Icons, DaadExport, DebugFiles,
  DelayHint, DaadHelp;

type
  TDaadWindow = class;

  { A scrolling list of text lines drawn by its owner }
  TDaadView = class(TCustomControl)
  protected
    FOwnerWin: TDaadWindow;
    FLineH, FCharW: Integer;
    FTop: Integer;
    FScroll: TScrollBar;
    FBoldFont: TFont;
    FEditor: TEdit;
    FCombo: TComboBox;      // editor with a list (vocabulary words)
    FEditTarget: Integer;   // what is being edited (meaning depends on the view)
    procedure MeasureFont;
    function VisibleLines: Integer;
    function LineCount: Integer; virtual; abstract;
    procedure ScrollTo(Line: Integer);
    procedure ScrollChange(Sender: TObject);
    function DrawText(X, Y: Integer; const S: string; AColor: TColor; Bold: Boolean): Integer;
    procedure BeginEdit(Line, Col, Chars, Value, Target: Integer);
    { Edit with a list of "number text" items to choose from }
    procedure BeginComboEdit(Line, Col, Value, Target: Integer; const Items: TStringArray);
    procedure ComboSelect(Sender: TObject);
    procedure EditorKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure EditorExit(Sender: TObject);
    procedure EndEdit(Commit: Boolean);
    procedure Commit(Target, Value: Integer); virtual;
    procedure Resize; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor CreateView(AOwner: TDaadWindow);
    destructor Destroy; override;
    procedure UpdateScroll;
    procedure EnsureVisible(Line: Integer);
    function Editing: Boolean;
  end;

  { The entries and condacts of one process }
  TDaadCodeView = class(TDaadView)
  private
    FLines: array of Integer;   // condact index, or -1 - entry index for an entry's line
    FSel: Integer;              // selected line, -1 if none
    FMenu: TPopupMenu;
    FEnabledItem, FRemoveItem, FToggleItem, FConditionItem: TMenuItem;
    FDefaultHint: string;
    FSearch: string;            // the text searched last
    function SelCondact: Integer;
    function LineText(L: Integer): string;
    procedure MenuClick(Sender: TObject);
    { The state of a condition (CondactState) as a tick, cross or "?" }
    procedure DrawState(X, Y, State: Integer);
  protected
    function LineCount: Integer; override;
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure DblClick; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor CreateView(AOwner: TDaadWindow);
    procedure Build;
    function LineOfCondact(C: Integer): Integer;
    procedure SelectCondact(C: Integer);
    { Ask for a text and find it in the process; F3 finds the next one }
    procedure Search;
    procedure SearchNext;
  end;

  { The breakpoints }
  TDaadBreakView = class(TDaadView)
  private
    FSel: Integer;
    FMenu: TPopupMenu;
    FEnabledItem: TMenuItem;
    procedure MenuClick(Sender: TObject);
  protected
    function LineCount: Integer; override;
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DblClick; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor CreateView(AOwner: TDaadWindow);
  end;

  { The flags, or the objects' locations }
  TDaadDataView = class(TDaadView)
  private
    FObjects: Boolean;
    FDefaultHint: string;
    { Flags or objects shown, in as many columns as fit (each ColChars wide):
      down the first column, then the next }
    function ItemCount: Integer;
    function ColChars: Integer;
    function Columns: Integer;
    { The item under (X, Y), -1 if none; Col: the character within it }
    function ItemAt(X, Y: Integer; out Row, Col, Base: Integer): Integer;
    { Changed by the last condact run (with Step) }
    function Changed(N: Integer): Boolean;
  protected
    function LineCount: Integer; override;
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure Commit(Target, Value: Integer); override;
  end;

  { A breakpoint on a condact, with its condition on flags }
  TDaadBreakEntry = record
    Addr: Word;
    Enabled: Boolean;
    CondText: string;
    Cond: TDaadCondition;   // nil: always
  end;

  TDaadWindow = class(TForm)
  private
    FEmu: TEmulator;
    FGame: TDaadGame;
    FMem: TDaadMemory;
    FMap: array[0..$FFFF] of Byte;
    FFlags: array[0..511] of Byte;   // the flags, then the objects' locations
    FPrevFlags: array[0..511] of Byte;   // as they were before the last step
    FShowChanges: Boolean;           // stopped by Step: changes are shown in red
    FStepping: Boolean;              // Step pressed: the next stop shows changes
    FUser: Integer;                  // address of the flags (IX), -1 until known
    FCurrent: Integer;               // condact about to run, -1 if none
    FAtBreak: Boolean;               // stopped by a breakpoint
    FProcess: Integer;               // process shown
    FWasPaused: Boolean;
    FTicks: Integer;
    FImages: TImageList;
    FToolbar: TToolBar;
    FRunButton, FBreakButton: TToolButton;
    FProcessBox: TComboBox;
    FEngineLabel: TLabel;            // PAW, DAAD or Quill
    FAfterInput: TCheckBox;
    FCode: TDaadCodeView;
    FBreakView: TDaadBreakView;
    FBreaks: array of TDaadBreakEntry;
    FFlagView, FObjView: TDaadDataView;
    FStatusBar: TStatusBar;
    FTimer: TTimer;
    FDataPanel, FObjZone: TPanel;
    FSplitMoved: Boolean;            // the user placed the splitter: keep it
    procedure FormResize(Sender: TObject);
    procedure SplitMoved(Sender: TObject);
    function AddButton(AIcon: TIconKind; const AHint: string; AHandler: TNotifyEvent): TToolButton;
    function MakeZone(AParent: TWinControl; const ACaption: string; AWidth: Integer;
      AAlign: TAlign): TPanel;
    { Read the database again; False if there is no game }
    function LoadGame: Boolean;
    procedure ReadFlags;
    procedure ShowProcess(P: Integer);
    procedure ProcessChange(Sender: TObject);
    procedure UpdateStatus;
    procedure UpdateRunButtons;
    procedure Tick(Sender: TObject);
    procedure DoRun(Sender: TObject);
    procedure DoExportProcess(Sender: TObject);
    procedure DoExportSource(Sender: TObject);
    { Ask for a .dsf or .sce file; Sce: which one it is }
    function AskSourceFile(const ADefault: string; out FileName: string; out Sce: Boolean): Boolean;
    { PAW game to DSF: as a PAW game, or converted to DAAD (ToDaad); False if
      cancelled }
    function AskPawMode(Sce: Boolean; out ToDaad: Boolean): Boolean;
    procedure ConvertedNotice;
    procedure DoBreak(Sender: TObject);
    procedure DoStep(Sender: TObject);
    procedure DoStepOver(Sender: TObject);
    procedure AfterInputClick(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FocusMainWindow(Data: PtrInt);
    { Give the emulation the enabled breakpoints }
    function AnyEditing: Boolean;
  public
    { Give the emulation the enabled breakpoints }
    procedure PushBreaks;
    procedure FocusCode;
    { Vocabulary words of a kind, for the flags that hold them }
    function WordList(Kind: Integer): TStringArray;
    { The word (and its synonyms) with number V, '' if none }
    function WordText(V, Kind: Integer): string;
    { Breakpoints, by condact address }
    function BreakIndex(Addr: Word): Integer;
    procedure ToggleBreak(Addr: Word);
    procedure SetBreakEnabled(Index: Integer; Value: Boolean);
    procedure RemoveBreak(Index: Integer);
    procedure RemoveAllBreaks;
    { Breakpoints to and from a JSON file (DebugFiles); Load replaces them }
    procedure SaveBreaksAs;
    procedure LoadBreaksAsk;
    function LoadBreaksFile(const FileName: string; out Error: string): Boolean;
    { Ask for the condition of the breakpoint at Addr (adding it if needed) }
    procedure EditCondition(Addr: Word);
    function BreakCount: Integer;
    function BreakEntry(Index: Integer): TDaadBreakEntry;
    { "P1 E5  NOUN2 251" for the condact at Addr }
    function CondactLabel(Addr: Word): string;
    { Show the condact at Addr in the process zone }
    procedure ShowCondact(Addr: Word);
    constructor CreateFor(AOwner: TComponent; AEmu: TEmulator);
    destructor Destroy; override;
    { The emulation stopped at a condact: show it }
    procedure BreakHit;
    { Change flag N (0-255) or, from 256, the location of object N-256 }
    procedure SetValue(N, Value: Integer);
    { Whether condact C (the current one) holds with the flags as they are:
      1 yes, 0 no, -1 can't tell (CHANCE, PICTURE...), -2 not a condition }
    function CondactState(const C: TDaadCondact): Integer;
    property Game: TDaadGame read FGame;
    property User: Integer read FUser;
    property Current: Integer read FCurrent;
  end;

var
  DaadWindow: TDaadWindow;

{ Open the Adventure Debugger, stopping at the next condact. Says so and returns
  False if there is no DAAD game in memory. }
function ShowDaadDebugger(Emu: TEmulator): Boolean;

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
  GUTTER = 3;          // characters before the address: the arrow
  ENTRY_COLOR = $00602000;
  LANGUAGES: array[Boolean] of string = ('English', 'Spanish');

function Pick(Cond: Boolean; A, B: TColor): TColor;
begin
  if Cond then Result := A else Result := B;
end;

function ShowDaadDebugger(Emu: TEmulator): Boolean;
var
  Running: Boolean;
begin
  if DaadWindow = nil then DaadWindow := TDaadWindow.CreateFor(Application, Emu);
  Result := DaadWindow.LoadGame;
  if not Result then
  begin
    MessageDlg('Adventure Debugger', 'There is no DAAD, PAW or Quill game in memory: no ' +
      'DAAD database (DDB version 2 or 3, as made by DC 2.0 or later and DRC) nor a PAW or ' +
      'Quill one was found.', mtInformation, [mbOK], 0);
    Exit;
  end;
  // Follow the interpreter (it may still be, for "stop after player
  // input"), and stop at the next condact
  Running := not Emu.Paused;
  Emu.Lock;
  try
    if not Emu.Spec.DaadOn then Emu.Spec.SetDaadMap(@DaadWindow.FMap);
    if Running then Emu.Spec.DaadStop := dsNext;
  finally
    Emu.Unlock;
  end;
  DaadWindow.PushBreaks;
  DaadWindow.FCurrent := -1;
  DaadWindow.FWasPaused := Emu.Paused;
  DaadWindow.Show;
  DaadWindow.BringToFront;
  DaadWindow.ReadFlags;
  DaadWindow.ShowProcess(0);
  DaadWindow.UpdateStatus;
  DaadWindow.UpdateRunButtons;
  DaadWindow.FocusCode;
end;

{ TDaadView }

constructor TDaadView.CreateView(AOwner: TDaadWindow);
begin
  inherited Create(AOwner);
  FOwnerWin := AOwner;
  TabStop := True;
  Color := clWhite;
  Font.Name := MONO_FONT;
  Font.Size := 10;
  FBoldFont := TFont.Create;
  FBoldFont.Assign(Font);
  FBoldFont.Style := [fsBold];
  BorderStyle := bsSingle;
  FScroll := TScrollBar.Create(Self);
  FScroll.Parent := Self;
  FScroll.Kind := sbVertical;
  FScroll.Align := alRight;
  FScroll.TabStop := False;
  FScroll.OnChange := @ScrollChange;
end;

destructor TDaadView.Destroy;
begin
  FBoldFont.Free;
  inherited Destroy;
end;

procedure TDaadView.MeasureFont;
begin
  Canvas.Font := Font;
  FLineH := Canvas.TextHeight('Xy') + 2;
  FCharW := Canvas.TextWidth('0');
end;

function TDaadView.VisibleLines: Integer;
begin
  if FLineH = 0 then MeasureFont;
  Result := Max(1, ClientHeight div FLineH);
end;

procedure TDaadView.UpdateScroll;
var
  Last: Integer;
begin
  Last := Max(0, LineCount - VisibleLines);
  if FTop > Last then FTop := Last;
  FScroll.OnChange := nil;
  FScroll.Min := 0;
  FScroll.Max := Max(0, LineCount - 1);
  FScroll.PageSize := Min(VisibleLines, Max(1, LineCount));
  FScroll.LargeChange := Max(1, VisibleLines - 1);
  FScroll.Position := FTop;
  FScroll.OnChange := @ScrollChange;
end;

procedure TDaadView.ScrollTo(Line: Integer);
begin
  if Editing then EndEdit(False);
  FTop := EnsureRange(Line, 0, Max(0, LineCount - VisibleLines));
  UpdateScroll;
  Invalidate;
end;

procedure TDaadView.ScrollChange(Sender: TObject);
begin
  if Editing then EndEdit(False);
  FTop := EnsureRange(FScroll.Position, 0, Max(0, LineCount - VisibleLines));
  Invalidate;
end;

procedure TDaadView.EnsureVisible(Line: Integer);
begin
  if Line < 0 then Exit;
  if (Line < FTop) or (Line >= FTop + VisibleLines) then
    ScrollTo(Line - VisibleLines div 3)
  else
    UpdateScroll;
end;

function TDaadView.DrawText(X, Y: Integer; const S: string; AColor: TColor; Bold: Boolean): Integer;
begin
  if Bold then Canvas.Font := FBoldFont else Canvas.Font := Font;
  Canvas.Font.Color := AColor;
  Canvas.Brush.Style := bsClear;
  Canvas.TextOut(X, Y, S);
  Result := X + Canvas.TextWidth(S);
  Canvas.Font := Font;
end;

procedure TDaadView.Resize;
begin
  inherited Resize;
  UpdateScroll;
end;

function TDaadView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  if Editing then EndEdit(False);
  ScrollTo(FTop - Sign(WheelDelta) * 3);
  Result := True;
end;

procedure TDaadView.KeyDown(var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_UP: ScrollTo(FTop - 1);
    VK_DOWN: ScrollTo(FTop + 1);
    VK_PRIOR: ScrollTo(FTop - VisibleLines + 1);
    VK_NEXT: ScrollTo(FTop + VisibleLines - 1);
    VK_HOME: ScrollTo(0);
    VK_END: ScrollTo(LineCount);
  else
    inherited KeyDown(Key, Shift);
    Exit;
  end;
  Key := 0;
end;

procedure TDaadView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if CanFocus then SetFocus;
end;

function TDaadView.Editing: Boolean;
begin
  Result := ((FEditor <> nil) and FEditor.Visible) or ((FCombo <> nil) and FCombo.Visible);
end;

{ Edit a decimal value (0-255) shown at Line, from character Col }
procedure TDaadView.BeginEdit(Line, Col, Chars, Value, Target: Integer);
begin
  if FEditor = nil then
  begin
    FEditor := TEdit.Create(Self);
    FEditor.Parent := Self;
    FEditor.Font.Assign(Font);
    FEditor.BorderStyle := bsNone;
    FEditor.Color := RGBToColor(255, 255, 200);
    FEditor.OnKeyDown := @EditorKeyDown;
    FEditor.OnExit := @EditorExit;
  end;
  FEditTarget := Target;
  FEditor.SetBounds(2 + Col * FCharW - 1, (Line - FTop) * FLineH, (Chars + 1) * FCharW, FLineH);
  FEditor.MaxLength := Chars;
  FEditor.Text := IntToStr(Value);
  FEditor.Visible := True;
  FEditor.SetFocus;
  FEditor.SelectAll;
end;

procedure TDaadView.BeginComboEdit(Line, Col, Value, Target: Integer; const Items: TStringArray);
var
  I: Integer;
begin
  if FCombo = nil then
  begin
    FCombo := TComboBox.Create(Self);
    FCombo.Parent := Self;
    FCombo.Font.Assign(Font);
    FCombo.Style := csDropDown;
    FCombo.DropDownCount := 20;
    FCombo.OnKeyDown := @EditorKeyDown;
    FCombo.OnExit := @EditorExit;
    FCombo.OnSelect := @ComboSelect;
  end;
  FEditTarget := Target;
  FCombo.Items.Clear;
  for I := 0 to High(Items) do FCombo.Items.Add(Items[I]);
  FCombo.SetBounds(2 + Col * FCharW - 1, (Line - FTop) * FLineH - 2, 26 * FCharW, FCombo.Height);
  FCombo.Text := IntToStr(Value);
  FCombo.Visible := True;
  FCombo.SetFocus;
  FCombo.SelectAll;
end;

procedure TDaadView.ComboSelect(Sender: TObject);
begin
  EndEdit(True);
end;

procedure TDaadView.EditorKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_RETURN:
      begin
        Key := 0;
        EndEdit(True);
      end;
    VK_ESCAPE:
      begin
        Key := 0;
        EndEdit(False);
      end;
  end;
end;

{ Leaving the editor cancels it (as in the Z80 debugger): only Enter or a
  choice from the list changes the value }
procedure TDaadView.EditorExit(Sender: TObject);
begin
  if Editing then EndEdit(False);
end;

procedure TDaadView.EndEdit(Commit: Boolean);
var
  V: Integer;
  S: string;
begin
  if not Editing then Exit;
  if (FCombo <> nil) and FCombo.Visible then
  begin
    // "020 COGER" from the list, or a number typed
    S := Trim(FCombo.Text);
    if Pos(' ', S) > 0 then S := Copy(S, 1, Pos(' ', S) - 1);
    FCombo.Visible := False;
  end
  else
  begin
    S := Trim(FEditor.Text);
    FEditor.Visible := False;
  end;
  if Commit then
  begin
    V := StrToIntDef(S, -1);
    if (V >= 0) and (V <= 255) then Self.Commit(FEditTarget, V);
  end;
  if CanFocus then SetFocus;
  Invalidate;
end;

procedure TDaadView.Commit(Target, Value: Integer);
begin
end;

{ TDaadCodeView }

const
  MENU_TOGGLE = 1;
  MENU_CONDITION = 2;
  MENU_ENABLE = 3;
  MENU_REMOVE = 4;
  MENU_SHOW = 5;
  MENU_REMOVE_ALL = 6;
  MENU_SAVE = 7;
  MENU_LOAD = 8;
  MENU_SEARCH = 9;

function AddMenuItem(Menu: TPopupMenu; const ACaption: string; ATag: Integer;
  AHandler: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(Menu);
  Result.Caption := ACaption;
  Result.Tag := ATag;
  Result.OnClick := AHandler;
  Menu.Items.Add(Result);
end;

constructor TDaadCodeView.CreateView(AOwner: TDaadWindow);
begin
  inherited CreateView(AOwner);
  FSel := -1;
  FMenu := TPopupMenu.Create(Self);
  AddMenuItem(FMenu, 'Search...  (Ctrl+F, F3: next)', MENU_SEARCH, @MenuClick);
  AddMenuItem(FMenu, '-', 0, nil);
  FToggleItem := AddMenuItem(FMenu, 'Toggle breakpoint  (Space)', MENU_TOGGLE, @MenuClick);
  FConditionItem := AddMenuItem(FMenu, 'Breakpoint with condition...', MENU_CONDITION, @MenuClick);
  FEnabledItem := AddMenuItem(FMenu, 'Enabled', MENU_ENABLE, @MenuClick);
  FRemoveItem := AddMenuItem(FMenu, 'Remove breakpoint', MENU_REMOVE, @MenuClick);
end;

{ A line as the view shows it: an entry's address, words and number; a
  condact's address, the condact and the text it prints }
function TDaadCodeView.LineText(L: Integer): string;
var
  G: TDaadGame;
  E: Integer;
begin
  G := FOwnerWin.Game;
  if FLines[L] < 0 then
  begin
    E := -1 - FLines[L];
    Result := Format('%d > %s %s', [E - G.Processes[G.Entries[E].Process].FirstEntry + 1,
      G.VocWord(G.Entries[E].Verb, 0), G.VocWord(G.Entries[E].Noun, 2)]);
  end
  else
    Result := Format('%s "%s"', [G.CondactText(G.Condacts[FLines[L]]),
      G.CondactMessage(G.Condacts[FLines[L]])]);
end;

procedure TDaadCodeView.Search;
var
  S: string;
begin
  S := FSearch;
  if not InputQuery('Search the process', 'Text to find (condacts, words, the texts they ' +
    'print; F3 finds the next one):', S) or (Trim(S) = '') then Exit;
  FSearch := Trim(S);
  SearchNext;
end;

{ From the line after the selected one, round the process }
procedure TDaadCodeView.SearchNext;
var
  I, L: Integer;
  Want: string;
begin
  if FSearch = '' then
  begin
    Search;
    Exit;
  end;
  if Length(FLines) = 0 then Exit;
  Want := UpperCase(FSearch);
  for I := 1 to Length(FLines) do
  begin
    L := (Max(FSel, -1) + I) mod Length(FLines);
    if Pos(Want, UpperCase(LineText(L))) > 0 then
    begin
      FSel := L;
      EnsureVisible(L);
      Invalidate;
      FOwnerWin.FStatusBar.SimpleText := Format('Found "%s" (F3: next)', [FSearch]);
      Exit;
    end;
  end;
  Beep;
  FOwnerWin.FStatusBar.SimpleText := Format('"%s" is not in this process', [FSearch]);
end;

function TDaadCodeView.SelCondact: Integer;
begin
  if (FSel >= 0) and (FSel <= High(FLines)) and (FLines[FSel] >= 0) then
    Result := FLines[FSel]
  else
    Result := -1;
end;

procedure TDaadCodeView.SelectCondact(C: Integer);
begin
  FSel := LineOfCondact(C);
  EnsureVisible(FSel);
  Invalidate;
end;

procedure TDaadCodeView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  C, B: Integer;
  P: TPoint;
begin
  DelayedHint.Cancel;
  inherited MouseDown(Button, Shift, X, Y);
  if FLineH = 0 then MeasureFont;
  if FTop + Y div FLineH <= High(FLines) then FSel := FTop + Y div FLineH;
  Invalidate;
  C := SelCondact;
  if Button = mbRight then
  begin
    // Search always; the breakpoint items on a condact
    B := -1;
    if C >= 0 then B := FOwnerWin.BreakIndex(FOwnerWin.Game.Condacts[C].Addr);
    FToggleItem.Enabled := C >= 0;
    FConditionItem.Enabled := C >= 0;
    FEnabledItem.Enabled := B >= 0;
    FEnabledItem.Checked := (B >= 0) and FOwnerWin.BreakEntry(B).Enabled;
    FRemoveItem.Enabled := B >= 0;
    P := ClientToScreen(Point(X, Y));
    FMenu.PopUp(P.X, P.Y);
  end;
end;

{ Over a condact's name: what it does, after a second (the view's own hint
  is left out there) }
procedure TDaadCodeView.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  L, X0: Integer;
  CName, Help: string;
  G: TDaadGame;
begin
  inherited MouseMove(Shift, X, Y);
  if FDefaultHint = '' then FDefaultHint := Hint;
  Help := '';
  G := FOwnerWin.Game;
  if FLineH = 0 then MeasureFont;
  L := FTop + Y div FLineH;
  // The name comes under the entry's verb
  X0 := 2 + (GUTTER + 8) * FCharW;
  if G.Valid and (Y >= 0) and (L <= High(FLines)) and (FLines[L] >= 0) and (X >= X0) then
  begin
    CName := Trim(Copy(G.CondactText(G.Condacts[FLines[L]]), 1, 8));
    if X < X0 + Length(CName) * FCharW then
    begin
      Help := CondactHelp(CName, G.Engine);
      if Help <> '' then
        DelayedHint.Request(Self, Rect(X0, (L - FTop) * FLineH, X0 + Length(CName) * FCharW,
          (L - FTop + 1) * FLineH), Help);
    end;
  end;
  if Help = '' then
  begin
    DelayedHint.Cancel;
    if Hint <> FDefaultHint then Hint := FDefaultHint;
  end
  else if Hint <> '' then
  begin
    Hint := '';
    Application.CancelHint;
  end;
end;

procedure TDaadCodeView.MouseLeave;
begin
  inherited MouseLeave;
  DelayedHint.Cancel;
end;

procedure TDaadCodeView.DblClick;
begin
  if SelCondact >= 0 then FOwnerWin.ToggleBreak(FOwnerWin.Game.Condacts[SelCondact].Addr);
end;

procedure TDaadCodeView.KeyDown(var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_F: if ssCtrl in Shift then Search else
      begin
        inherited KeyDown(Key, Shift);
        Exit;
      end;
    VK_SPACE: if SelCondact >= 0 then FOwnerWin.ToggleBreak(FOwnerWin.Game.Condacts[SelCondact].Addr);
    VK_UP, VK_DOWN:
      begin
        if Key = VK_UP then FSel := Max(0, FSel - 1) else FSel := Min(High(FLines), FSel + 1);
        EnsureVisible(FSel);
        Invalidate;
      end;
  else
    inherited KeyDown(Key, Shift);
    Exit;
  end;
  Key := 0;
end;

procedure TDaadCodeView.MenuClick(Sender: TObject);
var
  C, B: Integer;
  A: Word;
begin
  if (Sender as TMenuItem).Tag = MENU_SEARCH then
  begin
    Search;
    Exit;
  end;
  C := SelCondact;
  if C < 0 then Exit;
  A := FOwnerWin.Game.Condacts[C].Addr;
  B := FOwnerWin.BreakIndex(A);
  case (Sender as TMenuItem).Tag of
    MENU_TOGGLE: FOwnerWin.ToggleBreak(A);
    MENU_CONDITION: FOwnerWin.EditCondition(A);
    MENU_ENABLE: if B >= 0 then FOwnerWin.SetBreakEnabled(B, not FOwnerWin.BreakEntry(B).Enabled);
    MENU_REMOVE: if B >= 0 then FOwnerWin.RemoveBreak(B);
  end;
end;

function TDaadCodeView.LineCount: Integer;
begin
  Result := Length(FLines);
end;

procedure TDaadCodeView.Build;
var
  G: TDaadGame;
  E, C, N: Integer;
begin
  G := FOwnerWin.Game;
  SetLength(FLines, 0);
  if not G.Valid or (FOwnerWin.FProcess < 0) or (FOwnerWin.FProcess > High(G.Processes)) then
  begin
    UpdateScroll;
    Invalidate;
    Exit;
  end;
  N := 0;
  with G.Processes[FOwnerWin.FProcess] do
    for E := FirstEntry to FirstEntry + EntryCount - 1 do
    begin
      SetLength(FLines, N + 1 + G.Entries[E].CondactCount);
      FLines[N] := -1 - E;
      Inc(N);
      for C := G.Entries[E].FirstCondact to G.Entries[E].FirstCondact + G.Entries[E].CondactCount - 1 do
      begin
        FLines[N] := C;
        Inc(N);
      end;
    end;
  UpdateScroll;
  Invalidate;
end;

function TDaadCodeView.LineOfCondact(C: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FLines) do
    if FLines[I] = C then Exit(I);
  Result := -1;
end;

procedure TDaadCodeView.DrawState(X, Y, State: Integer);
var
  S: Integer;
begin
  if State = -2 then Exit;
  S := FLineH - 6;
  Inc(Y, 3);
  // A white box behind, so it shows on any line colour
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := TC(clWhite);
  Canvas.Pen.Color := TC(clWhite);
  Canvas.Rectangle(X - 2, Y - 2, X + S + 3, Y + S + 3);
  if State = -1 then
  begin
    DrawText(X + (S - FCharW) div 2, Y - 3, '?', TC(RGBToColor(235, 130, 0)), True);
    Exit;
  end;
  Canvas.Pen.Width := 2;
  if State = 1 then
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

procedure TDaadCodeView.Paint;
var
  G: TDaadGame;
  I, L, Y, X, E, B: Integer;
  OnBreak: Boolean;
  Cond: TDaadCondact;
  Msg, S: string;
  Arrow: array[0..2] of TPoint;
begin
  if FLineH = 0 then MeasureFont;
  Canvas.Brush.Color := Color;
  Canvas.FillRect(ClientRect);
  G := FOwnerWin.Game;
  if not G.Valid then Exit;
  for I := 0 to VisibleLines do
  begin
    L := FTop + I;
    if L > High(FLines) then Break;
    Y := I * FLineH;
    if FLines[L] < 0 then
    begin
      // An entry: its number, verb and noun
      E := -1 - FLines[L];
      Canvas.Brush.Color := TC(RGBToColor(238, 242, 250));
      Canvas.FillRect(0, Y, ClientWidth, Y + FLineH);
      X := 2 + GUTTER * FCharW;
      // The entry's number in its process (the first is 1)
      X := DrawText(X, Y, Format('%4d  ', [E - G.Processes[G.Entries[E].Process].FirstEntry + 1]),
        TC(clGray), False);
      S := Format('> %-6s %-6s', [G.VocWord(G.Entries[E].Verb, 0), G.VocWord(G.Entries[E].Noun, 2)]);
      DrawText(X, Y, S, TC(ENTRY_COLOR), True);
      Continue;
    end;
    Cond := G.Condacts[FLines[L]];
    B := FOwnerWin.BreakIndex(Cond.Addr);
    OnBreak := (B >= 0) and FOwnerWin.BreakEntry(B).Enabled;
    if B >= 0 then
    begin
      // Breakpoints in red, pale when switched off (as in the Z80 debugger)
      if OnBreak then Canvas.Brush.Color := TC(RGBToColor(205, 40, 40))
      else Canvas.Brush.Color := TC(RGBToColor(245, 205, 205));
      Canvas.FillRect(0, Y, ClientWidth, Y + FLineH);
      if FOwnerWin.BreakEntry(B).Cond <> nil then
        DrawText(2, Y, '?', Pick(OnBreak, TC(clWhite), TC(clBlack)), True);
    end;
    if FLines[L] = FOwnerWin.Current then
    begin
      if B < 0 then
      begin
        Canvas.Brush.Color := TC(RGBToColor(205, 240, 205));
        Canvas.FillRect(0, Y, ClientWidth, Y + FLineH);
      end;
      // The green arrow, as in the Z80 debugger
      Canvas.Brush.Color := TC(RGBToColor(0, 150, 0));
      Canvas.Pen.Color := TC(RGBToColor(0, 110, 0));
      Arrow[0] := Point(4 + FCharW div 2, Y + 3);
      Arrow[1] := Point(4 + FCharW * 2, Y + FLineH div 2);
      Arrow[2] := Point(4 + FCharW div 2, Y + FLineH - 3);
      Canvas.Polygon(Arrow);
    end;
    // Under the entry's verb (where the address was)
    X := 2 + (GUTTER + 8) * FCharW;
    S := G.CondactText(Cond);
    if OnBreak then
    begin
      // Dark theme: the condact always bright white
      if DarkTheme then X := DrawText(X, Y, Copy(S, 1, 8), clWhite, True)
      else X := DrawText(X, Y, Copy(S, 1, 8), RGBToColor(255, 235, 140), False);
      X := DrawText(X, Y, Copy(S, 9, MaxInt), TC(clWhite), False);
    end
    else
    begin
      if DarkTheme then X := DrawText(X, Y, Copy(S, 1, 8), clWhite, True)
      else X := DrawText(X, Y, Copy(S, 1, 8), clBlue, False);
      X := DrawText(X, Y, Copy(S, 9, MaxInt), TC(clBlack), False);
    end;
    Msg := G.CondactMessage(Cond);
    if Msg <> '' then
      DrawText(Max(X + 2 * FCharW, 2 + (GUTTER + 26) * FCharW), Y, '"' + Msg + '"',
        Pick(OnBreak, TC(RGBToColor(255, 205, 205)), TC(clGray)), False);
    // At the current condact, a condition: holds (tick), fails (cross) or
    // depends on something else (an orange question mark)
    if FLines[L] = FOwnerWin.Current then
      DrawState(ClientWidth - FScroll.Width - 3 * FCharW, Y, FOwnerWin.CondactState(Cond));
  end;
  // The selected line
  if (FSel >= FTop) and (FSel <= High(FLines)) and (FSel < FTop + VisibleLines + 1) then
  begin
    Y := (FSel - FTop) * FLineH;
    Canvas.Brush.Style := bsClear;
    Canvas.Pen.Color := TC(RGBToColor(0, 0, 120));
    Canvas.Pen.Style := psDot;
    Canvas.Rectangle(GUTTER * FCharW - 2, Y, ClientWidth - FScroll.Width - 1, Y + FLineH);
    Canvas.Pen.Style := psSolid;
    Canvas.Brush.Style := bsSolid;
  end;
end;

{ TDaadBreakView }

constructor TDaadBreakView.CreateView(AOwner: TDaadWindow);
begin
  inherited CreateView(AOwner);
  FSel := -1;
  FMenu := TPopupMenu.Create(Self);
  AddMenuItem(FMenu, 'Condition...  (Enter)', MENU_CONDITION, @MenuClick);
  FEnabledItem := AddMenuItem(FMenu, 'Enabled  (Space)', MENU_ENABLE, @MenuClick);
  AddMenuItem(FMenu, 'Show in the process', MENU_SHOW, @MenuClick);
  AddMenuItem(FMenu, 'Remove  (Delete)', MENU_REMOVE, @MenuClick);
  AddMenuItem(FMenu, '-', 0, nil);
  AddMenuItem(FMenu, 'Remove all', MENU_REMOVE_ALL, @MenuClick);
  AddMenuItem(FMenu, '-', 0, nil);
  AddMenuItem(FMenu, 'Save breakpoints (JSON)...', MENU_SAVE, @MenuClick);
  AddMenuItem(FMenu, 'Load breakpoints (JSON)...', MENU_LOAD, @MenuClick);
end;

function TDaadBreakView.LineCount: Integer;
begin
  Result := FOwnerWin.BreakCount;
end;

procedure TDaadBreakView.Paint;
var
  I, N, Y, X, Box: Integer;
  E: TDaadBreakEntry;
begin
  if FLineH = 0 then MeasureFont;
  Canvas.Brush.Color := Color;
  Canvas.FillRect(ClientRect);
  if LineCount = 0 then
  begin
    DrawText(4, 0, 'Insert (or Space in the process): add a breakpoint', TC(clGray), False);
    Exit;
  end;
  if FSel > LineCount - 1 then FSel := LineCount - 1;
  for I := 0 to VisibleLines do
  begin
    N := FTop + I;
    if N >= LineCount then Break;
    E := FOwnerWin.BreakEntry(N);
    Y := I * FLineH;
    if N = FSel then
    begin
      Canvas.Brush.Color := TC(RGBToColor(210, 225, 250));
      Canvas.FillRect(0, Y, ClientWidth, Y + FLineH);
    end;
    // The on/off box
    Box := FLineH - 6;
    Canvas.Brush.Color := TC(clWhite);
    Canvas.Pen.Color := TC(clGray);
    Canvas.Rectangle(4, Y + 3, 4 + Box, Y + 3 + Box);
    if E.Enabled then
    begin
      Canvas.Pen.Color := TC(RGBToColor(205, 40, 40));
      Canvas.Pen.Width := 2;
      Canvas.MoveTo(6, Y + 3 + Box div 2);
      Canvas.LineTo(4 + Box div 2, Y + 1 + Box);
      Canvas.LineTo(2 + Box, Y + 5);
      Canvas.Pen.Width := 1;
    end;
    X := 8 + Box;
    X := DrawText(X, Y, IntToHex(E.Addr, 4) + '  ', TC(clBlack), True);
    X := DrawText(X, Y, Format('%-28s', [FOwnerWin.CondactLabel(E.Addr)]), TC(clBlack), False);
    if E.CondText <> '' then
      DrawText(X, Y, 'if ' + E.CondText, TC(RGBToColor(140, 90, 0)), False);
  end;
end;

procedure TDaadBreakView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  N: Integer;
  P: TPoint;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if FLineH = 0 then MeasureFont;
  N := FTop + Y div FLineH;
  if N >= LineCount then
  begin
    Invalidate;
    Exit;
  end;
  FSel := N;
  Invalidate;
  if (Button = mbLeft) and (X < 6 + FLineH) then
    FOwnerWin.SetBreakEnabled(N, not FOwnerWin.BreakEntry(N).Enabled)
  else if Button = mbRight then
  begin
    FEnabledItem.Checked := FOwnerWin.BreakEntry(N).Enabled;
    P := ClientToScreen(Point(X, Y));
    FMenu.PopUp(P.X, P.Y);
  end;
end;

procedure TDaadBreakView.DblClick;
begin
  if (FSel >= 0) and (FSel < LineCount) then FOwnerWin.EditCondition(FOwnerWin.BreakEntry(FSel).Addr);
end;

procedure TDaadBreakView.KeyDown(var Key: Word; Shift: TShiftState);
var
  C: Integer;
begin
  case Key of
    VK_INSERT:
      begin
        // The condact selected in the process
        C := FOwnerWin.FCode.SelCondact;
        if (C >= 0) and (FOwnerWin.BreakIndex(FOwnerWin.Game.Condacts[C].Addr) < 0) then
          FOwnerWin.ToggleBreak(FOwnerWin.Game.Condacts[C].Addr)
        else if C < 0 then
          MessageDlg('Breakpoints', 'Select a condact in the process first.', mtInformation, [mbOK], 0);
      end;
    VK_DELETE: if (FSel >= 0) and (FSel < LineCount) then FOwnerWin.RemoveBreak(FSel);
    VK_SPACE:
      if (FSel >= 0) and (FSel < LineCount) then
        FOwnerWin.SetBreakEnabled(FSel, not FOwnerWin.BreakEntry(FSel).Enabled);
    VK_RETURN: DblClick;
    VK_UP: FSel := Max(0, FSel - 1);
    VK_DOWN: FSel := Min(LineCount - 1, FSel + 1);
  else
    inherited KeyDown(Key, Shift);
    Exit;
  end;
  EnsureVisible(FSel);
  Invalidate;
  Key := 0;
end;

procedure TDaadBreakView.MenuClick(Sender: TObject);
begin
  case (Sender as TMenuItem).Tag of
    MENU_SAVE:
      begin
        FOwnerWin.SaveBreaksAs;
        Exit;
      end;
    MENU_LOAD:
      begin
        FOwnerWin.LoadBreaksAsk;
        Exit;
      end;
  end;
  if (FSel < 0) or (FSel >= LineCount) then Exit;
  case (Sender as TMenuItem).Tag of
    MENU_CONDITION: FOwnerWin.EditCondition(FOwnerWin.BreakEntry(FSel).Addr);
    MENU_ENABLE: FOwnerWin.SetBreakEnabled(FSel, not FOwnerWin.BreakEntry(FSel).Enabled);
    MENU_SHOW: FOwnerWin.ShowCondact(FOwnerWin.BreakEntry(FSel).Addr);
    MENU_REMOVE: FOwnerWin.RemoveBreak(FSel);
    MENU_REMOVE_ALL: FOwnerWin.RemoveAllBreaks;
  end;
end;

{ TDaadDataView }

function TDaadDataView.ItemCount: Integer;
begin
  if not FObjects then
  begin
    // The Quill has 37 (33 flags, the order's words, the location...)
    if FOwnerWin.Game.Valid then Result := FOwnerWin.Game.FlagCount else Result := 256;
  end
  else if FOwnerWin.Game.Valid then Result := FOwnerWin.Game.NumObjects
  else Result := 0;
end;

function TDaadDataView.ColChars: Integer;
begin
  if FObjects then Result := 40 else Result := 31;
end;

function TDaadDataView.Columns: Integer;
begin
  // Measuring needs the window: while it is being built, one column
  if not HandleAllocated then Exit(1);
  if FLineH = 0 then MeasureFont;
  Result := Max(1, (ClientWidth - FScroll.Width - 4) div (ColChars * FCharW));
end;

function TDaadDataView.LineCount: Integer;
var
  C: Integer;
begin
  C := Columns;
  Result := (ItemCount + C - 1) div C;
end;

function TDaadDataView.ItemAt(X, Y: Integer; out Row, Col, Base: Integer): Integer;
var
  C: Integer;
begin
  Result := -1;
  if FLineH = 0 then MeasureFont;
  Row := FTop + Y div FLineH;
  C := (X - 2) div (ColChars * FCharW);
  if (X < 2) or (C >= Columns) then Exit;
  Base := C * ColChars;
  Col := (X - 2) div FCharW - Base;
  Result := C * LineCount + Row;
  if (Row >= LineCount) or (Result >= ItemCount) then Result := -1;
end;

function TDaadDataView.Changed(N: Integer): Boolean;
begin
  if FObjects then Inc(N, 256);
  Result := FOwnerWin.FShowChanges and (FOwnerWin.FFlags[N] <> FOwnerWin.FPrevFlags[N]);
end;

procedure TDaadDataView.Paint;
var
  I, C, N, Y, X, X0, V, Rows: Integer;
  Known: Boolean;
  S: string;
  ValueColor: TColor;
begin
  if FLineH = 0 then MeasureFont;
  Canvas.Brush.Color := Color;
  Canvas.FillRect(ClientRect);
  Known := FOwnerWin.User >= 0;
  Rows := LineCount;
  for C := 0 to Columns - 1 do
    for I := 0 to VisibleLines do
    begin
      if FTop + I >= Rows then Break;
      N := C * Rows + FTop + I;
      if N >= ItemCount then Break;
      Y := I * FLineH;
      X0 := 2 + C * ColChars * FCharW;
      X := DrawText(X0, Y, Format('%.3d ', [N]), TC(clGray), False);
      if not Known then
      begin
        DrawText(X, Y, '---', TC(clGray), False);
        Continue;
      end;
      // Changed by the last condact: red
      if Changed(N) then ValueColor := TC(RGBToColor(210, 0, 0)) else ValueColor := TC(clBlack);
      if not FObjects then
      begin
        // "000 007 @ 090": the flag, its value and the value of flag 7
        V := FOwnerWin.FFlags[N];
        X := DrawText(X, Y, Format('%.3d', [V]), ValueColor, True);
        X := DrawText(X, Y, ' @ ', TC(clGray), False);
        X := DrawText(X, Y, Format('%.3d', [FOwnerWin.FFlags[V]]), TC(clBlack), False);
        S := FlagName(N, FOwnerWin.Game.Engine);
        if S <> '' then DrawText(X + FCharW, Y, Copy(S, 1, ColChars - 15), TC(clGray), False);
      end
      else
      begin
        // "000 254 carried  lamp"
        V := FOwnerWin.FFlags[256 + N];
        X := DrawText(X, Y, Format('%.3d', [V]), ValueColor, True);
        S := LocationName(V);
        X := DrawText(X + FCharW, Y, Format('%-11s', [S]), TC(RGBToColor(0, 110, 0)), False);
        DrawText(X + FCharW, Y, Copy(FOwnerWin.Game.ObjectText(N), 1, ColChars - 21), TC(clGray), False);
      end;
    end;
end;

procedure TDaadDataView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  N, Row, Col, Base: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if (Button <> mbLeft) or (FOwnerWin.User < 0) then Exit;
  N := ItemAt(X, Y, Row, Col, Base);
  if N < 0 then Exit;
  if FObjects then
  begin
    if (Col >= 4) and (Col < 7) then BeginEdit(Row, Base + 4, 3, FOwnerWin.FFlags[256 + N], 256 + N);
  end
  else if (Col >= 4) and (Col < 7) and (FlagWordKind(N) >= 0) then
    // A vocabulary word: pick it from the list, or type its number
    BeginComboEdit(Row, Base + 4, FOwnerWin.FFlags[N], N, FOwnerWin.WordList(FlagWordKind(N)))
  else if (Col >= 4) and (Col < 7) then
    BeginEdit(Row, Base + 4, 3, FOwnerWin.FFlags[N], N)
  else if (Col >= 10) and (Col < 13) then
    // The flag it points at
    BeginEdit(Row, Base + 10, 3, FOwnerWin.FFlags[FOwnerWin.FFlags[N]], FOwnerWin.FFlags[N]);
end;

{ Over the value of a flag holding a vocabulary word: the word }
procedure TDaadDataView.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  N, Row, Col, Base, Kind, V: Integer;
  S: string;
begin
  inherited MouseMove(Shift, X, Y);
  if FDefaultHint = '' then FDefaultHint := Hint;
  S := FDefaultHint;
  N := ItemAt(X, Y, Row, Col, Base);
  if not FObjects and (FOwnerWin.User >= 0) and (N >= 0) and (Col >= 4) and (Col < 7) then
  begin
    Kind := FlagWordKind(N);
    if Kind >= 0 then
    begin
      V := FOwnerWin.FFlags[N];
      S := FOwnerWin.WordText(V, Kind);
      if V = 255 then S := Format('%s = 255: no word (_)', [FlagName(N, FOwnerWin.Game.Engine)])
      else if S = '' then S := Format('%s = %d: not a word of the vocabulary', [FlagName(N, FOwnerWin.Game.Engine), V])
      else S := Format('%s = %d: %s', [FlagName(N, FOwnerWin.Game.Engine), V, S]);
    end;
  end;
  if S <> Hint then
  begin
    Hint := S;
    Application.CancelHint;
  end;
end;

procedure TDaadDataView.Commit(Target, Value: Integer);
begin
  FOwnerWin.SetValue(Target, Value);
end;

{ TDaadWindow }

constructor TDaadWindow.CreateFor(AOwner: TComponent; AEmu: TEmulator);
var
  Zone, Header, Data: TPanel;
  Split: TSplitter;
  Lbl: TLabel;
  Sep: TToolButton;
begin
  inherited CreateNew(AOwner, 0);
  FEmu := AEmu;
  FGame := TDaadGame.Create;
  FUser := -1;
  FCurrent := -1;
  Caption := 'Adventure Debugger';
  Width := 840;
  Height := 480;
  Position := poMainFormCenter;
  KeyPreview := True;
  OnKeyDown := @FormKeyDown;
  OnClose := @FormClose;

  FImages := TImageList.Create(Self);
  LoadIcons(FImages);
  FToolbar := TToolBar.Create(Self);
  FToolbar.Parent := Self;
  FToolbar.Images := FImages;
  FToolbar.ShowHint := True;
  FToolbar.ButtonWidth := IconSize + 10;
  FToolbar.ButtonHeight := IconSize + 10;
  FToolbar.AutoSize := True;
  FRunButton := AddButton(ikRun, 'Run (F5)', @DoRun);
  FBreakButton := AddButton(ikBreak, 'Break: stop at the next condact', @DoBreak);
  AddButton(ikStepInto, 'Step: run one condact (F7)', @DoStep);
  AddButton(ikStepOver, 'Step over (F10): run a PROCESS until it returns', @DoStepOver);
  Sep := TToolButton.Create(FToolbar);
  Sep.Parent := FToolbar;
  Sep.Style := tbsDivider;
  Sep.Left := FToolbar.Width + 1000;
  AddButton(ikSave, 'Export this process as source (.dsf or .sce, by the file''s extension)...',
    @DoExportProcess);
  AddButton(ikDisk, 'Export the whole game as source: DSF (DAAD Ready, DRC) or SCE (original ' +
    'DAAD compiler), by the file''s extension...', @DoExportSource);
  Sep := TToolButton.Create(FToolbar);
  Sep.Parent := FToolbar;
  Sep.Style := tbsDivider;
  Sep.Left := FToolbar.Width + 1000;
  FAfterInput := TCheckBox.Create(Self);
  FAfterInput.Parent := FToolbar;
  FAfterInput.Caption := 'Stop after player input';
  FAfterInput.Hint := 'Stop at the next condact once PARSE has read an order (typed by the ' +
    'player or left in the input buffer)';
  FAfterInput.ShowHint := True;
  FAfterInput.Left := FToolbar.Width + 1000;
  FAfterInput.BorderSpacing.Left := 6;
  FAfterInput.OnClick := @AfterInputClick;
  // As tall as the buttons, so it is centred among them
  FAfterInput.AutoSize := False;
  FAfterInput.Width := Canvas.TextWidth(FAfterInput.Caption) + ScaleX(30, 96);
  FAfterInput.Height := FToolbar.ButtonHeight;

  FStatusBar := TStatusBar.Create(Self);
  FStatusBar.Parent := Self;
  FStatusBar.SimplePanel := True;

  // Data (right): flags | objects
  Data := TPanel.Create(Self);
  Data.Parent := Self;
  Data.Align := alRight;
  Data.Width := 520;
  Data.BevelOuter := bvNone;
  FDataPanel := Data;
  Zone := MakeZone(Data, 'Objects location', 270, alRight);
  FObjZone := Zone;
  FObjView := TDaadDataView.CreateView(Self);
  FObjView.FObjects := True;
  FObjView.Parent := Zone;
  FObjView.Align := alClient;
  FObjView.Hint := 'Click a location to change it (252 not created, 253 worn, 254 carried)';
  FObjView.ShowHint := True;
  Zone := MakeZone(Data, 'Flags', 0, alClient);
  FFlagView := TDaadDataView.CreateView(Self);
  FFlagView.Parent := Zone;
  FFlagView.Align := alClient;
  FFlagView.Hint := 'Click a value to change it; the one after @ changes the flag it points at';
  FFlagView.ShowHint := True;

  Split := TSplitter.Create(Self);
  Split.Parent := Self;
  Split.Align := alRight;
  Split.OnMoved := @SplitMoved;
  OnResize := @FormResize;

  // Code (rest): the process, chosen in the header
  Zone := MakeZone(Self, 'Process', 0, alClient);
  Header := TPanel(Zone.Controls[0]);
  Lbl := TLabel(Header.Controls[0]);
  FProcessBox := TComboBox.Create(Self);
  FProcessBox.Parent := Header;
  FProcessBox.Style := csDropDownList;
  FProcessBox.AnchorSideLeft.Control := Lbl;
  FProcessBox.AnchorSideLeft.Side := asrRight;
  FProcessBox.BorderSpacing.Left := 8;
  FProcessBox.Top := 0;
  FProcessBox.Width := 130;
  FProcessBox.OnChange := @ProcessChange;
  // The engine of the game, at the right end of the header
  FEngineLabel := TLabel.Create(Self);
  FEngineLabel.Parent := Header;
  FEngineLabel.Font.Style := [fsBold];
  FEngineLabel.AnchorSideRight.Control := Header;
  FEngineLabel.AnchorSideRight.Side := asrRight;
  FEngineLabel.BorderSpacing.Right := 8;
  FEngineLabel.Anchors := [akRight];
  FEngineLabel.AnchorVerticalCenterTo(Header);
  FEngineLabel.Caption := '';
  FCode := TDaadCodeView.CreateView(Self);
  FCode.Parent := Zone;
  FCode.Align := alClient;
  FCode.Hint := 'Double-click or Space: breakpoint; right-click: menu';
  FCode.ShowHint := True;

  // Breakpoints, under the process
  Split := TSplitter.Create(Self);
  Split.Parent := Zone;
  Split.Align := alBottom;
  Split.Top := 100000;
  Data := MakeZone(Zone, 'Breakpoints', 0, alBottom);
  Data.Height := 100;
  Data.Top := 200000;
  Data.BorderSpacing.Around := 0;
  Data.BorderSpacing.Top := 3;
  FBreakView := TDaadBreakView.CreateView(Self);
  FBreakView.Parent := Data;
  FBreakView.Align := alClient;
  FBreakView.Hint := 'Insert: add (the condact selected in the process), Delete: remove, ' +
    'Space or the box: on/off, Enter or double-click: condition, right-click: menu';
  FBreakView.ShowHint := True;

  FTimer := TTimer.Create(Self);
  FTimer.Interval := 250;
  FTimer.OnTimer := @Tick;
end;

destructor TDaadWindow.Destroy;
var
  I: Integer;
begin
  // The emulation must not keep the conditions
  FEmu.Lock;
  try
    FEmu.Spec.SetDaadBreaks([]);
  finally
    FEmu.Unlock;
  end;
  for I := 0 to High(FBreaks) do FBreaks[I].Cond.Free;
  FGame.Free;
  inherited Destroy;
end;

function TDaadWindow.AddButton(AIcon: TIconKind; const AHint: string;
  AHandler: TNotifyEvent): TToolButton;
begin
  Result := TToolButton.Create(FToolbar);
  Result.Parent := FToolbar;
  Result.ImageIndex := Ord(AIcon);
  Result.Hint := AHint;
  Result.OnClick := AHandler;
  Result.Left := FToolbar.Width + 1000;
end;

{ A zone with a tinted header and a bold title, as in the Z80 debugger }
function TDaadWindow.MakeZone(AParent: TWinControl; const ACaption: string; AWidth: Integer;
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
  Header.Height := 26;
  Header.BevelOuter := bvNone;
  Header.Color := RGBToColor(214, 224, 242);
  Header.ParentBackground := False;
  Lbl := TLabel.Create(Self);
  Lbl.Parent := Header;
  Lbl.Caption := ACaption;
  Lbl.Font.Style := [fsBold];
  Lbl.Left := 6;
  Lbl.AnchorVerticalCenterTo(Header);
end;

function TDaadWindow.LoadGame: Boolean;
var
  A: Integer;
  MapChanged: Boolean;
  Old: array of Byte;
begin
  FEmu.Lock;
  try
    for A := 0 to $FFFF do FMem[A] := FEmu.Spec.Peek(A);
  finally
    FEmu.Unlock;
  end;
  Result := FGame.Load(FMem);
  if Result then FEngineLabel.Caption := EngineName(FGame.Engine) else FEngineLabel.Caption := '';
  if not Result then Exit;
  // A different game (or a new one loaded): follow its condacts
  SetLength(Old, Length(FMap));
  Move(FMap, Old[0], Length(FMap));
  FGame.BuildMap(@FMap);
  MapChanged := not CompareMem(@FMap, @Old[0], Length(FMap));
  if MapChanged and Visible then
  begin
    FEmu.Lock;
    try
      FEmu.Spec.SetDaadMap(@FMap);
    finally
      FEmu.Unlock;
    end;
  end;
  FProcessBox.Items.BeginUpdate;
  try
    if FProcessBox.Items.Count <> FGame.NumProcesses then
    begin
      FProcessBox.Items.Clear;
      for A := 0 to FGame.NumProcesses - 1 do FProcessBox.Items.Add(IntToStr(A));
    end;
    // PAW's process 0 is the response table; The Quill's two are the
    // event and status tables
    if FGame.IsQuill and (FProcessBox.Items.Count = 2) then
    begin
      FProcessBox.Items[0] := '0 (events)';
      FProcessBox.Items[1] := '1 (status)';
    end
    else if FProcessBox.Items.Count > 0 then
      if FGame.IsPAW then FProcessBox.Items[0] := '0 (responses)' else FProcessBox.Items[0] := '0';
  finally
    FProcessBox.Items.EndUpdate;
  end;
end;

procedure TDaadWindow.ReadFlags;
var
  I: Integer;
begin
  if FUser < 0 then Exit;
  FEmu.Lock;
  try
    // The flags, then the object locations (after the flags in The Quill)
    for I := 0 to 255 do
      if I < FGame.FlagCount then FFlags[I] := FEmu.Spec.Peek(Word(FUser + I)) else FFlags[I] := 0;
    for I := 0 to 255 do FFlags[256 + I] := FEmu.Spec.Peek(Word(FUser + FGame.ObjectsOffset + I));
  finally
    FEmu.Unlock;
  end;
  FFlagView.UpdateScroll;
  FObjView.UpdateScroll;
  FFlagView.Invalidate;
  FObjView.Invalidate;
end;

procedure TDaadWindow.ShowProcess(P: Integer);
begin
  if not FGame.Valid then Exit;
  P := EnsureRange(P, 0, FGame.NumProcesses - 1);
  if P <> FProcess then
  begin
    FCode.FTop := 0;
    FCode.FSel := -1;
  end;
  FProcess := P;
  FProcessBox.ItemIndex := P;
  FCode.Build;
end;

procedure TDaadWindow.ProcessChange(Sender: TObject);
begin
  if FProcessBox.ItemIndex >= 0 then ShowProcess(FProcessBox.ItemIndex);
end;

procedure TDaadWindow.BreakHit;
var
  Reopened: Boolean;
  Fetch, I: Integer;
  IX: Word;
  Recent: array[0..DAAD_ENTRY_HISTORY - 1] of Integer;
begin
  Reopened := not Visible;
  if Reopened then
  begin
    // Stopped after player input with the window closed: open it again
    Show;
    PushBreaks;
  end;
  FEmu.Lock;
  try
    Fetch := FEmu.Spec.DaadFetch;
    IX := FEmu.Spec.Cpu.IX.W;
    for I := 0 to High(Recent) do Recent[I] := FEmu.Spec.DaadEntry(I);
    FAtBreak := FEmu.Spec.DaadBreakHit and (FEmu.Spec.BreakKind = bkDaad);
  finally
    FEmu.Unlock;
  end;
  FWasPaused := True;
  LoadGame;
  FCurrent := -1;
  if FGame.Valid and (Fetch >= 0) then FCurrent := FGame.CondactIn(Fetch, Recent);
  // While a condact runs, IX points at the flags
  if FCurrent >= 0 then FUser := IX;
  // After a step, what the condact changed is shown in red
  FShowChanges := FStepping and (FUser >= 0);
  FStepping := False;
  if FShowChanges then Move(FFlags, FPrevFlags, SizeOf(FFlags));
  ReadFlags;
  if FCurrent >= 0 then
  begin
    ShowProcess(FGame.Entries[FGame.Condacts[FCurrent].Entry].Process);
    // The execution line is the selected one
    FCode.SelectCondact(FCurrent);
  end;
  FCode.Invalidate;
  UpdateStatus;
  UpdateRunButtons;
  // F7, F10... go to the process zone at once
  FocusCode;
end;

{ Focus on the window and the process zone: F7 / F10 step at once }
procedure TDaadWindow.FocusCode;
begin
  BringToFront;
  SetFocus;
  if FCode.CanFocus then FCode.SetFocus;
end;

procedure TDaadWindow.SetValue(N, Value: Integer);
begin
  if FUser < 0 then Exit;
  FPrevFlags[N] := Value;   // a change made here is not the condact's
  FEmu.Lock;
  try
    if N >= 256 then FEmu.Spec.Poke(Word(FUser + FGame.ObjectsOffset + N - 256), Value)
    else FEmu.Spec.Poke(Word(FUser + N), Value);
  finally
    FEmu.Unlock;
  end;
  ReadFlags;
end;

procedure TDaadWindow.UpdateStatus;
var
  S: string;
  E: Integer;
begin
  if not FGame.Valid then
    S := 'No DAAD, PAW or Quill game in memory'
  else if not FEmu.Paused then
  begin
    if FEmu.Spec.DaadFetchPC < 0 then
      S := 'Running: learning the interpreter, it stops when the game runs an entry ' +
        '(the game may be waiting for a command)'
    else if FEmu.Spec.DaadStop <> dsNone then
      S := 'Running to the next condact (the game may be waiting for a command)'
    else
      S := 'Running';
  end
  else if FCurrent >= 0 then
  begin
    E := FGame.Condacts[FCurrent].Entry;
    if FAtBreak then S := 'Breakpoint: stopped at %s (process %d, entry %d)'
    else S := 'Stopped at %s (process %d, entry %d)';
    S := Format(S, [DelSpace1(FGame.CondactText(FGame.Condacts[FCurrent])),
      FGame.Entries[E].Process, E - FGame.Processes[FGame.Entries[E].Process].FirstEntry]);
  end
  else
    S := 'Stopped outside the condacts: Step (F7) runs to the next one';
  if FGame.IsQuill then
    S := S + Format('    Quill database (version %s) at %.4X, %d objects, %d locations',
      [Copy('A?C', FGame.QuillVersion, 1), FGame.Base, FGame.NumObjects, FGame.NumLocations])
  else if FGame.IsPAW then
    S := S + Format('    PAW database at %.4X, %d processes, %d objects, %d locations',
      [FGame.Base, FGame.NumProcesses, FGame.NumObjects, FGame.NumLocations])
  else
    S := S + Format('    DDB v%d at %.4X, %s, %d processes, %d objects, %d locations',
      [FGame.Version, FGame.Base, LANGUAGES[FGame.Language = 1], FGame.NumProcesses,
       FGame.NumObjects, FGame.NumLocations]);
  if FUser < 0 then S := S + '; flags shown from the first stop';
  FStatusBar.SimpleText := S;
end;

procedure TDaadWindow.UpdateRunButtons;
begin
  FRunButton.Enabled := FEmu.Paused;
  FBreakButton.Enabled := not FEmu.Paused;
end;

procedure TDaadWindow.Tick(Sender: TObject);
var
  Paused: Boolean;
begin
  if not Visible then Exit;
  UpdateRunButtons;
  if AnyEditing then Exit;
  Paused := FEmu.Paused;
  if Paused and FWasPaused then Exit;
  if Paused then
    // Stopped by something else (the Z80 debugger, a breakpoint)
    BreakHit
  else
  begin
    FCurrent := -1;
    // Now and then: a different game may have been loaded
    Inc(FTicks);
    if FTicks mod 8 = 0 then
    begin
      LoadGame;
      FCode.Build;
    end;
    ReadFlags;
    FCode.Invalidate;
    UpdateStatus;
  end;
  FWasPaused := Paused;
end;

function TDaadWindow.AskSourceFile(const ADefault: string; out FileName: string;
  out Sce: Boolean): Boolean;
var
  Dlg: TSaveDialog;
begin
  Result := False;
  Sce := False;
  Dlg := TSaveDialog.Create(Self);
  try
    // A Quill game only as DAAD Ready / DRC source
    if FGame.IsQuill then
      Dlg.Filter := 'DAAD Ready / DRC source (*.dsf)|*.dsf|All files|*.*'
    else
      Dlg.Filter := 'DAAD Ready / DRC source (*.dsf)|*.dsf|Original DAAD source (*.sce)|*.sce|' +
        'All files|*.*';
    Dlg.FileName := ADefault;
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    if not Dlg.Execute then Exit;
    FileName := Dlg.FileName;
    // No extension typed: the one of the type chosen in the dialog
    if ExtractFileExt(FileName) = '' then
    begin
      if (Dlg.FilterIndex = 2) and not FGame.IsQuill then FileName := FileName + '.sce'
      else FileName := FileName + '.dsf';
      if FileExists(FileName) and (MessageDlg(ExtractFileName(FileName) +
        ' already exists. Replace it?', mtConfirmation, [mbYes, mbNo], 0) <> mrYes) then Exit;
    end;
    // The format is the file's: .sce, else DSF
    Sce := SameText(ExtractFileExt(FileName), '.sce');
    Result := True;
  finally
    Dlg.Free;
  end;
end;

function TDaadWindow.AskPawMode(Sce: Boolean; out ToDaad: Boolean): Boolean;
begin
  ToDaad := False;
  Result := True;
  // A Quill game: always converted to DAAD, as a DSF
  if FGame.IsQuill then
  begin
    if Sce then
    begin
      MessageDlg('A Quill game can only be exported as a DSF (DAAD Ready / DRC source), ' +
        'converted to DAAD.', mtInformation, [mbOK], 0);
      Exit(False);
    end;
    ToDaad := True;
    Exit;
  end;
  // An SCE is written as the PAW game is
  if not FGame.IsPAW or Sce then Exit;
  case QuestionDlg('Export a PAW game',
    'This is a PAW game. Export it as it is (PAW condacts and processes), or try to convert ' +
    'it to DAAD (as PAWS2DAAD does, with the processes of DAAD''s empty database)?',
    mtConfirmation, [mrYes, 'As a PAW game', mrNo, 'Convert to DAAD', mrCancel, 'Cancel'], 0) of
    mrYes: ToDaad := False;
    mrNo: ToDaad := True;
  else
    Result := False;
  end;
end;

procedure TDaadWindow.ConvertedNotice;
begin
  MessageDlg('The ' + EngineName(FGame.Engine) + ' game has been converted to DAAD, but the ' +
    'conversion can''t be complete: ' +
    'check the source by hand for possible issues (start with the "PAWS2DAAD note" comments), ' +
    'then compile it and test the game.', mtWarning, [mbOK], 0);
end;

procedure TDaadWindow.DoExportProcess(Sender: TObject);
var
  FileName: string;
  Sce, ToDaad: Boolean;
  Lines: TStringList;
begin
  if not FGame.Valid or (FProcess < 0) or (FProcess >= Length(FGame.Processes)) then Exit;
  if not AskSourceFile(Format('pro%d', [FProcess]), FileName, Sce) then Exit;
  if not AskPawMode(Sce, ToDaad) then Exit;
  Lines := ExportDaadProcess(FGame, FProcess, Sce, ToDaad);
  try
    try
      SaveDaadSource(Lines, FileName, Sce);
      FStatusBar.SimpleText := Format('Process %d exported to %s', [FProcess, ExtractFileName(FileName)]);
      if ToDaad then ConvertedNotice;
    except
      on E: Exception do MessageDlg('Could not save: ' + E.Message, mtError, [mbOK], 0);
    end;
  finally
    Lines.Free;
  end;
end;

procedure TDaadWindow.DoExportSource(Sender: TObject);
var
  FileName, Base: string;
  Sce, ToDaad: Boolean;
  Lines: TStringList;
begin
  if not FGame.Valid then Exit;
  // Named after the game file loaded last (COZUMEL.TAP: COZUMEL.dsf or .sce)
  FEmu.Lock;
  try
    Base := ChangeFileExt(FEmu.Spec.LastMediaFile, '');
  finally
    FEmu.Unlock;
  end;
  if Base = '' then Base := 'game';
  if not AskSourceFile(Base, FileName, Sce) then Exit;
  if not AskPawMode(Sce, ToDaad) then Exit;
  Lines := ExportDaadSource(FGame, Sce, ToDaad);
  try
    try
      SaveDaadSource(Lines, FileName, Sce);
      FStatusBar.SimpleText := 'Game exported to ' + ExtractFileName(FileName);
      if ToDaad then ConvertedNotice;
    except
      on E: Exception do MessageDlg('Could not save: ' + E.Message, mtError, [mbOK], 0);
    end;
  finally
    Lines.Free;
  end;
end;

procedure TDaadWindow.DoRun(Sender: TObject);
begin
  FStepping := False;
  if not FEmu.Paused then Exit;
  FEmu.Lock;
  try
    FEmu.Spec.DaadStop := dsNone;
  finally
    FEmu.Unlock;
  end;
  FEmu.Resume;
  FWasPaused := False;
  FCurrent := -1;
  FCode.Invalidate;
  UpdateStatus;
  UpdateRunButtons;
end;

procedure TDaadWindow.DoBreak(Sender: TObject);
begin
  FEmu.Lock;
  try
    FEmu.Spec.DaadStop := dsNext;
  finally
    FEmu.Unlock;
  end;
  UpdateStatus;
end;

procedure TDaadWindow.DoStep(Sender: TObject);
begin
  if not FEmu.Paused then
  begin
    DoBreak(Sender);   // first press stops; further presses step
    Exit;
  end;
  FStepping := True;
  FEmu.Lock;
  try
    FEmu.Spec.DaadStop := dsNext;
  finally
    FEmu.Unlock;
  end;
  FEmu.Resume;
  FWasPaused := False;
  UpdateStatus;
end;

procedure TDaadWindow.DoStepOver(Sender: TObject);
begin
  FStepping := False;
  if not FEmu.Paused then
  begin
    DoBreak(Sender);
    Exit;
  end;
  FEmu.Lock;
  try
    // Over a PROCESS: the next condact with the stack back where it is now
    if (FCurrent >= 0) and (FGame.Condacts[FCurrent].Opcode = OP_PROCESS) and
       (FEmu.Spec.DaadFetch = FGame.Condacts[FCurrent].Addr) then
    begin
      FEmu.Spec.DaadSP := FEmu.Spec.Cpu.SP.W;
      FEmu.Spec.DaadStop := dsOver;
    end
    else
      FEmu.Spec.DaadStop := dsNext;
  finally
    FEmu.Unlock;
  end;
  FEmu.Resume;
  FWasPaused := False;
  UpdateStatus;
end;

procedure TDaadWindow.AfterInputClick(Sender: TObject);
begin
  FEmu.Lock;
  try
    FEmu.Spec.DaadStopAfterParse := FAfterInput.Checked;
  finally
    FEmu.Unlock;
  end;
end;

function TDaadWindow.AnyEditing: Boolean;
begin
  Result := FFlagView.Editing or FObjView.Editing;
end;

function TDaadWindow.WordList(Kind: Integer): TStringArray;
var
  Nouns: TStringArray;
  I: Integer;
begin
  Result := FGame.VocWords(Kind);
  // Nouns below 20 (N, S...) are verbs too
  if Kind = 0 then
  begin
    Nouns := FGame.VocWords(2);
    for I := 0 to High(Nouns) do
      if StrToIntDef(Copy(Nouns[I], 1, 3), 99) < 20 then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := Nouns[I];
      end;
  end;
  SetLength(Result, Length(Result) + 1);
  Result[High(Result)] := '255 _ (no word)';
end;

function TDaadWindow.WordText(V, Kind: Integer): string;
var
  List: TStringArray;
  I: Integer;
begin
  List := WordList(Kind);
  for I := 0 to High(List) do
    if Copy(List[I], 1, 4) = Format('%.3d ', [V]) then Exit(Copy(List[I], 5, MaxInt));
  Result := '';
end;

function TDaadWindow.BreakIndex(Addr: Word): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FBreaks) do
    if FBreaks[I].Addr = Addr then Exit(I);
  Result := -1;
end;

function TDaadWindow.BreakCount: Integer;
begin
  Result := Length(FBreaks);
end;

function TDaadWindow.BreakEntry(Index: Integer): TDaadBreakEntry;
begin
  Result := FBreaks[Index];
end;

procedure TDaadWindow.PushBreaks;
var
  List: array of TDaadBreak;
  I: Integer;
begin
  SetLength(List, 0);
  for I := 0 to High(FBreaks) do
    if FBreaks[I].Enabled then
    begin
      SetLength(List, Length(List) + 1);
      List[High(List)].Addr := FBreaks[I].Addr;
      List[High(List)].Cond := FBreaks[I].Cond;
    end;
  FEmu.Lock;
  try
    FEmu.Spec.SetDaadBreaks(List);
  finally
    FEmu.Unlock;
  end;
  FCode.Invalidate;
  FBreakView.UpdateScroll;
  FBreakView.Invalidate;
end;

procedure TDaadWindow.ToggleBreak(Addr: Word);
var
  I: Integer;
begin
  I := BreakIndex(Addr);
  if I >= 0 then
  begin
    RemoveBreak(I);
    Exit;
  end;
  SetLength(FBreaks, Length(FBreaks) + 1);
  FBreaks[High(FBreaks)].Addr := Addr;
  FBreaks[High(FBreaks)].Enabled := True;
  FBreaks[High(FBreaks)].CondText := '';
  FBreaks[High(FBreaks)].Cond := nil;
  PushBreaks;
end;

procedure TDaadWindow.SetBreakEnabled(Index: Integer; Value: Boolean);
begin
  FBreaks[Index].Enabled := Value;
  PushBreaks;
end;

procedure TDaadWindow.RemoveBreak(Index: Integer);
var
  Cond: TDaadCondition;
  I: Integer;
begin
  Cond := FBreaks[Index].Cond;
  for I := Index to High(FBreaks) - 1 do FBreaks[I] := FBreaks[I + 1];
  SetLength(FBreaks, Length(FBreaks) - 1);
  PushBreaks;
  Cond.Free;   // once the emulation no longer has it
end;

procedure TDaadWindow.RemoveAllBreaks;
var
  Old: array of TDaadBreakEntry;
  I: Integer;
begin
  Old := Copy(FBreaks);
  SetLength(FBreaks, 0);
  PushBreaks;
  for I := 0 to High(Old) do Old[I].Cond.Free;
end;

{ The flags and objects take 60% of the width (so they show
  in several columns on a wide window), until the splitter is moved }
procedure TDaadWindow.FormResize(Sender: TObject);
begin
  if FSplitMoved or (FDataPanel = nil) then Exit;
  FDataPanel.Width := Max(520, ClientWidth * 3 div 5);
  FObjZone.Width := Max(270, FDataPanel.Width * 7 div 20);
end;

procedure TDaadWindow.SplitMoved(Sender: TObject);
begin
  FSplitMoved := True;
end;

procedure TDaadWindow.SaveBreaksAs;
var
  Dlg: TSaveDialog;
  Data: TDaadBreakDataArray;
  I: Integer;
begin
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := 'DAAD breakpoints (*.json)|*.json|All files|*.*';
    Dlg.DefaultExt := 'json';
    Dlg.FileName := 'daad-breakpoints.json';
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    if not Dlg.Execute then Exit;
    SetLength(Data, Length(FBreaks));
    for I := 0 to High(FBreaks) do
    begin
      Data[I].Addr := FBreaks[I].Addr;
      Data[I].Enabled := FBreaks[I].Enabled;
      Data[I].Condition := FBreaks[I].CondText;
      Data[I].Condact := CondactLabel(FBreaks[I].Addr);
    end;
    try
      SaveDaadBreaks(Data, Dlg.FileName);
      FStatusBar.SimpleText := Format('%d breakpoints saved to %s',
        [Length(Data), ExtractFileName(Dlg.FileName)]);
    except
      on E: Exception do MessageDlg('Could not save: ' + E.Message, mtError, [mbOK], 0);
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TDaadWindow.LoadBreaksAsk;
var
  Dlg: TOpenDialog;
  Error: string;
begin
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Filter := 'DAAD breakpoints (*.json)|*.json|All files|*.*';
    Dlg.Options := Dlg.Options + [ofFileMustExist];
    if not Dlg.Execute then Exit;
    if LoadBreaksFile(Dlg.FileName, Error) then
      FStatusBar.SimpleText := Format('%d breakpoints loaded from %s',
        [Length(FBreaks), ExtractFileName(Dlg.FileName)])
    else
      MessageDlg('Could not load the breakpoints: ' + Error, mtError, [mbOK], 0);
  finally
    Dlg.Free;
  end;
end;

function TDaadWindow.LoadBreaksFile(const FileName: string; out Error: string): Boolean;
var
  Data: TDaadBreakDataArray;
  I: Integer;
  Cond: TDaadCondition;
  CondError: string;
begin
  Result := LoadDaadBreaks(FileName, Data, Error);
  if not Result then Exit;
  // Check the conditions first: a bad file changes nothing
  for I := 0 to High(Data) do
    if Trim(Data[I].Condition) <> '' then
    begin
      Cond := TDaadCondition.Parse(Data[I].Condition, CondError);
      if Cond = nil then
      begin
        Error := Format('%.4X: %s', [Data[I].Addr, CondError]);
        Exit(False);
      end;
      Cond.Free;
    end;
  RemoveAllBreaks;
  SetLength(FBreaks, Length(Data));
  for I := 0 to High(Data) do
  begin
    FBreaks[I].Addr := Data[I].Addr;
    FBreaks[I].Enabled := Data[I].Enabled;
    FBreaks[I].CondText := Trim(Data[I].Condition);
    if FBreaks[I].CondText <> '' then
      FBreaks[I].Cond := TDaadCondition.Parse(FBreaks[I].CondText, CondError)
    else
      FBreaks[I].Cond := nil;
  end;
  PushBreaks;
  FBreakView.UpdateScroll;
  FBreakView.Invalidate;
  FCode.Invalidate;
end;

procedure TDaadWindow.EditCondition(Addr: Word);
var
  CondStr, Error: string;
  Cond, Old: TDaadCondition;
  I: Integer;
begin
  I := BreakIndex(Addr);
  if I >= 0 then CondStr := FBreaks[I].CondText else CondStr := '';
  repeat
    if not InputQuery('Breakpoint condition',
      Format('Stop at %.4X (%s) only when this holds (empty = always).', [Addr, CondactLabel(Addr)]) +
      LineEnding + 'Flags as fN (decimal), @fN for the flag fN points at, numbers in decimal,' +
      LineEnding + '= <> < > <= >=, AND OR NOT, ( ).' + LineEnding +
      'Examples:  f0 = 3 AND f10>11    f33 = 20 OR @f51 > 3    NOT f38 = 1', CondStr) then Exit;
    CondStr := Trim(CondStr);
    Cond := nil;
    Error := '';
    if CondStr <> '' then Cond := TDaadCondition.Parse(CondStr, Error);
    if (CondStr <> '') and (Cond = nil) then
      MessageDlg('Invalid condition: ' + Error, mtError, [mbOK], 0);
  until (CondStr = '') or (Cond <> nil);
  // A condition needs a breakpoint to apply to
  I := BreakIndex(Addr);
  if I < 0 then
  begin
    ToggleBreak(Addr);
    I := BreakIndex(Addr);
  end;
  Old := FBreaks[I].Cond;
  FBreaks[I].Cond := Cond;
  FBreaks[I].CondText := CondStr;
  FBreaks[I].Enabled := True;
  PushBreaks;
  Old.Free;
end;

function TDaadWindow.CondactState(const C: TDaadCondact): Integer;
var
  CName: string;
  P0, P1, Here, Prev: Integer;

  function Obj(N: Integer): Integer;
  begin
    if N < FGame.NumObjects then Result := FFlags[256 + N] else Result := -1;
  end;

  function Res(Value: Boolean): Integer;
  begin
    if Value then Result := 1 else Result := 0;
  end;

begin
  Result := -2;
  if FGame.IsPAW then CName := PAW_CONDACT_NAMES[C.Opcode] else CName := CONDACT_NAMES[C.Opcode];
  // Conditions that depend on what is outside the flags
  if (CName = 'CHANCE') or (CName = 'ISDONE') or (CName = 'ISNDONE') or (CName = 'PICTURE') or
     (CName = 'INKEY') or (CName = 'QUIT') or (CName = 'PARSE') or (FGame.IsPAW and (CName = 'TIMEOUT')) then
    Exit(-1);
  if Pos(',' + CName + ',', ',AT,NOTAT,ATGT,ATLT,PRESENT,ABSENT,WORN,NOTWORN,CARRIED,NOTCARR,ZERO,' +
    'NOTZERO,EQ,NOTEQ,GT,LT,SAME,NOTSAME,BIGGER,SMALLER,ADJECT1,ADVERB,PREP,NOUN2,ADJECT2,ISAT,' +
    'ISNOTAT,HASAT,HASNAT,') = 0 then Exit;
  if FUser < 0 then Exit(-1);   // flags not known yet
  P0 := C.Params[0];
  if C.Indirect then P0 := FFlags[P0];
  P1 := C.Params[1];
  // v3: an INDIR before it makes the second parameter a flag's value
  if not FGame.IsPAW and (FGame.Version >= 3) then
  begin
    Prev := FGame.CondactAt(C.Addr) - 1;
    if (Prev >= 0) and (FGame.Condacts[Prev].Entry = C.Entry) and
       (FGame.Condacts[Prev].Opcode = OP_INDIR) then P1 := FFlags[FGame.Condacts[Prev].Params[0]];
  end;
  Here := FFlags[FGame.LocationFlag];
  if CName = 'AT' then Result := Res(Here = P0)
  else if CName = 'NOTAT' then Result := Res(Here <> P0)
  else if CName = 'ATGT' then Result := Res(Here > P0)
  else if CName = 'ATLT' then Result := Res(Here < P0)
  else if CName = 'PRESENT' then
    Result := Res((Obj(P0) = LOC_WORN) or (Obj(P0) = LOC_CARRIED) or (Obj(P0) = Here))
  else if CName = 'ABSENT' then
    Result := Res(not ((Obj(P0) = LOC_WORN) or (Obj(P0) = LOC_CARRIED) or (Obj(P0) = Here)))
  else if CName = 'WORN' then Result := Res(Obj(P0) = LOC_WORN)
  else if CName = 'NOTWORN' then Result := Res(Obj(P0) <> LOC_WORN)
  else if CName = 'CARRIED' then Result := Res(Obj(P0) = LOC_CARRIED)
  else if CName = 'NOTCARR' then Result := Res(Obj(P0) <> LOC_CARRIED)
  else if CName = 'ZERO' then Result := Res(FFlags[P0] = 0)
  else if CName = 'NOTZERO' then Result := Res(FFlags[P0] <> 0)
  else if CName = 'EQ' then Result := Res(FFlags[P0] = P1)
  else if CName = 'NOTEQ' then Result := Res(FFlags[P0] <> P1)
  else if CName = 'GT' then Result := Res(FFlags[P0] > P1)
  else if CName = 'LT' then Result := Res(FFlags[P0] < P1)
  else if CName = 'SAME' then Result := Res(FFlags[P0] = FFlags[P1])
  else if CName = 'NOTSAME' then Result := Res(FFlags[P0] <> FFlags[P1])
  else if CName = 'BIGGER' then Result := Res(FFlags[P0] > FFlags[P1])
  else if CName = 'SMALLER' then Result := Res(FFlags[P0] < FFlags[P1])
  else if CName = 'ADJECT1' then Result := Res(FFlags[35] = P0)
  else if CName = 'ADVERB' then Result := Res(FFlags[36] = P0)
  else if CName = 'PREP' then Result := Res(FFlags[43] = P0)
  else if CName = 'NOUN2' then Result := Res(FFlags[44] = P0)
  else if CName = 'ADJECT2' then Result := Res(FFlags[45] = P0)
  else if (CName = 'ISAT') or (CName = 'ISNOTAT') then
  begin
    if P1 = 255 then P1 := Here;   // HERE
    Result := Res((Obj(P0) = P1) = (CName = 'ISAT'));
  end
  else if (CName = 'HASAT') or (CName = 'HASNAT') then
    // Bit (value mod 8) of flag 59 - value div 8
    Result := Res((((FFlags[59 - P0 div 8] shr (P0 and 7)) and 1) <> 0) = (CName = 'HASAT'));
end;

function TDaadWindow.CondactLabel(Addr: Word): string;
var
  C, E: Integer;
begin
  C := FGame.CondactAt(Addr);
  if C < 0 then Exit('(not a condact)');
  E := FGame.Condacts[C].Entry;
  Result := Format('P%d E%d  %s', [FGame.Entries[E].Process,
    E - FGame.Processes[FGame.Entries[E].Process].FirstEntry + 1, DelSpace1(FGame.CondactText(FGame.Condacts[C]))]);
end;

procedure TDaadWindow.ShowCondact(Addr: Word);
var
  C: Integer;
begin
  C := FGame.CondactAt(Addr);
  if C < 0 then Exit;
  ShowProcess(FGame.Entries[FGame.Condacts[C].Entry].Process);
  FCode.SelectCondact(C);
end;

procedure TDaadWindow.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if AnyEditing then Exit;
  case Key of
    VK_ESCAPE: Close;
    VK_F3: if FCode.Focused then FCode.SearchNext;
    VK_F5: DoRun(Self);
    VK_F7: DoStep(Self);
    VK_F10: DoStepOver(Self);
  else
    Exit;
  end;
  Key := 0;
end;

procedure TDaadWindow.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  CloseAction := caHide;
  FEmu.Lock;
  try
    // "Stop after player input" goes on working (the window opens again
    // when it stops); breakpoints act only while the window is open
    FEmu.Spec.SetDaadBreaks([]);
    FEmu.Spec.DaadStop := dsNone;
    if not FAfterInput.Checked then FEmu.Spec.SetDaadMap(nil);
  finally
    FEmu.Unlock;
  end;
  // Closing the debugger carries on running, like Run (F5)
  if FEmu.Paused then FEmu.Resume;
  // The keys go to the main window again
  Application.QueueAsyncCall(@FocusMainWindow, 0);
end;

procedure TDaadWindow.FocusMainWindow(Data: PtrInt);
begin
  if (Application.MainForm <> nil) and Application.MainForm.CanFocus then
  begin
    Application.MainForm.BringToFront;
    Application.MainForm.SetFocus;
  end;
end;

end.

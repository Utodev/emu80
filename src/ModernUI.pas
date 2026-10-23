{ ModernUI: the pieces of emu80's modern interface (Settings > General >
  Interface, --ui modern), in the style of Multipaint: dark grey, palettes
  with a title strip and big flat buttons with an icon and a label, all
  drawn here so they look the same on every platform. Also the dialog that
  asks which interface to use the first time emu80 starts. }
unit ModernUI;

{$mode objfpc}{$H+}

interface

uses
  Classes, Types, SysUtils, Math, Controls, Graphics, Forms, StdCtrls, ExtCtrls, ImgList, LCLType, ComCtrls, Menus,
  Grids, Generics.Collections{$IFDEF WINDOWS}, Windows{$ENDIF};

const
  // The palette of the modern interface
  MUI_BACK = $003A3A3A;        // window
  MUI_PANEL = $002F2F2F;       // palettes
  MUI_TITLE = $00252525;       // palette title strips, header
  MUI_EDGE = $001F1F1F;        // palette borders
  MUI_BUTTON = $00444444;
  MUI_BUTTON_HOT = $00525252;
  MUI_BUTTON_EDGE = $00555555;
  MUI_TEXT = $00E6E6E6;
  MUI_DIM = $00B9B9B9;
  MUI_ACCENT = $0066D1FF;      // #FFD166 (TColor is BGR)
  MUI_ACCENT_TEXT = $001B1B1B;
  MUI_SCREEN_FRAME = $00202020;

type
  { A flat, dark button with an icon (from Images) and/or a caption, the
    icon above the caption or left of it. Toggle buttons show Down in the
    accent colour. }
  TFlatButton = class(TCustomControl)
  private
    FImages: TCustomImageList;
    FImageIndex: Integer;
    FDown: Boolean;
    FHot: Boolean;
    FIconTop: Boolean;
    procedure SetDown(Value: Boolean);
  protected
    procedure Paint; override;
    procedure MouseEnter; override;
    procedure MouseLeave; override;
    procedure TextChanged; override;
    procedure SetEnabled(Value: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
    property Images: TCustomImageList read FImages write FImages;
    property ImageIndex: Integer read FImageIndex write FImageIndex;
    property Down: Boolean read FDown write SetDown;
    { Icon above the caption (big palette buttons), else to its left }
    property IconTop: Boolean read FIconTop write FIconTop;
    property OnClick;
    property Caption;
    property Hint;
    property ShowHint;
  end;

  { A dark area: the header, the bottom bar, the columns }
  TDarkPanel = class(TCustomControl)
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  { The note shown the first time emu80 starts: the interface is the modern
    one, and the button (its icon from Images) that changes to the classic }
  TModernNotice = class(TCustomControl)
  public
    Images: TCustomImageList;
    IconIndex: Integer;
  protected
    procedure Paint; override;
  end;

  { A palette: a box with its title on a strip at the top }
  TPaletteBox = class(TCustomControl)
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    { Where its contents start (below the title strip) }
    function TitleHeight: Integer;
  end;

  { The cassette in the tape palette: two reels and how far the tape is }
  TCassette = class(TCustomControl)
  private
    FProgress: Double;
    FTurn: Integer;
    FLoaded: Boolean;
    procedure SetLoaded(Value: Boolean);
  protected
    procedure Paint; override;
    procedure TextChanged; override;
  public
    constructor Create(AOwner: TComponent); override;
    { Progress 0..1; Playing turns the reels a step at each call }
    procedure Show(Progress: Double; Playing: Boolean);
    { False: an empty cassette player, without a tape in it }
    property Loaded: Boolean read FLoaded write SetLoaded;
  end;

{ A scaled size for the controls (96 DPI design units) }
function MUIScale(V: Integer): Integer;
{ A dark title bar for the window (Windows 10 and 11; nothing elsewhere) }
procedure SetDarkTitle(Form: TCustomForm; Dark: Boolean);

const
  { A control with this Tag sets its own colours: the theme leaves it alone }
  THEME_OWN_COLOURS = $7EC0;

var
  { The modern interface is in use: the other windows are dark too }
  DarkTheme: Boolean = False;

{ A colour as the theme shows it: as it is, or (dark theme) with its
  lightness turned round, keeping its hue: white grounds become dark grey,
  black text light grey, pastel highlights dark tints, dark coloured text
  light. Custom-drawn views pass every colour through it. }
function TC(C: TColor): TColor;
{ A window and its controls in the theme in use (the dark one remembers
  their own colours, to go back to them) }
procedure ThemeForm(Form: TCustomForm);
{ Every window open, and from now on each one as it is shown }
procedure ThemeAllForms;
{ A popup menu drawn in the modern interface's colours }
procedure DarkMenu(Menu: TPopupMenu);

implementation

uses
  LCLProc, LCLIntf, Icons{$IFDEF LCLWin32}, Win32Proc, Themes{$ENDIF};

function MUIScale(V: Integer): Integer;
begin
  Result := MulDiv(V, Screen.PixelsPerInch, 96);
end;

procedure SetDarkTitle(Form: TCustomForm; Dark: Boolean);
{$IFDEF WINDOWS}
const
  DWMWA_USE_IMMERSIVE_DARK_MODE = 20;
  DWMWA_USE_IMMERSIVE_DARK_MODE_OLD = 19;   // Windows 10 before 20H1
type
  TDwmSetWindowAttribute = function(Wnd: HWND; Attr: DWORD; Value: Pointer; Size: DWORD): HRESULT; stdcall;
var
  Lib: HMODULE;
  SetAttr: TDwmSetWindowAttribute;
  Value: BOOL;
begin
  if not Form.HandleAllocated then Exit;
  // Looked up at run time: older Windows has no such attribute (or library)
  Lib := LoadLibrary('dwmapi.dll');
  if Lib = 0 then Exit;
  try
    Pointer(SetAttr) := GetProcAddress(Lib, 'DwmSetWindowAttribute');
    if not Assigned(SetAttr) then Exit;
    Value := Dark;
    if SetAttr(Form.Handle, DWMWA_USE_IMMERSIVE_DARK_MODE, @Value, SizeOf(Value)) <> S_OK then
      SetAttr(Form.Handle, DWMWA_USE_IMMERSIVE_DARK_MODE_OLD, @Value, SizeOf(Value));
  finally
    FreeLibrary(Lib);
  end;
end;
{$ELSE}
begin
end;
{$ENDIF}

function TC(C: TColor): TColor;
var
  RGB: LongInt;
  R, G, B, Mx, Mn, L, S, H, Q, P: Double;

  function Hue(T: Double): Double;
  begin
    if T < 0 then T := T + 1;
    if T > 1 then T := T - 1;
    if T < 1 / 6 then Result := P + (Q - P) * 6 * T
    else if T < 1 / 2 then Result := Q
    else if T < 2 / 3 then Result := P + (Q - P) * (2 / 3 - T) * 6
    else Result := P;
  end;

begin
  Result := C;
  if not DarkTheme or (C = clNone) or (C = clDefault) then Exit;
  RGB := ColorToRGB(C);
  R := (RGB and $FF) / 255;
  G := ((RGB shr 8) and $FF) / 255;
  B := ((RGB shr 16) and $FF) / 255;
  Mx := Math.Max(R, Math.Max(G, B));
  Mn := Math.Min(R, Math.Min(G, B));
  L := (Mx + Mn) / 2;
  if Mx = Mn then
  begin
    S := 0;
    H := 0;
  end
  else
  begin
    if L > 0.5 then S := (Mx - Mn) / (2 - Mx - Mn) else S := (Mx - Mn) / (Mx + Mn);
    if Mx = R then H := (G - B) / (Mx - Mn) + Ord(G < B) * 6
    else if Mx = G then H := (B - R) / (Mx - Mn) + 2
    else H := (R - G) / (Mx - Mn) + 4;
    H := H / 6;
  end;
  // The other way round, between dark grey and light grey
  L := 0.12 + (1 - L) * 0.78;
  if S = 0 then
  begin
    R := L; G := L; B := L;
  end
  else
  begin
    if L < 0.5 then Q := L * (1 + S) else Q := L + S - L * S;
    P := 2 * L - Q;
    R := Hue(H + 1 / 3);
    G := Hue(H);
    B := Hue(H - 1 / 3);
  end;
  Result := RGBToColor(Round(R * 255), Round(G * 255), Round(B * 255));
end;

type
  { A control's own colours, kept while the dark theme shows others }
  TThemeOrig = record
    Color, FontColor, Fixed: TColor;
    AutoSized: Boolean;        // a check box sized to its text
    Width: Integer;
  end;

  { Forgets the colours of controls as they are destroyed }
  TThemeKeeper = class(TComponent)
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    Origs: specialize TDictionary<TControl, TThemeOrig>;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure ActiveFormChange(Sender: TObject; Form: TCustomForm);
    procedure ToolBarPaint(Sender: TObject);
  end;

var
  Keeper: TThemeKeeper = nil;

constructor TThemeKeeper.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Origs := specialize TDictionary<TControl, TThemeOrig>.Create;
end;

destructor TThemeKeeper.Destroy;
begin
  Origs.Free;
  inherited Destroy;
end;

procedure TThemeKeeper.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent is TControl) then Origs.Remove(TControl(AComponent));
end;

{ A toolbar in the dark theme: its colour behind the buttons (the platform
  would paint it light) }
procedure TThemeKeeper.ToolBarPaint(Sender: TObject);
var
  T: TToolBar;
begin
  T := Sender as TToolBar;
  T.Canvas.Brush.Color := T.Color;
  T.Canvas.FillRect(T.ClientRect);
end;

procedure TThemeKeeper.ActiveFormChange(Sender: TObject; Form: TCustomForm);
begin
  if Form <> nil then ThemeForm(Form);
end;

{ Controls that are a field to type in or a list: the window colour }
function IsField(C: TControl): Boolean;
begin
  Result := (C is TCustomEdit) or (C is TCustomListBox) or (C is TCustomComboBox) or
    (C is TCustomListView) or (C is TCustomTreeView) or (C is TCustomGrid);
end;

{$IFDEF WINDOWS}
{ A control without (Off) or with its visual style (uxtheme, looked up at
  run time) }
procedure NoVisualStyle(H: HWND; Off: Boolean);
type
  TSetWindowTheme = function(Wnd: HWND; App, Ids: PWideChar): HRESULT; stdcall;
var
  Lib: HMODULE;
  SetTheme: TSetWindowTheme;
  Blank: WideString;
begin
  Lib := LoadLibrary('uxtheme.dll');
  if Lib = 0 then Exit;
  try
    Pointer(SetTheme) := GetProcAddress(Lib, 'SetWindowTheme');
    if not Assigned(SetTheme) then Exit;
    Blank := ' ';
    if Off then SetTheme(H, PWideChar(Blank), PWideChar(Blank)) else SetTheme(H, nil, nil);
  finally
    FreeLibrary(Lib);
  end;
end;
{$ENDIF}

{$IFDEF WINDOWS}
{ Check boxes, radio buttons and tabs drawn here in the dark theme: Windows
  draws them light (and their text black) whatever their colours. Their
  window is subclassed (comctl32, looked up at run time) to paint them. }

type
  TSubclassProc = function(Wnd: HWND; Msg: UINT; WP: WPARAM; LP: LPARAM; Id: UINT_PTR;
    Data: DWORD_PTR): LRESULT; stdcall;

var
  SetSubclass: function(Wnd: HWND; Proc: TSubclassProc; Id: UINT_PTR; Data: DWORD_PTR): BOOL; stdcall = nil;
  RemoveSubclass: function(Wnd: HWND; Proc: TSubclassProc; Id: UINT_PTR): BOOL; stdcall = nil;
  DefSubclass: function(Wnd: HWND; Msg: UINT; WP: WPARAM; LP: LPARAM): LRESULT; stdcall = nil;

const
  DARK_EDGE = $00606060;
  DARK_TAB = $00222222;

function SubclassReady: Boolean;
var
  Lib: HMODULE;
begin
  if not Assigned(DefSubclass) then
  begin
    Lib := LoadLibrary('comctl32.dll');
    if Lib <> 0 then
    begin
      Pointer(SetSubclass) := GetProcAddress(Lib, 'SetWindowSubclass');
      Pointer(RemoveSubclass) := GetProcAddress(Lib, 'RemoveWindowSubclass');
      Pointer(DefSubclass) := GetProcAddress(Lib, 'DefSubclassProc');
    end;
  end;
  Result := Assigned(SetSubclass) and Assigned(RemoveSubclass) and Assigned(DefSubclass);
end;

function StripAmpersands(const Caption: string): string;
var
  I: Integer;
begin
  Result := '';
  I := 1;
  while I <= Length(Caption) do
  begin
    if Caption[I] = '&' then Inc(I);
    if I <= Length(Caption) then Result := Result + Caption[I];
    Inc(I);
  end;
end;

procedure PaintCheck(Wnd: HWND; Ctl: TCustomCheckBox; DC: HDC);
var
  Cv: TCanvas;
  R: Windows.RECT;
  Box, X, Y, State: Integer;
  Back: TColor;
  Text: string;
begin
  Windows.GetClientRect(Wnd, R);
  Cv := TCanvas.Create;
  try
    Cv.Handle := DC;
    if Ctl.Parent <> nil then Back := Ctl.Parent.Color else Back := Ctl.Color;
    Cv.Brush.Color := Back;
    Cv.FillRect(Classes.Rect(R.Left, R.Top, R.Right, R.Bottom));
    Box := MUIScale(14);
    X := R.Left + 1;
    Y := (R.Top + R.Bottom - Box) div 2;
    State := Windows.SendMessage(Wnd, BM_GETCHECK, 0, 0);
    Cv.Pen.Color := DARK_EDGE;
    if Ctl.Enabled then Cv.Brush.Color := MUI_BUTTON else Cv.Brush.Color := Back;
    if Ctl is TRadioButton then
    begin
      Cv.Ellipse(X, Y, X + Box, Y + Box);
      if State = BST_CHECKED then
      begin
        Cv.Pen.Color := MUI_ACCENT;
        Cv.Brush.Color := MUI_ACCENT;
        Cv.Ellipse(X + MUIScale(4), Y + MUIScale(4), X + Box - MUIScale(4), Y + Box - MUIScale(4));
      end;
    end
    else
    begin
      Cv.Rectangle(X, Y, X + Box, Y + Box);
      if State = BST_CHECKED then
      begin
        Cv.Pen.Color := MUI_ACCENT;
        Cv.Pen.Width := Max(2, MUIScale(2));
        Cv.Line(X + MUIScale(3), Y + Box div 2, X + Box * 5 div 12, Y + Box - MUIScale(4));
        Cv.Line(X + Box * 5 div 12, Y + Box - MUIScale(4), X + Box - MUIScale(3), Y + MUIScale(3));
        Cv.Pen.Width := 1;
      end
      else if State = BST_INDETERMINATE then
      begin
        Cv.Brush.Color := MUI_ACCENT;
        Cv.FillRect(X + MUIScale(4), Y + MUIScale(4), X + Box - MUIScale(4), Y + Box - MUIScale(4));
      end;
    end;
    Cv.Font := Ctl.Font;
    if not Ctl.Enabled then Cv.Font.Color := $00808080
    else if (Cv.Font.Color = clDefault) or (Cv.Font.Color = clWindowText) then Cv.Font.Color := MUI_TEXT;
    Cv.Brush.Style := bsClear;
    Text := StripAmpersands(Ctl.Caption);
    X := X + Box + MUIScale(6);
    Y := (R.Top + R.Bottom - Cv.TextHeight('Ag')) div 2;
    Cv.TextOut(X, Y, Text);
    if Windows.GetFocus = Wnd then
    begin
      Cv.Brush.Style := bsSolid;
      Cv.Brush.Color := Back;
      Cv.Font.Color := MUI_TEXT;
      Cv.DrawFocusRect(Classes.Rect(X - 2, Y, X + Cv.TextWidth(Text) + 2, Y + Cv.TextHeight('Ag')));
    end;
  finally
    Cv.Handle := 0;
    Cv.Free;
  end;
end;

procedure PaintTabs(Wnd: HWND; Ctl: TWinControl; DC: HDC);
var
  Cv: TCanvas;
  R, T: Windows.RECT;
  I, N, Sel, Bottom: Integer;
  Item: TTCItem;
  Buf: array[0..255] of WideChar;
  Text: string;
begin
  Windows.GetClientRect(Wnd, R);
  Cv := TCanvas.Create;
  try
    Cv.Handle := DC;
    if Ctl.Parent <> nil then Cv.Brush.Color := Ctl.Parent.Color else Cv.Brush.Color := Ctl.Color;
    Cv.FillRect(Classes.Rect(R.Left, R.Top, R.Right, R.Bottom));
    Cv.Font := Ctl.Font;
    N := Windows.SendMessage(Wnd, TCM_GETITEMCOUNT, 0, 0);
    Sel := Windows.SendMessage(Wnd, TCM_GETCURSEL, 0, 0);
    Bottom := R.Top;
    for I := 0 to N - 1 do
    begin
      Windows.SendMessage(Wnd, TCM_GETITEMRECT, I, LPARAM(@T));
      Bottom := Max(Bottom, T.Bottom);
    end;
    // The pages' frame, under the tabs
    Cv.Brush.Style := bsClear;
    Cv.Pen.Color := DARK_EDGE;
    Cv.Rectangle(R.Left, Bottom, R.Right, R.Bottom);
    for I := 0 to N - 1 do
    begin
      Windows.SendMessage(Wnd, TCM_GETITEMRECT, I, LPARAM(@T));
      FillChar(Item, SizeOf(Item), 0);
      Item.mask := TCIF_TEXT;
      Item.pszText := LPTSTR(@Buf[0]);
      Item.cchTextMax := Length(Buf);
      Buf[0] := #0;
      Windows.SendMessage(Wnd, TCM_GETITEMW, I, LPARAM(@Item));
      Text := StripAmpersands(UTF8Encode(WideString(PWideChar(@Buf[0]))));
      Cv.Brush.Style := bsSolid;
      if I = Sel then
      begin
        // The tab chosen: joined to its page, with the accent on top
        Dec(T.Top, MUIScale(2));
        Cv.Brush.Color := Ctl.Color;
        Cv.Pen.Color := DARK_EDGE;
        Cv.Rectangle(T.Left, T.Top, T.Right, T.Bottom + 1);
        Cv.FillRect(T.Left + 1, T.Bottom - 1, T.Right - 1, T.Bottom + 1);
        Cv.Brush.Color := MUI_ACCENT;
        Cv.FillRect(T.Left, T.Top, T.Right, T.Top + MUIScale(2));
        Cv.Font.Color := clWhite;
      end
      else
      begin
        Cv.Brush.Color := DARK_TAB;
        Cv.Pen.Color := DARK_EDGE;
        Cv.Rectangle(T.Left, T.Top, T.Right, T.Bottom);
        Cv.Font.Color := MUI_DIM;
      end;
      Cv.Brush.Style := bsClear;
      Cv.TextOut((T.Left + T.Right - Cv.TextWidth(Text)) div 2,
        (T.Top + T.Bottom - Cv.TextHeight('Ag')) div 2 + 1, Text);
    end;
  finally
    Cv.Handle := 0;
    Cv.Free;
  end;
end;

procedure PaintTrackBar(Wnd: HWND; Ctl: TWinControl; DC: HDC);
var
  Cv: TCanvas;
  R, Ch, Th: Windows.RECT;
  I, N, X, Y: Integer;

  procedure Tick(TX: Integer);
  begin
    Cv.Line(TX, Y, TX, Y + MUIScale(4));
  end;

begin
  Windows.GetClientRect(Wnd, R);
  Windows.SendMessage(Wnd, TBM_GETCHANNELRECT, 0, LPARAM(@Ch));
  Windows.SendMessage(Wnd, TBM_GETTHUMBRECT, 0, LPARAM(@Th));
  Cv := TCanvas.Create;
  try
    Cv.Handle := DC;
    if Ctl.Parent <> nil then Cv.Brush.Color := Ctl.Parent.Color else Cv.Brush.Color := Ctl.Color;
    Cv.FillRect(Classes.Rect(R.Left, R.Top, R.Right, R.Bottom));
    // The channel
    Cv.Pen.Color := DARK_EDGE;
    Cv.Brush.Color := DARK_TAB;
    Cv.Rectangle(Ch.Left, Ch.Top, Ch.Right, Ch.Bottom);
    // The ticks, under it: both ends and those between
    Cv.Pen.Color := MUI_DIM;
    Y := Th.Bottom + MUIScale(2);
    X := (Th.Right - Th.Left) div 2;
    with TTrackBar(Ctl) do
      if (Max > Min) and (TickStyle <> tsNone) then
      begin
        N := Math.Max(Frequency, 1);
        I := Min;
        while I <= Max do
        begin
          Tick(Ch.Left + X + MulDiv(I - Min, Ch.Right - Ch.Left - 2 * X - 1, Max - Min));
          if (I < Max) and (I + N > Max) then I := Max else Inc(I, N);
        end;
      end;
    // The thumb, in the accent colour
    if Ctl.Enabled then Cv.Brush.Color := MUI_ACCENT else Cv.Brush.Color := MUI_BUTTON;
    Cv.Pen.Color := MUI_ACCENT_TEXT;
    Cv.RoundRect(Th.Left, Th.Top, Th.Right, Th.Bottom, MUIScale(3), MUIScale(3));
  finally
    Cv.Handle := 0;
    Cv.Free;
  end;
end;

procedure PaintGroupBox(Wnd: HWND; Ctl: TWinControl; DC: HDC);
var
  Cv: TCanvas;
  R: Windows.RECT;
  H, X: Integer;
  Text: string;
begin
  Windows.GetClientRect(Wnd, R);
  Cv := TCanvas.Create;
  try
    Cv.Handle := DC;
    Cv.Font := Ctl.Font;
    Text := StripAmpersands(Ctl.Caption);
    H := Cv.TextHeight('Ag');
    // Over Windows' light frame and black caption (the labels inside, drawn
    // by LCL, are left alone)
    Cv.Brush.Color := Ctl.Color;
    Cv.FillRect(R.Left, R.Top, R.Right, R.Top + H + 2);
    Cv.FillRect(R.Left, R.Top, R.Left + 3, R.Bottom);
    Cv.FillRect(R.Right - 3, R.Top, R.Right, R.Bottom);
    Cv.FillRect(R.Left, R.Bottom - 3, R.Right, R.Bottom);
    Cv.Brush.Style := bsClear;
    Cv.Pen.Color := DARK_EDGE;
    Cv.RoundRect(R.Left, R.Top + H div 2, R.Right, R.Bottom, MUIScale(6), MUIScale(6));
    if Text <> '' then
    begin
      X := R.Left + MUIScale(8);
      Cv.Brush.Style := bsSolid;
      Cv.FillRect(X - 3, R.Top, X + Cv.TextWidth(Text) + 3, R.Top + H);
      Cv.Brush.Style := bsClear;
      if Ctl.Enabled then Cv.Font.Color := MUI_TEXT else Cv.Font.Color := $00808080;
      Cv.TextOut(X, R.Top, Text);
    end;
  finally
    Cv.Handle := 0;
    Cv.Free;
  end;
end;

function DarkProc(Wnd: HWND; Msg: UINT; WP: WPARAM; LP: LPARAM; Id: UINT_PTR;
  Data: DWORD_PTR): LRESULT; stdcall;
var
  PS: Windows.PAINTSTRUCT;
  DC: HDC;
  Ctl: TWinControl;
begin
  Ctl := TWinControl(Pointer(Data));
  if Ctl is TCustomGroupBox then
  begin
    // Windows and LCL paint it (and the labels in it), then its frame and
    // caption are drawn again
    if Msg = WM_NCDESTROY then RemoveSubclass(Wnd, TSubclassProc(@DarkProc), 1);
    Result := DefSubclass(Wnd, Msg, WP, LP);
    if (Msg = WM_PAINT) or (Msg = WM_SETTEXT) or (Msg = WM_ENABLE) then
    begin
      DC := Windows.GetDC(Wnd);
      PaintGroupBox(Wnd, Ctl, DC);
      Windows.ReleaseDC(Wnd, DC);
    end;
    Exit;
  end;
  case Msg of
    WM_PAINT:
      begin
        DC := Windows.BeginPaint(Wnd, PS);
        if Ctl is TCustomCheckBox then PaintCheck(Wnd, TCustomCheckBox(Ctl), DC)
        else if Ctl is TCustomTrackBar then PaintTrackBar(Wnd, Ctl, DC)
        else PaintTabs(Wnd, Ctl, DC);
        Windows.EndPaint(Wnd, PS);
        Exit(0);
      end;
    WM_ERASEBKGND: Exit(1);
    WM_NCDESTROY:
      begin
        RemoveSubclass(Wnd, TSubclassProc(@DarkProc), 1);
        Exit(DefSubclass(Wnd, Msg, WP, LP));
      end;
  end;
  Result := DefSubclass(Wnd, Msg, WP, LP);
  // Windows draws a button at once when it is clicked, checked, focused...:
  // drawn again over it
  if Ctl is TCustomCheckBox then
    case Msg of
      BM_SETCHECK, BM_SETSTATE, BM_CLICK, WM_SETFOCUS, WM_KILLFOCUS, WM_ENABLE, WM_SETTEXT,
      WM_LBUTTONDOWN, WM_LBUTTONUP, WM_LBUTTONDBLCLK, WM_KEYDOWN, WM_KEYUP, WM_UPDATEUISTATE,
      WM_CAPTURECHANGED, WM_MOUSEMOVE:
        begin
          DC := Windows.GetDC(Wnd);
          PaintCheck(Wnd, TCustomCheckBox(Ctl), DC);
          Windows.ReleaseDC(Wnd, DC);
        end;
    end
  else if Ctl is TCustomTrackBar then
    case Msg of
      TBM_SETPOS, TBM_SETRANGE, WM_LBUTTONDOWN, WM_LBUTTONUP, WM_MOUSEMOVE, WM_KEYDOWN, WM_KEYUP,
      WM_SETFOCUS, WM_KILLFOCUS, WM_ENABLE, WM_SIZE:
        Windows.InvalidateRect(Wnd, nil, False);
    end
  else
    case Msg of
      TCM_SETCURSEL, WM_LBUTTONDOWN, WM_MOUSEMOVE, WM_MOUSELEAVE, WM_SIZE, WM_SETFONT:
        Windows.InvalidateRect(Wnd, nil, False);
    end;
end;

{ A check box or a tab control drawn here (Dark) or by Windows }
procedure DarkDrawn(C: TWinControl; Dark: Boolean);
begin
  if not C.HandleAllocated or not SubclassReady then Exit;
  if Dark then SetSubclass(C.Handle, @DarkProc, 1, DWORD_PTR(Pointer(C)))
  else RemoveSubclass(C.Handle, @DarkProc, 1);
  Windows.InvalidateRect(C.Handle, nil, True);
end;
{$ENDIF}

{ The modern interface's own pieces are dark already; native status bars
  keep their black text, so they stay light; hints draw themselves (see
  TDarkHintWindow) }
function Untouched(C: TControl): Boolean;
begin
  Result := (C is TFlatButton) or (C is TDarkPanel) or (C is TPaletteBox) or (C is TCassette) or
    (C is TStatusBar) or (C is THintWindow) or (C.Tag = THEME_OWN_COLOURS);
end;

type
  { The hints of every window: in the dark theme white on dark grey (the
    system would draw a light one) }
  TDarkHintWindow = class(THintWindow)
  protected
    procedure Paint; override;
  end;

procedure TDarkHintWindow.Paint;
var
  R: TRect;
begin
  if not DarkTheme or (ControlCount > 0) then
  begin
    inherited Paint;
    Exit;
  end;
  R := ClientRect;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := $00303030;
  Canvas.Pen.Color := MUI_BUTTON_EDGE;
  Canvas.Rectangle(R);
  InflateRect(R, -4, -4);
  Canvas.Font.Assign(Font);
  Canvas.Font.Color := clWhite;
  Canvas.Brush.Style := bsClear;
  LCLIntf.DrawText(Canvas.GetUpdatedHandle([csFontValid, csBrushValid]), PChar(Caption), Length(Caption),
    R, DT_LEFT or DT_WORDBREAK or DT_NOPREFIX);
end;

{ A control's own colours (and those inside it), before any is changed:
  a control that takes its parent's colour would otherwise take the dark
  one as its own }
procedure Remember(C: TControl);
var
  O: TThemeOrig;
  I: Integer;
begin
  if Untouched(C) then Exit;
  if not Keeper.Origs.ContainsKey(C) then
  begin
    O.Color := C.Color;
    O.FontColor := C.Font.Color;
    if C is TCustomGrid then O.Fixed := TStringGrid(C).FixedColor else O.Fixed := clNone;
    O.AutoSized := C.AutoSize;
    O.Width := C.Width;
    Keeper.Origs.Add(C, O);
    C.FreeNotification(Keeper);
  end;
  if C is TWinControl then
    for I := 0 to TWinControl(C).ControlCount - 1 do Remember(TWinControl(C).Controls[I]);
end;

{$IFDEF LCLWin32}
var
  { Controls (by window) that took their background from their parent: the
    dark theme stops it }
  ParentPaints: specialize TDictionary<HWND, Boolean> = nil;
{$ENDIF}

procedure ThemeControl(C: TControl);
var
  O: TThemeOrig;
  I: Integer;
  Base, Ink: TColor;
{$IFDEF LCLWin32}
  Info: PWin32WindowInfo;
{$ENDIF}
begin
  if Untouched(C) or not Keeper.Origs.TryGetValue(C, O) then Exit;
  if DarkTheme then
  begin
    Base := O.Color;
    if Base = clDefault then
      if IsField(C) then Base := clWindow else Base := clBtnFace;
    Ink := O.FontColor;
    if Ink = clDefault then Ink := clWindowText;
    C.Color := TC(Base);
    C.Font.Color := TC(Ink);
    // Push buttons stay light, as Windows draws them: their text too
    if C is TCustomButton then C.Font.Color := O.FontColor;
    // Fields to type in: white ink, easier to read
    if (C is TCustomEdit) and (O.FontColor = clDefault) then C.Font.Color := clWhite;
    // Lists to choose from: white on black, as the menus
    if C is TCustomComboBox then
    begin
      C.Color := clBlack;
      C.Font.Color := clWhite;
    end;
    if O.Fixed <> clNone then TStringGrid(C).FixedColor := TC(O.Fixed);
  end
  else
  begin
    C.Color := O.Color;
    C.Font.Color := O.FontColor;
    if O.Fixed <> clNone then TStringGrid(C).FixedColor := O.Fixed;
  end;
  if C is TToolBar then
    if DarkTheme and not Assigned(TToolBar(C).OnPaint) then TToolBar(C).OnPaint := @Keeper.ToolBarPaint
    else if not DarkTheme and (TMethod(TToolBar(C).OnPaint).Code = Pointer(@TThemeKeeper.ToolBarPaint)) then
      TToolBar(C).OnPaint := nil;
{$IFDEF WINDOWS}
  // Themed check boxes, radio buttons, group boxes and status bars ignore
  // the colours: without the visual style they take them
  // A tab's page: Windows paints its body light, whatever its colour (LCL
  // asks for the themed background of a page); dark, its own colour
{$IFDEF LCLWin32}
  if C is TCustomPage then
  begin
    TWinControl(C).HandleNeeded;
    Info := GetWin32WindowInfo(TWinControl(C).Handle);
    if Info <> nil then
    begin
      Info^.isTabPage := ThemeServices.ThemesEnabled and not DarkTheme;
      Info^.needParentPaint := Info^.isTabPage;
    end;
  end
  else if (C is TWinControl) and TWinControl(C).HandleAllocated then
  begin
    // What is on a page draws over the page's light background, in black:
    // dark, it draws its own background and its text in its colour
    Info := GetWin32WindowInfo(TWinControl(C).Handle);
    if Info <> nil then
    begin
      if ParentPaints = nil then ParentPaints := specialize TDictionary<HWND, Boolean>.Create;
      if not ParentPaints.ContainsKey(TWinControl(C).Handle) then
        ParentPaints.Add(TWinControl(C).Handle, Info^.needParentPaint);
      Info^.needParentPaint := ParentPaints[TWinControl(C).Handle] and not DarkTheme;
    end;
  end;
{$ENDIF}
  if ((C is TCustomCheckBox) or (C is TCustomTabControl) or (C is TCustomGroupBox) or
      ((C is TCustomTrackBar) and (TCustomTrackBar(C).Orientation = trHorizontal))) and
     TWinControl(C).HandleAllocated then
    DarkDrawn(TWinControl(C), DarkTheme);
  if ((C is TCustomCheckBox) or (C is TCustomGroupBox) or (C is TCustomComboBox) or
      (C is TCustomTrackBar)) and
     TWinControl(C).HandleAllocated then
  begin
    NoVisualStyle(TWinControl(C).Handle, DarkTheme);
    // Without its style the text is drawn a little wider than measured:
    // room for it, so the last letter isn't cut
    if C is TCustomCheckBox then
      if DarkTheme then
      begin
        C.AutoSize := False;
        C.Width := O.Width + MUIScale(12);
      end
      else
      begin
        C.Width := O.Width;
        C.AutoSize := O.AutoSized;
      end;
  end;
{$ENDIF}
  if C is TWinControl then
    for I := 0 to TWinControl(C).ControlCount - 1 do ThemeControl(TWinControl(C).Controls[I]);
  C.Invalidate;
end;

procedure ThemeForm(Form: TCustomForm);
begin
  if Keeper = nil then Exit;
  // The main window has its own two looks
  if Form = Application.MainForm then Exit;
  Remember(Form);
  ThemeControl(Form);
  SetDarkTitle(Form, DarkTheme);
end;

procedure ThemeAllForms;
var
  I: Integer;
begin
  if Keeper = nil then
  begin
    Keeper := TThemeKeeper.Create(Application);
    Screen.AddHandlerActiveFormChanged(@Keeper.ActiveFormChange);
  end;
  SetDarkIcons(DarkTheme);
  for I := 0 to Screen.CustomFormCount - 1 do ThemeForm(Screen.CustomForms[I]);
end;

{ Dark popup menus: every item drawn here }

type
  TMenuPainter = class
    procedure Measure(Sender: TObject; ACanvas: TCanvas; var AWidth, AHeight: Integer);
    procedure Draw(Sender: TObject; ACanvas: TCanvas; ARect: Types.TRect; AState: LCLType.TOwnerDrawState);
    procedure Popup(Sender: TObject);
  end;

var
  MenuPainter: TMenuPainter = nil;
  OldPopupHandler: TNotifyEvent = nil;
{$IFDEF WINDOWS}
  MenuBrush: HBRUSH = 0;
{$ENDIF}

function MenuText(const Caption: string): string;
var
  I: Integer;
begin
  // Without the & marking the access key ("&&" is an ampersand)
  Result := '';
  I := 1;
  while I <= Length(Caption) do
  begin
    if Caption[I] = '&' then Inc(I);
    if I <= Length(Caption) then Result := Result + Caption[I];
    Inc(I);
  end;
end;

procedure TMenuPainter.Measure(Sender: TObject; ACanvas: TCanvas; var AWidth, AHeight: Integer);
var
  Item: TMenuItem;
begin
  Item := Sender as TMenuItem;
  ACanvas.Font := Screen.MenuFont;
  if Item.IsLine then
  begin
    AHeight := MUIScale(7);
    AWidth := MUIScale(40);
    Exit;
  end;
  AHeight := Max(MUIScale(24), ACanvas.TextHeight('Ag') + MUIScale(8));
  AWidth := MUIScale(28) + ACanvas.TextWidth(MenuText(Item.Caption)) + MUIScale(24);
  if Item.ShortCut <> 0 then Inc(AWidth, ACanvas.TextWidth(ShortCutToText(Item.ShortCut)) + MUIScale(24));
end;

procedure TMenuPainter.Draw(Sender: TObject; ACanvas: TCanvas; ARect: Types.TRect; AState: LCLType.TOwnerDrawState);
var
  Item: TMenuItem;
  Ink: TColor;
  Y, X, H: Integer;
  Arrow: array[0..2] of TPoint;
  S: string;
begin
  Item := Sender as TMenuItem;
  ACanvas.Font := Screen.MenuFont;
  ACanvas.Brush.Style := bsSolid;
  if (LCLType.odSelected in AState) and not Item.IsLine and Item.Enabled then
    ACanvas.Brush.Color := MUI_BUTTON_HOT
  else
    ACanvas.Brush.Color := MUI_PANEL;
  ACanvas.FillRect(ARect);
  if Item.IsLine then
  begin
    Y := (ARect.Top + ARect.Bottom) div 2;
    ACanvas.Pen.Color := MUI_BUTTON_EDGE;
    ACanvas.Line(ARect.Left + MUIScale(8), Y, ARect.Right - MUIScale(8), Y);
    Exit;
  end;
  if Item.Enabled then Ink := MUI_TEXT else Ink := $00707070;
  H := ARect.Bottom - ARect.Top;
  // The tick (a dot for a choice among several), in the accent colour
  if Item.Checked then
  begin
    ACanvas.Pen.Color := MUI_ACCENT;
    ACanvas.Brush.Color := MUI_ACCENT;
    X := ARect.Left + MUIScale(10);
    Y := ARect.Top + H div 2;
    if Item.RadioItem then
      ACanvas.Ellipse(X - MUIScale(3), Y - MUIScale(3), X + MUIScale(4), Y + MUIScale(4))
    else
    begin
      ACanvas.Pen.Width := Max(2, MUIScale(2));
      ACanvas.Line(X - MUIScale(4), Y, X - MUIScale(1), Y + MUIScale(3));
      ACanvas.Line(X - MUIScale(1), Y + MUIScale(3), X + MUIScale(5), Y - MUIScale(4));
      ACanvas.Pen.Width := 1;
    end;
  end;
  ACanvas.Brush.Style := bsClear;
  ACanvas.Font.Color := Ink;
  Y := ARect.Top + (H - ACanvas.TextHeight('Ag')) div 2;
  ACanvas.TextOut(ARect.Left + MUIScale(28), Y, MenuText(Item.Caption));
  if Item.ShortCut <> 0 then
  begin
    S := ShortCutToText(Item.ShortCut);
    if Item.Enabled then ACanvas.Font.Color := MUI_DIM;
    ACanvas.TextOut(ARect.Right - MUIScale(16) - ACanvas.TextWidth(S), Y, S);
  end;
  if Item.Count > 0 then
  begin
    // The arrow of a submenu
    X := ARect.Right - MUIScale(12);
    Y := ARect.Top + H div 2;
    Arrow[0] := Classes.Point(X - MUIScale(3), Y - MUIScale(4));
    Arrow[1] := Classes.Point(X + MUIScale(1), Y);
    Arrow[2] := Classes.Point(X - MUIScale(3), Y + MUIScale(4));
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := Ink;
    ACanvas.Pen.Color := Ink;
    ACanvas.Polygon(Arrow);
  end;
{$IFDEF WINDOWS}
  // Windows draws its own (black) arrow after this: not in the item
  ExcludeClipRect(ACanvas.Handle, ARect.Left, ARect.Top, ARect.Right, ARect.Bottom);
{$ENDIF}
end;

{ Just before a dark menu is shown, with its handles made: its background
  (behind the items, round them) dark too }
procedure TMenuPainter.Popup(Sender: TObject);
{$IFDEF WINDOWS}
var
  Info: TMenuInfo;
{$ENDIF}
begin
{$IFDEF WINDOWS}
  if (Sender is TPopupMenu) and (TMethod(TPopupMenu(Sender).OnDrawItem).Data = Pointer(Self)) then
  begin
    if MenuBrush = 0 then MenuBrush := CreateSolidBrush(ColorToRGB(MUI_PANEL));
    FillChar(Info, SizeOf(Info), 0);
    Info.cbSize := SizeOf(Info);
    Info.fMask := MIM_BACKGROUND or MIM_APPLYTOSUBMENUS;
    Info.hbrBack := MenuBrush;
    SetMenuInfo(TPopupMenu(Sender).Items.Handle, @Info);
  end;
{$ENDIF}
  if Assigned(OldPopupHandler) then OldPopupHandler(Sender);
end;

procedure DarkMenu(Menu: TPopupMenu);
begin
  if MenuPainter = nil then
  begin
    MenuPainter := TMenuPainter.Create;
    OldPopupHandler := OnMenuPopupHandler;
    OnMenuPopupHandler := @MenuPainter.Popup;
  end;
  Menu.OwnerDraw := True;
  Menu.OnMeasureItem := @MenuPainter.Measure;
  Menu.OnDrawItem := @MenuPainter.Draw;
end;

{ TModernNotice }

procedure TModernNotice.Paint;
const
  BEFORE = 'To change to the classic one, click the ';
  AFTER = ' button.';
var
  R: TRect;
  X, Y, LineH: Integer;
begin
  R := ClientRect;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := $00303030;
  Canvas.Pen.Color := MUI_ACCENT;
  Canvas.Pen.Width := 2;
  Canvas.Rectangle(R.Left + 1, R.Top + 1, R.Right, R.Bottom);
  Canvas.Pen.Width := 1;
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Assign(Font);
  Canvas.Font.Height := -MUIScale(14);
  LineH := Canvas.TextHeight('Ag') + MUIScale(4);
  X := MUIScale(14);
  Y := MUIScale(10);
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := MUI_ACCENT;
  Canvas.TextOut(X, Y, 'WARNING');
  Inc(Y, LineH);
  Canvas.Font.Style := [];
  Canvas.Font.Color := clWhite;
  Canvas.TextOut(X, Y, 'This is the modern interface.');
  Inc(Y, LineH);
  // The button's own icon, in the text
  Canvas.TextOut(X, Y, BEFORE);
  Inc(X, Canvas.TextWidth(BEFORE));
  if Images <> nil then
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := MUI_BUTTON;
    Canvas.Pen.Color := MUI_BUTTON_EDGE;
    Canvas.RoundRect(X, Y - MUIScale(3), X + Images.Width + MUIScale(10), Y + LineH - MUIScale(1), 5, 5);
    Images.Draw(Canvas, X + MUIScale(5), Y + (LineH - MUIScale(4) - Images.Height) div 2, IconIndex);
    Inc(X, Images.Width + MUIScale(10));
    Canvas.Brush.Style := bsClear;
  end;
  Canvas.TextOut(X, Y, AFTER);
end;

{ TFlatButton }

constructor TFlatButton.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FImageIndex := -1;
  FIconTop := True;
  ControlStyle := ControlStyle + [csClickEvents] - [csAcceptsControls];
  Font.Color := MUI_TEXT;
  ShowHint := True;
end;

procedure TFlatButton.SetDown(Value: Boolean);
begin
  if FDown = Value then Exit;
  FDown := Value;
  Invalidate;
end;

procedure TFlatButton.MouseEnter;
begin
  inherited MouseEnter;
  FHot := True;
  Invalidate;
end;

procedure TFlatButton.MouseLeave;
begin
  inherited MouseLeave;
  FHot := False;
  Invalidate;
end;

procedure TFlatButton.TextChanged;
begin
  inherited TextChanged;
  Invalidate;
end;

procedure TFlatButton.SetEnabled(Value: Boolean);
begin
  inherited SetEnabled(Value);
  Invalidate;
end;

procedure TFlatButton.Paint;
var
  R: TRect;
  Back, Edge, Ink: TColor;
  IconW, IconH, TextW, TextH, X, Y, Gap: Integer;
  HasIcon: Boolean;
begin
  R := ClientRect;
  if FDown then
  begin
    Back := MUI_ACCENT;
    Edge := clWhite;
    Ink := MUI_ACCENT_TEXT;
  end
  else
  begin
    if FHot and Enabled then Back := MUI_BUTTON_HOT else Back := MUI_BUTTON;
    Edge := MUI_BUTTON_EDGE;
    if Enabled then Ink := MUI_TEXT else Ink := $00777777;
  end;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := Parent.Brush.Color;
  Canvas.FillRect(R);
  Canvas.Brush.Color := Back;
  Canvas.Pen.Color := Edge;
  Canvas.RoundRect(R.Left, R.Top, R.Right, R.Bottom, MUIScale(6), MUIScale(6));
  HasIcon := (FImages <> nil) and (FImageIndex >= 0);
  if HasIcon then
  begin
    IconW := FImages.Width;
    IconH := FImages.Height;
  end
  else
  begin
    IconW := 0;
    IconH := 0;
  end;
  Canvas.Font.Assign(Font);
  Canvas.Font.Color := Ink;
  if FDown then Canvas.Font.Style := [fsBold];
  Canvas.Brush.Style := bsClear;
  TextW := Canvas.TextWidth(Caption);
  TextH := Canvas.TextHeight('Ag');
  if Caption = '' then TextH := 0;
  Gap := MUIScale(4);
  if FIconTop then
  begin
    Y := (R.Bottom - IconH - TextH - Ord(HasIcon and (Caption <> '')) * Gap) div 2;
    if HasIcon then FImages.Draw(Canvas, (R.Right - IconW) div 2, Y, FImageIndex, Enabled);
    if Caption <> '' then
      Canvas.TextOut((R.Right - TextW) div 2, Y + IconH + Ord(HasIcon) * Gap, Caption);
  end
  else
  begin
    X := (R.Right - IconW - TextW - Ord(HasIcon and (Caption <> '')) * Gap) div 2;
    if HasIcon then FImages.Draw(Canvas, X, (R.Bottom - IconH) div 2, FImageIndex, Enabled);
    if Caption <> '' then
      Canvas.TextOut(X + IconW + Ord(HasIcon) * Gap, (R.Bottom - TextH) div 2, Caption);
  end;
end;

{ TDarkPanel }

constructor TDarkPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csAcceptsControls];
  Color := MUI_BACK;
end;

procedure TDarkPanel.Paint;
begin
  Canvas.Brush.Color := Color;
  Canvas.FillRect(ClientRect);
end;

{ TPaletteBox }

constructor TPaletteBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csAcceptsControls];
  Color := MUI_PANEL;
  Font.Color := MUI_DIM;
end;

function TPaletteBox.TitleHeight: Integer;
begin
  Result := MUIScale(24);
end;

procedure TPaletteBox.Paint;
var
  R: TRect;
begin
  R := ClientRect;
  Canvas.Brush.Color := Parent.Brush.Color;
  Canvas.FillRect(R);
  Canvas.Brush.Color := MUI_PANEL;
  Canvas.Pen.Color := MUI_EDGE;
  Canvas.RoundRect(R.Left, R.Top, R.Right, R.Bottom, MUIScale(8), MUIScale(8));
  Canvas.Brush.Color := MUI_TITLE;
  Canvas.Pen.Color := MUI_TITLE;
  Canvas.Rectangle(R.Left + 1, R.Top + MUIScale(4), R.Right - 1, R.Top + TitleHeight);
  Canvas.RoundRect(R.Left + 1, R.Top + 1, R.Right - 1, R.Top + TitleHeight, MUIScale(8), MUIScale(8));
  Canvas.Font.Assign(Font);
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Height := -MUIScale(11);
  Canvas.Brush.Style := bsClear;
  Canvas.TextOut(MUIScale(10), (TitleHeight - Canvas.TextHeight('A')) div 2, UpperCase(Caption));
  Canvas.Brush.Style := bsSolid;
end;

{ TCassette }

constructor TCassette.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Color := $001D1D1D;
end;

procedure TCassette.Show(Progress: Double; Playing: Boolean);
begin
  if Playing then FTurn := (FTurn + 1) mod 6;
  if (Abs(Progress - FProgress) > 0.001) or Playing then
  begin
    FProgress := Progress;
    Invalidate;
  end;
end;

procedure TCassette.TextChanged;
begin
  inherited TextChanged;
  Invalidate;
end;

procedure TCassette.SetLoaded(Value: Boolean);
begin
  if FLoaded = Value then Exit;
  FLoaded := Value;
  Invalidate;
end;

{ A cassette player without a tape: its recessed compartment with the two
  empty spindles, the head, the capstan and the pinch roller }
procedure DrawEmptyPlayer(Cv: TCanvas; R: TRect; Back: TColor);
const
  CASE_COL = $00262626;
  CASE_EDGE = $00585858;
  WELL = $00141414;
  METAL = $00A0A0A0;
var
  W, H, I, X, K, RS: Integer;
  A: Double;
  Pts: array[0..3] of TPoint;

  function PX(F: Double): Integer;
  begin
    Result := R.Left + Round(W * F);
  end;

  function PY(F: Double): Integer;
  begin
    Result := R.Top + Round(H * F);
  end;

  procedure Circle(CX, CY, Rad: Integer; Pen, Fill: TColor);
  begin
    Cv.Pen.Color := Pen;
    Cv.Brush.Color := Fill;
    Cv.Ellipse(CX - Rad, CY - Rad, CX + Rad + 1, CY + Rad + 1);
  end;

begin
  Cv.Brush.Style := bsSolid;
  Cv.Brush.Color := Back;
  Cv.FillRect(R);
  W := R.Right - R.Left;
  H := R.Bottom - R.Top;
  if W > H * 158 div 100 then
  begin
    W := H * 158 div 100;
    R.Left := R.Left + (R.Right - R.Left - W) div 2;
    R.Right := R.Left + W;
  end;
  // The player's front and the compartment sunk into it
  Cv.Pen.Color := CASE_EDGE;
  Cv.Brush.Color := CASE_COL;
  Cv.RoundRect(R.Left, R.Top, R.Right, R.Bottom, W div 18, W div 18);
  Cv.Pen.Color := $00080808;
  Cv.Brush.Color := WELL;
  Cv.RoundRect(PX(0.06), PY(0.1), PX(0.94), PY(0.9), W div 30, W div 30);
  RS := Math.Max(4, Round(W * 0.055));
  // The two spindles, with their teeth
  for I := 0 to 1 do
  begin
    X := PX(0.29 + I * 0.42);
    Circle(X, PY(0.44), RS * 14 div 10, $00303030, $001C1C1C);
    Circle(X, PY(0.44), RS, $00606060, $00808080);
    Circle(X, PY(0.44), RS * 6 div 10, $00202020, $00202020);
    Cv.Pen.Color := $00B0B0B0;
    Cv.Pen.Width := Math.Max(2, RS div 4);
    for K := 0 to 5 do
    begin
      A := K * Pi / 3;
      Cv.Line(X + Round(Cos(A) * RS * 0.35), PY(0.44) + Round(Sin(A) * RS * 0.35),
        X + Round(Cos(A) * RS * 0.62), PY(0.44) + Round(Sin(A) * RS * 0.62));
    end;
    Cv.Pen.Width := 1;
  end;
  // The head block, the capstan and the pinch roller along the bottom
  Pts[0] := Classes.Point(PX(0.4), PY(0.9) - 1);
  Pts[1] := Classes.Point(PX(0.44), PY(0.68));
  Pts[2] := Classes.Point(PX(0.56), PY(0.68));
  Pts[3] := Classes.Point(PX(0.6), PY(0.9) - 1);
  Cv.Pen.Color := $00505050;
  Cv.Brush.Color := $00383838;
  Cv.Polygon(Pts);
  Cv.Brush.Color := METAL;
  Cv.Pen.Color := $00606060;
  Cv.Rectangle(PX(0.475), PY(0.7), PX(0.525), PY(0.8));
  Circle(PX(0.26), PY(0.8), Math.Max(2, W div 50), $00404040, METAL);
  Circle(PX(0.74), PY(0.8), Math.Max(2, W div 50), $00404040, METAL);
  Circle(PX(0.15), PY(0.8), Math.Max(3, W div 28), $00101010, $00181818);
  Circle(PX(0.85), PY(0.8), Math.Max(3, W div 28), $00101010, $00181818);
end;

{ A compact cassette: its shell with screws, the label (the tape's name and
  the rainbow stripes), the window with the tape wound on both reels (as much
  on each as has been played), the hubs turning while it plays, and the
  head opening below }
procedure DrawCassette(Cv: TCanvas; R: TRect; Back: TColor; Progress: Double; Turn: Integer;
  const Title: string);
const
  SHELL = $00353535;
  SHELL_EDGE = $00585858;
  LABEL_PAPER = $00C8E2EC;     // cream
  INK = $00803010;             // blue pen
  TAPE = $001E2D46;            // brown oxide
  TAPE_EDGE = $002C4466;
  STRIPES: array[0..3] of TColor = ($000000D8, $0000D8F0, $0000C000, $00D8C000);
var
  Win: TRect;
  W, H, LX1, LX2, LY1, LY2, HubY, Hub1, Hub2, RH, RMax, I, SW, X, Y: Integer;
  P: Double;
  Pts: array[0..3] of TPoint;
  S: string;

  function PX(F: Double): Integer;
  begin
    Result := R.Left + Round(W * F);
  end;

  function PY(F: Double): Integer;
  begin
    Result := R.Top + Round(H * F);
  end;

  procedure Screw(CX, CY: Integer);
  var
    SR: Integer;
  begin
    SR := Math.Max(2, W div 70);
    Cv.Pen.Color := $00242424;
    Cv.Brush.Color := $00808080;
    Cv.Ellipse(CX - SR, CY - SR, CX + SR + 1, CY + SR + 1);
    Cv.Pen.Color := $00404040;
    Cv.Line(CX - SR + 1, CY, CX + SR, CY);
  end;

  procedure Pack(CX: Integer; Radius: Double);
  var
    PR: Integer;
  begin
    PR := Round(Radius);
    Cv.Pen.Color := TAPE_EDGE;
    Cv.Brush.Color := TAPE;
    Cv.Ellipse(CX - PR, HubY - PR, CX + PR + 1, HubY + PR + 1);
  end;

  procedure HubWheel(CX: Integer);
  var
    K: Integer;
    A: Double;
  begin
    // The white hub with its teeth, turning
    Cv.Pen.Color := $00909090;
    Cv.Brush.Color := $00E8E8E8;
    Cv.Ellipse(CX - RH, HubY - RH, CX + RH + 1, HubY + RH + 1);
    Cv.Brush.Color := $00202020;
    Cv.Pen.Color := $00202020;
    Cv.Ellipse(CX - RH * 6 div 10, HubY - RH * 6 div 10, CX + RH * 6 div 10 + 1, HubY + RH * 6 div 10 + 1);
    Cv.Pen.Color := $00E8E8E8;
    Cv.Pen.Width := Math.Max(2, RH div 4);
    // Anticlockwise, as the reels of a cassette playing (the screen's Y
    // grows downwards, so the angle goes down)
    for K := 0 to 5 do
    begin
      A := (K * 60 - Turn * 10) * Pi / 180;
      Cv.Line(CX + Round(Cos(A) * RH * 0.35), HubY + Round(Sin(A) * RH * 0.35),
        CX + Round(Cos(A) * RH * 0.62), HubY + Round(Sin(A) * RH * 0.62));
    end;
    Cv.Pen.Width := 1;
  end;

begin
  Cv.Brush.Style := bsSolid;
  Cv.Brush.Color := Back;
  Cv.FillRect(R);
  // As wide as a cassette is for its height (100 x 63 mm), centred
  W := R.Right - R.Left;
  H := R.Bottom - R.Top;
  if W > H * 158 div 100 then
  begin
    W := H * 158 div 100;
    R.Left := R.Left + (R.Right - R.Left - W) div 2;
    R.Right := R.Left + W;
  end;
  // The shell
  Cv.Pen.Color := SHELL_EDGE;
  Cv.Brush.Color := SHELL;
  Cv.RoundRect(R.Left, R.Top, R.Right, R.Bottom, W div 18, W div 18);
  Screw(PX(0.045), PY(0.07));
  Screw(PX(0.955), PY(0.07));
  Screw(PX(0.045), PY(0.93));
  Screw(PX(0.955), PY(0.93));
  // The head opening at the bottom: a trapezoid with the capstan holes
  Pts[0] := Classes.Point(PX(0.17), R.Bottom - 1);
  Pts[1] := Classes.Point(PX(0.23), PY(0.75));
  Pts[2] := Classes.Point(PX(0.77), PY(0.75));
  Pts[3] := Classes.Point(PX(0.83), R.Bottom - 1);
  Cv.Pen.Color := SHELL_EDGE;
  Cv.Brush.Color := $002A2A2A;
  Cv.Polygon(Pts);
  Cv.Brush.Color := $00141414;
  Cv.Pen.Color := $00141414;
  for I := 0 to 1 do
  begin
    X := PX(0.32 + I * 0.36);
    Y := PY(0.875);
    Cv.Ellipse(X - W div 50, Y - W div 50, X + W div 50 + 1, Y + W div 50 + 1);
    X := PX(0.42 + I * 0.16);
    Cv.Rectangle(X - W div 70, Y - W div 70, X + W div 70 + 1, Y + W div 70 + 1);
  end;
  Screw(PX(0.5), PY(0.86));
  // The label
  LX1 := PX(0.075);
  LX2 := PX(0.925);
  LY1 := PY(0.09);
  LY2 := PY(0.68);
  Cv.Pen.Color := $009AB4C0;
  Cv.Brush.Color := LABEL_PAPER;
  Cv.RoundRect(LX1, LY1, LX2, LY2, W div 40, W div 40);
  // The rainbow stripes across its right end, slanted
  SW := Math.Max(2, W div 40);
  Cv.Pen.Style := psClear;
  for I := 0 to 3 do
  begin
    X := LX2 - SW * 8 + I * SW;
    Pts[0] := Classes.Point(X, LY2 - 1);
    Pts[1] := Classes.Point(X + SW * 3, LY1 + H div 5);
    Pts[2] := Classes.Point(X + SW * 4, LY1 + H div 5);
    Pts[3] := Classes.Point(X + SW, LY2 - 1);
    Cv.Brush.Color := STRIPES[I];
    Cv.Polygon(Pts);
  end;
  Cv.Pen.Style := psSolid;
  // The tape's name, written on it
  S := Title;
  if S <> '' then
  begin
    Cv.Font.Name := 'Segoe Print';
    Cv.Font.Height := -Math.Max(9, H div 9);
    Cv.Font.Color := INK;
    Cv.Brush.Style := bsClear;
    while (S <> '') and (Cv.TextWidth(S) > LX2 - LX1 - W div 6) do
      S := Copy(S, 1, Length(S) - 1);
    Cv.TextOut(LX1 + W div 30, LY1 + Math.Max(1, H div 50), S);
    Cv.Brush.Style := bsSolid;
  end;
  // The window, with the tape on the reels: the left one gives it, the
  // right one takes it (the areas are what they would be)
  HubY := PY(0.44);
  Hub1 := PX(0.29);
  Hub2 := PX(0.71);
  RH := Math.Max(4, Round(W * 0.055));
  RMax := Round(W * 0.2);
  Win := Classes.Rect(PX(0.25), HubY - Round(H * 0.17), PX(0.75), HubY + Round(H * 0.17));
  Cv.Pen.Color := $00505050;
  Cv.Brush.Color := $00262626;
  Cv.Rectangle(Win);
  P := EnsureRange(Progress, 0, 1);
  Cv.ClipRect := Classes.Rect(Win.Left + 1, Win.Top + 1, Win.Right - 1, Win.Bottom - 1);
  Cv.Clipping := True;
  Pack(Hub1, Sqrt(Sqr(RH * 1.3) + (1 - P) * (Sqr(RMax) - Sqr(RH * 1.3))));
  Pack(Hub2, Sqrt(Sqr(RH * 1.3) + P * (Sqr(RMax) - Sqr(RH * 1.3))));
  Cv.Clipping := False;
  // The holes in the label for the hubs, and the hubs
  Cv.Pen.Color := $009AB4C0;
  Cv.Brush.Color := $00262626;
  for I := 0 to 1 do
  begin
    if I = 0 then X := Hub1 else X := Hub2;
    Cv.Ellipse(X - RH * 14 div 10, HubY - RH * 14 div 10, X + RH * 14 div 10 + 1, HubY + RH * 14 div 10 + 1);
  end;
  HubWheel(Hub1);
  HubWheel(Hub2);
end;

procedure TCassette.Paint;
begin
  if FLoaded then
    DrawCassette(Canvas, ClientRect, Parent.Brush.Color, FProgress, FTurn, Caption)
  else
    DrawEmptyPlayer(Canvas, ClientRect, Parent.Brush.Color);
end;

initialization
  HintWindowClass := TDarkHintWindow;

end.

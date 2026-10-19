{ MdView: a Markdown viewer for README.md (Help > Documentation). It shows
  the subset of Markdown the manual uses: headings, paragraphs with
  **bold**, *italic*, `code` and [links](#anchor), "- " and "1. " lists (one
  level of nesting), fenced code blocks, pipe tables and --- rules. Links to
  #anchors scroll to the heading (GitHub's anchor names), others open in
  the browser. Find looks for text and highlights the words that match. }
unit MdView;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, Graphics, Controls, StdCtrls, Forms, LCLType, LCLIntf;

type
  TMdStyle = set of (msBold, msItalic, msCode, msLink);

  { A word (or part of one) of running text }
  TMdAtom = record
    Text: string;
    Style: TMdStyle;
    Link: string;
    Space: Boolean;        // a space before it (else it sticks to the one before)
  end;
  TMdAtoms = array of TMdAtom;

  TMdBlockKind = (mbPara, mbHeading, mbBullet, mbNumber, mbCode, mbTable, mbRule);

  TMdBlock = record
    Kind: TMdBlockKind;
    Level: Integer;        // heading 1-4, list nesting 0-1
    Number: string;        // "3." for numbered lists
    Atoms: TMdAtoms;
    Lines: TStringList;    // code blocks
    Cells: array of array of TMdAtoms;   // tables: rows (0 = header) and cells
    Anchor: string;        // headings
  end;

  TMdItemKind = (miText, miBox, miLine);

  { Something laid out on the page, in document coordinates }
  TMdItem = record
    Kind: TMdItemKind;
    R: TRect;
    Text: string;
    Style: TMdStyle;
    Size: Integer;         // font size, points
    Color: TColor;
    Link: string;
  end;

  TMdView = class(TCustomControl)
  private
    FBlocks: array of TMdBlock;
    FItems: array of TMdItem;
    FAnchors: TStringList;     // anchor = Y (as an object)
    FScroll: TScrollBar;
    FTop: Integer;
    FHeight: Integer;          // of the whole document
    FLayoutWidth: Integer;
    FMeasure: TBitmap;
    FFound: array of Integer;  // items highlighted by Find
    FFindFrom: Integer;        // where the next Find starts in FPlain
    FPlain: string;            // the text items joined, for Find
    FPlainItem: array of Integer;   // FPlain position -> item
    procedure Clear;
    procedure Parse(const Source: TStrings);
    procedure Layout;
    procedure SetFont(C: TCanvas; Style: TMdStyle; Size: Integer);
    procedure AddItem(Kind: TMdItemKind; const R: TRect; const AText: string; Style: TMdStyle;
      Size: Integer; AColor: TColor; const Link: string = '');
    function WrapAtoms(const Atoms: TMdAtoms; X, Y, AWidth, Size: Integer; Bold: Boolean;
      AColor: TColor; Emit: Boolean): Integer;
    function AtomsWidth(const Atoms: TMdAtoms; Size: Integer): Integer;
    function MinAtomWidth(const Atoms: TMdAtoms; Size: Integer): Integer;
    procedure ScrollChange(Sender: TObject);
    procedure SetTop(Value: Integer);
    function ItemAt(X, Y: Integer): Integer;
    procedure UpdateScroll;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure LoadFromFile(const FileName: string);
    procedure LoadFromText(const AText: string);
    { Scroll to a heading by its anchor ("7-divmmc-and-sd-cards") }
    function GoToAnchor(const Anchor: string): Boolean;
    { Find the next match of What (case-insensitive) from the last one;
      False if there is none (the search then starts again at the top) }
    function Find(const What: string): Boolean;
  end;

{ GitHub's anchor for a heading: lower case, punctuation removed, spaces to - }
function MdAnchor(const Heading: string): string;
{ The atoms of a line of Markdown text }
function ParseInline(const S: string): TMdAtoms;

implementation

const
  BASE_SIZE = 10;
  HEADING_SIZES: array[1..4] of Integer = (20, 16, 13, 11);
  LINK_COLOR = $C05A00;      // BGR
  CODE_COLOR = $202090;
  CODE_BACK = $F2F0F0;
  RULE_COLOR = $D8D8D8;
  FIND_BACK = $60E8FF;
  HEADING_COLOR = $503010;

function MdAnchor(const Heading: string): string;
var
  Ch: Char;
begin
  Result := '';
  for Ch in LowerCase(Heading) do
    if Ch in ['a'..'z', '0'..'9', '_', '-'] then Result := Result + Ch
    else if Ch = ' ' then Result := Result + '-'
    else if Ord(Ch) >= 128 then Result := Result + Ch;   // UTF-8 letters stay
end;

{ The plain text of atoms (for anchors) }
function AtomsText(const Atoms: TMdAtoms): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(Atoms) do
  begin
    if Atoms[I].Space and (Result <> '') then Result := Result + ' ';
    Result := Result + Atoms[I].Text;
  end;
end;

function ParseInline(const S: string): TMdAtoms;
var
  Atoms: TMdAtoms;
  Word: string;
  Pending: Boolean;          // a space before the next atom

  procedure Flush(Style: TMdStyle; const Link: string);
  var
    N: Integer;
  begin
    if Word = '' then Exit;
    N := Length(Atoms);
    SetLength(Atoms, N + 1);
    Atoms[N].Text := Word;
    Atoms[N].Style := Style;
    Atoms[N].Link := Link;
    Atoms[N].Space := Pending;
    if (Link = '') and ((Pos('http://', Word) = 1) or (Pos('https://', Word) = 1)) then
    begin
      Atoms[N].Link := Word;
      Include(Atoms[N].Style, msLink);
    end;
    Pending := False;
    Word := '';
  end;

  // Text from I to Stop-1 with Style; * and ** toggle, ` starts code,
  // [ starts a link
  procedure Run(I, Stop: Integer; Style: TMdStyle; const Link: string);
  var
    J, K, Ticks: Integer;
    Close, Target, Code: string;
    Parts: TStringArray;
    Inner: TMdStyle;
  begin
    while I < Stop do
    begin
      if S[I] = ' ' then
      begin
        Flush(Style, Link);
        Pending := True;
        Inc(I);
      end
      else if (S[I] = '\') and (I + 1 < Stop) and (S[I + 1] in ['\', '`', '*', '_', '|', '[', ']', '#', '-']) then
      begin
        Word := Word + S[I + 1];
        Inc(I, 2);
      end
      else if S[I] = '`' then
      begin
        Ticks := 0;
        while (I + Ticks < Stop) and (S[I + Ticks] = '`') do Inc(Ticks);
        Close := StringOfChar('`', Ticks);
        K := Pos(Close, Copy(S, I + Ticks, Stop - I - Ticks));
        if K = 0 then
        begin
          Word := Word + Close;
          Inc(I, Ticks);
          Continue;
        end;
        Flush(Style, Link);
        Code := Copy(S, I + Ticks, K - 1);
        I := I + Ticks + K - 1 + Ticks;
        if (Length(Code) > 1) and (Code[1] = ' ') and (Code[Length(Code)] = ' ') then
          Code := Copy(Code, 2, Length(Code) - 2);
        // One atom per word, so long code can wrap at its spaces
        Parts := Code.Split([' '], TStringSplitOptions.ExcludeEmpty);
        for J := 0 to High(Parts) do
        begin
          if J > 0 then Pending := True;
          Word := Parts[J];
          Flush(Style + [msCode], Link);
        end;
      end
      else if (S[I] = '*') and (I + 1 < Stop) and (S[I + 1] = '*') then
      begin
        // **bold**: needs a closing ** after a non-space
        K := Pos('**', Copy(S, I + 2, Stop - I - 2));
        if (K > 1) and (S[I + 2] <> ' ') and (S[I + 2 + K - 2] <> ' ') then
        begin
          Flush(Style, Link);
          Run(I + 2, I + 2 + K - 1, Style + [msBold], Link);
          Flush(Style + [msBold], Link);
          I := I + 2 + K - 1 + 2;
        end
        else
        begin
          Word := Word + '**';
          Inc(I, 2);
        end;
      end
      else if (S[I] = '*') and (I + 1 < Stop) and (S[I + 1] <> ' ') then
      begin
        K := Pos('*', Copy(S, I + 1, Stop - I - 1));
        if (K > 1) and (S[I + K - 1] <> ' ') then
        begin
          Flush(Style, Link);
          Run(I + 1, I + K, Style + [msItalic], Link);
          Flush(Style + [msItalic], Link);
          I := I + K + 1;
        end
        else
        begin
          Word := Word + '*';
          Inc(I);
        end;
      end
      else if (S[I] = '[') and (Link = '') then
      begin
        // [text](target)
        J := I + 1;
        K := 1;
        while (J < Stop) and (K > 0) do
        begin
          if S[J] = '[' then Inc(K)
          else if S[J] = ']' then Dec(K);
          if K > 0 then Inc(J);
        end;
        if (J + 1 < Stop) and (S[J] = ']') and (S[J + 1] = '(') and
           (Pos(')', Copy(S, J + 2, Stop - J - 2)) > 0) then
        begin
          K := Pos(')', Copy(S, J + 2, Stop - J - 2));
          Target := Trim(Copy(S, J + 2, K - 1));
          Flush(Style, Link);
          Inner := Style + [msLink];
          Run(I + 1, J, Inner, Target);
          Flush(Inner, Target);
          I := J + 2 + K;
        end
        else
        begin
          Word := Word + '[';
          Inc(I);
        end;
      end
      else
      begin
        Word := Word + S[I];
        Inc(I);
      end;
    end;
    Flush(Style, Link);
  end;

begin
  Atoms := nil;
  Word := '';
  Pending := False;
  Run(1, Length(S) + 1, [], '');
  Result := Atoms;
end;

{ The cells of a table row "| a | b |" (\| is a | inside a cell) }
function SplitRow(const S: string): TStringArray;
var
  T, Cell: string;
  I, N: Integer;
  InCode: Boolean;
begin
  Result := nil;
  T := Trim(S);
  if (T <> '') and (T[1] = '|') then Delete(T, 1, 1);
  if (T <> '') and (T[Length(T)] = '|') and ((Length(T) < 2) or (T[Length(T) - 1] <> '\')) then
    SetLength(T, Length(T) - 1);
  Cell := '';
  InCode := False;
  I := 1;
  while I <= Length(T) do
  begin
    if (T[I] = '\') and (I < Length(T)) and (T[I + 1] = '|') then
    begin
      Cell := Cell + '\|';
      Inc(I, 2);
      Continue;
    end;
    if T[I] = '`' then InCode := not InCode;
    if (T[I] = '|') and not InCode then
    begin
      N := Length(Result);
      SetLength(Result, N + 1);
      Result[N] := Trim(Cell);
      Cell := '';
    end
    else
      Cell := Cell + T[I];
    Inc(I);
  end;
  N := Length(Result);
  SetLength(Result, N + 1);
  Result[N] := Trim(Cell);
end;

{ A table cell's text: \| inside code is shown as | }
function CellAtoms(const S: string): TMdAtoms;
var
  I: Integer;
begin
  Result := ParseInline(S);
  for I := 0 to High(Result) do
    if msCode in Result[I].Style then
      Result[I].Text := StringReplace(Result[I].Text, '\|', '|', [rfReplaceAll]);
end;

function IsTableSeparator(const S: string): Boolean;
var
  Ch: Char;
begin
  Result := Pos('-', S) > 0;
  for Ch in Trim(S) do
    if not (Ch in ['|', '-', ':', ' ']) then Exit(False);
end;

{ "# Title" to "#### Title" (a # with no space after it is just text) }
function IsHeading(const S: string): Boolean;
var
  I: Integer;
begin
  I := 1;
  while (I <= Length(S)) and (S[I] = '#') do Inc(I);
  Result := (I > 1) and (I <= 7) and (I <= Length(S)) and (S[I] = ' ');
end;

function IsNumbered(const S: string; out Num, Rest: string): Boolean;
var
  I: Integer;
begin
  I := 1;
  while (I <= Length(S)) and (S[I] in ['0'..'9']) do Inc(I);
  Result := (I > 1) and (I < Length(S)) and (S[I] = '.') and (S[I + 1] = ' ');
  if Result then
  begin
    Num := Copy(S, 1, I);
    Rest := Trim(Copy(S, I + 2, MaxInt));
  end;
end;

{ TMdView }

constructor TMdView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Color := clWhite;
  TabStop := True;
  DoubleBuffered := True;
  FAnchors := TStringList.Create;
  FMeasure := TBitmap.Create;
  FMeasure.SetSize(4, 4);
  FScroll := TScrollBar.Create(Self);
  FScroll.Parent := Self;
  FScroll.Kind := sbVertical;
  FScroll.Align := alRight;
  FScroll.TabStop := False;
  FScroll.OnChange := @ScrollChange;
end;

destructor TMdView.Destroy;
begin
  Clear;
  FAnchors.Free;
  FMeasure.Free;
  inherited Destroy;
end;

procedure TMdView.Clear;
var
  I: Integer;
begin
  for I := 0 to High(FBlocks) do FBlocks[I].Lines.Free;
  FBlocks := nil;
  FItems := nil;
  FFound := nil;
  FAnchors.Clear;
end;

procedure TMdView.LoadFromFile(const FileName: string);
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.LoadFromFile(FileName);
    Parse(L);
  finally
    L.Free;
  end;
end;

procedure TMdView.LoadFromText(const AText: string);
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.Text := AText;
    Parse(L);
  finally
    L.Free;
  end;
end;

procedure TMdView.Parse(const Source: TStrings);
var
  I, N, Indent: Integer;
  Line, T, Para, Num, Rest: string;
  Kind: TMdBlockKind;
  Level: Integer;
  Cells: TStringArray;
  Used: TStringList;

  function NewBlock(AKind: TMdBlockKind): Integer;
  begin
    Result := Length(FBlocks);
    SetLength(FBlocks, Result + 1);
    FBlocks[Result].Kind := AKind;
    FBlocks[Result].Lines := nil;
  end;

  // A line that starts another kind of block (ends a paragraph or item)
  function StartsBlock(const S: string): Boolean;
  var
    U, A, B: string;
  begin
    U := TrimLeft(S);
    Result := (U = '') or IsHeading(U) or (Copy(U, 1, 2) = '- ') or
      (Copy(U, 1, 3) = '```') or (Copy(U, 1, 1) = '|') or (Trim(U) = '---') or
      IsNumbered(U, A, B);
  end;

begin
  Clear;
  Used := TStringList.Create;
  try
  I := 0;
  while I < Source.Count do
  begin
    Line := Source[I];
    T := Trim(Line);
    if T = '' then
    begin
      Inc(I);
      Continue;
    end;
    if Copy(T, 1, 3) = '```' then
    begin
      N := NewBlock(mbCode);
      FBlocks[N].Lines := TStringList.Create;
      Inc(I);
      while (I < Source.Count) and (Copy(Trim(Source[I]), 1, 3) <> '```') do
      begin
        FBlocks[N].Lines.Add(Source[I]);
        Inc(I);
      end;
      Inc(I);
      Continue;
    end;
    if (T = '---') or (T = '***') then
    begin
      NewBlock(mbRule);
      Inc(I);
      Continue;
    end;
    if IsHeading(T) then
    begin
      Level := 0;
      while (Level < Length(T)) and (T[Level + 1] = '#') do Inc(Level);
      N := NewBlock(mbHeading);
      FBlocks[N].Level := Min(Level, 4);
      FBlocks[N].Atoms := ParseInline(Trim(Copy(T, Level + 1, MaxInt)));
      FBlocks[N].Anchor := MdAnchor(AtomsText(FBlocks[N].Atoms));
      // As GitHub: the second heading with the same anchor gets -1, then -2
      Num := FBlocks[N].Anchor;
      Indent := 0;
      while Used.IndexOf(FBlocks[N].Anchor) >= 0 do
      begin
        Inc(Indent);
        FBlocks[N].Anchor := Num + '-' + IntToStr(Indent);
      end;
      Used.Add(FBlocks[N].Anchor);
      Inc(I);
      Continue;
    end;
    if (T[1] = '|') and (I + 1 < Source.Count) and IsTableSeparator(Source[I + 1]) then
    begin
      N := NewBlock(mbTable);
      Cells := SplitRow(T);
      SetLength(FBlocks[N].Cells, 1);
      SetLength(FBlocks[N].Cells[0], Length(Cells));
      for Level := 0 to High(Cells) do FBlocks[N].Cells[0][Level] := CellAtoms(Cells[Level]);
      Inc(I, 2);
      while (I < Source.Count) and (Copy(Trim(Source[I]), 1, 1) = '|') do
      begin
        Cells := SplitRow(Source[I]);
        Level := Length(FBlocks[N].Cells);
        SetLength(FBlocks[N].Cells, Level + 1);
        SetLength(FBlocks[N].Cells[Level], Length(FBlocks[N].Cells[0]));
        for Indent := 0 to Min(High(Cells), High(FBlocks[N].Cells[0])) do
          FBlocks[N].Cells[Level][Indent] := CellAtoms(Cells[Indent]);
        Inc(I);
      end;
      Continue;
    end;
    // Paragraph or list item: the lines that follow until a blank line or
    // another block
    Indent := Length(Line) - Length(TrimLeft(Line));
    Num := '';
    if Copy(T, 1, 2) = '- ' then
    begin
      Kind := mbBullet;
      Para := Trim(Copy(T, 3, MaxInt));
    end
    else if IsNumbered(T, Num, Rest) then
    begin
      Kind := mbNumber;
      Para := Rest;
    end
    else
    begin
      Kind := mbPara;
      Para := T;
    end;
    Inc(I);
    while (I < Source.Count) and not StartsBlock(Source[I]) do
    begin
      Para := Para + ' ' + Trim(Source[I]);
      Inc(I);
    end;
    N := NewBlock(Kind);
    if Kind = mbPara then FBlocks[N].Level := 0
    else FBlocks[N].Level := Min(Indent div 2, 1);
    FBlocks[N].Number := Num;
    FBlocks[N].Atoms := ParseInline(Para);
  end;
  finally
    Used.Free;
  end;
  FLayoutWidth := -1;
  FTop := 0;
  Layout;
  Invalidate;
end;

procedure TMdView.SetFont(C: TCanvas; Style: TMdStyle; Size: Integer);
begin
  if msCode in Style then
  begin
    {$IFDEF WINDOWS}
    C.Font.Name := 'Consolas';
    {$ELSE}
    {$IFDEF DARWIN}
    C.Font.Name := 'Menlo';
    {$ELSE}
    C.Font.Name := 'Monospace';
    {$ENDIF}
    {$ENDIF}
  end
  else
    C.Font.Name := 'default';
  C.Font.Size := Size;
  C.Font.Style := [];
  if msBold in Style then C.Font.Style := C.Font.Style + [fsBold];
  if msItalic in Style then C.Font.Style := C.Font.Style + [fsItalic];
  if msLink in Style then C.Font.Style := C.Font.Style + [fsUnderline];
end;

procedure TMdView.AddItem(Kind: TMdItemKind; const R: TRect; const AText: string;
  Style: TMdStyle; Size: Integer; AColor: TColor; const Link: string);
var
  N: Integer;
begin
  N := Length(FItems);
  SetLength(FItems, N + 1);
  FItems[N].Kind := Kind;
  FItems[N].R := R;
  FItems[N].Text := AText;
  FItems[N].Style := Style;
  FItems[N].Size := Size;
  FItems[N].Color := AColor;
  FItems[N].Link := Link;
end;

function TMdView.AtomsWidth(const Atoms: TMdAtoms; Size: Integer): Integer;
var
  I: Integer;
  C: TCanvas;
begin
  C := FMeasure.Canvas;
  Result := 0;
  for I := 0 to High(Atoms) do
  begin
    SetFont(C, Atoms[I].Style, Size);
    Inc(Result, C.TextWidth(Atoms[I].Text));
    if Atoms[I].Space and (I > 0) then
    begin
      SetFont(C, [], Size);
      Inc(Result, C.TextWidth(' '));
    end;
  end;
end;

function TMdView.MinAtomWidth(const Atoms: TMdAtoms; Size: Integer): Integer;
var
  I, W: Integer;
  C: TCanvas;
begin
  C := FMeasure.Canvas;
  Result := 0;
  W := 0;
  for I := 0 to High(Atoms) do
  begin
    SetFont(C, Atoms[I].Style, Size);
    if Atoms[I].Space then W := 0;
    Inc(W, C.TextWidth(Atoms[I].Text));
    Result := Max(Result, W);
  end;
end;

{ Lay the atoms out in lines from (X, Y), AWidth wide; returns the height
  used. Emit False only measures. }
function TMdView.WrapAtoms(const Atoms: TMdAtoms; X, Y, AWidth, Size: Integer; Bold: Boolean;
  AColor: TColor; Emit: Boolean): Integer;
var
  C: TCanvas;
  LineStart, I, J, Cx, LineH, SpaceW, Start: Integer;
  Widths: array of Integer;
  Style: TMdStyle;

  function AtomStyle(K: Integer): TMdStyle;
  begin
    Result := Atoms[K].Style;
    if Bold then Include(Result, msBold);
  end;

  procedure EmitLine(First, Last: Integer);
  var
    K, Px, W: Integer;
    Col: TColor;
  begin
    Px := X;
    for K := First to Last do
    begin
      if Atoms[K].Space and (K > First) then Inc(Px, SpaceW);
      W := Widths[K];
      if Emit then
      begin
        if msLink in Atoms[K].Style then Col := LINK_COLOR
        else if msCode in Atoms[K].Style then Col := CODE_COLOR
        else Col := AColor;
        // A space inside code (or a link) is part of the coloured run
        if Atoms[K].Space and (K > First) and (Atoms[K - 1].Style * [msCode, msLink] <> []) and
           (Atoms[K].Style * [msCode, msLink] = Atoms[K - 1].Style * [msCode, msLink]) and
           (Atoms[K].Link = Atoms[K - 1].Link) then
          AddItem(miText, Rect(Px - SpaceW, Y, Px, Y + LineH), ' ', AtomStyle(K), Size, Col,
            Atoms[K].Link);
        AddItem(miText, Rect(Px, Y, Px + W, Y + LineH), Atoms[K].Text, AtomStyle(K), Size, Col,
          Atoms[K].Link);
      end;
      Inc(Px, W);
    end;
  end;

begin
  Result := 0;
  if Length(Atoms) = 0 then Exit;
  C := FMeasure.Canvas;
  SetFont(C, [], Size);
  SpaceW := C.TextWidth(' ');
  LineH := C.TextHeight('Ag') + 2;
  SetLength(Widths, Length(Atoms));
  for I := 0 to High(Atoms) do
  begin
    Style := AtomStyle(I);
    SetFont(C, Style, Size);
    Widths[I] := C.TextWidth(Atoms[I].Text);
  end;
  LineStart := 0;
  Cx := 0;
  I := 0;
  while I <= High(Atoms) do
  begin
    if Atoms[I].Space and (I > LineStart) then Inc(Cx, SpaceW);
    Inc(Cx, Widths[I]);
    if (Cx > AWidth) and (I > LineStart) then
    begin
      // Break before the word this atom belongs to
      J := I;
      while (J > LineStart) and not Atoms[J].Space do Dec(J);
      if J = LineStart then J := I;
      EmitLine(LineStart, J - 1);
      Inc(Y, LineH);
      Inc(Result, LineH);
      LineStart := J;
      Cx := 0;
      I := J;
      Start := I;
      while I <= High(Atoms) do
      begin
        if Atoms[I].Space and (I > Start) then Break;
        Inc(Cx, Widths[I]);
        Inc(I);
      end;
      Continue;
    end;
    Inc(I);
  end;
  EmitLine(LineStart, High(Atoms));
  Inc(Result, LineH);
end;

procedure TMdView.Layout;
var
  B, Y, X, W, Size, LineH, Gap, R, Col, Cols, Avail, Extra, TotalMin, TotalWant, H, RowH, Cx, K, TableTop, Indent: Integer;
  C: TCanvas;
  MinW, WantW, ColW: array of Integer;
  Bullet: string;
  Bk: ^TMdBlock;
begin
  FItems := nil;
  FFound := nil;
  FAnchors.Clear;
  // Not yet sized: laid out when it is
  if ClientWidth < 50 then
  begin
    FLayoutWidth := -1;
    FHeight := 0;
    Exit;
  end;
  C := FMeasure.Canvas;
  SetFont(C, [], BASE_SIZE);
  LineH := C.TextHeight('Ag') + 2;
  Gap := LineH div 2;
  Indent := LineH * 3 div 2;
  W := ClientWidth - FScroll.Width - 2 * Gap - 8;
  if W < 100 then W := 100;
  FLayoutWidth := ClientWidth;
  X := Gap + 4;
  Y := Gap;
  for B := 0 to High(FBlocks) do
  begin
    Bk := @FBlocks[B];
    case Bk^.Kind of
      mbHeading:
        begin
          Size := HEADING_SIZES[Bk^.Level];
          if B > 0 then Inc(Y, LineH);
          FAnchors.AddObject(Bk^.Anchor, TObject(PtrInt(Y)));
          Inc(Y, WrapAtoms(Bk^.Atoms, X, Y, W, Size, True, HEADING_COLOR, True));
          if Bk^.Level <= 2 then
          begin
            Inc(Y, 3);
            AddItem(miLine, Rect(X, Y, X + W, Y + 1), '', [], 0, RULE_COLOR);
            Inc(Y, 2);
          end;
          Inc(Y, Gap);
        end;
      mbPara:
        Inc(Y, WrapAtoms(Bk^.Atoms, X, Y, W, BASE_SIZE, False, clBlack, True) + Gap);
      mbBullet, mbNumber:
        begin
          Cx := X + Bk^.Level * Indent;
          if Bk^.Kind = mbNumber then Bullet := Bk^.Number
          else if Bk^.Level > 0 then Bullet := #$E2#$80#$93     // en dash for nested items
          else Bullet := #$E2#$80#$A2;
          AddItem(miText, Rect(Cx + LineH div 3, Y, Cx + Indent, Y + LineH), Bullet, [], BASE_SIZE, clBlack);
          Inc(Y, WrapAtoms(Bk^.Atoms, Cx + Indent, Y, W - (Cx - X) - Indent, BASE_SIZE, False,
            clBlack, True));
          // Items of a list are closer together than paragraphs
          if (B < High(FBlocks)) and (FBlocks[B + 1].Kind in [mbBullet, mbNumber]) then Inc(Y, 3)
          else Inc(Y, Gap);
        end;
      mbCode:
        begin
          SetFont(C, [msCode], BASE_SIZE - 1);
          H := C.TextHeight('Ag') + 1;
          AddItem(miBox, Rect(X, Y, X + W, Y + Bk^.Lines.Count * H + Gap), '', [], 0, CODE_BACK);
          for R := 0 to Bk^.Lines.Count - 1 do
            AddItem(miText, Rect(X + Gap, Y + Gap div 2 + R * H, X + W, Y + Gap div 2 + (R + 1) * H),
              Bk^.Lines[R], [msCode], BASE_SIZE - 1, clBlack);
          Inc(Y, Bk^.Lines.Count * H + Gap + Gap);
        end;
      mbRule:
        begin
          AddItem(miLine, Rect(X, Y + Gap, X + W, Y + Gap + 1), '', [], 0, RULE_COLOR);
          Inc(Y, 2 * Gap + 1);
        end;
      mbTable:
        begin
          Cols := Length(Bk^.Cells[0]);
          SetLength(MinW, Cols);
          SetLength(WantW, Cols);
          SetLength(ColW, Cols);
          for Col := 0 to Cols - 1 do
          begin
            MinW[Col] := 0;
            WantW[Col] := 0;
            for R := 0 to High(Bk^.Cells) do
            begin
              if R = 0 then
              begin
                // The header is bold
                for K := 0 to High(Bk^.Cells[0][Col]) do Include(Bk^.Cells[0][Col][K].Style, msBold);
              end;
              MinW[Col] := Max(MinW[Col], MinAtomWidth(Bk^.Cells[R][Col], BASE_SIZE));
              WantW[Col] := Max(WantW[Col], AtomsWidth(Bk^.Cells[R][Col], BASE_SIZE));
            end;
            Inc(MinW[Col], 2 * Gap);
            Inc(WantW[Col], 2 * Gap + 2);
          end;
          TotalMin := 0;
          TotalWant := 0;
          for Col := 0 to Cols - 1 do
          begin
            Inc(TotalMin, MinW[Col]);
            Inc(TotalWant, WantW[Col]);
          end;
          Avail := W;
          for Col := 0 to Cols - 1 do
            if TotalWant <= Avail then ColW[Col] := WantW[Col]
            else if TotalMin >= Avail then ColW[Col] := MinW[Col]
            else
            begin
              // What doesn't fit is shared out by how much each column wants
              Extra := Avail - TotalMin;
              ColW[Col] := MinW[Col] + Int64(Extra) * (WantW[Col] - MinW[Col]) div Max(1, TotalWant - TotalMin);
            end;
          Avail := 0;
          for Col := 0 to Cols - 1 do Inc(Avail, ColW[Col]);
          TableTop := Y;
          for R := 0 to High(Bk^.Cells) do
          begin
            RowH := LineH;
            for Col := 0 to Cols - 1 do
              RowH := Max(RowH, WrapAtoms(Bk^.Cells[R][Col], 0, 0, ColW[Col] - 2 * Gap, BASE_SIZE,
                False, clBlack, False));
            Inc(RowH, Gap);
            if R = 0 then AddItem(miBox, Rect(X, Y, X + Avail, Y + RowH), '', [], 0, CODE_BACK);
            Cx := X;
            for Col := 0 to Cols - 1 do
            begin
              WrapAtoms(Bk^.Cells[R][Col], Cx + Gap, Y + Gap div 2, ColW[Col] - 2 * Gap, BASE_SIZE,
                False, clBlack, True);
              Inc(Cx, ColW[Col]);
            end;
            AddItem(miLine, Rect(X, Y, X + Avail, Y + 1), '', [], 0, RULE_COLOR);
            Inc(Y, RowH);
          end;
          AddItem(miLine, Rect(X, Y, X + Avail, Y + 1), '', [], 0, RULE_COLOR);
          Cx := X;
          for Col := 0 to Cols do
          begin
            AddItem(miLine, Rect(Cx, TableTop, Cx + 1, Y + 1), '', [], 0, RULE_COLOR);
            if Col < Cols then Inc(Cx, ColW[Col]);
          end;
          Inc(Y, Gap + 1);
        end;
    end;
  end;
  FHeight := Y + Gap;
  // Text for Find
  FPlain := '';
  FPlainItem := nil;
  for B := 0 to High(FItems) do
    if FItems[B].Kind = miText then
    begin
      K := Length(FPlain);
      FPlain := FPlain + LowerCase(FItems[B].Text) + ' ';
      SetLength(FPlainItem, Length(FPlain));
      for R := K to Length(FPlain) - 1 do FPlainItem[R] := B;
    end;
  FFindFrom := 1;
  UpdateScroll;
end;

procedure TMdView.UpdateScroll;
begin
  FScroll.Min := 0;
  FScroll.Max := Max(0, FHeight);
  FScroll.PageSize := Max(1, ClientHeight);
  FScroll.LargeChange := Max(1, ClientHeight - 40);
  FScroll.SmallChange := 40;
  SetTop(FTop);
end;

procedure TMdView.SetTop(Value: Integer);
begin
  Value := Max(0, Min(Value, FHeight - ClientHeight));
  if Value <> FTop then
  begin
    FTop := Value;
    Invalidate;
  end;
  if FScroll.Position <> FTop then FScroll.Position := FTop;
end;

procedure TMdView.ScrollChange(Sender: TObject);
begin
  SetTop(FScroll.Position);
end;

procedure TMdView.Resize;
begin
  inherited Resize;
  if (FLayoutWidth <> ClientWidth) and (Length(FBlocks) > 0) then
  begin
    Layout;
    Invalidate;
  end
  else
    UpdateScroll;
end;

procedure TMdView.Paint;
var
  I, K: Integer;
  R: TRect;
  Found: Boolean;
begin
  Canvas.Brush.Color := clWhite;
  Canvas.FillRect(ClientRect);
  for I := 0 to High(FItems) do
  begin
    R := FItems[I].R;
    if (R.Bottom < FTop) or (R.Top > FTop + ClientHeight) then Continue;
    OffsetRect(R, 0, -FTop);
    case FItems[I].Kind of
      miBox, miLine:
        begin
          Canvas.Brush.Color := FItems[I].Color;
          Canvas.FillRect(R);
        end;
      miText:
        begin
          Found := False;
          for K := 0 to High(FFound) do
            if FFound[K] = I then Found := True;
          SetFont(Canvas, FItems[I].Style, FItems[I].Size);
          Canvas.Font.Color := FItems[I].Color;
          if Found then
          begin
            Canvas.Brush.Color := FIND_BACK;
            Canvas.FillRect(R);
          end
          else if (msCode in FItems[I].Style) and (FItems[I].Size = BASE_SIZE) then
          begin
            // Inline code on a grey background
            Canvas.Brush.Color := CODE_BACK;
            Canvas.FillRect(R);
          end;
          Canvas.Brush.Style := bsClear;
          Canvas.TextOut(R.Left, R.Top, FItems[I].Text);
          Canvas.Brush.Style := bsSolid;
        end;
    end;
  end;
end;

function TMdView.ItemAt(X, Y: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FItems) do
    if (FItems[I].Kind = miText) and (FItems[I].Link <> '') and
       PtInRect(FItems[I].R, Point(X, Y + FTop)) then Exit(I);
  Result := -1;
end;

procedure TMdView.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if ItemAt(X, Y) >= 0 then Cursor := crHandPoint else Cursor := crDefault;
end;

procedure TMdView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  I: Integer;
  Link: string;
begin
  inherited MouseDown(Button, Shift, X, Y);
  SetFocus;
  I := ItemAt(X, Y);
  if (I < 0) or (Button <> mbLeft) then Exit;
  Link := FItems[I].Link;
  if Copy(Link, 1, 1) = '#' then GoToAnchor(Copy(Link, 2, MaxInt))
  else if Pos('://', Link) > 0 then OpenURL(Link);
end;

procedure TMdView.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  case Key of
    VK_UP: SetTop(FTop - 40);
    VK_DOWN: SetTop(FTop + 40);
    VK_PRIOR: SetTop(FTop - ClientHeight + 40);
    VK_NEXT, VK_SPACE: SetTop(FTop + ClientHeight - 40);
    VK_HOME: SetTop(0);
    VK_END: SetTop(FHeight);
  else
    Exit;
  end;
  Key := 0;
end;

function TMdView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  SetTop(FTop - WheelDelta);
  Result := True;
end;

function TMdView.GoToAnchor(const Anchor: string): Boolean;
var
  I: Integer;
begin
  I := FAnchors.IndexOf(LowerCase(Anchor));
  Result := I >= 0;
  if Result then SetTop(PtrInt(FAnchors.Objects[I]) - 8);
end;

function TMdView.Find(const What: string): Boolean;
var
  P, I, First, Last: Integer;
  S: string;
begin
  FFound := nil;
  S := LowerCase(Trim(What));
  Result := False;
  if S = '' then FFindFrom := 1;
  if S <> '' then
  begin
    P := Pos(S, Copy(FPlain, FFindFrom, MaxInt));
    if P > 0 then
    begin
      P := P + FFindFrom - 1;
      First := FPlainItem[P - 1];
      Last := FPlainItem[P + Length(S) - 2];
      for I := First to Last do
        if FItems[I].Kind = miText then
        begin
          SetLength(FFound, Length(FFound) + 1);
          FFound[High(FFound)] := I;
        end;
      FFindFrom := P + Length(S);
      // Into view, a third of the way down
      if (FItems[First].R.Top < FTop) or (FItems[First].R.Bottom > FTop + ClientHeight) then
        SetTop(FItems[First].R.Top - ClientHeight div 3);
      Result := True;
    end
    else
      FFindFrom := 1;
  end;
  Invalidate;
end;

end.

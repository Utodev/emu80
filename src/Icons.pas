{ Icons: toolbar icons drawn in code, so they scale cleanly with the screen
  DPI and need no image files. Shapes are designed on a 16x16 grid. }
unit Icons;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Controls, Forms, Types;

type
  TIconKind = (
    ikOpen, ikSave, ikReset, ikNMI, ikPause, ikTurbo, ikTape, ikPlay, ikStop, ikDisk,
    ikDebugger, ikSettings,
    ikRun, ikBreak, ikBreakpoint, ikCondition, ikClearBreakpoints, ikStepInto, ikStepOver,
    ikRunToCursor, ikGoTo, ikWatch,
    ikModel, ikSound, ikMute, ikRewind, ikPlayFrom, ikMoveUp, ikMoveDown, ikDelete, ikRecord,
    ikRefresh, ikRename, ikSDCard, ikFolderUp, ikNewFolder, ikChip, ikZ80, ikImportFolder, ikFolder,
    ikEject, ikTheme, ikMenu, ikKeyboard, ikCartridge, ikKey);

{ Toolbar icon size for the current screen (16 px at 96 DPI) }
function IconSize: Integer;
{ Fill an image list with all icons, in TIconKind order (index = Ord(kind)),
  ASize pixels square (0: the toolbar's size) }
procedure LoadIcons(Images: TImageList; ASize: Integer = 0);
{ Draw the icons for a dark background (or not) and redraw every list loaded
  so far that is still alive }
procedure SetDarkIcons(Dark: Boolean);

var
  { The icons are being drawn for a dark background (the modern interface) }
  DarkIcons: Boolean = False;

implementation

const
  MASK_COLOR = clFuchsia;

function IconSize: Integer;
begin
  Result := Round(16 * Screen.PixelsPerInch / 96);
  if Result < 16 then Result := 16;
end;

type
  { Draws on a Size x Size canvas using 16x16 design coordinates }
  TPainter = class
    C: TCanvas;
    K: Double;
    function P(X, Y: Double): TPoint;
    function S(V: Double): Integer;
    procedure Pen(Color: TColor; Width: Double = 1);
    procedure Fill(Color: TColor);
    procedure Poly(const Pts: array of Double);
    procedure Rect(X1, Y1, X2, Y2: Double);
    procedure RoundRect(X1, Y1, X2, Y2, R: Double);
    procedure Circle(CX, CY, R: Double);
    procedure Line(X1, Y1, X2, Y2: Double);
  end;

function TPainter.P(X, Y: Double): TPoint;
begin
  Result := Point(Round(X * K), Round(Y * K));
end;

function TPainter.S(V: Double): Integer;
begin
  Result := Round(V * K);
  if Result < 1 then Result := 1;
end;

procedure TPainter.Pen(Color: TColor; Width: Double);
begin
  C.Pen.Color := Color;
  C.Pen.Width := S(Width);
end;

procedure TPainter.Fill(Color: TColor);
begin
  C.Brush.Style := bsSolid;
  C.Brush.Color := Color;
end;

procedure TPainter.Poly(const Pts: array of Double);
var
  A: array of TPoint;
  I: Integer;
begin
  SetLength(A, Length(Pts) div 2);
  for I := 0 to High(A) do A[I] := P(Pts[I * 2], Pts[I * 2 + 1]);
  C.Polygon(A);
end;

procedure TPainter.Rect(X1, Y1, X2, Y2: Double);
begin
  C.Rectangle(Round(X1 * K), Round(Y1 * K), Round(X2 * K), Round(Y2 * K));
end;

procedure TPainter.RoundRect(X1, Y1, X2, Y2, R: Double);
begin
  C.RoundRect(Round(X1 * K), Round(Y1 * K), Round(X2 * K), Round(Y2 * K), S(R), S(R));
end;

procedure TPainter.Circle(CX, CY, R: Double);
begin
  C.Ellipse(Round((CX - R) * K), Round((CY - R) * K), Round((CX + R) * K), Round((CY + R) * K));
end;

procedure TPainter.Line(X1, Y1, X2, Y2: Double);
begin
  C.Line(P(X1, Y1), P(X2, Y2));
end;

const
  Blue = $C06020;        // TColor is BGR: RGB(32, 96, 192)
  DarkBlue = $803010;
  Red = $2828D0;
  DarkRed = $101080;
  Green = $30A030;
  DarkGreen = $106010;
  Yellow = $30C8F0;
  DarkYellow = $1080B0;
  Grey = $808080;
  DarkGrey = $404040;
  LightGrey = $D0D0D0;

procedure DrawIcon(D: TPainter; Kind: TIconKind);
var
  I: Integer;
begin
  case Kind of
    ikOpen:
      begin
        // Folder with its flap open
        D.Pen(DarkYellow); D.Fill(Yellow);
        D.Poly([1, 4, 6, 4, 7, 5, 13, 5, 13, 13, 1, 13]);
        D.Fill($70E0FF);
        D.Poly([3, 8, 15, 8, 13, 13, 1, 13]);
      end;
    ikSave:
      begin
        // Floppy disk
        D.Pen(DarkBlue); D.Fill(Blue);
        D.Poly([2, 2, 12, 2, 14, 4, 14, 14, 2, 14]);
        D.Fill(clWhite); D.Rect(4, 2, 11, 7);
        D.Fill(LightGrey); D.Rect(5, 10, 11, 14);
      end;
    ikReset:
      begin
        // Red button with a power symbol
        D.Pen(DarkRed); D.Fill(Red); D.Circle(8, 8, 7);
        D.Pen(clWhite, 1.6);
        D.C.Brush.Style := bsClear;
        D.C.Arc(D.S(4), D.S(4), D.S(12), D.S(12), D.S(10.5), D.S(4.5), D.S(5.5), D.S(4.5));
        D.Line(8, 3, 8, 8);
      end;
    ikNMI:
      begin
        // Lightning bolt
        D.Pen(DarkYellow); D.Fill(Yellow);
        D.Poly([9, 1, 3, 9, 7, 9, 5, 15, 13, 6, 9, 6, 11, 1]);
      end;
    ikPause:
      begin
        // Blue button with pause bars
        D.Pen(DarkBlue); D.Fill(Blue); D.Circle(8, 8, 7);
        D.Pen(clWhite); D.Fill(clWhite);
        D.Rect(5, 4.5, 7, 11.5); D.Rect(9, 4.5, 11, 11.5);
      end;
    ikTurbo:
      begin
        // Fast forward
        D.Pen(DarkGreen); D.Fill(Green);
        D.Poly([1, 3, 8, 8, 1, 13]);
        D.Poly([8, 3, 15, 8, 8, 13]);
      end;
    ikTape:
      begin
        // Cassette: body, window and two reels
        D.Pen(clBlack); D.Fill(DarkGrey); D.RoundRect(1, 3, 15, 13, 2);
        D.Fill(LightGrey); D.Rect(3, 5, 13, 9);
        D.Pen(DarkGrey); D.Fill(clWhite); D.Circle(5.5, 7, 1.6); D.Circle(10.5, 7, 1.6);
        D.Pen(Grey); D.Fill(Grey); D.Poly([4, 13, 5, 11, 11, 11, 12, 13]);
      end;
    ikPlay, ikRun:
      begin
        if Kind = ikPlay then begin D.Pen(DarkGreen); D.Fill(Green); end
        else begin D.Pen(DarkBlue); D.Fill(Blue); end;
        D.Poly([4, 2, 13, 8, 4, 14]);
      end;
    ikStop:
      begin
        D.Pen(DarkBlue); D.Fill(Blue); D.Rect(3, 3, 13, 13);
      end;
    ikDisk:
      begin
        // Amstrad 3" Compact Floppy Disc: tall black case, oval head window,
        // white hub in the middle, red label with a grey strip at the bottom
        D.Pen(clBlack); D.Fill($202020); D.RoundRect(2, 0.5, 14, 15.5, 1.5);
        D.Pen(clWhite); D.Fill(clWhite); D.Rect(3, 1, 4.5, 2.5);          // write protect tab
        D.Pen($A0A0A0); D.Fill($A0A0A0); D.RoundRect(6.5, 1.5, 9.5, 6, 3); // head window
        D.Pen(clWhite); D.Fill(clWhite); D.Circle(8, 8.3, 1.9);            // hub
        D.Pen($202020); D.Fill($202020); D.Circle(8, 8.3, 0.6);
        D.Pen(Red); D.Fill(Red); D.Rect(3, 10.8, 13, 13.2);                // label
        D.Pen(LightGrey); D.Fill(LightGrey); D.Rect(3, 13.2, 13, 14.8);
      end;
    ikDebugger:
      begin
        // Magnifying glass over a chip
        D.Pen(DarkGrey); D.Fill(Grey); D.Rect(1, 5, 10, 14);
        D.Pen(DarkGrey, 1);
        D.Line(3, 3, 3, 5); D.Line(6, 3, 6, 5); D.Line(3, 14, 3, 16); D.Line(6, 14, 6, 16);
        D.Pen(DarkBlue, 1.5); D.Fill($FFE8C0); D.Circle(10, 6, 4);
        D.Pen(DarkBlue, 2.2); D.Line(13, 9, 15, 12);
      end;
    ikSettings:
      begin
        // Gear: teeth as a square and its rotation, then the hub
        D.Pen(DarkGrey); D.Fill(Grey);
        D.Poly([6.5, 1, 9.5, 1, 9.5, 15, 6.5, 15]);
        D.Poly([1, 6.5, 15, 6.5, 15, 9.5, 1, 9.5]);
        D.Poly([2.6, 4.7, 4.7, 2.6, 13.4, 11.3, 11.3, 13.4]);
        D.Poly([11.3, 2.6, 13.4, 4.7, 4.7, 13.4, 2.6, 11.3]);
        D.Circle(8, 8, 5);
        D.Fill(clWhite); D.Circle(8, 8, 2);
      end;
    ikBreak:
      begin
        D.Pen(DarkBlue); D.Fill(Blue);
        D.Rect(4, 3, 7, 13); D.Rect(9, 3, 12, 13);
      end;
    ikBreakpoint:
      begin
        D.Pen(DarkRed); D.Fill(Red); D.Circle(8, 8, 5.5);
      end;
    ikCondition:
      begin
        // Breakpoint with a question mark
        D.Pen(DarkRed); D.Fill(Red); D.Circle(6, 9, 5);
        D.C.Font.Name := 'Arial';
        D.C.Font.Style := [fsBold];
        D.C.Font.Height := -D.S(11);
        D.C.Font.Color := DarkBlue;
        D.C.Brush.Style := bsClear;
        D.C.TextOut(D.S(9), D.S(0), '?');
      end;
    ikClearBreakpoints:
      begin
        D.Pen(DarkRed); D.Fill(Red); D.Circle(7, 7, 5);
        D.Pen(DarkGrey, 2); D.Line(9, 9, 15, 15); D.Line(15, 9, 9, 15);
      end;
    ikStepInto, ikStepOver:
      begin
        // Code lines, and an arrow into them (step into) or over them
        D.Pen(Grey, 1.5);
        D.Line(2, 10, 14, 10); D.Line(2, 13, 10, 13);
        D.Pen(Blue, 1.6); D.C.Brush.Style := bsClear;
        if Kind = ikStepInto then
        begin
          D.Line(8, 1, 8, 6);
          D.Fill(Blue); D.Poly([5, 5, 11, 5, 8, 8.5]);
        end
        else
        begin
          D.C.Arc(D.S(2), D.S(1), D.S(14), D.S(13), D.S(14), D.S(7), D.S(2), D.S(7));
          D.Fill(Blue); D.Poly([11, 6, 15.5, 6, 13.5, 9.5]);
        end;
      end;
    ikRunToCursor:
      begin
        // Arrow running into a text cursor
        D.Pen(DarkYellow); D.Fill(Yellow);
        D.Poly([1, 6, 7, 6, 7, 3, 12, 8, 7, 13, 7, 10, 1, 10]);
        D.Pen(clBlack, 1.5); D.Line(14, 2, 14, 14);
      end;
    ikWatch:
      begin
        // Glasses
        D.Pen(DarkGrey, 1.4); D.Fill($F0D8B0);
        D.Circle(4.5, 9, 3); D.Circle(11.5, 9, 3);
        D.C.Brush.Style := bsClear;
        D.Line(7.5, 8.5, 8.5, 8.5);
        D.Line(1.5, 8, 1, 5); D.Line(14.5, 8, 15, 5);
      end;
    ikModel:
      begin
        // Chip: black body with pins on both sides and a notch
        D.Pen(DarkGrey, 1);
        for I := 0 to 3 do
        begin
          D.Line(1, 3.5 + I * 3, 4, 3.5 + I * 3);
          D.Line(12, 3.5 + I * 3, 15, 3.5 + I * 3);
        end;
        D.Pen(clBlack); D.Fill($303030); D.RoundRect(3.5, 1.5, 12.5, 14.5, 1.5);
        D.Pen(Grey); D.Fill(Grey); D.Circle(6, 4, 1);
      end;
    ikSound, ikMute:
      begin
        // Speaker, with waves or a red cross
        D.Pen(DarkGrey); D.Fill(Grey);
        D.Poly([1.5, 5.5, 4.5, 5.5, 8.5, 2, 8.5, 14, 4.5, 10.5, 1.5, 10.5]);
        D.C.Brush.Style := bsClear;
        if Kind = ikSound then
        begin
          D.Pen(Blue, 1.3);
          D.C.Arc(D.S(6), D.S(5), D.S(12), D.S(11), D.S(11), D.S(3), D.S(11), D.S(13));
          D.C.Arc(D.S(5), D.S(2.5), D.S(15), D.S(13.5), D.S(13), D.S(1), D.S(13), D.S(15));
        end
        else
        begin
          D.Pen(Red, 2); D.Line(10, 5, 15, 11); D.Line(15, 5, 10, 11);
        end;
      end;
    ikRewind:
      begin
        D.Pen(DarkGreen); D.Fill(Green);
        D.Poly([8, 3, 1, 8, 8, 13]);
        D.Poly([15, 3, 8, 8, 15, 13]);
      end;
    ikPlayFrom:
      begin
        // Play from a marked block: a bar and a play triangle
        D.Pen(DarkBlue); D.Fill(Blue); D.Rect(2, 3, 4.5, 13);
        D.Pen(DarkGreen); D.Fill(Green); D.Poly([6.5, 2.5, 14.5, 8, 6.5, 13.5]);
      end;
    ikMoveUp, ikMoveDown:
      begin
        D.Pen(DarkBlue); D.Fill(Blue);
        if Kind = ikMoveUp then
          D.Poly([8, 1.5, 14.5, 8.5, 10.5, 8.5, 10.5, 14.5, 5.5, 14.5, 5.5, 8.5, 1.5, 8.5])
        else
          D.Poly([8, 14.5, 14.5, 7.5, 10.5, 7.5, 10.5, 1.5, 5.5, 1.5, 5.5, 7.5, 1.5, 7.5]);
      end;
    ikRefresh:
      begin
        // Circular arrow
        D.Pen(DarkGreen, 1.8); D.C.Brush.Style := bsClear;
        D.C.Arc(D.S(2.5), D.S(2.5), D.S(13.5), D.S(13.5), D.S(8), D.S(2.5), D.S(13.5), D.S(5));
        D.Pen(DarkGreen, 1); D.Fill(Green); D.Poly([10.5, 0.5, 15, 4.5, 10, 7]);
      end;
    ikRename:
      begin
        // Pencil writing on a line
        D.Pen(DarkGrey, 1.2); D.Line(1.5, 14.5, 14.5, 14.5);
        D.Pen(DarkYellow); D.Fill(Yellow); D.Poly([4, 12, 3, 13.5, 4.5, 13, 13.5, 4, 12, 2.5]);
        D.Pen(DarkRed); D.Fill(Red); D.Poly([12, 2.5, 13.5, 4, 15, 2.5, 13.5, 1]);
      end;
    ikSDCard:
      begin
        // SD card: cut corner at the top right, gold contacts
        D.Pen(DarkBlue); D.Fill(Blue);
        D.Poly([3, 1, 10.5, 1, 13, 3.5, 13, 15, 3, 15]);
        D.Pen(DarkYellow); D.Fill(Yellow);
        D.Rect(4.5, 2, 5.8, 5); D.Rect(6.6, 2, 7.9, 5); D.Rect(8.7, 2, 10, 5);
        D.Pen(clWhite); D.Fill(clWhite); D.Rect(4.5, 9, 11.5, 13.5);
      end;
    ikFolderUp, ikNewFolder, ikImportFolder, ikFolder:
      begin
        D.Pen(DarkYellow); D.Fill(Yellow);
        D.Poly([1, 4, 6, 4, 7, 5, 14, 5, 14, 14, 1, 14]);
        if Kind = ikImportFolder then
        begin
          // An arrow going into the folder
          D.Pen(DarkBlue); D.Fill(Blue);
          D.Poly([7.5, 13, 11.5, 9, 9, 9, 9, 1, 6, 1, 6, 9, 3.5, 9]);
        end
        else if Kind = ikFolderUp then
        begin
          D.Pen(DarkGreen); D.Fill(Green);
          D.Poly([7.5, 6, 11.5, 10, 9, 10, 9, 13, 6, 13, 6, 10, 3.5, 10]);
        end
        else if Kind = ikNewFolder then
        begin
          D.Pen(DarkGreen, 2);
          D.Line(7.5, 7, 7.5, 13); D.Line(4.5, 10, 10.5, 10);
        end;
      end;
    ikEject:
      begin
        // Eject: a triangle over a bar
        D.Pen(DarkBlue); D.Fill(Blue);
        D.Poly([2.5, 9.5, 8, 3, 13.5, 9.5]);
        D.Rect(2.5, 11.5, 13.5, 14);
      end;
    ikRecord:
      begin
        // REC: a red circle with a black border
        D.Pen(clBlack, 1.2); D.Fill($2020E0); D.Circle(8, 8, 5.5);
      end;
    ikDelete:
      begin
        D.Pen(DarkRed, 3);
        D.Line(3.5, 3.5, 12.5, 12.5); D.Line(12.5, 3.5, 3.5, 12.5);
      end;
    ikChip:
      begin
        // A chip (registers): black body with pins on both sides
        D.Pen(Grey, 1.2);
        for I := 0 to 3 do
        begin
          D.Line(1.5, 3.5 + I * 3, 4, 3.5 + I * 3);
          D.Line(12, 3.5 + I * 3, 14.5, 3.5 + I * 3);
        end;
        if DarkIcons then
        begin
          // Lighter on a dark background, or it can't be seen
          D.Pen(LightGrey, 1.2);
          for I := 0 to 3 do
          begin
            D.Line(1.5, 3.5 + I * 3, 4, 3.5 + I * 3);
            D.Line(12, 3.5 + I * 3, 14.5, 3.5 + I * 3);
          end;
          D.Pen(LightGrey); D.Fill(Grey); D.Rect(4, 2, 12, 15);
          D.Pen(clWhite); D.Fill(clWhite); D.Circle(6, 4, 0.8);
        end
        else
        begin
          D.Pen(clBlack); D.Fill(DarkGrey); D.Rect(4, 2, 12, 15);
          D.Pen(LightGrey); D.Fill(LightGrey); D.Circle(6, 4, 0.8);
        end;
      end;
    ikZ80:
      begin
        // "Z80" in bold, small
        D.C.Font.Name := 'Arial';
        D.C.Font.Style := [fsBold];
        D.C.Font.Height := -D.S(8);
        D.C.Font.Quality := fqNonAntialiased;
        if DarkIcons then D.C.Font.Color := clWhite else D.C.Font.Color := DarkBlue;
        D.C.Brush.Style := bsClear;
        D.C.TextOut((D.S(16) - D.C.TextWidth('Z80')) div 2, (D.S(16) - D.C.TextHeight('Z80')) div 2, 'Z80');
      end;
    ikMenu:
      begin
        // A menu drops down: a triangle pointing down
        if DarkIcons then begin D.Pen(LightGrey); D.Fill(LightGrey); end
        else begin D.Pen(DarkGrey); D.Fill(DarkGrey); end;
        D.Poly([3.5, 6, 12.5, 6, 8, 11.5]);
      end;
    ikTheme:
      begin
        // Half light, half dark: the interface's look
        if DarkIcons then D.Pen(LightGrey, 1.2) else D.Pen(DarkGrey, 1.2);
        D.Fill(clWhite);
        D.Circle(8, 8, 6);
        D.Fill(DarkGrey);
        D.C.Chord(D.S(2), D.S(2), D.S(14), D.S(14), D.S(8), D.S(2), D.S(8), D.S(14));
      end;
    ikKeyboard:
      begin
        // A Spectrum key: dark, with a letter and the stripe of colours
        D.Pen(DarkGrey); D.Fill($585048);
        D.RoundRect(1.5, 3, 14.5, 14, 2.5);
        D.Pen(Red); D.Line(9, 5.2, 10.4, 5.2);
        D.Pen(Yellow); D.Line(10.4, 5.2, 11.8, 5.2);
        D.Pen(Green); D.Line(11.8, 5.2, 13.2, 5.2);
        D.C.Font.Name := 'Arial';
        D.C.Font.Style := [fsBold];
        D.C.Font.Height := -D.S(8);
        D.C.Font.Quality := fqNonAntialiased;
        D.C.Font.Color := clWhite;
        D.C.Brush.Style := bsClear;
        D.C.TextOut(D.S(3.5), D.S(5.5), 'K');
      end;
    ikCartridge:
      begin
        // An MSX cartridge: a dark body with the notch at the top, a label and the contacts at the bottom
        D.Pen(clBlack); D.Fill($585048);
        D.Poly([3, 1, 13, 1, 13, 12, 12, 13, 4, 13, 3, 12]);
        D.Pen(clWhite); D.Fill(clWhite); D.Rect(5, 3, 11, 8);
        D.Pen(DarkRed); D.Fill(Red); D.Rect(5, 5, 11, 6.5);
        D.Pen(DarkYellow); D.Fill(Yellow);
        D.Rect(4.5, 13, 5.5, 15); D.Rect(6.5, 13, 7.5, 15); D.Rect(8.5, 13, 9.5, 15); D.Rect(10.5, 13, 11.5, 15);
      end;
    ikKey:
      begin
        // A key of a keyboard seen from above: light, its top smaller than its base, a symbol on it
        D.Pen(DarkGrey); D.Fill($C8C8C8);
        D.RoundRect(1.5, 1.5, 14.5, 14.5, 3);
        D.Pen($A0A0A0); D.Fill(clWhite);
        D.RoundRect(3.5, 2.5, 12.5, 11, 2);
        D.C.Font.Name := 'Arial';
        D.C.Font.Style := [fsBold];
        D.C.Font.Height := -D.S(8);
        D.C.Font.Quality := fqNonAntialiased;
        D.C.Font.Color := DarkGrey;
        D.C.Brush.Style := bsClear;
        D.C.TextOut((D.S(16) - D.C.TextWidth('@')) div 2, D.S(2.5), '@');
      end;
    ikGoTo:
      begin
        // Signpost
        D.Pen(DarkGrey, 1.5); D.Line(4, 3, 4, 15);
        D.Pen(DarkGreen); D.Fill(Green);
        D.Poly([5, 3, 13, 3, 15, 5.5, 13, 8, 5, 8]);
      end;
  end;
end;

type
  { The image lists loaded, to redraw them when the background changes }
  TIconLists = class(TComponent)
  public
    Lists: TFPList;
    Sizes: array of Integer;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Add(Images: TImageList; ASize: Integer);
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  end;

var
  Loaded: TIconLists = nil;

constructor TIconLists.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Lists := TFPList.Create;
end;

destructor TIconLists.Destroy;
begin
  Lists.Free;
  inherited Destroy;
end;

procedure TIconLists.Add(Images: TImageList; ASize: Integer);
var
  I: Integer;
begin
  I := Lists.IndexOf(Images);
  if I < 0 then
  begin
    I := Lists.Add(Images);
    SetLength(Sizes, Lists.Count);
    Images.FreeNotification(Self);
  end;
  Sizes[I] := ASize;
end;

procedure TIconLists.Notification(AComponent: TComponent; Operation: TOperation);
var
  I, J: Integer;
begin
  inherited Notification(AComponent, Operation);
  if Operation <> opRemove then Exit;
  I := Lists.IndexOf(AComponent);
  if I < 0 then Exit;
  Lists.Delete(I);
  for J := I to High(Sizes) - 1 do Sizes[J] := Sizes[J + 1];
  SetLength(Sizes, Lists.Count);
end;

procedure DrawList(Images: TImageList; ASize: Integer); forward;

procedure LoadIcons(Images: TImageList; ASize: Integer);
begin
  if Loaded = nil then Loaded := TIconLists.Create(Application);
  Loaded.Add(Images, ASize);
  DrawList(Images, ASize);
end;

procedure SetDarkIcons(Dark: Boolean);
var
  I: Integer;
begin
  if Dark = DarkIcons then Exit;
  DarkIcons := Dark;
  if Loaded <> nil then
    for I := 0 to Loaded.Lists.Count - 1 do
      DrawList(TImageList(Loaded.Lists[I]), Loaded.Sizes[I]);
end;

procedure DrawList(Images: TImageList; ASize: Integer);
var
  Kind: TIconKind;
  Bmp: TBitmap;
  Painter: TPainter;
  Size: Integer;
begin
  if ASize > 0 then Size := ASize else Size := IconSize;
  Images.Clear;
  Images.Width := Size;
  Images.Height := Size;
  Painter := TPainter.Create;
  Bmp := TBitmap.Create;
  try
    Bmp.SetSize(Size, Size);
    Painter.C := Bmp.Canvas;
    Painter.K := Size / 16;
    for Kind := Low(TIconKind) to High(TIconKind) do
    begin
      Bmp.Canvas.Brush.Style := bsSolid;
      Bmp.Canvas.Brush.Color := MASK_COLOR;
      Bmp.Canvas.Pen.Style := psSolid;
      Bmp.Canvas.FillRect(0, 0, Size, Size);
      DrawIcon(Painter, Kind);
      Images.AddMasked(Bmp, MASK_COLOR);
    end;
  finally
    Bmp.Free;
    Painter.Free;
  end;
end;

end.

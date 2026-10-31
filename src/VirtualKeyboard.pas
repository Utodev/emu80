{ VirtualKeyboard: a window (not modal) with the symbols most often wanted and
  hard to find on the machines' keyboards, in rows of 6. A click types one on
  the machine in use, with the keys that give it there (the way --keyin
  types); only the ones the machine can type are shown, packed in their order.
  Esc closes it. }
unit VirtualKeyboard;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, StdCtrls, ExtCtrls, Graphics, LCLType;

type
  { Types Sym on the machine (or, DryRun, only tells whether it can) }
  TTypeSymbolEvent = function(const Sym: string; DryRun: Boolean): Boolean of object;

procedure ShowVirtualKeyboard(AOwner: TComponent; OnType: TTypeSymbolEvent);

implementation

const
  SYMBOLS: array[0..34] of string = (
    '|', ':', ';', '.', ',', '/',
    '@', '+', '*', '-', '=', '#',
    '!', '"', '·', '$', '%', '&',
    '(', ')', '?', '''', '[', ']',
    '{', '}', '<', '>', '~', '¬',
    '_', '¿', '¡', 'ñ', 'Ñ');
  COLS = 6;

type
  TVirtualKeyboardForm = class(TForm)
  private
    FOnType: TTypeSymbolEvent;
    FButtons: array[0..High(SYMBOLS)] of TButton;
    FTimer: TTimer;
    FSize, FGap: Integer;
    FShown: string;                    // which are shown ('1' or '0' each), to lay them out only on a change
    procedure SymbolClick(Sender: TObject);
    procedure RefreshButtons(Sender: TObject);
    procedure KeyDownHandler(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure CloseHandler(Sender: TObject; var CloseAction: TCloseAction);
  end;

var
  Keyboard: TVirtualKeyboardForm;

procedure TVirtualKeyboardForm.SymbolClick(Sender: TObject);
begin
  if Assigned(FOnType) then FOnType(SYMBOLS[(Sender as TButton).Tag], False);
end;

{ The machine may change while the window is open: what it can type, every half second }
procedure TVirtualKeyboardForm.RefreshButtons(Sender: TObject);
var
  I, N: Integer;
  Shown: string;
begin
  if not Assigned(FOnType) then Exit;
  Shown := '';
  for I := 0 to High(SYMBOLS) do
    if FOnType(SYMBOLS[I], True) then Shown := Shown + '1' else Shown := Shown + '0';
  if Shown = FShown then Exit;
  FShown := Shown;
  // Only the ones it can type, one after another in their order; the window as tall as their rows
  N := 0;
  for I := 0 to High(SYMBOLS) do
  begin
    FButtons[I].Visible := Shown[I + 1] = '1';
    if not FButtons[I].Visible then Continue;
    FButtons[I].SetBounds(FGap + (N mod COLS) * (FSize + FGap), FGap + (N div COLS) * (FSize + FGap), FSize, FSize);
    Inc(N);
  end;
  ClientHeight := FGap + Max(1, (N + COLS - 1) div COLS) * (FSize + FGap);
end;

procedure TVirtualKeyboardForm.KeyDownHandler(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then Close;
end;

procedure TVirtualKeyboardForm.CloseHandler(Sender: TObject; var CloseAction: TCloseAction);
begin
  FTimer.Enabled := False;
  CloseAction := caFree;
  Keyboard := nil;
end;

procedure ShowVirtualKeyboard(AOwner: TComponent; OnType: TTypeSymbolEvent);
var
  I, Size, Gap: Integer;
begin
  if Keyboard <> nil then
  begin
    Keyboard.Show;
    Keyboard.BringToFront;
    Exit;
  end;
  Keyboard := TVirtualKeyboardForm.CreateNew(AOwner);
  with Keyboard do
  begin
    FOnType := OnType;
    Caption := 'Virtual Keyboard';
    BorderStyle := bsToolWindow;
    FormStyle := fsStayOnTop;
    KeyPreview := True;
    OnKeyDown := @KeyDownHandler;
    OnClose := @CloseHandler;
    Size := Scale96ToScreen(40);
    Gap := Scale96ToScreen(4);
    FSize := Size;
    FGap := Gap;
    Font.Height := -Scale96ToScreen(18);
    for I := 0 to High(SYMBOLS) do
    begin
      FButtons[I] := TButton.Create(Keyboard);
      FButtons[I].Parent := Keyboard;
      FButtons[I].Caption := SYMBOLS[I];
      // "&" alone would be taken as a hotkey's mark
      if SYMBOLS[I] = '&' then FButtons[I].Caption := '&&';
      FButtons[I].Tag := I;
      FButtons[I].TabStop := False;
      FButtons[I].OnClick := @SymbolClick;
      FButtons[I].Font.Style := [fsBold];
    end;
    ClientWidth := Gap + COLS * (Size + Gap);
    Position := poMainFormCenter;
    FTimer := TTimer.Create(Keyboard);
    FTimer.Interval := 500;
    FTimer.OnTimer := @RefreshButtons;
    RefreshButtons(nil);
    Show;
  end;
end;

end.

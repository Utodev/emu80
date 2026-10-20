{ DelayHint: a hint shown after the mouse rests on something for a second
  (longer help texts: what an instruction or a condact does, a flag's
  meaning). The views ask for it while the mouse moves and cancel it when
  it leaves the spot. }
unit DelayHint;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls, ExtCtrls, LCLIntf;

type
  TDelayedHint = class(TComponent)
  private
    FTimer: TTimer;
    FWindow: THintWindow;
    FText: string;
    FArea: TRect;          // screen coordinates of what the hint is about
    procedure TimerFire(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    { Show AText in a second if the mouse stays inside Area (a control's
      client coordinates); asking again for the same keeps the wait }
    procedure Request(Control: TControl; const Area: TRect; const AText: string);
    procedure Cancel;
  end;

{ The one shared by every view }
function DelayedHint: TDelayedHint;

implementation

const
  HINT_DELAY = 1000;     // ms
  HINT_WIDTH = 480;      // longer lines wrap

var
  TheHint: TDelayedHint;

function DelayedHint: TDelayedHint;
begin
  if TheHint = nil then TheHint := TDelayedHint.Create(Application);
  Result := TheHint;
end;

constructor TDelayedHint.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := HINT_DELAY;
  FTimer.OnTimer := @TimerFire;
end;

procedure TDelayedHint.Request(Control: TControl; const Area: TRect; const AText: string);
var
  R: TRect;
begin
  R.TopLeft := Control.ClientToScreen(Area.TopLeft);
  R.BottomRight := Control.ClientToScreen(Area.BottomRight);
  if (AText = FText) and EqualRect(R, FArea) then Exit;
  Cancel;
  if AText = '' then Exit;
  FText := AText;
  FArea := R;
  FTimer.Enabled := True;
end;

procedure TDelayedHint.Cancel;
begin
  FTimer.Enabled := False;
  FText := '';
  FArea := Rect(0, 0, 0, 0);
  if (FWindow <> nil) and FWindow.Visible then FWindow.Hide;
end;

procedure TDelayedHint.TimerFire(Sender: TObject);
var
  P: TPoint;
  R, Work: TRect;
begin
  FTimer.Enabled := False;
  P := Mouse.CursorPos;
  if (FText = '') or not PtInRect(FArea, P) then Exit;
  // The application's kind (dark in the dark theme)
  if FWindow = nil then FWindow := HintWindowClass.Create(Self);
  R := FWindow.CalcHintRect(HINT_WIDTH, FText, nil);
  // Below the spot, kept on the screen
  OffsetRect(R, P.X, FArea.Bottom + 2);
  Work := Screen.MonitorFromPoint(P).WorkareaRect;
  if R.Right > Work.Right then OffsetRect(R, Work.Right - R.Right, 0);
  if R.Left < Work.Left then OffsetRect(R, Work.Left - R.Left, 0);
  if R.Bottom > Work.Bottom then OffsetRect(R, 0, FArea.Top - 2 - R.Bottom);
  FWindow.ActivateHint(R, FText);
end;

end.

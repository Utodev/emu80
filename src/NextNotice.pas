{ NextNotice: the note shown when the ZX Spectrum Next's distribution isn't
  installed (pzx can't include it): where to download it, as a link that
  opens in the browser, and where to install it from. One window, so it takes
  the theme in use. }
unit NextNotice;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, Graphics, LCLType, LCLIntf;

procedure ShowNoNextDistro;

implementation

uses
  NextCard, ModernUI;

type
  TNoticeForm = class(TForm)
  private
    procedure LinkClick(Sender: TObject);
  public
    constructor CreateNotice;
  end;

constructor TNoticeForm.CreateNotice;
var
  Before, Link, After: TLabel;
  Ok: TButton;
  W, Y: Integer;
begin
  inherited CreateNew(nil, 0);
  Caption := 'ZX Spectrum Next';
  BorderStyle := bsDialog;
  Position := poMainFormCenter;
  W := ScaleX(520, 96);
  ClientWidth := W;
  KeyPreview := True;
  Y := ScaleY(16, 96);

  Before := TLabel.Create(Self);
  Before.Parent := Self;
  Before.AutoSize := False;
  Before.WordWrap := True;
  Before.Caption := 'La distribución de Spectrum Next no está instalada. Por favor descarga desde';
  Before.SetBounds(ScaleX(16, 96), Y, W - ScaleX(32, 96), ScaleY(20, 96));
  Inc(Y, ScaleY(24, 96));

  // The download page, opened in the system's browser
  Link := TLabel.Create(Self);
  Link.Parent := Self;
  Link.Caption := NEXT_DOWNLOAD_URL;
  Link.Font.Style := [fsUnderline];
  Link.Cursor := crHandPoint;
  Link.Hint := 'Open it in the browser';
  Link.ShowHint := True;
  Link.OnClick := @LinkClick;
  // Its own colour: a link's, readable on either theme
  Link.Tag := THEME_OWN_COLOURS;
  if DarkTheme then Link.Font.Color := $00FFC678 else Link.Font.Color := clBlue;
  Link.Left := ScaleX(16, 96);
  Link.Top := Y;
  Inc(Y, ScaleY(28, 96));

  After := TLabel.Create(Self);
  After.Parent := Self;
  After.AutoSize := False;
  After.WordWrap := True;
  After.Caption := 'y después accede al menú Options/Install Spectrum Next Distribution.';
  After.SetBounds(ScaleX(16, 96), Y, W - ScaleX(32, 96), ScaleY(40, 96));
  Inc(Y, ScaleY(52, 96));

  Ok := TButton.Create(Self);
  Ok.Parent := Self;
  Ok.Caption := 'OK';
  Ok.Default := True;
  Ok.Cancel := True;
  Ok.ModalResult := mrOK;
  Ok.SetBounds(W - ScaleX(96, 96), Y, ScaleX(80, 96), ScaleY(28, 96));
  ClientHeight := Y + ScaleY(44, 96);
end;

procedure TNoticeForm.LinkClick(Sender: TObject);
begin
  OpenURL(NEXT_DOWNLOAD_URL);
end;

procedure ShowNoNextDistro;
var
  F: TNoticeForm;
begin
  F := TNoticeForm.CreateNotice;
  try
    F.ShowModal;
  finally
    F.Free;
  end;
end;

end.

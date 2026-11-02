{ Logo: the program's logo (a black banner, so it looks right on both themes),
  drawn where there is room for it, and the About box that shows it. }
unit Logo;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Types;

{ Draw the logo inside R, as big as fits and centred }
procedure DrawLogo(Cv: TCanvas; const R: TRect);
{ The logo's height for a given width }
function LogoHeight(AWidth: Integer): Integer;
{ The logo's width for a given height }
function LogoWidth(AHeight: Integer): Integer;
{ The About box: the logo, then Text }
procedure ShowAbout(const ATitle, AText: string);

implementation

uses
  Forms, Controls, StdCtrls, ExtCtrls, LCLType, LCLIntf, Lang;

{$I Logo.inc}

var
  Pic: TPortableNetworkGraphic = nil;

function LoadLogo: TPortableNetworkGraphic;
var
  S: TMemoryStream;
begin
  if Pic = nil then
  begin
    S := TMemoryStream.Create;
    try
      S.WriteBuffer(LOGO_PNG[0], SizeOf(LOGO_PNG));
      S.Position := 0;
      Pic := TPortableNetworkGraphic.Create;
      Pic.LoadFromStream(S);
    finally
      S.Free;
    end;
  end;
  Result := Pic;
end;

function LogoHeight(AWidth: Integer): Integer;
begin
  Result := AWidth * LOGO_HEIGHT div LOGO_WIDTH;
end;

function LogoWidth(AHeight: Integer): Integer;
begin
  Result := AHeight * LOGO_WIDTH div LOGO_HEIGHT;
end;

procedure DrawLogo(Cv: TCanvas; const R: TRect);
var
  W, H: Integer;
  Dest: TRect;
begin
  W := R.Right - R.Left;
  H := LogoHeight(W);
  if H > R.Bottom - R.Top then
  begin
    H := R.Bottom - R.Top;
    W := H * LOGO_WIDTH div LOGO_HEIGHT;
  end;
  if (W < 1) or (H < 1) then Exit;
  Dest := Bounds(R.Left + (R.Right - R.Left - W) div 2, R.Top + (R.Bottom - R.Top - H) div 2, W, H);
  // Smooth when it shrinks (the default stretching is not)
  SetStretchBltMode(Cv.Handle, HALFTONE);
  Cv.StretchDraw(Dest, LoadLogo);
end;

type
  TAboutForm = class(TForm)
  private
    FLogo: TPaintBox;
    procedure LogoPaint(Sender: TObject);
  public
    constructor CreateAbout(const ATitle, AText: string);
  end;

procedure TAboutForm.LogoPaint(Sender: TObject);
begin
  DrawLogo(FLogo.Canvas, FLogo.ClientRect);
end;

constructor TAboutForm.CreateAbout(const ATitle, AText: string);
var
  Memo: TMemo;
  Ok: TButton;
  W, Pad, LH: Integer;
begin
  inherited CreateNew(nil, 0);
  Caption := ATitle;
  BorderStyle := bsDialog;
  Position := poMainFormCenter;
  KeyPreview := True;
  Pad := ScaleX(16, 96);
  W := ScaleX(620, 96);
  ClientWidth := W;
  LH := LogoHeight(W - 2 * Pad);

  FLogo := TPaintBox.Create(Self);
  FLogo.Parent := Self;
  FLogo.SetBounds(Pad, Pad, W - 2 * Pad, LH);
  FLogo.OnPaint := @LogoPaint;

  Memo := TMemo.Create(Self);
  Memo.Parent := Self;
  Memo.ReadOnly := True;
  Memo.BorderStyle := bsNone;
  Memo.ParentColor := True;
  Memo.WordWrap := True;
  Memo.ScrollBars := ssAutoVertical;
  Memo.Text := AText;
  Memo.SetBounds(Pad, 2 * Pad + LH, W - 2 * Pad, ScaleY(300, 96));

  Ok := TButton.Create(Self);
  Ok.Parent := Self;
  Ok.Caption := _('OK');
  Ok.Default := True;
  Ok.Cancel := True;
  Ok.ModalResult := mrOK;
  Ok.SetBounds(W - Pad - ScaleX(80, 96), Memo.Top + Memo.Height + Pad, ScaleX(80, 96), ScaleY(28, 96));
  ClientHeight := Ok.Top + Ok.Height + Pad;
end;

procedure ShowAbout(const ATitle, AText: string);
var
  F: TAboutForm;
begin
  F := TAboutForm.CreateAbout(ATitle, AText);
  try
    F.ShowModal;
  finally
    F.Free;
  end;
end;

finalization
  Pic.Free;

end.

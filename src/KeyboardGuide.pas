{ KeyboardGuide: a window (not modal) with the ZX Spectrum keyboard map (the
  keywords of every key) and nothing else, at the picture's own size (1064 px
  wide; smaller only if the screen is). Esc or a click closes it. }
unit KeyboardGuide;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, ExtCtrls, Graphics, LCLType;

procedure ShowKeyboardGuide(AOwner: TComponent);

implementation

{$I KeyboardGuide.inc}

type
  TGuideForm = class(TForm)
    procedure KeyDownHandler(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ClickHandler(Sender: TObject);
    procedure CloseHandler(Sender: TObject; var CloseAction: TCloseAction);
  end;

var
  Guide: TGuideForm;

procedure TGuideForm.KeyDownHandler(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then Close;
end;

procedure TGuideForm.ClickHandler(Sender: TObject);
begin
  Close;
end;

procedure TGuideForm.CloseHandler(Sender: TObject; var CloseAction: TCloseAction);
begin
  CloseAction := caFree;
  Guide := nil;
end;

procedure ShowKeyboardGuide(AOwner: TComponent);
var
  Img: TImage;
  Pic: TPortableNetworkGraphic;
  Stream: TMemoryStream;
  Work: TRect;
  W, H: Integer;
begin
  if Guide <> nil then
  begin
    Guide.Show;
    Guide.BringToFront;
    Exit;
  end;
  Pic := TPortableNetworkGraphic.Create;
  Stream := TMemoryStream.Create;
  try
    Stream.WriteBuffer(KEYBOARD_GUIDE, KEYBOARD_GUIDE_SIZE);
    Stream.Position := 0;
    Pic.LoadFromStream(Stream);
  finally
    Stream.Free;
  end;
  // The picture's own size, or less if the screen is small
  W := Pic.Width;
  H := Pic.Height;
  Work := Screen.WorkAreaRect;
  if W > (Work.Right - Work.Left) * 9 div 10 then
  begin
    H := H * ((Work.Right - Work.Left) * 9 div 10) div W;
    W := (Work.Right - Work.Left) * 9 div 10;
  end;
  if H > (Work.Bottom - Work.Top) * 85 div 100 then
  begin
    W := W * ((Work.Bottom - Work.Top) * 85 div 100) div H;
    H := (Work.Bottom - Work.Top) * 85 div 100;
  end;
  Guide := TGuideForm.CreateNew(AOwner);
  Guide.Caption := 'ZX Spectrum keyboard';
  Guide.BorderStyle := bsDialog;
  Guide.Position := poScreenCenter;
  Guide.KeyPreview := True;
  Guide.OnKeyDown := @Guide.KeyDownHandler;
  Guide.OnClose := @Guide.CloseHandler;
  Guide.ClientWidth := W;
  Guide.ClientHeight := H;
  Img := TImage.Create(Guide);
  Img.Parent := Guide;
  Img.Align := alClient;
  Img.Stretch := True;
  Img.Proportional := True;
  Img.Picture.Assign(Pic);
  Img.OnClick := @Guide.ClickHandler;
  Pic.Free;
  Guide.Show;
end;

end.

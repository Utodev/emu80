{ PathTitle: a window title with a file's full path ("Tape browser -
  C:\games\jsw.tap"). When it doesn't fit in the title bar, the path is cut
  at its start ("Tape browser - ...\games\jsw.tap"), so the file name always
  shows; it is fitted again when the window is resized. }
unit PathTitle;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Graphics{$IFDEF WINDOWS}, Windows{$ENDIF};

type
  TPathTitle = class(TComponent)
  private
    FForm: TForm;
    FBefore, FPath, FAfter: string;
    FOldResize: TNotifyEvent;
    procedure FormResize(Sender: TObject);
    procedure Fit;
  public
    { For AForm (which owns it); takes over its OnResize, calling the one
      it had }
    constructor Create(AForm: TForm); reintroduce;
    { The title: Before, then Path (cut at its start if need be), then After }
    procedure SetTitle(const Before, Path, After: string);
  end;

implementation

const
  ELLIPSIS = #$E2#$80#$A6;   // "…"

{ A canvas with the title bar's font, to measure titles }
function TitleCanvas: Graphics.TBitmap;
{$IFDEF WINDOWS}
var
  M: TNONCLIENTMETRICS;
{$ENDIF}
begin
  Result := Graphics.TBitmap.Create;
  Result.Canvas.Font.Assign(Screen.SystemFont);
{$IFDEF WINDOWS}
  FillChar(M, SizeOf(M), 0);
  M.cbSize := SizeOf(M);
  if SystemParametersInfo(SPI_GETNONCLIENTMETRICS, SizeOf(M), @M, 0) then
    Result.Canvas.Font.Handle := CreateFontIndirect(M.lfCaptionFont);
{$ENDIF}
end;

constructor TPathTitle.Create(AForm: TForm);
begin
  inherited Create(AForm);
  FForm := AForm;
  FOldResize := AForm.OnResize;
  AForm.OnResize := @FormResize;
end;

procedure TPathTitle.FormResize(Sender: TObject);
begin
  if FPath <> '' then Fit;
  if Assigned(FOldResize) then FOldResize(Sender);
end;

procedure TPathTitle.SetTitle(const Before, Path, After: string);
begin
  FBefore := Before;
  FPath := Path;
  FAfter := After;
  Fit;
end;

procedure TPathTitle.Fit;
var
  Room, Cut: Integer;
  FileName, Dir, Text: string;
  B: Graphics.TBitmap;
begin
  Text := FBefore + FPath + FAfter;
  if FPath = '' then
  begin
    FForm.Caption := Text;
    Exit;
  end;
  // The title bar less its icon and buttons
  Room := FForm.Width - FForm.Scale96ToScreen(175);
  B := TitleCanvas;
  try
    if B.Canvas.TextWidth(Text) > Room then
    begin
      // Leading characters of the folder off until it fits (whole UTF-8
      // characters): the name stays
      FileName := ExtractFileName(FPath);
      Dir := ExtractFilePath(FPath);
      Cut := 0;
      repeat
        Inc(Cut);
        while (Cut < Length(Dir)) and ((Ord(Dir[Cut + 1]) and $C0) = $80) do Inc(Cut);
        Text := FBefore + ELLIPSIS + Copy(Dir, Cut + 1, MaxInt) + FileName + FAfter;
      until (Cut >= Length(Dir)) or (B.Canvas.TextWidth(Text) <= Room);
      // Not even the name fits: it is shown anyway
      if Cut >= Length(Dir) then Text := FBefore + ELLIPSIS + PathDelim + FileName + FAfter;
    end;
  finally
    B.Free;
  end;
  if FForm.Caption <> Text then FForm.Caption := Text;
end;

end.

program ochenta;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, Forms, MainForm;

{$R *.res}

begin
  RequireDerivedFormResource := False;
  Application.Title := 'ochenta';
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TMainWindow, MainWindow);
  Application.Run;
end.

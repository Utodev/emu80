{ cpcrun: runs a CPC with a disk or tape inserted, for N frames, and saves
  the picture (a tool for trying programs without the GUI).

    cpcrun <roms folder> <cpc464|cpc664|cpc6128> <file.dsk|file.cdt|file.tzx|-> <frames> <out.png> [typed text]

  The disk or tape is loaded the way the File > Open does (RUN" for a tape,
  RUN"<program> for a disk). Extra arguments after the first picture:
  "<frames>:<out.png>" take more pictures at those frame counts. With the
  environment variable CPCRUN_CRTC (0-4) chooses the CRTC chip; with CPCRUN_NOAUTO the program is not started: only the
  disk or tape is inserted. }
program cpcrun;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Models, Spectrum, DSK, ScreenCapture;

var
  Sp: TSpectrum;
  M: TSpectrumModel;
  Ext, Err: string;
  Disk: TDiskImage;
  F: array of LongWord;
  Frames, Done, I, Next: Integer;
  Shots: array of record At: Integer; Name: string; end;
  Typed: string;

procedure Shot(const Name: string);
begin
  SetLength(F, FB_WIDTH * SCREEN_HEIGHT);
  Sp.CopyFrameBuffer(@F[0]);
  SavePNG(F, Name, 1, True);
end;

begin
  if ParamCount < 5 then
  begin
    WriteLn('usage: cpcrun <roms> <model> <file|-> <frames> <out.png> [typed text] [frames:out.png ...]');
    Halt(2);
  end;
  M := ModelFromName(ParamStr(2), smCPC6128);
  Sp := TSpectrum.Create(M, ParamStr(1));
  if GetEnvironmentVariable('CPCRUN_CRTC') <> '' then
    Sp.CPC.CrtcType := StrToIntDef(GetEnvironmentVariable('CPCRUN_CRTC'), 1);
  Ext := LowerCase(ExtractFileExt(ParamStr(3)));
  if Ext = '.dsk' then
  begin
    Disk := TDiskImage.Create;
    Disk.LoadFromFile(ParamStr(3));
    Sp.FDC.InsertDisk(0, Disk);
    if GetEnvironmentVariable('CPCRUN_NOAUTO') = '' then Sp.AutoLoad(True)
    else Sp.Reset(True);
  end
  else if (Ext = '.cdt') or (Ext = '.tzx') then
  begin
    Sp.Tape.LoadFile(ParamStr(3));
    if GetEnvironmentVariable('CPCRUN_NOAUTO') = '' then Sp.AutoLoad(False);
  end;
  Frames := StrToIntDef(ParamStr(4), 100);
  SetLength(Shots, 0);
  Typed := '';
  for I := 6 to ParamCount do
    if Pos(':', ParamStr(I)) > 0 then
    begin
      SetLength(Shots, Length(Shots) + 1);
      Shots[High(Shots)].At := StrToIntDef(Copy(ParamStr(I), 1, Pos(':', ParamStr(I)) - 1), 0);
      Shots[High(Shots)].Name := Copy(ParamStr(I), Pos(':', ParamStr(I)) + 1, 999);
    end
    else Typed := Typed + ParamStr(I);
  if Typed <> '' then
    if not Sp.TypeText(Typed, Err) then WriteLn('typing: ', Err);
  Done := 0;
  while Done < Frames do
  begin
    Sp.RunFrame;
    Inc(Done);
    for I := 0 to High(Shots) do
      if Shots[I].At = Done then Shot(Shots[I].Name);
  end;
  Shot(ParamStr(5));
  WriteLn('PC=', IntToHex(Sp.Cpu.PC.W, 4), ' frames=', Done);
  Sp.Free;
end.

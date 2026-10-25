{ sambatch: tries every disk image of a folder on a SAM Coupe: loads it, says
  what kind of disk it is, boots it the way the GUI does (F9 in BASIC) and saves
  the picture after N frames (a tool for trying a collection without the GUI).

    sambatch <roms folder> <disks folder> <out folder> [frames]

  One line for each file: its name, what it is (or why it can't be loaded) and
  where the CPU is at the end. The pictures are <out folder>/<file>.png. }
program sambatch;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Models, Spectrum, ScreenCapture, DSK, DiskFormat;

var
  Files: TStringList;
  SR: TSearchRec;
  Dir, OutDir, Name, Err: string;
  Sp: TSpectrum;
  Disk: TDiskImage;
  Problem: TDiskProblem;
  F: array of LongWord;
  Frames, I, K, Lit: Integer;
begin
  if ParamCount < 3 then
  begin
    WriteLn('usage: sambatch <roms> <disks folder> <out folder> [frames]');
    Halt(2);
  end;
  Dir := IncludeTrailingPathDelimiter(ParamStr(2));
  OutDir := IncludeTrailingPathDelimiter(ParamStr(3));
  ForceDirectories(OutDir);
  Frames := 1500;
  if ParamCount >= 4 then Frames := StrToInt(ParamStr(4));
  Files := TStringList.Create;
  try
    if FindFirst(Dir + '*', faAnyFile, SR) = 0 then
    begin
      repeat
        if (SR.Attr and faDirectory) = 0 then Files.Add(SR.Name);
      until FindNext(SR) <> 0;
      FindClose(SR);
    end;
    Files.Sort;
    for K := 0 to Files.Count - 1 do
    begin
      Name := Files[K];
      Disk := LoadDiskImage(Dir + Name, Problem, Err);
      if Disk = nil then
      begin
        WriteLn(Format('%-60s  NOT LOADED: %s', [Name, Err]));
        Continue;
      end;
      Sp := TSpectrum.Create(smSAM, ParamStr(1));
      try
        Sp.InsertDiskAt(0, Disk);
        Sp.AutoLoad(True);
        for I := 1 to Frames do Sp.RunFrame;
        SetLength(F, FB_WIDTH * SCREEN_HEIGHT);
        Sp.CopyFrameBuffer(@F[0]);
        SavePNG(F, OutDir + ChangeFileExt(Name, '') + '.png', 1, True);
        // ERRNR (5C3A) is BASIC's last error when it is at its prompt (0 = OK, 53 = No DOS)
        Lit := 0;
        for I := 0 to High(F) do
          if (F[I] and $FFFFFF) <> 0 then Inc(Lit);
        WriteLn(Format('%-60s  %-12s  PC=%.4X LMPR=%.2X VMPR=%.2X ERRNR=%d lit=%d%%', [Name,
          DiskKindName(ClassifyDisk(Disk)), Sp.Cpu.PC.W, Sp.SAM.LMPR, Sp.SAM.VMPR, Sp.Peek($5C3A),
          Lit * 100 div Length(F)]));
      finally
        Sp.Free;
      end;
    end;
  finally
    Files.Free;
  end;
end.

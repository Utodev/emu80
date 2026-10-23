{ cpcbatch: boots a disk (or loads a .sna) on a CPC 6128, or the model given,
  as File > Open does, runs it for N frames and writes one line about the
  picture: the colours in it and whether it still looks like the BASIC prompt
  (blue paper, three colours or fewer), plus a PNG. For trying a collection of
  games (see tests/CPC-MANUAL-TESTS.md).

    cpcbatch <roms> <model> <file.dsk|.sna> <frames> <out.png> [-keys]

  -keys: after the run it answers N, RETURN, SPACE, RETURN to what waits for a
  key, runs on, and looks again; the line is marked SUSPECT only if the picture
  looks like the BASIC prompt both before and after. }
program cpcbatch;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Models, Spectrum, DSK, ScreenCapture, Snapshot;

type
  TLook = record
    Colours, Blue: Integer;
    Basic: Boolean;
  end;

var
  Sp: TSpectrum;
  Disk: TDiskImage;
  F: array of LongWord;
  N: Integer;
  A, B: TLook;
  Err: string;

function Look: TLook;
var
  I, K: Integer;
  Colours: array of LongWord;
begin
  SetLength(F, FB_WIDTH * SCREEN_HEIGHT);
  Sp.CopyFrameBuffer(@F[0]);
  SetLength(Colours, 0);
  Result.Blue := 0;
  for I := 0 to High(F) do
  begin
    if F[I] = $FF000080 then Inc(Result.Blue);
    K := 0;
    while (K <= High(Colours)) and (Colours[K] <> F[I]) do Inc(K);
    if K > High(Colours) then
    begin
      SetLength(Colours, Length(Colours) + 1);
      Colours[High(Colours)] := F[I];
    end;
  end;
  Result.Colours := Length(Colours);
  Result.Blue := Result.Blue * 100 div Length(F);
  Result.Basic := (Result.Colours <= 3) and (Result.Blue > 50);
end;

begin
  if ParamCount < 5 then Halt(2);
  try
    Sp := TSpectrum.Create(ModelFromName(ParamStr(2), smCPC6128), ParamStr(1));
    if LowerCase(ExtractFileExt(ParamStr(3))) = '.sna' then LoadSNA(Sp, ParamStr(3))
    else
    begin
      Disk := TDiskImage.Create;
      Disk.LoadFromFile(ParamStr(3));
      Sp.FDC.InsertDisk(0, Disk);
      Sp.AutoLoad(True);
    end;
    for N := 1 to StrToIntDef(ParamStr(4), 2500) do Sp.RunFrame;
    A := Look;
    B := A;
    if Pos('-keys', ParamStr(6)) = 1 then
    begin
      Sp.TypeText('n\n', Err);
      for N := 1 to 600 do Sp.RunFrame;
      Sp.TypeText(' \n', Err);
      for N := 1 to 1200 do Sp.RunFrame;
      B := Look;
    end;
    SavePNG(F, ParamStr(5), 1, True, True);
    Write(ExtractFileName(ParamStr(3)), ' colours=', A.Colours, '/', B.Colours, ' blue=', A.Blue, '%/', B.Blue,
      '% PC=', IntToHex(Sp.Cpu.PC.W, 4));
    if A.Basic and B.Basic then Write(' SUSPECT(basic prompt)');
    WriteLn;
    Sp.Free;
  except
    on E: Exception do WriteLn(ExtractFileName(ParamStr(3)), ' ERROR ', E.Message);
  end;
end.

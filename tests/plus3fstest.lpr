{ plus3fstest: the +3DOS file system used by the disk browser. Writes,
  reads, renames and deletes files on a new disk, then has the emulated +3
  load a program written from outside.

    plus3fstest <roms folder> }
program plus3fstest;

{$mode objfpc}{$H+}

uses
  SysUtils, Models, Spectrum, DSK, Plus3FS;

var
  Failures: Integer = 0;
  D: TDiskImage;
  FS: TPlus3Disk;
  Data, Back, Prog: TBytes;
  Sp: TSpectrum;
  I: Integer;
  Ok: Boolean;

procedure Check(Cond: Boolean; const What: string);
begin
  if not Cond then
  begin
    WriteLn('FAIL  ', What);
    Inc(Failures);
  end;
end;

begin
  D := TDiskImage.Create;
  D.CreatePlus3Formatted;
  FS := TPlus3Disk.Create(D);
  Check((FS.Count = 0) and (FS.FreeBytes = 173 * 1024), 'new disk: no files, 173K free');
  SetLength(Data, 40000);
  for I := 0 to High(Data) do Data[I] := Byte(I * 13 + I shr 8);
  FS.WriteFile('big.bin', AddPlus3Header(Data, FT_BYTES, 25000, 32768));
  I := FS.FindFile('BIG.BIN');
  Check((I = 0) and FS[I].HasHeader and (FS[I].DataLength = 40000) and (FS[I].Param1 = 25000),
    'header of a written file');
  Back := FS.ReadFile(I);
  Check((Length(Back) = 40128) and CompareMem(@Back[128], @Data[0], 40000), 'file read back');
  FS.WriteFile('raw', Copy(Data, 0, 300));
  Check(not FS[FS.FindFile('raw')].HasHeader and (FS[FS.FindFile('raw')].Size = 384),
    'file without a header');
  FS.RenameFile(FS.FindFile('raw'), 'other.txt');
  Check((FS.FindFile('raw') < 0) and (FS.FindFile('OTHER.TXT') >= 0), 'rename');
  try FS.RenameFile(FS.FindFile('other.txt'), 'big.bin'); Ok := False; except Ok := True; end;
  Check(Ok, 'rename onto an existing name is refused');
  try FS.WriteFile('bad*name', Data); Ok := False; except Ok := True; end;
  Check(Ok, 'invalid name is refused');
  FS.DeleteFile(FS.FindFile('big.bin'));
  Check((FS.Count = 1) and (FS.FreeBytes = 172 * 1024), 'delete frees the space');
  SetLength(Data, 200000);
  try FS.WriteFile('huge', Data); Ok := False; except Ok := True; end;
  Check(Ok, 'a file bigger than the free space is refused');
  // DISK: 10 POKE 40000,123, autostart at line 10, run by the +3 Loader
  Prog := TBytes.Create($00, $0A, 23, 0, $F4, $34, $30, $30, $30, $30, $0E, 0, 0, $40, $9C, 0,
    $2C, $31, $32, $33, $0E, 0, 0, 123, 0, 0, $0D);
  FS.WriteFile('DISK', AddPlus3Header(Prog, FT_PROGRAM, 10, Length(Prog)));
  FS.Free;
  Sp := TSpectrum.Create(smPlus3, ParamStr(1));
  Sp.SetFastDisk(True);
  Sp.FDC.InsertDisk(0, D);
  Sp.AutoLoad;
  for I := 1 to 600 do Sp.RunFrame;
  Check(Sp.Peek(40000) = 123, 'the +3 loads and runs a program written by the disk browser');
  Sp.Free;
  if Failures = 0 then WriteLn('+3 disk file system: all passed')
  else WriteLn('+3 disk file system: ', Failures, ' failed');
  if Failures > 0 then Halt(1);
end.

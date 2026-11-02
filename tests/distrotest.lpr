{ Installing the ZX Spectrum Next distribution from a zip (NextCard):
  the layout it leaves, zips that aren't distributions, paths that would
  write outside the folder, and clearing the folder. Needs no ROMs. }
program distrotest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Zipper, NextCard;

var
  Failures: Integer = 0;
  Base: string;

procedure Check(Cond: Boolean; const What: string);
begin
  if not Cond then
  begin
    WriteLn('FAIL  ', What);
    Inc(Failures);
  end;
end;

procedure Put(const FileName, Text: string);
var
  S: TStringList;
begin
  ForceDirectories(ExtractFilePath(FileName));
  S := TStringList.Create;
  try
    S.Text := Text;
    S.SaveToFile(FileName);
  finally
    S.Free;
  end;
end;

{ A zip with these entries (archive names exactly as given) }
procedure MakeZip(const ZipFile: string; const Names: array of string);
var
  Z: TZipper;
  I: Integer;
  S: TStringStream;
begin
  Z := TZipper.Create;
  try
    Z.FileName := ZipFile;
    for I := 0 to High(Names) do
    begin
      S := TStringStream.Create('content of ' + Names[I]);
      Z.Entries.AddFileEntry(S, Names[I]);
    end;
    Z.ZipAllFiles;
  finally
    Z.Free;
  end;
end;

function Fresh(const Name: string): string;
begin
  Result := Base + Name + PathDelim;
  ClearNextDistroDir(Result);
  RemoveDir(Result);
  ForceDirectories(Result);
end;

function Count(const Dir: string): Integer;
var
  Info: TSearchRec;
begin
  Result := 0;
  if FindFirst(Dir + '*', faAnyFile, Info) = 0 then
  begin
    repeat
      if (Info.Name <> '.') and (Info.Name <> '..') then Inc(Result);
    until FindNext(Info) <> 0;
    FindClose(Info);
  end;
end;

var
  Dir, Zip, Msg: string;
  F: TFileStream;
  R: TDistroInstall;
begin
  Base := IncludeTrailingPathDelimiter(GetTempDir) + 'ochenta-distrotest-' + IntToStr(GetProcessID) + PathDelim;
  ForceDirectories(Base);
  Zip := Base + 'test.zip';
  try
    // At the top of the zip
    Dir := Fresh('a');
    MakeZip(Zip, ['machines/next/enNextZX.rom', 'machines/next/enNxtmmc.rom', 'TBBLUE.FW', 'README.md',
      'machines/next/', 'docs/readme.txt']);
    R := InstallNextDistroZip(Zip, Dir, Msg);
    Check(R = diOk, 'a distribution at the top installs: ' + Msg);
    Check(FileExists(Dir + 'machines/next/enNextZX.rom') and FileExists(Dir + 'TBBLUE.FW') and
      FileExists(Dir + 'docs/readme.txt'), 'its files are where the emulator looks');
    Check(NextDistroReady(Dir), 'it is recognised as a distribution');
    Check(not DirectoryExists(Dir + '.ochenta-install'), 'no work folder is left');

    // Inside one folder of the zip: no extra level
    Dir := Fresh('b');
    MakeZip(Zip, ['Next-2.0/machines/next/enNextZX.rom', 'Next-2.0/machines/next/enNxtmmc.rom',
      'Next-2.0/TBBLUE.FW', '__MACOSX/junk']);
    R := InstallNextDistroZip(Zip, Dir, Msg);
    Check(R = diOk, 'a distribution inside a folder installs: ' + Msg);
    Check(NextDistroReady(Dir) and FileExists(Dir + 'TBBLUE.FW') and not DirectoryExists(Dir + 'Next-2.0'),
      'no extra directory level');
    Check(not DirectoryExists(Dir + '__MACOSX'), 'what is outside the distribution isn''t unpacked');

    // Over what was there
    Dir := Fresh('c');
    Put(Dir + 'machines/next/old.txt', 'old');
    Put(Dir + 'TBBLUE.FW', 'old firmware');
    MakeZip(Zip, ['machines/next/enNextZX.rom', 'machines/next/enNxtmmc.rom', 'TBBLUE.FW']);
    R := InstallNextDistroZip(Zip, Dir, Msg);
    Check((R = diOk) and NextDistroReady(Dir), 'it installs over a folder with something in it: ' + Msg);

    // Not distributions
    Dir := Fresh('d');
    Put(Dir + 'keep.txt', 'mine');
    MakeZip(Zip, ['hello.txt', 'sub/other.txt']);
    R := InstallNextDistroZip(Zip, Dir, Msg);
    Check(R = diInvalid, 'a zip without the ROMs is not a distribution');
    Check(FileExists(Dir + 'keep.txt') and not FileExists(Dir + 'hello.txt') and
      not DirectoryExists(Dir + '.ochenta-install'), 'nothing of it is left');
    MakeZip(Zip, ['machines/next/enNextZX.rom', 'machines/next/other.rom']);
    R := InstallNextDistroZip(Zip, Dir, Msg);
    Check(R = diInvalid, 'a zip with only some of the ROMs is not a distribution');
    Check(not DirectoryExists(Dir + 'machines'), 'what was unpacked is gone');
    F := TFileStream.Create(Zip, fmCreate);
    F.WriteBuffer(PChar('this is not a zip file at all')^, 29);
    F.Free;
    R := InstallNextDistroZip(Zip, Dir, Msg);
    Check(R = diInvalid, 'a file that is not a zip is not a distribution: ' + Msg);
    R := InstallNextDistroZip(Base + 'missing.zip', Dir, Msg);
    Check((R = diError) and (Msg <> ''), 'a missing file is an error');

    // Paths that leave the folder: refused, nothing written anywhere
    Dir := Fresh('e');
    MakeZip(Zip, ['machines/next/enNextZX.rom', 'machines/next/enNxtmmc.rom', '../evil.txt']);
    R := InstallNextDistroZip(Zip, Dir, Msg);
    Check(R = diError, 'a .. path is refused: ' + Msg);
    Check(not FileExists(Base + 'evil.txt') and not FileExists(Dir + 'evil.txt') and (Count(Dir) = 0),
      'nothing is written with a .. path');
    MakeZip(Zip, ['machines/next/enNextZX.rom', 'machines/next/enNxtmmc.rom', 'x/..\..\evil2.txt']);
    R := InstallNextDistroZip(Zip, Dir, Msg);
    Check((R = diError) and not FileExists(Base + 'evil2.txt') and (Count(Dir) = 0),
      'a backslash .. path is refused');
    MakeZip(Zip, ['machines/next/enNextZX.rom', 'machines/next/enNxtmmc.rom', '/tmp/ochenta-evil3.txt']);
    R := InstallNextDistroZip(Zip, Dir, Msg);
    Check((R = diError) and not FileExists('/tmp/ochenta-evil3.txt') and (Count(Dir) = 0),
      'an absolute path is refused');
    MakeZip(Zip, ['machines/next/enNextZX.rom', 'machines/next/enNxtmmc.rom', 'C:/evil4.txt']);
    R := InstallNextDistroZip(Zip, Dir, Msg);
    Check((R = diError) and (Count(Dir) = 0), 'a drive path is refused');

    // Clearing the folder
    Dir := Fresh('f');
    Put(Dir + 'a.txt', 'a');
    Put(Dir + 'sub/deep/b.txt', 'b');
    Put(Dir + '.hidden/c.txt', 'c');
    ClearNextDistroDir(Dir);
    Check(DirectoryExists(Dir) and (Count(Dir) = 0), 'clearing leaves the folder empty');
  finally
    ClearNextDistroDir(Base);
    RemoveDir(Base);
  end;
  if Failures = 0 then
    WriteLn('Next distribution install (layout, invalid zips, unsafe paths): all passed')
  else
    Halt(1);
end.

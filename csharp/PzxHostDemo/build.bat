@echo off
rem Builds PzxHostDemo.exe (32 bits, as pzxlib.dll is) with the .NET Framework's csc
rem and puts pzxlib.dll next to it.
rem In the sources: the library is build\lib\pzxlib.dll (src/lib/build-lib.sh) and the
rem result goes to build\csharp. In a pzx package (tests\PzxHostDemo): the library is
rem in the lib folder and the result stays here.
set CSC=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe
if exist "%~dp0..\..\..\src\lib\PzxApi.pas" (
  set DLL=%~dp0..\..\..\build\lib\pzxlib.dll
  set OUT=%~dp0..\..\..\build\csharp
) else (
  set DLL=%~dp0..\..\lib\pzxlib.dll
  set OUT=%~dp0
)
if not exist "%OUT%" mkdir "%OUT%"
"%CSC%" /nologo /target:exe /platform:x86 /out:"%OUT%\PzxHostDemo.exe" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll "%~dp0Pzx.cs" "%~dp0Program.cs"
if errorlevel 1 exit /b 1
copy /y "%DLL%" "%OUT%\pzxlib.dll" >nul
echo Built %OUT%\PzxHostDemo.exe

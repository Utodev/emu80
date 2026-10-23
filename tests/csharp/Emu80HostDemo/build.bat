@echo off
rem Builds Emu80HostDemo.exe (32 bits, as emu80lib.dll is) with the .NET Framework's csc
rem and puts emu80lib.dll next to it.
rem In the sources: the library is build\lib\emu80lib.dll (src/lib/build-lib.sh) and the
rem result goes to build\csharp. In a emu80 package (tests\Emu80HostDemo): the library is
rem in the lib folder and the result stays here.
set CSC=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe
if exist "%~dp0..\..\..\src\lib\Emu80Api.pas" (
  set DLL=%~dp0..\..\..\build\lib\emu80lib.dll
  set OUT=%~dp0..\..\..\build\csharp
) else (
  set DLL=%~dp0..\..\lib\emu80lib.dll
  set OUT=%~dp0
)
if not exist "%OUT%" mkdir "%OUT%"
"%CSC%" /nologo /target:exe /platform:x86 /out:"%OUT%\Emu80HostDemo.exe" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll "%~dp0Emu80.cs" "%~dp0Program.cs"
if errorlevel 1 exit /b 1
copy /y "%DLL%" "%OUT%\emu80lib.dll" >nul
echo Built %OUT%\Emu80HostDemo.exe

@echo off
rem Builds OchentaHostDemo.exe (32 bits, as ochentalib.dll is) with the .NET Framework's csc
rem and puts ochentalib.dll next to it.
rem In the sources: the library is build\lib\ochentalib.dll (src/lib/build-lib.sh) and the
rem result goes to build\csharp. In a ochenta package (tests\OchentaHostDemo): the library is
rem in the lib folder and the result stays here.
set CSC=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe
if exist "%~dp0..\..\..\src\lib\OchentaApi.pas" (
  set DLL=%~dp0..\..\..\build\lib\ochentalib.dll
  set OUT=%~dp0..\..\..\build\csharp
) else (
  set DLL=%~dp0..\..\lib\ochentalib.dll
  set OUT=%~dp0
)
if not exist "%OUT%" mkdir "%OUT%"
"%CSC%" /nologo /target:exe /platform:x86 /out:"%OUT%\OchentaHostDemo.exe" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll "%~dp0Ochenta.cs" "%~dp0Program.cs"
if errorlevel 1 exit /b 1
copy /y "%DLL%" "%OUT%\ochentalib.dll" >nul
echo Built %OUT%\OchentaHostDemo.exe

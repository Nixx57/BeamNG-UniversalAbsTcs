@echo off
setlocal

set "modRoot=%~dp0"
set "modRoot=%modRoot:~0,-1%"
for %%I in ("%modRoot%") do set "archivePath=%%~dpIuniversalAbsTcs_v0.1.zip"
set "tempDir=%TEMP%\universalAbsTcs_package"

if exist "%archivePath%" del /f /q "%archivePath%"
if exist "%tempDir%" rmdir /s /q "%tempDir%"
mkdir "%tempDir%"

xcopy "%modRoot%\lua" "%tempDir%\lua\" /E /I /Y >nul
xcopy "%modRoot%\ui" "%tempDir%\ui\" /E /I /Y >nul

pushd "%tempDir%"
tar.exe -a -c -f "%archivePath%" lua ui
popd

rmdir /s /q "%tempDir%"

echo Created "%archivePath%"
endlocal

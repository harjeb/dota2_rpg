@echo off
setlocal
set "DOTA=C:\Program Files (x86)\Steam\steamapps\common\dota 2 beta"
if not "%~1"=="" set "DOTA=%~1"
if not exist "%DOTA%\game\bin\win64\resourcecompiler.exe" (
    echo Enter the full path to your "dota 2 beta" folder:
    set /p "DOTA=Path: "
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install-ui.ps1" -DotaPath "%DOTA%"
if errorlevel 1 (
    echo UI98 installation failed. Read the error above before restarting or publishing.
) else (
    echo UI98 installed. Restart the custom game to refresh Panorama and localization.
)
pause

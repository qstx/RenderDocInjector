@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0manage-layer.ps1" Register
exit /b %errorlevel%

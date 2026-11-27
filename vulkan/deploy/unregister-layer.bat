@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0manage-layer.ps1" Unregister
exit /b %errorlevel%

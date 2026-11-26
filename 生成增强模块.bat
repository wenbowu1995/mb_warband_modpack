@echo off
chcp 65001 >nul
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0manager.ps1"
if errorlevel 1 (
  echo.
  echo [ERROR] Startup failed. See startup-error.txt in this folder.
  pause
)

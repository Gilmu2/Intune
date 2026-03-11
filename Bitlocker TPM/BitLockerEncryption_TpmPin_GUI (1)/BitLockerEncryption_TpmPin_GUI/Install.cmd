@echo off
REM Run PowerShell script hidden without showing window
"%~dp0ServiceUI.exe" -process:explorer.exe "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File "%~dp0BitLockerEncryption_TpmPin_GUI.ps1"


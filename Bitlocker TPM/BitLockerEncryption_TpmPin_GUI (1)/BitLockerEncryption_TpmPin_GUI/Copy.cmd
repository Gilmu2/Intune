@echo off
xcopy "%~dp0*" "C:\Windows\TEMP\BitLockerEncryption_TpmPin_GUI" /E /Y /I /H
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File "%~dp0ScheduledTask.ps1"

@echo off
cd %~dp0
copy LGPO.exe C:\Windows\System32

lgpo.exe /g LGPO /v

start secpol.msc

pause

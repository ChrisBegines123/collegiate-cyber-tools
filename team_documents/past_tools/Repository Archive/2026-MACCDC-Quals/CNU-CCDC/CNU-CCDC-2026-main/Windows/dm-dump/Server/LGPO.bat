@echo off
cd %~dp0
copy LGPO.exe C:\Windows\System32

lgpo.exe /g {84C808B4-561C-418B-BF71-D512480B9FB7} /v

start secpol.msc

pause

@echo off

:AddUsers
set /p "user=Enter the name of a user to add.  Type '0' to move on."
if "%user%"=="0" goto EndOfAddUsers
goto AddUsers

:EndOfAddUsers

echo Loop Exited
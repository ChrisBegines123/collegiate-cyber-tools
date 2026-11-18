
@echo off
set servicesList=PlugPlay Spooler

:stopService 


for %%i in (%servicesList%) do (
   sc stop %%i 
   if ERRORLEVEL 1 echo Unable to stop %%i. Check to see if it is already stopped. 
   pause 
   sc config %%i start=disabled 
   if ERRORLEVEL 1 echo Unable to disable %%i. Check to see if it is already disabled. 
   pause 
) 

cmd /k 

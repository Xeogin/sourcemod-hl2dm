@echo off
SetLocal EnableExtensions

dir /b /s /a-d * > list.tmp

del list.txt 2>NUL
del list_dl.txt 2>NUL
for /f "delims=" %%a in (list.tmp) do call :Replace "%%a"
del list.tmp

::pause
goto :eof

:Replace
  set "s=%~1"
  call set "s=%%s:%~dp0=%%"
  set "s=%s:\=/%"
  if "%s%" neq "list.tmp" if "%s%" neq "list.txt" if "%s%" neq "list_dl.txt" if "%s%" neq "%~nx0" (
    >> list.txt echo %s%
    >> list_dl.txt echo 	AddFileToDownloadsTable("%s%"^)^;
  )
exit /b

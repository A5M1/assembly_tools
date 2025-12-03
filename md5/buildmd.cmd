@echo off
echo Building md5sum.asm...
nasm -f win64 md5sum.asm -o md5sum.obj
if errorlevel 1 (
    echo NASM compilation failed!
    pause
    exit /b 1
)
GoLink.exe /ni /console /entry start md5sum.obj kernel32.dll shell32.dll user32.dll 
if errorlevel 1 (
    echo GoLink failed!
    pause
    exit /b 1
)

if not exist md5sum.exe (
    echo Output file md5sum.exe was not created!
    pause
    exit /b 1
)

echo Build successful!

if exist "C:\Program Files\Git\usr\bin\md5sum.exe" (
    echo System md5sum:
    "C:\Program Files\Git\usr\bin\md5sum.exe" md5sum.asm 
)
echo Our md5sum:
md5sum.exe md5sum.asm
echo Press anykey to exit.
pause>nul
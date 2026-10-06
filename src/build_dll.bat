@echo off
REM ====================================================================
REM AutoTranslator Native DLL Compilation Script
REM Visual Studio (Developer Command Prompt / x86 Native Tools)
REM ====================================================================

echo [1/3] Setting up x86 32-bit compilation environment...
if "%VSCMD_ARG_TGT_ARCH%"=="" (
    if exist "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars32.bat" (
        call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars32.bat"
    ) else if exist "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvars32.bat" (
        call "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvars32.bat"
    )
)

echo [2/3] Compiling at_native.cpp into 32-bit AutoTranslatorNative.dll...
cl.exe /O2 /LD /EHsc /W3 /D_USRDLL /D_WINDLL at_native.cpp /Fe:AutoTranslatorNative.dll /link winhttp.lib user32.lib /MACHINE:X86

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ====================================================================
    echo [SUCCESS] AutoTranslatorNative.dll compiled successfully!
    echo Copying AutoTranslatorNative.dll to ../libs/ ...
    copy /Y AutoTranslatorNative.dll ..\libs\
    echo ====================================================================
) else (
    echo.
    echo [ERROR] Compilation failed! Check MSVC Developer Command Prompt output.
)

pause

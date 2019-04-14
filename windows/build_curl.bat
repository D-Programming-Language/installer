@setlocal
@echo on

:: Also See: https://www.appveyor.com/docs/build-environment
SET ROOT=%CD%
SET ORIG_PATH=%PATH%
SET MINGW_PATH=C:\MinGW\bin
SET MINGW64_PATH=C:\mingw-w64\x86_64-6.3.0-posix-seh-rt_v5-rev1\mingw64\bin

:: --------------------------------------------------------------------
:: Download and Unpack

echo 4ff941449631ace0d4d203e3483be9dbc9da454084111f97ea0a2114e19bf066 zlib.tar.xz> sha256sums
echo f5f6fd3c72b7b8389969f4fb671ed8532fa9b5bb7a5cae7ca89bc1cea45c7878 curl.tar.xz>> sha256sums
echo 52329e960a0278fa7f228057260d577847ae2f1844ee449f9d7acbf73cbb3ca4 bup.zip>> sha256sums
echo 51f4d90d0dac3beb6fb5f8a4193ee0fae45b60eecc2dfdb9012f89eedce95a7c pexports.tar.xz>> sha256sums

appveyor DownloadFile https://zlib.net/zlib-%ZLIB_VER%.tar.xz -FileName zlib.tar.xz || exit /B 1
appveyor DownloadFile https://curl.haxx.se/download/curl-%CURL_VER%.tar.xz -FileName curl.tar.xz || exit /B 1
appveyor DownloadFile http://ftp.digitalmars.com/bup.zip -FileName bup.zip || exit /B 1
appveyor DownloadFile https://sourceforge.net/projects/mingw/files/MinGW/Extension/pexports/pexports-%PEXPORTS_VER%/pexports-%PEXPORTS_VER%-mingw32-bin.tar.xz -FileName pexports.tar.xz || exit /B 1

:: e.g. from git installation
sha256sum -c sha256sums || exit /B 1

7z x zlib.tar.xz || exit /B 1
7z x zlib.tar || exit /B 1
7z x curl.tar.xz || exit /B 1
7z x curl.tar || exit /B 1
7z x bup.zip || exit /B 1
7z x pexports.tar.xz || exit /B 1
7z x pexports.tar || exit /B 1

move zlib-%ZLIB_VER% zlib
move curl-%CURL_VER% curl

SET ZLIB_PATH=%ROOT%\zlib

call "c:\Program Files (x86)\Microsoft Visual Studio 14.0\VC\vcvars32.bat"

:: --------------------------------------------------------------------
:: Build x86 DLL and import libs

SET PATH=%MINGW_PATH%;%ORIG_PATH%
echo %PATH%
dir %MINGW_PATH%

mingw32-make -C zlib -f win32\Makefile.gcc || exit /B 1
mingw32-make -C curl\lib -f Makefile.m32 CFG=mingw32-winssl-zlib-ipv6 LDFLAGS=-static || exit /B 1
strip -s curl\lib\libcurl.dll

mkdir dmd2\windows\bin dmd2\windows\lib
copy curl\lib\libcurl.dll dmd2\windows\bin
dm\bin\implib /system dmd2\windows\lib\curl.lib curl\lib\libcurl.dll || exit /B 1
mkdir dmd2\windows\lib32mscoff
bin\pexports curl\lib\libcurl.dll > curl.def || exit /B 1
lib /MACHINE:X86 /DEF:curl.def /OUT:dmd2\windows\lib32mscoff\curl.lib || exit /B 1
del dmd2\windows\lib32mscoff\curl.exp

mingw32-make -C zlib -fwin32/Makefile.gcc clean
mingw32-make -C curl\lib -f Makefile.m32 clean

:: --------------------------------------------------------------------
:: Build x64 DLL and import libs

SET PATH=%MINGW64_PATH%;%ORIG_PATH%
echo %PATH%
dir %MINGW64_PATH%

mingw32-make -C zlib -f win32\Makefile.gcc || exit /B 1
mingw32-make -C curl\lib -f Makefile.m32 CFG=mingw32-winssl-zlib-ipv6 LDFLAGS=-static || exit /B 1
strip -s curl\lib\libcurl.dll

mkdir dmd2\windows\bin64 dmd2\windows\lib64
copy curl\lib\libcurl.dll dmd2\windows\bin64
bin\pexports curl\lib\libcurl.dll > curl.def || exit /B 1
lib /MACHINE:X64 /DEF:curl.def /OUT:dmd2\windows\lib64\curl.lib || exit /B 1
del dmd2\windows\lib64\curl.exp

mingw32-make -C zlib -fwin32/Makefile.gcc clean
mingw32-make -C curl\lib -f Makefile.m32 clean

:: --------------------------------------------------------------------
:: Zip it up

7z a libcurl-%CURL_VER%-WinSSL-zlib-x86-x64.zip dmd2

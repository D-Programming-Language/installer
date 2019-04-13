@setlocal

set ROOT=%CD%

call "c:\Program Files (x86)\Microsoft Visual Studio\2017\Community\VC\Auxiliary\Build\vcvars32.bat"
cd %ROOT%

echo fbcf47c5e543f4cdac6bb9bbbc6327ff24217cd7eafc5571549ad6d237287f9c lld.src.tar.xz> sha256sums
echo 8bc1f844e6cbde1b652c19c1edebc1864456fd9c78b8c1bea038e51b363fe222 llvm.src.tar.xz>> sha256sums

set LLVM_URL=http://releases.llvm.org/%LLVM_VER%
appveyor DownloadFile %LLVM_URL%/lld-%LLVM_VER%.src.tar.xz  -FileName lld.src.tar.xz  || exit /B 1
appveyor DownloadFile %LLVM_URL%/llvm-%LLVM_VER%.src.tar.xz -FileName llvm.src.tar.xz || exit /B 1

:: e.g. from git installation
sha256sum -c sha256sums || exit /B 1

7z x llvm.src.tar.xz || exit /B 1
7z x lld.src.tar.xz  || exit /B 1

7z x llvm.src.tar || exit /B 1
7z x lld.src.tar  || exit /B 1

move llvm-%LLVM_VER%.src llvm
move lld-%LLVM_VER%.src llvm\tools\lld

set lld_build_dir=build-lld
if not exist %lld_build_dir%\nul md %lld_build_dir%
cd %lld_build_dir%

set CMAKE_OPT=-G "Visual Studio 15"
set CMAKE_OPT=%CMAKE_OPT% -DCMAKE_BUILD_TYPE=Release
set CMAKE_OPT=%CMAKE_OPT% -DLLVM_TARGETS_TO_BUILD=X86
set CMAKE_OPT=%CMAKE_OPT% -DLLVM_USE_CRT_DEBUG=MTd
set CMAKE_OPT=%CMAKE_OPT% -DLLVM_USE_CRT_RELEASE=MT
set CMAKE_OPT=%CMAKE_OPT% -DLLVM_USE_CRT_MINSIZEREL=MT
set CMAKE_OPT=%CMAKE_OPT% -DLLVM_INCLUDE_DIRS="c:/projects/llvm/include"

cmake %CMAKE_OPT% ..\llvm || exit /B 1
devenv LLVM.sln /project lld /Build "MinSizeRel|Win32" || exit /B 1

cd MinSizeRel\bin
7z a %ROOT%\lld-link-%LLVM_VER%.zip lld-link.exe lld-lib.exe

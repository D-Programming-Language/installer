setlocal
call "%VSINSTALLDIR%\VC\Auxiliary\Build\vcvarsall.bat" x64
echo on

if "%BRANCH%" == "" set BRANCH=stable
if "%HOST_DMD_VERSION%" == "" set HOST_DMD_VERSION=2.090.0

rem to be run from installer root dir with dmd2 and dm folders
set DMD_DIR=%CD%\dmd2
set DMD_BIN_DIR=%DMD_DIR%\windows\bin
set HOST_DC=%DMD_BIN_DIR%\dmd.exe
set PATH=%DMD_BIN_DIR%;%PATH%;%CD%\dm\bin
set VCDIR=%VCToolsInstallDir%
set SDKDIR=.

cd create_dmd_release

"%HOST_DC%" -m32 -gf build_all.d common.d -version=NoVagrant || exit /B 1
build_all v%HOST_DMD_VERSION% %BRANCH% || exit /B 1

; Release Manager:
;
; Preliminary instructions
; ------------------------
;
; Please use the special build of NSIS that supports large strings.
; Updating the PATH will often not work or work incorrectly with the
; regular build of NSIS.
;
; http://nsis.sourceforge.net/Special_Builds
;
;
; Instructions
; ------------
;
; Two defines must be set to use the installer:
; - EmbedD2Dir: The path to the directory tree recursively embedded in the
;               generated installer.
; - Version2:   The DMD version number.
;
; The easiest way is to use the /D command line options for makensis
;   makensis /DEmbedD2Dir=<some path> /DVersion2=2.xxx
;
; The Extras that are downloaded should be updated to use the latest versions.

;--------------------------------------------------------
; Defines
;--------------------------------------------------------

; Required
; --------
; EmbedD2Dir. Can be specified here rather than on the makensis command line:
;!define EmbedD2Dir "<path to files to install>"

; Version2. Can be specified here rather than on the makensis command line:
;!define Version2 "2.0xx"


; Routinely Update
; ----------------
; Visual D
!define VersionVisualD "1.3.1"

; Update Rarely Needed
; --------------------
; Files
!define VisualDFilename "VisualD-v${VersionVisualD}.exe"
!define VS2013Filename "vs_community2013.exe"
!define VS2017Filename "vs_community2017.exe"
!define VS2017BTFilename "vs_BuildTools2017.exe"
!define VS2019Filename "vs_community2019.exe"
!define VS2019BTFilename "vs_BuildTools2019.exe"
!define VCRedistx86Filename "vcredist_x86.exe"
!define VCRedistx64Filename "vcredist_x64.exe"

; URLs
!define VisualDBaseURL "https://github.com/dlang/visuald/releases/download"

!define VisualDUrl "${VisualDBaseURL}/v${VersionVisualD}/${VisualDFilename}"

!define VS2013Url "http://go.microsoft.com/fwlink/?LinkId=517284"
!define VS2017Url "https://download.visualstudio.microsoft.com/download/pr/100404311/045b56eb413191d03850ecc425172a7d/vs_Community.exe"
!define VS2017BuildToolsUrl "https://download.visualstudio.microsoft.com/download/pr/100404314/e64d79b40219aea618ce2fe10ebd5f0d/vs_BuildTools.exe"
!define VS2019Url "https://download.visualstudio.microsoft.com/download/pr/8ab6eab3-e151-4f4d-9ca5-07f8434e46bb/8cc1a4ebd138b5d0c2b97501a198f5eacdc434daa8a5c6564c8e23fdaaad3619/vs_Community.exe"
!define VS2019BuildToolsUrl "https://download.visualstudio.microsoft.com/download/pr/8ab6eab3-e151-4f4d-9ca5-07f8434e46bb/cfffd18469d936d6cb9dff55fd4ae538035e7f247f1756c5a31f3e03751d7ee7/vs_BuildTools.exe"

; see https://stackoverflow.com/questions/12206314/detect-if-visual-c-redistributable-for-visual-studio-2012-is-installed/14878248
; selecting VC2010
!define VCRedistx86Url "https://download.microsoft.com/download/1/6/5/165255E7-1014-4D0A-B094-B6A430A6BFFC/vcredist_x86.exe"
!define VCRedistx64Url "https://download.microsoft.com/download/1/6/5/165255E7-1014-4D0A-B094-B6A430A6BFFC/vcredist_x64.exe"

!define VCRedistx86RegKey "SOFTWARE\Classes\Installer\Products\1926E8D15D0BCE53481466615F760A7F"
!define VCRedistx64RegKey "SOFTWARE\Classes\Installer\Products\1D5E3C0FEDA1E123187686FED06E995A"

; ----------------
; Publishing Details
!define DPublisher "D Language Foundation"
!define DName "DMD"
!define ARP "Software\Microsoft\Windows\CurrentVersion\Uninstall\${DName}"

; Version2 Fallback
; The version will be pulled from the VERSION file in the dmd repository if
; not specified with /D to makensis or defined above. Change the path to match.
!define D2VersionPath "..\..\dmd\VERSION"
!ifndef Version2
  !define /file Version2 ${D2VersionPath}
!endif

Unicode True

;--------------------------------------------------------
; Includes
;--------------------------------------------------------

!include "MUI.nsh"
!include "EnvVarUpdate.nsh"
!include "FileFunc.nsh"
!include "TextFunc.nsh"
!include "Sections.nsh"
!include "LogicLib.nsh"
!include "x64.nsh"

;------------------------------------------------------------
; Variables
;------------------------------------------------------------

Var I
Var J
Var K
Var InstanceCheck
Var VCVer
Var VCPath


;--------------------------------------------------------
; General definitions
;--------------------------------------------------------

; Name of the installer
Name "D Programming Language"

; Name of the output file of the installer
!define InstallerFilename "dmd-${Version2}.exe"
OutFile ${InstallerFilename}

; Where the program will be installed
InstallDir "C:\D"

; Take the installation directory from the registry, if possible
InstallDirRegKey HKCU "Software\${DName}" "InstallationFolder"

; This is so no one can corrupt the installer
CRCCheck force

SetCompressor /SOLID lzma
SetCompressorDictSize 112

;------------------------------------------------------------
; Macros definition
;------------------------------------------------------------

; Check if a dmd installer instance is already running
!macro OneInstanceOnly
  System::Call 'kernel32::CreateMutexA(i 0, i 0, t "digital_mars_d_compiler_installer") ?e'
  Pop $R0
  StrCmp $R0 0 +3
    MessageBox MB_OK|MB_ICONSTOP "An instance of DMD installer is already running" /SD IDOK
    Abort
!macroend


!macro DownloadAndRun Filename Url AltUrl
  inetc::get /CAPTION "Downloading ${Filename}..." /BANNER "" "${Url}" "$TEMP\${Filename}"
  Pop $0
  StrCmp $0 "OK" run_${Filename}
  !if `${AltUrl}` != ""
    inetc::get /CAPTION "Downloading ${Filename}..." /BANNER "" "${AltUrl}" "$TEMP\${Filename}"
    Pop $0
    StrCmp $0 "OK" run_${Filename}
  !endif

  ; failed
  MessageBox MB_OK|MB_ICONEXCLAMATION "Could not download ${Filename}$\r$\n$\r$\n${Url}" /SD IDOK

  Goto dandr_done_${Filename}

  run_${Filename}:
  DetailPrint "Running ${Filename}"
  ExecWait "$TEMP\${Filename}"

  Delete "$TEMP\${Filename}"

  dandr_done_${Filename}:
!macroend

; Read SDK registry entry and check if kernel32.lib exists in the expected lib folder
!macro _DetectSDK REG_KEY VALUE LIBFOLDER
    ClearErrors
    ReadRegStr $0 HKLM "Software\Microsoft\${REG_KEY}" ${VALUE}
    IfErrors +2 0
    IfFileExists "$0${LIBFOLDER}\kernel32.lib" +2
    SetErrors
!macroend

;--------------------------------------------------------
; Interface settings
;--------------------------------------------------------

; Confirmation when exiting the installer
!define MUI_ABORTWARNING

!define MUI_ICON "installer-icon.ico"
!define MUI_UNICON "uninstaller-icon.ico"


;--------------------------------------------------------
; Language selection dialog settings
;--------------------------------------------------------

; Remember the installation language
!define MUI_LANGDLL_REGISTRY_ROOT "HKCU"
!define MUI_LANGDLL_REGISTRY_KEY "Software\D"
!define MUI_LANGDLL_REGISTRY_VALUENAME "Installer Language"


;--------------------------------------------------------
; Installer pages
;--------------------------------------------------------

!define MUI_WELCOMEFINISHPAGE_BITMAP "d2-installer-image.bmp"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
Page custom VCInstallPage VCInstallPageValidate
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_WELCOME
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH


;--------------------------------------------------------
; The languages
;--------------------------------------------------------

!insertmacro MUI_LANGUAGE "English"


; Reserve files needed by the installation
; (move files needed by the installer itself to the beginning of the solid archive
;  to avoid pauses when switching pages)
!insertmacro MUI_RESERVEFILE_LANGDLL

ReserveFile /Plugin INetC.dll
ReserveFile "vcinstall.ini"

;--------------------------------------------------------
; Sections
;--------------------------------------------------------

SectionGroup /e "D2"
  Section "-D2" Dmd2Files
    ; This section is mandatory
    SectionIn RO

    SetOutPath $INSTDIR
    CreateDirectory "$INSTDIR"

    ; Embed the directory specified
    File /r ${EmbedD2Dir}

    ; Create 32-bit command line batch file
    FileOpen $0 "$INSTDIR\dmd2vars32.bat" w
    FileWrite $0 "@echo.$\n"
    FileWrite $0 "@echo Setting up 32-bit environment for using DMD 2 from %~dp0dmd2\windows\bin.$\n"
    FileWrite $0 "@set PATH=%~dp0dmd2\windows\bin;%PATH%$\n"
    FileClose $0

    ; Create 64-bit command line batch file
    FileOpen $0 "$INSTDIR\dmd2vars64.bat" w
    FileWrite $0 "@echo.$\n"
    FileWrite $0 "@echo Setting up 64-bit environment for using DMD 2 from %~dp0dmd2\windows\bin.$\n"
    FileWrite $0 "@echo.$\n"
    FileWrite $0 "@echo dmd must still be called with -m64 in order to generate 64-bit code.$\n"
    FileWrite $0 "@echo This command prompt adds the path of extra 64-bit DLLs so generated programs$\n"
    FileWrite $0 "@echo which use the extra DLLs (notably libcurl) can be executed.$\n"
    FileWrite $0 "@set PATH=%~dp0dmd2\windows\bin;%PATH%$\n"
    FileWrite $0 "@set PATH=%~dp0dmd2\windows\bin64;%PATH%$\n"
    FileClose $0

    ; Write installation dir in the registry
    WriteRegStr HKLM "SOFTWARE\${DName}" "InstallationFolder" "$INSTDIR"

    ; Registry keys for dmd uninstaller
    WriteRegStr HKLM "${ARP}" "DisplayName" "${DName}"
    WriteRegStr HKLM "${ARP}" "DisplayVersion" "${Version2}"
    WriteRegStr HKLM "${ARP}" "UninstallString" "$INSTDIR\uninstall.exe"
    WriteRegStr HKLM "${ARP}" "DisplayIcon" "$INSTDIR\uninstall.exe"
    WriteRegStr HKLM "${ARP}" "Publisher" "${DPublisher}"
    WriteRegStr HKLM "${ARP}" "HelpLink" "http://dlang.org/"
    WriteRegDWORD HKLM "${ARP}" "NoModify" 1
    WriteRegDWORD HKLM "${ARP}" "NoRepair" 1
    WriteUninstaller "uninstall.exe"
  SectionEnd


  Section "Add to PATH" AddD2ToPath
    ${If} ${RunningX64}
      ${EnvVarUpdate} $0 "PATH" "A" "HKLM" "$INSTDIR\dmd2\windows\bin64"
    ${EndIf}
    ${EnvVarUpdate} $0 "PATH" "A" "HKLM" "$INSTDIR\dmd2\windows\bin"
    ${EnvVarUpdate} $0 "PATH" "A" "HKLM" "$INSTDIR\dmd2\windows\bin64"
  SectionEnd


  Section "Start Menu" StartMenuShortcuts
    CreateDirectory "$SMPROGRAMS\D"

    CreateShortCut "$SMPROGRAMS\D\D2 HTML Documentation.lnk" "$INSTDIR\dmd2\html\d\index.html"
    CreateShortCut "$SMPROGRAMS\D\D2 32-bit Command Prompt.lnk" '%comspec%' '/k ""$INSTDIR\dmd2vars32.bat""' "" "" SW_SHOWNORMAL "" "Open D2 32-bit Command Prompt"
    CreateShortCut "$SMPROGRAMS\D\D2 64-bit Command Prompt.lnk" '%comspec%' '/k ""$INSTDIR\dmd2vars64.bat""' "" "" SW_SHOWNORMAL "" "Open D2 64-bit Command Prompt"
  SectionEnd
SectionGroupEnd


SectionGroup /e "Extras"
  Section /o "Download Visual D" VisualDDownload
    !insertmacro DownloadAndRun ${VisualDFilename} ${VisualDUrl} ""
  SectionEnd
SectionGroupEnd

;--------------------------------------------------------
; Custom page
;--------------------------------------------------------

Function VCInstallPage

  Call DetectVC
  StrCmp $VCVer "" ask_vs
  Abort
  ask_vs:

  !insertmacro MUI_HEADER_TEXT "Choose Visual Studio Installation" "Choose the Visual C runtime to link against"
  !insertmacro MUI_INSTALLOPTIONS_EXTRACT "vcinstall.ini"
  !insertmacro MUI_INSTALLOPTIONS_DISPLAY "vcinstall.ini"

FunctionEnd

Function VCInstallPageValidate

  !insertmacro MUI_INSTALLOPTIONS_READ $0 "vcinstall.ini" "Field 2" "State"
  StrCmp $0 1 install_vs2013
  !insertmacro MUI_INSTALLOPTIONS_READ $0 "vcinstall.ini" "Field 3" "State"
  StrCmp $0 1 install_vs2019
  !insertmacro MUI_INSTALLOPTIONS_READ $0 "vcinstall.ini" "Field 4" "State"
  StrCmp $0 1 install_bt2019
  !insertmacro MUI_INSTALLOPTIONS_READ $0 "vcinstall.ini" "Field 5" "State"
  StrCmp $0 1 install_vc2010
  goto done_vc

  install_vs2013:
    !insertmacro DownloadAndRun ${VS2013Filename} ${VS2013Url} ""
    goto done_vc

  install_vs2019:
    !insertmacro DownloadAndRun ${VS2019Filename} ${VS2019Url} ""
    goto done_vc

  install_bt2019:
    !insertmacro DownloadAndRun ${VS2019BTFilename} ${VS2019BuildToolsUrl} ""
    goto done_vc

  install_vc2010:
    Call InstallVCRedistributable
    goto done_vc

  done_vc:

FunctionEnd

;--------------------------------------------------------
; Helper functions
;--------------------------------------------------------

Function InstallVCRedistributable

    SetRegView 64 ; look at the 64-bit registry hive if available
    ClearErrors
    ReadRegStr $0 HKLM "${VCRedistx86RegKey}" "ProductName"
    IfErrors 0 vcredistx86_installed
        !insertmacro DownloadAndRun ${VCRedistx86Filename} ${VCRedistx86Url} ""
    vcredistx86_installed:

    ClearErrors
    ReadRegStr $0 HKLM "${VCRedistx64RegKey}" "ProductName"
    IfErrors 0 vcredistx64_installed
        !insertmacro DownloadAndRun ${VCRedistx64Filename} ${VCRedistx64Url} ""
    vcredistx64_installed:
    SetRegView 32 ; retore default

FunctionEnd

Function DetectVC
    ClearErrors

    Call DetectVS2019_InstallationFolder
    StrCpy $1 "VC2019"
    StrCmp $0 "" not_vc2019 vs2019
    vs2019:
        ${LineRead} "$0\VC\Auxiliary\Build\Microsoft.VCToolsVersion.default.txt" "1" $2
        IfErrors not_vc2019
        StrCpy $0 "$0\VC\Tools\MSVC\$2"
        Goto done_vs
    not_vc2019:

    Call DetectVS2019BuildTools_InstallationFolder
    StrCpy $1 "VC2019BT"
    StrCmp $0 "" not_vc2019BT vs2019BT
    vs2019BT:
        ${LineRead} "$0\VC\Auxiliary\Build\Microsoft.VCToolsVersion.default.txt" "1" $2
        IfErrors not_vc2019BT
        StrCpy $0 "$0\VC\Tools\MSVC\$2"
        Goto done_vs
    not_vc2019BT:

    ReadRegStr $0 HKLM "SOFTWARE\Microsoft\VisualStudio\SxS\VS7" "15.0"
    StrCpy $1 "VC2017"
    IfErrors not_vc2017
        ${LineRead} "$0\VC\Auxiliary\Build\Microsoft.VCToolsVersion.default.txt" "1" $2
        IfErrors not_vc2017
        StrCpy $0 "$0\VC\Tools\MSVC\$2"
        Goto done_vs
    not_vc2017:

    Call DetectVS2017BuildTools_InstallationFolder
    StrCpy $1 "VC2017BT"
    StrCmp $0 "" not_vc2017BT vs2017BT
    vs2017BT:
        ${LineRead} "$0\VC\Auxiliary\Build\Microsoft.VCToolsVersion.default.txt" "1" $2
        IfErrors not_vc2017BT
        StrCpy $0 "$0\VC\Tools\MSVC\$2"
        Goto done_vs
    not_vc2017BT:

    ClearErrors
    ReadRegStr $0 HKLM "Software\Microsoft\VisualStudio\14.0\Setup\VC" "ProductDir"
    StrCpy $1 "VC2015"
    IfErrors 0 done_vs
    ClearErrors
    ReadRegStr $0 HKLM "Software\Microsoft\VisualStudio\12.0\Setup\VC" "ProductDir"
    StrCpy $1 "VC2013"
    IfErrors 0 done_vs
    ClearErrors
    ReadRegStr $0 HKLM "Software\Microsoft\VisualStudio\11.0\Setup\VC" "ProductDir"
    StrCpy $1 "VC2012"
    IfErrors 0 done_vs
    ClearErrors
    ReadRegStr $0 HKLM "Software\Microsoft\VisualStudio\10.0\Setup\VC" "ProductDir"
    StrCpy $1 "VC2010"
    IfErrors 0 done_vs
    ClearErrors
    ReadRegStr $0 HKLM "Software\Microsoft\VisualStudio\9.0\Setup\VC" "ProductDir"
    StrCpy $1 "VC2008"
    IfErrors done done_vs

    done_vs:
    StrCpy $VCPath $0
    StrCpy $VCVer $1
    done:

FunctionEnd

;--------------------------------------------------------
; Installer functions
;--------------------------------------------------------

Function .onInit
  ; Check if a dmd installer instance is already running
  !insertmacro OneInstanceOnly


  ; Force install without uninstall (useful if uninstall is broken)
  ${GetParameters} $R0
  StrCmp $R0 "/f" done_uninst


  ; Remove previous dmd installation if any
  ; this section is for previous dmd installer only
  ReadRegStr $R5 HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\D" "UninstallString"
  ReadRegStr $R6 HKLM "SOFTWARE\D" "Install_Dir"
  StrCmp $R5 "" done_uninst_prev
  MessageBox MB_OKCANCEL|MB_ICONQUESTION \
  "A previous DMD is installed on your system$\n$\nPress 'OK' to replace it with ${DName} ${Version2}" \
  /SD IDOK IDOK +2
  Abort
  ClearErrors
  ; Run uninstaller fron installed directory
  ExecWait '$R5 /S _?=$R6' $K
  ; Exit if uninstaller return an error
  IfErrors 0 +3
    MessageBox MB_OK|MB_ICONSTOP \
    "An error occurred when removing DMD$\n$\nRun '${InstallerFilename} /f' to force install ${DName} ${Version2}" \
    /SD IDOK
    Abort
  ; Remove in background the remaining uninstaller program itself
  Sleep 1000
  ExecWait '$R5 /S'
  ; MessageBox MB_OK|MB_ICONINFORMATION "Previous DMD uninstalled" /SD IDOK

  done_uninst_prev:
  ; End of removing previous dmd installation section


  ; Remove if dmd is already installed
  ReadRegStr $R0 HKLM "${ARP}" "UninstallString"
  StrCmp $R0 "" done_uninst

  ReadRegStr $I HKLM "${ARP}" "DisplayName"
  ReadRegStr $J HKLM "${ARP}" "DisplayVersion"
  MessageBox MB_OKCANCEL|MB_ICONQUESTION \
  "$I v$J is installed on your system$\n$\nPress 'OK' to replace it with ${DName} ${Version2}" \
  /SD IDOK IDOK uninst
  Abort

  uninst:
    ${GetParent} $R0 $INSTDIR

    ClearErrors
    ; Run uninstaller from installed directory
    ExecWait '$R0 /IC False _?=$INSTDIR' $K
    ; Exit if uninstaller return an error
    IfErrors 0 +3
      MessageBox MB_OK|MB_ICONSTOP \
      "An error occurred when removing $I v$J$\n$\nRun '${InstallerFilename} /f' to force install ${DName} ${Version2}" \
      /SD IDOK
      Abort
    ; Exit if uninstaller is cancelled by user
    StrCmp $K 0 +2
      Abort
    ; Remove in background the remaining uninstaller program itself
    Exec '$R0 /IC False /S'

  done_uninst:
FunctionEnd


; Contains descriptions of components and other stuff
!include d2-installer-descriptions.nsh


;--------------------------------------------------------
; Uninstaller
;--------------------------------------------------------

Section "Uninstall"
  ; Remove directories from PATH (for all users)
  ${un.EnvVarUpdate} $0 "PATH" "R" "HKLM" "$INSTDIR\dmd2\windows\bin64"
  ${un.EnvVarUpdate} $0 "PATH" "R" "HKLM" "$INSTDIR\dmd2\windows\bin"

  ; Remove stuff from registry
  DeleteRegKey HKLM "${ARP}"
  DeleteRegKey HKLM "SOFTWARE\${DName}"

  ; Remove the uninstaller
  Delete $INSTDIR\uninstall.exe

  ; Remove the generated batch files
  Delete $INSTDIR\dmd2vars32.bat
  Delete $INSTDIR\dmd2vars64.bat

  ; Remove shortcuts
  Delete "$SMPROGRAMS\D\D2 HTML Documentation.lnk"
  Delete "$SMPROGRAMS\D\D2 Documentation.lnk"
  Delete "$SMPROGRAMS\D\D2 32-bit Command Prompt.lnk"
  Delete "$SMPROGRAMS\D\D2 64-bit Command Prompt.lnk"
  RMDir "$SMPROGRAMS\D"

  ${GetOptions} $CMDLINE "/S" $R0
  IfErrors 0 rmdir
  MessageBox MB_OKCANCEL|MB_ICONEXCLAMATION \
  "The uninstaller will now recursively delete ALL files and directories under '$INSTDIR\dmd2'. Continue?" \
  /SD IDOK IDOK rmdir
  Abort

  rmdir:
  ; Remove used directories
  RMDir /r "$INSTDIR\dmd2"
  RMDir "$INSTDIR"
SectionEnd


;--------------------------------------------------------
; Uninstaller functions
;--------------------------------------------------------

Function un.onInit
  ; Check if a dmd installer instance is already running
  ; Do not check if "/IC False" argument is passed to uninstaller
  ${GetOptions} $CMDLINE "/IC" $InstanceCheck
  ${IfNot} "$InstanceCheck" == "False"
    !insertmacro OneInstanceOnly
  ${EndIf}
FunctionEnd

;--------------------------------------------------------
; VS 2017/2019 detection functions
;
; returns path to VS (not VC) in $0
;--------------------------------------------------------
Function DetectVS2017BuildTools_InstallationFolder

  ClearErrors
  StrCpy $0 0
  loop:
    EnumRegKey $1 HKLM SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall $0
    StrCmp $1 "" done
    ReadRegStr $2 HKLM SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$1 DisplayName
    IfErrors NoDisplayName
        StrCmp $2 "Visual Studio Build Tools 2017" 0 NotVS2017BT
            ReadRegStr $2 HKLM SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$1 InstallLocation
            IfErrors NoInstallLocation
                ; MessageBox MB_YESNO|MB_ICONQUESTION "$2$\n$\nMore?" IDYES 0 IDNO done
                StrCpy $0 "$2\\"
                return
            NoInstallLocation:
        NotVS2017BT:
    NoDisplayName:
    IntOp $0 $0 + 1
    Goto loop
  done:
  StrCpy $0 ""

FunctionEnd

Function DetectVS2019_InstallationFolder

  ClearErrors
  StrCpy $0 0
  loop:
    EnumRegKey $1 HKLM SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall $0
    StrCmp $1 "" done
    ReadRegStr $2 HKLM SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$1 DisplayName
    IfErrors NoDisplayName
        StrCpy $3 $2 14
        StrCmp $3 "Visual Studio " 0 NotVS2019
        StrCpy $3 $2 12 -12
        StrCmp $3 "2019 Preview" IsVS2019
        StrCpy $3 $2 4 -4
        StrCmp $3 "2019" IsVS2019 NotVS2019
        IsVS2019:
            ReadRegStr $2 HKLM SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$1 InstallLocation
            IfErrors NoInstallLocation
                StrCpy $0 "$2\\"
                return
            NoInstallLocation:
        NotVS2019:
    NoDisplayName:
    IntOp $0 $0 + 1
    Goto loop
  done:
  StrCpy $0 ""

FunctionEnd

Function DetectVS2019BuildTools_InstallationFolder

  ClearErrors
  StrCpy $0 0
  loop:
    EnumRegKey $1 HKLM SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall $0
    StrCmp $1 "" done
    ReadRegStr $2 HKLM SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$1 DisplayName
    IfErrors NoDisplayName
        StrCmp $2 "Visual Studio Build Tools 2019" 0 NotVS2019BT
            ReadRegStr $2 HKLM SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$1 InstallLocation
            IfErrors NoInstallLocation
                StrCpy $0 "$2\\"
                return
            NoInstallLocation:
        NotVS2019BT:
    NoDisplayName:
    IntOp $0 $0 + 1
    Goto loop
  done:
  StrCpy $0 ""

FunctionEnd


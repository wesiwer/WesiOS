Unicode true

!include "MUI2.nsh"
!include "x64.nsh"

!ifndef VERSION
  !define VERSION "0.0.0"
!endif
!ifndef BUILD_DIR
  !error "BUILD_DIR define is required"
!endif
!ifndef OUTPUT_FILE
  !define OUTPUT_FILE "WesiOS-Setup.exe"
!endif
!ifndef ICON_FILE
  ; makensis resolves resource paths from the script directory.
  !define ICON_FILE "..\runner\resources\app_icon.ico"
!endif

!define PRODUCT_NAME "WesiOS"
!define PRODUCT_PUBLISHER "Wesi Inc."
!define PRODUCT_EXE "wesios.exe"
!define PRODUCT_DIR "WesiOS"
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\WesiOS"

Name "${PRODUCT_NAME}"
OutFile "${OUTPUT_FILE}"
InstallDir "$PROGRAMFILES64\${PRODUCT_DIR}"
InstallDirRegKey HKLM "${UNINSTALL_KEY}" "InstallLocation"
RequestExecutionLevel admin
SetCompressor /SOLID lzma
SetCompressorDictSize 64
BrandingText "WesiOS"
Icon "${ICON_FILE}"
UninstallIcon "${ICON_FILE}"
VIProductVersion "${VERSION}.0"
VIAddVersionKey /LANG=1049 "ProductName" "${PRODUCT_NAME}"
VIAddVersionKey /LANG=1049 "CompanyName" "${PRODUCT_PUBLISHER}"
VIAddVersionKey /LANG=1049 "FileDescription" "Установщик WesiOS"
VIAddVersionKey /LANG=1049 "FileVersion" "${VERSION}"
VIAddVersionKey /LANG=1049 "ProductVersion" "${VERSION}"
VIAddVersionKey /LANG=1049 "LegalCopyright" "Wesi Inc."

!define MUI_ABORTWARNING
!define MUI_ICON "${ICON_FILE}"
!define MUI_UNICON "${ICON_FILE}"
!define MUI_WELCOMEPAGE_TITLE "Установка WesiOS"
!define MUI_WELCOMEPAGE_TEXT "Мастер установит WesiOS ${VERSION} на этот компьютер.$\r$\n$\r$\nПеред продолжением рекомендуется закрыть запущенный WesiOS."
!define MUI_FINISHPAGE_RUN "$INSTDIR\${PRODUCT_EXE}"
!define MUI_FINISHPAGE_RUN_TEXT "Запустить WesiOS"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "Russian"

Section "WesiOS" SEC_MAIN
  SectionIn RO
  SetShellVarContext all
  SetRegView 64
  SetOutPath "$INSTDIR"

  ; Kill an older running copy so DLLs can be replaced cleanly.
  nsExec::ExecToLog 'taskkill /F /IM ${PRODUCT_EXE}'

  File /r "${BUILD_DIR}\*.*"
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  CreateDirectory "$SMPROGRAMS\WesiOS"
  CreateShortcut "$SMPROGRAMS\WesiOS\WesiOS.lnk" "$INSTDIR\${PRODUCT_EXE}" "" "$INSTDIR\${PRODUCT_EXE}" 0
  CreateShortcut "$SMPROGRAMS\WesiOS\Удалить WesiOS.lnk" "$INSTDIR\Uninstall.exe"
  CreateShortcut "$DESKTOP\WesiOS.lnk" "$INSTDIR\${PRODUCT_EXE}" "" "$INSTDIR\${PRODUCT_EXE}" 0

  WriteRegStr HKLM "${UNINSTALL_KEY}" "DisplayName" "WesiOS"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "Publisher" "${PRODUCT_PUBLISHER}"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\${PRODUCT_EXE}"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKLM "${UNINSTALL_KEY}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
  WriteRegDWORD HKLM "${UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKLM "${UNINSTALL_KEY}" "NoRepair" 1
SectionEnd

Section "Uninstall"
  SetShellVarContext all
  SetRegView 64
  nsExec::ExecToLog 'taskkill /F /IM ${PRODUCT_EXE}'

  Delete "$DESKTOP\WesiOS.lnk"
  Delete "$SMPROGRAMS\WesiOS\WesiOS.lnk"
  Delete "$SMPROGRAMS\WesiOS\Удалить WesiOS.lnk"
  RMDir "$SMPROGRAMS\WesiOS"
  DeleteRegKey HKLM "${UNINSTALL_KEY}"
  RMDir /r "$INSTDIR"
SectionEnd

; Installer Windows (Inno Setup 6).  Build dulu:  flutter build windows --release
; Lalu:  iscc /DAppVersion=1.0.0 installer\dynamic_island.iss
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{B6C1B7A2-5E0F-4F0E-9C3A-3D1B1E6D2A11}
AppName=Dynamic Island
AppVersion={#AppVersion}
AppPublisher=AjarHer08
DefaultDirName={autopf}\Dynamic Island
DefaultGroupName=Dynamic Island
OutputDir=..\dist
OutputBaseFilename=dynamic-island-{#AppVersion}-setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\dynamic_island.exe
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

[Tasks]
Name: "desktopicon"; Description: "Buat ikon di desktop"; Flags: unchecked
Name: "startup"; Description: "Jalankan otomatis saat Windows mulai"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{group}\Dynamic Island"; Filename: "{app}\dynamic_island.exe"
Name: "{autodesktop}\Dynamic Island"; Filename: "{app}\dynamic_island.exe"; Tasks: desktopicon
Name: "{userstartup}\Dynamic Island"; Filename: "{app}\dynamic_island.exe"; Tasks: startup

[Run]
Filename: "{app}\dynamic_island.exe"; Description: "Jalankan Dynamic Island"; Flags: nowait postinstall skipifsilent

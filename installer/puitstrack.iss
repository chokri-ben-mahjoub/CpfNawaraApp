; Installateur Windows de PuitsTrack (Inno Setup 6).
; Généré par installer\build_setup.ps1 — ne pas compiler à la main sans avoir
; d'abord lancé "flutter build windows --release" et copié les DLL VC++.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#define AppName "PuitsTrack"
#define AppExe "puitstrack.exe"
#define BuildDir "..\build\windows\x64\runner\Release"

[Setup]
; AppId FIXE : c'est lui qui permet aux versions suivantes de se reconnaître
; (mise à jour en place) et au désinstallateur de retrouver l'app.
; Ne jamais le changer.
AppId={{4A3A2CBC-6F34-4C47-8138-83A7B7AB12B0}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppName}
VersionInfoVersion={#AppVersion}
; Sans droits admin : installation pour l'utilisateur courant
; (%LOCALAPPDATA%\Programs\PuitsTrack). Pour C:\Program Files\PuitsTrack
; (tous les utilisateurs, droits admin) : lancer "Setup.exe /ALLUSERS".
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=commandline
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
DisableDirPage=yes
DisableReadyPage=yes
ShowLanguageDialog=no
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Ferme l'app si elle est ouverte pendant une mise à jour.
CloseApplications=yes
RestartApplications=no
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
OutputDir=Output
OutputBaseFilename=PuitsTrack-Setup-{#AppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
; Tout le dossier Release (exe, DLL Flutter et plugins, sqlite3.dll, DLL
; Visual C++ copiées par build_setup.ps1, dossier data).
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Fichiers de l'app uniquement : les données (AppData\Roaming\PuitsTrack) et
; les sauvegardes (Téléchargements\PuitsTrack) sont conservées.
Type: filesandordirs; Name: "{app}"
